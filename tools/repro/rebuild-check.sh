#!/usr/bin/env bash
# rebuild-check.sh - automated "rebuild and compare" (idea#322). Any content difference fails (exit 1).
# Usage: rebuild-check.sh --manifest-dir manifests/<kind>/<name> SOURCE
#   SOURCE is one of:
#     --rootfs DIR [--packages FILE]   compare an already unpacked tree (tests, fixtures, or a mounted card)
#     --image FILE                     unpack a built image (extract-rootfs.sh) and compare
#     --rebuild                        check out BUILD_SHA from build.env in a temp worktree, run that kind's
#                                      build.sh (client: sudo; router: x86_64), then compare the new image
# Compares: content.tsv (content-manifest.py, volatile paths ignored) and packages.tsv. image.sha256 is reported
# only (byte-identical images are not required, Koen 2026-10-26).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(git -C "$HERE" rev-parse --show-toplevel)
MD=""; ROOT=""; PKGS=""; IMG=""; REBUILD=0
while [ $# -gt 0 ]; do case "$1" in
  --manifest-dir) MD="$2"; shift 2;; --rootfs) ROOT="$2"; shift 2;; --packages) PKGS="$2"; shift 2;;
  --image) IMG="$2"; shift 2;; --rebuild) REBUILD=1; shift;; *) echo "unknown arg $1" >&2; exit 2;; esac; done
[ -d "$MD" ] && [ -f "$MD/build.env" ] || { echo "--manifest-dir with build.env required" >&2; exit 2; }
KIND=$(sed -n 's/^KIND=//p' "$MD/build.env"); SHA=$(sed -n 's/^BUILD_SHA=//p' "$MD/build.env")
T=$(mktemp -d); trap 'rm -rf "$T"; [ -n "${WT:-}" ] && git -C "$REPO" worktree remove --force "$WT" 2>/dev/null; true' EXIT
if [ $REBUILD = 1 ]; then
  [ -n "$SHA" ] || { echo "build.env has no BUILD_SHA" >&2; exit 2; }
  WT="$T/src"; git -C "$REPO" worktree add --detach "$WT" "$SHA" >/dev/null
  case "$KIND" in
    client) sudo "$WT/tools/client-image/build.sh" --dev --no-xz --out "$T/out" --manifest-out "$T/m" ;;
    router) "$WT/tools/router-image/build.sh" --dev "$T/out" ;;
    *) echo "unknown KIND $KIND" >&2; exit 2;; esac
  IMG=$(find "$T/out" -maxdepth 1 \( -name "idea-*.img" -o -name "idea-router-*.bin" \) | head -1)
fi
if [ -n "$IMG" ]; then
  ROOT="$T/root"; "$HERE/extract-rootfs.sh" "$IMG" "$ROOT" >/dev/null
  if [ -z "$PKGS" ]; then PKGS="$T/packages.tsv"
    if [ "$KIND" = client ]; then dpkg-query --admindir="$ROOT/var/lib/dpkg" -W -f='${Package}\t${Version}\t${Architecture}\n' | LC_ALL=C sort -u > "$PKGS"
    else "$HERE/router-packages.sh" "$ROOT" > "$PKGS"; fi; fi
fi
[ -n "$ROOT" ] || { echo "give --rootfs, --image or --rebuild" >&2; exit 2; }
OWN=$(sed -n 's/^CONTENT_OWNERS=//p' "$MD/build.env"); [ "${OWN:-1}" = 0 ] && export REPRO_NO_OWNER=1
python3 "$HERE/content-manifest.py" "$ROOT" > "$T/content.tsv"
rc=0
echo "== content ($KIND $(sed -n 's/^NAME=//p' "$MD/build.env"))"; "$HERE/compare-manifest.sh" "$MD/content.tsv.xz" "$T/content.tsv" || rc=1
if [ -n "$PKGS" ]; then echo "== packages"; "$HERE/compare-manifest.sh" "$MD/packages.tsv" "$PKGS" || rc=1
else echo "== packages: not checked (no package list for this source)"; fi
if [ -n "$IMG" ] && [ -f "$MD/image.sha256" ]; then
  [ "$(cut -d' ' -f1 "$MD/image.sha256")" = "$(sha256sum "$IMG" | cut -d' ' -f1)" ] && echo "== image: byte-identical (bonus)" \
    || echo "== image: not byte-identical (not required)"; fi
[ $rc = 0 ] && echo "REBUILD CHECK: PASS" || echo "REBUILD CHECK: FAIL"
exit $rc
