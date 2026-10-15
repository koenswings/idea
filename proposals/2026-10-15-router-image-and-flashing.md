---
title: "IDEA School Router – Image and Automated Flashing"
subtitle: "One OpenWrt image for every Cudy WR3000S, flashed and checked by a script"
audience: "Proposal · Status: Draft for Koen · 15 October 2026"
---

**Author:** Steve (Lead Bot)
**Date:** 2026-10-15
**Status:** Draft. Open decisions in section 10.

# 1. Problem

Today a school router is set up by hand, following section 3 of the school server install manual
(`docs/manuals/install/install-manual-school-server/`): two firmware uploads in a browser, a calibration backup,
`school-router-setup.sh`, then Tailscale by hand with the auth key typed in. That is about an hour per router,
easy to get wrong, and every router ends up slightly different.

Koen's requirements (15 October 2026):

* An **IDEA-specific OpenWrt image**, built with the official OpenWrt **Image Builder** plus a **uci-defaults
  first-boot script**. It comes up with Tailscale and the `IDEA` Wi-Fi already working.
* Default passwords follow the IDEA convention `<name>911!`: Wi-Fi `IDEA` uses `idea911!`, the router login is
  `root` / `admin911!`.
* An **automated flashing procedure**: first flash from Cudy stock firmware through Cudy's intermediate OpenWrt
  image, then `sysupgrade` to the IDEA image. It should be scripted from a laptop or Pi over Ethernet, and later
  become a **flash station** in the Console/Engine.
* Steve's own suggestions for further customisation.

Koen has bought Cudy WR3000S routers and collects them on 16 October. Their hardware revision is not known yet.

# 2. What stays the same (school design of 13–14 October)

This proposal changes **how** the router gets its settings, not **what** they are. The existing design stays:

* Every school uses the **same addresses**: router `10.42.0.1`, Engines on `10.42.0.0/24`, students on Wi-Fi
  `10.42.1.0/24`, teachers on `10.42.2.0/24`. There are no school numbers.
* **Two PoE Pi 5 Engines** behind the Cudy. **Starlink** in bypass mode on the Cudy WAN port.
* Wi-Fi **`IDEA`** (students) reaches the Pis only, **never** the WAN. Client isolation is on.
* Wi-Fi **`IDEA-Teachers`** gets internet through **one** firewall rule, `Teachers-Internet`, which is off by default
  and can be switched on and off (later from the Console).
* **Tailscale is always on** on the router and the Pis, with the one fleet tag `tag:idea` and one fleet auth key.
  There are no per-school keys or tags. ACL: admins → `tag:idea`; `tag:idea` reaches nothing.
* The router's DNS is the **fallback for `idea.local`** (mDNS on the Engines is the main path).
* Pis **move between schools without admin work**. Pis get **sticker names** (two words, for example `brave-otter`).

The image simply bakes `school-router-setup.sh` (manual Appendix A) and `router-tailscale-zone.sh` (A.2) into the
first boot, so the manual and the image share one source of truth.

# 3. The hardware: Cudy WR3000S v1 (checked on the web, 15 October 2026)

| Fact | Value | Source |
|---|---|---|
| OpenWrt support | Yes, **WR3000S v1**, since **24.10.0**; current stable **25.12.5** | [1], [3], [4] |
| SoC / RAM / flash | MediaTek **MT7981B**, 2 × 1.3 GHz, **256 MB RAM**, **128 MB SPI-NAND** | [1], [5] |
| Ports | 5 × 1 GbE (1 WAN, 4 LAN), no 2.5 GbE, no USB | [1] |
| Wi-Fi | MT7981 + MT7976CN, 2.4 GHz 2×2 ax, 5 GHz ax | [1] |
| Power | 12 V DC barrel | [1] |
| OpenWrt target / profile | `mediatek/filogic`, profile `cudy_wr3000s-v1` | [3], [4] |
| Official sysupgrade image | `openwrt-25.12.5-mediatek-filogic-cudy_wr3000s-v1-squashfs-sysupgrade.bin`, SHA-256 `b0a26c80…aa8b2` | [4] |
| Image Builder | `openwrt-imagebuilder-25.12.5-mediatek-filogic.Linux-x86_64.tar.zst` | [6] |
| Tailscale package | `tailscale-1.102.3-r1.apk`, **10.5 MB** compressed (aarch64_cortex-a53) | [7] |
| 24.10 branch | still maintained, latest **24.10.8** | [3] |

