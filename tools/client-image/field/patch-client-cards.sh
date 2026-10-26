#!/bin/bash
# patch-client-cards.sh - bring already-flashed IDEA client SD cards (s14 & co) up to s15 in place, no reflash.
# Atlas, 2026-10-17 (committed for idea#322 = the "17 Oct card patch" applied to the Zimbabwe kit cards). Runs ON wh (wizardly-hugle) with up to 4 cards in USB card readers.
#
#   sudo bash ~/client-card-patch/patch-client-cards.sh --dry-run          # check only, writes nothing
#   sudo bash ~/client-card-patch/patch-client-cards.sh                    # check + patch + verify + fsck
#   ... [--undock] [--dev /dev/sdX]...
#   Order per card: read-only check -> (undock: unmount) -> read-only fsck -> patch ONLY if clean -> verify -> fsck again.
#   Result per card: PASS (pack it) | FAIL (fix the cause, rerun) | SUSPECT - DO NOT PACK (fs damage; never repaired)
#
# What it patches (exactly what s15 = 26.04-20261017-291b962 ships, and what field/idea-fix-client.sh (#261) does):
#   1. /etc/default/keyboard  -> byte-identical to s15 (XKBLAYOUT="us", XKBVARIANT="", model pc105)
#   2. /etc/X11/xorg.conf.d/00-keyboard.conf -> only if present with a non-"us" XkbLayout (s15 has none): layout -> us
#   3. Chrome managed policy /etc/opt/chrome/policies/managed/idea.json -> drop "NewTabPageLocation" (#261)
# Reset-on-reboot: overlayroot=tmpfs on the kernel cmdline; the "lower layer" IS the card's ext4 root, and the upper
# layer is tmpfs (gone at reboot). Patching the card's root offline therefore patches the layer that survives.
# Overlay state and the Wi-Fi PSK (compared by hash, never printed) are CHECKED, never changed.
#
# Safety: only USB disks with exactly 2 partitions (vfat LABEL=system-boot, ext4 LABEL=writable) whose root has
# /etc/idea-client-version (26.04-YYYYMMDD-<sha>) + /usr/local/sbin/idea-client-mode + the Chrome policy.
# Never: the disk holding / or /boot/firmware, non-USB disks, >256 GB, any disk with apps/ or instances/ (Engine
# App/Backup disks), any partition used by a container, any disk with META.yaml (Engine-docked) unless --undock.
# Checks read the raw fs with debugfs -c (no mount). Writes happen only if needed, under flock -x on the whole disk
# (udev defers events while locked), after re-verifying the reader serial + size. Backups of every changed file go
# to /home/pi/quarantine/clientcard-<readerserial>-<ts>/ first. Idempotent: a patched card is never mounted rw.
#
# There is no repair mode: e2fsck only ever runs with -n (Steve 2026-10-17 12:54).
# --undock: wh's Engine auto-docks a client card on insertion (mounts root rw at /disks/sdX2, bootfs ro at
#   /run/idea-usb/sdX1) and WRITES /META.yaml (diskName "writable"). With --undock the script unmounts, fscks, and
#   (only if clean) quarantines that
#   META.yaml (copy in the backup dir, then removed from the card), unmounts those two Engine mounts, and patches.
#   The Engine's store keeps its disk record (never edited here). Without --undock a docked card is FAIL ENGINE_DOCKED.
set -uo pipefail
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
DRY=0; UNDOCK=0; DEVS=(); MAXCARDS=4
while [ $# -gt 0 ]; do case "$1" in
  --dry-run|-n) DRY=1;; --undock) UNDOCK=1;; --repair-minor|--minor-max) echo "--repair-minor is disabled (Steve 2026-10-17 12:54: never repair client cards)" >&2; exit 2;; --dev) DEVS+=("$2"); shift;;
  -h|--help) sed -n '2,32p' "$0"; exit 0;; *) echo "unknown arg $1" >&2; exit 2;; esac; shift; done
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 2; }
TS=$(date +%Y%m%d-%H%M%S); QBASE=${CCP_QBASE:-/home/pi/quarantine}
log(){ echo "$(date +%T) [$CUR] $*"; }; CUR=-
KBD_S15='XKBMODEL="pc105"
XKBLAYOUT="us"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"'
# s15 reference hashes: s15-manifest.sha256 next to this script (generated from the s15 image on the box)
MAN="$(dirname "$(readlink -f "$0")")/s15-manifest.sha256"
[ -r "$MAN" ] || { echo "missing $MAN" >&2; exit 2; }
KBD_S15_SHA=$(awk '$2=="/etc/default/keyboard"{print $1}' "$MAN"); POL_S15_SHA=$(awk '$2=="/etc/opt/chrome/policies/managed/idea.json"{print $1}' "$MAN")
[ ${#KBD_S15_SHA} = 64 ] && [ ${#POL_S15_SHA} = 64 ] || { echo "bad manifest $MAN" >&2; exit 2; }
E2N=/tmp/e2fsck-1.47.2   # Debian bookworm-backports e2fsck 1.47.2 arm64 (read-only use only)
POL=/etc/opt/chrome/policies/managed/idea.json
XK=/etc/X11/xorg.conf.d/00-keyboard.conf
NM=/etc/NetworkManager/system-connections/IDEA.nmconnection
# Committed copy (idea#322): the field key is not in git. Give its sha256 (IDEA_WIFI_PSK_SHA256) or a file holding the key
# (IDEA_WIFI_PSK_FILE, default ~/.config/idea-client-image/wifi-psk). The 17 Oct run had the key inline; nothing else differs.
PSK_SHA=${IDEA_WIFI_PSK_SHA256:-}
if [ -z "$PSK_SHA" ]; then PF=${IDEA_WIFI_PSK_FILE:-$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)/.config/idea-client-image/wifi-psk}
  [ -r "$PF" ] || { echo "need IDEA_WIFI_PSK_SHA256 or a key file at $PF" >&2; exit 2; }
  PSK_SHA=$(head -n 1 "$PF" | tr -d '\r\n' | sha256sum | cut -d' ' -f1); fi

# ---------- read-only helpers (debugfs -c on the raw partition, never mounts) ----------
dcat(){ local o; o=$(debugfs -c -R "cat $2" "$1" 2>&1 >/dev/null); printf '%s' "$o" | grep -qiE 'not found|error|bad magic|no such|corrupt|could not|short read' && return 1; debugfs -c -R "cat $2" "$1" 2>/dev/null; }
# partition N of a disk (sdb -> sdb2; loop0 -> loop0p2 for the box self-test only)
# Box self-test only (CCP_SELFTEST_LOOP=1, loop devices only): partitions are separate offset loops CCP_SELFTEST_P1/P2.
part(){ case "$1" in /dev/loop*) [ "${CCP_SELFTEST_LOOP:-0}" = 1 ] && [ "$1" = "${CCP_SELFTEST_DISK:-}" ] && eval echo "\$CCP_SELFTEST_P$2" || echo "${1}p$2";; *) echo "$1$2";; esac; }
dexists(){ debugfs -c -R "stat $2" "$1" 2>&1 | grep -q '^Inode:'; }
dsha(){ dcat "$1" "$2" | sha256sum | cut -d' ' -f1; }

