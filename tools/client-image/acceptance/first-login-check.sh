#!/bin/bash
# First-login acceptance for a freshly flashed IDEA client (idea#202). Runs on the box; reaches the client over SSH
# as admin through a jump host (default idea03) with the TEST admin key. Needs sudo on the client: uses the documented
# convention password <account>911! via sudo -S (sent over the SSH stdin, never echoed or logged).
# Usage: first-login-check.sh CLIENT_IP [--jump idea03] [--key ~/.config/idea-client-image/test_admin_key] [--out DIR] [--wait 300]
# Output: PASS/FAIL per item, screenshot(s) in OUT. Exit 0 only if every item passed.
set -u
IP="${1:?client IP}"; shift; JUMP=idea03; KEY="$HOME/.config/idea-client-image/test_admin_key"; OUT="./first-login-$(date +%Y%m%d-%H%M%S)"; WAIT=300
while [ $# -gt 0 ]; do case "$1" in --jump) JUMP="$2"; shift 2;; --key) KEY="$2"; shift 2;; --out) OUT="$2"; shift 2;; --wait) WAIT="$2"; shift 2;; *) echo "bad arg $1" >&2; exit 2;; esac; done
mkdir -p "$OUT"; S=(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -i "$KEY" -J "$JUMP" "admin@$IP")
PW="admin911!"
REMOTE=$(cat <<'R'
set -u; IFS= read -r PW; W="$1"; fails=0; R=/tmp/idea-accept; rm -rf $R; mkdir -p $R
su_(){ printf '%s\n' "$PW" | sudo -S -p '' "$@"; }
pass(){ echo "PASS: $*"; }; fail(){ echo "FAIL: $*"; fails=$((fails+1)); }
LU=$(id -u learner); RT=/run/user/$LU
cat > $R/shot.py <<'PY2'
# One-frame screenshot of the GNOME (Wayland) session via org.gnome.Mutter.ScreenCast + GStreamer pipewiresrc.
import sys, subprocess
from gi.repository import Gio, GLib
out=sys.argv[1]; bus=Gio.bus_get_sync(Gio.BusType.SESSION); loop=GLib.MainLoop(); node={}
def call(path,iface,meth,args,rt=None):
    return bus.call_sync('org.gnome.Mutter.ScreenCast',path,iface,meth,args,GLib.VariantType(rt) if rt else None,0,10000,None)
sess=call('/org/gnome/Mutter/ScreenCast','org.gnome.Mutter.ScreenCast','CreateSession',GLib.Variant('(a{sv})',({},)),'(o)').unpack()[0]
strm=call(sess,'org.gnome.Mutter.ScreenCast.Session','RecordMonitor',GLib.Variant('(sa{sv})',('',{'cursor-mode':GLib.Variant('u',0)})),'(o)').unpack()[0]
def on(c,s,p,i,sig,params): node['id']=params.unpack()[0]; loop.quit()
bus.signal_subscribe('org.gnome.Mutter.ScreenCast','org.gnome.Mutter.ScreenCast.Stream','PipeWireStreamAdded',strm,None,0,on)
call(sess,'org.gnome.Mutter.ScreenCast.Session','Start',None)
GLib.timeout_add_seconds(10,loop.quit); loop.run()
rc=1
if 'id' in node:
    rc=subprocess.call(['timeout','20','gst-launch-1.0','-q','pipewiresrc','path=%d'%node['id'],'num-buffers=3','!','videoconvert','!','pngenc','snapshot=true','!','filesink','location='+out])
try: call(sess,'org.gnome.Mutter.ScreenCast.Session','Stop',None)
except Exception: pass
sys.exit(rc)
PY2
chmod 755 $R; chmod 644 $R/shot.py
asl(){ su_ -u learner env HOME=/home/learner XDG_RUNTIME_DIR=$RT WAYLAND_DISPLAY=wayland-0 XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=GNOME DBUS_SESSION_BUS_ADDRESS=unix:path=$RT/bus "$@"; }
su_ true 2>/dev/null && pass "sudo with <account>911! convention" || { fail "sudo -S failed"; echo "SUMMARY fails=$fails"; exit 1; }
# 1 learner autologin Wayland session
t=0; sid=""; while [ $t -lt "$W" ]; do
  for s in $(loginctl list-sessions --no-legend | awk '{print $1}'); do
    eval "$(loginctl show-session $s -p Name -p Type -p Class -p Active -p Service | sed 's/^/S_/')"
    [ "$S_Name" = learner ] && [ "$S_Type" = wayland ] && [ "$S_Class" = user ] && [ "$S_Active" = yes ] && sid=$s; done
  [ -n "$sid" ] && [ -S $RT/wayland-0 ] && [ -S $RT/bus ] && break; sleep 5; t=$((t+5)); done
[ -n "$sid" ] && pass "learner Wayland session $sid active (gdm autologin, ${t}s)" || fail "no active learner Wayland session after ${W}s"
sleep 20   # let first-login autostart run
# 2 no gnome-initial-setup
! dpkg -s gnome-initial-setup >/dev/null 2>&1 && ! pgrep -f '^/usr/libexec/gnome-initial-setup' >/dev/null && su_ test -f /home/learner/.config/gnome-initial-setup-done && pass "no gnome-initial-setup (not installed, not running, done-file)" || fail "gnome-initial-setup present/running"
# 3 desktop icon trusted + one-shot autostart disabled itself
v=$(asl gio info -a metadata::trusted /home/learner/Desktop/idea-console.desktop 2>&1 | awk '/metadata::trusted/{print $2}')
[ "$v" = true ] && pass "idea-console.desktop metadata::trusted=true" || fail "metadata::trusted='$v'"
su_ grep -qx 'Hidden=true' /home/learner/.config/autostart/idea-trust-desktop.desktop && pass "trust autostart ran and disabled itself (Hidden=true)" || fail "trust autostart not disabled"
# 4 screenshot of the desktop
shot(){ asl gdbus call --session --dest org.gnome.ScreenSaver --object-path /org/gnome/ScreenSaver --method org.gnome.ScreenSaver.SetActive false >/dev/null 2>&1; sleep 2; asl timeout 45 python3 $R/shot.py /tmp/idea-shot-$1.png >$R/shot.err 2>&1; [ -s /tmp/idea-shot-$1.png ] && su_ cp /tmp/idea-shot-$1.png $R/$1.png; }
shot desktop && pass "screenshot desktop.png" || fail "screenshot: $(tail -c 200 $R/shot.err)"
# 5 Chrome: launch the IDEA shortcut, then inspect profile
# launch the IDEA shortcut inside learner's real session environment (systemd --user scope, so Chrome outlives gtk-launch), as a click would
asl systemd-run --user --scope --quiet --collect gtk-launch idea-console >/dev/null 2>&1; t=0; while [ $t -lt 90 ] && ! su_ test -f /home/learner/.config/google-chrome/Default/Preferences; do sleep 5; t=$((t+5)); done; sleep 10
pgrep -u learner -af 'chrome' | grep -q -- '--password-store=basic' && pass "Chrome running with --password-store=basic" || fail "Chrome not running with --password-store=basic"
shot chrome && pass "screenshot chrome.png" || fail "chrome screenshot"
# 5b Chrome window really visible: chrome.png must differ clearly from desktop.png
cat > $R/winchk.py <<'PY3'
import sys,zlib,struct
def px(p):
    d=open(p,'rb').read(); i=8; idat=b''; w=h=0
    while i<len(d):
        n=struct.unpack('>I',d[i:i+4])[0]; t=d[i+4:i+8]; c=d[i+8:i+8+n]; i+=12+n
        if t==b'IHDR': w,h=struct.unpack('>II',c[:8])
        if t==b'IDAT': idat+=c
    return w,h,zlib.decompress(idat)
a=px(sys.argv[1]); b=px(sys.argv[2])
if a[:2]!=b[:2]: sys.exit(1)
x,y=a[2],b[2]; step=max(1,len(x)//200000); diff=sum(1 for k in range(0,min(len(x),len(y)),step) if abs(x[k]-y[k])>24)
frac=diff/(min(len(x),len(y))/step); print("   chrome window: %.1f%% of sampled bytes changed"%(100*frac)); sys.exit(0 if frac>0.10 else 1)
PY3
python3 $R/winchk.py $R/desktop.png $R/chrome.png && pass "Chrome window visible (chrome.png differs from desktop.png)" || fail "no visible Chrome window in chrome.png"
P=/home/learner/.config/google-chrome
cat > $R/chrome.py <<'PY'
import json,sys,os
p=sys.argv[1]; ok=True
def say(m): print("   chrome: "+m)
if not os.path.exists(p+"/First Run"): say("First Run sentinel missing"); ok=False
ls=json.load(open(p+"/Local State")); pr=json.load(open(p+"/Default/Preferences"))
sec=pr.get("default_search_provider_data",{}).get("template_url_data",{})
sc=json.dumps(pr.get("search_engine_choice",{}))+json.dumps(ls.get("search_engine_choice",{}))
say("search_engine_choice="+sc[:160])
if "pending" in sc.lower(): ok=False
pm=pr.get("credentials_enable_service"); say("credentials_enable_service=%s template=%s"%(pm,sec.get("url","(policy)")))
if pm is True: ok=False
sys.exit(0 if ok else 1)
PY
su_ python3 $R/chrome.py $P && pass "Chrome profile: First Run sentinel kept, no choice screen pending, password manager off" || fail "Chrome profile checks (see above)"
# 5c power cut: kill Chrome hard, mark the profile Crashed, run the login fix-up as the session would, relaunch:
#     the fix-up must restore exit_type=Normal and the relaunch must show no "Restore pages?" bubble (screenshot chrome-after-crash.png)
Pf=$P/Default/Preferences
su_ pkill -KILL -u learner -f chrome 2>/dev/null; sleep 3
su_ -u learner python3 -c "import json,sys;p=sys.argv[1];d=json.load(open(p));d.setdefault('profile',{}).update(exit_type='Crashed',exited_cleanly=False);json.dump(d,open(p,'w'))" $Pf
asl /usr/local/bin/idea-chrome-clean-exit
ex=$(su_ python3 -c "import json,sys;p=json.load(open(sys.argv[1]))['profile'];print(p.get('exit_type'),p.get('exited_cleanly'))" $Pf 2>&1)
ex=$(printf '%s\n' "$ex" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' | tail -n 1)   # strip blank lines / stray whitespace (sudo -S can emit a leading newline)
asl systemd-run --user --scope --quiet --collect gtk-launch idea-console >/dev/null 2>&1; sleep 20
shot chrome-after-crash
[ "$ex" = "Normal True" ] && pgrep -u learner -f chrome >/dev/null && [ -s $R/chrome-after-crash.png ] && pass "power-cut sim: fix-up set exit_type=Normal, Chrome relaunched (check chrome-after-crash.png: no Restore bubble)" || fail "power-cut sim: profile '$ex' after fix-up / Chrome or screenshot missing"
su_ pkill -TERM -u learner -f chrome 2>/dev/null; sleep 3; true
# 6 LibreOffice: first start as learner creates the user profile; the xcd values must win
asl timeout 90 soffice --headless --terminate_after_init >/dev/null 2>&1
X=/home/learner/.config/libreoffice/4/user/registrymodifications.xcu
[ -f /etc/libreoffice/registry/idea.xcd ] && pass "idea.xcd present" || fail "idea.xcd missing"
! su_ grep -qsE 'FirstStartWizardCompleted.*<value>false|ShowTipOfTheDay.*<value>true' $X && su_ grep -q 'FirstStartWizardCompleted' /etc/libreoffice/registry/idea.xcd && pass "LibreOffice: xcd sets wizard done/tips off; profile $(su_ test -f $X && echo present || echo 'not created by headless init') has no override" || fail "LibreOffice profile overrides the xcd"
# 7 SuperTuxKart: offline, player exists
su_ grep -q '<enable_internet value="2"' /home/learner/.config/supertuxkart/config-0.10/config.xml && su_ grep -q 'first-time="false"' /home/learner/.config/supertuxkart/config-0.10/players.xml && pass "SuperTuxKart: internet not allowed, player seeded, first-time done" || fail "SuperTuxKart seed"
chmod 644 $R/*.png 2>/dev/null; su_ chown admin $R/*.png 2>/dev/null
echo "SUMMARY fails=$fails"; exit $fails
R
)
{ printf '%s\n' "$PW"; } | "${S[@]}" "bash -c $(printf '%q' "$REMOTE") _ $WAIT" 2>&1 | tee "$OUT/first-login-check.txt"
rc=${PIPESTATUS[1]}
scp -q -o BatchMode=yes -i "$KEY" -J "$JUMP" "admin@$IP:/tmp/idea-accept/*.png" "$OUT/" 2>/dev/null && echo "screenshots: $(ls "$OUT"/*.png 2>/dev/null | tr '\n' ' ')"
grep -c '^PASS' "$OUT/first-login-check.txt" | sed 's/^/passed: /'; grep -c '^FAIL' "$OUT/first-login-check.txt" | sed 's/^/failed: /'
exit $rc
