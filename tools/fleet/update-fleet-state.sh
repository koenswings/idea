#!/usr/bin/env bash
# update-fleet-state.sh <pi> <field> <value>
# Checkout layout: /home/pi/idea/agents/<repo> (see proposals/pi-checkout-layout.md)
# Atomic read-modify-write of fleet-state.json
# Must be run from the koenswings/idea repo root or with STATE_FILE set.
set -euo pipefail

PI="${1:?Usage: update-fleet-state.sh <pi> <field> <value>}"
FIELD="${2:?}"
VALUE="${3:?}"

STATE_FILE="${STATE_FILE:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/fleet-state.json}"

if [ ! -f "$STATE_FILE" ]; then
    echo "ERROR: fleet-state.json not found" >&2
    exit 1
fi

# Use jq to update atomically (write to temp, then move)
TMP=$(mktemp)
jq --arg pi "$PI" --arg field "$FIELD" --arg value "$VALUE" \
    '.[$pi][$field] = $value' "$STATE_FILE" > "$TMP"
mv "$TMP" "$STATE_FILE"

echo "Updated fleet-state.json: $PI.$FIELD = $VALUE"

# Append audit event
AUDIT_FILE="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/audit/audit-$(date +%Y).jsonl"
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"bot\":\"Ops Bot\",\"action\":\"fleet_state_update\",\"pi\":\"$PI\",\"field\":\"$FIELD\",\"value\":\"$VALUE\"}" >> "$AUDIT_FILE"
