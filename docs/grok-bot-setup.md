# IDEA Platform: Grok Bot Setup

**Author:** Atlas (updated Lead / Steve for idea#147)
**Date:** 2026-09-20; workflow update 2026-09-28
**Status:** Authoritative — describes the current setup
**Related:** idea#147 — Dev Bot + SSH official; Grok Build runner path parked

---

## Contents

| # | Section |
|:---:|---|
| **1** | Overview |
| **2** | Platform — Subscription · Coding tools (Dev Bot live / Grok Build parked) · Pi Fleet · Filesystem layout · Fleet Scripts · GitHub |
| **3** | Development Workflow — Bug fix path · Feature path · Paper trail |
| **4** | Fleet Review Environments — Scripts · Manifest · Deploy · Golden instance · Health · Test claim protocol |
| **5** | Quality Control — QC gate · Post-merge scan · Living docs · Doc policy · AGENTS.md contract |
| **6** | Routines — All scheduled and event-triggered workflows |
| **7** | Team Structure — Roles · Group chats · Memory model |
| **8** | Bot Descriptions — Lead · Engine Dev · Console Dev · App Dev · Ops · Marco |
| **9** | AGENTS.md for Each Repo — Engine · Console · App Dev (templates PARKED) |
| **10** | Audit Trail — GitHub Actions logs · Structured event log · Recommended approach |
| **11** | koenswings/idea Repository |

---

## 1. Overview

This document describes the IDEA development setup on Grok Bot — the platform, tools, workflows, quality standards, team structure, and Bot configurations.

Development conversations happen in Grok Bot chat. Code lives on GitHub. **Dev Bots implement** with their own tools; they run tests over SSH on fleet Pis and open PRs. **Ops** deploys review environments via fleet scripts. Koen evaluates every PR on real Pi hardware before squash-merging. Quality is enforced at every step — in Bot descriptions, in each repo's AGENTS.md, and by fleet / quality scripts.

The Grok Build + GitHub Actions self-hosted runner coding path is **parked** (see §2.2). Pis are test / review / golden hardware, not coding agents, until that path is deliberately revived.

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
| Grok Build (coding on Pis) | **PARKED** — pay-per-use if revived | Optional install on idea02 for health check; not the live coding path |
| Cursor Cloud Agents | Not used | IDEA builds ARM — x86 VMs cannot build or test it |

### 2.2 Coding tools

#### Live path — Dev Bots

**Dev Bots** (Engine Dev / Console Dev / App Dev) implement code with their own tools: clone the repo, edit, commit, and open PRs via GitHub. They run domain tests over **SSH on a fleet Pi** (typically `idea03`, or any idle non-golden). They read the repo's `AGENTS.md` for build / test / deploy conventions. Continuity of domain expertise across tasks is intentional — that is why Dev Bots remain the implementers rather than fresh one-shot coding agents.

#### Parked path — Grok Build + Pi runners (idea#147)

**PARKED (2026-09-28).** Do not use for new work unless Koen deliberately revives this path.

Historically the design was: all coding on the Pi fleet via **Grok Build** (xAI's open-source terminal coding agent on ARM64), triggered headless on a GitHub Actions self-hosted runner. That path is not the live workflow. Grok Build and/or a self-hosted runner **may remain installed on `idea02`** for health-check purposes only. Pis are **not** coding agents while this path is parked.

**State on idea02 (idea#147):** after this change merges, Atlas stops the self-hosted runner service on idea02 and sets `runner: parked` in `fleet-state.json`. The Grok Build binary (1.0.40, default model `grok-4.6`) stays installed. The only workflow in `koenswings/idea` is the manual `runner-test.yml` (`workflow_dispatch`); it will fail while the runner service is stopped, which is expected.

Preserved reference (for revival only):

- Reads `AGENTS.md` natively; Plan Mode; headless `grok -p "task"`; OpenRouter model routing
- Install (parked): `curl -fsSL https://x.ai/cli/install.sh | bash` then `grok auth login`

### 2.3 Pi Fleet

The IDEA fleet is a variable number of Raspberry Pis — any Pi enrolled in Tailscale with a hostname matching `idea*` is automatically discovered and available for work. There is no hardcoded Pi count.

Each Pi runs:

- Tailscale (hostname: `idea<N>`, reachable at `idea<N>.tail2d60.ts.net`)
- Engine running via pm2 with cwd `/home/pi/idea/agents/agent-engine-dev`

**Roles:** Pis are **test / review / golden** hardware. They are **not** coding agents while the Grok Build runner path is parked (§2.2).

- **Shared test and review pool:** `idea01`, `idea03`, `idea04` (`role: spare` or `review`). Dev Bots claim a pool Pi for testing (§4.6); Ops deploys PRs for review to an idle pool Pi.
- **Golden:** `idea02` (`role: golden`) — never used for testing or review.

**Parked on idea02 only:** Grok Build stays installed; the self-hosted runner service is stopped after idea#147 merges (`runner: parked`). Neither is used for coding.

**Roles are assigned dynamically at runtime** by the fleet scripts (see Section 2.4). By convention, the first available Pi for a given domain is used. One Pi is the dedicated golden Pi (`role: golden`, currently `idea02`); `idea01`, `idea03`, and `idea04` form the shared non-golden test/review pool (`role: spare` or `review`). These assignments are recorded in `fleet-state.json` and update as Pis come and go.

### 2.3.1 Pi filesystem layout (canonical — test, dev, production)

Koen locked this tree on 2026-09-24 (revised same day: App repos nest under `agent-app-dev`). The same nesting applies on fleet Pis, local quality-scan / box checkouts, and production. Agent repos live **under** `idea/agents/`, not as siblings of `idea`. App GitHub repos are **direct children of `agent-app-dev/`** (not siblings of `agent-engine-dev` / `agent-console-dev`, and not under `agent-app-dev/apps/` — that folder is in-repo harness content).

```
/home/pi/idea/                          # clone of koenswings/idea
  agents/
    agent-engine-dev/                   # Engine source + runtime (pm2 cwd)
    agent-console-dev/                  # Console source; serve built dist from here
    agent-app-dev/                      # koenswings/agent-app-dev workspace
      app-kolibri/                      # clone of koenswings/app-kolibri
      app-nextcloud/
      app-kiwix/
      app-milkwise/
```

| Role | Canonical path |
|------|----------------|
| Engine pm2 cwd / `ENGINE_CWD` | `/home/pi/idea/agents/agent-engine-dev` |
| `ENGINE_BIN` | `/home/pi/idea/agents/agent-engine-dev/dist/src/index.js` |
| Console `consolePath` (Vite build output) | `/home/pi/idea/agents/agent-console-dev/dist` |
| quality-scan remote test cwd (`agent-*-dev`) | `/home/pi/idea/agents/<repo>` |
| quality-scan remote test cwd (`app-*`) | `/home/pi/idea/agents/agent-app-dev/<repo>` |
| quality-scan local `repo_path` (`agent-*-dev`) | `${IDEA_ROOT}/agents/<name>` |
| quality-scan local `repo_path` (`app-*`) | `${IDEA_ROOT}/agents/agent-app-dev/<name>` |

**Retired as primary** (migrate away; do not document as the path to use):

- `/home/pi/projects/engine`
- `/home/pi/console-dist`
- `/home/pi/agent-engine-dev` / `/home/pi/agent-console-dev` as siblings of `idea` (or of `/home/pi`)
- `app-*` as siblings of `agent-*-dev` under `idea/agents/`

Optional during migration: keep a symlink from an old path to the new tree, then remove it once fleet scripts and Engine `config.yaml` point at the nested paths.

Proposal / migration notes: [`proposals/pi-checkout-layout.md`](../proposals/pi-checkout-layout.md).

### 2.4 Fleet Scripts

All deterministic fleet operations are implemented as scripts in `koenswings/idea/tools/fleet/`. Bots call these scripts and act on their output — they do not reimplement the logic.

| Script | Purpose |
|--------|---------|
| `idea-setup.sh` | Platform install: discover all `idea*` Pis via Tailscale, verify dependencies, initialise `fleet-state.json`. **Skips Grok Build install and GitHub Actions runner registration by default**; an opt-in flag installs them (parked path, §2.2). The opt-in flag is `--with-grok-build` (the install steps themselves are still a stub). |
| `find-available-pi.sh <domain>` | Read `fleet-state.json`, apply domain affinity, return the first idle Pi. Returns empty if none available. |
| `deploy.sh <pi> <component> <repo> <branch>` | Full deploy sequence for the given component type (engine/console/app-disk): checkout, build, start, health check |
| `teardown.sh <pi>` | Reverse deploy: clean state, restore main, mark Pi idle in `fleet-state.json` |
| `update-golden.sh <component> <version>` | Update the golden Pi to the given version of a component |
| `set-golden-pi.sh` | Designate the most recently idle Pi as the new golden instance |
| `check-fleet-health.sh` | HTTP health check all deployed Pis, return JSON status |
| `update-fleet-state.sh [--create] [--json\|--null] <pi> <field> [<value>]` | Locked (flock), atomic read-modify-write of `fleet-state.json`. `--null` clears a field to JSON `null`; unknown Pis are refused unless `--create` |

All scripts are idempotent. They write their results to stdout as structured JSON for Bot consumption.

Fleet and quality scripts also append one JSON event line to `audit/audit-<YYYY>.jsonl` in `koenswings/idea` after every significant action. This provides a permanent, inspectable record of all system-level events (see the Audit Trail section below for the full design).

**Installation:** scripts live in `koenswings/idea/tools/fleet/`. They run on any Pi that has the idea repo cloned. Dependencies: `bash`, `jq`, `curl`, `ssh`, `tailscale`. All standard on fleet Pis.

Quality scripts (`quality-scan.sh`, `check-app-versions.sh`) live under `koenswings/idea/tools/quality/`, not under `tools/fleet/`. See Section 5 and `tools/README.md`.

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
  → implements with own tools (clone / GitHub); reads AGENTS.md
  → claims an idle pool Pi (idea01 / idea03 / idea04; never golden idea02)
    and runs domain tests over SSH — claim protocol §4.6
  → releases the Pi (main restored, pm2 restarted, status idle)
  │
  ▼
Dev Bot runs QC gate (see Section 5)
  ├── FAIL → Dev Bot fixes and retries (one retry max)
  ├── FAIL after retry → escalates to Lead Bot with diagnosis
  └── PASS → opens PR linked to issue
           → posts PR link as comment on issue
           → notifies Lead Bot (and Ops Bot for deploy)
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
  └── approved → Koen squash-merges PR on GitHub → issue auto-closes
  │
  ▼
Ops Bot calls teardown.sh <pi>
  → calls update-golden.sh <component> <version> (golden Pi moves to main; its version is updated)
  → calls check-fleet-health.sh (verifies the fleet is healthy)
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

Pis in this section are **review / golden / test** targets. Coding work does **not** run on Pi runners while the Grok Build path is parked (§2.2). Dev Bots claim an idle pool Pi to run tests before opening a PR (§4.6); Ops then deploys the PR branch to an idle pool Pi for Koen's live evaluation.

### 4.1 Fleet Manifest

`fleet-state.json` in `koenswings/idea` is the live record of every Pi in the fleet. It is updated exclusively via `update-fleet-state.sh` to prevent concurrent write conflicts.

```json
{
  "idea02": {
    "role": "golden", "pr": null, "status": "idle",
    "version": "engine main@b233ccb, console main@af473f1"
  },
  "idea03": {
    "role": "review", "pr": null, "status": "idle",
    "version": "engine main@b233ccb, console main@af473f1"
  }
}
```

`idea02` is the dedicated golden Pi and `idea03` the review Pi (idea#118); see §4.4. Every Pi records the mains or PR it runs in `version` / `pr`. New Pis are added by running `idea-setup.sh`; they appear in `fleet-state.json` automatically.

### 4.2 Pi Allocation

`find-available-pi.sh <domain>` implements all allocation logic:

1. Read `fleet-state.json`
2. Find a Pi with `status: idle` and matching domain (domain affinity)
3. If none with matching domain, find any idle non-golden Pi (overflow)
4. If none idle, return empty (PR is queued)

The golden Pi (`role: golden`) is never used for PR review, whatever its `status`. Its designation can shift if it goes down (`set-golden-pi.sh`).

Ops Bot calls the script, reads the result, and acts. It does not reimplement the selection logic.

### 4.3 Deployment

`deploy.sh <pi> <component> <repo> <branch>` handles the full deploy sequence for each component type. Agent git/build work happens **inside** `/home/pi/idea/agents/<repo>`; App repos use `/home/pi/idea/agents/agent-app-dev/<app-*>` (see §2.3.1). There is no separate primary rsync target at `/home/pi/console-dist`.

**Engine** (pm2, not Docker):
```
ssh to pi
  cd /home/pi/idea/agents/agent-engine-dev
  git fetch origin && git checkout <branch>
  pnpm install --frozen-lockfile && pnpm build
  pm2 restart engine                  (cwd = this tree; ENGINE_CWD / ENGINE_BIN under it)
  pm2 logs engine --lines 20          (verify clean start)
  curl http://localhost:80/api/store-url  (health check)
```

**Console** (built in-tree, served by Engine):
```
ssh to pi
  cd /home/pi/idea/agents/agent-console-dev
  git fetch origin && git checkout <branch>
  pnpm install --frozen-lockfile && pnpm build   # Vite → dist/
  # Engine config.yaml: consolePath: /home/pi/idea/agents/agent-console-dev/dist
  pm2 restart engine
HTTP check on http://<pi>/            (expect 200)
```

Migration note for existing Pis that still have `/home/pi/console-dist`: point `consolePath` at `agents/agent-console-dev/dist`, then remove or stop documenting the old directory. Optional one-time rsync into the new tree is fine during cutover; it is not the ongoing primary path.

**App Disk** (simulates physical dock):
```
rsync apps/<app>/ to pi:/tmp/<app>-pr-<N>/
ssh: docker compose up -d
ssh: docker compose ps                (verify running)
```

`teardown.sh <pi>` reverses the deploy and restores the Pi to a clean main-branch state under `idea/agents/`.

### 4.4 Golden Instance

One Pi is the dedicated golden instance (idea#118, Koen 2026-09-27; this replaces the temporary single-Pi rule from idea PR #112). Today that is `idea02`: `role: golden`, `status: idle`, `pr: null`, and a `version` such as `engine main@b233ccb, console main@af473f1`. It always runs the latest merged `main` of all components, keeps MilkWise running as a real workload, and is never used for PR review. `role: golden` (not `status`) is what excludes it from `find-available-pi.sh`.

PR review deploys go to an idle Pi from the shared pool (`idea01`, `idea03`, or `idea04`; `role: spare` or `review`), for example `http://idea03.tail2d60.ts.net:8080/`. After a merge, `update-golden.sh` moves the golden Pi to `main` and updates its `version` (until idea#107 implements it, Ops does this by hand with `update-fleet-state.sh`); if the golden Pi becomes unavailable, `set-golden-pi.sh` designates the most recently idle Pi.

### 4.5 Health Monitoring

`check-fleet-health.sh` runs on a cron schedule (every 30 minutes via GitHub Actions). It HTTP-checks all deployed Pis and returns a JSON status report. Ops Bot reads the report and alerts Lead Bot if any Pi is unreachable. It does not implement the check logic itself.

After each teardown, `check-fleet-health.sh` is called to verify the freed Pi is clean before marking it idle.

> **Known gap (idea#147):** the 30-minute health-check cron via GitHub Actions described above **does not exist as a workflow**. The only workflow in `koenswings/idea` is the manual `runner-test.yml`. Recorded as a follow-up (a scheduler that does not depend on the parked Pi runner), not fixed here.

### 4.6 Using fleet Pis for testing (claim protocol)

Applies to **all Dev Bots** (Engine, Console, App) whenever they use a fleet Pi for testing, a dev Console, or image builds. Decided in Design Review for idea#147 (Axle, Pixel, Kid, Atlas, 2026-09-28).

**Pool:** `idea01`, `idea03`, `idea04` (`role: spare` or `review`) are the shared test and review pool. **`idea02` (golden) is never used.**

**Claim:**
```bash
BOT_NAME=<bot> tools/fleet/update-fleet-state.sh <pi> status testing
BOT_NAME=<bot> tools/fleet/update-fleet-state.sh <pi> claim "<bot>: <repo>#<issue/PR>"
```
Pick an `idle` pool Pi. The bot name goes in the `claim` field (`BOT_NAME` also records it in the audit line). Do not overwrite the Pi's existing `note` field, which holds its isolation details.

**Release:** restore `main` in every tree you touched, restart the Engine with pm2 **as pi**, then:
```bash
BOT_NAME=<bot> tools/fleet/update-fleet-state.sh --null <pi> claim
BOT_NAME=<bot> tools/fleet/update-fleet-state.sh <pi> status idle
```

`find-available-pi.sh` returns only `idle` Pis, so Ops review deploys skip claimed Pis automatically.

**Rules (everyone):**
- Never use golden `idea02`.
- Leave each Pi's isolated store, `mdns: false` and local `config.yaml` untouched.
- Never take more than one Pi down at a time.

**Engine (Axle):**
- On the claimed Pi, stop the pm2 Engine (as pi) before testing.
- Run tests from a **separate checkout**, not the deployed tree (`/home/pi/idea/agents/agent-engine-dev`), kept off the fleet store.
- Restore `main` and restart pm2 before release.
- `IDEA_NETWORK_TESTS` stays off unless an issue asks for it.
- `store-template.json` is never touched.

**Sudoers:** a Dev Bot may install its PR's version of `11-engine-files` via `installEngineSudoers` on a Pi it has claimed, and must restore `main`'s version before release. Golden `idea02` sudoers stays with Atlas.

**App (Kid):**
- Builds can run on any claimed ARM64 pool Pi (not idea02); check each image with `docker manifest inspect`.
- On a claimed pool Pi, stop the pm2 Engine while App Harness runs, restore it on release, and use the deployed `/home/pi/idea/agents/agent-engine-dev` tree read-only; do not modify that tree.
- Before release: `docker compose down -v` for every harness project, remove test images, and leave no test disk mounted.
- `dd` test-disk writes stay with Atlas on idea03 only (idea#139).

**Console (Pixel):**
- Unit tests and typecheck run off-Pi against the mock store (no claim needed).
- A dev Console pointed at a Pi's Engine counts as using that Pi and needs a claim.
- Command testing never targets idea02.

**Where tests run (idea#152, 2026-09-28):**
- On-Pi hardware tests (`script/hw-roundtrip.ts`, `pnpm test:hw`) run on **idea03**, which keeps a hardware test disk docked permanently.
- `pnpm test:full` runs on **idea01 or idea04**. Its preflight (idea#105) refuses to run on idea03 while the test disk is docked.

**idea03 hardware test disk.** Identify it only by these IDs, never by a device name such as `sdb`:

| Field | Value |
|---|---|
| Model | Intenso SSD, 111.8G |
| USB bridge serial (`ID_USB_SERIAL_SHORT`) | `26A1EE83197F` |
| Disk serial (`ID_SERIAL_SHORT`) | `3813430-532011020` |
| Partition 1 | vfat, UUID `3E50-902A`, label `system-boot` |
| Partition 2 | ext4, UUID `378383c9-0612-4c82-9c07-8c34d15253ba`, label `writable` |

- Hardware tests touch only this disk.
- `dd` writes (idea#139), erase, the App Harness and erase tests (idea#138) must refuse it, and each has an automated check that proves the refusal.
- Never undock or wipe it. idea03's root SSD (serial `AA202000000000004820`) is never a test target.
- The same IDs are recorded in idea03's `note` in `fleet-state.json`.

**Handoffs to Koen (standing rule, 2026-09-28):** never ask Koen to run a specific test. Any test that is needed is coded as an automated test (unit, integration or on-Pi hardware) and passes before handoff. A handoff contains the PR URL, the review URL and the test evidence, never manual test steps. This applies to Ops review-deploy reports as well: Atlas reports the PR, the review URL and automated evidence (HTTP health, pm2 state, store and `mdns` checks, test results).

---

## 5. Quality Control

Quality is maintained through two mechanisms that enforce the same rules: a per-PR gate that runs before any code merges, and a scheduled scan that runs those same rules across everything already merged. The rules are not different between the two — the gate applies them to the current PR, the scan applies them to the full codebase.

All checks are implemented in `tools/quality/quality-scan.sh`. Bots invoke the script and act on the JSON output. They do not reimplement the logic.

`quality-scan.sh` resolves `agent-*-dev` repos to `${IDEA_ROOT}/agents/<name>` and `app-*` repos to `${IDEA_ROOT}/agents/agent-app-dev/<name>` locally; remote domain tests use the same nesting on the selected Pi (`/home/pi/idea/agents/…`) — the same layout as production (§2.3.1).

### 5.1 The Rules

These rules apply both at the PR gate and in the scheduled scan:

**Tests must pass**

- Engine: `pnpm test:full` — builds then runs vitest on ARM hardware; results written to `test/testresults/`
- Console: `pnpm test` + `pnpm typecheck`
- App Dev: App Harness (`node tests/<app>/smoke.mjs`) — spawns a real Engine and verifies containers reach Running state

**Structure**

- No source files (`.ts`, `.js`, `.tsx`, `.jsx`) in any `docs/` folder
- No `.md` files in `src/`
- Test files live in `test/` only

**Code hygiene**

- No hardcoded credentials — `process.env` or `import.meta.env` only
- No `console.log` in production code paths
- No commented-out blocks longer than 5 lines without an explanatory comment
- No `TODO` or `FIXME` without a linked GitHub issue number

**Documentation currency**

- Every file in `docs/` describes the system as it currently exists. If a PR changes implemented behaviour, the affected `docs/` files must be updated in the same PR.
- If a PR adds a new file to `docs/`, `docs/INDEX.md` must be updated in the same PR.
- `AGENTS.md` must be updated in any PR that changes build, test, or deploy procedures.

**Staleness** (scan only — cannot be checked at PR time):

- Any file in any `docs/` folder whose last-modified date is more than 30 days older than the most recent source commit that would logically affect it.
- Any `AGENTS.md` whose last-modified date is more than 14 days older than the most recent build-related source commit in that repo.

### 5.2 The PR Gate

Dev Bots invoke `quality-scan.sh --pr --repo <name> --base <sha> --head <sha>` before opening any PR, where `<base>` is the commit on `main` the branch starts from and `<head>` is the branch tip. The script checks the changes in `<base>..<head>` against all the rules above (except staleness, which only applies to the full codebase). If any check fails, the Dev Bot fixes it and retries once. After two failures, the Dev Bot escalates to Lead Bot with the script output — it never opens a PR on failing checks.

### 5.3 The Scheduled Scan

`quality-scan.sh` runs on two triggers:

1. **After every merge to main** — Lead Bot invokes it automatically
2. **Every Monday morning** — Lead Bot invokes it on schedule

The script scans all IDEA repos: `idea`, `agent-engine-dev`, `agent-console-dev`, `agent-app-dev`, and all app repos under `agent-app-dev/` (`app-kolibri`, `app-nextcloud`, `app-kiwix`, `app-milkwise`).

It returns a JSON report. Lead Bot reads the report and files GitHub issues for any violations:

- Structural and code hygiene violations → label: `quality`
- Stale docs/ files or AGENTS.md → label: `docs-review`
- Engine tests failing on main → Lead Bot notifies Koen immediately, before filing any issues

Kid (App Dev Bot) additionally calls `tools/quality/check-app-versions.sh` as part of the Monday scan. That script reads each app's `app.yaml`, queries DockerHub and GitHub for latest upstream versions, and returns a JSON diff. Kid files issues (label: `app-update`) for any new versions found.


## 6. Routines

Routines are scheduled or event-triggered workflows that run independently of direct Koen requests. They keep the system healthy, documentation current, and apps up to date.

![Scheduled Routines](../proposals/routines.png)

| Trigger | Owner | Routine | Outcome |
|---------|-------|---------|---------|
| After every merge | Lead Bot (automated) | `quality-scan.sh` across all repos + golden update via `update-golden.sh` | Quality issues filed; merged mains recorded; freed Pi health verified |
| Weekly — Monday | Lead Bot + App Dev Bot | `quality-scan.sh` + `check-app-versions.sh` | Quality report; app-update issues for new upstream versions |
| Every 30 min (cron) — **not implemented** (§4.5 gap) | Ops Bot via `check-fleet-health.sh` | HTTP health check all deployed Pis | Alert Lead Bot if any Pi unreachable |
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

> **Pending Bot description updates (idea#147 follow-up, Koen):** the `RUN` steps below already describe the live path. Lines each bot flagged for Koen to update in the live descriptions after the AGENTS.md PRs land:
> - **Atlas (Ops):** "After teardown: run pnpm test:full on freed Pi's main branch via script"; "cron via GitHub Actions" health check (does not exist, §4.5).
> - **Kid (App Dev):** "trigger Grok Build"; idea03-only builds ("Build on ARM Pi (idea03) only", "rebuild on idea03") — now any claimed ARM64 pool Pi (§4.6).
> - **Axle (Engine Dev):** "trigger Grok Build".
> - **Pixel (Console Dev):** "trigger Grok Build"; the non-existent `scripts/deploy-fleet.sh`.
>
> Where a line below conflicts with §4.6, §4.6 wins.

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

PROPOSALS: all proposals live in koenswings/idea/proposals/. A proposal
can be a requirements sketch, an implementation analysis, or both —
the level of detail should match the complexity of the change.

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
   Any level of detail is acceptable — requirements only, full
   implementation analysis, or anything between.
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
- `agent-engine-dev/proposals/solution-description.md` — vision and intent. Use it to understand long-term design rationale and find missing features.

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
YOUR AGENTS.md: read at the start of every implementation task.

Authoritative docs: docs/ARCHITECTURE.md, docs/COMMANDS.md,
docs/SCRIPTS.md, docs/PI_FLEET.md
Intent: agent-engine-dev/proposals/solution-description.md (not necessarily implemented)

DESIGN REVIEW DUTY:
Assess architecturally: sound for the Engine? Risks around Automerge
sync, udev, USB exclusivity, offline-first? Conflicts with constraints?
Be direct. Your review is an input to the decision, not a veto.

EXECUTION DUTY:
1. READ — GitHub issue + agreed approach comment. No comment = ask Lead Bot.
2. RUN — implement with your own tools (clone / GitHub). Claim an idle
   pool Pi (idea01/03/04, never idea02) and run tests over SSH; release
   it when done (claim protocol, §4.6). Do not trigger Grok Build or Pi
   runners — that path is parked (idea#147 / §2.2).
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
Built via Vite → dist/ under /home/pi/idea/agents/agent-console-dev;
Engine serves that dist via consolePath.

Key constraints:
- Solid.js fine-grained reactivity:
  * All <For> loops must be ID-keyed — never index-keyed
  * No broad store subscriptions — use derived signals
- No external CSS frameworks — main.css only
- No CDNs or external dependencies at runtime (fully offline)
- TypeScript strict mode
- Chrome Extension (background.ts): legacy, keep building, never add logic

YOUR REPO: github.com/koenswings/agent-console-dev
YOUR AGENTS.md: read at the start of every implementation task.
DEPLOY SCRIPT: scripts/deploy-fleet.sh

DESIGN REVIEW DUTY:
Assess: affects Console UI, data model, or store layer? Reactivity or
rendering implications? Conflicts with offline-first or Solid.js patterns?

EXECUTION DUTY:
1. READ — GitHub issue + agreed approach comment. No comment = ask Lead Bot.
2. RUN — implement with your own tools (clone / GitHub). Claim an idle
   pool Pi (idea01/03/04, never idea02) and run tests over SSH; release
   it when done (claim protocol, §4.6). Do not trigger Grok Build or Pi
   runners — that path is parked (idea#147 / §2.2).
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
YOUR AGENTS.md: read at the start of every implementation task.

DESIGN REVIEW DUTY:
Assess: affects App Disk format, compose.yaml conventions, app.yaml
schema, or Engine dock detection? ARM64 compatibility concerns?

EXECUTION DUTY:
1. READ — GitHub issue + agreed approach comment. No comment = ask Lead Bot.
2. RUN — implement with your own tools (clone / GitHub). Claim an idle
   ARM64 pool Pi (idea01/03/04, never idea02) and run harness tests / image
   builds over SSH; release it when done (claim protocol, §4.6). Do not
   trigger Grok Build or Pi runners — that path is parked (idea#147 / §2.2).
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
- update-fleet-state.sh [--create] [--json|--null] <pi> <field> [<value>] — locked, atomic state update
  (clear a field with --null, e.g. update-fleet-state.sh --null idea02 pr)

DEPLOY WORKFLOW (triggered when Dev Bot passes QC):
1. Call find-available-pi.sh <domain>. Read result.
2. If Pi found: call deploy.sh. Read health check result.
   Update fleet-state.json via update-fleet-state.sh.
   Notify Lead Bot with URL.
3. If no Pi available: record PR in queue in fleet-state.json.
   Notify Lead Bot: "no idle Pi — PR queued."
4. After merge: call teardown.sh on review Pi.
   Call update-golden.sh for the merged component (golden Pi to main, version updated).
   Call check-fleet-health.sh. Verify clean.
   Call find-available-pi.sh for any queued PRs. Deploy if found.

HEALTH MONITORING:
Call check-fleet-health.sh every 30 minutes (cron via GitHub Actions).
Read the JSON report. If any Pi is unreachable: alert Lead Bot immediately,
stop all other changes.

GOLDEN INSTANCE:
One Pi carries role: golden (today idea02; status stays idle). Its version
records the mains it runs (engine main@<sha>, console main@<sha>). It always
runs latest merged main, keeps MilkWise running, and is never used for PR
review: find-available-pi.sh skips role golden. Review deploys go to review
Pis (today idea03). If the golden Pi goes down, call set-golden-pi.sh to
designate a new one.

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

## 9. AGENTS.md for Each Repo (templates PARKED)

AGENTS.md is the per-repo operational manual for whoever implements in that repo. **Live path:** Dev Bots read it at the start of every implementation task. **Parked path:** if Grok Build is revived, it also reads AGENTS.md natively at the start of a run. Owned by the Dev Bot for that repo. Must be updated in the same PR as any change to build, test, or deploy procedures.

**PARKED (idea#147, Design Review decision):** the templates in §9.1–9.3 are kept as the parked Grok Build revival text — they say "You are Grok Build on an ARM64 Raspberry Pi runner" and are **not** the live instructions. Live implementers are Dev Bots using clone / GitHub + claimed-Pi SSH tests (§2.2, §3, §4.6). Each repo's real `AGENTS.md` is owned by its Dev Bot; follow-up PRs from Axle, Pixel and Kid rewrite that wording in their repos.

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
proposals/         Proposals and historical design reasoning
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

The fleet deploy scripts handle all deployment logic. The implementer's job (Dev Bot live; Grok Build if revived) is to produce a passing test suite and open a PR — Ops Bot does the rest.

**config.yaml key settings**

```yaml
settings:
  httpPort: 80          # Serves Console web app + /api/store-url
  consolePath: /home/pi/idea/agents/agent-console-dev/dist
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
proposals/             Proposals and historical design reasoning
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
proposals/          Proposals and historical design reasoning
```

Each App repo (e.g. koenswings/app-kolibri):
```
compose.yaml        App Disk manifest — x-app metadata + x-app-version
app.yaml            Build approach, upstream monitoring sources
app/                Dockerfile + source (custom build only)
docs/               Authoritative docs for this App
proposals/          Proposals and historical design reasoning
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
ENGINE_BIN=/home/pi/idea/agents/agent-engine-dev/dist/src/index.js \
ENGINE_CWD=/home/pi/idea/agents/agent-engine-dev \
node tests/<app>/smoke.mjs
```

**Deploy (Ops Bot handles this via deploy.sh)**

The implementer's job (Dev Bot live; Grok Build if revived) is to produce a passing harness result and open a PR.

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

### 10.1 Coding-work audit (live vs parked)

**Live path:** Dev Bot implementation leaves the normal GitHub trail — commits, PR diffs, QC comments, and SSH test artefacts attached to the PR (for example `test/testresults/`). There is no Pi-runner coding workflow to log while Grok Build is parked.

**Parked path (Grok Build + Pi runners):** If revived, every Grok Build invocation would run via a GitHub Actions workflow on a Pi runner. GitHub retains the full console output per run — every file read, command, test result, and error — tied to the PR and commit. Configure retention in repository settings (default 90 days). Until revival, treat runner / Grok Build Action logs as historical or health-check only (idea02).

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

- **PR / commit / test artefacts** for the technical detail of live Dev Bot coding work; **GitHub Actions logs** only if the parked Grok Build runner path is revived
- **Structured audit log** for the operational ledger — what Bot did what, when, and what the outcome was

Together they cover the full picture: GitHub depth for code changes, the JSONL log for operational breadth.

---

## 11. koenswings/idea Repository

`koenswings/idea` is the IDEA org root. It contains:

| File / Directory | Purpose | Owner |
|-----------------|---------|-------|
| `CONTEXT.md` | Condensed mission, product, team structure — Lead Bot reads at design sessions | Koen (via PR) |
| `proposals/` | Any document that develops an idea — from requirements sketch to full implementation analysis. The permanent record of every decision made and reasoning behind it. | Lead Bot (PRs), Koen (merges) |
| `proposals/` | PR-based proposal process | Any Bot (PRs), Koen (merges) |
| `docs/` | Org-level authoritative docs | Lead Bot / Koen |
| `tools/fleet/` | Fleet management scripts | Ops Bot (via PRs) |
| `tools/quality/` | Quality scan and version check scripts | Lead Bot / App Dev Bot (via PRs) |
| `tools/pdf/` | PDF generation script | Any Bot (via PRs) |
| `fleet-state.json` | Live Pi fleet state — updated via update-fleet-state.sh | Ops Bot (scripts) |
| `audit/audit-<YYYY>.jsonl` | Structured audit log — appended by Bots after every system event | All Bots (via scripts) |
| `README.md` | Overview of the repo | Koen |
