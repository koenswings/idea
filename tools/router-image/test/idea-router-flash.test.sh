#!/usr/bin/env bash
# idea-router-flash.test.sh — offline run of the whole flash chain (idea#277) against mocks. No router touched.
#  * mock Cudy stock web UI: test/mock-stock-ui.py on 127.0.0.1, driven by a REAL headless Chromium via stock-ui.mjs
#  * mock router: ssh/scp/sshpass stand-ins with a stage (stock -> intermediate -> idea) and the commands the script
#    uses (board name, /proc/mtd, mtd dumps, sysupgrade -b/-T/-n, /etc/idea/version, --check, tailscale for enrol)
#  * mock `ip` that records the temporary station addresses
# Needs: node (>= 20), Chromium or Chrome, python3. Usage: tools/router-image/test/idea-router-flash.test.sh (exit 0 = pass)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; SCRIPT="$HERE/../idea-router-flash"
pass=0; fail=0
check() { local n="$1"; shift; if "$@"; then echo "PASS $n"; pass=$((pass+1)); else echo "FAIL $n"; fail=$((fail+1)); fi; }
WORK="$(mktemp -d)"; SRVPID=""; PSPID=""
cleanup_test() { [ -n "$PSPID" ] && kill "$PSPID" 2>/dev/null; [ -n "$SRVPID" ] && kill "$SRVPID" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup_test EXIT
export WORK
gen() { printf 'fake-%s-%s-not-real' "$1" "$(head -c 9 /dev/urandom | od -An -tx1 | tr -d ' \n')"; }
PW=$(gen rootpw); SPW=$(gen stockpw); KEYV=$(gen tskey)          # generated now, never committed
printf '%s\n' "$PW" > "$WORK/pw"; printf '%s\n' "$SPW" > "$WORK/spw"; printf '%s\n' "$KEYV" > "$WORK/key"
chmod 600 "$WORK/pw" "$WORK/spw" "$WORK/key"
mkdir -p "$WORK/bin" "$WORK/img" "$WORK/tmp" "$WORK/r"

# Images: a fake "intermediate" (its md5/size become the expected values) and a fake IDEA sysupgrade image + SHA256SUMS
head -c 300000 /dev/urandom > "$WORK/img/cudy_wr3000s-v1-sysupgrade_20251119.bin"
IMG=idea-router-0.1.0-dev-test-cudy_wr3000s-v1-squashfs-sysupgrade.bin
head -c 200000 /dev/urandom > "$WORK/img/$IMG"; (cd "$WORK/img" && sha256sum "$IMG" > SHA256SUMS)
INTER="$WORK/img/cudy_wr3000s-v1-sysupgrade_20251119.bin"
IMD5=$(md5sum < "$INTER" | cut -d' ' -f1); ISIZE=$(stat -c %s "$INTER")

# ---- mock router (one script; ssh, scp and sshpass are thin front-ends to it) ----
cat > "$WORK/bin/router" <<'SH'
#!/usr/bin/env bash
# router <host> <command> ; state in $WORK/r ; /tmp/* -> $WORK/r/tmp/*, /dev/mtdN -> $WORK/r/mtdN
R="$WORK/r"; host="$1"; cmd="$2"; stage=$(cat "$R/stage" 2>/dev/null || echo stock)
has() { grep -qxF "$1" "$WORK/addrs" 2>/dev/null; }
case "$host" in
  192.168.1.1) [ "$stage" = intermediate ] && has 192.168.1.50/24 || exit 255 ;;
  10.42.0.1)   [ "$stage" = idea ] && has 10.42.0.50/24 && [ "${VIA_SSHPASS:-}" = ok ] || exit 255 ;;
  *) exit 255 ;;
