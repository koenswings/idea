# IDEA Platform — Migration Runbook
## From: standalone openclaw + standalone mission-control → unified compose

**Executed by:** Claude Code in a tmux SSH session (independent of OpenClaw)  
**Risk:** Low — OpenClaw stays up throughout MC migration; brief restart at the end  
**Rollback:** < 2 minutes (see bottom of this file)

---

## What this migration does

Moves from two independent Docker Compose stacks to one unified platform compose at `idea/platform/compose.yaml`. Mission Control moves from `openclaw_proxy-net` to `idea-net` and reaches OpenClaw by service name instead of host bridge IP.

```
Before:
  /home/pi/openclaw/             ← compose for openclaw-gateway
  /home/pi/openclaw/mission-control/  ← separate compose for 5 MC containers
  
After:
  /home/pi/idea/platform/compose.yaml  ← one compose for all 6 services
```

---

## Prerequisites

- [ ] idea PR #7 (`feat/idea-openclaw-setup`) is merged and pulled
- [ ] You are in a tmux session (`tmux new-session -s migration`)
- [ ] Working directory: `/home/pi/idea`
- [ ] OpenClaw is running (verify: `docker ps | grep openclaw-gateway`)

---

## Step 0 — Discovery: verify the compose template

Before applying anything, read the actual MC compose to verify the template matches.

```bash
cat /home/pi/openclaw/mission-control/docker-compose.yml
# or
cat /home/pi/openclaw/mission-control/compose.yaml
```

Check against `idea/platform/compose.yaml`:
- [ ] Image names match (`openclaw-mission-control-backend`, `frontend`, `webhook-worker`)
- [ ] Volume names and mounts match
- [ ] Environment variables are complete (the template was derived from `docker inspect` — it may be missing some)
- [ ] `POSTGRES_PASSWORD` / `DATABASE_URL` password matches (extract from running env or compose file)
- [ ] Any additional services not captured in the template

Also read the entrypoint script:
```bash
cat /home/pi/openclaw/entrypoint.sh
```

---

## Step 1 — Backup current state

```bash
BACKUP_DIR="/home/pi/backups/pre-migration-$(date +%Y%m%d-%H%M)"
mkdir -p "${BACKUP_DIR}"

# Backup compose files
cp /home/pi/openclaw/docker-compose.yml "${BACKUP_DIR}/" 2>/dev/null || \
  cp /home/pi/openclaw/compose.yaml "${BACKUP_DIR}/compose-openclaw.yaml" 2>/dev/null
cp -r /home/pi/openclaw/mission-control/ "${BACKUP_DIR}/mission-control/"

# Backup live config
cp ~/.openclaw/openclaw.json "${BACKUP_DIR}/openclaw.json"
cp /home/pi/openclaw/entrypoint.sh "${BACKUP_DIR}/entrypoint.sh"

# Backup secrets (redacted log — do NOT print contents)
ls /home/pi/openclaw/secrets/ > "${BACKUP_DIR}/secrets-list.txt"

echo "Backup written to ${BACKUP_DIR}"
```

---

## Step 2 — Prepare platform secrets and support files

The unified compose reads secrets from `idea/platform/secrets/` (gitignored). Copy them from the current location:

```bash
mkdir -p /home/pi/idea/platform/secrets/
chmod 700 /home/pi/idea/platform/secrets/

# Copy existing secrets
cp /home/pi/openclaw/secrets/anthropic_api_key.txt \
   /home/pi/idea/platform/secrets/anthropic_api_key.txt
cp /home/pi/openclaw/secrets/openclaw_gateway_token.txt \
   /home/pi/idea/platform/secrets/openclaw_gateway_token.txt

# Extract MC DB password and write as a secret file
# Find it from the running MC compose or running container env:
docker exec openclaw-mission-control-backend-1 \
  env | grep DATABASE_URL | sed 's/.*postgres:\/\/postgres:\(.*\)@.*/\1/'
# Then write it:
# echo "<password>" > /home/pi/idea/platform/secrets/mc_db_password.txt
# chmod 600 /home/pi/idea/platform/secrets/mc_db_password.txt

# Copy entrypoint script
cp /home/pi/openclaw/entrypoint.sh /home/pi/idea/platform/entrypoint.sh
chmod +x /home/pi/idea/platform/entrypoint.sh
```

> **Note:** Check the DB password against what's in the MC compose file and/or the running container. The compose.yaml template uses `${MC_DB_PASSWORD}` — you may need to set this in a `.env` file or convert it to the secrets approach. Update `idea/platform/compose.yaml` if the actual MC compose handles this differently.

---

## Step 3 — Validate the new compose

