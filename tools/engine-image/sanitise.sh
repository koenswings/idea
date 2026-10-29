#!/usr/bin/env bash
# sanitise.sh ROOT - remove device identity from a mounted Engine root fs (idea#322). Idempotent second pass after the
# Engine's own offline build (agent-engine-dev); verify-sanitised.sh checks the result.
set -euo pipefail
M="${1:?usage: sanitise.sh ROOT}"; [ -d "$M/etc" ] || { echo "not a root fs: $M" >&2; exit 2; }
: > "$M/etc/machine-id"; rm -f "$M/var/lib/dbus/machine-id"; ln -s /etc/machine-id "$M/var/lib/dbus/machine-id" 2>/dev/null || true
rm -f "$M"/etc/ssh/ssh_host_*
# regenerate host keys on first boot (Raspberry Pi OS ships regenerate_ssh_host_keys.service)
if [ -f "$M/lib/systemd/system/regenerate_ssh_host_keys.service" ]; then
  ln -sf /lib/systemd/system/regenerate_ssh_host_keys.service "$M/etc/systemd/system/multi-user.target.wants/regenerate_ssh_host_keys.service"; fi
if [ -d "$M/var/lib/tailscale" ]; then find "$M/var/lib/tailscale" -mindepth 1 -delete; fi
rm -f "$M/etc/tailscale/debug-authkey"
if [ -f "$M/META.yaml" ]; then sed -i '/^diskId:/d;/^isHardwareId:/d' "$M/META.yaml"; fi
rm -f "$M"/root/.bash_history "$M"/home/*/.bash_history
echo "sanitised: $M"