esac
p() { case "$1" in /tmp/*) echo "$R/tmp/${1#/tmp/}";; /dev/mtd*) echo "$R/${1#/dev/}";; *) echo "$R/none";; esac; }
mkdir -p "$R/tmp"
case "$cmd" in
  true) exit 0 ;;
  "cat /tmp/sysinfo/board_name") echo "${FAKE_BOARD:-cudy,wr3000s-v1}" ;;
  "cat /proc/mtd") printf 'dev:    size   erasesize  name\nmtd0: 00100000 00020000 "BL2"\nmtd1: 00080000 00020000 "u-boot-env"\nmtd2: 00200000 00020000 "Factory"\nmtd3: 00080000 00020000 "bdinfo"\nmtd4: 00200000 00020000 "FIP"\n' ;;
  "cat /etc/idea/version") printf 'IDEA_ROUTER_VERSION=0.1.0-dev\nGIT=test\n' ;;
  "cat "*) cat "$(p "${cmd#cat }")" ;;
  "sha256sum "*) f=$(p "${cmd#sha256sum }"); [ -f "$f" ] || exit 1
     if [ -n "${FAKE_MTD_CORRUPT:-}" ] && [ "$f" = "$R/mtd2" ]; then echo "$(printf 0%.0s {1..64})  ${cmd#sha256sum }"; exit 0; fi
     echo "$(sha256sum < "$f" | cut -d' ' -f1)  ${cmd#sha256sum }" ;;
  "rm -f "*) rm -f "$(p "${cmd#rm -f }")" ;;
  "sysupgrade -b "*) printf 'mock backup stage=%s tailscale-state=%s\n' "$stage" "$(cat "$R/up" 2>/dev/null)" | gzip > "$(p "${cmd#sysupgrade -b }")" ;;
  "sysupgrade -T "*) [ -s "$(p "${cmd#sysupgrade -T }")" ] ;;
  "sysupgrade -n "*) echo "sysupgrade -n" >> "$R/flashes"; rm -f "$R/tmp/"*; echo idea > "$R/stage"; exit 255 ;;
  "test -s /etc/idea/version") [ -z "${FAKE_NOVERSION:-}" ] ;;
  "sh /usr/share/idea/school-router-setup.sh --check") [ -n "${FAKE_CHECK_FAIL:-}" ] && { echo "CHECK FAIL wifi"; exit 1; }; echo "ALL CHECKS OK" ;;
  *"/etc/idea/sticker"*) n=$(sed -n "s/.*hostname='\([a-z-]*\)'.*/\1/p" <<<"$cmd"); echo "$n" > "$R/sticker"; echo "$n" > "$R/hostname" ;;
  "tailscale status --json"*)
     [ -f "$R/up" ] || { echo '{"BackendState":"NeedsLogin","Self":{"Online":false}}'; exit 0; }
     printf '{"BackendState":"Running","Self":{"HostName":"%s","Online":true,"Tags":["tag:idea"]}}\n' "$(cat "$R/hostname")" ;;
  "chmod 600 /tmp/tskey") [ -f "$R/tmp/tskey" ] ;;
  "tailscale up"*) grep -q -- '--auth-key=file:/tmp/tskey' <<<"$cmd" && [ -s "$R/tmp/tskey" ] && echo node-identity > "$R/up" ;;
  "test ! -e /tmp/tskey") [ ! -e "$R/tmp/tskey" ] ;;
  "tailscale ip -4"*) echo 100.64.1.2 ;;
  *) echo "mock router: unknown command: $cmd" >&2; exit 1 ;;
esac
SH
cat > "$WORK/bin/fssh" <<'SH'
#!/usr/bin/env bash
echo "ssh $*" >> "$WORK/argv.log"
host=""; for a in "$@"; do [[ -z "$host" && "$a" == root@* ]] && host="${a#*@}"; done
exec "$WORK/bin/router" "$host" "${!#}"
SH
cat > "$WORK/bin/fscp" <<'SH'
#!/usr/bin/env bash
echo "scp $*" >> "$WORK/argv.log"
src="${@: -2:1}"; dst="${!#}"; host="${dst#*@}"; host="${host%%:*}"; rpath="${dst#*:}"
"$WORK/bin/router" "$host" true || exit 1
mkdir -p "$WORK/r/tmp"; cp "$src" "$WORK/r/tmp/${rpath#/tmp/}"
SH
cat > "$WORK/bin/fsshpass" <<'SH'
#!/usr/bin/env bash
echo "sshpass $*" >> "$WORK/argv.log"
[ "$1" = -e ] || exit 90; shift
[ "${SSHPASS:-}" = "$(head -1 "$WORK/pw")" ] && VIA_SSHPASS=ok
unset SSHPASS; export VIA_SSHPASS; exec "$@"
SH
cat > "$WORK/bin/fip" <<'SH'
#!/usr/bin/env bash
echo "ip $*" >> "$WORK/ip.log"; touch "$WORK/addrs"
case "$1 $2" in
  "-o addr") while read -r a; do echo "2: eth1    inet $a scope global eth1"; done < "$WORK/addrs" ;;
  "addr add") grep -qxF "$3" "$WORK/addrs" && exit 2; echo "$3" >> "$WORK/addrs" ;;
  "addr del") grep -vxF "$3" "$WORK/addrs" > "$WORK/addrs.n"; mv "$WORK/addrs.n" "$WORK/addrs" ;;
