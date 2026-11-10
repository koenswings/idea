#!/usr/bin/env bash
# Offline tests for tag-fleet-idea.sh (idea#375 T-c). No live Tailscale, no Pi.
set -uo pipefail
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$D" rev-parse --show-toplevel)"
pass=0; fail=0
ok()  { echo "PASS $1"; pass=$((pass+1)); }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
check() { local n="$1"; shift; if "$@"; then ok "$n"; else bad "$n"; fi; }

check "script bash -n" bash -n "$D/tag-fleet-idea.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export STATE_FILE="$WORK/fleet-state.json" BOT_NAME=Atlas SKIP_SSH=1
cat > "$STATE_FILE" <<'JSON'
{
  "idea01": {"role":"golden","status":"idle","claim":null,"tailscale":"100.99.231.94"},
  "idea02": {"role":"fleet-pending","status":"hold","claim":null,"tailscale":"100.85.108.118"},
  "idea03": {"role":"spare","status":"idle","claim":null,"tailscale":"100.126.117.80"},
  "idea04": {"role":"spare","status":"idle","claim":null,"tailscale":"100.108.39.45"},
  "wizardly-hugle": {"role":"production","status":"production","claim":null,"tailscale":"100.115.60.6"}
}
JSON

"$D/tag-fleet-idea.sh" >/dev/null 2>&1
check "missing mode exits 2" test $? = 2

"$D/tag-fleet-idea.sh" --advertise-tags --pi idea03 >/dev/null 2>&1
check "refuses --advertise-tags" test $? = 2
"$D/tag-fleet-idea.sh" --unsafe-cli-reauth >/dev/null 2>&1
check "refuses --unsafe-cli-reauth" test $? = 2

OUT="$("$D/tag-fleet-idea.sh" order)"
check "order lists idea03 first" bash -c 'jq -e ".order[0]==\"idea03\" and .order[-1]==\"idea01\"" >/dev/null <<<"$0"' "$OUT"

# status fixture: kits tagged but offline; fleet untagged
cat > "$WORK/status.json" <<'JSON'
{
  "Self": {"HostName":"box-2-1","Online":true,"TailscaleIPs":["100.64.66.119"],"Tags":null,"KeyExpiry":"2027-04-15T09:29:40Z"},
  "Peer": {
    "a": {"HostName":"idea03","Online":true,"TailscaleIPs":["100.126.117.80"],"Tags":null,"KeyExpiry":"2026-12-02T13:36:43Z"},
    "b": {"HostName":"idea01","Online":true,"TailscaleIPs":["100.99.231.94"],"Tags":null,"KeyExpiry":"2027-03-27T14:01:31Z"},
    "c": {"HostName":"sunny-robin","Online":false,"TailscaleIPs":["100.96.98.10"],"Tags":["tag:idea"],"KeyExpiry":""},
    "d": {"HostName":"openclaw-pi","Online":true,"TailscaleIPs":["100.115.60.6"],"Tags":null,"KeyExpiry":"2027-04-06T08:20:17Z"}
  }
}
JSON
export TAILSCALE_STATUS_JSON="$WORK/status.json"

OUT="$("$D/tag-fleet-idea.sh" preflight)"
check "preflight ok when kits tagged but offline" bash -c 'jq -e ".ok==true and .tag_idea_count==1 and .tag_idea_hub_count==0 and .canary.tcp22==false" >/dev/null <<<"$0"' "$OUT"

"$D/tag-fleet-idea.sh" precheck --pi wizardly-hugle >/dev/null 2>&1
check "refuses wizardly-hugle" test $? = 2
"$D/tag-fleet-idea.sh" precheck --pi idea >/dev/null 2>&1
check "refuses idea" test $? = 2
"$D/tag-fleet-idea.sh" precheck --pi sunny-robin >/dev/null 2>&1
check "refuses kit sunny-robin" test $? = 2

OUT="$("$D/tag-fleet-idea.sh" precheck --pi idea03)"
check "precheck idea03 ok and untagged" bash -c 'jq -e ".ok==true and .pi==\"idea03\" and .node.has_idea==false and .expected_ip==\"100.126.117.80\"" >/dev/null <<<"$0"' "$OUT"

# claimed by someone else
python3 - "$STATE_FILE" <<'PY'
import json,sys
p=sys.argv[1]
d=json.load(open(p)); d["idea03"]["claim"]="Kid testing"; json.dump(d, open(p,"w"))
PY
"$D/tag-fleet-idea.sh" precheck --pi idea03 >/dev/null 2>&1
check "refuses Pi claimed by someone else" test $? = 1
python3 - "$STATE_FILE" <<'PY'
import json,sys
p=sys.argv[1]
d=json.load(open(p)); d["idea03"]["claim"]=None; json.dump(d, open(p,"w"))
PY

# wait timeout on untagged
"$D/tag-fleet-idea.sh" wait --pi idea03 --timeout 1 >/dev/null 2>&1
check "wait times out if still untagged" test $? = 1

# wait succeeds when already tagged
python3 - "$WORK/status.json" <<'PY'
import json,sys
p=sys.argv[1]
d=json.load(open(p))
d["Peer"]["a"]["Tags"]=["tag:idea"]
d["Peer"]["a"]["KeyExpiry"]=""
json.dump(d, open(p,"w"))
PY
OUT="$("$D/tag-fleet-idea.sh" wait --pi idea03 --timeout 2)"
check "wait succeeds once tagged" bash -c 'jq -e ".ok==true and .node.has_idea==true" >/dev/null <<<"$0"' "$OUT"

OUT="$(SKIP_SSH=1 "$D/tag-fleet-idea.sh" postcheck --pi idea03)"
check "postcheck pass when tagged and IP matches" bash -c 'jq -e ".ok==true and .node.has_idea==true and .ssh.detail==\"skipped\"" >/dev/null <<<"$0"' "$OUT"

# IP mismatch fails
python3 - "$WORK/status.json" <<'PY'
import json,sys
p=sys.argv[1]
d=json.load(open(p)); d["Peer"]["a"]["TailscaleIPs"]=["100.64.0.1"]; json.dump(d, open(p,"w"))
PY
OUT="$(SKIP_SSH=1 "$D/tag-fleet-idea.sh" postcheck --pi idea03 || true)"
check "postcheck fails on IP change" bash -c 'jq -e ".ok==false" >/dev/null <<<"$0"' "$OUT"

echo "tag-fleet-idea.test.sh: $pass passed, $fail failed"
[ "$fail" = 0 ]
