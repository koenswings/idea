#!/usr/bin/env bash
# kit-kolibri-morango.sh — idea#288 first contact: apply app-kolibri#8 (MORANGO_SYSTEM_ID=idea-${hostname}-${port})
# to every Kolibri instance (real + Demo) on ONE Engine, restarting each changed instance through the Engine.
# Usage: kit-kolibri-morango.sh --host <tailscale-name> [--ip <ip>] [--dry-run]
# Exit: 0 ok/nothing to do | 2 usage/refused host | 3 unreachable/Engine helper failed | 10 temp >75C
#       11 Console or an app not answering | 12 instance ids not unique after | 13 conflict/unsupported compose (not touched)
#       14 restart failed or instance not healthy in time | 75 busy (lock held)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS_SOCK="${TS_SOCK:-/home/box/.local/share/tailscale/tailscaled.sock}"
PROXY="${PROXY:-127.0.0.1:1055}"
LOGDIR="${LOGDIR:-/workspace/idea288/logs}"
ENGINE_DIR="${ENGINE_DIR:-~/idea/agents/agent-engine-dev}"
HELPER_REMOTE="script/.zz-kolibri-morango.ts"
TEMP_MAX="${TEMP_MAX:-75}"
HEALTH_WAIT="${HEALTH_WAIT:-300}"
DENY_HOSTS="idea idea02 wizardly-hugle"   # wh/Milkwise and idea02 are never touched

# ---------- pure logic (unit-tested in test/run-tests.sh) ----------
expected_id() { printf 'idea-%s-%s' "$1" "$2"; }

# compose_state <compose text on stdin> -> none | template | literal:<value> | multi
compose_state() {
  local lines; lines="$(grep -E '^[[:space:]]*(-[[:space:]]*MORANGO_SYSTEM_ID=|MORANGO_SYSTEM_ID:)' || true)"
  local n; n=$(printf '%s' "$lines" | grep -c . || true)
  [ "$n" = 0 ] && { echo none; return; }
  [ "$n" -gt 1 ] && { echo multi; return; }
  local v; v="$(printf '%s' "$lines" | sed -E 's/^[[:space:]]*-?[[:space:]]*MORANGO_SYSTEM_ID[=:][[:space:]]*//; s/^["'"'"']//; s/["'"'"'][[:space:]]*$//; s/[[:space:]]+$//')"
  if [ "$v" = 'idea-${hostname}-${port}' ]; then echo template; else echo "literal:$v"; fi
}

# decide <compose_state> <container MORANGO value or ''> <expected> -> SKIP | RESTART | PATCH_RESTART | PATCH_ONLY | CONFLICT
decide() {
  local cs="$1" cur="$2" exp="$3"
  case "$cs" in
    none)     [ "$cur" = "$exp" ] && echo PATCH_ONLY || echo PATCH_RESTART ;;
    template) [ "$cur" = "$exp" ] && echo SKIP || echo RESTART ;;
    literal:*) if [ "${cs#literal:}" = "$exp" ]; then [ "$cur" = "$exp" ] && echo SKIP || echo RESTART; else echo CONFLICT; fi ;;
    *) echo CONFLICT ;;
  esac
}

# patch_compose: stdin compose -> stdout compose with the #8 lines after the single "- KOLIBRI_LISTEN_PORT=" line.
# Returns 13 (prints nothing) when there is not exactly one such list-form line.
patch_compose() {
  local in; in="$(cat)"
  local n; n=$(printf '%s\n' "$in" | grep -cE '^[[:space:]]*-[[:space:]]*KOLIBRI_LISTEN_PORT=' || true)
  [ "$n" = 1 ] || return 13
  printf '%s\n' "$in" | awk '
    { print }
    /^[[:space:]]*-[[:space:]]*KOLIBRI_LISTEN_PORT=/ && !done {
      match($0, /^[[:space:]]*/); ind = substr($0, 1, RLENGTH)
      print ind "# Unique Kolibri/Morango instance id per instance (app-kolibri#8, applied by idea#288 first contact)."
      print ind "- MORANGO_SYSTEM_ID=idea-${hostname}-${port}"
      done = 1
    }'
}

