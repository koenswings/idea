# hub/ — services on the hub Pi `idea`

The Pi `idea` (formerly `wizardly-hugle`, "wh"; Tailscale 100.115.60.6; fleet-state key `wizardly-hugle`) runs an IDEA Engine and is also the organisation's **hub**: the field-support Telegram relay, the kit and mail watchers, the graphify server and the Caddy web server. This folder is the hub's one home in the repo. Layout, rules and migration plan: [`proposals/2026-11-04-hub-services.md`](../proposals/2026-11-04-hub-services.md) (proposal #408, approved by Koen 2026-11-13).

Status: phase 3 of the migration in progress. The Telegram relay (idea#482), kit-watch + mail-watch (idea#484), graphify-serve (idea#485) and the host step (idea#486: crontabs captured; `boot.sh` and the Caddyfile still placeholders, see [`host/README.md`](host/README.md)) are in `hub/`. The other rows below are still only on the Pi and come into `hub/` in later issues. Nothing in this folder is deployed automatically: each deploy waits for the personal app's Backup Disk (#375 item 9) and Koen's OK.

## What runs on the hub

Facts come from the proposal #408 inventory (read-only, 2026-11-04, graphify and leftovers checked 2026-11-13) and from existing repo docs. "Not recorded" means the repo does not say yet; it will be filled when that service moves in.

| Service | Runs as | Port | In `hub/` | Code / config on the Pi | State | Logs | Secrets (env, mode 600) |
|---|---|---|---|---|---|---|---|
| Telegram relay (`@IDEA_SupportBot`) | systemd `--user` unit `tg-relay.service`, user `pi` (linger) | none (outbound long-poll to Telegram) | [`services/telegram-relay/`](services/telegram-relay/) | `~/tg-relay/` | `~/tg-relay/state.json`, `~/tg-relay/files/` | `~/tg-relay/relay.log`; `journalctl --user -u tg-relay.service` | `~/.config/tg-relay/env` |
| kit-watch + mail-watch (`idea-support@agentmail.to`) | systemd `--user` timer `kit-watch.timer` (every minute) + oneshot `kit-watch.service`, user `pi` (linger); today still the pi crontab until the idea#484 deploy | none (outbound only: tailscale status, AgentMail API, routine webhook) | [`services/kit-watch/`](services/kit-watch/) | `~/kit-watch/{kit-watch,mail-watch}.py` | `~/kit-watch/state.json`, `mail-state.json`, `DISABLED` | `~/kit-watch/watch.log`; `journalctl --user -u kit-watch.service` | `~/.config/kit-watch/env` (`KIT_WEBHOOK_URL`, `KIT_WEBHOOK_KEY`, `AGENTMAIL_API_KEY`) |
| graphify-serve | systemd `--user` unit `graphify-serve.service`, user `pi` (linger) | 8083, all interfaces | [`services/graphify/`](services/graphify/) | unit only (system `python3 -m http.server`); old `~/graphify-env` venv not needed | serves `/home/pi/graphify-out` (5 May 2026 graph; rebuild retired; never written by install) | `journalctl --user -u graphify-serve.service` | none (no LLM key) |
| Caddy, caddy-api | system units `caddy`, `caddy-api` | not recorded (`capture.sh` lists :80/:443/:2019) | [`host/caddy/`](host/) (Caddyfile is a placeholder until captured) | `/etc/caddy` | not recorded | `journalctl -u caddy` | not recorded |
| Host cron (root) | root crontab: 05:00 reboot, hourly avahi restart, `@reboot /usr/local/bin/boot.sh` | — | [`host/`](host/) (`cron.root` captured; `boot.sh` placeholder until captured) | `/usr/local/bin/boot.sh` | — | `journalctl -u cron` | — |
| IDEA Engine + Console | pm2 process `engine` as `pi` | Console 8081 on idea (fleet-state `console_port`) | no — Engine install, not a hub service | `/home/pi/idea` + agent checkouts | Engine store | pm2 | — |

## Owners

Proposal #408 notes that no owner list exists yet (gap 6), and per-service owners are **not yet assigned**; fill them in as each service moves in. What the proposal does fix: changes reach the hub only via a merged PR plus a re-run of that service's `install.sh`, deploys go service by service with Koen's OK, and the Engine fix for the dotted Nextcloud backup instance ids is owned by Axle.

## Drift check: `check.sh` (idea#483)

`hub/check.sh` is **read-only**: it compares what is deployed on the hub with this checkout and prints `ok` / `DRIFT` lines. It never writes files, never touches units, cron or services, and compares env files by key **name** only (values are never printed).

    hub/check.sh                     # on the hub, as pi, from a checkout of main
    hub/check.sh --service telegram-relay
    hub/check.sh --no-state          # file checks only, skip systemd enabled/active
    hub/check.sh --root DIR --home /home/pi   # against a fake tree (tests)

Exit 0 = no drift, 1 = drift, 2 = usage error. It checks the Telegram relay, kit-watch, graphify and the host. For the relay: deployed `~/tg-relay/{tg_relay.py,tg-send}` and `~/.config/systemd/user/tg-relay.service` byte for byte against `services/telegram-relay/`, the `~/.local/bin/tg-send` link, modes (700 dirs, 600 env), env key names against `.env.example`, no unexpected files in `~/tg-relay/` beyond the relay's own state and logs, and that `tg-relay.service` is enabled and active (`systemctl --user`). For kit-watch (idea#484) it checks: both scripts and both units byte for byte, the modes, the env key names, no unexpected files in `~/kit-watch/`, that `kit-watch.timer` is enabled and active, that linger is on, and that the pi crontab (`crontab -l`, read-only) has no kit-watch or mail-watch line left. For graphify (idea#485): the unit byte for byte and its mode, that `~/graphify-out` exists, that `graphify-serve.service` is enabled and active, and linger. For the host (idea#486): `boot.sh` and the Caddyfile byte for byte (a placeholder is drift), the active root and pi crontab lines, and that `caddy.service` is active; see [`host/README.md`](host/README.md).

Tests (box only, fake tree): `bash hub/tests/check.test.sh`.

## Rules (from proposal #408)

- **Secrets** live only in `~/.config/<service>/env`, mode 600, on the Pi. The repo holds an `.env.example` with key names only. No service reads another service's env file.
- **Read-only checkout.** The hub Pi pulls its checkouts over plain https, with no token in the remote URL and none stored in git config. That includes the three remotes switched on 13 Nov: `idea`, `agent-engine-dev` and `agent-app-dev` (the repos are public). Nobody edits files in place on the hub. The `gh` CLI login on the Pi is left as it is unless Koen asks for a change.
- **Changes** reach the hub only via a merged PR followed by a re-run of that service's `install.sh`. A drift check (`check.sh`, idea#483) reports anything else.
- **Each service folder** has the same shape: code, unit file(s), `install.sh`, `.env.example`, `README.md`, tests where it makes sense. Its README covers: what it does; how it runs; state and where it lives; env keys; logs; how to install; how to roll back.
- Units run as `pi` (systemd `--user`); the Engine's pm2 process stays as `pi`.

## Planned layout

```
hub/
  README.md          this file
  bootstrap.sh       later: fresh Pi -> installs every service (idempotent)
  check.sh           read-only drift report (idea#483)
  host/              cron.pi, cron.root, boot.sh, caddy/Caddyfile, install.sh, capture.sh (idea#486)
  services/
    telegram-relay/  moved from tools/telegram-relay (idea#482)
    kit-watch/       kit-watch + mail-watch as a systemd --user timer (idea#484)
    graphify/        graphify-serve user unit (idea#485)
```
