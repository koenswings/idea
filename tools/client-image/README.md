# tools/client-image — IDEA student client image

Implements the build pipeline of proposal **idea#201** (`proposals/2026-10-15-student-client-image.md`, §9).
Takes the official **Ubuntu Desktop 26.04.1 raspi** image (SHA-256 pinned and cross-checked with Ubuntu's
`SHA256SUMS`), customises it offline in an arm64 chroot, and writes:

```
out/idea-client-26.04-<YYYYMMDD>-<gitsha>.img.xz
out/idea-client-26.04-<YYYYMMDD>-<gitsha>.img.xz.sha256
out/idea-client-26.04-<YYYYMMDD>-<gitsha>.MANIFEST.txt   # every package + version
```

## Run

```
sudo tools/client-image/build.sh [--dev] [--base ubuntu-26.04.1-...+raspi.img.xz] [--out DIR] [--work DIR] [--no-xz] [--apt-pins FILE|none] [--manifest-out DIR]
```

* Host: Linux amd64 with `qemu-user-static` (binfmt `aarch64` with the `F` flag) or a native arm64 Pi.
  Required tools (checked at start by `build.sh`): `losetup`, `mountpoint`, `fstrim` (util-linux), `parted`,
  `sfdisk` (fdisk), `e2fsck`/`resize2fs`/`dumpe2fs` (e2fsprogs), `mcopy`/`mmd` (mtools), `xz` (xz-utils), `curl`, `git`, `sha256sum`, `truncate`,
  `chroot` (coreutils), `python3`; on amd64 also `qemu-aarch64-static`:
  `sudo apt install util-linux fdisk parted e2fsprogs mtools xz-utils curl git python3 qemu-user-static`.
* The chroot's apt sources are rewritten to `ports.ubuntu.com/ubuntu-ports` (arm64); the build stops if no arm64 lists come back. No vfat kernel module or `/dev/loopNpM` nodes needed (works in containers):
  the root partition is loop-mounted by offset, the FAT boot partition is edited with `mtools`.
* Image size: the last step shrinks the root fs to its used size + `ROOT_FREE_MB` and cuts the file, failing if the raw
  image exceeds `MAX_IMAGE_BYTES` (14,000,000,000; the smallest "16 GB" card seen holds 15,931,539,456). Labels, UUIDs
  and PARTUUID are unchanged; cloud-init `growpart` + `resizefs` expand root to the full card on first boot.
* ~25 GB free disk; 30-60 min under qemu on an 8-core box.

## Reproducible builds (idea#322)

* **Release = clean tree, HEAD exactly at a tag, HEAD on `origin/main`.** Otherwise `build.sh` refuses; `--dev`
  builds anything and names the image `...-dev` (never for the field). The version date is the commit date.
* **apt pinned:** `apt-pins.tsv` (package, version; the s14/s15 kit list) - requested packages are installed at
  their pinned versions and a release fails unless the full installed list equals the pins. Ubuntu ports has no dated
  snapshots, so the exact `.deb`s are archived per build with `tools/repro/archive-debs.py` (see `deployments/README.md`).
* **Inputs verified:** base image + Chrome `.deb` by sha256 (`client-image.conf`); mismatch = file kept as `.bad`, build fails.
* **Manifest:** every build writes `manifests/client/<name>/` (build.env, inputs.tsv, packages.tsv, content.tsv.xz,
  image.sha256). Commit it. `tools/repro/rebuild-check.sh --manifest-dir manifests/client/<name> --image <img>` (or
  `--rebuild`) compares content; volatile paths are listed in `tools/repro/volatile.txt`.

## Secrets: flash time only (never in the image, never in git, never printed)

