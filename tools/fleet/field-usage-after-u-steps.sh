#!/usr/bin/env bash
# field-usage-after-u-steps.sh — prepare the steps that run once Koen finishes
# the idea#375 U-items for idea#416 (T-b, T-c, ACL matrix, sidecar usage key).
#
# Default is --dry-run: read-only pre-checks (fleet-state + tailscale
# status/whois from the box), print the plan, never SSH a mutation, never
# claim, never install a key, never apply a Tailscale tag.
#
#   field-usage-after-u-steps.sh [--dry-run] plan
#   field-usage-after-u-steps.sh [--dry-run] preflight
#   field-usage-after-u-steps.sh [--dry-run] precheck --pi idea03
#   field-usage-after-u-steps.sh [--dry-run] tag --pi idea03
#   field-usage-after-u-steps.sh [--dry-run] probe-acl [--from-pi idea03]
#   field-usage-after-u-steps.sh [--dry-run] install-key --pi idea03
#   field-usage-after-u-steps.sh [--dry-run] rollback-key --pi idea03
#   field-usage-after-u-steps.sh [--dry-run] verify --pi idea03
#   field-usage-after-u-steps.sh order
#
# --apply is required for anything that would wait on a live tag change,
# install a key, or run a mutating helper verb. Tags themselves are never
# applied here: tag-fleet-idea.sh only pre/waits/post-checks; Koen clicks
# Edit tags (see tag-fleet-idea-tc.md).
#
# Credentials: never read into git, never printed. Paths only:
#   USAGE_PULL_PUBKEY_FILE   0600 public key for install-usage-key
#   USAGE_PULL_PRIVKEY_FILE  0600 private key used only to verify the forced command
#   IDEA_HUB_AUTHKEY_FILE    0600 U-3 sidecar auth key (existence/mode check only)
#   SIDECAR_IPV4             optional; otherwise discovered from tag:idea-hub
#
# Test hooks: TAILSCALE_STATUS_JSON, STATE_FILE, SKIP_SSH=1, TS_SOCK
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=fleet-lib.sh
source "$SCRIPT_DIR/fleet-lib.sh"

TS_SOCK="${TS_SOCK:-/home/box/.local/share/tailscale/tailscaled.sock}"
ORDER="idea03 idea04 idea02 idea01"
ALLOW="idea01 idea02 idea03 idea04"
DENY="idea wizardly-hugle sunny-robin happy-zebra kind-panda"
DRY_RUN=1
MODE=""
PI=""
FROM_PI=""

usage() { sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --apply) DRY_RUN=0; shift ;;
    plan|preflight|precheck|tag|probe-acl|install-key|rollback-key|verify|order)
      MODE="$1"; shift ;;
    --pi) PI="${2:-}"; shift 2 ;;
    --from-pi) FROM_PI="${2:-}"; shift 2 ;;
    --unsafe-cli-reauth|--advertise-tags)
      echo "ERROR: refusing $1; tags are applied only via admin-console Edit tags." >&2
      exit 2 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$MODE" ] || { echo "ERROR: mode required" >&2; usage >&2; exit 2; }

allowed_pi() { case " $ALLOW " in *" $1 "*) return 0 ;; esac; return 1; }
denied_pi() { case " $DENY " in *" $1 "*) return 0 ;; esac; return 1; }

need_pi() {
  [ -n "$PI" ] || { echo "ERROR: --pi required for $MODE" >&2; exit 2; }
  if denied_pi "$PI" || ! allowed_pi "$PI"; then
    echo "ERROR: refusing $PI (allow: $ALLOW; later: $DENY)" >&2
    exit 2
  fi
  fl_known "$PI" || { echo "ERROR: $PI is not in fleet-state.json" >&2; exit 1; }
}