# ids_unique: one id per line on stdin; prints duplicates, returns 1 if any (empty ids count as missing -> 1)
ids_unique() {
  local all; all="$(cat)"
  if printf '%s\n' "$all" | grep -qxE '(-|)'; then echo "missing-id"; return 1; fi
  local d; d="$(printf '%s\n' "$all" | sort | uniq -d)"
  [ -z "$d" ] || { echo "$d"; return 1; }
}

is_kolibri_app() { [[ "$1" =~ ^kolibri ]] && [[ ! "$1" =~ ^kolibri-channel-builder ]]; }

[ "${KKM_LIB:-0}" = 1 ] && return 0 2>/dev/null

# ---------- main ----------
HOST="" IP="" DRY=0
while [ $# -gt 0 ]; do case "$1" in
  --host) HOST="$2"; shift 2;; --ip) IP="$2"; shift 2;; --dry-run) DRY=1; shift;;
  -h|--help) sed -n 2,7p "$0"; exit 0;; *) echo "unknown arg $1" >&2; exit 2;; esac; done
[ -n "$HOST" ] || { echo "--host required" >&2; exit 2; }
for d in $DENY_HOSTS; do [ "$HOST" = "$d" ] && { echo "REFUSED: $HOST is never touched" >&2; exit 2; }; done
[ "${IP:-}" = 100.115.60.6 ] && { echo "REFUSED: wh" >&2; exit 2; }

mkdir -p "$LOGDIR"
LOG="$LOGDIR/kolibri-morango-$HOST-$(date +%Y%m%d-%H%M%S)$([ $DRY = 1 ] && echo -dry).log"
exec > >(tee -a "$LOG") 2>&1
LOCK="/tmp/idea-kolibri-morango-$HOST.lock"
exec 8>>"$LOCK"
flock -n 8 || { echo "BUSY: lock $LOCK held ($(cat "$LOCK.pid" 2>/dev/null || echo '?')); not starting" >&2; exit 75; }
echo "$$ $(date '+%F %T')" > "$LOCK.pid"
log() { echo "$(date '+%F %T %Z') $*"; }
log "kit-kolibri-morango host=$HOST dry_run=$DRY log=$LOG"

if [ -z "$IP" ]; then
  IP="$(tailscale --socket "$TS_SOCK" status --json 2>/dev/null | python3 -c '
import json,sys; h=sys.argv[1]; d=json.load(sys.stdin)
for p in (d.get("Peer") or {}).values():
    if p.get("HostName")==h or p.get("DNSName","").split(".")[0]==h:
        print((p.get("TailscaleIPs") or [""])[0]); break' "$HOST")"
fi
[ -n "$IP" ] || { log "ERROR: no Tailscale IP for $HOST (box Tailscale down or host unknown)"; exit 3; }
[ "$IP" = 100.115.60.6 ] && { log "REFUSED: wh"; exit 2; }
rsh() {
  if [ -n "${SSH_CMD:-}" ]; then $SSH_CMD "$IP" "$@"
  else ssh -o BatchMode=yes -o ConnectTimeout=15 -o ProxyCommand="nc -X 5 -x $PROXY %h %p" "pi@$IP" "$@"; fi
}
RHOST="$(rsh hostname)" || { log "ERROR: ssh to $HOST ($IP) failed"; exit 3; }
[ "$RHOST" = "$HOST" ] || { log "ERROR: $IP answers as '$RHOST', expected '$HOST'"; exit 3; }
log "reached $HOST at $IP"

# Helper upload (an untracked file in the Engine checkout; not an Engine update). Read-only by itself.
rsh "cat > $ENGINE_DIR/$HELPER_REMOTE" < "$HERE/kit-kolibri-morango-engine.ts" || { log "ERROR: helper upload failed"; exit 3; }
eng() { rsh "cd $ENGINE_DIR && timeout 400 ./node_modules/.bin/tsx $HELPER_REMOTE $*"; }
HTTP_PORT="$(rsh "grep -E '^[[:space:]]*httpPort:' $ENGINE_DIR/config.yaml | head -1 | sed -E 's/[^0-9]*([0-9]+).*/\1/'")"; HTTP_PORT="${HTTP_PORT:-80}"

