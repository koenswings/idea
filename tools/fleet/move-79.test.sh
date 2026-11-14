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
export FAKE_HOST="$host" FAKE_R="$R" MV79_LOSETUP="$W/bin/losetup-ro" MV79_MKFS="$W/bin/mkfs-fake" \
  MV79_APPDATA_ROOTS="$R/app-data-roots" MV79_ROOT_OWNER="$(id -u):$(id -g)" MV79_PEER_KEY="$R/engine.pub" MV79_AUTHZ="$R/authz"
exec bash -c "$cmd"
SH
cat > "$W/bin/vcgencmd" <<'SH'
#!/usr/bin/env bash
echo "temp=$(cat "$FAKE_R/temp" 2>/dev/null || echo 50.0)'C"
SH
cat > "$W/bin/pm2" <<'SH'
#!/usr/bin/env bash
echo "pm2 $*" >> "$FAKE_R/pm2.log"
j="$FAKE_R/pm2.json"
merge_env() {
  python3 - "$j" <<'PY'
import json, os, sys
p = sys.argv[1]
try:
    data = json.load(open(p))
except Exception:
    data = [{"name":"engine","pm2_env":{"status":"online","username":"pi","env":{}}}]
if not data:
    data = [{"name":"engine","pm2_env":{"status":"online","username":"pi","env":{}}}]
env = data[0].setdefault("pm2_env", {}).setdefault("env", {})
root = os.environ.get("FAKE_R") or ""
for k in ("IDEA_TEST_MODE","IDEA_DISKS_ROOT","IDEA_WATCH_DIR","IDEA_CONFIG_FILE","IDEA_STORE_DIR"):
    if k in os.environ:
        v = os.environ[k]
        if root and v.startswith(root):
            v = "@ROOT@" + v[len(root):]
        env[k] = v
data[0]["pm2_env"]["status"] = "online"
data[0]["pm2_env"]["username"] = "pi"
json.dump(data, open(p, "w"))
PY
}
clear_env() {
  python3 - "$j" <<'PY'
import json, sys
p = sys.argv[1]
data = [{"name":"engine","pm2_env":{"status":"online","username":"pi","env":{}}}]
json.dump(data, open(p, "w"))
PY
}
case "$*" in
  jlist|"") cat "$j" ;;
  "restart engine --update-env"|*"restart engine"*) merge_env; cat "$j" >/dev/null ;;
  "restart idea-usage"*|"restart idea-usage --update-env") ;;
  "delete engine"|"delete idea-usage") ;;
  "start pm2.config.cjs") clear_env ;;
  save) ;;
  *) cat "$j" ;;
esac
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
  "image inspect") [ -e "$FAKE_R/image-present" ] || exit 1; [ "$3" = -f ] && cat "$FAKE_R/image-id"; exit 0 ;;
  "save "*) [ "$#" = 2 ] && [ -e "$FAKE_R/image-present" ] || exit 1; echo "DOCKER_SAVE $2 $(cat "$FAKE_R/image-id")"; echo "$FAKE_HOST docker save $2" >> "$W/docker.log" ;;
  "load ") read -r _ tag id; [ -n "$id" ] || exit 1; touch "$FAKE_R/image-present"; echo "$id" > "$FAKE_R/image-id"; echo "$tag" > "$FAKE_R/image-tag"
           echo "$FAKE_HOST docker load $tag $id" >> "$W/docker.log"; echo "Loaded image: $tag" ;;
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
if [ "$1" = -l ]; then   # read-only listing; with a command: is that command allowed without a password
  [ -n "${FAKE_NOSUDO:-}" ] && { echo "sudo: a password is required"; exit 1; }
  if [ -z "${2:-}" ]; then cat "$FAKE_R/sudo-l"; exit 0; fi
  grep -qE "NOPASSWD: (.*, )?(ALL|$2)(,|\$)" "$FAKE_R/sudo-l" && { echo "$2"; exit 0; }; exit 1; fi
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
  /usr/bin/umount) grep -v " $2$" "$T" > "$T.t"; mv "$T.t" "$T"
    n=$(( $(cat "$FAKE_R/umountn" 2>/dev/null || echo 0) + 1 )); echo $n > "$FAKE_R/umountn"; mkdir -p "$FAKE_R/unmounted-$n"
    find "$2" -mindepth 1 -maxdepth 1 -exec mv {} "$FAKE_R/unmounted-$n/" \; ;;
  /usr/bin/find|/usr/bin/sha256sum) exit 1 ;;
  true) [ -z "${FAKE_NOSUDO:-}" ] ;;
  /usr/bin/tee) [ "$2" = -a ] && [ "$3" = "$MV79_APPDATA_ROOTS" ] || exit 9; exec /usr/bin/tee -a "$3" ;;
  /usr/bin/cp) [ "$3" = "$MV79_APPDATA_ROOTS" ] || exit 9; exec /bin/cp "$2" "$3" ;;
  /usr/bin/chown|/usr/bin/chmod) [ "$3" = "$MV79_APPDATA_ROOTS" ] || [ "$3" = "$FAKE_R/fixroot" ] || exit 9
    [ "$1" = /usr/bin/chmod ] && exec /bin/chmod "$2" "$3"; exec /bin/chown "$2" "$3" ;;
  /usr/bin/install) [ "$*" = "/usr/bin/install -d -o pi -g pi -m 0755 $9" ] || exit 9; exec /bin/mkdir -m 0755 "$9" ;;
  /usr/bin/rmdir) case "$2" in "$FAKE_R"/fixroot/idea-test-*) exec /bin/rmdir "$2" ;; *) exit 9 ;; esac ;;
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
    dk=[{k:d[k] for k in ('id','name','device')} for d in disks(R)]; ins=insts(R)
    if os.path.exists(R+'/diskb-docked'):
        dk.append({'id':'diskb202610301247','name':'Disk B','device':'sdb'})
        ins.append({'id':'nc1','name':'nextcloud-files-b-001','instanceOf':'nextcloud','status':open(R+'/diskb-docked').read().strip() or 'Running','diskId':'diskb202610301247','port':8080,'lastStarted':1})
    print(json.dumps({'engineId':'e-'+os.path.basename(R),'hostname':os.path.basename(R),'lastBooted':1,'moveAppCrossEngine': not os.path.exists(R+'/nocap'),
        'disks':dk,'instances':ins}))
