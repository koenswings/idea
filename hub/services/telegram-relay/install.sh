#!/bin/sh
# Install on the hub Pi "idea" (formerly wizardly-hugle) as user pi (user service; linger is already on). Never prints secrets.
# Safe to re-run: code and unit are refreshed from this checkout; an existing ~/.config/tg-relay/env is never
# rewritten, so a real token is never replaced by empty or example values. .env.example is never copied.
set -e
cd "$(dirname "$0")"
D=$HOME/tg-relay; C=$HOME/.config/tg-relay
mkdir -p "$D/files" "$C" "$HOME/.config/systemd/user" "$HOME/.local/bin"
chmod 700 "$D" "$D/files" "$C"
cp tg_relay.py tg-send "$D/"; chmod 700 "$D/tg_relay.py" "$D/tg-send"
ln -sf "$D/tg-send" "$HOME/.local/bin/tg-send"
if [ ! -e "$C/env" ]; then
  # First install only: empty token plus the kit webhook keys copied from kit-watch (if present).
  # Written to a temp file and moved into place, so a failed run never leaves a half-written env.
  T=$(umask 077; mktemp "$C/env.new.XXXXXX")
  echo "TELEGRAM_BOT_TOKEN=" > "$T"
  if [ -r "$HOME/.config/kit-watch/env" ]; then
    grep -E '^KIT_WEBHOOK_(URL|KEY)=' "$HOME/.config/kit-watch/env" >> "$T" || true
  else
    echo "note: ~/.config/kit-watch/env not found; add KIT_WEBHOOK_URL/KIT_WEBHOOK_KEY to $C/env by hand" >&2
  fi
  chmod 600 "$T"; mv "$T" "$C/env"
  echo "created $C/env (TELEGRAM_BOT_TOKEN is empty; set it by hand)"
else
  echo "kept existing $C/env (not rewritten)"
fi
chmod 600 "$C/env"
cp tg-relay.service "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
systemctl --user enable tg-relay.service
systemctl --user restart tg-relay.service || true
echo "installed; status:"; systemctl --user is-active tg-relay.service || true
