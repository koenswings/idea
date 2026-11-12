#!/usr/bin/env bash
# move-79.sh — idea#79 real two-Engine Move run: one App instance moves from idea04 (source) to
# idea01's new App disk (target) with the Engine's own cross-Engine `moveApp` (agent-engine-dev#289).
#
#   BOT_NAME=Atlas tools/fleet/move-79.sh --preflight                  # read-only, safe any time
#   BOT_NAME=Atlas tools/fleet/move-79.sh --go --koen-yes "<ref>"     # the real run (needs Koen's fresh yes)
#   options: --instance <name|id>  (default: the only instance on idea04's App disk; >1 -> must choose)
#            --skip-restore        leave both Pis on the PR build (default: restore to the recorded main SHAs)
#
# What --go does (each step writes a marker; a re-run skips finished steps; .done ends it):
#   preflight -> claim idea04+idea01 (Atlas) -> deploy PR #289 Engine on idea04, then idea01
#   (deploy-engine-remote.sh, one at a time, temp guard 75/65 C) -> wait for moveAppCrossEngine on both
#   -> manifest of the source folder (file count, bytes, sha256 per file) -> `moveApp <id> <srcDisk> <tgtDisk>`
#   sent to idea04 -> verify on idea01 (Running on the target disk, manifest compare, Console HTTP + store)
#   -> restore both Engines to their recorded commits -> release claims -> .done.
#   (--target-only with --preflight checks idea01 only.) Source size vs target free space is checked at the manifest step.
# Nothing is ever deleted: the Engine quarantines the source (helper v4), this script only reads and moves markers.
# Never touches wh (100.115.60.6) or idea02. pm2 always runs as pi (checked). No pkill/pgrep -f.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
STATE_FILE="${STATE_FILE:-$REPO_ROOT/fleet-state.json}"; export STATE_FILE
BOT_NAME="${BOT_NAME:-}"; export BOT_NAME
UFS="$HERE/update-fleet-state.sh"

SRC_PI=idea04; SRC_HOST="${SRC_HOST:-100.108.39.45}"
TGT_PI=idea01; TGT_HOST="${TGT_HOST:-100.99.231.94}"
TGT_SERIAL=2026080400771; TGT_UUID=93ad8cc4-acba-47fe-9cb4-363789935e5c
TGT_DISK_ID=cd8787b352df466b86d91975fe3a372b; TGT_MOUNT=/disks/sdb1
PR_BRANCH=axle/move-app-79; PR_SHA="${PR_SHA:-96b6f19bd3ebc4db785f1abd76da5a5aff6ddcde}"   # agent-engine-dev#289 head
TGT_RESTORE_SHA=77d961b68254879184f97a9a454484bbbe02aac6     # Koen 10-29 11:14: idea01 back to Engine 77d961b
ENGINE_DIR=/home/pi/idea/agents/agent-engine-dev; HELPER_REMOTE=script/.zz-move-79.ts
TEMP_PAUSE=75; TEMP_RESUME=65; TEMP_POLL="${TEMP_POLL:-30}"
WORK="${MOVE_WORK:-$HOME/.local/state/idea-move-79}"; mkdir -p "$WORK/steps"
EVID="$WORK/evidence-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$EVID"; LOG="$EVID/run.log"

TARGET_ONLY=0; MODE=""; KOEN_YES=""; INSTANCE=""; SKIP_RESTORE=0
while [ $# -gt 0 ]; do case "$1" in
  --preflight) MODE=preflight ;; --go) MODE=go ;;
  --koen-yes) KOEN_YES="${2:?}"; shift ;; --instance) INSTANCE="${2:?}"; shift ;;
  --skip-restore) SKIP_RESTORE=1 ;; --target-only) TARGET_ONLY=1 ;; -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
  *) echo "unknown option $1" >&2; exit 2 ;; esac; shift; done
[ -n "$MODE" ] || { sed -n '2,18p' "$0"; exit 2; }

log() { printf '%s %s\n' "$(date '+%F %T %Z')" "$*" | tee -a "$LOG" >&2; }
die() { log "STOP: $*"; rollback_hint; exit 3; }
rsh() { local host="$1"; shift
  case "$host" in 100.115.60.6|*idea02*) echo "refusing protected host $host" >&2; return 99 ;; esac
  ssh -o BatchMode=yes -o ConnectTimeout=15 -o ProxyCommand="$HOME/.local/bin/socks-connect %h %p" "pi@$host" "$@"; }