The image holds **no** Wi-Fi key and **no** SSH keys (idea#322). After writing a card, before its first boot:

```
tools/client-image/set-card-timezone.sh --timezone Africa/Harare --boot /media/$USER/system-boot   # idea#208 (PR #319)
tools/client-image/set-card-secrets.sh --boot /media/$USER/system-boot    # files from ~/.config/idea-client-image/secrets.env
```

`set-card-secrets.sh` writes `idea-secrets/wifi-psk` and `idea-secrets/admin_authorized_keys` to the boot partition;
on first boot `idea-firstboot` runs `idea-secrets-apply` (writes the root-only NetworkManager profile from
`/usr/share/idea/IDEA.nmconnection.template`, installs admin's keys), then wipes the files from the boot partition.
Copy `secrets.env.example` to `~/.config/idea-client-image/secrets.env` (chmod 600). `scan-secrets.sh` fails the build
if a Wi-Fi profile, psk, admin authorized_keys, private key or Tailscale key is in the image.

**Local admin password rule:** the hidden `admin` account's local (console / `su - admin`) password follows Koen's
convention **`<accountname>911!`**, i.e. `admin911!` (`ADMIN_USER` in `client-image.conf`). It is a documented
convention, not a secret: `customise.sh` hashes it (SHA-512, random salt) at build time. SSH stays **key-only**
(`PasswordAuthentication no`, `AllowUsers admin`), so the password only works at the keyboard. `learner` has no password.

## What the image does (proposal section)

| | |
|---|---|
| §4 accounts | `learner`: GDM autologin, no password, no sudo/adm/lpadmin, polkit denies software/users/time (Wi-Fi is open to learner since idea#285). `admin`: hidden, sudo, SSH key only (`AllowUsers admin`, no passwords), local password for `su - admin` |
| §6 apps | from `.deb` only (`client-image.conf`); build fails if any package has no arm64 candidate |
| §7 updates off | `unattended-upgrades`, `update-notifier`, Software, Pro client, fwupd removed; apt/fwupd/motd timers masked; `APT::Periodic::*=0`; snaps held forever at first boot; `snapd.refresh.timer` masked |
| browser (idea#203 §1) | **Google Chrome stable**, official arm64 `.deb` pinned in `client-image.conf` (`CHROME_DEB`, `CHROME_DEB_SHA256`), fetched once into `work/` and sha-checked, installed offline; Google apt source + cron job removed, `apt-mark hold`. Fallback: `build.sh --browser chromium` (xtradeb PPA `.deb`, same hold + policies). Managed policy (`browser.sh`): home/startup = `file:///usr/share/idea/start.html`, `LocalNetworkAccessAllowedForUrls` = `file://*`, `http://*.local`, sign-in/sync/promos/default-browser prompt/component updates off |
| Console shortcut + discovery (idea#203 §2) | **One** "IDEA" shortcut (`idea-console.desktop`, app menu + learner desktop) opens `start.html`: home Engine (`idea-home.txt` on the FAT boot partition → `/etc/idea/home-engine` by `idea-home-engine.service` at boot) → last Engine that opened → `http://idea.local`, 1.5 s per probe; sticker-name field (strict hostname validation) always shown, prominent on failure; friendly not-found text, never a browser error. No per-app icons, no `/go`, no Nextcloud links, no Engine name or IP in the image |
| time zone (idea#208) | Image default **UTC** (`TIMEZONE="UTC"`), no country zone baked in. The school zone is set at flash time: a one-line `idea-timezone.txt` (`Area/City`, tz database name) on the FAT boot partition, written by `set-card-timezone.sh --timezone Africa/Harare --boot <mounted boot partition>` or by the Engine's Flash step (passes the Engine's own zone). `idea-timezone.service` applies it on **every** boot (`timedatectl set-timezone`, needed because reset-on-reboot discards `/etc` changes); a missing or invalid file leaves UTC |
| §8 first boot | `idea-firstboot`: hostname `idea-pc-<last4 serial>`, new SSH host keys and machine-id (nothing model-specific) |
| §5 reset B | Reset-on-reboot **ON by default** (`OVERLAY=on`, 2026-10-16): tmpfs overlay over root, every write erased at reboot. Armed once by `idea-overlay-arm.service` after first-boot setup, then one automatic reboot. Switch: `sudo idea-client-mode normal|overlay|status` (see *Reset on reboot*) |
| idea#202 (2026-10-15) | `config.txt`: KMS overlay per model (`[pi4]` `vc4-kms-v3d` = Pi 400, `[pi5]` `vc4-kms-v3d-pi5` = Pi 500), none in `[all]`, `disable_fw_kms_setup=1` kept, stock cmdline - one image boots both. `curl`. Firefox snap removed from the seed (+ launchers); Chrome only. Chrome launchers + `google-chrome.desktop` override (`/usr/local/share/applications`) use `--password-store=basic`; policy `PasswordManagerEnabled=false`, Google as fixed default search (no choice screen), `PromotionsEnabled=false`, `initial_preferences` + `First Run` sentinel skip first-run. Desktop icon learner-owned 755, trusted by a one-shot learner autostart (`gio set … metadata::trusted true`, then `Hidden=true`). First-run off: LibreOffice `/etc/libreoffice/registry/idea.xcd`, GCompris `isFirstRun=false`, SuperTuxKart (`config-0.10`: `enable_internet=2`, seeded player Learner, `first-time=false`), gnome-initial-setup purged + done-file, GNOME welcome tour off (dconf). GeoGebra is not in the image (offline web app on the Engine). Icon: IDEA logo C (`files/idea-logo/`) as `idea-console` (hicolor scalable/256/48) for the shortcut and dock |
| first-login acceptance | `acceptance/first-login-check.sh CLIENT_IP [--jump idea03]` (from the box, TEST admin key, sudo via the `admin911!` convention over SSH stdin): learner Wayland autologin, gnome-screenshot of desktop + Chrome, gio trusted flag, trust autostart self-disabled, no gnome-initial-setup, Chrome profile (no choice screen pending, password store basic), LibreOffice profile vs xcd, SuperTuxKart seed. PASS/FAIL per item |
| §12 CI | `verify-image.sh` (in chroot) + `scan-secrets.sh` run on every build; non-zero exit fails the build |


Tests (no image build): `cd tests && npm i && npm test` (start.html in headless Chrome with mocked Engines); `tests/home-engine.test.sh`; `tests/timezone.test.sh`; `sudo tests/chroot-check.sh` (browser.sh + verify-browser.sh in a minimal arm64 Ubuntu rootfs; needs root network access for apt).
The boot test and the Pi 400 ↔ Pi 500 swap test (§12) need hardware and are tracked separately.

## Reset on reboot (overlay) - on by default

Since 2026-10-16 (idea#202) every client card resets on each reboot: the root file system is mounted read-only under a
tmpfs overlay, so anything a learner (or admin) changes is gone after the next reboot.

* **How it is switched:** kernel argument `overlayroot=tmpfs` in `/boot/firmware/current/cmdline.txt`. Ubuntu 26.04 boots
  a dracut initramfs, and overlayroot's dracut hook reads only the kernel command line - `/etc/overlayroot.conf` is
  kept in sync but is not what switches it. The stock firmware initrd has no overlay hooks, so `customise.sh` rebuilds
  it with the `overlayfs` + `overlayroot` dracut modules plus every driver/firmware of the stock initrd and copies it to
  `/boot/firmware/current/initrd.img`.
* **First boot runs once, on the real disk:** the card ships with the overlay *off*. On first boot cloud-init
  `growpart`/`resizefs` grow root to the card, `idea-firstboot` sets hostname/SSH host keys/machine-id, snaps seed; then
  `idea-overlay-arm.service` (before GDM) adds `overlayroot=tmpfs`, writes `/var/lib/idea-overlay-armed` and reboots
  once. All done-markers are on the real disk, so none of this repeats. Expect one extra reboot ~1-2 min after the
  very first power-on. The learner's desktop-icon trust (`idea-trust-desktop` autostart) re-runs at each login after a
  reboot, because the learner's home is reset too.
* **Turn it off in the field** (e.g. a teacher needs files to survive): log in as admin, then
  `sudo idea-client-mode normal` and reboot. The boot partition is not under the overlay, so this works from overlay mode
  and survives the reboot; the arm service never re-arms (marker present). Turn it back on: `sudo idea-client-mode overlay`
  and reboot. `idea-client-mode status` shows the next-boot and running mode.
* **Making a lasting change while the overlay is on:** switch it off, reboot, change, switch it on, reboot.
* Build with `OVERLAY=off` in `client-image.conf` to ship cards that never arm the overlay.

* **Shrink (idea#322):** `shrink-image.sh` (called by `build.sh`) cuts the root to used + `ROOT_FREE_MB`; if that exceeds `MAX_IMAGE_BYTES` it cuts to the cap while at least `ROOT_FREE_MIN_MB` stays free. This is the step s16 needed by hand (s16 = 13,999,996,928 bytes, reproduced by the plan test). Tests: `tests/shrink.test.sh`.
