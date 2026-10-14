# IDEA Documentation Rules

**Status:** Proposed (for Koen's approval) · **Maintained by:** Atlas (with Steve) · 14 October 2026

These rules **extend** the rules that already apply in this repo. They do not replace them:

- [`proposals/README.md`](../proposals/README.md): designs and decisions, format and lifecycle.
- [`docs/README.md`](README.md): authoritative, as-implemented documentation.
- [`CONTEXT.md`](../CONTEXT.md): product knowledge (Engine, Console, App Disks).

Where this file and those files seem to disagree, those files win and this file gets fixed.
Nothing has been moved yet: the table in §3 is the proposed migration, executed only after
Koen approves it.

## 1. The existing rules (unchanged)

1. **`proposals/` holds designs and decisions.** File: `proposals/<YYYY-MM-DD>-<topic>.md`,
   with the header `**Author:**` / `**Date:**` / `**Status:** Draft | Approved | Declined |
   Superseded by <link>`. Koen merging the PR = approved. After implementation the proposal
   stays unchanged as the record of *why*. A decision record (e.g. "Tailscale: one
   `tag:idea` key") is a proposal file too. There is **no** `docs/design/` and **no**
   `docs/decisions/`. Every proposal gets an entry in `proposals/INDEX.md`.
2. **`docs/` is authoritative**: it describes only what is implemented, it is updated in the
   same PR as the change that makes it true, and Atlas maintains it. When a design is
   implemented, its result (not the reasoning) is written here. Ops runbooks for things
   that run today (boot recovery, fleet procedures) belong here, e.g. `docs/ops/`.
   Every file under `docs/` is listed in `docs/INDEX.md` (checked by the quality scan).
3. **`CONTEXT.md`** holds product knowledge for the agents.
4. **Component-internal technical docs stay in their own repo** (Engine, Console, each app:
   README, `docs/`, `proposals/` that concern only that component).

## 2. New: user-facing manuals and the house style

5. **New category: `docs/manuals/<audience>/<name>/`** for manuals written for people
   outside the dev team: teacher tutorial, lesson manuals, install manuals, field and
   remote-access guides. Audiences: `teachers`, `install`, `field`. Manuals are authoritative
   docs: they describe the system as it is and are updated when it changes.
6. **Source, build script and PDF are committed together** in the manual's folder:
   `<name>.md` (+ chapters/diagrams), `build.py`, `<name>.pdf`. The PDF is rebuilt in the
   same commit as any source change. No `__pycache__`, no intermediate HTML. A proposal
   that has a PDF keeps its assets in `proposals/<YYYY-MM-DD>-<topic>/` next to the `.md`.
7. **One house style module, in `docs/house-style/`** (`housestyle.py`, `house.css`, README).
   No copies elsewhere. Build scripts find it relative to the repo or via `IDEA_HOUSE_STYLE`.
8. **Naming:** kebab-case, descriptive full names (`install-manual-school-server`); no
   `DESIGN.md`, no person names in folder names (use the role: `remote-access-guide`).
   The PDF title carries the full human title.
9. **Status line on top** of every document (proposals use the proposal header).
10. **No secrets:** no keys, auth keys, passwords, tokens. Demo-account passwords stay in an
    internal note outside `docs/`. A deliberate exception (e.g. a Tailscale IP a field
    engineer needs) is stated in that manual's README.
11. **The box is never the final location.** Evidence and raw test output (logs, JSON,
    test screenshots, diag dirs) stay out of `docs/`; summarise them in the GitHub issue.

## 3. Inventory and proposed locations

Recent documents (≈ last 3 weeks). "box" = only on Koen's Grok Bot box.

| Document | Current location | Proposed location |
|---|---|---|
| IDEA Field Support Channel – Design | idea PR #188 | `proposals/2026-10-14-field-support-channel.md` (+ folder for PDF/diagram/build) — done in #188 |
| Teacher tutorial | agent-app-dev `docs/tutorial-justice/` (main) + PR #14 | `docs/manuals/teachers/teacher-tutorial/` |
| Lesson manuals (Form 3 variables, Grade 5A fractions) | agent-app-dev PR #15 `docs/lesson-manuals/` | `docs/manuals/teachers/lesson-manuals/` |
| Install manual 1 – school server | agent-app-dev PR #15 `docs/install-guides/` | `docs/manuals/install/install-manual-school-server/` |
| Install manual 2 – client Pi 400 | agent-app-dev PR #15 `docs/install-guides/` | `docs/manuals/install/install-manual-client-pi400/` |
| Router setup scripts | agent-app-dev PR #15 `docs/install-guides/scripts/` | `docs/manuals/install/scripts/` |
| Remote access guide (Justice) | agent-app-dev PR #15 `docs/justice-access/` | `docs/manuals/field/remote-access-guide/` |
| House style module | agent-app-dev PR #14/#15 `docs/house-style/`; box copies | `docs/house-style/` (single copy) |
| Demo accounts (internal) | agent-app-dev `docs/tutorial-justice/demo-accounts-internal.md` | out of `docs/` (contains passwords) |
| wizardly-hugle tutorial notes (DONE.md) | agent-app-dev PR #15 | evidence: issue comment, not `docs/` |
| **Store growth proposal** | idea `docs/store/STORE-GROWTH-PROPOSAL.md` (main, via #186) | **misplaced:** a design → `proposals/2026-10-13-store-growth.md` |
| Store compaction plan | idea `docs/store/COMPACTION-PLAN-devpool.md` (main, via #186) | executed procedure → `docs/ops/` runbook is fine; the reasoning part belongs in the store-growth proposal |
| Store compaction result 2026-10-13 | idea `docs/store/COMPACTION-RESULT-devpool-20261013.md` (main, via #186) | evidence → summarise in the issue, or keep as a short ops record in `docs/ops/` (Koen to choose) |
| Engine key / root helper designs | idea `proposals/design-*.md` (main, #186) | correct folder; rename to dated `proposals/2026-10-13-<topic>.md` optional |
| Boot recovery runbook | idea PR #187 `docs/ops/BOOT-RECOVERY.md` | `docs/ops/` (correct; kebab-case name) |
| Avahi hostname clash | idea PR #187 `docs/ops/AVAHI-HOSTNAME-CLASH.md` | a proposed fix → `proposals/`; any as-run workaround stays in `docs/ops/` |
| Tailscale `tag:idea` decision | idea PR #187 `docs/ops/TAILSCALE-DECISION.md` | `proposals/2026-10-13-tailscale-single-fleet-tag.md` |
| Fleet store ID record | idea PR #185 (fleet state) | same (data, not a document) |
| Engine/Console/app technical docs and proposals | their own repos | stay |
| Audit 2026-10-13, r86q diagnostics | box | box / issue (evidence) |
| Box working copies (store design, support channel design) | box | delete after the idea PRs merge |

**Earlier tutorials for Marco:** not found in the `idea` repo (main, branches, PRs or
history). The only teacher tutorial in Git is agent-app-dev `docs/tutorial-justice/`.

## 4. Migration plan (after approval)

1. Do not merge agent-app-dev #14/#15; one idea PR moves their contents and the house style
   into `docs/manuals/…` and `docs/house-style/`, fixes each `build.py` path, rebuilds every
   PDF and checks for secrets; then #14/#15 are closed with a pointer.
2. One idea PR moves `docs/store/STORE-GROWTH-PROPOSAL.md` to `proposals/` and settles the
   compaction plan/result per §3.
3. #187 is adjusted per §3 (Tailscale decision and avahi proposal to `proposals/`).
4. `docs/INDEX.md` and `proposals/INDEX.md` are updated in each of those PRs.
