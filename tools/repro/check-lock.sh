#!/usr/bin/env bash
# check-lock.sh TYPE LOCK INSTALLED - verify an image's installed package list equals its lock file (idea#322).
# LOCK: written by make-lock.sh (header type must equal TYPE, entry count must match the body).
# INSTALLED: package<TAB>version[<TAB>arch...] lines (dpkg-query / router packages.tsv).
# Exit 0 = exact match; 1 = mismatch or bad lock (short diff printed); 2 = usage error.
set -uo pipefail
[ $# = 3 ] || { echo "usage: check-lock.sh client|router LOCK INSTALLED" >&2; exit 2; }
TYPE=$1; LOCK=$2; INST=$3; D=$(cd "$(dirname "$0")" && pwd)
for f in "$LOCK" "$INST"; do [ -r "$f" ] || { echo "cannot read $f" >&2; exit 2; }; done
h=$(head -1 "$LOCK")
case "$h" in "# idea-lock v1 "*) ;; *) echo "not an idea lock file: $LOCK" >&2; exit 1;; esac
[[ " $h " == *" type=$TYPE "* ]] || { echo "lock type mismatch: want $TYPE, header: $h" >&2; exit 1; }
want=$(sed -n 's/.* entries=\([0-9]*\).*/\1/p' <<<"$h"); have=$(grep -vc '^#' "$LOCK")
[ "$want" = "$have" ] || { echo "lock body has $have entries, header says $want (edited by hand?)" >&2; exit 1; }
T=$(mktemp); trap 'rm -f "$T"' EXIT; cut -f1,2 "$INST" | grep -v '^#' > "$T"
"$D/compare-manifest.sh" "$LOCK" "$T" || { echo "LOCK MISMATCH ($TYPE): installed packages differ from $(basename "$LOCK")" >&2; exit 1; }