**Does Tailscale fit?** Yes, easily. On a 128 MB NAND the wiki reports about 48 MiB free overlay on the stock
OpenWrt image [1]. In our image Tailscale is **inside the squashfs** (compressed, read-only), so it does not use the
overlay at all; the 10.5 MB package is a fraction of the ~100 MB UBI space. The `tailscaled` process uses about
30–50 MB of RAM at runtime, which fits in 256 MB next to dnsmasq, hostapd and LuCI. We will measure free RAM in the
test plan (section 9) rather than trust these numbers.

**Release choice:** build on **25.12.5**, the release the install manual already uses. 25.12 uses `apk` instead of
`opkg`; the Image Builder hides this difference. 24.10.8 is the fallback if 25.12 shows a problem on this device.

## 3.1 Which revision did Koen get? (do this tomorrow)

**From the label** (bottom of the router):

1. Model must read **WR3000S** and hardware version **V1.x**. WR3000, WR3000H, WR3000E and WR3000P are other devices
   with other images. Anything other than WR3000S V1 → stop.
2. Read the **serial number**. Serials that start with `S000` carry the production year and week (YYWW) in
   characters 9–12 [1]. Example: `S000xxxx2611xxxxx` → 2026, week 11.
3. **Week 2543 or later** (from November 2025) means the **new ESMT F50L1G41LC flash chip** [1], [2]. Those units
   need the **new** Cudy intermediate image (20251119 build) and OpenWrt 24.10.5 or later. 25.12.5 qualifies.
   Since Koen bought them in 2026, assume the new chip.

**From the stock web UI** (`http://192.168.10.1` or `http://cudy.net`, laptop on a LAN port):

* **Status / System** (or the footer) shows model, **hardware version** and **firmware version**.
* Note the firmware version. Recent stock (2.4.6 and later) first asks to create an admin password [1].
  Never *downgrade* stock to 2.3.x or older on a new-flash unit [2].

**From the intermediate image** (the script does this automatically, section 6): over SSH the flash station reads
`/proc/mtd`, `dmesg | grep -i spi-nand` (shows the chip name) and the board name, and refuses to go on if the
board is not `cudy,wr3000s-v1`.

# 4. The IDEA router image

## 4.1 How it is built

A script in the repo, `tools/router-image/build.sh`, runs the official Image Builder (no compiling, 2–3 minutes):

```bash
make image PROFILE=cudy_wr3000s-v1 \
  PACKAGES="luci luci-ssl tailscale umdns luci-i18n-base-en -wpad-basic-mbedtls wpad-mbedtls \
            luci-app-sqm sqm-scripts prometheus-node-exporter-lua ..." \
  FILES=files/ EXTRA_IMAGE_NAME=idea-<version>
```

* `files/` holds the IDEA overlay: `/etc/uci-defaults/90-idea-setup` (the first-boot script),
  `/etc/idea/version`, `/etc/sysupgrade.conf` (keep-list), the banner, and the LED/button scripts.
* The **first-boot script** is `school-router-setup.sh` turned into a uci-defaults file: it runs once at the
  first boot after a flash, writes all settings with `uci`, and is then deleted by OpenWrt automatically.
  It is **idempotent** (deletes and re-creates its own sections), so running it twice gives the same result.
* The output is **one image for every school** (no per-school values), named
  `idea-router-<version>-cudy_wr3000s-v1-squashfs-sysupgrade.bin`, with a `SHA256SUMS` file.
* The build pins the Image Builder by version **and SHA-256**, so the same inputs always give the same image.
  CI can build it; the release is attached to a GitHub release like the client image.

## 4.2 What the first boot sets

