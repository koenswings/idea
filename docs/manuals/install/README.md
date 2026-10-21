**Status:** Authoritative (follows the school network design; not yet run on hardware) · **Maintained by:** Marco (with Atlas) · 19 October 2026

# Install manuals

19 October 2026: both manuals updated for the Zimbabwe kit handed over on 18 October 2026 (school server v1.3: new chapter "The Zimbabwe kit"; classroom computer v2.1: temporary IDEA-Teachers procedure for idea#285 and the reset on restart).

| Folder | PDF | Topic |
|---|---|---|
| `install-manual-school-server/` | `install-manual-school-server.pdf`  | Starlink → Cudy WR3000S (OpenWrt + Tailscale) → TL-SG105PE PoE+ switch → Pi 5 IDEA Engines (one or more) |
| `install-manual-classroom-computer/` | `install-manual-classroom-computer.pdf`  | Raspberry Pi 400 or Pi 500 + Raspberry Pi Monitor (one PSU) + the IDEA client image (Ubuntu Desktop 26.04.1 LTS, Chrome, IDEA icon) |
| `scripts/` | – | `school-router-setup.sh`, `router-tailscale-zone.sh` (OpenWrt 25.12 uci; tested with the 25.12.5 x86 rootfs `uci` + `fw4 print`, not yet on a real Cudy; no longer printed in the school-server manual) and `make-install-diagrams.py` (writes both manuals' `diagrams/*.svg`) |

Build: `python3 build.py` in each manual folder (uses `docs/house-style`, regenerates the diagrams). It fails if a
"to confirm" marker or a school-numbering leftover (`10.N.`, `school-N`, `tag:school`) is in the source, a diagram or the PDF.

Addressing and naming (school network design): every school uses the same subnets (wired `10.42.0.0/24`, Wi-Fi `10.42.1.0/24` and
`10.42.2.0/24`). The installer names each Pi with a unique two-word sticker name. One Tailscale tag (`tag:idea`) and one fleet
key for all schools.

**Not yet true on hardware:** the sticker naming (`provision-fleet.sh … auto=<ip>`, the `Sticker name:` line,
`/home/pi/STICKER.txt`) and the Console listing all Engines from the database come from the Engine's sticker-hostname change, which is not merged yet (the Console part, listing all Engines from the database, is merged).
The classroom computer manual describes the IDEA client image, which is built but not yet boot-tested on a Pi 400 and a Pi 500.

No auth keys or tokens: everything in `<ANGLE BRACKETS>` is a placeholder. The router defaults (`IDEA`/`idea911!`, `IDEA-Teachers`/`idea-teachers911!`, `root`/`admin911!`) follow the public `<name>911!` convention (*IDEA School Router – Image and Automated Flashing* proposal); the client image's `admin` account uses `admin911!`.