helper() { local host="$1"; shift; rsh "$host" "cd $ENGINE_DIR && MOVE_TIMEOUT=${MOVE_TIMEOUT:-5400} npx tsx $HELPER_REMOTE $*"; }
upload_helper() { rsh "$1" "cat > $ENGINE_DIR/$HELPER_REMOTE" < "$HERE/move-79-engine.ts"; }
done_step() { [ -e "$WORK/steps/$1" ]; }
mark() { date '+%F %T %Z' > "$WORK/steps/$1"; log "step $1: done"; }
temp_of() { { rsh "$1" 'vcgencmd measure_temp' 2>/dev/null || true; } | grep -oE '[0-9]+(\.[0-9]+)?' | head -1 || true; }
temp_gate() {  # pause above 75 C, resume below 65 C (polls every TEMP_POLL s)
  local host="$1" t; t="$(temp_of "$host")"; [ -n "$t" ] || { log "temp $host: unreadable"; return 0; }
  if awk -v t="$t" -v p=$TEMP_PAUSE 'BEGIN{exit !(t>p)}'; then
    log "temp $host ${t} C > ${TEMP_PAUSE} C: PAUSED until < ${TEMP_RESUME} C"
    while t="$(temp_of "$host")"; awk -v t="${t:-99}" -v r=$TEMP_RESUME 'BEGIN{exit !(t>=r)}'; do sleep "$TEMP_POLL"; done
    log "temp $host ${t} C: resumed"
  else log "temp $host ${t} C ok"; fi; }

rollback_hint() { cat <<RB | tee -a "$LOG" >&2
ROLLBACK (nothing is ever deleted by this run):
 - Refused / MOVE FAILED (...; source kept): nothing to undo; the source instance stays on $SRC_PI (Engine restarts it).
 - Done but wrong on $TGT_PI: stop it there, then send moveApp <newId> $TGT_DISK_ID <idea04 diskId> on $TGT_PI
   (same cross-Engine path back), or put the quarantined source back on $SRC_PI:
   sudo mv <disk>/.idea-quarantine/<id>-<stamp> <disk>/instances/<id>  (path = op.move.quarantinePath in $EVID/op.json),
   then re-dock the disk / pm2 restart engine (as pi) so the Engine re-registers it.
 - Engines: tools/fleet/deploy-engine-remote.sh pi@$TGT_HOST $TGT_RESTORE_SHA --yes (and $SRC_PI to the SHA in $WORK/src-version).
 - Claims: BOT_NAME=Atlas tools/fleet/update-fleet-state.sh --null <pi> claim ; status idle.
 Evidence: $EVID
RB
}

