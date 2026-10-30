#!/usr/bin/env bash
# archive-inputs.sh - keep a private copy of every build input of an image release (idea#322, "pin now, archive later").
# Usage:
#   archive-inputs.sh --out DIR [--inputs inputs.tsv]... [--file LABEL=PATH]... [--dir LABEL=DIR]... [--debs PKGLIST] [--offline]
#   archive-inputs.sh --verify DIR
# --inputs  rows "<label>\t<url-or-path>\t<sha256>\t<size>" as written by build.sh (repro_inputs_row): each is copied from the
#           local cache path when present (--cache-dir, default ~/.cache/idea-*-image), else downloaded, and must match sha256.
# --file    one extra file, e.g. engine-lock=engine.lock.json; --dir a whole directory as a tar, e.g. engine-cache=DIR.
# --debs    package list for archive-debs.py (client/engine .debs from the mirror); skipped with --offline.
# Writes DIR/<label>/<file>, DIR/ARCHIVE.tsv (label, file, sha256, size, source), DIR/SHA256SUMS and DIR/SIZE.
# The archive is kept on the bot computer / an IDEA disk, never in git or a GitHub release (it may hold large vendor files).
# Secrets: refuses any input (file or directory) containing a Tailscale auth key or a private key.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=""; VERIFY=""; OFFLINE=0; DEBS=""; INPUTS=(); FILES=(); DIRS=(); CACHES=()
while [ $# -gt 0 ]; do case "$1" in
  --out) OUT="$2"; shift 2;; --verify) VERIFY="$2"; shift 2;; --inputs) INPUTS+=("$2"); shift 2;;
  --file) FILES+=("$2"); shift 2;; --dir) DIRS+=("$2"); shift 2;; --debs) DEBS="$2"; shift 2;;
  --cache-dir) CACHES+=("$2"); shift 2;; --offline) OFFLINE=1; shift;;
  -h|--help) sed -n '2,13p' "$0"; exit 0;; *) echo "unknown arg $1" >&2; exit 2;; esac; done
sha(){ sha256sum "$1" | cut -d' ' -f1; }
if [ -n "$VERIFY" ]; then
  [ -f "$VERIFY/SHA256SUMS" ] || { echo "no SHA256SUMS in $VERIFY" >&2; exit 2; }
  (cd "$VERIFY" && sha256sum --quiet -c SHA256SUMS) || { echo "archive verify: FAILED" >&2; exit 1; }
  echo "archive verify: ok ($(wc -l < "$VERIFY/SHA256SUMS") files)"; exit 0; fi
[ -n "$OUT" ] || { echo "--out DIR or --verify DIR required" >&2; exit 2; }
[ ${#INPUTS[@]} -gt 0 ] || [ ${#FILES[@]} -gt 0 ] || [ ${#DIRS[@]} -gt 0 ] || [ -n "$DEBS" ] || { echo "nothing to archive" >&2; exit 2; }
[ ${#CACHES[@]} -gt 0 ] || CACHES=("$HOME/.cache/idea-engine-image" "$HOME/.cache/idea-client-image" "$HOME/.cache/idea-router-image")
PAT='tskey-(auth|client)-|-----BEGIN [A-Z ]*PRIVATE KEY-----'   # same strictness as the image secret scan
secret_check(){
  if grep -rIlE -- "$PAT" "$1" >/dev/null 2>&1; then echo "refusing $1: matches a secret pattern" >&2; exit 1; fi; }
mkdir -p "$OUT"; ROWS="$OUT/ARCHIVE.tsv.new"; : > "$ROWS"
put(){ # label src-file source-desc [want-sha]
  local l="$1" s="$2" d="$3" w="${4:-}" dst got
  [[ $l =~ ^[A-Za-z0-9._-]+$ ]] || { echo "bad label $l" >&2; exit 2; }
  secret_check "$s"; mkdir -p "$OUT/$l"; dst="$OUT/$l/$(basename "$s")"
  if ! { [ -f "$dst" ] && [ "$(sha "$dst")" = "$(sha "$s")" ]; }; then cp --preserve=timestamps "$s" "$dst.part"; mv "$dst.part" "$dst"; fi
  got=$(sha "$dst")
  if [ -n "$w" ] && [ "$got" != "$w" ]; then echo "sha256 mismatch for $l/$(basename "$s"): got $got expected $w" >&2; exit 1; fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$l" "$(basename "$s")" "$got" "$(stat -c %s "$dst")" "$d" >> "$ROWS"; }
for f in "${INPUTS[@]}"; do
  while IFS=$'\t' read -r l src want _size; do [ -n "${l:-}" ] || continue; case "$l" in \#*) continue;; esac
    b=$(basename "$src"); hit=""
    if [ -f "$src" ]; then hit="$src"; else for c in "${CACHES[@]}"; do [ -f "$c/$b" ] && { hit="$c/$b"; break; }; done; fi
    if [ -z "$hit" ]; then
      [ $OFFLINE = 0 ] || { echo "missing offline: $l $b (not in cache)" >&2; exit 1; }
      case "$src" in https://*) ;; *) echo "not found and not an https URL: $src" >&2; exit 1;; esac
      mkdir -p "$OUT/.dl"; curl -fL --retry 3 -o "$OUT/.dl/$b" "$src"; hit="$OUT/.dl/$b"; fi
    put "$l" "$hit" "$src" "$want"
  done < "$f"; done
for kv in "${FILES[@]}"; do l="${kv%%=*}"; p="${kv#*=}"; [ -f "$p" ] || { echo "no file $p" >&2; exit 1; }; put "$l" "$p" "file:$(basename "$p")"; done
for kv in "${DIRS[@]}"; do l="${kv%%=*}"; p="${kv#*=}"; [ -d "$p" ] || { echo "no dir $p" >&2; exit 1; }
  secret_check "$p"; mkdir -p "$OUT/.tar"; tb="$OUT/.tar/$l.tar"
  tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -C "$p" -cf "$tb" .; put "$l" "$tb" "dir:$(basename "$p")"; done
if [ -n "$DEBS" ]; then
  if [ $OFFLINE = 1 ]; then echo "skip debs (--offline)" >&2
  else python3 "$HERE/archive-debs.py" --manifest "$DEBS" --out "$OUT/debs"
    (cd "$OUT/debs" && sha256sum -- *.deb) | while read -r h n; do
      printf 'debs\t%s\t%s\t%s\t%s\n' "$n" "$h" "$(stat -c %s "$OUT/debs/$n")" "mirror" >> "$ROWS"; done; fi; fi
# clean temp copies (move, never delete in place: quarantine)
for t in .dl .tar; do [ -d "$OUT/$t" ] && mv "$OUT/$t" "$OUT/$t.quarantine-$(date +%Y%m%d-%H%M%S)"; done
LC_ALL=C sort -u "$ROWS" > "$OUT/ARCHIVE.tsv"; mv "$ROWS" "$OUT/.ARCHIVE.tsv.last"
awk -F'\t' '{print $3"  "$1"/"$2}' "$OUT/ARCHIVE.tsv" > "$OUT/SHA256SUMS"
awk -F'\t' '{s+=$4} END{print s+0}' "$OUT/ARCHIVE.tsv" > "$OUT/SIZE"
echo "archived $(wc -l < "$OUT/ARCHIVE.tsv") inputs, $(cat "$OUT/SIZE") bytes, in $OUT"
