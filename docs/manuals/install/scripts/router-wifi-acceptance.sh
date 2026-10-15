#!/bin/sh
# router-wifi-acceptance.sh - idea#203 router half: can the Wi-Fi networks find the Engines?
#
# Client mode (laptop/Pi joined to IDEA or IDEA-Teachers; run once per SSID):
#   sh router-wifi-acceptance.sh client <STICKER> [<STICKER> ...]
#   Checks: Wi-Fi address in the right subnet; idea.local and each <STICKER>.local via
#   mDNS (avahi-resolve or getent/nss-mdns) and via router DNS (idea.local only);
#   HTTP GET of each name returns 2xx/3xx.
# Router mode (no Wi-Fi client at hand; run from a machine with ssh to the router):
#   sh router-wifi-acceptance.sh router [root@10.42.0.1]
#   Runs school-router-setup.sh-style checks on the router: avahi reflector up on the three
#   bridges, idea.local in dnsmasq, and an HTTP GET of every idea.local address from the router.
# Output: PASS/FAIL lines, last line "result: N failure(s)"; exit 0 only if all pass.
NET_PREFIX="${NET_PREFIX:-10.42}"
FAILS=0
ok()  { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; FAILS=$((FAILS + 1)); }
info() { echo "INFO  $1"; }

mdns_ip() {  # <name>.local -> first IPv4 via mDNS, empty if none
  if command -v avahi-resolve >/dev/null 2>&1; then
    timeout 6 avahi-resolve -4 -n "$1" 2>/dev/null | awk 'NR==1{print $2}'
  elif command -v dns-sd >/dev/null 2>&1; then          # macOS
    ( dns-sd -G v4 "$1" & P=$!; sleep 4; kill $P ) 2>/dev/null | awk '/Add/ && $6 ~ /^[0-9.]+$/ {print $6; exit}'
  else
    getent ahostsv4 "$1" 2>/dev/null | awk 'NR==1{print $1}'
  fi
}
dns_ip() {  # <name> <server> -> first IPv4 from the router DNS
  nslookup "$1" "$2" 2>/dev/null | awk '/^Name:/{n=1} n && /^Address/{sub(/^Address:? */,""); print; exit}'
}
http_ok() {  # <url> -> 0 if 2xx/3xx
  C=$(curl -s -o /dev/null -m 8 -w '%{http_code}' "$1" 2>/dev/null)
  case "$C" in 2??|3??) return 0 ;; *) return 1 ;; esac
}

client() {
  [ $# -ge 1 ] || { echo "usage: $0 client <STICKER> [...]"; exit 2; }
  MYIP=$(ip -4 -o addr show 2>/dev/null | awk '{split($4,a,"/"); print a[1]}' | grep "^$NET_PREFIX\." | head -1)
  [ -z "$MYIP" ] && MYIP=$(ifconfig 2>/dev/null | awk '/inet /{print $2}' | grep "^$NET_PREFIX\." | head -1)
  case "$MYIP" in
    "$NET_PREFIX".1.*) SSID=IDEA ;;
    "$NET_PREFIX".2.*) SSID=IDEA-Teachers ;;
    "$NET_PREFIX".0.*) SSID=wired-LAN ;;
    *) SSID=unknown ;;
  esac
  if [ "$SSID" = IDEA ] || [ "$SSID" = IDEA-Teachers ]; then ok "on $SSID ($MYIP)"; else bad "not on an IDEA Wi-Fi (ip=${MYIP:-none})"; fi
  GW="$NET_PREFIX.$(echo "$MYIP" | cut -d. -f3).1"
  for N in idea "$@"; do
    H="$N.local"
    IP=$(mdns_ip "$H")
    if [ -n "$IP" ]; then ok "[$SSID] mDNS $H -> $IP"; else bad "[$SSID] mDNS $H"; fi
    if [ "$N" = idea ]; then
      D=$(dns_ip "$H" "$GW")
      case "$D" in "$NET_PREFIX".0.[2-9]) ok "[$SSID] router DNS $H -> $D" ;; *) bad "[$SSID] router DNS $H (got '${D}')" ;; esac
    fi
    if http_ok "http://$H/"; then ok "[$SSID] HTTP GET http://$H/"
    elif [ -n "$IP" ] && http_ok "http://$IP/"; then bad "[$SSID] HTTP by name failed, by IP $IP worked (resolver issue)"
    else bad "[$SSID] HTTP GET http://$H/"; fi
  done
}

router() {
  T="${1:-root@$NET_PREFIX.0.1}"
  OUT=$(ssh -o BatchMode=yes -o ConnectTimeout=8 "$T" "NP=$NET_PREFIX; "'
    pidof avahi-daemon >/dev/null && echo "R avahi-running"
    grep -qx enable-reflector=yes /etc/avahi/avahi-daemon.conf && echo "R reflector-on"
    grep -qx allow-interfaces=br-lan,br-students,br-teachers /etc/avahi/avahi-daemon.conf && echo "R ifaces-ok"
    logread 2>/dev/null | grep avahi-daemon | grep -o "Joining mDNS multicast group on interface br-[a-z]*" | sort -u | sed "s/.* /J /"
    for z in students teachers; do [ "$(uci -q get firewall.${z}_mdns.dest_port)" = 5353 ] && echo "R fw-$z"; done
    for ip in $(awk "{print \$1}" /tmp/hosts/idea 2>/dev/null); do echo "H $ip"
      wget -q -T 6 -O /dev/null "http://$ip/" && echo "G $ip"; done
    nslookup idea.local 127.0.0.1 2>/dev/null | grep -q "Address.*$NP\.0\.[2-9]" && echo "R dns-ok"
  ' 2>&1) || { bad "ssh $T"; }
  for k in avahi-running reflector-on ifaces-ok fw-students fw-teachers dns-ok; do
    echo "$OUT" | grep -qx "R $k" && ok "router: $k" || bad "router: $k"
  done
  for b in br-lan br-students br-teachers; do
    echo "$OUT" | grep -qx "J $b" && ok "router: avahi joined $b" || info "router: no 'joined $b' in logread (log may have rotated)"
  done
  HS=$(echo "$OUT" | awk '$1=="H"{print $2}')
  [ -n "$HS" ] && ok "router: idea.local = $(echo $HS)" || bad "router: idea.local has no live Engine lease"
  for ip in $HS; do echo "$OUT" | grep -qx "G $ip" && ok "router: HTTP GET http://$ip/" || bad "router: HTTP GET http://$ip/"; done
}

case "$1" in
  client) shift; client "$@" ;;
  router) shift; router "$@" ;;
  *) sed -n '2,14p' "$0"; exit 2 ;;
esac
echo "result: $FAILS failure(s)"
[ "$FAILS" -eq 0 ]
