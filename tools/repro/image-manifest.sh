#!/usr/bin/env bash
# image-manifest.sh IMAGE OUT.tsv - manifest v2 (image-manifest.py) of a client disk image, per partition (idea#322).
#   IMAGE: idea-client-*.img, or .img.xz (decompressed sparse into $REPRO_TMP, default /tmp, and removed after).
#   Read-only: each partition is attached with `losetup -r -o OFFSET` and mounted ro (ext4: ro,noload). Needs sudo.
#   Writes partition-table lines (type P) first: label type + per partition start/size/type/bootable and the
#   filesystem type + label. Disk id and filesystem UUIDs are normalised away (they are random per build).
set -euo pipefail
export PATH="$PATH:/usr/sbin:/sbin"
HERE=$(cd "$(dirname "$0")" && pwd)
IMG="${1:?usage: image-manifest.sh IMAGE OUT.tsv}"; OUT="${2:?usage: image-manifest.sh IMAGE OUT.tsv}"
SUDO=""; [ "$(id -u)" = 0 ] || SUDO="sudo -n"
T=$(mktemp -d "${REPRO_TMP:-/tmp}/imgman.XXXXXX"); LOOPS=()
cleanup(){ rc=$?; set +e; for m in "$T"/mnt/*; do mountpoint -q "$m" && $SUDO umount "$m"; done
  for l in "${LOOPS[@]}"; do $SUDO losetup -d "$l"; done; rm -rf "$T"; exit "$rc"; }
trap cleanup EXIT
RAW="$IMG"
case "$IMG" in *.xz) RAW="$T/image.img"; xz -dc -T0 "$IMG" | dd of="$RAW" bs=4M conv=sparse status=none;; esac
# Partition table straight from the image file (no partscan needed: works in containers without udev).
SECT=$(sfdisk -d "$RAW" | sed -n 's/^sector-size: *//p'); SECT=${SECT:-512}
LAY="$T/layout.tsv"
sfdisk -d "$RAW" | awk -F'[:,]' '
  /^label:/ {gsub(/ /,"",$2); print "-\tP\t-\t-\t-\tlabel="$2"\t-\t(partition-table)"}
  / : start=/ { n=$1; gsub(/ /,"",n); sub(/^.*[^0-9]/,"",n); c="";
    for(i=2;i<=NF;i++){f=$i; gsub(/ /,"",f); if(f!="" && f !~ /^uuid=/) c=c (c==""?"":",") f}
    print "p" n "\tP\t-\t-\t-\t" c "\t-\t(partition)" }' > "$LAY"
PARTS=(); LOOPS=()
while read -r n st sz; do
  L=$($SUDO losetup -r -f --show -o $((st*SECT)) --sizelimit $((sz*SECT)) "$RAW"); LOOPS+=("$L")
  fst=$($SUDO blkid -p -o value -s TYPE "$L" || true); lab=$($SUDO blkid -p -o value -s LABEL "$L" || true)
  printf 'p%s\tP\t-\t-\t-\tfs=%s,label=%s\t-\t(filesystem)\n' "$n" "${fst:-none}" "$lab" >> "$LAY"
  [ -n "$fst" ] || continue
  name="p$n"; [ "$fst" = ext4 ] && name=root; [ "$fst" = vfat ] && name=boot
  if [ "$fst" = vfat ]; then
    # FAT: read with mtools (no vfat module needed; FAT has no owners/modes, so those columns are "-").
    mkdir -p "$T/fat/p$n"; MTOOLS_SKIP_CHECK=1 mcopy -s -n -m -i "$RAW@@$((st*SECT))" '::/*' "$T/fat/p$n/"
    PARTS+=("$name=fat:$T/fat/p$n")
  else
    mkdir -p "$T/mnt/p$n"; opt=ro; [ "$fst" = ext4 ] && opt=ro,noload
    $SUDO mount -t "$fst" -o "$opt" "$L" "$T/mnt/p$n"; PARTS+=("$name=$T/mnt/p$n")
  fi
done < <(sfdisk -d "$RAW" | sed -n 's/^.*[^0-9]\([0-9][0-9]*\) : start= *\([0-9]*\), size= *\([0-9]*\).*/\1 \2 \3/p')
[ ${#PARTS[@]} -gt 0 ] || { echo "no mountable partitions in $IMG" >&2; exit 1; }
LC_ALL=C sort -o "$LAY" "$LAY"
$SUDO python3 "$HERE/image-manifest.py" --layout "$LAY" "${PARTS[@]}" > "$OUT"
echo "image manifest: $OUT ($(grep -vc '^#' "$OUT") entries)"
