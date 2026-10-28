# Zimbabwe kit deployment, 20 October 2026

This page brings together what we know about the kit delivered to two schools in Zimbabwe on 20 October 2026,
so field coordination and the teacher guides can start from one place. It points to the detailed records and
marks what we still have to find out. It contains no passwords: default passwords follow the `<name>911!`
convention and are never written down here.

Tracking issue: [idea#288](https://github.com/koenswings/idea/issues/288). Release tag: `zimbabwe-2026-10-20`.
Batch name in the records: `zimbabwe-2026-10`.

## The schools

The two schools are Chigonda and Nharira. We don't yet know which kit went to which school.

| | First school | Second school |
|---|---|---|
| Name | Chigonda or Nharira: TBC (asked Justice, 28 Oct 2026) | TBC (asked Justice, 28 Oct 2026) |
| Level | Primary | TBC (asked Justice, 28 Oct 2026) |
| Number of students | TBC (asked Justice, 28 Oct 2026) | TBC (asked Justice, 28 Oct 2026) |
| Number of teachers | TBC (asked Justice, 28 Oct 2026) | TBC (asked Justice, 28 Oct 2026) |
| Grades, classes and subjects using the computers | TBC (asked Justice, 28 Oct 2026) | TBC (asked Justice, 28 Oct 2026) |
| Days and hours the kit is on | TBC (asked Justice, 28 Oct 2026) | TBC (asked Justice, 28 Oct 2026) |
| Power (mains, solar, generator) | TBC (asked Justice, 28 Oct 2026) | TBC (asked Justice, 28 Oct 2026) |
| Language of lessons | TBC (asked Justice, 28 Oct 2026) | TBC (asked Justice, 28 Oct 2026) |
| School server sticker names | TBC (asked Justice, 28 Oct 2026) | TBC (asked Justice, 28 Oct 2026) |
| Classroom computers at the school | TBC (asked Justice, 28 Oct 2026) | TBC (asked Justice, 28 Oct 2026) |
| Pain points and wishes | TBC (asked Justice, 28 Oct 2026) | TBC (asked Justice, 28 Oct 2026) |

## What was in the kit

Sources: `fleet-state.json`, `deployments/` records, [idea#288](https://github.com/koenswings/idea/issues/288).

| Device | Sticker name | Hardware | Software | Last seen read-only |
|---|---|---|---|---|
| School server (Engine) | sunny-robin | Raspberry Pi 5 (Waveshare D case), USB SSD Intenso AA000000000000003120 | Engine `adfd9d3`, Console checkout `654224e` (dist from agent-console-dev#162) | 26 Oct 2026 capture |
| School server (Engine) | happy-zebra | Raspberry Pi 5 (Waveshare case), USB SSD Intenso AA000000000000010473 | Engine `adfd9d3`, Console checkout `654224e` | 28 Oct 2026 capture |
| School server (Engine) | kind-panda | Raspberry Pi 5, NVMe (cloned from the FIT stick) | Engine `adfd9d3` (fleet-state) | Not seen yet (offline about 9 days as of 28 Oct 2026, idea#288) |
| Router | sunny-robin-router | Cudy WR3000S v1, LAN MAC d4:0d:ab:50:ce:7e | OpenWrt 25.12.5 r33051-f5dae5ece4; IDEA router image `b2f00bc` (likely, retro record) | 26 Oct 2026 |
| Router | happy-zebra-router | Cudy WR3000S v1, LAN MAC d4:0d:ab:50:ca:c8 | OpenWrt 25.12.5 r33051-f5dae5ece4; IDEA router image `b2f00bc` (likely, retro record) | 28 Oct 2026 |
| Router | kind-panda-router | Cudy WR3000S v1 | IDEA router image `b2f00bc` (likely, retro record) | Not seen yet |
| Classroom computers | n/a | 10 cards; 9 machines seen on the sunny-robin network (7 Raspberry Pi 500, 2 Raspberry Pi 400) | Client image f00748e (patched) or s15 | 27 Oct 2026 |

All three Engines share one kit store, so every school server lists the others when they meet. Teachers open the
Console at `http://idea.local`, or reach one specific school server at `http://<sticker>.local`.

Engines were installed on 18 October 2026 (Console dist 17 October). The routers' install dates are not known yet.

## Kolibri IDs

Each Kolibri has its own `MORANGO_SYSTEM_ID` (app-kolibri#8), so the schools' Kolibris can sync without clashing.
Checked so far: sunny-robin (26 Oct) and happy-zebra (28 Oct); all ids are unique and nothing needed changing.
kind-panda is checked when it comes online.

## Still open

From the field (asked Justice, 28 Oct 2026): every TBC field in "The schools" above.

From ops (Atlas), waiting for the devices to come online:

- kind-panda: Kolibri ID check, disk space, on-device capture.
- kind-panda-router: firmware version and MAC.
- happy-zebra-router: WAN MAC and the IDEA router release file.
- Full router captures for sunny-robin-router and happy-zebra-router (SSH doesn't get through over Tailscale yet).
- happy-zebra: turn the 28 Oct capture into a full record.
- The 10th classroom computer, and which card is in which machine.
- Router install dates and the Cudy intermediate firmware source: only Koen knows these.

## Detailed records

- `deployments/engines/<sticker>/` and `deployments/routers/<sticker>/`: one record per device.
- `deployments/clients/`: card records, `kit-hosts-zimbabwe-2026-10.tsv` (machines seen on the kit network) and `UNACCOUNTED.txt`.
- `deployments/README.md`: the record format.
