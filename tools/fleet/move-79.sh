#!/usr/bin/env bash
# move-79.sh — two-Engine Move proof (idea#79, agent-engine-dev#289) between two claimed pool Pis, using
# loop-file scratch App Disks (no physical disks). Default for the #289 proof: source idea03, target idea04.
#
#   BOT_NAME=Atlas tools/fleet/move-79.sh --preflight                              # read-only
#   BOT_NAME=Atlas tools/fleet/move-79.sh --create-disks --ref "<who said go>"     # make + dock mv289-src/-dst
#   BOT_NAME=Atlas tools/fleet/move-79.sh --move       --ref "<ref>"               # source -> target
#   BOT_NAME=Atlas tools/fleet/move-79.sh --move-back  --ref "<ref>"               # target -> source
#   BOT_NAME=Atlas tools/fleet/move-79.sh --teardown   --ref "<ref>"               # undock, detach, quarantine
# Options (env in brackets):
#   --source <pi> [MOVE_SOURCE, default idea03]   --target <pi> [MOVE_TARGET, default idea04]
#   --src-disk <id> [default mv289-src]  --dst-disk <id> [default mv289-dst]  (must start with --prefix)
#   --instance <name> [default mv289-web]  --prefix <p> [default mv289-]  --size-gb <n> [default 4]
#   --src-slot/--dst-slot idea-test-N [default: first free 1..8]  --engine-sha <sha> [ENGINE_SHA; expected HEAD]
#   --image <ref> [MV_IMAGE; scratch App image, must already be on both Pis]  --data-mb <n> [default 16]
# Guards (every mode): both Pis claimed by $BOT_NAME in fleet-state; neither is wizardly-hugle/idea, idea01,
# idea02, a golden/production/kit Pi; Engine store is 2VroE; scratch never on Disk B / WD / a boot disk; only
# loop devices this script created are mounted or detached (by their own /dev/loopN, never losetup -D);
# kid-kolibri-demo and the hands-off containers must be identical (id, state, StartedAt) before and after.
# Loop disks dock only on an Engine in fixture (testMode) mode: pm2 env IDEA_TEST_MODE=true,
# IDEA_DISKS_ROOT=/home/pi/idea/duration-disks, IDEA_WATCH_DIR=/home/pi/idea/duration-watch. This script never
# changes the Engine or its env; --preflight reports it. Docs: tools/fleet/move-79.md.
# pf never fails, so `cond && pf PASS .. || pf FAIL ..` is a safe if/else here.
# shellcheck disable=SC2015
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
STATE_FILE="${STATE_FILE:-$REPO_ROOT/fleet-state.json}"; export STATE_FILE
BOT_NAME="${BOT_NAME:-}"; export BOT_NAME
REMOTE="$HERE/move-79-remote.sh"
ENGINE_DIR="${MV_ENGINE_DIR:-/home/pi/idea/agents/agent-engine-dev}"; HELPER_REMOTE=script/.zz-move-79.ts
EXPECT_STORE="automerge:2VroE"
FIXTURE_ROOT="${MV_FIXTURE_ROOT:-/home/pi/idea/duration-disks}"; FIXTURE_WATCH="${MV_FIXTURE_WATCH:-/home/pi/idea/duration-watch}"
SCRATCH="${MV_SCRATCH:-/home/pi/mv289-scratch}"
KID_PROJECT="kid-kolibri-demo"; KID_PI="${KID_PI:-idea03}"
# Disk B, the WD, and every boot disk listed in tools/fleet/field-usage-rollout.md (idea01, idea02, happy-zebra,
# sunny-robin, idea03, idea04, idea). The root disk of each Pi is also refused dynamically.
PROTECTED_SERIALS="3813430-532011020,20070Q450002,AA000000000000055000,AA000000000000055060,AA000000000000010473,AA000000000000003120,AA202000000000004820,AA202000000000002167,AA000000000000000724"
DENY_NAMES="wizardly-hugle idea idea01 idea02"
DENY_HOSTS="100.115.60.6 192.168.0.231 100.99.231.94 100.85.108.118"
TEMP_PAUSE=75; TEMP_RESUME=65; TEMP_POLL="${TEMP_POLL:-30}"; DOCK_WAIT="${DOCK_WAIT:-180}"

