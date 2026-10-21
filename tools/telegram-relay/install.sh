#!/bin/sh
# Install on wizardly-hugle as user pi (user service; linger is already on). Never prints secrets.
set -e
D=$HOME/tg-relay; C=$HOME/.config/tg-relay
mkdir -p "$D/files" "$C" "$HOME/.config/systemd/user" "$HOME/.local/bin"
chmod 700 "$D" "$D/files" "$C"
cp tg_relay.py tg-send "$D/"; chmod 700 "$D/tg_relay.py" "$D/tg-send"
ln -sf "$D/tg-send" "$HOME/.local/bin/tg-send"
if [ ! -f "$C/env" ]; then
  umask 077
  { echo "TELEGRAM_BOT_TOKEN="; grep -E '^KIT_WEBHOOK_(URL|KEY)=' "$HOME/.config/kit-watch/env"; } > "$C/env"
fi
chmod 600 "$C/env"
cp tg-relay.service "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
systemctl --user enable tg-relay.service
systemctl --user restart tg-relay.service || true
echo "installed; status:"; systemctl --user is-active tg-relay.service || true