claim_ok() {
  local claim
  claim="$(fl_get "$PI" claim)"
  if [ -n "$claim" ] && [ "$claim" != "null" ] && [[ "$claim" != "${BOT_NAME:-Atlas}"* ]]; then
    echo "ERROR: $PI is claimed by someone else ($claim)" >&2
    return 1
  fi
  if [ -n "$claim" ] && [ "$claim" != "null" ]; then
    return 0
  fi
  # unclaimed is required before we start a Pi (T-c / key install)
  return 0
}

require_unclaimed() {
  local claim status
  claim="$(fl_get "$PI" claim)"
  status="$(fl_get "$PI" status)"
  if [ -n "$claim" ] && [ "$claim" != "null" ]; then
    echo "ERROR: $PI is claimed ($claim); wait until it is unclaimed" >&2
    return 1
  fi
  if [ "$PI" != idea02 ] && [ "$status" != idle ]; then
    echo "ERROR: $PI status is $status (need idle), except idea02 which stays hold" >&2
    return 1
  fi
  if [ "$PI" = idea02 ] && [ "$status" != hold ]; then
    echo "ERROR: idea02 must stay status hold (T-c tags it, no deploy)" >&2
    return 1
  fi
  return 0
}

status_json() {
  if [ -n "${TAILSCALE_STATUS_JSON:-}" ]; then
    cat "$TAILSCALE_STATUS_JSON"
  else
    tailscale --socket "$TS_SOCK" status --json
  fi
}

# whois is read-only. Never print the raw document (may include user emails).
# Returns a compact tags/ip/hostname object, or empty.
whois_view() {
  local ip="$1"
  if [ -n "${TAILSCALE_STATUS_JSON:-}" ]; then
    # tests: derive from the status fixture instead of calling whois
    python3 - "$ip" 3<&0 <<'PY'
import json, sys
ip = sys.argv[1]
data = json.load(open("/dev/fd/3"))
nodes = [data.get("Self") or {}]
nodes.extend((data.get("Peer") or {}).values())
for n in nodes:
    ips = n.get("TailscaleIPs") or []
    if ip in ips:
        tags = n.get("Tags") or []
        host = n.get("HostName") or (n.get("DNSName") or "").split(".")[0]
        print(json.dumps({"ip": ip, "hostname": host, "tags": tags,
                          "online": bool(n.get("Online")),
                          "key_expiry": n.get("KeyExpiry") or ""},
                         separators=(",", ":")))
        sys.exit(0)
sys.exit(1)
PY
    return
  fi
  # Live: tailscale whois --json; keep only non-secret fields.
  tailscale --socket "$TS_SOCK" whois --json "$ip" 2>/dev/null | python3 - "$ip" <<'PY' || true
import json, sys
ip = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
n = data.get("Node") or data
tags = n.get("Tags") or data.get("Caps") or []
if isinstance(tags, dict):
    tags = list(tags)
host = n.get("Name") or n.get("Hostinfo", {}).get("Hostname") or ""
if host and "." in host:
    host = host.split(".")[0]
ips = n.get("Addresses") or []
ip4 = next((i.split("/")[0] for i in ips if ":" not in i), ip)
print(json.dumps({"ip": ip4, "hostname": host, "tags": tags,
                  "online": True, "key_expiry": n.get("KeyExpiry") or ""},
                 separators=(",", ":")))
PY
}

