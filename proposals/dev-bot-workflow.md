# Proposal: Officialise Dev Bot + SSH workflow; park Grok Build runner path

**Issue:** [idea#147](https://github.com/koenswings/idea/issues/147)
**Author:** Steve (Lead Bot), for Koen Swings
**Date:** 2026-09-28
**Status:** Design Review complete — approved by Axle, Pixel, Kid, Atlas (2026-09-28)
**Decision:** Koen go-ahead 2026-09-28 — make the current approach official and update the docs

---

## What

Make the **actual** development workflow the official design in `CONTEXT.md` and `docs/grok-bot-setup.md`, and park the unused Grok Build + GitHub Actions self-hosted runner coding path until we deliberately revive it.

**Official path (Koen approved 2026-09-28):**

1. Lead discusses with Koen → approach comment on the GitHub issue → delegate to Dev Bot.
2. Dev Bot (Axle / Pixel / Kid) implements with its own tools (clone / GitHub), runs tests via SSH on a fleet Pi (typically `idea03` / any idle non-golden), opens a PR, notifies Lead.
3. Ops (Atlas) uses fleet scripts to deploy to a review Pi; Lead notifies Koen with PR URL + live review URL.
4. Koen squash-merges; Ops updates golden / fleet mains.
5. Grok Build + GitHub Actions self-hosted runner coding path is **PARKED** (may remain installed on `idea02` for health check). Pis are test / review / golden hardware, not coding agents, until we revive the runner path deliberately.

## Why

- Docs today describe: Dev Bot → trigger Grok Build on a Pi runner → QC → PR → Ops deploy.
- The team already ships successfully with Dev Bots implementing directly and testing over SSH.
- Dev Bots keep domain expertise, memory across tasks, design-review participation, and judgement calls. Fresh Grok Build runs lack that continuity.
- Docs should describe what we run, not a parked design presented as live.

## Current vs docs

| Aspect | Docs today | Reality (make official) |
|--------|------------|-------------------------|
| Who implements | Grok Build on Pi runner (headless) | Dev Bot (Axle / Pixel / Kid) via clone / GitHub tools |
| Where tests run | Inside Grok Build on the runner Pi | SSH to a fleet Pi (idle non-golden, typically idea03) |
| Who opens the PR | Grok Build / Dev Bot after runner run | Dev Bot after QC |
| Review deploy | Ops + fleet scripts | Unchanged (real) |
| Golden / fleet mains | Ops after merge | Unchanged (real) |
| Grok Build + runners | Described as the coding path | **Parked** — optional health-check install on idea02 |

## Changes

1. **`CONTEXT.md`** — Team / workflow paragraph: Dev Bots implement; Pis are test / review / golden; park Grok Build runner path; one-line test claim rule.
2. **`docs/grok-bot-setup.md`**
   - Overview + §2.1 / §2.2: stop calling Grok Build the live coding tool; label it **PARKED**.
   - §2.3: Pis are test / review / golden hardware; runner / Grok Build install on idea02 is optional / parked, not a coding agent.
   - §3.1 / §3.2: Dev Bot implements → SSH tests → QC → PR → Ops deploy (no “triggers Grok Build”).
   - §8 Dev Bot EXECUTION DUTY: `RUN` = implement with own tools + SSH tests (not trigger Grok Build).
   - §4: no coding-runner claims; review / golden behaviour unchanged.
   - §4.6 (new): **Using fleet Pis for testing (claim protocol)** — see Decisions 4–9.
   - §4.5 / §6: record that the 30-minute GitHub Actions health-check cron does not exist (follow-up).
   - §9 / §10: AGENTS.md and audit wording for the live Dev Bot path; runner / Grok Build logs noted as parked history, not deleted.

Fleet scripts (`find-available-pi`, `deploy`, `teardown`, golden helpers) stay as documented — they are real.

## Out of scope

- Installing runners on idea01 / idea03 / idea04
- Building a Grok Build task-handing workflow
- Changing Design Review or proposal process
- idea01-as-golden swap (separate discussion)
- Asking Atlas which model Grok Build uses (informational only; not blocking)

## Decisions (Design Review, 2026-09-28)

1. **Templates** — the §9 AGENTS.md templates stay, under a **PARKED** heading.
2. **`idea-setup.sh`** — documented as skipping Grok Build and runner install by default, with an opt-in flag. *Follow-up (Atlas):* the script change itself; not edited here.
3. **idea02 runner** — after merge, Atlas stops the self-hosted runner service on idea02 and sets `runner: parked` in `fleet-state.json`. Grok Build 1.0.40 (default model `grok-4.6`) stays installed. *Gap / follow-up:* the documented 30-minute health-check cron via GitHub Actions does not exist; the only workflow is the manual `runner-test.yml` in `idea`.
4. **Pool** — `idea01`, `idea03`, `idea04` (`role: spare` or `review`) are the shared test and review pool. `idea02` (golden) is never used.
5. **Claim protocol (all Dev Bots)** — before using a Pi: `update-fleet-state.sh <pi> status testing`, bot name in a note. On release: restore `main`, restart pm2 as pi, set status `idle`. `find-available-pi.sh` returns only idle Pis, so review deploys skip claimed Pis. Never golden idea02; leave each Pi's isolated store, `mdns:false` and local `config.yaml` untouched; never take more than one Pi down at a time.
6. **Engine (Axle)** — stop the pm2 Engine as pi before testing; test from a separate checkout (not the deployed tree) kept off the fleet store; restore `main` and restart pm2 before release. `IDEA_NETWORK_TESTS` off unless an issue asks. `store-template.json` never touched.
7. **Sudoers** — a Dev Bot may install its PR's `11-engine-files` via `installEngineSudoers` on a Pi it has claimed and must restore `main`'s version before release. Golden idea02 sudoers stays with Atlas.
8. **App (Kid)** — builds on any claimed ARM64 pool Pi (not idea02), each checked with `docker manifest inspect`. Before release: `docker compose down -v` for every harness project, remove test images, no test disk left mounted. `dd` test-disk writes stay with Atlas on idea03 only (idea#139).
9. **Console (Pixel)** — unit tests and typecheck off-Pi against the mock store. A dev Console pointed at a Pi's Engine counts as using that Pi and needs a claim. Command testing never targets idea02.
10. **Follow-ups after merge**
    - Axle, Pixel, Kid: each opens a PR rewriting their repo's `AGENTS.md` ("You are Grok Build…" wording).
    - Koen then updates the Bot descriptions. Flagged lines: **Atlas** — teardown `pnpm test:full` via script; GitHub Actions cron. **Kid** — trigger Grok Build; idea03-only builds. **Axle** — trigger Grok Build. **Pixel** — trigger Grok Build; non-existent `scripts/deploy-fleet.sh`.
    - Atlas: `idea-setup.sh` default/opt-in flag; stop idea02 runner + `runner: parked`; health-check scheduler.

---

**Related:** idea#147 · idea#107 (fleet script stubs) · idea#118 (dedicated golden) · idea#139 (hardware test disks)
