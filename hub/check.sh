#!/usr/bin/env bash
# shellcheck disable=SC2329  # helpers and check_<service> are called indirectly via "check_${SVC//-/_}"
# hub/check.sh — READ-ONLY drift check for the hub Pi `idea` (idea#483, proposal #408).
#
# Compares what is deployed on the hub against this checkout and reports drift.
# It only reads: it never writes, copies, deletes, enables, starts or restarts anything,
# and never edits units or cron. Env files are compared by key NAME only; values are
# never read into the output.
#
# Usage: hub/check.sh [--root DIR] [--home DIR] [--service NAME]... [--no-state] [--list] [-h]
#   --root DIR      prefix for every deployed path (tests point this at a fake tree). Default: none.
#   --home DIR      the deployed user's home, before --root is applied. Default: $HOME.
#   --service NAME  check only NAME (repeatable). Default: every service in SERVICES.
#   --no-state      skip systemd enabled/active checks (file checks only).
#   --list          print the known services and exit.
# Env: HUB_CHECK_SYSTEMCTL  systemctl command to use (default: systemctl). Tests set a stub.
#
# Exit: 0 = no drift, 1 = drift found, 2 = usage error.
#
# Adding a service (kit-watch, mail-watch, graphify, host, ...): write a check_<name> function
# using the helpers below (same_file, expect_link, expect_mode, env_keys, unit_state,
# no_extra_files) and add <name> to SERVICES.
set -u

SERVICES="telegram-relay"

HUB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=""
HOME_D=${HOME:-/home/pi}
STATE=1
ONLY=()
SYSTEMCTL=${HUB_CHECK_SYSTEMCTL:-systemctl}

usage() { sed -n '3,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || { usage >&2; exit 2; }; ROOT=${2%/}; shift 2 ;;
    --home) [ $# -ge 2 ] || { usage >&2; exit 2; }; HOME_D=${2%/}; shift 2 ;;
    --service) [ $# -ge 2 ] || { usage >&2; exit 2; }; ONLY+=("$2"); shift 2 ;;
    --no-state) STATE=0; shift ;;
    --list) for s in $SERVICES; do echo "$s"; done; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done
if [ ${#ONLY[@]} -gt 0 ]; then
  for s in "${ONLY[@]}"; do
    case " $SERVICES " in *" $s "*) ;; *) echo "unknown service: $s (try --list)" >&2; exit 2 ;; esac
  done
  SERVICES="${ONLY[*]}"
fi

DRIFT=0
SVC=""
ok()    { echo "ok    [$SVC] $*"; }
drift() { echo "DRIFT [$SVC] $*"; DRIFT=1; }
# Deployed path: --root prefix + path. Pass paths as the hub sees them (e.g. "$HOME_D/tg-relay").
dp() { printf '%s%s' "$ROOT" "$1"; }

# same_file REPO_FILE DEPLOYED_PATH: byte-for-byte compare (cmp only reads).
same_file() {
  local src=$1 dst; dst=$(dp "$2")
  if [ ! -e "$dst" ]; then drift "missing: $2 (repo: ${src#"$HUB_DIR"/})"
  elif [ ! -f "$dst" ]; then drift "not a regular file: $2"
  elif cmp -s "$src" "$dst"; then ok "same: $2"
  else drift "differs from repo: $2 (repo: ${src#"$HUB_DIR"/})"
  fi
}

# expect_link LINK TARGET: LINK is a symlink to TARGET (with or without the --root prefix).
expect_link() {
  local l; l=$(dp "$1")
  if [ ! -L "$l" ]; then drift "not a symlink: $1 (want -> $2)"; return; fi
  local t; t=$(readlink "$l")
  if [ "$t" = "$2" ] || [ "$t" = "$(dp "$2")" ]; then ok "link: $1 -> $2"
  else drift "link $1 -> $t (want $2)"
  fi
}

# expect_mode PATH MODE: octal permission bits, e.g. 600.
expect_mode() {
  local p; p=$(dp "$1")
  [ -e "$p" ] || { drift "missing: $1 (want mode $2)"; return; }
  local m; m=$(stat -c %a "$p")
  if [ "$m" = "$2" ]; then ok "mode $2: $1"; else drift "mode $m (want $2): $1"; fi
}

