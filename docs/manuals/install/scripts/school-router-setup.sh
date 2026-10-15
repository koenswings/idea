#!/bin/sh
# school-router-setup.sh - IDEA school router settings for OpenWrt 25.12 on a Cudy WR3000S v1
#
# What it does: LAN 10.42.0.1/24, two Wi-Fi networks in their own firewall zones
# ('IDEA' = students 10.42.1.0/24, 'IDEA-Teachers' = teachers 10.42.2.0/24),
# Engine addresses .2-.9 by DHCP vendor class 'idea-engine' (no MAC reservations),
# the switch at .10 (optional MAC), and the firewall rules.
# The pre-flashed IDEA router image (router image and flashing proposal, idea#209)
# already has all of this; use this script only to set up a router by hand.
# It does NOT install Tailscale (see manual Appendix D.2.7).
#
# 1. Edit the values below on your laptop. NEVER commit real passwords to git.
# 2. Copy it:   scp -O school-router-setup.sh root@192.168.1.1:/tmp/
# 3. Run it:    ssh root@192.168.1.1 'sh /tmp/school-router-setup.sh'
#    The router reboots at the end and comes back on 10.42.0.1.
# 4. Check it:  ssh root@10.42.0.1 'sh /tmp/school-router-setup.sh --check'
#    Read-only: prints PASS/FAIL per item, exit code 0 only if all pass.
#
# Options: --check (verify only, changes nothing)   --no-reboot (apply, commit, restart
# the services, but do not reboot). Running the script twice gives the same result.
set -e

MODE=apply; REBOOT=1
for A in "$@"; do
  case "$A" in
    --check) MODE=check ;;
    --no-reboot) REBOOT=0 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $A"; exit 2 ;;
  esac
done
R="${IDEA_ROOT:-}"                        # file root; only the unit test sets it

NET_PREFIX='10.42'                        # the same at every school (no school numbers)
SWITCH_MAC=''                             # TL-SG105PE MAC from its label (optional)
STUDENT_WIFI_KEY='idea911!'               # IDEA default (<name>911!); the school changes it later
TEACHER_WIFI_KEY='idea-teachers911!'      # IDEA default; the school changes it later
COUNTRY='ZW'                              # Wi-Fi regulatory country (Zimbabwe)

# ---- idea#203 router half: mDNS reflector + idea.local in DNS ---------------------
# Wired Engines announce idea.local (one holder) and <STICKER>.local by mDNS on the LAN.
# Multicast does not cross the router between br-lan, br-students and br-teachers, so
# avahi-daemon reflects mDNS between exactly those three bridges (never WAN/tailscale).
# umdns (named in the image proposal) answers for the router itself but cannot reflect,
# hence avahi. Fallback: dnsmasq answers idea.local with every live Engine lease
# (.2-.9), kept up to date by a DHCP hotplug script (image proposal 5.2).
MDNS_PKG='avahi-nodbus-daemon'
AVAHI_CONF="$R/etc/avahi/avahi-daemon.conf"
IDEA_HOSTS="$R/tmp/hosts/idea"
HOTPLUG="$R/etc/hotplug.d/dhcp/90-idea-local"

write_avahi_conf() {
  mkdir -p "$(dirname "$AVAHI_CONF")"
  cat > "$AVAHI_CONF" <<AVAHI
# IDEA (school-router-setup.sh): reflect mDNS between the wired LAN and the two Wi-Fi networks
[server]
use-ipv4=yes
use-ipv6=no
allow-interfaces=br-lan,br-students,br-teachers
deny-interfaces=wan,wan6,tailscale0
check-response-ttl=no
use-iff-running=no
ratelimit-interval-usec=1000000
ratelimit-burst=1000

[publish]
publish-addresses=yes
publish-hinfo=no
publish-workstation=no
publish-domain=yes

[reflector]
enable-reflector=yes
reflect-ipv=no

[rlimits]
rlimit-core=0
rlimit-data=4194304
rlimit-fsize=0
rlimit-nofile=768
rlimit-stack=4194304
rlimit-nproc=3
AVAHI
}

