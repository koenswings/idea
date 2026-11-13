#!/usr/bin/env bash
# prove-helper-v7.sh — Atlas ready-to-run proof of Axle's helper v7 (idea#412,
# agent-engine-dev PR #309 at a8dcd3a). Durable home: tools/fleet (idea#422).
#
# Prep-only default: --dry-run / --self-test never SSH, never claim, never
# write fleet-state. A live run requires --yes --pi idea03|idea04 and must
# only happen after Axle has released the Pi (one Pi down at a time).
# Rollback is fail-closed (idea#422): after restore, helper, drop-in, Engine
# SHA and pm2 engine-online are asserted, and a mismatch exits non-zero.
#
#
# Install order (PR #309 / docs/SCRIPTS.md): backup v5 pieces, checkout the
# Engine SHA, ./install-root-helpers (helper + export + four-path drop-in;
# sudoers recopied but unchanged by this PR), confirm `idea-app-data 7`,
# pnpm build, pm2 restart engine && pm2 save as pi.
# Rollback: quarantine v7 files (never rm -rf), restore the timestamped v5
# backup, visudo -c, sshd -t + reload, checkout the previous Engine SHA,
# pnpm build, pm2 restart/save as pi, health-check, release the claim.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
MODE="live"          # live | dry-run | self-test
WANT_YES=0
PI=""
PUSH_FLEET_STATE="${PUSH_FLEET_STATE:-1}"
BOT_NAME="${BOT_NAME:-Atlas}"
ENGINE_SHA="${ENGINE_SHA:-a8dcd3af207e2aeeaf73a3fdbc2ef087e1743a4a}"
ENGINE_BRANCH="${ENGINE_BRANCH:-feat/idea-usage-export-412}"
ENGINE_DIR="${ENGINE_DIR:-/home/pi/idea/agents/agent-engine-dev}"
ENGINE_SRC="${ENGINE_SRC:-/workspace/agent-engine-dev}"
if [ -z "${IDEA_REPO:-}" ]; then
  IDEA_REPO="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
  IDEA_REPO="${IDEA_REPO:-/workspace/idea-fs-102155}"
fi
PROVE_HELPER_JSON_DIR="${PROVE_HELPER_JSON_DIR:-/tmp}"
TS_SOCK="${TS_SOCK:-/home/box/.local/share/tailscale/tailscaled.sock}"
SOCKS="${SOCKS:-127.0.0.1:1055}"
OUT_JSON="${OUT_JSON:-}"
HELPER="/usr/local/sbin/idea-app-data"
EXPORT_BIN="/usr/local/sbin/idea-usage-export"
DROPIN="/etc/ssh/sshd_config.d/10-idea-peer.conf"
USAGE_FILE="/etc/ssh/idea_usage_keys/pi"
USAGE_TMPFILES="/etc/tmpfiles.d/idea-usage.conf"
USAGE_ROOT_LIVE="/var/lib/idea/usage"
RUN_IDEA="/run/idea"
SUDOERS_10="/etc/sudoers.d/10-engine"
SUDOERS_11="/etc/sudoers.d/11-engine-files"
FOUR_PATH='AuthorizedKeysFile .ssh/authorized_keys .ssh/authorized_keys2 /etc/ssh/idea_authorized_keys/%u /etc/ssh/idea_usage_keys/%u'
THREE_PATH='AuthorizedKeysFile .ssh/authorized_keys .ssh/authorized_keys2 /etc/ssh/idea_authorized_keys/%u'
USAGE_CMD='/usr/local/sbin/idea-usage-export'
EXPECTED_CHECKLIST='https://github.com/koenswings/idea/issues/412#issuecomment-6779343720'
EXPECTED_PR='https://github.com/koenswings/agent-engine-dev/pull/309'

TESTS='[]'
CLAIMED=0
RELEASED=0
MUTATED=0
ROLLED_BACK=0
HOST=""
BOX_IP=""
BACKUP_DIR=""
PRE_SHA=""
PRE_BRANCH=""
WORK=""
KEY=""
PUB64=""
OVERALL=0
EXITING=0

usage() {
  cat <<'EOF'
Usage:
  prove-helper-v7.sh --dry-run --pi <idea03|idea04>
  prove-helper-v7.sh --self-test
  prove-helper-v7.sh --yes --pi <idea03|idea04>

Live run (--yes) claims the Pi as Atlas, installs helper v7 from engine
PR #309 (default SHA a8dcd3a), runs the idea#412 proof steps, rolls back
to v5, health-checks, and releases the claim. Do not run this while another
bot holds idea03 or idea04; only one Pi may be down at a time.

  --pi NAME        idea03 or idea04 (idea01 golden and idea02 hold are refused)
  --yes            actually claim / install / proof / roll back / release
  --dry-run        parse args, print the plan, run offline self-tests; no SSH
  --self-test      offline tests only (export format, CGNAT table, parsers)
  --json PATH      write the JSON summary here (default under $PROVE_HELPER_JSON_DIR)
  -h, --help       this help

Environment:
  IDEA_REPO ENGINE_SRC ENGINE_SHA ENGINE_DIR BOT_NAME PUSH_FLEET_STATE
  TS_SOCK SOCKS OUT_JSON PROVE_HELPER_JSON_DIR
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }
usage_error() { echo "ERROR: $*" >&2; usage >&2; exit 2; }

log() { printf '%s\n' "$*"; }
# AuthorizedKeysFile line of an sshd drop-in (comments above it are allowed).
akf_line() { tr -d '\r' | sed -n '/^[Aa]uthorized[Kk]eys[Ff]ile[[:space:]]/{ s/[[:space:]]*$//; p; q; }'; }



is_cgnat_ipv4() {
  # Same rule as idea-app-data check_usage_ipv4 / appDataHelper.checkUsageFromIpv4:
  # dotted quad, each octet 0-255, and 100.64.0.0/10 (o1==100 && 64<=o2<=127).
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
  local o1="${BASH_REMATCH[1]}" o2="${BASH_REMATCH[2]}" o3="${BASH_REMATCH[3]}" o4="${BASH_REMATCH[4]}"
  (( o1 <= 255 && o2 <= 255 && o3 <= 255 && o4 <= 255 )) || return 1
  if (( o1 == 100 && o2 >= 64 && o2 <= 127 )); then
    return 0
  fi
  return 1
}

allow_pi() {
  case "$1" in
    idea03|idea04) return 0 ;;
    idea01) usage_error "refusing $1: golden image, not for helper proofs" ;;
    idea02) usage_error "refusing $1: hold / FLEET_DENY, not for helper proofs" ;;
    idea|wizardly-hugle|sunny-robin|happy-zebra|kind-panda)
      usage_error "refusing $1: production idea/wh or a kit; not a pool Pi" ;;
    *) usage_error "unknown --pi '$1' (only idea03 or idea04)" ;;
  esac
}

note() {
  # note <name> <pass|fail|skip> <detail>
  local name="$1" status="$2" detail="$3" ok=false
  case "$status" in
    pass) ok=true ;;
    fail) ok=false; OVERALL=1 ;;
    skip) ok=true ;;
    *) die "internal: bad status '$status'" ;;
  esac
  local tag
  tag="$(printf '%s' "$status" | tr '[:lower:]' '[:upper:]')"
  printf '[%s] %s: %s\n' "$tag" "$name" "$detail"
  TESTS="$(jq -c --arg n "$name" --arg s "$status" --argjson ok "$ok" --arg d "$detail" \
    '. + [{name:$n,status:$s,ok:$ok,detail:$d}]' <<<"$TESTS")"
}

write_json() {
  local path="$1"
  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -n \
    --arg generatedAt "$now" \
    --arg stamp "$STAMP" \
    --arg mode "$MODE" \
    --arg pi "$PI" \
    --arg host "$HOST" \
    --arg boxIp "$BOX_IP" \
    --arg engineSha "$ENGINE_SHA" \
    --arg engineDir "$ENGINE_DIR" \
    --arg backupDir "$BACKUP_DIR" \
    --arg preSha "$PRE_SHA" \
    --arg checklist "$EXPECTED_CHECKLIST" \
    --arg pr "$EXPECTED_PR" \
    --argjson claimed "$CLAIMED" \
    --argjson released "$RELEASED" \
    --argjson mutated "$MUTATED" \
    --argjson rolledBack "$ROLLED_BACK" \
    --argjson ok "$( [[ $OVERALL -eq 0 ]] && echo true || echo false )" \
    --argjson steps "$TESTS" \
    '{
      generatedAt:$generatedAt, stamp:$stamp, mode:$mode, ok:$ok,
      pi:$pi, host:$host, boxIp:$boxIp, engineSha:$engineSha, engineDir:$engineDir,
      backupDir:$backupDir, preEngineSha:$preSha,
      claimed:($claimed==1), released:($released==1),
      mutated:($mutated==1), rolledBack:($rolledBack==1),
      checklist:$checklist, pr:$pr, steps:$steps
    }' > "$path"
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --pi) [ $# -ge 2 ] || usage_error "--pi needs a value"; PI="$2"; shift 2 ;;
      --yes) WANT_YES=1; shift ;;
      --dry-run) MODE="dry-run"; shift ;;
      --self-test) MODE="self-test"; shift ;;
      --json) [ $# -ge 2 ] || usage_error "--json needs a path"; OUT_JSON="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      --) shift; break ;;
      -*) usage_error "unknown option: $1" ;;
      *) usage_error "unexpected argument: $1" ;;
    esac
  done
  [ $# -eq 0 ] || usage_error "unexpected argument: $1"
  if [ "$MODE" = "self-test" ]; then
    PI="${PI:-self}"
  else
    [ -n "$PI" ] || usage_error "--pi is required (idea03 or idea04)"
    allow_pi "$PI"
  fi
  if [ "$MODE" = "live" ] && [ "$WANT_YES" != 1 ]; then
    usage_error "refusing to run live without --yes (use --dry-run or --self-test)"
  fi
  if [ -z "$OUT_JSON" ]; then
    if [ "$MODE" = "live" ]; then
      OUT_JSON="${PROVE_HELPER_JSON_DIR}/prove-helper-v7-${PI}-${STAMP}.json"
    else
      OUT_JSON="${PROVE_HELPER_JSON_DIR}/prove-helper-v7-${MODE}-${STAMP}.json"
    fi
  fi
}

