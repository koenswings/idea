#!/bin/bash
# backup-agent-identities.sh
# Backs up all agent identity and memory files to the agent-identities GitHub repo.
# Runs nightly via cron. Alerts Atlas on Telegram if any identity file drifts unexpectedly.
#
# Expects:
#   /home/pi/agent-identities/  — local clone of koenswings/agent-identities (no branch protection)
#   /home/pi/.openclaw/openclaw.json — OpenClaw config (for Telegram bot token)
#   GITHUB_TOKEN env var — or set in /home/pi/agent-identities/.git/config credentials
#
# Schedule (Pi crontab):
#   0 3 * * * /home/pi/idea/scripts/backup-agent-identities.sh >> /var/log/agent-backup.log 2>&1

set -euo pipefail

# Workspace path works both from container (/home/node/workspace) and Pi host (/home/pi/idea)
WORKSPACE="${WORKSPACE_ROOT:-/home/node/workspace}/agents"
BACKUP_REPO="/tmp/agent-identities-backup-$$"
ATLAS_CHAT="-5105695997"
AGENTS="agent-operations-manager agent-engine-dev agent-console-dev agent-site-dev agent-programme-manager"
IDENTITY_FILES="AGENTS.md SOUL.md IDENTITY.md USER.md TOOLS.md HEARTBEAT.md"

# Load GitHub token and Telegram bot token
GITHUB_TOKEN="${GITHUB_TOKEN:-$(grep GITHUB_TOKEN "${WORKSPACE_ROOT:-/home/node/workspace}/agents/agent-operations-manager/.env" 2>/dev/null | cut -d= -f2 || echo '')}"
BOT_TOKEN="$(jq -r '.channels.telegram.botToken' /home/pi/.openclaw/openclaw.json 2>/dev/null || echo '')"

log() { echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*"; }

log "Starting agent identity backup"

# Clone backup repo fresh to temp dir
trap "rm -rf '$BACKUP_REPO'" EXIT
git clone "https://koenswings:${GITHUB_TOKEN}@github.com/koenswings/agent-identities.git" "$BACKUP_REPO" 2>/dev/null
git -C "$BACKUP_REPO" config user.email "atlas@idea-platform.org"
git -C "$BACKUP_REPO" config user.name "Atlas"

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
  CHANGED=$(git -C "$BACKUP_REPO" diff --name-only -- "$agent/" 2>/dev/null \
    | grep -v "^$agent/memory/" \
    | grep -v "^$agent/outputs/" \
    | grep -v "^$agent/MEMORY\.md" \
    || true)

  if [ -n "$CHANGED" ]; then
    STATS=$(git -C "$BACKUP_REPO" diff --stat -- "$agent/" 2>/dev/null \
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
git -C "$BACKUP_REPO" add -A
if git -C "$BACKUP_REPO" diff --cached --quiet; then
  log "No changes — nothing to commit"
else
  git -C "$BACKUP_REPO" commit -m "backup: $(date -u '+%Y-%m-%d')"
  git -C "$BACKUP_REPO" push origin main
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
