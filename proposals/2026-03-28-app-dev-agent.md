# Proposal: App Developer & Maintainer Agent (Forge)

**Proposed by:** Atlas (operations-manager) — on behalf of Axle (engine-dev)
**Date:** 2026-03-28
**Status:** Proposed

---

## Problem

IDEA's educational apps (Kolibri, Nextcloud, Kiwix, etc.) are distributed on App Disks.
Each disk contains a `compose.yaml` referencing a Docker image and a version number. When
an upstream project releases a new version, nothing currently happens — there is no agent
responsible for monitoring, updating, testing, or proposing new apps. The app repos
(`app-kolibri`, `app-nextcloud`, `app-kiwix`, `app-kolibri-studio`, `app-seafile`) exist
but are unattended.

This creates two risks: schools receive outdated software with known bugs or security issues;
and new apps that could benefit teachers never get evaluated or integrated.

---

## Proposed Solution

Add a sixth operational agent — **Forge ⚒️**, App Developer & Maintainer — with four
responsibilities:

1. **Version monitoring** — detect new upstream releases of existing apps and initiate the
   update cycle
2. **App updates** — update `compose.yaml`, bump the IDEA version number, run compatibility
   tests, and open a PR for CEO review
3. **New app proposals** — identify and evaluate new apps suitable for offline African schools
4. **Test framework** — own and maintain the shared compatibility test harness; run upgrade
   tests across all apps before any release

---

## Agent Design

### Identity

- **Name:** Forge ⚒️
- **Role title:** App Developer & Maintainer
- **Agent ID:** `app-dev` (proposed)
- **Workspace repo:** `agent-app-dev` (new — identity files and memory only, consistent with
  other agent repos)
- **Telegram group:** New dedicated group, same pattern as all other agents
- **MC board:** New board in the Engineering board group

### Repo Structure

```
koenswings/
  agent-app-dev/          ← Forge's workspace (identity, memory, outputs)
  app-harness/            ← Shared test harness (new repo — owned by Forge)
  app-kolibri/
    tests/                ← Kolibri-specific tests (Forge adds this structure)
    test-data/            ← Test data snapshots (see Open Questions on size)
    compose.yaml
  app-nextcloud/
    tests/
    test-data/
    compose.yaml
  app-kiwix/
    tests/
    test-data/
    compose.yaml
  app-kolibri-studio/
    tests/
    test-data/
    compose.yaml
  app-seafile/
    tests/
    test-data/
    compose.yaml
```

The shared test harness (`app-harness`) provides primitives that all app test suites can
depend on. Axle's engine test infrastructure (`testMode`, disk simulation) is available
as a dependency — Forge does not duplicate it.

### Version Monitoring

Forge uses the Docker Hub public tags API (no auth required for public images) to detect
new upstream versions. A manifest file in `app-harness` (e.g., `apps/versions.yaml`)
tracks the current IDEA version of each app alongside the upstream image it is pinned to.

Monitoring runs as an OpenClaw **cron job** (daily). When a new upstream tag is detected:
1. Forge opens a branch in the relevant app repo
2. Updates `compose.yaml` with the new image tag
3. Bumps the IDEA version (minor bump for upstream minor/patch; major bump for major)
4. Runs the compatibility test suite (see below)
5. If tests pass: opens a PR with a structured description and test results
6. If tests fail: opens a PR marked `[FAILING TESTS]` so CEO knows review is needed

The CEO merges the PR. A GitHub Actions pipeline in the app repo builds the Docker image
and pushes it to DockerHub under `koenswings` (see Open Questions on namespace).

### Compatibility Test Framework

Tests use the engine test infrastructure Axle has already built (testMode + disk simulation
from `agent-engine-dev`). Forge adds the app-level layer on top:

- **Smoke tests** — HTTP health check against the running container
- **UI tests** — Playwright: load key pages, assert core content visible
- **Data migration tests** — for major upgrades: confirm existing data survives the upgrade
- **Offline test** — confirm the container starts and serves with no outbound network access

App-specific tests live in each app repo (`app-kolibri/tests/`). The shared harness in
`app-harness` provides the scaffolding: start a test engine, dock a fixture disk, wait for
the instance to reach `Running`, then hand off to the app's test suite.

Axle maintains the engine primitives; Forge maintains the app-level harness and the
per-app test suites.

### New App Proposals

