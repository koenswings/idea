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
  (no forwarding), the Starlink CGNAT DHCP exception (D10), no root password (set at flash time by
  `idea-router-enrol` from `~/.config/idea-router/root-password`, idea#322),
  SSH on LAN (plus tailscale zone).
* `/etc/idea/version`, `/etc/sysupgrade.conf` keeps `/etc/tailscale/` and `/etc/idea/`.
* `/usr/share/idea/school-router-setup.sh` for `--check` on the router.

## Reproducible builds (idea#322)
* `build.sh` refuses a release unless the tree is clean and HEAD is a tag on `origin/main` (`--dev` for dev builds).
* Pinned: Image Builder (version + sha256), feed indexes (`feeds.lock`, sha256 per `packages.adb`), packages
  (`package-pins.tsv`; a release fails on drift). Cudy intermediate firmware recorded in `config.env` (sha256 + MD5 + size).
* Manifest per build in `manifests/router/<name>/`; `tools/repro/rebuild-check.sh` compares a rebuild.

## Not in it
* No root password (flash time, `idea-router-enrol`).
* No Tailscale auth key (flash station pushes it after boot; proposal 4.3).
* No per-school or per-router values. Sticker name is written later to `/etc/idea/sticker`.
* Not yet: LED/button scripts, captive DNS redirect, NTP server, health CGI, the
  `idea-router-flash` flash-station script (it will call `idea-router-enrol`), on-router self-test.

## Tailscale enrol (flash station)
`idea-router-enrol <sticker> [10.42.0.1]` runs after the IDEA image has booted (proposal 4.3, 5.4):
writes `/etc/idea/sticker`, sets the hostname, copies the fleet key
(`~/.config/idea-router/fleet-authkey`, must be mode 600) to `/tmp/tskey` on the router, runs
`tailscale up --reset --auth-key=file:/tmp/tskey --advertise-tags=tag:idea --hostname=<sticker> --accept-dns=false --accept-routes=false`,
removes the key (also on failure), checks `tailscale status` shows it online with `tag:idea`, and logs to
`~/.local/state/idea-router/enrol.log` without the key. Re-running on an enrolled router pushes no key.
Offline test: `test/idea-router-enrol.test.sh` (mock ssh/scp).

## Label values
`config.env` holds every value from the router label as `LABEL_TODO_*`. A build with any left
needs `ALLOW_LABEL_TODO=1` (dev build). If the label is not WR3000S V1.x, `PROFILE` is wrong.

### Rebuilding an old router image offline (idea#322)

The OpenWrt release feeds change within a release (for example, ca-bundle, tailscale and luasocket all moved between
the kit build and 2026-10-26). Because of that, a normal build fails the `feeds.lock` check once upstream moves.
To rebuild a shipped image, use its archived packages:

    PKG_ARCHIVE=/workspace/idea-archive/router/b2f00bc-openwrt-25.12.5/apk tools/router-image/build.sh --dev out/

This was verified on 2026-10-26: the b2f00bc kit image rebuilt from the archive was byte-identical (sha256 8e084dc0…).
Every build writes the exact .apk files it used to `$WORK/archive/<name>/` (or to `ARCHIVE_OUT`) with a `SHA256SUMS`.
