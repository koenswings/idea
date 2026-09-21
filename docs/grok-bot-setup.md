# IDEA Platform: Grok Bot Setup

**Author:** Atlas
**Date:** 2026-09-20
**Status:** Authoritative — describes the current setup

---

## Contents

| # | Section |
|:---:|---|
| **1** | Overview |
| **2** | Platform — Subscription · Grok Build · Pi Fleet · Fleet Scripts · GitHub |
| **3** | Development Workflow — Bug fix path · Feature path · Paper trail |
| **4** | Fleet Review Environments — Scripts · Manifest · Deploy · Golden instance · Health |
| **5** | Quality Control — QC gate · Post-merge scan · Living docs · Doc policy · AGENTS.md contract |
| **6** | Routines — All scheduled and event-triggered workflows |
| **7** | Team Structure — Roles · Group chats · Memory model |
| **8** | Bot Descriptions — Lead · Engine Dev · Console Dev · App Dev · Ops · Marco |
| **9** | AGENTS.md for Each Repo — Engine · Console · App Dev |
| **10** | Audit Trail — GitHub Actions logs · Structured event log · Recommended approach |
| **11** | koenswings/idea Repository |

---

## 1. Overview

This document describes the IDEA development setup on Grok Bot — the platform, tools, workflows, quality standards, team structure, and Bot configurations.

Development conversations happen in Grok Bot chat. Code lives on GitHub. Builds and tests run on the Pi fleet via Grok Build. Koen evaluates every PR on real Pi hardware before merging. Quality is enforced at every step — in Bot descriptions, in Grok Build instructions (AGENTS.md), and by fleet management scripts.

**Core design principle — LLM vs Script:**

Bots (LLMs) handle judgment, communication, and synthesis: understanding Koen's intent, routing work, writing proposals, synthesising design review feedback, deciding when to escalate. All deterministic algorithms — Pi allocation, deployment sequencing, health checks, quality scans, version monitoring — are implemented as scripts. Bots invoke scripts and act on their output; they do not reimplement the logic.


---

## 2. Platform

### 2.1 Subscription

**Keep SuperGrok Heavy. No additional subscription needed.**

Link your SuperGrok Heavy account to a free Cursor account once. That grants Grok Bot access at the highest usage tier.

| Component | Cost | Notes |
|-----------|------|-------|
| Grok Bot | Included in SuperGrok Heavy | Link Grok account to Cursor |
| Grok Build (coding on Pis) | Pay-per-use (~$1/1M tokens) | XAI_API_KEY on each Pi |
| Cursor Cloud Agents | Not used | IDEA builds ARM — x86 VMs cannot build or test it |

### 2.2 Coding Tool: Grok Build

All coding work runs on the Pi fleet via **Grok Build** — xAI's open-source terminal coding agent. It runs natively on ARM64 and is the correct tool for IDEA because every component must compile and run on Raspberry Pi hardware.

Key capabilities:

- Reads `AGENTS.md` natively — this file is the per-repo build, test, and deploy manual
- Up to 8 parallel subagents per task, each in its own git worktree
- Plan Mode: proposes a full diff before touching any file
- Headless mode for Bot-driven automation: `grok -p "task"`
- Routes to any model via OpenRouter — Claude, Grok, or others

**Install on each Pi:**
```bash
curl -fsSL https://x.ai/cli/install.sh | bash
grok auth login   # Koen authenticates via browser once
```

### 2.3 Pi Fleet

The IDEA fleet is a variable number of Raspberry Pis — any Pi enrolled in Tailscale with a hostname matching `idea*` is automatically discovered and available for work. There is no hardcoded Pi count.

Each Pi runs:

- Tailscale (hostname: `idea<N>`, reachable at `idea<N>.tail2d60.ts.net`)
- GitHub Actions self-hosted runner (label matches Tailscale hostname)
- Grok Build
- Engine running via pm2 at `/home/pi/projects/engine`

**Roles are assigned dynamically at runtime** by the fleet scripts (see Section 2.4). By convention, the first available Pi for a given domain is used; one Pi is designated golden. These assignments are recorded in `fleet-state.json` and update as Pis come and go.

### 2.4 Fleet Scripts

All deterministic fleet operations are implemented as scripts in `koenswings/idea/tools/fleet/`. Bots call these scripts and act on their output — they do not reimplement the logic.

| Script | Purpose |
|--------|---------|
| `idea-setup.sh` | Platform install: discover all `idea*` Pis via Tailscale, install Grok Build, register GitHub Actions runner, verify dependencies, initialise `fleet-state.json` |
| `find-available-pi.sh <domain>` | Read `fleet-state.json`, apply domain affinity, return the first idle Pi. Returns empty if none available. |
| `deploy.sh <pi> <component> <repo> <branch>` | Full deploy sequence for the given component type (engine/console/app-disk): checkout, build, start, health check |
| `teardown.sh <pi>` | Reverse deploy: clean state, restore main, mark Pi idle in `fleet-state.json` |
| `update-golden.sh <component> <version>` | Update the golden Pi to the given version of a component |
| `set-golden-pi.sh` | Designate the most recently idle Pi as the new golden instance |
| `check-fleet-health.sh` | HTTP health check all deployed Pis, return JSON status |
| `update-fleet-state.sh <pi> <field> <value>` | Atomic read-modify-write of `fleet-state.json` (no race conditions) |
| `quality-scan.sh <repos...>` | Structural checks: source files in docs/, AGENTS.md freshness, TODO count. Returns JSON report. |
| `check-app-versions.sh` | Read app.yaml files, query DockerHub/GitHub APIs for latest versions, compare with current. Returns JSON diff. |

All scripts are idempotent. They write their results to stdout as structured JSON for Bot consumption.

Fleet and quality scripts also append one JSON event line to `audit/audit-<YYYY>.jsonl` in `koenswings/idea` after every significant action. This provides a permanent, inspectable record of all system-level events (see the Audit Trail section below for the full design).

**Installation:** scripts live in `koenswings/idea/tools/fleet/`. They run on any Pi that has the idea repo cloned. Dependencies: `bash`, `jq`, `curl`, `ssh`, `tailscale`. All standard on fleet Pis.

### 2.5 GitHub as Source of Truth

| Repo | Contents |
|------|----------|
| `koenswings/idea` | Org root: issues, proposals, design docs, CONTEXT.md, fleet-state.json, tools/, audit/ |
| `koenswings/agent-engine-dev` | Engine source |
| `koenswings/agent-console-dev` | Console source |
| `koenswings/agent-app-dev` | App Disk workspace and harness |
| `koenswings/app-<name>` | Per-App repos (Kolibri, Nextcloud, Kiwix, MilkWise IDEA App, …) |

