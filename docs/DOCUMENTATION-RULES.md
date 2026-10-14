# IDEA Documentation Rules

**Status:** Proposed (for Koen's approval) · **Maintained by:** Steve / Atlas · 14 October 2026

Where each document lives, how it is named and built. Nothing has been moved yet: the
table in §3 is the proposed migration, executed only after Koen approves it.

## 1. Rules

1. **Product and user-facing documentation lives in the `idea` repo**, under `docs/`:

   | Folder | What goes there |
   |---|---|
   | `docs/teachers/` | Teacher tutorials and lesson manuals (per-lesson subfolders) |
   | `docs/install/` | Install manuals (school server, client Pi) and their helper scripts |
   | `docs/field/` | Guides for field/support people (e.g. remote access guide) |
   | `docs/design/` | Approved and proposed cross-component designs |
   | `docs/ops/` | Fleet operations runbooks (boot recovery, avahi clash, store compaction) |
   | `docs/decisions/` | Decision records (one file per decision, dated) |
   | `docs/house-style/` | The one house style module (`housestyle.py`, `house.css`, README) |

   The existing `proposals/` folder stays for proposals not yet approved; once approved a
   design moves (or is copied as final) to `docs/design/`.
2. **Component-internal technical docs stay in their own repo**: Engine, Console and each
   app repo keep their README, `docs/` (architecture, commands, scripts) and `proposals/`
   that concern only that component.
3. **The box is never the final location.** A document that exists only on the box is a
   draft. Evidence and raw test output (logs, JSON, screenshots of test runs, diag dirs)
   stay on the box or are attached/summarised in GitHub issues; they are not committed to
   `docs/`.
4. **One house style module, in one place** (`idea/docs/house-style/`). No copies in other
   repos or document folders. Build scripts locate it relative to the repo, or via the
   `IDEA_HOUSE_STYLE` environment variable.
5. **Source, build script and PDF are committed together** in one folder:
   `<name>.md` (+ chapters/diagrams), `build.py`, `<name>.pdf`. The PDF is rebuilt in the
   same commit as any source change. No `__pycache__`, no intermediate HTML.
6. **Naming:** kebab-case, descriptive full names, for folders and files
   (`field-support-channel-design.md`, `install-manual-school-server.md`). No `DESIGN.md`,
   no person names in folder names (use the role: `field/remote-access-guide`). The PDF
   title metadata carries the full human title (e.g. "IDEA Field Support Channel – Design").
7. **Status line on top:** Draft / Proposed / Approved YYYY-MM-DD, plus owner.
8. **Secrets never included:** no keys, auth keys, passwords, tokens. Demo-account
   passwords go in an internal note outside `docs/`. A deliberate exception (e.g. a
   Tailscale IP a field engineer needs) is listed in the document's README.
9. **Indexes:** every new or moved document gets an entry in `docs/INDEX.md`.

## 2. House style move: what breaks

Moving `docs/house-style/` from `agent-app-dev` (PRs #14/#15) to `idea/docs/house-style/`:

- Every `build.py` today does `sys.path.insert(0, HERE/../house-style)` or uses a local
  copy (`/workspace/support-channel-design/house-style`, `/workspace/teacher-manuals/house-style`).
  After the move those imports still work **if the documents move with it** to
  `idea/docs/<folder>/<doc>/` (two levels deep: path becomes `../../house-style`). Each
  `build.py` needs that one-line path change; `field-support-channel/build.py` already
  searches `IDEA_HOUSE_STYLE`, `./house-style` and `../../house-style`.
- Anything left in `agent-app-dev` that builds PDFs would need a checkout of `idea` and
  `IDEA_HOUSE_STYLE` set. Proposal: nothing user-facing stays there, so nothing breaks.
- `house.css` references to fonts/images must be relative to the module folder (check
  during the move). Box copies of the module are deleted after the move.

## 3. Inventory and proposed locations

Recent documents (≈ last 3 weeks). "box" = only on Koen's Grok Bot box.

| Document | Current location | Proposed location |
|---|---|---|
| IDEA Field Support Channel – Design | idea PR #188 `docs/design/field-support-channel/` | same (already compliant) |
| Teacher tutorial (Justice) | agent-app-dev `docs/tutorial-justice/` (main) + PR #14 build/fixes | `idea/docs/teachers/teacher-tutorial/` |
| Demo accounts (internal) | agent-app-dev `docs/tutorial-justice/demo-accounts-internal.md` | out of `docs/`; internal note (contains passwords) |
| House style module | agent-app-dev PR #14/#15 `docs/house-style/`; box copies | `idea/docs/house-style/` (single copy) |
| Install manual 1 – school server | agent-app-dev PR #15 `docs/install-guides/manual-1-school-server.*` | `idea/docs/install/install-manual-school-server/` |
| Install manual 2 – client Pi 400 | agent-app-dev PR #15 `docs/install-guides/manual-2-client-pi400.*` | `idea/docs/install/install-manual-client-pi400/` |
| Router setup scripts | agent-app-dev PR #15 `docs/install-guides/scripts/` | `idea/docs/install/scripts/` |
| Justice remote access guide | agent-app-dev PR #15 `docs/justice-access/` | `idea/docs/field/remote-access-guide/` |
| Lesson manuals (Form 3 variables, Grade 5A fractions) | agent-app-dev PR #15 `docs/lesson-manuals/`; sources box `/workspace/teacher-manuals/` | `idea/docs/teachers/lesson-manuals/` |
| wizardly-hugle tutorial notes (DONE.md) | agent-app-dev PR #15 `docs/duration-evidence/…` | evidence: issue comment / box, not `docs/` |
| Store growth proposal, compaction plan + result | idea `docs/store/` (main, #186) | `idea/docs/ops/store/` (plan/result) + `docs/design/` (proposal) |
| Engine key / root helper designs | idea `proposals/design-*.md` (main, #186) | `idea/docs/design/` once approved |
| Boot recovery, avahi clash runbooks | idea PR #187 `docs/ops/` | same; rename kebab-case |
| Tailscale tag:idea decision | idea PR #187 `docs/ops/TAILSCALE-DECISION.md` | `idea/docs/decisions/2026-10-tailscale-tag-idea.md` |
| Fleet store ID record | idea PR #185 (fleet state) | same (data, not a document) |
| Store history r86q | agent-engine-dev `docs/STORE_HISTORY_R86Q.md` | stays (Engine-internal) |
| Engine PI_FLEET / ARCHITECTURE / COMMANDS / SCRIPTS | agent-engine-dev `docs/` | stays |
| Duration-test proposals + PDFs | agent-engine-dev `proposals/` | stays (component) |
| Console architecture, proposals | agent-console-dev `docs/`, `proposals/` | stays |
| App READMEs, Nextcloud files-disk | app repos `README.md`, `docs/` | stays |
| Audit 2026-10-13 (AUDIT.md, branch archive list, proof plan) | box `/workspace/audit-20261013/` | box / issue (evidence) |
| r86q diagnostics (NOTES.md + logs) | box `/workspace/r86q-diag/` | box / issue (evidence) |
| Store design working copy (PROPOSAL.md) | box `/workspace/store-design/` | delete box copy (in idea `docs/store/`) |
| Support channel design working copy | box `/workspace/support-channel-design/` | delete box copy after #188 merges |

**Earlier tutorials for Marco:** not found in the `idea` repo (main, branches, PRs or
history). The only teacher tutorial in Git is agent-app-dev `docs/tutorial-justice/`
(on main), with build fixes in PR #14.

## 4. Migration plan (after approval)

1. Merge or close agent-app-dev #14/#15 as Koen prefers; then one idea PR moves the
   documents and the house style per §3 and fixes each `build.py` path.
2. Rebuild every PDF from the moved sources in that PR; verify no secrets.
3. Leave a pointer README in `agent-app-dev/docs/` to the new locations.
4. Update `docs/INDEX.md`.
