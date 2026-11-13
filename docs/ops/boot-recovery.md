# Boot recovery: fstab loop mounts and what comes back after a reboot

**Status:** Authoritative (current roles as of 2026-11-13; historical incidents dated below) · **Maintained by:** Atlas (Ops)
Sources: Engine main (`AutoStart.ts`, `usbDeviceMonitor.ts` watch dir `/dev/engine`, `script/build_image_assets/crondefs`), `docs/grok-bot-setup.md` §4.6, `tools/README.md`, `fleet-state.json`, `tools/engine-image/`, and the 2026-10 ops-box notes cited in the historical sections (`duration-evidence/path-a-ready-r33/BOOT-RECOVERY.md`, `path-a-ready-r39/READY.md`, `testmode-audit.md`, `post-reboot-20261008/HANG-ANALYSIS.md`, `path-a-stage2-20261009/D5-REBOOT-HOLD.md`).

## Current fleet (2026-11-13)

| Host | Role now | Addresses |
|---|---|---|
| idea03 | Shared test/review pool (`role: spare`); Console main `ffab96d` | Tailscale 100.126.117.80, LAN 192.168.0.228 |
| idea04 | Shared test/review pool (`role: spare`); Console main `ffab96d` | Tailscale 100.108.39.45, LAN 192.168.0.113 |
| idea01 | Golden, read-only for tests (since 2026-10-28); never claimed | Tailscale 100.99.231.94, LAN 192.168.0.138 |
| idea02 | On hold (`role: fleet-pending`); not a pool Pi, never claimed | Tailscale 100.85.108.118, LAN 10.99.0.12 |
| Production | Hostname `idea` (fleet-state key `wizardly-hugle`) | `idea.tail2d60.ts.net`, Tailscale 100.115.60.6, LAN 192.168.0.231 |

pm2 runs as user `pi` (systemd unit `pm2-pi.service`). Engine and Console process changes must survive a reboot (`pm2 save`, and the unit enabled with `pm2 startup systemd -u pi`). Do not run pm2 as root.