elif mode=='peers':
    def pa(h):
        f=h+'/store-authorized'
        return {'sshKey':'SHA256:s-'+os.path.basename(h),'hostKey':'SHA256:h-'+os.path.basename(h),'authorized':[l.strip() for l in open(f) if l.strip()]} if os.path.exists(f) else None
    print(json.dumps({'localEngineId':'e-'+os.path.basename(R),'engines':[{'id':'e-'+os.path.basename(h),'hostname':os.path.basename(h),'peerAccess':pa(h)} for h in sorted(hosts)]}))
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
  DOCK_WAIT=10 TEMP_POLL=0 MV_FIXTURE_SLEEP=0
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
    git -C "$W/$h/engine" init -q && GIT_AUTHOR_DATE=@1763000000 GIT_COMMITTER_DATE=@1763000000 git -C "$W/$h/engine" -c user.email=t@t -c user.name=t commit -q --allow-empty -m x
    printf '/home/pi/idea/other-root\n' > "$W/$h/app-data-roots"; chmod 644 "$W/$h/app-data-roots"; chmod 755 "$W/$h/fixroot"
    printf 'settings:\n  isDev: false\n  peerAccess: false\n  storeIdentityFolder: store-identity\n  storeDataFolder: store-data\n' > "$W/$h/engine/config.yaml"; chmod 640 "$W/$h/engine/config.yaml"
    printf '{}
' > "$W/$h/engine/store-identity/store-template.json"
    mkdir -p "$W/$h/engine/store-identity-scratch" "$W/$h/engine/store-data-scratch"
    cp "$W/$h/engine/store-identity/store-template.json" "$W/$h/engine/store-identity-scratch/store-template.json"
    echo "automerge:3NuVdsXJzcUjn6J4Qb2k96wmrTBJ" > "$W/$h/engine/store-identity-scratch/store-url.txt"
    printf 'settings:\n  isDev: false\n  peerAccess: false\n  storeIdentityFolder: store-identity-scratch\n  storeDataFolder: store-data-scratch\n' > "$W/$h/engine/config.fixture.yaml"
    echo "ssh-ed25519 AAAAC3k${h//./} idea-engine" > "$W/$h/engine.pub"; echo "sha256:$(printf 'a%.0s' {1..64})" > "$W/$h/image-id"
    touch "$W/$h/image-present"; echo 50.1 > "$W/$h/temp"
    printf 'Matching Defaults entries for pi on x:\n    env_reset\n\nUser pi may run the following commands on x:\n    (ALL : ALL) ALL\n    (ALL) NOPASSWD: ALL\n' > "$W/$h/sudo-l"
    jq -n --arg r "@ROOT@" '[{name:"engine",pm2_env:{status:"online",username:"pi",env:{IDEA_TEST_MODE:"true",IDEA_DISKS_ROOT:($r+"/fixroot"),IDEA_WATCH_DIR:($r+"/watch"),IDEA_CONFIG_FILE:"./config.fixture.yaml",IDEA_STORE_DIR:"./store-data-scratch"}}}]' > "$W/$h/pm2.json"
    : > "$W/$h/docker-ps"; : > "$W/$h/docker-started"
  done
  echo AA202000000000004820 > "$W/$SRC/root-serial"; echo AA202000000000002167 > "$W/$TGT/root-serial"
  # idea03: Kid's demo + hands-off sidecars; slot 1 already used by something else (not empty)
  printf 'k1|kid-kolibri-demo-kolibri-1|running\ns1|idea166-kolibri-live|exited\nh1|idea-hub-sidecar|exited\n' > "$W/$SRC/docker-ps"
  printf 'k1 2026-11-13T08:00:00Z\ns1 2026-11-13T04:00:00Z\nh1 2026-11-13T04:00:00Z\n' > "$W/$SRC/docker-started"
  echo busy > "$W/$SRC/fixroot/idea-test-1/other"
  add_peers
}
add_peers() {  # both Engines accept each other: store authorized[] + the authorized_keys lines the Engine's own sync writes
  local a b; for a in "$SRC" "$TGT"; do b=$TGT; [ "$a" = "$TGT" ] && b=$SRC
    echo "e-$b SHA256:s-$b SHA256:h-$b" > "$W/$a/store-authorized"
    echo "command=\"/usr/local/sbin/idea-peer-gate e-$b\",restrict ssh-ed25519 AAAAC3k${b//./} idea-engine" > "$W/$a/authz"; done; }