MODE=""; REF=""; SRC_PI="${MOVE_SOURCE:-idea03}"; TGT_PI="${MOVE_TARGET:-idea04}"
PREFIX=mv289-; SRC_DISK=""; DST_DISK=""; INSTANCE=""; SIZE_GB=4; SRC_SLOT=""; DST_SLOT=""
ENGINE_SHA="${ENGINE_SHA:-}"; DATA_MB=16
MV_IMAGE="${MV_IMAGE:-nginx:alpine@sha256:df221db836e1754089190208cee7eeda94f233197056426eda74a43ab1abeac2}"
usage() { sed -n '2,23p' "$0"; }
while [ $# -gt 0 ]; do case "$1" in
  --preflight) MODE=preflight ;; --create-disks) MODE=create ;; --move) MODE=move ;;
  --move-back) MODE=move-back ;; --teardown) MODE=teardown ;;
  --ref) REF="${2:?}"; shift ;; --source) SRC_PI="${2:?}"; shift ;; --target) TGT_PI="${2:?}"; shift ;;
  --src-disk) SRC_DISK="${2:?}"; shift ;; --dst-disk) DST_DISK="${2:?}"; shift ;;
  --instance) INSTANCE="${2:?}"; shift ;; --prefix) PREFIX="${2:?}"; shift ;; --size-gb) SIZE_GB="${2:?}"; shift ;;
  --src-slot) SRC_SLOT="${2:?}"; shift ;; --dst-slot) DST_SLOT="${2:?}"; shift ;;
  --engine-sha) ENGINE_SHA="${2:?}"; shift ;; --image) MV_IMAGE="${2:?}"; shift ;; --data-mb) DATA_MB="${2:?}"; shift ;;
  -h|--help) usage; exit 0 ;;
  *) echo "unknown option $1" >&2; exit 2 ;; esac; shift; done
[ -n "$MODE" ] || { usage; exit 2; }
SRC_DISK="${SRC_DISK:-${PREFIX}src}"; DST_DISK="${DST_DISK:-${PREFIX}dst}"; INSTANCE="${INSTANCE:-${PREFIX}web}"
RUN_ID="${PREFIX%-}-$SRC_PI-$TGT_PI"
WORK="${MOVE_WORK:-$HOME/.local/state/idea-move-79/$RUN_ID}"; mkdir -p "$WORK"
EVID="$WORK/evidence-$(date +%Y%m%d-%H%M%S)-$MODE"; mkdir -p "$EVID"; LOG="$EVID/run.log"

log() { printf '%s %s\n' "$(date '+%F %T %Z')" "$*" | tee -a "$LOG" >&2; }
die() { log "STOP: $*"; rollback_hint; exit 3; }
refuse() { log "REFUSED: $*"; exit 4; }
rsh() { local host="$1"; shift
  local h; for h in $DENY_HOSTS; do [ "$host" = "$h" ] && { echo "refusing protected host $host" >&2; return 99; }; done
  if [ -n "${SSH_CMD:-}" ]; then
    # shellcheck disable=SC2086
    $SSH_CMD "pi@$host" "$@"
  else ssh -o BatchMode=yes -o ConnectTimeout=15 -o ProxyCommand="$HOME/.local/bin/socks-connect %h %p" "pi@$host" "$@"; fi; }
remote() { local host="$1"; shift; rsh "$host" "bash -s -- $(printf '%q ' "$@")" < "$REMOTE"; }
helper() { local host="$1"; shift; rsh "$host" "cd $ENGINE_DIR && MOVE_TIMEOUT=${MOVE_TIMEOUT:-5400} npx tsx $HELPER_REMOTE $*"; }
upload_helper() {  # the one write --preflight makes: the untracked store-reader script (skipped when identical)
  local want; want="$(sha256sum < "$HERE/move-79-engine.ts" | cut -d' ' -f1)"
  [ "$(rsh "$1" "sha256sum < $ENGINE_DIR/$HELPER_REMOTE 2>/dev/null | cut -d' ' -f1" || true)" = "$want" ] && return 0
  rsh "$1" "cat > $ENGINE_DIR/$HELPER_REMOTE" < "$HERE/move-79-engine.ts"; }
