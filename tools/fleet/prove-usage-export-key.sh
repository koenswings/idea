#!/usr/bin/env bash
# prove-usage-export-key.sh — pool-Pi proof of restrict,from=,command= (idea#416 / idea#412).
#
# Claims are NOT done here: claim the Pi first with
#   BOT_NAME=Atlas tools/fleet/update-fleet-state.sh <pi> status testing
#   BOT_NAME=Atlas tools/fleet/update-fleet-state.sh <pi> claim 'Atlas idea#416 export proof'
# and release it afterwards. Only idea03 or idea04. Never idea01, idea02, idea, or a kit.
#
# Usage:
#   prove-usage-export-key.sh --yes --pi idea03
#
# The script:
#   - generates a throwaway ed25519 key on the box (never printed)
#   - pins from= to the box Tailscale IPv4
#   - installs /etc/ssh/idea_usage_keys/pi and extends 10-idea-peer.conf
#   - uses Axle's /usr/local/sbin/idea-usage-export if present and not a stub;
#     otherwise installs tools/fleet/idea-usage-export.stub.sh (marked as a stub)
#   - proves: allowed verb; other command / shell refused; other source IP refused
#   - restores the Pi: original drop-in put back, proof files quarantined
#     with a .quarantine-<utc-ts> suffix (never rm -rf)
#
# Does not touch docked disks, /disks, or /home/pi/kid-quarantine.
# Does not print private keys, public keys, or auth tokens.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=fleet-lib.sh
source "$SCRIPT_DIR/fleet-lib.sh"

YES=0
PI=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --yes) YES=1; shift ;;
    --pi) PI="${2:-}"; shift 2 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ "$YES" = 1 ] || { echo "ERROR: refusing to change a Pi without --yes" >&2; exit 2; }
[ -n "$PI" ] || { echo "ERROR: --pi required" >&2; exit 2; }
case "$PI" in
  idea03|idea04) ;;
  *) echo "ERROR: proof host must be idea03 or idea04, not $PI" >&2; exit 2 ;;
esac

fl_known "$PI" || { echo "ERROR: unknown Pi $PI" >&2; exit 1; }
role="$(fl_get "$PI" role)"
status="$(fl_get "$PI" status)"
claim="$(fl_get "$PI" claim)"
host="$(fl_host "$PI")"
[ -n "$host" ] || { echo "ERROR: $PI has no tailscale address" >&2; exit 1; }
case "$role" in spare|review) ;; *) echo "ERROR: $PI role is $role (need spare or review)" >&2; exit 1 ;; esac
case "$status" in hold|paused|production|kit) echo "ERROR: $PI status is $status" >&2; exit 1 ;; esac
if [ -z "$claim" ] || [ "$claim" = "null" ]; then
  echo "ERROR: $PI is not claimed; claim it as Atlas before running this proof" >&2
  exit 1
fi
if [[ "$claim" != "$BOT_NAME"* ]]; then
  echo "ERROR: $PI is claimed by someone else ($claim)" >&2
  exit 1
fi

ssh_pi() {
  fl_ssh "$host" "$@"
}

TS_SOCK="${TS_SOCK:-/home/box/.local/share/tailscale/tailscaled.sock}"
BOX_IP="$(tailscale --socket "$TS_SOCK" ip -4 2>/dev/null | head -1 || true)"
[ -n "$BOX_IP" ] || { echo "ERROR: could not read box Tailscale IPv4" >&2; exit 1; }

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
WORK="$(mktemp -d /tmp/idea416-proof.XXXXXX)"
chmod 700 "$WORK"
KEY="$WORK/idea416-usage-proof"
TESTS='[]'
RESTORED=0
CHANGED=0
INSTALLED_STUB=0
DROPIN_REMOTE="/etc/ssh/sshd_config.d/10-idea-peer.conf"
USAGE_DIR="/etc/ssh/idea_usage_keys"
USAGE_FILE="$USAGE_DIR/pi"
EXPORT_BIN="/usr/local/sbin/idea-usage-export"
DROPIN_BACKUP=""
MODIFIED_SAVED=""

note_test() {
  local name="$1" ok="$2" detail="$3"
  TESTS="$(jq -c --arg n "$name" --argjson ok "$ok" --arg d "$detail" \
    '. + [{name:$n,ok:$ok,detail:$d}]' <<<"$TESTS")"
}

