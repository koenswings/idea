# shellcheck shell=bash
# identity-lib.sh - shared parser/validator for IDEA identity files (idea#322). Sourced, never executed.
# Identity file (one per device; on the bot computer only, ~/.config/idea-identities/<name>.identity, mode 0600):
#   IDEA_IDENTITY=1
#   TYPE=client                      client | router
#   NAME=idea-pc-5b4c                hostname label: [a-z0-9-], 1-63, no leading/trailing '-'
#   TIMEZONE=Africa/Harare           tz database zone (same rule as set-card-timezone.sh, idea#208)
#   HOME_MODE=idea01                 client: home Engine name (idea-home.txt, idea#203) or "none"
#   TAILSCALE_KEY_REF=/home/.../key  PATH of a 0600 file holding the key, or "none". The key itself is never here.
# The file is parsed as plain KEY=VALUE text (never sourced). Unknown keys, a raw tskey-* value, or a bad mode fail.
IDENTITY_DIR="${IDEA_IDENTITY_DIR:-$HOME/.config/idea-identities}"
ID_ZONEINFO="${IDEA_ZONEINFO:-/usr/share/zoneinfo}"
id_err(){ echo "identity: $*" >&2; return 1; }
id_valid_name(){ printf '%s' "$1" | grep -Eqx '[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?'; }
id_valid_tz(){ printf '%s' "$1" | grep -Eqx '[A-Za-z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+){0,2}' && [ -f "$ID_ZONEINFO/$1" ] && head -c 4 "$ID_ZONEINFO/$1" | grep -q '^TZif'; }
id_mode(){ stat -c %a "$1"; }
id_in_repo(){ local top; top=$(git -C "$(dirname "$(realpath "$1")")" rev-parse --show-toplevel 2>/dev/null) && [ -n "$top" ]; }
# id_resolve NAME|PATH -> path
id_resolve(){ case "$1" in */*) echo "$1";; *) echo "$IDENTITY_DIR/$1.identity";; esac; }
# id_load FILE: sets ID_TYPE ID_NAME ID_TIMEZONE ID_HOME ID_KEYREF; validates everything; prints nothing secret
id_load(){
  local f=$1 k v line ver=""; ID_TYPE=""; ID_NAME=""; ID_TIMEZONE=""; ID_HOME=""; ID_KEYREF=""
  [ -f "$f" ] || { id_err "no identity file: $f"; return 1; }
  [ "$(id_mode "$f")" = 600 ] || { id_err "$f must be mode 0600 (is $(id_mode "$f"))"; return 1; }
  id_in_repo "$f" && { id_err "refusing: $f is inside a git repository (identity files never go to GitHub)"; return 1; }
  grep -q 'tskey-' "$f" && { id_err "refusing: $f holds a raw Tailscale key; store it in a 0600 file and set TAILSCALE_KEY_REF"; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}; case "$line" in ''|'#'*) continue;; esac
    [[ "$line" == *=* ]] || { id_err "bad line in $f"; return 1; }
    k=${line%%=*}; v=${line#*=}
    case "$k" in IDEA_IDENTITY) ver=$v;; TYPE) ID_TYPE=$v;; NAME) ID_NAME=$v;; TIMEZONE) ID_TIMEZONE=$v;;
      HOME_MODE) ID_HOME=$v;; TAILSCALE_KEY_REF) ID_KEYREF=$v;; *) id_err "unknown key '$k' in $f"; return 1;; esac
  done < "$f"
  [ "$ver" = 1 ] || { id_err "$f: IDEA_IDENTITY=1 missing"; return 1; }
  id_check_fields
}
id_check_fields(){
  case "$ID_TYPE" in client|router) ;; *) id_err "TYPE must be client or router"; return 1;; esac
  id_valid_name "$ID_NAME" || { id_err "NAME is not a hostname label: '$ID_NAME'"; return 1; }
  id_valid_tz "$ID_TIMEZONE" || { id_err "TIMEZONE is not a tz database zone: '$ID_TIMEZONE'"; return 1; }
  [ "$ID_HOME" = none ] || id_valid_name "${ID_HOME%.local}" || { id_err "HOME_MODE must be an Engine name or none"; return 1; }
  if [ "$ID_KEYREF" != none ]; then
    case "$ID_KEYREF" in /*) ;; *) id_err "TAILSCALE_KEY_REF must be an absolute path or none"; return 1;; esac
    [ -f "$ID_KEYREF" ] || { id_err "Tailscale key file missing: $ID_KEYREF"; return 1; }
    [ "$(id_mode "$ID_KEYREF")" = 600 ] || { id_err "Tailscale key file must be mode 0600"; return 1; }
    id_in_repo "$ID_KEYREF" && { id_err "refusing: Tailscale key file is inside a git repository"; return 1; }
  fi; return 0; }
