#!/bin/bash
set -e
DATE=$(date +%Y%m%d)
BACKUP_DIR=/home/pi/idea/backups
IDENTITIES_REPO=/home/pi/agent-identities

mkdir -p "$BACKUP_DIR"

# 1. MC PostgreSQL dump (via docker exec — pg_dump runs inside the container)
MC_PW=$(cat /home/pi/idea/platform/secrets/mc_db_password.txt)
docker exec -e PGPASSWORD="$MC_PW" openclaw-mission-control-db-1 \
  pg_dump -U postgres mission_control --format=custom \
  > "$BACKUP_DIR/mc-$DATE.dump"

# 2. OpenClaw state (config + agent dirs)
tar czf "$BACKUP_DIR/openclaw-$DATE.tar.gz" \
  --exclude="${HOME}/.openclaw/agents/*/sessions/*.jsonl" \
  ~/.openclaw/

# 3. Copy to agent-identities repo and push
mkdir -p "$IDENTITIES_REPO/backups"
cp "$BACKUP_DIR/mc-$DATE.dump" "$IDENTITIES_REPO/backups/"
cp "$BACKUP_DIR/openclaw-$DATE.tar.gz" "$IDENTITIES_REPO/backups/"

# 4. Push
cd "$IDENTITIES_REPO"
git add backups/
git commit -m "backup: $DATE" --allow-empty
git push origin main

# 5. Prune local backups older than 7 days
find "$BACKUP_DIR" -name "*.dump" -mtime +7 -delete
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +7 -delete

echo "[$(date)] Platform backup complete ($DATE)"
