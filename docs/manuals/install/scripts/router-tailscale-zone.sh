#!/bin/sh
# router-tailscale-zone.sh - give tailscale0 its own firewall zone on the school router
# (OpenWrt wiki "Tailscale", Initial Setup). Admins on the tailnet may reach the router
# itself (LuCI/SSH); nothing is forwarded (no subnet routes, no exit node).
set -e
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
