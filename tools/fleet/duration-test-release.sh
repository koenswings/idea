#!/usr/bin/env bash
# duration-test-release.sh — clear duration-test claims and document Pi restore (idea#166).
#
# Clears claim + status=idle via update-fleet-state.sh for Pis claimed for a walk.
# Does **not** SSH to Pis (Tailscale may be absent). Prints the Design Review
# restore checklist: leave the shared pool store (2VroE, mdns: true). Pool is
# idea03 and idea04 only (never golden idea01, never walker-host idea02).
# Honours fleet-state claims: never clears a claim that is not this duration
# walk (or, with --pis only, a duration-walk claim).
# --run-teardown runs teardown.sh <pi> --yes (idea#107: restores main, post-check,
# marks the Pi idle). A Pi whose teardown fails keeps its claim and status (exit 1);
# the other Pis are still released. It is not documented here as a complete restore.
#
# Usage:
#   duration-test-release.sh [--dry-run] --walk-id <id>
#   duration-test-release.sh [--dry-run] --pis idea03,idea04
#   duration-test-release.sh [--dry-run] --walk-id <id> --run-teardown
#
# Options:
#   --walk-id ID   release Pis whose claim contains "duration-walk <ID>"
#   --pis LIST     explicit comma-separated pool Pis (idea03/idea04 only)
#   --run-teardown run tools/fleet/teardown.sh <pi> --yes first; a Pi whose teardown fails keeps
#                  its claim and status (exit 1), so it is never marked idle off main
#   --dry-run      print plan only
#   -h|--help      show this help
#
# Environment: STATE_FILE, BOT_NAME (default "Atlas Ops") — same as claim script.
#
# Exit: 0 released (or dry-run), 1 runtime, 2 usage.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UFS="${SCRIPT_DIR}/update-fleet-state.sh"
TEARDOWN="${TEARDOWN:-${SCRIPT_DIR}/teardown.sh}"
POOL_ALLOWED='idea03 idea04'

usage() { sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "ERROR: $*" >&2; exit 1; }
usage_error() { echo "ERROR: $*" >&2; echo "Run with --help for usage." >&2; exit 2; }

WALK_ID=""
PIS_EXPLICIT=()
DRY_RUN=0
RUN_TEARDOWN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --walk-id)
      [ $# -ge 2 ] || usage_error "--walk-id needs an id"
      WALK_ID="$2"; shift 2
      ;;
    --pis)
      [ $# -ge 2 ] || usage_error "--pis needs a comma-separated list"
      IFS=',' read -r -a PIS_EXPLICIT <<< "$2"; shift 2
      ;;
    --run-teardown) RUN_TEARDOWN=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) usage_error "unknown option: $1" ;;
    *) usage_error "unexpected argument: $1" ;;
  esac
done