kv() { sed -n "s/^$2=//p" <<<"$1" | head -1; }
section() { awk -v s="--- $2" '$0==s{f=1;next} /^--- /{f=0} f' <<<"$1"; }
temp_of() { { rsh "$1" 'vcgencmd measure_temp' 2>/dev/null || true; } | grep -oE '[0-9]+(\.[0-9]+)?' | head -1 || true; }
temp_gate() {  # pause above 75 C, resume below 65 C
  local host="$1" t; t="$(temp_of "$host")"; [ -n "$t" ] || { log "temp $host: unreadable"; return 0; }
  if awk -v t="$t" -v p=$TEMP_PAUSE 'BEGIN{exit !(t>p)}'; then
    log "temp $host ${t} C > ${TEMP_PAUSE} C: PAUSED until < ${TEMP_RESUME} C"
    while t="$(temp_of "$host")"; awk -v t="${t:-99}" -v r=$TEMP_RESUME 'BEGIN{exit !(t>=r)}'; do sleep "$TEMP_POLL"; done
    log "temp $host ${t} C: resumed"
  else log "temp $host ${t} C ok"; fi; }

rollback_hint() { cat <<RB | tee -a "$LOG" >&2
ROLLBACK / CLEANUP (nothing is deleted by this script):
 - Disks: BOT_NAME=$BOT_NAME $0 --teardown --ref "<ref>" (undock via sentinel, umount our slot, losetup -d our
   own /dev/loopN, images + state moved to $SCRATCH/quarantine-<stamp>/ on each Pi).
 - A failed move keeps the source (Engine: "MOVE FAILED ...; source kept"). A moved instance's old folder is in
   <slot>/.idea-quarantine/<id>-<stamp> on the scratch disk itself (op.move.quarantinePath in $WORK/op-*.json).
 - kid-kolibri-demo and the hands-off containers are never touched; compare <evidence>/guard-*.txt with docker ps.
 - Claims: BOT_NAME=$BOT_NAME tools/fleet/update-fleet-state.sh --null <pi> claim ; ... <pi> status idle
 Evidence: $EVID
RB
}

# ---------- guards that need no Pi ----------
pi_field() { jq -r --arg p "$1" --arg f "$2" '.[$p][$f] // empty' "$STATE_FILE"; }
pi_host() { local h; h="$(pi_field "$1" tailscale)"; [ -n "$h" ] || h="$(pi_field "$1" host)"; printf '%s' "$h"; }
guard_pi() {  # guard_pi <pi> <role-word>
  local pi="$1" what="$2" n role status host h
  jq -e --arg p "$pi" 'has($p) and ($p|startswith("_")|not)' "$STATE_FILE" >/dev/null || refuse "$what $pi is not in fleet-state"
  for n in $DENY_NAMES; do [ "$pi" = "$n" ] && refuse "$what $pi is protected (wizardly-hugle/idea, golden idea01, idea02)"; done
  role="$(pi_field "$pi" role)"; status="$(pi_field "$pi" status)"
  case "$role" in golden|production|kit-engine|kit|fleet-pending) refuse "$what $pi has role $role" ;; esac
  [ "$status" = kit ] && refuse "$what $pi is a kit"
  host="$(pi_host "$pi")"; [ -n "$host" ] || refuse "$what $pi has no host"
  for h in $DENY_HOSTS; do [ "$host" = "$h" ] && refuse "$what $pi resolves to protected host $host"; done
  for h in $(pi_field "$pi" host) $(pi_field "$pi" lan); do for n in $DENY_HOSTS; do [ "$h" = "$n" ] && refuse "$what $pi address $h is protected"; done; done
  return 0; }
guard_claims() {
  [ -n "$BOT_NAME" ] || refuse "set BOT_NAME (the claim owner, e.g. Atlas)"
  local pi c bad=0; for pi in "$SRC_PI" "$TGT_PI"; do c="$(pi_field "$pi" claim)"
    if [[ "$c" == "$BOT_NAME"* ]]; then log "claim $pi: '$c' (ok)"; else log "claim $pi: '${c:-none}' is not $BOT_NAME"; bad=1; fi; done
  [ $bad = 0 ] || refuse "both $SRC_PI and $TGT_PI must be claimed by $BOT_NAME in fleet-state before any Pi is contacted"; }
