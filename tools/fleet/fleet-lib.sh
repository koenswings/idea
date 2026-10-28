#!/usr/bin/env bash
# fleet-lib.sh — shared helpers for deploy.sh, teardown.sh, update-golden.sh and set-golden-pi.sh (idea#107).
# Sourced, never run. Box-side: everything reaches the Pi over ssh (Tailscale IP via the box SOCKS proxy).
#
# Env overrides (tests and routines):
#   STATE_FILE    fleet-state.json (default: <repo root>/fleet-state.json)
#   BOT_NAME      recorded in fleet-state claims and audit lines (default "Ops Bot")
#   SSH_CMD       full ssh command prefix, called as: $SSH_CMD pi@<host> <remote cmd>
#                 (default: ssh BatchMode + ProxyCommand through $PROXY)
#   PROXY         SOCKS proxy for ssh (default 127.0.0.1:1055)
#   HEALTH_DIR    PAUSED/HOLD files of check-fleet-health.sh (default ~/.cache/idea-fleet-health)
#   FLEET_DENY    space-separated Pis these scripts never touch (default "idea02")
#   DENY_HOSTS    addresses never touched (default "100.115.60.6", the wh/'idea' production host)
#   ENGINE_DIR / CONSOLE_DIR / APP_DIR   checkout paths on the Pi (locked nested layout)
#   POST_WAIT     seconds to wait after a pm2 restart before the post-check (default 20)
set -o pipefail

FLEET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${STATE_FILE:-$(git -C "$FLEET_DIR" rev-parse --show-toplevel)/fleet-state.json}"
export STATE_FILE
BOT_NAME="${BOT_NAME:-Ops Bot}"; export BOT_NAME
PROXY="${PROXY:-127.0.0.1:1055}"
HEALTH_DIR="${HEALTH_DIR:-$HOME/.cache/idea-fleet-health}"
FLEET_DENY="${FLEET_DENY:-idea02}"
DENY_HOSTS="${DENY_HOSTS:-100.115.60.6}"
ENGINE_DIR="${ENGINE_DIR:-/home/pi/idea/agents/agent-engine-dev}"
CONSOLE_DIR="${CONSOLE_DIR:-/home/pi/idea/agents/agent-console-dev}"
APP_DIR="${APP_DIR:-/home/pi/idea/agents/agent-app-dev}"
POST_WAIT="${POST_WAIT:-20}"
UFS="$FLEET_DIR/update-fleet-state.sh"

