#!/usr/bin/env bash
# engine-placement.test.sh — idea#335: where quality-scan runs Engine tests.
# Box by default; opt-in claimed idle pool Pi (claim, pm2 stop/start as pi, release);
# idea01 default + stop-aware, box fallback (idea#332); refusals for idea02, production, kits, busy/claimed Pis.
# SSH and update-fleet-state.sh are stubbed; no network, no real Pi.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAN="${SCRIPT_DIR}/quality-scan.sh"
pass=0; fail=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

mkdir -p "$T/root/agents/agent-engine-dev" "$T/bin"
cat >"$T/root/agents/agent-engine-dev/package.json" <<'J'
{"scripts":{"test:full":"echo engine-tests-ran; test -z \"${IDEA_TEST_ALLOW_LIVE:-}\" || exit 99; if [ -n \"${FAKE_OUT:-}\" ]; then cat \"$FAKE_OUT\"; fi; exit ${FAKE_TRC:-0}"}}
J
git -C "$T/root/agents/agent-engine-dev" init -q
git -C "$T/root/agents/agent-engine-dev" -c user.email=t@t -c user.name=t add -A
git -C "$T/root/agents/agent-engine-dev" -c user.email=t@t -c user.name=t commit -qm init
# fake pnpm: run the script body from package.json
cat >"$T/bin/pnpm" <<'S'
#!/usr/bin/env bash
body="$(jq -r --arg k "$1" '.scripts[$k]' package.json)"; exec bash -c "$body"
S
# fake ssh: log argv after the host; answer pm2 jlist from $FAKE_ONLINE
cat >"$T/bin/fakessh" <<'S'
#!/usr/bin/env bash
while [[ "$1" == -o ]]; do shift 2; done
host="$1"; shift
[[ "${FAKE_UNREACHABLE:-0}" == 1 ]] && exit 255
echo "$host :: $*" >>"$FAKE_LOG"
case "$*" in
  *"ls-remote"*) echo "${FAKE_SHA:-0123456789abcdef0123456789abcdef01234567}	refs/heads/main" ;;
  *"pm2 jlist"*) if [[ "${FAKE_ONLINE:-1}" == 1 ]]; then echo '[{"name":"engine","pm2_env":{"status":"online"}}]'; else echo '[]'; fi ;;
  *"pnpm test:full"*) echo remote-tests-ran; [[ -n "${FAKE_OUT:-}" ]] && cat "$FAKE_OUT"; exit "${FAKE_RC:-0}" ;;
esac
S
# fake update-fleet-state.sh: log calls
cat >"$T/bin/fakeufs" <<'S'
#!/usr/bin/env bash
echo "ufs BOT=${BOT_NAME} $*" >>"$FAKE_LOG"
S
chmod +x "$T/bin/"*

mkstate() {
  cat >"$T/state.json" <<'J'
{"idea01":{"role":"spare","status":"idle","host":"10.0.0.1","claim":null},
 "idea02":{"role":"fleet-pending","status":"hold","host":"10.0.0.2","claim":null},
 "idea03":{"role":"review","status":"idle","host":"10.0.0.3","claim":null},
 "idea04":{"role":"spare","status":"idle","host":"10.0.0.4","claim":"Axle x"},
 "wizardly-hugle":{"role":"production","status":"production","host":"10.0.0.5","claim":null},
 "sunny-robin":{"role":"kit-engine","status":"kit","host":"10.0.0.6","claim":null}}
J
}

