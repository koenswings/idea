**Status:** Authoritative · **Maintained by:** Koen / Steve (manuals: Marco; ops docs: Atlas) · 14 November 2026

# docs/: IDEA's documentation as it is today

This folder helps you find IDEA's current documentation. Everything here is written for what is running now, not for plans. For the full list, with every file and who keeps it, see [`INDEX.md`](INDEX.md).

## The rule

This section explains what may go in this folder. **Docs here describe only what is implemented.** If something is not live yet, its design and decision history go in [`../proposals/`](../proposals/README.md). Product knowledge (Engine, Console, App Disks) is in [`../CONTEXT.md`](../CONTEXT.md). The placement, naming, build and secrets rules are in [`DOCUMENTATION-RULES.md`](DOCUMENTATION-RULES.md).

An authoritative doc is updated in the **same PR** as the change that makes it true. When a design reaches `Implemented`, its result moves here; the proposal keeps the decision.

## Manuals for teachers, operators and the field

This section lists the user-facing manuals and their current PDF versions. Each manual lives in `manuals/<audience>/<name>/` with its source, build script and pictures. Older PDFs are in that folder's `superseded/`.

| Manual | Current PDF | Folder |
|---|---|---|
| IDEA for Teachers: Tutorial | v2.2 | [`manuals/teachers/teacher-tutorial/`](manuals/teachers/teacher-tutorial/) |
| Lesson manuals: Grade 5A — Add and subtract fractions, Form 3 — Variables and expressions | v1.3 | [`manuals/teachers/lesson-manuals/`](manuals/teachers/lesson-manuals/) |
| IDEA for Operators: Tutorial | v1.1 | [`manuals/operators/operator-tutorial/`](manuals/operators/operator-tutorial/) |
| IDEA Field Install Manual: School Server | v1.8 | [`manuals/install/install-manual-school-server/`](manuals/install/install-manual-school-server/) |
| IDEA Field Install Manual: Classroom Computer | v2.6 | [`manuals/install/install-manual-classroom-computer/`](manuals/install/install-manual-classroom-computer/) |
| IDEA Kit: Accounts and Passwords (private, for the install team) | v1.1 | [`manuals/install/accounts-and-passwords/`](manuals/install/accounts-and-passwords/) |
| Router setup scripts (used by the install manuals) | — | [`manuals/install/scripts/`](manuals/install/scripts/) |
| IDEA Demo Server: Remote Access | v1.2 | [`manuals/field/remote-access-guide/`](manuals/field/remote-access-guide/) |
| IDEA kit: a note for your school | v1.0 | [`manuals/field/school-handover-note/`](manuals/field/school-handover-note/) |

At a school, people reach the Console at `http://idea.local` or `http://<sticker>.local` (the name on the box's sticker). The manuals use only those two addresses.

All PDFs use the single IDEA house style in [`house-style/`](house-style/).

## How IDEA is set up and run

This section points to the docs about the platform and day-to-day operations.

| Doc | What it covers |
|---|---|
| [`grok-bot-setup.md`](grok-bot-setup.md) | How the IDEA team works on Grok Bot: bots, fleet scripts, test claims, quality control and routines |
| [`RELEASES.md`](RELEASES.md) | How device images are released in two stages: build a generic image, then personalise it |
| [`ops/security-overview.md`](ops/security-overview.md) | Security from the ops side (draft); contains no secret values |
| [`ops/tailscale-field-access.md`](ops/tailscale-field-access.md) | How IDEA staff reach schools and devices remotely |
| [`ops/zimbabwe-2026-10-deployment.md`](ops/zimbabwe-2026-10-deployment.md) | The October 2026 Zimbabwe kit deployment (draft) |
| [`ops/engine-deploy-pool-pi.md`](ops/engine-deploy-pool-pi.md) | Deploying the Engine on a test-pool device |
| [`ops/boot-recovery.md`](ops/boot-recovery.md) | What comes back after a reboot, and how to recover mounts |
| [`ops/store-compaction-devpool.md`](ops/store-compaction-devpool.md) | Runbook for compacting the test-pool store |

The field support channel design is a proposal, so it lives in [`../proposals/2026-10-14-field-support-channel/`](../proposals/2026-10-14-field-support-channel/).

## Keeping this page current

This section says who updates what. When you add, rename or version a doc, update [`INDEX.md`](INDEX.md) in the same PR, and this page too if the change affects a row above. Atlas looks after `ops/` and the folder rules with Steve; Marco looks after the manuals.
