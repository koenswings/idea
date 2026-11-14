# hub/ — services on the hub Pi `idea`

The Pi `idea` (formerly `wizardly-hugle`, "wh"; Tailscale 100.115.60.6; fleet-state key `wizardly-hugle`) runs an IDEA Engine and is also the organisation's **hub**: the field-support Telegram relay, the kit and mail watchers, the graphify server and the Caddy web server. This folder is the hub's one home in the repo. Layout, rules and migration plan: [`proposals/2026-11-04-hub-services.md`](../proposals/2026-11-04-hub-services.md) (proposal #408, approved by Koen 2026-11-13).

Status: phase 2 of the migration (idea#482). Only the Telegram relay is in `hub/` so far. The other rows below are still only on the Pi and come into `hub/` in later issues (phase 3). Nothing in this folder is deployed automatically.

## What runs on the hub

Facts come from the proposal #408 inventory (read-only, 2026-11-04, graphify and leftovers checked 2026-11-13) and from existing repo docs. "Not recorded" means the repo does not say yet; it will be filled when that service moves in.

| Service | Runs as | Port | In `hub/` | Code / config on the Pi | State | Logs | Secrets (env, mode 600) |
|---|---|---|---|---|---|---|---|
| Telegram relay (`@IDEA_SupportBot`) | systemd `--user` unit `tg-relay.service`, user `pi` (linger) | none (outbound long-poll to Telegram) | [`services/telegram-relay/`](services/telegram-relay/) | `~/tg-relay/` | `~/tg-relay/state.json`, `~/tg-relay/files/` | `~/tg-relay/relay.log`; `journalctl --user -u tg-relay.service` | `~/.config/tg-relay/env` |
| kit-watch | pi crontab, every minute (to become a systemd `--user` timer + oneshot service) | not recorded | not yet (`services/kit-watch/`) | `~/kit-watch/*.py` | not recorded | not recorded | `~/.config/kit-watch/env` (kit webhook keys) |
| mail-watch (`idea-support@agentmail.to`) | pi crontab, every minute (to become a systemd `--user` timer + oneshot service) | not recorded | not yet (`services/kit-watch/`) | `~/kit-watch/*.py` | not recorded | not recorded | not recorded |
| graphify-serve | systemd `--user` unit | 8083, all interfaces | not yet (`services/graphify/`) | `~/graphify-env` | serves `/home/pi/graphify-out` (5 May 2026 graph; rebuild retired) | journal (`--user` unit) | none (no LLM key) |
| Caddy, caddy-api | system units `caddy`, `caddy-api` | not recorded | not yet (`host/caddy/`) | `/etc/caddy` | not recorded | not recorded | not recorded |
| Host cron (root) | root crontab: 05:00 reboot, hourly avahi restart, `@reboot /usr/local/bin/boot.sh` | — | not yet (`host/`) | `/usr/local/bin/boot.sh` | — | not recorded | — |
| IDEA Engine + Console | pm2 process `engine` as `pi` | Console 8081 on idea (fleet-state `console_port`) | no — Engine install, not a hub service | `/home/pi/idea` + agent checkouts | Engine store | pm2 | — |
| MilkWise (production) | container | 3333, 3334 (`tools/fleet/field-usage-lockdown-flows.md` F3) | no — not a hub service | — | — | — | — |

## Owners

Proposal #408 notes that no owner list exists yet (gap 6), and per-service owners are **not yet assigned**; fill them in as each service moves in. What the proposal does fix: changes reach the hub only via a merged PR plus a re-run of that service's `install.sh`, deploys go service by service with Koen's OK, and the Engine fix for the dotted Nextcloud backup instance ids is owned by Axle.

## Rules (from proposal #408)

- **Secrets** live only in `~/.config/<service>/env`, mode 600, on the Pi. The repo holds an `.env.example` with key names only. No service reads another service's env file.
- **Read-only checkout.** The Pi pulls `koenswings/idea` over plain https (no token in the remote URL). Nobody edits files in place on the hub.
- **Changes** reach the hub only via a merged PR followed by a re-run of that service's `install.sh`. A drift check (`check.sh`, idea#483) reports anything else.
- **Each service folder** has the same shape: code, unit file(s), `install.sh`, `.env.example`, `README.md`, tests where it makes sense. Its README covers: what it does; how it runs; state and where it lives; env keys; logs; how to install; how to roll back.
- Units run as `pi` (systemd `--user`); the Engine's pm2 process stays as `pi`.

## Planned layout

```
hub/
  README.md          this file
  bootstrap.sh       later: fresh Pi -> installs every service (idempotent)
  check.sh           read-only drift report (idea#483)
  host/              later: cron.pi, cron.root, boot.sh, caddy/Caddyfile
  services/
    telegram-relay/  moved from tools/telegram-relay (idea#482)
    kit-watch/       later: kit-watch + mail-watch as a systemd --user timer
    graphify/        later
```
