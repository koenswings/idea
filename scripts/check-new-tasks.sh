#!/usr/bin/env bash
# check-new-tasks.sh — auto-trigger reviewer agents for `cross-agent` tagged tasks.
# Runs every 2 minutes via pi cron. No LLM involved — pure shell + MC API.
#
# For each agent board:
#   - Finds tasks tagged "cross-agent" with status "inbox"
#   - Checks triggered-tasks.log to avoid double-triggering
#   - Marks task in_progress (prevents a second cron run from firing the same task)
#   - Appends task ID to triggered-tasks.log
#   - Fires an isolated OpenClaw gateway session for the reviewer agent

set -euo pipefail

MC_URL="http://172.18.0.1:8000"  # also reachable as http://mission-control-backend:8000 from within idea-net
LOG_DIR="/home/pi/idea/logs"
TRIGGERED_LOG="$LOG_DIR/triggered-tasks.log"
SCRIPT_LOG="$LOG_DIR/check-new-tasks.log"
TOKEN_FILE="/home/pi/.mc-token"

mkdir -p "$LOG_DIR"
touch "$TRIGGERED_LOG"

log() { echo "[check-new-tasks $(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$SCRIPT_LOG"; }

# ── Auth token ────────────────────────────────────────────────────────────────
if [[ ! -f "$TOKEN_FILE" ]]; then
  log "ERROR: $TOKEN_FILE not found — cannot authenticate"
  exit 1
fi
TOKEN=$(cat "$TOKEN_FILE")

# ── Agent boards ──────────────────────────────────────────────────────────────
declare -A BOARDS
BOARDS["axle"]="6bddb9d2-c06f-444d-8b18-b517aeaa6aa8"
BOARDS["pixel"]="ac508766-e9e3-48a0-b6a5-54c6ffcdc1a3"
BOARDS["beacon"]="7cc2a1cf-fa22-485f-b842-bb22cb758257"
BOARDS["atlas"]="d0cfa49e-edcb-4a23-832b-c2ae2c99bf67"
BOARDS["marco"]="3f1be9c8-87e7-4a5d-9d3b-99756c35e3a9"

# Agent IDs for session invocation (board lead agents)
declare -A AGENTS
AGENTS["axle"]="8a0b3f32-8ebd-4b9b-93ff-1aad53269be3"
AGENTS["pixel"]="bd2b264f-4727-4799-8522-66114cc59a1c"
AGENTS["beacon"]="70404eba-4e1c-4d2d-bcb5-f34bfd32ad7b"
AGENTS["atlas"]="ac172302-3c45-4a51-bdb3-dc233a0f65e8"
AGENTS["marco"]="c1aeb3f8-a258-448f-afcb-f518bdc47bca"

# ── Process each board ────────────────────────────────────────────────────────
for NAME in "${!BOARDS[@]}"; do
  BOARD_ID="${BOARDS[$NAME]}"
  AGENT_ID="${AGENTS[$NAME]}"

  # Fetch inbox tasks tagged "cross-agent"
  RESPONSE=$(curl -sf \
    -H "Authorization: Bearer $TOKEN" \
    "$MC_URL/api/v1/boards/$BOARD_ID/tasks?status=inbox&tag=cross-agent" \
    2>/dev/null || echo "")

  if [[ -z "$RESPONSE" ]]; then
    continue
  fi

  # Extract task IDs, titles, descriptions (requires jq)
  TASK_COUNT=$(echo "$RESPONSE" | jq -r '.total // 0')
  if [[ "$TASK_COUNT" -eq 0 ]]; then
    continue
  fi

  log "$NAME board: $TASK_COUNT cross-agent inbox task(s) found"

  # Process each task
  echo "$RESPONSE" | jq -c '.items[]' | while IFS= read -r TASK_JSON; do
    TASK_ID=$(echo "$TASK_JSON" | jq -r '.id')
    TASK_TITLE=$(echo "$TASK_JSON" | jq -r '.title')
    TASK_DESC=$(echo "$TASK_JSON" | jq -r '.description // ""')

    # Guard: already triggered?
    if grep -qF "$TASK_ID" "$TRIGGERED_LOG"; then
      log "$NAME: task $TASK_ID already triggered — skip"
      continue
    fi

    log "$NAME: triggering task $TASK_ID — $TASK_TITLE"

    # Mark task in_progress (prevents double-trigger on slow sessions)
    PATCH_RESULT=$(curl -sf -X PATCH \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"status":"in_progress"}' \
      "$MC_URL/api/v1/boards/$BOARD_ID/tasks/$TASK_ID" \
      2>/dev/null || echo "")

    if [[ -z "$PATCH_RESULT" ]]; then
      log "$NAME: WARNING — failed to mark task $TASK_ID in_progress; skipping trigger to avoid double-fire"
      continue
    fi

    # Record in triggered log immediately
    echo "$TASK_ID" >> "$TRIGGERED_LOG"

    # Build the prompt
    PROMPT=$(printf 'You have a cross-agent task.\n\nTitle: %s\n\n%s\n\nPlease:\n1. Read the artifact referenced above\n2. Write your response (PR comment, annotation, answer, or flag)\n3. Mark task %s as done via the MC API\n\n⚠ This is a depth-1 cross-agent session. Do not create any further tasks.' \
      "$TASK_TITLE" "$TASK_DESC" "$TASK_ID")

    # Fire isolated session via OpenClaw gateway
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
      log "$NAME: task $TASK_ID → session $SESSION_ID started"
    else
      log "$NAME: WARNING — session fire failed for task $TASK_ID (task is in_progress, will not retry automatically)"
    fi

  done
done

log "Scan complete"
