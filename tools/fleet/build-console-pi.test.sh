#!/usr/bin/env bash
# build-console-pi.test.sh — offline tests for Console builds and the hide-list guard.
# #189-style fakes carry dist/hidden-instances.json into the new dist (no restore).
# Pre-#189 / wipe fakes drop the file so the guard restores it.
# Usage: tools/fleet/build-console-pi.test.sh  (exit 0 = all pass)
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build-console-pi.sh"
pass=0; fail=0
check() { local n="$1"; shift; if "$@"; then echo "PASS $n"; pass=$((pass+1)); else echo "FAIL $n"; fail=$((fail+1)); fi; }
check_not() { local n="$1"; shift; if ! "$@"; then echo "PASS $n"; pass=$((pass+1)); else echo "FAIL $n"; fail=$((fail+1)); fi; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
mk() { rm -rf "$W/c"; mkdir -p "$W/c/dist"; echo old > "$W/c/dist/index.html"; }
# agent-console-dev#189: swap dist/ → dist.prev and copy the hide list into the new tree.
CARRY='if [ -d dist ]; then rm -rf dist.prev; mv dist dist.prev; fi; mkdir dist; echo built > dist/index.html; if [ -f dist.prev/hidden-instances.json ]; then cp -p dist.prev/hidden-instances.json dist/hidden-instances.json; fi'
# Pre-#189 (#188-style) swap: new dist does not get the hide list.
SWAP='if [ -d dist ]; then rm -rf dist.prev; mv dist dist.prev; fi; mkdir dist; echo built > dist/index.html'
WIPE='rm -rf dist && mkdir dist && echo built > dist/index.html'

# --- #189: build carries the file; the script must not restore ---
mk; printf '{"hidden":["fixture-1","missing-2"]}\n' > "$W/c/dist/hidden-instances.json"
cp "$W/c/dist/hidden-instances.json" "$W/orig.json"
out="$(CONSOLE_BUILD_CMD="$CARRY" TMPDIR="$W" "$S" --dir "$W/c" 2>&1)"; rc=$?
check "carry: exit 0" [ "$rc" = 0 ]
check "carry: new dist built" grep -qx built "$W/c/dist/index.html"
check "carry: hide list survived without restore" cmp -s "$W/orig.json" "$W/c/dist/hidden-instances.json"
check "carry: previous tree kept as dist.prev" grep -qx old "$W/c/dist.prev/index.html"
check "carry: hide list also in dist.prev" cmp -s "$W/orig.json" "$W/c/dist.prev/hidden-instances.json"
check "carry: says build kept the file" grep -q "build kept" <<<"$out"
check_not "carry: did not restore" grep -q "restored" <<<"$out"
check "carry: temp backup cleaned" [ -z "$(ls -d "$W"/console-keep.* 2>/dev/null)" ]

mk
out="$(CONSOLE_BUILD_CMD="$CARRY" TMPDIR="$W" "$S" --dir "$W/c" 2>&1)"; rc=$?
check "carry absent: exit 0" [ "$rc" = 0 ]
check "carry absent: stays absent" [ ! -e "$W/c/dist/hidden-instances.json" ]
check "carry absent: says so" grep -q "none after" <<<"$out"

# Failed #188/#189 build leaves live dist/ in place; hide list stays, no restore needed.
mk; printf '{"hidden":["x"]}' > "$W/c/dist/hidden-instances.json"; cp "$W/c/dist/hidden-instances.json" "$W/orig.json"
echo old > "$W/c/dist/index.html"
out="$(CONSOLE_BUILD_CMD='exit 7' TMPDIR="$W" "$S" --dir "$W/c" 2>&1)"; rc=$?
check "fail no-wipe: exit 1" [ "$rc" = 1 ]
check "fail no-wipe: live dist left in place" grep -qx old "$W/c/dist/index.html"
check "fail no-wipe: hide list still present" cmp -s "$W/orig.json" "$W/c/dist/hidden-instances.json"
check "fail no-wipe: says build kept the file" grep -q "build kept" <<<"$out"
check_not "fail no-wipe: did not restore" grep -q "restored" <<<"$out"

# --- Guard: pre-#189 swap or a wipe drops the file; restore only then ---
mk; printf '{"hidden":["fixture-1","missing-2"]}\n' > "$W/c/dist/hidden-instances.json"
cp "$W/c/dist/hidden-instances.json" "$W/orig.json"
out="$(CONSOLE_BUILD_CMD="$SWAP" TMPDIR="$W" "$S" --dir "$W/c" 2>&1)"; rc=$?
check "pre-189 swap: exit 0" [ "$rc" = 0 ]
check "pre-189 swap: new dist built" grep -qx built "$W/c/dist/index.html"
check "pre-189 swap: guard restored hide list" cmp -s "$W/orig.json" "$W/c/dist/hidden-instances.json"
check "pre-189 swap: previous tree kept as dist.prev" grep -qx old "$W/c/dist.prev/index.html"
check "pre-189 swap: says restored" grep -q "restored" <<<"$out"
check_not "pre-189 swap: does not say build kept" grep -q "build kept" <<<"$out"

mk; printf '{"hidden":["fixture-1","missing-2"]}\n' > "$W/c/dist/hidden-instances.json"
cp "$W/c/dist/hidden-instances.json" "$W/orig.json"
out="$(CONSOLE_BUILD_CMD="$WIPE" TMPDIR="$W" "$S" --dir "$W/c" 2>&1)"; rc=$?
check "wipe: exit 0" [ "$rc" = 0 ]
check "wipe: dist rebuilt" grep -qx built "$W/c/dist/index.html"
check "wipe: guard restored hide list" cmp -s "$W/orig.json" "$W/c/dist/hidden-instances.json"
check "wipe: says restored" grep -q "restored" <<<"$out"

mk; printf '{"hidden":["x"]}' > "$W/c/dist/hidden-instances.json"; cp "$W/c/dist/hidden-instances.json" "$W/orig.json"
out="$(CONSOLE_BUILD_CMD='rm -rf dist; exit 7' TMPDIR="$W" "$S" --dir "$W/c" 2>&1)"; rc=$?
check "fail wipe: exit 1" [ "$rc" = 1 ]
check "fail wipe: guard restored hide list" cmp -s "$W/orig.json" "$W/c/dist/hidden-instances.json"
check "fail wipe: says restored" grep -q "restored" <<<"$out"

out="$("$S" --bogus 2>&1)"; check "bad arg: exit 2" [ $? = 2 ]
out="$("$S" --dir "$W/nope" 2>&1)"; check "missing dir: exit 2" [ $? = 2 ]

echo "pass=$pass fail=$fail"; [ "$fail" = 0 ]
