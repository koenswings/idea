# idea/platform

The IDEA virtual company platform: OpenClaw (AI agent runtime) + Mission Control (task management), configured and deployed as one unified stack.

## Contents

| File | Purpose |
|---|---|
| `compose.yaml` | Unified Docker Compose — all 6 services on one network |
| `openclaw.json` | Agent roster, model config, Telegram bindings — no secrets, committed |
| `.env.template` | Credential placeholders — committed |
| `.env` | Actual credentials — **gitignored, never commit** |
| `secrets/` | Docker secret files — **gitignored, never commit** |
| `entrypoint.sh` | OpenClaw container entrypoint — copied from openclaw repo during migration |

## Install on a fresh Pi

```bash
git clone https://github.com/koenswings/idea /home/pi/idea
cd /home/pi/idea
bash scripts/setup.sh
```

## Migrate from standalone setup

```bash
# In a tmux session on the Pi — Claude Code executes this
cd /home/pi/idea
claude
# Tell Claude: "Read scripts/MIGRATE.md and execute the migration"
```

## Apply config changes

After merging changes to `openclaw.json`:

```bash
bash /home/pi/idea/scripts/apply-config.sh
```

## Day-to-day platform commands

```bash
cd /home/pi/idea

# Status
docker compose -f platform/compose.yaml ps

# Logs
docker compose -f platform/compose.yaml logs -f openclaw-gateway
docker compose -f platform/compose.yaml logs -f mission-control-backend

# Restart a service
docker compose -f platform/compose.yaml restart openclaw-gateway

# Full restart
docker compose -f platform/compose.yaml restart
```
