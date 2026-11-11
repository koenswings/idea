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
check "preflight canary null when kits tagged but offline" bash -c 'jq -e ".ok==false and .tag_idea_count==1 and .tag_idea_hub_count==0 and .canary==null and .canary_reason==\"no_online_tagged_engine\"" >/dev/null <<<"$0"' "$OUT"
check "offline preflight note is not a lockout claim" bash -c 'jq -e "[.notes[] | select(test(\"lock out\")) ] | length == 0" >/dev/null <<<"$0"' "$OUT"
check "offline preflight note mentions canary null" bash -c 'jq -e "[.notes[] | select(test(\"canary: null\"))] | length > 0" >/dev/null <<<"$0"' "$OUT"

# Remaining precheck/wait/postcheck cases need preflight ok, so add an
# online tagged Engine and a TCP_PROBE_CMD hook (never open a real socket).
cat > "$WORK/tcp-open.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat > "$WORK/tcp-fail.sh" <<'SH'
#!/usr/bin/env bash
exit 1
SH
cat > "$WORK/tcp-second-ok.sh" <<'SH'
#!/usr/bin/env bash
# Fail the first Engine (happy-zebra), succeed on the second (sunny-robin).
case "$1" in
  100.96.98.10) exit 0 ;;
  *) exit 1 ;;
esac
SH
chmod +x "$WORK/tcp-open.sh" "$WORK/tcp-fail.sh" "$WORK/tcp-second-ok.sh"

python3 - "$WORK/status.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["Peer"]["c"]["Online"] = True
json.dump(d, open(p, "w"))
PY
export TCP_PROBE_CMD="$WORK/tcp-open.sh"

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

# --- SSH canary selection (skip *-router, prefer tagged Engines) ---

# Router listed first, then two online Engines. Canary must be the Engine.
cat > "$WORK/status-router-first.json" <<'JSON'
{
  "Self": {"HostName":"box-2-1","Online":true,"TailscaleIPs":["100.64.66.119"],"Tags":null,"KeyExpiry":"2027-04-15T09:29:40Z"},
  "Peer": {
    "r": {"HostName":"happy-zebra-router","DNSName":"happy-zebra-router.tailnet.","Online":true,"TailscaleIPs":["100.110.73.52"],"Tags":["tag:idea"],"KeyExpiry":""},
    "e1": {"HostName":"happy-zebra","DNSName":"happy-zebra.tailnet.","Online":true,"TailscaleIPs":["100.102.94.100"],"Tags":["tag:idea"],"KeyExpiry":""},
    "e2": {"HostName":"sunny-robin","Online":true,"TailscaleIPs":["100.96.98.10"],"Tags":["tag:idea"],"KeyExpiry":""},
    "a": {"HostName":"idea03","Online":true,"TailscaleIPs":["100.126.117.80"],"Tags":null,"KeyExpiry":"2026-12-02T13:36:43Z"}
  }
}
JSON
OUT="$(TAILSCALE_STATUS_JSON="$WORK/status-router-first.json" TCP_PROBE_CMD="$WORK/tcp-open.sh" "$D/tag-fleet-idea.sh" preflight)"
check "router-first list chooses tagged Engine" bash -c 'jq -e ".ok==true and .canary.ip==\"100.102.94.100\" and .canary.name==\"happy-zebra\" and .canary.tcp22==true and .canary_reason==null and (.skipped_routers|length)==1 and .skipped_routers[0].name==\"happy-zebra-router\" and .skipped_routers[0].ip==\"100.110.73.52\" and .canary.tried[0].ip==\"100.102.94.100\"" >/dev/null <<<"$0"' "$OUT"
check "router-first notes report canary and skipped router" bash -c 'jq -e "[.notes[] | select(test(\"happy-zebra \\\\(100.102.94.100\\\\)\"))] | length > 0" >/dev/null <<<"$0" && jq -e "[.notes[] | select(test(\"happy-zebra-router \\\\(100.110.73.52\\\\)\"))] | length > 0" >/dev/null <<<"$0"' "$OUT"

