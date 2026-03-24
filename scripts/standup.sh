#!/usr/bin/env bash
# standup.sh — CEO-triggered standup. Run by sending /standup in Telegram.
#
# Flow:
#   1. Runs standup-seed.sh to generate/refresh today's standup context file
#   2. Sends a standup prompt to each agent via isolated MC gateway session
#      (agents write their contribution directly to the standup file)
#   3. Agents commit and push their contributions
#
# Trigger: `/standup` Telegram command, or run directly on pi.
# Not a daily cron — CEO-triggered only.

set -euo pipefail

MC_URL="http://172.18.0.1:8000"
IDEA_DIR="/home/pi/idea"
LOG_DIR="$IDEA_DIR/logs"
SCRIPT_LOG="$LOG_DIR/standup.log"
TOKEN_FILE="/home/pi/.mc-token"
TODAY=$(date +"%Y-%m-%d")
STANDUP_FILE="$IDEA_DIR/standups/$TODAY.md"

mkdir -p "$LOG_DIR"

log() { echo "[standup $(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$SCRIPT_LOG"; }

# ── Auth ──────────────────────────────────────────────────────────────────────
if [[ ! -f "$TOKEN_FILE" ]]; then
  log "ERROR: $TOKEN_FILE not found"
  exit 1
fi
TOKEN=$(cat "$TOKEN_FILE")

# ── Step 1: Seed standup context ──────────────────────────────────────────────
log "Running standup-seed.sh"
"$IDEA_DIR/scripts/standup-seed.sh" >> "$SCRIPT_LOG" 2>&1

# Check if standup was skipped
if grep -q "STANDUP_SKIPPED" "$STANDUP_FILE" 2>/dev/null; then
  log "Standup seed reported no changes — skipping agent prompts"
  exit 0
fi

log "Standup file ready: $STANDUP_FILE"

# ── Agent roster ──────────────────────────────────────────────────────────────
# Format: "name:agent_id:role_header"
AGENTS=(
  "veri:ac172302-3c45-4a51-bdb3-dc233a0f65e8:quality-manager"
  "axle:8a0b3f32-8ebd-4b9b-93ff-1aad53269be3:engine-dev"
  "pixel:bd2b264f-4727-4799-8522-66114cc59a1c:console-dev"
  "beacon:70404eba-4e1c-4d2d-bcb5-f34bfd32ad7b:site-dev"
  "marco:c1aeb3f8-a258-448f-afcb-f518bdc47bca:programme-manager"
)

# ── Step 2: Prompt each agent ─────────────────────────────────────────────────
for ENTRY in "${AGENTS[@]}"; do
  IFS=':' read -r NAME AGENT_ID ROLE_HEADER <<< "$ENTRY"

  PROMPT=$(printf 'Today is %s. The standup file is ready at `../../standups/%s.md` (absolute path: %s).\n\nPlease:\n1. Read the ## Context section of the standup file\n2. Add your `## %s` contribution below the existing content:\n   - What you worked on yesterday / what is in progress\n   - Any blockers\n   - What you plan to do today\n   - Session cost (check your last session cost if available)\n3. Commit and push the standup file:\n   `cd ../../ && git add standups/%s.md && git commit -m "Standup %s: %s" && git push`\n\nKeep your contribution concise — 3–5 bullet points maximum.' \
    "$TODAY" "$TODAY" "$STANDUP_FILE" "$ROLE_HEADER" "$TODAY" "$TODAY" "$ROLE_HEADER")

  SESSION_PAYLOAD=$(jq -n \
    --arg agent "$AGENT_ID" \
    --arg prompt "$PROMPT" \
    '{
      "agentId": $agent,
      "sessionTarget": "isolated",
      "payload": {
        "kind": "agentTurn",
        "prompt": $prompt
      },
      "delivery": {
        "mode": "announce",
        "channel": "last"
      }
    }')

  FIRE_RESULT=$(curl -sf -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$SESSION_PAYLOAD" \
    "$MC_URL/api/v1/gateway/sessions" \
    2>/dev/null || echo "")

  if [[ -n "$FIRE_RESULT" ]]; then
    SESSION_ID=$(echo "$FIRE_RESULT" | jq -r '.id // "unknown"')
    log "$NAME: standup session $SESSION_ID started"
  else
    log "$NAME: WARNING — session fire failed"
  fi
done

log "All standup sessions started. Agents will contribute to $STANDUP_FILE."