cleanup() {
  local rc=$?
  if [ "$CHANGED" = 1 ] && [ "$RESTORED" != 1 ]; then
    restore_pi || echo "WARNING: restore_pi failed during cleanup" >&2
  fi
  # Quarantine box-side private key material; never delete with rm -rf.
  if [ -d "$WORK" ]; then
    mv "$WORK" "${WORK}.quarantine-${STAMP}" 2>/dev/null || true
  fi
  exit "$rc"
}
trap cleanup EXIT

reload_sshd() {
  ssh_pi 'sudo sshd -t && (sudo systemctl reload ssh || sudo systemctl reload sshd)'
}

restore_pi() {
  # Restore drop-in first so sshd no longer references the usage key file,
  # then quarantine proof files. Never rm -rf.
  if [ -n "$DROPIN_BACKUP" ]; then
    ssh_pi "sudo test -f '$DROPIN_BACKUP' && sudo cp -p '$DROPIN_BACKUP' '$DROPIN_REMOTE'"
    reload_sshd
    # Keep a copy of what we wrote, if it still differs.
    ssh_pi "sudo test -f '$DROPIN_REMOTE' || true" >/dev/null
  fi
  # Quarantine usage key file / dir / stub / leftover tmp key.
  ssh_pi "STAMP='$STAMP' EXPORT_BIN='$EXPORT_BIN' USAGE_FILE='$USAGE_FILE' USAGE_DIR='$USAGE_DIR' INSTALLED_STUB='$INSTALLED_STUB' bash -s" <<'REMOTE'
set -euo pipefail
q() {
  local f="$1"
  if sudo test -e "$f"; then
    sudo mv "$f" "${f}.quarantine-${STAMP}"
  fi
}
q /tmp/idea416-usage-proof-key
q /tmp/idea416-usage-proof.publine
q /tmp/idea-usage-export.stub
q "$USAGE_FILE"
# Only quarantine the export binary if we installed the stub.
if [ "${INSTALLED_STUB}" = 1 ]; then
  q "$EXPORT_BIN"
fi
if sudo test -d "$USAGE_DIR"; then
  # Leave the directory if it now only holds quarantine files; rename only if empty of live keys.
  if ! sudo test -e "$USAGE_FILE"; then
    # If the directory has nothing but we created it, quarantine it when empty.
    if [ "$(sudo find "$USAGE_DIR" -mindepth 1 -maxdepth 1 ! -name '.quarantine-*' ! -name '*.quarantine-*' | wc -l)" = 0 ]; then
      sudo mv "$USAGE_DIR" "${USAGE_DIR}.quarantine-${STAMP}" 2>/dev/null || true
    fi
  fi
fi
REMOTE
  RESTORED=1
  # Confirm operator SSH still works.
  ssh_pi true
}

# --- temperature ---
temp="$(ssh_pi 'cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || true' || true)"
if [ -n "$temp" ]; then
  temp_c="$(python3 -c "print(round($temp/1000,1))" 2>/dev/null || echo "")"
  if [ -n "$temp_c" ]; then
    python3 -c "import sys; sys.exit(0 if float('$temp_c')<=75 else 1)" || {
      echo "ERROR: $PI is ${temp_c} C > 75 C; not starting proof" >&2
      exit 1
    }
  fi
fi

# --- preflight: operator SSH and drop-in exist ---
ssh_pi true
if ! ssh_pi "sudo test -f '$DROPIN_REMOTE'"; then
  echo "ERROR: $DROPIN_REMOTE is missing on $PI; refusing to invent a drop-in" >&2
  exit 1
fi

ORIG_DROPIN="$(ssh_pi "sudo cat '$DROPIN_REMOTE'")"
printf '%s\n' "$ORIG_DROPIN" > "$WORK/10-idea-peer.conf.original"
# Refuse to proceed if the live drop-in has no AuthorizedKeysFile (would be unsafe to guess).
echo "$ORIG_DROPIN" | grep -q '^AuthorizedKeysFile ' || {
  echo "ERROR: $DROPIN_REMOTE has no AuthorizedKeysFile line" >&2
  exit 1
}

EXISTING_EXPORT="$(ssh_pi "if sudo test -f '$EXPORT_BIN'; then echo present; else echo absent; fi")"
EXPORT_KIND="stub"
if [ "$EXISTING_EXPORT" = present ]; then
  if ssh_pi "sudo grep -q 'STUB: idea-usage-export' '$EXPORT_BIN'"; then
    EXPORT_KIND="stub-already"
  else
    EXPORT_KIND="axle"
  fi
fi