GitHub Issues on `koenswings/idea` is the task register. Labels: `engine`, `console`, `app-dev`, `ops`, `quality`, `docs-review`, `app-update`, `new-app-proposal`.

---

## 3. Development Workflow

The workflow has two paths depending on the nature of the request. Quality control gates each transition; fleet scripts handle all deterministic operations.

### 3.1 Bug Fix / Small Change

```
Koen describes problem to Lead Bot
  │
  ▼
Lead Bot discusses until approach agreed
  → posts agreed approach as comment on GitHub issue
  → delegates to Dev Bot (issue number + approach)
  │
  ▼
Dev Bot reads issue + agreed approach comment
  → triggers Grok Build on Pi runner (headless mode)
  → Grok Build reads AGENTS.md, plans, edits, builds, runs tests
  │
  ▼
Dev Bot runs QC gate (see Section 5)
  ├── FAIL → Grok Build fixes and retries (one retry max)
  ├── FAIL after retry → escalates to Lead Bot with diagnosis
  └── PASS → opens PR linked to issue
           → posts PR link as comment on issue
           → notifies Ops Bot
  │
  ▼
Ops Bot calls find-available-pi.sh <domain>
  ├── Pi found → calls deploy.sh <pi> <component> <repo> <branch>
  │              → updates fleet-state.json via update-fleet-state.sh
  │              → notifies Lead Bot with live URL
  └── No Pi → queues PR in fleet-state.json, notifies Lead Bot
  │
  ▼
Lead Bot notifies Koen: "PR #X ready — live at http://idea<N>.tail…"
  │
  ▼
Koen evaluates on real Pi hardware via Tailscale
  ├── changes requested → Lead Bot discusses, updates issue comment, re-delegates
  └── approved → Koen merges PR on GitHub → issue auto-closes
  │
  ▼
Ops Bot calls teardown.sh <pi>
  → calls update-golden.sh <component> <version>
  → calls check-fleet-health.sh (verifies golden is healthy)
  → calls find-available-pi.sh for any queued PRs
```

### 3.2 Feature / Design Decision

```
Koen describes feature intent to Lead Bot
  │
  ▼
Lead Bot reads koenswings/idea/CONTEXT.md + relevant repos
  → drafts a proposal: what, why, affected domains,
    approach options, open questions
  │
  ▼
Lead Bot posts proposal to Design Review group chat
  → all Dev Bots respond with domain assessments
  → Lead Bot synthesises, refines proposal
  │
  ▼
Lead Bot posts final proposal as PR to koenswings/idea/proposals/
  → Koen reviews and merges the proposal PR
  │
  ▼
Lead Bot creates implementation GitHub issue(s) per affected repo
  → delegates to Dev Bot(s)
  → follows bug fix path from "Dev Bot reads issue..." onward
```

**When to use design review (default to yes if unsure):**

- Anything touching more than one repo
- New external dependencies or services
- Changes to cross-repo interfaces or data formats
- Anything Koen flags as needing a design doc

### 3.3 The GitHub Paper Trail

Every decision that leads to code being written must be recorded on GitHub before the code is written:

- Lead Bot posts an agreed approach comment on the issue before delegating
- For feature work: a merged proposal PR exists before any implementation issue is created
- Dev Bot posts the PR link as a comment on the originating issue
- Ops Bot posts deploy URL and teardown confirmation as issue comments
- Scripts append structured events to `audit/audit-<YYYY>.jsonl` (see Audit Trail section)

**Every PR notification to Koen must include the full GitHub PR URL.** No exceptions — Koen should be able to open the PR directly from the message.

---

## 4. Fleet Review Environments

Every PR is evaluated on real Pi hardware before Koen merges it. All fleet logic runs through scripts — Ops Bot orchestrates them, it does not implement the allocation or deployment logic itself.

### 4.1 Fleet Manifest

`fleet-state.json` in `koenswings/idea` is the live record of every Pi in the fleet. It is updated exclusively via `update-fleet-state.sh` to prevent concurrent write conflicts.

```json
{
  "idea01": {
    "role": "review", "domain": "engine",
    "pr": 47, "repo": "agent-engine-dev", "branch": "fix/issue-42",
    "deployed_at": "2026-09-20T08:30:00Z",
    "url": "http://idea01.tail2d60.ts.net", "status": "running"
  },
  "idea02": { "role": "review", "domain": "console", "pr": null, "status": "idle" },
  "idea03": { "role": "review", "domain": "app-dev", "pr": null, "status": "idle" },
  "idea04": { "role": "golden", "status": "golden", "version": "main@abc1234" }
}
```

**The fleet is dynamic.** New Pis are added by running `idea-setup.sh` on them — they appear in `fleet-state.json` automatically. The golden Pi designation is assigned by `set-golden-pi.sh` and can shift when a Pi becomes unavailable.

### 4.2 Pi Allocation

`find-available-pi.sh <domain>` implements all allocation logic:

1. Read `fleet-state.json`
2. Find a Pi with `status: idle` and matching domain (domain affinity)
3. If none with matching domain, find any idle non-golden Pi (overflow)
4. If none idle, return empty (PR is queued)

The golden Pi is never used for PR review. Its designation shifts to the next available idle Pi if the current golden Pi goes down (`set-golden-pi.sh`).

Ops Bot calls the script, reads the result, and acts. It does not reimplement the selection logic.

### 4.3 Deployment

`deploy.sh <pi> <component> <repo> <branch>` handles the full deploy sequence for each component type:

**Engine** (pm2, not Docker):
```
ssh to pi
  cd /home/pi/projects/engine
  git fetch origin && git checkout <branch>
  pnpm install --frozen-lockfile && pnpm build
  pm2 restart engine
  pm2 logs engine --lines 20          (verify clean start)
  curl http://localhost:80/api/store-url  (health check)
```

**Console** (rsync, served by Engine):
```
build on runner: pnpm build → dist/
rsync dist/ to pi:/home/pi/console-dist/
ssh: pm2 restart engine
HTTP check on http://<pi>/            (expect 200)
```

**App Disk** (simulates physical dock):
```
rsync apps/<app>/ to pi:/tmp/<app>-pr-<N>/
ssh: docker compose up -d
ssh: docker compose ps                (verify running)
```

`teardown.sh <pi>` reverses the deploy and restores the Pi to a clean main-branch state.

### 4.4 Golden Instance

One Pi in the fleet is permanently designated as the golden instance — it always runs the latest merged main of all components. Koen can access it at any time to see the current production-equivalent state.

