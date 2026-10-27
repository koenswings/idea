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
src="${@: -2:1}"; cp "$src" "$WORK/r/tskey"
SH
chmod +x "$WORK/bin/"*; export WORK
reset() { rm -rf "$WORK/r" "$WORK/argv.log" "$WORK/log"; mkdir -p "$WORK/r"; printf '%s\n' "$SECRET" > "$WORK/key"; chmod 600 "$WORK/key"; }
run() { IDEA_ROOT_PASSWORD_FILE="${RPWF:-$WORK/nopw}" IDEA_FLEET_KEY="$WORK/key" IDEA_ROUTER_LOG="$WORK/log" IDEA_VERIFY_SLEEP=0 SSH="$WORK/bin/fssh" SCP="$WORK/bin/fscp" \
        bash "$SCRIPT" "$@" > "$WORK/out" 2>&1; }
noleak() { ! grep -rqF "$SECRET" "$WORK/out" "$WORK/log" "$WORK/argv.log" 2>/dev/null; }
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
