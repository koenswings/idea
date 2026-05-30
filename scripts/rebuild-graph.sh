#!/bin/bash
set -e
echo "[$(date)] Graphify rebuild triggered" >> /home/pi/idea/logs/graphify-rebuild.log
cd /home/pi/idea
source /home/pi/graphify-env/bin/activate
# Load Anthropic API key if not already set (needed by graphify's Claude backend)
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  ANTHROPIC_API_KEY=$(cat /home/pi/idea/platform/secrets/anthropic_api_key.txt)
  export ANTHROPIC_API_KEY
fi
graphify . --update --no-viz --obsidian \
  >> /home/pi/idea/logs/graphify-rebuild.log 2>&1
echo "[$(date)] Graphify rebuild complete" >> /home/pi/idea/logs/graphify-rebuild.log