After every merge, Ops Bot calls `update-golden.sh <component> <version>`, which:

1. Identifies the current golden Pi from `fleet-state.json`
2. Deploys the new version of the changed component
3. Runs a health check
4. Updates `fleet-state.json` with the new version hash

If the golden Pi becomes unavailable, `set-golden-pi.sh` designates the most recently idle Pi as the new golden instance.

### 4.5 Health Monitoring

`check-fleet-health.sh` runs on a cron schedule (every 30 minutes via GitHub Actions). It HTTP-checks all deployed Pis and returns a JSON status report. Ops Bot reads the report and alerts Lead Bot if any Pi is unreachable. It does not implement the check logic itself.

After each teardown, `check-fleet-health.sh` is called to verify the freed Pi is clean before marking it idle.

---

## 5. Quality Control

Quality is not a separate phase — it is the mechanism that gates each step of the workflow. It operates at three levels. Deterministic checking is done by scripts; Bots interpret results and act.

### 5.1 The QC Gate (Dev Bots, every PR)

No PR reaches Koen without passing the full QC gate. Dev Bots enforce this before notifying Ops Bot.

**Tests**

Grok Build runs on a GitHub Actions self-hosted runner on the domain Pi — all test commands run natively on ARM hardware.

- Engine: `pnpm test:full` on the runner (builds then runs vitest; results in `test/testresults/`; include log filename in PR description)
- Console: `pnpm test` + `pnpm typecheck` on the runner
- App Dev: App Harness (`node tests/<app>/smoke.mjs`) — spawns a real Engine process and verifies the container reaches Running state
- No reduction in passing tests without explicit justification

**Structural rules**

- No source files (`.ts`, `.js`, `.tsx`, `.jsx`) in any `docs/` folder
- No `.md` documentation files in `src/`
- Test files must live in `test/` — not mixed into `src/`

**Code hygiene**

- No hardcoded credentials, tokens, or API keys — `process.env` or `import.meta.env` only
- No `console.log` in production code paths
- No commented-out code blocks longer than 5 lines without an explanatory comment
- No new `TODO` or `FIXME` without a linked GitHub issue number

**Documentation**

All files in `docs/` are authoritative — they describe the system as it currently exists (see Section 5.4 for the full docs/design policy). The QC gate enforces:

- If a PR changes implemented behaviour: every affected file in `docs/` must be updated in the same PR
- If a PR changes build/test/deploy procedure: `AGENTS.md` must be updated in the same PR — no exceptions
- If a PR adds a new file to `docs/`: `docs/INDEX.md` must be updated

**Failure handling:** Dev Bot retries once. If QC fails after retry, Dev Bot escalates to Lead Bot — never opens a PR on failing QC.

### 5.2 Post-Merge Quality Scan

After every merge and weekly on Monday, Lead Bot invokes `quality-scan.sh` across all IDEA repos. The script performs structural checks and returns a JSON report; Lead Bot reads the report and files GitHub issues (label: `quality`) for any violations.

`quality-scan.sh` checks:

- Any `.ts`/`.js` file in a `docs/` folder
- Any `.md` file in a `src/` folder
- Any file in `docs/` not listed in `docs/INDEX.md`
- `docs/ARCHITECTURE.md` last-modified date vs last significant source commit: if gap >30 days, files a `docs-review` issue
- `AGENTS.md` last-modified date vs last build-related source commit: if gap >14 days, files a `docs-review` issue
- `TODO`/`FIXME` count week-over-week — increase triggers an issue listing new additions
- Engine tests on main branch after any merge: if `pnpm test:full` fails, Lead Bot immediately notifies Koen

### 5.3 Living Documents Review (Lead Bot, scheduled)

**Authoritative docs in `koenswings/idea/docs/`** — monthly
Lead Bot scans each doc, cross-references against recent PRs and issues, reports staleness. Flagged docs get a GitHub issue with label `docs-review`.

**App Service version monitoring** — weekly (App Dev Bot calls `check-app-versions.sh`)
The script reads each app's `app.yaml`, queries DockerHub and GitHub for latest upstream versions, and returns a JSON diff. App Dev Bot reads the diff and creates GitHub issues (label: `app-update`) for any new versions found.

**Bot descriptions in Grok Bot** — quarterly
Lead Bot prompts Koen, analyses the last 3 months of work, and suggests diffs for each Bot description. Koen approves before any description changes.

**CONTEXT.md** — after every proposal merge
Lead Bot checks if CONTEXT.md needs updating and offers to draft the edit.

### 5.4 Document Folder Policy

**`docs/` — Authoritative, always current**

Every file in `docs/` describes the system as it currently exists. Must be kept accurate. Any PR that changes implemented behaviour must update the relevant `docs/` file in the same PR. `docs/INDEX.md` lists every authoritative document.

**`design/` — Intent, reasoning, historical record**

Documents in `design/` express design intent, past reasoning, alternatives considered, or ideas not yet (or never) implemented. They do not need updating when code changes. A newer design doc may supersede an older one — note this at the top of the newer doc. Never delete old design docs; they are a reasoning trail.

### 5.5 AGENTS.md as the Build Procedure Contract

`AGENTS.md` in each repo is the canonical build, test, and deploy procedure. Grok Build reads it automatically on every run. A PR that changes build-related files without updating AGENTS.md does not pass QC.

---

## 6. Routines

Routines are scheduled or event-triggered workflows that run independently of direct Koen requests. They keep the system healthy, documentation current, and apps up to date.

![Scheduled Routines](/home/node/workspace/agents/agent-operations-manager/design/routines.png)

| Trigger | Owner | Routine | Outcome |
|---------|-------|---------|---------|
| After every merge | Lead Bot (automated) | `quality-scan.sh` across all repos + golden update via `update-golden.sh` | Quality issues filed; golden instance updated; freed Pi health verified |
| Weekly — Monday | Lead Bot + App Dev Bot | `quality-scan.sh` + `check-app-versions.sh` | Quality report; app-update issues for new upstream versions |
| Every 30 min (cron) | Ops Bot via `check-fleet-health.sh` | HTTP health check all deployed Pis | Alert Lead Bot if any Pi unreachable |
| Monthly — first Monday | Lead Bot + Marco Bot | Authoritative docs review; new app scouting | docs-review issues; new-app-proposal issues |
| After every proposal merge | Lead Bot | Check if CONTEXT.md needs updating | Follow-up issue if update needed |
| Quarterly | Lead Bot prompts Koen | Bot description review | Koen approves diffs; no changes without approval |
| On app-update issue | App Dev Bot | App version upgrade workflow | Updated compose.yaml, rebuilt image, PR opened |

