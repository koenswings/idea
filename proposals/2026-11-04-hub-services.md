# The hub Pi `idea`: put its services in the repo under `hub/`

**Author:** Steve · IDEA Lead Bot
**Date:** 2026-11-04
**Status:** Approved by Koen on 2026-11-13, with the comments applied below.
**Refs:** PR #407 (relay sync, phase 1, merged). Related: `proposals/2026-10-20-telegram-field-support.md`, `proposals/pi-checkout-layout.md`, `proposals/scheduled-backup-disk.md`.
**Affects:** `koenswings/idea` (new `hub/` folder, `tools/telegram-relay/` moves), Ops (the Pi `idea`).

---

## 1. What the hub is

The Pi `idea` (formerly `wizardly-hugle`, "wh"; Tailscale 100.115.60.6) started as an Engine. It is now also the organisation's central brain: it runs the field-support Telegram relay, the kit and mail watchers, the graphify server, and the Caddy web server. Each of these was added on its own, mostly by hand over SSH. Nothing lists what runs there, and several pieces exist only on the SD card. If that card died, nobody could rebuild the hub from the repo.

This proposal calls that role **the hub**, and gives it one home in `koenswings/idea`: a `hub/` folder with one sub-folder per service, an install script that rebuilds a fresh Pi, and a read-only drift check.

## 2. Inventory (read-only, 2026-11-04 ~04:00 CET)

