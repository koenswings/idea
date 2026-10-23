# IDEA Documentation Rules

**Status:** Approved (Koen merged #189, 14 October 2026) · **Maintained by:** Atlas (with Steve)

These rules **extend** the rules that already apply in this repo. They do not replace them:

- [`proposals/README.md`](../proposals/README.md): designs and decisions, format and lifecycle.
- [`docs/README.md`](README.md): authoritative, as-implemented documentation.
- [`CONTEXT.md`](../CONTEXT.md): product knowledge (Engine, Console, App Disks).

Where this file and those files seem to disagree, those files win and this file gets fixed.
The migration in §3/§4 has been carried out (#187, #188, #190, #191); §3 lists the
current locations.

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

## 3. Inventory (current locations)

Recent documents (≈ last 3 weeks). "box" = only on Koen's Grok Bot box.

| Document | Location | Done in |
|---|---|---|
| IDEA Field Support Channel – Design | `proposals/2026-10-14-field-support-channel.md` (+ `proposals/2026-10-14-field-support-channel/` for PDF, diagram, build) | #188 |
| Teacher tutorial | `docs/manuals/teachers/teacher-tutorial/` | #191 |
| Lesson manuals (Form 3 variables, Grade 5A fractions) | `docs/manuals/teachers/lesson-manuals/` | #191 |
| IDEA Field Install Manual: School Server | `docs/manuals/install/install-manual-school-server/` | #191 |
| IDEA Field Install Manual: Classroom Computer | `docs/manuals/install/install-manual-classroom-computer/` | #191 |
| IDEA Kit: Accounts and Passwords (private) | `docs/manuals/install/accounts-and-passwords/` | #296 |
| Router setup scripts | `docs/manuals/install/scripts/` | #191 |
| Remote access guide (field engineer) | `docs/manuals/field/remote-access-guide/` | #191 |
| House style module | `docs/house-style/` (single copy) | #191 |
| Demo accounts (internal) | out of `docs/` (contains passwords) | — |
| wizardly-hugle tutorial notes (DONE.md) | evidence: issue comment, not `docs/` | — |
| Store growth proposal | `proposals/2026-10-13-store-growth.md` | #190 |
| Store compaction plan + result record (3zoqd → 2VroE, 2026-10-13) | `docs/ops/store-compaction-devpool.md` (runbook); raw evidence stays on the box | #190 |
| Engine key / root helper designs | `proposals/design-per-pi-engine-key.md`, `proposals/design-school-engine-key.md`, `proposals/design-root-helper.md` (dated rename optional) | #186 |
| Engine deploy on a pool Pi (option 2, store-identity kept) | `docs/ops/engine-deploy-pool-pi.md` + `tools/fleet/deploy-engine-pi.sh` | this PR |
| Boot recovery runbook | `docs/ops/boot-recovery.md` | #187 |
| Avahi hostname clash (proposed fix) | `proposals/2026-10-13-avahi-hostname-clash.md` | #187 |
| Tailscale `tag:idea` decision | `proposals/2026-10-13-tailscale-single-fleet-tag.md` | #187 |
| Fleet store ID record | `fleet-state.json` (data, not a document) | #185 |
| Engine/Console/app technical docs and proposals | their own repos | — |
| Audit 2026-10-13, r86q diagnostics | box / issue (evidence) | — |
| Box working copies (store design, support channel design) | box; delete now that the idea PRs have merged | — |

There is no `docs/store/` any more.

**Earlier tutorials for Marco:** not found in the `idea` repo (main, branches, PRs or
history). The only teacher tutorial in Git is agent-app-dev `docs/tutorial-justice/`.

## 4. Migration plan (done)

1. Do not merge agent-app-dev #14/#15; one idea PR moves their contents and the house style
   into `docs/manuals/…` and `docs/house-style/`, fixes each `build.py` path, rebuilds every
   PDF and checks for secrets; then #14/#15 are closed with a pointer.
2. One idea PR moves `docs/store/STORE-GROWTH-PROPOSAL.md` to `proposals/` and settles the
   compaction plan/result per §3.
3. #187 is adjusted per §3 (Tailscale decision and avahi proposal to `proposals/`).
4. `docs/INDEX.md` and `proposals/INDEX.md` are updated in each of those PRs.
