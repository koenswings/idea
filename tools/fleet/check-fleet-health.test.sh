#!/usr/bin/env bash
# check-fleet-health.test.sh — tests for check-fleet-health.sh with faked ssh and curl.
# No Pi, no network, no real fleet-state touched. Usage: tools/fleet/check-fleet-health.test.sh
# Exit 0 if all checks pass, 1 otherwise.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFH="$SCRIPT_DIR/check-fleet-health.sh"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
pass=0; fail=0
ok()  { echo "PASS $1"; pass=$((pass + 1)); }
bad() { echo "FAIL $1"; fail=$((fail + 1)); }
check() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
real_fp() { cat "$REPO_ROOT/fleet-state.json" | sha256sum; }
REAL_BEFORE="$(real_fp)"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
FAKE="$WORK/fake"; mkdir -p "$FAKE"
export FAKE HEALTH_DIR="$WORK/health" STATE_FILE="$WORK/fleet-state.json"

# Fake ssh: output = $FAKE/<host>.ssh, exit code = $FAKE/<host>.ssh_rc (default 0).
cat > "$WORK/ssh" <<'SH'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in *@*) host="${a#*@}";; esac; done
echo "$*" >> "$FAKE/ssh.log"
rc=$(cat "$FAKE/$host.ssh_rc" 2>/dev/null || echo 0)
[ "$rc" = 255 ] && { echo "ssh: connect to host $host port 22: Connection timed out" >&2; exit 255; }
cat "$FAKE/$host.ssh" 2>/dev/null; exit "$rc"
SH
# Fake curl: prints $FAKE/<host>.http (default 200); "000" plus exit 28 simulates a timeout.
cat > "$WORK/curl" <<'SH'
#!/usr/bin/env bash
url="${!#}"; host="${url#http://}"; host="${host%%:*}"
code=$(cat "$FAKE/$host.http" 2>/dev/null || echo 200)
printf '%s' "$code"; [ "$code" = 000 ] && exit 28; exit 0
SH
chmod +x "$WORK/ssh" "$WORK/curl"
export SSH_BIN="$WORK/ssh" CURL_BIN="$WORK/curl"

E=df1a250aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; C=b4eff52bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
healthy() { printf 'ENGINE_STATUS=online\nENGINE_USER=pi\nENGINE_RESTARTS=%s\nENGINE_SHA=%s\nCONSOLE_SHA=%s\nDISK_PCT=%s\n' \
  "${1:-0}" "${2:-$E}" "${3:-$C}" "${4:-37}"; }
