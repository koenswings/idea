#!/usr/bin/env bash
# idea-router-enrol.test.sh — offline dry-run of idea-router-enrol with a mock ssh/scp "router".
# No router touched. Usage: tools/router-image/test/idea-router-enrol.test.sh  (exit 0 = all pass)
set -uo pipefail
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/idea-router-enrol"
pass=0; fail=0
check() { local n="$1"; shift; if "$@"; then echo "PASS $n"; pass=$((pass+1)); else echo "FAIL $n"; fail=$((fail+1)); fi; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
SECRET="FAKE-TEST-KEY-not-real"
mkdir -p "$WORK/bin"
# Mock router: state in $WORK/r. Records every argv in $WORK/argv.log (to prove the key is never on a command line).
cat > "$WORK/bin/fssh" <<'SH'
#!/usr/bin/env bash
echo "ssh $*" >> "$WORK/argv.log"
R="$WORK/r"; cmd="${!#}"
[ -n "${FAKE_DOWN:-}" ] && exit 255
# FAKE_NEEDPW: router with a root password and no authorized key (fresh IDEA image, idea#276)
[ -n "${FAKE_NEEDPW:-}" ] && [ "${VIA_SSHPASS:-}" != ok ] && exit 255
case "$cmd" in
  true) exit 0 ;;
  *"/etc/idea/sticker"*) n=$(sed -n "s/.*hostname='\([a-z-]*\)'.*/\1/p" <<<"$cmd"); echo "$n" > "$R/sticker"; echo "$n" > "$R/hostname" ;;
  "tailscale status --json"*)
     [ -f "$R/up" ] || { echo '{"BackendState":"NeedsLogin","Self":{"Online":false}}'; exit 0; }
     printf '{"BackendState":"Running","Self":{"HostName":"%s","Online":true,"Tags":["tag:idea"]}}\n' "$(cat "$R/hostname")" ;;
  "chmod 600 /tmp/tskey") [ -f "$R/tskey" ] ;;
  "tailscale up"*) [ -n "${FAKE_UPFAIL:-}" ] && exit 1
     grep -q -- '--auth-key=file:/tmp/tskey' <<<"$cmd" && grep -q -- '--advertise-tags=tag:idea' <<<"$cmd" \
       && grep -q -- '--accept-dns=false' <<<"$cmd" && [ -s "$R/tskey" ] && touch "$R/up" ;;
  "rm -f /tmp/tskey") rm -f "$R/tskey" ;;
  "test ! -e /tmp/tskey") [ ! -e "$R/tskey" ] ;;
  "tailscale ip -4"*) echo 100.64.1.2 ;;
  "passwd root"*) cat > "$R/rootpw" ;;
  *) echo "mock: unknown $cmd" >&2; exit 1 ;;
esac
SH
cat > "$WORK/bin/fscp" <<'SH'
#!/usr/bin/env bash
echo "scp $*" >> "$WORK/argv.log"
[ -n "${FAKE_NEEDPW:-}" ] && [ "${VIA_SSHPASS:-}" != ok ] && exit 1
src="${@: -2:1}"; cp "$src" "$WORK/r/tskey"
SH
# Mock sshpass: must be called as 'sshpass -e', must get the password in env SSHPASS (never argv).
cat > "$WORK/bin/fsshpass" <<'SH'
#!/usr/bin/env bash
echo "sshpass $*" >> "$WORK/argv.log"
[ "$1" = -e ] || { echo "mock sshpass: expected -e" >&2; exit 90; }
shift
[ "${SSHPASS:-}" = "$(cat "$WORK/pwexpect")" ] && VIA_SSHPASS=ok
unset SSHPASS; export VIA_SSHPASS
exec "$@"
SH
chmod +x "$WORK/bin/"*; export WORK
reset() { rm -rf "$WORK/r" "$WORK/argv.log" "$WORK/log"; mkdir -p "$WORK/r"; printf '%s\n' "$SECRET" > "$WORK/key"; chmod 600 "$WORK/key"; }
run() { SSHPASS_CMD="$WORK/bin/fsshpass" IDEA_ROOT_PASSWORD_FILE="${RPWF:-$WORK/nopw}" IDEA_FLEET_KEY="$WORK/key" IDEA_ROUTER_LOG="$WORK/log" IDEA_VERIFY_SLEEP=0 SSH="$WORK/bin/fssh" SCP="$WORK/bin/fscp" \
        bash "$SCRIPT" "$@" > "$WORK/out" 2>&1; }
noleak() { ! grep -rqF "$SECRET" "$WORK/out" "$WORK/log" "$WORK/argv.log" 2>/dev/null; }
PW="fake-pw-$RANDOM$RANDOM-not-real"; printf '%s\n' "$PW" > "$WORK/pwexpect"
pwfile() { printf '%s\n' "$PW" > "$WORK/pw"; chmod 600 "$WORK/pw"; }
nopwleak() { ! grep -rqF "$PW" "$WORK/out" "$WORK/log" "$WORK/argv.log" 2>/dev/null; }
PWSECRET="FAKE-root-pw-not-real"
pwnoleak() { ! grep -rqF "$PWSECRET" "$WORK/out" "$WORK/log" "$WORK/argv.log" 2>/dev/null; }

reset; run sunny-robin; rc=$?
check "enrol succeeds" [ "$rc" = 0 ]
check "sticker written" [ "$(cat "$WORK/r/sticker")" = sunny-robin ]
check "hostname set" [ "$(cat "$WORK/r/hostname")" = sunny-robin ]
check "tailscale up ran" [ -f "$WORK/r/up" ]
check "key removed from router" [ ! -e "$WORK/r/tskey" ]
check "PASS logged" grep -q "PASS enrolled" "$WORK/log"
check "key never in output/log/argv" noleak

