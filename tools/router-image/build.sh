#!/bin/bash
# tools/router-image/build.sh - build the IDEA router image with the official
# OpenWrt Image Builder (idea#209). x86_64 Linux only (the IB is x86_64).
# Usage: tools/router-image/build.sh [--dev] [OUTDIR]   (env: WORK=/path/cache, ALLOW_LABEL_TODO=1, MANIFEST_OUT=DIR,
#        PKG_ARCHIVE=DIR of archived .apk + SHA256SUMS for an offline rebuild of exact package versions)
# Reproducible (idea#322): release = clean tree at a tag on origin/main (--dev: stamped dev, never for the field);
# IB pinned by version + sha256, feed indexes by feeds.lock, packages by package-pins.tsv (release fails on drift);
# NO secrets in the image (root password + Tailscale key are set by idea-router-enrol at flash time);
# manifest (build.env, inputs.tsv, packages.tsv, content.tsv.xz, image.sha256) -> manifests/router/<name>/.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(cd "$HERE/../.." && pwd)
# shellcheck source=SCRIPTDIR/config.env
. "$HERE/config.env"
. "$REPO/tools/repro/lib.sh"
DEV=0; [ "${1:-}" = --dev ] && { DEV=1; shift; }
repro_release_guard "$REPO" "$DEV"
OUT=${1:-$PWD/out}; WORK=${WORK:-$HOME/.cache/idea-router-ib}
mkdir -p "$OUT" "$WORK"
if grep -q "='LABEL_TODO_" "$HERE/config.env" && [ "${ALLOW_LABEL_TODO:-0}" != 1 ]; then
  echo "LABEL_TODO_ values remain in config.env; set ALLOW_LABEL_TODO=1 for a dev build"; exit 2; fi
