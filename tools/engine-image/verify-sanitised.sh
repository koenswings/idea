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
# Positive check (idea#453): the image must carry the baked fleet operator key list (root-owned, plain public keys
# only) or no operator can log in (sshd is key-only). Each non-comment line must be a bare key that ssh-keygen -lf accepts.
operator_keys_ok() {
  local f="$1/etc/ssh/idea_operator_keys/pi" line keys=0 t
  [ -f "$f" ] && [ ! -L "$f" ] && [ -s "$f" ] || return 1
  command -v ssh-keygen >/dev/null || { echo "ssh-keygen not found" >&2; return 1; }
  ! grep -q 'PRIVATE KEY' "$f" || return 1
  t=$(mktemp) || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in ''|'#'*) continue ;; esac
    [[ "$line" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com)\ [A-Za-z0-9+/]+=*(\ .*)?$ ]] || { rm -f "$t"; return 1; }
    printf '%s\n' "$line" > "$t"
    ssh-keygen -lf "$t" >/dev/null 2>&1 || { rm -f "$t"; return 1; }
    keys=$((keys+1))
  done < "$f"
  rm -f "$t"
  [ "$keys" -gt 0 ]
}
c "operator keys: /etc/ssh/idea_operator_keys/pi holds plain public keys" operator_keys_ok "$M"
# Positive check (idea#518): boot/firmware/cmdline.txt is one line and carries cgroup_enable=memory exactly once
# (kernel-cmdline.sh appends it); without it the firmware's cgroup_disable=memory leaves Docker without memory accounting.
cmdline_memcg_ok() {
  local f="$1/boot/firmware/cmdline.txt"
  [ -f "$f" ] && [ ! -L "$f" ] && [ "$(grep -c '' "$f")" = 1 ] || return 1
  [ "$(tr -s '[:blank:]' '\n' < "$f" | grep -cxF cgroup_enable=memory)" = 1 ]
}
c "kernel cmdline: cgroup_enable=memory once in boot/firmware/cmdline.txt" cmdline_memcg_ok "$M"
echo "verify-sanitised: $((n-fail))/$n passed"
[ "$fail" = 0 ]
