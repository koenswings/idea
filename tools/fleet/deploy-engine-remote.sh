#!/usr/bin/env bash
# deploy-engine-remote.sh — run deploy-engine-pi.sh on ONE Pi from the box, holding a per-host lock on
# the box for the whole run (non-blocking; busy -> exit 75), so two routines on this box never deploy the
# same Pi at once. The Pi-side lock in deploy-engine-pi.sh (/tmp/idea-deploy.lock) covers other boxes/bots.
#
#   tools/fleet/deploy-engine-remote.sh <host-or-ip> <tip-sha> [--fetch <branch>] [--dry-run|--yes]
#
# SSH goes straight to the Tailscale IP through the box SOCKS proxy (never a jump host).
# Env overrides (tests): SSH_CMD, BOX_LOCK_DIR, PROXY.
set -euo pipefail
HOST="${1:?usage: <host-or-ip> <tip-sha> [args...]}"; shift
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
