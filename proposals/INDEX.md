# Proposals Index — IDEA (Org Level)

New ideas awaiting CEO approval. Any agent or the CEO can open a proposal.
See `proposals/README.md` for format and lifecycle guidance.

Update this file whenever a proposal is added, approved, rejected, or superseded.

---

## 2026-04-01-agent-identity-memory-architecture.md
**Status:** Proposed — awaiting CEO decision  ·  **Date:** 2026-04-01  ·  **Author:** Atlas
Proposes a new three-layer architecture for agent identity and memory. Group 1 files (AGENTS.md,
SOUL.md, etc.) move to `idea/identity/`; memory and outputs move to a new `idea-memory` repo;
cron handles all backup — agents never run git for memory. Eliminates memory/updates PR workflow.
Includes identity change protocol via Telegram relay.
→ [proposals/2026-04-01-agent-identity-memory-architecture.md](2026-04-01-agent-identity-memory-architecture.md)

## 2026-03-28-app-dev-agent.md
**Status:** Proposed — awaiting CEO decision  ·  **Date:** 2026-03-28  ·  **Author:** Atlas
Proposes Kit 🎒 as a sixth operational agent (App Developer & Maintainer). Covers role
definition, app repos as git submodules, harness, monitoring, Docker builds on Pi, and
data storage approach. Two sub-proposals pending (data storage options, compatibility matrix).
→ [proposals/2026-03-28-app-dev-agent.md](2026-03-28-app-dev-agent.md)