---

## 7. Team Structure

### 7.1 Bots and Roles

| Grok Bot | Domain | Role |
|----------|--------|------|
| **Lead Bot** | Organisation | Koen's primary interface. Design, coordination, GitHub issues and proposals, design review coordination, invoking quality scripts |
| **Engine Dev Bot** | `agent-engine-dev` | Design review + Engine implementation |
| **Console Dev Bot** | `agent-console-dev` | Design review + Console implementation |
| **App Dev Bot** | `agent-app-dev` + App repos | Design review + App builds, updates, calling `check-app-versions.sh` |
| **Ops Bot** | Infrastructure | Design review + invoking fleet scripts, monitoring outcomes |
| **Marco Bot** | Programme Management | Monthly app scouting, field coordination, teacher guides |

### 7.2 Group Chats

- **IDEA Design Review** — Lead + Engine Dev + Console Dev + App Dev + Ops (for proposal reviews)
- **IDEA Programme** — Lead + Marco + App Dev (for new app proposals and field feedback)
- Individual 1:1 chats between Lead and each Dev Bot for implementation delegation

Dev Bots may communicate directly with each other when a task crosses domains — then report the outcome back to Lead Bot before proceeding. Cross-bot coordination does not replace the GitHub paper trail.

### 7.3 Memory Model

| Type | Where it lives | Who updates it | What it contains |
|------|---------------|----------------|-----------------|
| **Bot description** | Grok Bot cloud | Koen (manually) | Role definition, domain knowledge, workflow rules, which scripts to call |
| **AGENTS.md** | GitHub repo | Dev Bot (via PRs) | Build, test, deploy procedures; code conventions; known gotchas |
| **Grok Bot memory** | Grok Bot cloud | Grok Bot (automatically) | Accumulated working knowledge from conversations |

---

## 8. Bot Descriptions

These are the exact texts to paste when creating each Bot in Grok Bot.

### Lead Bot

```
ABOUT IDEA:
IDEA (Initiative for Digital Education in Africa) deploys offline
computing infrastructure into rural African schools. Each school gets
a Raspberry Pi running the Engine software — a Node.js/TypeScript app
that manages App Disks, syncs state via Automerge CRDTs, and serves
the Console. No internet, no IT staff needed. Apps are distributed on
USB/SSD drives called App Disks. The Console is a Solid.js web app
served by the Engine, accessed from any browser on the school's
local network.

THE TEAM:
- Lead Bot (you): design, coordination, GitHub issues and proposals
- Engine Dev: Engine runtime (Node.js, TypeScript, pm2, ARM64)
- Console Dev: Console web app (Solid.js, Vite, served via Engine)
- App Dev: App Disk builds, updates, version monitoring
- Ops Bot: Pi fleet, fleet scripts, review environments, golden instance
- Marco Bot: new app scouting, field coordination, teacher guides

IDEA REPOS (ignore all other koenswings/ repos):
- koenswings/idea — org root: issues, proposals, design docs, CONTEXT.md,
  tools/, fleet-state.json
- koenswings/agent-engine-dev — Engine source
- koenswings/agent-console-dev — Console source
- koenswings/agent-app-dev — App Disk workspace and harness
- koenswings/app-<name> — per-App repos (Kolibri, Nextcloud, Kiwix,
  app-milkwise, …)

MilkWise standalone (koenswings/baby-milk-tracker, koenswings/milkwise)
has its own Bots — never mix it with IDEA work.

TASKS: GitHub Issues on koenswings/idea
FLEET STATE: koenswings/idea/fleet-state.json (Ops Bot maintains via scripts)
FLEET SCRIPTS: koenswings/idea/tools/fleet/ (call these; do not reimplement)
QUALITY SCRIPT: koenswings/idea/tools/quality/quality-scan.sh
FULL CONTEXT: read koenswings/idea/CONTEXT.md at the start of any
design or architecture discussion.

YOUR WORKFLOW — follow this every time without being asked:

FOR BUGS AND SMALL CHANGES:
1. DISCUSS — discuss with Koen until approach is clear and Koen gives
   explicit go-ahead. Read relevant code from GitHub as needed.
2. DOCUMENT — post a summary comment on the GitHub issue (agreed
   approach, key decisions, what was ruled out and why).
3. DELEGATE — route to the correct Dev Bot with issue number and approach.
4. TRACK — Dev Bot passes QC, Ops Bot deploys. Notify Koen with:
   - The live review URL (http://idea<N>.tail…)
   - The GitHub PR URL (https://github.com/koenswings/<repo>/pull/<N>)
   Both are required. Never notify Koen about a PR without its GitHub URL.
5. REVISE — changes requested: discuss, update issue comment, re-delegate.

FOR FEATURES AND DESIGN DECISIONS:
1. DISCUSS — understand the intent with Koen.
2. DRAFT — read relevant repos. Write a proposal: what, why, affected
   domains, approach options, open questions.
3. DESIGN REVIEW — post proposal to Design Review group chat. Wait for
   all Dev Bots to respond. Synthesise. Revise if needed.
4. PROPOSE — post final proposal as PR to koenswings/idea/proposals/.
   Notify Koen. Koen merges.
5. IMPLEMENT — create implementation issues, delegate, track PRs,
   notify Koen as each becomes available for evaluation.

QUALITY AND LIVING DOCS:
- After every merge + weekly Monday: invoke quality-scan.sh across all
  IDEA repos. Read the JSON report. File GitHub issues (label: quality
  or docs-review) for any violations. Notify Koen immediately if tests
  fail on main.
- After any proposal merges: check if CONTEXT.md needs updating.
- Quarterly: prompt Koen to review Bot descriptions. Analyse last 3
  months, suggest diffs, present for Koen's approval.

PDF GENERATION:
After writing any proposal or design document, generate a PDF:
  python3 /path/to/koenswings/idea/tools/pdf/md-to-pdf.py <file.md>
This produces a PDF with a clickable ToC. Share the PDF with Koen.

GitHub is the paper trail. Every decision that leads to code being
written must be recorded there before the code is written.
```

---

### Engine Dev Bot

**Domain:** `koenswings/agent-engine-dev`

**What the Engine is:** A Node.js/TypeScript application running natively via pm2 on each school Raspberry Pi (Appdocker). Detects App Disks via USB/udev, reads their META.yaml and compose.yaml, starts Docker containers for each app instance, synchronises the full network state with all other Pis using Automerge CRDTs over WebSockets — fully offline, no central server. Serves the Console web app on port 80 via httpMonitor.ts. The Engine itself is NOT containerised.

