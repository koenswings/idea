# Authoritative Documentation Index — IDEA (Org Level)

Authoritative descriptions of IDEA's organisation, infrastructure, and operations **as they
currently exist** — not as they are intended or planned (that's `proposals/`).

Update this file whenever an authoritative doc is added or significantly revised.

---

## grok-bot-setup.md
**Status:** Authoritative  ·  **Maintained by:** Atlas / Steve
IDEA development setup on Grok Bot: platform, fleet scripts, workflows (Dev Bot + SSH;
Grok Build runner path parked, idea#147), fleet-Pi test claim protocol (§4.6), quality
control (§5), routines, team structure, and Bot descriptions.
→ [docs/grok-bot-setup.md](grok-bot-setup.md)

## README.md
**Status:** Authoritative  ·  **Maintained by:** Koen / Steve
Short orientation for the `docs/` folder.
→ [docs/README.md](README.md)

## ops/BOOT-RECOVERY.md
**Status:** Authoritative  ·  **Maintained by:** Atlas
What comes back after a reboot, fstab loop mounts for fixture disks (rules, rollback), the 05:00 reboot hold, after-reboot checklist.
→ [docs/ops/BOOT-RECOVERY.md](ops/BOOT-RECOVERY.md)

## ops/AVAHI-HOSTNAME-CLASH.md
**Status:** Authoritative (root cause; fix not merged)  ·  **Maintained by:** Atlas
Engine mDNS (ciao) vs avahi both claiming `<host>.local` -> "<host> (2)" rename at every start; impact and proposed fix.
→ [docs/ops/AVAHI-HOSTNAME-CLASH.md](ops/AVAHI-HOSTNAME-CLASH.md)

## ops/TAILSCALE-DECISION.md
**Status:** Decided (Koen)  ·  **Maintained by:** Atlas
Tailscale always on at schools; one fleet tag `tag:idea` and one fleet auth key; ACL admins->tag:idea only, no Pi-to-Pi over Tailscale (LAN websocket only).
→ [docs/ops/TAILSCALE-DECISION.md](ops/TAILSCALE-DECISION.md)