print_plan() {
  cat <<EOF
Plan for ${PI} (engine PR #309 @ ${ENGINE_SHA:0:7}, idea#412):
  1. fetch origin/main in IDEA_REPO and read latest fleet-state.json
  2. precheck: ${PI} role spare, status idle, claim null; SSH helper is v5;
     git status in ${ENGINE_DIR} is clean of tracked changes; SoC <= 75 C
  3. claim as BOT_NAME=${BOT_NAME} (status testing + claim text); push only
     fleet-state.json and audit/audit-2026.jsonl when PUSH_FLEET_STATE=${PUSH_FLEET_STATE}
  4. backup to /home/pi/idea416-v5-backup-${STAMP}:
     idea-app-data, 10-idea-peer.conf, 10-engine, 11-engine-files, engine SHA
     (does not touch /home/pi/kid-quarantine or /disks)
  5. git fetch + checkout --detach ${ENGINE_SHA:0:7} in ${ENGINE_DIR}
     (never reset --hard); ./install-root-helpers; confirm idea-app-data 7
  6. pnpm build && pm2 restart engine && pm2 save  (as pi)
  7. proof: version 7; four-path drop-in; export bin root:root 0755;
     sudoers vs this PR; CGNAT rejects (non-100.64/10 leave files alone);
     install-usage-key <box-ts-ipv4> ssh-ed25519 <throwaway>; constructed
     restrict,from,command line; allowed SSH verbs (since, archive-and-clear
     --before 2000-01-01 and the equals form --before=2000-01-01); refused
     commands; wrong source IP (127.0.0.1); export format via IDEA_USAGE_ROOT
     fixture (real tree left untouched); tmpfiles.d/idea-usage.conf plus
     /var/lib/idea/usage and /run/idea created by installRootHelpers
  8. SKIP pnpm test:full (checklist comment does not ask; suite hung idea04)
     SKIP sync-peers (would rewrite /etc/ssh/idea_authorized_keys/pi)
     SKIP starting the idea-usage pm2 process (helper proof only; local
     pm2.config.cjs is restored and we only pm2 restart engine)
  9. rollback: quarantine v7 helper, export, usage key, new drop-in;
     quarantine /etc/tmpfiles.d/idea-usage.conf and /var/lib/idea/usage
     and /run/idea if this install created them and they are empty/test-only
     (never rm -rf; never touch idea-usb.conf, /run/idea-usb, /disks, or
     /var/lib/idea itself); restore v5 backup; visudo -c; sshd -t + reload;
     checkout previous Engine SHA; pnpm build; pm2 restart/save as pi
 10. health check (no --alert) and operator SSH
 11. release claim (status idle, claim null) and push fleet-state
Checklist: ${EXPECTED_CHECKLIST}
PR:         ${EXPECTED_PR}
JSON:       ${OUT_JSON}
EOF
}

# --- offline export / CGNAT proofs (also used live against a copied tree) ---

LOCAL_EXPORT=""

resolve_local_export() {
  if [ -n "$LOCAL_EXPORT" ] && [ -f "$LOCAL_EXPORT" ]; then
    return 0
  fi
  if [ -f "$ENGINE_SRC/script/build_image_assets/idea-usage-export" ]; then
    LOCAL_EXPORT="$ENGINE_SRC/script/build_image_assets/idea-usage-export"
    return 0
  fi
  return 1
}

validate_since_stream() {
  local text="$1" expect="${2-}"
  local f="$WORK/validate-since.ndjson"
  printf '%s\n' "$text" > "$f"
  python3 - "$f" "$expect" <<'PY'
import json, sys
path, expect_since = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
lines = [ln for ln in text.splitlines() if ln.strip()]
if not lines:
    print("empty stream"); sys.exit(1)
try:
    objs = [json.loads(ln) for ln in lines]
except json.JSONDecodeError as e:
    print(f"not NDJSON: {e}"); sys.exit(1)
end = objs[-1]
if end.get("type") != "end":
    print(f"last record type={end.get('type')!r}, want end"); sys.exit(1)
if end.get("schema") != "idea-usage-export/1":
    print(f"end.schema={end.get('schema')!r}"); sys.exit(1)
for key in ("since", "engine", "usageMonitoring", "counts", "errors"):
    if key not in end:
        print(f"end missing {key}"); sys.exit(1)
if expect_since and end.get("since") != expect_since:
    print(f"end.since={end.get('since')!r} want {expect_since}"); sys.exit(1)
counts = end["counts"]
if not isinstance(counts, dict):
    print("end.counts is not an object"); sys.exit(1)
for key in ("day", "sample", "presence"):
    if key not in counts or not isinstance(counts[key], int):
        print(f"end.counts.{key} missing or not int"); sys.exit(1)
if not isinstance(end["errors"], int) or end["errors"] < 0:
    print("end.errors must be a non-negative int"); sys.exit(1)
if not end.get("engine"):
    print("end.engine empty"); sys.exit(1)
ranks = {"presence": 0, "day": 1, "sample": 2}
schemas = {
    "presence": "idea-usage-presence/1",
    "day": "idea-usage-day/1",
    "sample": "idea-usage-sample/1",
}
got = {"day": 0, "sample": 0, "presence": 0}
prev_day = ""
prev_rank = -1
for o in objs[:-1]:
    t = o.get("type")
    if t not in ranks:
        print(f"unexpected type {t!r} before end"); sys.exit(1)
    if o.get("schema") != schemas[t]:
        print(f"{t}.schema={o.get('schema')!r}"); sys.exit(1)
    day = o.get("day")
    if not day:
        print(f"{t} missing day"); sys.exit(1)
    if prev_day and day < prev_day:
        print(f"days not sorted: {day} after {prev_day}"); sys.exit(1)
    if day != prev_day:
        prev_day = day
        prev_rank = -1
    r = ranks[t]
    if r < prev_rank:
        print(f"order {t} after a later kind on {day}"); sys.exit(1)
    prev_rank = r
    got[t] += 1
    if "payload" not in o:
        print(f"{t} missing payload"); sys.exit(1)
if got != {k: counts[k] for k in got}:
    print(f"counts {counts} != emitted {got}"); sys.exit(1)
print("ok")
PY
}

validate_archived() {
  local text="$1" before="${2-}"
  local f="$WORK/validate-archived.json"
  printf '%s\n' "$text" > "$f"
  python3 - "$f" "$before" <<'PY'
import json, sys
path, before = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read().strip()
if not text:
    print("empty archive stdout"); sys.exit(1)
try:
    obj = json.loads(text.splitlines()[0])
except json.JSONDecodeError as e:
    print(f"archived is not JSON: {e}"); sys.exit(1)
if obj.get("type") != "archived":
    print(f"type={obj.get('type')!r}"); sys.exit(1)
if obj.get("schema") != "idea-usage-export/1":
    print(f"schema={obj.get('schema')!r}"); sys.exit(1)
for key in ("before", "days", "files"):
    if key not in obj:
        print(f"archived missing {key}"); sys.exit(1)
if before and obj.get("before") != before:
    print(f"before={obj.get('before')!r} want {before}"); sys.exit(1)
if not isinstance(obj["days"], int) or not isinstance(obj["files"], int):
    print("days/files must be ints"); sys.exit(1)
print("ok")
PY
}

make_export_fixture() {
  # Layout matches idea-usage-export at 00063a4 (tree layout unchanged
  # from 6d01431; 00063a4 only changed emission: type-schema constants,
  # instance from payload, js_ready ints, hostname first label). Not the
  # earlier USAGE-CONTRACT draft that used usage/presence/<day>.ndjson and
  # a separate IDEA_USAGE_SETTINGS file:
  #   $root/settings.json
  #   $root/YYYY-MM-DD/presence.ndjson
  #   $root/YYYY-MM-DD/<instance>.json
  #   $root/YYYY-MM-DD/<instance>.samples.ndjson
  local root="$1" monitoring="${2:-on}"
  if [ -e "$root" ]; then
    echo "ERROR: fixture path already exists: $root" >&2
    return 1
  fi
  mkdir -p "$root/2026-02-15" "$root/2026-03-01" "$root/2026-03-02" "$root/.archive/should-not-read"
  case "$monitoring" in
    on)  printf '%s\n' '{"usageMonitoring":"on"}' > "$root/settings.json" ;;
    off) printf '%s\n' '{"usageMonitoring":"off"}' > "$root/settings.json" ;;
    missing) ;;
    *) echo "ERROR: monitoring must be on|off|missing" >&2; return 1 ;;
  esac
  cat > "$root/2026-02-15/old-inst.json" <<'JSON'
{"schema":"idea-usage-day/1","instance":"old-inst","day":"2026-02-15"}
JSON
  cat > "$root/2026-03-01/presence.ndjson" <<'JSON'
{"schema":"idea-usage-presence/1","ts":"2026-03-01T08:00:00+00:00","kind":"sample"}
JSON
  cat > "$root/2026-03-01/inst-a.json" <<'JSON'
{"schema":"idea-usage-day/1","instance":"inst-a","day":"2026-03-01"}
JSON
  cat > "$root/2026-03-01/inst-a.samples.ndjson" <<'JSON'
{"schema":"idea-usage-sample/1","ts":"2026-03-01T08:05:00+00:00","instance":"inst-a"}
JSON
  cat > "$root/2026-03-02/inst-b.json" <<'JSON'
{"schema":"idea-usage-day/1","instance":"inst-b","day":"2026-03-02"}
JSON
  printf '%s\n' '{"ignored":true}' > "$root/.archive/should-not-read/nope.json"
}

run_export() {
  local root="$1"
  shift
  local exp="$LOCAL_EXPORT"
  EXP_OUT=""; EXP_ERR=""; EXP_RC=0
  set +e
  EXP_OUT="$(env -u SSH_ORIGINAL_COMMAND \
    IDEA_USAGE_ROOT="$root" \
    IDEA_USAGE_ENGINE="self-test-engine" \
    python3 "$exp" "$@" 2>"$WORK/exp.err")"
  EXP_RC=$?
  set -e
  EXP_ERR="$(cat "$WORK/exp.err" 2>/dev/null || true)"
}

