#!/usr/bin/env bash
# check-fleet-health.sh — health-check every Pi in fleet-state.json (idea#149). JSON on stdout.
#
# Per Pi (host = .tailscale, else .host):
#   reachable  ssh over Tailscale answers (BatchMode, short timeout)
#   console    Console answers HTTP 200 on http://<host>:<console_port>/
#              (console_port from fleet-state; 8080 when the Pi has none)
#   engine     pm2 process "engine" is online, runs as pi, and its restart count has
#              not gone up since the previous run (baseline kept in $HEALTH_DIR)
#   versions   deployed Engine/Console HEADs match .version in fleet-state
#              ("engine main@<sha>, console main@<sha>"); skipped when .version is unset
#   disk       root filesystem use below $DISK_MAX_PCT (default 90)
# A Pi with a claim (or status other than idle) is still checked and reported, but it
# is marked "claimed" and never counts as a failure; its versions are not compared.
#
# Usage: tools/fleet/check-fleet-health.sh [--origin] [--pi NAME]... [--alert]
#   --origin   git fetch, then read fleet-state.json from origin/main instead of the
#              working tree, so claims made since the last pull are seen (routine use)
#   --pi NAME  only check this Pi (repeatable)
#   --alert    also decide whether to alert, using $HEALTH_DIR/alert.json
#              (alert when a problem is new, changes, lasts beyond ALERT_REPEAT_SECS
#              (default 7200) since the last alert, or clears). Adds an "alert" object,
#              and creates/removes $HEALTH_DIR/PAUSED while the fleet is unhealthy.
#              Manual walk hold: while $HEALTH_DIR/HOLD exists, PAUSED is kept (created if
#              missing) and never removed, even on a healthy run; the report then shows
#              alert.hold=true, alert.fleet_changes_paused=true and alert.hold_file.
#              Remove HOLD to hand PAUSED back to the health check.
# Exit: 0 all unclaimed Pis healthy, 1 at least one unhealthy, 2 usage/state error.
#
# Env overrides (used by the tests): STATE_REPO (repo for --origin), STATE_FILE, HEALTH_DIR, SSH_BIN, CURL_BIN,
#   DISK_MAX_PCT, ALERT_REPEAT_SECS, NOW (epoch secs), SSH_USER,
#   ENGINE_DIR, CONSOLE_DIR (paths on the Pi, default ~/idea/agents/agent-*-dev).
# Needs jq on the machine running it. Pis need only ssh, node, pm2, git, df.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_REPO="${STATE_REPO:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)}"
STATE_FILE="${STATE_FILE:-$STATE_REPO/fleet-state.json}"
HEALTH_DIR="${HEALTH_DIR:-$HOME/.cache/idea-fleet-health}"
SSH_BIN="${SSH_BIN:-ssh}"
CURL_BIN="${CURL_BIN:-curl}"
SSH_USER="${SSH_USER:-pi}"
DISK_MAX_PCT="${DISK_MAX_PCT:-90}"
ALERT_REPEAT_SECS="${ALERT_REPEAT_SECS:-7200}"
NOW="${NOW:-$(date +%s)}"
ENGINE_DIR="${ENGINE_DIR:-~/idea/agents/agent-engine-dev}"
CONSOLE_DIR="${CONSOLE_DIR:-~/idea/agents/agent-console-dev}"

ONLY=()
ALERT=0
ORIGIN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --pi) [ $# -ge 2 ] || { echo "usage: --pi NAME" >&2; exit 2; }; ONLY+=("$2"); shift 2 ;;
    --alert) ALERT=1; shift ;;
    --origin) ORIGIN=1; shift ;;
    -h|--help) sed -n '2,37p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null || { echo "ERROR: jq not found" >&2; exit 2; }
if [ $ORIGIN -eq 1 ]; then
  ORIGIN_STATE="$(mktemp)"; trap 'rm -f "$ORIGIN_STATE"' EXIT
  git -C "$STATE_REPO" fetch -q origin main 2>/dev/null \
    && git -C "$STATE_REPO" show origin/main:fleet-state.json > "$ORIGIN_STATE" 2>/dev/null \
    || { echo "ERROR: cannot read fleet-state.json from origin/main in $STATE_REPO" >&2; exit 2; }
  STATE_FILE="$ORIGIN_STATE"
fi
[ -f "$STATE_FILE" ] && jq -e 'type=="object"' "$STATE_FILE" >/dev/null 2>&1 \
  || { echo "ERROR: cannot read fleet state $STATE_FILE" >&2; exit 2; }