fstate() { local h="$W/$1"; for f in "$h/app-data-roots" "$h/engine/config.yaml"; do printf '%s %s\n' "$(sha256sum < "$f" | cut -c1-64)" "$(stat -c '%u:%g %a %F' "$f")"; done; stat -c '%u:%g %a' "$h/fixroot"; }
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

# The Pi-side paths (/etc/idea/app-data-roots, the Engine key, authorized_keys) are pointed at the sandbox by the
# MV79_* env the fake ssh exports; the remote script itself is never patched.
cp "$R" "$W/remote.sh.orig"
restore_remote() { :; }
add_roots() { :; }   # kept for the older call sites: app-data-roots now comes from reset_hosts + --setup-window
FAKE_HEAD="$(cd "$W" && git init -q h && GIT_AUTHOR_DATE=@1763000000 GIT_COMMITTER_DATE=@1763000000 git -C h -c user.email=t@t -c user.name=t commit -q --allow-empty -m x && git -C h rev-parse HEAD)"
export ENGINE_SHA="$FAKE_HEAD" MV_MIN_RELEASE_SHA="$FAKE_HEAD"

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
export MOVE_WORK="$W/work-pf"; F0="$(fstate "$SRC")$(fstate "$TGT")"; run --preflight
check "preflight before the window: NOT READY only on TODOs (slot line, peerAccess)" bash -c "[ $(rc) = 1 ] && grep -q 'PREFLIGHT TODO: idea03 .*no scratch slot line yet' '$W/out' && grep -q 'PREFLIGHT TODO: idea04 config.yaml peerAccess' '$W/out' && ! grep -q 'PREFLIGHT FAIL' '$W/out'"
check "  peer keys check passes (read-only)" has "peer keys idea03<->idea04 in place"
check "  no sudo / no mutation during preflight" bash -c "! grep -vqE 'losetup --version|sudo -l$' '$W/sudo.log'"
check "  preflight left app-data-roots, config.yaml, fixture root as they were" test "$(fstate "$SRC")$(fstate "$TGT")" = "$F0"
run --setup-window --ref test; run --preflight
check "preflight ALL PASS on a ready fake pool (after --setup-window)" bash -c "[ $(rc) = 0 ] && grep -q 'ALL PASS' '$W/out'"
check "  kid-kolibri-demo seen running on idea03" has "kid-kolibri-demo running"
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

echo "== window prerequisites: fail cases (setup refuses, nothing changed)"
pf_setup() {  # pf_setup <label> <grep>: preflight shows FAIL <grep>, setup refuses, files unchanged, no window state
  local F; F="$(fstate "$SRC" 2>/dev/null)$(fstate "$TGT" 2>/dev/null)"; export MOVE_WORK="$W/work-$RANDOM"
  run --preflight; check "$1: preflight FAIL" pf_has "$2"
  run --setup-window --ref test; check "  setup refused" bash -c "[ $(rc) = 3 ] && grep -q 'window setup blocked' '$W/out'"
  check "  nothing changed, no window state" unchanged "$F"; }
