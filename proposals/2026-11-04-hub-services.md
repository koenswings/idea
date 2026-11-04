# The hub Pi `idea`: put its services in the repo under `hub/`

**Author:** Steve · IDEA Lead Bot
**Date:** 2026-11-04
**Status:** Draft for Koen. Koen asked for this on 2026-11-04 ("Ok go ahead", after the relay question).
**Refs:** PR #407 (relay sync, phase 1). Related: `proposals/2026-10-20-telegram-field-support.md`, `proposals/pi-checkout-layout.md`, `proposals/scheduled-backup-disk.md` (MilkWise backup).
**Affects:** `koenswings/idea` (new `hub/` folder, `tools/telegram-relay/` moves), Ops (the Pi `idea`).

---

## 1. What the hub is

The Pi `idea` (formerly `wizardly-hugle`, "wh"; Tailscale 100.115.60.6) started as an Engine. It is now also the organisation's central brain: it runs the field-support Telegram relay, the kit and mail watchers, the graphify server, the Caddy web server, and it co-hosts MilkWise production. Each of these was added on its own, mostly by hand over SSH. Nothing lists what runs there, and several pieces exist only on the SD card. If that card died, nobody could rebuild the hub from the repo.

This proposal calls that role **the hub**, and gives it one home in `koenswings/idea`: a `hub/` folder with one sub-folder per service, an install script that rebuilds a fresh Pi, and a read-only drift check.

## 2. Inventory (read-only, 2026-11-04 ~04:00 CET)

| Service | How it runs | Code on the Pi | In a repo? | Documented? |
|---|---|---|---|---|
| Telegram relay (`@IDEA_SupportBot`) | systemd `--user` unit `tg-relay.service` | `~/tg-relay/` | Yes, `tools/telegram-relay/` (live copy synced by #407) | Yes, README + install.sh + tests |
| kit-watch | pi crontab, every minute | `~/kit-watch/*.py` | No | No |
| mail-watch | pi crontab, every minute | `~/kit-watch/*.py` | No | No |
| graphify-serve | systemd `--user` unit | `~/graphify-env` | No | No |
| Caddy web server, caddy-api | system units `caddy`, `caddy-api` | `/etc/caddy` | No | No |
| Host cron (root) | root crontab: 05:00 reboot, hourly avahi restart, `@reboot /usr/local/bin/boot.sh` | `/usr/local/bin/boot.sh` | No | No |
| MilkWise backup | `/etc/cron.d/milkwise-backup` | — | No (belongs to MilkWise) | No |
| MilkWise (production, :3333) | Docker | — | Own repo | Own repo |
| IDEA Engine | Engine install | `/home/pi/idea` + agents | Yes | Yes |

Secrets in use: `~/.config/tg-relay/env` (relay token, read by `tg_relay.py` itself) and `~/.config/kit-watch/env` (kit webhook keys, also copied into the relay env by `install.sh`).

## 3. Gaps

1. **Not reproducible.** kit-watch, mail-watch, graphify, Caddy config and the root cron jobs exist only on the Pi.
2. **Drift.** The relay ran code that was not in the repo (fixed by #407). Nothing detects drift.
3. **Hidden coupling.** The relay install depends on the untracked `~/.config/kit-watch/env`.
4. **Security finding.** A GitHub personal access token is stored in plain text in the origin URL in `/home/pi/idea/.git/config`. Fix: revoke it and use a read-only deploy key for the hub checkout. **This needs Koen's OK** (it is a change on production).
5. **Leftovers.** Two Nextcloud backup stacks from 27 Oct and assorted ad-hoc folders in `/home/pi`.
6. **No owner list.** No one place says which service runs on which port, who owns it, where its logs and state live.

## 4. Recommended layout

```
hub/
  README.md          what runs on the hub: services, ports, owners, logs, state
  bootstrap.sh       fresh Pi -> installs every service (idempotent, safe to re-run)
  check.sh           read-only drift report: deployed files/units/cron vs repo
  host/
    cron.pi          pi crontab (kit-watch moves to a timer, see below)
    cron.root        05:00 reboot, hourly avahi restart, @reboot boot.sh
    boot.sh
    caddy/Caddyfile
  services/
    telegram-relay/  moved from tools/telegram-relay: code, .service, install.sh, .env.example, README, tests
    kit-watch/       kit-watch + mail-watch, as a systemd --user timer (replaces the every-minute cron)
    graphify/        unit + install.sh + README
docs/ops/hub-runbook.md   restore from scratch, secret rotation, moving to new hardware
```

Each service folder has the same shape: code, unit file(s), `install.sh`, `.env.example`, `README.md`, tests where it makes sense. `bootstrap.sh` just calls each service's `install.sh` plus the host step.

## 5. Rules

- **Secrets** live only in `~/.config/<service>/env`, mode 600, on the Pi. The repo holds an `.env.example` with key names only. No service reads another service's env file (the relay gets its own copy of the webhook keys).
- **Read-only checkout.** The Pi pulls `koenswings/idea` with a read-only deploy key. Nobody edits files in place on the hub.
- **Changes** reach the hub only via a merged PR followed by a re-run of that service's `install.sh`. `check.sh` shows anything else as drift.
- **Per-service README checklist:** what it does; how it runs (unit/timer/cron); state and where it lives; env keys; logs; how to install; how to roll back.

## 6. MilkWise stays out

MilkWise is co-hosted on the hub but is not part of it. `hub/README.md` gets a one-line note that it runs there (port 3333, Docker). Its backup cron (`/etc/cron.d/milkwise-backup`) belongs in the MilkWise repo, until the Scheduled Backup Disk replaces it.

## 7. Alternatives considered

| Option | For | Against |
|---|---|---|
| **A. `hub/` in `koenswings/idea` (recommended)** | One repo already holds ops tools, issues and proposals; relay is already there | idea repo grows |
| B. Separate `koenswings/idea-hub` repo | Clean boundary, own access rights | Only pays off if other people maintain the hub; splits ops docs; relay must move repos |
| C. Stay in `tools/` | No move | `tools/` mixes laptop scripts with hub services; no bootstrap or drift check |
| D. Fold services into Engine Apps | Uses Engine install/backup | Relay and watchers are not school Apps; ties org infrastructure to kit releases |

## 8. Migration plan

1. **Relay sync** — PR #407 (done, awaiting merge).
2. **Create `hub/`**: README, `check.sh`, move `tools/telegram-relay/` to `hub/services/telegram-relay/` (leave a pointer in `tools/`). No Pi change.
3. **Bring in the rest**: kit-watch/mail-watch (as a timer), graphify, `host/` (cron, boot.sh, Caddyfile), `bootstrap.sh`, runbook. Deploy service by service with Koen's OK, checking `check.sh` shows no drift.
4. **Token rotation**: revoke the PAT in `/home/pi/idea/.git/config`, switch the hub checkout to a read-only deploy key. Needs Koen's OK.
5. **Cleanup** of the two 27 Oct Nextcloud backup stacks and ad-hoc home folders: quarantine first, delete only with Koen's OK.

## 9. Open questions for Koen

1. Is `hub/` inside `koenswings/idea` OK, or do you want a separate `idea-hub` repo?
2. May I revoke the GitHub token on the hub and switch to a deploy key (phase 4), and when?
3. Should kit-watch's every-minute cron become a systemd timer, or stay cron?
4. Is graphify still needed on the hub, or can it be retired?
5. Can the 27 Oct Nextcloud backup stacks be removed after quarantine?
