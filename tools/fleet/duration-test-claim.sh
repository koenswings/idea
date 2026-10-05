#!/usr/bin/env bash
# duration-test-claim.sh — claim N pool Pis for a duration-tests walk (idea#166).
#
# Claims every participating pool Pi for the *whole walk* (Design Review Ops gate).
# Pool only: idea01 / idea03 / idea04 (role spare|review). Refuses idea02 and any
# role:golden. Wraps update-fleet-state.sh; does not reimplement fleet-state I/O.
#
# Usage:
#   duration-test-claim.sh [--count N] [--dry-run] <walk-id>
#   duration-test-claim.sh [--dry-run] --pis idea01,idea03 <walk-id>
#
# Options:
#   --count N   claim the first N idle pool Pis (default: 2). Ignored with --pis.
#   --pis LIST  comma-separated explicit pool Pis (must all be idle + unclaimed).
#   --dry-run   print the plan; do not write fleet-state.
#   -h|--help   show this help
#
# Environment:
#   STATE_FILE  path to fleet-state.json (passed through to update-fleet-state.sh)
#   BOT_NAME    claim / audit bot (default: "Atlas Ops")
#   WALK_REF    issue/PR tag embedded in claim (default: "idea#166")
#
# Claim text: "<BOT_NAME>: duration-walk <walk-id> <WALK_REF>"
# Status set to "testing" (same as §4.6 claim protocol).
#
# Exit: 0 claimed (or dry-run ok), 1 runtime (busy / golden / missing), 2 usage.
# Offline-safe: only needs jq + fleet-state; no SSH / Tailscale.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UFS="${SCRIPT_DIR}/update-fleet-state.sh"
POOL_ALLOWED='idea01 idea03 idea04'

usage() { sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "ERROR: $*" >&2; exit 1; }
usage_error() { echo "ERROR: $*" >&2; echo "Run with --help for usage." >&2; exit 2; }

COUNT=2
PIS_EXPLICIT=()
DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --count)
      [ $# -ge 2 ] || usage_error "--count needs N"
      COUNT="$2"
      [[ "$COUNT" =~ ^[1-9][0-9]*$ ]] || usage_error "--count must be a positive integer"
      shift 2
      ;;
    --pis)
      [ $# -ge 2 ] || usage_error "--pis needs a comma-separated list"
      IFS=',' read -r -a PIS_EXPLICIT <<< "$2"
      shift 2
      ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) usage_error "unknown option: $1" ;;
    *) break ;;
  esac
done

