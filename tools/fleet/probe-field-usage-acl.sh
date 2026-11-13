#!/usr/bin/env bash
# probe-field-usage-acl.sh — read-only TCP probes for the field-usage ACL (idea#416).
#
# Modes:
#   idea-to-idea  From a pool Pi, try other pool Pis on listed ports.
#                 Expected: every connect fails (timeout/refused). That is PASS.
#   hub-to-idea   From the sidecar (tag:idea-hub), try dests on port 22
#                 (expected: open) and on the other listed ports (expected: fail).
#
# Usage:
#   probe-field-usage-acl.sh idea-to-idea [--from-pi idea03] [--dests idea01,idea04]
#   probe-field-usage-acl.sh hub-to-idea --i-am-hub [--dests idea01,idea03,idea04]
#   probe-field-usage-acl.sh --help
#
# Options:
#   --from-pi NAME    SSH to NAME and run the connects there (box-side).
#   --source-name N   Identity of the probing node (default: --from-pi or 'local').
#   --dests LIST      Comma-separated fleet-state names. Default: idea01,idea03,idea04
#                     minus the source. Kits, idea02 and idea/wizardly-hugle are
#                     omitted unless listed explicitly.
#   --ports LIST      Comma-separated TCP ports (default: 22,80,443,3333,3334,8080,8081).
#   --timeout SEC     Per-connect timeout (default: 3).
#   --i-am-hub        Declare that this process runs on (or as) the sidecar.
#   --state-file PATH Override fleet-state.json.
#
# Read-only: opens TCP connections with a short timeout and never authenticates,
# writes files, or changes sshd. Prints one JSON object to stdout.
#
# Environment:
#   STATE_FILE, BOT_NAME, SSH_CMD, PROXY   (see fleet-lib.sh)
#   PROBE_CONNECT_CMD   test hook: command that receives <host> <port> <timeout>
#                       and exits 0 if open, 1 if unreachable. Prints a one-word
#                       reason (opened|timeout|refused|error).
#
# Exit: 0 all outcomes match the mode, 1 otherwise, 2 usage.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=fleet-lib.sh
source "$SCRIPT_DIR/fleet-lib.sh"

usage() { sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'; }

MODE=""
FROM_PI=""
SOURCE_NAME=""
DESTS_RAW=""
PORTS_RAW="22,80,443,3333,3334,8080,8081"
TIMEOUT="3"
I_AM_HUB=0

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    idea-to-idea|hub-to-idea) MODE="$1"; shift ;;
    --from-pi) FROM_PI="${2:-}"; shift 2 ;;
    --source-name) SOURCE_NAME="${2:-}"; shift 2 ;;
    --dests) DESTS_RAW="${2:-}"; shift 2 ;;
    --ports) PORTS_RAW="${2:-}"; shift 2 ;;
    --timeout) TIMEOUT="${2:-}"; shift 2 ;;
    --i-am-hub) I_AM_HUB=1; shift ;;
    --state-file) STATE_FILE="${2:-}"; export STATE_FILE; shift 2 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$MODE" ] || { echo "ERROR: mode required (idea-to-idea or hub-to-idea)" >&2; usage >&2; exit 2; }
[[ "$TIMEOUT" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "ERROR: --timeout must be a number" >&2; exit 2; }

if [ -n "$FROM_PI" ]; then
  fl_known "$FROM_PI" || { echo "ERROR: unknown Pi '$FROM_PI'" >&2; exit 2; }
  SOURCE_NAME="${SOURCE_NAME:-$FROM_PI}"
fi
SOURCE_NAME="${SOURCE_NAME:-local}"

DEFAULT_POOL="idea01 idea03 idea04"
if [ -n "$DESTS_RAW" ]; then
  DESTS_CSV="$DESTS_RAW"
else
  DESTS_CSV=""
  for n in $DEFAULT_POOL; do
    [ "$n" = "$SOURCE_NAME" ] && continue
    DESTS_CSV="${DESTS_CSV:+$DESTS_CSV,}$n"
  done
fi

IFS=',' read -r -a DEST_NAMES <<< "$DESTS_CSV"
IFS=',' read -r -a PORTS <<< "$PORTS_RAW"

PROTECTED="idea wizardly-hugle sunny-robin happy-zebra kind-panda"
for n in "${DEST_NAMES[@]}"; do
  n="$(echo "$n" | tr -d '[:space:]')"
  [ -n "$n" ] || continue
  if [ -z "$DESTS_RAW" ]; then
    case " $PROTECTED " in *" $n "*) echo "ERROR: refusing default dest $n" >&2; exit 2 ;; esac
  fi
done

# Resolve dest name -> ip from fleet-state when possible.
resolve_ip() {
  local name="$1" ip
  if [ -f "${STATE_FILE:-}" ] && fl_known "$name" 2>/dev/null; then
    ip="$(fl_host "$name")"
    [ -n "$ip" ] && { printf '%s' "$ip"; return 0; }
  fi
  case "$name" in
    idea01) printf '100.99.231.94' ;;
    idea02) printf '100.85.108.118' ;;
    idea03) printf '100.126.117.80' ;;
    idea04) printf '100.108.39.45' ;;
    idea|wizardly-hugle) printf '100.115.60.6' ;;
    *) return 1 ;;
  esac
}