pf_has() { [ "$(rc)" = 1 ] && grep -q "PREFLIGHT FAIL: .*$1" "$W/out"; }
unchanged() { [ "$(fstate "$SRC" 2>/dev/null)$(fstate "$TGT" 2>/dev/null)" = "$1" ] && ! ls "$W"/1*/scratch/window.win >/dev/null 2>&1; }
both_as() { [ "$(rc)" = 0 ] && [ "$(fstate "$SRC")" = "$1" ] && [ "$(fstate "$TGT")" = "$2" ]; }
reset_state; reset_hosts; mv "$W/$TGT/app-data-roots" "$W/$TGT/adr.real"; ln -s adr.real "$W/$TGT/app-data-roots"
pf_setup "app-data-roots is a symlink" "idea04 /etc/idea/app-data-roots is a symlink"
reset_hosts; mv "$W/$SRC/app-data-roots" "$W/$SRC/adr.gone"
pf_setup "app-data-roots missing" "idea03 /etc/idea/app-data-roots is missing"
reset_hosts; chmod 664 "$W/$SRC/app-data-roots"
pf_setup "app-data-roots mode 664" "idea03 /etc/idea/app-data-roots is '.* 664 regular file'"
reset_hosts; mv "$W/$TGT/fixroot" "$W/$TGT/fixroot.real"; ln -s fixroot.real "$W/$TGT/fixroot"
pf_setup "fixture root is a symlink" "idea04 .*fixroot.*symlink"
reset_hosts; FAKE_NOSUDO=1 pf_setup "sudo -n -l: no NOPASSWD rules (password required)" "sudo -n -l lists no NOPASSWD rules"
reset_hosts; printf 'User pi may run the following commands on x:\n    (root) NOPASSWD: /usr/sbin/losetup -f --show *, /usr/bin/chown, /usr/bin/chmod\n    (root) NOPASSWD: /usr/bin/tee -a /etc/idea/app-data-roots\n    (root) PASSWD: /usr/bin/cp\n' > "$W/$TGT/sudo-l"
pf_setup "sudo -n -l: partial NOPASSWD rules" "idea04 sudo -n -l: no NOPASSWD rule for: /usr/bin/tee(only with fixed arguments) /usr/bin/cp /usr/bin/install /usr/bin/rmdir "
check "  chown/chmod not listed as missing" bash -c "! grep -q 'no NOPASSWD rule for: /usr/bin/ch' '$W/out'"
reset_hosts; printf 'User pi may run the following commands on x:\n    (www-data) NOPASSWD: ALL\n    (ALL) NOPASSWD: ALL, !/usr/bin/rmdir\n' > "$W/$SRC/sudo-l"
pf_setup "sudo -n -l: ALL rule but rmdir negated / ALL only as another user" "idea03 sudo -n -l: no NOPASSWD rule for: /usr/bin/rmdir(negated)"
reset_state; reset_hosts; export MOVE_WORK="$W/work-sudo"
printf 'User pi may run the following commands on x:\n    (root) NOPASSWD: /usr/sbin/losetup, /usr/bin/mount, /usr/bin/umount, /usr/bin/chown, /usr/bin/chmod, /usr/bin/tee, /usr/bin/cp, /usr/bin/install, /usr/bin/rmdir\n' > "$W/$SRC/sudo-l"
run --preflight; check "sudo -n -l: each needed command listed with NOPASSWD -> PASS" has "idea03 sudo -n -l: NOPASSWD entries cover"
check "  ALL rule on idea04 -> PASS" has "idea04 sudo -n -l: an ALL rule with NOPASSWD covers"
check "  sudo -l only; sudoers never touched" bash -c "! grep -qE 'visudo|sudoers' '$W/sudo.log' && ! grep -hvE '^ *#' '$S' '$W/remote.sh.orig' | grep -qE 'visudo|>>? *[^ ]*sudoers'"
run --setup-window --ref test; check "  setup works with per-command rules (checks each with sudo -n -l <cmd>)" bash -c "[ $(rc) = 0 ] && grep -q 'WINDOW SET UP' '$W/out'"
reset_hosts; jq '.[0].pm2_env.env.IDEA_CONFIG_FILE="/etc/idea/engine.yaml"' "$W/$TGT/pm2.json" > "$W/t" && mv "$W/t" "$W/$TGT/pm2.json"
pf_setup "Engine reads another config file" "IDEA_CONFIG_FILE=/etc/idea/engine.yaml"
reset_hosts; : > "$W/$SRC/store-authorized"
pf_setup "peer keys: idea03's Engine has not accepted idea04" "peer keys between idea03 and idea04 are NOT in place: idea03's Engine has not accepted idea04's key"
check "  message says the script never changes keys and to ask Steve" bash -c "grep -q 'never adds or changes SSH keys, so ask Steve' '$W/out'"
reset_hosts; : > "$W/$TGT/authz"
pf_setup "peer keys: idea04's authorized_keys lacks idea03's Engine key" "idea04's authorized keys lack idea03's Engine key"
reset_hosts; rm "$W/$SRC/store-authorized" "$W/$TGT/store-authorized"; A0="$(cat "$W"/1*/authz "$W"/1*/engine.pub | sha256sum)"
pf_setup "peer keys: no peerAccess in the store at all" "peer keys between idea03 and idea04 are NOT in place"
check "  no SSH key file written by preflight/setup" test "$(cat "$W"/1*/authz "$W"/1*/engine.pub | sha256sum)" = "$A0"
check "no SSH key writes anywhere in the scripts (code lines)" bash -c "! grep -hvE '^ *#' '$S' '$W/remote.sh.orig' | grep -nE 'ssh-keygen|ssh-copy-id|sync-peers|>>? *[^ ]*(authorized_keys|idea_authorized_keys|known_hosts|idea_engine_ed25519)'"
reset_hosts; chmod 444 "$W/$TGT/authz"; mv "$W/$TGT/authz" "$W/$TGT/authz.x"; touch "$W/$TGT/authz"; chmod 000 "$W/$TGT/authz"
export MOVE_WORK="$W/work-$RANDOM"; run --preflight
if [ -r "$W/$TGT/authz" ]; then echo "SKIP unreadable authorized_keys (running as root)"; else
check "unreadable authorized_keys: store check only (INFO, not FAIL)" bash -c "grep -q \"PREFLIGHT INFO: peer keys: idea04's authorized_keys file is not readable\" '$W/out' && grep -q 'peer keys idea03<->idea04 in place' '$W/out'"; fi
chmod 644 "$W/$TGT/authz"

