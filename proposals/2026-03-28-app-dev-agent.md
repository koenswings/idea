# Proposal: App Developer & Maintainer Agent (Kit)

**Proposed by:** Atlas (operations-manager) — on behalf of Axle (engine-dev)
**Date:** 2026-03-28
**Status:** Proposed

---

## Problem

IDEA's educational apps (Kolibri, Nextcloud, Kiwix, etc.) are distributed on App Disks.
Each disk contains a `compose.yaml` referencing one or more Docker images. When upstream
projects release new versions — or when a supporting service (MariaDB, Redis, etc.) gets a
security fix — nothing currently happens. There is no agent responsible for monitoring,
building, testing, or maintaining the app stack. The app repos are unattended.

This creates two risks: schools receive outdated software with known bugs or security issues;
and new apps that could benefit teachers never get evaluated or integrated.

---

## Proposed Solution

Add a sixth operational agent — **Kit 🎒**, App Developer & Maintainer — with the following
responsibilities:

1. **Version monitoring** — detect new versions of all services in each app's compose stack,
   including supporting services (MariaDB, Redis, etc.) and IDEA-developed services
2. **Building** — build updated Docker images on the Pi via `build-instance`; no CI pipeline
3. **Testing** — run the compatibility test suite before any release
4. **Maintenance** — own the full service stack of each app, not just the top-level image
5. **New app proposals** — identify and evaluate apps suitable for offline African schools

---

## Agent Identity

- **Name:** Kit 🎒
- **Role title:** App Developer & Maintainer
- **Agent ID:** `app-dev` (proposed)
- **Workspace repo:** `agent-app-dev`
- **Telegram group:** New dedicated group, same pattern as all other agents
- **MC board:** New board in the Engineering board group

---

## File System Structure

The app repos live **inside Kit's workspace** (`agent-app-dev/`), as git submodules. Each
app repo remains an independent GitHub repo (`koenswings/app-kolibri`, etc.) but is linked
into Kit's workspace so Kit has everything it needs in one place.

```
/home/pi/idea/agents/
  agent-app-dev/                ← Kit's workspace
    harness/                    ← shared test harness (part of this repo)
    app-kolibri/                ← git submodule → koenswings/app-kolibri
    app-nextcloud/              ← git submodule → koenswings/app-nextcloud
    app-kiwix/                  ← git submodule → koenswings/app-kiwix
    app-kolibri-studio/         ← git submodule → koenswings/app-kolibri-studio
    app-seafile/                ← git submodule → koenswings/app-seafile
    AGENTS.md
    MEMORY.md
    ...
  agent-engine-dev/             ← Axle
  agent-console-dev/            ← Pixel
  agent-site-dev/               ← Beacon
  agent-programme-manager/      ← Marco
  agent-operations-manager/     ← Atlas
```

Each app repo structure:
```
app-kolibri/
  compose.yaml            ← service definitions; Kit keeps all image versions current
  monitoring.yaml         ← version monitoring strategy + compatibility matrix
  build-instance          ← Pi-based build script; Kit owns and runs this
  tests/
    smoke.ts              ← HTTP health check
    ui/homepage.spec.ts   ← Playwright UI test
  test-data/              ← initial data for test runs (see data storage proposal)
  META.yaml               ← app disk metadata (diskId, version, etc.)
  apps/
    kolibri-1.0/
      compose.yaml
```

The test harness (`agent-app-dev/harness/`) provides scaffolding shared across all apps:
start a test engine in testMode, dock a fixture disk, wait for Running, hand off to the
app's own test suite. It builds on Axle's engine test primitives (`testMode`, disk
simulation) — Kit depends on these; Axle maintains them.

---

## What Kit Monitors

### Monthly cadence (all apps)

Kit monitors the full service stack of each app, not just the primary image. For a
typical app this means checking every image reference in `compose.yaml`:

- Primary application image (e.g. `learningequality/kolibri:v0.15`)
- Database services (e.g. `mariadb:10.6`, `postgres:15`)
- Cache / proxy services (e.g. `redis:7`, `nginx:1.25`)
- Any other service in the compose file

When a new version is detected for any service, Kit assesses whether the update is:
- **Patch/minor** — update, test, build, open PR
- **Major** — assess for breaking changes first; may require a `[From Kit] Feasibility`
  task to Axle if engine compatibility could be affected

### IDEA-developed services (service-specific monitoring)

Some apps depend on services IDEA has built rather than off-the-shelf images. For these,
version monitoring cannot use Docker Hub — it is service-specific and requires research.