# ---------- preflight (read-only) ----------
PF_OK=1
pf() { log "PREFLIGHT $1: $2"; [ "$1" = PASS ] || PF_OK=0; }
preflight_target() {
  local claim status; claim="$(jq -r ".$TGT_PI.claim // empty" "$STATE_FILE")"; status="$(jq -r ".$TGT_PI.status" "$STATE_FILE")"
  [ -z "$claim" ] || [[ "$claim" == Atlas* ]] && pf PASS "$TGT_PI fleet-state claim='${claim:-none}' status=$status" || pf FAIL "$TGT_PI claimed by $claim"
  local r; r="$(rsh "$TGT_HOST" "lsblk -nro NAME,SERIAL,UUID,MOUNTPOINT; echo ---; cat $TGT_MOUNT/META.yaml; echo ---; echo AVAIL=\$(df -B1 --output=avail $TGT_MOUNT | tail -1); echo NINST=\$(ls -A $TGT_MOUNT/instances 2>/dev/null | wc -l); echo ---; vcgencmd measure_temp; echo ---; pm2 jlist" 2>>"$LOG")" \
    || { pf FAIL "$TGT_PI unreachable"; return; }
  printf '%s\n' "$r" > "$EVID/target-raw.txt"
  local dev; dev="$(awk -v s=$TGT_SERIAL '$2==s{print $1}' <<<"$r")"
  [ -n "$dev" ] && pf PASS "$TGT_PI disk serial $TGT_SERIAL on /dev/$dev" || pf FAIL "$TGT_PI disk serial $TGT_SERIAL not present"
  grep -q "$TGT_UUID .*$TGT_MOUNT\$\|$TGT_UUID $TGT_MOUNT" <<<"$r" && pf PASS "UUID $TGT_UUID mounted at $TGT_MOUNT" || pf FAIL "UUID $TGT_UUID not mounted at $TGT_MOUNT"
  grep -q "diskId: $TGT_DISK_ID" <<<"$r" && pf PASS "META.yaml diskId $TGT_DISK_ID" || pf FAIL "META.yaml diskId mismatch"
  local avail n; avail="$(sed -n 's/^AVAIL= *//p' <<<"$r")"; n="$(sed -n 's/^NINST=//p' <<<"$r")"
  [ "${avail:-0}" -gt 1073741824 ] && pf PASS "target free $(( avail / 1024 / 1024 / 1024 )) GiB" || pf FAIL "target free ${avail:-?} B"
  echo "$avail" > "$EVID/target-avail"
  [ "${n:-0}" = 0 ] && pf PASS "target instances/ empty" || pf FAIL "target already holds $n instance folder(s)"
  local t; t="$(grep -oE "temp=[0-9.]+" <<<"$r" | cut -d= -f2)"
  awk -v t="$t" 'BEGIN{exit !(t<=75)}' && pf PASS "$TGT_PI temp ${t} C" || pf FAIL "$TGT_PI temp ${t} C > 75"
  local pm; pm="$(sed -n '/^\[/,$p' <<<"$r" | jq -r '.[]|select(.name=="engine")|"\(.pm2_env.status) \(.pm2_env.username)"' 2>/dev/null)"
  [ "$pm" = "online pi" ] && pf PASS "$TGT_PI pm2 engine online as pi" || pf FAIL "$TGT_PI pm2 engine: '${pm:-missing}'"
  upload_helper "$TGT_HOST" 2>>"$LOG" || { pf FAIL "helper upload to $TGT_PI"; return; }
  local st; st="$(helper "$TGT_HOST" state 2>>"$LOG" | tail -1)"; echo "$st" > "$EVID/target-state.json"
  jq -e --arg d "$TGT_DISK_ID" '.disks|any(.id==$d)' <<<"$st" >/dev/null && pf PASS "Engine on $TGT_PI lists disk $TGT_DISK_ID as docked" || pf FAIL "Engine on $TGT_PI does not list $TGT_DISK_ID"
  pf PASS "$TGT_PI moveAppCrossEngine now: $(jq -r .moveAppCrossEngine <<<"$st") (expected false until the PR build is deployed at go-time)"
  local code; code="$(rsh "$TGT_HOST" 'curl -s -o /dev/null -w %{http_code} http://127.0.0.1/' 2>/dev/null || true)"
  [ "$code" = 200 ] && pf PASS "$TGT_PI Console HTTP 200" || pf FAIL "$TGT_PI Console HTTP ${code:-none}"
}
preflight_source() {
  local claim; claim="$(jq -r ".$SRC_PI.claim // empty" "$STATE_FILE")"
  if [ -n "$claim" ] && [[ "$claim" != Atlas* ]]; then pf FAIL "$SRC_PI claimed by $claim (must be released first)"; fi
  if ! rsh "$SRC_HOST" true 2>>"$LOG"; then pf FAIL "$SRC_PI unreachable, waiting on idea#375 item 7 (power-cycle)"; return; fi
  local t; t="$(temp_of "$SRC_HOST")"; awk -v t="${t:-0}" 'BEGIN{exit !(t<=75)}' && pf PASS "$SRC_PI temp ${t:-?} C" || pf FAIL "$SRC_PI temp $t C"
  local pm; pm="$(rsh "$SRC_HOST" pm2 jlist | jq -r '.[]|select(.name=="engine")|"\(.pm2_env.status) \(.pm2_env.username)"' || true)"
  [ "$pm" = "online pi" ] && pf PASS "$SRC_PI pm2 engine online as pi" || pf FAIL "$SRC_PI pm2 engine: '${pm:-missing}'"
  rsh "$SRC_HOST" "lsblk -nro NAME,SERIAL,SIZE,MOUNTPOINT" > "$EVID/source-lsblk.txt" 2>>"$LOG" || true
  rsh "$SRC_HOST" "cd $ENGINE_DIR && git rev-parse HEAD" > "$EVID/source-version" 2>>"$LOG" || true
  upload_helper "$SRC_HOST" 2>>"$LOG" || { pf FAIL "helper upload to $SRC_PI"; return; }
  local st; st="$(helper "$SRC_HOST" state 2>>"$LOG" | tail -1)"; echo "$st" > "$EVID/source-state.json"
  local disks; disks="$(jq -r '[.disks[]|select(.device|test("^sd"))]|length' <<<"$st" 2>/dev/null || echo 0)"
  [ "${disks:-0}" -ge 1 ] && pf PASS "$SRC_PI USB App disk(s) docked: $(jq -c '[.disks[]|select(.device|test("^sd"))|.id]' <<<"$st")" || pf FAIL "$SRC_PI no USB App disk docked"
  local sel; sel="$(jq -c --arg q "$INSTANCE" '[.instances[]|select(($q=="") or .name==$q or .id==$q)]' <<<"$st")"
  case "$(jq length <<<"$sel")" in
    1) jq -c '.[0]' <<<"$sel" > "$EVID/source-instance.json"; pf PASS "source instance $(jq -c '.[0]|{id,name,status,diskId}' <<<"$sel")" ;;
    0) pf FAIL "source instance '${INSTANCE:-any}' not found on $SRC_PI" ;;
    *) pf FAIL "several instances on $SRC_PI, choose with --instance: $(jq -c 'map(.name)' <<<"$sel")" ;;
  esac
}

