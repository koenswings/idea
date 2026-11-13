#!/usr/bin/env bash
# move-79-remote.sh — Pi-side half of move-79.sh. Sent over ssh as `bash -s -- <sub> <args...>` (never installed).
# Runs as pi. Root only through sudo -n with absolute paths: the #343 loop forms
#   /usr/sbin/losetup -f --show <img> | /usr/sbin/losetup -d /dev/loopN | /usr/bin/mount -t ext4 | /usr/bin/umount
# and, for the window prerequisites only (winsetup / winrestore):
#   /usr/bin/tee -a <app-data-roots> | /usr/bin/cp <backup> <app-data-roots> | /usr/bin/chown | /usr/bin/chmod
#   /usr/bin/install -d -o pi -g pi -m 0755 <slot> | /usr/bin/rmdir <slot>   (app-data-roots is 0644: read as pi)
# Never `losetup -D`, never rm -rf, never an SSH key file write: teardown moves image + state into
# <scratch>/quarantine-<stamp>/; the window backup lives in <scratch>/quarantine-window-<stamp>/.
#
#   probe   <scratch> <image> <engineDir> [<slots,> <root> <config> <minSha>]  read-only facts (KEY=VALUE + sections)
#   winsetup   <scratch> <root> <slot> <config> <stamp>   back up + set app-data-roots slot line, root-own <root>, peerAccess: true
#   winrestore <scratch>                                  restore exactly what winsetup changed, then verify (sha256 + stat)
#   create  <scratch> <root> <watch> <slot> <diskId> <sizeGB> <prefix> <protected-serials> [<instance> <image> <dataMB>]
#   dock    <scratch> <watch> <diskId>                fire the testMode sentinel <watch>/<slot> (unlink + create)
#   undock  <scratch> <watch> <diskId>                remove the sentinel (the Engine undocks the disk)
#   detach  <scratch> <diskId> <stamp>                umount our slot, detach OUR loop device, quarantine image + state
#   freeslot <scratch> <root> <watch>                 first idea-test-N (1..8): no sentinel, not recorded, absent or empty + unmounted
#   manifest <dir>                                    "sha256  relpath" per file, sorted (read-only)
#   guardsnap                                         hands-off containers: id|name|state|startedAt (read-only)
set -uo pipefail
# Read-only losetup and mkfs paths; overridable only by the offline test (env does not cross ssh).
LOSETUP_RO="${MV79_LOSETUP:-/usr/sbin/losetup}"; MKFS="${MV79_MKFS:-/usr/sbin/mkfs.ext4}"
APPDATA="${MV79_APPDATA_ROOTS:-/etc/idea/app-data-roots}"; ROOT_OWNER="${MV79_ROOT_OWNER:-0:0}"
PEER_PUB="${MV79_PEER_KEY:-$HOME/.ssh/idea_engine_ed25519.pub}"; AUTHZ="${MV79_AUTHZ:-/etc/ssh/idea_authorized_keys/pi}"
sub="${1:-}"; shift || true
refuse() { echo "REFUSE: $*"; exit 10; }
st_get() { sed -n "s/^$2=//p" "$1" | head -1; }
disk_serial_of_path() {  # serial of the whole disk holding a path ('' for loop/none)
  local src pk; src="$(findmnt -n -o SOURCE -T "$1" 2>/dev/null | sed 's/\[.*\]$//')"
  pk="$(lsblk -no PKNAME "$src" 2>/dev/null | head -1)"; [ -n "$pk" ] || pk="$(basename "$src")"
  lsblk -dno SERIAL "/dev/$pk" 2>/dev/null | head -1 | tr -d ' '
}
fstat() { stat -c '%u:%g %a %F' "$1" 2>/dev/null; }          # "0:0 644 regular file"
fsha() { sha256sum < "$1" 2>/dev/null | cut -d' ' -f1; }
appdata_problem() {  # '' when app-data-roots is a regular, non-symlink, root:root 0644 file
  if [ -L "$APPDATA" ]; then echo "is a symlink"; return; fi
  [ -e "$APPDATA" ] || { echo "is missing"; return; }
  local s; s="$(fstat "$APPDATA")"; [ "$s" = "$ROOT_OWNER 644 regular file" ] || echo "is '$s', want '$ROOT_OWNER 644 regular file'"; }
