#!/usr/bin/env bash
# Offline tests for field-usage-after-u-steps.sh. No live Tailscale, no Pi.
set -uo pipefail
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$D/field-usage-after-u-steps.sh"
pass=0; fail=0
ok()  { echo "PASS $1"; pass=$((pass+1)); }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
check() { local n="$1"; shift; if "$@"; then ok "$n"; else bad "$n"; fi; }

check "script bash -n" bash -n "$S"

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

"$S" >/dev/null 2>&1
check "missing mode exits 2" test $? = 2

"$S" --advertise-tags --pi idea03 >/dev/null 2>&1
check "refuses --advertise-tags" test $? = 2

OUT="$("$S" order)"
check "order is idea03, idea04, idea02, idea01" bash -c 'jq -e ".order==[\"idea03\",\"idea04\",\"idea02\",\"idea01\"]" >/dev/null <<<"$0"' "$OUT"

# default is dry-run
OUT="$("$S" plan)"
check "plan is dry-run by default" bash -c 'jq -e ".dry_run==true and .ok==true" >/dev/null <<<"$0"' "$OUT"

cat > "$WORK/status.json" <<'JSON'
{
  "Self": {"HostName":"box-2-1","Online":true,"TailscaleIPs":["100.64.66.119"],"Tags":null,"KeyExpiry":"2027-04-15T09:29:40Z"},
  "Peer": {
    "a": {"HostName":"idea03","Online":true,"TailscaleIPs":["100.126.117.80"],"Tags":null,"KeyExpiry":"2026-12-02T13:36:43Z"},
    "b": {"HostName":"idea01","Online":true,"TailscaleIPs":["100.99.231.94"],"Tags":null,"KeyExpiry":"2027-03-27T14:01:31Z"},
    "c": {"HostName":"idea04","Online":true,"TailscaleIPs":["100.108.39.45"],"Tags":null,"KeyExpiry":""},
    "d": {"HostName":"idea02","Online":true,"TailscaleIPs":["100.85.108.118"],"Tags":null,"KeyExpiry":"2026-12-02T13:36:43Z"},
    "e": {"HostName":"sunny-robin","Online":false,"TailscaleIPs":["100.96.98.10"],"Tags":["tag:idea"],"KeyExpiry":""}
  }
}
JSON
export TAILSCALE_STATUS_JSON="$WORK/status.json"

OUT="$("$S" --dry-run preflight)"
check "preflight ok when kits tagged, hub unseen, canary skipped" bash -c 'jq -e ".ok==true and .dry_run==true and .u_item_signals.u1_tag_idea_hub_visible==false and .u_item_signals.tag_idea_exists_on_some_node==true and .applied==false" >/dev/null <<<"$0"' "$OUT"
# credential report must not include file contents (no key material fields)
check "preflight credential report has no data/secret/pem fields" bash -c 'jq -e "(.credential_paths|tostring|test(\"BEGIN|ssh-ed25519|tskey-|PRIVATE\")|not)" >/dev/null <<<"$0"' "$OUT"

"$S" --dry-run precheck --pi wizardly-hugle >/dev/null 2>&1
check "refuses wizardly-hugle" test $? = 2
"$S" --dry-run precheck --pi sunny-robin >/dev/null 2>&1
check "refuses a kit" test $? = 2

OUT="$("$S" --dry-run precheck --pi idea03)"
check "precheck idea03 idle unclaimed" bash -c 'jq -e ".ok==true and .pi==\"idea03\" and .node.has_idea==false and .expected_ip==\"100.126.117.80\"" >/dev/null <<<"$0"' "$OUT"

# claimed by someone else
python3 - "$STATE_FILE" <<'PY'
import json,sys
p=sys.argv[1]
d=json.load(open(p)); d["idea03"]["claim"]="Kid testing"; d["idea03"]["status"]="testing"
json.dump(d, open(p,"w"))
PY
"$S" --dry-run precheck --pi idea03 >/dev/null 2>&1
check "refuses a Pi claimed by someone else" test $? = 1
python3 - "$STATE_FILE" <<'PY'
import json,sys
p=sys.argv[1]
d=json.load(open(p)); d["idea03"]["claim"]=None; d["idea03"]["status"]="idle"
json.dump(d, open(p,"w"))
PY

OUT="$("$S" --dry-run tag --pi idea03)"
check "dry-run tag does not apply and stays ok" bash -c 'jq -e ".ok==true and .dry_run==true and .applied==false" >/dev/null <<<"$0"' "$OUT"

OUT="$("$S" --dry-run probe-acl --from-pi idea03)"
check "dry-run probe-acl does not SSH" bash -c 'jq -e ".ok==true and .dry_run==true and .applied==false" >/dev/null <<<"$0"' "$OUT"

OUT="$("$S" --dry-run install-key --pi idea03)"
check "dry-run install-key without pubkey path is ok=false, applied=false" bash -c 'jq -e ".dry_run==true and .applied==false and .ok==false" >/dev/null <<<"$0"' "$OUT"

# 0600 pubkey fixture (contents must never appear in JSON)
install -m 0600 /dev/null "$WORK/pull.pub"
printf 'ssh-ed25519 AAAA-TEST-NOT-A-REAL-KEY comment\n' > "$WORK/pull.pub"
chmod 0600 "$WORK/pull.pub"
export USAGE_PULL_PUBKEY_FILE="$WORK/pull.pub" SIDECAR_IPV4="100.64.1.8"
OUT="$("$S" --dry-run install-key --pi idea03)"
check "dry-run install-key with 0600 pubkey + sidecar IP is ok, not applied" bash -c 'jq -e ".ok==true and .applied==false and .sidecar_ipv4==\"100.64.1.8\"" >/dev/null <<<"$0"' "$OUT"
check "install-key JSON does not leak the fixture pubkey" bash -c 'grep -q "AAAA-TEST-NOT-A-REAL-KEY" <<<"$0" && exit 1 || exit 0' "$OUT"

# too-open key file
chmod 0644 "$WORK/pull.pub"
OUT="$("$S" --dry-run install-key --pi idea03)"
check "too-open pubkey is not ok" bash -c 'jq -e ".ok==false and .pubkey.ok==false" >/dev/null <<<"$0"' "$OUT"
chmod 0600 "$WORK/pull.pub"

"$S" --dry-run install-key --pi idea01 >/dev/null 2>&1
check "refuses to install a usage key on golden idea01" test $? = 2
"$S" --dry-run install-key --pi idea02 >/dev/null 2>&1
check "refuses to install a usage key on idea02 hold" test $? = 2

OUT="$("$S" --dry-run rollback-key --pi idea03)"
check "dry-run rollback-key is applied=false" bash -c 'jq -e ".ok==true and .applied==false and .dry_run==true" >/dev/null <<<"$0"' "$OUT"

OUT="$("$S" --dry-run verify --pi idea03)"
check "dry-run verify lists the ACL matrix" bash -c 'jq -e ".ok==true and (.matrix|length)==3 and .applied==false" >/dev/null <<<"$0"' "$OUT"

# --apply install-key must refuse in this prepare-only script (no Pi mutation)
"$S" --apply install-key --pi idea03 >/dev/null 2>&1
check "--apply install-key is refused (prepare-only, no mutation)" test $? = 2

echo "field-usage-after-u-steps.test.sh: $pass passed, $fail failed"
[ "$fail" = 0 ]
