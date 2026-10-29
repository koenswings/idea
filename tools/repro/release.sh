#!/usr/bin/env bash
# release.sh --type client|router --tag TAG [--prev TAG|none] [--root DIR] [--keep-worktree] [--proof] - Stage 1 release (idea#322).
# Builds the generic image from a clean checkout of TAG (git worktree, so the caller's tree is never used), makes its
# v2 image manifest (client: image-manifest.sh; router: the build's content.tsv.xz), compares it with the previous
# release and stores everything in a release folder on the bot computer. No GitHub Releases, no upload.
#   Release folder (default IDEA_RELEASES=~/idea-releases):  <root>/<type>/<tag>/
#     image file + .sha256, build-out/ (other build outputs), manifest/ (build manifest dir), image-manifest.tsv.xz (client), diff-vs-<prev>.txt,
#     RELEASE.txt (type, tag, commit, image, sha256, previous, diff result, built-at UTC)
#   <root>/<type>/LATEST holds the newest tag; --prev defaults to it (first release: --prev none).
# Client build cache (base image, Chrome .deb): <root>/.work-client. A release folder is never overwritten (exit 1). A failed build leaves nothing in <root>/<type>/<tag>.
# --proof: proof build of a tag that is NOT on origin/main (e.g. a throwaway branch merging open PRs). The release guard
#   is told to accept the tag's own commit (REPRO_MAIN_REF=<commit>, passed through sudo with `sudo env`), and the result
#   is stamped as a proof, never a release: stored in <root>/<type>/proof/<tag>/, image renamed *-proof*, RELEASE.txt
#   kind=proof + NOT-FOR-FIELD.txt, LATEST is never updated and a proof can never be used as --prev.
# Test hooks (env): RELEASE_BUILD_CMD (default: the type's build.sh), RELEASE_IMAGE_MANIFEST_CMD (default image-manifest.sh).
set -euo pipefail
R=$(cd "$(dirname "$0")" && pwd); REPO=$(git -C "$R" rev-parse --show-toplevel)
TYPE=""; TAG=""; PREV=""; PROOF=0; ROOT="${IDEA_RELEASES:-$HOME/idea-releases}"; KEEP=0
while [ $# -gt 0 ]; do case "$1" in
  --type) TYPE="$2"; shift 2;; --tag) TAG="$2"; shift 2;; --prev) PREV="$2"; shift 2;; --root) ROOT="$2"; shift 2;;
  --keep-worktree) KEEP=1; shift;; --proof) PROOF=1; shift;; *) echo "unknown arg $1" >&2; exit 2;; esac; done
case "$TYPE" in client|router) ;; *) echo "--type client|router required" >&2; exit 2;; esac
[ -n "$TAG" ] || { echo "--tag required" >&2; exit 2; }
[[ "$TAG" =~ ^[A-Za-z0-9._/-]+$ ]] && [[ "$TAG" != *..* ]] || { echo "bad tag name: $TAG" >&2; exit 2; }
COMMIT=$(git -C "$REPO" rev-parse -q --verify "refs/tags/$TAG^{commit}") || { echo "no such tag: $TAG" >&2; exit 1; }
SAFE=${TAG//\//_}; DEST="$ROOT/$TYPE/$SAFE"; KIND=release
[ "$SAFE" != proof ] || { echo "tag name 'proof' is reserved" >&2; exit 2; }
if [ "$PROOF" = 1 ]; then KIND=proof; DEST="$ROOT/$TYPE/proof/$SAFE"; fi
[ ! -e "$DEST" ] || { echo "release exists, not overwriting: $DEST" >&2; exit 1; }
[ -n "$PREV" ] || PREV=$(cat "$ROOT/$TYPE/LATEST" 2>/dev/null || echo none)
if [ "$PREV" != none ]; then PREV=${PREV//\//_}; [ "$PREV" != proof ] && [[ "$PREV" != proof_* ]] || { echo "a proof build cannot be --prev" >&2; exit 2; }; [ -f "$ROOT/$TYPE/$PREV/RELEASE.txt" ] || { echo "previous release not found: $ROOT/$TYPE/$PREV" >&2; exit 1; }; fi
mkdir -p "$ROOT/$TYPE" "$(dirname "$DEST")"; chmod 700 "$ROOT" 2>/dev/null || true
STAGE=$(mktemp -d "$ROOT/$TYPE/.stage-$SAFE.XXXXXX"); WT="$STAGE/src"
cleanup(){ rc=$?; set +e; [ "$KEEP" = 1 ] || git -C "$REPO" worktree remove --force "$WT" >/dev/null 2>&1
  [ $rc = 0 ] || { mv "$STAGE" "$STAGE.failed-$(date +%Y%m%d-%H%M%S)" 2>/dev/null; echo "release FAILED; work kept in $STAGE.failed-*" >&2; }; exit $rc; }
trap cleanup EXIT
git -C "$REPO" worktree add -q --detach "$WT" "$COMMIT"
OUT="$STAGE/out"; MAN="$STAGE/manifest"; mkdir -p "$OUT"
echo "== build $TYPE from $TAG ($COMMIT) [$KIND]"
MAINREF=(env -u REPRO_MAIN_REF);   # a normal release never inherits a caller REPRO_MAIN_REF
 [ "$PROOF" = 1 ] && MAINREF=(env "REPRO_MAIN_REF=$COMMIT")   # proof: guard accepts this commit; env survives sudo
if [ -n "${RELEASE_BUILD_CMD:-}" ]; then "${MAINREF[@]}" RELEASE_KIND="$KIND" RELEASE_SRC="$WT" RELEASE_OUT="$OUT" RELEASE_MANIFEST="$MAN" bash -c "$RELEASE_BUILD_CMD"
elif [ "$TYPE" = client ]; then sudo "${MAINREF[@]}" "$WT/tools/client-image/build.sh" --out "$OUT" --work "$ROOT/.work-client" --manifest-out "$MAN"
else "${MAINREF[@]}" MANIFEST_OUT="$MAN" WORK="${ROUTER_WORK:-$HOME/.cache/idea-router-ib}" "$WT/tools/router-image/build.sh" "$OUT"; fi
shopt -s nullglob
if [ "$TYPE" = client ]; then imgs=("$OUT"/idea-client-*.img.xz "$OUT"/idea-client-*.img); else imgs=("$OUT"/idea-router-*-squashfs-sysupgrade.bin); fi
shopt -u nullglob; IMG="${imgs[0]:-}"
[ -n "$IMG" ] && [ -f "$IMG" ] || { echo "build produced no $TYPE image in $OUT" >&2; exit 1; }
case "$(basename "$IMG")" in *-dev*) echo "refusing: dev-stamped image $(basename "$IMG") (tag must be a release build)" >&2; exit 1;; esac
if [ "$PROOF" = 1 ]; then b=$(basename "$IMG"); case "$b" in *-squashfs-*) nb="${b/-squashfs-/-proof-squashfs-}";; *.img.xz) nb="${b%.img.xz}-proof.img.xz";; *) nb="${b%.img}-proof.img";; esac
  mv "$IMG" "$(dirname "$IMG")/$nb"; IMG="$(dirname "$IMG")/$nb"; fi
