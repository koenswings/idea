# OpenClaw: Docker vs Native Install

**Author:** Atlas 🗺️  
**Date:** 2026-03-30  
**Status:** Implemented  
**Implemented:** 2026-04-06  

---

## Background

OpenClaw is currently deployed as a Docker container (`openclaw-gateway`) inside
`platform/compose.yaml`. All five agent sessions run inside this container. The container
mounts `/home/pi/idea` as `/home/node/workspace`, making the IDEA repo available to agents
at a predictable path.

This setup was chosen for deployment consistency. It has worked well, but has introduced a
persistent friction point: the container user (`node`, uid 1000 inside the container) does not
map cleanly to the host user (`pi`, uid 1000) in all code execution contexts. This has
surfaced as root-owned `dist/` directories in the Engine repo, and is expected to recur with
any agent that builds code or interacts with hardware devices via `/dev/`.

This document evaluates two options for resolving this and recommends a migration to native
install.

---

## Current State

```
/home/pi/idea/platform/compose.yaml
  └── openclaw-gateway (image: ghcr.io/openclaw/openclaw:latest)
        volume: /home/pi/idea    → /home/node/workspace
        volume: /home/pi/.openclaw → /home/node/.openclaw
  └── mission-control-backend
  └── mission-control-frontend
  └── mission-control-webhook-worker
  └── postgres
  └── redis
```

OpenClaw config lives at `/home/pi/.openclaw/openclaw.json` on the host — it is bind-mounted
into the container at `/home/node/.openclaw/openclaw.json`. All agent sessions run inside the
container. Agents address files using the container path (`/home/node/workspace/...`).

---

## The Problem

### 1. UID mismatch in build contexts

When an agent runs `pnpm build` (e.g., inside a tmux session started by OpenClaw), the
process runs as the `node` user inside the container. Files created in the mounted workspace
(`/home/pi/idea/agents/agent-engine-dev/dist/`) are owned by uid 1000 on the host — which
is also `pi`. This should be equivalent, but breaks in practice when:
- `pnpm` or Node spawns subprocesses that inherit a different umask
- CI-mode builds run with elevated permissions
- Host-side scripts (e.g., `run-tests.sh` via SSH) expect a consistent owner

This caused the `root-owned dist/` issue Axle encountered (fixed in PR #17 as a workaround).

### 2. Hardware device access

Agents that need access to `/dev/` (e.g., Axle reading USB disk devices) require bind-mounts
into the container. A udev rule on the host sets permissions for `pi`; but the container user
is `node`. This mismatch requires `chmod 777` workarounds that reset on reboot.

### 3. Container overhead on Pi 4

OpenClaw in Docker adds ~150–200 MB RAM overhead compared to native. On a Pi 4 with 4 GB
this is acceptable but not free — every MB counts for school Pis.

---

## Option A — Docker + `--user 1000:1000`

Add `user: "1000:1000"` to the `openclaw-gateway` service in `platform/compose.yaml`.

```yaml
services:
  openclaw-gateway:
    image: ghcr.io/openclaw/openclaw:latest
    user: "1000:1000"          # ← add this
    ...
```

**What it fixes:** Build-context UID mismatch — files created inside the container would be
owned by uid 1000 (`pi`) on the host.

**What it does not fix:**
- Hardware device access still requires bind-mounts and matching permissions
- Container overhead remains
- Root-owned files created before this change are not cleaned up automatically

**Risk:** OpenClaw's Docker image may write files to paths owned by root at startup (e.g.,
`/etc/`, `/var/`) — running as non-root could break the container startup. Needs testing
before committing.

**Effort:** One line in `compose.yaml`. Fast to test.

**Verdict:** Surgical fix for the immediate issue. Does not address the structural causes.
Appropriate as a temporary measure while native migration is planned.

---

## Option B — Native Install

Install OpenClaw directly on the Pi using the official npm package:

```bash
npm install -g openclaw@latest
openclaw onboard --install-daemon
```

OpenClaw supports macOS/Linux natively with Node 22.14+ (IDEA already installs Node 22 on
the Pi via `setup.sh`). The `--install-daemon` flag creates a systemd service that runs under
the calling user (`pi`).

**What it fixes:**
- All agent processes run as `pi` — no UID mismatch in any context
- `/dev/` devices accessible directly — udev rules target `pi`, no bind-mounts needed
- Build artifacts owned by `pi` by default — no workarounds
- ~150–200 MB RAM freed

**What changes:**
- OpenClaw is no longer managed by Docker — `compose.yaml` loses the `openclaw-gateway` service
- `setup.sh` needs updating (install native instead of Docker-based)
- Path references in agent config must be preserved (see below)

**Risk:** Slightly less deployment isolation — OpenClaw shares the Node.js installation with
other tools. OpenClaw updates happen via `npm update -g` rather than Docker image pulls.

**Effort:** Moderate — migration runbook, `setup.sh` update, verification. One-time cost.

**Verdict:** The correct long-term solution. Removes the entire class of UID mismatch problems
and simplifies the platform architecture. Recommended.

---

## Path Preservation Strategy

All agents reference files using the Docker container path `/home/node/workspace/...`. Agents
also reference each other's repos at `/home/node/workspace/agents/...`. AGENTS.md files,
TOOLS.md, MEMORY.md, and the CLAUDE.md pointer lists all use this path.

**Changing all path references is high-churn and error-prone.** The clean approach is to
preserve the path on the host via a symlink:

```bash
sudo mkdir -p /home/node
sudo ln -sfn /home/pi/idea /home/node/workspace
```

After this, `/home/node/workspace/` on the Pi host resolves to `/home/pi/idea/`. All existing
path references continue to work without any changes to agent config, AGENTS.md files, or
TOOLS.md.

