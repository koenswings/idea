#!/usr/bin/env bash
# lock-apt-prefs.sh LOCK - print an apt preferences file pinning EVERY package in LOCK to its exact version (idea#322).
# Priority 1001 lets apt downgrade to the pinned version; dependencies resolve to pinned versions too.
set -euo pipefail
if ! { [ $# = 1 ] && [ -r "$1" ]; }; then echo "usage: lock-apt-prefs.sh LOCK" >&2; exit 2; fi
grep -v '^#' "$1" | awk -F'\t' '{printf "Package: %s\nPin: version %s\nPin-Priority: 1001\n\n", $1, $2}'
