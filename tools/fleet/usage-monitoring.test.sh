#!/usr/bin/env bash
# Offline tests for usage-monitoring.sh (idea#411). Fake ssh, temp fleet-state.
# No Pi, no real fleet-state.json touched.
set -uo pipefail
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$D/usage-monitoring.sh"
REPO_ROOT="$(git -C "$D" rev-parse --show-toplevel)"
real_fp() { cat "$REPO_ROOT/fleet-state.json" "$REPO_ROOT"/audit/*.jsonl 2>/dev/null | sha256sum; }
REAL_BEFORE="$(real_fp)"
pass=0; fail=0
check() { local n="$1"; shift; if "$@"; then echo "PASS $n"; pass=$((pass+1)); else echo "FAIL $n"; fail=$((fail+1)); fi; }

check "script bash -n" bash -n "$S"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/health"
cat > "$WORK/bin/fakessh" <<'SH'
#!/usr/bin/env bash
host="${1#pi@}"; shift
cmd="$*"
echo "$host :: $cmd" >> "$WORK/ssh.log"
case "$cmd" in
  *pm2*|*docker*|*systemctl*|*compose*)
    echo "FORBIDDEN $cmd" >> "$WORK/forbid.log"
    exit 9
    ;;
  */idea-usage-settings\ status)
    cat "$WORK/remote-status"
    ;;
  */idea-usage-settings\ on)
    printf 'on\n' > "$WORK/remote-status"
    echo on
    ;;
  */idea-usage-settings\ off)
    printf 'off\n' > "$WORK/remote-status"
    echo off
    ;;
  *)
    echo "unexpected: $cmd" >&2
    exit 9
    ;;
esac
SH
chmod +x "$WORK/bin/fakessh"
printf 'off\n' > "$WORK/remote-status"

export PATH="$WORK/bin:$PATH" WORK SSH_CMD="$WORK/bin/fakessh" \
  STATE_FILE="$WORK/fleet-state.json" HEALTH_DIR="$WORK/health" BOT_NAME=Atlas

reset_state() {
cat > "$STATE_FILE" <<'JSON'
{
  "idea01": {"role":"golden","status":"idle","claim":null,"tailscale":"100.99.231.94"},
  "idea02": {"role":"fleet-pending","status":"hold","claim":null,"tailscale":"100.85.108.118"},
  "idea03": {"role":"spare","status":"idle","claim":null,"tailscale":"100.126.117.80"},
  "idea04": {"role":"spare","status":"testing","claim":"Kid","tailscale":"100.108.39.45"},
  "wizardly-hugle": {"role":"production","status":"production","claim":null,"tailscale":"100.115.60.6"},
  "sunny-robin": {"role":"kit-engine","status":"kit","claim":null,"tailscale":"100.96.98.10"}
}
JSON
rm -f "$WORK/ssh.log" "$WORK/forbid.log"
printf 'off\n' > "$WORK/remote-status"
}

j() { jq -r "$1" <<<"$OUT"; }
run() { OUT="$("$@" 2>/dev/null)"; RC=$?; }

reset_state
run "$S"
check "missing args exits 2" test "$RC" = 2

reset_state
run "$S" idea03 enable; check "bad verb exits 2" test "$RC" = 2
check "bad verb does not ssh" test ! -e "$WORK/ssh.log"

reset_state
run "$S" idea03 status extra; check "extra arg exits 2" test "$RC" = 2

reset_state
run "$S" idea03 status
check "status on idle spare exits 0" test "$RC" = 0
check "status JSON ok" test "$(j .ok)" = true
check "status previous is off" test "$(j .previous)" = off
check "status value is off" test "$(j .value)" = off
check "status unchanged" test "$(j .unchanged)" = true
check "status names the pi" test "$(j .pi)" = idea03
check "status ssh is helper status only" bash -c 'grep -q "idea-usage-settings status" "$0" && ! grep -Eq "pm2|docker|systemctl|sudo " "$0"' "$WORK/ssh.log"

reset_state
run "$S" idea03 on
check "on from off exits 0" test "$RC" = 0
check "on previous is off" test "$(j .previous)" = off
check "on value is on" test "$(j .value)" = on
check "on is a change" test "$(j .unchanged)" = false
check "on ssh never mentions pm2 or docker" bash -c '! grep -Eq "pm2|docker|systemctl|sudo " "$0"' "$WORK/ssh.log"
check "on called status then on" bash -c 's=$(grep -n "idea-usage-settings status" "$0" | head -1 | cut -d: -f1); o=$(grep -n "idea-usage-settings on" "$0" | head -1 | cut -d: -f1); [ -n "$s" ] && [ -n "$o" ] && [ "$o" -gt "$s" ]' "$WORK/ssh.log"

run "$S" idea03 on
check "on twice is idempotent" test "$RC" = 0
check "second on previous is on" test "$(j .previous)" = on
check "second on value is on" test "$(j .value)" = on
check "second on unchanged" test "$(j .unchanged)" = true

run "$S" idea03 off
check "off from on exits 0" test "$RC" = 0
check "off previous is on" test "$(j .previous)" = on
check "off value is off" test "$(j .value)" = off

run "$S" idea03 off
check "off twice is idempotent" test "$RC" = 0
check "second off unchanged" test "$(j .unchanged)" = true

reset_state
run "$S" idea01 on
check "refuses golden idea01" test "$RC" = 1
check "golden: no ssh" test ! -e "$WORK/ssh.log"

reset_state
run "$S" idea02 on
check "refuses idea02 (deny list)" test "$RC" = 1
check "idea02: no ssh" test ! -e "$WORK/ssh.log"

reset_state
run "$S" wizardly-hugle on
check "refuses wizardly-hugle / idea" test "$RC" = 1
check "idea host: no ssh" test ! -e "$WORK/ssh.log"

reset_state
run "$S" idea04 on
check "refuses a Pi claimed by someone else" test "$RC" = 1
check "foreign claim: no ssh" test ! -e "$WORK/ssh.log"

reset_state
run "$S" sunny-robin on
check "refuses a kit without --approve-kit-window" test "$RC" = 1
check "kit without window: no ssh" test ! -e "$WORK/ssh.log"

reset_state
run "$S" sunny-robin on --approve-kit-window
check "kit allowed with --approve-kit-window" test "$RC" = 0
check "kit toggle value is on" test "$(j .value)" = on
check "kit ssh used the helper" bash -c 'grep -q "idea-usage-settings on" "$0" && ! grep -Eq "pm2|docker" "$0"' "$WORK/ssh.log"

reset_state
run "$S" ghost on
check "refuses unknown Pi" test "$RC" = 1
check "unknown Pi not created" test "$(jq 'has("ghost")' "$STATE_FILE")" = false

reset_state
touch "$HEALTH_DIR/HOLD"
run "$S" idea03 on
check "refuses while fleet HOLD" test "$RC" = 1
check "HOLD: no ssh" test ! -e "$WORK/ssh.log"
rm -f "$HEALTH_DIR/HOLD"

reset_state
run "$S" --ignore-fleet-hold idea03 status
check "--ignore-fleet-hold still works when no hold" test "$RC" = 0

check "no forbidden helper invocations" test ! -e "$WORK/forbid.log"
check "real fleet-state.json and audit/ untouched" test "$(real_fp)" = "$REAL_BEFORE"

echo "---"
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
