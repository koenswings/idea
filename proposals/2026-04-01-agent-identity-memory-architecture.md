# Proposal: Agent Identity and Memory Architecture

**Proposed by:** Atlas (operations-manager)
**Date:** 2026-04-01
**Status:** Proposed

---

## Problem

The current approach to agent configuration and memory has three structural weaknesses:

**1. Memory is tracked in git with PR overhead.**
Every session note requires a commit, push, PR creation, PR verification, merge, and branch
recreation. Agents forget steps. PRs accumulate. Memory updates that should be instant take
days to reach main. The `memory/updates` branch workflow is the single biggest source of
operational friction in the current setup.

**2. Identity files are scattered across five separate repos.**
Each agent's `AGENTS.md`, `SOUL.md`, `TOOLS.md`, and related files live in their own repo.
Installing the virtual company on a new node requires cloning five repos and manually ensuring
consistency. Atlas making an org-wide change (e.g., updating the cross-agent protocol) requires
PRs across five repos simultaneously.

**3. Agents are responsible for their own persistence.**
Agents push their own memory to git. When sessions end unexpectedly or agents are interrupted
mid-task, memory is lost. Relying on agent discipline for backup is inherently fragile.

---

## Proposed Solution

A three-layer architecture that separates identity (who the agent is), memory (what the agent
remembers), and working code (what the agent builds).

### Layer 1 — Agent identity: `idea/identity/`

All Group 1 files for every agent live in a subfolder of the existing `idea` repo:

```
idea/
  identity/
    atlas/
      AGENTS.md
      SOUL.md
      IDENTITY.md
      USER.md
      TOOLS.md
      HEARTBEAT.md
      CLAUDE.md
    axle/
      AGENTS.md, SOUL.md, ...
    pixel/
      AGENTS.md, SOUL.md, ...
    beacon/
      AGENTS.md, SOUL.md, ...
    marco/
      AGENTS.md, SOUL.md, ...
```

These files:
- Live on `main` in the `idea` repo — branch-protected, PR-reviewed
- Are the **canonical source of truth** for each agent's behaviour
- Are copied into each agent's workspace during install (see below)
- Are maintained by Atlas as the COO
- Change rarely and deliberately

**Why in `idea/` rather than a new repo:** identity files are org-level config, not code. They
belong alongside `CONTEXT.md`, `design/`, and `BACKLOG.md`. One less repo to clone on restore.

### Layer 2 — Agent memory: `idea-memory` repo (new)

A dedicated repo with **no branch protection**. Agents write directly to main.

```
idea-memory/
  atlas/
    MEMORY.md
    memory/
      2026-04-01.md
      ...
    outputs/
      2026-04-01-0900-topic.md
      ...
  axle/
    memory/
    outputs/
  pixel/ ...
  beacon/ ...
  marco/ ...
```

These files:
- Are written locally by agents immediately, with no git involvement
- Are **never pushed by agents** — a cron handles all persistence
- Are the agent's session continuity layer — summarised traces read at boot
- Include `outputs/` which are the full auditable trace of past interactions (written but
  never auto-read)

**Memory vs outputs distinction:**
- `memory/YYYY-MM-DD.md` — summarised traces: what happened, decisions, open threads. Read at
  session start. Gives the agent continuity.
- `MEMORY.md` (Atlas only) — long-term distillation of durable facts. Read at session start.
- `outputs/` — full traces: complete responses for audit and reference. Never auto-loaded.

### Layer 3 — Agent working repos (unchanged)

Each agent repo (`agent-engine-dev`, `agent-console-dev`, etc.) remains exactly as it is —
code, docs, design files, tests. Branch-protected. PR-reviewed. Identity and memory files are
no longer tracked here.

---

## Cron Backup

A single cron job on the Pi handles all memory persistence:

```
backup-memory.sh   runs: every hour
```

For each agent workspace, it:
1. Detects any new or modified files in `memory/`, `MEMORY.md`, and `outputs/`
2. Copies them to the corresponding directory in the `idea-memory` working tree
3. Commits and pushes to `origin/main`

Agents write files locally. That is their only responsibility. The cron ensures nothing is lost
even if a session ends unexpectedly.

A daily cron also backs up identity files from agent workspaces to `idea/identity/`:

```
backup-identity.sh   runs: daily (or on demand)
```

This is a safety net only — identity changes go through explicit PRs as the primary mechanism.

---

## Identity Change Protocol

When an agent's behaviour needs to change (new procedure, updated protocol, corrected habit):

1. **Atlas edits** the relevant Group 1 file on disk in the agent's workspace
2. **Atlas commits** the change to `idea/identity/[agent]/` on a branch and opens a PR
3. **Atlas notifies** via Koen: `📨 For [Agent]: your AGENTS.md has been updated. Change:
   [one-sentence summary]. Please read your AGENTS.md now to pick it up in this session.`
