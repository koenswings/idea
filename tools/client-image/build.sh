#!/usr/bin/env bash
# Build idea-client-<ver>.img.xz from the official Ubuntu raspi desktop image (proposal idea#201 §9).
# Usage: sudo tools/client-image/build.sh [--dev] [--browser chrome|chromium] [--chrome-deb FILE] [--base /path/to/base.img.xz]
#        [--out DIR] [--work DIR] [--no-xz] [--apt-pins FILE|none] [--manifest-out DIR]
# Reproducible (idea#322): a release build needs a clean tree at a tag on origin/main (--dev: any tree, image stamped
# "dev", never for the field); apt versions pinned by apt-pins.tsv; every download sha256-verified; the image holds
# NO secrets (Wi-Fi key + admin SSH keys are written at flash time by set-card-secrets.sh); a manifest
# (build.env, inputs.tsv, packages.tsv, content.tsv.xz, image.sha256) goes to manifests/client/<name>/ - commit it.
# Host: amd64 or arm64 Linux with losetup, qemu-user-static (binfmt for aarch64 on amd64), xz, parted, e2fsprogs.
set -euo pipefail
export PATH="$PATH:/usr/sbin:/sbin"
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
. "$HERE/client-image.conf"
. "$REPO/tools/repro/lib.sh"
BASE=""; CHROME_FILE=""; DEV=0; PINS="$HERE/apt-pins.tsv"; MOUT=""
OUT="$HERE/out"; WORK="$HERE/work"; XZ=1; EXTRA_MB=6144
while [ $# -gt 0 ]; do case "$1" in
  --base) BASE="$2"; shift 2;; --browser) BROWSER="$2"; shift 2;; --chrome-deb) CHROME_FILE="$2"; shift 2;;
  --dev) DEV=1; shift;; --apt-pins) PINS="$2"; shift 2;; --manifest-out) MOUT="$2"; shift 2;;
  --secrets|--test-secrets) echo "$1 is gone (idea#322): images carry no secrets; use set-card-secrets.sh at flash time" >&2; exit 2;;
  --out) OUT="$2"; shift 2;; --work) WORK="$2"; shift 2;; --no-xz) XZ=0; shift;;
  *) echo "unknown arg $1" >&2; exit 2;; esac; done
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
# required host tools (Debian/Ubuntu packages: util-linux fdisk parted e2fsprogs mtools xz-utils curl git coreutils;
# qemu-user-static + binfmt only on non-arm64 hosts)
need="losetup parted sfdisk dumpe2fs e2fsck resize2fs mcopy mmd xz curl git sha256sum truncate mountpoint chroot fstrim python3"
[ "$(uname -m)" = aarch64 ] || need="$need qemu-aarch64-static"
missing=""; for t in $need; do command -v "$t" >/dev/null 2>&1 || [ -x "/usr/bin/$t" ] || missing="$missing $t"; done
[ -z "$missing" ] || { echo "missing host tools:$missing (apt install util-linux fdisk parted e2fsprogs mtools xz-utils curl git qemu-user-static)" >&2; exit 1; }

# --- release guard (idea#322): clean tree, tagged, on origin/main; --dev stamps a non-release image ---
repro_release_guard "$REPO" "$DEV"
[ "$PINS" = none ] && PINS=""; [ -z "$PINS" ] || [ -s "$PINS" ] || { echo "apt pins file missing: $PINS" >&2; exit 1; }
[ "$DEV" = 1 ] || [ -n "$PINS" ] || { echo "refusing release build without apt pins" >&2; exit 1; }
# version date = commit date (not build date), so a rebuild of the same commit gets the same name
CDATE=$(git -C "$REPO" log -1 --format=%cd --date=format:%Y%m%d HEAD)
VER="26.04-$CDATE-$BUILD_SHORT"; [ "$BUILD_KIND" = release ] || VER="$VER-dev"; NAME="idea-client-$VER"
mkdir -p "$OUT" "$WORK"

# --- base image: fetch if needed, verify sha (pinned + live SHA256SUMS when reachable) ---
[ -n "$BASE" ] || BASE="$WORK/$BASE_IMAGE"
repro_fetch "$BASE_URL/$BASE_IMAGE" "$BASE_SHA256" "$BASE" || exit 1
INPUTS="$WORK/inputs.tsv"; repro_inputs_row base "$BASE_URL/$BASE_IMAGE" "$BASE" > "$INPUTS"
if live=$(curl -fsL "$BASE_URL/SHA256SUMS" 2>/dev/null | awk -v f="*$BASE_IMAGE" '$2==f{print $1}') && [ -n "$live" ]; then
  [ "$live" = "$BASE_SHA256" ] || { echo "pinned sha differs from live SHA256SUMS" >&2; exit 1; }; fi

case "$BROWSER" in chrome|chromium) ;; *) echo "--browser must be chrome or chromium" >&2; exit 2;; esac
# --- Chrome .deb: pinned version, fetched once (offline afterwards), sha256 must match client-image.conf ---
if [ "$BROWSER" = chrome ]; then
  [ -n "$CHROME_FILE" ] || CHROME_FILE="$WORK/$CHROME_DEB"
  repro_fetch "$CHROME_DEB_URL" "$CHROME_DEB_SHA256" "$CHROME_FILE" || exit 1
  repro_inputs_row chrome-deb "$CHROME_DEB_URL" "$CHROME_FILE" >> "$INPUTS"
fi