LIST="$(eng list)" || { log "ERROR: Engine helper list failed: $LIST"; exit 3; }
declare -a IDS=() DISKS=() NAMES=() DIRS=() PORTS=()
while IFS= read -r j; do
  [ -n "$j" ] || continue
  read -r id name of status disk device < <(python3 -c 'import json,sys;d=json.loads(sys.argv[1]);print(d["id"],d["name"].replace(" ","_"),d["instanceOf"],d["status"],d["diskId"],d["device"] or "-")' "$j")
  is_kolibri_app "$of" || continue
  dir="$(rsh "if [ -d /disks/$device/instances/$id ] && [ -f /disks/$device/instances/$id/compose.yaml ]; then echo /disks/$device/instances/$id; elif [ -f /instances/$id/compose.yaml ]; then echo /instances/$id; fi" </dev/null)"
  [ -n "$dir" ] || { log "WARN: $id ($name) has no compose.yaml on disk; skipped"; continue; }
  port="$(rsh "grep -E '^port=' $dir/.env | tail -1 | cut -d= -f2" </dev/null)"
  IDS+=("$id"); DISKS+=("$disk"); NAMES+=("$name"); DIRS+=("$dir"); PORTS+=("$port")
  log "found Kolibri instance id=$id name=$name app=$of status=$status disk=$disk dir=$dir port=$port"
done <<< "$LIST"
log "Kolibri instances on $HOST: ${#IDS[@]}"
ORPHANS="$(rsh "docker ps --format '{{.Names}}' | grep -i kolibri" || true)"
for c in $ORPHANS; do known=0; for id in "${IDS[@]}"; do [[ "$c" == "$id"-* ]] && known=1; done
  [ $known = 1 ] || log "NOTE: container $c is not an Engine-managed Kolibri on a docked disk; not touched"; done

info_id() { rsh "curl -s -m 10 http://127.0.0.1:$1/api/public/info/" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("instance_id") or "-")
except Exception: print("-")'; }
cur_env() { rsh "c=\$(docker ps -q --filter label=com.docker.compose.project=$1 | head -1); [ -n \"\$c\" ] && docker inspect \$c --format '{{range .Config.Env}}{{println .}}{{end}}' | sed -n 's/^MORANGO_SYSTEM_ID=//p'"; }
health() { # $1 = label; exits on failure
  local t; t="$(rsh "vcgencmd measure_temp 2>/dev/null || awk '{printf \"temp=%.1f\", \$1/1000}' /sys/class/thermal/thermal_zone0/temp" | sed -E "s/[^0-9.]//g")"
  log "health[$1]: temp=${t}C"
  awk -v t="$t" -v m="$TEMP_MAX" 'BEGIN{exit !(t=="" || t>m)}' && { log "ABORT: temperature ${t}C > ${TEMP_MAX}C (or unreadable)"; exit 10; }
  local c; c="$(rsh "curl -s -o /dev/null -m 10 -w '%{http_code}' http://127.0.0.1:$HTTP_PORT/")"
  [[ "$c" =~ ^[23] ]] || { log "ABORT: Console :$HTTP_PORT answered '$c'"; exit 11; }
  local bad; bad="$(rsh "docker ps -a --filter label=com.docker.compose.project --format '{{.Names}} {{.Status}}' | grep -E '\(unhealthy\)|Restarting' || true")"
  [ -z "$bad" ] || { log "ABORT: app container(s) not healthy: $bad"; exit 11; }
  local i; for i in "${!IDS[@]}"; do [ "$(info_id "${PORTS[$i]}")" != - ] || { log "ABORT: ${NAMES[$i]} (:${PORTS[$i]}) not answering /api/public/info/"; exit 11; }; done
}
show_ids() { local i out=""; for i in "${!IDS[@]}"; do v="$(info_id "${PORTS[$i]}")"; log "$1 instance_id ${NAMES[$i]} :${PORTS[$i]} = $v"; out+="$v"$'\n'; done; printf '%s' "$out"; }

