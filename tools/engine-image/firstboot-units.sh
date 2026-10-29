#!/usr/bin/env bash
# firstboot-units.sh ROOT - record (never fail on) the Engine's first-boot units in a mounted root fs (INTERFACE.md).
# Records units, cron and the engine#291 identity hook (idea-engine-identity via root @reboot cron); absent is recorded, not an error.
set -uo pipefail
M="${1:?usage: firstboot-units.sh ROOT}"; W="$M/etc/systemd/system/multi-user.target.wants"
st(){ if [ -L "$W/$1" ] || [ -e "$W/$1" ]; then echo enabled; elif compgen -G "$M/etc/systemd/system/$1" >/dev/null || compgen -G "$M/lib/systemd/system/$1" >/dev/null; then echo installed-not-enabled; else echo absent; fi; }
for u in regenerate_ssh_host_keys.service idea-engine-firstboot.service pm2-pi.service docker.service ssh.service avahi-daemon.service tailscaled.service cron.service; do
  printf 'unit %-34s %s\n' "$u" "$(st "$u")"; done
# idea-engine-identity (engine#291): /usr/local/sbin, 0755 root, run every boot by boot.sh from a root @reboot crontab line
I="$M/usr/local/sbin/idea-engine-identity"
if [ -e "$I" ]; then echo "idea-engine-identity: present $(stat -c '%a %U' "$I")"; else echo "idea-engine-identity: absent (engine build without engine#291)"; fi
if grep -qs '^@reboot .*boot\.sh' "$M/var/spool/cron/crontabs/root"; then echo "root @reboot boot.sh: present"; else echo "root @reboot boot.sh: absent"; fi