# Result accumulator: steps[] of {step,ok,detail}; emitted once as JSON by fl_finish.
FL_STEPS="[]"
FL_SCRIPT="$(basename "$0")"
fl_step() { FL_STEPS="$(jq -c --arg s "$1" --argjson ok "$2" --arg d "${3:-}" '. + [{step:$s,ok:$ok,detail:$d}]' <<<"$FL_STEPS")"; }
# fl_finish <exit> <ok> <message> [extra-json]
fl_finish() {
  local rc="$1" ok="$2" msg="$3" extra="${4:-{\}}"
  jq -nc --arg script "$FL_SCRIPT" --argjson ok "$ok" --arg msg "$msg" --argjson steps "$FL_STEPS" \
     --argjson extra "$extra" --arg bot "$BOT_NAME" --arg at "$(date -u +%FT%TZ)" \
     '{script:$script,ok:$ok,message:$msg,bot:$bot,at:$at,steps:$steps} + $extra'
  exit "$rc"
}
fl_die() { fl_step "${2:-guard}" false "$1"; fl_finish "${3:-1}" false "$1"; }
fl_usage() { sed -n "2,${1}p" "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

fl_get() { jq -r --arg p "$1" --arg f "$2" '.[$p][$f] // empty' "$STATE_FILE"; }
fl_known() { jq -e --arg p "$1" 'has($p) and ($p|startswith("_")|not)' "$STATE_FILE" >/dev/null; }
fl_host() { local h; h="$(fl_get "$1" tailscale)"; [ -n "$h" ] || h="$(fl_get "$1" host)"; printf '%s' "$h"; }
fl_set() { "$UFS" "$@" >/dev/null 2>&1; }   # one audited field write (update-fleet-state.sh)

fl_ssh() {  # fl_ssh <host> <remote command>
  local host="$1"; shift
  if [ -n "${SSH_CMD:-}" ]; then
    # shellcheck disable=SC2086
    $SSH_CMD "pi@$host" "$@"
  else
    ssh -o BatchMode=yes -o ConnectTimeout=15 -o ProxyCommand="nc -X 5 -x $PROXY %h %p" "pi@$host" "$@"
  fi
}

# fl_paused: fleet changes are paused while check-fleet-health.sh keeps PAUSED or HOLD.
fl_paused() { [ -e "$HEALTH_DIR/PAUSED" ] || [ -e "$HEALTH_DIR/HOLD" ]; }

# fl_guard_pi <pi> <mode>: refuse anything these scripts must never touch.
#   mode review  : review/spare Pi for deploy/teardown (refuse golden, production, kit, pending)
#   mode golden  : the golden Pi (role must be golden)
fl_guard_pi() {
  local pi="$1" mode="$2" role status claim host d
  fl_known "$pi" || fl_die "unknown Pi '$pi' (not in fleet-state.json)"
  for d in $FLEET_DENY; do [ "$pi" = "$d" ] && fl_die "$pi is on the deny list (FLEET_DENY): not touched"; done
  host="$(fl_host "$pi")"; [ -n "$host" ] || fl_die "$pi has no tailscale/host address"
  for d in $DENY_HOSTS; do [ "$host" = "$d" ] && fl_die "$pi resolves to protected host $host: not touched"; done
  role="$(fl_get "$pi" role)"; role="${role:-review}"; status="$(fl_get "$pi" status)"; claim="$(fl_get "$pi" claim)"
  case "$mode" in
    review) case "$role" in review|spare) ;; *) fl_die "$pi has role '$role': deploy/teardown only run on review or spare Pis" ;; esac ;;
    golden) [ "$role" = golden ] || fl_die "$pi has role '$role', not golden" ;;
  esac
  case "$status" in hold|paused|production|kit) fl_die "$pi status is '$status': not touched" ;; esac
  if [ -n "$claim" ] && [[ "$claim" != "$BOT_NAME"* ]]; then fl_die "$pi is claimed by someone else ($claim)"; fi
  fl_step guard true "$pi role=$role status=${status:-?} host=$host"
}

# fl_temp_ok <host>: refuse to start build work above 75 C (fleet rule; resume below 65 C is the caller's retry).
fl_temp_ok() {
  local t; t="$(fl_ssh "$1" 'vcgencmd measure_temp 2>/dev/null | grep -oE "[0-9]+(\.[0-9]+)?" | head -1' 2>/dev/null)"
  [ -z "$t" ] && { fl_step temperature true "vcgencmd unavailable"; return 0; }
  if awk -v t="$t" 'BEGIN{exit !(t>75)}'; then fl_step temperature false "${t} C > 75 C"; return 1; fi
  fl_step temperature true "${t} C"
}

