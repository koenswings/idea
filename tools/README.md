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
| `update-fleet-state.sh <pi> <field> <value>` | Atomic read-modify-write of fleet-state.json |

Status: stub files. Full implementation in Phase 2.

## quality/

Quality scan and version monitoring scripts. Lead Bot and App Dev Bot call these.

| Script | Purpose |
|--------|---------|
| `quality-scan.sh` | Structural checks across repos — source files in docs/, AGENTS.md freshness, TODO count. Returns JSON report. |
| `check-app-versions.sh` | Read app.yaml files, query upstream APIs, return JSON diff of new versions |

Status: stub files. Full implementation in Phase 2.

## pdf/

| Script | Purpose |
|--------|---------|
| `md-to-pdf.py` | Markdown to PDF with clickable two-level ToC via Chromium headless |

Installation: `apt-get install -y python3-markdown` (chromium already on Pi).