manifest() {  # manifest <host> <dir> -> "count bytes" + per-file sums in evidence
  rsh "$1" "sudo -n find '$2' -type f -printf '%P\n' | LC_ALL=C sort | (cd '$2' && sudo -n xargs -r -d '\n' sha256sum)" ; }

# ---------- main ----------
exec 9>>"$WORK/lock"; flock -n 9 || { echo "BUSY: another move-79.sh holds $WORK/lock" >&2; exit 75; }
log "move-79.sh $MODE (evidence $EVID)"
if [ -e "$WORK/.done" ]; then log "already done ($(cat "$WORK/.done")); nothing to do"; exit 0; fi
preflight_target; if [ "$TARGET_ONLY" = 1 ] && [ "$MODE" = preflight ]; then log "PREFLIGHT idea04 part skipped (--target-only)"; else preflight_source; fi
if [ "$MODE" = preflight ]; then log "PREFLIGHT RESULT: $([ $PF_OK = 1 ] && echo ALL PASS || echo NOT READY)"; exit $(( 1 - PF_OK )); fi

[ "$BOT_NAME" = Atlas ] || die "run with BOT_NAME=Atlas"
[ -n "$KOEN_YES" ] || die "--go needs --koen-yes \"<Koen's fresh yes: time + link>\""
[ $PF_OK = 1 ] || die "preflight not clean"
log "Koen's yes: $KOEN_YES"; echo "$KOEN_YES" > "$EVID/koen-yes.txt"
[ -s "$WORK/src-version" ] || cp "$EVID/source-version" "$WORK/src-version"
cp -n "$EVID/source-instance.json" "$WORK/source-instance.json"
SID="$(jq -r .id "$WORK/source-instance.json")"; SDISK="$(jq -r .diskId "$WORK/source-instance.json")"; SNAME="$(jq -r .name "$WORK/source-instance.json")"

if ! done_step claim; then
  "$UFS" "$SRC_PI" claim Atlas && "$UFS" "$SRC_PI" status testing
  "$UFS" "$TGT_PI" claim Atlas && "$UFS" "$TGT_PI" status testing
  log "claimed $SRC_PI + $TGT_PI in $STATE_FILE (push via the usual fleet-state flow)"; mark claim; fi
for pair in "$SRC_PI:$SRC_HOST" "$TGT_PI:$TGT_HOST"; do pi="${pair%%:*}"; host="${pair#*:}"
  done_step "deploy-$pi" && continue
  temp_gate "$host"
  SSH_CMD="ssh -o BatchMode=yes -o ConnectTimeout=15 -o ProxyCommand=$HOME/.local/bin/socks-connect\ %h\ %p" \
    "$HERE/deploy-engine-remote.sh" "pi@$host" "$PR_SHA" --fetch "$PR_BRANCH" --yes >>"$LOG" 2>&1 || die "PR deploy on $pi failed (deploy aborts before pm2 restart)"
  upload_helper "$host"; mark "deploy-$pi"; done
if ! done_step capability; then
  for host in "$SRC_HOST" "$TGT_HOST"; do ok=0
    for _ in $(seq 1 40); do [ "$(helper "$host" state | tail -1 | jq -r .moveAppCrossEngine)" = true ] && { ok=1; break; }; sleep 15; done
    [ $ok = 1 ] || die "moveAppCrossEngine not advertised by $host after 10 min"; done; mark capability; fi
