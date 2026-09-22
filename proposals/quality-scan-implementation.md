# Proposal: Implement `tools/quality/quality-scan.sh`

**Author:** Steve (Lead Bot)
**Date:** 2026-09-22
**Revised:** 2026-09-22 (Design Review + Koen: single-Pi golden exception; no INDEX grace)
**Status:** Ready for proposal PR — Design Review complete; Koen decisions locked
**Spec source:** `docs/grok-bot-setup.md` §5 at `d05695a` (rules in 5.1, PR gate in 5.2, scheduled scan in 5.3)
**Affects:** `koenswings/idea` (primary); Dev Bot QC workflows; Lead Bot post-merge / Monday routines; Ops audit path

---

## 1. Problem

`tools/quality/quality-scan.sh` and `tools/quality/check-app-versions.sh` are Phase 2 stubs. Section 5 defines one coherent rule set and requires Bots to invoke this script for both the PR gate and the scheduled scan. Until the script exists, Lead and Dev Bots cannot enforce quality deterministically and must not reimplement the checks.

---

## 2. Goals

1. Replace the stub with a real `quality-scan.sh` that implements **all** §5.1 rules (plus domain-specific bake-ins agreed in Design Review).
2. Support two invocation modes that share the same check engine:
   - **PR gate** (`--pr`) — §5.2
   - **Scheduled / full scan** — §5.3
3. Emit a single structured JSON report on stdout for Bot consumption.
4. Append one audit event line to `audit/audit-<year>.jsonl` after every run.
5. Stay bash + `jq` + git (and repo-native test runners only where tests are required). No LLM logic inside the script.

Out of scope: implementing `check-app-versions.sh` (Kid calls it separately on Mondays). App compose rules (x-app-version, named volumes, health checks, ports ≥3000, ARM64 manifest) stay in Kid’s PR QC / harness — not in this script.

---

## 3. Affected domains

| Domain | Impact |
|--------|--------|
| **idea (Lead / tools)** | Owns the script; scheduled scan; issues from report; audit log |
| **Engine (Axle)** | Tests + structure/hygiene/docs; `store-template.json` hard error |
| **Console (Pixel)** | Tests + structure/hygiene/docs; ID-keyed `<For>`; no broad store subscriptions |
| **Apps (Kid)** | Harness on full scan when scheduled; app repos in scan set; compose rules **not** in this script |
| **Ops (Atlas)** | `find-available-pi.sh` for test hosts; audit path; likely implements script on `idea` |

---

## 4. Recommended approach

### 4.1 Location and CLI

Path: `koenswings/idea/tools/quality/quality-scan.sh` (not under `tools/fleet/`). Same PR updates §2.4 of `docs/grok-bot-setup.md` so quality scripts are listed only under quality tools.

```bash
# Full / scheduled scan (default: all IDEA repos)
./tools/quality/quality-scan.sh
./tools/quality/quality-scan.sh --repos idea,agent-engine-dev,agent-console-dev

# PR gate
./tools/quality/quality-scan.sh --pr --repo <name> --base <sha> --head <sha>

```

Default repo set: `idea`, `agent-engine-dev`, `agent-console-dev`, `agent-app-dev`, `app-kolibri`, `app-nextcloud`, `app-kiwix`, `app-milkwise`.

Exit codes: `0` = clean; `1` = violations; `2` = script error.

### 4.2 Modes vs checks

| Check | `--pr` | Full scan |
|-------|:------:|:---------:|
| Tests | Yes — via Pi selection (same rules as full) | Yes — via Pi selection below |
| Structure / hygiene / docs currency | Yes | Yes |
| Domain bake-ins (store-template, Console `<For>`, …) | Yes | Yes |
| Staleness | **No** | **Yes** |

### 4.3 Where full-scan tests run (Koen + Design Review)

1. Call `find-available-pi.sh <domain>` (`engine` / `console` / `app-dev`).
2. If an idle Pi is returned → run that domain’s tests there.
3. If **no** idle Pi because other Pis are busy → record `tests_skipped` with reason (`no_idle_pi`). **Do not** fall back to golden in this case.
4. **Single-Pi exception (Koen):** if `fleet-state.json` contains **exactly one** Pi, that Pi may be used for tests even when its role is `golden`. This keeps a one-Pi fleet usable as a continuous dev/test platform.
5. Never use golden when the fleet has more than one Pi.

There is no `--skip-tests` flag: both modes attempt tests under the Pi-selection rules.

### 4.4 Check implementations (deterministic)

**Tests**

- Engine: `pnpm test:full` on selected Engine Pi.
- Console: `pnpm test` + `pnpm typecheck` on selected Console Pi.
- Apps: App Harness smoke for apps that have harness entries, on selected app-dev Pi; otherwise `tests_skipped` with `no-harness`.

