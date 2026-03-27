# idea/openclaw

IDEA-specific OpenClaw configuration. OpenClaw is the platform IDEA runs on; this folder is IDEA's configuration of it.

## Contents

| File | Purpose |
|---|---|
| `openclaw.json` | Agent roster, model config, Telegram bindings, channel settings — committed, no secrets |
| `.env.template` | Credential placeholders — committed |
| `.env` | Actual credentials — **gitignored, never commit** |

## How it works

`openclaw.json` is deployed to `~/.openclaw/openclaw.json` inside the Docker container (the location OpenClaw reads at startup). The setup script handles substitution and deployment:

```bash
bash /home/pi/idea/scripts/setup.sh
```

## Updating the agent roster

If you add or remove agents, or change Telegram bindings, edit `openclaw.json` here, then apply via the gateway restart command:

```bash
sudo docker restart openclaw-gateway
```

Or, from the OpenClaw control UI → Config tab.

## Credentials

Credentials live in `.env` (gitignored). To regenerate:

```bash
cp .env.template .env
# Edit .env with your values
```

Then re-run `setup.sh` or manually update `~/.openclaw/openclaw.json` and restart the gateway.
