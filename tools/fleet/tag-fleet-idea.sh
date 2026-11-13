#!/usr/bin/env bash
# tag-fleet-idea.sh — pre/post checks for idea#375 T-c (tag fleet Pis as tag:idea).
#
# This script never applies a tag. The safe apply path is Koen's admin-console
# "Edit tags" on the Machines page (see tag-fleet-idea-tc.md). `tailscale up
# --advertise-tags` re-authenticates and can drop SSH; it is not implemented
# here on purpose.
#
# Usage:
#   tag-fleet-idea.sh preflight
#   tag-fleet-idea.sh precheck  --pi idea03
#   tag-fleet-idea.sh wait      --pi idea03 [--timeout 600]
#   tag-fleet-idea.sh postcheck --pi idea03
#   tag-fleet-idea.sh run       --pi idea03
#   tag-fleet-idea.sh order
#
# One Pi per invocation. Recommended order: idea03, idea04, idea02, idea01.
# idea/wizardly-hugle and the kits are refused (later: #374 or Koen's OK).
#
# Environment: STATE_FILE, BOT_NAME, SSH_CMD, PROXY (fleet-lib.sh);
#   TS_SOCK (default /home/box/.local/share/tailscale/tailscaled.sock);
#   TAILSCALE_STATUS_JSON  test hook: read status --json from this file;
#   SKIP_SSH=1             test hook: do not SSH (postcheck records skipped);
#   TCP_PROBE_CMD          test hook: command invoked with the IPv4 to probe
#                          TCP 22 (exit 0 = open). Used by the preflight canary;
#                          takes precedence over socks-connect and a plain socket.
#   SOCKS_CONNECT_BIN      path to socks-connect (default ~/.local/bin/socks-connect).
#                          If executable, the canary probes TCP 22 through it
#                          (userspace Tailscale, SOCKS 1055): timeout 6
#                          socks-connect <ip> 22, SSH-2.0- banner means opened.
#                          If it is not executable, fall back to a plain socket.
#   TCP_PROBE_PORT         test hook: port for the socks/plain probe (default 22).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=fleet-lib.sh
source "$SCRIPT_DIR/fleet-lib.sh"

TS_SOCK="${TS_SOCK:-/home/box/.local/share/tailscale/tailscaled.sock}"
ALLOW="idea01 idea02 idea03 idea04"
DENY="idea wizardly-hugle sunny-robin happy-zebra kind-panda"
ORDER="idea03 idea04 idea02 idea01"
WAIT_TIMEOUT=600
PI=""
MODE=""

usage() { sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    preflight|precheck|wait|postcheck|run|order) MODE="$1"; shift ;;
    --pi) PI="${2:-}"; shift 2 ;;
    --timeout) WAIT_TIMEOUT="${2:-}"; shift 2 ;;
    --unsafe-cli-reauth|--advertise-tags|--apply)
      echo "ERROR: this script never applies tags (including via $1)." >&2
      echo "Use the admin-console Edit tags path in tag-fleet-idea-tc.md." >&2
      exit 2 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$MODE" ] || { echo "ERROR: mode required" >&2; usage >&2; exit 2; }

if [ "$MODE" = order ]; then
  jq -nc --arg order "$ORDER" --arg reason "idea03 first (spare, shares the 2026-12-02 14:36 Europe/Brussels expiry, SSH recently proven); idea04 next spare; idea02 hold but named by T-c for the same expiry; idea01 golden last. idea/wh and kits later." \
    '{script:"tag-fleet-idea.sh",ok:true,mode:"order",order:($order|split(" ")),reason:$reason}'
  exit 0
fi

allowed_pi() {
  case " $ALLOW " in *" $1 "*) return 0 ;; esac
  return 1
}
denied_pi() {
  case " $DENY " in *" $1 "*) return 0 ;; esac
  return 1
}

need_pi() {
  [ -n "$PI" ] || { echo "ERROR: --pi required for $MODE" >&2; exit 2; }
  if denied_pi "$PI" || ! allowed_pi "$PI"; then
    echo "ERROR: refusing $PI (allow: $ALLOW; later: $DENY)" >&2
    exit 2
  fi
  fl_known "$PI" || { echo "ERROR: $PI is not in fleet-state.json" >&2; exit 2; }
}