run_export_ssh_env() {
  local root="$1" cmd="$2"
  local exp="$LOCAL_EXPORT"
  EXP_OUT=""; EXP_ERR=""; EXP_RC=0
  set +e
  EXP_OUT="$(env \
    SSH_ORIGINAL_COMMAND="$cmd" \
    IDEA_USAGE_ROOT="$root" \
    IDEA_USAGE_ENGINE="self-test-engine" \
    python3 "$exp" 2>"$WORK/exp.err")"
  EXP_RC=$?
  set -e
  EXP_ERR="$(cat "$WORK/exp.err" 2>/dev/null || true)"
}

expect_invalid() {
  local name="$1"
  if [ "$EXP_RC" = 2 ] && [[ "$EXP_ERR" == *invalid\ arguments* ]] && [ -z "$EXP_OUT" ]; then
    note "$name" pass "exit 2 invalid arguments"
  else
    note "$name" fail "rc=$EXP_RC err=$(printf '%s' "$EXP_ERR" | tr '\n' ' ' | cut -c1-80)"
  fi
}

run_offline_export_tests() {
  resolve_local_export || { note "local_export_present" fail "no idea-usage-export under $ENGINE_SRC"; return 1; }
  note "local_export_present" pass "$LOCAL_EXPORT"

  local fix_on="$WORK/fixture-on" fix_off="$WORK/fixture-off" fix_miss="$WORK/fixture-missing" fix_noop="$WORK/fixture-noop"
  make_export_fixture "$fix_on" on
  make_export_fixture "$fix_off" off
  make_export_fixture "$fix_miss" missing
  make_export_fixture "$fix_noop" on

  run_export "$fix_miss" since 2026-03-01
  if [ "$EXP_RC" = 10 ] && [ -z "$EXP_OUT" ] && [[ "$EXP_ERR" == *disabled* ]]; then
    note "export_disabled_missing_settings" pass "exit 10, empty stdout, stderr mentions disabled"
  else
    note "export_disabled_missing_settings" fail "rc=$EXP_RC out='${EXP_OUT:0:80}' err='${EXP_ERR:0:80}'"
  fi

  run_export "$fix_off" since 2026-03-01
  if [ "$EXP_RC" = 10 ] && [ -z "$EXP_OUT" ] && [[ "$EXP_ERR" == *disabled* ]]; then
    note "export_disabled_off" pass "exit 10 when usageMonitoring=off"
  else
    note "export_disabled_off" fail "rc=$EXP_RC err='${EXP_ERR:0:80}'"
  fi

  run_export "$fix_on" since 2026-03-01
  local msg
  if [ "$EXP_RC" != 0 ]; then
    note "export_since_stream" fail "rc=$EXP_RC err='${EXP_ERR:0:120}'"
  elif ! msg="$(validate_since_stream "$EXP_OUT" "2026-03-01")"; then
    note "export_since_stream" fail "$msg"
  elif printf '%s\n' "$EXP_OUT" | grep -q '2026-02-15'; then
    note "export_since_stream" fail "February row leaked into since 2026-03-01"
  elif printf '%s\n' "$EXP_OUT" | grep -q should-not-read; then
    note "export_since_stream" fail ".archive/ was read"
  else
    note "export_since_stream" pass "NDJSON end marker, presence/day/sample order, Feb excluded"
  fi

  run_export "$fix_on" since 2026-12-01
  if [ "$EXP_RC" = 0 ] && validate_since_stream "$EXP_OUT" "2026-12-01" >/dev/null \
     && python3 -c 'import json,sys; e=json.loads(open(sys.argv[1]).read().splitlines()[-1]); assert e["counts"]=={"day":0,"sample":0,"presence":0}' "$WORK/validate-since.ndjson"; then
    note "export_since_empty" pass "future since yields only end with zero counts"
  else
    note "export_since_empty" fail "rc=$EXP_RC out='${EXP_OUT:0:160}'"
  fi

  # 00063a4 emission: type-schema constants, instance from payload, engine
  # first hostname label, JSON.stringify integer spelling.
  local fix_emit="$WORK/fixture-00063a4-emit"
  mkdir -p "$fix_emit/2026-03-01"
  printf '%s\n' '{"usageMonitoring":"on"}' > "$fix_emit/settings.json"
  cat > "$fix_emit/2026-03-01/zzz-name.json" <<'JSON'
{"schema":"idea-usage-day/not-the-envelope","instance":"aaa-inst","day":"2026-03-01","n":52.0}
JSON
  set +e
  EXP_OUT="$(env -u SSH_ORIGINAL_COMMAND \
    IDEA_USAGE_ROOT="$fix_emit" \
    IDEA_USAGE_ENGINE="pi.example.lan" \
    python3 "$LOCAL_EXPORT" since 2026-03-01 2>"$WORK/exp.err")"
  EXP_RC=$?
  set -e
  EXP_ERR="$(cat "$WORK/exp.err" 2>/dev/null || true)"
  if [ "$EXP_RC" = 0 ] && python3 -c '
import json, sys
text = sys.stdin.read()
lines = [ln for ln in text.splitlines() if ln.strip()]
objs = [json.loads(ln) for ln in lines]
day = next(o for o in objs if o.get("type") == "day")
end = objs[-1]
assert day.get("schema") == "idea-usage-day/1", day.get("schema")
assert day.get("instance") == "aaa-inst", day.get("instance")
assert end.get("engine") == "pi", end.get("engine")
raw = next(ln for ln, o in zip(lines, objs) if o.get("type") == "day")
assert "\"n\":52" in raw and "\"n\":52.0" not in raw, raw
print("ok")
' <<<"$EXP_OUT" >/dev/null; then
    note "export_00063a4_emission" pass "schema constants, payload instance, engine first label, js_ready ints"
  else
    note "export_00063a4_emission" fail "rc=$EXP_RC out='${EXP_OUT:0:200}' err='${EXP_ERR:0:80}'"
  fi

  run_export "$fix_on" id
  expect_invalid export_refuse_argv_id
  run_export "$fix_on" since
  expect_invalid export_refuse_argv_since
  run_export "$fix_on" since 2026-13-01
  expect_invalid export_refuse_argv_since_bad_month
  run_export "$fix_on" since 2026-02-30
  expect_invalid export_refuse_argv_since_bad_day
  run_export "$fix_on" since '2026-03-01;id'
  expect_invalid export_refuse_argv_since_metachar_in_date
  run_export "$fix_on" archive-and-clear
  expect_invalid export_refuse_argv_archive_only
  run_export "$fix_on" archive-and-clear --before
  expect_invalid export_refuse_argv_archive_no_date

  run_export_ssh_env "$fix_on" "since 2026-03-01"
  if [ "$EXP_RC" = 0 ] && validate_since_stream "$EXP_OUT" "2026-03-01" >/dev/null; then
    note "export_ssh_env_since" pass "SSH_ORIGINAL_COMMAND since works"
  else
    note "export_ssh_env_since" fail "rc=$EXP_RC err='${EXP_ERR:0:80}'"
  fi
  run_export_ssh_env "$fix_on" ""
  expect_invalid export_refuse_ssh_env_empty
  run_export_ssh_env "$fix_on" "id"
  expect_invalid export_refuse_ssh_env_id
  run_export_ssh_env "$fix_on" "since 2026-03-01;id"
  expect_invalid export_refuse_ssh_env_since_semicolon
  run_export_ssh_env "$fix_on" "archive-and-clear --before 2026-03-01 && id"
  expect_invalid export_refuse_ssh_env_archive_and
  run_export_ssh_env "$fix_on" 'since 2026-03-01; rm -rf /'
  expect_invalid export_refuse_ssh_env_since_rm

  run_export "$fix_on" archive-and-clear --before 2026-03-01
  if [ "$EXP_RC" != 0 ]; then
    note "export_archive" fail "rc=$EXP_RC err='${EXP_ERR:0:120}'"
  elif ! msg="$(validate_archived "$EXP_OUT" "2026-03-01")"; then
    note "export_archive" fail "$msg"
  elif [ -e "$fix_on/2026-02-15/old-inst.json" ]; then
    note "export_archive" fail "February tree still in live usage root"
  elif [ ! -e "$fix_on/2026-03-01/inst-a.json" ]; then
    note "export_archive" fail "March tree was archived (must be strictly-before)"
  elif ! find "$fix_on/.archive" -name 'old-inst.json' | grep -q .; then
    note "export_archive" fail "February file not under .archive/<before>-<stamp>/"
  elif [ ! -e "$fix_on/settings.json" ]; then
    note "export_archive" fail "settings.json was removed"
  else
    note "export_archive" pass "strictly-before 2026-03-01 archived Feb only; settings.json left"
  fi

  run_export "$fix_noop" archive-and-clear --before 2000-01-01
  if [ "$EXP_RC" = 0 ] && validate_archived "$EXP_OUT" "2000-01-01" >/dev/null \
     && [ -e "$fix_noop/2026-03-01/inst-a.json" ] \
     && [ -e "$fix_noop/2026-02-15/old-inst.json" ]; then
    note "export_archive_noop_2000" pass "archive --before 2000-01-01 leaves live tree"
  else
    note "export_archive_noop_2000" fail "rc=$EXP_RC out='${EXP_OUT:0:120}'"
  fi

  # a8dcd3a: equals form --before=YYYY-MM-DD is also accepted.
  run_export "$fix_noop" archive-and-clear --before=2000-01-01
  if [ "$EXP_RC" = 0 ] && validate_archived "$EXP_OUT" "2000-01-01" >/dev/null      && [ -e "$fix_noop/2026-03-01/inst-a.json" ]      && [ -e "$fix_noop/2026-02-15/old-inst.json" ]; then
    note "export_archive_noop_before_eq" pass "archive --before=2000-01-01 accepted and leaves live tree"
  else
    note "export_archive_noop_before_eq" fail "rc=$EXP_RC out='${EXP_OUT:0:120}'"
  fi
  run_export "$fix_on" archive-and-clear --before=
  expect_invalid export_refuse_argv_archive_before_eq_empty
  run_export "$fix_on" archive-and-clear --before=2026-13-01
  expect_invalid export_refuse_argv_archive_before_eq_bad_month
  run_export_ssh_env "$fix_noop" "archive-and-clear --before=2000-01-01"
  if [ "$EXP_RC" = 0 ] && validate_archived "$EXP_OUT" "2000-01-01" >/dev/null; then
    note "export_ssh_env_archive_before_eq" pass "SSH_ORIGINAL_COMMAND archive-and-clear --before=2000-01-01"
  else
    note "export_ssh_env_archive_before_eq" fail "rc=$EXP_RC err='${EXP_ERR:0:80}'"
  fi
}