run sunny-robin; rc=$?   # second run: idempotent, no key push
check "re-run succeeds" [ "$rc" = 0 ]
check "re-run reports already enrolled" grep -q "already on the tailnet" "$WORK/out"
check "re-run pushes no key" [ "$(grep -c '^scp' "$WORK/argv.log")" = 1 ]

reset; rm "$WORK/key"; run sunny-robin; rc=$?
check "missing key file -> rc 3" [ "$rc" = 3 ]
check "missing key names file" grep -q "fleet key file missing" "$WORK/out"
check "missing key: router untouched" [ ! -e "$WORK/argv.log" ]

reset; chmod 644 "$WORK/key"; run sunny-robin; rc=$?
check "mode 644 -> rc 3" [ "$rc" = 3 ]
check "mode message" grep -q "has mode 644, must be 600" "$WORK/out"

reset; run Bad_Name; rc=$?
check "bad sticker -> rc 2" [ "$rc" = 2 ]

reset; run sunny-robin-router; rc=$?
check "-router suffix accepted" [ "$rc" = 0 ]
check "-router hostname set" [ "$(cat "$WORK/r/hostname")" = sunny-robin-router ]
check "-router: key never leaked" noleak
for bad in sunny-robin-switch sunny-robin-router-x sunny router-robin-sunny-x; do
  reset; run "$bad"; rc=$?
  check "bad name $bad -> rc 2" [ "$rc" = 2 ]
done

reset; FAKE_DOWN=1 run sunny-robin; rc=$?
check "router down -> rc 4" [ "$rc" = 4 ]

reset; FAKE_UPFAIL=1 run sunny-robin; rc=$?
check "tailscale up failure -> rc 5" [ "$rc" = 5 ]
check "key removed after failure" [ ! -e "$WORK/r/tskey" ]
check "failure: key never leaked" noleak

# ---- password mode (idea#276) against a password-only mock router ----
reset; FAKE_NEEDPW=1 run sunny-robin; rc=$?
check "pw-only router, key mode -> rc 4" [ "$rc" = 4 ]
check "key mode uses BatchMode" grep -q "BatchMode=yes" "$WORK/argv.log"

reset; pwfile; FAKE_NEEDPW=1 IDEA_ROUTER_PASSWORD_FILE="$WORK/pw" run sunny-robin; rc=$?
check "password file mode enrols" [ "$rc" = 0 ]
check "password mode: tailscale up ran" [ -f "$WORK/r/up" ]
check "password mode: key removed" [ ! -e "$WORK/r/tskey" ]
check "password mode: every ssh/scp went through sshpass -e" [ "$(grep -c '^sshpass -e ' "$WORK/argv.log")" -ge 5 ]
nobatch() { ! grep -q "BatchMode=yes" "$WORK/argv.log"; }; check "password mode: no BatchMode" nobatch
check "password mode: logged as mode=password" grep -q "mode=password" "$WORK/log"
check "password never in argv/output/log" nopwleak
check "password mode: key never leaked" noleak

reset; FAKE_NEEDPW=1 run --password-stdin sunny-robin < "$WORK/pwexpect"; rc=$?
check "--password-stdin enrols" [ "$rc" = 0 ]
check "--password-stdin: password never in argv/output/log" nopwleak

reset; FAKE_NEEDPW=1 run --password-stdin sunny-robin < /dev/null; rc=$?
check "--password-stdin empty -> rc 3" [ "$rc" = 3 ]
check "empty stdin: router untouched" [ ! -e "$WORK/argv.log" ]

reset; pwfile; chmod 644 "$WORK/pw"; IDEA_ROUTER_PASSWORD_FILE="$WORK/pw" run sunny-robin; rc=$?
check "password file mode 644 -> rc 3" [ "$rc" = 3 ]
check "password file mode message" grep -q "password file .* has mode 644, must be 600" "$WORK/out"
check "bad password file: router untouched" [ ! -e "$WORK/argv.log" ]

reset; IDEA_ROUTER_PASSWORD_FILE="$WORK/nope" run sunny-robin; rc=$?
check "password file missing -> rc 3" [ "$rc" = 3 ]

reset; printf 'wrong-fake-pw\n' > "$WORK/pw"; chmod 600 "$WORK/pw"; FAKE_NEEDPW=1 IDEA_ROUTER_PASSWORD_FILE="$WORK/pw" run sunny-robin; rc=$?
check "wrong password -> rc 4" [ "$rc" = 4 ]


# idea#322: root password is a flash-time secret (file, stdin only)
reset; printf '%s\n' "$PWSECRET" > "$WORK/rpw"; chmod 600 "$WORK/rpw"; RPWF="$WORK/rpw" run sunny-robin; rc=$?
check "root pw: enrol succeeds" [ "$rc" = 0 ]
check "root pw: set via stdin" [ "$(head -n1 "$WORK/r/rootpw")" = "$PWSECRET" ]
check "root pw: never in output/log/argv" pwnoleak
reset; printf '%s\n' "$PWSECRET" > "$WORK/rpw"; chmod 644 "$WORK/rpw"; RPWF="$WORK/rpw" run sunny-robin; rc=$?
check "root pw: world-readable file -> rc 3" [ "$rc" = 3 ]
reset; run sunny-robin; rc=$?
check "root pw: missing file -> warn, still enrols" [ "$rc" = 0 ] && grep -q "WARN no root password" "$WORK/out"
echo "$pass passed, $fail failed"; [ "$fail" = 0 ]
