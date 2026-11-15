#!/usr/bin/env bash
# hub/host/capture.sh: READ-ONLY capture of the hub files that hub/ does not hold yet
# (idea#484-#486). Run on the hub Pi "idea" as pi, only under a fleet-state claim and with
# Steve's go. It changes nothing on the host: it only reads, and writes copies into a new
# private folder (mode 700) under /tmp, which the operator then reviews and copies into a PR.
#
# Usage: hub/host/capture.sh [OUTDIR]     (default: a new /tmp/hub-capture-<stamp>.XXXX)
#
# It copies: /usr/local/bin/boot.sh, /etc/caddy/* (regular files), the root and pi crontabs,
# "systemctl cat" + state of caddy and caddy-api, ~/.config/systemd/user/graphify-serve.service,
# ~/kit-watch/{kit-watch,mail-watch}.py and /etc/cron.weekly/renew-tailscale-cert.
# It lists (names only, never contents) /etc/cron.d. It never reads env files (~/.config/*/env).
# Root-only files are read with "sudo -n" (fails cleanly without a sudo rule; no prompt).
#
# A secret-pattern scan prints, per copied file, only the COUNT of suspicious lines (never the
# lines). Any non-zero count must be resolved (value moved to an env file) before a copy goes
# into the repo. Nothing is sent anywhere.
# Env (tests only): HUB_CAPTURE_ROOT prefixes the host paths (/usr/local/bin, /etc) with a fake tree.
set -uo pipefail
R=${HUB_CAPTURE_ROOT:-}
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d "/tmp/hub-capture-$(date +%Y%m%dT%H%M%S).XXXX"); else mkdir -p "$OUT"; fi
chmod 700 "$OUT"; umask 077
SUDO="sudo -n"; [ "$(id -u)" = 0 ] && SUDO=""
note() { echo "$*" | tee -a "$OUT/NOTES.txt"; }
grab() {  # grab SRC NAME [root]: copy only if readable (no partial files are left behind)
  local src=$1 name=$2 s=""
  [ "${3:-}" = root ] && s=$SUDO
  if $s test -f "$src" && $s test -r "$src"; then $s cat "$src" > "$OUT/$name"; note "copied: $src -> $name"
  else note "missing or unreadable (root files need sudo -n): $src"; fi
}
note "hub capture (read-only) on $(hostname) at $(date -Is) by $(id -un)"
grab "$R/usr/local/bin/boot.sh" boot.sh root
mkdir -p "$OUT/caddy"
while IFS= read -r f; do
  [ -n "$f" ] && grab "$f" "caddy/$(basename "$f")" root
done < <($SUDO find "$R/etc/caddy" -maxdepth 1 -type f 2>/dev/null | LC_ALL=C sort)
if c=$($SUDO crontab -l -u root 2>/dev/null); then printf '%s\n' "$c" > "$OUT/cron.root"; note "copied: root crontab -> cron.root"
else note "root crontab unreadable (needs sudo -n) or empty"; fi
if c=$(crontab -l 2>/dev/null); then printf '%s\n' "$c" > "$OUT/cron.pi"; note "copied: $(id -un) crontab -> cron.pi"
else note "no crontab for $(id -un)"; fi
for u in caddy caddy-api; do
  if c=$(systemctl cat "$u.service" 2>/dev/null); then printf '%s\n' "$c" > "$OUT/$u.service.cat"; note "copied: systemctl cat $u.service"
  else note "no unit: $u.service"; fi
  echo "$u.service enabled=$(systemctl is-enabled "$u.service" 2>/dev/null) active=$(systemctl is-active "$u.service" 2>/dev/null)" >> "$OUT/units-state.txt"
done
grab "$HOME/.config/systemd/user/graphify-serve.service" graphify-serve.service
echo "graphify-serve.service enabled=$(systemctl --user is-enabled graphify-serve.service 2>/dev/null) active=$(systemctl --user is-active graphify-serve.service 2>/dev/null)" >> "$OUT/units-state.txt"
mkdir -p "$OUT/kit-watch"
grab "$HOME/kit-watch/kit-watch.py" kit-watch/kit-watch.py
grab "$HOME/kit-watch/mail-watch.py" kit-watch/mail-watch.py
grab "$R/etc/cron.weekly/renew-tailscale-cert" renew-tailscale-cert root
if ls -l "$R/etc/cron.d" > "$OUT/cron.d-names.txt" 2>/dev/null; then note "listed (names only): /etc/cron.d"; fi
ss -ltn 2>/dev/null | awk 'NR==1 || /:(80|443|2019|8083|8081) /' > "$OUT/listen-ports.txt"
# shellcheck disable=SC2094  # SHA256SUMS is excluded from the list it is written from
(cd "$OUT" && find . -type f ! -name SHA256SUMS -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > SHA256SUMS)
note "secret-pattern scan (counts only; any non-zero count must be fixed before a repo copy):"
PAT='(token|secret|passw|api[_-]?key|bearer|authorization|basic_?auth|BEGIN [A-Z ]*PRIVATE|ghp_|github_pat_|tskey-|sk-)'
(cd "$OUT" && find . -type f ! -name NOTES.txt ! -name SHA256SUMS | LC_ALL=C sort | while read -r f; do
  n=$(grep -ciE "$PAT" "$f" || true); note "  $f: $n"; done)
note "done: $OUT (mode 700). Review, then copy what belongs in hub/ into a PR. Leave this folder in /tmp or quarantine it with mv; nothing here was changed on the host."