run_offline_fleetstate_parse() {
  local fs="$IDEA_REPO/fleet-state.json"
  if [ ! -f "$fs" ]; then
    note "fleetstate_parse" skip "no $fs on this box"
    return 0
  fi
  if python3 - "$fs" <<'FLEETPY'
import json, sys
data = json.load(open(sys.argv[1]))
for pi in ("idea03", "idea04"):
    node = data.get(pi)
    if not isinstance(node, dict):
        print(f"missing {pi}"); sys.exit(1)
    ip = node.get("tailscale") or node.get("host") or ""
    if not ip.startswith("100."):
        print(f"{pi} has no 100.x address: {ip!r}"); sys.exit(1)
    role = node.get("role")
    if role != "spare":
        print(f"{pi} role={role!r} (want spare)"); sys.exit(1)
print("ok")
FLEETPY
  then
    note "fleetstate_parse" pass "read idea03/idea04 tailscale addresses and spare roles (claim status not required offline)"
  else
    note "fleetstate_parse" fail "could not parse $fs"
  fi
}

run_offline_cgnat_tests() {
  local ip
  for ip in 100.64.0.0 100.64.66.119 100.126.117.80 100.108.39.45 100.127.255.255; do
    if is_cgnat_ipv4 "$ip"; then
      note "cgnat_accept_${ip}" pass "100.64/10 accepted"
    else
      note "cgnat_accept_${ip}" fail "should accept $ip"
    fi
  done
  for ip in 8.8.8.8 10.42.0.1 127.0.0.1 192.168.1.1 100.63.255.255 100.128.0.1 \
            1.1.1.1 100.64.0 100.64.0.0.1 100.64.0.-1 "" "restrict,from=\"1.2.3.4\""; do
    local slug
    slug="$(printf '%s' "${ip:-empty}" | tr ' "/.' '____' | cut -c1-50)"
    if is_cgnat_ipv4 "$ip"; then
      note "cgnat_reject_${slug}" fail "should reject '$ip'"
    else
      note "cgnat_reject_${slug}" pass "rejected"
    fi
  done
}

run_offline_helper_parse_tests() {
  local helper="$ENGINE_SRC/script/build_image_assets/idea-app-data"
  if [ ! -f "$helper" ]; then
    note "helper_source" fail "missing $helper"
    return 1
  fi
  if grep -q "VERSION=7" "$helper" && grep -q 'install-usage-key' "$helper"; then
    note "helper_source" pass "idea-app-data at ENGINE_SRC is VERSION=7 and has install-usage-key"
  else
    note "helper_source" fail "ENGINE_SRC idea-app-data is not the v7 helper"
  fi
  # Confirm the helper builds the restrict line itself and checks 100.64/10.
  if grep -Fq 'restrict,from=\"$2\",command=\"$USAGE_EXPORT_CMD\"' "$helper" \
     && grep -q 'o1 == 100 && o2 >= 64 && o2 <= 127' "$helper"; then
    note "helper_builds_restrict_line" pass "helper constructs restrict,from,command and checks 100.64/10"
  else
    note "helper_builds_restrict_line" fail "could not find constructed restrict line or CGNAT check"
  fi
  if grep -Fq '<ipv4> ssh-ed25519 <base64>' "$helper" \
     && grep -q 'install-usage-key' "$helper"; then
    note "helper_argv_shape" pass "install-usage-key <ipv4> ssh-ed25519 <base64>"
  else
    note "helper_argv_shape" fail "argv shape comment/check not found"
  fi
  # Sudoers are not part of PR #309's diff vs main (when we have git).
  if [ -d "$ENGINE_SRC/.git" ]; then
    local diff
    diff="$(git -C "$ENGINE_SRC" diff --name-only "${ENGINE_SHA}^" "$ENGINE_SHA" -- \
      script/build_image_assets/10-engine script/build_image_assets/11-engine-files \
      script/build_image_assets/*sudoers* 2>/dev/null || true)"
    # The PR may be more than one commit; compare merge-base with origin/main if present.
    if git -C "$ENGINE_SRC" rev-parse --verify origin/main >/dev/null 2>&1; then
      diff="$(git -C "$ENGINE_SRC" diff --name-only origin/main "$ENGINE_SHA" -- \
        ':script/build_image_assets/10-engine' ':script/build_image_assets/11-engine-files' \
        ':script/build_image_assets/*sudoers*' 2>/dev/null || true)"
    fi
    if [ -z "$diff" ]; then
      note "sudoers_unchanged_in_pr" pass "no sudoers file differs vs origin/main at $ENGINE_SHA"
    else
      note "sudoers_unchanged_in_pr" fail "sudoers files differ: $diff"
    fi
    local drop
    drop="$(git -C "$ENGINE_SRC" show "$ENGINE_SHA:script/build_image_assets/10-idea-peer.conf" 2>/dev/null | akf_line)"
    if [ "$drop" = "$FOUR_PATH" ]; then
      note "dropin_four_path" pass "PR drop-in is the four-path AuthorizedKeysFile line"
    else
      note "dropin_four_path" fail "unexpected drop-in content"
    fi
    local got_sha
    got_sha="$(git -C "$ENGINE_SRC" rev-parse "$ENGINE_SHA" 2>/dev/null || true)"
    if [ "$got_sha" = "a8dcd3af207e2aeeaf73a3fdbc2ef087e1743a4a" ] || [ "${got_sha:0:7}" = "a8dcd3a" ]; then
      note "engine_sha" pass "$got_sha"
    else
      note "engine_sha" fail "ENGINE_SRC does not resolve $ENGINE_SHA (got ${got_sha:-none})"
    fi
  else
    note "sudoers_unchanged_in_pr" skip "ENGINE_SRC is not a git checkout"
  fi
}

# --- live helpers -----------------------------------------------------------

