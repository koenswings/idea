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
  `idea-engine`, firewall zones, `Teachers-Internet` rule off, avahi reflector on
  br-lan/br-students/br-teachers, `idea.local` dnsmasq hotplug. Then the tailscale zone
  (no forwarding), the Starlink CGNAT DHCP exception (D10), root password `admin911!`,
  SSH on LAN (plus tailscale zone).
* `/etc/idea/version`, `/etc/sysupgrade.conf` keeps `/etc/tailscale/` and `/etc/idea/`.
* `/usr/share/idea/school-router-setup.sh` for `--check` on the router.

## Not in it
* No Tailscale auth key (flash station pushes it after boot; proposal 4.3).
* No per-school or per-router values. Sticker name is written later to `/etc/idea/sticker`.
* Not yet: LED/button scripts, captive DNS redirect, NTP server, health CGI, the
  `idea-router-flash` flash-station script, `test/`.

## Label values
`config.env` holds every value from the router label as `LABEL_TODO_*`. A build with any left
needs `ALLOW_LABEL_TODO=1` (dev build). If the label is not WR3000S V1.x, `PROFILE` is wrong.