echo "== window prerequisites: setup variants + exact restore"
reset_state; reset_hosts; export MOVE_WORK="$W/work-var"
printf 'settings:\n  isDev: false\n' > "$W/$SRC/engine/config.yaml"; chmod 600 "$W/$SRC/engine/config.yaml"          # no peerAccess line
printf 'settings:\n  peerAccess: true\n' > "$W/$TGT/engine/config.yaml"; chmod 644 "$W/$TGT/engine/config.yaml"      # already on
printf '/home/pi/idea/duration-disks/idea-test-7\n%s\n' "$W/$TGT/fixroot/idea-test-1" > "$W/$TGT/app-data-roots"  # already listed
F0S="$(fstate "$SRC")"; F0T="$(fstate "$TGT")"; CT0="$(stat -c %i "$W/$SRC/engine/config.yaml")"
run --setup-window --ref test
check "setup inserts peerAccess: true under settings: when absent" bash -c "[ $(rc) = 0 ] && sed -n 2p '$W/$SRC/engine/config.yaml' | grep -q '^  peerAccess: true' && [ \$(stat -c %i '$W/$SRC/engine/config.yaml') = $CT0 ]"
check "  config already peerAccess: true and slot already listed: idea04 untouched" test "$(fstate "$TGT")" = "$F0T"
run --preflight; check "  preflight ALL PASS" bash -c "[ $(rc) = 0 ]"
run --teardown --ref test
check "  teardown restores the 0600 config byte-exact" both_as "$F0S" "$F0T"
reset_state; reset_hosts; export MOVE_WORK="$W/work-half"
printf 'nosettings: 1\n' > "$W/$TGT/engine/config.yaml"; F0T="$(fstate "$TGT")"; F0S="$(fstate "$SRC")"
run --setup-window --ref test
check "half-finished setup (no settings: block on idea04) stops" bash -c "[ $(rc) = 3 ] && grep -q 'could not set peerAccess' '$W/out'"
run --setup-window --ref test
check "  re-run refuses until teardown" bash -c "[ $(rc) = 3 ] && grep -q 'half-finished window setup' '$W/out'"
run --teardown --ref test
check "  teardown restores the half-finished setup exactly on both Pis" both_as "$F0S" "$F0T"
check "  idea04 app-data-roots slot line removed again" bash -c "! grep -q idea-test '$W/$TGT/app-data-roots'"
reset_state; reset_hosts; export MOVE_WORK="$W/work-mm"; run --setup-window --ref test
echo "  peerAccess: true  # hand edit" >> "$W/$SRC/engine/config.yaml"; chmod 600 "$W/$SRC/engine/config.yaml"
run --teardown --ref test
check "teardown verifies after restore (config overwritten with the backup, mode fixed)" bash -c "[ $(rc) = 0 ] && grep -q 'idea03 CONFIG_STAT restored' '$W/out'"
reset_hosts; export MOVE_WORK="$W/work-sym"; run --setup-window --ref test
mv "$W/$TGT/app-data-roots" "$W/$TGT/adr.real"; ln -s adr.real "$W/$TGT/app-data-roots"; run --teardown --ref test
check "teardown refuses to write through an app-data-roots that became a symlink" bash -c "[ $(rc) = 3 ] && grep -q 'became a symlink' '$W/out'"

echo "== scratch image by repo:tag (IDs compared, never in compose)"
BID="sha256:$(printf 'b%.0s' {1..64})"; AID="sha256:$(printf 'a%.0s' {1..64})"
reset_state; reset_hosts; export MOVE_WORK="$W/work-imgpf"; echo "$BID" > "$W/$TGT/image-id"; run --preflight
check "preflight FAILs when nginx:alpine has a different ID on the two Pis" bash -c "[ $(rc) = 1 ] && grep -q 'nginx:alpine image ID differs: idea03 sha256:aaaa.*idea04 sha256:bbbb' '$W/out'"
reset_hosts; run --preflight; check "  same ID -> PASS" has "nginx:alpine has the same image ID on idea03 and idea04"
run --preflight --image-id "$BID"; check "  --image-id pin mismatch -> FAIL" bash -c "[ $(rc) = 1 ] && grep -q 'idea03 nginx:alpine is sha256:aaaa.*pinned' '$W/out'"
run --preflight --image-id "$AID"; check "  --image-id pin match -> no pin FAIL" bash -c "! grep -q 'pinned' '$W/out'"