status_json() {
  if [ -n "${TAILSCALE_STATUS_JSON:-}" ]; then
    cat "$TAILSCALE_STATUS_JSON"
  else
    tailscale --socket "$TS_SOCK" status --json
  fi
}

# Print one JSON object describing a named node from status --json, or empty.
node_view() {
  local name="$1"
  python3 - "$name" 3<&0 <<'PY'
import json, sys
name = sys.argv[1]
data = json.load(open('/dev/fd/3'))
nodes = [data.get("Self") or {}]
nodes.extend((data.get("Peer") or {}).values())
want_ip = None
# optional second strategy: match known fleet IPs later in caller
for n in nodes:
    host = n.get("HostName") or ""
    dns = (n.get("DNSName") or "").split(".")[0]
    if host == name or dns == name:
        ips = n.get("TailscaleIPs") or []
        ip4 = next((i for i in ips if ":" not in i), ips[0] if ips else "")
        tags = n.get("Tags") or []
        expiry = n.get("KeyExpiry") or ""
        print(json.dumps({
            "name": name,
            "hostname": host,
            "ip": ip4,
            "online": bool(n.get("Online")),
            "tags": tags,
            "has_idea": "tag:idea" in tags,
            "has_idea_hub": "tag:idea-hub" in tags,
            "key_expiry": expiry,
            "user_id": n.get("UserID"),
        }, separators=(",", ":")))
        sys.exit(0)
sys.exit(1)
PY
}

scan_tags() {
  python3 - 3<&0 <<'PY'
import json, sys

def first_label(dns):
    return (dns or "").split(".")[0]

def is_router(n, host):
    dns = first_label(n.get("DNSName") or "")
    return host.endswith("-router") or dns.endswith("-router")

data = json.load(open("/dev/fd/3"))
nodes = [data.get("Self") or {}]
nodes.extend((data.get("Peer") or {}).values())
idea, hub, online_tagged, online_engines, skipped_routers = [], [], [], [], []
for n in nodes:
    host = n.get("HostName") or first_label(n.get("DNSName") or "") or "?"
    tags = n.get("Tags") or []
    ips = n.get("TailscaleIPs") or []
    ip4 = next((i for i in ips if ":" not in i), "")
    rec = {"name": host, "ip": ip4, "online": bool(n.get("Online")), "tags": tags,
           "key_expiry": n.get("KeyExpiry") or "", "router": is_router(n, host)}
    if "tag:idea" in tags:
        idea.append(rec)
        if rec["online"]:
            online_tagged.append(rec)
            if rec["router"]:
                skipped_routers.append({"name": rec["name"], "ip": rec["ip"]})
            else:
                online_engines.append(rec)
    if "tag:idea-hub" in tags:
        hub.append(rec)
print(json.dumps({"tag_idea": idea, "tag_idea_hub": hub,
                  "online_tagged": online_tagged,
                  "online_engines": online_engines,
                  "skipped_routers": skipped_routers},
                 separators=(",", ":")))
PY
}

# Max online tagged Engines to probe as the SSH canary (short timeout each).
CANARY_PROBE_LIMIT="${CANARY_PROBE_LIMIT:-3}"

