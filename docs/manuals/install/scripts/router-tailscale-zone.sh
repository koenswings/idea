#!/bin/sh
# router-tailscale-zone.sh - give tailscale0 its own firewall zone on the school router
# (OpenWrt wiki "Tailscale", Initial Setup). Admins on the tailnet may reach the router
# itself (LuCI/SSH); nothing is forwarded (no subnet routes, no exit node).
#
# This script only sets the OpenWrt interface and zone. It does not install Tailscale
# or join the tailnet. Enrolment is tools/router-image/idea-router-enrol, which reads
# the fleet auth key from IDEA_FLEET_KEY or ~/.config/idea-router/fleet-authkey
# (mode 0600) and advertises tag:idea. No credentials belong in this file or in the repo.
#
# Usage: sh router-tailscale-zone.sh [--dry-run]
#   --dry-run  print the uci and service commands and exit 0; make no changes.
# The firstboot image copy (tools/router-image/build.sh) strips the init.d lines.
set -e

if [ "${1:-}" = "--dry-run" ]; then
	cat <<'DRY'
uci -q delete network.tailscale || true
uci set network.tailscale=interface
uci set network.tailscale.proto='none'
uci set network.tailscale.device='tailscale0'
uci -q delete firewall.tailscale || true
uci set firewall.tailscale=zone
uci set firewall.tailscale.name='tailscale'
uci add_list firewall.tailscale.network='tailscale'
uci set firewall.tailscale.input='ACCEPT'
uci set firewall.tailscale.output='ACCEPT'
uci set firewall.tailscale.forward='REJECT'
uci commit
/etc/init.d/network reload
/etc/init.d/firewall restart
DRY
	echo "dry-run: no changes"
	exit 0
fi
if [ "$#" -ne 0 ]; then
	echo "usage: $0 [--dry-run]" >&2
	exit 2
fi

uci -q delete network.tailscale || true
uci set network.tailscale=interface
uci set network.tailscale.proto='none'
uci set network.tailscale.device='tailscale0'
uci -q delete firewall.tailscale || true
uci set firewall.tailscale=zone
uci set firewall.tailscale.name='tailscale'
uci add_list firewall.tailscale.network='tailscale'
uci set firewall.tailscale.input='ACCEPT'
uci set firewall.tailscale.output='ACCEPT'
uci set firewall.tailscale.forward='REJECT'
uci commit
/etc/init.d/network reload
/etc/init.d/firewall restart
echo "tailscale zone ready"
