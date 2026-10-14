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

## store/COMPACTION-PLAN-devpool.md
**Status:** Authoritative (executed 2026-10-13)  ·  **Maintained by:** Axle (plan) / Atlas (executor)
Procedure for compacting the dev-pool Automerge store into a fresh document (freeze, merge heads, swap, verify steps 13-18, rollback).
→ [docs/store/COMPACTION-PLAN-devpool.md](store/COMPACTION-PLAN-devpool.md)

## store/COMPACTION-RESULT-devpool-20261013.md
**Status:** Authoritative  ·  **Maintained by:** Atlas
Evidence summary of the 2026-10-13 compaction: 3zoqd -> 2VroE, 175,189 changes -> 1, 26 MB -> 322 KB, downtime 14:54-15:14 CEST, verify PASS.
→ [docs/store/COMPACTION-RESULT-devpool-20261013.md](store/COMPACTION-RESULT-devpool-20261013.md)

## store/STORE-GROWTH-PROPOSAL.md
**Status:** Design, in pool proof (engine #192/#194, console #148; target < 2k changes/day)  ·  **Maintained by:** Axle
Why the shared store grows (heartbeats/metrics in history) and the plan: ephemeral heartbeat/metrics, archive ops, compaction.
→ [docs/store/STORE-GROWTH-PROPOSAL.md](store/STORE-GROWTH-PROPOSAL.md)

## DOCUMENTATION-RULES.md
**Status:** Proposed  ·  **Maintained by:** Steve / Atlas
Where documents live, naming, build and secrets rules; inventory with proposed locations.
→ [docs/DOCUMENTATION-RULES.md](DOCUMENTATION-RULES.md)
