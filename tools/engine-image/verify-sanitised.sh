#!/usr/bin/env bash
# verify-sanitised.sh ROOT - fail (exit 1) if a mounted Engine root fs still carries device identity (idea#322).
# shellcheck disable=SC2016  # checks are single-quoted bash -c bodies; the root fs is passed as $0
set -uo pipefail
M="${1:?usage: verify-sanitised.sh ROOT}"; fail=0; n=0
c() { local d="$1"; shift; n=$((n+1)); if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=$((fail+1)); fi; }
c "machine-id empty" test ! -s "$M/etc/machine-id"
c "no ssh host keys" bash -c '! compgen -G "$0/etc/ssh/ssh_host_*" >/dev/null' "$M"
c "ssh host keys regenerate on first boot" bash -c 'compgen -G "$0/etc/systemd/system/*.wants/regenerate_ssh_host_keys.service" >/dev/null || compgen -G "$0/etc/systemd/system/*.requires/regenerate_ssh_host_keys.service" >/dev/null || compgen -G "$0/etc/systemd/system/*.wants/sshd-keygen.service" >/dev/null' "$M"
c "no tailscale state" bash -c '! [ -d "$0/var/lib/tailscale" ] || [ -z "$(ls -A "$0/var/lib/tailscale")" ]' "$M"
c "no tailscale debug authkey" test ! -e "$M/etc/tailscale/debug-authkey"
c "no /META.yaml diskId" bash -c '! grep -qE "^(diskId|isHardwareId):" "$0/META.yaml" 2>/dev/null' "$M"
c "no idea-secrets dir" bash -c '! compgen -G "$0/boot/firmware/idea-secrets*" >/dev/null' "$M"
echo "verify-sanitised: $((n-fail))/$n passed"
[ "$fail" = 0 ]
