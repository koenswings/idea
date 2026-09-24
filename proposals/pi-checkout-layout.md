# Pi / local checkout layout — nest agent repos under `idea/agents/`

**Author:** Steve  
**Date:** 2026-09-24  
**Status:** Decided (Koen locked 2026-09-24)  
**Related:** #62, #63

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
    agent-app-dev/
    app-kolibri/
    app-nextcloud/
    app-kiwix/
    app-milkwise/
```

| Role | Canonical path |
|------|----------------|
| Engine pm2 cwd / `ENGINE_CWD` | `/home/pi/idea/agents/agent-engine-dev` |
| `ENGINE_BIN` | `/home/pi/idea/agents/agent-engine-dev/dist/src/index.js` |
| Console `consolePath` | `/home/pi/idea/agents/agent-console-dev/dist` |
| quality-scan remote test cwd | `/home/pi/idea/agents/<repo>` |
| quality-scan local `repo_path` (non-idea) | `${IDEA_ROOT}/agents/<name>` |

**Retired as primary:** `/home/pi/projects/engine`, `/home/pi/console-dist`, `/home/pi/agent-*-dev` as siblings of `idea` (or of `/home/pi`).

## Why

- One tree to document, clone, and SSH into
- Matches historical OpenClaw-era nesting (`idea/agents/…`) without keeping the old platform
- Fixes scanner/fleet path drift behind #62 / #63

## Migration notes (idea02 and other Pis)

1. Ensure `/home/pi/idea` is a clone of `koenswings/idea` on `main`.
2. Clone or move agent/app repos into `/home/pi/idea/agents/<name>`.
3. Point Engine `config.yaml` `consolePath` at `/home/pi/idea/agents/agent-console-dev/dist`.
4. Run Engine via pm2 with cwd `/home/pi/idea/agents/agent-engine-dev` (`ENGINE_CWD` / `ENGINE_BIN` under that tree).
5. Build Console in-tree (`pnpm build` → `dist/`); do not treat `/home/pi/console-dist` as primary (optional symlink during cutover).
6. Re-run `quality-scan.sh` full mode; #62 / #63 should clear once paths exist.

Local quality-scan / box checkouts use the same nesting: agent repos under `idea/agents/<name>`, not siblings of `idea`. `--repo-root` overrides the parent of `agents/` (fixtures live at `tools/quality/testdata/agents/`).

## Affected scripts / docs (this PR)

- `docs/grok-bot-setup.md` — §2.3.1 layout; deploy §4.3; AGENTS samples
- `tools/quality/quality-scan.sh` — `repo_path` + remote test path
- `tools/quality/testdata/agents/` — fixtures nested for selftest
- `tools/fleet/*` — stub headers/comments for implementers (Atlas)
- `README.md`, `tools/README.md`, `proposals/INDEX.md`

Agent-engine-dev / agent-console-dev repos are **not** changed in this PR (idea only). Ops will migrate idea02 after merge.
