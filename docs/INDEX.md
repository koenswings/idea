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

## DOCUMENTATION-RULES.md
**Status:** Proposed  ·  **Maintained by:** Steve / Atlas
Extends proposals/README.md and docs/README.md: adds docs/manuals/<audience>/<name>/ and docs/house-style/; naming, build and secrets rules; inventory with proposed locations.
→ [docs/DOCUMENTATION-RULES.md](DOCUMENTATION-RULES.md)

## ops/boot-recovery.md
**Status:** Authoritative  ·  **Maintained by:** Atlas
What comes back after a reboot, fstab loop mounts for fixture disks (rules, rollback), the 05:00 reboot hold, after-reboot checklist.
→ [docs/ops/boot-recovery.md](ops/boot-recovery.md)

## ops/store-compaction-devpool.md
**Status:** Authoritative (executed 2026-10-13)  ·  **Maintained by:** Atlas
Runbook for compacting the dev-pool Automerge store into a fresh document (freeze, merge heads, swap, verify 13-18, rollback), with the result record: 3zoqd -> 2VroE on 2026-10-13 14:54-15:14 CEST, cover-all r86t 128/128 afterwards.
→ [docs/ops/store-compaction-devpool.md](ops/store-compaction-devpool.md)
