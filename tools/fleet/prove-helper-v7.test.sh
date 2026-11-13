#!/usr/bin/env bash
# Offline tests for prove-helper-v7.sh (idea#422). Never SSH, never claim a Pi.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
RUNNER="$ROOT/prove-helper-v7.sh"
pass=0
fail=0
export PROVE_HELPER_JSON_DIR="${PROVE_HELPER_JSON_DIR:-/tmp}"

ok() { echo "[PASS] $1"; pass=$((pass+1)); }
bad() { echo "[FAIL] $1"; fail=$((fail+1)); }

bash -n "$RUNNER" && ok "bash -n runner" || bad "bash -n runner"

# --- idea#422: function-presence / truncation guard ---
# shellcheck source=prove-helper-v7.sh
# Source only after bash -n; main is guarded by BASH_SOURCE.
# shellcheck disable=SC1091
source "$RUNNER"
if declare -F rollback_pi >/dev/null && declare -F restore_local_engine_files >/dev/null \
   && declare -F assert_rollback_state >/dev/null && declare -F check_rollback_pi_integrity >/dev/null; then
  ok "required rollback functions are present"
else
  bad "required rollback functions missing"
fi

if out="$(check_rollback_pi_integrity "$RUNNER")"; then
  ok "rollback_pi integrity (drop-in, checkout, overrides, assertions): $out"
else
  bad "rollback_pi integrity failed: $out"
fi

# A truncated copy of rollback_pi (the idea#422 bug) must be rejected.
TRUNC="$(mktemp /tmp/prove-helper-v7-truncated.XXXXXX.sh)"
python3 - "$RUNNER" "$TRUNC" <<'PY'
import pathlib, re, sys
src, dest = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
text = src.read_text()
m = re.search(r"^rollback_pi\(\) \{", text, re.M)
m2 = re.search(r"\nhealth_check\(\) \{", text[m.start():])
body_start = m.start()
body_end = m.start() + m2.start()
body = text[body_start:body_end]
# Simulate the truncation: drop drop-in restore, visudo/sshd, checkout, override
# restore and fail-closed assertions, leave a typo fragment like the live bug.
cut_at = body.find("sudo install -o root -g root -m 0755")
if cut_at < 0:
    cut_at = len(body) // 3
truncated = body[:cut_at] + "\n  ocal_engine_overrides_after_rollback_checkout\n}\n"
new = text[:body_start] + truncated + text[body_end:]
dest.write_text(new)
PY
set +e
tout="$(check_rollback_pi_integrity "$TRUNC" 2>&1)"
trc=$?
set -e
if [ "$trc" -ne 0 ]; then
  ok "integrity check rejects a truncated rollback_pi (rc=$trc)"
else
  bad "integrity check missed truncation: $tout"
fi
# quarantine the truncated copy (never rm -rf)
mv "$TRUNC" "${TRUNC}.quarantine"

# --- idea#422: fail-closed assertion with canned values (no SSH) ---
PRE_SHA="631475e239a4adcfccb8e7de24f7e0f0f3761ac7"
if assert_rollback_state "idea-app-data 5" "$THREE_PATH" "$PRE_SHA" "online"; then
  ok "assert_rollback_state passes a complete restore"
else
  bad "assert_rollback_state rejected a complete restore"
fi
set +e
err="$(assert_rollback_state "idea-app-data 5" "$THREE_PATH" "a8dcd3af207e2aeeaf73a3fdbc2ef087e1743a4a" "online" 2>&1)"
arc=$?
set -e
if [ "$arc" -ne 0 ] && grep -q "Engine HEAD" <<<"$err" && grep -q "ERROR: rollback incomplete" <<<"$err"; then
  ok "assert_rollback_state fails closed when Engine stayed on the test SHA"
else
  bad "assert_rollback_state SHA mismatch rc=$arc err=$err"
fi
set +e
err="$(assert_rollback_state "idea-app-data 7" "wrong" "$PRE_SHA" "stopped" 2>&1)"
arc=$?
set -e
if [ "$arc" -ne 0 ] && grep -q "helper is" <<<"$err" && grep -q "drop-in" <<<"$err" && grep -q "pm2 engine" <<<"$err"; then
  ok "assert_rollback_state lists helper, drop-in and pm2 mismatches"
else
  bad "assert_rollback_state incomplete error rc=$arc err=$err"
fi

# --- idea#422: mocked-ssh test of the rollback path ---
MOCK_PM2_JLIST='[{"name":"engine","pm2_env":{"status":"online","username":"pi"}}]'
mock_ssh_pi() {
  local cmd="$*"
  case "$cmd" in
    *'sudo -n /usr/local/sbin/idea-app-data version'*|*'sudo -n $HELPER version'*)
      printf '%s\n' "${MOCK_HELPER_VER:-idea-app-data 5}" ;;
    *'sudo cat /etc/ssh/sshd_config.d/10-idea-peer.conf'*|*'sudo cat $DROPIN'*)
      printf '%s\n' "${MOCK_DROPIN:-$THREE_PATH}" ;;
    *'rev-parse HEAD'*)
      printf '%s\n' "${MOCK_SHA:-$PRE_SHA}" ;;
    *'pm2 jlist'*|*jlist*)
      printf '%s\n' "$MOCK_PM2_JLIST" ;;
    *'usage-quarantine-report.txt'*)
      printf '%s\n' "quarantined /etc/tmpfiles.d/idea-usage.conf" ;;
    *'echo PRESENT'*|*'echo ABSENT'*)
      printf '%s\n' "ABSENT" ;;
    *)
      # first remote restore script, pnpm build, override restore, etc.
      return 0 ;;
  esac
}
ssh_pi() { mock_ssh_pi "$@"; }

