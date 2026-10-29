#!/usr/bin/env bash
# idea-identity.sh - manage IDEA device identity files on the bot computer (idea#322). Format: identity-lib.sh.
#   idea-identity.sh new --name N --timezone Area/City [--type client|router|engine] [--home ENGINE|none] [--tailscale-key-ref PATH|none]
#   idea-identity.sh check NAME|FILE      validate (exit 0 = ok)
#   idea-identity.sh show NAME|FILE       print the fields; the key is shown only as its reference ("set"/"none")
#   idea-identity.sh list
#   (--type engine needs --home none, the default)
# Files: ${IDEA_IDENTITY_DIR:-~/.config/idea-identities}/<name>.identity, dir 0700, file 0600, never overwritten.
# Never prints a Tailscale key. Exit: 0 ok, 1 invalid, 2 usage.
set -euo pipefail
umask 077
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/identity-lib.sh"
cmd=${1:-}; shift || true
case "$cmd" in
  new) ID_TYPE=client; ID_NAME=""; ID_TIMEZONE=""; ID_HOME=none; ID_KEYREF=none
    while [ $# -gt 0 ]; do case "$1" in --name) ID_NAME=$2; shift 2;; --timezone) ID_TIMEZONE=$2; shift 2;; --type) ID_TYPE=$2; shift 2;;
      --home) ID_HOME=$2; shift 2;; --tailscale-key-ref) ID_KEYREF=$2; shift 2;; *) echo "unknown arg $1" >&2; exit 2;; esac; done
    [ -n "$ID_NAME" ] && [ -n "$ID_TIMEZONE" ] || { echo "new needs --name and --timezone" >&2; exit 2; }
    case "$ID_KEYREF" in tskey-*) echo "refusing: give the PATH of a 0600 key file, not the key" >&2; exit 1;; esac
    id_check_fields || exit 1
    install -d -m 700 "$IDENTITY_DIR"; id_in_repo "$IDENTITY_DIR/." && { echo "refusing: $IDENTITY_DIR is inside a git repository" >&2; exit 1; }
    F="$IDENTITY_DIR/$ID_NAME.identity"; [ ! -e "$F" ] || { echo "identity exists, not overwriting: $F" >&2; exit 1; }
    printf 'IDEA_IDENTITY=1\nTYPE=%s\nNAME=%s\nTIMEZONE=%s\nHOME_MODE=%s\nTAILSCALE_KEY_REF=%s\n' \
      "$ID_TYPE" "$ID_NAME" "$ID_TIMEZONE" "$ID_HOME" "$ID_KEYREF" > "$F.tmp"; chmod 600 "$F.tmp"; mv "$F.tmp" "$F"
    echo "identity: $F";;
  check) [ $# = 1 ] || exit 2; id_load "$(id_resolve "$1")" && echo "identity ok: $ID_NAME ($ID_TYPE)";;
  show) [ $# = 1 ] || exit 2; id_load "$(id_resolve "$1")" || exit 1
    k=none; [ "$ID_KEYREF" = none ] || k="set ($ID_KEYREF)"
    printf 'type=%s\nname=%s\ntimezone=%s\nhome=%s\ntailscale_key=%s\n' "$ID_TYPE" "$ID_NAME" "$ID_TIMEZONE" "$ID_HOME" "$k";;
  list) [ -d "$IDENTITY_DIR" ] || exit 0; for f in "$IDENTITY_DIR"/*.identity; do [ -e "$f" ] && basename "$f" .identity; done; true;;
  *) sed -n 2,9p "$0"; exit 2;;
esac
