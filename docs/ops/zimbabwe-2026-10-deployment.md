# Zimbabwe kit deployment, 20 October 2026

This page brings together what we know about the kit delivered to two schools in Zimbabwe on 20 October 2026,
so field coordination and the teacher guides can start from one place. It points to the detailed records and
marks what we still have to find out. It contains no passwords: default passwords follow the `<name>911!`
convention and are never written down here.

Tracking issue: [idea#288](https://github.com/koenswings/idea/issues/288). Release tag: `zimbabwe-2026-10-20`.
Batch name in the records: `zimbabwe-2026-10`.

## The schools

The two schools are Chigonda and Nharira. We know which kit is at each site from what the bots saw online; which
school is which site has not been observed, so this page doesn't name it.

| | Site 1 | Site 2 |
|---|---|---|
| School server and router | sunny-robin, sunny-robin-router | happy-zebra, happy-zebra-router |
| Switch | TP-Link TL-SG105PE, MAC 58:d8:12:34:aa:81 (router leases, 30 Oct 2026) | TP-Link TL-SG105PE, MAC 58:d8:12:34:a9:ef |
| Classroom computers | idea-pc-fc95, idea-pc-7d02, idea-pc-9f95 (3) | idea-pc-35f2, idea-pc-58c3, idea-pc-5b4c, idea-pc-671c, idea-pc-841d (5) |

Not yet placed at a site: the kind-panda school server (not yet observed at a site), its router (not installed yet; recorded when it comes online), and idea-pc-f63a (not yet observed at a site).

Sources for the mapping: Steve's review of this page (28 Oct 2026, site mapping and switch); the happy-zebra-router
DHCP leases of 28 Oct 2026 (Atlas, "Still open" below), which show exactly the five Site 2 computers;
`deployments/clients/kit-hosts-zimbabwe-2026-10.tsv` and `fleet-state.json` `sunny-robin.clients` for the hostnames,
models and MACs. Switches: from each router's DHCP leases (happy-zebra 29 Oct, sunny-robin 30 Oct 2026), in `fleet-state.json`.

> **Note on the 27 Oct sighting.** `kit-hosts-zimbabwe-2026-10.tsv` and `fleet-state.json` (`sunny-robin.clients`)
> list all 9 machines as seen on the sunny-robin kit network on 27 Oct 2026. Those 9 included the five Site 2
> computers, so that list is not a per-site list: use the site table above for where each computer is.

## What was in the kit

Sources: `fleet-state.json`, `deployments/` records, [idea#288](https://github.com/koenswings/idea/issues/288).

| Device | Sticker name | Site | Hardware | Software | Last seen read-only |
|---|---|---|---|---|---|
| School server (Engine) | sunny-robin | 1 | Raspberry Pi 5 (Waveshare D case), USB SSD Intenso AA000000000000003120 | Engine `adfd9d3`, Console checkout `654224e` (dist from agent-console-dev#162) | 26 Oct 2026 capture; 5 Nov 2026 first-contact read; boot reads 14 and 15 Nov 2026 |
| School server (Engine) | happy-zebra | 2 | Raspberry Pi 5 (Waveshare case), USB SSD Intenso AA000000000000010473 | Engine `adfd9d3`, Console checkout `654224e` | 28 Oct 2026 capture; 30 Oct 2026 capture-engine-record; 6 Nov 2026 SSH read (hostname, uptime, temperature) |
| School server (Engine) | kind-panda | not yet observed | Raspberry Pi 5, NVMe (cloned from the FIT stick) | Engine `adfd9d3` (fleet-state) | Never read at a site. Last seen on Tailscale 18 Oct 2026 21:41 CEST; offline since (idea#288 watch, 15 Nov 2026) |
| Router | sunny-robin-router | 1 | Cudy WR3000S v1, LAN MAC d4:0d:ab:50:ce:7e | OpenWrt 25.12.5 r33051-f5dae5ece4; IDEA router image `b2f00bc` (confirmed on the device 29 Oct 2026, `/etc/idea/version`) | 29 Oct 2026 capture; 5 Nov 2026 ubus read |
| Router | happy-zebra-router | 2 | Cudy WR3000S v1, LAN MAC d4:0d:ab:50:ca:c8 | OpenWrt 25.12.5 r33051-f5dae5ece4; IDEA router image `b2f00bc` (confirmed on the device 29 Oct 2026, `/etc/idea/version`) | 29 Oct 2026 capture |
| Router | kind-panda-router | not yet observed | Cudy WR3000S v1 | Not installed yet; recorded when it comes online | Device never read. Its Tailscale node (100.86.136.9) was last seen 18 Oct 2026 21:41 CEST |
| Switch | n/a | 1 | TP-Link TL-SG105PE, MAC 58:d8:12:34:aa:81 | n/a | 30 Oct 2026 (sunny-robin-router DHCP lease) |
| Switch | n/a | 2 | TP-Link TL-SG105PE, MAC 58:d8:12:34:a9:ef | n/a | 29 Oct 2026 (happy-zebra-router DHCP lease) |
| Classroom computers | n/a | 1 | 3: idea-pc-fc95 (Raspberry Pi 500), idea-pc-7d02 and idea-pc-9f95 (Raspberry Pi 400) | Client image f00748e (patched) or s15 | 27 Oct 2026 |
| Classroom computers | n/a | 2 | 5 Raspberry Pi 500: idea-pc-35f2, idea-pc-58c3, idea-pc-5b4c, idea-pc-671c, idea-pc-841d | Client image f00748e (patched) or s15 | 28 Oct 2026 (happy-zebra-router leases) |
| Classroom computer | n/a | not yet observed | idea-pc-f63a (Raspberry Pi 500) | Client image f00748e (patched) or s15 | 27 Oct 2026 |

In total, 9 classroom computers have been seen online (3 at Site 1, 5 at Site 2, and idea-pc-f63a, whose site is not
yet observed). Any further computer is recorded when it comes online.

All three Engines share one kit store, so every school server lists the others when they meet. Teachers open the
Console at `http://idea.local`, or reach one specific school server at `http://<sticker>.local`.

Engines were installed on 18 October 2026 (Console dist 17 October). The three kit routers were flashed on Friday 16 October 2026 (Koen, 29 Oct 2026).

## Kolibri IDs

Each Kolibri has its own `MORANGO_SYSTEM_ID` (app-kolibri#8), so the schools' Kolibris can sync without clashing.
Checked so far: sunny-robin (26 Oct, read again unchanged on 5 Nov) and happy-zebra (28 Oct); all ids are unique and nothing needed changing.
kind-panda is checked when it comes online. The same values are in `fleet-state.json` (`kolibri` on each Engine).

| School server | Port | Kolibri | `MORANGO_SYSTEM_ID` | Kolibri instance_id | Checked |
| --- | --- | --- | --- | --- | --- |
| sunny-robin | 62650 | Kolibri (Engine) | `idea-sunny-robin-62650` | `65fb422ad074f056c6c34b4e0c0b2973` | 26 Oct 2026 |
| sunny-robin | 64439 | container, not Engine-listed | `idea-sunny-robin-64439` | `0eb293613aad2ebb5f204d186b8a5d1c` | 26 Oct 2026 |
| happy-zebra | 65439 | Kolibri_Demo (Engine) | `idea-happy-zebra-65439` | `cd9feeb7dbef09b9ac22896394c45ddb` | 28 Oct 2026 |
| happy-zebra | 62561 | container, not Engine-listed | `idea-happy-zebra-62561` | `ed370fd83b528743e8b58e6c16287f65` | 28 Oct 2026 |
| kind-panda | n/a | not read yet (offline) | n/a | n/a | open |

## Routers observed on 29 Oct 2026

Read by Atlas on 29 Oct 2026 around 09:50 CET, read-only, over a LAN jump: box to the kit Engine over Tailscale, then
SSH to the router at `10.42.0.1` (dropbear listens on the LAN only). Nothing was changed on the routers or Engines.
Full captures (secrets redacted) are on the box under `/workspace/idea-archive/captures/`.

| Router | Firmware | `/etc/idea/version` | LAN MAC | WAN MAC | ed25519 host key | Capture |
|---|---|---|---|---|---|---|
| sunny-robin-router | OpenWrt 25.12.5 r33051-f5dae5ece4 (kernel 6.12.94) | 0.1.0-dev, GIT b2f00bc, SETUP_REF 7eedd03, cudy_wr3000s-v1 | d4:0d:ab:50:ce:7e | d4:0d:ab:50:ce:7f | `SHA256:TiKa2HFDh4SH+0Y0TzBAQlSrPfGb3imK84wBU/iKVtE` (matches 28 Oct) | `sunny-robin-router-20261029T084928Z.txt` |
| happy-zebra-router | OpenWrt 25.12.5 r33051-f5dae5ece4 (kernel 6.12.94) | 0.1.0-dev, GIT b2f00bc, SETUP_REF 7eedd03, cudy_wr3000s-v1 | d4:0d:ab:50:ca:c8 | d4:0d:ab:50:ca:c9 | `SHA256:TBywMXMvqm4/ZGOeWt08itc0p+GE/HFc3lmq7UnsWzs` (matches 28 Oct) | `happy-zebra-router-20261029T084956Z.txt` |

Both routers run the IDEA router image `b2f00bc`, now confirmed on the device. Dropbear: `Interface=lan`, port 22.
kind-panda-router is not yet installed.

## Kit check on 30 Oct 2026

**Record: sunny-robin-router read by Atlas on 30 Oct 2026 at 13:00 CET**, read-only, from the box over Tailscale to
sunny-robin, then SSH to the router at `10.42.0.1` (`/tmp/dhcp.leases`, `iw dev <iface> station dump`, `uci show wireless`).
Nothing was written on the Engine or router. happy-zebra and happy-zebra-router dropped off Tailscale at about 12:50 CET
and couldn't be read at 12:58–13:01 CET.

| Engine (sticker) | Engine Tailscale IP | Router Tailscale IP | Site | School | Client Wi-Fi seen 30 Oct | Status 30 Oct |
|---|---|---|---|---|---|---|
| sunny-robin | 100.96.98.10 | 100.96.34.29 | 1 | Chigonda: INFERRED by Steve from Koen's 30 Oct 12:11 CET message ("the system at Qigong is up"), not observed | Leases (13:00 CET): idea-pc-841d (10.42.1.153), idea-pc-9f95, idea-pc-7d02, a phone, the switch and the Engine. 3 Wi-Fi stations: idea-pc-841d on `IDEA` (-47 dBm), idea-pc-7d02 and the phone on `IDEA-Teachers` | Engine and router online |
| happy-zebra | 100.102.94.100 | 100.110.73.52 | 2 | Nharira: client Wi-Fi network name `NHARIRA HIGH` seen in capture `/workspace/state/client-wifi-unlock/happy-zebra/10.42.1.184.log` (line 13; idea-pc-35f2 saved Wi-Fi profiles, 28 Oct 2026 via happy-zebra) | Not read (offline at 12:58 CET) | Offline from ~12:50 CET |
| kind-panda | 100.80.238.59 | n/a | not yet observed | not yet observed | n/a | Engine offline (11 days); router not yet installed |

SSIDs on sunny-robin-router: `IDEA` and `IDEA-Teachers` on both radios.

**idea-pc-841d** was seen at Site 2 on 28 Oct 2026 (Wi-Fi unlock via happy-zebra at 11:32 CET) and at Site 1 on
30 Oct 2026 at 13:00 CET (sunny-robin-router lease and station). It wasn't in sunny-robin-router's 09:18 CET lease read
today (`sunny-robin-router-leases-hints-20261030T0818Z.json`), so it joined later. A ping from sunny-robin to 10.42.1.153
fails, as expected: the kit firewall doesn't let the Engine reach the student network. Its site column in the tables
above reflects 28 Oct.

## sunny-robin first contact, 5 Nov 2026

Read by Atlas on 5 Nov 2026, about 10:26 to 10:36 CET, read-only; nothing was installed, restarted or changed.
Evidence on the box: `/workspace/idea288/first-contact-sunny-robin-20261105-1026/`.

- Engine `adfd9d3` and Console checkout `654224e`, the same as on 26 Oct. pm2 shows `engine` online as `pi` with 0 restarts.
- `store-identity/store-url.txt` in the Engine checkout holds the shared kit store `automerge:3Vvvigx8bKcuwKALqMVz85GhDqrk`
  (file dated 18 Oct 2026), and the Engine's `/api/store-url` returns the same id. `/var/lib/idea/client-images` is empty.
- Console: `:80` answers HTTP 200; `:8080` is refused.
- Apps: 2 Kiwix, 2 Nextcloud and 2 Kolibri stacks up, including Nextcloud `zq54tg24tjrkwrar2va`, which was stopped
  (Exited 255) on 26 Oct. Kolibri ids unchanged.
- Disk: root SSD only, `/` 194 GB of 469 GB used (43%); no other disk docked. eth0 `10.42.0.4`, MAC `98:fe:54:3f:22:f3`.
- Temperature 64.8 to 68.6 °C. `vcgencmd get_throttled` = `0x50000`: under-voltage and the soft temperature limit
  have occurred since boot; no throttling was active at the time.
- sunny-robin-router (ubus over Tailscale): same model, firmware and MACs as on 29 Oct.

Later read-only boot reads of sunny-robin (box `down-watch-*` folders): it had booted at 05:48 CET on 14 Nov and at
05:58 CET on 15 Nov 2026, and `get_throttled` was `0x50000` both times. The Engine keeps no journal across reboots,
so the reason for a reboot can't be read afterwards. These are recorded in `fleet-state.json`
(`sunny-robin.observed`, `sunny-robin.power_observed`).

## Still open

From ops (Atlas). Status on 15 Nov 2026, 15:30 CET (first written 30 Oct 2026):

- **kind-panda: BLOCKED (offline).** The Kolibri ID check, `df -h /` and the on-device capture all wait for it.
  It was last seen on Tailscale on 18 Oct 2026 at 21:41 CEST and has not been online since (idea#288 watch, 15 Nov 2026).
- **kind-panda-router: not yet installed.** Nothing about the device is recorded until our watcher sees it online
  and we read it ourselves. Its Tailscale node (100.86.136.9) was last seen on 18 Oct 2026 at 21:41 CEST.
- **happy-zebra-router WAN MAC: DONE.** It's `d4:0d:ab:50:ca:c9`, read through ubus.
- **Router release file and full captures (sunny-robin-router, happy-zebra-router): DONE 29 Oct 2026.** See
  "Routers observed on 29 Oct 2026" above. We made no router changes.
- **happy-zebra full record: DONE.** `deployments/engines/happy-zebra/capture-2026-10-28/` (record, packages,
  images, helpers, raw capture) plus `capture-2026-10-30/` (capture-engine-record.sh, read-only, 30 Oct 2026):
  `files.sha256` and `dist.sha256` (identical to sunny-robin's), Console dist sha256 and tool versions.
- **Router host keys (ed25519):** happy-zebra-router `SHA256:TBywMXMvqm4/ZGOeWt08itc0p+GE/HFc3lmq7UnsWzs`,
  sunny-robin-router `SHA256:TiKa2HFDh4SH+0Y0TzBAQlSrPfGb3imK84wBU/iKVtE`. Both were read on 28 Oct 2026 from the
  Engine on the same LAN. happy-zebra's `known_hosts` (last written 18 Oct 2026, 19:10) holds a different key for
  10.42.0.1. Why they differ has not been observed; that file stays unchanged until a device on the kit LAN can check the key.
- **Further classroom computers and the card-to-machine mapping: not yet observed.** Our card log has no mapping.
  The happy-zebra router's leases on 28 Oct showed only machines we already know (35f2, 5b4c, 671c, 841d, 58c3).
  We record any other computer, and its card, when a bot sees it online (for example with `capture-device.sh`).
- **Sites of kind-panda (with kind-panda-router) and idea-pc-f63a: not yet observed.** We record them when they come
  online on a site's network.
- **TP-Link switches: DONE.** Both observed in their router's DHCP leases (happy-zebra 58:d8:12:34:a9:ef on 29 Oct,
  sunny-robin 58:d8:12:34:aa:81 on 30 Oct 2026) and recorded in `fleet-state.json`.
- **Router flash date: DONE.** All three routers were flashed on Friday 16 October 2026 (Koen, 29 Oct 2026).
- **Cudy intermediate firmware source: DONE (file), download step not logged.** `cudy_wr3000s-v1-sysupgrade_20251119.bin`,
  14,945,872 bytes, sha256 `463e6e31e7361ec8177d2c3a136674297fd179eafaa166fe459731cdf1b35773`, MD5
  `403e276f74fd29917fd4260294d1a137`. Its MD5 and size match the file the OpenWrt wiki names in Cudy's Google Drive folder
  (`https://drive.google.com/drive/folders/1BKVarlwlNxf7uJUtRhuMGUqeCa5KpMnj`, `WR3000S 1.0.zip`), linked from Cudy's
  *OpenWrt Software Download* page. The box's build report of 16 Oct 2026 shows it staged on wh with that MD5. No bot
  record of the actual download (URL, time) was found. Mirror: the `field/zimbabwe-2026-10` release asset.
- **120 GB test disk (`_test_disks.wds120-20070Q450002`): DONE.** Label `IDEA Disk` and diskId `20070Q450002` are in
  `fleet-state.json` (idea#526, 15 Nov 2026).
- **idea-pc-35f2 rename: DONE.** The client reported `idea-pc-35f2` after the reboot that ended the rename (27 Oct 2026,
  about 18:43 CET) and again on 28 Oct 2026 at 11:21 CET via happy-zebra.
- **happy-zebra Console port:** answered HTTP 200 on `:80` (idea#288 watch, 29 Oct 2026), now `console_port` 80 in
  `fleet-state.json`, the same as sunny-robin.

## Detailed records

- `deployments/engines/<sticker>/` and `deployments/routers/<sticker>/`: one record per device.
- `deployments/clients/`: card records, `kit-hosts-zimbabwe-2026-10.tsv` (machines seen on the kit network) and `UNACCOUNTED.txt`.
- `deployments/README.md`: the record format.