# Only routers online: canary null, distinct reason, not a lockout claim.
cat > "$WORK/status-routers-only.json" <<'JSON'
{
  "Self": {"HostName":"box-2-1","Online":true,"TailscaleIPs":["100.64.66.119"],"Tags":null,"KeyExpiry":"2027-04-15T09:29:40Z"},
  "Peer": {
    "r": {"HostName":"happy-zebra-router","Online":true,"TailscaleIPs":["100.110.73.52"],"Tags":["tag:idea"],"KeyExpiry":""},
    "r2": {"HostName":"sunny-robin-router","DNSName":"sunny-robin-router.tailnet.","Online":true,"TailscaleIPs":["100.64.1.2"],"Tags":["tag:idea"],"KeyExpiry":""},
    "e_off": {"HostName":"sunny-robin","Online":false,"TailscaleIPs":["100.96.98.10"],"Tags":["tag:idea"],"KeyExpiry":""}
  }
}
JSON
OUT="$(TAILSCALE_STATUS_JSON="$WORK/status-routers-only.json" TCP_PROBE_CMD="$WORK/tcp-fail.sh" "$D/tag-fleet-idea.sh" preflight)"
check "only-routers online reports canary null" bash -c 'jq -e ".ok==false and .canary==null and .canary_reason==\"no_online_tagged_engine\" and (.skipped_routers|length)==2 and (.skipped_routers|map(.name)|index(\"happy-zebra-router\"))!=null" >/dev/null <<<"$0"' "$OUT"
check "only-routers note is not a lockout claim" bash -c 'jq -e "[.notes[] | select(test(\"lock out\"))] | length == 0" >/dev/null <<<"$0"' "$OUT"
check "only-routers note explains routers skipped" bash -c 'jq -e "[.notes[] | select(test(\"canary: null\") and test(\"happy-zebra-router\") and test(\"no sshd\"))] | length > 0" >/dev/null <<<"$0"' "$OUT"

# First Engine probe fails, second Engine succeeds.
OUT="$(TAILSCALE_STATUS_JSON="$WORK/status-router-first.json" TCP_PROBE_CMD="$WORK/tcp-second-ok.sh" "$D/tag-fleet-idea.sh" preflight)"
check "second Engine used after first probe fails" bash -c 'jq -e ".ok==true and .canary.ip==\"100.96.98.10\" and .canary.name==\"sunny-robin\" and .canary.tcp22==true and (.canary.tried|length)==2 and .canary.tried[0].ip==\"100.102.94.100\" and .canary.tried[0].tcp22==false and .canary.tried[1].ip==\"100.96.98.10\" and .canary.tried[1].tcp22==true and .skipped_routers[0].name==\"happy-zebra-router\"" >/dev/null <<<"$0"' "$OUT"

# All Engine probes fail: tcp22_failed is a lock-out warning (routers still skipped).
OUT="$(TAILSCALE_STATUS_JSON="$WORK/status-router-first.json" TCP_PROBE_CMD="$WORK/tcp-fail.sh" "$D/tag-fleet-idea.sh" preflight)"
check "all Engine probes failing is tcp22_failed" bash -c 'jq -e ".ok==false and .canary.tcp22==false and .canary_reason==\"tcp22_failed\" and .canary.ip==\"100.96.98.10\" and (.canary.tried|length)==2 and .skipped_routers[0].name==\"happy-zebra-router\"" >/dev/null <<<"$0"' "$OUT"
check "tcp22_failed note warns about lockout" bash -c 'jq -e "[.notes[] | select(test(\"lock out\"))] | length > 0" >/dev/null <<<"$0"' "$OUT"

# --- SOCKS / plain-socket canary probe (userspace Tailscale) ---

cat > "$WORK/socks-banner.sh" <<'SH'
#!/usr/bin/env bash
# Fake socks-connect <ip> <port>: print an SSH banner, then idle.
printf 'SSH-2.0-OpenSSH_9.2p1_test\r\n'
sleep 8
SH
cat > "$WORK/socks-silent.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat > "$WORK/socks-fail.sh" <<'SH'
#!/usr/bin/env bash
echo "socks fail" >&2
exit 1
SH
cat > "$WORK/socks-log.sh" <<'SH'
#!/usr/bin/env bash
echo "called $*" >> "$WORK/socks-called.log"
printf 'SSH-2.0-should-not-be-used\r\n'
SH
chmod +x "$WORK/socks-banner.sh" "$WORK/socks-silent.sh" "$WORK/socks-fail.sh" "$WORK/socks-log.sh"

