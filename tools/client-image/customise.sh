#!/bin/bash
# Runs INSIDE the arm64 chroot. Applies proposal idea#201 §4-§8 and idea#203 (browser, start page). Never prints secrets.
set -euo pipefail
B=/root/.idea-build; . $B/client-image.conf; . $B/version.env; . $B/browser.env; set +x; . $B/secrets.env
export DEBIAN_FRONTEND=noninteractive LC_ALL=C
policy=/usr/sbin/policy-rc.d; printf '#!/bin/sh\nexit 101\n' > $policy; chmod +x $policy   # no daemons in chroot

# arm64 lives on ports.ubuntu.com/ubuntu-ports, not archive/security.ubuntu.com (those have no arm64 lists)
for f in /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list; do [ -f "$f" ] || continue
  sed -i -E 's#https?://(([a-z]{2}\.)?archive|security)\.ubuntu\.com/ubuntu/?#http://ports.ubuntu.com/ubuntu-ports/#g' "$f"; done
apt-get update -q
ls /var/lib/apt/lists/*binary-arm64_Packages* >/dev/null 2>&1 && apt-cache policy | grep -q 'arch=arm64' \
  || { echo "FATAL: no arm64 package lists after apt-get update; check /etc/apt/sources (need ports.ubuntu.com/ubuntu-ports) and network" >&2; exit 1; }
apt-get purge -y -q $PACKAGES_REMOVE 2>/dev/null || for p in $PACKAGES_REMOVE; do apt-get purge -y -q "$p" 2>/dev/null || true; done
ALL="$PACKAGES_OFFICE $PACKAGES_EDU $PACKAGES_GAMES $PACKAGES_SYSTEM"
# fail hard if any package has no arm64 candidate (CI rule §12)
miss=$(apt-cache policy $ALL | awk '/^[^ ].*:$/{p=substr($1,1,length($1)-1)} /Candidate: \(none\)/{printf " %s",p}')
for p in $ALL; do apt-cache policy "$p" 2>/dev/null | grep -q Candidate || miss="$miss $p"; done
[ -z "$miss" ] || { echo "MISSING arm64 packages:$miss" >&2; exit 1; }
apt-get install -y -q --no-install-recommends $ALL
apt-get autoremove -y -q; apt-get clean

# --- locale, time zone, keyboard ---
sed -i "s/^# *${LOCALE} /${LOCALE} /" /etc/locale.gen; locale-gen >/dev/null; update-locale LANG=$LOCALE
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime; echo $TIMEZONE > /etc/timezone
printf 'XKBMODEL="pc105"\nXKBLAYOUT="%s"\nXKBVARIANT="%s"\nXKBOPTIONS=""\nBACKSPACE="guess"\n' "$KEYBOARD_LAYOUT" "$KEYBOARD_VARIANT" > /etc/default/keyboard

# --- accounts (§4) ---
# Ubuntu raspi desktop ships no default user; first-boot wizard (oem-config / gnome-initial-setup) disabled below.
id learner >/dev/null 2>&1 || useradd -m -s /bin/bash -c "Learner" learner
passwd -d learner >/dev/null
for g in sudo adm lpadmin; do gpasswd -d learner $g >/dev/null 2>&1 || true; done
usermod -aG audio,video,plugdev,netdev learner 2>/dev/null || true
id admin >/dev/null 2>&1 || useradd -m -s /bin/bash -c "IDEA support" -G sudo admin
usermod -p "$ADMIN_PASSWORD_HASH" admin
install -d -m 700 -o admin -g admin /home/admin/.ssh
install -m 600 -o admin -g admin $B/admin_authorized_keys /home/admin/.ssh/authorized_keys
# hide admin from the login screen
printf '[User]\nSystemAccount=true\n' > /var/lib/AccountsService/users/admin
# GDM autologin, no first-boot wizard
mkdir -p /etc/gdm3
cat > /etc/gdm3/custom.conf <<C
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=learner
WaylandEnable=true
InitialSetupEnable=false
C
systemctl disable oem-config.service oem-config.target 2>/dev/null || true
rm -f /var/lib/oem-config/run 2>/dev/null || true
apt-get purge -y -q oem-config oem-config-gtk oem-config-slideshow-ubuntu 2>/dev/null || true
mkdir -p /home/learner/.config; echo yes > /home/learner/.config/gnome-initial-setup-done

# SSH: key only, admin only
cat > /etc/ssh/sshd_config.d/10-idea.conf <<C
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
AllowUsers admin
C
systemctl enable ssh 2>/dev/null || true

# polkit: learner cannot change network/software/users/power-management
mkdir -p /etc/polkit-1/rules.d
cp $B/files/50-idea-learner.rules /etc/polkit-1/rules.d/

# --- GNOME defaults for learner (dconf system db) ---
mkdir -p /etc/dconf/db/local.d/locks /etc/dconf/profile
printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user
cp $B/files/00-idea-dconf /etc/dconf/db/local.d/00-idea
cp $B/files/00-idea-locks /etc/dconf/db/local.d/locks/00-idea
dconf update

# --- updates OFF (§7) ---
cat > /etc/apt/apt.conf.d/99idea-no-updates <<C
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::AutocleanInterval "0";
APT::Periodic::Unattended-Upgrade "0";
C
for t in apt-daily.timer apt-daily-upgrade.timer fwupd-refresh.timer motd-news.timer ua-timer.timer update-notifier-download.timer update-notifier-motd.timer; do
  systemctl disable $t 2>/dev/null || true; systemctl mask $t 2>/dev/null || true; done
# snaps: whatever remains in the seed is held forever on first boot; snapd refresh timer masked
mkdir -p /etc/systemd/system/snapd.service.d
cp $B/files/idea-snap-hold.service /etc/systemd/system/; systemctl enable idea-snap-hold.service
systemctl mask snapd.refresh.timer snapd.snap-repair.timer 2>/dev/null || true
# Software Center / Pro prompts gone; disable apport
sed -i 's/^enabled=1/enabled=0/' /etc/default/apport 2>/dev/null || true

# --- browser, policies, start page, home-Engine boot step, the one IDEA shortcut (idea#203) ---
. $B/browser.sh
sed -i "s/@BROWSER_DESKTOP@/$BROWSER_DESKTOP/" /etc/dconf/db/local.d/00-idea; dconf update

# --- Wi-Fi profile (root-only) ---
f=/etc/NetworkManager/system-connections/IDEA.nmconnection
umask 077; cat > $f <<C
[connection]
id=$WIFI_SSID
type=wifi
autoconnect=true
permissions=
[wifi]
mode=infrastructure
ssid=$WIFI_SSID
[wifi-security]
key-mgmt=wpa-psk
psk=$WIFI_PSK
[ipv4]
method=auto
[ipv6]
method=ignore
C
chmod 600 $f; umask 022

# --- small-Pi tweaks ---
printf 'ALGO=zstd\nPERCENT=50\n' > /etc/default/zramswap; systemctl enable zramswap 2>/dev/null || true
systemctl --global mask tracker-miner-fs-3.service 2>/dev/null || true

# --- first boot: hostname from Pi serial, new SSH host keys + machine-id ---
install -m 755 $B/files/idea-firstboot /usr/local/sbin/idea-firstboot
sed -i "s/@PREFIX@/$HOSTNAME_PREFIX/" /usr/local/sbin/idea-firstboot
cp $B/files/idea-firstboot.service /etc/systemd/system/; systemctl enable idea-firstboot.service
rm -f /etc/ssh/ssh_host_*; : > /etc/machine-id; rm -f /var/lib/dbus/machine-id

# --- reset level B: overlayroot installed, off unless OVERLAY=on; switch tool ---
install -m 755 $B/files/idea-client-mode /usr/local/sbin/idea-client-mode
if [ "$OVERLAY" = on ]; then sed -i 's/^overlayroot=.*/overlayroot="tmpfs"/' /etc/overlayroot.conf
else sed -i 's/^overlayroot=.*/overlayroot=""/' /etc/overlayroot.conf; fi

echo "$IDEA_CLIENT_VERSION" > /etc/idea-client-version
chown -R learner:learner /home/learner
rm -f $policy; rm -rf /var/lib/apt/lists/* /tmp/* /var/log/*.log
history -c 2>/dev/null || true
echo "customise: done ($IDEA_CLIENT_VERSION)"
