#!/bin/sh
# router-starlink-cgnat-exception.sh — narrow WAN DHCP exception before Tailscale's
# CGNAT drop (idea#209 D10). Starlink (and other CGNAT ISPs) put the DHCP server in
# 100.64.0.0/10; Tailscale's ts-input rule otherwise drops DHCPACK and the WAN lease
# fails to renew. Inserts UDP 67→68 accept on wan before the drop, and re-applies it
# from a hotplug script when interfaces come up (tailscaled rebuilds ts-input).
# Safe to run more than once. Source: tailscale/tailscale#12828.
set -e

HELPER=/usr/libexec/idea-cgnat-dhcp-exception.sh
HOTPLUG=/etc/hotplug.d/iface/90-idea-cgnat-dhcp

mkdir -p /usr/libexec /etc/hotplug.d/iface

cat > "$HELPER" << 'HELPER'
#!/bin/sh
# Accept WAN DHCP replies (UDP 67→68) before Tailscale's 100.64.0.0/10 drop in ts-input.
# No-op if nft or the chain is not ready yet.
command -v nft >/dev/null 2>&1 || exit 0
nft list chain ip filter ts-input >/dev/null 2>&1 || exit 0
if nft list chain ip filter ts-input 2>/dev/null | grep -q 'udp sport 67 udp dport 68'; then
	exit 0
fi
nft insert rule ip filter ts-input iifname "wan" udp sport 67 udp dport 68 counter accept
HELPER
chmod 755 "$HELPER"

cat > "$HOTPLUG" << EOF
#!/bin/sh
[ "\$ACTION" = ifup ] || exit 0
# Re-apply after wan or tailscale0 comes up; tailscaled rebuilds ts-input on start.
sleep 2
$HELPER
EOF
chmod 755 "$HOTPLUG"

"$HELPER"
echo "Starlink CGNAT DHCP exception installed (D10)"