# --- generate throwaway key (box) ---
ssh-keygen -t ed25519 -N '' -f "$KEY" -C "idea416-usage-proof-do-not-use" >/dev/null
FP="$(ssh-keygen -l -f "$KEY.pub" | awk '{print $2}')"
PUB_LINE="$(awk '{print $1" "$2}' "$KEY.pub")"
AUTH_LINE="restrict,from=\"${BOX_IP}\",command=\"${EXPORT_BIN}\" ${PUB_LINE} idea416-usage-proof"
# Do not print AUTH_LINE (contains the public key). Write to a 0600 file.
printf '%s\n' "$AUTH_LINE" > "$WORK/authorized_line"
chmod 600 "$WORK/authorized_line" "$KEY" "$KEY.pub"

# Build new drop-in text on the box.
python3 - "$WORK/10-idea-peer.conf.original" "$WORK/10-idea-peer.conf.new" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
extra = "/etc/ssh/idea_usage_keys/%u"
lines = open(src).read().splitlines(True)
out = []
found = False
for line in lines:
    if line.startswith("AuthorizedKeysFile ") and extra not in line:
        line = line.rstrip("\n")
        if not line.endswith(extra):
            line = line + " " + extra
        line = line + "\n"
        found = True
    out.append(line)
if not found and not any(extra in ln for ln in lines):
    sys.exit("no AuthorizedKeysFile line to extend")
open(dst, "w").writelines(out)
PY

# --- install on the Pi ---
# Copy files via stdin (no scp dependency, no keys in argv).
b64_auth="$(base64 -w0 < "$WORK/authorized_line")"
b64_dropin="$(base64 -w0 < "$WORK/10-idea-peer.conf.new")"
b64_stub="$(base64 -w0 < "$SCRIPT_DIR/idea-usage-export.stub.sh")"

ssh_pi "STAMP='$STAMP' DROPIN_REMOTE='$DROPIN_REMOTE' USAGE_DIR='$USAGE_DIR' USAGE_FILE='$USAGE_FILE' EXPORT_BIN='$EXPORT_BIN' EXPORT_KIND='$EXPORT_KIND' B64_AUTH='$b64_auth' B64_DROPIN='$b64_dropin' B64_STUB='$b64_stub' bash -s" <<'REMOTE'
set -euo pipefail
printf '%s' "$B64_AUTH" | base64 -d > /tmp/idea416-usage-proof.publine
chmod 600 /tmp/idea416-usage-proof.publine
printf '%s' "$B64_DROPIN" | base64 -d > /tmp/idea416-10-idea-peer.conf.new
if [ "$EXPORT_KIND" != axle ]; then
  printf '%s' "$B64_STUB" | base64 -d > /tmp/idea-usage-export.stub
  chmod 755 /tmp/idea-usage-export.stub
fi
sudo mkdir -p "$USAGE_DIR"
sudo chmod 755 "$USAGE_DIR"
sudo chown root:root "$USAGE_DIR"
# Backup the live drop-in before changing it.
sudo cp -p "$DROPIN_REMOTE" "${DROPIN_REMOTE}.quarantine-${STAMP}-original"
sudo cp /tmp/idea416-10-idea-peer.conf.new "$DROPIN_REMOTE"
sudo chown root:root "$DROPIN_REMOTE"
sudo chmod 644 "$DROPIN_REMOTE"
sudo cp /tmp/idea416-usage-proof.publine "$USAGE_FILE"
sudo chown root:root "$USAGE_FILE"
sudo chmod 644 "$USAGE_FILE"
if [ "$EXPORT_KIND" != axle ]; then
  if sudo test -f "$EXPORT_BIN"; then
    sudo mv "$EXPORT_BIN" "${EXPORT_BIN}.quarantine-${STAMP}-before-stub"
  fi
  sudo cp /tmp/idea-usage-export.stub "$EXPORT_BIN"
  sudo chown root:root "$EXPORT_BIN"
  sudo chmod 755 "$EXPORT_BIN"
fi
sudo sshd -t
REMOTE

DROPIN_BACKUP="${DROPIN_REMOTE}.quarantine-${STAMP}-original"
if [ "$EXPORT_KIND" != axle ]; then
  INSTALLED_STUB=1
fi
CHANGED=1
reload_sshd

# Operator SSH must still work after the reload (normal keys, not the proof key).
if ssh_pi true; then
  note_test "operator-ssh-after-reload" true "normal key still accepted"
else
  note_test "operator-ssh-after-reload" false "normal key failed after sshd reload"
  echo "ERROR: operator SSH failed after reload; restoring" >&2
  restore_pi
  jq -nc --argjson tests "$TESTS" --arg pi "$PI" '{ok:false,message:"operator SSH failed after sshd reload",pi:$pi,tests:$tests}'
  exit 1