(cd "$OUT" && sha256sum "$(basename "$IMG")" > "$(basename "$IMG").sha256"); SHA=$(cut -d' ' -f1 "$IMG.sha256")
# manifest of the new image + diff against the previous release
if [ "$TYPE" = client ]; then NEWM="$STAGE/image-manifest.tsv"; ${RELEASE_IMAGE_MANIFEST_CMD:-"$WT/tools/repro/image-manifest.sh"} "$IMG" "$NEWM"; xz -T0 -f "$NEWM"; NEWM="$NEWM.xz"
else NEWM="$MAN/content.tsv.xz"; [ -f "$NEWM" ] || { echo "router build wrote no $NEWM" >&2; exit 1; }; fi
DIFFRES="first release (no previous)"
if [ "$PREV" != none ]; then
  if [ "$TYPE" = client ]; then OLDM="$ROOT/$TYPE/$PREV/image-manifest.tsv.xz"; CMP=(python3 "$WT/tools/repro/compare-image-manifest.py" "$OLDM" "$NEWM")
  else OLDM="$ROOT/$TYPE/$PREV/manifest/content.tsv.xz"; CMP=("$WT/tools/repro/compare-manifest.sh" "$OLDM" "$NEWM"); fi
  set +e; "${CMP[@]}" > "$STAGE/diff-vs-$PREV.txt" 2>&1; rc=$?; set -e
  case $rc in 0) DIFFRES="identical content to $PREV";; 1) DIFFRES="differs from $PREV (review diff-vs-$PREV.txt)";;
    *) cat "$STAGE/diff-vs-$PREV.txt" >&2; echo "manifest compare failed (rc $rc)" >&2; exit 1;; esac
fi
mv "$IMG" "$IMG.sha256" "$STAGE/"
{ echo "kind=$KIND"; echo "type=$TYPE"; echo "tag=$TAG"; echo "commit=$COMMIT"; echo "image=$(basename "$IMG")"; echo "sha256=$SHA"
  echo "previous=$PREV"; echo "diff=$DIFFRES"; echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"; } > "$STAGE/RELEASE.txt"
[ "$KEEP" = 1 ] || git -C "$REPO" worktree remove --force "$WT"
mv "$OUT" "$STAGE/build-out"   # build logs + package list; nothing is deleted
[ "$PROOF" = 1 ] && echo "PROOF BUILD of $TAG ($COMMIT), not on origin/main: never flash to the field, never a release." > "$STAGE/NOT-FOR-FIELD.txt"
mv "$STAGE" "$DEST"; [ "$PROOF" = 1 ] || { echo "$SAFE" > "$ROOT/$TYPE/LATEST.tmp" && mv "$ROOT/$TYPE/LATEST.tmp" "$ROOT/$TYPE/LATEST"; }
trap - EXIT; echo "release: $DEST"; cat "$DEST/RELEASE.txt"
