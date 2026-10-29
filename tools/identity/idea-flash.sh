#!/usr/bin/env bash
# idea-flash.sh - Stage 2 (idea#322): write a release image to a card and personalise it with an identity file.
#   idea-flash.sh --image IMG(.img|.img.xz) --device /dev/sdX --identity NAME|FILE --yes
#   idea-flash.sh --boot DIR --identity NAME|FILE          (identity only, onto an already-written, mounted boot partition)
# Identity: identity-lib.sh format, kept in ~/.config/idea-identities/ (0600). A NEW identity (idea-identity.sh new)
# gives a new device; a SAVED one gives an exact twin / replacement of the device it belongs to.
# Writes to the FAT boot partition (extends the idea#208 time-zone pattern, same validation as set-card-timezone.sh):
#   idea-timezone.txt   zone, applied at every boot (idea-timezone.service)
#   idea-home.txt       home Engine (idea#203), empty for HOME_MODE=none (always empty for an engine identity)
#   idea-hostname.txt   device name; idea-firstboot sets it and deletes the file
#   idea-secrets/tailscale-authkey  copied from TAILSCALE_KEY_REF (if set); wiped by idea-secrets-apply on first boot
#   idea-identity.txt   non-secret record: name, type, zone, home, image + sha256, flashed_at (UTC)
# Client and Engine cards: client identity needs idea-client-*.img(.xz), engine identity needs idea-engine-*.img(.xz);
# a type/image mismatch is refused. A router identity is refused here (router: tools/router-image/idea-router-flash, key via IDEA_FLEET_KEY).
# Never prints the key. Exit: 0 ok, 1 refused/invalid, 2 usage, 3 write failed.
# Test hooks: IDEA_FLASH_ALLOW_FILE=1 (regular file as --device), IDEA_FLASH_MOUNT / IDEA_FLASH_UMOUNT commands.
set -euo pipefail
umask 077
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(cd "$HERE/../.." && pwd); . "$HERE/identity-lib.sh"
TZSET="$REPO/tools/client-image/set-card-timezone.sh"
IMG=""; DEV=""; BOOT=""; IDENT=""; YES=0
while [ $# -gt 0 ]; do case "$1" in
  --image) IMG=$2; shift 2;; --device) DEV=$2; shift 2;; --boot) BOOT=$2; shift 2;; --identity) IDENT=$2; shift 2;;
  --yes) YES=1; shift;; -h|--help) sed -n 2,18p "$0"; exit 0;; *) echo "unknown arg $1" >&2; exit 2;; esac; done
[ -n "$IDENT" ] || { echo "--identity NAME|FILE required" >&2; exit 2; }
{ [ -n "$BOOT" ] && [ -z "$DEV$IMG" ]; } || { [ -z "$BOOT" ] && [ -n "$DEV" ] && [ -n "$IMG" ]; } || { echo "give --boot DIR, or --image + --device" >&2; exit 2; }
id_load "$(id_resolve "$IDENT")" || exit 1
case "$ID_TYPE" in client|engine) ;; *) echo "identity $ID_NAME is a $ID_TYPE; use tools/router-image/idea-router-flash for routers" >&2; exit 1;; esac
"$TZSET" --check "$ID_TIMEZONE" --zoneinfo "$ID_ZONEINFO" || exit 1
SHA=-
write_identity(){ local b=$1
  [ -f "$b/config.txt" ] || { echo "$b does not look like a Pi boot partition (no config.txt)" >&2; return 1; }
  "$TZSET" --timezone "$ID_TIMEZONE" --boot "$b" --zoneinfo "$ID_ZONEINFO" >/dev/null
  if [ "$ID_TYPE" = engine ] || [ "$ID_HOME" = none ]; then : > "$b/idea-home.txt"; else printf '%s\n' "${ID_HOME%.local}" > "$b/idea-home.txt"; fi
  printf '%s\n' "$ID_NAME" > "$b/idea-hostname.txt"
  if [ "$ID_KEYREF" != none ]; then mkdir -p "$b/idea-secrets"; cp "$ID_KEYREF" "$b/idea-secrets/tailscale-authkey"; k="set"; else k="none"; fi
  printf 'name=%s\ntype=%s\ntimezone=%s\nhome=%s\ntailscale_key=%s\nimage=%s\nimage_sha256=%s\nflashed_at=%s\n' "$ID_NAME" "$ID_TYPE" \
    "$ID_TIMEZONE" "$ID_HOME" "$k" "$(basename "${IMG:--}")" "$SHA" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$b/idea-identity.txt"
  sync; echo "identity written: $ID_NAME (zone $ID_TIMEZONE, home $ID_HOME, tailscale key $k)"; }