fi

usage_ssh() {
  # Identify with the throwaway key only. Do not print the key path in JSON.
  ssh -o BatchMode=yes -o IdentitiesOnly=yes -o ConnectTimeout=15 \
    -o StrictHostKeyChecking=accept-new \
    -o ProxyCommand="${HOME}/.local/bin/socks-connect %h %p" \
    -i "$KEY" \
    -o UserKnownHostsFile="$WORK/known_hosts" \
    "pi@$host" "$@"
}

# Test 1: allowed verb
allowed_out=""
allowed_rc=0
allowed_out="$(usage_ssh since 2026-01-01 2>"$WORK/allowed.err")" || allowed_rc=$?
if [ "$allowed_rc" = 0 ] && echo "$allowed_out" | grep -q '"verb":"since"\|"schema":"idea-usage'; then
  note_test "allowed-since" true "since 2026-01-01 accepted"
elif [ "$allowed_rc" = 0 ] && [ -n "$allowed_out" ]; then
  note_test "allowed-since" true "since 2026-01-01 accepted (non-stub exporter)"
else
  note_test "allowed-since" false "since 2026-01-01 failed rc=$allowed_rc"
fi

# Test 2a: other command
other_rc=0
usage_ssh id >"$WORK/other.out" 2>"$WORK/other.err" || other_rc=$?
if [ "$other_rc" != 0 ]; then
  note_test "refused-other-command" true "id refused rc=$other_rc"
else
  note_test "refused-other-command" false "id was accepted"
fi

# Test 2b: shell / empty command (no remote argv)
shell_rc=0
usage_ssh >"$WORK/shell.out" 2>"$WORK/shell.err" || shell_rc=$?
if [ "$shell_rc" != 0 ]; then
  note_test "refused-shell" true "empty command / shell refused rc=$shell_rc"
else
  note_test "refused-shell" false "empty command opened a session"
fi

# Test 3: different source IP — from the Pi itself to 127.0.0.1
# Copy the private key over stdin (not argv). Quarantined in restore_pi.
base64 -w0 < "$KEY" | ssh_pi 'base64 -d > /tmp/idea416-usage-proof-key && chmod 600 /tmp/idea416-usage-proof-key'
src_rc=0
src_out="$(ssh_pi "ssh -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -i /tmp/idea416-usage-proof-key pi@127.0.0.1 since 2026-01-01" 2>"$WORK/src.err")" || src_rc=$?
# Note: assigning src_rc inside $(...) does not survive the subshell. Capture || outside.
if [ "$src_rc" != 0 ]; then
  note_test "refused-other-source" true "from= 127.0.0.1 refused rc=$src_rc"
else
  note_test "refused-other-source" false "connection from 127.0.0.1 was accepted"
fi

restore_pi
note_test "restored" true "drop-in restored, proof files quarantined"

# Confirm operator SSH after restore
if ssh_pi true; then
  note_test "operator-ssh-after-restore" true "normal key works after restore"
else
  note_test "operator-ssh-after-restore" false "normal key failed after restore"
fi

FAIL="$(jq '[.[] | select(.ok==false)] | length' <<<"$TESTS")"
TOTAL="$(jq 'length' <<<"$TESTS")"
PASS="$(jq '[.[] | select(.ok==true)] | length' <<<"$TESTS")"
if [ "$FAIL" = 0 ]; then OK=true; RC=0; else OK=false; RC=1; fi

jq -nc \
  --arg script "prove-usage-export-key.sh" \
  --argjson ok "$OK" \
  --arg message "export-key proof on $PI: $PASS passed, $FAIL failed" \
  --arg pi "$PI" \
  --arg host "$host" \
  --arg box_ip "$BOX_IP" \
  --arg export_kind "$EXPORT_KIND" \
  --arg fingerprint "$FP" \
  --arg stamp "$STAMP" \
  --argjson tests "$TESTS" \
  --arg bot "${BOT_NAME:-Atlas}" \
  --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson pass "$PASS" --argjson fail "$FAIL" \
  '{
     script:$script, ok:$ok, message:$message, pi:$pi, host:$host,
     box_from_ip:$box_ip, export_kind:$export_kind,
     key_fingerprint:$fingerprint, stamp:$stamp,
     tests:$tests, summary:{pass:$pass, fail:$fail},
     bot:$bot, at:$at,
     notes:[
       "Private and public keys were not printed.",
       "Proof files were quarantined with a .quarantine-<ts> suffix.",
       "Kid quarantine paths and docked disks were not touched."
     ]
   }'
exit "$RC"