esac
SH
chmod +x "$WORK/bin/"*

# ---- mock stock UI ----
python3 "$HERE/mock-stock-ui.py" "$WORK/r" "$WORK/port" "$WORK/spw" & SRVPID=$!
for _ in $(seq 50); do [ -s "$WORK/port" ] && break; sleep 0.1; done
PORT=$(cat "$WORK/port")
( while :; do ps -eo args >> "$WORK/ps.log" 2>/dev/null; sleep 0.1; done ) & PSPID=$!

reset_router() { cat "$WORK/r/http.log" >> "$WORK/http-all.log" 2>/dev/null; rm -rf "$WORK/r"/* "$WORK/addrs" "$WORK/bk" "$WORK/state"; mkdir -p "$WORK/r/tmp"
  echo stock > "$WORK/r/stage"; head -c 4096 /dev/urandom > "$WORK/r/mtd2"; head -c 2048 /dev/urandom > "$WORK/r/mtd3"; }
run() { TMPDIR="$WORK/tmp" HOME="$WORK/home" IDEA_ROUTER_PASSWORD_FILE="$WORK/pw" IDEA_STOCK_PASSWORD_FILE="$WORK/spw" \
  IDEA_FLEET_KEY="$WORK/key" IDEA_ROUTER_BACKUPS="$WORK/bk" IDEA_ROUTER_LOG_DIR="$WORK/state" IDEA_ROUTER_LOG="$WORK/state/enrol.log" \
  IDEA_INTERMEDIATE_MD5="$IMD5" IDEA_INTERMEDIATE_SIZE="$ISIZE" IDEA_STOCK_URL="http://127.0.0.1:$PORT" \
  IDEA_WAIT_INTERMEDIATE="${WAITI:-20}" IDEA_WAIT_IDEA=20 IDEA_POLL=0.2 IDEA_VERIFY_SLEEP=0 \
  IP="$WORK/bin/fip" SSH="$WORK/bin/fssh" SCP="$WORK/bin/fscp" SSHPASS_CMD="$WORK/bin/fsshpass" \
  bash "$SCRIPT" sunny-robin-router "${INTERARG:-$INTER}" "${IMGARG:-$WORK/img/$IMG}" > "$WORK/out" 2>&1; }
D="$WORK/bk/sunny-robin-router"
nobrowser() { [ -z "$(ls -A "$WORK/tmp")" ] && ! pgrep -f "$WORK/tmp/idea-router-flash-chrome" >/dev/null; }
noaddrs() { [ ! -s "$WORK/addrs" ]; }
uploads() { cat "$WORK/r/http.log" 2>/dev/null | grep -c '^POST /cgi-bin/luci/admin/setup'; }
modes_ok() { [ "$(stat -c %a "$WORK/bk")" = 700 ] && [ "$(stat -c %a "$D")" = 700 ] && [ "$(stat -c %a "$D/.state")" = 700 ] \
  && [ -z "$(find "$D" -type f ! -perm 600)" ]; }
HTTPLOGS="$WORK/http-all.log"
secret_free() { cat "$WORK/r/http.log" >> "$HTTPLOGS" 2>/dev/null; touch "$HTTPLOGS"
  [ -s "$WORK/ps.log" ] && ! grep -rqF -e "$PW" -e "$SPW" -e "$KEYV" "$WORK/out" "$WORK/state" "$WORK/argv.log" "$WORK/ps.log" "$WORK/ip.log" "$HTTPLOGS"; }

# 1. full chain
reset_router; run; rc=$?
check "full chain rc 0" [ "$rc" = 0 ]
check "PASS line" grep -q "^PASS sunny-robin-router flashed, tested and enrolled" "$WORK/out"
check "stock config backup saved" compgen -G "$D/stock-config-*.bin" >/dev/null
check "intermediate uploaded through the browser (md5 equal)" [ "$(md5sum < "$WORK/r/uploaded.bin" | cut -d' ' -f1)" = "$IMD5" ]
check "browser logged in to stock UI" grep -q "logged in to stock UI" "$WORK/out"
check "mtd2 dump equals router" cmp -s "$D/mtd2-Factory.bin" "$WORK/r/mtd2"
check "mtd3 dump equals router" cmp -s "$D/mtd3-bdinfo.bin" "$WORK/r/mtd3"
check "intermediate sysupgrade backup" compgen -G "$D/sysupgrade-backup-intermediate-*.tar.gz" >/dev/null
check "sysupgrade -n once" [ "$(wc -l < "$WORK/r/flashes")" = 1 ]
check "sysupgrade -T before -n" grep -q "sysupgrade -T" "$WORK/argv.log"
check "idea version recorded" grep -q IDEA_ROUTER_VERSION "$D/idea-version.txt"
check "enrolled with sticker" [ "$(cat "$WORK/r/sticker")" = sunny-robin-router ]
check "fleet key gone from router" [ ! -e "$WORK/r/tmp/tskey" ]
check "final backup holds Tailscale state" bash -c "zcat '$D'/sysupgrade-backup-final-sunny-robin-router-*.tar.gz | grep -q node-identity"
check "backups 600 in 700 folders" modes_ok
check "every backup has a sha256 (stock, mtd2, mtd3, intermediate, final)" [ "$(find "$D" -maxdepth 1 -name '*.sha256' | wc -l)" = 5 ]
check "router /tmp cleaned" [ -z "$(ls -A "$WORK/r/tmp")" ]
check "temp addresses 192.168.1.50 + 10.42.0.50 were added" bash -c "grep -q 'addr add 192.168.1.50/24 dev eth1' '$WORK/ip.log' && grep -q 'addr add 10.42.0.50/24 dev eth1' '$WORK/ip.log'"
check "temp addresses removed on exit" noaddrs
check "browser + profile removed on exit" nobrowser
check "password mode used for the IDEA image" grep -q '^sshpass -e ' "$WORK/argv.log"
check "argv/ps/flash logs were captured" bash -c "[ -s '$WORK/argv.log' ] && [ -s '$WORK/ps.log' ] && [ -s '$WORK/state/flash.log' ]"
check "no password/key in argv, ps, output, logs" secret_free

# 2. re-run: everything skipped, no browser, no second flash
run; rc=$?
check "re-run rc 0" [ "$rc" = 0 ]
check "re-run: no second upload" [ "$(uploads)" = 1 ]
check "re-run: no second sysupgrade" [ "$(wc -l < "$WORK/r/flashes")" = 1 ]
check "re-run: no browser left" nobrowser

# 3. a backup altered after it was taken -> refuse
echo tamper >> "$D/mtd3-bdinfo.bin"; run; rc=$?
check "tampered backup -> rc 6" [ "$rc" = 6 ]
check "tampered backup named" grep -q "backup changed since it was taken" "$WORK/out"
run; rc=$?
check "after a mismatch the next run refuses (rc 6)" [ "$rc" = 6 ]

# 4. stock page shows another md5 -> refuse, nothing proceeds, cleanup still runs
reset_router
kill "$SRVPID"; wait "$SRVPID" 2>/dev/null; rm -f "$WORK/port"
FAKE_PAGE_MD5=1 python3 "$HERE/mock-stock-ui.py" "$WORK/r" "$WORK/port" "$WORK/spw" & SRVPID=$!
for _ in $(seq 50); do [ -s "$WORK/port" ] && break; sleep 0.1; done; PORT=$(cat "$WORK/port")
run; rc=$?
check "page md5 mismatch -> rc 6" [ "$rc" = 6 ]
check "page md5 mismatch: not proceeded" [ "$(cat "$WORK/r/stage")" = stock ]
check "page md5 mismatch: MISMATCH recorded" [ -f "$D/.state/MISMATCH" ]
check "page md5 mismatch: browser + profile removed" nobrowser
kill "$SRVPID"; wait "$SRVPID" 2>/dev/null; rm -f "$WORK/port"
python3 "$HERE/mock-stock-ui.py" "$WORK/r" "$WORK/port" "$WORK/spw" & SRVPID=$!
for _ in $(seq 50); do [ -s "$WORK/port" ] && break; sleep 0.1; done; PORT=$(cat "$WORK/port")

# 5. mtd2 sha256 differs on the router -> refuse, keep the bad dump aside
reset_router; FAKE_MTD_CORRUPT=1 run; rc=$?
check "mtd sha256 mismatch -> rc 6" [ "$rc" = 6 ]
check "mtd mismatch: .BAD kept, no good dump" bash -c "[ -f '$D/mtd2-Factory.bin.BAD' ] && [ ! -f '$D/mtd2-Factory.bin' ]"
check "mtd mismatch: no sysupgrade" [ ! -f "$WORK/r/flashes" ]
check "mtd mismatch: temp address removed" noaddrs

# 6. wrong board -> refuse
reset_router; FAKE_BOARD=cudy,wr3000h-v1 run; rc=$?
check "wrong board -> rc 6" [ "$rc" = 6 ]

# 7. resume: self-test fails after the flash; the re-run continues from the self-test only
reset_router; FAKE_CHECK_FAIL=1 run; rc=$?
check "self-test failure -> rc 5" [ "$rc" = 5 ]
check "self-test failure: cleanup removed 10.42.0.50" noaddrs
check "self-test failure: not enrolled" [ ! -f "$WORK/r/up" ]
up_before=$(uploads); run; rc=$?
check "resume after self-test fix -> rc 0" [ "$rc" = 0 ]
check "resume: no new upload" [ "$(uploads)" = "$up_before" ]
check "resume: sysupgrade -n still once" [ "$(wc -l < "$WORK/r/flashes")" = 1 ]
check "resume: enrolled" [ -f "$WORK/r/up" ]

# 8. intermediate never answers (upload "done" but the router stays on stock) -> rc 4, address cleaned
reset_router; mkdir -p "$D/.state"; touch "$D/.state/stock-backup.done" "$D/.state/stock-upload.done"
WAITI=1 run; rc=$?
check "intermediate never up -> rc 4" [ "$rc" = 4 ]
check "timeout prints recovery hint" grep -q "Cudy TFTP" "$WORK/out"
check "timeout: 192.168.1.50 removed" noaddrs

# 9. preflight refusals (router untouched)
reset_router; : > "$WORK/argv.log"
printf 'x' >> "$WORK/img/bad-inter.bin"; INTERARG="$WORK/img/bad-inter.bin" run; rc=$?
check "wrong intermediate file -> rc 3" [ "$rc" = 3 ]
cp "$WORK/img/$IMG" "$WORK/img/x-ubootmod-squashfs-sysupgrade.bin"; IMGARG="$WORK/img/x-ubootmod-squashfs-sysupgrade.bin" run; rc=$?
check "ubootmod image -> rc 3" [ "$rc" = 3 ]
cp "$WORK/img/$IMG" "$WORK/img/other-squashfs-sysupgrade.bin"; IMGARG="$WORK/img/other-squashfs-sysupgrade.bin" run; rc=$?
check "image without sha256 -> rc 3" [ "$rc" = 3 ]
chmod 644 "$WORK/pw"; run; rc=$?; chmod 600 "$WORK/pw"
check "password file 644 -> rc 3" [ "$rc" = 3 ]
check "preflight refusals touched no router" [ ! -s "$WORK/argv.log" ]
run_bad() { bash "$SCRIPT" Bad_Name a b >/dev/null 2>&1; }; run_bad; rc=$?
check "bad sticker -> rc 2" [ "$rc" = 2 ]

kill "$PSPID" 2>/dev/null; PSPID=""
check "whole suite: no password/key in argv, ps, output, logs" secret_free
echo "$pass passed, $fail failed"; [ "$fail" = 0 ]
