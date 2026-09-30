#!/usr/bin/env bash
# duration-test-health-wrap.sh — health baseline around intentional reboot churn (idea#166).
#
# Design Review Ops gate: claimed duration-walk Pis are already exempt from
# health failures (claim/status != idle). Still:
#   - run check-fleet-health.sh --origin so claims pushed to origin/main are seen
#   - optionally plant HEALTH_DIR/PAUSED for intentional reboot windows
#   - after churn, re-run --origin so pm2 restart baselines refresh
#
# Usage:
#   duration-test-health-wrap.sh before [--pause] [--pis idea01,idea03]
#   duration-test-health-wrap.sh after  [--clear-pause] [--pis idea01,idea03]
#   duration-test-health-wrap.sh status
#
# Options:
#   --pause         before: write PAUSED with a duration-test marker (intentional)
#   --clear-pause   after: remove PAUSED only if it carries our marker
#   --pis LIST      pass --pi NAME for each to check-fleet-health.sh
#   --dry-run       print the planned check-fleet-health invocation only
#   -h|--help
#
# Environment:
#   HEALTH_DIR   default ~/.cache/idea-fleet-health (same as check-fleet-health.sh)
#   STATE_REPO / STATE_FILE — passed through to check-fleet-health.sh
#
# Exit: mirrors check-fleet-health.sh (0/1/2). `status` always exits 0.
# Offline note: --origin needs git fetch; without Tailscale the live Pi checks
# will report unreachable — still useful to exercise claim visibility locally
# when STATE_FILE is a temp copy (tests use fakes).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFH="${SCRIPT_DIR}/check-fleet-health.sh"
MARKER_PREFIX="duration-test intentional pause"
HEALTH_DIR="${HEALTH_DIR:-$HOME/.cache/idea-fleet-health}"

usage() { sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "ERROR: $*" >&2; exit 1; }
usage_error() { echo "ERROR: $*" >&2; echo "Run with --help for usage." >&2; exit 2; }

[ $# -ge 1 ] || usage_error "expected before|after|status"
MODE="$1"; shift
case "$MODE" in
  before|after|status) ;;
  -h|--help) usage; exit 0 ;;
  *) usage_error "mode must be before|after|status" ;;
esac

PAUSE=0
CLEAR_PAUSE=0
DRY_RUN=0
PIS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --pause) PAUSE=1; shift ;;
    --clear-pause) CLEAR_PAUSE=1; shift ;;
    --pis)
      [ $# -ge 2 ] || usage_error "--pis needs a list"
      IFS=',' read -r -a PIS <<< "$2"; shift 2
      ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) usage_error "unknown option: $1" ;;
    *) usage_error "unexpected argument: $1" ;;
  esac
done

[ -f "$CFH" ] || die "check-fleet-health.sh not found at $CFH"
mkdir -p "$HEALTH_DIR"

if [ "$MODE" = status ]; then
  if [ -f "$HEALTH_DIR/PAUSED" ]; then
    echo "PAUSED: yes"
    echo "---"
    cat "$HEALTH_DIR/PAUSED"
  else
    echo "PAUSED: no"
  fi
  exit 0
fi

run_health() {
  local -a cmd=("$CFH" --origin)
  local p
  for p in "${PIS[@]:-}"; do
    p="${p// /}"
    [ -n "$p" ] || continue
    cmd+=(--pi "$p")
  done
  echo "Running: ${cmd[*]}"
  if [ "$DRY_RUN" = 1 ]; then
    echo "dry-run: skipped check-fleet-health.sh"
    return 0
  fi
  "${cmd[@]}"
}

if [ "$MODE" = before ]; then
  cat <<EOF
=== duration-test health BEFORE intentional reboot churn ===
- Claims must be on origin/main so --origin treats walk Pis as claimed
  (claimed Pis never fail the health gate / never alert).
- Prefer pushing the claim commit before starting reboot actions.
- Optional --pause plants \$HEALTH_DIR/PAUSED for the intentional window.
EOF
  if [ "$PAUSE" = 1 ]; then
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    msg="$MARKER_PREFIX since $ts (idea#166). Safe to clear with: duration-test-health-wrap.sh after --clear-pause"
    if [ "$DRY_RUN" = 1 ]; then
      echo "dry-run: would write PAUSED: $msg"
    else
      echo "$msg" > "$HEALTH_DIR/PAUSED"
      echo "Wrote $HEALTH_DIR/PAUSED"
    fi
  fi
  run_health
  exit $?
fi

# after
cat <<EOF
=== duration-test health AFTER intentional reboot churn ===
- Re-running --origin refreshes pm2 restart baselines so the next routine
  does not treat intentional reboots as a fresh failure.
- If --pause was used, pass --clear-pause once walk Pis are idle/claimed cleanly.
EOF
if [ "$CLEAR_PAUSE" = 1 ]; then
  if [ -f "$HEALTH_DIR/PAUSED" ] && grep -q "$MARKER_PREFIX" "$HEALTH_DIR/PAUSED" 2>/dev/null; then
    if [ "$DRY_RUN" = 1 ]; then
      echo "dry-run: would remove duration-test PAUSED marker"
    else
      rm -f "$HEALTH_DIR/PAUSED"
      echo "Removed duration-test PAUSED marker at $HEALTH_DIR/PAUSED"
    fi
  elif [ -f "$HEALTH_DIR/PAUSED" ]; then
    echo "WARN: PAUSED exists but is not a duration-test marker; leaving it alone:" >&2
    cat "$HEALTH_DIR/PAUSED" >&2
  else
    echo "No PAUSED file to clear"
  fi
fi
run_health
exit $?