**Structure**

- No `docs/**/*.{ts,js,tsx,jsx}`
- No `src/**/*.md`
- No test-like files under `src/` (`*.{test,spec}.{ts,js,tsx,jsx}`)

**Code hygiene**

- Hardcoded credentials (conservative patterns; exclude `process.env` / `import.meta.env`)
- `console.log` in production `src/` (exclude mocks/tests)
- Commented-out blocks >5 lines → **`warning`** initially (Design Review consensus)
- `TODO`/`FIXME` without `#N` or issue URL → error

**Domain bake-ins**

- Engine: any change to `store-template.json` → **error** (never regenerate/modify)
- Console: `<For>` not ID-keyed → **error**; broad store subscriptions → **error**; no CDN / external CSS frameworks

**Documentation currency — no grace period (Koen)**

- Every file under each repo’s `docs/` must be listed in that repo’s `docs/INDEX.md` when `docs/` exists. Missing `INDEX.md` while `docs/` has files → **error** immediately (no first-Monday grace list).
- `--pr`: new `docs/` file requires `docs/INDEX.md` changed in the same range; build/test/deploy path changes require `AGENTS.md` changed when that file exists.

**Staleness (full scan only)**

- Every file under any `docs/`: if last commit to the doc is >30 days older than related-source tip → `docs-review`.
- Related source v1:
  - Default: `src/` + behaviour configs
  - Apps: include `compose.yaml`, `app.yaml`, Dockerfiles
  - Engine: `src/`, `scripts/`, deploy paths AGENTS.md tracks
  - Console: `src/`, `scripts/deploy-fleet.sh`
- `AGENTS.md` >14 days older than build-related tip → `docs-review`

### 4.5 JSON report + audit

Unchanged from prior draft: one JSON object on stdout; `findings[].label` is `quality` or `docs-review`; Engine test failure on full scan → `severity: "critical"` (Lead notifies Koen first). Audit line via `BOT_NAME` env after each run.

### 4.6 Implementation ownership

After proposal merge: single PR to `koenswings/idea` implementing the script + §2.4 cleanup + fixtures/selftest. **Atlas** implements the script PR on `koenswings/idea` after this proposal merges.

---

## 5. Design Review synthesis (locked)

| Decision | Source |
|----------|--------|
| `tools/quality/` only; fix §2.4 | Atlas, all |
| Full-scan tests: idle Pi via `find-available-pi.sh`; never golden when multi-Pi busy | Atlas, Kid, Axle, Pixel |
| Single-Pi fleet: golden may run tests | **Koen** |
| No idle Pi (busy fleet): `tests_skipped`, not golden | Atlas + Koen |
| Commented-block: warning | All |
| No INDEX grace — update INDEX immediately | **Koen** |
| `check-app-versions.sh` separate | Kid |
| Compose/App Disk rules stay in Kid QC | Kid, Axle, Pixel |
| `store-template.json` touch = error | Axle |
| Console `<For>` ID-keyed + no broad store subs = error | Pixel |
| Staleness related-source includes app compose/app.yaml/Dockerfiles | Kid |
| Implementer after merge: Atlas | **Koen** |
| `--pr` runs domain tests in script | **Koen** |
| No `--skip-tests` flag | **Koen** |

---

## 6. Alternatives considered

| Option | Why not |
|--------|---------|
| Separate PR vs scan scripts | §5 wants one rule set / one script |
| Fall back to golden whenever idle is empty | Rejected — only allowed when fleet size is 1 |
| INDEX grace list for first Monday | Rejected by Koen — update INDEX now |
| Fold compose/ARM64 rules into this script | Rejected — Kid’s QC |

---

## 7. Decisions (Koen, 2026-09-22)

1. **Implementer after merge:** Atlas
2. **`--pr` mode:** `quality-scan.sh` also runs domain tests (not structural-only)
3. **`--skip-tests`:** not kept — full and `--pr` runs attempt tests under the Pi-selection rules; no docs-only skip flag

---

## 8. Success criteria

- `--pr` and full scan share one engine; JSON + audit line work
- Staleness covers **all** `docs/` files; `AGENTS.md` 14-day rule works
- Multi-Pi: never test on golden; single-Pi: may test on the only Pi even if golden
- Busy multi-Pi with no idle: `tests_skipped`, not golden fallback
- Missing `docs/INDEX.md` entries fail immediately
- Stub gone; `tools/README.md` marked implemented

---

## 9. References

- `docs/grok-bot-setup.md` §5 (`d05695a`)
- Design Review thread 2026-09-22 (Atlas, Kid, Axle, Pixel)
- Koen revision: single-Pi golden exception; no INDEX delay
