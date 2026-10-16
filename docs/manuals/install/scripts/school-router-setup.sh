#!/bin/sh
# school-router-setup.sh - IDEA school router settings for OpenWrt 25.12 on a Cudy WR3000S v1
#
# What it does: LAN 10.42.0.1/24, two Wi-Fi networks in their own firewall zones
# ('IDEA' = students 10.42.1.0/24, 'IDEA-Teachers' = teachers 10.42.2.0/24),
# DHCP reservations for the two Pis (+ optional switch), and the firewall rules.
# It does NOT install Tailscale (see manual section 3.7).
#
# 1. Edit the values below on your laptop. NEVER commit real passwords to git.
# 2. Copy it:   scp -O school-router-setup.sh root@192.168.1.1:/tmp/
# 3. Run it:    ssh root@192.168.1.1 'sh /tmp/school-router-setup.sh'
#    The router reboots at the end and comes back on 10.42.0.1.
set -e

NET_PREFIX='10.42'                        # the same at every school (no school numbers)
PI1_MAC=''                                # Pi #1 eth0 MAC, e.g. 2c:cf:67:00:00:01 (empty = add later)
PI2_MAC=''                                # Pi #2 eth0 MAC
SWITCH_MAC=''                             # TL-SG105PE MAC from its label (optional)
STUDENT_WIFI_KEY='<IDEA-WIFI-PASSWORD>'           # min. 8 characters
TEACHER_WIFI_KEY='<IDEA-TEACHERS-WIFI-PASSWORD>'  # min. 8 characters, different from the student one
COUNTRY='ZW'                              # Wi-Fi regulatory country (Zimbabwe)

case "$STUDENT_WIFI_KEY$TEACHER_WIFI_KEY" in
  *'<'*) echo "ERROR: replace the <...> Wi-Fi password placeholders first"; exit 1 ;;
esac

# ---- system --------------------------------------------------------------
uci set system.@system[0].hostname="idea-router"
uci set system.@system[0].zonename='Africa/Harare'
uci set system.@system[0].timezone='CAT-2'

# ---- wired LAN (router, Pis, switch) -----------------------------------------
uci set network.lan.ipaddr="$NET_PREFIX.0.1"
uci set network.lan.netmask='255.255.255.0'
uci set dhcp.lan.start='100'              # pool .100-.199; .2-.99 kept for fixed devices
uci set dhcp.lan.limit='100'

# ---- the two Wi-Fi networks: bridge + interface + DHCP ------------------------
for Z in students teachers; do
  if [ "$Z" = students ]; then NET=1; else NET=2; fi
  uci -q delete network.${Z}_dev || true
  uci set network.${Z}_dev=device
  uci set network.${Z}_dev.type='bridge'
  uci set network.${Z}_dev.name="br-$Z"
  uci -q delete network.$Z || true
  uci set network.$Z=interface
  uci set network.$Z.proto='static'
  uci set network.$Z.device="br-$Z"
  uci set network.$Z.ipaddr="$NET_PREFIX.$NET.1"
  uci set network.$Z.netmask='255.255.255.0'
  uci -q delete dhcp.$Z || true
  uci set dhcp.$Z=dhcp
  uci set dhcp.$Z.interface="$Z"
  uci set dhcp.$Z.start='10'
  uci set dhcp.$Z.limit='240'
  uci set dhcp.$Z.leasetime='2h'
done

# ---- DHCP reservations (fixed addresses) --------------------------------------
add_host() {  # <section> <label> <mac> <ip>   (no name: the Pis name themselves, manual 5.6)
  [ -n "$3" ] || { echo "note: no MAC for $2 yet - add the reservation later (manual 5.5)"; return 0; }
  uci -q delete dhcp.$1 || true
  uci set dhcp.$1=host
  uci set dhcp.$1.mac="$3"
  uci set dhcp.$1.ip="$4"
}
add_host pi1    "Pi #1"    "$PI1_MAC"    "$NET_PREFIX.0.2"
add_host pi2    "Pi #2"    "$PI2_MAC"    "$NET_PREFIX.0.3"
add_host switch "switch"    "$SWITCH_MAC" "$NET_PREFIX.0.4"

