#!/usr/bin/env bash
# build.sh - IDEA Engine image (idea#322 stage 5, Option A): Raspberry Pi OS Lite arm64 base (pinned) + the Engine's
# offline build run into the mounted root fs (agent-engine-dev, see INTERFACE.md) + our sanitise/verify second check
# + secret scan + shrink + xz + manifest. Output: <out>/idea-engine-<ver>.img.xz (never "-dev" unless --dev).
# Usage: sudo tools/engine-image/build.sh --engine-src DIR [--dev] [--out DIR] [--work DIR] [--no-xz] [--manifest-out DIR]
# Env: ENGINE_BUILD_CMD overrides the Engine step (runs with bash -c; MNT, ENGINE_SRC, OUT exported). Needs root, arm64 host
# or qemu-user-static binfmt; host tools as for the client builder.
# shellcheck disable=SC1091,SC2016  # sourced paths are resolved at run time; single-quoted commands are run by bash -c / dpkg-query
set -euo pipefail
export PATH="$PATH:/usr/sbin:/sbin"
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(git -C "$HERE" rev-parse --show-toplevel)
# shellcheck source=engine-image.conf
. "$HERE/engine-image.conf"
# shellcheck source=../repro/lib.sh
. "$REPO/tools/repro/lib.sh"
DEV=0; XZ=1; OUT="$REPO/out/engine"; WORK="$HOME/.cache/idea-engine-image"; ENGINE_SRC=""; MOUT=""
while [ $# -gt 0 ]; do case "$1" in
  --dev) DEV=1; shift;; --no-xz) XZ=0; shift;; --out) OUT="$2"; shift 2;; --work) WORK="$2"; shift 2;;
  --engine-src) ENGINE_SRC="$2"; shift 2;; --manifest-out) MOUT="$2"; shift 2;; *) echo "unknown arg $1" >&2; exit 2;; esac; done
[ -n "$ENGINE_SRC" ] && [ -d "$ENGINE_SRC/.git" ] || { echo "--engine-src DIR (agent-engine-dev checkout) required" >&2; exit 2; }
[ "$(id -u)" = 0 ] || { echo "run as root (sudo)" >&2; exit 1; }
need="losetup parted sfdisk dumpe2fs e2fsck resize2fs mcopy mmd xz curl git sha256sum truncate mountpoint chroot python3"
missing=""; for t in $need; do command -v "$t" >/dev/null || missing="$missing $t"; done
[ -z "$missing" ] || { echo "missing host tools:$missing" >&2; exit 1; }
repro_release_guard "$REPO" "$DEV"; export BUILD_KIND BUILD_SHA BUILD_TAG BUILD_STAMP
if [ "$DEV" = 0 ] && [ -n "$(git -C "$ENGINE_SRC" status --porcelain)" ]; then echo "refusing release build: engine source is dirty" >&2; exit 1; fi
ESHA=$(git -C "$ENGINE_SRC" rev-parse HEAD); ESHORT=$(git -C "$ENGINE_SRC" rev-parse --short=7 HEAD)
CDATE=$(git -C "$REPO" log -1 --format=%cd --date=format:%Y%m%d HEAD)
VER="trixie-$CDATE-$BUILD_SHORT-e$ESHORT"; [ "$BUILD_KIND" = release ] || VER="$VER-dev"; NAME="idea-engine-$VER"
mkdir -p "$OUT" "$WORK"; T0=$(date +%s)

BASE="$WORK/$BASE_IMAGE"; repro_fetch "$BASE_URL/$BASE_IMAGE" "$BASE_SHA256" "$BASE" || exit 1
INPUTS="$WORK/inputs.tsv"; repro_inputs_row base "$BASE_URL/$BASE_IMAGE" "$BASE" > "$INPUTS"
printf 'engine-src\t%s\t%s\t-\n' "$(git -C "$ENGINE_SRC" remote get-url origin 2>/dev/null || echo local)" "$ESHA" >> "$INPUTS"