scan_nodes() {
  python3 - 3<&0 <<'PY'
import json, sys
data = json.load(open("/dev/fd/3"))
nodes = [data.get("Self") or {}]
nodes.extend((data.get("Peer") or {}).values())
out = {"tag_idea": [], "tag_idea_hub": [], "fleet": {}, "online_tagged": []}
fleet_names = {"idea01", "idea02", "idea03", "idea04", "idea", "wizardly-hugle", "openclaw-pi"}
for n in nodes:
    host = n.get("HostName") or (n.get("DNSName") or "").split(".")[0] or "?"
    tags = n.get("Tags") or []
    ips = n.get("TailscaleIPs") or []
    ip4 = next((i for i in ips if ":" not in i), "")
    rec = {"name": host, "ip": ip4, "online": bool(n.get("Online")), "tags": tags,
           "key_expiry": n.get("KeyExpiry") or ""}
    if host in fleet_names or host in ("idea01", "idea02", "idea03", "idea04"):
        out["fleet"][host] = rec
    if "tag:idea" in tags:
        out["tag_idea"].append(rec)
        if rec["online"]:
            out["online_tagged"].append(rec)
    if "tag:idea-hub" in tags:
        out["tag_idea_hub"].append(rec)
print(json.dumps(out, separators=(",", ":")))
PY
}

secret_file_ok() {
  # Check a credential path without printing contents. Returns JSON {ok,reason,path,mode}.
  local path="${1:-}" label="$2"
  python3 - "$path" "$label" <<'PY'
import os, sys, json, stat
path, label = sys.argv[1], sys.argv[2]
out = {"label": label, "path": path or "", "ok": False, "mode": "", "reason": ""}
if not path:
    out["reason"] = "path not set"
    print(json.dumps(out, separators=(",", ":")))
    sys.exit(0)
if not os.path.exists(path):
    out["reason"] = "file does not exist"
    print(json.dumps(out, separators=(",", ":")))
    sys.exit(0)
if os.path.islink(path):
    out["reason"] = "refusing a symlink (use a regular 0600 file)"
    print(json.dumps(out, separators=(",", ":")))
    sys.exit(0)
if not os.path.isfile(path):
    out["reason"] = "not a regular file"
    print(json.dumps(out, separators=(",", ":")))
    sys.exit(0)
mode = stat.S_IMODE(os.stat(path).st_mode)
out["mode"] = f"{mode:04o}"
if mode & 0o077:
    out["reason"] = f"mode {mode:04o} is too open (need 0600 or 0400)"
    print(json.dumps(out, separators=(",", ":")))
    sys.exit(0)
if os.path.getsize(path) == 0:
    out["reason"] = "file is empty"
    print(json.dumps(out, separators=(",", ":")))
    sys.exit(0)
out["ok"] = True
out["reason"] = "present, non-empty, mode ok (contents not read into the report)"
print(json.dumps(out, separators=(",", ":")))
PY
}

u_item_signals() {
  local scan="$1"
  python3 - "$scan" <<'PY'
import json, sys
scan = json.loads(sys.argv[1])
hub = scan.get("tag_idea_hub") or []
idea = scan.get("tag_idea") or []
fleet = scan.get("fleet") or {}
# Observable only. Unused tagOwners (U-1/U-2 before a node exists) cannot be
# seen from status/whois; T-b remains the console confirmation.
signals = {
    "u1_tag_idea_hub_visible": bool(hub),
    "u3_sidecar_node_visible": bool(hub),
    "tc_fleet_tagged": {
        name: bool((fleet.get(name) or {}).get("tags") and
                   "tag:idea" in (fleet.get(name) or {}).get("tags", []))
        for name in ("idea03", "idea04", "idea02", "idea01")
    },
    "tag_idea_exists_on_some_node": bool(idea),
    "sidecar_ips": [n.get("ip") for n in hub if n.get("ip")],
}
print(json.dumps(signals, separators=(",", ":")))
PY
}

do_order() {
  jq -nc --arg order "$ORDER" \
    '{script:"field-usage-after-u-steps.sh",ok:true,mode:"order",
      order:($order|split(" ")),
      reason:"idea03 first (spare), idea04 next spare, idea02 hold (expiry), idea01 golden last. idea/wh and kits later (#374)."}'
}

