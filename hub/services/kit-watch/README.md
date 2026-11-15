# kit-watch and mail-watch (hub service, idea#484)

Two small zero-AI watchers on the hub Pi `idea`. They share one folder, one env file and one systemd `--user` timer. This replaces the two every-minute pi crontab lines (proposal #408, answered question 3).

- `kit-watch.py` (idea#288) watches the tailnet for the six Zimbabwe kit devices (`sunny-robin`, `happy-zebra`, `kind-panda` and their `-router`s). The first time each one shows up Online, it POSTs a `kit-device` event to the routine webhook, once per device. After all six have been seen it writes `DISABLED` and from then on every run returns at once.
- `mail-watch.py` watches the field-support mailbox `idea-support@agentmail.to`. For new message ids only, it POSTs `{type: "support-mail", count, newestReceived}` to the same webhook. It never sends mail content.
- Both watchers queue during quiet hours (00:00–07:00 Brussels) and post after 07:00. A failed POST is retried on the next run.

## Service checklist (proposal #408)

- **What it does:** see above.
- **How it runs:** the systemd **user** timer `kit-watch.timer` (as `pi`, linger on) fires every minute (`OnCalendar=*-*-* *:*:00`). It starts the **oneshot** `kit-watch.service`, which runs `kit-watch.py` and then `mail-watch.py`, each under `timeout 90` like the old cron lines. systemd never starts the service again while a run is still active, which replaces the cron `flock -n`. A `-` prefix on each `ExecStart` means one failing watcher does not stop the other. `ExecCondition` skips the run cleanly until `KIT_WEBHOOK_URL` is set.
- **Code on the hub:** `~/kit-watch/kit-watch.py`, `~/kit-watch/mail-watch.py` (dir mode 700), and the units in `~/.config/systemd/user/`.
- **State:** in `~/kit-watch/`: `state.json` (devices seen), `mail-state.json` (message ids seen and pending), `DISABLED` (all six devices seen), and the locks `.lock` and `.mail.lock`. `install.sh` never touches these.
- **Env keys:** `~/.config/kit-watch/env` (mode 600): `KIT_WEBHOOK_URL`, `KIT_WEBHOOK_KEY`, `AGENTMAIL_API_KEY`. `.env.example` has the key names only. Values may be shell-quoted, and they are parsed in-process. The old version ran `bash -c printf` for each value, which put the value on a process command line. No other service reads this file: the Telegram relay keeps its own copy of the two webhook keys in `~/.config/tg-relay/env`.
- **Optional overrides** (tests/dev, not secrets): `KIT_WATCH_HOME`, `KIT_WATCH_ENV`, `KIT_WATCH_TAILSCALE` (default `tailscale` on PATH, i.e. the system tailscaled on the hub), `KIT_WATCH_TAILSCALE_SOCKET` (unset = CLI default), `MAIL_WATCH_INBOX`, `MAIL_WATCH_API_BASE`.
- **Logs:** `~/kit-watch/watch.log` (+ `watch.log.1`, about 1 MB each). Secrets and mail content are never logged. Run history: `journalctl --user -u kit-watch.service`, `systemctl --user list-timers kit-watch.timer`.
- **Install / update** (on the hub as `pi`, after a merged PR and Koen's OK for the deploy):
  1. `sh ~/idea/hub/services/kit-watch/install.sh`. This refreshes the code and units, then enables and starts `kit-watch.timer`. It does not touch the crontab. Until step 3 the old cron lines keep running too. That overlap is safe because each script takes its own lock and dedups on its state file.
  2. Wait for a good run: `journalctl --user -u kit-watch.service -n 20` and `tail ~/kit-watch/watch.log`.
  3. `sh ~/idea/hub/services/kit-watch/install.sh --remove-cron`. This refuses unless the timer is enabled and active and the last service run succeeded. It backs up the pi crontab to `~/.idea-hub-backups/kit-watch/<stamp>/crontab.pi.before`, removes only the `kit-watch.py` and `mail-watch.py` lines, and moves the unused `.cron-*.lock` files into the same backup folder.
  4. `~/idea/hub/check.sh --service kit-watch` must report no drift.
- **Safe to re-run:** yes. An existing `~/.config/kit-watch/env` is never rewritten (only `chmod 600`). On a fresh Pi, a file with empty values is created in one step.
- **Roll back:** `systemctl --user disable --now kit-watch.timer`, then `crontab ~/.idea-hub-backups/kit-watch/<stamp>/crontab.pi.before`. For older code, check out the previous commit of this folder and re-run `install.sh`.

## Changes from the copy that ran under cron

This folder was rebuilt from the operator box's copy of the two scripts. The hub's own copy on `idea` was **not** read for this PR, because no Pi was touched. Before the deploy, diff the hub copy against this folder (`hub/check.sh --service kit-watch` shows it). Behaviour changes on purpose:

1. Paths come from `$HOME` or env (`~/kit-watch`, `~/.config/kit-watch/env`, `tailscale` on PATH) instead of being hard-coded.
2. The env file is parsed with `shlex` in-process, with the same result as the old `bash printf %s` for plain, quoted and `export` lines. Values never reach a command line.
3. When all six devices have been seen, kit-watch only writes `DISABLED`. It no longer edits its own crontab line.
4. Logged exception text for a failed `tailscale status` is now the exception type only.

## Tests

    cd hub/services/kit-watch && python3 -m unittest discover -s tests -v

`test_watchers.py` runs both scripts against a fake `tailscale` CLI, a fake webhook and a fake AgentMail API, with the Brussels hour pinned. It covers posting once, quiet hours, retry, all-seen disabling (crontab never called), dry run, env parsing and no secrets in logs. `test_install.py` runs `install.sh` against a fake `$HOME` with stub `systemctl`, `crontab` and `loginctl`. It checks re-runs (env and state kept byte for byte) and the `--remove-cron` guards and backup. Neither test touches a Pi, a real env file or a real crontab. `hub/tests/check.test.sh` covers the kit-watch drift checks.