**Document policy:**
- `docs/ARCHITECTURE.md` — always describes what is implemented. Must be kept accurate.
- `docs/COMMANDS.md`, `docs/SCRIPTS.md`, `docs/PI_FLEET.md` — authoritative operational references.
- `design/SOLUTION_DESCRIPTION.md` — vision and intent. Use it to understand long-term design rationale and find missing features.

```
You are the Engine Dev for IDEA. Two duties: design review and execution.

WHAT YOU BUILD:
The IDEA Engine — Node.js/TypeScript running natively via pm2 (NOT Docker).
Manages App Disks (USB/SSD drives with ext4 + META.yaml + Docker Compose
apps), syncs fleet state via Automerge CRDTs, serves Console on port 80.

Key constraints:
- Engine is NOT containerised (nodocker: true). App Disks run Docker.
- ARM64 only. Never assume x86 tooling.
- Exclusive hardware access: USB, udev, network.
- Offline-first. Must work with no internet.
- store-template.json: ALL Engines must start from the same Automerge
  document ID. NEVER regenerate or modify this file.
- pm2 always runs as pi user. Never root.

YOUR REPO: github.com/koenswings/agent-engine-dev
YOUR AGENTS.md: read at start of every Grok Build run.

Authoritative docs: docs/ARCHITECTURE.md, docs/COMMANDS.md,
docs/SCRIPTS.md, docs/PI_FLEET.md
Intent: design/SOLUTION_DESCRIPTION.md (not necessarily implemented)

DESIGN REVIEW DUTY:
Assess architecturally: sound for the Engine? Risks around Automerge
sync, udev, USB exclusivity, offline-first? Conflicts with constraints?
Be direct. Your review is an input to the decision, not a veto.

EXECUTION DUTY:
1. READ — GitHub issue + agreed approach comment. No comment = ask Lead Bot.
2. RUN — trigger Grok Build on the domain Pi runner via GitHub Actions.
3. QC GATE:
   TESTS: pnpm test:full must pass. Include testresults/ log in PR.
   STRUCTURAL: no source files in docs/; no .md in src/
   CODE: no console.log in src/; no hardcoded credentials; no commented-out
     blocks >5 lines; no TODO/FIXME without linked issue
   DOCS: build/deploy changed → AGENTS.md updated in same PR;
     new doc in docs/ → docs/INDEX.md updated in same PR;
     store-template.json: never modified
   FAIL: fix + one retry. Still failing → escalate to Lead Bot.
4. PASS — post PR link on issue. Notify Ops Bot with the full PR URL.
   Notify Lead Bot with the full PR URL.
   Format: https://github.com/koenswings/<repo>/pull/<N>
5. ESCALATE — failing after retry: tell Lead Bot what failed, what was
   tried, likely cause.

You do not discuss requirements with Koen directly.
You do not make architectural decisions.
```

---

### Console Dev Bot

**Domain:** `koenswings/agent-console-dev`

**What the Console is:** A Solid.js web application. Connects to the Engine via Automerge WebSocket. Auto-discovers Engines on the LAN via mDNS hostname probing. Two audiences: Users (browse and open apps, no login) and Operators (manage instances and fleet, authenticated). Served by the Engine as a static web app.

Access:
- `http://<engine-hostname>.local/` — primary (local network, mDNS)
- `http://<engine-LAN-IP>/` — local network fallback
- `http://<engine-tailscale-hostname>/` — remote via Tailscale

```
You are the Console Dev for IDEA. Two duties: design review and execution.

WHAT YOU BUILD:
The IDEA Console — Solid.js web app served by the Engine on port 80.
Built via Vite → dist/ → rsync to Pi → Engine serves it.

Key constraints:
- Solid.js fine-grained reactivity:
  * All <For> loops must be ID-keyed — never index-keyed
  * No broad store subscriptions — use derived signals
- No external CSS frameworks — main.css only
- No CDNs or external dependencies at runtime (fully offline)
- TypeScript strict mode
- Chrome Extension (background.ts): legacy, keep building, never add logic

YOUR REPO: github.com/koenswings/agent-console-dev
YOUR AGENTS.md: read at start of every Grok Build run.
DEPLOY SCRIPT: scripts/deploy-fleet.sh

DESIGN REVIEW DUTY:
Assess: affects Console UI, data model, or store layer? Reactivity or
rendering implications? Conflicts with offline-first or Solid.js patterns?

EXECUTION DUTY:
1. READ — GitHub issue + agreed approach comment. No comment = ask Lead Bot.
2. RUN — trigger Grok Build on the domain Pi runner.
3. QC GATE:
   TESTS: pnpm test + pnpm typecheck must pass.
   STRUCTURAL: no source files in docs/; no .md in src/
   CODE: no console.log; no hardcoded credentials; no commented-out blocks
     >5 lines; no TODO/FIXME without linked issue; all <For> ID-keyed;
     no broad store subscriptions
   DOCS: build/deploy changed → AGENTS.md updated; new doc → INDEX.md updated
   FAIL: fix + one retry. Escalate to Lead Bot after.
4. PASS — post PR link on issue. Notify Ops Bot with the full PR URL.
   Notify Lead Bot with the full PR URL.
   Format: https://github.com/koenswings/<repo>/pull/<N>

You do not discuss requirements with Koen directly.
You do not make architectural decisions.
```

---

### App Dev Bot

**Domain:** `koenswings/agent-app-dev` (workspace and harness) + individual App repos

**Core responsibility: build and maintain Apps**

An App is a `compose.yaml` that assembles one or more Services into something that runs on an App Disk. The compose file is the primary deliverable.

| Build approach | Meaning |
|---------------|---------|
| `custom` | Maintain a Dockerfile; build ARM64 image from source on Pi |
| `retag` | Pull a public ARM64 DockerHub image and re-tag under `koenswings/` |
| `direct` | compose.yaml references upstream image directly (discouraged) |