**Example — Kolibri:** Kolibri is distributed as a Pex file (Python executable). Monitoring
a new Kolibri version means checking for a new Pex file at the Learning Equality release
page, not Docker Hub. Kit must know the correct monitoring strategy per service and apply
it. This strategy is documented per app in a `monitoring.yaml` file in each app repo.

---

## Building

All Docker image builds run **on the Pi** using `build-instance`. There is no CI pipeline —
this was a deliberate decision to avoid cross-platform compilation complexity (building ARM
images on GitHub Actions is fragile; building on the Pi itself is reliable).

Kit runs `build-instance` after a version update passes tests. The resulting image is pushed
to DockerHub under `koenswings`. The App Disk is then updated with the new image reference.

DockerHub namespace: **`koenswings`** (personal account; migration to an org deferred until
GitHub org name is decided).

---

## Compatibility Test Framework

Tests use the engine test infrastructure Axle has already built (testMode + disk simulation).
Kit adds the app-level layer on top via `agent-app-dev/harness/`:

- **Smoke tests** — HTTP health check against the running container
- **UI tests** — Playwright: load key pages, assert core content visible
- **Data migration tests** — for major upgrades: confirm existing data survives
- **Offline test** — confirm the container starts and serves with no outbound network

App-specific tests live in each app repo (`app-kolibri/tests/`). See the data storage
sub-proposal (`2026-03-28-kit-data-storage.md`) for how initial test data is handled.

---

## Initial Data

Each app may require initial data to function — a pre-seeded database, a set of files,
or configuration. For Nextcloud specifically, Marco's presentations must be present in a
designated folder on every deployment.

See the data storage sub-proposal: `proposals/2026-03-28-kit-data-storage.md`.

---

## Interfaces with Other Agents

**Axle (Engine Dev)**
- Kit depends on Axle's engine test primitives (`testMode`, disk simulation)
- Major app version bumps that may affect engine compatibility: `[From Kit] Feasibility` task
- Engine changes that affect app compatibility: `[From Axle] Review` task to Kit to re-run tests

**Marco (Programme Manager)**
- `[From Kit] Opinion` tasks for field viability of new app proposals
- Kit notifies Marco when a new app version lands so Marco can update teacher guides
- Marco's presentations are pre-loaded into every Nextcloud deployment (see data storage proposal)

**Atlas (Operations Manager)**
- Standard PR review for all Kit PRs (app repo changes, harness changes)

---

## Compatibility Matrix

See the compatibility matrix sub-proposal: `proposals/2026-03-28-kit-compatibility-matrix.md`.

---

## New App Proposals

When Kit identifies a candidate app, the process is:
1. Kit assesses: offline capability, container size, teacher complexity, licence
2. `[From Kit] Opinion` to Marco — field viability
3. If Marco concurs: Kit creates a proposal in `idea/proposals/`
4. CEO approves by merging → creates a task on Kit's MC board
5. Kit creates the app repo, `monitoring.yaml`, test suite, and first App Disk

Kit-initiated proposals (without a Marco request) are limited to one per quarter to
keep scope bounded.

---

## Decisions (from open questions)

1. **DockerHub namespace:** `koenswings` — continue with personal account; migrate when
   GitHub org is decided
2. **Image builds:** On the Pi via `build-instance`; no CI pipeline
3. **Initial data storage:** See sub-proposal `2026-03-28-kit-data-storage.md`
4. **App disk build script:** Already exists — called `build-instance` (in each app repo)
5. **Compatibility matrix:** See sub-proposal `2026-03-28-kit-compatibility-matrix.md`
6. **App repos current state:** Audit each repo and open a bootstrap PR before monitoring begins
7. **Scope of new app proposals:** Bounded — Marco identifies need first; Kit-initiated max 1/quarter

---

## Affected Repos / Agents

**New repos (GitHub):**
- `koenswings/agent-app-dev` — Kit's workspace (includes `harness/` subdirectory)

**Existing repos with structural additions:**
- `app-kolibri`, `app-nextcloud`, `app-kiwix`, `app-kolibri-studio`, `app-seafile` — each
  gets `tests/`, `test-data/`, and `monitoring.yaml` added by Kit in a bootstrap PR;
  each is linked as a git submodule inside `agent-app-dev/`
- Each gets `build-instance` reviewed and standardised

**Agents affected:**
- Axle — provides engine test primitives; receives feasibility questions on major bumps
- Marco — field viability input; receives release notifications; presentations on Nextcloud
- Atlas — quality reviews Kit's PRs; updates org design to add Kit

**Infrastructure:**
- New OpenClaw agent config entry in `openclaw.json`
- New MC board in Engineering group
- New Telegram group
- Monthly cron job for version monitoring (OpenClaw cron scheduler)
