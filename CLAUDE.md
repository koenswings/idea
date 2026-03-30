# CLAUDE.md — IDEA repo

Pointer list for standalone Claude Code sessions in this repo.

## Active migration runbooks

- [`platform/MIGRATE-NATIVE.md`](platform/MIGRATE-NATIVE.md) — OpenClaw Docker → native install
  - Read `design/openclaw-native-migration.md` first for context
  - Execute from a tmux SSH session **outside OpenClaw** (see safety note in runbook)

## Key files

- `CONTEXT.md` — mission, solution overview, guiding principles
- `PROCESS.md` — how we work (PRs, backlog, communication standards)
- `ROLES.md` — who does what
- `BACKLOG.md` — current approved work items
- `design/INDEX.md` — all design docs
- `platform/compose.yaml` — Docker Compose for MC and infrastructure services
- `scripts/setup.sh` — full Pi setup script

## Rules

- Never push directly to `main` — all changes via PRs
- Commit memory/output files to `memory/updates` branch in each agent repo
- See `PROCESS.md` for full process