scan() {
  : >"$T/log"
  PATH="$T/bin:$PATH" FAKE_LOG="$T/log" QUALITY_SCAN_FLEET_STATE="$T/state.json" \
    QUALITY_SCAN_SSH="$T/bin/fakessh" QUALITY_SCAN_UFS="$T/bin/fakeufs" \
    IDEA_TEST_ALLOW_LIVE=1 QUALITY_SCAN_DRY_RUN_TESTS=0 QUALITY_SCAN_ENGINE_PI= "$@" "$SCAN" --repo-root "$T/root" --repos agent-engine-dev 2>/dev/null || true
}
check() { # name jq-expr json
  if echo "$3" | jq -e "$2" >/dev/null 2>&1; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1"; echo "$3" | jq -c '.results[0].checks.tests' 2>/dev/null || echo "$3" | tail -5; fail=$((fail+1)); fi
}
loghas() { if grep -qF -- "$2" "$T/log"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1 (log lacks: $2)"; cat "$T/log"; fail=$((fail+1)); fi; }
lognot() { if ! grep -qF -- "$2" "$T/log"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1 (log has: $2)"; fail=$((fail+1)); fi; }
tst='.results[0].checks.tests'

mkstate
out="$(scan env BOT_NAME=Atlas)"
check "box default passes, allow-live unset" "$tst.status==\"passed\" and $tst.where==\"box\"" "$out"
lognot "box default: no ssh, no claim" "::"

for pi in idea02 wizardly-hugle idea sunny-robin; do
  out="$(scan env BOT_NAME=Atlas QUALITY_SCAN_ENGINE_PI=$pi)"
  check "refuse $pi" "$tst.status==\"skipped\" and ($tst.reason==\"never_live_production\" or $tst.reason==\"unknown_pi\")" "$out"
  lognot "refuse $pi: no claim" "ufs"
done
out="$(scan env BOT_NAME=Atlas QUALITY_SCAN_ENGINE_PI=idea04)"
check "claimed idea04 → box fallback (pi_claimed)" "$tst.where==\"box\" and $tst.fallback_from==\"idea04\" and $tst.fallback_reason==\"pi_claimed\"" "$out"
lognot "claimed idea04: no claim taken" "ufs"

# idea#332 (Steve, option a): default target idea01, stop-aware like the other pool Pis
out="$(scan env -u QUALITY_SCAN_ENGINE_PI BOT_NAME=Atlas FAKE_ONLINE=1)"
check "default (unset) → pool idea01 passes" "$tst.status==\"passed\" and $tst.where==\"pool\"" "$out"
loghas "idea01 default: claim" "ufs BOT=Atlas idea01 claim"
loghas "idea01 live: pm2 stop engine" "10.0.0.1 :: pm2 stop engine"
loghas "idea01: pm2 restart engine" "10.0.0.1 :: pm2 restart engine"
loghas "idea01: release" "ufs BOT=Atlas --null idea01 claim"
loghas "idea01: idle" "ufs BOT=Atlas idea01 status idle"

sed 's/"idea01":{"role":"spare","status":"idle"/"idea01":{"role":"spare","status":"hold"/' "$T/state.json" >"$T/s2"; mv "$T/s2" "$T/state.json"
out="$(scan env -u QUALITY_SCAN_ENGINE_PI BOT_NAME=Atlas)"
check "idea01 held → box fallback" "$tst.where==\"box\" and $tst.fallback_reason==\"never_live_production\"" "$out"
lognot "idea01 held: no ssh" "::"
mkstate
sed 's/"idea01":{"role":"spare","status":"idle","host":"10.0.0.1","claim":null}/"idea01":{"role":"spare","status":"idle","host":"10.0.0.1","claim":"Kid x"}/' "$T/state.json" >"$T/s2"; mv "$T/s2" "$T/state.json"
out="$(scan env -u QUALITY_SCAN_ENGINE_PI BOT_NAME=Atlas)"
check "idea01 claimed → box fallback" "$tst.where==\"box\" and $tst.fallback_reason==\"pi_claimed\"" "$out"
mkstate
out="$(scan env -u QUALITY_SCAN_ENGINE_PI BOT_NAME=Atlas FAKE_UNREACHABLE=1)"
check "idea01 unreachable → box fallback" "$tst.where==\"box\" and $tst.fallback_reason==\"pi_unreachable\"" "$out"
lognot "unreachable: no claim" "ufs"
printf 'Test pre-flight: REFUSING to run tests — this machine looks like it runs a live Engine:\n  - live (non-test) containers are running: x\n' >"$T/preflight.out"
out="$(scan env -u QUALITY_SCAN_ENGINE_PI BOT_NAME=Atlas FAKE_ONLINE=1 FAKE_OUT="$T/preflight.out" FAKE_RC=1)"
check "idea01 pre-flight refuses → box fallback" "$tst.where==\"box\" and $tst.fallback_reason==\"preflight_refused\" and $tst.status==\"passed\"" "$out"
loghas "pre-flight refusal: Engine restored" "10.0.0.1 :: pm2 restart engine"
loghas "pre-flight refusal: claim released" "ufs BOT=Atlas --null idea01 claim"

out="$(scan env BOT_NAME=unknown QUALITY_SCAN_ENGINE_PI=idea03)"
check "pool needs BOT_NAME" "$tst.reason==\"claim_needs_bot_name\"" "$out"

out="$(scan env BOT_NAME=Atlas QUALITY_SCAN_ENGINE_PI=idea03 FAKE_ONLINE=1)"
check "pool idea03 passes" "$tst.status==\"passed\" and $tst.where==\"pool\"" "$out"
loghas "pool: claim as Atlas" "ufs BOT=Atlas idea03 claim"
loghas "pool: pm2 stop engine" "pm2 stop engine"
loghas "pool: allow-live unset remotely" "env -u IDEA_TEST_ALLOW_LIVE pnpm test:full"
loghas "pool: reads origin/main SHA" "git ls-remote \$(git -C /home/pi/idea/agents/agent-engine-dev remote get-url origin) refs/heads/main"
check "pool: scanned_sha recorded" "$tst.scanned_sha==\"0123456789abcdef0123456789abcdef01234567\" and $tst.scanned_ref==\"origin/main\"" "$out"
loghas "pool: fetches origin/main SHA in scratch" "git fetch -q \$(git -C /home/pi/idea/agents/agent-engine-dev remote get-url origin) 0123456789abcdef0123456789abcdef01234567"
loghas "pool: scratch clone of deployed tree" "git clone -q /home/pi/idea/agents/agent-engine-dev /home/pi/scratch/qs-agent-engine-dev-"
loghas "pool: checkout of the origin/main SHA" "git checkout -q 0123456789abcdef0123456789abcdef01234567"
lognot "pool: never cd into the deployed tree" "cd /home/pi/idea/agents/agent-engine-dev &&"
loghas "pool: scratch quarantined (moved)" "mkdir -p /home/pi/scratch/quarantine/"
lognot "pool: scratch never deleted" "rm -rf"
loghas "pool: pm2 restart engine" "pm2 restart engine"
loghas "pool: release claim" "ufs BOT=Atlas --null idea03 claim"
loghas "pool: status idle" "ufs BOT=Atlas idea03 status idle"
order="$(grep -nE 'pm2 stop|pnpm test:full|pm2 restart|--null idea03 claim' "$T/log" | cut -d: -f1 | tr '\n' ' ')"
if [[ "$(echo "$order" | tr ' ' '\n' | grep -v '^$' | sort -n | tr '\n' ' ')" == "$order" ]] && [[ $(echo "$order" | wc -w) -eq 4 ]]; then echo "PASS pool order stop→test→restart→release"; pass=$((pass+1)); else echo "FAIL pool order: $order"; fail=$((fail+1)); fi

out="$(scan env BOT_NAME=Atlas QUALITY_SCAN_ENGINE_PI=idea03 FAKE_ONLINE=1 FAKE_RC=1)"
check "pool failure reported" "$tst.status==\"failed\"" "$out"
loghas "pool failure still restores" "pm2 restart engine"
loghas "pool failure still releases" "--null idea03 claim"
loghas "pool failure still quarantines scratch" "mkdir -p /home/pi/scratch/quarantine/"
out="$(scan env BOT_NAME=Atlas QUALITY_SCAN_ENGINE_PI=idea03 FAKE_ONLINE=1 FAKE_SHA=garbage)"
check "pool: unreadable main SHA → skipped, not run" "$tst.reason==\"main_sha_unreadable\"" "$out"
lognot "unreadable SHA: no tests" "pnpm test:full"
loghas "unreadable SHA: still restored" "pm2 restart engine"

out="$(scan env BOT_NAME=Atlas QUALITY_SCAN_ENGINE_PI=idea03 FAKE_ONLINE=0)"
check "pool engine offline passes" "$tst.status==\"passed\"" "$out"
lognot "offline: no pm2 restart" "pm2 restart engine"

# Known box exceptions (PR #343, Steve option c)
K1='dist-test/test/automated/instance-lifecycle.test.js > Instance lifecycle (automated, real containers) > instance reaches Running and container responds to HTTP after dock'
K2='dist-test/test/automated/app-versioning.test.js > App versioning (automated, real containers) > v1.0 dock: version is read from disk and stored in instanceOf'
K3='dist-test/test/automated/app-versioning.test.js > App versioning (automated, real containers) > minor upgrade (v1.0→v1.1): instanceOf updated, lastStarted refreshed'
O1='dist-test/test/automated/other.test.js > Other > breaks'
printf ' FAIL  %s\n' "$K1" "$K2" "$K3" >"$T/known3.out"
cp "$T/known3.out" "$T/known3plus.out"; printf ' FAIL  %s\n' "$O1" >>"$T/known3plus.out"
printf ' ✓ %s 1ms\n' "$K1" "$K2" >"$T/known1.out"
for _ in $(seq 3000); do echo " ✓ filler 1ms"; done >>"$T/known1.out"; printf ' FAIL  %s\n' "$K3" >>"$T/known1.out"

out="$(scan env BOT_NAME=Atlas FAKE_OUT="$T/known3.out" FAKE_TRC=1)"
check "box: only the 3 known failures → pass" "$tst.status==\"passed\" and ($tst.known_box_exceptions|length)==3 and .ok==true" "$out"
out="$(scan env BOT_NAME=Atlas FAKE_OUT="$T/known3plus.out" FAKE_TRC=1)"
check "box: 3 known + 1 other → fail" "$tst.status==\"failed\" and $tst.other_failures==[\"$O1\"] and ($tst.known_box_exceptions|length)==3 and .ok==false" "$out"
out="$(scan env BOT_NAME=Atlas FAKE_OUT="$T/known1.out" FAKE_TRC=1)"
check "box: listed tests passing is fine" "$tst.status==\"passed\" and ($tst.known_box_exceptions_missing|length)==3" "$out"
out="$(scan env BOT_NAME=Atlas FAKE_TRC=1)"
check "box: rc!=0 with no parsed failure → fail" "$tst.status==\"failed\"" "$out"
out="$(scan env BOT_NAME=Atlas)"
check "box: listed test missing/renamed → warning" "($tst.known_box_exceptions_missing|length)==6 and ([.findings[]|select(.rule==\"tests.known_box_exception_missing\" and .severity==\"warning\")]|length)==6 and .ok==true" "$out"
# File-level [docker-setup] entries (idea#109/#111/#81)
F1='dist-test/test/automated/instance-start-status.test.js > Running only after compose up; failures end in Error (idea#109, real containers)'
{ printf ' FAIL  %s\nError: /usr/bin/bash: line 1: docker: command not found\n    exit code: 127\n⎯⎯[1/2]⎯\n\n' "$F1"; printf ' FAIL  %s\nAssertionError: expected 1 to be 2\n⎯⎯[2/2]⎯\n' "$K1"; } >"$T/file-docker.out"
printf ' FAIL  %s\nError: ENOSPC: no space left on device (docker: command not found later)\n⎯⎯[1/1]⎯\n' "$F1" >"$T/file-other.out"
out="$(scan env BOT_NAME=Atlas FAKE_OUT="$T/file-docker.out" FAKE_TRC=1)"
check "box: file failing with docker-not-found → exception" "$tst.status==\"passed\" and ($tst.known_box_exceptions|index(\"$F1\"))!=null" "$out"
out="$(scan env BOT_NAME=Atlas FAKE_OUT="$T/file-other.out" FAKE_TRC=1)"
check "box: same file, other error → fail" "$tst.status==\"failed\" and $tst.other_failures==[\"$F1\"]" "$out"

out="$(scan env BOT_NAME=Atlas QUALITY_SCAN_ENGINE_PI=idea03 FAKE_ONLINE=1 FAKE_OUT="$T/known3.out" FAKE_RC=1)"
check "pool: known test failing → fail" "$tst.status==\"failed\" and $tst.where==\"pool\" and .ok==false" "$out"

# app-dev (idea#335, Kid): `sh script/ensure-deps.sh` runs before smokes; milkwise smoke never runs
A="$T/root/agents/agent-app-dev"
mkdir -p "$A/script" "$A/tests/app-x" "$A/tests/app-milkwise"
echo '{}' >"$A/package.json"
echo 'echo ensure-deps >>"$FAKE_LOG"' >"$A/script/ensure-deps.sh"
echo 'require("fs").appendFileSync(process.env.FAKE_LOG, "smoke app-x\n")' >"$A/tests/app-x/smoke.mjs"
echo 'require("fs").appendFileSync(process.env.FAKE_LOG, "smoke milkwise\n")' >"$A/tests/app-milkwise/smoke.mjs"
sed -i 's/require("fs")/(await import("fs"))/' "$A/tests/app-x/smoke.mjs" "$A/tests/app-milkwise/smoke.mjs"
printf '#!/usr/bin/env bash\necho idea03\n' >"$T/bin/fakefind"; chmod +x "$T/bin/fakefind"
git -C "$A" init -q; git -C "$A" -c user.email=t@t -c user.name=t add -A; git -C "$A" -c user.email=t@t -c user.name=t commit -qm init
: >"$T/log"
out="$(PATH="$T/bin:$PATH" FAKE_LOG="$T/log" QUALITY_SCAN_FLEET_STATE="$T/state.json" QUALITY_SCAN_FLEET_FIND="$T/bin/fakefind" \
  QUALITY_SCAN_LOCAL_TESTS=1 QUALITY_SCAN_DRY_RUN_TESTS=0 BOT_NAME=Atlas "$SCAN" --repo-root "$T/root" --repos agent-app-dev 2>/dev/null || true)"
check "app-dev smokes pass" "$tst.status==\"passed\"" "$out"
first="$(head -1 "$T/log")"
if [[ "$first" == ensure-deps ]]; then echo "PASS app-dev: ensure-deps.sh runs first"; pass=$((pass+1)); else echo "FAIL app-dev: first log line '$first'"; fail=$((fail+1)); fi
loghas "app-dev: app-x smoke ran" "smoke app-x"
lognot "app-dev: milkwise smoke never runs" "smoke milkwise"

echo "---"
echo "engine-placement: ${pass} passed, ${fail} failed"
[[ $fail -eq 0 ]]
