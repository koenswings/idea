#!/usr/bin/env bash
# firstboot-units.sh ROOT - record (never fail on) the Engine's first-boot units in a mounted root fs (INTERFACE.md).
# idea-engine-identity arrives with engine#291; until then it is recorded as "absent", not an error.
set -uo pipefail
M="${1:?usage: firstboot-units.sh ROOT}"; W="$M/etc/systemd/system/multi-user.target.wants"
st(){ if [ -L "$W/$1" ] || [ -e "$W/$1" ]; then echo enabled; elif compgen -G "$M/etc/systemd/system/$1" >/dev/null || compgen -G "$M/lib/systemd/system/$1" >/dev/null; then echo installed-not-enabled; else echo absent; fi; }
for u in regenerate_ssh_host_keys.service idea-engine-firstboot.service pm2-pi.service docker.service ssh.service avahi-daemon.service tailscaled.service; do
  printf 'unit %-34s %s\n' "$u" "$(st "$u")"; done
if [ -e "$M/usr/local/sbin/idea-engine-identity" ]; then echo "idea-engine-identity: present"; else echo "idea-engine-identity: absent (expected until engine#291 is combined)"; fi
