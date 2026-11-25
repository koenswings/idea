#!/usr/bin/env bash
# find-available-pi.test.sh: offline tests with temp fleet-state copies. Exit 0 = all pass.
set -uo pipefail
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/find-available-pi.sh"
pass=0; fail=0
check() { local n="$1"; shift; if "$@"; then echo "PASS $n"; pass=$((pass+1)); else echo "FAIL $n"; fail=$((fail+1)); fi; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
base='{"_comment":"x",
 "idea01":{"role":"golden","status":"idle","claim":null},
 "idea02":{"role":"fleet-pending","status":"idle","claim":null},
 "idea03":{"role":"spare","status":"idle","claim":null},
 "idea04":{"role":"spare","status":"idle","claim":null},
 "kind-panda":{"role":"kit-engine","status":"idle"},
 "wizardly-hugle":{"role":"production","status":"idle"}}'
pick() { printf '%s' "$1" > "$W/s.json"; STATE_FILE="$W/s.json" bash "$SCRIPT" "${2:-engine}"; }
check "first idle pool Pi" [ "$(pick "$base")" = idea03 ]
check "domain no longer picks golden idea01 (engine)" [ "$(pick "$base" engine)" = idea03 ]
check "domain no longer picks idea02 (console)" [ "$(pick "$base" console)" = idea03 ]
check "claimed idle Pi skipped" [ "$(pick "$(jq '.idea03.claim="Kid: repro"' <<<"$base")")" = idea04 ]
s="$(jq '.idea03.status="testing" | .idea04.status="testing"' <<<"$base")"
pick "$s" >/dev/null; rc=$?
check "pool busy: kits, production, idea02, golden never returned (exit 1)" [ "$rc" = 1 ]
check "pool busy: nothing on stdout" [ -z "$(pick "$s")" ]
check "FLEET_DENY honoured" [ "$(printf '%s' "$base" > "$W/s.json"; FLEET_DENY="idea03" STATE_FILE="$W/s.json" bash "$SCRIPT")" = idea04 ]
check "role review counts as pool" [ "$(pick "$(jq '.idea03.status="testing" | .idea04.role="review"' <<<"$base")")" = idea04 ]
check "empty-string claim is unclaimed" [ "$(pick "$(jq '.idea03.claim=""' <<<"$base")")" = idea03 ]
echo "passed $pass, failed $fail"; [ "$fail" = 0 ]
