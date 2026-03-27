# IDEA — Initiative for Digital Education in Africa

IDEA deploys offline computing infrastructure into rural African schools that have no internet
access and no on-site IT support. A Raspberry Pi in each school runs completely offline,
giving teachers and students access to curated educational tools — Kolibri, Nextcloud, and
offline Wikipedia — accessible from any device on the school's local Wi-Fi.

---

## This Repository

This is the **org root** for the IDEA virtual company. It is the shared coordination layer
for a team of AI agents, each playing a defined role, working under CEO oversight.

It holds no agent workspace content. Agent code and working files live in their own repos
under `agents/`. This repo holds what the whole team shares:

```
idea/
├── platform/               ← IDEA Platform: unified Docker stack (OpenClaw + Mission Control)
│   ├── compose.yaml        ← 6 services on a shared network — the single source of truth
│   ├── openclaw.json       ← Agent roster and config (no secrets)
│   ├── .env.template       ← Credential placeholders (copy to .env, gitignored)
│   └── secrets/            ← API keys as files (gitignored, never commit)
├── CONTEXT.md              ← Shared knowledge: mission, system, key concepts (read by all agents)
├── ROLES.md                ← Agent roster with repo links and scope
├── PROCESS.md              ← How work flows: proposals, approvals, task dispatch
├── BACKLOG.md              ← Auto-exported from Mission Control (do not edit manually)
├── prompting-guide-opus.md ← Claude prompting best practices for writing AGENTS.md files
├── standups/               ← Daily standup records (CEO-triggered)
├── discussions/            ← Multi-agent dialogue threads
├── design/                 ← RFC-style design docs for complex features
├── proposals/              ← New ideas awaiting CEO approval
├── scripts/                ← Shared scripts (standup, task checks, backlog export, setup)
├── skills/                 ← Shared OpenClaw skills available to all agents
└── agents/                 ← Agent workspaces (independent git repos, nested here for mounting)
```

---

## The Team

| Agent | Repo | Role |
|-------|------|------|
| Atlas 🗺️ | [agent-operations-manager](https://github.com/koenswings/agent-operations-manager) | COO & Quality Manager — org design, operations, PR review across all repos |
| Axle ⚙️ | [agent-engine-dev](https://github.com/koenswings/agent-engine-dev) | Engine software: TypeScript, Node.js, Automerge, Docker, Raspberry Pi |
| Pixel 🖥️ | [agent-console-dev](https://github.com/koenswings/agent-console-dev) | Console UI: Solid.js, Chrome Extension |
| Beacon 🌐 | [agent-site-dev](https://github.com/koenswings/agent-site-dev) | Public website: static site, GitHub Pages |
| Marco 📋 | [agent-programme-manager](https://github.com/koenswings/agent-programme-manager) | Field coordination, teacher guides, supporter comms, fundraising |

The CEO (Koen) is the sole human. He approves all plans before execution and merges all PRs.

---

## How It Works

**Plan mode is always on.** No agent acts without first showing its plan to the CEO and
receiving approval. This is enforced at the OpenClaw platform level.

**All changes go via PR.** No agent commits directly to `main` in any repo. Branch protection
is active on all repos. Only the CEO merges.

**The backlog is the source of truth.** Agents work on tasks assigned in Mission Control.
`BACKLOG.md` is a read-only auto-export of the current board state.

**Proposals are how ideas grow.** Any agent can open a proposal by creating
`proposals/YYYY-MM-DD-<topic>.md` and raising a PR. The CEO decides by merging or closing.

**Agents coordinate through shared files.** Agents cannot talk to each other directly.
Cross-agent coordination happens through review tasks, discussion threads in `discussions/`,
and `@agent-id` mentions in shared documents.

See `PROCESS.md` for the full workflow.

---

## The Product

**The Engine** is a TypeScript/Node.js application running on each school's Raspberry Pi.
It detects and processes App Disks (USB drives containing educational applications), manages
Docker containers for each app, synchronises state across multiple Pis on the same school
network using Automerge (a CRDT library), and serves the Console UI on the local LAN.

**The Console** is a web UI accessible from any device on the school's Wi-Fi. Teachers
use it to see and manage the apps running on the Pi.

**App Disks** are USB drives or SSDs containing one application bundled with metadata.
Plugging a disk in starts the app. Removing it stops it. No configuration required.

The system is designed to run **unattended**. It starts automatically, handles errors
gracefully, and requires no human intervention during normal operation. Reliability is the
primary design constraint — more important than features, performance, or convenience.

---

## Shared Knowledge

All agents read `CONTEXT.md` at the start of each session. That file covers the mission,
the system architecture, key concepts (App Disks, offline-first, data sync), and guiding
principles. Updating `CONTEXT.md` propagates new knowledge to all agents simultaneously.

---

## Infrastructure

The virtual company runs on a Raspberry Pi 5 using the **IDEA Platform** — OpenClaw (AI agent
runtime) and Mission Control (task management), deployed together as a unified Docker stack defined
in `platform/compose.yaml`. Each agent has a dedicated Telegram group for direct communication
with the CEO.

Access (Tailscale required):
- Mission Control: `https://openclaw-pi.tail2d60.ts.net:4000`
- OpenClaw UI: `https://openclaw-pi.tail2d60.ts.net`
