# Agent Context and Startup Protocol

**Status:** Reference  
**Author:** Axle (Engine Developer)  
**Date:** 2026-03-24  
**Scope:** All IDEA agents

---

## Overview

Every IDEA agent runs inside OpenClaw. At the start of every session the agent has no memory of
previous conversations — context is rebuilt from files. This document explains exactly what
each agent knows when it wakes up, how that knowledge gets there, and who is responsible for
maintaining each file.

---

## Two Loading Mechanisms

### 1. Auto-injected by OpenClaw (always present, no agent action needed)

OpenClaw injects these files from each agent's workspace directory directly into the system
prompt before the first message. The agent does not need to call `read` — the content is
already in context.

| File | Purpose | When injected |
|---|---|---|
| `AGENTS.md` | Operating instructions, startup checklist, role definition | Every session |
| `SOUL.md` | Persona, tone, and boundaries | Every session |
| `USER.md` | Who the user is and how to address them | Every session |
| `IDENTITY.md` | Agent name, vibe, and emoji | Every session |
| `TOOLS.md` | Local tool notes and conventions | Every session |
| `HEARTBEAT.md` | Checklist for heartbeat polling runs | Every session |
| `BOOTSTRAP.md` | First-run setup ritual | First session only (then deleted) |

Injection limits: 20,000 chars per file; 150,000 chars total across all files. Files are
truncated silently if they exceed these limits. Run `/context list` in any session to inspect
exact sizes and truncation status.

**Important:** `SOUL.md`, `USER.md`, and `IDENTITY.md` should NOT be listed in the `AGENTS.md`
startup checklist — they are already in context. Listing them wastes tokens.

### 2. Explicitly read by the agent (agent calls `read` tool on startup)

These files are not auto-injected. The agent must call `read` on them. The instruction to do
so comes from `AGENTS.md` (which itself was auto-injected). Every agent's `AGENTS.md` must
list these explicitly.

| File | What it contains | Who reads it |
|---|---|---|
| `../../CONTEXT.md` | IDEA mission, solution overview, guiding principles | **All agents** — every session |
| `../../BACKLOG.md` | Approved work items (auto-exported from Mission Control) | All agents |
| `memory/YYYY-MM-DD.md` | Daily memory log (today + yesterday) | All agents |
| `MEMORY.md` | Curated long-term memory | Researcher only (main session) |
| `CLAUDE.md` | Project conventions, key commands, architecture overview | Engine Dev, Researcher |
| `docs/SOLUTION_DESCRIPTION.md` | Full solution requirements and vision | Engine Dev |
| `../../standups/` (latest) | Recent standup records | Quality Manager, Programme Manager |
| `../../design/` (relevant docs) | RFC-style design docs for active features | Console Dev |

---

## Per-Agent Startup Checklist

What each agent reads at the start of every session (in addition to the auto-injected files):

### Axle — Engine Developer
1. `../../CONTEXT.md`
2. `docs/SOLUTION_DESCRIPTION.md`
3. `CLAUDE.md`
4. `../../BACKLOG.md`
5. `memory/YYYY-MM-DD.md` (today + yesterday)

### Pixel — Console UI Developer
1. `../../CONTEXT.md`
2. `../../BACKLOG.md`
3. `memory/YYYY-MM-DD.md` (today + yesterday)
4. `../../design/` (relevant docs before feature work)

### Beacon — Site Developer
1. `../../CONTEXT.md`
2. `../../BACKLOG.md`
3. `content-drafts/` (new content to implement)
4. `memory/YYYY-MM-DD.md` (today + yesterday)

### Veri — Quality Manager
1. `../../CONTEXT.md`
2. `../../BACKLOG.md`
3. `../../standups/` (latest)
4. GitHub — open PRs across engine, console, site repos
5. `memory/YYYY-MM-DD.md` (today + yesterday)

### Marco — Programme Manager
1. `../../CONTEXT.md`
2. `../../BACKLOG.md`
3. `../../standups/` (latest)
4. `memory/YYYY-MM-DD.md` (today + yesterday)

### Compass — Researcher
1. `../../CONTEXT.md`
2. `memory/YYYY-MM-DD.md` (today + yesterday)
3. `MEMORY.md` (main session only)

---

## Memory Architecture

Each agent maintains its own memory. There is no shared memory store between agents.

| File | Location | Written by | Survives reboot? | Auto-injected? |
|---|---|---|---|---|
| Daily log | `memory/YYYY-MM-DD.md` | Agent (during session) | Yes | No — must be read |
| Long-term memory | `MEMORY.md` | Agent (curated from daily logs) | Yes | No — must be read |
| Auto-injected files | workspace root | CEO / agent | Yes | Yes — always present |
| Session history | `~/.openclaw/agents/<id>/sessions/` | OpenClaw | Yes (until pruned) | No — OpenClaw managed |

### Daily log lifecycle

1. Agent reads today's and yesterday's `memory/YYYY-MM-DD.md` at session start
2. Agent appends significant decisions, work done, and open questions during the session
3. Pre-compaction flush: OpenClaw triggers a memory write before context is summarised
4. Periodically (every few days): agent reviews recent logs and distils into `MEMORY.md`

### What belongs in memory

| Worth writing down | Not worth writing down |
|---|---|
| Decisions made and why | Routine tool calls |
| Open questions and blockers | Successful reads with no surprises |
| Key technical context (branch names, git state) | Content already in AGENTS.md |
| Koen's stated preferences | Anything in auto-injected files |
| Unresolved items for next session | |

---

## Maintenance

### When `CONTEXT.md` changes
Koen updates `../../CONTEXT.md` at the org level. All agents pick up the change
automatically — they read it fresh at every session start.

### When an agent's role changes
Update that agent's `AGENTS.md`. The change is effective immediately on next session start
(OpenClaw auto-injects the current file).

### When a new agent is added
1. Create workspace directory under `agents/`
2. Copy standard files: `SOUL.md`, `USER.md`, `IDENTITY.md`, `TOOLS.md`, `HEARTBEAT.md`, `BOOTSTRAP.md`
3. Write `AGENTS.md` with role definition and startup checklist (must include `../../CONTEXT.md`)
4. Register agent in `openclaw.json` with correct workspace path
5. Add binding to Telegram group in `openclaw.json`
6. Run BOOTSTRAP session to confirm identity

### Checking injection sizes
Run `/context list` in any active session to see exact file sizes and whether truncation
occurred. If a file is being truncated, either shorten it or split content into a linked
document the agent reads manually.

---

## Common Mistakes

| Mistake | Fix |
|---|---|
| Listing `SOUL.md`/`USER.md`/`IDENTITY.md` in startup checklist | Remove them — they are auto-injected |
| Not reading `CONTEXT.md` at session start | It must be in every agent's `AGENTS.md` startup list |
| Putting project docs in auto-injected files | Keep auto-injected files small; reference docs are read manually |
| Large `TOOLS.md` exceeding per-file limit | Move content to docs/ and link from TOOLS.md |
| Not writing memory before context compaction | OpenClaw triggers a flush, but agents should write proactively too |