mkdir -p "$HEALTH_DIR" || { echo "ERROR: cannot create $HEALTH_DIR" >&2; exit 2; }
RESTARTS_FILE="$HEALTH_DIR/restarts.json"
[ -s "$RESTARTS_FILE" ] && jq -e 'type=="object"' "$RESTARTS_FILE" >/dev/null 2>&1 || echo '{}' > "$RESTARTS_FILE"

mapfile -t PIS < <(jq -r 'keys_unsorted[] | select(startswith("_") | not)' "$STATE_FILE")
if [ ${#ONLY[@]} -gt 0 ]; then
  for p in "${ONLY[@]}"; do
    jq -e --arg p "$p" 'has($p)' "$STATE_FILE" >/dev/null || { echo "ERROR: $p not in fleet state" >&2; exit 2; }
  done
  PIS=("${ONLY[@]}")
fi

# Runs on the Pi. Prints KEY=VALUE lines only.
REMOTE='
pm2 jlist 2>/dev/null | node -e "
let s=\"\";process.stdin.on(\"data\",d=>s+=d).on(\"end\",()=>{
  let a=[];try{a=JSON.parse(s.slice(s.indexOf(\"[\")))}catch(e){console.log(\"PM2_ERROR=unparseable\");return}
  const p=a.find(x=>x.name===\"engine\");
  if(!p){console.log(\"ENGINE_STATUS=missing\");return}
  console.log(\"ENGINE_STATUS=\"+p.pm2_env.status);
  console.log(\"ENGINE_USER=\"+(p.pm2_env.username||\"\"));
  console.log(\"ENGINE_RESTARTS=\"+p.pm2_env.restart_time);
})" 2>/dev/null || echo PM2_ERROR=node-failed
echo "ENGINE_SHA=$(git -C '"$ENGINE_DIR"' rev-parse HEAD 2>/dev/null)"
echo "CONSOLE_SHA=$(git -C '"$CONSOLE_DIR"' rev-parse HEAD 2>/dev/null)"
echo "DISK_PCT=$(df -P / 2>/dev/null | awk "NR==2{gsub(/%/,\"\",\$5);print \$5}")"
'

kv() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1; }

results=()
new_restarts="$(cat "$RESTARTS_FILE")"
for PI in "${PIS[@]}"; do
  entry="$(jq -c --arg p "$PI" '.[$p]' "$STATE_FILE")"
  host="$(jq -r '.tailscale // .host // empty' <<<"$entry")"
  claim="$(jq -r '.claim // empty' <<<"$entry")"
  status="$(jq -r '.status // "unknown"' <<<"$entry")"
  version="$(jq -r '.version // empty' <<<"$entry")"
  claimed=false
  if [ -n "$claim" ] || [ "$status" != "idle" ]; then claimed=true; fi
  problems=()

  if [ -z "$host" ]; then
    problems+=("no host/tailscale address in fleet-state")
    results+=("$(jq -nc --arg pi "$PI" --argjson claimed "$claimed" --arg claim "$claim" --arg status "$status" \
      --argjson problems "$(printf '%s\n' "${problems[@]}" | jq -R . | jq -sc .)" \
      '{pi:$pi,host:null,status:$status,claim:(if $claim=="" then null else $claim end),claimed:$claimed,ok:false,checks:{},problems:$problems}')")
    continue
  fi

  # console (from here, over Tailscale), on the Pi's console_port (default 8080)
  console_port="$(jq -r '.console_port // 8080' <<<"$entry")"
  console_ok=false
  if [[ "$console_port" =~ ^[0-9]+$ ]] && [ "$console_port" -ge 1 ] && [ "$console_port" -le 65535 ]; then
    http="$("$CURL_BIN" -s -o /dev/null --max-time 10 -w '%{http_code}' "http://$host:$console_port/" 2>/dev/null)"
    http="${http:-000}"
    [ "$http" = 200 ] && console_ok=true
    $console_ok || problems+=("console HTTP $http on :$console_port")
  else
    http=""
    problems+=("fleet-state console_port '$console_port' is not a port number")
  fi

  # everything else over one ssh
  out="$("$SSH_BIN" -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 \
        "$SSH_USER@$host" "$REMOTE" 2>/dev/null)"; ssh_rc=$?
  reachable=true
  if [ $ssh_rc -eq 255 ] || { [ $ssh_rc -ne 0 ] && [ -z "$out" ]; }; then reachable=false; fi

  e_status=""; e_user=""; e_restarts=""; e_sha=""; c_sha=""; disk=""; prev=""
  engine_ok=false; versions_ok=null; disk_ok=false
  exp_engine="$(sed -n 's/.*engine [^@,]*@\([0-9a-f]\{7,40\}\).*/\1/p' <<<"$version")"
  exp_console="$(sed -n 's/.*console [^@,]*@\([0-9a-f]\{7,40\}\).*/\1/p' <<<"$version")"
  if ! $reachable; then
    problems+=("unreachable over Tailscale ssh ($host)")
    versions_ok=false
  else
    e_status="$(kv "$out" ENGINE_STATUS)"; e_user="$(kv "$out" ENGINE_USER)"
    e_restarts="$(kv "$out" ENGINE_RESTARTS)"; e_sha="$(kv "$out" ENGINE_SHA)"
    c_sha="$(kv "$out" CONSOLE_SHA)"; disk="$(kv "$out" DISK_PCT)"
    pm2err="$(kv "$out" PM2_ERROR)"
    prev="$(jq -r --arg p "$PI" '.[$p] // empty' "$RESTARTS_FILE")"

    if [ -n "$pm2err" ]; then problems+=("pm2 unreadable ($pm2err)")
    elif [ "$e_status" = missing ] || [ -z "$e_status" ]; then problems+=("pm2 has no engine process")
    elif [ "$e_status" != online ]; then problems+=("engine is $e_status in pm2")
    elif [ "$e_user" != "$SSH_USER" ]; then problems+=("engine runs as '${e_user:-unknown}', not $SSH_USER")
    elif [[ "$e_restarts" =~ ^[0-9]+$ ]] && [[ "$prev" =~ ^[0-9]+$ ]] && [ "$e_restarts" -gt "$prev" ]; then
      problems+=("engine restarted $((e_restarts - prev))x since last check ($prev -> $e_restarts)")
    else engine_ok=true; fi
    if [[ "$e_restarts" =~ ^[0-9]+$ ]]; then
      new_restarts="$(jq -c --arg p "$PI" --argjson n "$e_restarts" '.[$p]=$n' <<<"$new_restarts")"
    fi

    if $claimed || [ -z "$version" ]; then versions_ok=null
    elif [ -z "$exp_engine" ] || [ -z "$exp_console" ]; then
      versions_ok=false; problems+=("fleet-state version '$version' not in 'engine main@<sha>, console main@<sha>' form")
    else
      versions_ok=true
      if [[ "$e_sha" != "$exp_engine"* ]]; then versions_ok=false; problems+=("engine at ${e_sha:0:7}, fleet-state says $exp_engine"); fi
      if [[ "$c_sha" != "$exp_console"* ]]; then versions_ok=false; problems+=("console at ${c_sha:0:7}, fleet-state says $exp_console"); fi
    fi

    if [[ "$disk" =~ ^[0-9]+$ ]]; then
      if [ "$disk" -lt "$DISK_MAX_PCT" ]; then disk_ok=true; else problems+=("root disk ${disk}% full (limit ${DISK_MAX_PCT}%)"); fi
    else problems+=("root disk usage unreadable"); fi
  fi

  ok=true; [ ${#problems[@]} -gt 0 ] && ok=false
  results+=("$(jq -nc \
    --arg pi "$PI" --arg host "$host" --arg status "$status" --arg claim "$claim" --argjson claimed "$claimed" \
    --argjson ok "$ok" --argjson reachable "$reachable" --arg http "$http" --argjson console_ok "$console_ok" --arg console_port "$console_port" \
    --argjson engine_ok "$engine_ok" --arg e_status "$e_status" --arg e_user "$e_user" \
    --arg e_restarts "$e_restarts" --arg prev "$prev" \
    --argjson versions_ok "$versions_ok" --arg e_sha "${e_sha:0:7}" --arg c_sha "${c_sha:0:7}" \
    --arg exp_engine "$exp_engine" --arg exp_console "$exp_console" \
    --argjson disk_ok "$disk_ok" --arg disk "$disk" --argjson max "$DISK_MAX_PCT" \
    --argjson problems "$( [ ${#problems[@]} -gt 0 ] && printf '%s\n' "${problems[@]}" | jq -R . | jq -sc . || echo '[]')" \
    'def n: if .=="" then null else (tonumber? // .) end; def s: if .=="" then null else . end;
     {pi:$pi, host:$host, status:$status, claim:($claim|s), claimed:$claimed, ok:$ok,
      checks:{
        reachable:{ok:$reachable},
        console:{ok:$console_ok, http:($http|n), port:($console_port|n)},
        engine:{ok:$engine_ok, status:($e_status|s), user:($e_user|s), restarts:($e_restarts|n), previous_restarts:($prev|n)},
        versions:{ok:$versions_ok, engine:($e_sha|s), console:($c_sha|s), expected_engine:($exp_engine|s), expected_console:($exp_console|s)},
        disk:{ok:$disk_ok, used_pct:($disk|n), max_pct:$max}},
      problems:$problems}')")
done

echo "$new_restarts" > "$RESTARTS_FILE.tmp" && mv "$RESTARTS_FILE.tmp" "$RESTARTS_FILE"

report="$(printf '%s\n' "${results[@]}" | jq -sc --argjson now "$NOW" '
  {checked_at: ($now|todate), pis: .,
   unhealthy: [.[] | select(.ok|not) | select(.claimed|not) | .pi],
   claimed_with_problems: [.[] | select(.ok|not) | select(.claimed) | .pi]}
  | .ok = (.unhealthy|length==0)')"

if [ $ALERT -eq 1 ]; then
  ALERT_FILE="$HEALTH_DIR/alert.json"
  last='{}'; [ -s "$ALERT_FILE" ] && last="$(jq -c . "$ALERT_FILE" 2>/dev/null || echo '{}')"
  # Signature: unhealthy Pis and their problems, with restart counts stripped so a
  # still-climbing counter is "the same problem", not a new one.
  sig="$(jq -c '[.pis[] | select(.ok|not) | select(.claimed|not)
                 | {pi, problems: [.problems[] | sub(" [0-9]+x since last check.*"; " restarting")]}]' <<<"$report")"
  decision="$(jq -nc --argjson last "$last" --argjson sig "$sig" --argjson now "$NOW" --argjson rep "$ALERT_REPEAT_SECS" '
    ($last.signature // []) as $ls | ($last.alerted_at // 0) as $at |
    if ($sig|length)==0 then
      (if ($ls|length)>0 then {send:true, reason:"resolved"} else {send:false, reason:"healthy"} end)
    elif ($ls|length)==0 then {send:true, reason:"new"}
    elif $sig != $ls then {send:true, reason:"changed"}
    elif ($now - $at) >= $rep then {send:true, reason:"persisting"}
    else {send:false, reason:"already alerted"} end
    | .since = (if ($sig|length)==0 then null elif ($ls|length)==0 then $now else ($last.since // $now) end)
    | .signature = $sig')"
  if jq -e '.send' <<<"$decision" >/dev/null; then
    jq -c --argjson now "$NOW" '{signature, since, alerted_at: (if (.signature|length)>0 then $now else null end)}' <<<"$decision" > "$ALERT_FILE"
  fi
  HOLD_FILE="$HEALTH_DIR/HOLD"
  hold=false; [ -e "$HOLD_FILE" ] && hold=true
  if $hold; then
    # Manual walk hold: keep (or create) PAUSED and never remove it here.
    [ -f "$HEALTH_DIR/PAUSED" ] || echo "fleet changes paused (manual hold $HOLD_FILE) since $(date -u -d "@$NOW" +%FT%TZ)" > "$HEALTH_DIR/PAUSED"
  elif jq -e '.signature|length>0' <<<"$decision" >/dev/null; then
    [ -f "$HEALTH_DIR/PAUSED" ] || echo "fleet changes paused by check-fleet-health.sh since $(date -u -d "@$NOW" +%FT%TZ)" > "$HEALTH_DIR/PAUSED"
  else
    rm -f "$HEALTH_DIR/PAUSED"
  fi
  report="$(jq -c --argjson d "$decision" --arg paused "$HEALTH_DIR/PAUSED" --arg holdf "$HOLD_FILE" --argjson hold "$hold" \
    '.alert = {send:$d.send, reason:$d.reason, unhealthy_since:(if $d.since then ($d.since|todate) else null end),
               fleet_changes_paused: ($hold or ($d.signature|length>0)), pause_file:$paused,
               hold:$hold, hold_file:(if $hold then $holdf else null end)}' <<<"$report")"
fi

jq . <<<"$report"
jq -e '.ok' <<<"$report" >/dev/null && exit 0 || exit 1
