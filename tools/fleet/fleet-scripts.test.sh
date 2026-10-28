#!/usr/bin/env bash
# fleet-scripts.test.sh — offline tests for deploy.sh, teardown.sh, update-golden.sh, set-golden-pi.sh (idea#107).
# Fake ssh (SSH_CMD), fake git ls-remote and gh, a temp fleet-state.json. No Pi, no GitHub, no real state touched.
# Usage: tools/fleet/fleet-scripts.test.sh   (exit 0 = all pass)
set -uo pipefail
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$D" rev-parse --show-toplevel)"
real_fp() { cat "$REPO_ROOT/fleet-state.json" "$REPO_ROOT"/audit/*.jsonl 2>/dev/null | sha256sum; }
REAL_BEFORE="$(real_fp)"
pass=0; fail=0
check() { local n="$1"; shift; if "$@"; then echo "PASS $n"; pass=$((pass+1)); else echo "FAIL $n"; fail=$((fail+1)); fi; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/health"
REALGIT="$(command -v git)"
cat > "$WORK/bin/git" <<SH
#!/usr/bin/env bash
if [ "\$1" = ls-remote ]; then
  case "\$2" in *agent-engine-dev*) echo "eeee000000000000000000000000000000000001 \$3" ;;
                *agent-console-dev*) echo "cccc000000000000000000000000000000000002 \$3" ;;
                *app-*) echo "aaaa000000000000000000000000000000000003 \$3" ;; esac
  [ "\$3" = refs/heads/nope ] && exit 0
  exit 0
fi
exec "$REALGIT" "\$@"
SH
cat > "$WORK/bin/gh" <<'SH'
#!/usr/bin/env bash
case "$*" in *compare/bad1234...main*) echo diverged ;; *compare/*) echo ahead ;;
  *commits/*) echo "eeee111111111111111111111111111111111111" ;; esac
SH
cat > "$WORK/bin/fakessh" <<'SH'
#!/usr/bin/env bash
host="${1#pi@}"; shift; cmd="$*"
echo "$host :: ${cmd//$'\n'/ }" >> "$WORK/ssh.log"
[ -n "${FAKE_UNREACH:-}" ] && [[ " $FAKE_UNREACH " == *" $host "* ]] && exit 255
case "$cmd" in
  true) exit 0 ;;
  *vcgencmd*) echo "${FAKE_TEMP:-50.0}" ;;
  "bash -s --"*) cat >/dev/null; echo "engine deployed"; [ -z "${FAKE_ENGINE_FAIL:-}" ] ;;
  PORT=*) cat >/dev/null; echo "ENGINE=${FAKE_ENGINE:-online pi}"; echo "CONSOLE=200"; echo "INSTANCE=milkwise:3333:${FAKE_INST:-200}" ;;
  *"--dir"*) cat >/dev/null; echo "Console built" ;;
  *"git fetch"*) echo "CHECKED_OUT abc" ;;
  *) echo "unexpected: $cmd" >&2; exit 9 ;;
esac
SH
chmod +x "$WORK/bin/"*
export PATH="$WORK/bin:$PATH" WORK SSH_CMD="$WORK/bin/fakessh" STATE_FILE="$WORK/fleet-state.json" \
       HEALTH_DIR="$WORK/health" BOT_NAME=Atlas POST_WAIT=0 BOX_LOCK_DIR="$WORK"
reset_state() {
cat > "$STATE_FILE" <<'JSON'
{ "_comment": "test",
  "idea01": {"role":"spare","status":"idle","pr":null,"claim":null,"tailscale":"10.0.0.1","version":"engine main@1111111, console main@2222222"},
  "idea02": {"role":"golden","status":"idle","claim":null,"tailscale":"10.0.0.2"},
  "idea03": {"role":"review","status":"idle","claim":null,"tailscale":"10.0.0.3","idle_since":"2026-10-20T00:00:00Z"},
  "idea04": {"role":"spare","status":"idle","claim":"Axle #346","tailscale":"10.0.0.4"},
  "wh":     {"role":"spare","status":"idle","claim":null,"tailscale":"100.115.60.6"},
  "kit1":   {"role":"kit-engine","status":"kit","tailscale":"10.0.0.9"},
  "gold":   {"role":"golden","status":"idle","claim":null,"tailscale":"10.0.0.7","version":"engine main@1111111, console main@2222222"} }
JSON
rm -f "$WORK/ssh.log" "$HEALTH_DIR"/*; }
j() { jq -r "$1" <<<"$OUT"; }
st() { jq -r --arg p "$1" --arg f "$2" '.[$p][$f] // "null"' "$STATE_FILE"; }
run() { OUT="$("$@" 2>/dev/null)"; RC=$?; }

# --- deploy.sh ---
reset_state
run "$D/deploy.sh" idea01 engine agent-engine-dev feat-x
check "deploy dry run exits 0"            test "$RC" = 0
check "deploy dry run is valid JSON"      bash -c 'jq -e .ok >/dev/null <<<"$0"' "$OUT"
check "deploy dry run touches nothing"    test ! -e "$WORK/ssh.log"
check "deploy dry run leaves state idle"  test "$(st idea01 status)" = idle
run "$D/deploy.sh" idea01 engine agent-engine-dev feat-x --yes
check "deploy engine exits 0"             test "$RC" = 0
check "deploy engine resolves sha"        test "$(j .sha)" = eeee000000000000000000000000000000000001
check "deploy sets status deployed"       test "$(st idea01 status)" = deployed
check "deploy sets claim Atlas"           bash -c '[[ "$0" == Atlas* ]]' "$(st idea01 claim)"
check "deploy sets branch"                test "$(st idea01 branch)" = feat-x
check "deploy runs post_check ok"         test "$(j '.steps[]|select(.step=="post_check").ok')" = true
check "deploy writes audit lines"         test -s "$WORK/audit/audit-$(date -u +%Y).jsonl"
run "$D/deploy.sh" idea01 console agent-console-dev feat-c --yes
check "deploy console (own claim) ok"     test "$RC" = 0
check "deploy console builds"             grep -q -- "--dir" "$WORK/ssh.log"
reset_state
run "$D/deploy.sh" idea03 app-disk app-kolibri feat-a --yes
check "deploy app-disk ok"                test "$RC" = 0
check "deploy app-disk under agent-app-dev" bash -c 'jq -e ".steps[]|select(.step==\"checkout /home/pi/idea/agents/agent-app-dev/app-kolibri\")" >/dev/null <<<"$0"' "$OUT"
reset_state
run "$D/deploy.sh" idea02 engine agent-engine-dev x --yes;   check "deploy refuses idea02 (deny)"   test "$RC" = 1
run "$D/deploy.sh" gold engine agent-engine-dev x --yes;     check "deploy refuses golden"           test "$RC" = 1
run "$D/deploy.sh" kit1 engine agent-engine-dev x --yes;     check "deploy refuses kit engine"       test "$RC" = 1
run "$D/deploy.sh" wh engine agent-engine-dev x --yes;       check "deploy refuses wh host"          test "$RC" = 1
run "$D/deploy.sh" idea04 engine agent-engine-dev x --yes;   check "deploy refuses other bot claim"  test "$RC" = 1
check "refused claim left untouched"      test "$(st idea04 claim)" = "Axle #346"
run "$D/deploy.sh" ghost engine agent-engine-dev x --yes;    check "deploy refuses unknown Pi"       test "$RC" = 1
check "unknown Pi not created"            test "$(jq 'has("ghost")' "$STATE_FILE")" = false
run "$D/deploy.sh" idea01 engine agent-console-dev x;        check "deploy repo/component mismatch = 2" test "$RC" = 2
run "$D/deploy.sh" idea01 bogus agent-engine-dev x;          check "deploy bad component = 2"        test "$RC" = 2
run "$D/deploy.sh" idea01;                                    check "deploy usage = 2"                test "$RC" = 2
touch "$HEALTH_DIR/HOLD"
run "$D/deploy.sh" idea01 engine agent-engine-dev x --yes;   check "deploy refuses while HOLD"       test "$RC" = 1
rm -f "$HEALTH_DIR/HOLD"
FAKE_TEMP=78.2 run "$D/deploy.sh" idea01 engine agent-engine-dev x --yes
check "deploy refuses above 75 C"         test "$RC" = 1
check "hot Pi not claimed"                test "$(st idea01 claim)" = null
FAKE_INST=000 run "$D/deploy.sh" idea01 engine agent-engine-dev x --yes
check "deploy fails when MilkWise down"   test "$RC" = 1
check "failed post-check is reported"     bash -c 'jq -e ".steps[]|select(.step==\"post_check\" and .ok==false)" >/dev/null <<<"$0"' "$OUT"
reset_state
FAKE_ENGINE_FAIL=1 run "$D/deploy.sh" idea01 engine agent-engine-dev x --yes
check "deploy engine failure exits 1"     test "$RC" = 1

# --- teardown.sh ---
reset_state
"$D/deploy.sh" idea01 app-disk app-kolibri feat-a --yes >/dev/null 2>&1
run "$D/teardown.sh" idea01
check "teardown dry run exits 0"          test "$RC" = 0
check "teardown dry run keeps deployed"   test "$(st idea01 status)" = deployed
run "$D/teardown.sh" idea01 --yes
check "teardown exits 0"                  test "$RC" = 0
check "teardown status idle"              test "$(st idea01 status)" = idle
check "teardown pr null (JSON null)"      test "$(jq -c '.idea01.pr' "$STATE_FILE")" = null
check "teardown claim/branch/repo null"   test "$(jq -c '[.idea01.claim,.idea01.branch,.idea01.repo]' "$STATE_FILE")" = "[null,null,null]"
check "teardown writes version"           test "$(st idea01 version)" = "engine main@eeee000000000000000000000000000000000001, console main@cccc000000000000000000000000000000000002"
check "teardown sets idle_since"          test "$(st idea01 idle_since)" != null
check "teardown restores app checkout"    grep -q "git fetch" "$WORK/ssh.log"
run "$D/teardown.sh" idea01 --yes;        check "teardown idempotent"              test "$RC" = 0
run "$D/teardown.sh" gold --yes;          check "teardown refuses golden"          test "$RC" = 1
run "$D/teardown.sh" idea04 --yes;        check "teardown refuses other claim"     test "$RC" = 1
"$D/deploy.sh" idea03 engine agent-engine-dev f --yes >/dev/null 2>&1
FAKE_ENGINE="stopped pi" run "$D/teardown.sh" idea03 --yes
check "teardown fails if engine not online" test "$RC" = 1
check "failed teardown stays claimed"     test "$(st idea03 status)" = deployed

# --- update-golden.sh ---
reset_state
run "$D/update-golden.sh" engine main --yes
check "update-golden refuses 2 golden Pis" test "$RC" = 1
jq 'del(.idea02)' "$STATE_FILE" > "$WORK/s" && mv "$WORK/s" "$STATE_FILE"
run "$D/update-golden.sh" engine main
check "update-golden dry run ok"          test "$RC" = 0
check "update-golden dry run no version change" test "$(st gold version)" = "engine main@1111111, console main@2222222"
run "$D/update-golden.sh" engine main --yes
check "update-golden engine ok"           test "$RC" = 0
check "update-golden updates engine part only" test "$(st gold version)" = "engine main@eeee000000000000000000000000000000000001, console main@2222222"
check "update-golden status stays idle"   test "$(st gold status)" = idle
run "$D/update-golden.sh" console eeee111 --yes
check "update-golden console by sha ok"   test "$RC" = 0
run "$D/update-golden.sh" engine bad1234 --yes
check "update-golden refuses sha not on main" test "$RC" = 1
run "$D/update-golden.sh" engine 'x;rm' --yes
check "update-golden rejects bad version = 2" test "$RC" = 2
FAKE_INST=500 run "$D/update-golden.sh" engine main --yes
check "update-golden no version write on failed check" test "$(j .ok)" = false
jq 'del(.gold)' "$STATE_FILE" > "$WORK/s" && mv "$WORK/s" "$STATE_FILE"
run "$D/update-golden.sh" engine main --yes
check "update-golden refuses no golden"   test "$RC" = 1

# --- set-golden-pi.sh ---
reset_state; jq 'del(.idea02)' "$STATE_FILE" > "$WORK/s" && mv "$WORK/s" "$STATE_FILE"
run "$D/set-golden-pi.sh" --yes
check "set-golden no change when golden reachable" test "$(j .changed)" = false
FAKE_UNREACH=10.0.0.7 run "$D/set-golden-pi.sh"
check "set-golden dry run picks newest idle_since" test "$(j .golden)" = idea03
check "set-golden dry run changes nothing" test "$(st idea03 role)" = review
FAKE_UNREACH=10.0.0.7 run "$D/set-golden-pi.sh" --yes
check "set-golden promotes idea03"        test "$(st idea03 role)" = golden
check "set-golden demotes old golden"     test "$(st gold role)" = golden-unavailable
check "set-golden lists next steps"       test "$(j '.next_steps|length')" = 2
reset_state; jq 'del(.idea02,.gold)' "$STATE_FILE" > "$WORK/s" && mv "$WORK/s" "$STATE_FILE"
FAKE_UNREACH=10.0.0.3 run "$D/set-golden-pi.sh" --yes
check "set-golden skips unreachable, never claimed/wh/kit" test "$(j .golden)" = idea01
reset_state
run "$D/set-golden-pi.sh" --yes;          check "set-golden refuses 2 golden"      test "$RC" = 1
# --pi <name>: explicit target (idea02 removed so only "gold" is golden)
reset_state; jq 'del(.idea02)' "$STATE_FILE" > "$WORK/s" && mv "$WORK/s" "$STATE_FILE"
run "$D/set-golden-pi.sh" --pi idea01
check "set-golden --pi dry run targets idea01"   test "$(j .golden)" = idea01
check "set-golden --pi dry run changes nothing"  test "$(st idea01 role)" = spare
run "$D/set-golden-pi.sh" --yes --pi idea01
check "set-golden --pi promotes idea01"          test "$(st idea01 role)" = golden
check "set-golden --pi reachable old -> spare"   test "$(st gold role)" = spare
check "set-golden --pi old golden idle"          test "$(st gold status)" = idle
run "$D/set-golden-pi.sh" --yes --pi idea01
check "set-golden --pi same Pi is no change"     test "$(j .changed)" = false
reset_state; jq 'del(.idea02)' "$STATE_FILE" > "$WORK/s" && mv "$WORK/s" "$STATE_FILE"
FAKE_UNREACH=10.0.0.7 run "$D/set-golden-pi.sh" --yes --pi idea01
check "set-golden --pi unreachable old -> golden-unavailable" test "$(st gold role)" = golden-unavailable
reset_state; jq 'del(.idea02)' "$STATE_FILE" > "$WORK/s" && mv "$WORK/s" "$STATE_FILE"
FAKE_UNREACH=10.0.0.1 run "$D/set-golden-pi.sh" --yes --pi idea01
check "set-golden --pi refuses unreachable"      test "$RC" = 1
check "set-golden --pi unreachable keeps state"  test "$(st idea01 role)/$(st gold role)" = spare/golden
run "$D/set-golden-pi.sh" --yes --pi idea04;     check "set-golden --pi refuses claimed"  test "$RC" = 1
run "$D/set-golden-pi.sh" --yes --pi kit1;       check "set-golden --pi refuses non-pool" test "$RC" = 1
run "$D/set-golden-pi.sh" --yes --pi wh;         check "set-golden --pi refuses wh host"  test "$RC" = 1
run "$D/set-golden-pi.sh" --yes --pi nope;       check "set-golden --pi refuses unknown"  test "$RC" = 1
run "$D/set-golden-pi.sh" --yes --pi;            check "set-golden --pi needs a name = 2" test "$RC" = 2
check "set-golden --pi refusals change nothing"  test "$(st gold role)" = golden

# --- --ignore-fleet-hold (skips ONLY the fleet-wide HOLD/PAUSED) ---
reset_state; touch "$HEALTH_DIR/HOLD"; echo "paused" > "$HEALTH_DIR/PAUSED"
ERR="$("$D/deploy.sh" idea01 engine agent-engine-dev x --yes --ignore-fleet-hold 2>&1 >/dev/null)"
run "$D/deploy.sh" idea01 engine agent-engine-dev x --yes --ignore-fleet-hold
check "override: deploy proceeds under HOLD+PAUSED" test "$RC" = 0
check "override: JSON fleet_hold_ignored true"  test "$(j .fleet_hold_ignored)" = true
check "override: JSON lists both flags"         test "$(j '.fleet_hold_flags|join(",")')" = "HOLD,PAUSED"
check "override: warning on stderr"             bash -c '[[ "$0" == *"WARNING: --ignore-fleet-hold"* ]]' "$ERR"
check "override: HOLD/PAUSED files untouched"   test -e "$HEALTH_DIR/HOLD" -a -e "$HEALTH_DIR/PAUSED"
run "$D/teardown.sh" idea01 --yes --ignore-fleet-hold
check "override: teardown proceeds"             test "$RC" = 0
run "$D/teardown.sh" idea01 --yes
check "no override: teardown still refuses"     test "$RC" = 1
for t in idea02 gold kit1 wh idea04; do
  run "$D/deploy.sh" "$t" engine agent-engine-dev x --yes --ignore-fleet-hold
  check "override: per-Pi refusal $t kept"      test "$RC" = 1
done
jq '.idea03.status="hold"' "$STATE_FILE" > "$WORK/s" && mv "$WORK/s" "$STATE_FILE"
run "$D/deploy.sh" idea03 engine agent-engine-dev x --yes --ignore-fleet-hold
check "override: per-Pi status hold kept"       test "$RC" = 1
jq '.idea03.status="paused"' "$STATE_FILE" > "$WORK/s" && mv "$WORK/s" "$STATE_FILE"
run "$D/deploy.sh" idea03 engine agent-engine-dev x --yes --ignore-fleet-hold
check "override: per-Pi status paused kept"     test "$RC" = 1
FAKE_TEMP=80.0 run "$D/deploy.sh" idea01 engine agent-engine-dev x --yes --ignore-fleet-hold
check "override: temperature still refuses"     test "$RC" = 1
run "$D/update-golden.sh" engine main --yes --ignore-fleet-hold
check "override: update-golden still refuses 2 golden" test "$RC" = 1
rm -f "$HEALTH_DIR/HOLD" "$HEALTH_DIR/PAUSED"
run "$D/deploy.sh" idea01 engine agent-engine-dev x --ignore-fleet-hold
check "override without hold: no field"         test "$(j '.fleet_hold_ignored // "absent"')" = absent

check "real fleet-state and audit untouched" test "$(real_fp)" = "$REAL_BEFORE"
echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
