#!/usr/bin/env bash
# engine-image.test.sh - offline tests for tools/engine-image (idea#322 stage 5): sanitise.sh + verify-sanitised.sh on a
# fixture root tree, the pinned base, and build.sh argument checks. No root, no network, no image.
set -uo pipefail
R=$(cd "$(dirname "$0")/.." && pwd); REPO=$(git -C "$R" rev-parse --show-toplevel); EI="$REPO/tools/engine-image"
pass=0; fail=0
check() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS $n"; pass=$((pass+1)); else echo "FAIL $n"; fail=$((fail+1)); fi; }
nope() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "FAIL $n (expected failure)"; fail=$((fail+1)); else echo "PASS $n"; pass=$((pass+1)); fi; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
F="$W/root"; mkdir -p "$F/etc/ssh" "$F/var/lib/tailscale" "$F/var/lib/dbus" "$F/etc/tailscale" "$F/lib/systemd/system" "$F/etc/systemd/system/multi-user.target.wants" "$F/boot/firmware" "$F/home/pi"
echo 0123456789abcdef > "$F/etc/machine-id"; echo k > "$F/etc/ssh/ssh_host_ed25519_key"; echo k > "$F/etc/ssh/ssh_host_ed25519_key.pub"
echo s > "$F/var/lib/tailscale/tailscaled.state"; echo k > "$F/etc/tailscale/debug-authkey"; echo u > "$F/lib/systemd/system/regenerate_ssh_host_keys.service"
printf 'diskId: abc\nisHardwareId: true\nversion: 1\n' > "$F/META.yaml"; echo h > "$F/home/pi/.bash_history"
# idea#453: the baked operator key list (public keys only) is part of a good image, not identity
OPK="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP5pJ426w/HVTUBn4wIfxv4XGnRjoQnihRAavat+ww/p atlas-box@grok-bot"
mkdir -p "$F/etc/ssh/idea_operator_keys"; printf '# fleet operators\n%s\n' "$OPK" > "$F/etc/ssh/idea_operator_keys/pi"
# idea#518: stock Raspberry Pi OS cmdline.txt (one line, no trailing newline, no cgroup flag)
CLB='console=serial0,115200 console=tty1 root=PARTUUID=abcd1234-02 rootfstype=ext4 fsck.repair=yes rootwait'
printf '%s' "$CLB" > "$F/boot/firmware/cmdline.txt"
nope "verify fails on a dirty root" "$EI/verify-sanitised.sh" "$F"
check "verify reports every identity item + missing cmdline flag (7 FAIL lines)" bash -c "[ \"\$('$EI/verify-sanitised.sh' '$F' | grep -c '^FAIL')\" = 7 ]"
check "sanitise succeeds" "$EI/sanitise.sh" "$F"
nope "verify fails without cgroup_enable=memory in cmdline.txt" "$EI/verify-sanitised.sh" "$F"
check "kernel-cmdline.sh appends the configured flag" "$EI/kernel-cmdline.sh" "$F"
check "cmdline.txt: same single line + cgroup_enable=memory" bash -c "[ \"\$(cat '$F/boot/firmware/cmdline.txt')\" = '$CLB cgroup_enable=memory' ] && [ \"\$(grep -c '' '$F/boot/firmware/cmdline.txt')\" = 1 ]"
check "kernel-cmdline.sh is idempotent (flag once, one line)" bash -c "'$EI/kernel-cmdline.sh' '$F' | grep -q 'already present' && [ \"\$(grep -o cgroup_enable=memory '$F/boot/firmware/cmdline.txt' | wc -l)\" = 1 ] && [ \"\$(wc -l < '$F/boot/firmware/cmdline.txt')\" = 1 ]"
check "verify passes after sanitise" "$EI/verify-sanitised.sh" "$F"
check "sanitise is idempotent" bash -c "'$EI/sanitise.sh' '$F' && '$EI/verify-sanitised.sh' '$F'"
check "META.yaml keeps non-identity lines" grep -q '^version: 1$' "$F/META.yaml"
check "machine-id exists and is empty" bash -c "test -e '$F/etc/machine-id' && test ! -s '$F/etc/machine-id'"
F2="$W/root2"; mkdir -p "$F2/etc/systemd/system/sysinit.target.wants" "$F2/lib/systemd/system"; echo u > "$F2/lib/systemd/system/regenerate_ssh_host_keys.service"; ln -s /lib/systemd/system/regenerate_ssh_host_keys.service "$F2/etc/systemd/system/sysinit.target.wants/"
check "ssh regen via sysinit.target.wants recorded enabled" bash -c "'$EI/firstboot-units.sh' '$F2' | grep -q 'regenerate_ssh_host_keys.service *enabled'"
check "ssh regen via sysinit.target.wants passes our verify check" bash -c "'$EI/verify-sanitised.sh' '$F2' | grep -q '^ok   ssh host keys regenerate'"
check "ssh key regeneration enabled" test -L "$F/etc/systemd/system/multi-user.target.wants/regenerate_ssh_host_keys.service"
check "shell history removed" test ! -e "$F/home/pi/.bash_history"
check "sanitise keeps the operator key list" test -s "$F/etc/ssh/idea_operator_keys/pi"
check "verify reports the operator key check ok" bash -c "'$EI/verify-sanitised.sh' '$F' | grep -q '^ok   operator keys'"
# operator key list (idea#453): several keys ok; missing, empty, symlink, options, junk, private key all fail
K="$F/etc/ssh/idea_operator_keys/pi"; cp "$K" "$W/opk.good"
ssh-keygen -q -t ed25519 -N '' -C second@test -f "$W/second" >/dev/null 2>&1
cat "$W/second.pub" >> "$K"; check "verify passes with two operator keys" "$EI/verify-sanitised.sh" "$F"
rm -f "$K"; nope "verify fails without the operator key list" "$EI/verify-sanitised.sh" "$F"
: > "$K"; nope "verify fails on an empty operator key list" "$EI/verify-sanitised.sh" "$F"
echo '# only a comment' > "$K"; nope "verify fails on a comment-only operator key list" "$EI/verify-sanitised.sh" "$F"
rm -f "$K"; ln -s "$W/opk.good" "$K"; nope "verify fails on a symlinked operator key list" "$EI/verify-sanitised.sh" "$F"
rm -f "$K"; printf 'command="/bin/sh" %s\n' "$OPK" > "$K"; nope "verify fails on a key line with options" "$EI/verify-sanitised.sh" "$F"
printf '%s\nnot a key\n' "$OPK" > "$K"; nope "verify fails on a junk line" "$EI/verify-sanitised.sh" "$F"
printf '%s\nssh-ed25519 AAAAbroken x\n' "$OPK" > "$K"; nope "verify fails on a key ssh-keygen rejects" "$EI/verify-sanitised.sh" "$F"
{ echo "$OPK"; cat "$W/second"; } > "$K"; nope "verify fails on private key material" "$EI/verify-sanitised.sh" "$F"
cp "$W/opk.good" "$K"; check "verify passes again with the good list" "$EI/verify-sanitised.sh" "$F"
# idea#518 kernel cmdline: duplicates, two lines, symlink, look-alike tokens, explicit flags
CF="$F/boot/firmware/cmdline.txt"; cp "$CF" "$W/cl.good"
printf '%s cgroup_enable=memory cgroup_enable=memory\n' "$CLB" > "$CF"; nope "verify fails on a duplicated cgroup flag" "$EI/verify-sanitised.sh" "$F"
printf '%s\ncgroup_enable=memory\n' "$CLB" > "$CF"; nope "verify fails on a two-line cmdline.txt" "$EI/verify-sanitised.sh" "$F"
nope "kernel-cmdline.sh refuses a two-line cmdline.txt" "$EI/kernel-cmdline.sh" "$F"
rm -f "$CF"; ln -s "$W/cl.good" "$CF"; nope "kernel-cmdline.sh refuses a symlinked cmdline.txt" "$EI/kernel-cmdline.sh" "$F"
nope "verify fails on a symlinked cmdline.txt" "$EI/verify-sanitised.sh" "$F"
rm -f "$CF"; nope "kernel-cmdline.sh refuses a missing cmdline.txt" "$EI/kernel-cmdline.sh" "$F"
printf '%s xcgroup_enable=memory\n' "$CLB" > "$CF"; nope "verify does not accept a look-alike token" "$EI/verify-sanitised.sh" "$F"
check "kernel-cmdline.sh appends the exact token next to a look-alike" bash -c "'$EI/kernel-cmdline.sh' '$F' && '$EI/verify-sanitised.sh' '$F'"
printf '%s\n' "$CLB" > "$CF"; check "kernel-cmdline.sh takes explicit flags, each once" bash -c "'$EI/kernel-cmdline.sh' '$F' a=1 b=2 && '$EI/kernel-cmdline.sh' '$F' a=1 b=2 && [ \"\$(cat '$CF')\" = '$CLB a=1 b=2' ]"
nope "kernel-cmdline.sh refuses a flag with a space" "$EI/kernel-cmdline.sh" "$F" "a b"
cp "$W/cl.good" "$CF"; check "verify passes again with the good cmdline.txt" "$EI/verify-sanitised.sh" "$F"
check "build.sh appends the cmdline flag before our verify" bash -c "awk '/ENGINE_BUILD_CMD:-/{e=NR} /kernel-cmdline.sh\" \"\\\$MNT\"/{k=NR} /verify-sanitised.sh\" \"\\\$MNT\"/{v=NR} END{exit !(e && e<k && k<v)}' '$EI/build.sh'"
check "engine-image.conf appends cgroup_enable=memory" bash -c ". '$EI/engine-image.conf' && [[ \" \$KERNEL_CMDLINE_APPEND \" == *' cgroup_enable=memory '* ]]"
mkdir -p "$F/boot/firmware/idea-secrets"; nope "verify fails on a left idea-secrets dir" "$EI/verify-sanitised.sh" "$F"
nope "sanitise refuses a non-root dir" "$EI/sanitise.sh" "$W/nothing"
check "base pinned by URL + 64-hex sha256, Raspberry Pi OS Lite arm64" bash -c ". '$EI/engine-image.conf' && [[ \$BASE_SHA256 =~ ^[0-9a-f]{64}$ ]] && [[ \$BASE_URL == https://downloads.raspberrypi.com/raspios_lite_arm64/* ]] && [[ \$BASE_IMAGE == *-arm64-lite.img.xz ]]"
check "release-file limit is 2 GiB" bash -c ". '$EI/engine-image.conf' && [ \"\$RELEASE_FILE_LIMIT_BYTES\" = 2147483648 ]"
set +e; "$EI/build.sh" --out "$W/o" >/dev/null 2>&1; rc=$?; set -e
check "build.sh without --engine-src: usage error (2)" test "$rc" = 2
check "build.sh names images idea-engine-*, -dev only for --dev" bash -c "grep -q 'NAME=\"idea-engine-\$VER\"' '$EI/build.sh' && grep -q 'VER=\"\$VER-dev\"' '$EI/build.sh'"
check "build.sh runs our sanitise, verify and secret scan after the Engine step" bash -c "awk '/ENGINE_BUILD_CMD:-/{e=NR} /sanitise.sh\" \"\\\$MNT\"/{s=NR} /verify-sanitised.sh\" \"\\\$MNT\"/{v=NR} /scan-secrets.sh\" \"\\\$MNT\"/{c=NR} END{exit !(e && e<s && s<v && v<c)}' '$EI/build.sh'"
# engine-build.json parsing (Axle's shape: passed = named checks with no problems, failed = list of strings, total optional)
H=$(git -C "$REPO" rev-parse HEAD); LS=$(printf '%064d' 0)
printf '{"engine_commit":"%s","engine_version":"v","lock_sha256":"%s","verify":{"passed":9,"failed":[]}}' "$H" "$LS" > "$W/ok.json"
printf '{"engine_commit":"%s","engine_version":"v","lock_sha256":"%s","verify":{"passed":0,"failed":["/META.yaml present","pm2 runs as root"]}}' "$H" "$LS" > "$W/bad.json"
printf '{"engine_commit":"%s","verify":{"passed":0,"failed":["build did not finish"]}}' "$H" > "$W/unfinished.json"
check "engine report 9/9 accepted" "$EI/engine-report.sh" "$W/ok.json" "$REPO"
printf '{"engine_commit":"%s","engine_version":"v","lock_sha256":"%s","verify":{"passed":13,"failed":[]}}' "$H" "$LS" > "$W/ok13.json"
check "engine report 13 checks accepted (count not hardcoded)" "$EI/engine-report.sh" "$W/ok13.json" "$REPO"
printf '{"engine_commit":"%s","engine_version":"v","lock_sha256":"%s","verify":{"passed":13,"total":13,"failed":[]}}' "$H" "$LS" > "$W/tot.json"
check "engine report passed == total accepted" "$EI/engine-report.sh" "$W/tot.json" "$REPO"
printf '{"engine_commit":"%s","engine_version":"v","lock_sha256":"%s","verify":{"passed":12,"total":13,"failed":[]}}' "$H" "$LS" > "$W/short.json"
nope "engine report passed < total refused" "$EI/engine-report.sh" "$W/short.json" "$REPO"
printf '{"engine_commit":"%s","engine_version":"v","lock_sha256":"%s","verify":{"passed":11,"failed":["a","b"]}}' "$H" "$LS" > "$W/part.json"
nope "engine report with some checks failing refused" "$EI/engine-report.sh" "$W/part.json" "$REPO"
check "engine report failures printed one per line" bash -c "[ \"\$('$EI/engine-report.sh' '$W/bad.json' | grep -c '^engine verify FAIL:')\" = 2 ]"
nope "engine report with failures refused" "$EI/engine-report.sh" "$W/bad.json"
nope "'build did not finish' report refused" "$EI/engine-report.sh" "$W/unfinished.json"
nope "missing report refused" "$EI/engine-report.sh" "$W/none.json"
nope "report for another commit refused" "$EI/engine-report.sh" "$W/ok.json" "$W/engine-other"
git init -q "$W/engine-other"; git -C "$W/engine-other" -c user.name=t -c user.email=t@t commit -q --allow-empty -m x
nope "report commit must match the engine source" "$EI/engine-report.sh" "$W/ok.json" "$W/engine-other"
mkdir -p "$F/usr/local/sbin" "$F/var/spool/cron/crontabs"; check "identity hook absent is recorded, not an error" bash -c "'$EI/firstboot-units.sh' '$F' | grep -q 'root @reboot boot.sh: absent'"
install -m 755 /dev/null "$F/usr/local/sbin/idea-engine-identity"; echo '@reboot /home/pi/boot.sh > /home/pi/boot.out 2>&1' > "$F/var/spool/cron/crontabs/root"
check "identity via root @reboot boot.sh recorded" bash -c "o=\$('$EI/firstboot-units.sh' '$F'); grep -q 'idea-engine-identity: present 755' <<<\"\$o\" && grep -q 'root @reboot boot.sh: present' <<<\"\$o\""
check "first-boot units recorded; ssh key regeneration enabled" bash -c "'$EI/firstboot-units.sh' '$F' | grep -q 'regenerate_ssh_host_keys.service *enabled'"
echo "engine-image tests: $pass passed, $fail failed"; [ "$fail" = 0 ]