path_problem() {  # absolute, no trailing slash, no . / .. / empty components, no symlink anywhere in the path
  local p="$1" a="" c; [[ "$p" == /* ]] || { echo "not absolute"; return; }
  [ "$p" != / ] && [[ "$p" != */ ]] || { echo "trailing slash"; return; }
  [[ "/$p/" == *"/./"* || "/$p/" == *"/../"* || "$p" == *"//"* ]] && { echo "has . / .. / empty component"; return; }
  IFS=/ read -ra parts <<<"${p#/}"; for c in "${parts[@]}"; do a="$a/$c"; [ -L "$a" ] && { echo "component $a is a symlink"; return; }; done; }
root_problem() {  # the fixture root must be owned by ROOT_OWNER and not group/other writable
  local s m; s="$(stat -c '%u:%g' "$1" 2>/dev/null)"; m="$(stat -c '%a' "$1" 2>/dev/null)"
  [ -n "$s" ] || { echo "missing"; return; }; [ -L "$1" ] && { echo "is a symlink"; return; }
  [ "$s" = "$ROOT_OWNER" ] || { echo "owner $s, want $ROOT_OWNER"; return; }
  (( 8#$m & 8#022 )) && echo "mode $m is group/other writable"; }
config_peer() { local v; v="$(sed -n 's/^[[:space:]]\{1,\}peerAccess:[[:space:]]*\([a-z]*\).*/\1/p' "$1" 2>/dev/null | head -1)"; echo "${v:-unset}"; }
guardsnap() {
  docker ps -a --format '{{.ID}}|{{.Names}}|{{.State}}' 2>/dev/null \
    | grep -E '\|(kid-kolibri-demo[^|]*|idea166-[^|]*|nextcloud-files-b-001[^|]*|idea-hub-sidecar[^|]*)\|' \
    | while IFS='|' read -r id name state; do
        printf '%s|%s|%s|%s\n' "$id" "$name" "$state" "$(docker inspect -f '{{.State.StartedAt}}' "$id" 2>/dev/null)"; done | sort
}
case "$sub" in
probe)
  scratch="$1"; image="$2"; ED="${3:-/home/pi/idea/agents/agent-engine-dev}"
  slots="${4:-}" root="${5:-/home/pi/idea/duration-disks}" cfg="${6:-}" minsha="${7:-}"; [ -n "$cfg" ] || cfg="$ED/config.yaml"
  echo "HOSTNAME=$(hostname)"
  echo "TEMP=$(vcgencmd measure_temp 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)"
  echo "ENGINE_HEAD=$(git -C "$ED" rev-parse HEAD 2>/dev/null)"
  echo "STORE_URL=$(cat "$ED/store-identity/store-url.txt" 2>/dev/null)"
  rs="$(findmnt -n -o SOURCE / | sed 's/\[.*\]$//')"; rpk="$(lsblk -no PKNAME "$rs" 2>/dev/null | head -1)"
  echo "ROOT_DISK=${rpk:-$(basename "$rs")}"; echo "ROOT_SERIAL=$(disk_serial_of_path /)"
  mkdir -p "$scratch" 2>/dev/null || true
  echo "SCRATCH_SERIAL=$(disk_serial_of_path "$scratch")"
  echo "SCRATCH_AVAIL=$(df -B1 --output=avail "$scratch" 2>/dev/null | tail -1 | tr -d ' ')"
  echo "SUDO_LOSETUP=$(sudo -n /usr/sbin/losetup --version >/dev/null 2>&1 && echo yes || echo no)"
  echo "IMAGE_PRESENT=$(docker image inspect "$image" >/dev/null 2>&1 && echo yes || echo no)"
  echo "IMAGE_ID=$(docker image inspect -f '{{.Id}}' "$image" 2>/dev/null)"
  [ -n "$minsha" ] && echo "ENGINE_HAS_MIN=$(git -C "$ED" merge-base --is-ancestor "$minsha" HEAD 2>/dev/null && echo yes || echo no)"
  echo "APPDATA_PROBLEM=$(appdata_problem)"; echo "APPDATA_STAT=$(fstat "$APPDATA")"; echo "APPDATA_SHA=$(fsha "$APPDATA")"
  miss=""; bad=""; for sl in ${slots//,/ }; do grep -qxF -- "$root/$sl" "$APPDATA" 2>/dev/null || miss="$miss $root/$sl"
    pp="$(path_problem "$root/$sl")"; [ -z "$pp" ] || bad="$bad $root/$sl: $pp;"; done
  echo "APPDATA_MISSING_SLOTS=${miss# }"; echo "SLOT_PATH_PROBLEMS=${bad# }"
  echo "FIXROOT_PROBLEM=$(root_problem "$root")"; echo "FIXROOT_STAT=$(stat -c '%u:%g %a' "$root" 2>/dev/null)"; echo "FIXROOT_PATH_PROBLEM=$(path_problem "$root")"
  echo "CONFIG_PATH=$cfg"; echo "CONFIG_PEERACCESS=$(config_peer "$cfg")"; echo "CONFIG_SHA=$(fsha "$cfg")"; echo "CONFIG_STAT=$(fstat "$cfg")"
  echo "WINDOW_ACTIVE=$([ -f "$scratch/window.win" ] && echo yes || echo no)"
  echo "ENGINE_PUB=$(awk '{print $2}' "$PEER_PUB" 2>/dev/null)"
  echo "AUTHZ_READABLE=$([ -r "$AUTHZ" ] && echo yes || echo no)"
  pm2 jlist 2>/dev/null | python3 -c '
import json,sys
try: ps=json.load(sys.stdin)
except Exception: ps=[]
for p in ps:
  if p.get("name")=="engine":
    e=p.get("pm2_env",{}); env=e.get("env",{}) or {}
    g=lambda k: e.get(k, env.get(k,""))
    print("PM2_ENGINE=%s %s" % (e.get("status",""), e.get("username","")))
    for k in ("IDEA_TEST_MODE","IDEA_DISKS_ROOT","IDEA_WATCH_DIR","IDEA_CONFIG_FILE"): print("%s=%s" % (k, g(k)))' 2>/dev/null
  echo "APP_DATA_ROOTS=$(tr '\n' ' ' < "$APPDATA" 2>/dev/null)"
  echo "CONSOLE_HTTP=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1/ 2>/dev/null)"
  echo "--- LSBLK"; lsblk -dnro NAME,SERIAL,SIZE,TYPE 2>/dev/null
  echo "--- LOOPS"; "$LOSETUP_RO" -n -l -O NAME,BACK-FILE 2>/dev/null
  echo "--- SCRATCH_STATE"; for f in "$scratch"/*.state; do [ -f "$f" ] && { echo "## $f"; cat "$f"; }; done
  echo "--- GUARD"; guardsnap
  echo "--- AUTHZ"; sed -n 's/.*idea-peer-gate \([^"]*\)".* ssh-ed25519 \([A-Za-z0-9+/=]*\).*/\1 \2/p' "$AUTHZ" 2>/dev/null
  echo "--- SUDO_L"; LC_ALL=C sudo -n -l 2>&1 | head -60     # read-only: lists pi's sudo rules, changes nothing
  echo "--- WINDOW"; cat "$scratch/window.win" 2>/dev/null
  echo "--- END" ;;
winsetup)
  scratch="$1" root="$2" slot="$3" cfg="$4" stamp="$5"
  [[ "$slot" =~ ^idea-test-[0-9]+$ ]] || refuse "slot $slot is not idea-test-N"
  case "$root" in /disks|/disks/*|/) refuse "disks root $root is not a fixture root" ;; esac
  [ -f "$scratch/window.win" ] && refuse "a window is already set up ($scratch/window.win); restore it first"
  pr="$(appdata_problem)"; [ -z "$pr" ] || refuse "$APPDATA $pr (setup only works on a regular root:root 0644 file)"
  pr="$(path_problem "$root")"; [ -z "$pr" ] || refuse "fixture root $root: $pr"
  [ -d "$root" ] || refuse "fixture root $root missing"
  sp="$root/$slot"; pr="$(path_problem "$sp")"; [ -z "$pr" ] || refuse "slot path $sp: $pr"
  [ -f "$cfg" ] && [ ! -L "$cfg" ] || refuse "Engine config $cfg missing or a symlink"
  for c in /usr/bin/chown /usr/bin/chmod /usr/bin/tee /usr/bin/cp /usr/bin/install /usr/bin/rmdir; do
    sudo -n -l "$c" >/dev/null 2>&1 || refuse "sudo -n not allowed for $c (never changing sudoers)"; done
  bk="$scratch/quarantine-window-$stamp"; mkdir -p "$bk" || refuse "mkdir $bk"
  cat "$APPDATA" > "$bk/app-data-roots.orig" || refuse "backup of $APPDATA failed"
  cp -p "$cfg" "$bk/config.orig" || refuse "backup of $cfg failed"
  aStat="$(fstat "$APPDATA")" aSha="$(fsha "$APPDATA")" rStat="$(stat -c '%u:%g %a' "$root")" cStat="$(fstat "$cfg")" cSha="$(fsha "$cfg")"
  [ "$(fsha "$bk/app-data-roots.orig")" = "$aSha" ] && [ "$(fsha "$bk/config.orig")" = "$cSha" ] || refuse "backup copies do not match the originals"
  { printf 'backup=%s\nappdata=%s\nappdataStat=%s\nappdataSha=%s\nroot=%s\nrootStat=%s\nslot=%s\nconfig=%s\nconfigStat=%s\nconfigSha=%s\n' \
      "$bk" "$APPDATA" "$aStat" "$aSha" "$root" "$rStat" "$slot" "$cfg" "$cStat" "$cSha"; } > "$bk/window.orig"
  cp "$bk/window.orig" "$scratch/window.win"
  # 1. fixture root root-owned, not group/other writable (original owner/mode recorded above)
  if [ -n "$(root_problem "$root")" ]; then echo "rootChanged=1" >> "$scratch/window.win"; { sudo -n /usr/bin/chown "$ROOT_OWNER" "$root" && sudo -n /usr/bin/chmod go-w "$root"; } || refuse "chown/chmod $root failed"
    echo "ROOT_FIXED $root $(stat -c '%u:%g %a' "$root") (was $rStat)"; fi
  [ -z "$(root_problem "$root")" ] || refuse "fixture root still $(root_problem "$root")"
  # 2. slot dir (pi-owned mount point inside the root-owned fixture root)
  if [ ! -e "$sp" ]; then echo "slotCreated=1" >> "$scratch/window.win"; sudo -n /usr/bin/install -d -o pi -g pi -m 0755 "$sp" || refuse "install -d $sp failed"; echo "SLOT_CREATED $sp"; fi
  [ -d "$sp" ] && [ ! -L "$sp" ] || refuse "slot $sp is not a plain directory"
  pr="$(path_problem "$sp")"; [ -z "$pr" ] || refuse "slot path $sp: $pr"
  # 3. app-data-roots: append only the slot line (newline first if the file does not end in one)
  if ! grep -qxF -- "$sp" "$APPDATA"; then
    if [ -s "$APPDATA" ] && [ -n "$(tail -c1 "$APPDATA")" ]; then pre=$'\n'; else pre=""; fi
    echo "appdataAppended=$sp" >> "$scratch/window.win"
    printf '%s%s\n' "$pre" "$sp" | sudo -n /usr/bin/tee -a "$APPDATA" >/dev/null || refuse "append to $APPDATA failed"; echo "APPDATA_APPENDED $sp"; fi
  [ -z "$(appdata_problem)" ] || refuse "$APPDATA now $(appdata_problem)"
  # 4. peerAccess: true in the Engine config (rewrite in place: same inode, owner, mode)
  if [ "$(config_peer "$cfg")" != true ]; then
    if grep -qE '^[[:space:]]+peerAccess:' "$cfg"; then sed -E '0,/^([[:space:]]+)peerAccess:.*/s//\1peerAccess: true   # move-79 window, restored at teardown/' "$cfg" > "$bk/config.new"
    else awk '{print} /^settings:[[:space:]]*$/ && !d {print "  peerAccess: true   # move-79 window, restored at teardown"; d=1}' "$cfg" > "$bk/config.new"; fi
    [ "$(config_peer "$bk/config.new")" = true ] || refuse "could not set peerAccess in $cfg (no settings: block?)"
    echo "configChanged=1" >> "$scratch/window.win"; cat "$bk/config.new" > "$cfg" || refuse "write $cfg failed"; echo "CONFIG_PEERACCESS_SET $cfg"; fi
  echo "SETUP_OK backup=$bk slot=$sp" ;;
winrestore)
  scratch="$1"; ws="$scratch/window.win"; [ -f "$ws" ] || refuse "no active window ($ws)"
  bk="$(st_get "$ws" backup)" root="$(st_get "$ws" root)" slot="$(st_get "$ws" slot)" cfg="$(st_get "$ws" config)"
  [ "$(st_get "$ws" appdata)" = "$APPDATA" ] || refuse "app-data-roots path differs from the one recorded"
  sp="$root/$slot"; bad=0
  if [ "$(st_get "$ws" slotCreated)" = 1 ] && [ -e "$sp" ]; then
    findmnt -n --mountpoint "$sp" >/dev/null && refuse "slot $sp is still mounted (teardown the disk first)"
    [ -z "$(ls -A "$sp")" ] || refuse "slot $sp is not empty; left in place"
    sudo -n /usr/bin/rmdir "$sp" || refuse "rmdir $sp failed"; echo "SLOT_REMOVED $sp"; fi
  if [ "$(st_get "$ws" rootChanged)" = 1 ]; then read -r o m <<<"$(st_get "$ws" rootStat)"
    { sudo -n /usr/bin/chown "$o" "$root" && sudo -n /usr/bin/chmod "$m" "$root"; } || refuse "restore owner/mode of $root failed"; echo "ROOT_RESTORED $root $o $m"; fi
  if [ -n "$(st_get "$ws" appdataAppended)" ]; then
    [ -L "$APPDATA" ] && refuse "$APPDATA became a symlink; not writing through it"
    sudo -n /usr/bin/cp "$bk/app-data-roots.orig" "$APPDATA" || refuse "restore $APPDATA failed"; fi
  read -r ao am _ <<<"$(st_get "$ws" appdataStat)"
  [ "$(fstat "$APPDATA" | cut -d' ' -f1-2)" = "$ao $am" ] || { sudo -n /usr/bin/chown "$ao" "$APPDATA"; sudo -n /usr/bin/chmod "$am" "$APPDATA"; }
  if [ "$(st_get "$ws" configChanged)" = 1 ]; then cat "$bk/config.orig" > "$cfg" || refuse "restore $cfg failed"; fi
  read -r _ cm _ <<<"$(st_get "$ws" configStat)"; [ "$(fstat "$cfg" | cut -d' ' -f2)" = "$cm" ] || chmod "$cm" "$cfg"
  for chk in "appdata|$APPDATA|$(st_get "$ws" appdataSha)|$(st_get "$ws" appdataStat)" "config|$cfg|$(st_get "$ws" configSha)|$(st_get "$ws" configStat)"; do
    IFS='|' read -r what f sha st <<<"$chk"
    if [ "$(fsha "$f")" = "$sha" ] && [ "$(fstat "$f")" = "$st" ]; then echo "VERIFY_OK $what $f sha256 $sha stat '$st'"
    else echo "RESTORE_MISMATCH $what $f sha256 $(fsha "$f") stat '$(fstat "$f")' (want $sha '$st')"; bad=1; fi; done
  if [ "$(stat -c '%u:%g %a' "$root")" = "$(st_get "$ws" rootStat)" ]; then echo "VERIFY_OK root $root '$(st_get "$ws" rootStat)'"
  else echo "RESTORE_MISMATCH root $root '$(stat -c '%u:%g %a' "$root")' (want '$(st_get "$ws" rootStat)')"; bad=1; fi
  [ $bad = 0 ] || exit 11
  mv "$ws" "$bk/window.win.restored" && echo "RESTORE_OK backup kept in $bk" ;;
create)
  scratch="$1" root="$2" watch="$3" slot="$4" id="$5" size="$6" prefix="$7" protected="$8"
  inst="${9:-}" image="${10:-}" datamb="${11:-16}"
  case "$id" in "$prefix"*) ;; *) refuse "disk id $id lacks scratch prefix $prefix" ;; esac
  [[ "$slot" =~ ^idea-test-[0-9]+$ ]] || refuse "slot $slot is not idea-test-N"
  [[ "$size" =~ ^[0-9]+$ ]] && [ "$size" -ge 1 ] && [ "$size" -le 16 ] || refuse "size ${size} GB outside 1..16"
  case "$root" in /disks|/disks/*|/) refuse "disks root $root is not a fixture root" ;; esac
  if [ -n "$inst" ]; then case "$inst" in "$prefix"*) ;; *) refuse "instance $inst lacks prefix $prefix" ;; esac
    if [[ "$inst" =~ kid-|kolibri|i159|idea166|nextcloud ]]; then refuse "instance $inst looks like a protected instance"; fi; fi
  # The image is a file on the Pi's own root fs. It must never live on Disk B, the WD or any other external disk;
  # the boot disk is never *selected* as an App disk (only /dev/loopN devices this script made are used).
  ser="$(disk_serial_of_path "$scratch")"; rser="$(disk_serial_of_path /)"
  for p in ${protected//,/ }; do if [ "$ser" = "$p" ] && [ "$ser" != "$rser" ]; then refuse "scratch $scratch lives on protected disk serial $p"; fi; done
  [ "$ser" = "$rser" ] || refuse "scratch $scratch is not on the root disk (serial '$ser' vs root '$rser')"
  mp="$root/$slot"; img="$scratch/img/$id.img"; st="$scratch/$id.state"
  [ -e "$st" ] && refuse "state $st exists (tear down first)"; [ -e "$img" ] && refuse "image $img exists"
  [ -e "$watch/$slot" ] && refuse "sentinel $watch/$slot already exists"
  grep -rlqs "^slot=$slot$" "$scratch"/*.state && refuse "slot $slot recorded by another scratch disk"
  made=0; if [ ! -d "$mp" ]; then mkdir "$mp" || refuse "mkdir $mp"; made=1; fi
  findmnt -n --mountpoint "$mp" >/dev/null && refuse "slot $mp is already a mount point"
  [ -z "$(ls -A "$mp")" ] || refuse "slot $mp is not empty"
  avail="$(df -B1 --output=avail "$scratch" | tail -1 | tr -d ' ')"
  [ "$avail" -gt $(( (size + 1) * 1073741824 )) ] || refuse "scratch free ${avail} B < ${size}+1 GiB"
  mkdir -p "$scratch/img"; truncate -s "${size}G" "$img"
  "$MKFS" -q -F -L "$(echo "$id" | tr '[:lower:]' '[:upper:]' | cut -c1-16)" -E root_owner=1000:1000 "$img" || refuse "mkfs failed"
  dev="$(sudo -n /usr/sbin/losetup -f --show "$img")" || refuse "losetup failed"
  [[ "$dev" =~ ^/dev/loop[0-9]+$ ]] || refuse "unexpected loop device '$dev'"
  bf="$("$LOSETUP_RO" -n -O BACK-FILE "$dev" | sed 's/ *$//')"
  if [ "$bf" != "$img" ]; then echo "REFUSE: $dev backs '$bf', not $img"; exit 10; fi
  printf 'diskId=%s\nloop=%s\nimage=%s\nslot=%s\nmount=%s\nwatch=%s\nslotCreated=%s\ninstance=%s\ncreated=%s\n' \
    "$id" "$dev" "$img" "$slot" "$mp" "$watch" "$made" "$inst" "$(date -Is)" > "$st"
  sudo -n /usr/bin/mount -t ext4 "$dev" "$mp" || refuse "mount $dev $mp failed (state kept in $st for detach)"
  now="$(date +%s000)"
  printf 'diskId: "%s"\nisHardwareId: false\ndiskName: "%s (scratch, move-79)"\ncreated: %s\nlastDocked: %s\n' "$id" "$id" "$now" "$now" > "$mp/META.yaml"
  mkdir -p "$mp/apps" "$mp/instances" "$mp/services"
  if [ -n "$inst" ]; then
    app=mv79web; ver=1.0
    compose() { cat <<YAML
# mv79web: scratch App for the move-79 loop-disk proof (agent-engine-dev#289). Not a real App.
services:
  web:
    image: $image
    pull_policy: never
    labels:
      org.idea.test: "true"
      org.idea.mv79: "true"
    ports:
      - "\${port}:80"
    volumes:
      - ./data:/data
    restart: "no"
x-app:
  name: $app
  version: "$ver"
${1:+  instanceName: $1}
  title: "move-79 scratch"
  description: "Scratch App for the move-79 loop-disk proof. Not a real App."
  category: "it"
  url: "http://localhost:\${port}"
  icon: ""
  author: "Atlas (IDEA Ops)"
YAML
    }
    mkdir -p "$mp/apps/$app-$ver" "$mp/instances/$inst/data"
    compose "" > "$mp/apps/$app-$ver/compose.yaml"; compose "$inst" > "$mp/instances/$inst/compose.yaml"
    echo "scratch $inst $(date -Is)" > "$mp/instances/$inst/data/hello.txt"
    head -c "$(( datamb * 1048576 ))" /dev/urandom > "$mp/instances/$inst/data/payload.bin"
  fi
  echo "CREATED diskId=$id loop=$dev slot=$slot mount=$mp image=$img instance=${inst:-none}" ;;
dock|undock)
  scratch="$1" watch="$2" id="$3"; st="$scratch/$id.state"; [ -f "$st" ] || refuse "no state for $id"
  slot="$(st_get "$st" slot)"; [ "$(st_get "$st" watch)" = "$watch" ] || refuse "watch dir differs from the one recorded"
  if [ "$sub" = dock ]; then mkdir -p "$watch"; rm -f "$watch/$slot"; sleep 5; touch "$watch/$slot"; echo "DOCK sentinel $watch/$slot"
  else rm -f "$watch/$slot"; echo "UNDOCK sentinel $watch/$slot removed"; fi ;;
detach)
  scratch="$1" id="$2" stamp="$3"; st="$scratch/$id.state"; [ -f "$st" ] || refuse "no state for $id"
  dev="$(st_get "$st" loop)" img="$(st_get "$st" image)" mp="$(st_get "$st" mount)" watch="$(st_get "$st" watch)" slot="$(st_get "$st" slot)"
  [[ "$dev" =~ ^/dev/loop[0-9]+$ ]] || refuse "recorded device '$dev' is not a loop device"
  [ -e "$watch/$slot" ] && refuse "sentinel still present (undock first)"
  src="$(findmnt -n -o SOURCE --mountpoint "$mp" 2>/dev/null || true)"
  if [ -n "$src" ]; then [ "$src" = "$dev" ] || refuse "$mp is mounted from $src, not our $dev"
    sudo -n /usr/bin/umount "$mp" || refuse "umount $mp failed (busy?)"; echo "UNMOUNTED $mp"; fi
  other="$(findmnt -n -o TARGET -S "$dev" 2>/dev/null || true)"; [ -z "$other" ] || refuse "$dev still mounted at $other"
  bf="$("$LOSETUP_RO" -n -O BACK-FILE "$dev" 2>/dev/null | sed 's/ *$//')"
  if [ "$bf" = "$img" ]; then sudo -n /usr/sbin/losetup -d "$dev" && echo "DETACHED $dev"
  elif [ -n "$bf" ]; then refuse "$dev now backs '$bf', not $img: not detaching"; else echo "ALREADY_DETACHED $dev"; fi
  if [ "$(st_get "$st" slotCreated)" = 1 ] && [ -d "$mp" ] && [ -z "$(ls -A "$mp")" ]; then rmdir "$mp" && echo "RMDIR empty slot $mp"; fi
  q="$scratch/quarantine-$stamp"; mkdir -p "$q"
  [ -e "$img" ] && mv "$img" "$q/" && echo "QUARANTINED $q/$(basename "$img")"
  mv "$st" "$q/" && echo "QUARANTINED $q/$(basename "$st")" ;;
manifest)
  d="$1"; [ -d "$d" ] || refuse "no dir $d"
  (cd "$d" && { sudo -n /usr/bin/find . -type f -printf '%P\n' 2>/dev/null || find . -type f -printf '%P\n'; } | LC_ALL=C sort \
    | while IFS= read -r f; do { sudo -n /usr/bin/sha256sum "$f" 2>/dev/null || sha256sum "$f"; }; done) ;;
freeslot)
  scratch="$1" root="$2" watch="$3"
  for n in 1 2 3 4 5 6 7 8; do d="$root/idea-test-$n"
    [ -e "$watch/idea-test-$n" ] && continue
    grep -qs "^slot=idea-test-$n$" "$scratch"/*.state && continue
    if [ ! -e "$d" ]; then echo "idea-test-$n"; exit 0; fi
    findmnt -n --mountpoint "$d" >/dev/null && continue
    [ -z "$(ls -A "$d" 2>/dev/null)" ] && { echo "idea-test-$n"; exit 0; }
  done; exit 1 ;;
guardsnap) guardsnap ;;
*) echo "usage: probe|winsetup|winrestore|create|dock|undock|detach|freeslot|manifest|guardsnap" >&2; exit 2 ;;
esac
