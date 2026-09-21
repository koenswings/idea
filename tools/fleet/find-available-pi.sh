#!/usr/bin/env bash
# find-available-pi.sh <domain>
# Returns the hostname of the first idle Pi matching the domain.
# Domain affinity: engine→idea01, console→idea02, app-dev→idea03
# Falls back to any idle non-golden Pi if domain Pi is busy.
# Exits 0 with hostname on stdout; exits 1 if none available.
set -euo pipefail

DOMAIN="${1:-}"
STATE_FILE="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/fleet-state.json"

if [ ! -f "$STATE_FILE" ]; then
    echo "ERROR: fleet-state.json not found at $STATE_FILE" >&2
    exit 1
fi

# Domain affinity map
declare -A AFFINITY
AFFINITY["engine"]="idea01"
AFFINITY["console"]="idea02"
AFFINITY["app-dev"]="idea03"
AFFINITY["ops"]="idea04"

PREFERRED="${AFFINITY[$DOMAIN]:-}"

# Check preferred Pi first
if [ -n "$PREFERRED" ]; then
    STATUS=$(jq -r --arg pi "$PREFERRED" '.[$pi].status // "unknown"' "$STATE_FILE")
    ROLE=$(jq -r --arg pi "$PREFERRED" '.[$pi].role // "review"' "$STATE_FILE")
    if [ "$STATUS" = "idle" ] && [ "$ROLE" != "golden" ]; then
        echo "$PREFERRED"
        exit 0
    fi
fi

# Fall back: any idle non-golden Pi
for PI in $(jq -r 'keys[]' "$STATE_FILE"); do
    STATUS=$(jq -r --arg pi "$PI" '.[$pi].status // "unknown"' "$STATE_FILE")
    ROLE=$(jq -r --arg pi "$PI" '.[$pi].role // "review"' "$STATE_FILE")
    if [ "$STATUS" = "idle" ] && [ "$ROLE" != "golden" ] && [ "$PI" != "$PREFERRED" ]; then
        echo "$PI"
        exit 0
    fi
done

# None available
exit 1