# key_names FILE: KEY names from KEY=... lines, sorted. Prints names only, never values.
key_names() { sed -n 's/^[[:space:]]*\(export[[:space:]]\{1,\}\)\{0,1\}\([A-Za-z_][A-Za-z0-9_]*\)[[:space:]]*=.*/\2/p' "$1" | LC_ALL=C sort -u; }
# optional_names FILE: names from commented "# KEY=" lines (optional keys).
optional_names() { sed -n 's/^#[[:space:]]*\([A-Z_][A-Z0-9_]*\)=.*/\1/p' "$1" | LC_ALL=C sort -u; }

# env_keys EXAMPLE DEPLOYED_ENV: same key NAMES (required = uncommented in EXAMPLE,
# optional = "# KEY=" in EXAMPLE). Values are never printed.
env_keys() {
  local ex=$1 env; env=$(dp "$2")
  [ -e "$env" ] || { drift "missing env file: $2"; return; }
  [ -r "$env" ] || { drift "env file not readable by $(id -un): $2"; return; }
  local have want opt k bad=0
  have=$(key_names "$env"); want=$(key_names "$ex"); opt=$(optional_names "$ex")
  for k in $want; do
    grep -qx "$k" <<<"$have" || { drift "env key missing: $k in $2"; bad=1; }
  done
  for k in $have; do
    grep -qx "$k" <<<"$want" || grep -qx "$k" <<<"$opt" || { drift "env key not in ${ex#"$HUB_DIR"/}: $k in $2"; bad=1; }
  done
  [ "$bad" = 1 ] || ok "env key names match ${ex#"$HUB_DIR"/}: $2"
}

# unit_state UNIT: systemd --user unit is enabled and active (read-only queries).
unit_state() {
  [ "$STATE" = 1 ] || { echo "skip  [$SVC] unit state (--no-state): $1"; return; }
  local e a
  e=$($SYSTEMCTL --user is-enabled "$1" 2>/dev/null); e=${e:-unknown}
  a=$($SYSTEMCTL --user is-active "$1" 2>/dev/null); a=${a:-unknown}
  if [ "$e" = enabled ]; then ok "unit enabled: $1"; else drift "unit $1 is-enabled=$e (want enabled)"; fi
  if [ "$a" = active ]; then ok "unit active: $1"; else drift "unit $1 is-active=$a (want active)"; fi
}

# no_extra_files DIR NAME...: DIR (top level) holds only the listed names.
no_extra_files() {
  local d=$1; shift
  local p; p=$(dp "$d")
  [ -d "$p" ] || { drift "missing dir: $d"; return; }
  local f n bad=0
  for f in "$p"/* "$p"/.[!.]*; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    n=${f##*/}
    case " $* " in *" $n "*) ;; *) drift "unexpected file in $d: $n"; bad=1 ;; esac
  done
  [ "$bad" = 1 ] || ok "no unexpected files: $d"
}

# ---------- services ----------

# Telegram relay: matches what hub/services/telegram-relay/install.sh deploys.
check_telegram_relay() {
  local S="$HUB_DIR/services/telegram-relay" D="$HOME_D/tg-relay" C="$HOME_D/.config/tg-relay"
  same_file "$S/tg_relay.py" "$D/tg_relay.py"
  same_file "$S/tg-send" "$D/tg-send"
  same_file "$S/tg-relay.service" "$HOME_D/.config/systemd/user/tg-relay.service"
  expect_link "$HOME_D/.local/bin/tg-send" "$D/tg-send"
  expect_mode "$D" 700
  expect_mode "$C" 700
  expect_mode "$C/env" 600
  env_keys "$S/.env.example" "$C/env"
  # Deployed code plus the relay's own runtime state (state.json, its lock/tmp, logs, files/).
  no_extra_files "$D" tg_relay.py tg-send state.json state.json.lock state.json.tmp relay.log relay.log.1 files __pycache__
  unit_state tg-relay.service
}

echo "hub drift check (read-only): repo=$HUB_DIR home=$HOME_D${ROOT:+ root=$ROOT}"
for SVC in $SERVICES; do
  "check_${SVC//-/_}"
done
SVC=summary
if [ $DRIFT = 0 ]; then echo "no drift"; exit 0; fi
echo "drift found"; exit 1
