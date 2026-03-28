#!/usr/bin/env bash
# start-agents.sh — ensure all IDEA agent claude sessions exist on the Pi.
#
# Idempotent — safe to run multiple times; skips sessions that are already
# running. Run this after a Pi reboot before opening Tabby, or call it
# directly from a Tabby profile's "Initial command" field.
#
# Usage:
#   bash /home/pi/idea/scripts/start-agents.sh

set -euo pipefail

declare -A SESSIONS=(
  ["claude-operations"]="/home/pi/idea/agents/agent-operations-manager"
  ["claude-engine"]="/home/pi/idea/agents/agent-engine-dev"
  ["claude-console"]="/home/pi/idea/agents/agent-console-dev"
  ["claude-site"]="/home/pi/idea/agents/agent-site-dev"
  ["claude-programme"]="/home/pi/idea/agents/agent-programme-manager"
)

for session in "${!SESSIONS[@]}"; do
  dir="${SESSIONS[$session]}"
  if ! tmux has-session -t "$session" 2>/dev/null; then
    tmux new-session -d -s "$session" -c "$dir" "claude; exec bash -l"
    echo "✓  Started:  $session"
  else
    echo "·  Running:  $session"
  fi
done

echo ""
echo "All agent sessions ready."