IMG="$WORK/$NAME.img"; echo "decompressing base -> $IMG"; xz -dc -T0 "$BASE" > "$IMG"
truncate -s +"${EXTRA_MB}M" "$IMG"
# partition loops by offset (works in containers without /dev/loopNpM nodes)
parted -s "$IMG" resizepart 2 100%
poff(){ parted -sm "$IMG" unit B print | awk -F: -v n=$1 '$1==n{sub("B","",$2);sub("B","",$4);print $2" "$4}'; }
read -r O1 _ < <(poff 1); read O2 S2 < <(poff 2)
L2=$(losetup -f --show -o "$O2" --sizelimit "$S2" "$IMG")
MNT="$WORK/root"
cleanup() { set +e; for m in dev/pts dev proc sys run boot/firmware ""; do mountpoint -q "$MNT/$m" && umount -l "$MNT/$m"; done; losetup -d "$L2" 2>/dev/null; }
trap cleanup EXIT
e2fsck -fy "$L2" >/dev/null || true; resize2fs "$L2" >/dev/null
mkdir -p "$MNT"; mount "$L2" "$MNT"; # FAT boot partition via mtools (no vfat kernel module needed): unpack, bind in, write back changed files after
FW="$WORK/firmware"; rm -rf "$FW"; mkdir -p "$FW"; export MTOOLS_SKIP_CHECK=1
mcopy -s -n -i "$IMG@@$O1" '::/*' "$FW/"; ( cd "$FW" && find . -type f -exec sha256sum {} + | sort > "$WORK/fw.before" )
mkdir -p "$MNT/boot/firmware"; mount --bind "$FW" "$MNT/boot/firmware"
for m in dev dev/pts proc sys run; do mount --bind "/$m" "$MNT/$m"; done
if [ "$(uname -m)" != aarch64 ]; then cp /usr/bin/qemu-aarch64-static "$MNT/usr/bin/"; fi
mv "$MNT/etc/resolv.conf" "$MNT/etc/resolv.conf.idea-orig" 2>/dev/null || true; cp -L /etc/resolv.conf "$MNT/etc/resolv.conf"

# --- stage inputs (root-only dir, removed before packing; no secrets, idea#322) ---
S="$MNT/root/.idea-build"; install -d -m 700 "$S"
cp "$HERE/client-image.conf" "$HERE/customise.sh" "$HERE/browser.sh" "$HERE/verify-image.sh" "$HERE/verify-browser.sh" "$S/"; cp -r "$HERE/files" "$S/files"
printf 'BROWSER=%q\nCHROME_DEB=%q\n' "$BROWSER" "$CHROME_DEB" > "$S/browser.env"
[ "$BROWSER" = chrome ] && cp "$CHROME_FILE" "$S/$CHROME_DEB"
[ -z "$PINS" ] || cp "$PINS" "$S/apt-pins.tsv"
echo "IDEA_CLIENT_VERSION=$VER" > "$S/version.env"

chroot "$MNT" /bin/bash /root/.idea-build/customise.sh
chroot "$MNT" dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n' | LC_ALL=C sort -u > "$OUT/$NAME.MANIFEST.txt"
chroot "$MNT" /bin/bash /root/.idea-build/verify-image.sh
if [ -n "$PINS" ]; then
  if "$REPO/tools/repro/compare-manifest.sh" "$PINS" <(cut -f1,2 "$OUT/$NAME.MANIFEST.txt"); then echo "apt pins: installed list = pins"
  elif [ "$BUILD_KIND" = release ]; then echo "refusing release: installed packages differ from $PINS" >&2; exit 1
  else echo "WARNING (dev build): installed packages differ from pins" >&2; fi; fi

rm -rf "$S"; rm -f "$MNT/usr/bin/qemu-aarch64-static"
rm -f "$MNT/etc/resolv.conf"; mv "$MNT/etc/resolv.conf.idea-orig" "$MNT/etc/resolv.conf" 2>/dev/null || true
"$HERE/scan-secrets.sh" "$MNT"
MOUT="${MOUT:-$REPO/manifests/client/$NAME}"
"$REPO/tools/repro/write-manifest.sh" --out "$MOUT" --kind client --name "$NAME" --rootfs "$MNT" --packages "$OUT/$NAME.MANIFEST.txt" --inputs "$INPUTS"
umount "$MNT/boot/firmware"
( cd "$FW" && find . -type f -exec sha256sum {} + | sort > "$WORK/fw.after" )
comm -13 "$WORK/fw.before" "$WORK/fw.after" | awk '{print $2}' | while read -r f; do
  d=$(dirname "${f#./}"); [ "$d" = . ] || mmd -D s -i "$IMG@@$O1" "::/$d" 2>/dev/null || true
  mcopy -o -i "$IMG@@$O1" "$FW/${f#./}" "::/${f#./}"; echo "firmware updated: ${f#./}"; done
fstrim "$MNT" 2>/dev/null || true
cleanup; trap - EXIT

# Shrink (idea#202, idea#322): fit the smallest "16 GB" cards; scripted fallback to the cap replaces s16's hand shrink.
"$HERE/shrink-image.sh" "$IMG"

if [ $XZ = 1 ]; then xz -T0 -6 -f "$IMG"; F="$IMG.xz"; else F="$IMG"; fi
mv "$F" "$OUT/"; ( cd "$OUT" && sha256sum "$(basename "$F")" > "$(basename "$F").sha256" )
"$REPO/tools/repro/write-manifest.sh" --out "$MOUT" --image "$OUT/$(basename "$F")"
[ -z "${SUDO_USER:-}" ] || chown -R "$SUDO_USER" "$MOUT"
echo "built $OUT/$(basename "$F") ($BUILD_KIND $BUILD_STAMP)"; cat "$OUT/$(basename "$F").sha256"
echo "manifest: $MOUT (commit it; tools/repro/rebuild-check.sh --manifest-dir $MOUT --image <image> verifies a rebuild)"