idea01, idea03 and idea04 share the dev-pool store `automerge:2VroE…`. Production `idea` has its own store. Kits use the kit store `automerge:3Vvv…` (idea#452).

## 1. Why this runbook exists
On 2026-10-06 the pool still used a root cron `0 5 * * * /sbin/shutdown -r now` (plus hourly `systemctl restart avahi-daemon` and `@reboot /usr/local/bin/boot.sh`). After that 05:00 reboot, idea01's duration fixture disks (ext4 **loop images**, mounted by hand) were gone. The Engine then saw bare folders with only `META.yaml`: the empty disks looked right by luck, but `duration-add-files-001` was classified as an empty disk instead of `['app']`. **Not an Engine bug: a missing mount.**

The Engine image still ships those three cron lines in `script/build_image_assets/crondefs`. Treat the 05:00 line as live on a Pi until you have read that Pi's root crontab.

## 2. What does come back on its own
- **Engine-managed instances** (in the store's instanceDB): yes, when their disk is visible again. At boot the Engine's USB monitor walks the watch folder (default `/dev/engine`, from `90-docking.rules`) and mounts App Disks under `/disks`. Duration-test fixtures that still use the Stage 1 layout are the exception: they are re-added from `~/idea/duration-watch` sentinels with `IDEA_DISKS_ROOT=~/idea/duration-disks`. After the disk is docked, AutoStart (idea#176) starts the instance unless an operator stop is still in force. Engine-managed containers do not rely on a Docker restart policy; the Engine starts them.
- **Non-store fixture containers** (`idea166-*`, `idea168-*`): only if they have a Docker restart policy. As of 2026-10-06 (r33): `unless-stopped` for idea166-kiwix-live (idea01), idea168-kolibri-form3 and idea168-kolibri-g5a-khan (idea04). `idea166-nextcloud-live-*` on idea01 was left `restart=no` pending approval. Live presence was re-checked on 2026-11-13 on idea01, idea03 and idea04: leftover `idea166-*` / `idea168-*` containers were all **Exited**, and by then the idea03/idea04 leftovers already had `RestartPolicy=no`. Later the same day, under an Atlas claim, those idea03 and idea04 leftovers were renamed to `quarantine-20261113-*` and left Exited (see **Quarantined containers** below). idea01's four `idea166-*` leftovers were left in place (golden). Remove nothing else until a cleanup is agreed.

## 3. Loop mounts at boot (/etc/fstab)
Duration-test loop images need an fstab line so the slot path is mounted before the Engine's pm2 unit:
```
# idea duration-test loop images (nofail; before Engine pm2-pi)
/home/pi/idea/duration-disk-images/idea-test-N.ext4.img /home/pi/idea/duration-disks/idea-test-N ext4 loop,nofail,x-systemd.before=pm2-pi.service 0 0
```
Observed on **idea01** on 2026-11-13 17:29:36 CET: the four duration-test lines (idea-test-3/4/5/6) are still in `/etc/fstab`, but each is commented with a `#STAGE2-20261009#` prefix, so they do not mount at boot. `findmnt` has no `duration-disks` or loop-backed ext4 mounts (only `/` and `/disks/sdb1`). `/sbin/losetup -l` shows no loop device for those images (the only loop device is `/var/swap` on `loop0`; leave it alone). idea01 is golden and read-only: do not uncomment or edit fstab there unless Steve has a window.

Observed on **idea03** on 2026-11-13 17:28:40 CET: `/etc/fstab` has only the root and boot entries (no duration-test loop lines). No duration-disk mounts; `/sbin/losetup -l` likewise has no duration-test image (only `/var/swap` on `loop0`).

Observed on **idea04** on 2026-11-13 17:31 CET (read-only, under Steve's claim): `/etc/fstab` has only `proc`, `/boot/firmware` and `/` (no duration-test loop lines). There are no `/disks` mounts. `/sbin/losetup -l` shows no duration-test image (the only loop device is `/var/swap` on `loop0`; leave it alone).

Rules for applying a new line (pool Pis only, under a claim):
1. Back up first: `cp /etc/fstab /etc/fstab.bak-<run>-<ts>`.
2. Append the line(s), then `systemctl daemon-reload`. systemd adopts mounts that already exist.
3. Mount only the new target (`mount <target>`). **Never `mount -a`**: a loop entry can double-mount over a live mount.
4. Check: `findmnt --verify` (only the expected "[W] non-bind mount source … is a regular file" warnings), and the generated `*.mount` unit is active with `Before=pm2-pi.service`.
5. `nofail` means a missing image never blocks boot.

Rollback: `cp /etc/fstab.bak-<run>-<ts> /etc/fstab && systemctl daemon-reload`.

Caveat: data on the images now survives a reboot. A reboot no longer "resets" fixtures, so re-seed the empty and add-files images before a walk (Path A reset).

## 4. The 05:00 reboot during test work
The 05:00 reboot is defined in the **root crontab** (the same three lines the Engine image ships in `script/build_image_assets/crondefs`). It is not in the `pi` crontab, `/etc/crontab`, `/etc/cron.d`, or a systemd timer. A hold leaves the reboot line in place but comments it with a `#D5-HOLD-…#` marker (the Pi name and date in the marker differ). idea04 previously used `#DISKSTATION-HOLD`; that prefix was replaced on 2026-11-13.

- **idea01 (observed 2026-11-13 17:29:36 CET; golden, left untouched):** the D5 hold is still in place and was not changed. Root crontab (installed 2026-10-10 10:09:40 CET) has `#D5-HOLD-IDEA01-20261010# 0 5 * * * /sbin/shutdown -r now`. The hourly `systemctl restart avahi-daemon` and `@reboot /usr/local/bin/boot.sh` lines are still active. Backups remain in `~/idea/quarantine-stage2-20261009/` (`root-crontab.bak-20261009-1452`, `root-crontab.bak-20261010-1011`, plus `fstab.stage1`). Rollback: uncomment the 05:00 line with `sudo crontab -e` (remove only the `#D5-HOLD-IDEA01-20261010#` prefix), or restore from `~/idea/quarantine-stage2-20261009/root-crontab.bak-20261010-1011`. Do not edit idea01 without Steve's window.
- **idea03 (hold applied 2026-11-13 17:42:21 CET, under Atlas claim):** the 05:00 reboot is now held. Root crontab has `#D5-HOLD-idea03-20261113# 0 5 * * * /sbin/shutdown -r now`. The hourly avahi restart and `@reboot boot.sh` lines were left unchanged. Backup taken immediately before the hold: `/home/pi/crontab-root-backup-20261113T174221`. Rollback: uncomment the 05:00 line with `sudo crontab -e` (remove only the `#D5-HOLD-idea03-20261113#` prefix), or restore the backup with `sudo crontab /home/pi/crontab-root-backup-20261113T174221`.
- **idea04 (marker replaced 2026-11-13 17:44:59 CET, under Atlas claim):** the 05:00 reboot remains held; the previous `#DISKSTATION-HOLD` prefix was replaced with the D5 marker. Root crontab has `#D5-HOLD-idea04-20261113# 0 5 * * * /sbin/shutdown -r now`. The hourly avahi restart and `@reboot boot.sh` lines are still active and were not changed. Backup taken immediately before the replacement: `/home/pi/crontab-root-backup-20261113T174459`. Rollback: uncomment the 05:00 line with `sudo crontab -e` (remove only the `#D5-HOLD-idea04-20261113#` prefix), or restore the backup with `sudo crontab /home/pi/crontab-root-backup-20261113T174459` (that backup still has the `#DISKSTATION-HOLD` prefix).
- Production `idea` and idea02 were last recorded (2026-10-11) as still having the live 05:00 line; they were not re-checked here.
- The image default remains `0 5 * * * /sbin/shutdown -r now`. Later runbooks (scheduled backup, field-usage, hub services) still treat that reboot as current on production `idea` and on kits.
- Never schedule a walk across 05:00 where the reboot is active. Check the root crontab before relying on it.

## 5. Boot hang (idea01, 2026-10-08)
After the 05:00 shutdown idea01 did not reach userspace for ~4.5 h until a power cycle. The journal is volatile, so only indirect evidence exists; the hang was before the hardware watchdog arms (bootloader or kernel `rootwait` on the USB SSD).
Open suggestions (not applied): persistent journal on the pool, EEPROM update, cooling for idea01, BOOT_ORDER review. idea01 overheating is also why it is no longer in the quality-scan Engine-test chain (Steve, 2026-10-28).

## 6. After-reboot checklist
1. For any Pi that still uses loop fixtures: `findmnt` shows every loop slot as ext4 (`/dev/loopN`).
2. Engine up (`pm2` as `pi`), Console 200, store-url correct (pool `2VroE…`, production `idea` its own store, kits `3Vvv…`), queues 0.
3. Instances Running per store, subject to AutoStart (an operator-stopped app stays stopped). Start non-store fixture containers by hand if they have `restart=no`.
4. As last recorded: G5A Kolibri can crash in python-zeroconf when it starts together with Form3. The idea04 leftovers `idea168-kolibri-g5a-khan` and `idea168-kolibri-form3` were renamed to `quarantine-20261113-idea168-kolibri-g5a-khan` and `quarantine-20261113-idea168-kolibri-form3` on 2026-11-13 and left Exited; do not start them as part of a reboot recovery.
5. `check-fleet-health.sh --origin`.

## 7. Quarantined containers (2026-11-13)

Under Atlas claims, leftover Exited fixtures on idea03 and idea04 were renamed with `docker rename` only (not stopped, started, or removed). Reference checks found no Engine instance, process/pm2 arg, restart-policy, or running-container volume/network link that used those names or ids (a shared Docker `host` network is not a real coupling). idea01 was not touched.

| Pi | Old name | New name | Id | Image | Date |
|---|---|---|---|---|---|
| idea03 | `idea166-nextcloud-live-app` | `quarantine-20261113-idea166-nextcloud-live-app` | `39af4e842124ee66295bb8382680443e8a60855b7e8dd20644fc0d04d3202875` | `koenswings/nextcloud:1.0-31.0.1` | 2026-11-13 |
| idea03 | `idea166-nextcloud-live-db` | `quarantine-20261113-idea166-nextcloud-live-db` | `3971d6510966abe32a60db9c5c6d348b129954310de510ba8537e62172a1ea0f` | `koenswings/nextcloud-mariadb:1.0-11.7.2-MariaDB-ubu2404` | 2026-11-13 |
| idea03 | `idea166-kolibri-live` | `quarantine-20261113-idea166-kolibri-live` | `7fc08b4f64f2fa062608f5790e2723f2dc3e3fa8b0ff430926ea1ee2e2f1fea9` | `koenswings/kolibri:1.0-0.15.5-dev` | 2026-11-13 |
| idea04 | `idea168-kolibri-g5a-khan` | `quarantine-20261113-idea168-kolibri-g5a-khan` | `8aab26c796acd563f2812100373954993729b1a7f0395bff73c836ea67343c00` | `koenswings/kolibri:1.0-0.15.5-dev` | 2026-11-13 |
| idea04 | `idea168-kolibri-form3` | `quarantine-20261113-idea168-kolibri-form3` | `e8bc06774fc7658ed0f12c7e4a47931dbb3f5e48d4c408ebf26b097cde0b9810` | `koenswings/kolibri:1.0-0.15.5-dev` | 2026-11-13 |

idea03 apply window 17:42 CET: all three leftovers stayed Exited after the rename. `kid-kolibri-demo` (`bb580eb2907d`) was left Running. Disk B `nextcloud-files-b-001` was left Running. Sidecar `0d8f9984` was left Exited and untouched. Kid had already removed G5A/F3 instance `kolibri-st9ddvr2mf957oebpgv` (container `ddd2ef7d993a`); that container being gone is expected.

idea04 apply window 17:44 CET: both leftovers stayed Exited after the rename. No containers were Running on idea04.

**idea01 leftovers left in place** (golden; observed 2026-11-13 17:29:36 CET; not renamed). No `idea168-*`. All listed containers are Exited:

| Name | Status | Created | Image |
|---|---|---|---|
| `idea166-kiwix-live` | Exited (143), 2 weeks before the check | 2026-10-05 12:47:02 CEST | `ghcr.io/kiwix/kiwix-serve:3.8.2` |
| `idea166-nextcloud-live-app` | Exited (0), 2 weeks before the check | 2026-10-05 12:46:24 CEST | `koenswings/nextcloud:1.0-31.0.1` |
| `idea166-kolibri-live` | Exited (143), 6 weeks before the check | 2026-10-01 22:42:14 CEST | `koenswings/kolibri:1.0-0.15.5-dev` |
| `idea166-nextcloud-live-db` | Exited (0), 2 weeks before the check | 2026-10-01 22:42:14 CEST | `koenswings/nextcloud-mariadb:1.0-11.7.2-MariaDB-ubu2404` |