echo "== load-image (optional, guarded; docker save nginx:alpine | docker load)"
reset_state; reset_hosts; rm "$W/$TGT/image-present" "$W/$TGT/image-id"; export MOVE_WORK="$W/work-img"; : > "$W/docker.log"
run --load-image; check "load-image needs --ref" bash -c "[ $(rc) = 4 ]"
reset_state "Kid #159 run 3"; : > "$W/ssh.log"; run --load-image --ref test; check "load-image refused when not claimed (no ssh)" bash -c "[ $(rc) = 4 ] && ! [ -s '$W/ssh.log' ]"
reset_state; run --load-image --ref test
check "load-image saves nginx:alpine by tag and idea04 then has it with the same ID" bash -c "[ $(rc) = 0 ] && grep -q 'IMAGE READY on idea04: nginx:alpine sha256:aaaa' '$W/out' && [ \"\$(cat '$W/$TGT/image-id')\" = '$AID' ] && [ \"\$(cat '$W/$TGT/image-tag')\" = nginx:alpine ]"
img_only() { [ "$(cut -d' ' -f1-4 "$W/docker.log" | tr '\n' ';')" = "$SRC docker save nginx:alpine;$TGT docker load nginx:alpine;" ] && ! [ -s "$W/forbidden.log" ] && grep -q '^k1 2026-11-13T08:00:00Z$' "$W/$SRC/docker-started"; }
check "  only docker save nginx:alpine on idea03 and docker load on idea04; nothing restarted" img_only
: > "$W/docker.log"; run --load-image --ref test
check "  re-run (same ID already on idea04) is a no-op" bash -c "[ $(rc) = 0 ] && grep -q 'already has nginx:alpine with the same ID' '$W/out' && ! [ -s '$W/docker.log' ]"
echo "$BID" > "$W/$TGT/image-id"; : > "$W/docker.log"; run --load-image --ref test
check "load-image FAILs (no overwrite) when idea04 has nginx:alpine with a different ID" bash -c "[ $(rc) = 3 ] && grep -q 'DIFFERENT image ID' '$W/out' && [ \"\$(cat '$W/$TGT/image-id')\" = '$BID' ] && ! [ -s '$W/docker.log' ]"
echo "$AID" > "$W/$TGT/image-id"; run --load-image --image "nginx:alpine@sha256:abc" --ref test
check "load-image refuses a non repo:tag reference" bash -c "[ $(rc) = 3 ] && grep -q 'plain repo:tag' '$W/out'"
rm "$W/$SRC/image-present"; run --load-image --ref test
check "load-image stops when the source lacks the image" bash -c "[ $(rc) = 3 ] && grep -q 'not found on idea03' '$W/out'"

echo "== full run: setup-window -> create -> move -> move-back -> teardown -> release-check"
reset_state; reset_hosts; add_roots; export MOVE_WORK="$W/work-run"
chmod 775 "$W/$SRC/fixroot"; printf '/home/pi/idea/other-root' > "$W/$TGT/app-data-roots"   # group-writable root; no trailing newline
F0S="$(fstate "$SRC")"; F0T="$(fstate "$TGT")"
run --create-disks --size-gb 1 --data-mb 1 --ref "test"
check "create-disks refused before --setup-window" bash -c "[ $(rc) = 3 ] && grep -q 'run --setup-window first' '$W/out'"
run --setup-window --ref "test"
check "setup-window ok" bash -c "[ $(rc) = 0 ] && grep -q 'WINDOW SET UP' '$W/out'"
check "  app-data-roots: original line kept, slot line appended (idea03 slot 2)" bash -c "[ \"\$(cat '$W/$SRC/app-data-roots')\" = \"\$(printf '/home/pi/idea/other-root\n$W/$SRC/fixroot/idea-test-2')\" ]"
check "  app-data-roots without trailing newline gets one before the slot line" bash -c "[ \"\$(sed -n 2p '$W/$TGT/app-data-roots')\" = '$W/$TGT/fixroot/idea-test-1' ]"
check "  app-data-roots still a regular 0644 file" bash -c "[ \"\$(stat -c '%a %F' '$W/$SRC/app-data-roots')\" = '644 regular file' ]"
check "  fixture root no longer group-writable" bash -c "[ \"\$(stat -c %a '$W/$SRC/fixroot')\" = 755 ]"
check "  config.yaml peerAccess: true, mode kept" bash -c "grep -q '^  peerAccess: true' '$W/$SRC/engine/config.yaml' && [ \"\$(stat -c %a '$W/$SRC/engine/config.yaml')\" = 640 ] && [ \$(grep -c peerAccess '$W/$SRC/engine/config.yaml') = 1 ]"
check "  backups in the quarantine-window dir" bash -c "ls '$W/$SRC'/scratch/quarantine-window-*/app-data-roots.orig '$W/$SRC'/scratch/quarantine-window-*/config.orig >/dev/null"
check "  no SSH key file touched" bash -c "[ \"\$(cat '$W/$SRC/authz' '$W/$TGT/authz' '$W/$SRC/engine.pub' '$W/$TGT/engine.pub' | sha256sum)\" = \"$(cat "$W/$SRC/authz" "$W/$TGT/authz" "$W/$SRC/engine.pub" "$W/$TGT/engine.pub" | sha256sum)\" ]"
run --setup-window --ref "test"
check "setup-window re-run is a no-op" bash -c "[ $(rc) = 0 ] && grep -q 'already set up' '$W/out' && [ \$(grep -c idea-test '$W/$SRC/app-data-roots') = 1 ]"
run --create-disks --size-gb 1 --data-mb 1 --ref "test"
check "create-disks ok" bash -c "[ $(rc) = 0 ] && grep -q 'DISKS READY' '$W/out'"
check "  idea03 skipped busy slot 1, used idea-test-2" grep -q 'mv289-src.*idea-test-2' "$W/out"
check "  idea04 used free slot idea-test-1" bash -c "grep -q '^idea04 idea-test-1 /dev/loop' '$MOVE_WORK/created-mv289-dst'"
check "  sparse images under scratch" bash -c "[ -f '$W/$SRC/scratch/img/mv289-src.img' ] && [ -f '$W/$TGT/scratch/img/mv289-dst.img' ]"
check "  compose uses image: nginx:alpine (no ID, no digest)" bash -c "grep -q '^ *image: nginx:alpine$' '$W/$SRC/fixroot/idea-test-2/instances/mv289-web/compose.yaml' && ! grep -q sha256 '$W/$SRC/fixroot/idea-test-2/instances/mv289-web/compose.yaml'"
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
check "  window restored: verify OK on both Pis" bash -c "grep -q 'idea03 winrestore: .*RESTORE_OK' '$W/out' && grep -q 'idea04 winrestore: .*RESTORE_OK' '$W/out'"
check "  idea03 app-data-roots, config.yaml, fixture root owner/mode byte-exact as before" test "$(fstate "$SRC")" = "$F0S"
check "  idea04 (no-trailing-newline file) byte-exact as before" test "$(fstate "$TGT")" = "$F0T"
check "  slot dir made by the window removed; idea04's pre-existing empty slot kept" bash -c "! [ -e '$W/$SRC/fixroot/idea-test-2' ] && [ -d '$W/$TGT/fixroot/idea-test-1' ]"
check "  idea03's pre-existing busy slot 1 left alone" test -f "$W/$SRC/fixroot/idea-test-1/other"
check "  restore evidence written" bash -c "grep -q 'APPDATA_SHA restored' '$W/out' && grep -q 'CONFIG_STAT restored' '$W/out'"
run --teardown --ref "test"
check "teardown re-run is a no-op" bash -c "[ $(rc) = 0 ] && grep -q 'already restored' '$W/out'"

