**Status:** Authoritative (follows idea#184; not yet run on hardware) · **Maintained by:** Marco (with Atlas) · 14 October 2026

# Install manuals

| Folder | PDF | Topic |
|---|---|---|
| `install-manual-school-server/` | `install-manual-school-server.pdf`  | Starlink → Cudy WR3000S (OpenWrt + Tailscale) → TL-SG105PE PoE+ switch → 2× Pi 5 IDEA Engines |
| `install-manual-client-pi400/` | `install-manual-client-pi400.pdf`  | Raspberry Pi 400 + Raspberry Pi Monitor (one PSU) + Ubuntu Desktop 26.04.1 LTS |
| `scripts/` | – | `school-router-setup.sh`, `router-tailscale-zone.sh` (OpenWrt 25.12 uci; tested with the 25.12.5 x86 rootfs `uci` + `fw4 print`, not yet on a real Cudy; printed in the school-server manual, Appendix A) and `make-install-diagrams.py` (writes both manuals' `diagrams/*.svg`) |

Build: `python3 build.py` in each manual folder (uses `docs/house-style`, regenerates the diagrams). It fails if a
"to confirm" marker or a school-numbering leftover (`10.N.`, `school-N`, `tag:school`) is in the source, a diagram or the PDF.

Addressing and naming (idea#184): every school uses the same subnets (wired `10.42.0.0/24`, Wi-Fi `10.42.1.0/24` and
`10.42.2.0/24`). The installer names each Pi with a unique two-word sticker name. One Tailscale tag (`tag:idea`) and one fleet
key for all schools.

**Not yet true on hardware:** the sticker naming (`provision-fleet.sh … auto=<ip>`, the `Sticker name:` line,
`/home/pi/STICKER.txt`) and the Console listing all Engines from the database come from agent-engine-dev #201 and
agent-console-dev #152, which are not merged yet. The open decisions for Koen are listed in the idea PR that added this folder.

No auth keys or tokens: everything in `<ANGLE BRACKETS>` is a placeholder. The router defaults (`IDEA`/`idea911!`, `IDEA-Teachers`/`idea-teachers911!`, `root`/`admin911!`) follow the public `<name>911!` convention (router proposal, idea#209).
