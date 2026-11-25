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
- Serves the Console UI and `/api/store-url` over HTTP on `httpPort` (80 on a school install; the dev pool often uses 8080), and also on port 80 under the shared name `idea.local`
- Syncs with the other Engines of its store over a WebSocket on port 4321 (not over HTTP)

The Engine runs unattended. Reliability is the primary design constraint. If the local store is damaged, the Engine moves the bad files to a quarantine folder (it never deletes them) and, only when this store started from the shared template (`store-genesis.json`), rebuilds from `store-template.json`; a store with a different history waits for a peer instead of inventing a new one (engine#568). pm2 backs off on a crash loop instead of spinning. pm2 (as user `pi`, never root) runs two processes from `pm2.config.cjs`: `engine` and `idea-usage` (field usage monitoring, see below). Root-only work goes through small root helpers installed with `install-root-helpers` (for example `idea-app-data`, `idea-engine-identity`); the Engine calls them through `sudo -n`. Technical detail: `agent-engine-dev/docs/ARCHITECTURE.md` (what is implemented) and `docs/COMMANDS.md` (every command).

### Console

The Console is a Solid.js web app served by each Engine (port 80 on a school install). It is not a browser extension. At a school, open `http://idea.local` or `http://<sticker>.local`; staff can also reach it over Tailscale. Two audiences: Users open apps without logging in; Operators sign in (👤 **Operator Login**) to manage apps, disks, backups and classroom computer cards. Each Console lists every Engine of the school from the shared store; if its own Engine goes away, it reconnects or opens another live Engine's Console. It does not guess Engine names by mDNS: it asks the Engine that served it (`/api/store-url`) and Engines it used before. It connects to one Engine over WebSocket, reads the whole shared store from it, and sends commands by writing them into the target Engine's command queue in the store (`engineDB[<engineId>].commands`). An app of an Engine that is offline is still listed, but its **Open** button is greyed out with the hint "*<name>* is offline, so this app can't be opened right now" (Console #175).

### Names and addresses

- Every Engine has a unique **sticker name**: two lowercase words, an adjective and a noun, no digits (for example `brave-otter`). It is the hostname, the Tailscale name and the name on the case sticker (`/home/pi/STICKER.txt`).
- Every Engine also publishes the shared mDNS name **`idea.local`** (`ideaLocal.ts`, idea#203): the first Engine to claim it answers, and another takes over when it leaves.
- At a school, people open the Console only at **`http://idea.local`** or **`http://<sticker>.local`**. Manuals and teacher material use only those two addresses.
- Every school uses the **`10.42.x`** LAN: Engines get `10.42.0.2`–`.9`, the student Wi-Fi `IDEA` is `10.42.1.0/24` and the teacher Wi-Fi `IDEA-Teachers` is `10.42.2.0/24`. The Engine prefers a `10.42.x` address when it reports its LAN address (`lanPreferCidrs`).

### One shared store per fleet

All Engines of one fleet share **one** Automerge store document, named in `store-identity/store-url.txt`. An Engine only syncs with Engines of its own store (store-scoped peering). Today there are three stores:

| Store | Who uses it |
|---|---|
| `automerge:3Vvvigx8bKcuwKALqMVz85GhDqrk` (kit store) | The Zimbabwe kit Engines, and every new Engine image (idea#452) |
| `automerge:2VroE…` (dev pool) | The test pool `idea01`, `idea03`, `idea04` |
| `automerge:6f8m…` | Production `idea`, on its own |

Liveness is kept out of the store history: every 10 s each Engine sends an ephemeral heartbeat (`idea/hb`) and every 15 s its container metrics (`idea/metrics`); neither is stored. The stored "last seen" (`lastRun`) is written at boot and at most once an hour. A peer that has not been seen for 7 days loses its peer SSH key on the other Engines. Finished operations older than 7 days are moved out of the store into the Engine's own CommandLog document.

### Remote access and security defaults

- **Tailscale:** one fleet tag `tag:idea` and one reusable fleet key; admins can reach `tag:idea`, and `tag:idea` reaches nothing. A new Engine joins once at first boot and then deletes the key (engine#291). Details: `docs/ops/tailscale-field-access.md`.
- **Production `idea`** is reached as `idea.tail2d60.ts.net` (ports in the remote-access guide).
- **SSH** to every Pi is key-only, as `pi`.
- **Default passwords** follow the public convention `<accountname>911!`. The values themselves are only in the private Accounts and Passwords sheet; they are never written in a doc, issue or log.
- **Disk detection:** the udev rule `/etc/udev/rules.d/90-docking.rules` makes the `/dev/engine` links the Engine watches. `boot.sh` reinstalls it when it differs from the shipped copy, and the Engine log shows `[diskDetection] self-check passed` at startup.

### App Disks

An App Disk is a USB drive or SSD with ext4 filesystem containing a META.yaml and Docker Compose definitions. When docked into a school Pi, the Engine reads the metadata and starts the containers automatically. Instance data lives in `instances/<id>/data` on the disk, bind-mounted into the containers as `./data`. App compose files must not use Docker named volumes or absolute host paths (idea#141); Engine-generated Files Disk binds are allowed. App Disks are the distribution mechanism — no download, no installer, no internet.

The Apps in use today (version = IDEA App version, then the upstream version):

| App | Repo | Current version |
|---|---|---|
| Kolibri | `app-kolibri` | 1.3-0.19.5 |
| Nextcloud | `app-nextcloud` | 1.8-31.0.14 |
| Kiwix (offline Wikipedia) | `app-kiwix` | 1.3-3.8.2 |
| Usage dashboard (production `idea` only, not on school kits) | `app-usage-dashboard` | 1.6 |

Kolibri and Nextcloud can also run as separate **Demo** instances (`setupDemo`) for teacher training; the teacher tutorial uses them.

### Disk roles: App, Backup and Files

A docked disk can carry more than one role: **App**, **Backup** and **Files** can combine on one disk (`diskTypes`, for example `['app', 'files']`). A disk with only `META.yaml` and no role is an **empty IDEA disk** (`['empty']`).

- **Files Disk:** an ext4 disk whose `files/` folder the Engine mounts into opted-in Apps on the Engine it is docked to (Nextcloud first, via `x-app.filesMount`). There is no SMB or NFS share.
- **Erase** is a general action on any non-system disk (never the system disk or swap). After a content summary and a typed confirmation, it leaves an empty IDEA disk with the same disk ID; roles are then added separately.
- **Disk commands target disk IDs**, never disk names (names like "IDEA Disk" repeat).

Design: `proposals/files-disk.md` (idea#75; implementation issues are sub-issues of #75).

### Offline-First

Every component works without internet. This is the foundational constraint that shapes every technical decision.

### Field usage monitoring

IDEA measures whether donated kits are used as taught in the teacher tutorial. The existing Engine, Console, Automerge sync and Apps do not depend on this path: monitoring reads from them, and nothing old waits for it. The design is approved (PR #410) and implemented (idea#411–#416 closed). It is **not running on the field kits**: on kind-panda and sunny-robin the `idea-usage` process is not started (fleet-state, 22 November 2026).

- **On each kit:** a separate pm2 process, `idea-usage`, runs as `pi` alongside the Engine. When enabled it records presence every five minutes and calls each App's usage hook (`x-app.usage`), writing role-level day summaries to `/var/lib/idea/usage/` (usernames stay on the kit). It never opens the Automerge store; a unit test fails if `src/usage/` imports Automerge or the store modules. A persistent Engine setting `usageMonitoring` ships **off**, survives a reboot and an Engine update, and is turned on one kit at a time. Engines without monitoring ignore the hook field. The Engine reports a `usageSummaries` capability flag; nothing old requires it.
- **Export:** the programme collector on idea pulls summaries over SSH through the root helper's forced command (added in helper v7; the Engine now expects helper v25) `/usr/local/sbin/idea-usage-export` (only `since YYYY-MM-DD` and `archive-and-clear --before YYYY-MM-DD`). The key lives in root-owned `/etc/ssh/idea_usage_keys/%u`, restricted to the dashboard sidecar's Tailscale IPv4.
- **On idea:** the `app-usage-dashboard` App runs a collector with its own userspace Tailscale sidecar tagged `tag:idea-hub` (idea itself stays `tag:idea`). It watches Tailscale's LocalAPI — no LLM — stores uplink history and pulled summaries in SQLite on idea, and serves the programme dashboard. It does not touch MilkWise (ports 3333 and 3334) or idea's Engine. A school-local Console Usage panel (D2) is a later follow-up and is not in the first delivery.
- **Turning it off:** fleet-wide, remove the `tag:idea-hub → tag:idea` tcp/22 ACL; per kit, set `usageMonitoring` to off; on idea, stop the dashboard App; in an emergency, remove the key file. Stopping the `idea-usage` process by hand is not enough: without the persistent switch, a reboot or an Engine update would start it again.

Field Engines: kind-panda and sunny-robin were updated on 22 November 2026 (idea#374) to Engine `6c47f09` (main `c1cc4bb` plus the store-durability fix #568), Console `df13dbfa`, root helper v25, Apps Nextcloud 1.8, Kolibri 1.3 and Kiwix 1.3. happy-zebra stays on Engine `adfd9d3` with Console pr162 (agent-console-dev#162, unmerged) and is left untouched until Koen has checked it. `fleet-state.json` is the source of truth for what each kit runs.

Design: `proposals/2026-11-09-field-usage-monitoring.md` (PR #410). Implementation: idea#411–#417 (D2 is #417). Koen's Tailscale and threshold items stay on idea#375.

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

Development conversations happen in Grok Bot chat. Code lives on GitHub. **Dev Bots** (Engine / Console / App) implement changes with their own tools (clone / GitHub), run tests over SSH on a claimed pool Pi (`idea03` / `idea04`; never golden `idea01`, never `idea02`), and open PRs. **Ops** deploys each PR to a review Pi via fleet scripts; Lead notifies Koen with the PR URL and live review URL. Koen merges idea and App-repo PRs; app-kolibri PRs always need Koen's own words. Steve may squash-merge his delegated agent-engine-dev, agent-console-dev and app-nextcloud PRs under Koen's standing approval; the merge tool may ask Koen to confirm Console merges on a card. Ops updates golden / fleet mains. Pis are test / review / golden hardware — not coding agents.

The Grok Build + GitHub Actions self-hosted runner coding path is **parked** (may remain installed on `idea02` for health check) until deliberately revived. See `docs/grok-bot-setup.md` §2.2 and §3.

**Test claim rule:** before using a pool Pi a Dev Bot sets its `status` to `testing` (`update-fleet-state.sh`, bot name in the `claim` field); on release it restores `main`, restarts pm2 as pi and sets `status idle`. Never idea02; leave each Pi's store, `mdns:false`, `config.yaml`, and existing `note` field alone; one Pi down at a time. Full protocol: `docs/grok-bot-setup.md` §4.6.

`idea01` is the dedicated golden Pi (`role: golden`, since 2026-10-28 10:31 CET; `idea03` earlier that morning, `idea02` before 2026-10-07): it always runs the latest merged `main` and is never used for PR review. Its `version` records the mains it runs (for example `engine main@<sha>, console main@<sha>`) and its `status` is `idle` except while Ops is updating it (the live value is in `fleet-state.json`); `role: golden` is what excludes it from review allocation. The shared test/review pool is `idea03` and `idea04` (`role: spare` or `review`), picked by `find-available-pi.sh`. `idea02` is not a pool Pi: it is a LAN client and test-walk host (`role: fleet-pending`, `status: hold`) and is never claimed or deployed to. After every merge to `main`, Ops (Atlas) moves the golden Pi to `main` and updates its `version` (`update-golden.sh <component> main --yes`, idea#107). This dedicated-golden model (idea#118) replaces the temporary single-Pi rule from idea PR #112.

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

App upstream version checks are separate: App Dev Bot runs `tools/quality/check-app-versions.sh` in the Monday scan (`app-update` issues; idea#88).

**Full quality policy:** `docs/grok-bot-setup.md` §5 · **Implementation proposal:** `proposals/quality-scan-implementation.md` · **Layout:** `proposals/pi-checkout-layout.md`
