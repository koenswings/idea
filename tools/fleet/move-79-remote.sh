#!/usr/bin/env bash
# move-79-remote.sh — Pi-side half of move-79.sh. Sent over ssh as `bash -s -- <sub> <args...>` (never installed).
# Runs as pi. Root only through the exact sudo forms the #343 loop fixtures used:
#   sudo -n /usr/sbin/losetup -f --show <img> | sudo -n /usr/sbin/losetup -d /dev/loopN
#   sudo -n /usr/bin/mount -t ext4 /dev/loopN <slot> | sudo -n /usr/bin/umount <slot>
# Never `losetup -D`, never rm -rf: teardown moves image + state into <scratch>/quarantine-<stamp>/.
#
#   probe   <scratch> <image> <engineDir>                      read-only facts (KEY=VALUE lines + RAW sections)
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
sub="${1:-}"; shift || true
refuse() { echo "REFUSE: $*"; exit 10; }
st_get() { sed -n "s/^$2=//p" "$1" | head -1; }
disk_serial_of_path() {  # serial of the whole disk holding a path ('' for loop/none)
  local src pk; src="$(findmnt -n -o SOURCE -T "$1" 2>/dev/null | sed 's/\[.*\]$//')"
  pk="$(lsblk -no PKNAME "$src" 2>/dev/null | head -1)"; [ -n "$pk" ] || pk="$(basename "$src")"
  lsblk -dno SERIAL "/dev/$pk" 2>/dev/null | head -1 | tr -d ' '
}
guardsnap() {
  docker ps -a --format '{{.ID}}|{{.Names}}|{{.State}}' 2>/dev/null \
    | grep -E '\|(kid-kolibri-demo[^|]*|idea166-[^|]*|nextcloud-files-b-001[^|]*|idea-hub-sidecar[^|]*)\|' \
    | while IFS='|' read -r id name state; do
        printf '%s|%s|%s|%s\n' "$id" "$name" "$state" "$(docker inspect -f '{{.State.StartedAt}}' "$id" 2>/dev/null)"; done | sort
}
case "$sub" in
probe)
  scratch="$1"; image="$2"; ED="${3:-/home/pi/idea/agents/agent-engine-dev}"
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
  echo "APP_DATA_ROOTS=$(tr '\n' ' ' < /etc/idea/app-data-roots 2>/dev/null)"
  echo "CONSOLE_HTTP=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1/ 2>/dev/null)"
  echo "--- LSBLK"; lsblk -dnro NAME,SERIAL,SIZE,TYPE 2>/dev/null
  echo "--- LOOPS"; "$LOSETUP_RO" -n -l -O NAME,BACK-FILE 2>/dev/null
  echo "--- SCRATCH_STATE"; for f in "$scratch"/*.state; do [ -f "$f" ] && { echo "## $f"; cat "$f"; }; done
  echo "--- GUARD"; guardsnap
  echo "--- END" ;;
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
*) echo "usage: probe|create|dock|undock|detach|freeslot|manifest|guardsnap" >&2; exit 2 ;;
esac
