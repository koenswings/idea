#!/bin/bash
# backup-agent-identities.sh
# Backs up all agent identity and memory files to the agent-identities GitHub repo.
# Runs nightly via cron. Alerts Atlas on Telegram if any identity file drifts unexpectedly.
#
# Expects:
#   /home/pi/agent-identities/  — local clone of koenswings/agent-identities (no branch protection)
#   /root/.openclaw/openclaw.json — OpenClaw config (for Telegram bot token)
#   GITHUB_TOKEN env var — or set in /home/pi/agent-identities/.git/config credentials
#
# Schedule (Pi crontab):
#   0 3 * * * /home/pi/idea/scripts/backup-agent-identities.sh >> /var/log/agent-backup.log 2>&1

set -euo pipefail

WORKSPACE="/home/pi/idea/agents"
BACKUP_REPO="/home/pi/agent-identities"
ATLAS_CHAT="-5105695997"
AGENTS="agent-operations-manager agent-engine-dev agent-console-dev agent-site-dev agent-programme-manager"
IDENTITY_FILES="AGENTS.md SOUL.md IDENTITY.md USER.md TOOLS.md HEARTBEAT.md"

# Load Telegram bot token from OpenClaw config
BOT_TOKEN="$(jq -r '.channels.telegram.botToken' /root/.openclaw/openclaw.json 2>/dev/null || echo '')"

log() { echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*"; }

log "Starting agent identity backup"

# Ensure backup repo exists
if [ ! -d "$BACKUP_REPO/.git" ]; then
  log "ERROR: $BACKUP_REPO is not a git repo. Clone koenswings/agent-identities there first."
  exit 1
fi

cd "$BACKUP_REPO"
git pull --ff-only origin main 2>/dev/null || log "Warning: could not pull latest — continuing"

DRIFT_SUMMARY=""

for agent in $AGENTS; do
  SRC="$WORKSPACE/$agent"
  DEST="$BACKUP_REPO/$agent"

  [ -d "$SRC" ] || { log "Warning: $SRC not found — skipping"; continue; }
  mkdir -p "$DEST/memory" "$DEST/outputs"

  # Sync identity files
  for f in $IDENTITY_FILES MEMORY.md; do
    [ -f "$SRC/$f" ] && cp "$SRC/$f" "$DEST/$f"
  done

  # Sync memory and outputs directories
  [ -d "$SRC/memory" ]  && rsync -a --delete "$SRC/memory/"  "$DEST/memory/"  2>/dev/null || true
  [ -d "$SRC/outputs" ] && rsync -a --delete "$SRC/outputs/" "$DEST/outputs/" 2>/dev/null || true

  # Check for identity file drift (exclude memory/ outputs/ MEMORY.md — those change freely)
  CHANGED=$(git diff --name-only -- "$agent/" 2>/dev/null \
    | grep -v "^$agent/memory/" \
    | grep -v "^$agent/outputs/" \
    | grep -v "^$agent/MEMORY\.md" \
    || true)

  if [ -n "$CHANGED" ]; then
    STATS=$(git diff --stat -- "$agent/" 2>/dev/null \
      | grep "|" \
      | grep -v "memory/" \
      | grep -v "outputs/" \
      | grep -v "MEMORY\.md" \
      | sed "s|$agent/||g" \
      || true)
    DRIFT_SUMMARY="${DRIFT_SUMMARY}• ${agent}:\n${STATS}\n"
    log "Identity drift detected in $agent"
  fi
done

# Commit and push everything
git add -A
if git diff --cached --quiet; then
  log "No changes — nothing to commit"
else
  git commit -m "backup: $(date -u '+%Y-%m-%d')"
  git push origin main
  log "Backup committed and pushed"
fi

# Alert Atlas on Telegram if identity drift detected
if [ -n "$DRIFT_SUMMARY" ] && [ -n "$BOT_TOKEN" ]; then
  MSG="🔍 Identity drift detected — Atlas review needed:

$(echo -e "$DRIFT_SUMMARY")
Reply RATIFY <agent> or REVERT <agent> to act."

  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d "chat_id=${ATLAS_CHAT}" \
    --data-urlencode "text=${MSG}" \
    > /dev/null
  log "Drift alert sent to Atlas"
fi

log "Backup complete"