[ ${#IDS[@]} -gt 0 ] || { log "nothing to do (no Engine-managed Kolibri instances)"; exit 0; }
health before
BEFORE="$(show_ids BEFORE)"
dups="$(printf '%s' "$BEFORE" | ids_unique)" && log "BEFORE: ids unique" || log "BEFORE: ids NOT unique ($dups) — expected before the fix"

RC=0; QDIR="~/quarantine/kolibri-morango-$(date +%Y%m%d-%H%M%S)"
for i in "${!IDS[@]}"; do
  id="${IDS[$i]}" dir="${DIRS[$i]}" port="${PORTS[$i]}" name="${NAMES[$i]}" disk="${DISKS[$i]}"
  [[ "$port" =~ ^[0-9]+$ ]] || { log "ERROR: $name ($id) has no port in .env; not touched"; RC=13; continue; }
  exp="$(expected_id "$RHOST" "$port")"
  cs="$(rsh "cat $dir/compose.yaml" | compose_state)"
  cur="$(cur_env "$id")"
  act="$(decide "$cs" "$cur" "$exp")"
  log "PLAN $name ($id): expected=$exp compose=$cs container=${cur:-<unset>} -> $act"
  case "$act" in
    SKIP) continue ;;
    CONFLICT) log "CONFLICT: $name has a different MORANGO_SYSTEM_ID; not touched"; RC=13; continue ;;
  esac
  if [[ "$act" == PATCH_* ]]; then
    new="$(rsh "cat $dir/compose.yaml" | patch_compose)" || { log "UNSUPPORTED compose layout for $name; not touched"; RC=13; continue; }
    if [ $DRY = 1 ]; then
      log "DRY-RUN: would back up $dir/compose.yaml to $QDIR/$id-compose.yaml and apply:"
      diff <(rsh "cat $dir/compose.yaml") <(printf '%s\n' "$new") | sed 's/^/    /'
    else
      rsh "test -w $dir/compose.yaml" || { log "compose.yaml of $name not writable by pi; not touched"; RC=13; continue; }
      health "pre-$name"
      rsh "mkdir -p $QDIR && cp -p $dir/compose.yaml $QDIR/$id-compose.yaml" || { log "backup failed; stop"; exit 13; }
      printf '%s\n' "$new" | rsh "cat > $dir/compose.yaml.kkm-new && mv $dir/compose.yaml.kkm-new $dir/compose.yaml" || exit 13
      log "patched $dir/compose.yaml (backup $QDIR/$id-compose.yaml)"
    fi
  fi
  [ "$act" = PATCH_ONLY ] && continue
  if [ $DRY = 1 ]; then log "DRY-RUN: would run Engine commands: stopInstance $id $disk ; startInstance $id $disk ; then wait <=${HEALTH_WAIT}s for /api/public/info/ on :$port"; continue; fi
  health "pre-restart-$name"
  log "Engine: stopInstance $id $disk"; out="$(eng cmd stopInstance "$id" "$disk")" || { log "ABORT: stopInstance failed: $out (compose change kept; backup in $QDIR)"; exit 14; }; log "  $out"
  log "Engine: startInstance $id $disk"; out="$(eng cmd startInstance "$id" "$disk")" || { log "ABORT: startInstance failed: $out"; exit 14; }; log "  $out"
  ok=0; for _ in $(seq 1 $((HEALTH_WAIT/10))); do sleep 10
    [ "$(info_id "$port")" != - ] && [ "$(cur_env "$id")" = "$exp" ] && { ok=1; break; }; done
  [ $ok = 1 ] || { log "ABORT: $name not healthy with $exp after ${HEALTH_WAIT}s"; exit 14; }
  log "restarted $name: MORANGO_SYSTEM_ID=$exp, instance_id=$(info_id "$port")"
  health "post-restart-$name"
done

AFTER="$(show_ids AFTER)"
if [ $DRY = 1 ]; then log "DRY-RUN complete: nothing changed (rc=$RC)"; exit $RC; fi
dups="$(printf '%s' "$AFTER" | ids_unique)" || { log "FAIL: ids not unique after: $dups"; exit 12; }
log "AFTER: ids unique across $HOST"; exit $RC