No agent config changes. No PR for path updates. Zero churn.

---

## Impact Summary

| Area | Docker + --user | Native |
|---|---|---|
| UID mismatch (builds) | Fixed | Fixed |
| /dev/ hardware access | Not fixed | Fixed |
| RAM overhead | No change | −150–200 MB |
| Agent path references | No change | No change (symlink) |
| setup.sh | No change | Update required |
| compose.yaml | 1-line change | Remove openclaw-gateway service |
| OpenClaw updates | docker pull | npm update -g |
| Deployment isolation | Container | Process |
| Migration risk | Minimal | Low–moderate |

---

## Recommendation

**Immediate:** Apply Option A (`user: "1000:1000"`) as a fast fix for Axle's current blocker.
Test it first — if OpenClaw's startup requires root, fall back and prioritise the native
migration instead.

**Short-term:** Execute Option B (native install) as a planned migration. The migration is
self-contained and reversible.

See [`platform/MIGRATE-NATIVE.md`](../platform/MIGRATE-NATIVE.md) for the complete runbook.

---

## Executing the Migration with Claude Code

The migration **must be executed from a Claude Code session on the Pi host**, not from inside
an OpenClaw agent session (Atlas, Axle, or any other). Here is why, and how.

### Why not from inside OpenClaw

OpenClaw is the thing being migrated. The process looks like this:

1. Stop the `openclaw-gateway` Docker container
2. Install and start native OpenClaw
3. Remove `openclaw-gateway` from `compose.yaml`

Step 1 kills every agent session — including the one that issued the command. An agent that
starts this process cannot complete it. This is a fundamental constraint: you cannot migrate
a running system from inside itself.

Even using OpenClaw's `gateway restart` tooling does not help here — it restarts the
container, not the host daemon. Once the container is stopped, the agent is gone.

### Why Claude Code

Claude Code (`claude`) is an independent process on the Pi host. It runs outside the OpenClaw
container, directly as the `pi` user, with full access to the filesystem, systemd, and
Docker. It is not affected by OpenClaw being stopped or restarted.

This makes it the natural executor for a migration that requires:
- Running `docker compose stop` against the OpenClaw service
- Installing and enabling a new systemd daemon
- Verifying OpenClaw comes back up under the new process model
- Removing the old service from `compose.yaml`

### How to start the session

```bash
ssh pi@<pi-hostname>
tmux new -s migration        # or attach to an existing session
cd /home/pi/idea
claude                        # Claude Code picks up CLAUDE.md automatically
```

The `CLAUDE.md` file at the repo root is a pointer list for exactly this scenario. It gives
Claude Code the full context it needs: OpenClaw architecture, the migration runbook path,
and the three open questions to resolve before executing. No re-explanation needed.

### Session flow

1. Claude Code reads `CLAUDE.md`, then `platform/MIGRATE-NATIVE.md`
2. It resolves the three open questions (Option A test, `/home/node` check, Node version)
3. It executes the runbook step-by-step, verifying each step before continuing
4. On success: OpenClaw is running natively as `pi`, all agent sessions resume
5. On failure: rollback instructions in `MIGRATE-NATIVE.md` restore Docker in under 2 minutes

The tmux session ensures the migration survives any SSH disconnect. The ~60 seconds of
OpenClaw downtime during the switchover is the only interruption to agent availability.

---

## Open Questions (resolved at execution)

1. **`user: "1000:1000"` test** — skipped; Option A was never tested. Migration went directly to Option B (native).
2. **`/home/node` on Pi** — did not exist; symlink created cleanly at `/home/node/workspace → /home/pi/idea`.
3. **Node version** — Node 22 used; not upgraded to 24. OpenClaw 2026.4.2 works on Node 22.

---

## Execution Notes (2026-04-06)

Migration executed by Claude Code in a tmux SSH session. Deviations from runbook:

**1. Config was in a Docker named volume, not a bind-mount.**
The runbook assumes `~/.openclaw/` was accessible on the host as a bind-mount. In the actual
setup it was a named Docker volume (`openclaw_openclaw-data`). Extraction required:
```bash
docker cp openclaw-gateway:/root/.openclaw /tmp/openclaw-data
```
Followed by a Python script to rewrite all internal path references from `/root/.openclaw/`
to `/home/pi/.openclaw/`. The runbook Step 1 backup (`cp ~/.openclaw/`) would have been empty.

**2. `gateway.mode=local` required.**
OpenClaw 2026.4.2 refuses to start without `gateway.mode` set to `"local"`. This key was
absent in the Docker-era config. The runbook Step 4 states "no config migration needed" —
that was incorrect for this version.

**3. `ANTHROPIC_API_KEY` via systemd drop-in.**
Added at `~/.config/systemd/user/openclaw-gateway.service.d/env.conf` rather than the main
service unit. This matches the `setup.sh` native flow.

**4. Root-owned workspace** — discovered post-reboot (not during migration).
The Docker container ran as root, so all files created during that period were root-owned on
the host. Fixed with `sudo chown -R pi:pi /home/pi/idea` after the first nightly reboot.

**Post-migration state:**
- Service: `~/.config/systemd/user/openclaw-gateway.service` (user service, enabled, auto-starts)
- Version: OpenClaw 2026.4.2
- Config: `~/.openclaw/openclaw.json` with `gateway.mode=local`
- Workspace symlink: `/home/node/workspace → /home/pi/idea` (✅ verified)
- `setup.sh`: updated to native install flow (no Docker for OpenClaw)
- `platform/compose.yaml`: `openclaw-gateway` service removed (PR #29)