SPEC='[]'
for n in "${DEST_NAMES[@]}"; do
  n="$(echo "$n" | tr -d '[:space:]')"
  [ -n "$n" ] || continue
  ip="$(resolve_ip "$n")" || { echo "ERROR: cannot resolve $n" >&2; exit 2; }
  for port in "${PORTS[@]}"; do
    port="$(echo "$port" | tr -d '[:space:]')"
    [ -n "$port" ] || continue
    [[ "$port" =~ ^[0-9]+$ ]] || { echo "ERROR: bad port: $port" >&2; exit 2; }
    SPEC="$(jq -c --arg n "$n" --arg ip "$ip" --argjson p "$port" '. + [{name:$n,ip:$ip,port:$p}]' <<<"$SPEC")"
  done
done

expected_for() {
  local port="$1"
  if [ "$MODE" = "idea-to-idea" ]; then
    printf 'unreachable'
  else
    if [ "$port" = 22 ]; then printf 'open'; else printf 'unreachable'; fi
  fi
}

connect_one() {
  local host="$1" port="$2" timeout="$3"
  if [ -n "${PROBE_CONNECT_CMD:-}" ]; then
    $PROBE_CONNECT_CMD "$host" "$port" "$timeout"
    return $?
  fi
  python3 - "$host" "$port" "$timeout" <<'PY'
import socket, sys
host, port, timeout = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
s = socket.socket()
s.settimeout(timeout)
try:
    s.connect((host, port))
    print("opened")
    s.close()
    sys.exit(0)
except socket.timeout:
    print("timeout")
    sys.exit(1)
except ConnectionRefusedError:
    print("refused")
    sys.exit(1)
except OSError as e:
    name = e.__class__.__name__
    if getattr(e, "errno", None) in (113, 101, 111):
        print("unreachable")
    else:
        print(name)
    sys.exit(1)
except Exception as e:
    print(type(e).__name__)
    sys.exit(1)
PY
}

run_local_probes() {
  local out='[]' item name ip port expected reason rc ok
  for item in $(jq -c '.[]' <<<"$SPEC"); do
    name="$(jq -r .name <<<"$item")"
    ip="$(jq -r .ip <<<"$item")"
    port="$(jq -r .port <<<"$item")"
    expected="$(expected_for "$port")"
    reason="$(connect_one "$ip" "$port" "$TIMEOUT" 2>/dev/null || true)"
    # connect_one prints the reason; capture exit via PIPESTATUS if needed.
    if connect_one "$ip" "$port" "$TIMEOUT" >/tmp/idea416-probe-reason.$$ 2>/dev/null; then
      rc=0
    else
      rc=$?
    fi
    reason="$(cat /tmp/idea416-probe-reason.$$ 2>/dev/null || printf '%s' "$reason")"
    rm -f /tmp/idea416-probe-reason.$$
    if [ "$expected" = open ]; then
      if [ "$rc" = 0 ]; then ok=true; else ok=false; fi
    else
      if [ "$rc" = 0 ]; then ok=false; else ok=true; fi
    fi
    out="$(jq -c --arg n "$name" --arg ip "$ip" --argjson p "$port" \
      --arg result "$reason" --arg expected "$expected" --argjson ok "$ok" \
      '. + [{dest:$n,ip:$ip,port:$p,result:$result,expected:$expected,ok:$ok}]' <<<"$out")"
  done
  printf '%s' "$out"
}

run_remote_probes() {
  local host spec_b64 py
  host="$(fl_host "$FROM_PI")"
  [ -n "$host" ] || { echo "ERROR: $FROM_PI has no tailscale/host address" >&2; exit 2; }
  # Refuse to use a Pi claimed by someone else (read-only, but capacity tests
  # on a claimed Pi must not be disturbed).
  local claim
  claim="$(fl_get "$FROM_PI" claim)"
  if [ -n "$claim" ] && [ "$claim" != "null" ] && [[ "$claim" != "$BOT_NAME"* ]]; then
    echo "ERROR: $FROM_PI is claimed by someone else ($claim)" >&2
    exit 1
  fi
  spec_b64="$(printf '%s' "$SPEC" | base64 -w0 2>/dev/null || printf '%s' "$SPEC" | base64)"
  py=$(cat <<'PY'
import base64, json, os, socket, sys
spec = json.loads(base64.b64decode(os.environ["PROBE_SPEC_B64"]))
timeout = float(os.environ["PROBE_TIMEOUT"])
mode = os.environ["PROBE_MODE"]
out = []
for item in spec:
    host, port = item["ip"], int(item["port"])
    expected = "unreachable" if mode == "idea-to-idea" else ("open" if port == 22 else "unreachable")
    result, opened = "error", False
    s = socket.socket()
    s.settimeout(timeout)
    try:
        s.connect((host, port))
        opened = True
        result = "opened"
        s.close()
    except socket.timeout:
        result = "timeout"
    except ConnectionRefusedError:
        result = "refused"
    except OSError as e:
        result = "unreachable" if getattr(e, "errno", None) in (113, 101, 111) else type(e).__name__
    except Exception as e:
        result = type(e).__name__
    ok = (opened if expected == "open" else not opened)
    out.append({"dest": item["name"], "ip": host, "port": port, "result": result, "expected": expected, "ok": ok})
print(json.dumps(out))
PY
)
  PROBE_SPEC_B64="$spec_b64" PROBE_TIMEOUT="$TIMEOUT" PROBE_MODE="$MODE" \
    fl_ssh "$host" "PROBE_SPEC_B64='$spec_b64' PROBE_TIMEOUT='$TIMEOUT' PROBE_MODE='$MODE' python3 -" <<<"$py"
}