| Service | How it runs | Code on the Pi | In a repo? | Documented? | Explanation |
|---|---|---|---|---|---|
| Telegram relay (`@IDEA_SupportBot`) | systemd `--user` unit `tg-relay.service` | `~/tg-relay/` | Yes, `tools/telegram-relay/` (live copy synced by #407) | Yes, README + install.sh + tests | Hands field-support chats between the Telegram bot and Koen's monitor group, so staff can help people in the field over Telegram. |
| kit-watch | pi crontab, every minute | `~/kit-watch/*.py` | No | No | Runs every minute to watch kit-related events and hand them to the field-support webhook. It also holds the webhook keys that the Telegram relay copies into its own env. The code is only on the Pi today. It will move off crontab onto a systemd `--user` timer (a `.timer` unit plus a oneshot `.service` unit). |
| mail-watch | pi crontab, every minute | `~/kit-watch/*.py` | No | No | Runs every minute to watch the field-support mailbox (`idea-support@agentmail.to`), so email stays an alternative to Telegram. It lives in the same folder as kit-watch and is only on the Pi today. It will move off crontab onto a systemd `--user` timer (a `.timer` unit plus a oneshot `.service` unit). |
| graphify-serve | systemd `--user` unit | `~/graphify-env` | No | No | GRAPHIFY-TBD |
| Caddy web server, caddy-api | system units `caddy`, `caddy-api` | `/etc/caddy` | No | No | The web server (and its API) on the hub. It serves or proxies HTTP for services on idea. Its config is only on the Pi today. |
| Host cron (root) | root crontab: 05:00 reboot, hourly avahi restart, `@reboot /usr/local/bin/boot.sh` | `/usr/local/bin/boot.sh` | No | No | Scheduled host jobs that reboot the Pi at 05:00, restart Avahi every hour, and run `boot.sh` at startup, so the hub comes back up cleanly. |
| IDEA Engine | Engine install | `/home/pi/idea` + agents | Yes | Yes | The IDEA Engine already installed on this Pi (code under `/home/pi/idea` and the agent checkouts). idea still runs an Engine alongside the hub services. |

Secrets in use: `~/.config/tg-relay/env` (relay token, read by `tg_relay.py` itself) and `~/.config/kit-watch/env` (kit webhook keys, also copied into the relay env by `install.sh`).

## 3. Gaps

1. **Not reproducible.** kit-watch, mail-watch, graphify, Caddy config and the root cron jobs exist only on the Pi.
2. **Drift.** The relay ran code that was not in the repo (fixed by #407). Nothing detects drift.
3. **Hidden coupling.** The relay install depends on the untracked `~/.config/kit-watch/env`.
4. **Security finding.** A GitHub personal access token is stored in plain text in the origin URL in `/home/pi/idea/.git/config`. The 2026-11-13 survey found plaintext tokens only on production idea (three repo configs, two tokens). idea01, idea03 and idea04 are clean, and all three repos are public. Koen approved the fix (S-1) at 09:21 CET: switch the remotes to plain https, then Koen revokes both tokens on GitHub. Progress is under phase 4.
5. **Leftovers.** Two Nextcloud backup stacks from 27 Oct and assorted ad-hoc folders in `/home/pi`. Progress is under phase 5.
6. **No owner list.** No one place says which service runs on which port, who owns it, where its logs and state live.

## 4. Recommended layout

```
hub/
  README.md          what runs on the hub: services, ports, owners, logs, state
  bootstrap.sh       fresh Pi -> installs every service (idempotent, safe to re-run)
  check.sh           read-only drift report: deployed files/units/cron vs repo
  host/
    cron.pi          any remaining pi crontab entries (kit-watch and mail-watch are not here; they run as a systemd timer, see services/kit-watch/)
    cron.root        05:00 reboot, hourly avahi restart, @reboot boot.sh
    boot.sh
    caddy/Caddyfile
  services/
    telegram-relay/  moved from tools/telegram-relay: code, .service, install.sh, .env.example, README, tests
    kit-watch/       kit-watch + mail-watch, as a systemd --user timer: a .timer unit plus a oneshot .service unit (replaces the every-minute cron)
    graphify/        unit + install.sh + README
docs/ops/hub-runbook.md   restore from scratch, secret rotation, moving to new hardware
```

Each service folder has the same shape: code, unit file(s), `install.sh`, `.env.example`, `README.md`, tests where it makes sense. `bootstrap.sh` just calls each service's `install.sh` plus the host step. For kit-watch and mail-watch, "a systemd timer" means a `.timer` unit plus a oneshot `.service` unit.

## 5. Rules

- **Secrets** live only in `~/.config/<service>/env`, mode 600, on the Pi. The repo holds an `.env.example` with key names only. No service reads another service's env file (the relay gets its own copy of the webhook keys).
- **Read-only checkout.** The Pi pulls `koenswings/idea` over plain https (the repos are public; no token in the remote URL). Nobody edits files in place on the hub.
- **Changes** reach the hub only via a merged PR followed by a re-run of that service's `install.sh`. `check.sh` shows anything else as drift.
- **Per-service README checklist:** what it does; how it runs (unit/timer/cron); state and where it lives; env keys; logs; how to install; how to roll back.

## 6. Alternatives considered

| Option | For | Against |
|---|---|---|
| **A. `hub/` in `koenswings/idea` (recommended)** | One repo already holds ops tools, issues and proposals; relay is already there | idea repo grows |
| B. Separate `koenswings/idea-hub` repo | Clean boundary, own access rights | Only pays off if other people maintain the hub; splits ops docs; relay must move repos |
| C. Stay in `tools/` | No move | `tools/` mixes laptop scripts with hub services; no bootstrap or drift check |
| D. Fold services into Engine Apps | Uses Engine install/backup | Relay and watchers are not school Apps; ties org infrastructure to kit releases |

## 7. Migration plan

The migration (phases 1–3) starts only after the personal app on idea has its own Backup Disk (#375 item 9, #374). Phase 1 (the relay sync) already landed as #407 before this gate was set; phases 2 and 3 wait for that Backup Disk.

1. **Relay sync** — PR #407 (done; merged 2026-11-13 as 49a93fc).
2. **Create `hub/`**: README, `check.sh`, move `tools/telegram-relay/` to `hub/services/telegram-relay/` (leave a pointer in `tools/`). No Pi change. Not started; waits for the gate above.
3. **Bring in the rest**: kit-watch/mail-watch (as a systemd `--user` timer: a `.timer` unit plus a oneshot `.service` unit), graphify, `host/` (cron, boot.sh, Caddyfile), `bootstrap.sh`, runbook. Deploy service by service with Koen's OK, checking `check.sh` shows no drift. Not started; waits for the gate above.
4. **Token rotation** — in progress, 2026-11-13. The survey found plaintext tokens only on production idea (three repo configs, two tokens). idea01, idea03 and idea04 are clean. All three repos (`idea`, `agent-engine-dev`, `agent-app-dev`) are public. Koen approved S-1 at 09:21 CET: switch the three remotes on production idea to plain https. S1-TBD. Koen still revokes both tokens on GitHub.
5. **Cleanup** — in progress, 2026-11-13. Removal of the two 27 Oct Nextcloud backup stacks (compose down without `-v`, then quarantine the folders): STACKS-TBD. Cleanup of other ad-hoc home folders: not started (quarantine first, delete only with Koen's OK).

## 8. Open questions for Koen

1. Is `hub/` inside `koenswings/idea` OK, or do you want a separate `idea-hub` repo? **Answered 2026-11-13:** `hub/` inside `koenswings/idea` is OK (Koen approved this proposal).
2. May I revoke the GitHub token on the hub and switch to a deploy key (phase 4), and when? **Answered 2026-11-13:** Koen approved S-1 at 09:21 CET: switch the remotes to plain https (the repos are public). Koen still revokes both tokens on GitHub. See phase 4.
3. Should kit-watch's every-minute cron become a systemd timer, or stay cron? **Answered 2026-11-13:** it becomes a systemd timer, meaning a `.timer` unit plus a oneshot `.service` unit.
4. Is graphify still needed on the hub, or can it be retired? **Answered 2026-11-13:** it stays in. GRAPHIFY-TBD
5. Can the 27 Oct Nextcloud backup stacks be removed after quarantine? **Answered 2026-11-13:** yes; removal is under way in phase 5. STACKS-TBD
