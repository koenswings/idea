# Pi / local checkout layout — nest agent repos under `idea/agents/`

**Author:** Steve  
**Date:** 2026-09-24  
**Status:** Decided (Koen locked 2026-09-24; revised 2026-09-24)  
**Related:** #62, #63, #64

## Problem

Quality-scan and fleet docs assumed several different Pi layouts at once:

- Engine at `/home/pi/projects/engine`
- Console artifacts at `/home/pi/console-dist`
- Scanner remote tests at `/home/pi/<repo>` (sibling of `$HOME`)
- Local scan resolving agent repos as **siblings** of `idea`

Live scan on idea02 (#62 Console, #63 Engine CRITICAL) failed with `cd: /home/pi/agent-*-dev: No such file or directory` — connectivity was fine; the path assumption was wrong.

## Decision

One canonical tree for **test, dev, and production**:

```
/home/pi/idea/                          # clone of koenswings/idea
  agents/
    agent-engine-dev/                   # Engine source + runtime (pm2 cwd)
    agent-console-dev/                  # Console source; serve built dist/
    agent-app-dev/                      # koenswings/agent-app-dev workspace
      app-kolibri/                      # clone of koenswings/app-kolibri
      app-nextcloud/
      app-kiwix/
      app-milkwise/
```

App GitHub repos (`app-*`) are **direct children of `agent-app-dev/`**, not siblings of `agent-engine-dev` / `agent-console-dev`. Do **not** put them under `agent-app-dev/apps/` — that path is in-repo harness content (`apps/app-harness/`); App repos are separate checkouts.

| Role | Canonical path |
|------|----------------|
| Engine pm2 cwd / `ENGINE_CWD` | `/home/pi/idea/agents/agent-engine-dev` |
| `ENGINE_BIN` | `/home/pi/idea/agents/agent-engine-dev/dist/src/index.js` |
| Console `consolePath` | `/home/pi/idea/agents/agent-console-dev/dist` |
| quality-scan remote test cwd (`agent-*-dev`) | `/home/pi/idea/agents/<repo>` |
| quality-scan remote test cwd (`app-*`) | `/home/pi/idea/agents/agent-app-dev/<repo>` |
| quality-scan local `repo_path` (`agent-*-dev`) | `${IDEA_ROOT}/agents/<name>` |
| quality-scan local `repo_path` (`app-*`) | `${IDEA_ROOT}/agents/agent-app-dev/<name>` |

**Retired as primary:** `/home/pi/projects/engine`, `/home/pi/console-dist`, `/home/pi/agent-*-dev` as siblings of `idea` (or of `/home/pi`), and `app-*` as siblings of `agent-*-dev` under `idea/agents/`.

## Why

- One tree to document, clone, and SSH into
- Matches historical OpenClaw-era nesting (`idea/agents/…`) without keeping the old platform
- App Dev workspace owns App checkouts (same nesting as the App Dev Bot domain)
- Fixes scanner/fleet path drift behind #62 / #63

## Migration notes (idea02 and other Pis)

1. Ensure `/home/pi/idea` is a clone of `koenswings/idea` on `main`.
2. Clone or move `agent-engine-dev`, `agent-console-dev`, and `agent-app-dev` into `/home/pi/idea/agents/<name>`.
3. Clone or move App GitHub repos as **direct children** of `/home/pi/idea/agents/agent-app-dev/` (e.g. `…/agent-app-dev/app-kolibri`). If they were previously under `idea/agents/app-*`, move them under `agent-app-dev/`.
4. Point Engine `config.yaml` `consolePath` at `/home/pi/idea/agents/agent-console-dev/dist`.
5. Run Engine via pm2 with cwd `/home/pi/idea/agents/agent-engine-dev` (`ENGINE_CWD` / `ENGINE_BIN` under that tree).
6. Build Console in-tree (`pnpm build` → `dist/`); do not treat `/home/pi/console-dist` as primary (optional symlink during cutover).
7. Re-run `quality-scan.sh` full mode; #62 / #63 should clear once paths exist.

Local quality-scan / box checkouts use the same nesting: agent repos under `idea/agents/<name>`; App repos under `idea/agents/agent-app-dev/<name>`. `--repo-root` overrides the parent of `agents/` (fixtures live at `tools/quality/testdata/agents/`).

## Revision history

- **2026-09-24 (initial):** Nest all agent/app checkouts under `idea/agents/` as siblings.
- **2026-09-24 (Koen correction):** App repos (`app-kolibri`, `app-nextcloud`, `app-kiwix`, `app-milkwise`) nest **under `agent-app-dev/`**, not as siblings of `agent-engine-dev` / `agent-console-dev`.

## Affected scripts / docs (this PR)

- `docs/grok-bot-setup.md` — §2.3.1 layout; deploy §4.3; quality §5 paths
- `tools/quality/quality-scan.sh` — `repo_path` + remote test path (`app-*` under `agent-app-dev`)
- `tools/quality/testdata/agents/` — fixtures nested for selftest
- `tools/fleet/*` — stub headers/comments for implementers (Atlas)
- `README.md`, `tools/README.md`, `proposals/INDEX.md`

Agent-engine-dev / agent-console-dev / agent-app-dev repos are **not** changed in this PR (idea only). Ops will migrate idea02 after merge.
