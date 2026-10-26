#!/bin/bash
# Static CI checks inside the built rootfs (proposal §12 "Build CI"). Exit non-zero on any failure.
set -u; fail=0; B=/root/.idea-build; . $B/client-image.conf; . $B/browser.env
npass=0; nfail=0; bad(){ echo "FAIL: $*"; fail=1; nfail=$((nfail+1)); }; ok(){ echo "ok:   $*"; npass=$((npass+1)); }
for p in $PACKAGES_OFFICE $PACKAGES_EDU $PACKAGES_GAMES $PACKAGES_SYSTEM; do
  dpkg -s "$p" >/dev/null 2>&1 || bad "package $p not installed"; done
. $B/verify-browser.sh
if [ "$BROWSER" = chrome ]; then BROWSER_DESKTOP_V=google-chrome.desktop; POL_V=/etc/opt/chrome/policies/managed/idea.json; INITPREF_V=/opt/google/chrome/initial_preferences; PROF_V=google-chrome
else BROWSER_DESKTOP_V=chromium.desktop; POL_V=/etc/chromium/policies/managed/idea.json; INITPREF_V=/etc/chromium/initial_preferences; PROF_V=chromium; fi
id -nG learner | tr ' ' '\n' | grep -qxE 'sudo|adm|lpadmin|admin' && bad "learner in a privileged group" || ok "learner has no admin groups"
[ -z "$(getent shadow learner | cut -d: -f2)" ] && ok "learner passwordless" || bad "learner has a password"
grep -rqs 'learner' /etc/sudoers /etc/sudoers.d && bad "learner in sudoers" || ok "learner not in sudoers"
id -nG admin | grep -qw sudo && ok "admin has sudo" || bad "admin lacks sudo"
grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config.d/10-idea.conf && grep -q '^AllowUsers admin' /etc/ssh/sshd_config.d/10-idea.conf && ok "ssh key-only, admin only" || bad "sshd config"
grep -q 'AutomaticLogin=learner' /etc/gdm3/custom.conf && ok "autologin learner" || bad "autologin"
for p in unattended-upgrades update-notifier gnome-software snap-store; do dpkg -s $p >/dev/null 2>&1 && bad "$p still installed"; done
for t in apt-daily.timer apt-daily-upgrade.timer snapd.refresh.timer; do
  s=$(systemctl is-enabled $t 2>/dev/null || true); [ "$s" = masked ] && ok "$t masked" || bad "$t is '$s'"; done
grep -q 'Unattended-Upgrade "0"' /etc/apt/apt.conf.d/99idea-no-updates && ok "APT::Periodic 0" || bad "APT periodic"
systemctl is-enabled idea-snap-hold.service >/dev/null 2>&1 && ok "snap hold on boot" || bad "snap hold service"
[ "$(stat -c %a /etc/NetworkManager/system-connections/IDEA.nmconnection)" = 600 ] && ok "wifi profile root-only" || bad "wifi profile perms"
grep -q '^overlayroot=' /etc/overlayroot.conf && ok "overlayroot present: $(grep '^overlayroot=' /etc/overlayroot.conf)" || bad "overlayroot conf"
[ ! -s /etc/machine-id ] && ok "machine-id blank" || bad "machine-id baked in"
ls /etc/ssh/ssh_host_* >/dev/null 2>&1 && bad "ssh host keys baked in" || ok "no ssh host keys"
# idea#208: no country time zone in the image; flash-time zone applied at boot
[ "$TIMEZONE" = UTC ] && [ "$(cat /etc/timezone 2>/dev/null)" = UTC ] && [ "$(readlink -f /etc/localtime)" = "$(readlink -f /usr/share/zoneinfo/UTC)" ] && ok "time zone default UTC (no country zone)" || bad "image time zone is '$(cat /etc/timezone 2>/dev/null)', want UTC"
[ ! -e /boot/firmware/idea-timezone.txt ] && ok "no idea-timezone.txt baked on boot partition" || bad "idea-timezone.txt baked into image"
[ -x /usr/local/sbin/idea-timezone ] && systemctl is-enabled idea-timezone.service >/dev/null 2>&1 && ok "idea-timezone boot unit enabled" || bad "idea-timezone boot unit"
# --- idea#202 fixes (2026-10-15) ---
# 1 config.txt: KMS overlay per model, not in [all]
python3 - /boot/firmware/config.txt <<'P' && ok "config.txt: [pi4] vc4-kms-v3d + [pi5] vc4-kms-v3d-pi5, none in [all], disable_fw_kms_setup=1" || bad "config.txt KMS sections"
import sys
sec="all"; seen={}
for l in open(sys.argv[1]):
    l=l.strip()
    if l.startswith("[") and l.endswith("]"): sec=l[1:-1]; continue
    if l.startswith("dtoverlay=vc4-kms-v3d"): seen.setdefault(sec,[]).append(l)
    if l=="disable_fw_kms_setup=1": seen["fwkms"]=1
