#!/bin/sh
# hub/services/kit-watch/install.sh — install kit-watch + mail-watch as a systemd --user timer (idea#484).
# Run on the hub Pi "idea" as user pi (never root), from a checkout of main, after a merged PR and
# Koen's OK for the deploy. Never prints secrets.
#
#   sh hub/services/kit-watch/install.sh               install/refresh code + units, enable the timer
#   sh hub/services/kit-watch/install.sh --stage        code, units and env only, no systemctl/crontab (tests, bootstrap --stage)
#   sh hub/services/kit-watch/install.sh --remove-cron  then (separate step, once the timer has run
#                                                      fine) drop the two old pi crontab lines
#
# Safe to re-run:
#  - code and units are refreshed from this checkout; state (state.json, mail-state.json, watch.log,
#    DISABLED) in ~/kit-watch is never touched;
#  - an existing ~/.config/kit-watch/env is never rewritten (only chmod 600), so real keys are never
#    replaced by empty or example values; .env.example is never copied. On a fresh Pi an env file with
#    empty values is created in one step, and the service skips (ExecCondition) until it is filled in;
#  - --remove-cron backs up the crontab first, removes only the kit-watch.py / mail-watch.py lines,
#    and refuses unless kit-watch.timer is enabled + active and kit-watch.service has run successfully.
set -eu
SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
cd "$(dirname "$0")"
[ "$(id -u)" != 0 ] || { echo "run as pi, not root (systemd --user units)" >&2; exit 2; }
REMOVE_CRON=0; STAGE=0
case "${1:-}" in
  "") ;;
  --remove-cron) REMOVE_CRON=1 ;;
  --stage) STAGE=1 ;;
  -h|--help) sed -n '2,20p' "$SELF" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "unknown option: $1" >&2; exit 2 ;;
esac

D=$HOME/kit-watch; C=$HOME/.config/kit-watch; U=$HOME/.config/systemd/user
STAMP=$(date +%Y%m%dT%H%M%S)
BK=$HOME/.idea-hub-backups/kit-watch/$STAMP

if [ "$REMOVE_CRON" = 1 ]; then
  en=$(systemctl --user is-enabled kit-watch.timer 2>/dev/null || true)
  ac=$(systemctl --user is-active kit-watch.timer 2>/dev/null || true)
  ran=$(systemctl --user show -p InactiveExitTimestampMonotonic --value kit-watch.service 2>/dev/null || echo 0)
  res=$(systemctl --user show -p Result --value kit-watch.service 2>/dev/null || echo unknown)
  if [ "$en" != enabled ] || [ "$ac" != active ] || [ "${ran:-0}" = 0 ] || [ "$res" != success ]; then
    echo "refusing: kit-watch.timer is-enabled=$en is-active=$ac, kit-watch.service ran=${ran:-0} result=$res" >&2
    echo "install the timer first and wait for one good run (journalctl --user -u kit-watch.service)" >&2
    exit 1
  fi
  CUR=$(crontab -l 2>/dev/null || true)
  if ! printf '%s\n' "$CUR" | grep -qE '/kit-watch/(kit|mail)-watch\.py'; then
    echo "pi crontab has no kit-watch/mail-watch lines; nothing to remove"
  else
    mkdir -p "$BK"; chmod 700 "$HOME/.idea-hub-backups" "$HOME/.idea-hub-backups/kit-watch" "$BK"
    (umask 077; printf '%s\n' "$CUR" > "$BK/crontab.pi.before")
    (umask 077; printf '%s\n' "$CUR" | grep -vE '/kit-watch/(kit|mail)-watch\.py' > "$BK/crontab.pi.after" || true)
    crontab "$BK/crontab.pi.after"
    echo "removed kit-watch/mail-watch from the pi crontab; backup: $BK/crontab.pi.before"
    echo "roll back: crontab $BK/crontab.pi.before"
  fi
  # The cron-era flock files are no longer used: quarantine them (mv, never delete).
  for f in .cron-kit.lock .cron-mail.lock; do
    if [ -e "$D/$f" ]; then mkdir -p "$BK"; chmod 700 "$BK"; mv "$D/$f" "$BK/$f"; echo "moved $D/$f -> $BK/"; fi
  done
  exit 0
fi

mkdir -p "$D" "$C" "$U"
chmod 700 "$D" "$C"
for f in kit-watch.py mail-watch.py; do
  T=$(mktemp "$D/.$f.new.XXXXXX"); cp "$f" "$T"; chmod 700 "$T"; mv "$T" "$D/$f"
done
if [ ! -e "$C/env" ]; then
  T=$(umask 077; mktemp "$C/env.new.XXXXXX")
  grep -E '^[A-Z_][A-Z0-9_]*=' .env.example > "$T"
  chmod 600 "$T"; mv "$T" "$C/env"
  echo "created $C/env with empty values; fill it in by hand (the service skips until KIT_WEBHOOK_URL is set)"
else
  echo "kept existing $C/env (not rewritten)"
fi
chmod 600 "$C/env"
cp kit-watch.service kit-watch.timer "$U/"
[ "$STAGE" = 0 ] || { echo "staged code + units only; no session or crontab operations"; exit 0; }
systemctl --user daemon-reload
systemctl --user enable kit-watch.timer
systemctl --user start kit-watch.timer
linger=$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null || echo unknown)
[ "$linger" = yes ] || echo "WARNING: linger is '$linger' for $(id -un): user timers will not start at boot. Fix: sudo loginctl enable-linger $(id -un) (hub/bootstrap.sh does this)" >&2
echo "installed; kit-watch.timer: $(systemctl --user is-active kit-watch.timer || true)"
if crontab -l 2>/dev/null | grep -qE '/kit-watch/(kit|mail)-watch\.py'; then
  echo "note: the old pi crontab lines are still there (runs overlap safely: each script takes its own lock)."
  echo "      once journalctl --user -u kit-watch.service shows a good run: sh $0 --remove-cron"
fi
