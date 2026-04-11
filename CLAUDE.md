# CLAUDE.md — IDEA repo

Pointer list for standalone Claude Code sessions in this repo.

## Active migration runbooks

- [`platform/MIGRATE-NATIVE.md`](platform/MIGRATE-NATIVE.md) — OpenClaw Docker → native install
  - Read `design/openclaw-native-migration.md` first for context
  - Execute from a tmux SSH session **outside OpenClaw** (see safety note in runbook)
  - **Current state (2026-04-05):** MC containers are split across two Docker networks
    (`platform_idea-net` / `openclaw_idea-net`) due to a compose project name conflict
    after Pi hardware migration. The clean MC restart in Step 9 fixes this permanently.
  - `platform/compose.yaml` already has `name: openclaw` and `extra_hosts` for the MC
    backend/webhook-worker (merged via PRs #25 and #27). Pull `main` before starting.

## Key files

- `CONTEXT.md` — mission, solution overview, guiding principles
- `PROCESS.md` — how we work (PRs, backlog, communication standards)
- `ROLES.md` — who does what
- `BACKLOG.md` — current approved work items
- `design/INDEX.md` — all design docs
- `platform/compose.yaml` — Docker Compose for MC and infrastructure services
- `scripts/setup.sh` — full Pi setup script

## Rules

- Never push directly to `main` — all changes via PRs (exception: compose.yaml updated in Step 9 requires a PR)
- Agent memory/output files are written directly to disk — no commits needed
- See `PROCESS.md` for full process