if [ "$MODE" = "hub-to-idea" ] && [ -z "$FROM_PI" ] && [ "$I_AM_HUB" != 1 ] && [ -z "${PROBE_CONNECT_CMD:-}" ]; then
  echo "ERROR: hub-to-idea needs --from-pi <sidecar-or-host> or --i-am-hub (this node is the sidecar)" >&2
  exit 2
fi

NOTES='[]'
NOTES="$(jq -c --arg n "Pool Pis were untagged as of the 2026-10-29 idea#117 audit (idea#375 T-c still open). A probe from idea03/idea04 records actual reachability; it is not by itself proof of the tag:idea ACL until those nodes carry tag:idea." '. + [$n]' <<<"$NOTES")"
if [ "$MODE" = "hub-to-idea" ]; then
  NOTES="$(jq -c --arg n "hub-to-idea requires the sidecar (tag:idea-hub) after idea#375 U-3 and U-4. Do not treat a probe from an untagged box or a pool Pi as a hub proof." '. + [$n]' <<<"$NOTES")"
fi

PROBES='[]'
VIA="local"
if [ -n "$FROM_PI" ] && [ -z "${PROBE_CONNECT_CMD:-}" ]; then
  VIA="ssh:$FROM_PI"
  PROBES="$(run_remote_probes)"
else
  # Local / test-hook path. Avoid double-connect: run once per dest.
  PROBES='[]'
  for item in $(jq -c '.[]' <<<"$SPEC"); do
    name="$(jq -r .name <<<"$item")"
    ip="$(jq -r .ip <<<"$item")"
    port="$(jq -r .port <<<"$item")"
    expected="$(expected_for "$port")"
    reason_file="$(mktemp)"
    rc=0
    connect_one "$ip" "$port" "$TIMEOUT" >"$reason_file" 2>/dev/null || rc=$?
    reason="$(tr -d '\n' <"$reason_file")"
    rm -f "$reason_file"
    [ -n "$reason" ] || reason="error"
    if [ "$expected" = open ]; then
      if [ "$rc" = 0 ]; then ok=true; else ok=false; fi
    else
      if [ "$rc" = 0 ]; then ok=false; else ok=true; fi
    fi
    PROBES="$(jq -c --arg n "$name" --arg ip "$ip" --argjson p "$port" \
      --arg result "$reason" --arg expected "$expected" --argjson ok "$ok" \
      '. + [{dest:$n,ip:$ip,port:$p,result:$result,expected:$expected,ok:$ok}]' <<<"$PROBES")"
  done
fi

# Validate probes JSON
jq -e 'type=="array"' <<<"$PROBES" >/dev/null || { echo "ERROR: probe result was not JSON: $PROBES" >&2; exit 1; }

PASS="$(jq '[.[] | select(.ok==true)] | length' <<<"$PROBES")"
FAIL="$(jq '[.[] | select(.ok==false)] | length' <<<"$PROBES")"
TOTAL="$(jq 'length' <<<"$PROBES")"
if [ "$FAIL" = 0 ] && [ "$TOTAL" -gt 0 ]; then OK=true; RC=0; else OK=false; RC=1; fi

MSG="$MODE: $PASS passed, $FAIL failed, $TOTAL probes"
SOURCE_IP=""
if [ -n "$FROM_PI" ]; then SOURCE_IP="$(resolve_ip "$FROM_PI" || true)"; fi

jq -nc \
  --arg script "probe-field-usage-acl.sh" \
  --argjson ok "$OK" \
  --arg message "$MSG" \
  --arg mode "$MODE" \
  --arg source "$SOURCE_NAME" \
  --arg source_ip "$SOURCE_IP" \
  --arg via "$VIA" \
  --arg timeout "$TIMEOUT" \
  --argjson probes "$PROBES" \
  --argjson notes "$NOTES" \
  --arg bot "${BOT_NAME:-Atlas}" \
  --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson pass "$PASS" --argjson fail "$FAIL" --argjson total "$TOTAL" \
  '{
     script:$script, ok:$ok, message:$message, mode:$mode,
     source:{name:$source, ip:$source_ip, via:$via},
     timeout_s: ($timeout|tonumber),
     probes:$probes,
     summary:{pass:$pass, fail:$fail, total:$total},
     notes:$notes, bot:$bot, at:$at
   }'
exit "$RC"