guard_names() {
  [ "$SRC_PI" != "$TGT_PI" ] || refuse "source and target are the same Pi"
  local x; for x in "$SRC_DISK" "$DST_DISK" "$INSTANCE"; do
    case "$x" in "$PREFIX"*) ;; *) refuse "'$x' must start with the scratch prefix $PREFIX" ;; esac; done
  [[ "$PREFIX" =~ ^[a-z0-9]+-$ ]] || refuse "prefix must look like mv289-"
  [[ "$INSTANCE" =~ kid-|kolibri|i159|idea166|nextcloud ]] && refuse "instance $INSTANCE looks like a protected instance"
  [ "$SRC_DISK" != "$DST_DISK" ] || refuse "source and target disk ids are equal"
  return 0; }
guard_pi "$SRC_PI" source; guard_pi "$TGT_PI" target; guard_names
SRC_HOST="${SRC_HOST:-$(pi_host "$SRC_PI")}"; TGT_HOST="${TGT_HOST:-$(pi_host "$TGT_PI")}"
for h in "$SRC_HOST" "$TGT_HOST"; do for n in $DENY_HOSTS; do [ "$h" = "$n" ] && refuse "host override $h is protected"; done; done

exec 9>>"$WORK/lock"; flock -n 9 || { echo "BUSY: another move-79.sh holds $WORK/lock" >&2; exit 75; }
log "move-79.sh $MODE: source $SRC_PI ($SRC_HOST) disk $SRC_DISK -> target $TGT_PI ($TGT_HOST) disk $DST_DISK, instance $INSTANCE (evidence $EVID)"
guard_claims
if [ "$MODE" != preflight ]; then [ -n "$REF" ] || refuse "--$MODE needs --ref \"<who authorised this run, time + link>\""; log "ref: $REF"; fi

