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
asl(){ su_ -u learner env HOME=/home/learner XDG_RUNTIME_DIR=$RT WAYLAND_DISPLAY=wayland-0 DBUS_SESSION_BUS_ADDRESS=unix:path=$RT/bus "$@"; }
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
! dpkg -s gnome-initial-setup >/dev/null 2>&1 && ! pgrep -f gnome-initial-setup >/dev/null && [ -f /home/learner/.config/gnome-initial-setup-done ] && pass "no gnome-initial-setup (not installed, not running, done-file)" || fail "gnome-initial-setup present/running"
# 3 desktop icon trusted + one-shot autostart disabled itself
v=$(asl gio info -a metadata::trusted /home/learner/Desktop/idea-console.desktop 2>&1 | awk '/metadata::trusted/{print $2}')
[ "$v" = true ] && pass "idea-console.desktop metadata::trusted=true" || fail "metadata::trusted='$v'"
su_ grep -qx 'Hidden=true' /home/learner/.config/autostart/idea-trust-desktop.desktop && pass "trust autostart ran and disabled itself (Hidden=true)" || fail "trust autostart not disabled"
# 4 screenshot of the desktop
asl gnome-screenshot -f $R/desktop.png 2>$R/shot.err && pass "screenshot desktop.png" || fail "gnome-screenshot: $(head -c 200 $R/shot.err)"
# 5 Chrome: launch the IDEA shortcut, then inspect profile
asl gtk-launch idea-console >/dev/null 2>&1 & sleep 25
pgrep -u learner -af 'chrome' | grep -q -- '--password-store=basic' && pass "Chrome running with --password-store=basic" || fail "Chrome not running with --password-store=basic"
asl gnome-screenshot -f $R/chrome.png 2>>$R/shot.err && pass "screenshot chrome.png" || fail "chrome screenshot"
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
su_ pkill -u learner -f google-chrome 2>/dev/null; true
# 6 LibreOffice: first start as learner creates the user profile; the xcd values must win
asl timeout 90 soffice --headless --terminate_after_init >/dev/null 2>&1
X=/home/learner/.config/libreoffice/4/user/registrymodifications.xcu
[ -f /etc/libreoffice/registry/idea.xcd ] && pass "idea.xcd present" || fail "idea.xcd missing"
su_ test -f $X && ! su_ grep -qE 'FirstStartWizardCompleted.*<value>false|ShowTipOfTheDay.*<value>true' $X && pass "LibreOffice profile created; no wizard/tips override" || fail "LibreOffice registrymodifications missing or overrides the xcd"
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