tcp_22() {
  local host="$1"
  local port="${TCP_PROBE_PORT:-22}"
  local socks="${SOCKS_CONNECT_BIN:-${HOME}/.local/bin/socks-connect}"
  if [ -n "${TCP_PROBE_CMD:-}" ]; then
    "$TCP_PROBE_CMD" "$host"
    return $?
  fi
  if [ -x "$socks" ]; then
    # Userspace Tailscale: a plain connect to a 100.x IP fails. Probe through
    # socks-connect the same way do_health wraps SSH, and treat an SSH-2.0-
    # banner as opened. timeout 6; stdin is /dev/null (banner only, no login).
    python3 - "$socks" "$host" "$port" <<'PY'
import os, select, signal, subprocess, sys, time

socks, host, port = sys.argv[1], sys.argv[2], sys.argv[3]

def fail(msg):
    print(msg)
    sys.exit(1)

try:
    p = subprocess.Popen(
        ["timeout", "6", socks, host, port],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
except FileNotFoundError:
    # timeout(1) missing: still bound the probe to 6s in-process.
    try:
        p = subprocess.Popen(
            [socks, host, port],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError as e:
        fail(type(e).__name__)
except OSError as e:
    fail(type(e).__name__)

data = b""
deadline = time.monotonic() + 6
try:
    while time.monotonic() < deadline and not data.startswith(b"SSH-2.0-"):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        ready, _, _ = select.select([p.stdout], [], [], remaining)
        if not ready:
            break
        chunk = os.read(p.stdout.fileno(), 64)
        if not chunk:
            break
        data += chunk
finally:
    if p.poll() is None:
        try:
            os.killpg(p.pid, signal.SIGTERM)
        except OSError:
            p.kill()
        try:
            p.wait(timeout=1)
        except Exception:
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except OSError:
                pass
            try:
                p.wait(timeout=1)
            except Exception:
                pass

if data.startswith(b"SSH-2.0-"):
    print("opened")
    sys.exit(0)
fail("no-banner")
PY
    return $?
  fi
  python3 - "$host" "$port" <<'PY'
import socket, sys
host, port = sys.argv[1], int(sys.argv[2])
s = socket.socket()
s.settimeout(3)
try:
    s.connect((host, port))
    s.close()
    print("opened")
    sys.exit(0)
except Exception as e:
    print(type(e).__name__)
    sys.exit(1)
PY
}

NOTES='[]'
add_note() { NOTES="$(jq -c --arg n "$1" '. + [$n]' <<<"$NOTES")"; }

do_preflight() {
  local raw scan n_idea n_hub n_online n_engines
  local canary_ip="" canary_name="" canary_ok=false canary_reason="" tried='[]'
  local skipped_txt canary_obj ok
  raw="$(status_json)"
  scan="$(scan_tags <<<"$raw")"
  n_idea="$(jq '.tag_idea | length' <<<"$scan")"
  n_hub="$(jq '.tag_idea_hub | length' <<<"$scan")"
  n_online="$(jq '.online_tagged | length' <<<"$scan")"
  n_engines="$(jq '.online_engines | length' <<<"$scan")"
  skipped_txt="$(jq -r '
    if (.skipped_routers | length) == 0 then "none"
    else [.skipped_routers[] | "\(.name) (\(.ip))"] | join(", ")
    end' <<<"$scan")"
  if [ "$n_idea" -gt 0 ]; then
    add_note "tag:idea is already on $n_idea node(s) (kits/routers). The tag exists in the tailnet."
  else
    add_note "No peer currently shows Tags: tag:idea. Do not tag a fleet Pi until T-b confirms tagOwners includes tag:idea."
  fi
  if [ "$n_hub" -gt 0 ]; then
    add_note "tag:idea-hub is visible on $n_hub node(s). ACL Step A (U-1) has been used by at least one node."
  else
    add_note "tag:idea-hub is not visible on any node. Step A (U-1/U-2) may still be live as a tagOwners entry with no sidecar yet (U-3). status --json cannot see unused tags; T-b is the console confirmation."
  fi
  if [ "$n_engines" -eq 0 ]; then
    # Routers (or an empty online set) cannot prove admins → tag:idea:22.
    # This is not a lock-out claim: kit routers have no sshd on Tailscale.
    canary_reason="no_online_tagged_engine"
    if [ "$n_online" -gt 0 ]; then
      add_note "No online tagged Engine is available as an SSH canary (canary: null). Skipped *-router node(s): $skipped_txt. Kit routers have no sshd on Tailscale, so a failed probe to them is not a lock-out. T-b plus an online tagged Engine should confirm admins → tag:idea:22 before the first fleet tag."
    else
      add_note "No non-router tagged node is online (canary: null), so admin reachability to tag:idea cannot be proved from here. This is not a lock-out claim. T-b plus a later online tagged Engine canary should confirm admins → tag:idea before the first fleet tag."
    fi
  else
    local i=0 limit="$CANARY_PROBE_LIMIT" cip cname
    if [ "$n_engines" -lt "$limit" ]; then
      limit="$n_engines"
    fi
    while [ "$i" -lt "$limit" ]; do
      cip="$(jq -r --argjson i "$i" '.online_engines[$i].ip' <<<"$scan")"
      cname="$(jq -r --argjson i "$i" '.online_engines[$i].name' <<<"$scan")"
      if [ -n "$cip" ] && tcp_22 "$cip" >/dev/null; then
        canary_ok=true
        canary_ip="$cip"
        canary_name="$cname"
        tried="$(jq -c --arg ip "$cip" --arg name "$cname" '. + [{name:$name,ip:$ip,tcp22:true}]' <<<"$tried")"
        add_note "SSH canary is tagged Engine $cname ($cip); skipped *-router node(s): $skipped_txt. Admin device can open TCP 22. admins → tag:idea:22 appears to work, so tagging a fleet Pi should not lock out SSH from this box."
        break
      fi
      tried="$(jq -c --arg ip "$cip" --arg name "$cname" '. + [{name:$name,ip:$ip,tcp22:false}]' <<<"$tried")"
      canary_ip="$cip"
      canary_name="$cname"
      i=$((i + 1))
    done
    if [ "$canary_ok" != true ]; then
      canary_reason="tcp22_failed"
      add_note "Tried $limit online tagged Engine(s) as SSH canary (last: $canary_name $canary_ip) but TCP 22 from this box failed. Skipped *-router node(s): $skipped_txt. Do not tag a fleet Pi: tagging could lock out SSH."
    fi
  fi
  ok=true
  [ "$n_idea" -gt 0 ] || ok=false
  # Do not fail only because the hub tag is unseen (expected until U-3).
  # Fail when no Engine canary is online, or when probed Engines did not answer TCP 22.
  if [ "$canary_ok" != true ]; then ok=false; fi
  if [ -z "$canary_ip" ] && [ "$canary_reason" = "no_online_tagged_engine" ]; then
    canary_obj="null"
  else
    canary_obj="$(jq -nc --arg ip "$canary_ip" --arg name "$canary_name" \
      --argjson tcp "$canary_ok" --arg reason "$canary_reason" --argjson tried "$tried" \
      --argjson skipped "$(jq -c '.skipped_routers' <<<"$scan")" \
      '{ip:(if $ip=="" then null else $ip end),
        name:(if $name=="" then null else $name end),
        tcp22:$tcp,
        reason:(if $reason=="" then null else $reason end),
        skipped_routers:$skipped,
        tried:$tried}')"
  fi
  jq -nc --argjson ok "$ok" --argjson scan "$scan" --argjson notes "$NOTES" \
    --argjson canary "$canary_obj" --arg reason "$canary_reason" \
    --argjson skipped_routers "$(jq -c '.skipped_routers' <<<"$scan")" \
    '{script:"tag-fleet-idea.sh",mode:"preflight",ok:$ok,
      tag_idea_count:($scan.tag_idea|length),
      tag_idea_hub_count:($scan.tag_idea_hub|length),
      observed:$scan, canary:$canary,
      canary_reason:(if $reason=="" then null else $reason end),
      skipped_routers:$skipped_routers, notes:$notes}'
}

