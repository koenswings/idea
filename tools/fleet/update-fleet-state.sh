#!/usr/bin/env bash
# update-fleet-state.sh — safe read-modify-write of one field in fleet-state.json
#
# Usage:
#   update-fleet-state.sh [--create] <pi> <field> <value>          # store <value> as a JSON string
#   update-fleet-state.sh [--create] --json <pi> <field> <json>    # store <json> parsed as JSON (null, 5, true, {"a":1}, "x")
#   update-fleet-state.sh [--create] --null <pi> <field>           # clear the field: store JSON null
#
# Options:
#   --create   allow <pi> to be added if it is not already in the file
#              (without it, an unknown Pi is refused, so a typo can't create a fake Pi)
#   --json     parse <value> as JSON (jq --argjson) so it keeps its type
#   --null     shorthand for --json <pi> <field> null
#   -h|--help  show this help
#
# Environment:
#   STATE_FILE  path to fleet-state.json (default: <repo root>/fleet-state.json)
#   BOT_NAME    name recorded in the audit line (default: "Ops Bot")
#
# Guarantees:
#   - The whole read-modify-write runs under flock on "<STATE_FILE>.lock".
#   - The file is replaced atomically (temp file in the same directory + mv),
#     and its file mode is preserved.
#   - The audit line is built with jq, so any value is escaped correctly, and it is
#     appended to <dir of STATE_FILE>/audit/audit-<UTC year>.jsonl. A test run against
#     a copy never writes to the real audit log.
#
# Exit codes: 0 ok, 1 runtime error (missing file, unknown Pi, lock timeout), 2 usage error.
# Checkout layout: /home/pi/idea/agents/<repo> (see proposals/pi-checkout-layout.md)
set -euo pipefail

usage() { sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "ERROR: $*" >&2; exit 1; }
usage_error() { echo "ERROR: $*" >&2; echo "Run with --help for usage." >&2; exit 2; }

CREATE=0
MODE=string
while [ $# -gt 0 ]; do
    case "$1" in
        --create) CREATE=1; shift ;;
        --json)   [ "$MODE" = string ] || usage_error "--json and --null are mutually exclusive"; MODE=json; shift ;;
        --null)   [ "$MODE" = string ] || usage_error "--json and --null are mutually exclusive"; MODE=null; shift ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        -*) usage_error "unknown option: $1" ;;
        *) break ;;
    esac
done

if [ "$MODE" = null ]; then
    [ $# -eq 2 ] || usage_error "--null takes exactly <pi> <field>"
else
    [ $# -eq 3 ] || usage_error "expected <pi> <field> <value>"
fi
PI="$1"
FIELD="$2"
[ -n "$PI" ] || usage_error "<pi> must not be empty"
[ -n "$FIELD" ] || usage_error "<field> must not be empty"

case "$MODE" in
    string)
        VALUE="$3"
        [ -n "$VALUE" ] || usage_error "empty value; use --null to clear a field"
        VALUE_JSON=$(jq -n --arg v "$VALUE" '$v')
        ;;
    json)
        VALUE="$3"
        VALUE_JSON=$(printf '%s' "$VALUE" | jq -c . 2>/dev/null) || usage_error "--json value is not valid JSON: $VALUE"
        [ -n "$VALUE_JSON" ] || usage_error "--json value is empty"
        # Reject multiple JSON documents (e.g. "1 2")
        [ "$(printf '%s' "$VALUE" | jq -s 'length')" = 1 ] || usage_error "--json value must be a single JSON value"
        ;;
    null)
        VALUE_JSON=null
        ;;
esac

if [ -z "${STATE_FILE:-}" ]; then
    STATE_FILE="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/fleet-state.json"
fi
[ -f "$STATE_FILE" ] || die "fleet-state.json not found at $STATE_FILE"
# Resolve symlinks so we replace the real file, not the link.
STATE_FILE="$(readlink -f "$STATE_FILE")"
STATE_DIR="$(dirname "$STATE_FILE")"
LOCK_FILE="${STATE_FILE}.lock"
AUDIT_DIR="${STATE_DIR}/audit"
BOT="${BOT_NAME:-Ops Bot}"

TMP=""
cleanup() { if [ -n "$TMP" ]; then rm -f "$TMP"; fi; }
trap cleanup EXIT

exec 9>"$LOCK_FILE"
flock -w "${FLEET_LOCK_TIMEOUT:-30}" 9 || die "could not lock $LOCK_FILE within ${FLEET_LOCK_TIMEOUT:-30}s"

# --- critical section: read, check, modify, replace, audit ---
jq -e 'type == "object"' "$STATE_FILE" >/dev/null 2>&1 || die "$STATE_FILE is not a JSON object"

PI_TYPE=$(jq -r --arg pi "$PI" 'if has($pi) then (.[$pi] | type) else "missing" end' "$STATE_FILE")
case "$PI_TYPE" in
    object) ;;
    missing)
        [ "$CREATE" = 1 ] || die "unknown Pi '$PI' (not in $STATE_FILE). Pass --create to add it. Known Pis: $(jq -r '[keys[] | select(startswith("_") | not)] | join(", ")' "$STATE_FILE")"
        ;;
    *) die "entry '$PI' in $STATE_FILE is a $PI_TYPE, not an object" ;;
esac

PREVIOUS_JSON=$(jq -c --arg pi "$PI" --arg f "$FIELD" '.[$pi][$f] // null' "$STATE_FILE")

TMP=$(mktemp "${STATE_DIR}/.fleet-state.XXXXXX")
jq --arg pi "$PI" --arg field "$FIELD" --argjson value "$VALUE_JSON" \
    '.[$pi] = ((.[$pi] // {}) | .[$field] = $value)' "$STATE_FILE" > "$TMP"
# Preserve the original file mode (mktemp creates 0600).
chmod "$(stat -c '%a' "$STATE_FILE")" "$TMP"
mv -f "$TMP" "$STATE_FILE"
TMP=""

mkdir -p "$AUDIT_DIR"
AUDIT_FILE="${AUDIT_DIR}/audit-$(date -u +%Y).jsonl"
jq -nc \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg bot "$BOT" \
    --arg pi "$PI" \
    --arg field "$FIELD" \
    --argjson value "$VALUE_JSON" \
    --argjson previous "$PREVIOUS_JSON" \
    --argjson created "$([ "$PI_TYPE" = missing ] && echo true || echo false)" \
    '{ts: $ts, bot: $bot, action: "fleet_state_update", pi: $pi, field: $field, value: $value, previous: $previous}
     + (if $created then {created: true} else {} end)' >> "$AUDIT_FILE"
# --- end critical section (lock released when fd 9 closes at exit) ---

echo "Updated $(basename "$STATE_FILE"): $PI.$FIELD = $VALUE_JSON"
