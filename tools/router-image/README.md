# IDEA router image (Cudy WR3000S v1)

Build of the image described in `proposals/2026-10-15-router-image-and-flashing.md` (idea#209).
`./build.sh [OUTDIR]` runs the official OpenWrt 25.12.5 Image Builder (x86_64 Linux; pinned
by sha256 in `config.env`) for profile `cudy_wr3000s-v1`. No compiling, ~1-4 min.

## What is in it
* OpenWrt 25.12.5 + `packages.txt`: LuCI (https), full wpad-mbedtls, tailscale, umdns,
  avahi-nodbus-daemon (mDNS reflector, idea#211), sqm (off), prometheus-node-exporter-lua.
* `/etc/uci-defaults/90-idea-setup` (first boot, once): runs `school-router-setup.sh`
  from idea#211 head `7eedd03` (`SETUP_REF`) without its reboot: LAN 10.42.0.1/24, Wi-Fi
  `IDEA` / `idea911!` (students 10.42.1.0/24, isolated) and `IDEA-Teachers` /
  `idea-teachers911!` (10.42.2.0/24), country ZW, Engines .2-.9 by vendor class
  `idea-engine`, firewall zones, `Teachers-Internet` rule **on** (idea#209: teacher internet on by default; untick the rule, or
  `uci set firewall.teachers_internet.enabled='0'`, to switch it off remotely), avahi reflector on
  br-lan/br-students/br-teachers, `idea.local` dnsmasq hotplug. Then the tailscale zone
  (no forwarding), the Starlink CGNAT DHCP exception (D10), root password `admin911!`,
  SSH on LAN (plus tailscale zone).
* `/etc/idea/version`, `/etc/sysupgrade.conf` keeps `/etc/tailscale/` and `/etc/idea/`.
* `/usr/share/idea/school-router-setup.sh` for `--check` on the router.

## Not in it
* No Tailscale auth key (flash station pushes it after boot; proposal 4.3).
* No per-school or per-router values. Sticker name is written later to `/etc/idea/sticker`.
* Not yet: LED/button scripts, captive DNS redirect, NTP server, health CGI, an on-router self-test
  beyond `school-router-setup.sh --check`.

## Flash station: how it logs in (idea#276)
No key is baked into the image: a station key in `files/etc/dropbear/authorized_keys` would make every router in
the field trust that station. A freshly flashed router only has the root password (`admin911!`, `config.env`), so
the station logs in with it, through `sshpass -e`:
* Put the password in a file the station user owns, mode 600, e.g. `~/.config/idea-router/root-password`, and set
  `IDEA_ROUTER_PASSWORD_FILE` to it (or pipe it to `idea-router-enrol --password-stdin`).
* The scripts pass it to `sshpass` in the `SSHPASS` environment variable only: never on a command line (so not in
  `ps`), never printed, never in a log. Password mode is for the first login on a fresh router only.
* Without a password file, `idea-router-enrol` uses key mode (`ssh -o BatchMode=yes` with the station's own key),
  as before, e.g. for a router that already trusts an admin key.
* Station needs: `sshpass`, `ssh`/`scp`, Node >= 20 and Chromium or Chrome (browser step), `sudo ip` for the
  temporary addresses. It never talks to MilkWise or any Engine.

## Tailscale enrol (flash station)
`idea-router-enrol [--password-stdin] <sticker> [10.42.0.1]` runs after the IDEA image has booted (proposal 4.3, 5.4):
writes `/etc/idea/sticker`, sets the hostname, copies the fleet key
(`~/.config/idea-router/fleet-authkey`, must be mode 600) to `/tmp/tskey` on the router, runs
`tailscale up --reset --auth-key=file:/tmp/tskey --advertise-tags=tag:idea --hostname=<sticker> --accept-dns=false --accept-routes=false`,
removes the key (also on failure), checks `tailscale status` shows it online with `tag:idea`, and logs to
`~/.local/state/idea-router/enrol.log` without the key or password. Re-running on an enrolled router pushes no key.
Password mode with `IDEA_ROUTER_PASSWORD_FILE` or `--password-stdin` (see above); key mode otherwise.

## Full flash: `idea-router-flash` (idea#277)
`idea-router-flash <sticker>-router <cudy-intermediate.bin> <idea-...-squashfs-sysupgrade.bin>`, router cabled to
the station's `eth1` (`FLASH_IFACE`), router on stock firmware. It runs the chain that worked on router 3:
1. Stock config backup through the stock web UI (`STOCK_URL`, admin password from `IDEA_STOCK_PASSWORD_FILE`).
2. Intermediate image through the stock upgrade page (`STOCK_UPGRADE_PATH`) in a headless Chromium driven by the
   committed CDP step `stock-ui.mjs`. The file's MD5 and size are checked locally (`INTERMEDIATE_MD5/SIZE`) and
   against what the page shows before it clicks proceed.
3. Temporary station address `192.168.1.50/24`, waits for the intermediate OpenWrt on `192.168.1.1`, board check.
4. `mtd2` (Factory) and `mtd3` (bdinfo) dumps, sha256 compared with the router.
5. `sysupgrade -b` backup of the intermediate image.
6. IDEA image copied over (`scp -O`), sha256 checked against `SHA256SUMS`, `sysupgrade -T`; 7. `sysupgrade -n`.
8. Temporary address `10.42.0.50/24`, waits for `/etc/idea/version` on `10.42.0.1` (password mode).
9. Self-test: board name and `school-router-setup.sh --check`. 10. `idea-router-enrol` in password mode.
11. Final `sysupgrade -b` backup (SECRET, see below).

Rules: every step refuses to continue on a mismatch (exit 6) and the next run refuses too until the operator has
looked and removed `<backups>/<sticker>/.state/MISMATCH`. Each finished step leaves `.state/<step>.done`; re-running
the same command resumes after the last finished step (it first re-checks the sha256 of every backup). On every exit,
failure included, it removes the temporary `eth1` addresses it added, the headless browser and its profile, and its
files in the router's `/tmp`. If a router does not come back it prints the Cudy TFTP recovery hint (proposal 6.3).
Log: `~/.local/state/idea-router/flash.log` (no secrets).

## Router backups are secret (idea#278)
Backups live in `~/router-backups/<sticker>/` on the flash station (`IDEA_ROUTER_BACKUPS`): folders mode 700,
files mode 600, each with a `.sha256`.
* The **final** sysupgrade backup (`sysupgrade-backup-final-*.tar.gz`, taken after enrol) contains `/etc/tailscale/`
  (kept by `files/etc/sysupgrade.conf`), i.e. the router's **Tailscale node identity**. Anyone holding it can restore
  it and appear on the tailnet as that router, with `tag:idea`. Treat it like a password.
* All router backups stay **on the flash station only**: never commit them, never attach them to issues or PRs,
  never copy them to shared drives, chats or email. `.gitignore` blocks `router-backups/` and `*sysupgrade-backup*`.
* The Factory/bdinfo dumps hold the router's radio calibration and MAC; keep them with the backups for repairs.

**If a backup leaks:** treat that router's identity as compromised.
1. Tailscale admin console (`https://login.tailscale.com/admin/machines`), find the router by its sticker name
   (`<sticker>-router`), `...` menu, **Remove** (removes the node and invalidates the leaked state).
2. Re-enrol the router: on the router `tailscale logout` (or a fresh `sysupgrade -n`), then `idea-router-enrol`
   from the station; it gets a new node key. Then take a new final backup and delete the leaked copy where you can.
3. Note it on the router's issue (no file attached, no key text).

## Tests (no router, no hardware)
* `test/idea-router-enrol.test.sh`: enrol with a mock ssh/scp/sshpass router, key and password mode, no leaks.
* `test/idea-router-enrol.dropbear.test.sh`: password mode over a real throwaway dropbear (password-only) on
  127.0.0.1 with real ssh/scp/sshpass; samples `ps` to prove the password is never in argv. Needs sudo.
* `test/idea-router-flash.test.sh`: the whole flash chain against a mock stock web UI (`test/mock-stock-ui.py`,
  driven by a real headless Chromium) and a mock router: resume, mismatches, cleanup, modes, no leaks.
Test passwords and keys are generated at test time and are obviously fake.

## Label values
`config.env` holds every value from the router label as `LABEL_TODO_*`. A build with any left
needs `ALLOW_LABEL_TODO=1` (dev build). If the label is not WR3000S V1.x, `PROFILE` is wrong.
