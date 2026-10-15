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

* Host: Linux amd64 with `qemu-user-static` (binfmt `aarch64` with the `F` flag) or a native arm64 Pi; `parted`,
  `e2fsprogs`, `mtools`, `xz-utils`. No vfat kernel module or `/dev/loopNpM` nodes needed (works in containers):
  the root partition is loop-mounted by offset, the FAT boot partition is edited with `mtools`.
* ~25 GB free disk; 30-60 min under qemu on an 8-core box.

## Secrets (never in git, never printed)

Copy `secrets.env.example` to `~/.config/idea-client-image/secrets.env` (chmod 600) or pass `--secrets`.
It holds the support **authorized_keys** path (public keys only), the **admin password hash** (`mkpasswd -m sha-512`)
and the per-school **Wi-Fi PSK**. `build.sh` refuses a secrets file inside the repo and a private key in the keys file;
`scan-secrets.sh` fails the build if a secret value appears anywhere except `/etc/shadow` (hash) and the root-only
NetworkManager profile (PSK).

## What the image does (proposal section)

| | |
|---|---|
| §4 accounts | `learner`: GDM autologin, no password, no sudo/adm/lpadmin, polkit denies network/software/users/time. `admin`: hidden, sudo, SSH key only (`AllowUsers admin`, no passwords), local password for `su - admin` |
| §6 apps | from `.deb` only (`client-image.conf`); **Chromium** `.deb` from `ppa:xtradeb/apps` (Ubuntu only ships Chromium as a snap; no Chrome for arm64), pinned so only `chromium*` comes from that PPA; build fails if any package has no arm64 candidate |
| §7 updates off | `unattended-upgrades`, `update-notifier`, Software, Pro client, fwupd removed; apt/fwupd/motd timers masked; `APT::Periodic::*=0`; snaps held forever at first boot; `snapd.refresh.timer` masked |
| §6 browser + icons | Chromium managed policy: homepage + bookmarks (Console, Kolibri, Nextcloud, Kiwix, Scratch, GeoGebra). **Desktop and app-menu icons** for Nextcloud, Kolibri, Kiwix (`idea-open` opens the URL in Chromium app mode) |
| server addressing | **One place:** the `SERVER_HOST`/`URL_*` block in `client-image.conf` → `/etc/idea-client/servers.conf`; bookmarks, icons and menu entries are generated from it. Server discovery for several servers on one network is a separate follow-up proposal |
| §8 first boot | `idea-firstboot`: hostname `idea-pc-<last4 serial>`, new SSH host keys and machine-id (nothing model-specific) |
| §5 reset B | `overlayroot` installed, off unless `OVERLAY=on`; `idea-client-mode overlay|normal|status` |
| §12 CI | `verify-image.sh` (in chroot) + `scan-secrets.sh` run on every build; non-zero exit fails the build |

The boot test and the Pi 400 ↔ Pi 500 swap test (§12) need hardware and are tracked separately.
