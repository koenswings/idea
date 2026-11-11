#!/usr/bin/env bash
# usage-monitoring.sh — toggle usageMonitoring on one Pi (idea#411).
#
# Usage:
#   tools/fleet/usage-monitoring.sh <pi> on|off|status
#   tools/fleet/usage-monitoring.sh <pi> on|off|status --approve-kit-window
#
# Calls /usr/local/sbin/idea-usage-settings over SSH as pi (no sudo, no pm2,
# no docker). The helper writes only /var/lib/idea/usage/settings.json; the
# running idea-usage process re-reads it within a minute. This script never
# restarts the Engine or any App.
#
# Guards (field-usage-rollout.md §9):
#   - one Pi at a time
#   - kits (status=kit or role=kit-engine) unless --approve-kit-window
#   - golden (role=golden, including idea01)
#   - idea / wizardly-hugle (DENY_HOSTS, default 100.115.60.6)
#   - FLEET_DENY (default idea02)
#   - status hold|paused|production
#   - claimed by someone else
#   - fleet-wide HOLD/PAUSED (unless --ignore-fleet-hold)
#
# Prints one JSON object with ok, previous, value, unchanged and pi.
#
# Env: STATE_FILE, BOT_NAME, SSH_CMD, PROXY, HEALTH_DIR, FLEET_DENY, DENY_HOSTS
#      (fleet-lib.sh). USAGE_SETTINGS_HELPER overrides the remote helper path.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=fleet-lib.sh
source "$SCRIPT_DIR/fleet-lib.sh"

HELPER="${USAGE_SETTINGS_HELPER:-/usr/local/sbin/idea-usage-settings}"
KIT_WINDOW=0
PI=""
VERB=""

usage() { sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --approve-kit-window) KIT_WINDOW=1; shift ;;
    --ignore-fleet-hold) IGNORE_FLEET_HOLD=1; export IGNORE_FLEET_HOLD; shift ;;
    --) shift; break ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)
      if [ -z "$PI" ]; then PI="$1"
      elif [ -z "$VERB" ]; then VERB="$1"
      else echo "unexpected argument: $1" >&2; usage >&2; exit 2
      fi
      shift
      ;;
  esac
done

[ -n "$PI" ] && [ -n "$VERB" ] || { usage >&2; exit 2; }
case "$VERB" in on|off|status) ;; *) echo "verb must be on, off or status" >&2; usage >&2; exit 2 ;; esac
[[ "$PI" =~ ^[A-Za-z0-9_-]+$ ]] || fl_die "Pi name is not a safe token"
[[ "$HELPER" == /usr/local/sbin/idea-usage-settings ]] || fl_die "USAGE_SETTINGS_HELPER must be /usr/local/sbin/idea-usage-settings"

fl_fleet_hold_check

role=""; status=""; claim=""; host=""
fl_known "$PI" || fl_die "unknown Pi '$PI' (not in fleet-state.json)"
for d in $FLEET_DENY; do [ "$PI" = "$d" ] && fl_die "$PI is on the deny list (FLEET_DENY): not touched"; done
host="$(fl_host "$PI")"; [ -n "$host" ] || fl_die "$PI has no tailscale/host address"
for d in $DENY_HOSTS; do [ "$host" = "$d" ] && fl_die "$PI resolves to protected host $host: not touched"; done
role="$(fl_get "$PI" role)"; role="${role:-review}"
status="$(fl_get "$PI" status)"
claim="$(fl_get "$PI" claim)"
[ "$role" = golden ] && fl_die "$PI has role 'golden': not used as a test or toggle target"
[ "$role" = production ] && fl_die "$PI has role 'production': not touched"
case "$status" in
  production) fl_die "$PI status is 'production': not touched" ;;
  hold|paused) fl_die "$PI status is '$status': not touched" ;;
esac
if [ "$status" = kit ] || [ "$role" = kit-engine ]; then
  [ "$KIT_WINDOW" = 1 ] || fl_die "$PI is a kit: refused outside an approved idea#374 window (pass --approve-kit-window)"
fi
if [ -n "$claim" ] && [[ "$claim" != "$BOT_NAME"* ]]; then
  fl_die "$PI is claimed by someone else ($claim)"
fi
fl_step guard true "$PI role=$role status=${status:-?} host=$host"

remote_verb() {
  local out rc=0
  out="$(fl_ssh "$host" "$HELPER" "$1" 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    fl_die "idea-usage-settings $1 failed (exit $rc): $(printf '%s' "$out" | tr '\n' ' ')"
  fi
  out="$(printf '%s' "$out" | tr -d '\r' | tail -n 1)"
  case "$out" in on|off) printf '%s' "$out" ;; *) fl_die "idea-usage-settings $1 returned unexpected output" ;; esac
}

previous="$(remote_verb status)"
value="$previous"
if [ "$VERB" != status ]; then
  value="$(remote_verb "$VERB")"
fi
unchanged=false
[ "$previous" = "$value" ] && unchanged=true

fl_finish 0 true "usageMonitoring $value" "$(jq -nc \
  --arg pi "$PI" --arg previous "$previous" --arg value "$value" --argjson unchanged "$unchanged" \
  '{pi:$pi,previous:$previous,value:$value,unchanged:$unchanged}')"