4. **Koen forwards** the message to the agent's Telegram group
5. **Agent reads** the updated file immediately — aware in the current session
6. **Koen merges** the PR — change is on main and will auto-load in future sessions

This gives both Koen and the agent immediate awareness, while preserving git history for all
identity changes. No behavioural change takes effect silently.

---

## File Classification Reference

| File | Group | Who writes | How loaded | In git |
|------|-------|-----------|-----------|--------|
| AGENTS.md | 1 | Atlas/Koen | OpenClaw auto-injects at session start | idea/identity/ |
| SOUL.md | 1 | Atlas/Koen | OpenClaw auto-injects | idea/identity/ |
| IDENTITY.md | 1 | Atlas/Koen | OpenClaw auto-injects | idea/identity/ |
| USER.md | 1 | Atlas/Koen | OpenClaw auto-injects | idea/identity/ |
| TOOLS.md | 1 | Atlas/Koen | OpenClaw auto-injects | idea/identity/ |
| HEARTBEAT.md | 1 | Atlas/Koen | OpenClaw auto-injects | idea/identity/ |
| CLAUDE.md | 1 | Atlas/Koen | OpenClaw auto-injects (pointer only) | idea/identity/ |
| CONTEXT.md, design/, docs/, etc. | 2 | Koen/agents | Agent reads manually at boot | idea/ main |
| BACKLOG.md, standups/ | 2 | Auto-export/cron | Agent reads manually at boot | idea/ main |
| memory/YYYY-MM-DD.md | 3 | Agent | Agent reads manually at boot | idea-memory/ |
| MEMORY.md | 3 | Agent (Atlas only) | Agent reads manually at boot | idea-memory/ |
| outputs/ | 3 | Agent | Never auto-loaded (audit only) | idea-memory/ |

---

## Install / Restore Procedure

Setting up a new node:

```bash
# 1. Clone org repo (config, design docs, scripts, identity)
git clone https://github.com/koenswings/idea /home/pi/idea

# 2. Clone memory backup
git clone https://github.com/koenswings/idea-memory /home/pi/idea-memory

# 3. Copy identity files into agent workspaces (OpenClaw reads from workspace)
for agent in atlas axle pixel beacon marco; do
  cp -r /home/pi/idea/identity/$agent/* /home/pi/idea/agents/agent-*/
done

# 4. Copy memory files into agent workspaces
for agent in atlas axle pixel beacon marco; do
  cp -r /home/pi/idea-memory/$agent/* /home/pi/idea/agents/agent-*/
done

# 5. Configure cron jobs (backup-memory.sh, backup-identity.sh)
# Handled by existing platform setup scripts
```

Full restore of a complete system: two clones and two copy steps.

---

## Migration Plan

1. **Create `idea-memory` repo** (Koen) — empty, no branch protection
2. **Create `idea/identity/` structure** — Atlas copies current Group 1 files into place, opens PR
3. **Update OpenClaw config** for each agent to read Group 1 files from new location (or update
   workspace paths so files are still found at existing paths — TBD, see Open Questions)
4. **Write `backup-memory.sh`** — Atlas writes, Koen reviews and adds to cron
5. **Write `backup-identity.sh`** — Atlas writes, Koen reviews and adds to cron
6. **Remove memory tracking from agent repos** — add `memory/`, `MEMORY.md`, `outputs/` to
   `.gitignore` in each agent repo
7. **Close `memory/updates` PRs** in all five agent repos — this workflow is retired
8. **Update AGENTS.md** for all agents — memory section simplified, identity change protocol added
9. **Update virtual-company-design.md** — document the new architecture

---

## Impact on Agents

**Memory procedure (current):** write file → commit → push → verify PR → handle failures

**Memory procedure (proposed):** write file. Done.

**Identity change (current):** Atlas opens PR across multiple repos; agents pick it up next session

**Identity change (proposed):** Atlas edits file → Koen forwards Telegram message → agent aware
immediately → PR merges to persist

---

## Open Questions

1. **OpenClaw workspace path:** OpenClaw currently reads Group 1 files from each agent's
   workspace directory. If files move to `idea/identity/`, does OpenClaw need config changes,
   or can we maintain the same effective paths via copies/setup scripts? Needs testing.

2. **`idea-memory` repo visibility:** public or private? Memory files contain operational
   context and potentially sensitive infrastructure details. Recommend private.

3. **Cron frequency for memory backup:** hourly is proposed. Is more frequent needed? Less?

4. **MEMORY.md scope:** currently Atlas-only. Should other agents have a long-term MEMORY.md
   equivalent, or is daily memory sufficient for them?

5. **Outputs retention policy:** outputs/ will grow indefinitely. Should old outputs be pruned
   or archived after some period?
