#!/bin/bash
# Flash-time time zone for a classroom-computer card (idea#208). The image ships with UTC; this writes the school's
# zone to the card's FAT boot partition as idea-timezone.txt, and idea-timezone.service applies it at every boot.
# Usage: set-card-timezone.sh --timezone Area/City --boot <mounted boot partition dir> [--zoneinfo DIR]
#        set-card-timezone.sh --check Area/City        (validate only; exit 0 = valid)
# The Engine's Flash step (agent-engine-dev, idea#303) does the same: validate, then write "<zone>\n" to idea-timezone.txt.
set -euo pipefail
ZI=/usr/share/zoneinfo; TZV=""; BOOT=""; CHECK=0
die(){ echo "set-card-timezone: $*" >&2; exit 2; }
while [ $# -gt 0 ]; do case "$1" in
  --timezone) TZV=${2:-}; shift 2;; --boot) BOOT=${2:-}; shift 2;; --zoneinfo) ZI=${2:-}; shift 2;;
  --check) TZV=${2:-}; CHECK=1; shift 2;; -h|--help) sed -n 2,6p "$0"; exit 0;; *) die "unknown argument: $1";; esac; done
[ -n "$TZV" ] || die "--timezone Area/City is required"
valid(){ printf '%s' "$1" | grep -Eqx '[A-Za-z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+){0,2}' && [ -f "$ZI/$1" ] \
  && head -c 4 "$ZI/$1" | grep -q '^TZif'; }
valid "$TZV" || die "not a tz database zone: '$TZV' (e.g. Africa/Harare, Africa/Lusaka, UTC)"
[ "$CHECK" = 1 ] && exit 0
[ -n "$BOOT" ] || die "--boot <mounted boot partition> is required"
[ -f "$BOOT/config.txt" ] || die "$BOOT does not look like a Pi boot partition (no config.txt)"
printf '%s\n' "$TZV" > "$BOOT/idea-timezone.txt.tmp" && mv "$BOOT/idea-timezone.txt.tmp" "$BOOT/idea-timezone.txt"
echo "wrote $BOOT/idea-timezone.txt: $TZV"