echo "== release-check"
run --release-check
check "release-check FAILS while Engines are still in fixture mode / Disk B out" bash -c "[ $(rc) = 1 ] && grep -q 'still in fixture mode' '$W/out' && grep -q 'Disk B diskb202610301247 not docked' '$W/out'"
for h in "$SRC" "$TGT"; do jq '.[0].pm2_env.env={}' "$W/$h/pm2.json" > "$W/t" && mv "$W/t" "$W/$h/pm2.json"
  GIT_AUTHOR_DATE=@1763000100 GIT_COMMITTER_DATE=@1763000100 git -C "$W/$h/engine" -c user.email=t@t -c user.name=t commit -q --allow-empty -m main; done
echo Running > "$W/$SRC/diskb-docked"; run --release-check
check "release-check PASS: normal mode, >= min sha, Disk B + nextcloud-files-b-001 back, kid unchanged" bash -c "[ $(rc) = 0 ] && grep -q 'RELEASE CHECK: PASS' '$W/out'"
check "  evidence file lists every check" bash -c "f=\$(ls -t '$MOVE_WORK'/evidence-*-release-check/release-check.txt | head -1); grep -q 'kid-kolibri-demo unchanged and running' \$f && grep -q 'nextcloud-files-b-001 Running on Disk B' \$f && grep -q 'contains' \$f && grep -q 'RELEASE CHECK: PASS' \$f"
echo Stopped > "$W/$SRC/diskb-docked"; run --release-check
check "release-check FAILS when nextcloud-files-b-001 is not Running" bash -c "[ $(rc) = 1 ] && grep -q 'nextcloud-files-b-001 not Running' '$W/out'"
echo Running > "$W/$SRC/diskb-docked"; sed -i 's/^k1 .*/k1 2026-11-13T11:11:11Z/' "$W/$SRC/docker-started"; run --release-check
check "release-check FAILS when kid-kolibri-demo restarted (StartedAt differs from the window baseline)" bash -c "[ $(rc) = 1 ] && grep -q 'kid-kolibri-demo now' '$W/out'"
sed -i 's/^k1 .*/k1 2026-11-13T08:00:00Z/' "$W/$SRC/docker-started"; MV_MIN_RELEASE_SHA=1111111111111111111111111111111111111111 run --release-check
check "release-check FAILS when an Engine is not on the min release sha" bash -c "[ $(rc) = 1 ] && grep -q 'is not on 1111111 or newer' '$W/out'"
printf 'x\n' >> "$W/$TGT/app-data-roots"; run --release-check
check "release-check FAILS when app-data-roots drifted from the original" bash -c "[ $(rc) = 1 ] && grep -q 'idea04 APPDATA_SHA is' '$W/out'"

echo "== guard trips if a hands-off container changes mid-run"
reset_state; reset_hosts; add_roots; export MOVE_WORK="$W/work-tamper"
run --setup-window --ref test; run --create-disks --size-gb 1 --data-mb 1 --ref test
touch "$W/tamper"; run --move --ref test; rm -f "$W/tamper"
check "move stops when kid-kolibri-demo's StartedAt changes" bash -c "[ $(rc) = 3 ] && grep -q 'hands-off containers on idea03 changed' '$W/out'"

