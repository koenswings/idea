#!/usr/bin/env bash
# lock.test.sh - offline tests for make-lock.sh, check-lock.sh, lock-apt-prefs.sh and the committed lock files (idea#322).
# No root, no network, no image build. Usage: tools/repro/tests/lock.test.sh   (exit 0 = all pass)
# shellcheck disable=SC2016  # literal $ in grep patterns
set -uo pipefail
R=$(cd "$(dirname "$0")/.." && pwd); REPO=$(cd "$R/../.." && pwd)
pass=0; fail=0
check() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS $n"; pass=$((pass+1)); else echo "FAIL $n"; fail=$((fail+1)); fi; }
nope() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "FAIL $n (expected failure)"; fail=$((fail+1)); else echo "PASS $n"; pass=$((pass+1)); fi; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
printf 'zlib\t1.3-1\nacl\t2.3.2-2\tarm64\n# comment\n' > "$W/pins.tsv"
check "make-lock writes a lock" "$R/make-lock.sh" client "$W/pins.tsv" "$W/c.lock"
check "lock header has type and count" grep -q '^# idea-lock v1 type=client source=pins.tsv source_sha256=[0-9a-f]\{64\} entries=2$' "$W/c.lock"
check "lock body sorted, two columns" bash -c "[ \"\$(grep -v '^#' '$W/c.lock')\" = \"\$(printf 'acl\t2.3.2-2\nzlib\t1.3-1')\" ]"
printf 'acl\t2.3.2-2\tarm64\nzlib\t1.3-1\tarm64\n' > "$W/inst.tsv"
check "check-lock: exact match passes" "$R/check-lock.sh" client "$W/c.lock" "$W/inst.tsv"
printf 'acl\t2.3.2-3\tarm64\nzlib\t1.3-1\tarm64\n' > "$W/inst2.tsv"
nope "check-lock: version drift fails" "$R/check-lock.sh" client "$W/c.lock" "$W/inst2.tsv"
printf 'acl\t2.3.2-2\tarm64\nzlib\t1.3-1\tarm64\ngdb\t17.1\tarm64\n' > "$W/inst3.tsv"
nope "check-lock: extra package fails" "$R/check-lock.sh" client "$W/c.lock" "$W/inst3.tsv"
printf 'acl\t2.3.2-2\tarm64\n' > "$W/inst4.tsv"
nope "check-lock: missing package fails" "$R/check-lock.sh" client "$W/c.lock" "$W/inst4.tsv"
nope "check-lock: wrong type fails" "$R/check-lock.sh" router "$W/c.lock" "$W/inst.tsv"
cp "$W/c.lock" "$W/edited.lock"; printf 'extra\t1\n' >> "$W/edited.lock"
nope "check-lock: hand-edited lock (count) fails" "$R/check-lock.sh" client "$W/edited.lock" "$W/inst.tsv"
nope "check-lock: non-lock file fails" "$R/check-lock.sh" client "$W/pins.tsv" "$W/inst.tsv"
printf 'acl\t1\nacl\t2\n' > "$W/dup.tsv"; nope "make-lock: duplicate package fails" "$R/make-lock.sh" client "$W/dup.tsv" "$W/x.lock"
printf 'acl\n' > "$W/bad.tsv"; nope "make-lock: malformed line fails" "$R/make-lock.sh" client "$W/bad.tsv" "$W/x.lock"
: > "$W/empty.tsv"; nope "make-lock: empty list fails" "$R/make-lock.sh" client "$W/empty.tsv" "$W/x.lock"
nope "make-lock: bad type fails" "$R/make-lock.sh" laptop "$W/pins.tsv" "$W/x.lock"
"$R/lock-apt-prefs.sh" "$W/c.lock" > "$W/pref"
check "apt prefs pin each package at 1001" bash -c "[ \$(grep -c 'Pin-Priority: 1001' '$W/pref') = 2 ] && grep -q 'Pin: version 2.3.2-2' '$W/pref'"
# committed locks are exactly what make-lock.sh makes from the committed sources
"$R/make-lock.sh" client "$REPO/tools/client-image/pins/s16-pins.tsv" "$W/client.lock" >/dev/null
check "client.lock = make-lock(s16-pins.tsv)" cmp "$W/client.lock" "$REPO/tools/client-image/client.lock"
check "client.lock has 1815 entries" bash -c "[ \$(grep -vc '^#' '$REPO/tools/client-image/client.lock') = 1815 ]"
"$R/make-lock.sh" router "$REPO/tools/router-image/package-pins.tsv" "$W/router.lock" >/dev/null
check "router.lock = make-lock(package-pins.tsv)" cmp "$W/router.lock" "$REPO/tools/router-image/router.lock"
# builds use the lock and fail on mismatch (static wiring checks; real builds need root + network)
check "client build.sh defaults to client.lock" grep -q 'PINS="$HERE/client.lock"' "$REPO/tools/client-image/build.sh"
check "client build.sh fails on lock mismatch" grep -q 'check-lock.sh" client .*exit 1' "$REPO/tools/client-image/build.sh"
check "client build: no dev-only warning path left" bash -c "! grep -q 'WARNING (dev build): installed packages differ' '$REPO/tools/client-image/build.sh'"
check "customise.sh installs apt lock preferences" grep -q 'preferences.d/00-idea-lock.pref' "$REPO/tools/client-image/customise.sh"
check "router build.sh fails on lock mismatch" grep -q 'check-lock.sh" router .*exit 1' "$REPO/tools/router-image/build.sh"
check "bash -n build scripts" bash -n "$REPO/tools/client-image/build.sh" "$REPO/tools/router-image/build.sh"
echo "lock tests: $pass passed, $fail failed"; [ "$fail" = 0 ]