| Area | Setting |
|---|---|
| System | Hostname = the router's **sticker name** (section 5.4), time zone `Africa/Harare` (CAT-2), LuCI in English |
| Login | `root` / `admin911!` (open decision D2); SSH (dropbear) on LAN and Tailscale only, not on WAN or Wi-Fi |
| LAN | `10.42.0.1/24`; DHCP pool `.100–.199`; `.2–.99` reserved for fixed devices |
| Wi-Fi | `IDEA` (psk2, `idea911!`, isolation on) → `students` `10.42.1.0/24`; `IDEA-Teachers` (psk2, `idea-teachers911!`) → `teachers` `10.42.2.0/24`; both bands; country `ZW` |
| Firewall | as the manual: students/teachers → only DHCP, DNS and the Engines; `Teachers-Internet` rule present, **off** |
| DNS | dnsmasq answers `idea.local` with the live Engine addresses (section 5.2); everything else is forwarded upstream only for LAN and teachers |
| mDNS | `umdns` reflects mDNS between LAN and the Wi-Fi zones, as the client-browser proposal requires |
| Tailscale | `tailscale up --auth-key=file:… --advertise-tags=tag:idea --hostname=<sticker>`, `tailscale0` in its own zone with **no forwarding** (unchanged from manual 3.7) |
| Updates | none automatic; a new IDEA image is the only update (same rule as the client image) |

## 4.3 The fleet auth key: never in git, never in the image file

This is the one real secret. The rules:

* The key is **not** in the repo and **not** in the published image. If it were in the image, anyone who downloads
  an image could join the IDEA tailnet as `tag:idea`.
* The flash station puts it on the router **after** the IDEA image has booted, over SSH on the LAN cable:
  `scp` to `/tmp/tskey` (RAM only), `tailscale up --auth-key=file:/tmp/tskey`, then `rm`. It never appears on a
  command line or in a log.
* The key itself: **reusable, pre-authorised, tagged `tag:idea`**, not ephemeral (an ephemeral router would vanish
  from the tailnet when it is offline for a while, for example during a power cut). Tagged devices have key expiry
  off by default, so the router stays on after the key expires [8].
* The flash station reads it from `~/.config/idea-router/fleet-authkey` (mode 600), the same pattern as the client
  image's `secrets-test.env`. Rotating the key does not touch any router already enrolled.
* **Alternative (D4):** bake the key into a *private* build for a field installer who has no flash station. Then
  the built file itself is a secret and must never be uploaded to a release.

The Wi-Fi and root passwords are **not** secret by design (Koen, 15 October: easy, well-known defaults; teachers
can change them). They may be in the repo.

# 5. Customisation suggestions (evaluated)

**Recommended now** marks what I propose for the first image. "Later" means a separate step.

| # | Idea | Verdict | Why / how |
|---|---|---|---|
| 1 | Fixed LAN IP `10.42.0.1` + DHCP pool | **Now** | Already the design. |
| 2 | DHCP reservations for the Engines | **Now, changed** | MAC reservations break "Pis move without admin". Instead the Engines send DHCP vendor class `idea-engine`; dnsmasq gives that class addresses from `.2–.9` (section 5.1). |
| 3 | `idea.local` → Engines in router DNS | **Now** | A dnsmasq lease script keeps `idea.local` = the live Engine leases (section 5.2). |
| 4 | Sticker hostname for the router | **Now** | Same word list as the Pis; used for hostname and Tailscale name (section 5.4). |
| 5 | Firewall split students/teachers | **Now** | Already the design; image just bakes it in. |
| 6 | Captive/landing page → `idea.local` | **Now, light** | DNS hijack only: on `IDEA` every unknown name resolves to the router, which redirects HTTP to `http://idea.local`. Phones then show "sign in to network" and open the IDEA start page. No captive-portal package. |
| 7 | No auto-update | **Now** | No `attendedsysupgrade`, no cron updates. New image = update. |
| 8 | NTP without internet | **Now** | Router serves NTP to LAN/Wi-Fi (`sysntpd` server on). Upstream: pool via Starlink when up, and the Engines as peers. No RTC on either side, so we accept "time is right once Starlink was up once". |
| 9 | LuCI language | **Now** | English only (smaller, matches manuals). Add `luci-i18n-base-fr` etc. later per country. |
| 10 | Factory-reset behaviour | **Now** | The IDEA defaults live in the **squashfs** (uci-defaults), so the reset button / `firstboot` gives back the **IDEA** router, not plain OpenWrt. Only the Tailscale identity is lost (section 5.5). |
| 11 | Sysupgrade keep-list | **Now** | `/etc/sysupgrade.conf` keeps `/etc/tailscale/` (identity), `/etc/idea/` (sticker name, school-local changes). An image upgrade keeps the router on the tailnet with the same name. |
| 12 | Remote fleet monitoring over Tailscale | **Now** | `prometheus-node-exporter-lua` (or a tiny `/cgi-bin/idea-health` JSON) on the tailscale zone only. Atlas's fleet-health check reads it: uptime, WAN up, Starlink reachable, clients per SSID, free RAM. Needs one ACL line: admins → `tag:idea:9100` is already covered by admins → `tag:idea`. |
| 13 | Backup/restore config | **Now, small** | The flash station stores `sysupgrade -b` backups + the Factory/bdinfo calibration dump per serial in the IDEA backup area, not in git. |
| 14 | LED / button behaviour | **Now, small** | Status LED: blink while first boot runs, solid when Tailscale is up, slow blink when WAN is down. Reset button: short press = reboot, 10 s = IDEA factory reset (OpenWrt default). WPS button: **disabled** (WPS bypasses the Wi-Fi password). |
| 15 | Logging | **Now** | Logs in RAM (OpenWrt default, protects the NAND), 512 KB ring; Atlas pulls `logread` over Tailscale when needed. No remote syslog yet. |
| 16 | Bandwidth limits | **Later** | SQM (`cake`) on WAN only matters once teachers have internet. Package in the image, **off** by default. |
| 17 | Content filtering on teacher Wi-Fi | **Later (D6)** | Cheap option: dnsmasq forwards teacher DNS to a filtering resolver (e.g. a family DNS service) and blocks DoH/DoT. Real filtering needs policy decisions first. |
| 18 | Starlink WAN + 4G fallback | **Later (D7)** | WR3000S has **no USB**, so 4G needs an external 4G router/hotspot on a LAN port as a second WAN, with `mwan3`. Hardware decision first. |
| 19 | Expose a Tailscale subnet route | **No** | Contradicts "tag:idea reaches nothing / no subnet routes", and every school has the same `10.42.0.0/24`, so routes would collide. Admins reach each device directly. |
| 20 | Per-school passwords | **No** | Koen chose the `<name>911!` defaults. |