OUT="$(env -u TCP_PROBE_CMD SOCKS_CONNECT_BIN="$WORK/socks-banner.sh" TAILSCALE_STATUS_JSON="$WORK/status-router-first.json" "$D/tag-fleet-idea.sh" preflight)"
check "socks-connect banner is treated as opened" bash -c 'jq -e ".ok==true and .canary.tcp22==true and .canary.ip==\"100.102.94.100\" and .canary.name==\"happy-zebra\"" >/dev/null <<<"$0"' "$OUT"

OUT="$(env -u TCP_PROBE_CMD SOCKS_CONNECT_BIN="$WORK/socks-silent.sh" TAILSCALE_STATUS_JSON="$WORK/status-router-first.json" "$D/tag-fleet-idea.sh" preflight)"
check "socks-connect with no banner fails" bash -c 'jq -e ".ok==false and .canary_reason==\"tcp22_failed\" and .canary.tcp22==false" >/dev/null <<<"$0"' "$OUT"

OUT="$(env -u TCP_PROBE_CMD SOCKS_CONNECT_BIN="$WORK/socks-fail.sh" TAILSCALE_STATUS_JSON="$WORK/status-router-first.json" "$D/tag-fleet-idea.sh" preflight)"
check "socks-connect non-zero exit fails" bash -c 'jq -e ".ok==false and .canary_reason==\"tcp22_failed\" and .canary.tcp22==false" >/dev/null <<<"$0"' "$OUT"

rm -f "$WORK/socks-called.log"
OUT="$(TCP_PROBE_CMD="$WORK/tcp-open.sh" SOCKS_CONNECT_BIN="$WORK/socks-log.sh" TAILSCALE_STATUS_JSON="$WORK/status-router-first.json" "$D/tag-fleet-idea.sh" preflight)"
check "TCP_PROBE_CMD takes precedence over socks-connect" bash -c 'jq -e ".ok==true and .canary.tcp22==true and .canary.ip==\"100.102.94.100\"" >/dev/null <<<"$0"' "$OUT"
check "TCP_PROBE_CMD precedence does not invoke socks-connect" test ! -e "$WORK/socks-called.log"

# socks-connect absent: fall back to a plain socket (local listener, not a Pi).
cat > "$WORK/plain-listen.py" <<'PY'
import socket, sys, time
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 0))
port = s.getsockname()[1]
sys.stdout.write(str(port) + "\n")
sys.stdout.flush()
s.listen(5)
s.settimeout(15)
end = time.time() + 15
while time.time() < end:
    try:
        c, _ = s.accept()
    except socket.timeout:
        break
    try:
        c.settimeout(1)
        c.recv(1)
    except Exception:
        pass
    c.close()
s.close()
PY
PLAIN_PORT="$(python3 "$WORK/plain-listen.py" >"$WORK/plain-port.txt" & echo $! >"$WORK/plain-listen.pid"; sleep 0.2; cat "$WORK/plain-port.txt")"
cat > "$WORK/status-local-engine.json" <<JSON
{
  "Self": {"HostName":"box-2-1","Online":true,"TailscaleIPs":["100.64.66.119"],"Tags":null,"KeyExpiry":""},
  "Peer": {
    "e1": {"HostName":"happy-zebra","Online":true,"TailscaleIPs":["127.0.0.1"],"Tags":["tag:idea"],"KeyExpiry":""}
  }
}
JSON
OUT="$(env -u TCP_PROBE_CMD SOCKS_CONNECT_BIN="$WORK/no-such-socks-connect" TCP_PROBE_PORT="$PLAIN_PORT" TAILSCALE_STATUS_JSON="$WORK/status-local-engine.json" "$D/tag-fleet-idea.sh" preflight)"
check "absent socks-connect falls back to plain socket" bash -c 'jq -e ".ok==true and .canary.tcp22==true and .canary.ip==\"127.0.0.1\" and .canary.name==\"happy-zebra\"" >/dev/null <<<"$0"' "$OUT"
if [ -f "$WORK/plain-listen.pid" ]; then
  kill "$(cat "$WORK/plain-listen.pid")" 2>/dev/null || true
  wait "$(cat "$WORK/plain-listen.pid")" 2>/dev/null || true
fi


echo "tag-fleet-idea.test.sh: $pass passed, $fail failed"
[ "$fail" = 0 ]
