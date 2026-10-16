#!/bin/sh
# idea-fix-client: one-time field fix for already-flashed s14 client cards (idea#202), no reflash.
#  - keyboard layout -> US (Pi 500 US QWERTY): /etc/default/keyboard (console + GNOME default)
#  - Chrome new tab -> Chrome's normal Google new tab (drops NewTabPageLocation from the managed policy)
# Works in reset-on-reboot (overlay) mode: writes the real root underneath (/run/rootfsbase, remounted rw),
# and also the running overlay so the change shows now. Normal mode: writes / directly. Then reboots.
# Run at the keyboard as admin:  sudo sh idea-fix-client.sh      (--no-reboot skips the reboot). Learners who already chose a layout in GNOME Settings keep theirs until the overlay reset wipes it.
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
POL=etc/opt/chrome/policies/managed/idea.json
KB=etc/default/keyboard
fix() {  # $1 = root prefix
  r=$1
  if [ -f "$r/$KB" ]; then
    sed -i 's/^XKBLAYOUT=.*/XKBLAYOUT="us"/; s/^XKBVARIANT=.*/XKBVARIANT=""/' "$r/$KB"
  fi
  install -d "$r/etc/X11/xorg.conf.d"   # what localectl set-x11-keymap writes; GNOME/GDM read it via localed
  printf 'Section "InputClass"\n  Identifier "system-keyboard"\n  MatchIsKeyboard "on"\n  Option "XkbLayout" "us"\n  Option "XkbModel" "pc105"\nEndSection\n' > "$r/etc/X11/xorg.conf.d/00-keyboard.conf"
  if [ -f "$r/$POL" ]; then
    sed -i '/"NewTabPageLocation"/d' "$r/$POL"
    python3 -m json.tool "$r/$POL" >/dev/null || { echo "policy JSON broken in $r/$POL" >&2; exit 3; }
  fi
  echo "fixed: ${r:-/}"
}
if grep -q '^[^ ]* / overlay ' /proc/mounts; then
  L=/run/rootfsbase
  [ -d "$L/etc" ] || { echo "overlay on but $L missing; run: sudo idea-client-mode normal; reboot; rerun this" >&2; exit 4; }
  mount -o remount,rw "$L"
  fix "$L"; sync
  mount -o remount,ro "$L" || true
  fix ""   # running session too
else
  fix ""; sync
fi
echo "done. Check after reboot: chrome://policy (no NewTabPageLocation), and Shift+2 gives @"
[ "${1:-}" = --no-reboot ] || { sleep 3; reboot; }