[ -n "$WALK_ID" ] || [ ${#PIS_EXPLICIT[@]} -gt 0 ] || usage_error "need --walk-id and/or --pis"
command -v jq >/dev/null || die "jq not found"
[ -f "$UFS" ] || die "update-fleet-state.sh not found at $UFS"

if [ -z "${STATE_FILE:-}" ]; then
  STATE_FILE="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)/fleet-state.json"
fi
[ -f "$STATE_FILE" ] || die "fleet-state.json not found at $STATE_FILE"
export BOT_NAME="${BOT_NAME:-Atlas Ops}"

is_pool_name() {
  local p="$1"
  for a in $POOL_ALLOWED; do [ "$p" = "$a" ] && return 0; done
  return 1
}

refuse_golden() {
  local pi="$1"
  local role
  role="$(jq -r --arg p "$pi" '.[$p].role // "review"' "$STATE_FILE")"
  if [ "$pi" = "idea02" ] || [ "$role" = "golden" ]; then
    die "refusing to touch golden Pi '$pi' (role=$role)"
  fi
}

# Never clear another bot's claim, or a claim that is not this duration walk.
assert_releasable_claim() {
  local pi="$1"
  local claim
  claim="$(jq -r --arg p "$pi" '.[$p].claim // empty' "$STATE_FILE")"
  if [ -z "$claim" ] || [ "$claim" = "null" ]; then
    return 0
  fi
  if [ -n "$WALK_ID" ]; then
    if [[ "$claim" == *"duration-walk ${WALK_ID}"* ]]; then
      return 0
    fi
    die "refusing to release '$pi': claim is not this duration walk (claim=${claim})"
  fi
  if [[ "$claim" == *"duration-walk "* ]]; then
    return 0
  fi
  die "refusing to release '$pi': existing claim is not a duration-walk claim (claim=${claim})"
}

mapfile -t TARGETS < <(
  if [ ${#PIS_EXPLICIT[@]} -gt 0 ]; then
    for pi in "${PIS_EXPLICIT[@]}"; do
      pi="${pi// /}"
      [ -n "$pi" ] || continue
      echo "$pi"
    done
  else
    needle="duration-walk ${WALK_ID}"
    jq -r --arg n "$needle" '
      to_entries[]
      | select(.key | startswith("_") | not)
      | select((.value.claim // "") | tostring | contains($n))
      | .key
    ' "$STATE_FILE"
  fi
)

[ ${#TARGETS[@]} -gt 0 ] || die "no Pis matched (walk-id=${WALK_ID:-none} pis=${PIS_EXPLICIT[*]:-none})"

echo "Duration-test release plan:"
echo "  walk-id: ${WALK_ID:-"(explicit --pis)"}"
echo "  pis:     ${TARGETS[*]}"
echo "  teardown: $([ "$RUN_TEARDOWN" = 1 ] && echo "yes (teardown.sh <pi> --yes)" || echo no)"

for pi in "${TARGETS[@]}"; do
  jq -e --arg p "$pi" 'has($p)' "$STATE_FILE" >/dev/null || die "unknown Pi '$pi'"
  refuse_golden "$pi"
  if ! is_pool_name "$pi"; then
    die "refusing '$pi': duration-test pool is idea03 and idea04 only (idea01 is golden, idea02 is the walker host)"
  fi
  assert_releasable_claim "$pi"
done

if [ "$DRY_RUN" = 1 ]; then
  echo "dry-run: no fleet-state writes"
  exit 0
fi

TEARDOWN_FAILED=()
for pi in "${TARGETS[@]}"; do
  if [ "$RUN_TEARDOWN" = 1 ]; then
    echo "note: running teardown.sh $pi --yes" >&2
    if ! "$TEARDOWN" "$pi" --yes; then
      # Never mark a Pi idle that may still be off main: keep its claim and status for a human.
      echo "ERROR: teardown.sh $pi --yes failed; claim and status kept, Pi NOT released" >&2
      TEARDOWN_FAILED+=("$pi")
      continue
    fi
  fi
  BOT_NAME="$BOT_NAME" STATE_FILE="$STATE_FILE" "$UFS" --null "$pi" claim
  BOT_NAME="$BOT_NAME" STATE_FILE="$STATE_FILE" "$UFS" "$pi" status idle
done

cat <<'RESTORE'

=== Pi restore checklist (Design Review Ops gate) ===
For each released Pi, confirm over SSH when Tailscale is available:

1. Leave the shared dev store in place (automerge:2VroE…). Do not restore a
   unique store, and do not point at the kit store or production.
2. mDNS stays on: Engine config mdns: true (fleet-state .mdns should stay true).
3. Local config.yaml and the Pi note untouched (do not overwrite the Pi note).
4. pm2 engine online as user pi on merged main (or the intended post-walk tree).
5. Optional: tools/fleet/check-fleet-health.sh --origin --pi <pi>

Without --run-teardown this release only clears fleet-state claim/status. Leave 2VroE
and mdns: true as they are; do not force a unique store or mdns: false.
See tools/fleet/DURATION_TESTS.md
RESTORE

echo "Released $(( ${#TARGETS[@]} - ${#TEARDOWN_FAILED[@]} )) of ${#TARGETS[@]} Pi(s): ${TARGETS[*]}"

if [ ${#TEARDOWN_FAILED[@]} -gt 0 ]; then
  echo "NOT released (teardown failed): ${TEARDOWN_FAILED[*]}" >&2
  exit 1
fi
