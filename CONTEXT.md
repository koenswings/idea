# CONTEXT.md — IDEA Platform

*Read this at the start of any design or architecture discussion. It gives the shared foundation of knowledge every IDEA team member needs.*

---

## The Mission

**IDEA** (Initiative for Digital Education in Africa) deploys offline computing infrastructure into rural African schools that have no internet access and no on-site IT support.

**The problem:** Schools in rural Africa have teachers and students who could benefit from digital learning tools — but have no reliable internet, limited electricity, and no technical staff. Existing solutions assume connectivity and expertise that simply isn't there.

**Our approach:** A Raspberry Pi in each school, running completely offline. No internet, no cloud account, no IT knowledge required. Teachers and students get access to curated educational applications — Kolibri for learning content, Nextcloud for file sharing, offline Wikipedia for reference — all accessible from any device on the school's local Wi-Fi.

---

## The System

### Engine

The Engine is the core software running on each school Pi. It is a Node.js/TypeScript application (not Docker) managed by pm2. It:

- Detects and processes App Disks — USB drives or SSDs containing Docker Compose apps
- Manages app instances — starts, stops, and updates Docker containers
- Synchronises state across multiple Pis using Automerge CRDTs (no central server)
- Serves the Console UI over HTTP on port 80

The Engine runs unattended. Reliability is the primary design constraint.

### Console

The Console is a Solid.js web app served by the Engine on port 80. Accessible from any browser on the school's local network at `http://<engine-hostname>.local/` or via Tailscale remotely. Two audiences: Users (browse and open apps) and Operators (manage the fleet).

### App Disks

An App Disk is a USB drive or SSD with ext4 filesystem containing a META.yaml and Docker Compose definitions. When docked into a school Pi, the Engine reads the metadata and starts the containers automatically. App Disks are the distribution mechanism — no download, no installer, no internet.

### Disk roles: App, Backup and Files

A docked disk can carry more than one role: **App**, **Backup** and **Files** can combine on one disk (`diskTypes`, for example `['app', 'files']`). A disk with only `META.yaml` and no role is an **empty IDEA disk** (`['empty']`).

- **Files Disk:** an ext4 disk whose `files/` folder the Engine mounts into opted-in Apps on the Engine it is docked to (Nextcloud first, via `x-app.filesMount`). There is no SMB or NFS share.
- **Erase** is a general action on any non-system disk (never the system disk or swap). After a content summary and a typed confirmation, it leaves an empty IDEA disk with the same disk ID; roles are then added separately.
- **Disk commands target disk IDs**, never disk names (names like "IDEA Disk" repeat).

