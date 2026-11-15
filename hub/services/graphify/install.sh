#!/bin/sh
# hub/services/graphify/install.sh — install graphify-serve as a systemd --user unit (idea#485).
# Run on the hub Pi "idea" as user pi (never root), from a checkout of main, after a merged PR and
# Koen's OK for the deploy.
#
#   sh hub/services/graphify/install.sh           install/refresh the unit, enable + restart it
#   sh hub/services/graphify/install.sh --stage   copy the unit only (no systemctl); used by tests
#
# Safe to re-run. It only writes ~/.config/systemd/user/graphify-serve.service. It never deletes,
# rebuilds or writes the served files in ~/graphify-out, never touches ~/graphify-env, and needs no
# env file or key (no LLM key, as today). If a different unit is already there, it is backed up to
# ~/.idea-hub-backups/graphify/<stamp>/ before it is replaced.
set -eu
SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
cd "$(dirname "$0")"
[ "$(id -u)" != 0 ] || { echo "run as pi, not root (systemd --user unit)" >&2; exit 2; }
STAGE=0
case "${1:-}" in
  "") ;;
  --stage) STAGE=1 ;;
  -h|--help) sed -n '2,12p' "$SELF" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "unknown option: $1" >&2; exit 2 ;;
esac
OUT=$HOME/graphify-out; U=$HOME/.config/systemd/user; UNIT=graphify-serve.service
if [ "$STAGE" = 0 ] && [ ! -d "$OUT" ]; then
  echo "refusing: $OUT is missing. Restore it from a backup first; this script never rebuilds it." >&2
  exit 1
fi
mkdir -p "$U"
if [ -e "$U/$UNIT" ] && ! cmp -s "$UNIT" "$U/$UNIT"; then
  BK=$HOME/.idea-hub-backups/graphify/$(date +%Y%m%dT%H%M%S)
  mkdir -p "$BK"; chmod 700 "$HOME/.idea-hub-backups" "$HOME/.idea-hub-backups/graphify" "$BK"
  cp -p "$U/$UNIT" "$BK/$UNIT"
  echo "backed up the previous unit to $BK/$UNIT (roll back: cp it back, then daemon-reload + restart)"
fi
T=$(mktemp "$U/.$UNIT.new.XXXXXX"); cp "$UNIT" "$T"; chmod 644 "$T"; mv "$T" "$U/$UNIT"
if [ "$STAGE" = 1 ]; then echo "staged $U/$UNIT (no systemctl calls)"; exit 0; fi
linger=$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null || echo unknown)
[ "$linger" = yes ] || echo "WARNING: linger is '$linger' for $(id -un): the unit will not start at boot. Fix: sudo loginctl enable-linger $(id -un) (hub/bootstrap.sh does this)" >&2
systemctl --user daemon-reload
systemctl --user enable "$UNIT"
systemctl --user restart "$UNIT"
echo "installed; $UNIT: $(systemctl --user is-active "$UNIT" || true)"