echo "== scratch store: fixture mode must not use 2VroE"
reset_state; reset_hosts; add_roots
export MOVE_WORK="$W/work-scratch-guard"
# Strip the scratch config so the Engine would open live 2VroE while still in fixture mode (the 13 Nov failure).
for h in "$SRC" "$TGT"; do
  jq '.[0].pm2_env.env.IDEA_CONFIG_FILE="" | .[0].pm2_env.env.IDEA_STORE_DIR=""' "$W/$h/pm2.json" > "$W/t" && mv "$W/t" "$W/$h/pm2.json"
done
run --preflight
check "NOT READY when fixture mode would use the shared 2VroE store" bash -c "[ $(rc) = 1 ] && grep -q 'fixture mode is using' '$W/out' && grep -q '2VroE' '$W/out'"

echo "== start-fixture / stop-fixture (scratch store, live 2VroE untouched)"
reset_state; reset_hosts; add_roots
export MOVE_WORK="$W/work-start-fixture"
# Begin in normal mode on the live 2VroE store (no scratch identity yet).
for h in "$SRC" "$TGT"; do
  jq '.[0].pm2_env.env={}' "$W/$h/pm2.json" > "$W/t" && mv "$W/t" "$W/$h/pm2.json"
  rm -f "$W/$h/engine/config.fixture.yaml" "$W/$h/engine/store-identity-scratch/store-url.txt"
done
LIVE0="$(cat "$W/$SRC/engine/store-identity/store-url.txt")"
run --setup-window --ref test
check "setup-window still works from normal mode (2VroE live store)" bash -c "[ $(rc) = 0 ]"
run --start-fixture --ref test
check "start-fixture ok" bash -c "[ $(rc) = 0 ] && grep -q 'FIXTURE STARTED' '$W/out'"
check "  live store-url.txt still 2VroE on both Pis" bash -c "[ \"\$(cat '$W/$SRC/engine/store-identity/store-url.txt')\" = '$LIVE0' ] && [ \"\$(cat '$W/$TGT/engine/store-identity/store-url.txt')\" = '$LIVE0' ]"
check "  scratch identity written, not 2VroE" bash -c "u=\$(cat '$W/$SRC/engine/store-identity-scratch/store-url.txt'); [ -n \"\$u\" ] && [[ \$u == automerge:* ]] && [[ \$u != automerge:2VroE* ]] && [ \"\$u\" = \"\$(cat '$W/$TGT/engine/store-identity-scratch/store-url.txt')\" ]"
check "  pm2 env is fixture + config.fixture.yaml" bash -c "jq -e '.[0].pm2_env.env.IDEA_TEST_MODE==\"true\" and .[0].pm2_env.env.IDEA_CONFIG_FILE==\"./config.fixture.yaml\"' '$W/$SRC/pm2.json' >/dev/null"
check "  both Pis share this run's scratch URL" bash -c "[ -s '$MOVE_WORK/scratch-store-url.txt' ] && [ \"\$(cat '$W/$SRC/engine/store-identity-scratch/store-url.txt')\" = \"\$(cat '$MOVE_WORK/scratch-store-url.txt')\" ]"
run --preflight
check "preflight ALL PASS after --start-fixture" bash -c "[ $(rc) = 0 ] && grep -q 'ALL PASS' '$W/out' && grep -q 'scratch, not 2VroE' '$W/out'"
# Guard: prepare-scratch refuses the shared store (and does not rewrite the live file).
out="$(FAKE_R=$W/$SRC FAKE_HOST=$SRC bash "$R" prepare-scratch "$W/$SRC/engine" automerge:2VroEUvDkmYsDAwE5oG9YeFNadWH 2>&1)" || true
check "prepare-scratch refuses 2VroE" bash -c "grep -q 'shared fleet store' <<<'$out' || grep -q '2VroE' <<<'$out'"
check "  refuse left live store-url.txt unchanged" test "$(cat "$W/$SRC/engine/store-identity/store-url.txt")" = "$LIVE0"
out="$(FAKE_R=$W/$SRC FAKE_HOST=$SRC bash "$R" start-fixture "$W/$SRC/engine" automerge:2VroEUvDkmYsDAwE5oG9YeFNadWH "$W/$SRC/fixroot" "$W/$SRC/watch" 0 2>&1)" || true
check "start-fixture refuses a 2VroE URL" bash -c "grep -qE '2VroE|shared|refusing' <<<'$out'"
run --stop-fixture --ref test
check "stop-fixture ok" bash -c "[ $(rc) = 0 ] && grep -q 'FIXTURE STOPPED' '$W/out'"
check "  Engines back in normal mode (no fixture env)" bash -c "jq -e '(.[0].pm2_env.env.IDEA_TEST_MODE | not) and (.[0].pm2_env.env.IDEA_CONFIG_FILE | not)' '$W/$SRC/pm2.json' >/dev/null"
check "  live store-url.txt still 2VroE after stop" test "$(cat "$W/$SRC/engine/store-identity/store-url.txt")" = "$LIVE0"

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
