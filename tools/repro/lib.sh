#!/usr/bin/env bash
# shellcheck disable=SC2034  # BUILD_* are read by the scripts that source this file
# tools/repro/lib.sh - shared helpers for reproducible IDEA images (idea#322). Source it; nothing runs on load.
#   repro_release_guard REPO DEV   -> sets BUILD_KIND (release|dev), BUILD_SHA, BUILD_SHORT, BUILD_TAG, BUILD_STAMP
#   repro_fetch URL SHA256 DEST    -> download if missing, verify sha256; mismatch: file moved to DEST.bad, return 1
#   repro_inputs_row NAME URL FILE -> one inputs.tsv line (name, url, sha256, bytes)

# Release builds: clean tree, HEAD exactly at a tag, and HEAD contained in main (REPRO_MAIN_REF, default origin/main).
# DEV=1 (build.sh --dev) skips the checks and stamps the build "dev" (never a release, never for the field).
repro_release_guard() {
  local repo="$1" dev="${2:-0}" main="${REPRO_MAIN_REF:-origin/main}" dirty
  BUILD_SHA=$(git -C "$repo" rev-parse HEAD); BUILD_SHORT=$(git -C "$repo" rev-parse --short=7 HEAD)
  BUILD_TAG=$(git -C "$repo" describe --exact-match --tags HEAD 2>/dev/null || true)
  dirty=$(git -C "$repo" status --porcelain --untracked-files=normal 2>/dev/null | grep -v '^?? manifests/' || true)
  if [ "$dev" = 1 ]; then
    BUILD_KIND=dev; BUILD_STAMP="dev-$BUILD_SHORT$([ -n "$dirty" ] && echo -dirty)"
    echo "DEV BUILD: not a release (stamp $BUILD_STAMP); never ship it to the field" >&2; return 0; fi
  [ -z "$dirty" ] || { echo "refusing release build: working tree is dirty (use --dev for a dev build)" >&2; return 1; }
  [ -n "$BUILD_TAG" ] || { echo "refusing release build: HEAD $BUILD_SHORT is not tagged (use --dev for a dev build)" >&2; return 1; }
  git -C "$repo" merge-base --is-ancestor HEAD "$main" 2>/dev/null \
    || { echo "refusing release build: HEAD $BUILD_SHORT is not on $main (use --dev for a dev build)" >&2; return 1; }
  BUILD_KIND=release; BUILD_STAMP="$BUILD_TAG"
}

repro_sha() { sha256sum "$1" | cut -d' ' -f1; }

repro_fetch() {
  local url="$1" want="$2" dest="$3" got
  [ ${#want} = 64 ] || { echo "no sha256 pinned for $url" >&2; return 1; }
  if [ ! -f "$dest" ]; then
    curl -fL --retry 3 -o "$dest.part" "$url" || { rm -f "$dest.part"; echo "download failed: $url" >&2; return 1; }
    mv "$dest.part" "$dest"; fi
  got=$(repro_sha "$dest")
  if [ "$got" != "$want" ]; then mv -f "$dest" "$dest.bad"
    echo "sha256 mismatch for $(basename "$dest"): got $got expected $want (kept as $dest.bad)" >&2; return 1; fi
}

repro_inputs_row() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$(repro_sha "$3")" "$(stat -c %s "$3")"; }
