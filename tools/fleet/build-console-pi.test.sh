#!/usr/bin/env bash
# build-console-pi.test.sh — offline tests for hide-list restore around a Console build.
# Fakes cover a wipe (legacy / hostile build) and the agent-console-dev#188 swap
# (dist/ → dist.prev, new tree in dist/). Usage: tools/fleet/build-console-pi.test.sh
# (exit 0 = all pass)
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build-console-pi.sh"
pass=0; fail=0
check() { local n="$1"; shift; if "$@"; then echo "PASS $n"; pass=$((pass+1)); else echo "FAIL $n"; fail=$((fail+1)); fi; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
FAKE="rm -rf dist && mkdir dist && echo built > dist/index.html"
mk() { rm -rf "$W/c"; mkdir -p "$W/c/dist"; echo old > "$W/c/dist/index.html"; }

mk; printf '{"hidden":["fixture-1","missing-2"]}\n' > "$W/c/dist/hidden-instances.json"
cp "$W/c/dist/hidden-instances.json" "$W/orig.json"
out="$(CONSOLE_BUILD_CMD="$FAKE" TMPDIR="$W" "$S" --dir "$W/c" 2>&1)"; rc=$?
check "present: exit 0" [ "$rc" = 0 ]
check "present: build ran (dist rebuilt)" grep -qx built "$W/c/dist/index.html"
check "present: restored byte-identical" cmp -s "$W/orig.json" "$W/c/dist/hidden-instances.json"
check "present: temp backup cleaned" [ -z "$(ls -d "$W"/console-keep.* 2>/dev/null)" ]

mk
out="$(CONSOLE_BUILD_CMD="$FAKE" TMPDIR="$W" "$S" --dir "$W/c" 2>&1)"; rc=$?
check "absent: exit 0" [ "$rc" = 0 ]
check "absent: stays absent" [ ! -e "$W/c/dist/hidden-instances.json" ]
check "absent: says so" grep -q "none after" <<<"$out"

mk; printf '{"hidden":["x"]}' > "$W/c/dist/hidden-instances.json"; cp "$W/c/dist/hidden-instances.json" "$W/orig.json"
out="$(CONSOLE_BUILD_CMD='rm -rf dist; exit 7' TMPDIR="$W" "$S" --dir "$W/c" 2>&1)"; rc=$?
check "build fails: exit 1" [ "$rc" = 1 ]
check "build fails: hide list still restored" cmp -s "$W/orig.json" "$W/c/dist/hidden-instances.json"

out="$("$S" --bogus 2>&1)"; check "bad arg: exit 2" [ $? = 2 ]
out="$("$S" --dir "$W/nope" 2>&1)"; check "missing dir: exit 2" [ $? = 2 ]

# agent-console-dev#188: successful build moves dist/ aside to dist.prev and writes a new dist/.
SWAP='if [ -d dist ]; then rm -rf dist.prev; mv dist dist.prev; fi; mkdir dist; echo built > dist/index.html'
mk; printf '{"hidden":["fixture-1","missing-2"]}\n' > "$W/c/dist/hidden-instances.json"
cp "$W/c/dist/hidden-instances.json" "$W/orig.json"
echo old > "$W/c/dist/index.html"
out="$(CONSOLE_BUILD_CMD="$SWAP" TMPDIR="$W" "$S" --dir "$W/c" 2>&1)"; rc=$?
check "swap: exit 0" [ "$rc" = 0 ]
check "swap: new dist built" grep -qx built "$W/c/dist/index.html"
check "swap: hide list restored into new dist" cmp -s "$W/orig.json" "$W/c/dist/hidden-instances.json"
check "swap: previous tree kept as dist.prev" grep -qx old "$W/c/dist.prev/index.html"

# Failed pnpm build leaves live dist/ in place (#188); hide list must still be there.
mk; printf '{"hidden":["x"]}' > "$W/c/dist/hidden-instances.json"; cp "$W/c/dist/hidden-instances.json" "$W/orig.json"
echo old > "$W/c/dist/index.html"
out="$(CONSOLE_BUILD_CMD='exit 7' TMPDIR="$W" "$S" --dir "$W/c" 2>&1)"; rc=$?
check "fail no-wipe: exit 1" [ "$rc" = 1 ]
check "fail no-wipe: live dist left in place" grep -qx old "$W/c/dist/index.html"
check "fail no-wipe: hide list still present" cmp -s "$W/orig.json" "$W/c/dist/hidden-instances.json"

echo "pass=$pass fail=$fail"; [ "$fail" = 0 ]
