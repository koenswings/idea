# ROLES.md — IDEA Team

IDEA (Initiative for Digital Education in Africa) operates as a virtual company.
Each role is an AI agent with a defined workspace and scope. The CEO (Koen) is the sole human:
he approves all plans before execution and merges all PRs.

---

## Agent Roster

| Agent id | Repo | Workspace (container) | Scope |
|----------|------|-----------------------|-------|
| `engine-dev` | `koenswings/agent-engine-dev` | `/home/node/workspace/agents/agent-engine-dev` | Engine software: TypeScript, Automerge, Docker, Raspberry Pi |
| `console-dev` | `koenswings/agent-console-dev` | `/home/node/workspace/agents/agent-console-dev` | Console UI: Solid.js, Chrome Extension |
| `site-dev` | `koenswings/agent-site-dev` | `/home/node/workspace/agents/agent-site-dev` | Public website: Astro/Hugo, GitHub Pages |
| `quality-manager` | `koenswings/agent-quality-manager` | `/home/node/workspace/agents/agent-quality-manager` | PR review across all code repos; cross-project consistency |
| `programme-manager` | `koenswings/agent-programme-manager` | `/home/node/workspace/agents/agent-programme-manager` | Field coordination, teacher guides, supporter comms, fundraising |
| `researcher` | `koenswings/agent-researcher` | `/home/node/workspace/agents/agent-researcher` | Strategic advisor to CEO — org structure, governance (CEO-only) |

> **Note:** Repos are currently under `koenswings` while the GitHub organisation name is being
> finalised. Once the org is created, all repos will be transferred and these paths will update.

The `idea` repo (this repo) is the shared org root: `CONTEXT.md`, `ROLES.md`, `BACKLOG.md`,
`PROCESS.md`, `standups/`, `discussions/`, `design/`, `proposals/`.

---

## Shared Knowledge

All agents read `CONTEXT.md` (this repo root) at the start of each session. That file covers:
- IDEA's mission and the problem it solves
- How the system works: Engine, Console, App Disks, offline-first, data synchronization
- Guiding principles shared across all roles

`SOUL.md` (in each agent's sandbox) covers values and behaviour.
`AGENTS.md` (per agent repo root) covers role-specific instructions.
`CONTEXT.md` (this repo root) covers factual product and mission knowledge.

---

## How the Team Works

**Plan mode is always on.** No agent acts without first showing its plan to the CEO.

**All changes go via PR.** No agent commits directly to `main` in any repo.

**The backlog is the source of truth.** Agents only work on approved items in `BACKLOG.md`,
unless given explicit in-session instruction.

**Proposals are how ideas grow.** Any agent can open a proposal PR in `proposals/`.
See `PROCESS.md` for the full pipeline.

---

## Role Boundaries

- `engine-dev` and `console-dev` write code. They do not write external content.
- `quality-manager` reviews code and documents. It does not write features or content.
- `programme-manager` handles field coordination, teacher guides, supporter comms, and fundraising.
  It does not make external contact without CEO approval.
- `site-dev` builds the website. Content comes from `programme-manager` via PRs to `content-drafts/`.
- `researcher` advises the CEO on organisation structure. It does not participate in daily operations.

When a task spans roles (e.g., programme-manager needs a UX assessment from console-dev), it goes
through a proposal PR. See `PROCESS.md`.