write_hotplug() {
  mkdir -p "$(dirname "$HOTPLUG")"
  cat > "$HOTPLUG" <<'HP'
#!/bin/sh
# IDEA: keep idea.local in the router DNS = every live Engine lease (.2-.9). idea#203/#209 5.2
LEASES="${IDEA_LEASES:-/tmp/dhcp.leases}"
OUT="${IDEA_HOSTS:-/tmp/hosts/idea}"
PREFIX="${IDEA_NET_PREFIX:-10.42}"
mkdir -p "$(dirname "$OUT")"
TMP="$OUT.new"
: > "$TMP"
[ -f "$LEASES" ] && while read -r _exp _mac ip _rest; do
  case "$ip" in "$PREFIX".0.[2-9]) ;; *) continue ;; esac
  [ "$ACTION" = remove ] && [ "$ip" = "$IPADDR" ] && continue
  echo "$ip idea.local" >> "$TMP"
done < "$LEASES"
# an 'add' can run before dnsmasq has written the lease file
if [ "$ACTION" = add ] || [ "$ACTION" = update ]; then
  case "$IPADDR" in "$PREFIX".0.[2-9])
    grep -q "^$IPADDR " "$TMP" || echo "$IPADDR idea.local" >> "$TMP" ;;
  esac
fi
sort -u "$TMP" -o "$TMP"
if ! cmp -s "$TMP" "$OUT"; then
  mv "$TMP" "$OUT"
  [ -n "$IDEA_NO_HUP" ] || killall -HUP dnsmasq 2>/dev/null || true
else
  rm -f "$TMP"
fi
HP
  chmod 755 "$HOTPLUG"
}

if [ "$MODE" = check ]; then
  FAILS=0
  ok()  { echo "PASS  $1"; }
  bad() { echo "FAIL  $1"; FAILS=$((FAILS + 1)); }
  t() { D="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$D"; else bad "$D"; fi; }
  t "lan is $NET_PREFIX.0.1"            [ "$(uci -q get network.lan.ipaddr)" = "$NET_PREFIX.0.1" ]
  t "students net $NET_PREFIX.1.1"      [ "$(uci -q get network.students.ipaddr)" = "$NET_PREFIX.1.1" ]
  t "teachers net $NET_PREFIX.2.1"      [ "$(uci -q get network.teachers.ipaddr)" = "$NET_PREFIX.2.1" ]
  t "SSID IDEA"                         [ "$(uci -q get wireless.idea_s0.ssid)" = IDEA ]
  t "SSID IDEA-Teachers"                [ "$(uci -q get wireless.idea_t0.ssid)" = IDEA-Teachers ]
  t "Engine vendor-class range"         grep -q '^dhcp-vendorclass=set:engine,idea-engine' "$R/etc/dnsmasq.conf"
  t "Teachers-Internet rule exists"     [ -n "$(uci -q get firewall.teachers_internet)" ]
  t "$MDNS_PKG installed"               sh -c "command -v avahi-daemon || [ -x '$R/usr/sbin/avahi-daemon' ]"
  t "reflector enabled"                 grep -qx 'enable-reflector=yes' "$AVAHI_CONF"
  t "reflector only on lan+wifi"        grep -qx 'allow-interfaces=br-lan,br-students,br-teachers' "$AVAHI_CONF"
  t "avahi enabled at boot"             sh -c "ls '$R'/etc/rc.d/S*avahi-daemon"
  t "avahi running"                     sh -c "pgrep -x avahi-daemon || pidof avahi-daemon"
  for Z in students teachers; do
    t "firewall: mDNS 5353 from $Z"     [ "$(uci -q get firewall.${Z}_mdns.dest_port)" = 5353 ]
  done
  t "idea.local hotplug script"         [ -x "$HOTPLUG" ]
  t "idea.local hosts file present"     [ -f "$IDEA_HOSTS" ]
  if [ -s "$IDEA_HOSTS" ]; then
    ok "idea.local -> $(awk '{printf "%s ", $1}' "$IDEA_HOSTS")"
    t "dnsmasq answers idea.local"      sh -c "nslookup idea.local 127.0.0.1 | grep -q 'Address.*$NET_PREFIX.0.[2-9]'"
  else
    echo "INFO  idea.local: no live Engine lease yet (expected with no Engine plugged in)"
  fi
  echo "check: $FAILS failure(s)"
  [ "$FAILS" -eq 0 ]; exit $?
