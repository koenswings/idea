#!/usr/bin/env bash
# find-available-pi.sh [<domain>]
# Checkout layout: /home/pi/idea/agents/<repo> (see proposals/pi-checkout-layout.md)
# Returns the hostname of the first available POOL Pi in fleet-state.json.
# Available = role "spare" or "review" (the pool; never golden, fleet-pending, kit-engine or
#   production), status "idle", no claim (empty/null), and not in FLEET_DENY (default "idea02").
# The golden Pi (role: golden, today idea01) is never returned, whatever its status (idea#118).
# <domain> is accepted for compatibility and no longer changes the pick: the old affinity
# (engine->idea01, console->idea02) pointed at the golden Pi and the walker host. Pis are tried in
# fleet-state key order.
# Keys starting with "_" (_comment, _note) are metadata, not Pis.
# Env: STATE_FILE (default <repo root>/fleet-state.json), FLEET_DENY.
# Exits 0 with hostname on stdout; exits 1 if none available.
set -euo pipefail

DOMAIN="${1:-}"   # kept for callers; see header
: "$DOMAIN"
STATE_FILE="${STATE_FILE:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/fleet-state.json}"
FLEET_DENY="${FLEET_DENY:-idea02}"

if [ ! -f "$STATE_FILE" ]; then
    echo "ERROR: fleet-state.json not found at $STATE_FILE" >&2
    exit 1
fi

PI="$(jq -r --arg deny "$FLEET_DENY" '
  ($deny | split(" ") | map(select(length > 0))) as $d
  | to_entries[]
  | select(.key | startswith("_") | not)
  | select(.value | type == "object")
  | select((.value.role // "") as $r | $r == "spare" or $r == "review")
  | select((.value.status // "") == "idle")
  | select(((.value.claim // "") | tostring) == "")
  | select(.key as $k | $d | index($k) | not)
  | .key' "$STATE_FILE" | head -1)"

if [ -n "$PI" ]; then
    echo "$PI"
    exit 0
fi
exit 1