```bash
cd /home/pi/idea
docker compose -f platform/compose.yaml config
```

This validates the YAML syntax and resolves all variables. Fix any errors before proceeding. Common issues:
- Missing secret files → create them (Step 2)
- Missing `.env` variables → write to `platform/.env`
- Image not found locally → note which ones need pulling or building

---

## Step 4 — Stop standalone Mission Control

OpenClaw stays running throughout this step. Telegram remains connected.

```bash
# Find and stop the standalone MC compose
# (Project name is likely 'openclaw-mission-control' or 'mission-control')
cd /home/pi/openclaw/mission-control
docker compose down
# Do NOT use -v — this would delete the database volume
```

Verify MC is stopped:
```bash
docker ps | grep mission-control   # should return nothing
docker ps | grep openclaw-gateway  # should still be running
```

---

## Step 5 — Start unified compose

This step briefly restarts OpenClaw (30–60 seconds of downtime). Telegram connection drops and resumes automatically.

```bash
cd /home/pi/idea

# Apply the IDEA openclaw config (fills tokens, preserves gateway token)
# Source the credentials
source platform/.env  # or set MC_DB_PASSWORD manually

# Start everything
docker compose -f platform/compose.yaml up -d

# Watch the startup
docker compose -f platform/compose.yaml logs -f --tail=50
```

Press `Ctrl+C` when logs settle (all services showing healthy/running).

---

## Step 6 — Verify

```bash
# All 6 containers running
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# OpenClaw responding
curl -s http://localhost:18789/health | python3 -m json.tool

# MC API responding
curl -s http://localhost:8000/health

# MC frontend loading
curl -s -o /dev/null -w "%{http_code}" http://localhost:4000

# OpenClaw can now reach MC internally (check MC backend logs)
docker compose -f platform/compose.yaml logs mission-control-backend | tail -20
```

Expected: OpenClaw gateway running, MC backend/frontend/db/redis/worker all up.

---

## Step 7 — Update openclaw.json MC references

The MC API URL in openclaw.json was `http://172.18.0.1:8000` (host bridge). Now MC is reachable by service name. Check if openclaw.json references this URL anywhere:

```bash
grep "172.18.0" ~/.openclaw/openclaw.json
```

If found, update to `http://mission-control-backend:8000` (or `http://mission-control:8000` depending on service name used in compose) and restart the gateway:

```bash
docker compose -f platform/compose.yaml restart openclaw-gateway
```

---

## Step 8 — Send confirmation to Atlas via Telegram

Once everything is verified, send a message to the Atlas Telegram group to confirm the migration is complete. Atlas will do a final health check and update memory.

---

## Cleanup (after confirming everything works)

Only after at least 24 hours of stable operation:

```bash
# Remove old openclaw compose (keep the repo for reference, just stop managing it)
# The /home/pi/openclaw/ directory can remain as reference — just don't docker compose up from it again
```

---

## Rollback (if Step 5 or 6 fails)

OpenClaw rollback (if new compose fails to start):
```bash
cd /home/pi/openclaw
docker compose up -d  # restores original openclaw-gateway
```

MC rollback (if new compose has MC issues):
```bash
cd /home/pi/openclaw/mission-control
docker compose up -d  # restores all 5 MC containers
```

The database volumes are untouched by either compose down (no `-v` flag), so no data is lost on rollback.

---

## Key facts

| | Before | After |
|---|---|---|
| OpenClaw image | `ghcr.io/openclaw/openclaw:latest` | same |
| MC `BASE_URL` | `http://172.18.0.1:8000` | `http://mission-control-backend:8000` |
| Network | two separate networks | single `idea-net` |
| Secrets location | `/home/pi/openclaw/secrets/` | `/home/pi/idea/platform/secrets/` |
| Compose location | `/home/pi/openclaw/` + `/home/pi/openclaw/mission-control/` | `/home/pi/idea/platform/compose.yaml` |

## ⚠️ Volume safety — read before running anything

The compose.yaml uses `external: true` with exact volume names to reuse existing data:

| Volume in compose | Existing Docker volume | Contains |
|---|---|---|
| `openclaw-data` | `openclaw_openclaw-data` | OpenClaw config, sessions, agent state |
| `mc-db-data` | `openclaw-mission-control_postgres_data` | **All MC board/task data** |
| `mc-redis-data` | *(new)* | Redis cache — safe to recreate |

Before Step 4, verify these volumes exist:
```bash
docker volume ls | grep -E "openclaw_openclaw-data|openclaw-mission-control_postgres"
```
Expected output: both volumes listed. If either is missing, **stop and investigate**.
