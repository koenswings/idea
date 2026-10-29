#!/usr/bin/env bash
# shrink-image.sh IMG - shrink partition 2 (ext4 root) of a raw client image to fit MAX_IMAGE_BYTES (idea#202, idea#322).
# Replaces s16's manual shrink to 14 GB: root fs -> used + ROOT_FREE_MB headroom; when that does not fit the cap, the
# root is cut to the cap instead, as long as at least ROOT_FREE_MIN_MB stays free (else exit 1). Partition 2 and the
# file are cut to match. Labels/UUIDs/PARTUUID unchanged; cloud-init growpart+resizefs grows root on first boot.
# Env (defaults from client-image.conf): MAX_IMAGE_BYTES ROOT_FREE_MB ROOT_FREE_MIN_MB. Needs root (losetup).
#   shrink-image.sh --plan MINB BS O2   print WANT blocks + mode (headroom|cap) for the given numbers; no root, no image
set -euo pipefail
export PATH="$PATH:/usr/sbin:/sbin"
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=client-image.conf
[ -n "${MAX_IMAGE_BYTES:-}" ] || . "$HERE/client-image.conf"
: "${ROOT_FREE_MIN_MB:=2048}"
plan() { # MINB BS O2 -> "WANT mode"
  local minb=$1 bs=$2 o2=$3 want capb minw
  want=$(( minb + ROOT_FREE_MB*1024*1024/bs )); capb=$(( (MAX_IMAGE_BYTES - o2) / bs )); minw=$(( minb + ROOT_FREE_MIN_MB*1024*1024/bs ))
  if [ "$want" -le "$capb" ]; then echo "$want headroom"
  elif [ "$minw" -le "$capb" ]; then echo "$capb cap"
  else echo "rootfs needs $minw blocks (+${ROOT_FREE_MIN_MB}M min free) > cap $capb for MAX_IMAGE_BYTES=$MAX_IMAGE_BYTES" >&2; return 1; fi; }
if [ "${1:-}" = --plan ]; then [ $# = 4 ] || { echo "usage: shrink-image.sh --plan MINB BS O2" >&2; exit 2; }; plan "$2" "$3" "$4"; exit; fi
[ $# = 1 ] && [ -f "$1" ] || { echo "usage: shrink-image.sh IMG" >&2; exit 2; }
IMG=$1
read -r O2 S2 < <(parted -sm "$IMG" unit B print | awk -F: '$1==2{sub("B","",$2);sub("B","",$4);print $2" "$4}')
L2=$(losetup -f --show -o "$O2" --sizelimit "$S2" "$IMG"); trap 'losetup -d "$L2" 2>/dev/null || true' EXIT
e2fsck -fy "$L2" >/dev/null || true
BS=$(dumpe2fs -h "$L2" 2>/dev/null | awk -F: '/^Block size/{gsub(/ /,"",$2);print $2}')
MINB=$(resize2fs -P "$L2" 2>/dev/null | awk -F': ' '/minimum/{print $2}')
read -r WANT MODE < <(plan "$MINB" "$BS" "$O2") || exit 1
[ -n "${WANT:-}" ] || exit 1
resize2fs "$L2" "$WANT" >/dev/null; e2fsck -fn "$L2" >/dev/null; losetup -d "$L2"; trap - EXIT
echo ", $(( WANT*BS/512 ))" | sfdisk --no-reread -N 2 "$IMG" >/dev/null
truncate -s $(( O2 + WANT*BS )) "$IMG"
SZ=$(stat -c %s "$IMG"); [ "$SZ" -le "$MAX_IMAGE_BYTES" ] || { echo "image $SZ > MAX_IMAGE_BYTES $MAX_IMAGE_BYTES" >&2; exit 1; }
echo "image shrunk to $SZ bytes ($MODE: root free ~$(( (WANT-MINB)*BS/1024/1024 ))M, max $MAX_IMAGE_BYTES)"