do_plan() {
  cat >&2 <<EOF
Plan (default --dry-run; pass --apply only when Koen's U-steps are done and the target Pi is unclaimed).

Order: $ORDER   (one Pi at a time; never idea/wh/kits here)

T-b  Confirm the live ACL admin source in the tailnet console, then
     re-read tag state with: $0 preflight
     status/whois cannot see unused tagOwners; preflight records what
     is observable and warns if tag:idea is missing or admin TCP/22 to
     an online tagged node fails.

T-c  For each Pi in order:
     $0 precheck --pi <name>
     $0 tag --pi <name>          # --apply waits; Koen clicks Edit tags
                                 # + Disable key expiry. This script never
                                 # runs tailscale up --advertise-tags.
     $0 probe-acl --from-pi <name>   # idea-to-idea must be denied

Sidecar key (after U-1..U-5, sidecar registered, U-4 tcp/22 rule live):
     export USAGE_PULL_PUBKEY_FILE=/path/to/key.pub   # 0600, never paste
     export USAGE_PULL_PRIVKEY_FILE=/path/to/key      # 0600, verify only
     export IDEA_HUB_AUTHKEY_FILE=/path/to/authkey    # 0600, existence check
     export SIDECAR_IPV4=100.x.y.z                    # or discovered
     $0 install-key --pi <unclaimed spare>
     $0 verify --pi <name>
     $0 rollback-key --pi <name>   # quarantine the key, restore drop-in

Verification matrix:
     - idea-hub can reach tag:idea on tcp/22 (probe-acl hub-to-idea)
     - forced-command export works through install-usage-key
     - Pi-to-Pi over Tailscale is denied (probe-acl idea-to-idea)
     - rollback exists for the key install (rollback-key) and for a
       failed tag (see tag-fleet-idea-tc.md §7; restore admins → tag:idea)

See tools/fleet/field-usage-u-steps.md for the U-item → script map.
EOF
  jq -nc --argjson dry "$([[ $DRY_RUN = 1 ]] && echo true || echo false)" \
    --arg order "$ORDER" \
    '{script:"field-usage-after-u-steps.sh",ok:true,mode:"plan",dry_run:$dry,order:($order|split(" "))}'
}

do_preflight() {
  local raw scan signals key_pub key_priv auth sidecar="" canary_ok=false notes='[]'
  raw="$(status_json)"
  scan="$(scan_nodes <<<"$raw")"
  signals="$(u_item_signals "$scan")"
  if [ -n "${SIDECAR_IPV4:-}" ]; then
    sidecar="$SIDECAR_IPV4"
  else
    sidecar="$(jq -r '.sidecar_ips[0] // empty' <<<"$signals")"
  fi
  key_pub="$(secret_file_ok "${USAGE_PULL_PUBKEY_FILE:-}" USAGE_PULL_PUBKEY_FILE)"
  key_priv="$(secret_file_ok "${USAGE_PULL_PRIVKEY_FILE:-}" USAGE_PULL_PRIVKEY_FILE)"
  auth="$(secret_file_ok "${IDEA_HUB_AUTHKEY_FILE:-}" IDEA_HUB_AUTHKEY_FILE)"

  local n_idea n_hub n_online canary=""
  n_idea="$(jq '.tag_idea | length' <<<"$scan")"
  n_hub="$(jq '.tag_idea_hub | length' <<<"$scan")"
  n_online="$(jq '.online_tagged | length' <<<"$scan")"
  add() { notes="$(jq -c --arg n "$1" '. + [$n]' <<<"$notes")"; }
  if [ "$n_idea" -gt 0 ]; then
    add "tag:idea is visible on $n_idea node(s). The tag exists (T-b should still confirm tagOwners + admins → tag:idea)."
  else
    add "No node currently shows tag:idea. Do not tag a fleet Pi until T-b confirms tagOwners includes tag:idea."
  fi
  if [ "$n_hub" -gt 0 ]; then
    add "tag:idea-hub is visible on $n_hub node(s) (U-1 used, sidecar from U-3 appears registered). IPv4(s) recorded without secrets."
  else
    add "tag:idea-hub is not visible. U-1/U-2 may still be live as unused tagOwners; status/whois cannot see that. T-b is the console confirmation. Sidecar registration (U-3) is not observable yet."
  fi
  if [ "$n_online" -gt 0 ]; then
    canary="$(jq -r '.online_tagged[0].ip' <<<"$scan")"
    if [ "${SKIP_SSH:-0}" = 1 ]; then
      add "SKIP_SSH=1: skipped admin TCP/22 canary to $canary."
    elif python3 - "$canary" <<'PY'
import socket, sys
s=socket.socket(); s.settimeout(3)
try:
    s.connect((sys.argv[1], 22)); s.close(); sys.exit(0)
except Exception:
    sys.exit(1)
PY
    then
      canary_ok=true
      add "Admin device can open TCP 22 to online tagged node $canary."
    else
      add "Online tagged node $canary did not accept TCP 22 from this box. Do not tag a fleet Pi."
    fi
  else
    add "No tagged node is online, so admin reachability to tag:idea cannot be proved from here."
  fi

  local ok=true
  [ "$n_idea" -gt 0 ] || ok=false
  if [ "$n_online" -gt 0 ] && [ "${SKIP_SSH:-0}" != 1 ] && [ "$canary_ok" != true ]; then
    ok=false
  fi
  jq -nc --argjson ok "$ok" --argjson dry "$([[ $DRY_RUN = 1 ]] && echo true || echo false)" \
    --argjson scan "$scan" --argjson signals "$signals" --argjson notes "$notes" \
    --arg sidecar "$sidecar" --argjson canary_ok "$canary_ok" --arg canary "$canary" \
    --argjson usage_pub "$key_pub" --argjson usage_priv "$key_priv" --argjson authkey "$auth" \
    '{script:"field-usage-after-u-steps.sh",mode:"preflight",ok:$ok,dry_run:$dry,
      observed:$scan, u_item_signals:$signals, sidecar_ipv4:$sidecar,
      canary:{ip:$canary,tcp22:$canary_ok},
      credential_paths:{pubkey:$usage_pub,privkey:$usage_priv,authkey:$authkey},
      notes:$notes,
      applied:false}'
}