have_socks() {
  (echo >/dev/tcp/${SOCKS%:*}/${SOCKS#*:}) >/dev/null 2>&1
}

ensure_live_prereqs() {
  [ -d "$IDEA_REPO/.git" ] || die "IDEA_REPO not a git checkout: $IDEA_REPO"
  [ -x "$IDEA_REPO/tools/fleet/update-fleet-state.sh" ] || die "missing update-fleet-state.sh"
  # shellcheck disable=SC1091
  source "$IDEA_REPO/tools/fleet/fleet-lib.sh"
  BOX_IP="$(tailscale --socket "$TS_SOCK" ip -4 2>/dev/null | head -1 || true)"
  [ -n "$BOX_IP" ] || die "could not read box Tailscale IPv4 (is tailscaled up?)"
  is_cgnat_ipv4 "$BOX_IP" || die "box Tailscale IPv4 '$BOX_IP' is not in 100.64/10"
  have_socks || die "SOCKS proxy $SOCKS is not accepting connections"
  # A leftover SSH_CMD (e.g. from an interactive debug export) makes fl_ssh
  # expand quoted ProxyCommand incorrectly ("command-line line 0: invalid quotes").
  unset SSH_CMD
}

ssh_pi() {
  # Isolated from a leftover SSH_CMD and from ~/.ssh/config ProxyCommand stacking.
  # Same socks-connect path as documented for the box; IdentityFile is the box
  # operator key (never printed).
  ssh -F /dev/null     -o BatchMode=yes     -o IdentitiesOnly=yes     -o IdentityFile="${HOME}/.ssh/id_ed25519"     -o PreferredAuthentications=publickey     -o StrictHostKeyChecking=accept-new     -o UserKnownHostsFile="${HOME}/.ssh/known_hosts"     -o ConnectTimeout=15     -o ProxyCommand="${HOME}/.local/bin/socks-connect %h %p"     "pi@${HOST}"     "$@"
}

ssh_usage() {
  # Forced-command invocation via the throwaway usage key. Do not print keys.
  # Exit status is the remote forced-command status (or 255 on SSH refusal).
  local cmd="$1"
  ssh -F /dev/null \
    -o BatchMode=yes \
    -o IdentitiesOnly=yes \
    -o IdentityFile="$KEY" \
    -o PreferredAuthentications=publickey \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$WORK/known_hosts" \
    -o ConnectTimeout=15 \
    -o ProxyCommand="nc -X 5 -x ${SOCKS} %h %p" \
    "pi@${HOST}" \
    "$cmd"
}

fleet_push() {
  local msg="$1"
  git -C "$IDEA_REPO" add fleet-state.json audit/audit-2026.jsonl
  local extra
  extra="$(git -C "$IDEA_REPO" diff --cached --name-only | grep -vE '^(fleet-state.json|audit/audit-2026.jsonl)$' || true)"
  if [ -n "$extra" ]; then
    git -C "$IDEA_REPO" reset HEAD >/dev/null
    die "refusing to commit extra files with fleet-state: $extra"
  fi
  if git -C "$IDEA_REPO" diff --cached --quiet; then
    log "fleet-state: nothing to commit ($msg)"
    return 0
  fi
  git -C "$IDEA_REPO" commit -m "$msg"
  if [ "$PUSH_FLEET_STATE" = 1 ]; then
    git -C "$IDEA_REPO" push origin main
  else
    log "PUSH_FLEET_STATE=0: commit left local ($msg)"
  fi
}

fetch_fleet_state() {
  git -C "$IDEA_REPO" fetch origin main
  git -C "$IDEA_REPO" merge --ff-only origin/main
}

precheck_fleet() {
  local fs="$IDEA_REPO/fleet-state.json"
  [ -f "$fs" ] || die "missing $fs"
  python3 - "$fs" "$PI" <<'PY'
import json, sys
fs, pi = sys.argv[1], sys.argv[2]
data = json.load(open(fs))
if not isinstance(data, dict) or pi not in data or not isinstance(data[pi], dict):
    print(f"fleet-state has no node {pi}", file=sys.stderr)
    sys.exit(1)
node = data[pi]
claim = node.get("claim")
status = node.get("status")
role = node.get("role")
ipv4 = node.get("tailscale") or node.get("host") or ""
errs = []
if claim not in (None, "", "null"):
    errs.append(f"claim={claim!r} (want null)")
if status != "idle":
    errs.append(f"status={status!r} (want idle)")
if role and role != "spare":
    errs.append(f"role={role!r} (want spare)")
if not ipv4:
    errs.append("no tailscale/host IPv4")
print(json.dumps({"ipv4": ipv4, "status": status, "claim": claim, "role": role, "ok": not errs, "errors": errs}))
sys.exit(0 if not errs else 1)
PY
}

read_node_ipv4() {
  python3 - "$IDEA_REPO/fleet-state.json" "$PI" <<'PY'
import json, sys
fs, pi = sys.argv[1], sys.argv[2]
data = json.load(open(fs))
node = data.get(pi) or {}
print(node.get("tailscale") or node.get("host") or "")
PY
}

claim_pi() {
  BOT_NAME="$BOT_NAME" "$IDEA_REPO/tools/fleet/update-fleet-state.sh" "$PI" status testing
  BOT_NAME="$BOT_NAME" "$IDEA_REPO/tools/fleet/update-fleet-state.sh" "$PI" claim \
    "idea#416 helper v7 proof of engine PR #309 @ ${ENGINE_SHA:0:7}"
  CLAIMED=1
  fleet_push "fleet-state: Atlas claims ${PI} for idea#416 helper v7 proof"
}

release_pi() {
  BOT_NAME="$BOT_NAME" "$IDEA_REPO/tools/fleet/update-fleet-state.sh" --null "$PI" claim
  BOT_NAME="$BOT_NAME" "$IDEA_REPO/tools/fleet/update-fleet-state.sh" "$PI" status idle
  RELEASED=1
  fleet_push "fleet-state: Atlas releases ${PI} after idea#416 helper v7 proof"
}

precheck_pi() {
  local ver temp status porcelain
  ver="$(ssh_pi "sudo -n $HELPER version" | tr -d '\r' | tail -n1)"
  if [ "$ver" != "idea-app-data 5" ]; then
    note "precheck_helper_v5" fail "installed helper reports '${ver}' (want idea-app-data 5)"
    return 1
  fi
  note "precheck_helper_v5" pass "idea-app-data 5"
  porcelain="$(ssh_pi "git -C $ENGINE_DIR status --porcelain --untracked-files=no" || true)"
  unexpected="$(printf '%s\n' "$porcelain" | python3 -c '
import sys, re
ok = re.compile(r"^[ M][M ] (config\.yaml|pm2\.config\.cjs|store-identity/command-log-url\.txt|store-identity/store-url\.txt)$")
lines = [ln for ln in sys.stdin.read().splitlines() if ln.strip()]
bad = [ln for ln in lines if not ok.match(ln)]
print("\n".join(bad))
')"
  if [ -n "$unexpected" ]; then
    note "precheck_engine_clean" fail "unexpected tracked changes in $ENGINE_DIR; refusing checkout"
    return 1
  fi
  if [ -n "$porcelain" ]; then
    note "precheck_engine_clean" pass "only allowed local identity/config files are dirty (will backup+restore across checkout)"
  else
    note "precheck_engine_clean" pass "no tracked changes in Engine checkout"
  fi
  temp="$(ssh_pi "vcgencmd measure_temp 2>/dev/null || true" | tr -d '\r')"
  # temp looks like temp=42.1'C
  local c
  c="$(printf '%s' "$temp" | sed -n "s/.*temp=\([0-9.]*\).*/\1/p")"
  if [ -n "$c" ]; then
    python3 -c "import sys; sys.exit(0 if float('$c') <= 75 else 1)" || {
      note "precheck_temp" fail "SoC ${c} C is above 75 C; pause"
      return 1
    }
    note "precheck_temp" pass "SoC ${c} C"
  else
    note "precheck_temp" skip "vcgencmd not available"
  fi
}

backup_pi() {
  BACKUP_DIR="/home/pi/idea416-v5-backup-${STAMP}"
  ssh_pi "set -euo pipefail
    mkdir -p '$BACKUP_DIR'
    sudo cp -a '$HELPER' '$BACKUP_DIR/idea-app-data'
    sudo cp -a '$DROPIN' '$BACKUP_DIR/10-idea-peer.conf'
    sudo cp -a '$SUDOERS_10' '$BACKUP_DIR/10-engine'
    sudo cp -a '$SUDOERS_11' '$BACKUP_DIR/11-engine-files'
    if [ -e '$EXPORT_BIN' ]; then sudo cp -a '$EXPORT_BIN' '$BACKUP_DIR/idea-usage-export'; fi
    if [ -e '$USAGE_FILE' ]; then sudo cp -a '$USAGE_FILE' '$BACKUP_DIR/idea_usage_keys-pi'; fi
    git -C '$ENGINE_DIR' rev-parse HEAD > '$BACKUP_DIR/engine.sha'
    git -C '$ENGINE_DIR' rev-parse --abbrev-ref HEAD > '$BACKUP_DIR/engine.branch' || true
    hostname > '$BACKUP_DIR/hostname'
    sudo sha256sum '$HELPER' '$DROPIN' '$SUDOERS_10' '$SUDOERS_11' > '$BACKUP_DIR/hashes.txt'
    mkdir -p '$BACKUP_DIR/engine-local/store-identity'
    for f in config.yaml pm2.config.cjs store-identity/command-log-url.txt store-identity/store-url.txt; do
      if [ -e '$ENGINE_DIR'/"\$f" ]; then
        cp -a '$ENGINE_DIR'/"\$f" '$BACKUP_DIR/engine-local'/"\$f"
      fi
    done
    (cd '$ENGINE_DIR' && sha256sum config.yaml pm2.config.cjs store-identity/command-log-url.txt store-identity/store-url.txt) > '$BACKUP_DIR/engine-local.hashes'
    git -C '$ENGINE_DIR' status --porcelain --untracked-files=no > '$BACKUP_DIR/engine.porcelain' || true
    mkdir -p '$BACKUP_DIR/pre-usage'
    record_pre() {
      local name="\$1" path="\$2"
      if [ -e "\$path" ] || [ -L "\$path" ]; then
        echo PRESENT > '$BACKUP_DIR/pre-usage'/"\$name".state
      else
        echo ABSENT > '$BACKUP_DIR/pre-usage'/"\$name".state
      fi
    }
    record_pre usage_root /var/lib/idea/usage
    record_pre run_idea /run/idea
    record_pre tmpfiles /etc/tmpfiles.d/idea-usage.conf
  "
  PRE_SHA="$(ssh_pi "cat '$BACKUP_DIR/engine.sha'" | tr -d '\r')"
  PRE_BRANCH="$(ssh_pi "cat '$BACKUP_DIR/engine.branch'" | tr -d '\r')"
  [ -n "$PRE_SHA" ] || die "failed to record Engine SHA"
  note "backup" pass "$BACKUP_DIR (engine ${PRE_SHA:0:7}, branch ${PRE_BRANCH:-?})"
}

restore_local_engine_files() {
  ssh_pi "set -euo pipefail
    test -d '$BACKUP_DIR/engine-local'
    for f in config.yaml pm2.config.cjs store-identity/command-log-url.txt store-identity/store-url.txt; do
      if [ -e '$BACKUP_DIR/engine-local'/"\$f" ]; then
        cp -a '$BACKUP_DIR/engine-local'/"\$f" '$ENGINE_DIR'/"\$f"
      fi
    done
    (cd '$ENGINE_DIR' && sha256sum config.yaml pm2.config.cjs store-identity/command-log-url.txt store-identity/store-url.txt) > /tmp/idea416-engine-local.hashes
    cmp -s '$BACKUP_DIR/engine-local.hashes' /tmp/idea416-engine-local.hashes
    mv /tmp/idea416-engine-local.hashes /tmp/idea416-engine-local.hashes.quarantine-'$STAMP'
  "
}

clear_local_engine_files_for_checkout() {
  # Temporarily revert allowed local files to HEAD so git checkout can switch
  # SHAs. Not reset --hard; live copies already sit in BACKUP_DIR.
  ssh_pi "set -euo pipefail
    cd '$ENGINE_DIR'
    git checkout -- config.yaml pm2.config.cjs store-identity/command-log-url.txt store-identity/store-url.txt
  "
}

install_v7() {
  MUTATED=1
  clear_local_engine_files_for_checkout
  ssh_pi "set -euo pipefail
    cd '$ENGINE_DIR'
    git fetch origin '$ENGINE_BRANCH' \
      || git fetch origin '$ENGINE_SHA' \
      || git fetch origin pull/309/head
    got=\$(git rev-parse --verify '${ENGINE_SHA}^{commit}')
    test \"\$got\" = '$ENGINE_SHA'
    git checkout --detach '$ENGINE_SHA'
  "
  restore_local_engine_files
  note "local_engine_overrides_after_v7_checkout" pass "restored config.yaml / pm2.config.cjs / store-identity after ${ENGINE_SHA:0:7} checkout"
  ssh_pi "set -euo pipefail
    cd '$ENGINE_DIR'
    ./install-root-helpers
    gotver=\$(sudo -n '$HELPER' version | tr -d '\r' | tail -n1)
    test \"\$gotver\" = 'idea-app-data 7'
  "
  note "install_root_helpers" pass "checkout ${ENGINE_SHA:0:7} and idea-app-data 7"
  ssh_pi "set -euo pipefail
    cd '$ENGINE_DIR'
    pnpm build
    pm2 restart engine
    pm2 save
  "
  note "deploy_engine" pass "pnpm build + pm2 restart engine + pm2 save (as pi)"
}

prove_installed_bits() {
  local ver mode drop owners
  ver="$(ssh_pi "sudo -n $HELPER version" | tr -d '\r' | tail -n1)"
  if [ "$ver" = "idea-app-data 7" ]; then
    note "version_7" pass "$ver"
  else
    note "version_7" fail "got '$ver'"
  fi
  drop="$(ssh_pi "sudo cat $DROPIN" | akf_line)"
  if [ "$drop" = "$FOUR_PATH" ]; then
    note "dropin_four_path_live" pass "AuthorizedKeysFile includes idea_usage_keys/%u"
  else
    note "dropin_four_path_live" fail "drop-in is not the four-path line"
  fi
  owners="$(ssh_pi "stat -c '%U:%G %a %n' $EXPORT_BIN $HELPER")"
  if printf '%s\n' "$owners" | grep -q "root:root 755 $EXPORT_BIN" \
     && printf '%s\n' "$owners" | grep -q "root:root 755 $HELPER"; then
    note "export_bin_perms" pass "export and helper are root:root 0755"
  else
    note "export_bin_perms" fail "$owners"
  fi
  local akf
  akf="$(ssh_pi "sudo /usr/sbin/sshd -T -C user=pi,host=localhost,addr=127.0.0.1 | awk '/^authorizedkeysfile /{print}'")"
  if printf '%s' "$akf" | grep -q 'idea_authorized_keys/%u' \
     && printf '%s' "$akf" | grep -q 'idea_usage_keys/%u'; then
    note "sshd_akf" pass "sshd -T lists both extra AuthorizedKeysFile paths"
  else
    note "sshd_akf" fail "$akf"
  fi
  local tmpf usage_stat run_stat
  tmpf="$(ssh_pi "stat -c '%U:%G %a %n' $USAGE_TMPFILES 2>/dev/null || echo ABSENT")"
  if printf '%s' "$tmpf" | grep -q "root:root 644 $USAGE_TMPFILES"; then
    note "usage_tmpfiles_installed" pass "idea-usage.conf is root:root 0644"
  else
    note "usage_tmpfiles_installed" fail "$tmpf"
  fi
  usage_stat="$(ssh_pi "stat -c '%U:%G %a %n' $USAGE_ROOT_LIVE 2>/dev/null || echo ABSENT")"
  if printf '%s' "$usage_stat" | grep -q "pi:pi 750 $USAGE_ROOT_LIVE"; then
    note "usage_root_created" pass "/var/lib/idea/usage is pi:pi 0750 (created by installRootHelpers)"
  else
    note "usage_root_created" fail "$usage_stat"
  fi
  run_stat="$(ssh_pi "stat -c '%U:%G %a %n' $RUN_IDEA 2>/dev/null || echo ABSENT")"
  if printf '%s' "$run_stat" | grep -q "pi:pi 755 $RUN_IDEA"; then
    note "run_idea_created" pass "/run/idea is pi:pi 0755 (created by tmpfiles)"
  else
    note "run_idea_created" fail "$run_stat"
  fi
}

prove_cgnat_rejects() {
  # Generate the throwaway key first so RE_KEY64 is a real blob; never print it.
  ssh-keygen -t ed25519 -N '' -f "$KEY" -C "idea416-v7-proof-${STAMP}" >/dev/null
  PUB64="$(awk '{print $2}' "$KEY.pub")"
  [[ "$PUB64" == AAAAC3NzaC1lZDI1NTE5AAAAI* ]] || die "throwaway pubkey field 2 is not an ed25519 blob"
  local before after ip rc
  before="$(ssh_pi "sudo sha256sum $USAGE_FILE 2>/dev/null || echo ABSENT; sudo sha256sum $DROPIN")"
  local bad_ips=(8.8.8.8 10.42.0.1 127.0.0.1 192.168.1.1 100.63.255.255 100.128.0.1 1.2.3.4)
  for ip in "${bad_ips[@]}"; do
    set +e
    ssh_pi "sudo -n $HELPER install-usage-key '$ip' ssh-ed25519 '$PUB64'" >"$WORK/cgnat.out" 2>"$WORK/cgnat.err"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
      note "cgnat_live_reject_${ip}" fail "helper accepted non-CGNAT $ip"
    else
      note "cgnat_live_reject_${ip}" pass "helper refused $ip (rc=$rc)"
    fi
  done
  # Also refuse a pre-built options string passed as the ipv4 slot.
  set +e
  ssh_pi "sudo -n $HELPER install-usage-key 'restrict,from=\"8.8.8.8\"' ssh-ed25519 '$PUB64'" \
    >"$WORK/cgnat.out" 2>"$WORK/cgnat.err"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    note "cgnat_live_reject_options_string" fail "helper accepted a prebuilt restrict line as ipv4"
  else
    note "cgnat_live_reject_options_string" pass "helper refused a caller-supplied options string"
  fi
  after="$(ssh_pi "sudo sha256sum $USAGE_FILE 2>/dev/null || echo ABSENT; sudo sha256sum $DROPIN")"
  if [ "$before" = "$after" ]; then
    note "cgnat_rejects_leave_files" pass "usage key file and drop-in unchanged after refused installs"
  else
    note "cgnat_rejects_leave_files" fail "files changed after refused install-usage-key calls"
  fi
}

prove_install_usage_key() {
  local rc line_ok owners
  set +e
  ssh_pi "sudo -n $HELPER install-usage-key '$BOX_IP' ssh-ed25519 '$PUB64'" \
    >"$WORK/install-key.out" 2>"$WORK/install-key.err"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    note "install_usage_key" fail "rc=$rc err=$(tr '\n' ' ' < "$WORK/install-key.err" | cut -c1-160)"
    return 1
  fi
  # Verify constructed options without printing the key blob.
  line_ok="$(printf '%s\n' "$BOX_IP" | ssh_pi "sudo python3 -c '
import sys, pathlib
ip = sys.stdin.read().strip()
line = pathlib.Path(\"$USAGE_FILE\").read_text().splitlines()[0]
prefix = f\"restrict,from=\\\"{ip}\\\",command=\\\"/usr/local/sbin/idea-usage-export\\\" ssh-ed25519 \"
suffix = \" idea-usage\"
ok = line.startswith(prefix) and line.endswith(suffix)
blob = line[len(prefix):-len(suffix)] if ok else \"\"
print(\"OK\" if ok and blob.startswith(\"AAAAC3NzaC1lZDI1NTE5AAAAI\") else \"BAD\")
'")"
  owners="$(ssh_pi "stat -c '%U:%G %a' $USAGE_FILE")"
  if [ "$line_ok" = "OK" ] && [ "$owners" = "root:root 644" ]; then
    note "install_usage_key" pass "constructed restrict,from=${BOX_IP},command=... line; file root:root 0644"
  else
    note "install_usage_key" fail "constructed-line=${line_ok} owners=${owners}"
  fi
}

prove_ssh_verbs() {
  local rc out err
  # Allowed: since (pool trees are typically disabled / empty — exit 0 or 10 are both valid v7).
  set +e
  out="$(ssh_usage "since 2026-01-01" 2>"$WORK/since.err")"
  rc=$?
  set -e
  err="$(cat "$WORK/since.err" 2>/dev/null || true)"
  if [ "$rc" = 0 ] && validate_since_stream "$out" "2026-01-01" >/dev/null; then
    note "ssh_since" pass "forced-command since streamed an end marker (real or empty usage data)"
  elif [ "$rc" = 10 ] && [ -z "$out" ] && [[ "$err" == *disabled* ]]; then
    note "ssh_since" pass "forced-command since: usageMonitoring off/missing (exit 10 disabled) — valid v7"
  else
    note "ssh_since" fail "rc=$rc err=$(printf '%s' "$err" | tr '\n' ' ' | cut -c1-160)"
  fi

  # Allowed: archive-and-clear --before 2000-01-01 (nothing strictly before 2000; does not move real data).
  set +e
  out="$(ssh_usage "archive-and-clear --before 2000-01-01" 2>"$WORK/arch.err")"
  rc=$?
  set -e
  err="$(cat "$WORK/arch.err" 2>/dev/null || true)"
  if [ "$rc" = 0 ] && validate_archived "$out" "2000-01-01" >/dev/null; then
    note "ssh_archive_noop" pass "forced-command archive-and-clear --before 2000-01-01 (no-op)"
  elif [ "$rc" = 10 ] && [ -z "$out" ] && [[ "$err" == *disabled* ]]; then
    note "ssh_archive_noop" pass "forced-command archive: disabled (exit 10) — valid v7, live tree untouched"
  else
    note "ssh_archive_noop" fail "rc=$rc err=$(printf '%s' "$err" | tr '\n' ' ' | cut -c1-160)"
  fi

  # a8dcd3a allowed form: archive-and-clear --before=2000-01-01
  set +e
  out="$(ssh_usage "archive-and-clear --before=2000-01-01" 2>"$WORK/arch-eq.err")"
  rc=$?
  set -e
  err="$(cat "$WORK/arch-eq.err" 2>/dev/null || true)"
  if [ "$rc" = 0 ] && validate_archived "$out" "2000-01-01" >/dev/null; then
    note "ssh_archive_noop_before_eq" pass "forced-command archive-and-clear --before=2000-01-01 (no-op)"
  elif [ "$rc" = 10 ] && [ -z "$out" ] && [[ "$err" == *disabled* ]]; then
    note "ssh_archive_noop_before_eq" pass "forced-command archive equals-form: disabled (exit 10) — valid v7, live tree untouched"
  else
    note "ssh_archive_noop_before_eq" fail "rc=$rc err=$(printf '%s' "$err" | tr '\n' ' ' | cut -c1-160)"
  fi

  local bad
  for bad in "id" "" "since 2026-01-01;id" "uname -a" "archive-and-clear --before 2026-03-01;id"; do
    set +e
    out="$(ssh_usage "$bad" 2>"$WORK/bad.err")"
    rc=$?
    set -e
    err="$(cat "$WORK/bad.err" 2>/dev/null || true)"
    local slug
    slug="$(printf '%s' "${bad:-empty}" | tr ' \n;&' '____' | cut -c1-40)"
    if [ "$rc" = 2 ] && [[ "$err" == *invalid\ arguments* ]]; then
      note "ssh_refuse_${slug}" pass "exit 2 invalid arguments"
    else
      note "ssh_refuse_${slug}" fail "rc=$rc err=$(printf '%s' "$err" | tr '\n' ' ' | cut -c1-160)"
    fi
  done
}

prove_wrong_source() {
  # Copy the private key to a temp file on the Pi via stdin (never argv) and
  # ssh to pi@127.0.0.1 so from= sees 127.0.0.1, not the box CGNAT address.
  # Capture rc OUTSIDE any $(...) assignment.
  local remote_key="/tmp/idea416-v7-wrongsrc-${STAMP}"
  base64 -w0 "$KEY" | ssh_pi "base64 -d > '$remote_key' && chmod 600 '$remote_key'"
  set +e
  ssh_pi "ssh -F /dev/null -o BatchMode=yes -o IdentitiesOnly=yes -o IdentityFile='$remote_key' \
    -o PreferredAuthentications=publickey -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 \
    pi@127.0.0.1 since 2026-01-01" \
    >"$WORK/wrong.out" 2>"$WORK/wrong.err"
  local src_rc=$?
  set -e
  ssh_pi "mv '$remote_key' '${remote_key}.quarantine-${STAMP}' 2>/dev/null || true"
  if [ "$src_rc" != 0 ]; then
    note "ssh_wrong_source" pass "loopback usage-key SSH refused (rc=$src_rc); from= pinned to box IP"
  else
    note "ssh_wrong_source" fail "loopback usage-key SSH unexpectedly succeeded"
  fi
}

prove_export_format_on_pi() {
  local fix="/tmp/idea416-v7-fixture-${STAMP}"
  ssh_pi "python3 - <<'PY'
from pathlib import Path
root = Path('$fix')
if root.exists():
    raise SystemExit(f'fixture path already exists: {root}')
for rel in ('2026-02-15', '2026-03-01', '2026-03-02', '.archive/should-not-read'):
    (root / rel).mkdir(parents=True)
(root / 'settings.json').write_text('{\"usageMonitoring\":\"on\"}\\n')
(root / '2026-02-15/old-inst.json').write_text('{\"schema\":\"idea-usage-day/1\",\"instance\":\"old-inst\",\"day\":\"2026-02-15\"}\\n')
(root / '2026-03-01/presence.ndjson').write_text('{\"schema\":\"idea-usage-presence/1\",\"ts\":\"2026-03-01T08:00:00+00:00\",\"kind\":\"sample\"}\\n')
(root / '2026-03-01/inst-a.json').write_text('{\"schema\":\"idea-usage-day/1\",\"instance\":\"inst-a\",\"day\":\"2026-03-01\"}\\n')
(root / '2026-03-01/inst-a.samples.ndjson').write_text('{\"schema\":\"idea-usage-sample/1\",\"ts\":\"2026-03-01T08:05:00+00:00\",\"instance\":\"inst-a\"}\\n')
(root / '2026-03-02/inst-b.json').write_text('{\"schema\":\"idea-usage-day/1\",\"instance\":\"inst-b\",\"day\":\"2026-03-02\"}\\n')
print(root)
PY"
  local out rc
  set +e
  out="$(ssh_pi "env -u SSH_ORIGINAL_COMMAND IDEA_USAGE_ROOT='$fix' IDEA_USAGE_ENGINE='idea416-proof' $EXPORT_BIN since 2026-03-01")"
  rc=$?
  set -e
  if [ "$rc" = 0 ] && validate_since_stream "$out" "2026-03-01" >/dev/null \
     && ! printf '%s\n' "$out" | grep -q 2026-02-15; then
    note "format_since_fixture" pass "installed export: since stream format against fixture"
  else
    note "format_since_fixture" fail "rc=$rc (format proof via IDEA_USAGE_ROOT; live /var/lib/idea/usage untouched)"
  fi
  set +e
  out="$(ssh_pi "env -u SSH_ORIGINAL_COMMAND IDEA_USAGE_ROOT='$fix' $EXPORT_BIN archive-and-clear --before 2026-03-01")"
  rc=$?
  set -e
  if [ "$rc" = 0 ] && validate_archived "$out" "2026-03-01" >/dev/null; then
    note "format_archive_fixture" pass "installed export: archived object against fixture"
  else
    note "format_archive_fixture" fail "rc=$rc out=$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-160)"
  fi
  ssh_pi "mv '$fix' '${fix}.quarantine-${STAMP}'"
}

# Fail-closed checks for idea#422. Callable from tests with canned values
# (no SSH). Prints a clear ERROR and returns 1 if any restore step mismatches.
assert_rollback_state() {
  local ver="${1:-}" drop="${2:-}" sha="${3:-}" pm2="${4:-}"
  local errors=()
  if [ "$ver" != "idea-app-data 5" ]; then
    errors+=("helper is '${ver:-unset}', expected idea-app-data 5")
  fi
  if [ "$drop" != "$THREE_PATH" ]; then
    errors+=("drop-in AuthorizedKeysFile is not the pre-proof three-path line")
  fi
  if [ -z "${PRE_SHA:-}" ]; then
    errors+=("PRE_SHA is empty; cannot verify Engine checkout")
  else
    case "$sha" in
      "$PRE_SHA"|${PRE_SHA:0:7}*) ;;
      *) errors+=("Engine HEAD is '${sha:-unset}', expected pre-SHA ${PRE_SHA}") ;;
    esac
  fi
  if [ "$pm2" != "online" ]; then
    errors+=("pm2 engine status is '${pm2:-unset}', expected online")
  fi
  if [ "${#errors[@]}" -gt 0 ]; then
    echo "ERROR: rollback incomplete:" >&2
    local e
    for e in "${errors[@]}"; do
      echo "  - $e" >&2
    done
    return 1
  fi
  return 0
}

# Static guard: rollback_pi must still contain the restore steps a truncated
# patch previously dropped (drop-in, visudo/sshd, checkout, override restore,
# fail-closed assertions). Used by --self-test and prove-helper-v7.test.sh.
check_rollback_pi_integrity() {
  local src="${1:-$SCRIPT_DIR/prove-helper-v7.sh}"
  python3 - "$src" <<'INTEG'
import pathlib, re, sys, subprocess, tempfile, os
text = pathlib.Path(sys.argv[1]).read_text()
m = re.search(r"^rollback_pi\(\) \{", text, re.M)
if not m:
    print("MISSING_FUNCTION rollback_pi")
    sys.exit(1)
rest = text[m.start():]
m2 = re.search(r"\nhealth_check\(\) \{", rest)
body = rest[: m2.start()] if m2 else rest
if not m2:
    print("MISSING health_check after rollback_pi (function looks truncated)")
    sys.exit(1)
need = [
    "10-idea-peer.conf",
    "visudo",
    "sshd -t",
    "git checkout --detach",
    "restore_local_engine_files",
    "assert_rollback_state",
    "rev-parse",
    "pm2",
]
missing = [n for n in need if n not in body]
if re.search(r"(^|[\s;])ocal_engine_overrides", body):
    missing.append("truncated-fragment ocal_engine_overrides")
if missing:
    print("rollback_pi is missing required restore steps: " + ", ".join(missing))
    sys.exit(1)
with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as fh:
    fh.write("#!/usr/bin/env bash\n" + body + "\n")
    path = fh.name
try:
    r = subprocess.run(["bash", "-n", path], capture_output=True, text=True)
    if r.returncode != 0:
        print("rollback_pi failed bash -n:\n" + (r.stderr or r.stdout))
        sys.exit(1)
finally:
    os.unlink(path)
print("OK")
INTEG
}

rollback_pi() {
  local q="/home/pi/idea416-v7-quarantine-${STAMP}"
  ssh_pi "set -euo pipefail
    mkdir -p '$q'
    if [ -e '$HELPER' ]; then sudo mv '$HELPER' '$q/idea-app-data'; fi
    if [ -e '$EXPORT_BIN' ]; then sudo mv '$EXPORT_BIN' '$q/idea-usage-export'; fi
    if [ -e '$USAGE_FILE' ]; then sudo mv '$USAGE_FILE' '$q/idea_usage_keys-pi'; fi
    if [ -e '$DROPIN' ]; then sudo mv '$DROPIN' '$q/10-idea-peer.conf'; fi
    pre='$BACKUP_DIR/pre-usage'
    report='$q/usage-quarantine-report.txt'
    : > \"\$report\"
    is_test_only_dir() {
      local path=\"\$1\"
      [ -e \"\$path\" ] || return 0
      [ ! -L \"\$path\" ] || return 1
      local f rel
      while IFS= read -r -d '' f; do
        if [ -L \"\$f\" ]; then
          return 1
        fi
        rel=\"\${f#\\\"\$path\\\"/}\"
        if [ -f \"\$f\" ] && [ \"\$rel\" != settings.json ]; then
          return 1
        fi
      done < <(sudo find \"\$path\" -mindepth 1 -print0)
      return 0
    }
    if [ -f \"\$pre/tmpfiles.state\" ] && grep -qx ABSENT \"\$pre/tmpfiles.state\"; then
      if [ -e /etc/tmpfiles.d/idea-usage.conf ] || [ -L /etc/tmpfiles.d/idea-usage.conf ]; then
        sudo mv -- /etc/tmpfiles.d/idea-usage.conf '$q/idea-usage.conf'
        echo 'quarantined /etc/tmpfiles.d/idea-usage.conf' >> \"\$report\"
      else
        echo 'already absent /etc/tmpfiles.d/idea-usage.conf' >> \"\$report\"
      fi
    else
      echo 'left /etc/tmpfiles.d/idea-usage.conf (existed before install or no marker)' >> \"\$report\"
    fi
    if [ -f \"\$pre/usage_root.state\" ] && grep -qx ABSENT \"\$pre/usage_root.state\"; then
      if [ -e /var/lib/idea/usage ] || [ -L /var/lib/idea/usage ]; then
        if is_test_only_dir /var/lib/idea/usage; then
          sudo mv -- /var/lib/idea/usage '$q/var-lib-idea-usage'
          echo 'quarantined /var/lib/idea/usage' >> \"\$report\"
        else
          echo 'UNSAFE /var/lib/idea/usage: not empty/test-only; left in place' >> \"\$report\"
          exit 2
        fi
      else
        echo 'already absent /var/lib/idea/usage' >> \"\$report\"
      fi
    else
      echo 'left /var/lib/idea/usage (existed before install or no marker)' >> \"\$report\"
    fi
    if [ -f \"\$pre/run_idea.state\" ] && grep -qx ABSENT \"\$pre/run_idea.state\"; then
      if [ -e /run/idea ] || [ -L /run/idea ]; then
        if is_test_only_dir /run/idea; then
          sudo mv -- /run/idea '$q/run-idea'
          echo 'quarantined /run/idea' >> \"\$report\"
        else
          echo 'UNSAFE /run/idea: not empty/test-only; left in place' >> \"\$report\"
          exit 2
        fi
      else
        echo 'already absent /run/idea' >> \"\$report\"
      fi
    else
      echo 'left /run/idea (existed before install or no marker)' >> \"\$report\"
    fi
    sudo install -o root -g root -m 0755 '$BACKUP_DIR/idea-app-data' '$HELPER'
    sudo install -o root -g root -m 0644 '$BACKUP_DIR/10-idea-peer.conf' '$DROPIN'
    sudo install -o root -g root -m 0440 '$BACKUP_DIR/10-engine' '$SUDOERS_10'
    sudo install -o root -g root -m 0440 '$BACKUP_DIR/11-engine-files' '$SUDOERS_11'
    sudo visudo -c
    sudo visudo -cf '$SUDOERS_10'
    sudo visudo -cf '$SUDOERS_11'
    sudo /usr/sbin/sshd -t
    sudo systemctl reload ssh || sudo systemctl reload sshd
    cd '$ENGINE_DIR'
    git checkout -- config.yaml pm2.config.cjs store-identity/command-log-url.txt store-identity/store-url.txt
    git checkout --detach '$PRE_SHA'
  "
  restore_local_engine_files
  note "local_engine_overrides_after_rollback_checkout" pass "restored config.yaml / pm2.config.cjs / store-identity after ${PRE_SHA:0:7} checkout"
  ssh_pi "set -euo pipefail
    cd '$ENGINE_DIR'
    pnpm build
    pm2 restart engine
    pm2 save
  "
  ROLLED_BACK=1
  local ver drop sha pm2 urep usage_now run_now conf_now
  ver="$(ssh_pi "sudo -n $HELPER version" | tr -d '\r' | tail -n1)"
  drop="$(ssh_pi "sudo cat $DROPIN" | akf_line)"
  sha="$(ssh_pi "git -C $ENGINE_DIR rev-parse HEAD" | tr -d '\r' | tail -n1)"
  pm2="$(ssh_pi "pm2 jlist" | python3 -c 'import json,sys
try:
    procs=json.load(sys.stdin)
except Exception:
    print("unreadable")
    raise SystemExit
p=next((x for x in procs if x.get("name")=="engine"), None)
print("missing" if not p else ((p.get("pm2_env") or {}).get("status") or "unknown"))
')"
  urep="$(ssh_pi "cat '$q/usage-quarantine-report.txt' 2>/dev/null || echo missing")"
  usage_now="$(ssh_pi "if [ -e $USAGE_ROOT_LIVE ]; then echo PRESENT; else echo ABSENT; fi")"
  run_now="$(ssh_pi "if [ -e $RUN_IDEA ]; then echo PRESENT; else echo ABSENT; fi")"
  conf_now="$(ssh_pi "if [ -e $USAGE_TMPFILES ]; then echo PRESENT; else echo ABSENT; fi")"
  note "rollback_usage_paths" pass "usage=$usage_now run_idea=$run_now tmpfiles=$conf_now; $urep"
  if assert_rollback_state "$ver" "$drop" "$sha" "$pm2"; then
    note "rollback" pass "helper v5, three-path drop-in, Engine ${sha:0:7}, pm2 engine $pm2; v7 files at $q"
    return 0
  fi
  note "rollback" fail "helper='$ver' sha='${sha:-unset}' pm2='${pm2:-unset}' drop-in three-path? $([[ "$drop" = "$THREE_PATH" ]] && echo yes || echo no)"
  return 1
}



health_check() {
  local ver rc
  set +e
  ssh_pi "true"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    note "health_operator_ssh" pass "operator SSH works after rollback"
  else
    note "health_operator_ssh" fail "operator SSH rc=$rc"
  fi
  ver="$(ssh_pi "sudo -n $HELPER version" | tr -d '\r' | tail -n1 || true)"
  if [ "$ver" = "idea-app-data 5" ]; then
    note "health_helper_v5" pass "$ver"
  else
    note "health_helper_v5" fail "got '$ver'"
  fi
  set +e
  ssh_pi "pm2 describe engine >/dev/null"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    note "health_engine" pass "pm2 describe engine succeeded"
  else
    note "health_engine" fail "pm2 describe engine rc=$rc"
  fi
  local code
  set +e
  code="$(ssh_pi "curl -fsS -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/")"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ] && [ "$code" = "200" ]; then
    note "health_console" pass "console :8080 returned 200"
  else
    note "health_console" fail "console :8080 rc=$rc code=${code:-none}"
  fi
  # Never --alert (would create/remove PAUSED). Best-effort; do not fail the
  # whole proof if the wrapper is missing, but record the outcome.
  if [ -x "$IDEA_REPO/tools/fleet/check-fleet-health.sh" ]; then
    local wrap="$WORK/socks-ssh"
    cat > "$wrap" <<EOF
#!/usr/bin/env bash
exec ssh -o ProxyCommand="nc -X 5 -x ${SOCKS} %h %p" "\$@"
EOF
    chmod 700 "$wrap"
    set +e
    SSH_BIN="$wrap" "$IDEA_REPO/tools/fleet/check-fleet-health.sh" --pi "$PI" >/dev/null 2>"$WORK/health.err"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
      note "health_fleet" pass "check-fleet-health --pi $PI (no --alert) exited 0"
    else
      note "health_fleet" fail "check-fleet-health rc=$rc (no --alert was passed)"
    fi
  else
    note "health_fleet" skip "check-fleet-health.sh not found"
  fi
}

cleanup() {
  local rc=$?
  [ "$EXITING" = 1 ] && return 0
  EXITING=1
  if [ "$MODE" = "live" ]; then
    if [ "$MUTATED" = 1 ] && [ "$ROLLED_BACK" != 1 ]; then
      rollback_pi || log "WARNING: rollback_pi failed during cleanup"
    fi
    if [ "$CLAIMED" = 1 ] && [ "$RELEASED" != 1 ]; then
      release_pi || log "WARNING: release_pi failed during cleanup"
    fi
  fi
  if [ -n "$WORK" ] && [ -d "$WORK" ]; then
    mv "$WORK" "${WORK}.quarantine-${STAMP}" 2>/dev/null || true
    WORK="${WORK}.quarantine-${STAMP}"
  fi
  if [ -n "${OUT_JSON:-}" ]; then
    write_json "$OUT_JSON" || true
    if [ -d /workspace/idea416 ]; then
      ln -sfn "$(basename "$OUT_JSON")" /workspace/idea416/prove-helper-v7-last.json 2>/dev/null || true
    fi
    log "JSON summary: $OUT_JSON"
  fi
  exit "$rc"
}

run_live() {
  ensure_live_prereqs
  fetch_fleet_state
  local view
  if view="$(precheck_fleet)"; then
    note "precheck_fleet" pass "$view"
  else
    note "precheck_fleet" fail "${view:-not idle/unclaimed in latest fleet-state}"
    die "refusing to claim $PI (see precheck_fleet)"
  fi
  HOST="$(read_node_ipv4)"
  [ -n "$HOST" ] || die "fleet-state has no IPv4 for $PI"
  note "precheck_host" pass "$PI is $HOST"
  precheck_pi || die "precheck_pi failed"
  claim_pi
  note "claim" pass "BOT_NAME=$BOT_NAME claimed $PI"
  backup_pi
  install_v7
  prove_installed_bits
  prove_cgnat_rejects
  prove_install_usage_key
  prove_ssh_verbs
  prove_wrong_source
  prove_export_format_on_pi
  note "pnpm_test_full" skip "checklist comment 6779343720 does not ask for pnpm test:full on a Pi (Axle ran 9 vitest files / 211 passed on the box; test:full previously hung idea04)"
  note "sync_peers" skip "not run: sync-peers rewrites /etc/ssh/idea_authorized_keys/pi"
  if ! rollback_pi; then
    log "rollback_pi reported a mismatch; running health_check and release anyway"
  fi
  health_check
  release_pi
  note "release" pass "claim cleared, status idle"
}

main() {
  parse_args "$@"
  WORK="$(mktemp -d /tmp/idea416-v7.XXXXXX)"
  chmod 700 "$WORK"
  KEY="$WORK/idea416-usage-proof"
  trap cleanup EXIT

  case "$MODE" in
    self-test)
      if out="$(check_rollback_pi_integrity)"; then
        note "rollback_pi_integrity" pass "$out"
      else
        note "rollback_pi_integrity" fail "$out"
      fi
      run_offline_fleetstate_parse
      run_offline_cgnat_tests
      run_offline_helper_parse_tests
      run_offline_export_tests
      ;;
    dry-run)
      print_plan
      note "dry_run_parse" pass "accepted --pi $PI; live actions disabled"
      if out="$(check_rollback_pi_integrity)"; then
        note "rollback_pi_integrity" pass "$out"
      else
        note "rollback_pi_integrity" fail "$out"
      fi
      run_offline_fleetstate_parse
      run_offline_cgnat_tests
      run_offline_helper_parse_tests
      run_offline_export_tests
      note "no_pi_touch" pass "dry-run did not SSH, claim, or write fleet-state"
      ;;
    live)
      print_plan
      run_live
      ;;
  esac

  if [ "$OVERALL" -eq 0 ]; then
    log "ALL STEPS PASSED (mode=$MODE)"
  else
    log "SOME STEPS FAILED (mode=$MODE); see $OUT_JSON"
  fi
  exit "$OVERALL"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
