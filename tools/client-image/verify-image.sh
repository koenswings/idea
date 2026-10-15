#!/bin/bash
# Static CI checks inside the built rootfs (proposal §12 "Build CI"). Exit non-zero on any failure.
set -u; fail=0; B=/root/.idea-build; . $B/client-image.conf
bad(){ echo "FAIL: $*"; fail=1; }; ok(){ echo "ok:   $*"; }
for p in $PACKAGES_OFFICE $PACKAGES_BROWSER $PACKAGES_EDU $PACKAGES_GAMES $PACKAGES_SYSTEM; do
  dpkg -s "$p" >/dev/null 2>&1 || bad "package $p not installed"; done
dpkg -s chromium 2>/dev/null | grep -q '^Version:' && ! dpkg -s chromium | grep -q snap && ok "chromium is a real .deb" || bad "chromium .deb missing"
[ -f /etc/chromium/policies/managed/idea.json ] && ok "chromium bookmarks policy" || bad "chromium policy"
for a in nextcloud kolibri kiwix; do [ -f /usr/share/applications/idea-$a.desktop ] && [ -f /home/learner/Desktop/idea-$a.desktop ] && ok "$a menu+desktop icon" || bad "$a launcher"; done
. /etc/idea-client/servers.conf && [ -n "$URL_KOLIBRI" ] && ok "servers.conf" || bad "servers.conf"
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
grep -rlsE 'device_tree=|^\[pi4\]$|^\[pi5\]$' /boot/firmware/config.txt >/dev/null && echo "note: config.txt has model sections (expected from Ubuntu base; not added by us)"
exit $fail