do_precheck() {
  need_pi
  require_unclaimed || exit 1
  local pf view expected
  pf="$(do_preflight)"
  expected="$(fl_host "$PI")"
  view="$(status_json | python3 - "$PI" 3<&0 <<'PY'
import json, sys
name = sys.argv[1]
data = json.load(open("/dev/fd/3"))
nodes = [data.get("Self") or {}]
nodes.extend((data.get("Peer") or {}).values())
for n in nodes:
    host = n.get("HostName") or ""
    dns = (n.get("DNSName") or "").split(".")[0]
    if host == name or dns == name:
        ips = n.get("TailscaleIPs") or []
        ip4 = next((i for i in ips if ":" not in i), "")
        tags = n.get("Tags") or []
        print(json.dumps({"name": name, "ip": ip4, "online": bool(n.get("Online")),
                          "tags": tags, "has_idea": "tag:idea" in tags,
                          "key_expiry": n.get("KeyExpiry") or ""},
                         separators=(",", ":")))
        sys.exit(0)
sys.exit(1)
PY
)" || { echo "ERROR: $PI not found in tailscale status --json" >&2; exit 1; }
  local ip ok
  ip="$(jq -r .ip <<<"$view")"
  if [ -n "$expected" ] && [ "$ip" != "$expected" ]; then
    echo "ERROR: $PI IP $ip does not match fleet-state $expected" >&2
    exit 1
  fi
  ok="$(jq -r .ok <<<"$pf")"
  jq -nc --argjson ok "$ok" --argjson dry "$([[ $DRY_RUN = 1 ]] && echo true || echo false)" \
    --arg pi "$PI" --arg expected "$expected" --argjson node "$view" --argjson preflight "$pf" \
    '{script:"field-usage-after-u-steps.sh",mode:"precheck",ok:$ok,dry_run:$dry,pi:$pi,
      expected_ip:$expected,node:$node,preflight:$preflight,applied:false}'
}