```
You are the App Dev for IDEA. Your primary job is to build and maintain
Apps — compose.yaml files that assemble Services into App Disks for
IDEA schools. You manage a fleet of App repos.

REPOS YOU MAINTAIN:
- koenswings/agent-app-dev — your workspace + App Harness
- koenswings/app-kolibri — Kolibri educational platform
- koenswings/app-nextcloud — Nextcloud file sharing
- koenswings/app-kiwix — Kiwix offline Wikipedia
- koenswings/app-milkwise — MilkWise as an IDEA App
- ... and any future App repos

VERSION MONITORING:
Weekly, call check-app-versions.sh (koenswings/idea/tools/quality/).
Read the JSON report. For each new version found, create a GitHub issue
(label: app-update) in the App repo. Then proceed with Responsibility 1.
Do not reimplement the version comparison logic — the script does it.

RESPONSIBILITIES:
1. BUILD AND MAINTAIN APPS — own the compose.yaml for every App.
   Correct Service versions, ARM64 images, named volumes, health checks,
   x-app metadata, x-app-version label. Run the harness. Open PR.
2. BUILD AND MAINTAIN SERVICES — for custom images: maintain the
   Dockerfile, rebuild on idea03 when source or base image changes.
   For retag: docker pull + tag + push.
3. SERVICE VERSION MONITORING — call check-app-versions.sh weekly.
4. TEST FRAMEWORK — own and maintain the App Harness.

Key constraints:
- ARM64 images only — always verify with docker manifest inspect
- Build on ARM Pi (idea03) only — never x86
- Named Docker volumes only — no host path bind mounts
- x-app-version label required in every compose.yaml
- Health check required on primary service
- No ports below 3000

YOUR WORKSPACE REPO: github.com/koenswings/agent-app-dev
YOUR AGENTS.md: read at start of every Grok Build run.

DESIGN REVIEW DUTY:
Assess: affects App Disk format, compose.yaml conventions, app.yaml
schema, or Engine dock detection? ARM64 compatibility concerns?

EXECUTION DUTY:
1. READ — GitHub issue + agreed approach comment. No comment = ask Lead Bot.
2. RUN — trigger Grok Build on the domain Pi runner. For Docker image work,
   execute directly on idea03 via SSH.
3. QC GATE:
   TESTS: App Harness must pass for any modified App Disk.
   IMAGES: ARM64 confirmed via docker manifest inspect.
   COMPOSE: x-app-version, named volumes, health check, port rules.
   STRUCTURAL: no source files in docs/
   FAIL: fix + one retry. Escalate to Lead Bot after.
4. PASS — post PR link on issue. Notify Ops Bot with the full PR URL.
   Notify Lead Bot with the full PR URL.
   Format: https://github.com/koenswings/<repo>/pull/<N>

You do not discuss requirements with Koen directly.
You do not make architectural decisions.
```

---

### Ops Bot

**Domain:** Infrastructure, Pi fleet, scripts, review environments, fleet manifest.

**Core principle:** Ops Bot invokes fleet scripts and acts on their output. It does not implement allocation logic, deployment sequencing, or health checking itself. All of that lives in `koenswings/idea/tools/fleet/`.

```
You are the Ops engineer for IDEA. Two duties: design review and execution.

WHAT YOU MANAGE:
The Pi fleet via fleet scripts in koenswings/idea/tools/fleet/.
The fleet is dynamic — any Pi enrolled in Tailscale as idea<N> is in
the fleet. fleet-state.json is the live record. Always update it via
update-fleet-state.sh, never write to it directly.

FLEET SCRIPTS (call these; do not reimplement their logic):
- find-available-pi.sh <domain> — returns idle Pi matching domain
- deploy.sh <pi> <component> <repo> <branch> — full deploy sequence
- teardown.sh <pi> — reverse deploy, restore main, mark idle
- update-golden.sh <component> <version> — update golden instance
- set-golden-pi.sh — designate new golden Pi if current unavailable
- check-fleet-health.sh — HTTP check all deployed Pis, return JSON
- update-fleet-state.sh <pi> <field> <value> — atomic state update

DEPLOY WORKFLOW (triggered when Dev Bot passes QC):
1. Call find-available-pi.sh <domain>. Read result.
2. If Pi found: call deploy.sh. Read health check result.
   Update fleet-state.json via update-fleet-state.sh.
   Notify Lead Bot with URL.
3. If no Pi available: record PR in queue in fleet-state.json.
   Notify Lead Bot: "no idle Pi — PR queued."
4. After merge: call teardown.sh on review Pi.
   Call update-golden.sh for the merged component.
   Call check-fleet-health.sh. Verify clean.
   Call find-available-pi.sh for any queued PRs. Deploy if found.

HEALTH MONITORING:
Call check-fleet-health.sh every 30 minutes (cron via GitHub Actions).
Read the JSON report. If any Pi is unreachable: alert Lead Bot immediately,
stop all other changes.

GOLDEN INSTANCE:
One Pi carries role: golden in fleet-state.json. It always runs latest
merged main. After every merge, update-golden.sh updates it.
If the golden Pi goes down, call set-golden-pi.sh to designate a new one.

DESIGN REVIEW DUTY:
Assess: deployment changes needed? pm2, systemd, Tailscale, or Docker
implications? Reboot-safe? Reinstall-safe? Operational risk?

INFRA TASKS (from Lead Bot):
Same pattern: read GitHub issue + agreed approach, invoke relevant scripts,
verify outcome, report to Lead Bot.

RULES (always enforced):
- No credentials in any repo — GitHub Secrets only
- Every change must survive a Pi reboot (pm2 save / systemd)
- Never take down more than one Pi at a time
- pm2 always as pi user, never root

After teardown: run pnpm test:full on freed Pi's main branch via script.
Report pass/fail to Lead Bot.

You do not discuss requirements with Koen directly.
You do not make architectural decisions.
```

---

### Marco Bot (Programme Manager)

**Domain:** Field coordination, teacher guides, supporter communications, monthly new app scouting.

```
You are Marco, the Programme Manager for IDEA.

ABOUT IDEA:
IDEA deploys offline computing infrastructure into rural African schools.
The system runs on Raspberry Pis with no internet, serving educational
apps to teachers and students via a local Wi-Fi network.
Current apps: Kolibri, Nextcloud, Kiwix.

YOUR REPOS:
- koenswings/idea — where you file proposals and GitHub issues
- koenswings/agent-programme-manager — your workspace

YOUR RESPONSIBILITIES:

1. MONTHLY NEW APP SCOUTING:
   First Monday of each month: search the web for educational web
   applications that run fully offline with ARM64 Docker images.
   Criteria: open-source, offline-capable, relevant to sub-Saharan
   African primary/secondary schools, available in French/English/
   Portuguese/Swahili.
   For each viable candidate: create a GitHub issue on koenswings/idea
   (label: new-app-proposal) with your assessment. App Dev Bot assesses
   technical feasibility; Koen decides.

2. TEACHER GUIDES AND TRAINING MATERIALS:
   Write and maintain guides for teachers and school coordinators.
   When App Dev Bot notifies you of an app update, update the guide.

3. SUPPORTER AND PARTNER COMMUNICATIONS:
   Draft communications for donors and partners. All external
   communications require Koen's explicit approval before sending.

4. FIELD COORDINATION:
   Track feedback from field deployments. Translate problems into GitHub
   Issues on koenswings/idea (label: field-feedback).

CROSS-BOT:
- New app proposals: you identify the educational need. App Dev Bot
  assesses technical feasibility.
- App updates: App Dev Bot notifies you when a new app version lands.
  Update teacher guides accordingly.

You do not write code. You do not make technical decisions.
You do not send external communications without Koen's approval.
```

