#!/bin/bash
# Runs INSIDE the arm64 chroot (sourced by customise.sh, also used alone by tests/chroot-check.sh).
# Proposal idea#203 §1-§2: browser, managed policies, start page, home-Engine boot step, the one IDEA shortcut.
# Needs: B (staging dir), BROWSER (chrome|chromium), CHROME_DEB (when chrome).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
START_URL="file:///usr/share/idea/start.html"
case "$BROWSER" in
chrome)
  # official Google arm64 .deb, downloaded and sha-checked by build.sh; offline install, then Google's repo removed
  # and the package held: "updates off; a new tested image is the update".
  install -d /etc/default; echo 'repo_add_once="false"' > /etc/default/google-chrome   # stop the postinst/cron re-adding the repo
  apt-get install -y -q --no-install-recommends "$B/$CHROME_DEB"
  rm -f /etc/apt/sources.list.d/google-chrome.list /etc/apt/sources.list.d/google-chrome.sources /etc/cron.daily/google-chrome
  rm -f /etc/apt/trusted.gpg.d/google-chrome.gpg /usr/share/keyrings/google-chrome.gpg 2>/dev/null || true
  apt-mark hold google-chrome-stable >/dev/null
  BIN=google-chrome-stable; DESKTOP=google-chrome.desktop; POL=/etc/opt/chrome/policies/managed ;;
chromium)
  # FALLBACK (build.sh --browser chromium): community .deb from ppa:xtradeb/apps, pinned so only chromium* comes from it.
  install -d -m 755 /etc/apt/keyrings; cp $B/files/xtradeb-apps.asc /etc/apt/keyrings/
  . /etc/os-release
  echo "deb [signed-by=/etc/apt/keyrings/xtradeb-apps.asc] https://ppa.launchpadcontent.net/xtradeb/apps/ubuntu $VERSION_CODENAME main" > /etc/apt/sources.list.d/xtradeb-apps.list
  printf 'Package: *\nPin: release o=LP-PPA-xtradeb-apps\nPin-Priority: 1\n\nPackage: chromium*\nPin: release o=LP-PPA-xtradeb-apps\nPin-Priority: 1001\n' > /etc/apt/preferences.d/idea-chromium
  apt-get update -q; apt-get install -y -q --no-install-recommends chromium
  rm -f /etc/apt/sources.list.d/xtradeb-apps.list; apt-mark hold chromium >/dev/null
  BIN=chromium; DESKTOP=chromium.desktop; POL=/etc/chromium/policies/managed ;;
