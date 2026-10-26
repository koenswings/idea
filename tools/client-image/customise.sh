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
p=$(apt-cache policy); ls /var/lib/apt/lists/*binary-arm64_Packages* >/dev/null 2>&1 && grep -q 'b=arm64' <<<"$p" \
  || { echo "FATAL: no arm64 package lists after apt-get update; check /etc/apt/sources (need ports.ubuntu.com/ubuntu-ports) and network" >&2; exit 1; }
apt-get purge -y -q $PACKAGES_REMOVE 2>/dev/null || for p in $PACKAGES_REMOVE; do apt-get purge -y -q "$p" 2>/dev/null || true; done
ALL="$PACKAGES_OFFICE $PACKAGES_EDU $PACKAGES_GAMES $PACKAGES_SYSTEM"
# fail hard if any package has no arm64 candidate (CI rule §12)
miss=$(apt-cache policy $ALL | awk '/^[^ ].*:$/{p=substr($1,1,length($1)-1)} /Candidate: \(none\)/{printf " %s",p}')
for p in $ALL; do pol=$(apt-cache policy "$p" 2>/dev/null || true); grep -q Candidate <<<"$pol" || miss="$miss $p"; done
[ -z "$miss" ] || { echo "MISSING arm64 packages:$miss" >&2; exit 1; }
apt-get install -y -q --no-install-recommends $ALL
apt-get autoremove -y -q; apt-get clean

# --- locale, time zone, keyboard ---
sed -i "s/^# *${LOCALE} /${LOCALE} /" /etc/locale.gen; locale-gen >/dev/null; update-locale LANG=$LOCALE
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime; echo "$TIMEZONE" > /etc/timezone   # UTC; school zone at flash time (idea#208)
printf 'XKBMODEL="pc105"\nXKBLAYOUT="%s"\nXKBVARIANT="%s"\nXKBOPTIONS=""\nBACKSPACE="guess"\n' "$KEYBOARD_LAYOUT" "$KEYBOARD_VARIANT" > /etc/default/keyboard

# --- accounts (§4) ---
# Ubuntu raspi desktop ships no default user; first-boot wizard (oem-config / gnome-initial-setup) disabled below.
id learner >/dev/null 2>&1 || useradd -m -s /bin/bash -c "Learner" learner
passwd -d learner >/dev/null
for g in sudo adm lpadmin; do gpasswd -d learner $g >/dev/null 2>&1 || true; done
usermod -aG audio,video,plugdev,netdev learner 2>/dev/null || true
id admin >/dev/null 2>&1 || useradd -m -s /bin/bash -c "IDEA support" -G sudo admin
# local console password follows Koen's convention <account>911! (documented, not a secret); SSH stays key-only
ADMIN_PW="${ADMIN_USER:-admin}911!"; SALT=$(head -c 12 /dev/urandom | base64 | tr -dc 'A-Za-z0-9./' | head -c 16)
usermod -p "$(perl -e 'print crypt($ARGV[0], "\$6\$".$ARGV[1]."\$")' "$ADMIN_PW" "$SALT")" admin; unset ADMIN_PW
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

# --- boot config: KMS overlay per model, one image for Pi 400 ([pi4]) and Pi 500 ([pi5]) ---
python3 - /boot/firmware/config.txt <<'P'
import sys,re
p=sys.argv[1]; s=open(p).read()
s=re.sub(r'(?m)^dtoverlay=vc4-kms-v3d[ \t]*\n','',s)            # exact line only; cma-128 variants stay
if '# IDEA: per-model KMS' not in s:
    i=s.rfind('\n[all]'); blk='\n# IDEA: per-model KMS overlay (Pi 400 = pi4, Pi 500 = pi5)\n[pi4]\ndtoverlay=vc4-kms-v3d\n\n[pi5]\ndtoverlay=vc4-kms-v3d-pi5\n'
    s=s[:i]+blk+s[i:] if i>=0 else s+blk+'\n[all]\n'
open(p,'w').write(s)
P

# --- first-run wizards off ---
install -d /etc/libreoffice/registry; cp $B/files/idea-libreoffice.xcd /etc/libreoffice/registry/idea.xcd
# SuperTuxKart 1.5 (config-0.10): enable_internet=2 (not allowed, offline schools, no question) and a ready player
# "Learner" with story-mode first-time=false (no create-player / first-time screens). For learner and /etc/skel.
for h in /home/learner /etc/skel; do d=$h/.config/supertuxkart/config-0.10; install -d $d
  cp $B/files/stk-config.xml $d/config.xml; cp $B/files/stk-players.xml $d/players.xml; done
install -d /home/learner/.config/gcompris-qt; cp $B/files/gcompris-qt.conf /home/learner/.config/gcompris-qt/gcompris-qt.conf

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
# time zone from the boot partition (idea-timezone.txt, written at flash time), every boot (idea#208)
install -m 755 $B/files/idea-timezone /usr/local/sbin/idea-timezone
cp $B/files/idea-timezone.service /etc/systemd/system/; systemctl enable idea-timezone.service
rm -f /etc/ssh/ssh_host_*; : > /etc/machine-id; rm -f /var/lib/dbus/machine-id

# --- reset level B (reset-on-reboot): tmpfs overlay over root, switched by kernel arg overlayroot=tmpfs ---
# Ubuntu 26.04 boots a dracut initramfs from /boot/firmware/current/initrd.img; overlayroot's dracut hook reads only
# the kernel command line (not /etc/overlayroot.conf), and the stock firmware initrd has no overlay hooks. So:
# rebuild the initrd with the overlayfs+overlayroot modules plus every driver/firmware of the stock one, put it where
# the firmware loads it, and switch via current/cmdline.txt (idea-client-mode). OVERLAY=on (default since
# 2026-10-16): the image ships with the overlay OFF and idea-overlay-arm.service turns it ON once, right after
# first-boot setup (growpart/resizefs, idea-firstboot, snap seeding), then reboots - so those run once on the real disk.
install -m 755 $B/files/idea-client-mode /usr/local/sbin/idea-client-mode
install -m 755 $B/files/idea-overlay-arm /usr/local/sbin/idea-overlay-arm
cp $B/files/idea-overlay-arm.service /etc/systemd/system/
KV=$(ls /lib/modules | sort -V | tail -1); FWI=/boot/firmware/current/initrd.img
STOCK=$(lsinitrd "$FWI" 2>/dev/null | awk '{print $NF}')
MODS=$(printf '%s\n' "$STOCK" | grep '\.ko' | sed 's#.*/##; s/\.ko.*//' | sort -u | tr '\n' ' ')
FWS=$(printf '%s\n' "$STOCK" | grep '^usr/lib/firmware/.*\.[a-z0-9]*$' | sed 's#^#/#' | while read -r f; do if [ -f "$f" ]; then echo "$f"; fi; done | tr '\n' ' ')
[ -n "$MODS" ] || { echo "customise: cannot list stock initrd $FWI" >&2; exit 1; }
set -- --force --add "overlayfs overlayroot" --add-drivers "$MODS"; [ -z "$FWS" ] || set -- "$@" --install "$FWS"
dracut "$@" "/boot/initrd.img-$KV" "$KV"
cp "/boot/initrd.img-$KV" "$FWI"
sed -i 's/^overlayroot=.*/overlayroot=""/' /etc/overlayroot.conf; sed -i '1s/ *overlayroot=[^ ]*//' /boot/firmware/current/cmdline.txt
rm -f /var/lib/idea-overlay-armed
if [ "$OVERLAY" = on ]; then systemctl enable idea-overlay-arm.service; else systemctl disable idea-overlay-arm.service 2>/dev/null || true; fi

echo "$IDEA_CLIENT_VERSION" > /etc/idea-client-version
chown -R learner:learner /home/learner
rm -f $policy; rm -rf /var/lib/apt/lists/* /tmp/* /var/log/*.log
history -c 2>/dev/null || true
echo "customise: done ($IDEA_CLIENT_VERSION)"