[ $# -eq 1 ] || usage_error "expected <walk-id>"
WALK_ID="$1"
[ -n "$WALK_ID" ] || usage_error "<walk-id> must not be empty"
[[ "$WALK_ID" != *$'\n'* ]] || usage_error "<walk-id> must be a single line"

command -v jq >/dev/null || die "jq not found"
[ -f "$UFS" ] || die "update-fleet-state.sh not found at $UFS"

if [ -z "${STATE_FILE:-}" ]; then
  STATE_FILE="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)/fleet-state.json"
fi
[ -f "$STATE_FILE" ] || die "fleet-state.json not found at $STATE_FILE"

export BOT_NAME="${BOT_NAME:-Atlas Ops}"
WALK_REF="${WALK_REF:-idea#166}"
CLAIM_TEXT="${BOT_NAME}: duration-walk ${WALK_ID} ${WALK_REF}"

is_pool_name() {
  local p="$1"
  for a in $POOL_ALLOWED; do [ "$p" = "$a" ] && return 0; done
  return 1
}

# Refuse golden / idea02 / non-pool. Print reason on stderr; return 1 if refused.
assert_claimable() {
  local pi="$1"
  local role status claim
  if ! jq -e --arg p "$pi" 'has($p)' "$STATE_FILE" >/dev/null; then
    echo "unknown Pi '$pi' (not in fleet-state)" >&2
    return 1
  fi
  role="$(jq -r --arg p "$pi" '.[$p].role // "review"' "$STATE_FILE")"
  status="$(jq -r --arg p "$pi" '.[$p].status // "unknown"' "$STATE_FILE")"
  claim="$(jq -r --arg p "$pi" '.[$p].claim // empty' "$STATE_FILE")"
  if [ "$pi" = "idea02" ] || [ "$role" = "golden" ]; then
    echo "refusing golden Pi '$pi' (role=$role); duration walks never use idea02" >&2
    return 1
  fi
  if ! is_pool_name "$pi"; then
    echo "refusing '$pi': duration-test pool is idea01/idea03/idea04 only" >&2
    return 1
  fi
  if [ "$status" != "idle" ] || [ -n "$claim" ]; then
    echo "Pi '$pi' not free (status=$status claim=${claim:-null})" >&2
    return 1
  fi
  return 0
}

pick_pis() {
  local -a out=()
  local pi
  if [ ${#PIS_EXPLICIT[@]} -gt 0 ]; then
    for pi in "${PIS_EXPLICIT[@]}"; do
      pi="${pi// /}"
      [ -n "$pi" ] || continue
      out+=("$pi")
    done
    printf '%s\n' "${out[@]}"
    return 0
  fi
  # Prefer idea01, idea03, idea04 in that order (pool affinity for walks).
  for pi in $POOL_ALLOWED; do
    [ ${#out[@]} -ge "$COUNT" ] && break
    if assert_claimable "$pi" 2>/dev/null; then
      out+=("$pi")
    fi
  done
  if [ ${#out[@]} -lt "$COUNT" ]; then
    die "need $COUNT idle pool Pi(s); only ${#out[@]} available ($(printf '%s ' "${out[@]:-none}"))"
  fi
  printf '%s\n' "${out[@]}"
}

mapfile -t TARGETS < <(pick_pis)
[ ${#TARGETS[@]} -gt 0 ] || die "no Pis selected"

echo "Duration-test claim plan:"
echo "  walk-id: $WALK_ID"
echo "  claim:   $CLAIM_TEXT"
echo "  pis:     ${TARGETS[*]}"
if [ "$DRY_RUN" = 1 ]; then
  for pi in "${TARGETS[@]}"; do
    assert_claimable "$pi" || die "dry-run refused for $pi"
  done
  echo "dry-run: no fleet-state writes"
  exit 0
fi

# Validate all before writing; fail closed if any is golden/busy.
for pi in "${TARGETS[@]}"; do
  assert_claimable "$pi" || die "preflight failed for $pi"
done

CLAIMED=()
rollback() {
  local p
  for p in "${CLAIMED[@]}"; do
    echo "rollback: releasing $p" >&2
    BOT_NAME="$BOT_NAME" STATE_FILE="$STATE_FILE" "$UFS" --null "$p" claim >/dev/null 2>&1 || true
    BOT_NAME="$BOT_NAME" STATE_FILE="$STATE_FILE" "$UFS" "$p" status idle >/dev/null 2>&1 || true
  done
}
trap 'rc=$?; if [ $rc -ne 0 ] && [ ${#CLAIMED[@]} -gt 0 ]; then rollback; fi' EXIT

for pi in "${TARGETS[@]}"; do
  BOT_NAME="$BOT_NAME" STATE_FILE="$STATE_FILE" "$UFS" "$pi" status testing
  BOT_NAME="$BOT_NAME" STATE_FILE="$STATE_FILE" "$UFS" "$pi" claim "$CLAIM_TEXT"
  CLAIMED+=("$pi")
done

trap - EXIT
echo "Claimed ${#CLAIMED[@]} Pi(s) for duration walk '$WALK_ID': ${CLAIMED[*]}"
echo "Next: push fleet-state (so check-fleet-health --origin sees claims), then run the walker."
echo "See tools/fleet/DURATION_TESTS.md"