*) echo "unknown BROWSER=$BROWSER" >&2; exit 1;;
esac
# Chrome is the only browser: Firefox snap out of the seed (seed.yaml entry + .snap + assertion), any deb, any launcher
snap remove --purge firefox 2>/dev/null || true; rm -f /var/lib/snapd/seed/snaps/firefox_*.snap
if [ -f /var/lib/snapd/seed/seed.yaml ]; then python3 - /var/lib/snapd/seed/seed.yaml <<'P'
import sys,re
p=sys.argv[1]; s=open(p).read()
# drop the "- name: firefox" list item (any indent) with its indented keys; seed.yaml must not list a missing .snap
s=re.sub(r'(?m)^([ \t]*)- name: firefox\n(?:\1[ \t]+\S.*\n)*','',s); open(p,'w').write(s)
P
fi
grep -lsx "snap-name: firefox" /var/lib/snapd/seed/assertions/* 2>/dev/null | xargs -r rm -f || true
rm -f /var/lib/snapd/desktop/applications/firefox_*.desktop /usr/share/applications/firefox*.desktop /home/learner/Desktop/firefox*.desktop
apt-get purge -y -q firefox 2>/dev/null || true

install -d "$POL"
python3 - "$START_URL" > "$POL/idea.json" <<'P'
import json,sys
u=sys.argv[1]
print(json.dumps({
 "HomepageLocation":u,"HomepageIsNewTabPage":False,"ShowHomeButton":True,
 "RestoreOnStartup":4,"RestoreOnStartupURLs":[u],
 "LocalNetworkAccessAllowedForUrls":["file://*","http://*.local"],
 "BrowserSignin":0,"SyncDisabled":True,"SigninInterceptionEnabled":False,
 "PromotionalTabsEnabled":False,"DefaultBrowserSettingEnabled":False,"MetricsReportingEnabled":False,
 "PasswordManagerEnabled":False,"PromotionsEnabled":False,
 "DefaultSearchProviderEnabled":True,"DefaultSearchProviderName":"Google","DefaultSearchProviderKeyword":"google.com",
 "DefaultSearchProviderSearchURL":"https://www.google.com/search?q={searchTerms}",
 "DefaultSearchProviderSuggestURL":"https://www.google.com/complete/search?output=chrome&q={searchTerms}","ComponentUpdatesEnabled":False,"BackgroundModeEnabled":False,
 "PrivacySandboxPromptEnabled":False,"BookmarkBarEnabled":False},indent=1))
P
# first-run screen off (Chrome reads this next to its binary)
printf '{"distribution":{"skip_first_run_ui":true,"suppress_first_run_bubble":true,"suppress_first_run_default_browser_prompt":true,"make_chrome_default_for_user":true,"do_not_create_desktop_shortcut":true,"do_not_create_quick_launch_shortcut":true,"do_not_create_taskbar_shortcut":true},"browser":{"show_home_button":true,"check_default_browser":false},"sync_promo":{"show_on_first_run_allowed":false}}\n' \
  > "$( [ "$BROWSER" = chrome ] && echo /opt/google/chrome/initial_preferences || echo /etc/chromium/initial_preferences )"

# "First Run" sentinel in learner's profile: Chrome skips its whole first-run flow
PROF=$( [ "$BROWSER" = chrome ] && echo google-chrome || echo chromium )
install -d /home/learner/.config/$PROF; : > "/home/learner/.config/$PROF/First Run"
# default .desktop override (first in XDG_DATA_DIRS): every Exec gets --password-store=basic (no keyring prompt on autologin)
# and --ozone-platform-hint=auto (native Wayland on GNOME, X11 where only X11 runs; Pi 400 + Pi 500)
install -d /usr/local/share/applications
sed -E "s#^(Exec=[^ ]+)#\\1 --ozone-platform-hint=auto --password-store=basic#" /usr/share/applications/$DESKTOP > /usr/local/share/applications/$DESKTOP

# no "Restore pages?" bubble after a power cut: mark the profile cleanly exited at every login (idea#202)
install -m 755 $B/files/idea-chrome-clean-exit /usr/local/bin/
install -d /etc/xdg/autostart; install -m 644 $B/files/idea-chrome-clean-exit.desktop /etc/xdg/autostart/

# start page + home-Engine boot step (name comes from the card, never from the image)
install -d /usr/share/idea /etc/idea
install -m 644 $B/files/idea/start.html /usr/share/idea/start.html
install -m 755 $B/files/idea-home-engine /usr/local/sbin/idea-home-engine
cp $B/files/idea-home-engine.service /etc/systemd/system/; systemctl enable idea-home-engine.service
: > /etc/idea/home-engine; echo 'window.IDEA_HOME_ENGINE = "";' > /etc/idea/home-engine.js

# the ONE shortcut: app menu + learner desktop; no per-app icons, no /go, no Nextcloud links
# IDEA logo C (Koen's pick, idea#202 #9) as the shortcut/dock icon "idea-console"
H=/usr/share/icons/hicolor; install -d $H/scalable/apps $H/256x256/apps $H/48x48/apps
install -m 644 $B/files/idea-logo/idea-console.svg $H/scalable/apps/idea-console.svg
install -m 644 $B/files/idea-logo/idea-console-256.png $H/256x256/apps/idea-console.png
install -m 644 $B/files/idea-logo/idea-console-48.png $H/48x48/apps/idea-console.png
cp $B/files/idea.svg $H/scalable/apps/idea.svg   # legacy name kept
gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
sed "s/@BROWSER@/$BIN --ozone-platform-hint=auto --password-store=basic/" $B/files/idea-console.desktop > /usr/share/applications/idea-console.desktop
rm -f /usr/share/applications/idea-{nextcloud,kolibri,kiwix}.desktop /usr/local/bin/idea-open /home/learner/Desktop/idea-{nextcloud,kolibri,kiwix}.desktop
install -d /home/learner/Desktop
install -m 755 /usr/share/applications/idea-console.desktop /home/learner/Desktop/
chown learner:learner /home/learner/Desktop /home/learner/Desktop/idea-console.desktop 2>/dev/null || true
# trust it once, on learner's first login (gio needs the session's gvfs metadata daemon); the entry then disables itself
install -m 755 $B/files/idea-trust-desktop /usr/local/bin/
rm -f /etc/xdg/autostart/idea-trust-desktop.desktop
install -d /home/learner/.config/autostart; cp $B/files/idea-trust-desktop.desktop /home/learner/.config/autostart/
chown -R learner:learner /home/learner/.config 2>/dev/null || true
command -v xdg-settings >/dev/null && update-alternatives --set x-www-browser "$(command -v $BIN)" 2>/dev/null || true
install -d /etc/xdg; printf '[Default Applications]\ntext/html=%s\nx-scheme-handler/http=%s\nx-scheme-handler/https=%s\n' "$DESKTOP" "$DESKTOP" "$DESKTOP" > /etc/xdg/mimeapps.list
BROWSER_DESKTOP=$DESKTOP