# ---------- probe + preflight (read-only) ----------
PF_OK=1
pf() { log "PREFLIGHT $1: $2"; [ "$1" = PASS ] || [ "$1" = INFO ] || PF_OK=0; }
probe_pi() {  # probe_pi <pi> <host> <role>
  local pi="$1" host="$2" role="$3" r
  r="$(remote "$host" probe "$SCRATCH" "$MV_IMAGE" "$ENGINE_DIR" 2>>"$LOG")" || { pf FAIL "$pi unreachable / probe failed"; return; }
  printf '%s\n' "$r" > "$EVID/probe-$pi.txt"
  local t; t="$(kv "$r" TEMP)"
  if [ -z "$t" ]; then pf FAIL "$pi temperature unreadable"
  elif awk -v t="$t" -v p=$TEMP_PAUSE 'BEGIN{exit !(t>p)}'; then pf FAIL "$pi temp ${t} C > ${TEMP_PAUSE} C (pause; resume below ${TEMP_RESUME} C)"
  else pf PASS "$pi temp ${t} C"; fi
  local su; su="$(kv "$r" STORE_URL)"
  [[ "$su" == "$EXPECT_STORE"* ]] && pf PASS "$pi store ${su:0:20}… (2VroE)" || pf FAIL "$pi store '${su:-none}' is not 2VroE"
  local head; head="$(kv "$r" ENGINE_HEAD)"
  if [ -n "$ENGINE_SHA" ]; then [[ "$head" == "$ENGINE_SHA"* ]] && pf PASS "$pi Engine HEAD ${head:0:7} = expected" || pf FAIL "$pi Engine HEAD ${head:0:7}, expected ${ENGINE_SHA:0:7}"
  else pf INFO "$pi Engine HEAD ${head:-?} (no --engine-sha given)"; fi
  [ "$(kv "$r" PM2_ENGINE)" = "online pi" ] && pf PASS "$pi pm2 engine online as pi" || pf FAIL "$pi pm2 engine '$(kv "$r" PM2_ENGINE)'"
  local tm dr wd; tm="$(kv "$r" IDEA_TEST_MODE)"; dr="$(kv "$r" IDEA_DISKS_ROOT)"; wd="$(kv "$r" IDEA_WATCH_DIR)"
  if [ "$tm" = true ] && [ "$dr" = "$FIXTURE_ROOT" ] && [ "$wd" = "$FIXTURE_WATCH" ]; then pf PASS "$pi Engine in fixture mode ($dr, $wd)"
  else pf FAIL "$pi Engine not in fixture mode (IDEA_TEST_MODE='${tm}' IDEA_DISKS_ROOT='${dr}' IDEA_WATCH_DIR='${wd}'): a live Engine ignores loop/idea-test-N disks. Switching modes is Axle's call (see move-79.md), not this script's"; fi
  grep -qw -- "$FIXTURE_ROOT" <<<"$(kv "$r" APP_DATA_ROOTS)" && pf PASS "$pi /etc/idea/app-data-roots lists $FIXTURE_ROOT" || pf FAIL "$pi /etc/idea/app-data-roots lacks $FIXTURE_ROOT (helper would refuse the slot)"
  [ "$(kv "$r" SUDO_LOSETUP)" = yes ] && pf PASS "$pi sudo -n losetup available" || pf FAIL "$pi sudo -n /usr/sbin/losetup not allowed"
  [ "$(kv "$r" IMAGE_PRESENT)" = yes ] && pf PASS "$pi scratch App image present" || pf FAIL "$pi lacks image $MV_IMAGE (pull_policy never)"
  local ss rs p; ss="$(kv "$r" SCRATCH_SERIAL)"; rs="$(kv "$r" ROOT_SERIAL)"
  for p in ${PROTECTED_SERIALS//,/ }; do
    if [ "$ss" = "$p" ] && [ "$ss" != "$rs" ]; then pf FAIL "$pi scratch $SCRATCH sits on protected disk $p"; fi; done
  [ "$ss" = "$rs" ] && pf PASS "$pi scratch images live as files on the root fs (disk ${rs:-?}); the boot disk itself is never selected" || pf FAIL "$pi scratch fs serial '${ss}' is not the root disk '${rs}'"
  local av need; av="$(kv "$r" SCRATCH_AVAIL)"; need=$(( (SIZE_GB + 2) * 1073741824 ))
  [ "${av:-0}" -gt "$need" ] && pf PASS "$pi scratch free $(( ${av:-0} / 1073741824 )) GiB (need > $((SIZE_GB + 2)))" || pf FAIL "$pi scratch free ${av:-?} B < $need B"
  local loops; loops="$(section "$r" LOOPS)"
  pf INFO "$pi loop devices now: $(tr '\n' ';' <<<"$loops")"
  local kid; kid="$(section "$r" GUARD | grep "|$KID_PROJECT" || true)"
  if [ "$pi" = "$KID_PI" ]; then grep -q '|running|' <<<"$kid" && pf PASS "$pi $KID_PROJECT running: $kid (never touched)" || pf FAIL "$pi $KID_PROJECT not running: '${kid:-absent}'"
  elif [ -n "$kid" ]; then pf INFO "$pi has $KID_PROJECT: $kid (never touched)"; fi
  section "$r" GUARD > "$EVID/guard-$pi.baseline.txt"
  section "$r" SCRATCH_STATE > "$EVID/scratch-state-$pi.txt"
  local cons; cons="$(kv "$r" CONSOLE_HTTP)"; pf INFO "$pi Console HTTP ${cons:-none}"
  if upload_helper "$host" 2>>"$LOG"; then
    local st; st="$(helper "$host" state 2>>"$LOG" | tail -1)"; echo "$st" > "$EVID/state-$pi.json"
    pf INFO "$pi moveAppCrossEngine: $(jq -r '.moveAppCrossEngine // "?"' <<<"$st" 2>/dev/null) (must be true before --move)"
    pf INFO "$pi docked disks: $(jq -c '[.disks[]|{id,device}]' <<<"$st" 2>/dev/null)"
  else pf FAIL "$pi store helper upload failed"; fi
  : "$role"; }
guard_now() {  # hands-off containers (kid-kolibri-demo, idea166-*, nextcloud-files-b-001, idea-hub-sidecar) unchanged
  local pi="$1" host="$2" now; now="$(remote "$host" guardsnap 2>>"$LOG" || true)"
  printf '%s\n' "$now" > "$EVID/guard-$pi-$(date +%H%M%S).txt"
  [ -f "$EVID/guard-$pi.baseline.txt" ] || printf '%s\n' "$now" > "$EVID/guard-$pi.baseline.txt"   # baseline = first look in this invocation
  if ! diff <(grep -v '^$' "$EVID/guard-$pi.baseline.txt") <(grep -v '^$' <<<"$now") > "$EVID/guard-$pi.diff"; then
    die "hands-off containers on $pi changed (see $EVID/guard-$pi.diff): stopping before anything else"; fi
  if [ "$pi" = "$KID_PI" ]; then grep -q "|${KID_PROJECT}[^|]*|running|" <<<"$now" || die "$KID_PROJECT is not running on $pi"; fi
  log "guard $pi: hands-off containers unchanged"; }
first_free_slot() { remote "$1" freeslot "$SCRATCH" "$FIXTURE_ROOT" "$FIXTURE_WATCH"; }
disk_state() { helper "$1" state 2>>"$LOG" | tail -1; }
wait_docked() {  # wait_docked <host> <diskId> [instanceName-that-must-run]
  local host="$1" d="$2" inst="${3:-}" st
  for _ in $(seq 1 $(( DOCK_WAIT / 5 ))); do st="$(disk_state "$host")"
    if jq -e --arg d "$d" '.disks|any(.id==$d)' <<<"$st" >/dev/null 2>&1; then
      [ -z "$inst" ] && return 0
      jq -e --arg d "$d" --arg n "$inst" '.instances|any(.diskId==$d and .name==$n and .status=="Running")' <<<"$st" >/dev/null && return 0; fi
    sleep 5; done; return 1; }
wait_undocked() { local host="$1" d="$2"
  for _ in $(seq 1 $(( DOCK_WAIT / 5 ))); do jq -e --arg d "$d" '.disks|any(.id==$d)|not' <<<"$(disk_state "$host")" >/dev/null 2>&1 && return 0; sleep 5; done; return 1; }

run_preflight() {
  probe_pi "$SRC_PI" "$SRC_HOST" source; probe_pi "$TGT_PI" "$TGT_HOST" target
  log "PREFLIGHT RESULT: $([ $PF_OK = 1 ] && echo ALL PASS || echo NOT READY)"; }

# ---------- modes ----------
case "$MODE" in
preflight) run_preflight; exit $(( 1 - PF_OK )) ;;
create)
  run_preflight; [ $PF_OK = 1 ] || die "preflight not clean"
  for pair in "$SRC_PI|$SRC_HOST|$SRC_DISK|$SRC_SLOT|src" "$TGT_PI|$TGT_HOST|$DST_DISK|$DST_SLOT|dst"; do
    IFS='|' read -r pi host disk slot role <<<"$pair"
    [ -e "$WORK/created-$disk" ] && { log "$disk already created ($(cat "$WORK/created-$disk"))"; continue; }
    temp_gate "$host"; guard_now "$pi" "$host"
    [ -n "$slot" ] || slot="$(first_free_slot "$host")" || die "no free idea-test-N slot under $FIXTURE_ROOT on $pi"
    [[ "$slot" =~ ^idea-test-[0-9]+$ ]] || die "bad slot '$slot'"
    if [ "$role" = src ]; then out="$(remote "$host" create "$SCRATCH" "$FIXTURE_ROOT" "$FIXTURE_WATCH" "$slot" "$disk" "$SIZE_GB" "$PREFIX" "$PROTECTED_SERIALS" "$INSTANCE" "$MV_IMAGE" "$DATA_MB" 2>&1)" || true
    else out="$(remote "$host" create "$SCRATCH" "$FIXTURE_ROOT" "$FIXTURE_WATCH" "$slot" "$disk" "$SIZE_GB" "$PREFIX" "$PROTECTED_SERIALS" 2>&1)" || true; fi
    log "$pi create: $out"; grep -q '^CREATED ' <<<"$out" || die "create $disk on $pi failed"
    loop="$(grep -o 'loop=/dev/loop[0-9]*' <<<"$out" | cut -d= -f2)"
    echo "$pi $slot $loop" > "$WORK/created-$disk"
    remote "$host" dock "$SCRATCH" "$FIXTURE_WATCH" "$disk" >>"$LOG" 2>&1 || die "dock sentinel for $disk failed"
    if [ "$role" = src ]; then wait_docked "$host" "$disk" "$INSTANCE" || die "$disk/$INSTANCE not docked+Running on $pi within ${DOCK_WAIT}s"
    else wait_docked "$host" "$disk" || die "$disk not docked on $pi within ${DOCK_WAIT}s"; fi
    log "$disk docked on $pi ($slot, $loop)"; guard_now "$pi" "$host"; done
  log "DISKS READY: $SRC_DISK on $SRC_PI holds $INSTANCE (Running); $DST_DISK on $TGT_PI empty" ;;
