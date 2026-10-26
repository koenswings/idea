#!/usr/bin/env bash
# extract-rootfs.sh IMAGE DEST - unpack an IDEA image's root file tree into DEST (read-only on IMAGE), idea#322.
#   client: idea-client-*.img[.xz] (MBR, p1 FAT boot, p2 ext4 root) -> DEST/ (root) + DEST/boot/firmware/ (boot);
#           needs root (loop mount, read-only).
#   router: *-squashfs-sysupgrade.bin (tar with sysupgrade-*/root squashfs) -> DEST/ via unsquashfs (no root needed).
set -euo pipefail
export PATH="$PATH:/usr/sbin:/sbin"
IMG="${1:?usage: extract-rootfs.sh IMAGE DEST}"; DEST="${2:?usage: extract-rootfs.sh IMAGE DEST}"
mkdir -p "$DEST"; T=$(mktemp -d); trap 'set +e; mountpoint -q "$T/m" && umount "$T/m"; rm -rf "$T"' EXIT
case "$IMG" in
  *sysupgrade.bin)
    tar -xf "$IMG" -C "$T" --wildcards '*/root'; R=$(ls "$T"/sysupgrade-*/root)
    unsquashfs -no-progress -no-xattrs -ignore-errors -f -d "$DEST" "$R" >/dev/null 2>&1 || true
    [ -f "$DEST/etc/openwrt_release" ] || { echo "unsquashfs failed for $IMG" >&2; exit 1; } ;;
  *.img|*.img.xz)
    [ "$(id -u)" = 0 ] || { echo "client images need root (loop mount)" >&2; exit 1; }
    RAW="$IMG"; case "$IMG" in *.xz) RAW="$T/i.img"; xz -dc -T0 "$IMG" > "$RAW";; esac
    poff(){ parted -sm "$RAW" unit B print | awk -F: -v n="$1" '$1==n{sub("B","",$2);sub("B","",$4);print $2" "$4}'; }
    read -r O1 S1 < <(poff 1); read -r O2 S2 < <(poff 2); mkdir -p "$T/m"
    mount -o ro,loop,offset="$O2",sizelimit="$S2" "$RAW" "$T/m"; cp -a "$T/m/." "$DEST/"; umount "$T/m"
    mkdir -p "$DEST/boot/firmware"; MTOOLS_SKIP_CHECK=1 mcopy -s -n -i "$RAW@@$O1" '::/*' "$DEST/boot/firmware/"
    : "${S1:?}" ;;
  *) echo "unknown image type: $IMG" >&2; exit 2;;
esac
echo "extracted $IMG -> $DEST"
