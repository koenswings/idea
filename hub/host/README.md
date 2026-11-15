# hub/host: host setup of the hub Pi `idea` (idea#486)

Root crontab, the remaining pi crontab, `boot.sh` and the Caddy config, so a fresh Pi can be given the same host setup. Root is used only for these host jobs and the system Caddy units, as proposal #408 describes. The Engine's pm2 process and the hub's user systemd units stay as `pi`.

| File | Deployed to | Source | Status |
|---|---|---|---|
| `cron.root` | root crontab | idea's live root crontab, read-only captures 2026-11-13 and 2026-11-15. Its active lines are also the Engine image `crondefs` | **captured**: 05:00 reboot, hourly avahi restart, `@reboot /usr/local/bin/boot.sh` |
| `cron.pi` | pi crontab | live pi crontab, 2026-11-13 | **captured**: no active entries. kit-watch and mail-watch belong to `services/kit-watch/` (idea#484). Three already-disabled lines are kept as comments |
| `boot.sh` | `/usr/local/bin/boot.sh` (mode 755) | not read (no Pi touched) | **placeholder**, to be filled from `capture.sh` |
| `caddy/Caddyfile` | `/etc/caddy/Caddyfile` (mode 644) | not read (no Pi touched) | **placeholder**, to be filled from `capture.sh` |

Not managed here: `/etc/cron.d/*` (one file there belongs to a non-IDEA personal app on idea and stays out of the repo), the `/etc/cron.{daily,hourly,weekly}` package jobs, and `/etc/cron.weekly/renew-tailscale-cert`. That last one is captured for review; see the open question in the PR.

## `install.sh`: the host step

    sudo hub/host/install.sh                 # PLAN: read-only, prints what --apply would change
    sudo hub/host/install.sh --apply         # make the changes (Koen's OK first)
    sudo hub/host/install.sh --apply --allow-remove   # also allow dropping live cron lines the repo lacks

- **Plan by default.** Without `--apply` nothing is written. File differences are shown as sizes and sha256 prefixes only, never contents. Crontab differences are shown line by line.
- **Never an empty, placeholder or unvalidated copy.** A repo file still marked `HUB-PLACEHOLDER` is skipped and reported. A `cron.root` with no active line is refused. The Caddyfile is installed only after `caddy validate --adapter caddyfile` passes. After that, `caddy` is **reloaded**, not restarted, and `caddy-api` is never touched.
- **Never drops a live job by accident.** If the live crontab has active lines the repo file lacks, the install is refused unless `--allow-remove` is given. kit-watch and mail-watch lines are always refused here: they are removed by `services/kit-watch/install.sh --remove-cron`, as `pi`.
- **Backups first.** Every replaced file or crontab is copied to `/var/backups/idea-hub/host/<stamp>/` (mode 700) before it changes. To roll back, put the file back (`sudo cp …`, or `sudo crontab -u root …/crontab.root`) and run `sudo systemctl reload caddy` for the Caddyfile.
- **Safe to re-run.** A matching host gives `ok` lines only and takes no backup.
- `hub/bootstrap.sh` calls this step (idea#487). Comparisons use **active** crontab lines only, the same as `hub/check.sh`.
- Do not use `--apply` on idea for a new 05:00 reboot or a Caddy change until Koen has OK'd that deploy. Today's `cron.root` equals the live one, so `--apply` there changes nothing until the placeholders are filled.

## `capture.sh`: read-only capture of what is still missing

    hub/host/capture.sh            # on idea as pi, under a fleet-state claim, with Steve's go

It reads `/usr/local/bin/boot.sh`, `/etc/caddy/*`, both crontabs, `systemctl cat` and the state of `caddy` and `caddy-api`, the graphify unit, the two kit-watch scripts and `renew-tailscale-cert`. It copies them into a new private folder under `/tmp` (mode 700) with `SHA256SUMS`. `/etc/cron.d` is listed by name only, and env files are never read. Root files are read with `sudo -n`, so there is no prompt. A secret-pattern scan prints only a **count** per file. Any non-zero count must be fixed before a copy goes into the repo: move the value into an env file and reference it, e.g. `{env.NAME}` in a Caddyfile. The host itself is not changed. The copies then go into a follow-up PR that replaces the two placeholders. That PR also confirms the kit-watch and graphify copies in `services/`.

## Check and tests

- `hub/check.sh --service host` reports, read-only: `boot.sh` and the Caddyfile byte for byte (a placeholder counts as drift: "repo copy not captured yet"), the active root crontab lines (`sudo -n crontab -l -u root`) and pi crontab lines against `cron.root` and `cron.pi`, and that `caddy.service` is active. The state of `caddy-api` is printed, not judged.
- `bash hub/host/tests/host.test.sh`: install.sh and capture.sh against a fake host tree, with stub `crontab`, `systemctl`, `caddy` and `sudo`. Box only.
