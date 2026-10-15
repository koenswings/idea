#!/bin/bash
# Browser/start-page checks inside the rootfs (idea#203). Sourced by verify-image.sh; run alone by tests/chroot-check.sh.
# Needs BROWSER (chrome|chromium). Uses bad/ok from the caller if defined.
type bad >/dev/null 2>&1 || { fail=0; bad(){ echo "FAIL: $*"; fail=1; }; ok(){ echo "ok:   $*"; }; }
if [ "$BROWSER" = chrome ]; then PKG=google-chrome-stable; POL=/etc/opt/chrome/policies/managed/idea.json; BIN=google-chrome-stable
else PKG=chromium; POL=/etc/chromium/policies/managed/idea.json; BIN=chromium; fi
dpkg -s $PKG 2>/dev/null | grep -Eq '^Status: (install|hold) ok installed' && ok "$PKG installed (.deb)" || bad "$PKG not installed"
apt-mark showhold | grep -qx $PKG && ok "$PKG held" || bad "$PKG not held"
ls /etc/apt/sources.list.d/ 2>/dev/null | grep -qiE 'google|xtradeb' && bad "browser apt source still present" || ok "no Google/xtradeb apt source"
[ -e /etc/cron.daily/google-chrome ] && bad "google-chrome cron job present" || ok "no repo-re-adding cron job"
dpkg -s firefox >/dev/null 2>&1 && bad "firefox installed" || ok "no firefox"
python3 - "$POL" <<'P' && ok "policy $POL" || bad "policy $POL"
import json,sys
p=json.load(open(sys.argv[1])); u="file:///usr/share/idea/start.html"
assert p["HomepageLocation"]==u and p["RestoreOnStartup"]==4 and p["RestoreOnStartupURLs"]==[u]
assert set(p["LocalNetworkAccessAllowedForUrls"])=={"file://*","http://*.local"}
assert p["BrowserSignin"]==0 and p["SyncDisabled"] is True and p["ComponentUpdatesEnabled"] is False
assert p["PromotionalTabsEnabled"] is False and p["DefaultBrowserSettingEnabled"] is False
P
[ -s /usr/share/idea/start.html ] && ok "start.html" || bad "start.html missing"
[ -x /usr/local/sbin/idea-home-engine ] && systemctl is-enabled idea-home-engine.service >/dev/null 2>&1 && ok "home-engine boot unit enabled" || bad "home-engine boot unit"
[ ! -s /etc/idea/home-engine ] && ok "no Engine name baked in" || bad "/etc/idea/home-engine not empty in image"
d=/usr/share/applications/idea-console.desktop
grep -qx "Exec=$BIN --new-window file:///usr/share/idea/start.html" $d 2>/dev/null && [ -f /home/learner/Desktop/idea-console.desktop ] && ok "one IDEA shortcut (menu+desktop)" || bad "IDEA shortcut"
n=$(ls /usr/share/applications/idea-*.desktop /home/learner/Desktop/*.desktop 2>/dev/null | grep -vc idea-console.desktop)
[ "$n" = 0 ] && ok "no per-app icons" || bad "$n extra idea/desktop launchers"
[ -e /usr/local/bin/idea-open ] || [ -e /etc/idea-client/servers.conf ] && bad "old idea-open/servers.conf present" || ok "no idea-open, no servers.conf"
grep -rqsiE 'nextcloud|/go/' /usr/share/idea /usr/share/applications/idea-console.desktop "$POL" && bad "Nextcloud or /go link found" || ok "no Nextcloud or /go links"
