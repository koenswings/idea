#!/usr/bin/env bash
# deploy-engine-remote.sh — run deploy-engine-pi.sh on ONE Pi from the box, holding a per-host lock on
# the box for the whole run (non-blocking; busy -> exit 75), so two routines on this box never deploy the
# same Pi at once. The Pi-side lock in deploy-engine-pi.sh (/tmp/idea-deploy.lock) covers other boxes/bots.
#
#   tools/fleet/deploy-engine-remote.sh <host-or-ip> <tip-sha> [--fetch <branch>] [--dry-run|--yes] [--allow-midnight] [--ignore-fleet-hold]
#
# SSH goes straight to the Tailscale IP through the box SOCKS proxy (never a jump host).
# Remaining args are forwarded to deploy-engine-pi.sh, including --allow-midnight (idea#512).
# Fleet-wide pause (same rule as deploy.sh / update-golden.sh / teardown.sh via fleet-lib.sh): refuses (exit 1, also
# for --dry-run) while $HEALTH_DIR/PAUSED or HOLD exists (check-fleet-health.sh --alert, or a manual walk hold).
# --ignore-fleet-hold skips ONLY that check (warning on stderr; the files are never touched) and is not forwarded.
# Env overrides (tests): SSH_CMD, BOX_LOCK_DIR, PROXY, HEALTH_DIR (default ~/.cache/idea-fleet-health).
set -euo pipefail
HOST="${1:?usage: <host-or-ip> <tip-sha> [args...]}"; shift
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEALTH_DIR="${HEALTH_DIR:-$HOME/.cache/idea-fleet-health}"
ARGS=(); IGNORE_HOLD=0
for a in "$@"; do if [ "$a" = --ignore-fleet-hold ]; then IGNORE_HOLD=1; else ARGS+=("$a"); fi; done
set -- "${ARGS[@]}"
FLAGS=""; for f in HOLD PAUSED; do [ -e "$HEALTH_DIR/$f" ] && FLAGS="$FLAGS $f"; done
if [ -n "$FLAGS" ]; then
  if [ "$IGNORE_HOLD" = 1 ]; then
    echo "WARNING: --ignore-fleet-hold: fleet-wide${FLAGS} in $HEALTH_DIR ignored for this run" >&2
  else
    echo "REFUSED: fleet changes are paused ($HEALTH_DIR:${FLAGS}); --ignore-fleet-hold skips only this check" >&2; exit 1
  fi
fi
LOCK="${BOX_LOCK_DIR:-/tmp}/idea-deploy-${HOST//[^A-Za-z0-9._-]/_}.lock"
PROXY="${PROXY:-127.0.0.1:1055}"
exec 8>>"$LOCK"
flock -n 8 || { echo "BUSY: box lock $LOCK held ($(cat "$LOCK.pid" 2>/dev/null || echo '?')); not starting" >&2; exit 75; }
echo "$$ $(date '+%F %T')" > "$LOCK.pid"
if [ -n "${SSH_CMD:-}" ]; then
  # shellcheck disable=SC2086
  $SSH_CMD "$HOST" "bash -s -- $*" < "$DIR/deploy-engine-pi.sh"
else
  ssh -o BatchMode=yes -o ConnectTimeout=15 -o ProxyCommand="nc -X 5 -x $PROXY %h %p" "pi@$HOST" "bash -s -- $*" < "$DIR/deploy-engine-pi.sh"
fi