IMG="$WORK/$NAME.img"; echo "decompressing base -> $IMG"; xz -dc -T0 "$BASE" > "$IMG"
truncate -s +"${EXTRA_MB}M" "$IMG"; parted -s "$IMG" resizepart 2 100%
poff(){ parted -sm "$IMG" unit B print | awk -F: -v n="$1" '$1==n{sub("B","",$2);sub("B","",$4);print $2" "$4}'; }
read -r O1 _ < <(poff 1); read -r O2 S2 < <(poff 2)
L2=$(losetup -f --show -o "$O2" --sizelimit "$S2" "$IMG"); MNT="$WORK/root"; FW="$WORK/firmware"
cleanup() { set +e; for m in dev/pts dev proc sys run boot/firmware ""; do mountpoint -q "$MNT/$m" && umount -l "$MNT/$m"; done; losetup -d "$L2" 2>/dev/null; }
trap cleanup EXIT
e2fsck -fy "$L2" >/dev/null || true; resize2fs "$L2" >/dev/null
mkdir -p "$MNT"; mount "$L2" "$MNT"
if [ -d "$FW" ]; then mv "$FW" "$FW.old-$(date +%Y%m%d-%H%M%S)"; fi; mkdir -p "$FW"; export MTOOLS_SKIP_CHECK=1
mcopy -s -n -i "$IMG@@$O1" '::/*' "$FW/"; ( cd "$FW" && find . -type f -exec sha256sum {} + | sort > "$WORK/fw.before" )
mkdir -p "$MNT/boot/firmware"; mount --bind "$FW" "$MNT/boot/firmware"
for m in dev dev/pts proc sys run; do mount --bind "/$m" "$MNT/$m"; done
if [ "$(uname -m)" != aarch64 ]; then cp /usr/bin/qemu-aarch64-static "$MNT/usr/bin/"; fi
mv "$MNT/etc/resolv.conf" "$MNT/etc/resolv.conf.idea-orig" 2>/dev/null || true; cp -L /etc/resolv.conf "$MNT/etc/resolv.conf"

# --- Engine offline build (agent-engine-dev; interface: INTERFACE.md) ---
export MNT ENGINE_SRC OUT
DEFAULT_ENGINE_CMD='"$ENGINE_SRC/script/build-engine-offline" --root "$MNT" --boot "$MNT/boot/firmware" --report "$OUT/engine-build.json"'
set +e; bash -c "${ENGINE_BUILD_CMD:-$DEFAULT_ENGINE_CMD}"; erc=$?; set -e
case $erc in 0) ;; 2) echo "engine offline build: usage error (interface mismatch, see INTERFACE.md)" >&2; exit 1;;
  *) echo "engine offline build failed (rc $erc)" >&2; exit 1;; esac
chroot "$MNT" dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n' | LC_ALL=C sort -u > "$OUT/$NAME.MANIFEST.txt"

rm -f "$MNT/usr/bin/qemu-aarch64-static" "$MNT/etc/resolv.conf"; mv "$MNT/etc/resolv.conf.idea-orig" "$MNT/etc/resolv.conf" 2>/dev/null || true
# --- our second check: sanitise + verify + secret scan (the Engine build already strips identity) ---
"$HERE/sanitise.sh" "$MNT"
"$HERE/verify-sanitised.sh" "$MNT" | tee "$OUT/$NAME.verify.txt"
"$REPO/tools/client-image/scan-secrets.sh" "$MNT"
MOUT="${MOUT:-$REPO/manifests/engine/$NAME}"
"$REPO/tools/repro/write-manifest.sh" --out "$MOUT" --kind engine --name "$NAME" --rootfs "$MNT" --packages "$OUT/$NAME.MANIFEST.txt" --inputs "$INPUTS"
umount "$MNT/boot/firmware"
( cd "$FW" && find . -type f -exec sha256sum {} + | sort > "$WORK/fw.after" )
comm -13 "$WORK/fw.before" "$WORK/fw.after" | awk '{print $2}' | while read -r f; do
  d=$(dirname "${f#./}"); [ "$d" = . ] || mmd -D s -i "$IMG@@$O1" "::/$d" 2>/dev/null || true
  mcopy -o -i "$IMG@@$O1" "$FW/${f#./}" "::/${f#./}"; echo "firmware updated: ${f#./}"; done
fstrim "$MNT" 2>/dev/null || true
cleanup; trap - EXIT

MAX_IMAGE_BYTES=$MAX_IMAGE_BYTES ROOT_FREE_MB=$ROOT_FREE_MB ROOT_FREE_MIN_MB=$ROOT_FREE_MIN_MB "$REPO/tools/client-image/shrink-image.sh" "$IMG"
RAW=$(stat -c %s "$IMG")
if [ $XZ = 1 ]; then xz -T0 -6 -f "$IMG"; F="$IMG.xz"; else F="$IMG"; fi
FB=$(stat -c %s "$F")
if [ "$FB" -le "$RELEASE_FILE_LIMIT_BYTES" ]; then SIZE="ok ($FB <= $RELEASE_FILE_LIMIT_BYTES)"; else SIZE="OVER ($FB > $RELEASE_FILE_LIMIT_BYTES)"; fi
mv "$F" "$OUT/"; ( cd "$OUT" && sha256sum "$(basename "$F")" > "$(basename "$F").sha256" )
{ echo "raw_bytes=$RAW"; echo "file_bytes=$FB"; echo "release_file_limit=$SIZE"; echo "engine_commit=$ESHA"; echo "duration_s=$(( $(date +%s) - T0 ))"; } > "$OUT/$NAME.size.txt"
cat "$OUT/$NAME.size.txt"
"$REPO/tools/repro/write-manifest.sh" --out "$MOUT" --image "$OUT/$(basename "$F")"
[ -z "${SUDO_USER:-}" ] || chown -R "$SUDO_USER" "$MOUT" "$OUT"