do_tag() {
  need_pi
  require_unclaimed || exit 1
  local args=(precheck --pi "$PI")
  if [ "$DRY_RUN" = 1 ]; then
    # Dry-run: reuse our precheck + tag-fleet-idea precheck (no wait).
    local ours theirs
    ours="$(do_precheck)"
    if [ "${SKIP_SSH:-0}" = 1 ]; then
      theirs="$(SKIP_SSH=1 "$SCRIPT_DIR/tag-fleet-idea.sh" precheck --pi "$PI")"
    else
      # precheck of tag-fleet-idea.sh is read-only aside from an optional TCP canary
      theirs="$("$SCRIPT_DIR/tag-fleet-idea.sh" precheck --pi "$PI")"
    fi
    jq -nc --argjson ours "$ours" --argjson theirs "$theirs" --arg pi "$PI" \
      '{script:"field-usage-after-u-steps.sh",mode:"tag",ok:($ours.ok and $theirs.ok),
        dry_run:true,pi:$pi,precheck:$ours,tag_fleet_precheck:$theirs,applied:false,
        note:"Dry-run did not wait for Edit tags and did not apply a tag. Koen clicks Edit tags + Disable key expiry; then re-run with --apply to wait and post-check."}'
    return 0
  fi
  # --apply: still does not set the tag. Delegates to tag-fleet-idea.sh run
  # (prints console steps, waits, post-checks).
  echo "Delegating to tag-fleet-idea.sh run --pi $PI (tags are not applied by us)." >&2
  "$SCRIPT_DIR/tag-fleet-idea.sh" run --pi "$PI"
}

do_probe_acl() {
  local from="${FROM_PI:-$PI}"
  local probe="$SCRIPT_DIR/probe-field-usage-acl.sh"
  if [ "$DRY_RUN" = 1 ]; then
    jq -nc --arg from "$from" \
      '{script:"field-usage-after-u-steps.sh",mode:"probe-acl",ok:true,dry_run:true,
        from_pi:$from,applied:false,
        would_run:["probe-field-usage-acl.sh idea-to-idea --from-pi "+$from,
                   "probe-field-usage-acl.sh hub-to-idea --i-am-hub (from the sidecar, after U-4)"],
        note:"Dry-run did not SSH and did not open connections. After T-c, idea-to-idea must be all-denied; after U-4, hub-to-idea must open tcp/22 only."}'
    return 0
  fi
  [ -n "$from" ] || { echo "ERROR: --from-pi or --pi required for probe-acl --apply" >&2; exit 2; }
  "$probe" idea-to-idea --from-pi "$from"
}