reset() {
  rm -rf "${HEALTH_DIR:?}" "${FAKE:?}"/*
  cat > "$STATE_FILE" <<'JSON'
{ "_comment": "test",
  "p1": {"role":"golden","status":"idle","tailscale":"10.0.0.1","claim":null,"version":"engine main@df1a250, console main@b4eff52"},
  "p2": {"role":"review","status":"idle","tailscale":"10.0.0.2","claim":null,"version":"engine main@df1a250, console main@b4eff52"} }
JSON
  healthy > "$FAKE/10.0.0.1.ssh"; healthy > "$FAKE/10.0.0.2.ssh"
}
run() { OUT="$("$CFH" "$@")"; RC=$?; }
j() { jq -r "$1" <<<"$OUT"; }
has_problem() { jq -e --arg pi "$1" --arg re "$2" '.pis[] | select(.pi==$pi) | .problems | any(test($re))' <<<"$OUT" >/dev/null; }

# 1. all healthy
reset; run
check "healthy fleet exits 0" test "$RC" = 0
check "healthy: output is JSON with ok=true" test "$(j .ok)" = true
check "healthy: both Pis reported" test "$(j '.pis|length')" = 2
check "healthy: metadata keys are not Pis" test "$(j '[.pis[].pi]|join(",")')" = "p1,p2"
check "healthy: versions compared" test "$(j '.pis[0].checks.versions.ok')" = true
check "healthy: ssh goes to pi@<tailscale> with BatchMode" grep -q 'BatchMode=yes.*pi@10.0.0.1' "$FAKE/ssh.log"

# 2. unreachable (ssh 255 and curl timeout)
reset; echo 255 > "$FAKE/10.0.0.2.ssh_rc"; echo 000 > "$FAKE/10.0.0.2.http"; run
check "unreachable exits 1" test "$RC" = 1
check "unreachable: reachable.ok=false" test "$(j '.pis[1].checks.reachable.ok')" = false
check "unreachable: problem named" has_problem p2 "unreachable over Tailscale"
check "unreachable: listed in .unhealthy" test "$(j '.unhealthy|join(",")')" = p2
check "unreachable: other Pi still ok" test "$(j '.pis[0].ok')" = true

# 3. console not 200
reset; echo 502 > "$FAKE/10.0.0.1.http"; run
check "console 502 exits 1" test "$RC" = 1
check "console 502: problem named" has_problem p1 "console HTTP 502"
check "console 502: http recorded" test "$(j '.pis[0].checks.console.http')" = 502

# 4. engine stopped / missing / wrong user / pm2 unreadable
reset; healthy | sed 's/=online/=stopped/' > "$FAKE/10.0.0.1.ssh"; run
check "engine stopped exits 1" test "$RC" = 1
check "engine stopped: problem named" has_problem p1 "engine is stopped"
reset; echo "ENGINE_STATUS=missing" > "$FAKE/10.0.0.1.ssh"; printf 'ENGINE_SHA=%s\nCONSOLE_SHA=%s\nDISK_PCT=10\n' $E $C >> "$FAKE/10.0.0.1.ssh"; run
check "engine missing from pm2: flagged" has_problem p1 "no engine process"
reset; healthy | sed 's/USER=pi/USER=root/' > "$FAKE/10.0.0.1.ssh"; run
check "engine as root exits 1" test "$RC" = 1
check "engine as root: problem named" has_problem p1 "runs as 'root'"
reset; { echo "PM2_ERROR=unparseable"; healthy | grep -v ^ENGINE_; } > "$FAKE/10.0.0.1.ssh"; run
check "pm2 unreadable: flagged" has_problem p1 "pm2 unreadable"

# 5. restart jump
reset; healthy 3 > "$FAKE/10.0.0.1.ssh"; run
check "first run records baseline, no jump" test "$RC" = 0
check "baseline stored" test "$(jq -r .p1 "$HEALTH_DIR/restarts.json")" = 3
run
check "same count next run: ok" test "$RC" = 0
healthy 5 > "$FAKE/10.0.0.1.ssh"; run
check "restart jump exits 1" test "$RC" = 1
check "restart jump: problem names the jump" has_problem p1 "restarted 2x since last check \\(3 -> 5\\)"
run
check "jump not re-reported once baseline moves" test "$RC" = 0
healthy 0 > "$FAKE/10.0.0.1.ssh"; run
check "counter reset (pm2 delete/start) is not a failure" test "$RC" = 0

# 6. version drift
reset; healthy 0 0123456aaaa > "$FAKE/10.0.0.2.ssh"; run
check "engine drift exits 1" test "$RC" = 1
check "engine drift: problem names both shas" has_problem p2 "engine at 0123456, fleet-state says df1a250"
reset; healthy 0 $E 9999999 > "$FAKE/10.0.0.2.ssh"; run
check "console drift: flagged" has_problem p2 "console at 9999999, fleet-state says b4eff52"
reset; jq '.p2.version="something odd"' "$STATE_FILE" > "$WORK/s" && mv "$WORK/s" "$STATE_FILE"; run
check "unparseable fleet-state version: flagged" has_problem p2 "not in 'engine main@<sha>"
reset; jq 'del(.p2.version)' "$STATE_FILE" > "$WORK/s" && mv "$WORK/s" "$STATE_FILE"; healthy 0 0123456 > "$FAKE/10.0.0.2.ssh"; run
check "no version in fleet-state: versions skipped" test "$RC:$(j '.pis[1].checks.versions.ok')" = "0:null"

# 7. disk
reset; healthy 0 $E $C 95 > "$FAKE/10.0.0.1.ssh"; run
check "disk 95% exits 1" test "$RC" = 1
check "disk 95%: problem named" has_problem p1 "root disk 95% full"
reset; healthy 0 $E $C 89 > "$FAKE/10.0.0.1.ssh"; run
check "disk 89% is ok" test "$RC" = 0
reset; healthy 0 $E $C 50 > "$FAKE/10.0.0.1.ssh"; DISK_MAX_PCT=40 run
check "DISK_MAX_PCT override respected" test "$RC" = 1
reset; healthy | grep -v DISK > "$FAKE/10.0.0.1.ssh"; run
check "disk unreadable: flagged" has_problem p1 "root disk usage unreadable"

# 8. claimed Pis: reported, not failures, no version compare
reset; jq '.p2.claim="Axle idea#999" | .p2.status="deployed"' "$STATE_FILE" > "$WORK/s" && mv "$WORK/s" "$STATE_FILE"
healthy 0 1111111 2222222 > "$FAKE/10.0.0.2.ssh"; run
check "claimed Pi on a branch: versions not compared, exit 0" test "$RC:$(j '.pis[1].checks.versions.ok')" = "0:null"
check "claimed Pi marked claimed" test "$(j '.pis[1].claimed')" = true
echo 502 > "$FAKE/10.0.0.2.http"; run
check "claimed Pi with problems: still exit 0" test "$RC" = 0
check "claimed Pi problems reported" has_problem p2 "console HTTP 502"
check "claimed Pi listed in claimed_with_problems" test "$(j '.claimed_with_problems|join(",")')" = p2
check "claimed Pi not in unhealthy" test "$(j '.unhealthy|length')" = 0

# 9. multiple failures on one Pi all listed
reset; echo 503 > "$FAKE/10.0.0.1.http"; healthy 0 $E $C 97 | sed 's/=online/=errored/' > "$FAKE/10.0.0.1.ssh"; run
check "multiple problems all listed" test "$(j '.pis[0].problems|length')" = 3

# 10. --pi, usage and state errors
reset; run --pi p2
check "--pi limits to one Pi" test "$(j '[.pis[].pi]|join(",")')" = p2
"$CFH" --pi nope >/dev/null 2>&1; check "--pi unknown exits 2" test $? = 2
"$CFH" --bogus >/dev/null 2>&1; check "unknown flag exits 2" test $? = 2
STATE_FILE="$WORK/missing.json" "$CFH" >/dev/null 2>&1; check "missing fleet-state exits 2" test $? = 2
reset; jq '.p3={"status":"idle"}' "$STATE_FILE" > "$WORK/s" && mv "$WORK/s" "$STATE_FILE"; run
check "Pi without address: flagged, exit 1" test "$RC:$(j '.pis[2].problems[0]')" = "1:no host/tailscale address in fleet-state"

# 11. --alert: new, repeat suppression, change, 2h persistence, resolve, pause file
reset; NOW=1000 run --alert
check "alert: healthy -> no send" test "$(j .alert.send):$(j .alert.reason)" = "false:healthy"
check "alert: healthy -> no pause file" test ! -e "$HEALTH_DIR/PAUSED"
echo 502 > "$FAKE/10.0.0.1.http"; NOW=2000 run --alert
check "alert: new problem -> send" test "$(j .alert.send):$(j .alert.reason)" = "true:new"
check "alert: pause file created" test -e "$HEALTH_DIR/PAUSED"
check "alert: fleet_changes_paused true" test "$(j .alert.fleet_changes_paused)" = true
NOW=3800 run --alert
check "alert: same problem 30 min later -> silent" test "$(j .alert.send):$(j .alert.reason)" = "false:already alerted"
echo 503 > "$FAKE/10.0.0.1.http"; NOW=5600 run --alert
check "alert: problem changed -> send" test "$(j .alert.send):$(j .alert.reason)" = "true:changed"
check "alert: unhealthy_since kept from first alert" test "$(j .alert.unhealthy_since)" = "$(jq -rn '2000|todate')"
NOW=12799 run --alert
check "alert: same problem just under 2h after last alert -> silent" test "$(j .alert.send)" = false
NOW=12800 run --alert
check "alert: same problem 2h after last alert -> send" test "$(j .alert.send):$(j .alert.reason)" = "true:persisting"
NOW=14600 run --alert
check "alert: persisting re-alert resets the 2h clock" test "$(j .alert.send)" = false
healthy 4 > "$FAKE/10.0.0.2.ssh"; NOW=16800 run --alert
check "alert: second Pi joins -> send changed" test "$(j .alert.reason)" = changed
healthy 6 > "$FAKE/10.0.0.2.ssh"; NOW=18600 run --alert
check "alert: restart counter still climbing is the same problem" test "$(j .alert.send)" = false
rm "$FAKE/10.0.0.1.http"; healthy 6 > "$FAKE/10.0.0.2.ssh"; NOW=20400 run --alert
check "alert: all clear -> send resolved" test "$RC:$(j .alert.send):$(j .alert.reason)" = "0:true:resolved"
check "alert: pause file removed" test ! -e "$HEALTH_DIR/PAUSED"
NOW=22200 run --alert
check "alert: healthy after resolve -> silent" test "$(j .alert.send):$(j .alert.reason)" = "false:healthy"
jq '.p2.claim="x" | .p2.status="deployed"' "$STATE_FILE" > "$WORK/s" && mv "$WORK/s" "$STATE_FILE"
echo 502 > "$FAKE/10.0.0.2.http"; NOW=24000 run --alert
check "alert: claimed Pi problems never alert or pause" test "$(j .alert.send):$(test -e "$HEALTH_DIR/PAUSED" && echo p || echo n)" = "false:n"

# 11b. --alert with a manual walk hold ($HEALTH_DIR/HOLD)
reset; mkdir -p "$HEALTH_DIR"; echo "walk hold" > "$HEALTH_DIR/PAUSED"; touch "$HEALTH_DIR/HOLD"; NOW=1000 run --alert
check "hold: healthy run keeps PAUSED" test -e "$HEALTH_DIR/PAUSED"
check "hold: PAUSED content untouched" test "$(cat "$HEALTH_DIR/PAUSED")" = "walk hold"
check "hold: report hold=true, paused=true, hold_file" test "$RC:$(j .alert.hold):$(j .alert.fleet_changes_paused):$(j .alert.hold_file)" = "0:true:true:$HEALTH_DIR/HOLD"
rm "$HEALTH_DIR/PAUSED"; NOW=1100 run --alert
check "hold: missing PAUSED is created" test -e "$HEALTH_DIR/PAUSED"
echo 502 > "$FAKE/10.0.0.1.http"; NOW=1200 run --alert
rm "$FAKE/10.0.0.1.http"; NOW=1300 run --alert
check "hold: resolved run still keeps PAUSED" test "$(j .alert.reason):$(test -e "$HEALTH_DIR/PAUSED" && echo p)" = "resolved:p"
rm "$HEALTH_DIR/HOLD"; NOW=1400 run --alert
check "no hold: healthy run removes PAUSED as before" test ! -e "$HEALTH_DIR/PAUSED"
check "no hold: report hold=false, paused=false, hold_file null" test "$(j .alert.hold):$(j .alert.fleet_changes_paused):$(j .alert.hold_file)" = "false:false:null"
reset; mkdir -p "$HEALTH_DIR"; echo x > "$HEALTH_DIR/PAUSED"; NOW=1000 run --alert
check "no hold: stale PAUSED removed on healthy run" test ! -e "$HEALTH_DIR/PAUSED"
reset; mkdir -p "$HEALTH_DIR"; touch "$HEALTH_DIR/HOLD"; echo x > "$HEALTH_DIR/PAUSED"; NOW=1000 run
check "hold: without --alert PAUSED untouched and no alert object" test "$(j .alert):$(cat "$HEALTH_DIR/PAUSED")" = "null:x"

# 12. --origin reads fleet-state from origin/main, not the (stale) working tree
reset
git init -q --bare "$WORK/origin.git"
git clone -q "$WORK/origin.git" "$WORK/clone" 2>/dev/null
cp "$STATE_FILE" "$WORK/clone/fleet-state.json"
git -C "$WORK/clone" -c user.name=t -c user.email=t@t add fleet-state.json
git -C "$WORK/clone" -c user.name=t -c user.email=t@t commit -qm init
git -C "$WORK/clone" push -q origin HEAD:main 2>/dev/null
git clone -q -b main "$WORK/origin.git" "$WORK/other" 2>/dev/null
jq '.p2.claim="Axle idea#128" | .p2.status="testing"' "$WORK/other/fleet-state.json" > "$WORK/s" && mv "$WORK/s" "$WORK/other/fleet-state.json"
git -C "$WORK/other" -c user.name=t -c user.email=t@t commit -qam claim
git -C "$WORK/other" push -q origin main 2>/dev/null
healthy | sed 's/=online/=stopped/' > "$FAKE/10.0.0.2.ssh"; echo 000 > "$FAKE/10.0.0.2.http"
OUT="$(STATE_REPO="$WORK/clone" STATE_FILE="$WORK/clone/fleet-state.json" "$CFH")"; RC=$?
check "stale working tree: claimed Pi looks unhealthy" test "$RC" = 1
OUT="$(STATE_REPO="$WORK/clone" STATE_FILE="$WORK/clone/fleet-state.json" "$CFH" --origin)"; RC=$?
check "--origin sees the new claim: exit 0" test "$RC:$(j '.pis[1].claimed')" = "0:true"
check "--origin leaves the working tree alone" test "$(jq -r .p2.status "$WORK/clone/fleet-state.json")" = idle
STATE_REPO="$WORK/nope" "$CFH" --origin >/dev/null 2>&1; check "--origin without a repo exits 2" test $? = 2

check "real fleet-state.json untouched" test "$(real_fp)" = "$REAL_BEFORE"
echo "---"
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