move|move-back)
  if [ "$MODE" = move ]; then FP="$SRC_PI"; FH="$SRC_HOST"; FD="$SRC_DISK"; TP="$TGT_PI"; TH="$TGT_HOST"; TD="$DST_DISK"
  else FP="$TGT_PI"; FH="$TGT_HOST"; FD="$DST_DISK"; TP="$SRC_PI"; TH="$SRC_HOST"; TD="$SRC_DISK"; fi
  [ -e "$WORK/created-$SRC_DISK" ] && [ -e "$WORK/created-$DST_DISK" ] || die "run --create-disks first"
  [ -e "$WORK/done-$MODE" ] && { log "$MODE already done ($(cat "$WORK/done-$MODE"))"; exit 0; }
  [ "$MODE" = move-back ] && { [ -e "$WORK/done-move" ] || die "--move-back needs a finished --move"; }
  for p in "$FP|$FH" "$TP|$TH"; do IFS='|' read -r pi host <<<"$p"; temp_gate "$host"; guard_now "$pi" "$host"; done
  for h in "$FH" "$TH"; do upload_helper "$h"; done
  fs="$(disk_state "$FH")"; ts="$(disk_state "$TH")"; echo "$fs" > "$EVID/from-state.json"; echo "$ts" > "$EVID/to-state.json"
  for s in "$fs" "$ts"; do [ "$(jq -r .moveAppCrossEngine <<<"$s")" = true ] || die "moveAppCrossEngine not advertised by both Engines (deploy #289 first)"; done
  jq -e --arg d "$FD" '.disks|any(.id==$d)' <<<"$fs" >/dev/null || die "$FD not docked on $FP"
  jq -e --arg d "$TD" '.disks|any(.id==$d)' <<<"$ts" >/dev/null || die "$TD not docked on $TP"
  sel="$(jq -c --arg d "$FD" --arg n "$INSTANCE" '[.instances[]|select(.diskId==$d and .name==$n)]' <<<"$fs")"
  [ "$(jq length <<<"$sel")" = 1 ] || die "expected exactly one $INSTANCE on $FD ($FP), got $(jq -c 'map(.id)' <<<"$sel")"
  SID="$(jq -r '.[0].id' <<<"$sel")"; [[ "$SID" =~ kid-|kolibri|i159|idea166 ]] && die "refusing instance id $SID"
  FSLOT="$(jq -r --arg d "$FD" '.disks[]|select(.id==$d)|.device' <<<"$fs")"; TSLOT="$(jq -r --arg d "$TD" '.disks[]|select(.id==$d)|.device' <<<"$ts")"
  [[ "$FSLOT" =~ ^idea-test-[0-9]+$ && "$TSLOT" =~ ^idea-test-[0-9]+$ ]] || die "scratch disks are not on idea-test-N slots ($FSLOT, $TSLOT)"
  remote "$FH" manifest "$FIXTURE_ROOT/$FSLOT/instances/$SID" > "$EVID/source.sha256" || die "source manifest failed"
  log "source manifest: $(wc -l < "$EVID/source.sha256") files in $FP:$FIXTURE_ROOT/$FSLOT/instances/$SID"
  ( while sleep 60; do for h in "$FH" "$TH"; do t="$(temp_of "$h")"; log "watch temp $h ${t:-?} C"
      awk -v t="${t:-0}" 'BEGIN{exit !(t>75)}' && log "WARNING $h above 75 C during the move (not interrupted; next step pauses)"; done; done ) 9>&- & WATCH=$!   # 9>&-: the watcher must not keep the run lock
  log "sending to $FP: moveApp $SID $FD $TD"
  r="$(helper "$FH" cmd moveApp "$SID" "$FD" "$TD" | tail -1)" || true; kill "$WATCH" 2>/dev/null || true
  echo "$r" > "$EVID/trace.json"; log "trace: $r"
  helper "$FH" op "$SID" | tail -1 > "$EVID/op.json"; cp "$EVID/op.json" "$WORK/op-$MODE.json"; log "op: $(cat "$EVID/op.json")"
  code="$(jq -r '.move.code // empty' "$EVID/op.json")"
  case "$code" in MOVED|SOURCE_NOT_REMOVED|SOURCE_CHANGED) ;; *) die "move did not finish: ${code:-$(jq -r '.errorMessage // .error // "?"' <<<"$r")}" ;; esac
  temp_gate "$TH"
  NID="$(jq -r '.move.targetInstanceId // empty' "$EVID/op.json")"; [ -n "$NID" ] || die "op has no targetInstanceId"
  ti="$(helper "$TH" find "$INSTANCE" | jq -c --arg i "$NID" 'select(.id==$i)')"; echo "$ti" > "$EVID/target-instance.json"
  [ "$(jq -r .diskId <<<"$ti")" = "$TD" ] || die "instance $NID not stored on $TD"
  [ "$(jq -r .status <<<"$ti")" = Running ] || die "instance $NID on $TP is $(jq -r .status <<<"$ti"), not Running"
  remote "$TH" manifest "$FIXTURE_ROOT/$TSLOT/instances/$NID" > "$EVID/target.sha256" || die "target manifest failed"
  diff <(awk '{print $2}' "$EVID/source.sha256") <(awk '{print $2}' "$EVID/target.sha256") > "$EVID/files.diff" || die "file lists differ (see $EVID/files.diff); source kept or quarantined, never deleted"
  diff "$EVID/source.sha256" "$EVID/target.sha256" > "$EVID/sums.diff" || die "checksums differ (see $EVID/sums.diff)"
  port="$(jq -r '.port // empty' <<<"$ti")"
  if [ -n "$port" ]; then hc="$(rsh "$TH" "curl -s -o /dev/null -w %{http_code} --max-time 10 http://127.0.0.1:$port/" || true)"
    [ "$hc" = 200 ] || die "moved instance on $TP:$port answers HTTP ${hc:-none}"; log "moved instance answers HTTP 200 on $TP:$port"; fi
  for p in "$FP|$FH" "$TP|$TH"; do IFS='|' read -r pi host <<<"$p"; guard_now "$pi" "$host"; done
  echo "$code $NID $(date '+%F %T %Z')" > "$WORK/done-$MODE"
  log "$MODE DONE: $INSTANCE ($SID -> $NID) now Running on $TP disk $TD; files + sha256 identical ($(wc -l < "$EVID/target.sha256") files); code $code" ;;