do_install_key() {
  need_pi
  case "$PI" in
    idea03|idea04) ;;
    *) echo "ERROR: usage-key install on the pool is idea03 or idea04 only, not $PI (golden/hold/kits later or never here)" >&2; exit 2 ;;
  esac
  require_unclaimed || exit 1
  local pub auth sidecar
  pub="$(secret_file_ok "${USAGE_PULL_PUBKEY_FILE:-}" USAGE_PULL_PUBKEY_FILE)"
  auth="$(secret_file_ok "${IDEA_HUB_AUTHKEY_FILE:-}" IDEA_HUB_AUTHKEY_FILE)"
  sidecar="${SIDECAR_IPV4:-}"
  if [ -z "$sidecar" ]; then
    sidecar="$(jq -r '.u_item_signals.sidecar_ips[0] // empty' <<<"$(do_preflight)")"
  fi
  local ok=false
  if [ "$(jq -r .ok <<<"$pub")" = true ] && [ -n "$sidecar" ]; then ok=true; fi
  if [ "$DRY_RUN" = 1 ]; then
    jq -nc --argjson ok "$ok" --arg pi "$PI" --arg sidecar "$sidecar" \
      --argjson pub "$pub" --argjson auth "$auth" \
      '{script:"field-usage-after-u-steps.sh",mode:"install-key",ok:$ok,dry_run:true,pi:$pi,
        sidecar_ipv4:$sidecar,pubkey:$pub,authkey:$auth,applied:false,
        would_run:"helper install-usage-key with restrict,from=<sidecar_ipv4> using the public key at USAGE_PULL_PUBKEY_FILE (contents never printed). Then a forced-command since 2000-01-01 check, then leave rollback-key as the undo.",
        note:"Dry-run did not SSH and did not install a key. --apply is refused unless the pubkey path is a 0600 non-empty file and the sidecar IPv4 is known."}'
    return 0
  fi
  if [ "$(jq -r .ok <<<"$pub")" != true ]; then
    echo "ERROR: USAGE_PULL_PUBKEY_FILE is not ready ($(jq -r .reason <<<"$pub"))" >&2
    exit 1
  fi
  if [ -z "$sidecar" ]; then
    echo "ERROR: SIDECAR_IPV4 is not set and no tag:idea-hub node was visible" >&2
    exit 1
  fi
  echo "ERROR: --apply install-key is implemented as a plan only in this PR; do not install a standing production key without a follow-up that wraps helper install-usage-key + rollback-key. Re-run with --dry-run." >&2
  echo "Refusing to mutate $PI." >&2
  exit 2
}

do_rollback_key() {
  need_pi
  case "$PI" in idea03|idea04) ;; *) echo "ERROR: rollback-key is for idea03/idea04 pool proofs" >&2; exit 2 ;; esac
  if [ "$DRY_RUN" = 1 ]; then
    jq -nc --arg pi "$PI" \
      '{script:"field-usage-after-u-steps.sh",mode:"rollback-key",ok:true,dry_run:true,pi:$pi,applied:false,
        would_run:"quarantine /etc/ssh/idea_usage_keys/pi and any proof drop-in as .quarantine-<utc> (never rm -rf); restore the pre-install 10-idea-peer.conf; confirm operator SSH; check-fleet-health --pi (no --alert).",
        note:"Dry-run did not SSH and did not change the Pi."}'
    return 0
  fi
  echo "ERROR: --apply rollback-key is staged but not executed in this prepare-only PR. Use --dry-run, or a later apply window." >&2
  exit 2
}

do_verify() {
  need_pi
  if [ "$DRY_RUN" = 1 ]; then
    jq -nc --arg pi "$PI" \
      '{script:"field-usage-after-u-steps.sh",mode:"verify",ok:true,dry_run:true,pi:$pi,applied:false,
        matrix:[
          {name:"hub_to_idea_tcp22",expect:"tag:idea-hub can open tcp/22 on tag:idea (after U-4)"},
          {name:"forced_command_export",expect:"install-usage-key line accepts since YYYY-MM-DD and refuses a shell / wrong source"},
          {name:"idea_to_idea_denied",expect:"Pi-to-Pi over Tailscale is denied on 22,80,443,3333,3334,8080,8081 (after T-c)"}
        ],
        note:"Dry-run did not SSH. Run probe-acl and install-key in --apply only after Koen finishes the matching U-items and the Pi is unclaimed."}'
    return 0
  fi
  echo "ERROR: --apply verify is staged but not executed in this prepare-only PR (would SSH). Use --dry-run." >&2
  exit 2
}

case "$MODE" in
  order) do_order ;;
  plan) do_plan ;;
  preflight) do_preflight ;;
  precheck) do_precheck ;;
  tag) do_tag ;;
  probe-acl) do_probe_acl ;;
  install-key) do_install_key ;;
  rollback-key) do_rollback_key ;;
  verify) do_verify ;;
esac
