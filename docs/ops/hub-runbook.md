# Hub runbook: restore, secret rotation, new hardware (hub Pi `idea`)

**Status:** Authoritative for the repo side (`hub/` as merged). The hub migration (idea#484–#487) is **not deployed yet**. It waits for the personal app's Backup Disk (#375 item 9) and Koen's OK for each deploy. Until then idea still runs kit-watch and mail-watch from the pi crontab, and graphify and Caddy as set up by hand. · **Maintained by:** Atlas (Ops)
Sources: [`proposals/2026-11-04-hub-services.md`](../../proposals/2026-11-04-hub-services.md) (#408), [`hub/README.md`](../../hub/README.md), the service READMEs under `hub/services/`, [`hub/host/README.md`](../../hub/host/README.md), [`docs/ops/boot-recovery.md`](boot-recovery.md).

## 1. Rules that apply to every step

- **No secrets in the repo, ever.** Secrets live only on the hub in `~/.config/<service>/env`, mode 600, owned by `pi`. The repo has `.env.example` files with key names only. No service reads another service's env file. This runbook never asks you to commit, paste or print a secret.
- **Read-only checkout.** The hub pulls `koenswings/idea` over plain `https://github.com/koenswings/idea.git`, with no token in the URL or git config. Nobody edits files in place on the hub. Changes reach it only through a merged PR followed by a re-run of that service's `install.sh` or of `hub/bootstrap.sh`. `hub/check.sh` (read-only) reports anything else as drift.
- **Users.** The hub services are systemd `--user` units as `pi`, with linger on so they start at boot. The Engine's pm2 process stays as `pi` (`pm2 save`), never root. Root is used only for the host step: root crontab, `boot.sh`, Caddy.
- **One Pi down at a time.** Only idea, or a spare Steve has agreed, is a target. Take a fleet-state claim first (`tools/fleet/update-fleet-state.sh`; production key `wizardly-hugle`). Respect the Engine update midnight guard.
- **Deleting.** Never delete: quarantine with `mv` into a timestamped folder.
- The non-IDEA personal app on idea (its containers, its `/etc/cron.d` file, its backup) is outside `hub/` and outside this runbook. Do not touch it.

## 2. What the hub runs (after the migration)

| Service | Unit (as pi unless noted) | Repo | State on the hub | Env file |
|---|---|---|---|---|
| Telegram relay | `tg-relay.service` | `hub/services/telegram-relay/` | `~/tg-relay/state.json`, `~/tg-relay/files/` | `~/.config/tg-relay/env` |
| kit-watch + mail-watch | `kit-watch.timer` + oneshot `kit-watch.service` | `hub/services/kit-watch/` | `~/kit-watch/state.json`, `mail-state.json`, `DISABLED` | `~/.config/kit-watch/env` |
| graphify-serve | `graphify-serve.service` (port 8083) | `hub/services/graphify/` | `~/graphify-out/` (content, not in git) | none |
| Host | root crontab, `/usr/local/bin/boot.sh`, system `caddy` / `caddy-api` | `hub/host/` | `/etc/caddy/` | — |
| Engine + Console | pm2 `engine` | Engine install (not `hub/`) | Engine store, App Disks | — |

## 3. First cutover on idea (idea#484–#486), once #375 item 9 is done and Koen has OK'd it

Do one service at a time. Run `hub/check.sh` before and after each. Stop at the first surprise.

1. Claim idea in fleet-state. On idea as pi: `cd ~/idea && git pull --ff-only` (plain https).
2. **Capture what the repo does not hold yet**, read-only: `hub/host/capture.sh`. Review the folder it prints, on idea. Any non-zero secret count must be fixed first: move the value into an env file and do not copy it. Bring `boot.sh`, the Caddyfile and the live graphify unit and kit-watch scripts to the box, and open a PR that replaces the `HUB-PLACEHOLDER` files. That PR also aligns `services/` if the live copies differ. Merge with Koen's OK, then pull again.
3. **kit-watch** (#484): `sh hub/services/kit-watch/install.sh`. Wait for a good run (`journalctl --user -u kit-watch.service -n 20`, `tail ~/kit-watch/watch.log`). Then run `sh hub/services/kit-watch/install.sh --remove-cron`, then `hub/check.sh --service kit-watch`.
4. **graphify** (#485): `sh hub/services/graphify/install.sh`. Then `curl -sI http://127.0.0.1:8083/graph.html` must return 200, and `hub/check.sh --service graphify`.
5. **Host** (#486): `sudo hub/host/install.sh` (plan) and read it. Then `sudo hub/host/install.sh --apply` only if the plan shows the intended changes and nothing else. Then `hub/check.sh --service host`.
6. **Reboot acceptance** (one Pi, idea only, outside the midnight guard, with Koen's OK): after the reboot, `systemctl --user list-timers kit-watch.timer`, `systemctl --user is-active tg-relay graphify-serve`, `systemctl is-active caddy`, `pm2 ls` (engine online as pi), `hub/check.sh` (no drift). Also check `boot.sh` ran: `journalctl -b -t CRON` shows `/usr/local/bin/boot.sh`.
7. Release the claim (flag-first, check that it reads JSON null).

## 4. Restore the hub from scratch (same Pi, new SD card)

1. Flash and install the Engine as for any Pi (see the Engine docs and `docs/ops/engine-deploy-pool-pi.md`). The hub's own steps start once the Engine and pm2 are up as `pi`.
2. Clone the repo as pi over plain https: `git clone https://github.com/koenswings/idea.git ~/idea`. Never use a URL with a token.
3. **Restore secrets privately**, never via the repo or a chat:
   `install -d -m 700 ~/.config/kit-watch ~/.config/tg-relay`, then write each env file with `umask 077` (for example `umask 077; nano ~/.config/kit-watch/env`). Key names are in each `.env.example`. Values come from their owners (see §5). Both files must be non-empty, or `bootstrap.sh --apply` refuses.
4. **Restore state** from the latest private backup, if there is one: `~/tg-relay/state.json` (allowlist, monitor group, topics), `~/kit-watch/state.json` and `mail-state.json`, and `~/graphify-out/` (never rebuild it). Without `mail-state.json`, mail-watch's first run marks every current message as seen, so nothing old is re-announced. Open point: hub state is not in a scheduled backup today. See the PR for idea#487.
5. Plan, then apply: `~/idea/hub/bootstrap.sh` (read-only plan; it shows any blockers), then `~/idea/hub/bootstrap.sh --apply`. Apply enables linger, installs every service, runs the host step, then `check.sh`. If the old kit-watch cron lines are present it skips the host step, so follow §3 step 3, then re-run.
6. Reboot acceptance as in §3 step 6.

## 5. Rotate a secret (on the hub, never in the repo)

General pattern, as pi on idea:

    cp -p ~/.config/<service>/env ~/.config/<service>/env.bak-$(date +%Y%m%dT%H%M%S)   # private rollback copy, mode 600
    umask 077; nano ~/.config/<service>/env                                           # change the one value
    chmod 600 ~/.config/<service>/env

Then restart the service or wait for the next timer run, and check it. Afterwards move the `.bak-*` copy into the hub's private backups (`mv`). Do not leave it next to the live file: `check.sh` lists env key names only, but the extra file is clutter.

| Secret | Where it is used | Get the new value from | After changing |
|---|---|---|---|
| `TELEGRAM_BOT_TOKEN` | `~/.config/tg-relay/env` | Koen, via BotFather `/revoke` and new token for @IDEA_SupportBot | `systemctl --user restart tg-relay.service`; send a test message |
| `KIT_WEBHOOK_URL`, `KIT_WEBHOOK_KEY` | **both** `~/.config/kit-watch/env` and `~/.config/tg-relay/env` (each service keeps its own copy) | the routine webhook settings (Steve or Koen) | `systemctl --user restart tg-relay.service`; the next `kit-watch.service` run picks it up (check `watch.log` for `HTTP 2xx`) |
| `AGENTMAIL_API_KEY` | `~/.config/kit-watch/env` | the AgentMail console for `idea-support@agentmail.to` (Koen) | the next `kit-watch.service` run; `watch.log` must show no `ERROR AgentMail HTTP 401` |
| GitHub tokens | none on the hub: the checkouts use plain https | — | if one ever appears in a `.git/config`, switch the remote back to plain https and have Koen revoke the token |

Revoke the old value at its source only after the new one works.

## 6. Move the hub to new hardware

1. Agree the new Pi and a window with Steve. Claim both Pis. Only one Pi is down at a time.
2. On the new Pi: Engine install, then §4 steps 2–3 (clone, secrets). Bootstrap with `--spare <its hostname>` first. Install the services, but keep **kit-watch disabled** (`systemctl --user disable --now kit-watch.timer`) and the relay stopped. Two relays polling one bot token, or two watchers posting, would duplicate messages.
3. On old idea: stop the relay and the kit-watch timer, or comment out the cron lines if the migration has not happened there yet. Copy the state files (§4 step 4) to the new Pi over SSH, as pi.
4. On the new Pi: give it the hub's name (`idea`) and Tailscale identity as agreed with Steve and Koen. That covers the hostname, the Tailscale node and DNS, and any Caddy TLS name (see `renew-tailscale-cert` in `hub/host/capture.sh` output). Then run `hub/bootstrap.sh --apply`, start the relay and timer, and do the §3 step 6 checks.
5. Keep the old card untouched as the rollback for at least a week. Record the move in fleet-state.

## 7. Roll back

- One service: check out the previous commit of its folder and re-run its `install.sh`. Each README has a rollback section, for example `crontab ~/.idea-hub-backups/kit-watch/<stamp>/crontab.pi.before` for the watchers.
- Host: the files and crontabs replaced by `hub/host/install.sh --apply` are in `/var/backups/idea-hub/host/<stamp>/` (root, 700).