teardown)
  STAMP="$(date +%Y%m%d-%H%M%S)"
  for pair in "$SRC_PI|$SRC_HOST|$SRC_DISK" "$TGT_PI|$TGT_HOST|$DST_DISK"; do
    IFS='|' read -r pi host disk <<<"$pair"
    [ -e "$WORK/created-$disk" ] || { log "$disk: not created by this run on $pi (nothing to do)"; continue; }
    guard_now "$pi" "$host"; upload_helper "$host"
    remote "$host" undock "$SCRATCH" "$FIXTURE_WATCH" "$disk" >>"$LOG" 2>&1 || die "undock $disk on $pi failed"
    wait_undocked "$host" "$disk" || die "$disk still docked on $pi after ${DOCK_WAIT}s (sentinel removed; check the Engine)"
    out="$(remote "$host" detach "$SCRATCH" "$disk" "$STAMP" 2>&1)" || true; log "$pi detach: $out"
    grep -q '^QUARANTINED .*\.state$' <<<"$out" || die "detach of $disk on $pi incomplete"
    left="$(rsh "$host" "docker ps -a --filter label=org.idea.mv79=true --format '{{.ID}} {{.Names}} {{.Status}}'" || true)"
    log "$pi leftover scratch containers (not removed): ${left:-none}"
    mv "$WORK/created-$disk" "$EVID/"; guard_now "$pi" "$host"; done
  log "TEARDOWN DONE: images + state in $SCRATCH/quarantine-$STAMP/ on each Pi; release claims next" ;;
esac
