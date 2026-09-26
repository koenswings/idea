# IDEA Platform Tools

Shared scripts used by Grok Build and Bots across all IDEA work.

## fleet/

Fleet management scripts. Ops Bot calls these — all Pi allocation, deployment, and health logic lives here, not in Bot descriptions.

| Script | Purpose |
|--------|---------|
| `idea-setup.sh` | Discover all `idea*` Pis via Tailscale, install Grok Build, register GitHub Actions runner, initialise fleet-state.json |
| `find-available-pi.sh <domain>` | Return first idle Pi matching domain from fleet-state.json |
| `deploy.sh <pi> <component> <repo> <branch>` | Full deploy sequence (engine/console/app-disk) |
| `teardown.sh <pi>` | Reverse deploy, restore main, mark Pi idle |
| `update-golden.sh <component> <version>` | Update golden Pi to new version of a component |
| `set-golden-pi.sh` | Designate new golden Pi if current unavailable |
| `check-fleet-health.sh` | HTTP check all deployed Pis, return JSON status |
| `update-fleet-state.sh [--create] [--json\|--null] <pi> <field> [<value>]` | Locked (flock), atomic read-modify-write of one field in fleet-state.json. `--null` clears a field to JSON `null`, `--json` stores a typed JSON value, unknown Pis are refused unless `--create`. Audit line goes to `audit/` next to `STATE_FILE`. **Implemented**; `selftest.sh` exercises it against a temp copy |

Status: stub files. Full implementation in Phase 2.

Until a second Pi exists, `idea02` is also the review Pi: “golden” is a recorded state, not a separate machine. When idle (`status: idle`, `pr: null`, `role: review`), its `version` records the mains it runs; Ops (Atlas) updates it after every merge to `main`. With multiple Pis, restore the dedicated golden Pi (`role: golden`, `status: golden`, `version: main@<sha>`), which is never used for review.

## quality/

Quality scan and version monitoring scripts. Lead Bot and App Dev Bot call these.

| Script | Purpose | Status |
|--------|---------|--------|
| `quality-scan.sh` | Full/PR quality gate: structure, hygiene, docs currency, domain bake-ins, staleness (full only), domain tests via Pi selection. JSON report on stdout; audit line in `audit/`. | **Implemented** |
| `check-app-versions.sh` | Read app.yaml files, query upstream APIs, return JSON diff of new versions | Stub (Phase 2) |
| `selftest.sh` | Runs `quality-scan.sh` against `testdata/` fixtures (structural; no Pi required) | **Implemented** |

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
