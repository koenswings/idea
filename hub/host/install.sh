#!/usr/bin/env bash
# hub/host/install.sh: host step for the hub Pi "idea" (idea#486): root crontab, pi crontab,
# /usr/local/bin/boot.sh and /etc/caddy/Caddyfile from hub/host/. hub/bootstrap.sh calls it.
#
# Default is a PLAN: it only reads and prints what --apply would change. --apply needs root
# (sudo) and Koen's OK for that deploy (a new 05:00 reboot or a Caddy change in particular).
#
# Usage: sudo hub/host/install.sh [--apply] [--allow-remove] [--pi-user NAME] [--root DIR]
#   --apply         make the changes (backups first). Without it nothing is written.
#   --allow-remove  allow a crontab install that would drop ACTIVE lines the repo file lacks.
#                   Without it such an install is refused, so a live job is never lost by accident.
#   --pi-user NAME  the hub user whose crontab is cron.pi (default: pi).
#   --root DIR      prefix for every host path (tests use a fake tree; root not needed then).
# Env (tests): HUB_HOST_CRONTAB, HUB_HOST_SYSTEMCTL, HUB_HOST_CADDY (commands; defaults
#   crontab, systemctl, caddy).
#
# Safe to re-run. Never replaces a live file with an empty, placeholder or unvalidated copy:
#  - a repo file that still has a "HUB-PLACEHOLDER" line is never deployed (skipped, reported);
#  - a crontab whose repo copy has no active line is never installed for root;
#  - the Caddyfile is installed only after "caddy validate" passes, then caddy is reloaded
#    (not restarted); caddy-api is never touched;
#  - every replaced file or crontab is first copied to <root>/var/backups/idea-hub/host/<stamp>/.
# Exit: 0 = done / nothing to do, 1 = refused or failed, 2 = usage error.
# shellcheck disable=SC2001  # sed prefixes multi-line lists
set -euo pipefail
H=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
APPLY=0; ALLOW_REMOVE=0; ROOT=""; PIU=pi
CRONTAB=${HUB_HOST_CRONTAB:-crontab}; SYSTEMCTL=${HUB_HOST_SYSTEMCTL:-systemctl}; CADDY=${HUB_HOST_CADDY:-caddy}
usage() { sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --allow-remove) ALLOW_REMOVE=1; shift ;;
    --pi-user) [ $# -ge 2 ] || { usage >&2; exit 2; }; PIU=$2; shift 2 ;;
    --root) [ $# -ge 2 ] || { usage >&2; exit 2; }; ROOT=${2%/}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done
if [ "$APPLY" = 1 ] && [ -z "$ROOT" ] && [ "$(id -u)" != 0 ]; then
  echo "--apply on the real host needs root: sudo $0 --apply" >&2; exit 2
fi
STAMP=$(date +%Y%m%dT%H%M%S)
BK=$ROOT/var/backups/idea-hub/host/$STAMP
RC=0
say() { echo "[host] $*"; }
mode() { [ "$APPLY" = 1 ] && echo "apply" || echo "plan"; }
backup() {  # backup NAME < content
  mkdir -p "$BK"; chmod 700 "$BK"; (umask 077; cat > "$BK/$1")
}
placeholder() { grep -q 'HUB-PLACEHOLDER' "$1"; }
active() { grep -vE '^[[:space:]]*(#|$)' || true; }

# ---- files ----
# put_file REPO DEST MODE [VALIDATE_CMD...]: replace DEST with REPO if different (backup first).
put_file() {
  local src=$1 p=$2 m=$3; local dst=$ROOT$p; shift 3
  if placeholder "$src"; then say "SKIP $p: repo copy ${src#"$H"/} is still a placeholder (capture it from idea first)"; return 0; fi
  if [ ! -s "$src" ]; then say "REFUSE $p: repo copy is empty"; RC=1; return 0; fi
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then say "ok   $p matches the repo"; return 0; fi
  if [ $# -gt 0 ]; then
    if ! "$@" >/dev/null 2>&1; then say "REFUSE $p: validation failed: $*"; RC=1; return 0; fi
    say "valid ${src#"$H"/} ($1 validate)"
  fi
  # Contents are never printed (a live file may hold values that must not reach a log): sizes + sha256 only.
  if [ -f "$dst" ]; then say "$(mode) $p differs from the repo: live $(wc -c < "$dst") B sha256 $(sha256sum < "$dst" | cut -c1-12), repo $(wc -c < "$src") B sha256 $(sha256sum < "$src" | cut -c1-12)"
  else say "$(mode) $p is missing; would install it"; fi
  [ "$APPLY" = 1 ] || return 0
  [ -f "$dst" ] && backup "$(basename "$p")" < "$dst"
  mkdir -p "$(dirname "$dst")"
  local t; t=$(mktemp "$(dirname "$dst")/.hub-new.XXXXXX"); cp "$src" "$t"; chmod "$m" "$t"; mv "$t" "$dst"
  say "installed $p (backup of the old file in $BK)"
  CHANGED+=("$p")
}

# ---- crontabs ----
# put_cron USER REPO_FILE: install REPO_FILE as USER's crontab if the ACTIVE lines differ.
put_cron() {
  local u=$1 src=$2 live want have missing extra
  if ! live=$($CRONTAB -l -u "$u" 2>/dev/null); then live=""; fi
  want=$(active < "$src"); have=$(active <<<"$live")
  if [ "$want" = "$have" ]; then say "ok   crontab $u: active lines match ${src#"$H"/}"; return 0; fi
  if [ "$u" = root ] && [ -z "$want" ]; then say "REFUSE crontab root: ${src#"$H"/} has no active line"; RC=1; return 0; fi
  missing=$(comm -23 <(LC_ALL=C sort <<<"$want") <(LC_ALL=C sort <<<"$have") | sed '/^$/d')
  extra=$(comm -13 <(LC_ALL=C sort <<<"$want") <(LC_ALL=C sort <<<"$have") | sed '/^$/d')
  [ -z "$missing" ] || { say "$(mode) crontab $u: would ADD:"; sed 's/^/    + /' <<<"$missing"; }
  if [ -n "$extra" ]; then
    say "$(mode) crontab $u: live has active lines the repo lacks:"; sed 's/^/    - /' <<<"$extra"
    if grep -qE '/kit-watch/(kit|mail)-watch\.py' <<<"$extra"; then
      say "REFUSE crontab $u: kit-watch/mail-watch lines are removed by hub/services/kit-watch/install.sh --remove-cron (as $u), not here"
      RC=1; return 0
    fi
    if [ "$ALLOW_REMOVE" != 1 ]; then say "REFUSE crontab $u: would remove the lines above; re-run with --allow-remove if that is intended"; RC=1; return 0; fi
  fi
  [ "$APPLY" = 1 ] || return 0
  printf '%s\n' "$live" | backup "crontab.$u"
  $CRONTAB -u "$u" "$src"
  say "installed crontab $u (backup: $BK/crontab.$u)"
}

CHANGED=()
say "mode: $(mode)${ROOT:+ root=$ROOT}; repo: $H"
put_file "$H/boot.sh" /usr/local/bin/boot.sh 755
put_file "$H/caddy/Caddyfile" /etc/caddy/Caddyfile 644 "$CADDY" validate --adapter caddyfile --config "$H/caddy/Caddyfile"
put_cron root "$H/cron.root"
put_cron "$PIU" "$H/cron.pi"
if [ "$APPLY" = 1 ] && printf '%s\n' "${CHANGED[@]+"${CHANGED[@]}"}" | grep -qx /etc/caddy/Caddyfile; then
  if $SYSTEMCTL reload caddy; then say "reloaded caddy (caddy-api not touched)"
  else say "caddy reload FAILED: restore with: cp $BK/Caddyfile /etc/caddy/Caddyfile && systemctl reload caddy"; RC=1; fi
fi
[ "$APPLY" = 1 ] || say "plan only: nothing was written (use --apply, as root, with Koen's OK)"
exit $RC
