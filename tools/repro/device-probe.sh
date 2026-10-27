#!/bin/sh
# device-probe.sh - READ-ONLY inventory of one IDEA device, printed to stdout (idea#322). POSIX sh: runs on
# Ubuntu/Raspberry Pi OS (Engine, client card) and OpenWrt busybox (router). Writes nothing on the device.
# Normally run by capture-device.sh over ssh:  ssh host 'sh -s' < device-probe.sh
# Env: ENGINE_DIRS (space separated; default the usual Engine checkouts), HASH_DIRS (dirs to hash).
# Secret-bearing files are NEVER read: their paths are listed as "excluded" (no hash, no content).
export LC_ALL=C PATH=/usr/sbin:/sbin:/usr/bin:/bin:/usr/local/bin
S=""; [ "$(id -u)" = 0 ] || { sudo -n true 2>/dev/null && S="sudo -n"; }
sec(){ echo; echo "=== $1"; }
EXCL='etc/shadow|etc/gshadow|etc/shadow-|etc/gshadow-|etc/ssh/ssh_host_.*_key|etc/dropbear/.*|etc/NetworkManager/system-connections/.*|etc/wpa_supplicant/.*|etc/config/wireless|etc/config/tailscale|var/lib/tailscale/.*|etc/tailscale/.*|.*/\.ssh/.*|.*authkey.*|.*\.env|etc/idea/secrets.*|etc/machine-id'
sec "probe"; echo "version=1 date_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ) user=$(id -un) sudo=$([ -n "$S" ] && echo yes || echo no)"
sec "host"; echo "hostname=$(cat /proc/sys/kernel/hostname)"; uname -a
sec "os-release"; cat /etc/os-release 2>/dev/null; cat /etc/openwrt_release 2>/dev/null
sec "idea-versions"; for f in /etc/idea-client-version /etc/idea/version /boot/firmware/idea-home.txt /boot/firmware/idea-timezone.txt; do [ -r "$f" ] && { echo "--- $f"; cat "$f"; }; done
sec "temperature"; for t in /sys/class/thermal/thermal_zone*/temp; do [ -r "$t" ] && echo "$t $(cat "$t")"; done
sec "cmdline"; cat /proc/cmdline
sec "packages"
if command -v dpkg-query >/dev/null 2>&1; then dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n' | sort
elif command -v apk >/dev/null 2>&1; then apk list --installed 2>/dev/null | sort
elif command -v opkg >/dev/null 2>&1; then opkg list-installed | sort; fi
command -v snap >/dev/null 2>&1 && { sec "snaps"; snap list 2>/dev/null; }
sec "engine-git"
for d in ${ENGINE_DIRS:-$HOME/idea/agents/agent-engine-dev $HOME/idea/engine $HOME/engine /home/pi/idea/agents/agent-engine-dev}; do
  [ -d "$d/.git" ] || [ -f "$d/.git" ] || continue
  echo "dir=$d head=$(git -C "$d" rev-parse HEAD 2>/dev/null) branch=$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null) dirty_files=$(git -C "$d" status --porcelain 2>/dev/null | wc -l)"
  git -C "$d" status --porcelain 2>/dev/null | head -50 | sed 's/^/  /'
  [ -f "$d/pnpm-lock.yaml" ] && echo "pnpm-lock.yaml sha256=$(sha256sum "$d/pnpm-lock.yaml" | cut -d' ' -f1)"
done
for c in /home/pi/idea/agents/agent-console-dev /home/pi/console; do [ -d "$c/.git" ] && echo "console dir=$c head=$(git -C "$c" rev-parse HEAD 2>/dev/null)"; done
if command -v docker >/dev/null 2>&1; then
  sec "docker-images"; $S docker images --digests --format '{{.Repository}}:{{.Tag}}\t{{.Digest}}\t{{.ID}}' 2>/dev/null | sort
  sec "docker-containers"; $S docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}' 2>/dev/null | sort
  for n in $($S docker ps -aq 2>/dev/null); do $S docker inspect --format '{{.Name}}\t{{.Image}}' "$n" 2>/dev/null; done | sort
fi
sec "runtime-versions"
v(){ if command -v "$1" >/dev/null 2>&1; then o=$("$@" 2>/dev/null | head -1); echo "$1=${o:-UNKNOWN}"; else echo "$1=UNKNOWN"; fi; }
v tailscale version; v node --version; v npm --version; v pnpm --version; v pm2 --version
sec "console-dist-hashes"
CD=""; for c in /home/pi/idea/agents/agent-console-dev/dist /home/pi/console/dist; do [ -d "$c" ] && { CD=$c; break; }; done
if [ -n "$CD" ]; then echo "dir=$CD"; (cd "$CD" && find . -type f 2>/dev/null | sed 's|^\./||' | sort | while IFS= read -r f; do sha256sum "$f"; done); else echo "UNKNOWN (no console dist)"; fi
sec "kolibri-git"
k=0; for d in $(find /home/pi/idea -maxdepth 4 -type d -name 'app-kolibri*' 2>/dev/null | sort); do
  { [ -d "$d/.git" ] || [ -f "$d/.git" ]; } || continue; k=1
  echo "dir=$d head=$(git -C "$d" rev-parse HEAD 2>/dev/null || echo UNKNOWN)"; done
[ $k = 1 ] || echo "UNKNOWN (no app-kolibri checkout under /home/pi/idea)"
sec "helpers-sha256"
for f in $(ls -d /usr/local/sbin/idea-* 2>/dev/null | sort); do [ -f "$f" ] || continue; h=$($S sha256sum "$f" 2>/dev/null | cut -d' ' -f1); echo "${h:-UNKNOWN}  $f"; done
sec "apt-auto-update"
if command -v systemctl >/dev/null 2>&1; then for u in apt-daily.timer apt-daily-upgrade.timer unattended-upgrades; do
  echo "$u enabled=$(systemctl is-enabled "$u" 2>/dev/null || true) active=$(systemctl is-active "$u" 2>/dev/null || true)"; done
else echo "systemctl=UNKNOWN"; fi
echo "--- /var/log/apt/history.log (tail)"; if [ -r /var/log/apt/history.log ]; then tail -n 40 /var/log/apt/history.log; else $S tail -n 40 /var/log/apt/history.log 2>/dev/null || echo UNKNOWN; fi
command -v pm2 >/dev/null 2>&1 && { sec "pm2"; pm2 jlist 2>/dev/null | tr ',' '\n' | grep -E '"(name|status|pm_cwd|version)"' | head -60; }
sec "file-hashes"
for d in ${HASH_DIRS:-/etc /usr/local /usr/share/idea /opt /boot/firmware /www}; do
  [ -d "$d" ] || continue
  $S find "$d" -xdev -type f 2>/dev/null | sort | while IFS= read -r f; do
    r=${f#/}; if echo "$r" | grep -Eqx "$EXCL"; then echo "excluded  $f"; continue; fi
    h=$($S sha256sum "$f" 2>/dev/null | cut -d' ' -f1); echo "${h:-unreadable}  $f"; done
done
sec "end"
