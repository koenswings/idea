#!/usr/bin/env bash
# shellcheck disable=SC2016  # the fake ssh/sudo bodies are literal
# enable-memory-cgroup.test.sh — offline tests for enable-memory-cgroup.sh (idea#518). Fake ssh (SSH_CMD runs the
# remote script locally), fake sudo and systemd-run in PATH, a temp cmdline.txt. No Pi, nothing rebooted.
set -uo pipefail
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; S="$D/enable-memory-cgroup.sh"
pass=0; fail=0
check() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS $n"; pass=$((pass+1)); else echo "FAIL $n"; fail=$((fail+1)); fi; }
nope() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "FAIL $n (expected failure)"; fail=$((fail+1)); else echo "PASS $n"; pass=$((pass+1)); fi; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT; mkdir -p "$W/bin"
printf '#!/usr/bin/env bash\n[ "$1" = -n ] && shift\nexec "$@"\n' > "$W/bin/sudo"
printf '#!/usr/bin/env bash\necho "$*" >> "%s/reboots"\n' "$W" > "$W/bin/systemd-run"
printf '#!/usr/bin/env bash\nshift; exec bash -c "$1"\n' > "$W/bin/fake-ssh"
chmod +x "$W/bin/"*; export PATH="$W/bin:$PATH" SSH_CMD="$W/bin/fake-ssh" CMDLINE_PATH="$W/cmdline.txt"
BASE='console=tty1 root=PARTUUID=abcd1234-02 rootfstype=ext4 fsck.repair=yes rootwait'
run() { "$S" testpi "$@"; }
nreb() { [ -f "$W/reboots" ] && wc -l < "$W/reboots" || echo 0; }
"$S" >/dev/null 2>&1; rc=$?; check "no host: usage (2)" test "$rc" = 2
"$S" testpi --now >/dev/null 2>&1; rc=$?; check "unknown arg: usage (2)" test "$rc" = 2
printf '%s' "$BASE" > "$CMDLINE_PATH"
check "dry run succeeds" run
check "dry run changes nothing" test "$(cat "$CMDLINE_PATH")" = "$BASE"
check "dry run never reboots" test "$(nreb)" = 0
check "dry run shows the new line" bash -c "'$S' testpi | grep -qx 'after:  $BASE cgroup_enable=memory'"
check "--yes succeeds" run --yes
check "--yes appends to the single line" test "$(cat "$CMDLINE_PATH")" = "$BASE cgroup_enable=memory"
check "--yes keeps exactly one line" test "$(grep -c '' "$CMDLINE_PATH")" = 1
check "--yes leaves a timestamped backup with the old line" bash -c "f=\$(ls '$W'/cmdline.txt.bak-* | head -1) && [ \"\$(cat \"\$f\")\" = '$BASE' ]"
check "--yes schedules exactly one reboot" test "$(nreb)" = 1
check "second --yes does not add the flag twice" bash -c "'$S' testpi --yes && [ \"\$(grep -o cgroup_enable=memory '$CMDLINE_PATH' | wc -l)\" = 1 ]"
check "second --yes makes no second backup" test "$(find "$W" -maxdepth 1 -name 'cmdline.txt.bak-*' | wc -l)" = 1
printf '%s\nextra\n' "$BASE" > "$CMDLINE_PATH"; nope "two-line cmdline.txt refused" run --yes
check "two-line cmdline.txt left untouched" test "$(grep -c '' "$CMDLINE_PATH")" = 2
echo 'console=tty1 rootwait' > "$CMDLINE_PATH"; nope "cmdline.txt without root= refused" run --yes
rm -f "$CMDLINE_PATH"; nope "missing cmdline.txt refused" run
printf '%s xcgroup_enable=memory\n' "$BASE" > "$CMDLINE_PATH"; check "look-alike token: exact flag still appended" bash -c "'$S' testpi --yes && grep -q ' cgroup_enable=memory\$' '$CMDLINE_PATH'"
echo "passed $pass, failed $fail"; [ "$fail" = 0 ]
