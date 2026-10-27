#!/usr/bin/env bash
# write-manifest.sh --out DIR --kind client|router --name NAME --rootfs ROOT --packages FILE [--inputs FILE] [--image FILE]
# Writes the per-build manifest directory (idea#322), to be committed under manifests/<kind>/<name>/:
#   build.env        BUILD_KIND/BUILD_SHA/BUILD_TAG/BUILD_STAMP/NAME/KIND (from the environment set by repro_release_guard)
#   inputs.tsv       name, url, sha256, bytes of every downloaded input
#   packages.tsv     package <TAB> version <TAB> arch, sorted (same sidecar as deployments/ records)
#   content.tsv.xz   content manifest of ROOT (content-manifest.py), xz -9e; content.sha256 = sha256 of the plain tsv
#   image.sha256     sha256 of the image file (when --image is given; may be added later with --image only)
# No secrets: images carry none (secrets are injected at flash time), and this script never reads secret files.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=""; KIND=""; NAME=""; ROOT=""; PKGS=""; INPUTS=""; IMAGE=""
while [ $# -gt 0 ]; do case "$1" in
  --out) OUT="$2"; shift 2;; --kind) KIND="$2"; shift 2;; --name) NAME="$2"; shift 2;; --rootfs) ROOT="$2"; shift 2;;
  --packages) PKGS="$2"; shift 2;; --inputs) INPUTS="$2"; shift 2;; --image) IMAGE="$2"; shift 2;;
  *) echo "unknown arg $1" >&2; exit 2;; esac; done
[ -n "$OUT" ] || { echo "--out required" >&2; exit 2; }
mkdir -p "$OUT"
if [ -n "$ROOT" ]; then
  [ -n "$KIND" ] && [ -n "$NAME" ] && [ -n "$PKGS" ] || { echo "--kind, --name and --packages are required with --rootfs" >&2; exit 2; }
  OWN=1; { [ "$KIND" = router ] || [ "${REPRO_NO_OWNER:-0}" = 1 ]; } && OWN=0   # router trees are unpacked without root: no uid:gid column
  { printf 'KIND=%s\nNAME=%s\nCONTENT_OWNERS=%s\n' "$KIND" "$NAME" "$OWN"
    for v in BUILD_KIND BUILD_SHA BUILD_TAG BUILD_STAMP; do printf '%s=%s\n' "$v" "${!v:-}"; done; } > "$OUT/build.env"
  LC_ALL=C sort -u "$PKGS" | grep . > "$OUT/packages.tsv"
  if [ -n "$INPUTS" ]; then LC_ALL=C sort "$INPUTS" > "$OUT/inputs.tsv"; else : > "$OUT/inputs.tsv"; fi
  REPRO_NO_OWNER=$((1-OWN)) python3 "$HERE/content-manifest.py" "$ROOT" > "$OUT/content.tsv"
  sha256sum "$OUT/content.tsv" | sed "s#  .*#  content.tsv#" > "$OUT/content.sha256"
  xz -9e -f -T1 "$OUT/content.tsv"
fi
if [ -n "$IMAGE" ]; then (cd "$(dirname "$IMAGE")" && sha256sum "$(basename "$IMAGE")") > "$OUT/image.sha256"; fi
echo "manifest written: $OUT"