BACKUP_DIR="/tmp/idea416-v5-backup-mock"
STAMP="20261110T222614Z"
ENGINE_DIR="/home/pi/idea/agents/agent-engine-dev"
TESTS='[]'
OVERALL=0
note() { :; }  # keep mock quiet; rollback_pi still records via this no-op? We need note to exist and not die.
# The real note() appends to TESTS with jq. Use the real one — TESTS is set.

set +e
rollback_pi >/tmp/idea422-rollback-mock.out 2>/tmp/idea422-rollback-mock.err
mrc=$?
set -e
if [ "$mrc" -eq 0 ]; then
  ok "mocked rollback_pi succeeds when helper, drop-in, SHA and pm2 match"
else
  bad "mocked rollback_pi failed a complete restore rc=$mrc $(cat /tmp/idea422-rollback-mock.err)"
fi

MOCK_SHA="a8dcd3af207e2aeeaf73a3fdbc2ef087e1743a4a"
TESTS='[]'
OVERALL=0
set +e
rollback_pi >/tmp/idea422-rollback-partial.out 2>/tmp/idea422-rollback-partial.err
prc=$?
set -e
if [ "$prc" -ne 0 ] && grep -q "ERROR: rollback incomplete" /tmp/idea422-rollback-partial.err \
   && grep -q "Engine HEAD" /tmp/idea422-rollback-partial.err; then
  ok "mocked rollback_pi fails closed when Engine stayed on the test SHA"
else
  bad "mocked partial rollback rc=$prc err=$(cat /tmp/idea422-rollback-partial.err)"
fi
unset MOCK_SHA

# --- original offline CLI tests ---
if "$RUNNER" --help >/tmp/idea416-v7-help.out; then
  grep -q -- '--pi' /tmp/idea416-v7-help.out && ok "help mentions --pi" || bad "help missing --pi"
else
  bad "help exited nonzero"
fi

# Live without --yes must be refused.
set +e
"$RUNNER" --pi idea03 >/tmp/idea416-v7-noyes.out 2>/tmp/idea416-v7-noyes.err
rc=$?
set -e
if [ "$rc" = 2 ] && grep -q -- '--yes' /tmp/idea416-v7-noyes.err; then
  ok "live without --yes exits 2"
else
  bad "live without --yes rc=$rc"
fi

# Forbidden Pis
for pi in idea01 idea02 idea wizardly-hugle sunny-robin happy-zebra kind-panda; do
  set +e
  "$RUNNER" --dry-run --pi "$pi" >/tmp/idea416-v7-deny.out 2>/tmp/idea416-v7-deny.err
  rc=$?
  set -e
  if [ "$rc" = 2 ]; then
    ok "refuses --pi $pi"
  else
    bad "did not refuse --pi $pi (rc=$rc)"
  fi
done

# Unknown pi
set +e
"$RUNNER" --dry-run --pi idea99 >/tmp/idea416-v7-unk.out 2>/tmp/idea416-v7-unk.err
rc=$?
set -e
[ "$rc" = 2 ] && ok "refuses unknown pi" || bad "unknown pi rc=$rc"

# Dry-run + self-test (the real offline suite)
set +e
"$RUNNER" --dry-run --pi idea03 --json /tmp/idea416-v7-dryrun.json > /tmp/idea416-v7-dryrun.out
rc=$?
set -e
if [ "$rc" = 0 ]; then
  ok "dry-run idea03 exits 0"
else
  bad "dry-run idea03 exited $rc"
  tail -n 40 /tmp/idea416-v7-dryrun.out || true
fi
if [ -f /tmp/idea416-v7-dryrun.json ] && jq -e '.ok==true and .mode=="dry-run" and .pi=="idea03"' /tmp/idea416-v7-dryrun.json >/dev/null; then
  ok "dry-run JSON ok=true mode=dry-run"
else
  bad "dry-run JSON missing or not ok"
  jq . /tmp/idea416-v7-dryrun.json 2>/dev/null | head -40 || true
fi
if grep -q 'dry-run did not SSH' /tmp/idea416-v7-dryrun.out; then
  ok "dry-run states it did not touch a Pi"
else
  bad "dry-run missing no-touch note"
fi
if grep -q 'rollback_pi_integrity' /tmp/idea416-v7-dryrun.out; then
  ok "dry-run runs the rollback_pi integrity check"
else
  bad "dry-run skipped rollback_pi integrity"
fi
# Every printed step should be PASS or SKIP (no FAIL) on a healthy dry-run
if grep -E '^\[FAIL\]' /tmp/idea416-v7-dryrun.out; then
  bad "dry-run printed FAIL lines"
else
  ok "dry-run printed no FAIL lines"
fi

set +e
"$RUNNER" --self-test --json /tmp/idea416-v7-self.json > /tmp/idea416-v7-self.out
rc=$?
set -e
if [ "$rc" = 0 ]; then
  ok "self-test exits 0"
else
  bad "self-test exited $rc"
  tail -n 40 /tmp/idea416-v7-self.out || true
fi

echo
echo "prove-helper-v7.test.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
