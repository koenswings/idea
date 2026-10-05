#!/usr/bin/env bash
# duration-test-release.sh — clear duration-test claims and document Pi restore (idea#166).
#
# Clears claim + status=idle via update-fleet-state.sh for Pis claimed for a walk.
# Does **not** SSH to Pis (Tailscale may be absent). Prints the Design Review
# teardown restore checklist: unique Automerge store + mdns:false. Wraps the
# existing teardown.sh stub when --run-teardown is set (still a stub today).
#
# Usage:
#   duration-test-release.sh [--dry-run] --walk-id <id>
#   duration-test-release.sh [--dry-run] --pis idea01,idea03
#   duration-test-release.sh [--dry-run] --walk-id <id> --run-teardown
#
# Options:
#   --walk-id ID   release Pis whose claim contains "duration-walk <ID>"
#   --pis LIST     explicit comma-separated Pis (must be pool; never idea02)
#   --run-teardown also invoke tools/fleet/teardown.sh <pi> (stub until idea#107)
#   --dry-run      print plan only
#   -h|--help      show this help
#
# Environment: STATE_FILE, BOT_NAME (default "Atlas Ops") — same as claim script.
#
# Exit: 0 released (or dry-run), 1 runtime, 2 usage.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UFS="${SCRIPT_DIR}/update-fleet-state.sh"
TEARDOWN="${SCRIPT_DIR}/teardown.sh"
POOL_ALLOWED='idea01 idea03 idea04'

usage() { sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; }
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
echo "  teardown stub: $([ "$RUN_TEARDOWN" = 1 ] && echo yes || echo no)"

for pi in "${TARGETS[@]}"; do
  jq -e --arg p "$pi" 'has($p)' "$STATE_FILE" >/dev/null || die "unknown Pi '$pi'"
  refuse_golden "$pi"
  if ! is_pool_name "$pi"; then
    die "refusing '$pi': duration-test pool is idea01/idea03/idea04 only"
  fi
done

if [ "$DRY_RUN" = 1 ]; then
  echo "dry-run: no fleet-state writes"
  exit 0
fi

for pi in "${TARGETS[@]}"; do
  if [ "$RUN_TEARDOWN" = 1 ]; then
    echo "note: invoking teardown.sh $pi (stub until idea#107)" >&2
    if ! "$TEARDOWN" "$pi"; then
      echo "WARN: teardown.sh $pi failed/stubbed — continuing with fleet-state release" >&2
    fi
  fi
  BOT_NAME="$BOT_NAME" STATE_FILE="$STATE_FILE" "$UFS" --null "$pi" claim
  BOT_NAME="$BOT_NAME" STATE_FILE="$STATE_FILE" "$UFS" "$pi" status idle
done

cat <<'RESTORE'

=== Pi restore checklist (Design Review Ops gate) ===
For each released Pi, confirm over SSH when Tailscale is available:

1. Unique Automerge store still isolated (do NOT point at golden's store).
   Check Engine config / note in fleet-state for the Pi's own automerge: URL.
2. mDNS remains off: Engine config mdns: false (fleet-state .mdns should stay false).
3. Local config.yaml isolation details untouched (do not overwrite the Pi note).
4. pm2 engine online as user pi on merged main (or the intended post-walk tree).
5. Optional: tools/fleet/check-fleet-health.sh --origin --pi <pi>

teardown.sh is still a stub (idea#107). This release only clears fleet-state
claim/status; the restore steps above are the live teardown contract for walks.
See tools/fleet/DURATION_TESTS.md
RESTORE

echo "Released ${#TARGETS[@]} Pi(s): ${TARGETS[*]}"