if [ -n "$BOOT" ]; then [ -d "$BOOT" ] || { echo "no such dir: $BOOT" >&2; exit 2; }; write_identity "$BOOT" || exit 1; exit 0; fi
# --- full flash ---
[ -f "$IMG" ] || { echo "no image: $IMG" >&2; exit 2; }
case "$(basename "$IMG")" in "idea-$ID_TYPE-"*.img|"idea-$ID_TYPE-"*.img.xz) ;; *) echo "not an idea-$ID_TYPE-*.img(.xz) image for $ID_TYPE identity $ID_NAME: $IMG" >&2; exit 1;; esac
case "$(basename "$IMG")" in *-dev*) echo "refusing a dev-stamped image for a device" >&2; exit 1;; esac
if [ -f "$IMG.sha256" ]; then (cd "$(dirname "$IMG")" && sha256sum -c --quiet "$(basename "$IMG").sha256") || { echo "image sha256 mismatch" >&2; exit 1; }; fi
SHA=$(sha256sum "$IMG" | cut -d' ' -f1)
if [ "${IDEA_FLASH_ALLOW_FILE:-0}" = 1 ] && [ -f "$DEV" ]; then :
else
  [ -b "$DEV" ] || { echo "not a block device: $DEV" >&2; exit 1; }
  [ "$(lsblk -dno TYPE "$DEV")" = disk ] || { echo "$DEV is not a whole disk" >&2; exit 1; }
  [ "$(lsblk -dno RM "$DEV" | tr -d ' ')" = 1 ] || [ "$(lsblk -dno TRAN "$DEV")" = usb ] || { echo "$DEV is not removable/USB; refusing" >&2; exit 1; }
  lsblk -nro MOUNTPOINT "$DEV" | grep -q . && { echo "$DEV (or a partition) is mounted; unmount first" >&2; exit 1; }
  rootdev=$(lsblk -no PKNAME "$(findmnt -no SOURCE /)" 2>/dev/null || true); [ "/dev/$rootdev" != "$DEV" ] || { echo "$DEV holds / ; refusing" >&2; exit 1; }
fi
[ "$YES" = 1 ] || { echo "this ERASES $DEV; re-run with --yes" >&2; exit 1; }
echo "writing $(basename "$IMG") -> $DEV"
case "$IMG" in *.xz) xz -dc -T0 "$IMG";; *) cat "$IMG";; esac | dd of="$DEV" bs=4M conv=fsync,notrunc status=none || { echo "write failed" >&2; exit 3; }
MNT=$(mktemp -d); trap 'eval "${IDEA_FLASH_UMOUNT:-sudo umount \"\$MNT\"}" 2>/dev/null || true; rmdir "$MNT" 2>/dev/null || true' EXIT
if [ -n "${IDEA_FLASH_MOUNT:-}" ]; then eval "$IDEA_FLASH_MOUNT"
else sudo partprobe "$DEV" 2>/dev/null || true; sleep 2; P1="${DEV}1"; [ -b "$P1" ] || P1="${DEV}p1"; sudo mount -o uid="$(id -u)",umask=077 "$P1" "$MNT"; fi
write_identity "$MNT" || exit 3
echo "flashed $DEV: $(basename "$IMG") sha256 $SHA, identity $ID_NAME"