claim_ok() {
  local claim
  claim="$(fl_get "$PI" claim)"
  if [ -n "$claim" ] && [ "$claim" != "null" ] && [[ "$claim" != "$BOT_NAME"* ]]; then
    echo "ERROR: $PI is claimed by someone else ($claim)" >&2
    return 1
  fi
  return 0
}

expected_ip() { fl_host "$PI"; }

do_precheck() {
  need_pi
  claim_ok || exit 1
  local pf view expected
  pf="$(do_preflight)"
  # reset NOTES after preflight consumed them via do_preflight's own list —
  # parse preflight notes out of pf instead of relying on global.
  expected="$(expected_ip)"
  view="$(status_json | node_view "$PI")" || {
    echo "ERROR: $PI not found in tailscale status --json" >&2
    exit 1
  }
  local ip tags tagged expiry
  ip="$(jq -r .ip <<<"$view")"
  tagged="$(jq -r .has_idea <<<"$view")"
  expiry="$(jq -r .key_expiry <<<"$view")"
  if [ -n "$expected" ] && [ "$ip" != "$expected" ]; then
    echo "ERROR: $PI IP $ip does not match fleet-state $expected; not safe to tag" >&2
    exit 1
  fi
  local ok
  ok="$(jq -r .ok <<<"$pf")"
  if [ "$tagged" = true ]; then
    add_note "$PI already has tag:idea; postcheck/wait will be idempotent."
  else
    add_note "$PI is untagged (user-owned). Apply tag:idea via admin-console Edit tags; do not run tailscale up --advertise-tags from this session."
  fi
  if [ -n "$expiry" ]; then
    add_note "$PI KeyExpiry is $expiry (UTC). After Edit tags, also Disable key expiry — console tagging does not by itself turn expiry off unless the node is re-authenticated."
  fi
  if [ "$PI" = idea02 ]; then
    add_note "idea02 is status hold / not a pool Pi. T-c names it because it expires 2026-12-02 14:36 Europe/Brussels. Do not run deploy/teardown tools on it. Do not change its hold status."
  fi
  if [ "$PI" = idea01 ]; then
    add_note "idea01 is golden. Tag it last, only after idea03 and idea04 (and idea02) succeeded."
  fi
  jq -nc --argjson ok "$ok" --argjson preflight "$pf" --argjson node "$view" \
    --arg pi "$PI" --arg expected "$expected" --argjson notes "$NOTES" \
    '{script:"tag-fleet-idea.sh",mode:"precheck",ok:$ok,pi:$pi,expected_ip:$expected,
      node:$node,preflight:$preflight,notes:$notes}'
}

