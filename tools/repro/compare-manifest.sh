#!/usr/bin/env bash
# compare-manifest.sh EXPECTED ACTUAL - compare two manifests (content.tsv[.xz] or packages.tsv), idea#322.
# Exit 0 if identical (after dropping '#' comment lines), 1 with a short diff (max 200 lines) if not, 2 on usage error.
set -uo pipefail
[ $# = 2 ] || { echo "usage: compare-manifest.sh EXPECTED ACTUAL" >&2; exit 2; }
rd() { case "$1" in *.xz) xz -dc "$1";; *) cat "$1";; esac | grep -v '^#' | LC_ALL=C sort; }
for f in "$1" "$2"; do [ -r "$f" ] || { echo "cannot read $f" >&2; exit 2; }; done
d=$(diff <(rd "$1") <(rd "$2")); rc=$?
if [ $rc = 0 ]; then echo "manifest match: $(basename "$2") = $(basename "$1") ($(rd "$1" | wc -l) entries)"; exit 0; fi
n=$(printf '%s\n' "$d" | grep -c '^[<>]')
echo "MANIFEST DIFFERS: $n changed lines (< expected  > actual)"; printf '%s\n' "$d" | grep '^[<>]' | head -200; exit 1