Design: `proposals/files-disk.md` (idea#75; implementation issues are sub-issues of #75).

### Offline-First

Every component works without internet. This is the foundational constraint that shapes every technical decision.

---

## The Team (Grok Bots)

| Bot | Domain | Role |
|-----|--------|------|
| **Lead Bot** | Organisation | Koen's primary interface — design, coordination, GitHub issues and proposals |
| **Engine Dev Bot** | `agent-engine-dev` | Engine implementation and design review |
| **Console Dev Bot** | `agent-console-dev` | Console implementation and design review |
| **App Dev Bot** | `agent-app-dev` + App repos | App Disk builds, updates, version monitoring |
| **Ops Bot** | Infrastructure | Pi fleet, fleet scripts, review environments |
| **Marco Bot** | Programme Management | App scouting, field coordination, teacher guides |

Development conversations happen in Grok Bot chat. Code lives on GitHub. **Dev Bots** (Engine / Console / App) implement changes with their own tools (clone / GitHub), run tests over SSH on a claimed pool Pi (`idea01` / `idea03` / `idea04`; never golden `idea02`), and open PRs. **Ops** deploys each PR to a review Pi via fleet scripts; Lead notifies Koen with the PR URL and live review URL. Koen squash-merges; Ops updates golden / fleet mains. Pis are test / review / golden hardware — not coding agents.

The Grok Build + GitHub Actions self-hosted runner coding path is **parked** (may remain installed on `idea02` for health check) until deliberately revived. See `docs/grok-bot-setup.md` §2.2 and §3.

**Test claim rule:** before using a pool Pi a Dev Bot sets its `status` to `testing` (`update-fleet-state.sh`, bot name in the `claim` field); on release it restores `main`, restarts pm2 as pi and sets `status idle`. Never idea02; leave each Pi's store, `mdns:false`, `config.yaml`, and existing `note` field alone; one Pi down at a time. Full protocol: `docs/grok-bot-setup.md` §4.6.

`idea02` is the dedicated golden Pi (`role: golden`): it always runs the latest merged `main`, keeps MilkWise as a real workload, and is never used for PR review. Its `version` records the mains it runs (for example `engine main@<sha>, console main@<sha>`) and its `status` stays `idle`; `role: golden` is what excludes it from review allocation. The shared test/review pool is `idea01`, `idea03`, and `idea04` (`role: spare` or `review`), picked by `find-available-pi.sh`. After every merge to `main`, Ops (Atlas) moves the golden Pi to `main` and updates its `version` (`update-golden.sh` once implemented, idea#107). This dedicated-golden model (idea#118) replaces the temporary single-Pi rule from idea PR #112.

**Full setup documentation:** `docs/grok-bot-setup.md`

---

## IDEA Repos

| Repo | Contents |
|------|----------|
| `koenswings/idea` | Org root: issues, proposals, design docs, fleet-state.json, tools/, audit/ |
| `koenswings/agent-engine-dev` | Engine source |
| `koenswings/agent-console-dev` | Console source |
| `koenswings/agent-app-dev` | App Disk workspace and harness |
| `koenswings/app-<name>` | Per-App repos (Kolibri, Nextcloud, Kiwix, …) |

Checkout layout (Pis and local/box checkouts alike): `idea` at the root (`/home/pi/idea` on a Pi), agent repos nested at `idea/agents/<repo>`, and App repos nested under `idea/agents/agent-app-dev/app-<name>`. See `proposals/pi-checkout-layout.md` and `docs/grok-bot-setup.md` §2.3.1.

Tasks: GitHub Issues on `koenswings/idea` — labels: `engine`, `console`, `app-dev`, `ops`, `quality`, `docs-review`, `app-update`, `new-app-proposal`.

---

## Quality Control

All platform quality checks live in `tools/quality/quality-scan.sh`. Bots invoke the script and act on its JSON report (stdout) — they do not reimplement the rules.

| Mode | Invocation | When | Who |
|------|------------|------|-----|
| PR gate | `quality-scan.sh --pr --repo <name> --base <sha> --head <sha>` | Before opening a PR | Dev Bot for that domain |
| Full scan | `quality-scan.sh` (optionally `--repos a,b,c`) | After merges + weekly Monday | Lead Bot |

Checks: structure, hygiene, docs currency (every file under `docs/` listed in `docs/INDEX.md`; `--pr` also requires `docs/INDEX.md` / `AGENTS.md` updates when relevant), domain bake-ins (Engine `store-template.json` untouched; Console `<For>` lists keyed by ID), staleness (full scan only), and domain tests on a fleet Pi. Exit code: `0` clean, `1` violations, `2` script error; each run appends a line to `audit/audit-<year>.jsonl`. Findings carry the label `quality` or `docs-review` for the resulting GitHub issues.

Repo paths follow the nested layout: `agent-*-dev` at `idea/agents/<repo>`, `app-*` at `idea/agents/agent-app-dev/<repo>`. Remote tests run over SSH on the selected Pi in the same tree (`/home/pi/idea/agents/…`). `tools/quality/selftest.sh` runs the scanner against fixtures in `tools/quality/testdata/agents/` (no Pi needed).

App upstream version checks are separate: App Dev Bot runs `tools/quality/check-app-versions.sh` in the Monday scan (`app-update` issues); that script is still a Phase 2 stub.

**Full quality policy:** `docs/grok-bot-setup.md` §5 · **Implementation proposal:** `proposals/quality-scan-implementation.md` · **Layout:** `proposals/pi-checkout-layout.md`
