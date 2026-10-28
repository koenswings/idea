# IDEA Platform Tools

Shared scripts used by Grok Build and Bots across all IDEA work.

## fleet/

Fleet management scripts. Ops Bot calls these — all Pi allocation, deployment, and health logic lives here, not in Bot descriptions.

| Script | Purpose |
|--------|---------|
| `strip-cloud-init-sudoers.sh` | Remove cloud-init `pi ALL=(ALL) NOPASSWD:ALL` so Engine sudoers win (idea#153). **Implemented.** |
| `find-available-pi.sh <domain>` | Return first idle Pi matching domain from fleet-state.json |
| `deploy.sh <pi> <component> <repo> <branch>` | Full deploy sequence (engine/console/app-disk) |
| `deploy-engine-pi.sh <tip> [--fetch <branch>] [--yes]` | Option-2 Engine deploy on ONE pool Pi (run via `ssh <pi> bash -s`): keeps config.yaml, pm2.config.cjs and store-identity/ across the checkout, aborts before pm2 restart if store-url.txt is not 2VroE; applies the Engine's DHCP vendor class (idea#284) after the build. **Implemented**; tests: `deploy-engine-pi.test.sh`. Runbook: `docs/ops/engine-deploy-pool-pi.md` |
| `build-console-pi.sh [--dir <console dir>]` | Builds the Console on a Pi (run via `ssh <pi> bash -s`) and keeps the optional `dist/hidden-instances.json` hide list (agent-console-dev#166, idea#212) byte for byte across `vite build`, which empties dist/. If the file is absent, nothing is created. **Implemented**; tests: `build-console-pi.test.sh` |
| `teardown.sh <pi>` | Reverse deploy, restore main, mark Pi idle |
| `update-golden.sh <component> <version>` | Update golden Pi to new version of a component |
| `set-golden-pi.sh` | Designate new golden Pi if current unavailable |
| `check-fleet-health.sh` | Health-check every Pi in fleet-state (Tailscale ssh, Console on `console_port` (default :8080), pm2 engine, versions, disk, DHCP vendor-class drop-in + kit LAN lease in 10.42.0.2-.9 (idea#284; `--dhcp` also fails on claimed/kit Pis)); JSON out, exit 1 if unhealthy. Tests: `check-fleet-health.test.sh` |
| `update-fleet-state.sh [--create] [--json\|--null] <pi> <field> [<value>]` | Locked (flock), atomic read-modify-write of one field in fleet-state.json. `--null` clears a field to JSON `null`, `--json` stores a typed JSON value, unknown Pis are refused unless `--create`. Audit line goes to `audit/` next to `STATE_FILE`. **Implemented**; `selftest.sh` exercises it against a temp copy |
| `duration-test-claim.sh` | Claim N pool Pis (idea01/03/04 only; refuse golden idea02) for a duration-walk id via `update-fleet-state.sh` (idea#166). **Implemented**; offline tests in `duration-test-ops.test.sh` |
| `duration-test-release.sh` | Clear duration-walk claims → idle; print unique-store + mDNS-off restore checklist (see also `teardown.sh`) |
| `duration-test-health-wrap.sh` | `before`/`after` wrapper: `check-fleet-health.sh --origin` + optional intentional `PAUSED` around reboot churn |
| `DURATION_TESTS.md` | Ops checklist for duration walks: claim → run → reboot baseline → teardown → health clear |

Status: `find-available-pi`, `update-fleet-state`, `check-fleet-health`, `strip-cloud-init-sudoers`, and duration-test Ops hooks (`duration-test-*.sh`) and `deploy` / `teardown` / `update-golden` / `set-golden-pi` (idea#107; shared helpers in `fleet-lib.sh`, offline tests in `fleet-scripts.test.sh`) are implemented. The four idea#107 scripts are dry runs unless `--yes` is passed, print one JSON result, write state only through `update-fleet-state.sh`, and refuse `idea02`, the wh host, golden/production/kit Pis, hold/paused Pis, other bots' claims, a fleet PAUSED/HOLD and Pis above 75 °C. `--ignore-fleet-hold` skips **only** the fleet-wide HOLD/PAUSED check for one run (warning on stderr, `fleet_hold_ignored: true` + `fleet_hold_flags` in the JSON; the files are never touched); every per-Pi refusal and the temperature check still apply. `idea-setup.sh` was removed (idea#273): new Pis are built with the Engine's `build-engine`.

`idea02` is the dedicated golden Pi (`role: golden`): it always runs the latest merged `main`, keeps MilkWise as a real workload, and is never used for PR review. Its `version` records the mains it runs (for example `engine main@<sha>, console main@<sha>`) and its `status` stays `idle`; `role: golden` is what excludes it from review allocation. Review Pis (currently `idea03`, `role: review`) are picked by `find-available-pi.sh`. After every merge to `main`, Ops (Atlas) moves the golden Pi to `main` and updates its `version` (`update-golden.sh <component> main --yes`, idea#107). This dedicated-golden model (idea#118) replaces the temporary single-Pi rule from idea PR #112.

## quality/

Quality scan and version monitoring scripts. Lead Bot and App Dev Bot call these.

| Script | Purpose | Status |
|--------|---------|--------|
| `quality-scan.sh` | Full/PR quality gate: structure, hygiene, docs currency, domain bake-ins, staleness (full only), domain tests via Pi selection. JSON report on stdout; audit line in `audit/`. | **Implemented** |
| `check-app-versions.sh` | Read app.yaml monitors, query DockerHub / http-scrape, return JSON updates (idea#88) | **Implemented** |
| `selftest.sh` | Runs `quality-scan.sh` against `testdata/` fixtures (structural; no Pi required) | **Implemented** |
| `lib-static-assets.sh` | `is_static_doc_asset`: docs/ files that are static assets (stylesheets, images, PDFs, sample JSON/YAML/CSV data, `styles/` `assets/` `screenshots/` `superseded/` folders), skipped by `docs.missing_from_index` and `staleness.doc` (idea#308). Markdown is always checked. | **Implemented** |

```bash
./tools/quality/quality-scan.sh
./tools/quality/quality-scan.sh --repos idea,agent-engine-dev
./tools/quality/quality-scan.sh --pr --repo agent-engine-dev --base <sha> --head <sha>
./tools/quality/selftest.sh
```

## pdf/

| Script | Purpose |
|--------|---------|
| `md-to-pdf.py` | Markdown to PDF with clickable two-level ToC via Chromium headless |

Installation: `apt-get install -y python3-markdown` (chromium already on Pi).

## Checkout paths

Fleet and quality scripts assume the locked nested layout (Koen 2026-09-24; apps under agent-app-dev):

- Pi agent repos: `/home/pi/idea/agents/<agent-*-dev>`
- Pi App repos: `/home/pi/idea/agents/agent-app-dev/<app-*>`
- Local: same nesting under `${IDEA_ROOT}/` (`quality-scan.sh --repo-root` overrides the parent of `agents/`)
- Engine pm2 cwd: `/home/pi/idea/agents/agent-engine-dev`
- Console `consolePath`: `/home/pi/idea/agents/agent-console-dev/dist`

See `proposals/pi-checkout-layout.md` and `docs/grok-bot-setup.md` §2.3.1.