do_wait() {
  need_pi
  local view tagged deadline now
  deadline=$(( $(date +%s) + WAIT_TIMEOUT ))
  while :; do
    view="$(status_json | node_view "$PI")" || view=""
    tagged="$(jq -r '.has_idea // false' <<<"${view:-{\}}")"
    if [ "$tagged" = true ]; then
      jq -nc --arg pi "$PI" --argjson node "$view" \
        '{script:"tag-fleet-idea.sh",mode:"wait",ok:true,pi:$pi,node:$node,message:"tag:idea is now visible"}'
      return 0
    fi
    now=$(date +%s)
    if [ "$now" -ge "$deadline" ]; then
      echo "ERROR: timed out after ${WAIT_TIMEOUT}s waiting for tag:idea on $PI" >&2
      jq -nc --arg pi "$PI" --argjson node "${view:-null}" --argjson timeout "$WAIT_TIMEOUT" \
        '{script:"tag-fleet-idea.sh",mode:"wait",ok:false,pi:$pi,node:$node,timeout_s:$timeout}'
      return 1
    fi
    sleep 5
  done
}

do_postcheck() {
  need_pi
  claim_ok || exit 1
  local view expected ip tagged expiry ssh_ok=false ssh_detail="skipped" probe_ok=null
  expected="$(expected_ip)"
  view="$(status_json | node_view "$PI")" || {
    echo "ERROR: $PI not found in tailscale status --json after tagging" >&2
    exit 1
  }
  ip="$(jq -r .ip <<<"$view")"
  tagged="$(jq -r .has_idea <<<"$view")"
  expiry="$(jq -r .key_expiry <<<"$view")"
  if [ -n "$expected" ] && [ "$ip" != "$expected" ]; then
    add_note "IP changed: fleet-state $expected, status now $ip. Unexpected (docs say re-auth keeps the IP). Do not continue to the next Pi."
  else
    add_note "IP unchanged ($ip)."
  fi
  if [ "$tagged" = true ]; then
    add_note "$PI now shows Tags: tag:idea."
  else
    add_note "$PI still does not show tag:idea."
  fi
  if [ -n "$expiry" ]; then
    add_note "KeyExpiry is still set ($expiry UTC). Disable key expiry in the console (especially idea02/idea03, deadline 2026-12-02 14:36 Europe/Brussels)."
  else
    add_note "KeyExpiry is empty (no expiry)."
  fi
  if [ "${SKIP_SSH:-0}" != 1 ]; then
    if fl_ssh "$ip" true; then
      ssh_ok=true
      ssh_detail="ok"
    else
      ssh_ok=false
      ssh_detail="failed"
      add_note "SSH from this box to $ip failed after the tag change. Preferred rollback is to restore admins → tag:idea in the ACL (console cannot remove the last tag)."
    fi
  fi
  local ok=true
  [ "$tagged" = true ] || ok=false
  [ -z "$expected" ] || [ "$ip" = "$expected" ] || ok=false
  if [ "${SKIP_SSH:-0}" != 1 ]; then
    [ "$ssh_ok" = true ] || ok=false
  fi
  jq -nc --argjson ok "$ok" --arg pi "$PI" --arg expected "$expected" \
    --argjson node "$view" --argjson ssh_ok "$ssh_ok" --arg ssh_detail "$ssh_detail" \
    --argjson notes "$NOTES" \
    '{script:"tag-fleet-idea.sh",mode:"postcheck",ok:$ok,pi:$pi,expected_ip:$expected,
      node:$node,ssh:{ok:$ssh_ok,detail:$ssh_detail},notes:$notes}'
}

