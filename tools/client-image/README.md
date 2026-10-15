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
sudo tools/client-image/build.sh [--base ubuntu-26.04.1-...+raspi.img.xz] [--secrets FILE] [--out DIR] [--work DIR] [--no-xz]
```

* Host: Linux amd64 with `qemu-user-static` (binfmt `aarch64` with the `F` flag) or a native arm64 Pi.
  Required tools (checked at start by `build.sh`): `losetup`, `mountpoint`, `fstrim` (util-linux), `parted`,
  `e2fsck`/`resize2fs` (e2fsprogs), `mcopy`/`mmd` (mtools), `xz` (xz-utils), `curl`, `git`, `sha256sum`, `truncate`,
  `chroot` (coreutils), `python3`; on amd64 also `qemu-aarch64-static`:
  `sudo apt install util-linux parted e2fsprogs mtools xz-utils curl git python3 qemu-user-static`.
* The chroot's apt sources are rewritten to `ports.ubuntu.com/ubuntu-ports` (arm64); the build stops if no arm64 lists come back. No vfat kernel module or `/dev/loopNpM` nodes needed (works in containers):
  the root partition is loop-mounted by offset, the FAT boot partition is edited with `mtools`.
* ~25 GB free disk; 30-60 min under qemu on an 8-core box.

## Secrets (never in git, never printed)

Copy `secrets.env.example` to `~/.config/idea-client-image/secrets.env` (chmod 600) or pass `--secrets`.
It holds the support **authorized_keys** path (public keys only) and the per-school **Wi-Fi PSK**. `build.sh` refuses a secrets file inside the repo and a private key in the keys file;
`scan-secrets.sh` fails the build if a secret value appears anywhere except the root-only NetworkManager profile (PSK).

**Local admin password rule:** the hidden `admin` account's local (console / `su - admin`) password follows Koen's
convention **`<accountname>911!`**, i.e. `admin911!` (`ADMIN_USER` in `client-image.conf`). It is a documented
convention, not a secret: `customise.sh` hashes it (SHA-512, random salt) at build time. SSH stays **key-only**
(`PasswordAuthentication no`, `AllowUsers admin`), so the password only works at the keyboard. `learner` has no password.

## What the image does (proposal section)

| | |
|---|---|
| §4 accounts | `learner`: GDM autologin, no password, no sudo/adm/lpadmin, polkit denies network/software/users/time. `admin`: hidden, sudo, SSH key only (`AllowUsers admin`, no passwords), local password for `su - admin` |
| §6 apps | from `.deb` only (`client-image.conf`); build fails if any package has no arm64 candidate |
| §7 updates off | `unattended-upgrades`, `update-notifier`, Software, Pro client, fwupd removed; apt/fwupd/motd timers masked; `APT::Periodic::*=0`; snaps held forever at first boot; `snapd.refresh.timer` masked |
| browser (idea#203 §1) | **Google Chrome stable**, official arm64 `.deb` pinned in `client-image.conf` (`CHROME_DEB`, `CHROME_DEB_SHA256`), fetched once into `work/` and sha-checked, installed offline; Google apt source + cron job removed, `apt-mark hold`. Fallback: `build.sh --browser chromium` (xtradeb PPA `.deb`, same hold + policies). Managed policy (`browser.sh`): home/startup = `file:///usr/share/idea/start.html`, `LocalNetworkAccessAllowedForUrls` = `file://*`, `http://*.local`, sign-in/sync/promos/default-browser prompt/component updates off |
| Console shortcut + discovery (idea#203 §2) | **One** "IDEA" shortcut (`idea-console.desktop`, app menu + learner desktop) opens `start.html`: home Engine (`idea-home.txt` on the FAT boot partition → `/etc/idea/home-engine` by `idea-home-engine.service` at boot) → last Engine that opened → `http://idea.local`, 1.5 s per probe; sticker-name field (strict hostname validation) always shown, prominent on failure; friendly not-found text, never a browser error. No per-app icons, no `/go`, no Nextcloud links, no Engine name or IP in the image |
| §8 first boot | `idea-firstboot`: hostname `idea-pc-<last4 serial>`, new SSH host keys and machine-id (nothing model-specific) |
| §5 reset B | `overlayroot` installed, off unless `OVERLAY=on`; `idea-client-mode overlay|normal|status` |
| idea#202 (2026-10-15) | `config.txt`: KMS overlay per model (`[pi4]` `vc4-kms-v3d` = Pi 400, `[pi5]` `vc4-kms-v3d-pi5` = Pi 500), none in `[all]`, `disable_fw_kms_setup=1` kept, stock cmdline - one image boots both. `curl`. Firefox snap removed from the seed (+ launchers); Chrome only. Chrome launchers + `google-chrome.desktop` override (`/usr/local/share/applications`) use `--password-store=basic`; policy `PasswordManagerEnabled=false`, Google as fixed default search (no choice screen), `PromotionsEnabled=false`, `initial_preferences` + `First Run` sentinel skip first-run. Desktop icon learner-owned 755, trusted by a one-shot learner autostart (`gio set … metadata::trusted true`, then `Hidden=true`). First-run off: LibreOffice `/etc/libreoffice/registry/idea.xcd`, GCompris `isFirstRun=false`, SuperTuxKart (`config-0.10`: `enable_internet=2`, seeded player Learner, `first-time=false`), gnome-initial-setup purged + done-file, GNOME welcome tour off (dconf). GeoGebra is not in the image (offline web app on the Engine). Icon: IDEA logo C (`files/idea-logo/`) as `idea-console` (hicolor scalable/256/48) for the shortcut and dock |
| first-login acceptance | `acceptance/first-login-check.sh CLIENT_IP [--jump idea03]` (from the box, TEST admin key, sudo via the `admin911!` convention over SSH stdin): learner Wayland autologin, gnome-screenshot of desktop + Chrome, gio trusted flag, trust autostart self-disabled, no gnome-initial-setup, Chrome profile (no choice screen pending, password store basic), LibreOffice profile vs xcd, SuperTuxKart seed. PASS/FAIL per item |
| §12 CI | `verify-image.sh` (in chroot) + `scan-secrets.sh` run on every build; non-zero exit fails the build |


Tests (no image build): `cd tests && npm i && npm test` (start.html in headless Chrome with mocked Engines); `tests/home-engine.test.sh`; `sudo tests/chroot-check.sh` (browser.sh + verify-browser.sh in a minimal arm64 Ubuntu rootfs; needs root network access for apt).
The boot test and the Pi 400 ↔ Pi 500 swap test (§12) need hardware and are tracked separately.
