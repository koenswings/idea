# Runbook: OpenClaw Docker → Native Install Migration

**Executed by:** Claude Code in a tmux SSH session, running **outside OpenClaw**  
**Risk:** Low–moderate — brief OpenClaw downtime during cutover (~60 seconds)  
**Rollback:** < 2 minutes (see bottom of this file)  
**Design doc:** `idea/design/openclaw-native-migration.md`

---

## ⚠️ Safety: run this outside OpenClaw

This migration restarts OpenClaw. If it is run from inside an OpenClaw agent session, the
session will be interrupted mid-migration and may leave the system in an inconsistent state.

**Always execute this runbook from a standalone Claude Code session:**

```bash
# On your laptop, SSH into the Pi
ssh pi@openclaw-pi.tail2d60.ts.net

# Start or attach a persistent tmux session
tmux new-session -s native-migration   # or: tmux attach -t native-migration

# From inside tmux, start Claude Code in the idea directory
cd /home/pi/idea
claude   # or: npx claude, depending on how Claude Code is installed
```

The Claude Code session has access to the filesystem but is not routed through OpenClaw.
Telegram will be silent during the ~60-second cutover. It will reconnect automatically.

---

## Prerequisites

- [ ] Pi is accessible via SSH (Tailscale or LAN)
- [ ] You are in a tmux session on the Pi
- [ ] `design/openclaw-native-migration.md` has been read and understood
- [ ] `platform/compose.yaml` has been pulled from `main` (run `git pull` in `/home/pi/idea`)
- [ ] OpenClaw is currently running: `docker ps | grep openclaw-gateway`
- [ ] All agents are in a quiet state (no active work in progress)

---

## Step 0 — Discovery

Read the current state before touching anything.

```bash
# Confirm Node version on Pi
node --version   # need 22.14+ (24 preferred)

# Confirm OpenClaw is running in Docker
docker ps --format "table {{.Names}}\t{{.Status}}" | grep openclaw

# Check current openclaw config
cat ~/.openclaw/openclaw.json | python3 -m json.tool | head -40

# Check if /home/node already exists on the host
ls -la /home/node 2>/dev/null && echo "EXISTS" || echo "does not exist"

# Check workspace mount is working correctly
ls /home/pi/idea/agents/   # should show all 5 agent dirs
```

Record findings before proceeding. If `/home/node` exists and is not a symlink to something
benign, investigate before creating the symlink in Step 3.

---

## Step 1 — Backup

```bash
BACKUP_DIR="/home/pi/backups/pre-native-migration-$(date +%Y%m%d-%H%M)"
mkdir -p "${BACKUP_DIR}"

# Backup OpenClaw config and state
cp ~/.openclaw/openclaw.json "${BACKUP_DIR}/openclaw.json"
cp -r ~/.openclaw/ "${BACKUP_DIR}/openclaw-state/" 2>/dev/null || true

# Backup compose file
cp /home/pi/idea/platform/compose.yaml "${BACKUP_DIR}/compose.yaml"

# Record running container state
docker ps > "${BACKUP_DIR}/docker-ps.txt"
docker inspect openclaw-gateway > "${BACKUP_DIR}/openclaw-gateway-inspect.json" 2>/dev/null || true

echo "Backup written to ${BACKUP_DIR}"
ls -lh "${BACKUP_DIR}"
```

---

## Step 2 — Install OpenClaw natively

```bash
# Install the latest OpenClaw globally
npm install -g openclaw@latest

# Verify install
openclaw --version
openclaw doctor   # may warn about no running gateway — that's expected
```

If `npm install -g` fails due to libvips:
```bash
SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install -g openclaw@latest
```

If Node version is below 22.14, update first:
```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs
node --version   # verify
npm install -g openclaw@latest
```

---

## Step 3 — Create workspace symlink

This preserves all existing path references (`/home/node/workspace/...`) without touching
any agent config, AGENTS.md files, or TOOLS.md.

```bash
# Check if /home/node already exists
ls -la /home/node 2>/dev/null

# Create symlink (safe if /home/node does not exist or is already a symlink to idea)
sudo mkdir -p /home/node
sudo ln -sfn /home/pi/idea /home/node/workspace

# Verify
ls /home/node/workspace/agents/   # should list all 5 agent directories
ls /home/node/workspace/CONTEXT.md  # should exist
```

If `/home/node` already exists as a real directory with contents, do not proceed. Investigate
and adapt.

---

## Step 4 — Configure native OpenClaw to use existing config

OpenClaw native reads config from `~/.openclaw/openclaw.json` — the same file used by the
Docker container. No config migration is needed.

Verify the config path:
```bash
openclaw config get 2>/dev/null | head -5
# or
cat ~/.openclaw/openclaw.json | python3 -c "import sys,json; d=json.load(sys.stdin); print('agents:', len(d.get('agents', [])))"
```

The workspace path in openclaw.json uses `/home/node/workspace/...` — this will now resolve
via the symlink created in Step 3. No changes to openclaw.json are needed.

