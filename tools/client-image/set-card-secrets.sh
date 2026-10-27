#!/usr/bin/env bash
# shellcheck disable=SC1090  # sources a user-supplied config path
# set-card-secrets.sh - flash-time secrets for an IDEA client card (idea#322): the image carries none.
# Usage: set-card-secrets.sh --boot <mounted FAT boot partition> [--wifi-psk-file FILE] [--authorized-keys FILE]
#        default files from ~/.config/idea-client-image/secrets.env (WIFI_PSK_FILE=..., ADMIN_AUTHORIZED_KEYS_FILE=...)
# Writes <boot>/idea-secrets/{wifi-psk,admin_authorized_keys}; idea-firstboot applies them on the first boot and
# removes them from the boot partition. Run right after writing the image, before the first boot (same step as
# set-card-timezone.sh, idea#208). Never prints a secret value. Refuses files inside the git repo and private keys.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null || echo "$HERE")"
BOOT=""; PSKF=""; AKF=""; CONF="${IDEA_SECRETS_CONF:-$HOME/.config/idea-client-image/secrets.env}"
while [ $# -gt 0 ]; do case "$1" in
  --boot) BOOT="$2"; shift 2;; --wifi-psk-file) PSKF="$2"; shift 2;; --authorized-keys) AKF="$2"; shift 2;;
  -h|--help) sed -n '2,8p' "$0"; exit 0;; *) echo "unknown arg $1" >&2; exit 2;; esac; done
if [ -f "$CONF" ] && { [ -z "$PSKF" ] || [ -z "$AKF" ]; }; then
  set +x; . "$CONF"; PSKF="${PSKF:-${WIFI_PSK_FILE:-}}"; AKF="${AKF:-${ADMIN_AUTHORIZED_KEYS_FILE:-}}"; fi
[ -n "$BOOT" ] && [ -d "$BOOT" ] || { echo "--boot <mounted boot partition> required" >&2; exit 2; }
[ -f "$BOOT/config.txt" ] || { echo "$BOOT does not look like a client boot partition (no config.txt)" >&2; exit 2; }
[ -n "$PSKF$AKF" ] || { echo "nothing to write: give --wifi-psk-file and/or --authorized-keys" >&2; exit 2; }
inrepo(){ case "$(realpath "$1")" in "$REPO"/*) return 0;; esac; return 1; }
D="$BOOT/idea-secrets"; mkdir -p "$D"
if [ -n "$PSKF" ]; then
  [ -f "$PSKF" ] || { echo "wifi psk file missing: $PSKF" >&2; exit 3; }; inrepo "$PSKF" && { echo "refusing: psk file is inside the repo" >&2; exit 3; }
  n=$(head -n 1 "$PSKF" | tr -d '\r\n' | wc -c); [ "$n" -ge 8 ] && [ "$n" -le 63 ] || { echo "wifi psk must be 8-63 characters (got $n)" >&2; exit 3; }
  head -n 1 "$PSKF" | tr -d '\r\n' > "$D/wifi-psk"; echo "wrote $D/wifi-psk ($n chars)"; fi
if [ -n "$AKF" ]; then
  [ -f "$AKF" ] || { echo "authorized keys file missing: $AKF" >&2; exit 3; }; inrepo "$AKF" && { echo "refusing: keys file is inside the repo" >&2; exit 3; }
  grep -q 'PRIVATE KEY' "$AKF" && { echo "refusing: $AKF contains a private key" >&2; exit 3; }
  cp "$AKF" "$D/admin_authorized_keys"; echo "wrote $D/admin_authorized_keys ($(grep -c . "$AKF") keys)"; fi
sync