# ---------- candidate detection ----------
ROOTDISK=$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /)" 2>/dev/null)
BOOTDISK=$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /boot/firmware 2>/dev/null)" 2>/dev/null || true)
ctr_srcs(){ command -v docker >/dev/null && for c in $(docker ps -q); do docker inspect "$c" --format '{{range .Mounts}}{{.Source}} {{end}}'; done | tr ' ' '\n' | grep . ; }
if [ ${#DEVS[@]} = 0 ]; then
  for n in $(lsblk -dn -o NAME,TRAN,TYPE | awk '$2=="usb" && $3=="disk"{print $1}'); do DEVS+=("/dev/$n"); done
fi
declare -A R_VER R_KBD R_POL R_OVL R_PSK R_RES R_SER R_FS
ORDER=()
classify(){ # $1=/dev/sdX -> sets REASON, returns 0 if an IDEA client card
  local d=$1 n=${1#/dev/} p1 p2 sz
  REASON=""
  [ -b "$d" ] || { REASON="not a block device"; return 1; }
  [ "$n" != "$ROOTDISK" ] && [ "$n" != "$BOOTDISK" ] || { REASON="SYSTEM DISK of this host"; return 1; }
  if [ "${CCP_SELFTEST_LOOP:-0}" = 1 ] && [[ "$d" == /dev/loop* ]] && [ "$d" = "${CCP_SELFTEST_DISK:-}" ]; then :   # box self-test on a loop image only
  else [ "$(lsblk -dn -o TRAN "$d")" = usb ] || { REASON="not USB"; return 1; }; fi
  sz=$(blockdev --getsize64 "$d"); [ "$sz" -gt 0 ] && [ "$sz" -le 256000000000 ] || { REASON="size $sz out of range (no media or >256GB)"; return 1; }
  [ "${CCP_SELFTEST_LOOP:-0}" = 1 ] && [ "$d" = "${CCP_SELFTEST_DISK:-}" ] || [ "$(lsblk -ln -o TYPE "$d" | grep -c part)" = 2 ] || { REASON="not exactly 2 partitions"; return 1; }
  p1=$(part "$d" 1); p2=$(part "$d" 2)
  [ "$(blkid -s TYPE -o value "$p1")" = vfat ] && [ "$(blkid -s LABEL -o value "$p1")" = system-boot ] || { REASON="p1 not vfat system-boot"; return 1; }
  [ "$(blkid -s TYPE -o value "$p2")" = ext4 ] && [ "$(blkid -s LABEL -o value "$p2")" = writable ] || { REASON="p2 not ext4 writable"; return 1; }
  ctr_srcs 2>/dev/null | grep -qE "^($p1|$p2)\$|^/disks/${n}[12](/|\$)" && { REASON="used by a container"; return 1; }
  for m in $(findmnt -rn -o SOURCE,TARGET | awk -v a="$p1" -v b="$p2" '$1==a||$1==b{print $1"="$2}'); do
    case "$m" in "$p2=/disks/${n}2"|"$p1=/run/idea-usb/${n}1") ;; *) REASON="mounted elsewhere: $m"; return 1;; esac; done
  VER=$(dcat "$p2" /etc/idea-client-version | head -1)
  [[ "$VER" =~ ^26\.04-[0-9]{8}-[0-9a-f]{7}(-.*)?$ ]] || { REASON="no IDEA client signature (/etc/idea-client-version='$VER')"; return 1; }
  dexists "$p2" /usr/local/sbin/idea-client-mode && dexists "$p2" "$POL" || { REASON="client signature incomplete"; return 1; }
  for x in /apps /instances /backups; do dexists "$p2" $x && { REASON="has $x (Engine App/Backup disk) - never touched"; return 1; }; done
  return 0
}

# ---------- per-card check (read-only) ----------
check(){ # $1=dev ; fills NEED_* and report fields
  local d=$1 p2 p1 k pol cl mt ovl; p1=$(part "$d" 1); p2=$(part "$d" 2)
  k=$(dsha "$p2" /etc/default/keyboard)
  KL=$(dcat "$p2" /etc/default/keyboard | sed -n 's/^XKBLAYOUT=//p' | tr -d '"')
  NEED_KBD=0; [ "$k" = "$KBD_S15_SHA" ] || NEED_KBD=1
  NEED_XK=0; XKL=-; if dexists "$p2" "$XK"; then XKL=$(dcat "$p2" "$XK" | sed -n 's/.*"XkbLayout" *"\([^"]*\)".*/\1/p'); [ "$XKL" = us ] || NEED_XK=1; fi
  pol=$(dcat "$p2" "$POL"); NEED_POL=0; printf '%s' "$pol" | grep -q '"NewTabPageLocation"' && NEED_POL=1
  PSHA=$(printf '%s\n' "$pol" | sha256sum | cut -d' ' -f1)
  printf '%s\n' "$pol" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null && POLOK=json || POLOK=BROKEN
  # overlay: cmdline on bootfs (read via an ro mount, or the Engine's existing ro mount)
  mt=$(findmnt -rn -o TARGET -S "$p1" | head -1); local own=0
  if [ -z "$mt" ]; then mt=$(mktemp -d); mount -t vfat -o ro "$p1" "$mt" 2>/dev/null && own=1 || { rmdir "$mt"; mt=""; }; fi
  if [ -n "$mt" ]; then cl=$(cat "$mt/current/cmdline.txt" 2>/dev/null || echo "?")
  elif command -v mtype >/dev/null; then cl=$(MTOOLS_SKIP_CHECK=1 mtype -i "$p1" ::current/cmdline.txt 2>/dev/null || echo "?"); else cl="?"; fi
  [ "$own" = 1 ] && { umount "$mt"; rmdir "$mt"; }
  if printf '%s' "$cl" | grep -qw 'overlayroot=tmpfs'; then ovl="ON(next boot)"
  elif dexists "$p2" /var/lib/idea-overlay-armed; then ovl="OFF(normal,armed-before)"
  elif debugfs -c -R "ls /etc/systemd/system/multi-user.target.wants" "$p2" 2>/dev/null | grep -q idea-overlay-arm.service; then ovl="arms-at-first-boot"
  else ovl="OFF(no arm service)"; fi
  OVL=$ovl
  local ps; ps=$(dcat "$p2" "$NM" | sed -n 's/^psk=//p' | head -1 | tr -d '\n' | sha256sum | cut -d' ' -f1)
  [ "$ps" = "$PSK_SHA" ] && PSK=ok || PSK=WRONG
  log "version=$VER  XKBLAYOUT=$KL (s15-identical: $([ $NEED_KBD = 0 ] && echo yes || echo no))  xorg 00-keyboard=$XKL"
  log "chrome policy: NewTabPageLocation=$([ $NEED_POL = 1 ] && echo PRESENT || echo absent) $POLOK, =s15: $([ "$PSHA" = "$POL_S15_SHA" ] && echo yes || echo no)"
  log "overlay: $OVL   cmdline overlayroot: $(printf '%s' "$cl" | grep -o 'overlayroot=[^ ]*' || echo none)   wifi psk (field key): $PSK"
}

# ---------- per-card patch (under flock) ----------
patch_card(){ # $1=dev $2=readerserial $3=size $4=Q
  local d=$1 SER=$2 SZ=$3 Q=$4
  flock -x "$d" bash -s -- "$d" "$SER" "$SZ" "$Q" "$NEED_KBD" "$NEED_XK" "$NEED_POL" "$UNDOCK_META" "$(part "$d" 2)" <<'IN'
set -euo pipefail; export PATH=/usr/sbin:/sbin:/usr/bin:/bin
d=$1 SER=$2 SZ=$3 Q=$4 NK=$5 NX=$6 NP=$7 UM=$8 p2=$9
[ "$( (udevadm info -q property -n "$d" 2>/dev/null || true) | sed -n 's/^ID_SERIAL_SHORT=//p')" = "$SER" ] || { echo "serial changed under lock"; exit 9; }
[ "$(blockdev --getsize64 "$d")" = "$SZ" ] || { echo "size changed under lock"; exit 9; }
findmnt -rn -S "$p2" >/dev/null && { echo "p2 mounted under lock"; exit 9; }
M=$(mktemp -d); mount -t ext4 -o rw,noatime "$p2" "$M"
trap 'umount "$M" 2>/dev/null; rmdir "$M" 2>/dev/null' EXIT
bk(){ install -d "$Q/root$(dirname "$1")"; cp -a "$M$1" "$Q/root$1"; sha256sum "$M$1" | sed "s#$M##" >> "$Q/SHA256SUMS.before"; }
grep -q . "$M/etc/idea-client-version" || { echo "signature lost after mount"; exit 9; }
if [ "$NK" = 1 ]; then bk /etc/default/keyboard
  printf 'XKBMODEL="pc105"\nXKBLAYOUT="us"\nXKBVARIANT=""\nXKBOPTIONS=""\nBACKSPACE="guess"\n' > "$M/etc/default/keyboard.idea-new"
  chown root:root "$M/etc/default/keyboard.idea-new"; chmod 644 "$M/etc/default/keyboard.idea-new"
  mv "$M/etc/default/keyboard.idea-new" "$M/etc/default/keyboard"; echo "patched /etc/default/keyboard"; fi
X=/etc/X11/xorg.conf.d/00-keyboard.conf
if [ "$NX" = 1 ]; then bk $X; sed -i 's/\("XkbLayout" *\)"[^"]*"/\1"us"/' "$M$X"; echo "patched $X"; fi
P=/etc/opt/chrome/policies/managed/idea.json
if [ "$NP" = 1 ]; then bk $P
  python3 - "$M$P" <<'PY'
import json,sys,os
f=sys.argv[1]; d=json.load(open(f)); d.pop("NewTabPageLocation",None)
t=f+".idea-new"; open(t,"w").write(json.dumps(d,indent=1)+"\n"); st=os.stat(f); os.chmod(t,st.st_mode&0o7777); os.chown(t,st.st_uid,st.st_gid); os.replace(t,f)
PY
  echo "patched $P (NewTabPageLocation removed)"; fi
if [ "$UM" = 1 ] && [ -f "$M/META.yaml" ]; then cp -a "$M/META.yaml" "$Q/META.yaml.engine-autodock"; rm -f "$M/META.yaml"; echo "Engine-written /META.yaml quarantined + removed"; fi
sha256sum "$M/etc/default/keyboard" "$M$P" | sed "s#$M##" > "$Q/SHA256SUMS.after"
sync; umount "$M"; rmdir "$M"; trap - EXIT; sync
echo "unmounted; releasing lock"
IN
}

# ---------- file-system check (READ-ONLY, always before any write) ----------
# Steve 2026-10-17 12:54: never repair. Patch only a card whose check is clean; any fs damage -> SUSPECT - DO NOT PACK,
# card left as it is. (Lesson from reader 121220160204: e2fsck -fy "repairs" did not stick and changed thousands of
# inodes.) All output is kept in the card's quarantine dir.
fsck_stage(){ local d=$1 p1 p2; p1=$(part "$d" 1); p2=$(part "$d" 2); FSCK=clean; SUSPECT=""
  if fsck.vfat -n "$p1" > "$Q/fsck-vfat$2.txt" 2>&1; then VF=ok
  elif ! grep -vE '^(fsck\.fat [0-9].*|There are differences between boot sector and its backup\.|This is mostly harmless\. Differences: \(offset:original/backup\)| *65:01/00| *Not automatically fixing this\.|Dirty bit is set\. Fs was not properly unmounted and some data may be corrupt\.| *Automatically removing dirty bit\.|Leaving filesystem unchanged\.|/dev/.*: [0-9]+ files, .*|)$' "$Q/fsck-vfat$2.txt" | grep -q .; then VF="dirty-bit(benign)"
  else VF=ISSUES; fi
  log "fsck.vfat -n bootfs: $VF$([ "$VF" = ISSUES ] && grep -vE '^(fsck.fat [0-9]|$)' "$Q/fsck-vfat$2.txt" | head -4 | tr '\n' ' ')"
  # Steve 13:07: e2fsck on the card itself gives false "directory corrupted" through wh's 14cd:1212 readers (blocks
  # read fine and match s15), so the check runs on a metadata-only copy (e2image -r, sparse, ~180 MB, deleted after).
  local img=/var/tmp/ccp-meta-${CUR}-$$.raw e2=e2fsck; local -a envp=()
  [ -x "$E2N/e2fsck" ] && { e2="$E2N/e2fsck"; envp=(LD_LIBRARY_PATH="$E2N/lib"); }
  [ "$(df --output=avail -B1 /var/tmp | tail -1)" -gt 2000000000 ] || { FSCK=NOSPACE; SUSPECT="no space in /var/tmp for the metadata copy"; return 0; }
  if ! e2image -r "$p2" "$img" > "$Q/e2image$2.txt" 2>&1; then rm -f "$img"; FSCK=E2IMAGE_FAIL; SUSPECT="e2image failed"; return 0; fi
  env "${envp[@]}" "$e2" -f -n "$img" > "$Q/e2fsck-n$2.txt" 2>&1; local rc=$?; rm -f "$img"
  log "e2fsck $([ ${#envp[@]} -gt 0 ] && echo 1.47.2 || echo "(system)") -fn on metadata copy: rc=$rc"
  if [ $rc = 0 ]; then log "e2fsck -fn root (metadata copy): clean"
  else FSCK="ISSUES"; SUSPECT="e2fsck -fn: $(grep -vE '^(Pass [0-9]|e2fsck [0-9])|could be narrower|Optimize\?' "$Q/e2fsck-n$2.txt" | grep . | head -1 | cut -c1-70)"; log "e2fsck -fn root: ISSUES: $(grep -vE '^(Pass [0-9]|e2fsck [0-9])' "$Q/e2fsck-n$2.txt" | grep . | head -3 | tr '\n' ' ')"; fi
  [ "$VF" = ISSUES ] && { FSCK="$FSCK,vfat:ISSUES"; SUSPECT="${SUSPECT:+$SUSPECT; }bootfs fsck.vfat issues"; }
  return 0; }

echo "patch-client-cards $( [ $DRY = 1 ] && echo DRY-RUN || echo LIVE ) $TS  host=$(hostname) rootdisk=$ROOTDISK"
for d in "${DEVS[@]}"; do
  CUR=${d#/dev/}
  if ! classify "$d"; then log "skip: $REASON"; continue; fi
  [ ${#ORDER[@]} -lt $MAXCARDS ] || { log "skip: more than $MAXCARDS cards"; continue; }
  ORDER+=("$d")
  SER=$(udevadm info -q property -n "$d" 2>/dev/null | sed -n 's/^ID_SERIAL_SHORT=//p'); SZ=$(blockdev --getsize64 "$d"); R_SER[$d]=$SER
  Q=$QBASE/clientcard-${SER:-noserial}-$TS$([ $DRY = 1 ] && echo -dryrun); mkdir -p "$Q"; chmod 700 "$Q"
  log "IDEA client card: reader serial=$SER size=$SZ model=$(lsblk -dn -o MODEL "$d" | xargs) path=$(udevadm info -q property -n "$d" 2>/dev/null | sed -n 's/^ID_PATH=//p')  logs=$Q"
  P1=$(part "$d" 1); P2=$(part "$d" 2); UNDOCK_META=0; DOCKED=0; FSCK=-; SUSPECT=""
  dexists "$P2" /META.yaml && DOCKED=1
  findmnt -rn -S "$P2" >/dev/null && DOCKED=1
  check "$d"
  R_VER[$d]=$VER; R_KBD[$d]=$KL; R_POL[$d]=$([ $NEED_POL = 1 ] && echo NewTab-present || echo ok); R_OVL[$d]=$OVL; R_PSK[$d]=$PSK
  NEED=$((NEED_KBD+NEED_XK+NEED_POL))
  if [ $DOCKED = 1 ]; then
    meta=$(dcat "$P2" /META.yaml 2>/dev/null | tr '\n' ' ')
    log "Engine dock: mounts=[$(findmnt -rn -o SOURCE,TARGET | awk -v a="$P1" -v b="$P2" '$1==a||$1==b{printf "%s ",$2}')] META.yaml=[${meta:-none}]"
    if [ $UNDOCK = 0 ]; then R_RES[$d]="FAIL ENGINE_DOCKED (rerun with --undock)"; R_FS[$d]=-; continue; fi
    printf '%s' "$meta" | grep -qE 'diskName: *writable' || [ -z "$meta" ] || { R_RES[$d]="FAIL META.yaml not an Engine auto-dock of a client card"; R_FS[$d]=-; continue; }
    UNDOCK_META=1
  fi
  # 1) undock (unmount only; META.yaml is removed later, and only if the card checks clean)
  if [ $DOCKED = 1 ] && [ $DRY = 0 ]; then
    for m in $(findmnt -rn -o SOURCE,TARGET | awk -v a="$P1" -v b="$P2" '$1==a||$1==b{print $2}'); do
      [ -f "$m/META.yaml" ] && cp -a "$m/META.yaml" "$Q/META.yaml.before-undock"; log "unmount Engine mount $m"; umount "$m" || { R_RES[$d]="FAIL could not unmount $m"; R_FS[$d]=-; continue 2; }; done
  fi
  # 2) read-only fsck BEFORE any write
  if findmnt -rn -S "$P2" >/dev/null || findmnt -rn -S "$P1" >/dev/null; then R_FS[$d]="skipped(mounted)"
    R_RES[$d]=$([ $DRY = 1 ] && echo "DRY card is mounted (Engine dock): fsck runs in the live --undock run" || echo "FAIL still mounted"); continue; fi
  fsck_stage "$d" ""; R_FS[$d]=$FSCK
  if [ -n "$SUSPECT" ]; then R_RES[$d]="SUSPECT - DO NOT PACK (not patched; $SUSPECT)"; continue; fi
  if [ "$PSK" != ok ] || [ "$POLOK" != json ]; then R_RES[$d]="FAIL psk=$PSK policy=$POLOK (not patched)"; continue; fi
  # 3) patch only a clean card
  ACT="already patched"
  [ "$PSHA" = "$POL_S15_SHA" ] || [ $NEED_POL = 1 ] || { R_RES[$d]="FAIL chrome policy differs from s15 but has no NewTabPageLocation (not patched)"; continue; }
  if [ $NEED -gt 0 ] || [ $UNDOCK_META = 1 ]; then
    WHAT="$([ $NEED_KBD = 1 ] && echo ' keyboard')$([ $NEED_XK = 1 ] && echo ' xorg-kbd')$([ $NEED_POL = 1 ] && echo ' chrome-policy')$([ $UNDOCK_META = 1 ] && echo ' remove-Engine-META')"
    if [ $DRY = 1 ]; then R_RES[$d]="DRY clean; would patch:$WHAT"; continue; fi
    log "patching:$WHAT (backups in $Q)"
    if ! patch_card "$d" "$SER" "$SZ" "$Q" 2>&1 | sed "s/^/$(date +%T) [$CUR]   /"; then R_RES[$d]="FAIL patch step (see log; backups $Q)"; continue; fi
    sleep 12   # wh's Engine can re-dock on the udev change event after the lock is released
    if findmnt -rn -S "$P2" >/dev/null || findmnt -rn -S "$P1" >/dev/null; then
      for m in $(findmnt -rn -o SOURCE,TARGET | awk -v a="$P1" -v b="$P2" '$1==a||$1==b{print $2}'); do
        if [ -f "$m/META.yaml" ] && findmnt -no OPTIONS "$m" | grep -qw rw; then mv "$m/META.yaml" "$Q/META.yaml.post-redock"; log "Engine re-docked: META.yaml quarantined from $m"; fi
        log "unmount re-dock $m"; umount "$m" || log "WARNING: could not unmount $m"; done
    fi
    check "$d"; R_KBD[$d]=$KL; R_POL[$d]=$([ $NEED_POL = 1 ] && echo NewTab-present || echo ok)
    [ $((NEED_KBD+NEED_XK+NEED_POL)) = 0 ] || { R_RES[$d]="FAIL verify kbd=$NEED_KBD xorg=$NEED_XK pol=$NEED_POL"; continue; }
    dexists "$P2" /META.yaml && { R_RES[$d]="FAIL META.yaml still on card"; continue; }
    if findmnt -rn -S "$P2" >/dev/null; then R_RES[$d]="FAIL re-mounted after patch"; continue; fi
    # read-back guard (Steve 13:07): drop caches, read the files back from the card itself, compare with s15 manifest
    sync; echo 3 > /proc/sys/vm/drop_caches; blockdev --flushbufs "$P2" 2>/dev/null || true
    RB_OK=1; for f in /etc/default/keyboard "$POL"; do exp=$(awk -v f="$f" '$2==f{print $1}' "$MAN"); got=$(dsha "$P2" "$f")
      [ "$got" = "$exp" ] && log "read-back $f: sha256 = s15" || { RB_OK=0; log "read-back $f: MISMATCH got=$got exp=$exp"; }; done
    if dexists "$P2" "$XK"; then [ "$(dcat "$P2" "$XK" | sed -n 's/.*"XkbLayout" *"\([^"]*\)".*/\1/p')" = us ] && log "read-back $XK: XkbLayout us" || { RB_OK=0; log "read-back $XK: not us"; }; fi
    printf '%s\n' "$(cat "$Q/SHA256SUMS.after" 2>/dev/null)" | sed 's/^/    written: /'
    [ $RB_OK = 1 ] || { R_RES[$d]="FAIL read-back mismatch (backups $Q)"; R_FS[$d]=-; continue; }
    fsck_stage "$d" "-after"; R_FS[$d]="clean/after:$FSCK"
    [ -n "$SUSPECT" ] && { R_RES[$d]="SUSPECT - DO NOT PACK (after patch: $SUSPECT)"; continue; }
    ACT="patched"
  fi
  R_RES[$d]="PASS $ACT"
done
CUR=-
echo; F='%-6s %-14s %-24s %-5s %-15s %-14s %-5s %-24s %s\n'
printf "$F" DEV READER VERSION KBD CHROME-POLICY OVERLAY PSK FSCK RESULT
rc=0; for d in "${ORDER[@]}"; do printf "$F" "${d#/dev/}" "${R_SER[$d]}" "${R_VER[$d]}" "${R_KBD[$d]}" "${R_POL[$d]}" "${R_OVL[$d]%%(*}" "${R_PSK[$d]}" "${R_FS[$d]:--}" "${R_RES[$d]:-?}"; [[ "${R_RES[$d]:-}" == FAIL* || "${R_RES[$d]:-}" == SUSPECT* ]] && rc=1; done
[ ${#ORDER[@]} = 0 ] && { echo "no IDEA client card found"; rc=3; }
id pi >/dev/null 2>&1 && chown -R pi:pi "$QBASE"/clientcard-*-"$TS"* 2>/dev/null
sync; echo "Pack only PASS cards. A card is safe to pull when 'lsblk' shows it unmounted."
exit $rc
