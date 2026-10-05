#!/usr/bin/env bash
# duration-test-ops.test.sh — offline tests for duration-test Ops hooks (idea#166).
# No Pi, no Tailscale, no real fleet-state touched.
# Usage: tools/fleet/duration-test-ops.test.sh
# Exit 0 if all checks pass, 1 otherwise.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAIM="$SCRIPT_DIR/duration-test-claim.sh"
RELEASE="$SCRIPT_DIR/duration-test-release.sh"
WRAP="$SCRIPT_DIR/duration-test-health-wrap.sh"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"

pass=0; fail=0
ok()  { echo "PASS $1"; pass=$((pass + 1)); }
bad() { echo "FAIL $1"; fail=$((fail + 1)); }
check() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }

real_fp() { cat "$REPO_ROOT/fleet-state.json" "$REPO_ROOT"/audit/*.jsonl 2>/dev/null | sha256sum; }
REAL_BEFORE="$(real_fp)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export STATE_FILE="$WORK/fleet-state.json"
export BOT_NAME="selftest-atlas"
export HEALTH_DIR="$WORK/health"
mkdir -p "$HEALTH_DIR"

cat > "$STATE_FILE" <<'JSON'
{
  "_comment": "test copy",
  "idea02": {"role":"golden","status":"idle","claim":null,"mdns":true},
  "idea01": {"role":"spare","status":"idle","claim":null,"mdns":false},
  "idea03": {"role":"review","status":"idle","claim":null,"mdns":false},
  "idea04": {"role":"spare","status":"idle","claim":null,"mdns":false}
}
JSON
chmod 664 "$STATE_FILE"

claim_val() { jq -r --arg p "$1" '.[$p].claim // empty' "$STATE_FILE"; }
status_val() { jq -r --arg p "$1" '.[$p].status // empty' "$STATE_FILE"; }

# 1. refuse golden via --pis
"$CLAIM" --pis idea02 walk-t1 >/dev/null 2>&1; rc=$?
check "claim refuses idea02 (exit 1)" test "$rc" = 1
check "golden still idle/unclaimed" test "$(status_val idea02):$(claim_val idea02)" = "idle:"

# 2. claim two pool Pis by count
"$CLAIM" --count 2 walk-t1 >/dev/null
check "idea01 claimed for walk" test "$(claim_val idea01)" = "selftest-atlas: duration-walk walk-t1 idea#166"
check "idea03 claimed for walk" test "$(claim_val idea03)" = "selftest-atlas: duration-walk walk-t1 idea#166"
check "idea01 status testing" test "$(status_val idea01)" = testing
check "idea04 left free" test "$(status_val idea04):$(claim_val idea04)" = "idle:"

# 3. second claim while busy fails; does not touch free idea04 incorrectly mid-flight
"$CLAIM" --count 2 walk-t2 >/dev/null 2>&1; rc=$?
check "claim fails when not enough idle" test "$rc" = 1
check "idea04 still free after failed claim" test "$(status_val idea04):$(claim_val idea04)" = "idle:"

# 4. dry-run does not change state
before="$(sha256sum < "$STATE_FILE")"
"$CLAIM" --dry-run --pis idea04 walk-t3 >/dev/null
check "dry-run claim leaves state unchanged" test "$(sha256sum < "$STATE_FILE")" = "$before"

# 5. release by walk-id
"$RELEASE" --walk-id walk-t1 >/dev/null
check "release clears idea01 claim" test "$(claim_val idea01)" = ""
check "release sets idea01 idle" test "$(status_val idea01)" = idle
check "release clears idea03 claim" test "$(claim_val idea03)" = ""
check "golden untouched after release" test "$(status_val idea02):$(claim_val idea02)" = "idle:"

# 6. release refuses golden
"$RELEASE" --pis idea02 >/dev/null 2>&1; rc=$?
check "release refuses idea02" test "$rc" = 1

# 7. health-wrap pause marker (dry-run + real pause without calling live health)
# Stub check-fleet-health by putting a fake earlier in PATH? Simpler: --dry-run.
"$WRAP" before --pause --dry-run >/dev/null
check "dry-run before does not create PAUSED" test ! -e "$HEALTH_DIR/PAUSED"

# Replace CFH invocation path: run before --pause with dry-run false but
# intercept by pointing SCRIPT — instead call wrap with a fake CFH via PATH trick.
# Directly exercise pause/clear by invoking bash functions is heavy; use --dry-run
# for after clear and write marker ourselves for clear-pause path.
echo "duration-test intentional pause since test" > "$HEALTH_DIR/PAUSED"
"$WRAP" after --clear-pause --dry-run >/dev/null
# dry-run still clears? Looking at script: clear happens before dry-run skip of CFH,
# and clear respects DRY_RUN. So marker should remain.
check "dry-run after --clear-pause leaves marker" test -e "$HEALTH_DIR/PAUSED"

# Non-dry clear without running real CFH: patch by running only the clear path
# via a tiny inline copy — invoke wrap with CFH overridden by replacing file?
# Create a shim directory:
SHIM="$WORK/shim"; mkdir -p "$SHIM"
cat > "$SHIM/check-fleet-health.sh" <<'SH'
#!/usr/bin/env bash
echo '{"ok":true,"pis":[]}'; exit 0
SH
chmod +x "$SHIM/check-fleet-health.sh"
# health-wrap calls $SCRIPT_DIR/check-fleet-health.sh — cannot PATH-override.
# So just verify status helper and manual marker semantics already covered;
# call wrap status:
out="$("$WRAP" status)"
check "status reports PAUSED yes" grep -q 'PAUSED: yes' <<<"$out"

# Simulate clear by removing dry-run and temporarily swapping CFH in script dir is too invasive.
# Instead: source-free — use sed copy of wrap that points CFH at shim.
cp "$WRAP" "$WORK/wrap.sh"
sed -i "s|CFH=\"\${SCRIPT_DIR}/check-fleet-health.sh\"|CFH=\"$SHIM/check-fleet-health.sh\"|" "$WORK/wrap.sh"
bash "$WORK/wrap.sh" after --clear-pause >/dev/null
check "after --clear-pause removes duration-test marker" test ! -e "$HEALTH_DIR/PAUSED"

# 8. explicit --pis claim + release
"$CLAIM" --pis idea01,idea04 walk-t4 >/dev/null
check "explicit claim idea01" test -n "$(claim_val idea01)"
check "explicit claim idea04" test -n "$(claim_val idea04)"
"$RELEASE" --pis idea01,idea04 >/dev/null
check "explicit release idea01 idle" test "$(status_val idea01)" = idle
check "explicit release idea04 idle" test "$(status_val idea04)" = idle

# 9. App#10 fixture pack pointers in Ops checklist
DOC="$SCRIPT_DIR/DURATION_TESTS.md"
check "DURATION_TESTS pins App#10 da291d5a" grep -q 'da291d5a9aa3cd59dec6aa55940194dacc202dbf' "$DOC"
check "DURATION_TESTS lists duration-kolibri-grade5a-001" grep -q 'duration-kolibri-grade5a-001' "$DOC"
check "DURATION_TESTS lists duration-nextcloud-grade5a-001" grep -q 'duration-nextcloud-grade5a-001' "$DOC"
check "DURATION_TESTS lists duration-empty-001" grep -q 'duration-empty-001' "$DOC"
check "DURATION_TESTS lists duration-empty-002" grep -q 'duration-empty-002' "$DOC"

# 10. real fleet untouched
REAL_AFTER="$(real_fp)"
check "real fleet-state + audit untouched" test "$REAL_AFTER" = "$REAL_BEFORE"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