assert "dtoverlay=vc4-kms-v3d" not in seen.get("all",[]), "kms in [all]"
assert seen.get("pi4")==["dtoverlay=vc4-kms-v3d"], seen.get("pi4")
assert seen.get("pi5")==["dtoverlay=vc4-kms-v3d-pi5"], seen.get("pi5")
assert seen.get("fwkms")==1
P
l=$(tail -n 30 /boot/firmware/config.txt | grep -E '^\[' | tail -1); [ "$l" = "[all]" ] && ok "config.txt ends in [all]" || bad "config.txt last section is '$l'"
[ -f /boot/firmware/overlays/vc4-kms-v3d-pi5.dtbo ] || [ -f /boot/firmware/current/overlays/vc4-kms-v3d-pi5.dtbo ] && ok "vc4-kms-v3d-pi5.dtbo present" || bad "pi5 overlay dtbo missing"
c=/boot/firmware/current/cmdline.txt; [ -f $c ] || c=/boot/firmware/cmdline.txt
grep -q 'root=LABEL=writable' $c && ok "cmdline stock (root=LABEL=writable$(grep -q 'quiet splash' $c && echo ', quiet splash kept'))" || bad "cmdline.txt"
# 2 curl
command -v curl >/dev/null && dpkg -s curl >/dev/null 2>&1 && ok "curl installed" || bad "curl missing"
# 3 no Firefox anywhere
ls /var/lib/snapd/seed/snaps/firefox_* /var/lib/snapd/snaps/firefox_* >/dev/null 2>&1 && bad "firefox snap file present" || ok "no firefox snap file"
grep -qsi firefox /var/lib/snapd/seed/seed.yaml && bad "firefox in snap seed.yaml" || ok "firefox not in seed.yaml"
m=$(awk '$1=="file:"{print $2}' /var/lib/snapd/seed/seed.yaml 2>/dev/null | while read -r x; do [ -f /var/lib/snapd/seed/snaps/$x ] || echo "$x"; done)
[ -z "$m" ] && ok "snap seed intact (every seed.yaml file present)" || bad "seed.yaml lists missing snaps:" $m
grep -lsx 'snap-name: firefox' /var/lib/snapd/seed/assertions/* >/dev/null 2>&1 && bad "firefox seed assertion" || ok "no firefox seed assertion"
ls /usr/share/applications/firefox*.desktop /usr/local/share/applications/firefox*.desktop /var/lib/snapd/desktop/applications/firefox* /home/learner/Desktop/firefox* >/dev/null 2>&1 && bad "firefox launcher present" || ok "no firefox launchers"
grep -rqsi firefox /etc/dconf/db/local.d/ && bad "firefox in dock/dconf" || ok "no firefox in dock (dconf)"
# 4 Chrome launchers + password manager
for d in /usr/share/applications/idea-console.desktop /home/learner/Desktop/idea-console.desktop /usr/local/share/applications/$BROWSER_DESKTOP_V; do
  n=$(grep -c '^Exec=' $d 2>/dev/null); m=$(grep '^Exec=' $d 2>/dev/null | grep -- '--password-store=basic' | grep -c -- '--ozone-platform-hint=auto')
  [ "${n:-0}" -gt 0 ] && [ "$n" = "$m" ] && ok "--password-store=basic + --ozone-platform-hint=auto on all $n Exec in $d" || bad "--password-store=basic/--ozone-platform-hint=auto missing in $d"; done
# 5 search engine, choice screen, first run
python3 - "$POL_V" "$INITPREF_V" <<'P' && ok "policy: PasswordManager off, Google fixed default search (no choice screen), promotions off; initial_preferences skip_first_run_ui" || bad "search/first-run policy"
import json,sys
p=json.load(open(sys.argv[1])); i=json.load(open(sys.argv[2]))
assert p["PasswordManagerEnabled"] is False and p["PromotionsEnabled"] is False
assert p["DefaultSearchProviderEnabled"] is True and p["DefaultSearchProviderName"]=="Google"
assert p["DefaultSearchProviderSearchURL"]=="https://www.google.com/search?q={searchTerms}"
d=i["distribution"]; assert d["skip_first_run_ui"] and d["suppress_first_run_default_browser_prompt"] and d["suppress_first_run_bubble"]
P
[ -f "/home/learner/.config/$PROF_V/First Run" ] && ok "learner browser 'First Run' sentinel" || bad "no 'First Run' sentinel"
# 6 trusted desktop icon (static part; the gio call runs at first login)
f=/home/learner/Desktop/idea-console.desktop
[ "$(stat -c '%U:%G %a' $f 2>/dev/null)" = "learner:learner 755" ] && ok "desktop icon learner:learner 755" || bad "desktop icon owner/mode: $(stat -c '%U:%G %a' $f 2>/dev/null)"
a=/home/learner/.config/autostart/idea-trust-desktop.desktop
grep -qx 'Exec=/usr/local/bin/idea-trust-desktop' $a 2>/dev/null && ! grep -q '^Hidden=true' $a && [ "$(stat -c %U $a)" = learner ] && ok "one-shot trust autostart in learner's autostart" || bad "trust autostart entry"
[ ! -e /etc/xdg/autostart/idea-trust-desktop.desktop ] && ok "no system-wide trust autostart" || bad "system-wide trust autostart still present"
t=/usr/local/bin/idea-trust-desktop
[ -x $t ] && grep -q 'metadata::trusted true' $t && grep -q 'Hidden=true' $t && sh -n $t && ok "trust script: gio set trusted + self-disable" || bad "trust script"
# 7 first-run wizards
python3 - /etc/libreoffice/registry/idea.xcd <<'P' && ok "LibreOffice idea.xcd: wizard done, no tips, no what's-new, Default toolbar" || bad "LibreOffice xcd"
import xml.etree.ElementTree as E,sys
O="{http://openoffice.org/2001/registry}"; r=E.parse(sys.argv[1]).getroot(); v={}
for pr in r.iter("prop"): v[pr.get(O+"name")]=pr.find("value").text
assert v["FirstStartWizardCompleted"]=="true" and v["ShowTipOfTheDay"]=="false" and v["WhatsNew"]=="false" and v["WhatsNewDialog"]=="false"
assert v["ActiveWriter"]=="Default" and v["ActiveCalc"]=="Default" and v["ActiveImpress"]=="Default"
P
ls /usr/lib/libreoffice/program/libupdchklo.so >/dev/null 2>&1 && bad "LibreOffice update-check module present" || ok "LibreOffice has no update-check module"
dpkg -s geogebra >/dev/null 2>&1 && bad "geogebra package installed (no first-run config yet)" || ok "GeoGebra not in image (offline web app on the Engine) - nothing to suppress"
dpkg -s gnome-initial-setup >/dev/null 2>&1 && bad "gnome-initial-setup installed" || ok "gnome-initial-setup removed"
for p in oem-config ubuntu-desktop-provision gnome-tour; do dpkg -s $p >/dev/null 2>&1 && bad "$p installed"; done; ok "no oem-config/desktop-provision/gnome-tour"
[ "$(cat /home/learner/.config/gnome-initial-setup-done 2>/dev/null)" = yes ] && ok "gnome-initial-setup-done for learner" || bad "gnome-initial-setup-done"
grep -q "^welcome-dialog-last-shown-version='999'" /etc/dconf/db/local.d/00-idea && [ -s /etc/dconf/db/local ] && ok "GNOME welcome tour off (dconf db compiled)" || bad "welcome-dialog dconf"
grep -q '^InitialSetupEnable=false' /etc/gdm3/custom.conf && ok "GDM InitialSetupEnable=false" || bad "GDM initial setup"
grep -qx 'isFirstRun=false' /home/learner/.config/gcompris-qt/gcompris-qt.conf 2>/dev/null && ok "GCompris first-run off" || bad "GCompris conf"
# 9 IDEA logo C icon (shortcut + dock)
python3 - /usr/share/icons/hicolor <<'P' && ok "IDEA logo C icon: Icon=idea-console (menu+desktop), svg + 256 + 48 png, icon cache" || bad "idea-console icon"
import struct,sys,os
h=sys.argv[1]
for d in ("/usr/share/applications/idea-console.desktop","/home/learner/Desktop/idea-console.desktop"):
    assert "Icon=idea-console" in open(d).read().splitlines()
assert "<svg" in open(h+"/scalable/apps/idea-console.svg").read()
for n in (256,48):
    b=open("%s/%dx%d/apps/idea-console.png"%(h,n,n),"rb").read(24); assert b[:8]==b"\x89PNG\r\n\x1a\n" and struct.unpack(">II",b[16:24])==(n,n)
assert os.path.getsize(h+"/icon-theme.cache")>0
P
# 10 SuperTuxKart first-run (internet question, create-player/first-time) off
for h in /home/learner /etc/skel; do d=$h/.config/supertuxkart/config-0.10
  grep -q '<stkconfig version="8"' $d/config.xml 2>/dev/null && grep -q '<enable_internet value="2" />' $d/config.xml && grep -q '<current player="Learner"/>' $d/players.xml && grep -q 'first-time="false"' $d/players.xml \
    && ok "SuperTuxKart seeded in $h (internet not allowed, player Learner, first-time done)" || bad "SuperTuxKart seed in $h"; done
[ "$(stat -c %U /home/learner/.config/supertuxkart/config-0.10/config.xml 2>/dev/null)" = learner ] && ok "STK config owned by learner" || bad "STK config owner"
dpkg-query -W -f='${Version}' supertuxkart 2>/dev/null | grep -q '^1\.5' && ok "SuperTuxKart 1.5 (config-0.10 layout)" || bad "SuperTuxKart version changed: re-check STK keys"
command -v gnome-screenshot >/dev/null && ok "gnome-screenshot present (acceptance)" || bad "gnome-screenshot missing"
# 8 admin local password = <account>911!, ssh still key-only, learner none
h=$(getent shadow admin | cut -d: -f2)
[ "$(perl -e 'print crypt($ARGV[0],$ARGV[1])' "${ADMIN_USER:-admin}911!" "$h")" = "$h" ] && case "$h" in '$6$'*) true;; *) false;; esac && ok "admin local password follows <account>911! (sha-512)" || bad "admin password hash"
# 11 reset-on-reboot (idea#202, 2026-10-16): overlay ON by default, armed once after first boot
FWI=/boot/firmware/current/initrd.img; LS=$(lsinitrd "$FWI" 2>/dev/null)
printf '%s\n' "$LS" | grep -q 'hooks/cmdline/50-parse-overlayroot.sh' && printf '%s\n' "$LS" | grep -q 'hooks/pre-pivot/10-mount-overlayfs.sh' && printf '%s\n' "$LS" | grep -q 'fs/overlayfs/overlay.ko' \
  && ok "boot initrd has overlayroot/overlayfs hooks + overlay.ko" || bad "boot initrd lacks overlay support ($FWI)"
printf '%s\n' "$LS" | grep -q 'rp1-fw.ko' && ok "boot initrd keeps stock drivers (rp1-fw)" || bad "boot initrd lost stock drivers"
grep -qw 'overlayroot=tmpfs' /boot/firmware/current/cmdline.txt && bad "overlay already on in cmdline (first boot must run on the real disk)" || ok "first boot runs without overlay (cmdline)"
[ ! -e /var/lib/idea-overlay-armed ] && ok "overlay not yet armed" || bad "idea-overlay-armed marker baked in"
if [ "${OVERLAY:-on}" = on ]; then systemctl is-enabled idea-overlay-arm.service >/dev/null 2>&1 && ok "idea-overlay-arm enabled (reset-on-reboot ON by default)" || bad "idea-overlay-arm not enabled"
else systemctl is-enabled idea-overlay-arm.service >/dev/null 2>&1 && bad "idea-overlay-arm enabled with OVERLAY=off" || ok "overlay off (OVERLAY=off)"; fi
[ -x /usr/local/sbin/idea-client-mode ] && /usr/local/sbin/idea-client-mode status 2>/dev/null | grep -q 'next boot: normal' && ok "idea-client-mode status works" || bad "idea-client-mode"
echo "verify: $npass passed, $nfail failed, $((npass+nfail)) total"
exit $fail