# ---- Wi-Fi: same two SSIDs on 2.4 GHz (radio0) and 5 GHz (radio1) -------------
for R in 0 1; do
  uci set wireless.radio$R.country="$COUNTRY"
  uci set wireless.radio$R.disabled='0'
  uci -q delete wireless.default_radio$R || true
  uci -q delete wireless.idea_s$R || true
  uci set wireless.idea_s$R=wifi-iface
  uci set wireless.idea_s$R.device="radio$R"
  uci set wireless.idea_s$R.mode='ap'
  uci set wireless.idea_s$R.network='students'
  uci set wireless.idea_s$R.ssid='IDEA'
  uci set wireless.idea_s$R.encryption='psk2'
  uci set wireless.idea_s$R.key="$STUDENT_WIFI_KEY"
  uci set wireless.idea_s$R.isolate='1'          # students cannot reach each other's devices
  uci -q delete wireless.idea_t$R || true
  uci set wireless.idea_t$R=wifi-iface
  uci set wireless.idea_t$R.device="radio$R"
  uci set wireless.idea_t$R.mode='ap'
  uci set wireless.idea_t$R.network='teachers'
  uci set wireless.idea_t$R.ssid='IDEA-Teachers'
  uci set wireless.idea_t$R.encryption='psk2'
  uci set wireless.idea_t$R.key="$TEACHER_WIFI_KEY"
done

# ---- firewall zones -------------------------------------------------------------
for Z in students teachers; do
  uci -q delete firewall.$Z || true
  uci set firewall.$Z=zone
  uci set firewall.$Z.name="$Z"
  uci add_list firewall.$Z.network="$Z"
  uci set firewall.$Z.input='REJECT'      # router itself: only DHCP + DNS (rules below)
  uci set firewall.$Z.output='ACCEPT'
  uci set firewall.$Z.forward='REJECT'
  # NOTE: no 'forwarding' section to wan -> no internet, no outside DNS, no VPNs

  uci -q delete firewall.${Z}_dhcp || true
  uci set firewall.${Z}_dhcp=rule
  uci set firewall.${Z}_dhcp.name="Allow-DHCP-$Z"
  uci set firewall.${Z}_dhcp.src="$Z"
  uci set firewall.${Z}_dhcp.proto='udp'
  uci set firewall.${Z}_dhcp.dest_port='67'
  uci set firewall.${Z}_dhcp.family='ipv4'
  uci set firewall.${Z}_dhcp.target='ACCEPT'

  uci -q delete firewall.${Z}_dns || true
  uci set firewall.${Z}_dns=rule
  uci set firewall.${Z}_dns.name="Allow-DNS-$Z"
  uci set firewall.${Z}_dns.src="$Z"
  uci set firewall.${Z}_dns.proto='tcp udp'
  uci set firewall.${Z}_dns.dest_port='53'
  uci set firewall.${Z}_dns.target='ACCEPT'

  for P in 1 2; do
    S="${Z}_pi$P"
    uci -q delete firewall.$S || true
    uci set firewall.$S=rule
    uci set firewall.$S.name="Allow-$Z-to-Pi$P"
    uci set firewall.$S.src="$Z"
    uci set firewall.$S.dest='lan'
    uci set firewall.$S.dest_ip="$NET_PREFIX.0.$((P + 1))"
    uci set firewall.$S.proto='all'
    uci set firewall.$S.target='ACCEPT'
  done
done

# ---- the ONE switchable rule: teachers -> internet (starts OFF) -------------------
uci -q delete firewall.teachers_internet || true
uci set firewall.teachers_internet=rule
uci set firewall.teachers_internet.name='Teachers-Internet'
uci set firewall.teachers_internet.src='teachers'
uci set firewall.teachers_internet.dest='wan'
uci set firewall.teachers_internet.proto='all'
uci set firewall.teachers_internet.target='ACCEPT'
uci set firewall.teachers_internet.enabled='0'

uci commit
echo "Saved. Rebooting now. Reconnect your laptop cable to LAN2-LAN4 and open http://$NET_PREFIX.0.1"
reboot
