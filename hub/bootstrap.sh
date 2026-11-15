#!/usr/bin/env bash
# hub/bootstrap.sh: rebuild the hub services on the hub Pi "idea" from this checkout (idea#487).
# It only calls each service's install.sh plus the host step (hub/host/install.sh). It never
# touches the Engine, pm2, App/Backup Disks or Docker. Safe to re-run.
#
# Usage:
#   hub/bootstrap.sh                 PLAN (default, read-only): print the steps and blockers
#   hub/bootstrap.sh --apply [--spare NAME]
#                                    run them, as pi. Needs Koen's OK on production idea
#                                    (and, until it is done, the #375 item 9 gate).
#                                    --spare NAME: allow a spare Pi whose hostname is NAME
#                                    (only when Steve has agreed that spare).
#   hub/bootstrap.sh --stage --home DIR --root DIR
#                                    offline proof on the box: every installer in --stage mode
#                                    into a scratch HOME, host step as a PLAN against a scratch
#                                    root. No systemctl, loginctl, crontab or sudo calls.
#
# --apply refuses (before changing anything) unless: user is pi (never root); hostname is idea
# (or the agreed --spare); the checkout is clean and origin is plain https with no credentials;
# boot.sh and the Caddyfile are captured (no HUB-PLACEHOLDER); ~/graphify-out exists; both env
# files (~/.config/kit-watch/env, ~/.config/tg-relay/env) exist, non-empty, restored privately.
# It enables linger for pi if needed (so user units start at boot), installs kit-watch,
# telegram-relay and graphify, then runs the host step with --apply. If the old kit-watch cron
# lines are still in the pi crontab, the host step is skipped with a note: confirm a good
# kit-watch.service run, run "services/kit-watch/install.sh --remove-cron", then re-run this.
# Finally it runs hub/check.sh (read-only) and prints its verdict.
# Env (tests): HUB_BOOTSTRAP_SUDO (default "sudo -n").
set -euo pipefail
H=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MODE=plan; DEST=""; ROOT=""; SPARE=""
SUDO=${HUB_BOOTSTRAP_SUDO-sudo -n}
usage() { sed -n '2,27p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) MODE=plan; shift ;;
    --apply) MODE=apply; shift ;;
    --stage) MODE=stage; shift ;;
    --home) [ $# -ge 2 ] || { usage >&2; exit 2; }; DEST=$2; shift 2 ;;
    --root) [ $# -ge 2 ] || { usage >&2; exit 2; }; ROOT=$2; shift 2 ;;
    --spare) [ $# -ge 2 ] || { usage >&2; exit 2; }; SPARE=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done
SERVICES=(kit-watch telegram-relay graphify)
for s in "${SERVICES[@]}"; do
  [ -f "$H/services/$s/install.sh" ] || { echo "missing installer: services/$s/install.sh" >&2; exit 1; }
done
[ -f "$H/host/install.sh" ] || { echo "missing host step: host/install.sh" >&2; exit 1; }
say() { echo "[bootstrap] $*"; }
placeholders() { grep -l HUB-PLACEHOLDER "$H/host/boot.sh" "$H/host/caddy/Caddyfile" 2>/dev/null | sed "s|^$H/||" || true; }

if [ "$MODE" = plan ]; then
  say "PLAN only: nothing is changed. --apply would run, in order:"
  say "  0. checks: user pi, hostname idea (or --spare), clean checkout, plain-https origin, env files restored, ~/graphify-out present"
  say "  1. $SUDO loginctl enable-linger pi   (only if linger is off)"
  for s in "${SERVICES[@]}"; do say "  2. sh hub/services/$s/install.sh"; done
  say "  3. $SUDO hub/host/install.sh --apply   (skipped while the old kit-watch cron lines remain)"
  say "  4. hub/check.sh (read-only)"
  p=$(placeholders); [ -z "$p" ] || say "BLOCKER for --apply: not captured yet: $(echo "$p" | tr '\n' ' ')(see hub/host/README.md)"
  say "Production idea: only with Koen's OK; the migration waits for #375 item 9 (the personal app's Backup Disk)."
  exit 0
fi

if [ "$MODE" = stage ]; then
  [ -n "$DEST" ] && [ -n "$ROOT" ] || { echo "--stage needs --home DIR and --root DIR (scratch paths)" >&2; exit 2; }
  for p in "$DEST" "$ROOT"; do
    case "$p" in /*) ;; *) echo "stage paths must be absolute: $p" >&2; exit 2 ;; esac
    [ ! -L "$p" ] || { echo "stage paths must not be symlinks: $p" >&2; exit 2; }
    r=$(realpath -m "$p")
    case "$r" in /|/home|/home/*/|/root|/etc|/usr|/var|/workspace|"$(realpath -m "$HOME")") echo "refusing a real path as stage target: $r" >&2; exit 2 ;; esac
  done
  mkdir -p "$DEST" "$ROOT"
  for s in "${SERVICES[@]}"; do say "stage $s"; HOME=$DEST sh "$H/services/$s/install.sh" --stage; done
  say "host step (PLAN against $ROOT; stub crontab/systemctl/caddy, nothing written)"
  HUB_HOST_CRONTAB=true HUB_HOST_SYSTEMCTL=false HUB_HOST_CADDY=false bash "$H/host/install.sh" --root "$ROOT" || true
  say "stage done: files under $DEST only. Not a deploy and not a reboot proof."
  exit 0