# fl_remote_sha <repo-url-or-slug> <branch>: resolve a branch tip on GitHub (box side).
fl_remote_sha() {
  local url="$1"; [[ "$url" == */* && "$url" != *://* && "$url" != git@* ]] && url="https://github.com/$url"
  git ls-remote "$url" "refs/heads/$2" 2>/dev/null | awk 'NR==1{print $1}'
}

# fl_post_check <host>: Engine online under pi's pm2, Console 200 on localhost:<port>, and every running
# container with a published port answers HTTP (MilkWise and other live instances; idea#107 Decisions).
fl_post_check() {
  local host="$1" port="${2:-8080}" out
  out="$(fl_ssh "$host" "PORT=$port bash -s" <<'REMOTE' 2>/dev/null
st=$(pm2 jlist 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const p=JSON.parse(s).find(x=>x.name==="engine");console.log(p?p.pm2_env.status+" "+(p.pm2_env.username||""):"missing")}catch(e){console.log("error")}})')
echo "ENGINE=$st"
echo "CONSOLE=$(curl -s -o /dev/null --max-time 10 -w '%{http_code}' http://127.0.0.1:$PORT/ 2>/dev/null)"
if command -v docker >/dev/null 2>&1; then
  docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | while read -r name ports; do
    p=$(printf '%s' "$ports" | grep -oE '0\.0\.0\.0:[0-9]+' | head -1 | cut -d: -f2)
    [ -n "$p" ] || continue
    echo "INSTANCE=$name:$p:$(curl -s -o /dev/null --max-time 10 -w '%{http_code}' http://127.0.0.1:$p/ 2>/dev/null)"
  done
fi
REMOTE
)"
  local ok=true eng con bad=""
  eng="$(sed -n 's/^ENGINE=//p' <<<"$out")"; con="$(sed -n 's/^CONSOLE=//p' <<<"$out")"
  [[ "$eng" == online* ]] || { ok=false; bad+="engine '$eng'; "; }
  [ "$con" = 200 ] || { ok=false; bad+="console HTTP ${con:-000}; "; }
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    code="${l##*:}"; [[ "$code" =~ ^[1-4][0-9][0-9]$ ]] || { ok=false; bad+="instance ${l%:*} HTTP $code; "; }
  done < <(sed -n 's/^INSTANCE=//p' <<<"$out")
  fl_step post_check "$ok" "engine=${eng:-?} console=${con:-?} instances=$(sed -n 's/^INSTANCE=//p' <<<"$out" | tr '\n' ' ')${bad:+ FAIL: $bad}"
  $ok
}

# fl_checkout_remote <host> <dir> <repo-url> <ref> [build]: fetch + detached checkout of <ref> in <dir> on the Pi.
# Local edits are stashed (never discarded); build=console runs build-console-pi.sh (keeps hidden-instances.json).
fl_checkout_remote() {
  local host="$1" dir="$2" url="$3" ref="$4" build="${5:-}"
  [[ "$url" == */* && "$url" != *://* && "$url" != git@* ]] && url="https://github.com/$url"
  local script
  script="set -e
if [ ! -d '$dir/.git' ]; then mkdir -p \"\$(dirname '$dir')\"; git clone -q '$url' '$dir'; fi
cd '$dir'
git fetch -q '$url' '$ref'
want=\$(git rev-parse FETCH_HEAD)
if [ \"\$(git rev-parse HEAD)\" = \"\$want\" ] && [ -z \"\$(git status --porcelain --untracked-files=no)\" ]; then echo \"ALREADY \$want\"; exit 0; fi
[ -z \"\$(git status --porcelain --untracked-files=no)\" ] || git stash push -q -m \"fleet-deploy \$(date +%Y%m%d-%H%M%S)\"
git checkout -q --detach \"\$want\"
echo \"CHECKED_OUT \$want\""
  local out rc
  out="$(fl_ssh "$host" "$script" 2>&1)"; rc=$?
  if [ $rc -ne 0 ]; then fl_step "checkout $dir" false "$(tail -3 <<<"$out" | tr '\n' ' ')"; return 1; fi
  fl_step "checkout $dir" true "$(tail -1 <<<"$out")"
  if [ "$build" = console ] && ! grep -q '^ALREADY' <<<"$out"; then
    out="$(fl_ssh "$host" "cd '$dir' && pnpm install --frozen-lockfile --prefer-offline >/dev/null 2>&1 && bash -s -- --dir '$dir'" < "$FLEET_DIR/build-console-pi.sh" 2>&1)"; rc=$?
    fl_step "console build" "$([ $rc = 0 ] && echo true || echo false)" "$(tail -1 <<<"$out")"
    [ $rc = 0 ] || return 1
  fi
}

# fl_engine_deploy <host> <ref-branch> <sha> : reuse deploy-engine-remote.sh (keeps config + store identity).
fl_engine_deploy() {
  local host="$1" branch="$2" sha="$3" out rc
  out="$(SSH_CMD="${SSH_CMD:-}" PROXY="$PROXY" "$FLEET_DIR/deploy-engine-remote.sh" "$host" "$sha" --fetch "$branch" --yes 2>&1)"; rc=$?
  fl_step "engine deploy $sha" "$([ $rc = 0 ] && echo true || echo false)" "$(tail -2 <<<"$out" | tr '\n' ' ')"
  [ $rc = 0 ]
}
