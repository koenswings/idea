# BACKLOG.md — IDEA Master Backlog

All items here are approved by the CEO. Work on unapproved items only with explicit instruction.
To propose a new item, follow the process in `PROCESS.md`.

---

## HQ / Setup

- [ ] Create GitHub organisation (`idea-edu-africa`) and all repos
- [ ] Create `/home/pi/idea/` directory structure on Pi; move existing repos into place
- [ ] Update Docker volume mount in `compose.yaml`: `/home/pi/projects` → `/home/pi/idea`
- [ ] Create `CONTEXT.md` at org root — mission, solution overview, key concepts, guiding principles
- [ ] Create `prompting-guide-opus.md` at org root — Opus 4.6 prompting best practices
- [ ] Update `ROLES.md` to link all 7 repos
- [ ] Write `scripts/export-backlog.sh` — queries MC REST API, generates BACKLOG.md
- [ ] Design standup template (`standups/TEMPLATE.md`) and enhance `./standup` script
- [ ] Write AGENTS.md files for each agent workspace
- [ ] Update `openclaw.json` — rename existing agents, add new agents, update workspace paths
- [ ] Copy sandbox files (IDENTITY, SOUL, USER, TOOLS, HEARTBEAT, BOOTSTRAP) to each agent
- [ ] Restart OpenClaw after config change
- [ ] Set up branch protection on `main` in each GitHub repo (CEO-only merge)
- [ ] Pair browser with each new agent in the OpenClaw UI
- [ ] Run BOOTSTRAP session for each new agent
- [ ] Deploy Mission Control; configure board hierarchy (IDEA org → Engineering / HQ boards)
- [ ] Migrate backlog items into Mission Control
- [ ] Define cron and heartbeat schedule for all agents

---

## Engine

- [ ] Review and improve Solution Description
- [ ] Update Architecture doc from Solution Description
- [ ] Remove Docker dev environment support from docs and code
- [ ] Test setup design — automated tests, simulate disk dock/undock, multi-engine scenarios
- [ ] Refactor `script/` to `scripts/`
- [ ] Scan Solution Description for unimplemented features
- [ ] Review run architecture: which user? File ownership and permissions?

---

## Console UI

- [ ] Create repo and initial AGENTS.md
- [ ] Document Console UI architecture: Solid.js, Chrome Extension, Engine API contract
- [ ] First version of UI from Solution Description outline

---

## Website

- [ ] Confirm framework: Astro or Hugo
- [ ] Create repo and initial AGENTS.md
- [ ] Set up GitHub Pages deployment via GitHub Actions
- [ ] First version: mission, how it works, how to support

---

## Programme Manager

- [ ] Create repo and initial AGENTS.md
- [ ] Define brand voice and key messages (`brand/tone-of-voice.md`, `brand/key-messages.md`)
- [ ] Define teacher guide delivery pipeline (Engine-served + Console-embedded + printable PDF)
- [ ] Getting Started guide (hardware setup, first boot)
- [ ] App guides: Kolibri, Nextcloud, offline Wikipedia
- [ ] Privacy notice template for schools
- [ ] Research applicable grant programmes (EU development, UNESCO, UNICEF, Gates, RPi Foundation)
- [ ] Create grant tracking document (`grant-tracker.md`)
- [ ] Draft first funding opportunity brief
- [ ] Draft website content: mission page, how it works, how to support
- [ ] Create donor newsletter template
- [ ] Create impact report template