fi

# ---- --apply: every check first, before anything changes ----
fail() { echo "[bootstrap] REFUSE: $*" >&2; exit 1; }
[ -z "$DEST$ROOT" ] || { echo "--home/--root are only for --stage" >&2; exit 2; }
[ "$(id -u)" != 0 ] || fail "run as pi, never root (user units and pm2 stay as pi)"
[ "$(id -un)" = pi ] || fail "run as pi (current user: $(id -un))"
HN=$(hostname -s)
if [ -n "$SPARE" ]; then [ "$HN" = "$SPARE" ] || fail "hostname is $HN, not the agreed spare $SPARE"
else [ "$HN" = idea ] || fail "hostname is $HN; only idea (or an agreed --spare NAME) is a target"; fi
REPO=$(cd "$H/.." && pwd)
[ -z "$(git -C "$REPO" status --porcelain)" ] || fail "checkout $REPO has local changes; changes reach the hub only via merged PRs"
URL=$(git -C "$REPO" remote get-url origin 2>/dev/null || true)
[[ "$URL" =~ ^https://github\.com/koenswings/idea(\.git)?$ ]] || fail "origin must be plain https://github.com/koenswings/idea.git (no credentials); got a different URL"
p=$(placeholders); [ -z "$p" ] || fail "not captured yet: $(echo "$p" | tr '\n' ' ')(hub/host/capture.sh, then a PR)"
[ -d "$HOME/graphify-out" ] || fail "$HOME/graphify-out is missing: restore it first (never rebuilt here)"
for e in kit-watch tg-relay; do
  [ -s "$HOME/.config/$e/env" ] || fail "$HOME/.config/$e/env is missing or empty: restore it privately first (mode 600; see docs/ops/hub-runbook.md)"
done

linger=$(loginctl show-user pi -p Linger --value 2>/dev/null || echo unknown)
if [ "$linger" != yes ]; then say "enabling linger for pi"; $SUDO loginctl enable-linger pi; fi
for s in "${SERVICES[@]}"; do say "install $s"; sh "$H/services/$s/install.sh"; done
if crontab -l 2>/dev/null | grep -vE '^[[:space:]]*#' | grep -qE '/kit-watch/(kit|mail)-watch\.py'; then
  say "host step SKIPPED: the old kit-watch cron lines are still there. Confirm a good run"
  say "  (journalctl --user -u kit-watch.service), then: sh hub/services/kit-watch/install.sh --remove-cron, and re-run bootstrap."
else
  say "host step"; $SUDO bash "$H/host/install.sh" --apply
fi
say "drift check (read-only)"
if "$H/check.sh"; then say "done: no drift"; else say "done, but check.sh reports drift (see above)"; fi
