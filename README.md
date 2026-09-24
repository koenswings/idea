# IDEA — Initiative for Digital Education in Africa

IDEA deploys offline computing infrastructure into rural African schools that have no internet access and no on-site IT support. A Raspberry Pi in each school runs completely offline, giving teachers and students access to curated educational apps — Kolibri, Nextcloud, offline Wikipedia — accessible from any device on the school's local Wi-Fi.

---

## This Repository

This is the **org root** for the IDEA platform. It is the shared coordination layer for the Grok Bot development team — a small fleet of AI agents, each with a defined role, working under Koen's oversight.

It holds no agent workspace content. Agent code lives in its own repos. This repo holds what the whole team shares:

```
idea/
├── CONTEXT.md              ← Mission, product overview, team structure (Lead Bot reads this)
├── fleet-state.json        ← Live Pi fleet state (managed by tools/fleet/ scripts)
├── docs/                   ← Authoritative documentation — describes the system as it is
│   └── grok-bot-setup.md   ← Complete Grok Bot setup: team, workflow, Bot descriptions
├── proposals/              ← New ideas awaiting Koen's approval (see proposals/README.md)
├── tools/
│   ├── fleet/              ← Fleet management scripts (Pi allocation, deploy, health)
│   ├── quality/            ← Quality scan and app version monitoring scripts
│   └── pdf/                ← PDF generation (Markdown → PDF with clickable ToC)
└── audit/
    └── audit-<YYYY>.jsonl  ← Structured audit log — one JSON line per system event
```

---

## The Team

Development runs on Grok Bot. Five Bots plus a programme manager:

| Bot | Domain |
|-----|--------|
| Lead Bot | Design, coordination, GitHub issues and proposals |
| Engine Dev Bot | Engine runtime (`koenswings/agent-engine-dev`) |
| Console Dev Bot | Console web app (`koenswings/agent-console-dev`) |
| App Dev Bot | App Disk builds and updates (`koenswings/agent-app-dev` + App repos) |
| Ops Bot | Pi fleet, scripts, review environments |
| Marco Bot | App scouting, field coordination, teacher guides |

Koen is the CEO — every PR requires his review and merge.

---

## The Pi Fleet

A variable number of Raspberry Pis form the build, test, review, and golden-instance fleet. Any Pi enrolled in Tailscale as `idea<N>` is automatically discovered and available. Fleet state is tracked in `fleet-state.json` and managed by the scripts in `tools/fleet/`.

---

## Key Repos

| Repo | Contents |
|------|----------|
| `koenswings/idea` | This repo — org root |
| `koenswings/agent-engine-dev` | Engine source |
| `koenswings/agent-console-dev` | Console source |
| `koenswings/agent-app-dev` | App Disk workspace and harness |
| `koenswings/app-<name>` | Per-App repos (Kolibri, Nextcloud, Kiwix, …) |

Tasks tracked as GitHub Issues on this repo. Labels: `engine`, `console`, `app-dev`, `ops`, `quality`, `docs-review`, `app-update`, `new-app-proposal`.

---


## Checkout layout (Pi + local)

On fleet Pis and local quality-scan / box checkouts, clone `idea` then nest agent repos under `agents/`. App GitHub repos are checked out **under `agent-app-dev/`** (not as siblings of the other agent repos):

```
idea/
  agents/
    agent-engine-dev/     # Engine — pm2 cwd; ENGINE_CWD / ENGINE_BIN here
    agent-console-dev/    # Console — build → dist/; Engine consolePath points here
    agent-app-dev/        # App Disk workspace (koenswings/agent-app-dev)
      app-kolibri/        # clone of koenswings/app-kolibri
      app-nextcloud/
      app-kiwix/
      app-milkwise/
```

Canonical paths, retired layouts, and idea02 migration: [`docs/grok-bot-setup.md`](docs/grok-bot-setup.md) §2.3.1 and [`proposals/pi-checkout-layout.md`](proposals/pi-checkout-layout.md).

## Setup

Full documentation: [`docs/grok-bot-setup.md`](docs/grok-bot-setup.md)

For the migration from the prior OpenClaw setup: [`proposals/grok-bot-migration.md`](proposals/grok-bot-migration.md)

Rollback to the prior setup: `git checkout v-openclaw-final`