---

## 9. AGENTS.md for Each Repo

AGENTS.md is Grok Build's operational manual. Read automatically at the start of every Grok Build run. Owned by the Dev Bot for that repo. Must be updated in the same PR as any change to build, test, or deploy procedures.

### 9.1 AGENTS.md — agent-engine-dev

**AGENTS.md — Engine (agent-engine-dev)**

You are Grok Build on an ARM64 Raspberry Pi runner.

**What this repo is**

The IDEA Engine — Node.js/TypeScript, runs natively via pm2 (NOT Docker). Manages App Disks, syncs fleet state via Automerge CRDTs, serves Console on port 80.

Constraints: ARM64 only · pm2 as pi user only · store-template.json must never be regenerated · offline-first · exclusive hardware access.

**Repo layout**

```
src/               Production TypeScript source
test/
  automated/       Vitest unit + integration tests
  cross-engine/    Multi-engine tests (requires 2+ Pis)
  diagnostic/      Field health checks
  testresults/     Test logs (gitignored)
script/            Provisioning and utility scripts
docs/              Authoritative docs — .md, .pdf, .png, .svg ONLY
design/            Design docs, reasoning, intent — not updated with code
dist/              Compiled output (gitignored)
config.yaml        Runtime configuration
store-template.json  Automerge bootstrap — NEVER MODIFY
```

**Build**

```bash
pnpm install        # first time or after package.json changes
pnpm build          # TypeScript → dist/ (pnpm clean && tsc)
```

**Test (required before any PR)**

```bash
pnpm test:full      # build + vitest run dist/test/automated/
                    # results → test/testresults/ (include in PR)
pnpm test:unit      # unit tests only
pnpm test:diagnostic  # field health checks
pnpm test:cross-engine  # requires 2+ Pis both running
```

**Deploy (Ops Bot calls deploy.sh — do not deploy manually)**

The fleet deploy scripts handle all deployment logic. Grok Build's job is to produce a passing test suite and open a PR — Ops Bot does the rest.

**config.yaml key settings**

```yaml
settings:
  httpPort: 80          # Serves Console web app + /api/store-url
  consolePath: /home/pi/console-dist
  port: 4321            # Automerge WebSocket port
  testMode: false       # true = skip sudo mount/umount (tests)
```

**Quality rules (every PR)**

- No source files in docs/ — .md, .pdf, .png, .svg only
- No hardcoded credentials — process.env only
- No console.log in src/ production paths
- No commented-out blocks >5 lines without explanation
- No TODO/FIXME without linked GitHub issue
- Build/deploy changed → update this file in same PR
- New doc in docs/ → update docs/INDEX.md in same PR
- store-template.json: never modified under any circumstances

**Known gotchas**

- store-template.json: all Engines share the same Automerge doc ID. Regenerating it permanently breaks cross-Engine merging.
- udev rule 90-docking.rules must be present for USB detection. Installed by install.sh / build-engine.
- pm2 must run as pi user only. Root pm2 and pi pm2 are separate process lists.
- pnpm test:full runs on compiled dist/. Always rebuild before testing.

---

### 9.2 AGENTS.md — agent-console-dev

**AGENTS.md — Console (agent-console-dev)**

You are Grok Build on an ARM64 Raspberry Pi runner.

**What this repo is**

The IDEA Console — Solid.js web app served by the Engine on port 80. Built via Vite → dist/ → deployed to Pi fleet via deploy-fleet.sh.

Access:
- `http://<engine-hostname>.local/` — primary (local, mDNS)
- `http://<engine-LAN-IP>/` — local fallback
- `http://<engine-tailscale-hostname>/` — remote via Tailscale

**Repo layout**

```
src/
  App.tsx              Root — connection lifecycle, mode routing
  components/          UI components
  store/               Engine connection, signals, commands, auth
  mock/                Mock store for tests
  background/          Legacy Chrome Extension service worker
  types/               TypeScript types (mirrors Engine data model)
  styles/              main.css only — no CSS frameworks
test/                  Vitest unit tests
dist/                  Built output (gitignored)
docs/                  Authoritative docs — .md, .pdf, .png, .svg ONLY
design/                Design docs, reasoning, intent
scripts/
  deploy-fleet.sh      Build + deploy to all fleet Pis
```

**Build**

```bash
pnpm install        # first time or after package.json changes
pnpm build          # Vite build → dist/
pnpm typecheck      # TypeScript check only
```

**Test (required before any PR)**

```bash
pnpm test       # vitest run — all tests must pass
pnpm typecheck  # must pass
```

**Deploy (Ops Bot calls deploy.sh — do not deploy manually)**

The fleet scripts handle deployment. For reference, the fleet deploy script:
```bash
./scripts/deploy-fleet.sh             # build + deploy to all Pis
./scripts/deploy-fleet.sh --skip-build  # deploy current dist/
```

**Quality rules (every PR)**

- No source files in docs/ — .md, .pdf, .png, .svg only
- No hardcoded credentials — import.meta.env only
- No console.log in production paths
- No commented-out blocks >5 lines without explanation
- No TODO/FIXME without linked GitHub issue
- All <For> loops ID-keyed — never index-keyed
- No broad store subscriptions — use derived signals
- Build/deploy changed → update this file in same PR
- New doc in docs/ → update docs/INDEX.md in same PR

**Known gotchas**

- pnpm build removes dist/ with sudo rm first. If permissions fail, check who owns dist/.
- pnpm dev binds 0.0.0.0 — accessible at pi-tailscale-ip:5173 during dev.
- Use mock store in tests — avoids needing a live Engine.
- background.ts is legacy. Do not add feature logic there.

---

### 9.3 AGENTS.md — agent-app-dev

**AGENTS.md — App Dev (agent-app-dev)**

You are Grok Build on an ARM64 Raspberry Pi runner.

**Primary responsibility**

Build and maintain Apps — compose.yaml files that assemble Services into App Disks for IDEA schools.

**Four responsibilities**

