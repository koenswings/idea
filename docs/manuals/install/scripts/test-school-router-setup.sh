#!/bin/sh
# Unit test (no router needed): runs school-router-setup.sh against a fake root with a
# stub 'uci', twice (idempotence), then the idea.local hotplug script with fake leases.
set -u
D=$(cd "$(dirname "$0")" && pwd); W=$(mktemp -d); F=0
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/root"
cat > "$W/bin/uci" <<'U'
#!/bin/sh
DB="$UCI_DB"; touch "$DB"; [ "$1" = -q ] && shift
c=$1; shift; k=${1%%=*}; v=${1#*=}
case $c in
  set) awk -v p="$k=" 'index($0,p)!=1' "$DB" > "$DB.t"; mv "$DB.t" "$DB"; echo "$k=$v" >> "$DB" ;;
  add_list) echo "$k+=$v" >> "$DB" ;;
  del_list) grep -vxF "$k+=$v" "$DB" > "$DB.t"; mv "$DB.t" "$DB" ;;
  delete) grep -v "^$k[.=+]" "$DB" > "$DB.t"; mv "$DB.t" "$DB" ;;
  get) l=$(awk -v p="$k=" 'index($0,p)==1' "$DB" | tail -1); [ -n "$l" ] || exit 1; echo "${l#*=}" ;;
  commit) : ;;
esac
U
for c in reboot killall pgrep pidof nslookup; do printf '#!/bin/sh\nexit 1\n' > "$W/bin/$c"; done
chmod +x "$W/bin/"*
export PATH="$W/bin:$PATH" UCI_DB="$W/uci.db" IDEA_ROOT="$W/root"
mkdir -p "$W/root/usr/sbin" "$W/root/etc/rc.d"; : > "$W/root/usr/sbin/avahi-daemon"; chmod +x "$W/root/usr/sbin/avahi-daemon"
: > "$W/root/etc/rc.d/S61avahi-daemon"
a() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; F=$((F+1)); fi; }
sh "$D/school-router-setup.sh" --no-reboot > "$W/run1.log" 2>&1; a "apply run 1 exits 0" '[ $? -eq 0 ]'
cp "$W/uci.db" "$W/uci1"; cp "$W/root/etc/dnsmasq.conf" "$W/dm1"; cp "$W/root/etc/avahi/avahi-daemon.conf" "$W/av1"
sh "$D/school-router-setup.sh" --no-reboot > "$W/run2.log" 2>&1; a "apply run 2 exits 0" '[ $? -eq 0 ]'
sort "$W/uci1" > "$W/u1"; sort "$W/uci.db" > "$W/u2"
a "idempotent: uci state"  'cmp -s "$W/u1" "$W/u2"'
a "idempotent: dnsmasq.conf" 'cmp -s "$W/dm1" "$W/root/etc/dnsmasq.conf"'
a "idempotent: avahi conf"  'cmp -s "$W/av1" "$W/root/etc/avahi/avahi-daemon.conf"'
a "addnhosts listed once"   '[ "$(grep -c "addnhosts+=/tmp/hosts/idea" "$W/uci.db")" = 1 ]'
a "local=/local/ once"      '[ "$(grep -c "local+=/local/" "$W/uci.db")" = 1 ]'
a "reflector on"            'grep -qx enable-reflector=yes "$W/av1"'
a "only lan+wifi bridges"   'grep -qx allow-interfaces=br-lan,br-students,br-teachers "$W/av1"'
a "mDNS rule students"      'grep -qx "firewall.students_mdns.dest_port=5353" "$W/uci.db"'
a "mDNS rule teachers"      'grep -qx "firewall.teachers_mdns.dest_port=5353" "$W/uci.db"'
a "reboot not called"       '! grep -q Rebooting "$W/run2.log"'
H="$W/root/etc/hotplug.d/dhcp/90-idea-local"; O="$W/hosts"; L="$W/leases"
printf '1 aa 10.42.0.2 e1 *\n1 bb 10.42.0.3 e2 *\n1 cc 10.42.0.150 laptop *\n1 dd 10.42.1.20 phone *\n' > "$L"
hp() { env ACTION="$1" IPADDR="$2" IDEA_LEASES="$L" IDEA_HOSTS="$O" IDEA_NO_HUP=1 sh "$H"; }
hp update ''; a "two Engines -> two records" '[ "$(cat "$O")" = "$(printf "10.42.0.2 idea.local\n10.42.0.3 idea.local")" ]'
hp remove 10.42.0.3; a "remove drops Engine"     '[ "$(cat "$O")" = "10.42.0.2 idea.local" ]'
printf '1 aa 10.42.0.2 e1 *\n' > "$L"; hp add 10.42.0.4; a "add before lease file" 'grep -qx "10.42.0.4 idea.local" "$O"'
hp add 10.42.0.150; a "non-Engine ignored"      '! grep -q 150 "$O"'
: > "$L"; hp remove 10.42.0.2; a "no Engines -> empty" '[ ! -s "$O" ]'
sh "$D/school-router-setup.sh" --check > "$W/check.log" 2>&1; RC=$?
a "--check fails only on runtime items (avahi not running in test)" '[ $RC -ne 0 ] && [ "$(grep -c ^FAIL "$W/check.log")" = 1 ] && grep -q "FAIL  avahi running" "$W/check.log"'
sed -i 's/enable-reflector=yes/enable-reflector=no/' "$W/root/etc/avahi/avahi-daemon.conf"
sh "$D/school-router-setup.sh" --check > "$W/check2.log" 2>&1
a "--check catches reflector off" 'grep -q "FAIL  reflector enabled" "$W/check2.log"'
a "--check changes nothing"       '[ "$(grep -c . "$W/uci.db")" = "$(wc -l < "$W/u2")" ]'
echo "unit: $F failure(s)"; [ $F -eq 0 ]
