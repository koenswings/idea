#!/usr/bin/env bash
# Build idea-client-<ver>.img.xz from the official Ubuntu raspi desktop image (proposal idea#201 §9).
# Usage: sudo tools/client-image/build.sh [--base /path/to/base.img.xz] [--secrets FILE] [--out DIR] [--no-xz]
# Host: amd64 or arm64 Linux with losetup, qemu-user-static (binfmt for aarch64 on amd64), xz, parted, e2fsprogs.
set -euo pipefail
export PATH="$PATH:/usr/sbin:/sbin"
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
. "$HERE/client-image.conf"
BASE=""; SECRETS="${SUDO_USER:+$(getent passwd "$SUDO_USER" | cut -d: -f6)}/.config/idea-client-image/secrets.env"
OUT="$HERE/out"; WORK="$HERE/work"; XZ=1; EXTRA_MB=6144
while [ $# -gt 0 ]; do case "$1" in
  --base) BASE="$2"; shift 2;; --secrets) SECRETS="$2"; shift 2;;
  --out) OUT="$2"; shift 2;; --work) WORK="$2"; shift 2;; --no-xz) XZ=0; shift;;
  *) echo "unknown arg $1" >&2; exit 2;; esac; done
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }

# --- secrets: outside git, never echoed ---
[ -f "$SECRETS" ] || { echo "secrets file missing: $SECRETS (see secrets.env.example)" >&2; exit 1; }
case "$(realpath "$SECRETS")" in "$REPO"/*) echo "refusing: secrets file is inside the repo" >&2; exit 1;; esac
set +x; . "$SECRETS"
for v in ADMIN_AUTHORIZED_KEYS_FILE ADMIN_PASSWORD_HASH WIFI_PSK; do [ -n "${!v:-}" ] || { echo "secret $v not set" >&2; exit 1; }; done
grep -q 'PRIVATE KEY' "$ADMIN_AUTHORIZED_KEYS_FILE" && { echo "authorized keys file contains a private key" >&2; exit 1; }

GITSHA="$(git -C "$REPO" rev-parse --short HEAD)"; [ -z "$(git -C "$REPO" status --porcelain -- tools/client-image)" ] || GITSHA="${GITSHA}-dirty"
VER="26.04-$(date -u +%Y%m%d)-$GITSHA"; NAME="idea-client-$VER"
mkdir -p "$OUT" "$WORK"

# --- base image: fetch if needed, verify sha (pinned + live SHA256SUMS when reachable) ---
[ -n "$BASE" ] || BASE="$WORK/$BASE_IMAGE"
[ -f "$BASE" ] || curl -fL --retry 3 -o "$BASE" "$BASE_URL/$BASE_IMAGE"
echo "$BASE_SHA256  $BASE" | sha256sum -c --quiet || { echo "base image sha256 mismatch" >&2; exit 1; }
if live=$(curl -fsL "$BASE_URL/SHA256SUMS" 2>/dev/null | awk -v f="*$BASE_IMAGE" '$2==f{print $1}') && [ -n "$live" ]; then
  [ "$live" = "$BASE_SHA256" ] || { echo "pinned sha differs from live SHA256SUMS" >&2; exit 1; }; fi

IMG="$WORK/$NAME.img"; echo "decompressing base -> $IMG"; xz -dc -T0 "$BASE" > "$IMG"
truncate -s +"${EXTRA_MB}M" "$IMG"
# partition loops by offset (works in containers without /dev/loopNpM nodes)
parted -s "$IMG" resizepart 2 100%
poff(){ parted -sm "$IMG" unit B print | awk -F: -v n=$1 '$1==n{sub("B","",$2);sub("B","",$4);print $2" "$4}'; }
read O1 S1 < <(poff 1); read O2 S2 < <(poff 2)
L1=$(losetup -f --show -o "$O1" --sizelimit "$S1" "$IMG"); L2=$(losetup -f --show -o "$O2" --sizelimit "$S2" "$IMG")
MNT="$WORK/root"
cleanup() { set +e; for m in dev/pts dev proc sys run boot/firmware ""; do mountpoint -q "$MNT/$m" && umount -l "$MNT/$m"; done; losetup -d "$L1" "$L2" 2>/dev/null; }
trap cleanup EXIT
e2fsck -fy "$L2" >/dev/null || true; resize2fs "$L2" >/dev/null
mkdir -p "$MNT"; mount "$L2" "$MNT"; mount "$L1" "$MNT/boot/firmware"
for m in dev dev/pts proc sys run; do mount --bind "/$m" "$MNT/$m"; done
if [ "$(uname -m)" != aarch64 ]; then cp /usr/bin/qemu-aarch64-static "$MNT/usr/bin/"; fi
mv "$MNT/etc/resolv.conf" "$MNT/etc/resolv.conf.idea-orig" 2>/dev/null || true; cp -L /etc/resolv.conf "$MNT/etc/resolv.conf"

# --- stage inputs (secrets in a root-only dir, removed before packing) ---
S="$MNT/root/.idea-build"; install -d -m 700 "$S"
cp "$HERE/client-image.conf" "$HERE/customise.sh" "$HERE/verify-image.sh" "$S/"; cp -r "$HERE/files" "$S/files"
install -m 600 "$ADMIN_AUTHORIZED_KEYS_FILE" "$S/admin_authorized_keys"
( umask 077; printf 'ADMIN_PASSWORD_HASH=%q\nWIFI_PSK=%q\n' "$ADMIN_PASSWORD_HASH" "$WIFI_PSK" > "$S/secrets.env" )
echo "IDEA_CLIENT_VERSION=$VER" > "$S/version.env"

chroot "$MNT" /bin/bash /root/.idea-build/customise.sh
chroot "$MNT" dpkg-query -W -f='${Package}\t${Version}\n' > "$OUT/$NAME.MANIFEST.txt"
chroot "$MNT" /bin/bash /root/.idea-build/verify-image.sh

rm -rf "$S"; rm -f "$MNT/usr/bin/qemu-aarch64-static"
rm -f "$MNT/etc/resolv.conf"; mv "$MNT/etc/resolv.conf.idea-orig" "$MNT/etc/resolv.conf" 2>/dev/null || true
"$HERE/scan-secrets.sh" "$MNT" "$SECRETS"
fstrim "$MNT" 2>/dev/null || true
cleanup; trap - EXIT

if [ $XZ = 1 ]; then xz -T0 -6 -f "$IMG"; F="$IMG.xz"; else F="$IMG"; fi
mv "$F" "$OUT/"; ( cd "$OUT" && sha256sum "$(basename "$F")" > "$(basename "$F").sha256" )
echo "built $OUT/$(basename "$F")"; cat "$OUT/$(basename "$F").sha256"