When Forge identifies a candidate app (from the Docker Hub ecosystem, educational software
registries, or Marco's field feedback), the process is:

1. Forge assesses: offline capability, container size, complexity for teachers, licence
2. `[From Forge] Opinion` cross-agent task to Marco — field viability (is this useful for
   African schools?)
3. If Marco concurs: Forge creates a proposal in `idea/proposals/`
4. CEO approves by merging the proposal PR → creates a task on Forge's MC board
5. Forge builds the initial app repo structure, test suite, and first App Disk version

### Interfaces with Other Agents

**Axle (Engine Dev)**
- Forge depends on Axle's engine test primitives (`testMode`, disk simulation) — Axle
  maintains these as part of the engine; Forge imports them
- When an app major version requires engine changes: `[From Forge] Feasibility` task on
  Axle's board — assessment of whether the engine needs to change before the app can land
- When the engine changes in ways that affect app compatibility: `[From Axle] Review` task
  on Forge's board — Forge runs the full app test suite against the new engine version

**Marco (Programme Manager)**
- `[From Forge] Opinion` tasks to Marco for new app field viability assessments
- Forge notifies Marco (via cross-agent task or direct message) when a new app version lands,
  so Marco can update teacher guides and training materials
- Marco's field feedback is the primary signal for new app proposals

**Atlas (Operations Manager)**
- Standard PR review: Atlas reviews Forge's PRs (app repo changes, harness changes)
  for architectural consistency and offline-resilience before the CEO merges
- Forge is a sixth operational agent — Atlas owns the org design and quality review for it
  like any other

---

## Affected Repos / Agents

**New repos:**
- `koenswings/agent-app-dev` — Forge's workspace
- `koenswings/app-harness` — shared test harness

**Existing repos with structural additions:**
- `app-kolibri`, `app-nextcloud`, `app-kiwix`, `app-kolibri-studio`, `app-seafile` — each
  gets a `tests/` and `test-data/` directory added by Forge in a bootstrap PR

**Agents affected:**
- Axle — provides engine test primitives; receives feasibility questions on major bumps
- Marco — field viability input on new apps; receives version release notifications
- Atlas — quality reviews Forge's PRs; updates org design doc to add Forge

**Infrastructure:**
- New OpenClaw agent config entry (in `openclaw.json`)
- New MC board in Engineering group
- New Telegram group
- Daily cron job for version monitoring (OpenClaw cron scheduler)
- GitHub Actions in app repos (may need to be added if not present)

---

## Open Questions

1. **DockerHub namespace.** Images are currently planned for `koenswings/`. This is a
   personal account. Should IDEA have a dedicated DockerHub organisation before Forge starts
   building images? If `koenswings` is used now, migrating later breaks any disk that
   references the old image path.

2. **Image builds in CI.** Building Docker images requires internet access (to pull base
   images). This cannot happen on the Pi. Does IDEA have GitHub Actions configured on any
   app repo today? If not, this is a prerequisite before Forge can complete an update cycle.

3. **Test data size.** App test-data snapshots (a populated Kolibri database, a Nextcloud
   instance with test files) could be hundreds of MB or more. Git is not appropriate for
   large binaries. Options: git-lfs, external object storage, or ship test data inside the
   Docker image itself (cleanest for offline use). This policy needs to be decided before
   Forge adds `test-data/` to any app repo.

4. **App disk build.** Forge updates `compose.yaml` in the app repo, but the App Disk
   itself is a directory structure on a physical USB drive. Is there a `build-disk` script
   that creates this from the repo? If not, Forge needs to design and build one as a
   prerequisite.

5. **Compatibility matrix format.** Which IDEA Engine version does each app version require?
   A machine-readable manifest (`apps/versions.yaml`) should track this so the Engine can
   warn when an incompatible disk is inserted. Needs a defined schema before Forge starts
   versioning apps.

6. **App repos' current state.** The five existing app repos may have no CI, no tests, and
   no standard structure. Forge should audit these and open a bootstrap PR per repo before
   beginning any version monitoring work.

7. **Scope of "propose new apps."** Left unbounded this could be an infinite research task.
   Recommend a bounded trigger: Marco identifies an educational need first; Forge is only
   engaged to assess technical feasibility for an app that Marco has specifically requested.
   Forge-initiated proposals (no Marco request) should be limited to one per quarter.