---

## Step 5 — Test native daemon (dry run)

Before stopping Docker, start the native gateway in the foreground to verify it works:

```bash
# Start in foreground (Ctrl+C to stop)
openclaw gateway start --foreground 2>&1 | head -30
```

Wait for the gateway to report listening on port 18789. If it errors:
- Check for port conflict with the Docker container (both try to bind 18789)
- If port conflict: stop Docker first (Step 6), then retry

Expected output includes something like:
```
Gateway listening on port 18789
Telegram connected
Agent sessions loaded: 5
```

Stop with Ctrl+C once confirmed working.

---

## Step 6 — Stop Docker-based OpenClaw

⚠️ **Telegram goes silent from this point until Step 7.**

```bash
cd /home/pi/idea

# Stop only the openclaw-gateway container, keep MC and other services running
docker compose -f platform/compose.yaml stop openclaw-gateway

# Verify it stopped
docker ps | grep openclaw-gateway   # should return nothing
docker ps | grep mission-control    # MC should still be running
```

---

## Step 7 — Install and start native systemd daemon

```bash
# Install the systemd daemon (runs as current user: pi)
openclaw install-daemon
# or, if that sub-command isn't available:
openclaw gateway install-daemon

# Start the service
sudo systemctl start openclaw-gateway   # service name may vary — check what install-daemon created
# or:
openclaw gateway start
```

Check what service name was created:
```bash
systemctl list-units | grep openclaw
```

Enable on boot:
```bash
sudo systemctl enable openclaw-gateway   # use actual service name
```

Verify it's running:
```bash
openclaw gateway status
curl -s http://localhost:18789/health | python3 -m json.tool
```

---

## Step 8 — Verify full stack

```bash
# OpenClaw native is running
openclaw gateway status

# Telegram reconnected (watch logs briefly)
openclaw gateway logs | tail -20

# All MC services still running
docker compose -f platform/compose.yaml ps

# MC API still reachable
curl -s http://localhost:8000/health

# Agent sessions loaded (check via Telegram or Control UI)
# Send /init to each agent group to confirm they wake up
```

Send a test message to one agent group via Telegram. Confirm response.

---

## Step 9 — Remove openclaw-gateway from compose.yaml

Once native is confirmed stable, remove the Docker service from compose so it doesn't
accidentally get started again:

```bash
cd /home/pi/idea
```

Edit `platform/compose.yaml` — remove the `openclaw-gateway` service block entirely.
Keep all MC services.

Then:
```bash
# Validate the updated compose
docker compose -f platform/compose.yaml config

# Commit the change
git config user.email "koen@idea.org"
git config user.name "Koen"
git add platform/compose.yaml
git commit -m "platform: remove openclaw-gateway from Docker compose (now native)"
git push origin main   # or open a PR — follow the branch protection policy
```

---

## Step 10 — Update setup.sh

`scripts/setup.sh` currently installs OpenClaw via Docker. Update Step 5 (`start_openclaw`):

Replace:
```bash
# Old: runs OpenClaw via Docker
cd "${OPENCLAW_DIR}"
bash docker-setup.sh
```

With:
```bash
# New: installs OpenClaw natively
npm install -g openclaw@latest
openclaw onboard --install-daemon
```

Also update Step 1 (`install_deps`): remove the Docker install step if OpenClaw is the only
Docker use case — or keep Docker for MC containers.

Create a symlink for path compatibility:
```bash
sudo mkdir -p /home/node
sudo ln -sfn /home/pi/idea /home/node/workspace
```

Commit this as a PR to `main`.

---

## Step 11 — Send confirmation

Once everything is verified stable, send a Telegram message to the Atlas group:

> Native migration complete. OpenClaw running as native systemd daemon under pi user.
> Docker openclaw-gateway service removed. MC stack unchanged.

Atlas will do a final health check and update memory.

---

## Rollback

If the native daemon fails to start or agents don't respond:

```bash
# Stop native daemon
openclaw gateway stop
# or:
sudo systemctl stop openclaw-gateway

# Restart Docker-based gateway
cd /home/pi/idea
docker compose -f platform/compose.yaml up -d openclaw-gateway

# Verify Docker gateway is up
docker ps | grep openclaw-gateway
```

Docker config is unchanged — rollback completes in under 2 minutes. All agent state is
preserved (it's in `~/.openclaw/` which was never touched).

---

## Key facts

| | Before | After |
|---|---|---|
| OpenClaw runtime | Docker container | Native Node.js process |
| Run as user | node (uid 1000, container) | pi (uid 1000, host) |
| Config path | `~/.openclaw/` (bind-mount) | `~/.openclaw/` (direct) |
| Workspace path | `/home/node/workspace` (container) | `/home/node/workspace` (symlink → /home/pi/idea) |
| Agent path refs | unchanged | unchanged |
| Managed by | Docker Compose | systemd |
| MC stack | Docker Compose | Docker Compose (unchanged) |
| Updates | `docker pull` + restart | `npm update -g openclaw` + restart |