if ! done_step manifest; then
  SROOT="$(rsh "$SRC_HOST" "grep -l 'diskId: $SDISK' /disks/*/META.yaml" | head -1 | xargs -r dirname)"
  [ -n "$SROOT" ] || die "source disk $SDISK not mounted under /disks on $SRC_PI"
  manifest "$SRC_HOST" "$SROOT/instances/$SID" > "$WORK/source.sha256" || die "source manifest failed"
  sbytes="$(rsh "$SRC_HOST" "sudo -n du -sb '$SROOT/instances/$SID'" | cut -f1)"
  [ "${sbytes:-0}" -lt "$(( $(cat "$EVID/target-avail") - 1073741824 ))" ] || die "source ${sbytes} B does not fit on the target"
  log "source manifest: $(wc -l < "$WORK/source.sha256") files in $SROOT/instances/$SID"; mark manifest; fi
if ! done_step move; then
  temp_gate "$SRC_HOST"; temp_gate "$TGT_HOST"
  ( while sleep 60; do for h in "$SRC_HOST" "$TGT_HOST"; do t="$(temp_of "$h")"; log "watch temp $h ${t:-?} C"
      awk -v t="${t:-0}" 'BEGIN{exit !(t>75)}' && log "WARNING $h above 75 C during the move (Engine op not interruptible; next step will pause)"; done; done ) & WATCH=$!
  log "sending to $SRC_PI: moveApp $SID $SDISK $TGT_DISK_ID ($SNAME)"
  r="$(helper "$SRC_HOST" cmd moveApp "$SID" "$SDISK" "$TGT_DISK_ID" | tail -1)"; kill "$WATCH" 2>/dev/null || true
  echo "$r" > "$EVID/trace.json"; log "trace: $r"
  helper "$SRC_HOST" op "$SID" | tail -1 > "$EVID/op.json"; cp "$EVID/op.json" "$WORK/op.json"; log "op: $(cat "$EVID/op.json")"
  code="$(jq -r '.move.code // empty' "$EVID/op.json")"
  case "$code" in MOVED|SOURCE_NOT_REMOVED|SOURCE_CHANGED) mark move ;; *) die "move did not finish: ${code:-$(jq -r .errorMessage <<<"$r")}" ;; esac; fi
if ! done_step verify; then
  temp_gate "$TGT_HOST"
  NID="$(jq -r '.move.targetInstanceId' "$WORK/op.json")"
  ti="$(helper "$TGT_HOST" find "$SNAME" | jq -c --arg i "$NID" 'select(.id==$i)')"; echo "$ti" > "$EVID/target-instance.json"
  [ "$(jq -r .diskId <<<"$ti")" = "$TGT_DISK_ID" ] || die "instance $NID not stored on $TGT_DISK_ID"
  [ "$(jq -r .status <<<"$ti")" = Running ] || die "instance $NID on $TGT_PI is $(jq -r .status <<<"$ti"), not Running"
  manifest "$TGT_HOST" "$TGT_MOUNT/instances/$NID" > "$EVID/target.sha256" || die "target manifest failed"
  diff <(awk '{print $2}' "$WORK/source.sha256") <(awk '{print $2}' "$EVID/target.sha256") > "$EVID/files.diff" && fl=same || fl=differ
  sd="$(diff "$WORK/source.sha256" "$EVID/target.sha256" | grep -c '^>' || true)"
  log "verify: files $fl (src $(wc -l < "$WORK/source.sha256"), tgt $(wc -l < "$EVID/target.sha256")); checksum changes $sd (files a running App rewrites at start are listed in $EVID)"
  [ "$fl" = same ] || die "file lists differ (see $EVID/files.diff); source is quarantined, not deleted"
  code="$(rsh "$TGT_HOST" 'curl -s -o /dev/null -w %{http_code} http://127.0.0.1/' || true)"
  [ "$code" = 200 ] || die "Console on $TGT_PI HTTP $code"
  log "Console on $TGT_PI serves (HTTP 200) from the shared store that lists $SNAME Running on $TGT_DISK_ID"; mark verify; fi
if [ $SKIP_RESTORE = 0 ] && ! done_step restore; then
  for pair in "$TGT_PI:$TGT_HOST:$TGT_RESTORE_SHA" "$SRC_PI:$SRC_HOST:$(cat "$WORK/src-version")"; do
    IFS=: read -r pi host sha <<<"$pair"; temp_gate "$host"
    SSH_CMD="ssh -o BatchMode=yes -o ConnectTimeout=15 -o ProxyCommand=$HOME/.local/bin/socks-connect\ %h\ %p" \
      "$HERE/deploy-engine-remote.sh" "pi@$host" "$sha" --yes >>"$LOG" 2>&1 || die "restore of $pi to $sha failed"
    log "$pi restored to $sha"; done; mark restore; fi
if ! done_step release; then
  for pi in "$SRC_PI" "$TGT_PI"; do "$UFS" --null "$pi" claim; "$UFS" "$pi" status idle; done; mark release; fi
date '+%F %T %Z' > "$WORK/.done"; log "MOVE RUN COMPLETE: $SNAME now on $TGT_PI disk $TGT_DISK_ID; evidence $EVID"
