#!/usr/bin/env bash
# move-79.test.sh — offline tests for move-79.sh + move-79-remote.sh (no Pi, no GitHub, real fleet-state untouched).
# A fake ssh runs the Pi-side script locally in a per-host sandbox ($W/<host>), with fake vcgencmd, pm2, docker,
# curl, findmnt, lsblk, sudo (losetup/mount/umount), and a fake Engine store reader (npx tsx .zz-move-79.ts) that
# docks a disk when its testMode sentinel exists and performs moveApp by copy + quarantine.
# Usage: tools/fleet/move-79.test.sh   (exit 0 = all pass)
set -uo pipefail
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; S="$D/move-79.sh"; R="$D/move-79-remote.sh"
REPO_ROOT="$(git -C "$D" rev-parse --show-toplevel)"
real_fp() { cat "$REPO_ROOT/fleet-state.json" "$REPO_ROOT"/audit/*.jsonl 2>/dev/null | sha256sum; }
REAL_BEFORE="$(real_fp)"
pass=0; fail=0
check() { local n="$1"; shift; if "$@"; then echo "PASS $n"; pass=$((pass+1)); else echo "FAIL $n"; fail=$((fail+1)); fi; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/ops"; export W
SRC=100.126.117.80; TGT=100.108.39.45

# ---------- fakes ----------
cat > "$W/bin/fakessh" <<'SH'
#!/usr/bin/env bash
host="${1#pi@}"; shift; R="$W/$host"; cmd="$*"; cmd="${cmd//@ROOT@/$R}"
echo "$host :: ${cmd:0:160}" >> "$W/ssh.log"
[ -n "${FAKE_UNREACH:-}" ] && [ "$FAKE_UNREACH" = "$host" ] && exit 255
export FAKE_HOST="$host" FAKE_R="$R" MV79_LOSETUP="$W/bin/losetup-ro" MV79_MKFS="$W/bin/mkfs-fake"
exec bash -c "$cmd"
SH
cat > "$W/bin/vcgencmd" <<'SH'
#!/usr/bin/env bash
echo "temp=$(cat "$FAKE_R/temp" 2>/dev/null || echo 50.0)'C"
SH
cat > "$W/bin/pm2" <<'SH'
#!/usr/bin/env bash
cat "$FAKE_R/pm2.json"
SH
cat > "$W/bin/curl" <<'SH'
#!/usr/bin/env bash
printf 200
SH
cat > "$W/bin/docker" <<'SH'
#!/usr/bin/env bash
case "$1 $2" in
  "ps -a") if [[ "$*" == *org.idea.mv79* ]]; then exit 0; fi; cat "$FAKE_R/docker-ps" ;;
  "inspect -f") grep "^$4 " "$FAKE_R/docker-started" | cut -d' ' -f2 ;;
  "image inspect") [ -e "$FAKE_R/image-present" ] ;;
  *) echo "FORBIDDEN docker $*" >> "$W/forbidden.log"; exit 9 ;;
esac
SH
cat > "$W/bin/findmnt" <<'SH'
#!/usr/bin/env bash
T="$FAKE_R/mounts"; touch "$T"
a="$*"
case "$a" in
  "-n -o SOURCE /") echo /dev/sda2 ;;
  "-n -o SOURCE -T /") echo /dev/sda2 ;;
  "-n -o SOURCE -T "*) cat "$FAKE_R/scratch-dev" 2>/dev/null || echo /dev/sda2 ;;
  "-n --mountpoint "*) grep -q " ${a#-n --mountpoint } *$" "$T" ;;
  "-n -o SOURCE --mountpoint "*) awk -v m="${a#-n -o SOURCE --mountpoint }" '$2==m{print $1}' "$T" ;;
  "-n -o TARGET -S "*) awk -v d="${a#-n -o TARGET -S }" '$1==d{print $2}' "$T" ;;
  *) echo "findmnt? $a" >&2; exit 1 ;;
esac
SH
cat > "$W/bin/lsblk" <<'SH'
#!/usr/bin/env bash
case "$*" in
  "-no PKNAME /dev/sda2") echo sda ;; "-no PKNAME /dev/sdb1") echo sdb ;;
  "-dno SERIAL /dev/sda") cat "$FAKE_R/root-serial" ;; "-dno SERIAL /dev/sdb") echo 3813430-532011020 ;;
  -dnro*) echo "sda $(cat "$FAKE_R/root-serial") 223G disk"; echo "sdb 3813430-532011020 111G disk" ;;
  *) exit 0 ;;
esac
SH
cat > "$W/bin/sudo" <<'SH'
#!/usr/bin/env bash
[ "$1" = -n ] && shift
echo "$FAKE_HOST sudo $*" >> "$W/sudo.log"
L="$FAKE_R/loops"; T="$FAKE_R/mounts"; touch "$L" "$T"
case "$1" in
  /usr/sbin/losetup) shift
    case "$*" in
      --version) exit 0 ;;
      "-f --show "*) n=$(( $(cat "$FAKE_R/loopn" 2>/dev/null || echo 10) + 1 )); echo $n > "$FAKE_R/loopn"
                     echo "/dev/loop$n $3" >> "$L"; echo "/dev/loop$n" ;;
      "-d /dev/loop"*) grep -q "^$2 " "$L" || exit 1; grep -v "^$2 " "$L" > "$L.t"; mv "$L.t" "$L" ;;
      *) echo "FORBIDDEN losetup $*" >> "$W/forbidden.log"; exit 9 ;;
    esac ;;
  /usr/bin/mount) [ "$2 $3" = "-t ext4" ] || exit 9; echo "$4 $5" >> "$T" ;;
  /usr/bin/umount) grep -v " $2$" "$T" > "$T.t"; mv "$T.t" "$T" ;;
  /usr/bin/find|/usr/bin/sha256sum) exit 1 ;;
  *) echo "FORBIDDEN sudo $*" >> "$W/forbidden.log"; exit 9 ;;
esac
SH
cat > "$W/bin/losetup-ro" <<'SH'
#!/usr/bin/env bash
L="$FAKE_R/loops"; touch "$L"
case "$*" in
  "-n -O BACK-FILE "*) awk -v d="$4" '$1==d{print $2}' "$L" ;;
  "-n -l -O NAME,BACK-FILE") cat "$L" ;;
esac
SH
printf '#!/usr/bin/env bash\nexit 0\n' > "$W/bin/mkfs-fake"
cat > "$W/bin/npx" <<'SH'
#!/usr/bin/env bash
# fake: npx tsx script/.zz-move-79.ts <mode> [args]
shift 2; exec python3 "$W/bin/engine.py" "$@"
SH
cat > "$W/bin/engine.py" <<'PY'
import json, os, sys, glob, shutil, time, re
W=os.environ['W']; R=os.environ['FAKE_R']; mode=sys.argv[1]; args=sys.argv[2:]
def disks(r):
    out=[]
    for s in sorted(glob.glob(r+'/watch/idea-test-*')):
        slot=os.path.basename(s); meta=r+'/fixroot/'+slot+'/META.yaml'
        if os.path.exists(meta):
            did=re.search(r'diskId: "([^"]+)"', open(meta).read()).group(1); out.append({'id':did,'name':did,'device':slot,'root':r+'/fixroot/'+slot})
    return out
def insts(r):
    out=[]
    for d in disks(r):
        for i in sorted(glob.glob(d['root']+'/instances/*')):
            c=open(i+'/compose.yaml').read(); m=re.search(r'instanceName: (\S+)', c)
            out.append({'id':os.path.basename(i),'name':m.group(1) if m else os.path.basename(i),'instanceOf':'mv79web','status':'Running','diskId':d['id'],'port':18500,'lastStarted':1})
    return out
hosts=[h for h in glob.glob(W+'/1*') if os.path.isdir(h)]
if mode=='state':
    print(json.dumps({'engineId':'e-'+os.path.basename(R),'hostname':os.path.basename(R),'lastBooted':1,'moveAppCrossEngine': not os.path.exists(R+'/nocap'),
        'disks':[{k:d[k] for k in ('id','name','device')} for d in disks(R)],'instances':insts(R)}))
elif mode=='find':
    for h in hosts:
        for i in insts(h):
            if i['name']==args[0]: print(json.dumps(dict(i, dockedTo='e-'+os.path.basename(h))))
elif mode=='op':
    p=W+'/ops/'+args[0]+'.json'; print(open(p).read().strip() if os.path.exists(p) else json.dumps({'error':'no moveApp op'}))
elif mode=='cmd':
    assert args[0]=='moveApp', args; sid,fd,td=args[1:4]
    src=[d for d in disks(R) if d['id']==fd][0]; tgt=[(h,d) for h in hosts for d in disks(h) if d['id']==td][0][1]
    nid=sid+'-m'+str(len(os.listdir(W+'/ops'))+1)
    shutil.copytree(src['root']+'/instances/'+sid, tgt['root']+'/instances/'+nid, symlinks=True)
    q=src['root']+'/.idea-quarantine/'+sid+'-1'; os.makedirs(os.path.dirname(q), exist_ok=True); shutil.move(src['root']+'/instances/'+sid, q)
    json.dump({'id':'op1','status':'Done','move':{'code':'MOVED','targetInstanceId':nid,'quarantinePath':q}}, open(W+'/ops/'+sid+'.json','w'))
    if os.path.exists(W+'/tamper'):
        p=W+'/100.126.117.80/docker-started'; open(p,'w').write(open(p).read().replace('2026-11-13T08:00:00Z','2026-11-13T10:10:10Z'))
    print(json.dumps({'trace':'moveApp','status':'ok','errorCode':None,'errorMessage':None,'result':None}))
PY
chmod +x "$W/bin/"*
REALPATH="$PATH"
export PATH="$W/bin:$PATH" SSH_CMD="$W/bin/fakessh" STATE_FILE="$W/fleet-state.json" BOT_NAME=Atlas \
  MV_SCRATCH="@ROOT@/scratch" MV_FIXTURE_ROOT="@ROOT@/fixroot" MV_FIXTURE_WATCH="@ROOT@/watch" MV_ENGINE_DIR="@ROOT@/engine" \
  DOCK_WAIT=10 TEMP_POLL=0
MV_FIX_ROOT_FOR() { echo "$W/$1/fixroot"; }

reset_state() {  # $1 = claim for idea03/idea04
  local c="${1:-Atlas #289 move-79}"
  jq -n --arg c "$c" '{
   _comment:"test",
   idea01:{role:"golden",status:"idle",claim:$c,tailscale:"100.99.231.94"},
   idea02:{role:"fleet-pending",status:"idle",claim:$c,tailscale:"100.85.108.118"},
   idea03:{role:"spare",status:"testing",claim:$c,tailscale:"100.126.117.80",lan:"192.168.0.228"},
   idea04:{role:"spare",status:"testing",claim:$c,tailscale:"100.108.39.45",lan:"192.168.0.113"},
   "wizardly-hugle":{role:"production",status:"idle",claim:$c,host:"192.168.0.231",tailscale:"100.115.60.6"},
   "kind-panda":{role:"kit-engine",status:"kit",claim:$c,tailscale:"100.80.238.59"},
   idea05:{role:"spare",status:"idle",claim:$c,tailscale:"100.115.60.6"} }' > "$STATE_FILE"
}
reset_hosts() {
  rm -rf "${W:?}/${SRC:?}" "${W:?}/${TGT:?}" "${W:?}/ops"; mkdir -p "$W/ops"; : > "$W/sudo.log"; : > "$W/forbidden.log"
  for h in "$SRC" "$TGT"; do
    mkdir -p "$W/$h/engine/script" "$W/$h/engine/store-identity" "$W/$h/fixroot/idea-test-1" "$W/$h/watch" "$W/$h/scratch"
    echo "automerge:2VroEUvDkmYsDAwE5oG9YeFNadWH" > "$W/$h/engine/store-identity/store-url.txt"
    git -C "$W/$h/engine" init -q && git -C "$W/$h/engine" -c user.email=t@t -c user.name=t commit -q --allow-empty -m x
    touch "$W/$h/image-present"; echo 50.1 > "$W/$h/temp"
    jq -n --arg r "@ROOT@" '[{name:"engine",pm2_env:{status:"online",username:"pi",env:{IDEA_TEST_MODE:"true",IDEA_DISKS_ROOT:($r+"/fixroot"),IDEA_WATCH_DIR:($r+"/watch")}}}]' > "$W/$h/pm2.json"
    : > "$W/$h/docker-ps"; : > "$W/$h/docker-started"
  done
  echo AA202000000000004820 > "$W/$SRC/root-serial"; echo AA202000000000002167 > "$W/$TGT/root-serial"
  # idea03: Kid's demo + hands-off sidecars; slot 1 already used by something else (not empty)
  printf 'k1|kid-kolibri-demo-kolibri-1|running\ns1|idea166-kolibri-live|exited\nh1|idea-hub-sidecar|exited\n' > "$W/$SRC/docker-ps"
  printf 'k1 2026-11-13T08:00:00Z\ns1 2026-11-13T04:00:00Z\nh1 2026-11-13T04:00:00Z\n' > "$W/$SRC/docker-started"
  echo busy > "$W/$SRC/fixroot/idea-test-1/other"
}
# app-data-roots is read from /etc on the "Pi": the fake root cannot provide it, so preflight would FAIL on it.
# Shim: a cat that maps /etc/idea/app-data-roots to the sandbox.
cat > "$W/bin/tr" <<'SH'
#!/usr/bin/env bash
exec /usr/bin/tr "$@"
SH
mkdir -p "$W/etcshim"
run() { "$S" "$@" > "$W/out" 2>&1; echo $? > "$W/rc"; }
rc() { cat "$W/rc"; }
has() { grep -q -- "$1" "$W/out"; }
nossh() { ! [ -s "$W/ssh.log" ]; }

# The probe reads /etc/idea/app-data-roots; point the remote script at a sandbox copy via a sed'd copy.
REMOTE_ORIG="$R"; cp "$R" "$W/remote.sh.orig"
sed -i "s#/etc/idea/app-data-roots#\$FAKE_R/app-data-roots#" "$R"
restore_remote() { cp "$W/remote.sh.orig" "$REMOTE_ORIG"; }
trap 'restore_remote; rm -rf "$W"' EXIT
add_roots() { for h in "$SRC" "$TGT"; do echo "@ROOT@/fixroot" > "$W/$h/app-data-roots"; done; }   # tokens: compared box-side as-is

echo "== syntax / lint"
check "bash -n move-79.sh" bash -n "$S"
check "bash -n move-79-remote.sh" bash -n "$W/remote.sh.orig"
if command -v shellcheck >/dev/null; then check "shellcheck clean" shellcheck -x "$S" "$W/remote.sh.orig"; else echo "SKIP shellcheck (not installed)"; fi
check "no losetup -D anywhere (code lines)" bash -c "! grep -hvE '^ *#' '$S' '$W/remote.sh.orig' | grep -nE 'losetup +(-[a-zA-Z]*D|--detach-all)'"
check "no rm -rf / rm -r in the scripts (code lines)" bash -c "! grep -hvE '^ *#' '$S' '$W/remote.sh.orig' | grep -nE '(^|[^a-z])rm +-[a-zA-Z]*r'"

echo "== guards (no Pi contacted)"
reset_state; reset_hosts
: > "$W/ssh.log"; run --preflight --target idea01;            check "refuse target idea01 (golden)" bash -c "[ $(rc) = 4 ] && grep -q protected '$W/out'"; check "  no ssh" nossh
: > "$W/ssh.log"; run --preflight --target idea02;            check "refuse target idea02" bash -c "[ $(rc) = 4 ]"; check "  no ssh" nossh
: > "$W/ssh.log"; run --preflight --target wizardly-hugle;    check "refuse target wizardly-hugle" bash -c "[ $(rc) = 4 ]"; check "  no ssh" nossh
: > "$W/ssh.log"; run --preflight --target idea;              check "refuse target 'idea' (not in fleet-state / protected)" bash -c "[ $(rc) = 4 ]"
: > "$W/ssh.log"; run --preflight --target kind-panda;        check "refuse kit target" bash -c "[ $(rc) = 4 ] && grep -q kit-engine '$W/out'"
: > "$W/ssh.log"; run --preflight --target idea05;            check "refuse a Pi resolving to the production address" bash -c "[ $(rc) = 4 ] && grep -q 'protected host' '$W/out'"
: > "$W/ssh.log"; run --preflight --source idea04 --target idea04; check "refuse source == target" bash -c "[ $(rc) = 4 ]"
: > "$W/ssh.log"; run --preflight --instance kid-kolibri-demo; check "refuse Kid's demo as instance" bash -c "[ $(rc) = 4 ]"; check "  no ssh" nossh
: > "$W/ssh.log"; run --preflight --instance mv289-kolibri;   check "refuse kolibri-looking instance" bash -c "[ $(rc) = 4 ]"
: > "$W/ssh.log"; run --preflight --src-disk scratch1;        check "refuse disk id without prefix" bash -c "[ $(rc) = 4 ]"
: > "$W/ssh.log"; TGT_HOST=100.115.60.6 run --preflight;      check "refuse protected host override" bash -c "[ $(rc) = 4 ]"; check "  no ssh" nossh
reset_state "Kid #159 run 3"; : > "$W/ssh.log"; run --preflight; check "refuse when Pis are claimed by someone else" bash -c "[ $(rc) = 4 ] && grep -q 'must be claimed by Atlas' '$W/out'"; check "  no ssh before claim" nossh
reset_state; : > "$W/ssh.log"; BOT_NAME="" run --preflight;     check "refuse without BOT_NAME" bash -c "[ $(rc) = 4 ]"
: > "$W/ssh.log"; run --create-disks;                         check "mutating mode needs --ref" bash -c "[ $(rc) = 4 ] && grep -q -- '--ref' '$W/out'"; check "  no ssh" nossh

echo "== preflight"
reset_state; reset_hosts; add_roots
export MOVE_WORK="$W/work-pf"; run --preflight
check "preflight ALL PASS on a ready fake pool" bash -c "[ $(rc) = 0 ] && grep -q 'ALL PASS' '$W/out'"
check "  kid-kolibri-demo seen running on idea03" has "kid-kolibri-demo running"
check "  no sudo / no mutation during preflight" bash -c "! grep -vq 'losetup --version' '$W/sudo.log'"
check "  no loop images created" bash -c "! ls '$W/$SRC/scratch/img' 2>/dev/null | grep -q ."
jq '.[0].pm2_env.env={}' "$W/$TGT/pm2.json" > "$W/t" && mv "$W/t" "$W/$TGT/pm2.json"; run --preflight
check "NOT READY when the target Engine is not in fixture mode" bash -c "[ $(rc) = 1 ] && grep -q 'idea04 Engine not in fixture mode' '$W/out'"
reset_hosts; add_roots; echo 80.2 > "$W/$SRC/temp"; run --preflight
check "NOT READY above 75 C" bash -c "[ $(rc) = 1 ] && grep -q '80.2 C > 75' '$W/out'"
reset_hosts; add_roots; echo "automerge:4GQmXXXX" > "$W/$TGT/engine/store-identity/store-url.txt"; run --preflight
check "NOT READY on a non-2VroE store" bash -c "[ $(rc) = 1 ] && grep -q 'is not 2VroE' '$W/out'"
reset_hosts; add_roots; : > "$W/$SRC/docker-ps"; run --preflight
check "NOT READY when kid-kolibri-demo is not running on idea03" bash -c "[ $(rc) = 1 ] && grep -q 'kid-kolibri-demo not running' '$W/out'"
reset_hosts; add_roots; echo /dev/sdb1 > "$W/$SRC/scratch-dev"; run --preflight
check "NOT READY when scratch sits on Disk B" bash -c "[ $(rc) = 1 ] && grep -q 'protected disk 3813430-532011020' '$W/out'"
reset_hosts; add_roots; rm "$W/$TGT/image-present"; run --preflight
check "NOT READY when the scratch image is missing on the target" bash -c "[ $(rc) = 1 ] && grep -q 'lacks image' '$W/out'"
reset_hosts; add_roots; run --preflight --engine-sha deadbee
check "NOT READY when Engine HEAD differs from --engine-sha" bash -c "[ $(rc) = 1 ] && grep -q 'expected deadbee' '$W/out'"

echo "== full run: create -> move -> move-back -> teardown"
reset_state; reset_hosts; add_roots; export MOVE_WORK="$W/work-run"
run --create-disks --size-gb 1 --data-mb 1 --ref "test"
check "create-disks ok" bash -c "[ $(rc) = 0 ] && grep -q 'DISKS READY' '$W/out'"
check "  idea03 skipped busy slot 1, used idea-test-2" grep -q 'mv289-src.*idea-test-2' "$W/out"
check "  idea04 used free slot idea-test-1" bash -c "grep -q '^idea04 idea-test-1 /dev/loop' '$MOVE_WORK/created-mv289-dst'"
check "  sparse images under scratch" bash -c "[ -f '$W/$SRC/scratch/img/mv289-src.img' ] && [ -f '$W/$TGT/scratch/img/mv289-dst.img' ]"
check "  instance tree on the source disk" test -f "$W/$SRC/fixroot/idea-test-2/instances/mv289-web/data/payload.bin"
check "  META diskId mv289-dst on target" grep -q 'diskId: "mv289-dst"' "$W/$TGT/fixroot/idea-test-1/META.yaml"
check "  sentinels fired" bash -c "[ -e '$W/$SRC/watch/idea-test-2' ] && [ -e '$W/$TGT/watch/idea-test-1' ]"
run --create-disks --size-gb 1 --ref "test"
check "create-disks re-run is a no-op" bash -c "[ $(rc) = 0 ] && grep -q 'already created' '$W/out'"
run --move-back --ref test;  check "move-back before move refused" bash -c "[ $(rc) = 3 ]"
run --move --ref "test"
check "move ok (files + sha256 identical, HTTP 200)" bash -c "[ $(rc) = 0 ] && grep -q 'move DONE' '$W/out' && grep -q 'HTTP 200' '$W/out'"
check "  instance now on idea04 disk" bash -c "ls '$W/$TGT/fixroot/idea-test-1/instances' | grep -q '^mv289-web-m'"
check "  source quarantined on the scratch disk (not deleted)" test -d "$W/$SRC/fixroot/idea-test-2/.idea-quarantine/mv289-web-1"
run --move-back --ref "test"
check "move-back ok" bash -c "[ $(rc) = 0 ] && grep -q 'move-back DONE' '$W/out'"
check "  instance back on idea03 disk" bash -c "ls '$W/$SRC/fixroot/idea-test-2/instances' | grep -q '^mv289-web-m'"
run --teardown --ref "test"
check "teardown ok" bash -c "[ $(rc) = 0 ] && grep -q 'TEARDOWN DONE' '$W/out'"
check "  only our own loop devices detached, by /dev/loopN" bash -c "[ \$(grep -c 'losetup -d /dev/loop1[0-9]' '$W/sudo.log') = 2 ]"
check "  no loop devices left" bash -c "! [ -s '$W/$SRC/loops' ] && ! [ -s '$W/$TGT/loops' ]"
check "  slots unmounted" bash -c "! [ -s '$W/$SRC/mounts' ] && ! [ -s '$W/$TGT/mounts' ]"
check "  images + state quarantined (mv, not rm)" bash -c "ls '$W/$SRC'/scratch/quarantine-*/mv289-src.img '$W/$SRC'/scratch/quarantine-*/mv289-src.state '$W/$TGT'/scratch/quarantine-*/mv289-dst.img >/dev/null"
check "  sentinels removed" bash -c "! [ -e '$W/$SRC/watch/idea-test-2' ] && ! [ -e '$W/$TGT/watch/idea-test-1' ]"
check "  Kid's demo untouched (ids + StartedAt same)" grep -q '^k1 2026-11-13T08:00:00Z$' "$W/$SRC/docker-started"
check "  nothing forbidden called (losetup -D, docker stop/rm, other sudo)" bash -c "! [ -s '$W/forbidden.log' ]"

echo "== guard trips if a hands-off container changes mid-run"
reset_state; reset_hosts; add_roots; export MOVE_WORK="$W/work-tamper"
run --create-disks --size-gb 1 --data-mb 1 --ref test
touch "$W/tamper"; run --move --ref test; rm -f "$W/tamper"
check "move stops when kid-kolibri-demo's StartedAt changes" bash -c "[ $(rc) = 3 ] && grep -q 'hands-off containers on idea03 changed' '$W/out'"

echo "== remote unit checks"
reset_hosts
FR="$W/$SRC"
echo /dev/sdb1 > "$FR/scratch-dev"
out="$(FAKE_R=$FR FAKE_HOST=$SRC MV79_LOSETUP="$W/bin/losetup-ro" MV79_MKFS="$W/bin/mkfs-fake" bash "$W/remote.sh.orig" create "$FR/scratch" "$FR/fixroot" "$FR/watch" idea-test-3 mv289-x 1 mv289- 3813430-532011020,AA202000000000004820 2>&1)"
check "create refuses scratch on Disk B" grep -q 'protected disk serial 3813430-532011020' <<<"$out"
rm -f "$FR/scratch-dev"
out="$(FAKE_R=$FR bash "$W/remote.sh.orig" create "$FR/scratch" "$FR/fixroot" "$FR/watch" idea-test-1 mv289-x 1 mv289- none 2>&1)"
check "create refuses a non-empty slot" grep -q 'not empty' <<<"$out"
out="$(FAKE_R=$FR bash "$W/remote.sh.orig" create "$FR/scratch" /disks "$FR/watch" idea-test-3 mv289-x 1 mv289- none 2>&1)"
check "create refuses /disks as root" grep -q 'not a fixture root' <<<"$out"
out="$(FAKE_R=$FR bash "$W/remote.sh.orig" create "$FR/scratch" "$FR/fixroot" "$FR/watch" sdb1 mv289-x 1 mv289- none 2>&1)"
check "create refuses a non idea-test-N slot" grep -q 'not idea-test-N' <<<"$out"
printf 'diskId=mv289-y\nloop=/dev/loop77\nimage=%s/scratch/img/mv289-y.img\nslot=idea-test-5\nmount=%s/fixroot/idea-test-5\nwatch=%s/watch\nslotCreated=0\n' "$FR" "$FR" "$FR" > "$FR/scratch/mv289-y.state"
echo "/dev/loop77 /home/pi/someone-else.img" > "$FR/loops"
out="$(FAKE_R=$FR FAKE_HOST=$SRC MV79_LOSETUP="$W/bin/losetup-ro" bash "$W/remote.sh.orig" detach "$FR/scratch" mv289-y 20261113 2>&1)"
check "detach refuses a loop device that now backs someone else's file" bash -c "grep -q 'not detaching' <<<'$out' && grep -q loop77 '$FR/loops'"

restore_remote
check "real fleet-state.json and audit untouched" test "$(real_fp)" = "$REAL_BEFORE"
check "remote script restored byte-identical" cmp -s "$W/remote.sh.orig" "$R"
PATH="$REALPATH"
[ -n "${KEEP:-}" ] && trap - EXIT
echo "move-79.test.sh: $pass passed, $fail failed"; [ "$fail" = 0 ]
