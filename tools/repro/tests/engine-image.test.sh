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
nope "verify fails on a dirty root" "$EI/verify-sanitised.sh" "$F"
check "verify reports every identity item (6 FAIL lines)" bash -c "[ \"\$('$EI/verify-sanitised.sh' '$F' | grep -c '^FAIL')\" = 6 ]"
check "sanitise succeeds" "$EI/sanitise.sh" "$F"
check "verify passes after sanitise" "$EI/verify-sanitised.sh" "$F"
check "sanitise is idempotent" bash -c "'$EI/sanitise.sh' '$F' && '$EI/verify-sanitised.sh' '$F'"
check "META.yaml keeps non-identity lines" grep -q '^version: 1$' "$F/META.yaml"
check "machine-id exists and is empty" bash -c "test -e '$F/etc/machine-id' && test ! -s '$F/etc/machine-id'"
check "ssh key regeneration enabled" test -L "$F/etc/systemd/system/multi-user.target.wants/regenerate_ssh_host_keys.service"
check "shell history removed" test ! -e "$F/home/pi/.bash_history"
mkdir -p "$F/boot/firmware/idea-secrets"; nope "verify fails on a left idea-secrets dir" "$EI/verify-sanitised.sh" "$F"
nope "sanitise refuses a non-root dir" "$EI/sanitise.sh" "$W/nothing"
check "base pinned by URL + 64-hex sha256, Raspberry Pi OS Lite arm64" bash -c ". '$EI/engine-image.conf' && [[ \$BASE_SHA256 =~ ^[0-9a-f]{64}$ ]] && [[ \$BASE_URL == https://downloads.raspberrypi.com/raspios_lite_arm64/* ]] && [[ \$BASE_IMAGE == *-arm64-lite.img.xz ]]"
check "release-file limit is 2 GiB" bash -c ". '$EI/engine-image.conf' && [ \"\$RELEASE_FILE_LIMIT_BYTES\" = 2147483648 ]"
set +e; "$EI/build.sh" --out "$W/o" >/dev/null 2>&1; rc=$?; set -e
check "build.sh without --engine-src: usage error (2)" test "$rc" = 2
check "build.sh names images idea-engine-*, -dev only for --dev" bash -c "grep -q 'NAME=\"idea-engine-\$VER\"' '$EI/build.sh' && grep -q 'VER=\"\$VER-dev\"' '$EI/build.sh'"
check "build.sh runs our sanitise, verify and secret scan after the Engine step" bash -c "awk '/ENGINE_BUILD_CMD:-/{e=NR} /sanitise.sh\" \"\\\$MNT\"/{s=NR} /verify-sanitised.sh\" \"\\\$MNT\"/{v=NR} /scan-secrets.sh\" \"\\\$MNT\"/{c=NR} END{exit !(e && e<s && s<v && v<c)}' '$EI/build.sh'"
echo "engine-image tests: $pass passed, $fail failed"; [ "$fail" = 0 ]
