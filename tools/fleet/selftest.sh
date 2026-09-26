#!/usr/bin/env bash
# selftest.sh — exercise update-fleet-state.sh against a temp copy (no Pi, no real state touched)
# Usage: tools/fleet/selftest.sh     Exit 0 if all checks pass, 1 otherwise.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UFS="${SCRIPT_DIR}/update-fleet-state.sh"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"

pass=0
fail=0
ok()  { echo "PASS $1"; pass=$((pass + 1)); }
bad() { echo "FAIL $1"; fail=$((fail + 1)); }
check() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }

# Fingerprint the real state + audit so we can prove they were not touched.
real_fp() { cat "$REPO_ROOT/fleet-state.json" "$REPO_ROOT"/audit/*.jsonl 2>/dev/null | sha256sum; }
REAL_BEFORE="$(real_fp)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export STATE_FILE="$WORK/fleet-state.json"
export BOT_NAME="selftest"
cat > "$STATE_FILE" <<'JSON'
{
  "_comment": "test copy",
  "idea02": { "role": "review", "domain": "any", "pr": "idea#102 (console#122)", "status": "deployed" }
}
JSON
chmod 664 "$STATE_FILE"
AUDIT="$WORK/audit/audit-$(date -u +%Y).jsonl"

val()   { jq -c --arg pi "$1" --arg f "$2" '.[$pi][$f]' "$STATE_FILE"; }
typ()   { jq -r --arg pi "$1" --arg f "$2" '.[$pi][$f] | type' "$STATE_FILE"; }
mode()  { stat -c '%a' "$STATE_FILE"; }
lines() { [ -f "$AUDIT" ] && wc -l < "$AUDIT" || echo 0; }

# 1. set a string
"$UFS" idea02 status idle >/dev/null; rc=$?
check "successful update exits 0" test "$rc" = 0
check "string value stored as string" test "$(val idea02 status)" = '"idle"'

# 2. clear to null (--null)
"$UFS" --null idea02 pr >/dev/null
check "--null stores JSON null" test "$(typ idea02 pr)" = null

# 3. --json typed values
"$UFS" --json idea02 pr 5 >/dev/null
check "--json 5 stores number 5" test "$(val idea02 pr)" = 5
"$UFS" --json idea02 pr null >/dev/null
check "--json null stores JSON null" test "$(typ idea02 pr)" = null
"$UFS" --json idea02 runner_ok true >/dev/null
check "--json true stores boolean" test "$(typ idea02 runner_ok)" = boolean
"$UFS" idea02 note null >/dev/null
check "plain 'null' (no --json) stays a string" test "$(val idea02 note)" = '"null"'

# 4. invalid inputs
"$UFS" --json idea02 pr '{bad' >/dev/null 2>&1; rc=$?
check "--json invalid JSON rejected (exit 2)" test "$rc" = 2
"$UFS" idea02 pr "" >/dev/null 2>&1; rc=$?
check "empty string value rejected (exit 2)" test "$rc" = 2
"$UFS" idea02 pr >/dev/null 2>&1; rc=$?
check "missing value rejected (exit 2)" test "$rc" = 2

# 5. unknown Pi rejected without --create, file unchanged
before="$(sha256sum < "$STATE_FILE")"; nlines="$(lines)"
"$UFS" idea09 status idle >/dev/null 2>&1; rc=$?
check "unknown Pi rejected (exit 1)" test "$rc" = 1
check "unknown Pi: state file unchanged" test "$(sha256sum < "$STATE_FILE")" = "$before"
check "unknown Pi: no audit line written" test "$(lines)" = "$nlines"
check "unknown Pi: entry not created" test "$(jq 'has("idea09")' "$STATE_FILE")" = false

# 6. --create adds the Pi
"$UFS" --create idea09 status idle >/dev/null
check "--create adds new Pi" test "$(val idea09 status)" = '"idle"'
check "--create audit line marks created" test "$(tail -1 "$AUDIT" | jq -r .created)" = true

# 7. mode preserved (664 and 644)
check "file mode 664 preserved" test "$(mode)" = 664
chmod 644 "$STATE_FILE"; "$UFS" idea02 status deployed >/dev/null
check "file mode 644 preserved" test "$(mode)" = 644

# 8. audit line: valid JSON, typed, escaped quotes, right file
"$UFS" idea02 pr 'has "quotes" and \back\slash' >/dev/null
check "audit file is next to STATE_FILE" test -s "$AUDIT"
check "every audit line is valid JSON" bash -c "jq -e . '$AUDIT' >/dev/null"
check "audit value with quotes round-trips" test "$(tail -1 "$AUDIT" | jq -r .value)" = 'has "quotes" and \back\slash'
check "state value with quotes round-trips" test "$(jq -r '.idea02.pr' "$STATE_FILE")" = 'has "quotes" and \back\slash'
"$UFS" --null idea02 pr >/dev/null
check "audit records null as JSON null" test "$(tail -1 "$AUDIT" | jq -c '[.value, (.previous|type)]')" = '[null,"string"]'
check "audit bot from BOT_NAME" test "$(tail -1 "$AUDIT" | jq -r .bot)" = selftest

# 9. concurrency: 30 parallel writers to distinct fields; none lost
pids=()
for i in $(seq 1 30); do "$UFS" --json idea02 "c$i" "$i" >/dev/null & pids+=($!); done
cfail=0; for p in "${pids[@]}"; do wait "$p" || cfail=1; done
check "30 concurrent runs all exit 0" test "$cfail" = 0
check "30 concurrent runs: no update lost" test "$(jq '[.idea02 | to_entries[] | select(.key | test("^c[0-9]+$"))] | length' "$STATE_FILE")" = 30
check "state file still valid JSON after concurrency" bash -c "jq -e . '$STATE_FILE' >/dev/null"
check "no temp files left behind" test -z "$(find "$WORK" -maxdepth 1 -name '.fleet-state.*')"

# 10. real repo state and audit untouched
check "real fleet-state.json and audit/ untouched" test "$(real_fp)" = "$REAL_BEFORE"

echo "---"
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