cd "$WORK"
IB_URL="https://downloads.openwrt.org/releases/$OPENWRT_VERSION/targets/$OPENWRT_TARGET/$IB_FILE"
repro_fetch "$IB_URL" "$IB_SHA256" "$WORK/$IB_FILE" || exit 1
INPUTS="$WORK/inputs.tsv"; repro_inputs_row imagebuilder "$IB_URL" "$WORK/$IB_FILE" > "$INPUTS"
IB=${IB_FILE%.tar.zst}; [ -d "$IB" ] || tar --zstd -xf "$IB_FILE"
if [ -n "${PKG_ARCHIVE:-}" ]; then
  # offline (idea#322): install ONLY the archived .apk files (exact versions of a previous build); no feeds used.
  # The upstream release feeds change within a release (ca-bundle, tailscale, ...), so this is how an old image is rebuilt.
  [ -f "$PKG_ARCHIVE/SHA256SUMS" ] || { echo "PKG_ARCHIVE needs SHA256SUMS" >&2; exit 1; }
  (cd "$PKG_ARCHIVE" && sha256sum -c --quiet SHA256SUMS) || { echo "package archive hash mismatch" >&2; exit 1; }
  rm -rf "$IB-offline"; mkdir "$IB-offline"; tar --zstd -xf "$IB_FILE" -C "$IB-offline" --strip-components=1; IB="$IB-offline"
  for a in "$PKG_ARCHIVE"/*.apk; do b=$(basename "$a"); b=${b%.apk}; case "$b" in *.[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) b=${b%.*};; esac
    cp -n "$a" "$IB/packages/$b.apk"; done
  echo '# offline build from PKG_ARCHIVE (idea#322)' > "$IB/repositories"
  printf 'package-archive\tfile://%s\t%s\t-\n' "$PKG_ARCHIVE" "$(repro_sha "$PKG_ARCHIVE/SHA256SUMS")" >> "$INPUTS"
else
# feeds pinned (idea#322): the IB's repositories must be exactly feeds.lock, and each index must match its sha256
diff <(grep -v '^#' "$HERE/feeds.lock" | cut -f1 | sort) <(grep -v '^\s*#' "$IB/repositories" | grep . | sort) >/dev/null \
  || { echo "IB repositories differ from feeds.lock" >&2; exit 1; }
n=0; while IFS=$'\t' read -r u h; do n=$((n+1))
  repro_fetch "$u" "$h" "$WORK/feed-$n.adb" || { echo "feed index changed upstream: rebuild with PKG_ARCHIVE=<archived apks> or refresh feeds.lock + package-pins.tsv deliberately" >&2; exit 1; }
  repro_inputs_row "feed-$n" "$u" "$WORK/feed-$n.adb" >> "$INPUTS"; rm -f "$WORK/feed-$n.adb"
  done < <(grep -v '^#' "$HERE/feeds.lock")
fi
# overlay: static files + generated first-boot copies of the manual scripts
F="$WORK/files"; rm -rf "$F"; cp -a "$HERE/files" "$F"
mkdir -p "$F/usr/share/idea" "$F/etc/idea"   # empty dirs are not tracked by git
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
grep -q "@ROOT_PASSWORD@" "$F/etc/uci-defaults/90-idea-setup" && { echo "90-idea-setup still expects a baked root password" >&2; exit 1; }
GIT="$BUILD_SHORT"; [ "$BUILD_KIND" = release ] || GIT="$GIT-dev"; SETUP_SHA=$(git -C "$REPO" rev-parse --short "$SETUP_REF")
printf 'IDEA_ROUTER_VERSION=%s\nBUILD=%s\nGIT=%s\nSETUP_REF=%s\nOPENWRT=%s\nPROFILE=%s\n' "$IDEA_ROUTER_VERSION" "$BUILD_STAMP" "$GIT" "$SETUP_SHA" "$OPENWRT_VERSION" "$PROFILE" > "$F/etc/idea/version"
chmod 755 "$F/etc/uci-defaults/90-idea-setup" "$F"/usr/share/idea/*.sh
PKGS=$(grep -v '^\s*#' "$HERE/packages.txt" | xargs)
make -C "$IB" image PROFILE="$PROFILE" PACKAGES="$PKGS" FILES="$F" \
  EXTRA_IMAGE_NAME="idea-$IDEA_ROUTER_VERSION" BIN_DIR="$OUT/bin" -j"${JOBS:-2}"
SRC=""; for f in "$OUT"/bin/*"$PROFILE"-squashfs-sysupgrade.bin; do case "$f" in *ubootmod*) ;; *) SRC=$f ;; esac; done
NAME="idea-router-$IDEA_ROUTER_VERSION-$GIT-$PROFILE-squashfs-sysupgrade.bin"
cp "$SRC" "$OUT/$NAME"; (cd "$OUT" && sha256sum "$NAME" > SHA256SUMS && cat SHA256SUMS)
cp "$OUT"/bin/*.manifest "$OUT/" 2>/dev/null || true
# --- package pins + manifest (idea#322) ---
sed 's/ - /\t/' "$OUT"/bin/*.manifest | LC_ALL=C sort > "$OUT/packages.tsv"
if "$REPO/tools/repro/compare-manifest.sh" "$HERE/package-pins.tsv" <(cut -f1,2 "$OUT/packages.tsv"); then echo "package pins: match"
elif [ "$BUILD_KIND" = release ]; then echo "refusing release: packages differ from package-pins.tsv" >&2; exit 1
else echo "WARNING (dev build): packages differ from package-pins.tsv" >&2; fi
RT="$WORK/rootfs"; rm -rf "$RT"; "$REPO/tools/repro/extract-rootfs.sh" "$OUT/$NAME" "$RT" >/dev/null
"$REPO/tools/repro/router-packages.sh" "$RT" > "$OUT/packages.tsv"   # 3 columns: package, version, arch
MOUT="${MANIFEST_OUT:-$REPO/manifests/router/${NAME%-squashfs-sysupgrade.bin}}"
"$REPO/tools/repro/write-manifest.sh" --out "$MOUT" --kind router --name "${NAME%-squashfs-sysupgrade.bin}" --rootfs "$RT" \
  --packages "$OUT/packages.tsv" --inputs "$INPUTS" --image "$OUT/$NAME"
rm -rf "$RT"; echo "manifest: $MOUT (commit it)"
# package archive for the deployment record (idea#322): exact .apk files used, outside git
ARCH="${ARCHIVE_OUT:-$WORK/archive/${NAME%-squashfs-sysupgrade.bin}}"; mkdir -p "$ARCH"
cp -n "$IB"/packages/*.apk "$IB"/dl/*.apk "$ARCH/" 2>/dev/null || true; (cd "$ARCH" && sha256sum ./*.apk > SHA256SUMS)
echo "package archive: $ARCH (upload as a release asset; record it in deployments/)"
