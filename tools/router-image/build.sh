#!/bin/bash
# tools/router-image/build.sh - build the IDEA router image with the official
# OpenWrt Image Builder (idea#209). x86_64 Linux only (the IB is x86_64).
# Usage: tools/router-image/build.sh [OUTDIR]   (env: WORK=/path/cache, ALLOW_LABEL_TODO=1)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(cd "$HERE/../.." && pwd)
. "$HERE/config.env"
OUT=${1:-$PWD/out}; WORK=${WORK:-$HOME/.cache/idea-router-ib}
mkdir -p "$OUT" "$WORK"
if grep -q "='LABEL_TODO_" "$HERE/config.env" && [ "${ALLOW_LABEL_TODO:-0}" != 1 ]; then
  echo "LABEL_TODO_ values remain in config.env; set ALLOW_LABEL_TODO=1 for a dev build"; exit 2; fi
cd "$WORK"
[ -f "$IB_FILE" ] || curl -fL -o "$IB_FILE" "https://downloads.openwrt.org/releases/$OPENWRT_VERSION/targets/$OPENWRT_TARGET/$IB_FILE"
echo "$IB_SHA256  $IB_FILE" | sha256sum -c -
IB=${IB_FILE%.tar.zst}; [ -d "$IB" ] || tar --zstd -xf "$IB_FILE"
# overlay: static files + generated first-boot copies of the manual scripts
F="$WORK/files"; rm -rf "$F"; cp -a "$HERE/files" "$F"
# Router scripts: from SETUP_REF (default: idea#211 head 7eedd03 with the avahi reflector +
# idea.local hotplug, until #211 is merged; then set SETUP_REF=HEAD).
SETUP_REF=${SETUP_REF:-7eedd03}; S="$WORK/scripts"; rm -rf "$S"; mkdir -p "$S"
for f in school-router-setup.sh router-tailscale-zone.sh router-starlink-cgnat-exception.sh; do
  git -C "$REPO" show "$SETUP_REF:docs/manuals/install/scripts/$f" > "$S/$f"; done
# school-router-setup.sh minus its final commit/restart/reboot block (uci-defaults must not reboot)
sed '/^uci commit$/,$d' "$S/school-router-setup.sh" > "$F/usr/share/idea/school-router-setup.firstboot.sh"
echo 'uci commit' >> "$F/usr/share/idea/school-router-setup.firstboot.sh"
sed '/init.d/d' "$S/router-tailscale-zone.sh" > "$F/usr/share/idea/router-tailscale-zone.firstboot.sh"
cp "$S/router-starlink-cgnat-exception.sh" "$F/usr/share/idea/"
cp "$S/school-router-setup.sh" "$F/usr/share/idea/"   # for '--check' on the router
sed -i "s/@ROOT_PASSWORD@/$ROOT_PASSWORD/g" "$F/etc/uci-defaults/90-idea-setup"
GIT=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo nogit); SETUP_SHA=$(git -C "$REPO" rev-parse --short "$SETUP_REF")
printf 'IDEA_ROUTER_VERSION=%s\nGIT=%s\nSETUP_REF=%s\nOPENWRT=%s\nPROFILE=%s\n' "$IDEA_ROUTER_VERSION" "$GIT" "$SETUP_SHA" "$OPENWRT_VERSION" "$PROFILE" > "$F/etc/idea/version"
chmod 755 "$F/etc/uci-defaults/90-idea-setup" "$F"/usr/share/idea/*.sh
PKGS=$(grep -v '^\s*#' "$HERE/packages.txt" | xargs)
make -C "$IB" image PROFILE="$PROFILE" PACKAGES="$PKGS" FILES="$F" \
  EXTRA_IMAGE_NAME="idea-$IDEA_ROUTER_VERSION" BIN_DIR="$OUT/bin" -j"${JOBS:-2}"
SRC=$(ls "$OUT"/bin/*"$PROFILE"-squashfs-sysupgrade.bin | grep -v ubootmod)
NAME="idea-router-$IDEA_ROUTER_VERSION-$GIT-$PROFILE-squashfs-sysupgrade.bin"
cp "$SRC" "$OUT/$NAME"; (cd "$OUT" && sha256sum "$NAME" > SHA256SUMS && cat SHA256SUMS)
cp "$OUT"/bin/*.manifest "$OUT/" 2>/dev/null || true