do_health() {
  local health_script="$SCRIPT_DIR/check-fleet-health.sh"
  if [ ! -x "$health_script" ]; then
    echo "WARN: $health_script missing" >&2
    echo '{}'
    return 0
  fi
  if [ -z "${SSH_BIN:-}" ] && [ -x "${HOME}/.local/bin/socks-connect" ]; then
    local wrap
    wrap="$(mktemp)"
    printf '%s\n' '#!/usr/bin/env bash' "exec ssh -o ProxyCommand=\"${HOME}/.local/bin/socks-connect %h %p\" \"\$@\"" > "$wrap"
    chmod +x "$wrap"
    export SSH_BIN="$wrap"
  fi
  # Never --alert (would create/remove PAUSED). idea02 hold is reported, not failed.
  STATE_FILE="$STATE_FILE" "$health_script" --pi "$PI" 2>/dev/null || true
}

do_run() {
  need_pi
  local pre post health='{}'
  pre="$(do_precheck)" || { echo "$pre"; return 1; }
  echo "Ready for Koen to tag $PI:" >&2
  echo "  1. https://login.tailscale.com/admin/machines" >&2
  echo "  2. Open $PI (… menu) → Edit tags → add tag:idea → Save" >&2
  echo "  3. Disable key expiry on this machine (Edit tags does not turn it off by itself)." >&2
  echo "  4. Do not run tailscale up --advertise-tags on the Pi (re-auth, SSH can drop)." >&2
  echo "Waiting up to ${WAIT_TIMEOUT}s for Tags to include tag:idea …" >&2
  local wait_out
  if ! wait_out="$(do_wait)"; then
    echo "$wait_out"
    return 1
  fi
  NOTES='[]'
  post="$(do_postcheck)" || { echo "$post"; return 1; }
  if [ "${SKIP_SSH:-0}" != 1 ]; then
    health="$(do_health | jq -c '.' 2>/dev/null || echo '{}')"
  fi
  local ok
  ok="$(jq -s '.[0].ok and .[1].ok' <<<"$pre"$'\n'"$post")"
  jq -nc --argjson ok "$ok" --arg pi "$PI" --argjson pre "$pre" \
    --argjson wait "$wait_out" --argjson post "$post" --argjson health "$health" \
    '{script:"tag-fleet-idea.sh",mode:"run",ok:$ok,pi:$pi,
      precheck:$pre,wait:$wait,postcheck:$post,health:$health,
      applied:false,
      note:"Tags are never applied by this script."}'
}

case "$MODE" in
  preflight) do_preflight ;;
  precheck)  do_precheck ;;
  wait)      do_wait ;;
  postcheck) do_postcheck ;;
  run)       do_run ;;
esac