fi


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

# ---- Engines: fixed range by DHCP vendor class, no MAC reservations -------------
# Each Engine sends vendor class 'idea-engine' and gets an address in .2-.9 (proposal 5.1).
sed -i '/# IDEA engines/,+2d' "$R/etc/dnsmasq.conf" 2>/dev/null || true
mkdir -p "$R/etc"; cat >> "$R/etc/dnsmasq.conf" <<DNSMASQ
# IDEA engines
dhcp-vendorclass=set:engine,idea-engine
dhcp-range=tag:engine,$NET_PREFIX.0.2,$NET_PREFIX.0.9,255.255.255.0,12h
DNSMASQ
uci -q delete dhcp.pi1 || true
uci -q delete dhcp.pi2 || true
if [ -n "$SWITCH_MAC" ]; then
  uci -q delete dhcp.switch || true
  uci set dhcp.switch=host
  uci set dhcp.switch.mac="$SWITCH_MAC"
  uci set dhcp.switch.ip="$NET_PREFIX.0.10"
fi

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

  S="${Z}_engines"
  uci -q delete firewall.${Z}_pi1 || true
  uci -q delete firewall.${Z}_pi2 || true
  uci -q delete firewall.$S || true
  uci set firewall.$S=rule
  uci set firewall.$S.name="Allow-$Z-to-Engines"
  uci set firewall.$S.src="$Z"
  uci set firewall.$S.dest='lan'
  uci add_list firewall.$S.dest_ip="$NET_PREFIX.0.0/29"   # .2-.7 (.0/.1 are not Engines)
  uci add_list firewall.$S.dest_ip="$NET_PREFIX.0.8/31"   # .8-.9; the switch at .10 stays closed
  uci set firewall.$S.proto='all'
  uci set firewall.$S.target='ACCEPT'
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

# ---- mDNS reflector (idea#203): avahi on br-lan + both Wi-Fi bridges -----------
if ! command -v avahi-daemon >/dev/null 2>&1 && [ -z "$R" ]; then
  echo "installing $MDNS_PKG (the router needs internet once; the IDEA image has it built in)"
  if command -v apk >/dev/null 2>&1; then apk update && apk add "$MDNS_PKG"
  else opkg update && opkg install "$MDNS_PKG"; fi
fi
write_avahi_conf
for Z in students teachers; do
  uci -q delete firewall.${Z}_mdns || true
  uci set firewall.${Z}_mdns=rule
  uci set firewall.${Z}_mdns.name="Allow-mDNS-$Z"
  uci set firewall.${Z}_mdns.src="$Z"
  uci set firewall.${Z}_mdns.proto='udp'
  uci set firewall.${Z}_mdns.dest_port='5353'
  uci set firewall.${Z}_mdns.family='ipv4'
  uci set firewall.${Z}_mdns.target='ACCEPT'
done

# ---- idea.local in the router DNS (fallback; image proposal 5.2) -------------------
write_hotplug
uci -q del_list dhcp.@dnsmasq[0].addnhosts='/tmp/hosts/idea' || true
uci add_list dhcp.@dnsmasq[0].addnhosts='/tmp/hosts/idea'
# .local is not 'local=' in dnsmasq, so it would be forwarded upstream; keep it on the router
uci -q del_list dhcp.@dnsmasq[0].local='/local/' || true
uci add_list dhcp.@dnsmasq[0].local='/local/'
ACTION=update IPADDR='' IDEA_HOSTS="$IDEA_HOSTS" IDEA_NET_PREFIX="$NET_PREFIX" IDEA_NO_HUP=1 sh "$HOTPLUG"

uci commit
if [ "$REBOOT" = 0 ]; then
  [ -n "$R" ] || { /etc/init.d/avahi-daemon enable; /etc/init.d/avahi-daemon restart
    /etc/init.d/network reload; /etc/init.d/firewall reload; /etc/init.d/dnsmasq restart; }
  echo "Saved (no reboot). Check: sh $0 --check"
  exit 0
fi
[ -n "$R" ] || /etc/init.d/avahi-daemon enable
echo "Saved. Rebooting now. Reconnect your laptop cable to LAN2-LAN4 and open http://$NET_PREFIX.0.1"
reboot
