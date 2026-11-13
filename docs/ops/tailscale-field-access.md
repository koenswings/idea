**Status:** Authoritative (idea#117, docs side) · **Maintained by:** Atlas · 13 November 2026

# Tailscale field access

How IDEA staff reach schools and Pis over Tailscale. This page is the ops record for [idea#117](https://github.com/koenswings/idea/issues/117). It contains **no secret values**: no auth keys, tokens or passwords.

Related:

- Design (why): [`proposals/2026-10-13-tailscale-single-fleet-tag.md`](../../proposals/2026-10-13-tailscale-single-fleet-tag.md) (Approved, 13 October 2026). The proposal is unchanged; this page is what we follow.
- Security overview: [`docs/ops/security-overview.md`](security-overview.md).
- Sharing the demo server with a field engineer: [`docs/manuals/field/remote-access-guide/`](../manuals/field/remote-access-guide/).
- School install (LAN, stickers, `tag:idea` on kit devices): [`docs/manuals/install/install-manual-school-server/`](../manuals/install/install-manual-school-server/).
- Tagging the remaining untagged fleet Pis: [`tools/fleet/tag-fleet-idea-tc.md`](../../tools/fleet/tag-fleet-idea-tc.md) (idea#375 T-c; ready, not yet applied).
- Usage-dashboard ACL exception: [`tools/fleet/field-usage-acl.md`](../../tools/fleet/field-usage-acl.md) (idea#416).

## 1. The decided model

Koen decided this on 13 October 2026, and on 30 October 2026 chose option 3 for how a new Engine joins ([idea#117](https://github.com/koenswings/idea/issues/117) D-2).

- **One fleet tag, `tag:idea`, and one reusable fleet auth key** (the key is tagged `tag:idea`). There are no per-school tags or keys, so a Pi can move to another school with no admin step.
- **ACL:** admins can reach `tag:idea`; `tag:idea` can reach nothing. There is no Pi-to-Pi traffic over Tailscale. Pis talk to each other only on the school LAN (the Engine websocket and mDNS).
- **Tailscale is always on at schools**, on the router and on every Pi. It is not a debug mode switched on for a visit.
- **SSH to Pis is key-only**, and it goes **directly** to each Pi's Tailscale IP. There is no jump host.
- **Production idea** is reached as `idea.tail2d60.ts.net:<port>`. The earlier name was wizardly-hugle. The Tailscale IPv4 `100.115.60.6` is the fallback if MagicDNS does not resolve. Ports are listed in the remote-access guide.
- **Every school uses the `10.42.x` LAN**, and Engines and routers are identified by **sticker names** (two lowercase words, no digits), not by numbers.

The old ideas of `tag:school-pi`, per-school keys, and an untagged ephemeral debug key are superseded. They remain only as history in older proposal files.

## 2. How staff reach devices

### 2.1 Production idea

- In a browser, on a device already on the IDEA tailnet (or after a Tailscale share, as in the remote-access guide): `http://idea.tail2d60.ts.net:<port>`. If the name does not resolve, use `http://100.115.60.6:<port>`.
- Over SSH, as user `pi`, to idea's Tailscale address, with a key. Never through a jump host.

### 2.2 Fleet and kit Pis

- SSH as `pi@<tailscale-ip>`, key-only. Addresses live in `fleet-state.json` (and in `tailscale status`). Do not add a bastion or jump host.
- On the ops box, SSH may go through the box's local Tailscale SOCKS helper (`socks-connect`). That is a local proxy on the box, not a jump host on the tailnet.
- The kit router's SSH port is closed on the Tailscale side. Remote reads use LuCI (80/443) as root, from a device that the ACL allows. The school switch is not on Tailscale; its web page is reached through an SSH tunnel via a Pi on that school's LAN, as in the school-server install manual.

### 2.3 School LAN (`10.42.x` and sticker names)

The same plan at every school (install manual):

| Device | Address |
|---|---|
| Router | `10.42.0.1` (hostname `idea-router`) |
| Engines | DHCP `10.42.0.2`–`10.42.0.9` |
| Switch | `10.42.0.10` (not on Tailscale) |
| Student Wi-Fi `IDEA` | `10.42.1.0/24` |
| Teacher Wi-Fi `IDEA-Teachers` | `10.42.2.0/24` |

On the LAN, the Console is `http://idea.local` or `http://<sticker>.local`. On the tailnet, kit Engines and routers appear under their sticker names, tagged `tag:idea`. When an Engine moves school, the sticker name stays; there is no per-school Tailscale tag to change.

## 3. Joining the tailnet and the fleet key

**Option 3 (decided):** a new Engine joins once as `tag:idea` at first boot ([engine#291](https://github.com/koenswings/agent-engine-dev/issues/291)), then **deletes the key**. The generic image stays key-free. The fleet key is only needed on the days we flash or build, not for the life of the Pi. The three kit Engines already match this (tagged, not ephemeral, no expiry) and need no field action.

Until engine#291 lands, first-boot join is not yet in Engine code. Do not treat the old "latent debug / ephemeral activate" scripts as the target model.

**The fleet auth key is a secret.** It is never written into a document, repo, image, issue or log. On a Pi it is root-only (mode 0600) and only until the first successful join deletes it. Ops boxes keep their copy in a 0600 file outside any repo. Whether the live key is reusable and already tagged `tag:idea` is still a console check for Koen (idea#375 T-a).

## 4. ACL

The #117 rule is:

- admins → `tag:idea` (all Pis and routers): allowed;
- `tag:idea` → anything: **denied**.

A later, separate change for field-usage monitoring ([idea#416](https://github.com/koenswings/idea/issues/416)) adds `tag:idea-hub` on the usage-dashboard sidecar on idea, and allows that tag to reach `tag:idea` on **tcp/22 only**. It does not give school Pis Pi-to-Pi access on the tailnet. The saved L-1 policy and the paste-ready snippets are in `tools/fleet/field-usage-acl.md`. Nobody except the listed owner edits the live ACL.

## 5. Current state versus this design

These are facts already recorded in the repo, not a new audit.

**Matches the design**

- Kit Pis and kit routers (sunny-robin, happy-zebra, kind-panda) carry `tag:idea` and have no node-key expiry (audit 29 October 2026 on #117; rechecked 10 November 2026 in `tag-fleet-idea-tc.md`).
- School install and the remote-access guide already describe `tag:idea`, sticker names, the `10.42.x` LAN, and `idea.tail2d60.ts.net`.
- Routers enrol with `--advertise-tags=tag:idea` and without `--ephemeral` (`tools/router-image/idea-router-enrol`).

**Still open, tracked elsewhere**

- The five fleet nodes (idea01–04 and production idea) were still **untagged** and user-owned on 10 November 2026, with node-key expiry on. idea02 and idea03 expire on **2 December 2026 14:36 Europe/Brussels** unless they are tagged with re-authentication or Koen clicks Disable key expiry. Tagging the pool (and idea02) is idea#375 T-c; the runbook is ready and is **not** permission to apply a tag. Production idea is deferred until Koen OKs it.
- A console-only "Edit tags" click does not by itself disable key expiry (see the T-c runbook).
- The live fleet key's tag, reusable/ephemeral flags and expiry are still unconfirmed in the admin console (idea#375 T-a).
- Engine first-boot join-once and key deletion: engine#291. Engine docs in agent-engine-dev (`docs/PI_FLEET.md` and the `installTailscale` comment) still need to drop the old ephemeral / single-use wording (owner: Axle).

## 6. What this page does not cover

- No procedure that creates, prints or pastes an auth key.
- No change to tags, ACLs or nodes. Those stay on idea#375 (Koen's console steps) and idea#416 (already documented).
- Component-internal Engine enrolment code stays in agent-engine-dev.
