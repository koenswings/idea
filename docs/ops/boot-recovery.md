# Boot recovery: fstab loop mounts and what comes back after a reboot

**Status:** Authoritative (pool state as of 2026-10-13) · **Maintained by:** Atlas (Ops)
Sources (ops box): `duration-evidence/path-a-ready-r33/BOOT-RECOVERY.md` (2026-10-06), `path-a-ready-r39/READY.md`, `testmode-audit.md`, `post-reboot-20261008/HANG-ANALYSIS.md`, `path-a-stage2-20261009/D5-REBOOT-HOLD.md`.

## 1. Why
All Pis had a root cron `0 5 * * * /sbin/shutdown -r now` (plus hourly `systemctl restart avahi-daemon` and `@reboot /usr/local/bin/boot.sh`).
After the 05:00 reboot on 2026-10-06, idea01's duration fixture disks (ext4 **loop images**, mounted by hand) were gone. The Engine then saw bare folders with only `META.yaml`:
the empty disks looked right by luck, but `duration-add-files-001` was classified as an empty disk instead of `['app']`. **Not an Engine bug: a missing mount.**

## 2. What does come back on its own
- **Engine-managed instances** (in the store's instanceDB): yes. At boot the Engine undocks all previous disks, re-adds them from the `~/idea/duration-watch` sentinels and starts the instances. No restart policy is set on them, on purpose.
- **Non-store fixture containers** (`idea166-*`, `idea168-*`): only if they have a Docker restart policy. Set to `unless-stopped` (r33) for idea166-kiwix-live (idea01), idea168-kolibri-form3 and idea168-kolibri-g5a-khan (idea04). `idea166-nextcloud-live-*` on idea01 was left `restart=no` pending approval.

## 3. Loop mounts at boot (/etc/fstab)
One line per loop image, mounted directly at the slot path, before the Engine's pm2 unit:
```
# idea duration-test loop images (nofail; before Engine pm2-pi)
/home/pi/idea/duration-disk-images/idea-test-N.ext4.img /home/pi/idea/duration-disks/idea-test-N ext4 loop,nofail,x-systemd.before=pm2-pi.service 0 0
```
In place on idea01 for idea-test-3/4/5 (r33, 2026-10-06 05:49) and idea-test-6 (r39, 17:32).

Rules for applying it:
1. Back up first: `cp /etc/fstab /etc/fstab.bak-<run>-<ts>`.
2. Append the line(s), then `systemctl daemon-reload`. systemd adopts mounts that already exist.
3. Mount only the new target (`mount <target>`). **Never `mount -a`**: a loop entry can double-mount over a live mount.
4. Check: `findmnt --verify` (only the expected "[W] non-bind mount source … is a regular file" warnings), and the generated `*.mount` unit is active with `Before=pm2-pi.service`.
5. `nofail` means a missing image never blocks boot.

Rollback: `cp /etc/fstab.bak-<run>-<ts> /etc/fstab && systemctl daemon-reload`.

Caveat: data on the images now survives a reboot. A reboot no longer "resets" fixtures, so re-seed the empty and add-files images before a walk (Path A reset).

## 4. The 05:00 reboot during test work
- As last recorded (2026-10-11; check root crontab before relying on it), the 05:00 line is commented out on the pool (`#D5-HOLD-…#` prefix, backups in `~/idea/quarantine-stage2-20261009/`): idea01 since 2026-10-09/10, idea03 and idea04 since 2026-10-11. idea02 and wizardly-hugle keep it.
- Never schedule a walk across 05:00 where the reboot is active.
- Restore after the stage-2 proofs: remove the prefix (rollback notes per Pi in the D5 hold files).

## 5. Boot hang (idea01, 2026-10-08)
After the 05:00 shutdown idea01 did not reach userspace for ~4.5 h until a power cycle. The journal is volatile, so only indirect evidence exists; the hang was before the hardware watchdog arms (bootloader or kernel `rootwait` on the USB SSD).
Open suggestions (not applied): persistent journal on the pool, EEPROM update, cooling for idea01, BOOT_ORDER review.

## 6. After-reboot checklist
1. `findmnt` shows every loop slot as ext4 (`/dev/loopN`).
2. Engine up (pm2), Console 200, store-url correct, queues 0.
3. Instances Running per store; fixture containers up (start by hand if `restart=no`).
4. G5A Kolibri can crash in python-zeroconf when it starts together with Form3. If it hangs instead of exiting: `docker restart idea168-kolibri-g5a-khan`.
5. `check-fleet-health.sh --origin`.
