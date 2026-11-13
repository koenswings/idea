#!/usr/bin/env bash
# build-console-pi.sh — build the Console on a Pi with plain `pnpm build`.
#
# Since agent-console-dev#188, `pnpm build` writes into dist.new-<timestamp>/ and
# swaps it into dist/ only after a successful build, keeping one dist.prev for
# rollback (rename dist.prev to dist). Since agent-console-dev#189 (Console main
# cdda261), that build also copies dist/hidden-instances.json (idea#212,
# agent-console-dev#166) into the new tree. This script does not restore the
# hide list when the build already carried it.
#
# The script can still be pointed at an older Console (--dir, or a detached
# checkout of an older ref). Pool Consoles still run 6c15bcf (before #188/#189)
# and the kits are pinned to older versions, which do not copy the file. If
# hidden-instances.json was present before the build and is missing afterwards,
# this script restores the saved copy, byte for byte. No file before → no file
# after. Never overwrites a hide list the build already placed in dist/.
#
# Run on the Pi as pi, in the Console checkout (default /home/pi/idea/agents/agent-console-dev):
#   tools/fleet/build-console-pi.sh [--dir <console dir>]
#   or: ssh pi@<pi> 'bash -s' < tools/fleet/build-console-pi.sh
# Env: CONSOLE_BUILD_CMD (default "pnpm build"; tests use a fake).
# Exit: 0 ok · 1 build failed (hide list kept, or restored if it would otherwise
#   have been lost) · 2 usage · 3 restore/sha mismatch.
# Keep the fleet 75/65 °C rule: don't start a build on a Pi above 75 °C.
# Rollback of a bad Console tree: rename dist.prev to dist.
set -euo pipefail
DIR=/home/pi/idea/agents/agent-console-dev
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="${2:?--dir needs a path}"; shift 2 ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "usage: $0 [--dir <console dir>]" >&2; exit 2 ;;
  esac
done
cd "$DIR" || { echo "no Console dir $DIR" >&2; exit 2; }
F=dist/hidden-instances.json
BK="$(mktemp -d "${TMPDIR:-/tmp}/console-keep.XXXXXX")"
had=0; sum=""
if [ -f "$F" ]; then
  cp -p "$F" "$BK/hidden-instances.json"; had=1
  sum="$(sha256sum "$F" | cut -d' ' -f1)"
  echo "saved $F ($sum) to $BK"
fi
# Guard for pre-#189 Consoles: restore only if the new dist lacks a file the old one had.
keep_hide() {
  if [ -f "$F" ]; then
    [ "$had" = 1 ] && echo "build kept $F"
    return 0
  fi
  [ "$had" = 1 ] || return 0
  mkdir -p dist
  cp -p "$BK/hidden-instances.json" "$F"
  [ "$(sha256sum "$F" | cut -d' ' -f1)" = "$sum" ] || { echo "ERROR: $F restored but sha256 differs; backup kept in $BK" >&2; exit 3; }
  echo "restored $F (missing after the build; pre-#189 Console or failed wipe)"
}
rc=0
( eval "${CONSOLE_BUILD_CMD:-pnpm build}" ) || rc=$?   # subshell: an exit in the build cannot skip the guard
keep_hide
[ "$had" = 1 ] || echo "no $F before the build, none after"
rm -rf "$BK"
[ "$rc" = 0 ] || { echo "ERROR: Console build failed (exit $rc)" >&2; exit 1; }
echo "Console built in $DIR/dist"