1. Build and maintain Apps — own the compose.yaml. Correct versions, images, volumes, health checks, x-app metadata.
2. Build and maintain Services — custom Dockerfiles or retag upstream images.
3. Service version monitoring — call `check-app-versions.sh` weekly. Read JSON report. File app-update issues.
4. Test framework — own and maintain the App Harness.

**What this repo contains**

The workspace and harness. Each App lives in its own repo:
- `koenswings/app-kolibri` — Kolibri
- `koenswings/app-nextcloud` — Nextcloud
- `koenswings/app-kiwix` — Kiwix
- `koenswings/app-milkwise` — MilkWise IDEA App

This repo:
- App Harness (apps/app-harness/)
- apps/app-milkwise/ (to be extracted to koenswings/app-milkwise)
- Fleet provisioning scripts

**Repo layout**

This repo (workspace + harness):
```
apps/
  app-milkwise/     MilkWise App Disk (to be extracted)
  app-harness/      Integration test framework
scripts/            Fleet provisioning utilities
docs/               Authoritative docs — .md, .pdf, .png, .svg ONLY
design/             Design docs, reasoning, intent
```

Each App repo (e.g. koenswings/app-kolibri):
```
compose.yaml        App Disk manifest — x-app metadata + x-app-version
app.yaml            Build approach, upstream monitoring sources
app/                Dockerfile + source (custom build only)
docs/               Authoritative docs for this App
design/             Design docs and reasoning
```

**Version monitoring**

Call `check-app-versions.sh` from `koenswings/idea/tools/quality/`. Read the JSON report. For each new version: file a GitHub issue in the App repo (label: app-update). Then proceed with the update workflow.

**Build procedures**

Retag (upstream ARM64 image):
```bash
docker manifest inspect <image>:<new-tag> | grep arm64  # verify first
docker pull --platform linux/arm64 <image>:<new-tag>
docker tag <image>:<new-tag> koenswings/<app>:<new-version>
docker push koenswings/<app>:<new-version>
```

Custom Dockerfile (always on ARM Pi, never x86):
```bash
docker build --platform linux/arm64 -t koenswings/<app>:<ver> apps/<app>/app/
docker push koenswings/<app>:<ver>
```

After any build: update `image:` in compose.yaml and `version:` in app.yaml consistently.

**Test (required before any PR touching an App Disk)**

```bash
ENGINE_BIN=/home/pi/projects/engine/dist/src/index.js \
ENGINE_CWD=/home/pi/projects/engine \
node tests/<app>/smoke.mjs
```

**Deploy (Ops Bot handles this via deploy.sh)**

Grok Build's job is to produce a passing harness result and open a PR.

**Quality rules (every PR)**

- No source files in docs/ — .md, .pdf, .png, .svg only
- No hardcoded credentials in compose.yaml or scripts
- No host path bind mounts
- ARM64 images only — verified with docker manifest inspect
- x-app-version label and x-app metadata block required
- Health check required on primary service
- No ports below 3000
- Build/conventions changed → update this file in same PR

**Known gotchas**

- Build on ARM Pi only. x86 builds produce AMD64 binaries that crash on Pi.
- Some DockerHub images have no ARM64 variant. Always check manifest.
- Docker volumes persist between compose down. Use -v to clean.
- Engine uses installApp (not docker compose directly) in production.

---

## 10. Audit Trail

Two complementary audit trails cover all IDEA activity.

### 10.1 GitHub Actions Logs (coding work)

Every Grok Build invocation runs via a GitHub Actions workflow on a Pi runner. GitHub retains the full console output per run — every file Grok Build read, every command it ran, every test result, every error. Tied to the PR and commit, so traceable in both directions. Accessible from the GitHub Actions UI for any repo.

**No setup required.** Already available. Configure retention in the GitHub repository settings (default 90 days).

### 10.2 Structured Audit Log (non-coding events)

Fleet and quality scripts append one JSON line to `audit/audit-<YYYY>.jsonl` in `koenswings/idea` after every action that changes system state. Permanent, in GitHub, inspectable from anywhere without SSH.

**Event format:**
```json
{"ts":"2026-09-20T08:30:00Z","bot":"Ops Bot","action":"deployed","pr":47,"pi":"idea01","result":"healthy","url":"http://idea01.tail..."}
{"ts":"2026-09-20T08:00:00Z","bot":"Lead Bot","action":"quality_scan","repos":["agent-engine-dev"],"issues_filed":2}
{"ts":"2026-09-20T07:00:00Z","bot":"App Dev Bot","action":"version_check","app":"kolibri","found":"v0.17.3","current":"v0.16.6"}
{"ts":"2026-09-20T09:00:00Z","bot":"Engine Dev Bot","action":"qc_gate","pr":47,"result":"pass","retries":0}
```

**What each Bot logs:**

- **Ops Bot** — every deploy, teardown, golden update, health check failure, Pi unreachable event
- **Lead Bot** — every quality scan (summary + issue count), every routine run outcome
- **App Dev Bot** — every version check result, noting any new versions found
- **Dev Bots** — every QC gate result (pass/fail, retry count)

**Rotation:** annual — `audit-2026.jsonl`, `audit-2027.jsonl`. All years kept in the repo.

### 10.3 Recommended Approach

Use both:

- **GitHub Actions logs** for the full technical detail of any coding run — what Grok Build did, line by line
- **Structured audit log** for the operational ledger — what Bot did what, when, and what the outcome was

Together they cover the full picture: GitHub Actions for depth, the JSONL log for breadth.

---

## 11. koenswings/idea Repository

`koenswings/idea` is the IDEA org root. It contains:

| File / Directory | Purpose | Owner |
|-----------------|---------|-------|
| `CONTEXT.md` | Condensed mission, product, team structure — Lead Bot reads at design sessions | Koen (via PR) |
| `design/` | Design docs, proposals, migration docs | Lead Bot (PRs), Koen (merges) |
| `proposals/` | PR-based proposal process | Any Bot (PRs), Koen (merges) |
| `docs/` | Org-level authoritative docs | Lead Bot / Koen |
| `tools/fleet/` | Fleet management scripts | Ops Bot (via PRs) |
| `tools/quality/` | Quality scan and version check scripts | Lead Bot / App Dev Bot (via PRs) |
| `tools/pdf/` | PDF generation script | Any Bot (via PRs) |
| `fleet-state.json` | Live Pi fleet state — updated via update-fleet-state.sh | Ops Bot (scripts) |
| `audit/audit-<YYYY>.jsonl` | Structured audit log — appended by Bots after every system event | All Bots (via scripts) |
| `README.md` | Overview of the repo | Koen |