## 5.1 Engines get fixed addresses without MAC reservations

Each Engine sets DHCP option 60 (vendor class) to `idea-engine` (one line in its NetworkManager connection,
done by the Engine installer). The router has:

```
dhcp-vendorclass=set:engine,idea-engine
dhcp-range=tag:engine,10.42.0.2,10.42.0.9,12h
```

So the first two Engines at any school get addresses in `.2–.9`, with no per-Pi configuration. The firewall allows
students and teachers to the whole `10.42.0.2–10.42.0.9` range instead of exactly `.2` and `.3`. This replaces the
`PI1_MAC` / `PI2_MAC` fields in the manual. (The reserved switch address `.4` moves to `.10`.)

## 5.2 `idea.local` in the router DNS

A dnsmasq `dhcp-script` writes the current Engine leases into `/tmp/hosts/idea` (`10.42.0.x idea.local`) and reloads
dnsmasq on every lease change. When one Engine is switched off, its lease ages out and only the live one is
answered. This matches the takeover design (Axle, #203): mDNS from the holder is primary, the router is the backup.

## 5.3 First boot flow

1. Flash station writes the IDEA image (section 6).
2. First boot: `90-idea-setup` runs, sets everything in 4.2, LED blinks.
3. Flash station sends the sticker name and the fleet auth key over SSH; the router joins Tailscale; LED solid.
4. Flash station runs the self-test (section 9.1) and prints the sticker label.

## 5.4 Router sticker name

The flash station picks a two-word name from the same word list as the Pis (`provision-fleet.sh … auto`), checks
it is unused in the tailnet, writes it to `/etc/idea/sticker` and prints a label with: sticker name, `IDEA` Wi-Fi /
`idea911!`, `http://10.42.0.1` and the Cudy serial. The name is kept across upgrades (keep-list) and across a
factory reset only if we choose to (D5).

## 5.5 What a factory reset does

The reset gives back the IDEA defaults (Wi-Fi, firewall, `10.42.0.1`), so a school never ends up with an open
router. It also erases the Tailscale identity, so the router is **off the tailnet** until someone re-enrols it.
Options for D5: (a) accept this: a local helper calls support, we re-enrol over the LAN with the flash station or a
Pi; (b) let an Engine on the LAN re-enrol the router automatically (the Engine has a Tailscale identity and could
push the key over SSH). I recommend (a) for now and (b) as part of the Console flash station.

# 6. Automated flashing

## 6.1 Two steps, because Cudy stock only accepts Cudy-signed firmware

```
Cudy stock (192.168.10.1)  --web upload-->  Cudy intermediate OpenWrt (192.168.1.1, SSH root, no password)
      --scp + sysupgrade -n-->  IDEA image (10.42.0.1)  --SSH: sticker + auth key + self-test-->  done
```

* **Step 1 (stock → intermediate)** is a web form in Cudy's UI. It is the only step that is not plain SSH. The
  script `idea-router-flash` automates it with HTTP requests the way the browser does (login, upload, confirm) for
  the stock version we find tomorrow; if Cudy's UI changes, the script falls back to telling the operator
  "upload this file in the browser now" and waits for `192.168.1.1` to answer. **This needs testing on the real
  router before we rely on it.**
* The intermediate image must be the **20251119 build** for new-flash units, MD5 `403e276f…1a137`, size
  14,945,872 bytes [1], [2]. The script checks both before uploading. The WR3000H/P files have almost the same names.
* **Step 2 (intermediate → IDEA)**: the script checks the board name, dumps `Factory` and `bdinfo`
  (`/dev/mtd2`, `/dev/mtd3`) with SHA-256 check [1], then `scp -O` the IDEA image and `sysupgrade -n`.
  Never the `ubootmod` image (only a serial cable can undo it [1]).
* **Re-flashing an IDEA router** later skips step 1: `sysupgrade` (keeping settings) to the new IDEA version.

## 6.2 Where it runs

* **Phase 1 (now):** `tools/router-image/idea-router-flash` runs on a Linux laptop or a Pi with one Ethernet cable
  into the Cudy's LAN2. It needs only `ssh`, `scp`, `curl`, `sha256sum`. Koen or Atlas runs it; output is one
  line per step plus a final PASS/FAIL report.
* **Phase 2:** the same script on an **Engine as flash station** (Console "Flash router" button), using a spare
  Ethernet port or a USB-Ethernet adapter so the school LAN is not disturbed. The fleet key then stays on the
  Engine and never touches a laptop.
* **Batch:** one router at a time per cable. All routers start on the same addresses, so two at once would collide.

## 6.3 Recovery

If a router does not come back: Cudy's TFTP recovery (`recovery.bin` served on `192.168.1.88`, reset held at power-on)
[9]. The script prints these steps when a flash times out. The Factory/bdinfo dump from step 2 restores calibration
if a later accident wipes it.

# 7. Repo layout

```
tools/router-image/
  build.sh                     # Image Builder wrapper, pinned version + SHA-256
  packages.txt                 # package list
  files/etc/uci-defaults/90-idea-setup
  files/etc/sysupgrade.conf
  files/etc/idea/...           # version, lease script, LED/button hotplug
  idea-router-flash            # flash station script (stock -> intermediate -> IDEA -> enrol -> test)
  test/                        # self-test + fw4 render test (no hardware)
```

`docs/manuals/install/scripts/school-router-setup.sh` becomes a thin wrapper that runs the same setup file, so the
manual (for a router flashed by hand) and the image can never drift apart.

# 8. Changes to the manuals

* School server install manual, section 2–3: replace the hand flashing and `school-router-setup.sh` steps with
  "plug in the pre-flashed IDEA router, check the sticker", and move the hand procedure to an appendix.
* Section 5: drop the Pi MAC reservations (5.1 above).
* Teacher tutorial: the router Wi-Fi names and the `idea911!` / `idea-teachers911!` defaults, and how to change them
  in LuCI.

# 9. Test plan

## 9.1 Automatic self-test after each flash (the script runs it)

`/etc/idea/version` matches; `uci show` matches the expected settings; `fw4 print` contains no students→wan path;
both SSIDs up on both bands; `tailscale status` online with `tag:idea`; `nslookup idea.local 10.42.0.1`; free RAM
and overlay space logged.

## 9.2 Acceptance on the first real router (Atlas, with Koen)

* Label/revision and flash chip recorded; full flash from stock with the script, twice (once with a factory reset
  between).
* Phone on `IDEA`: gets `10.42.1.x`, opens `http://idea.local`, **cannot** reach the internet or the router's LuCI.
* Laptop on `IDEA-Teachers`: no internet; switch `Teachers-Internet` on → internet; off → none.
* Two Engines: get `.2–.9` without MAC config; switch one off → `idea.local` answers only the live one.
* Move an Engine to a "second school" (a second flashed router): works with no change.
* Factory reset button → IDEA defaults back; Tailscale re-enrol works.
* Sysupgrade to a newer IDEA build → same sticker name and tailnet identity.
* 24 h soak with 30 Wi-Fi clients: free RAM stays above 60 MB with Tailscale running.

# 10. Open decisions for Koen

| # | Question | My recommendation |
|---|---|---|
| D1 | OpenWrt base: 25.12.5 (current, matches manual) or 24.10.8 (older branch)? | **25.12.5** |
| D2 | Router login: `root` / `admin911!` (LuCI and SSH on LAN), SSH over Tailscale key-only? | **Yes**, same rule as the Pis: password on the LAN, keys remotely |
| D3 | Teacher Wi-Fi password: `idea-teachers911!` (fits the `<name>911!` convention)? | **Yes** |
| D4 | Auth key: injected by the flash station after first boot (never in an image), or a private image with the key baked in? | **Inject** |
| D5 | After a factory reset: re-enrol by hand (a), or automatically from an Engine (b)? | **(a) now, (b) with the Console flash station** |
| D6 | Teacher content filtering: none, filtering DNS resolver, or later? | **Later**, once teacher internet is in use |
| D7 | 4G fallback: buy an external 4G router per school? | **Later**, decide per school |
| D8 | Engines by DHCP vendor class (no MAC reservations), firewall to `.2–.9`? | **Yes** (needs a one-line Engine installer change) |
| D9 | Captive "sign in" page that opens `idea.local` on student phones? | **Yes** |

# 11. Work and owners

| Owner | Work |
|---|---|
| Atlas (Ops) | Image build script, first-boot script, flash script, self-test; first router acceptance with Koen |
| Axle (Engine) | DHCP vendor class `idea-engine` in the Engine installer; flash station in the Engine (phase 2) |
| Pixel (Console) | "Flash router" and "Teachers internet on/off" in the Console (phase 2) |
| Marco (manuals) | Manual and teacher tutorial changes (section 8) |

First step tomorrow: Koen reads the label (section 3.1) and sends a photo; Atlas builds the first image and flashes
one router with the script while Koen watches.

# Sources (checked on 15 October 2026)

1. OpenWrt wiki, *Cudy WR3000S v1* (Table of Hardware, installation, flash chip notice, MD5, backup, layout):
   `https://openwrt.org/toh/cudy/wr3000s_v1`. The wiki blocks automated fetches today; facts were read from its
   search snippet and from our own notes of 12 October in the install manual.
2. Cudy, *OpenWrt Software Download* (intermediate "transition" firmware, new-flash notice):
   `https://www.cudy.com/blogs/faq/openwrt-software-download`.
3. OpenWrt release index: `https://downloads.openwrt.org/releases/` (25.12.5 newest stable, 24.10.8 newest 24.10).
4. OpenWrt 25.12.5 `profiles.json`, mediatek/filogic (profile `cudy_wr3000s-v1`, image names, SHA-256):
   `https://downloads.openwrt.org/releases/25.12.5/targets/mediatek/filogic/profiles.json`.
5. OpenWrt pull request #16939, *mediatek: filogic: add support for Cudy WR3000S v1* (256 MB RAM, 128 MB SPI-NAND):
   `https://github.com/openwrt/openwrt/pull/16939`.
6. OpenWrt 25.12.5 Image Builder: `https://downloads.openwrt.org/releases/25.12.5/targets/mediatek/filogic/`.
7. OpenWrt 25.12.5 packages, aarch64_cortex-a53: `tailscale-1.102.3-r1.apk`, 10,537,181 bytes:
   `https://downloads.openwrt.org/releases/25.12.5/packages/aarch64_cortex-a53/packages/`.
8. OpenWrt wiki, *Tailscale*: `https://openwrt.org/docs/guide-user/services/vpn/tailscale/start`; IDEA proposal
   `proposals/2026-10-13-tailscale-single-fleet-tag.md`.
9. Cudy, *How to recover the Cudy router from OpenWrt firmware to Cudy official firmware*:
   `https://www.cudy.com/en-us/blogs/faq/how-to-recovery-the-cudy-router-from-openwrt-firmware-to-cudy-official-firmware`.
10. IDEA repo: `docs/manuals/install/install-manual-school-server/install-manual-school-server.md` (sections 2–3, 3.7),
    `docs/manuals/install/scripts/school-router-setup.sh`, `router-tailscale-zone.sh`,
    `proposals/2026-10-15-client-browser-and-server-discovery.md`.
