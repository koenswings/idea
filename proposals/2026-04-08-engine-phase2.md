# Proposal: Engine Phase 2 — Concurrent Operations, Cross-Engine Tests, Interrupted Task Recovery

**Proposed by:** Axle (Engine Developer)
**Date:** 2026-04-08
**Status:** Proposed

## Problem

Three gaps in the current Engine runtime limit production readiness and reliability:

1. **No concurrency support** — operations (copy, backup, upgrade) are fire-and-forget with no
   queue or guard against parallel mutations to the same app or disk. In a classroom environment,
   multiple events (disk insert + timer + user action) can easily race.

2. **No cross-engine integration tests** — tests run against a single engine instance. Multi-engine
   scenarios (app assignment, peer sync, CRDT conflict resolution) are untested.

3. **No interrupted task recovery** — if the Engine process restarts mid-operation (power cut,
   crash), tasks left in the `running` state are never resumed or retried. The system silently
   ignores them.

## Proposed solution

Three scope items, each independently implementable:

### Group P: Concurrent operation safety
- Introduce an operation queue / lock per resource (disk, app instance)
- Ensure operations that mutate the same resource are serialised
- Return `409 Conflict` (or queue the operation) when a lock is held
- Tests: concurrent copyApp + ejectDisk should not corrupt state

### Group Q: Cross-engine integration tests
- Test harness for two-engine scenarios (can use Docker Compose in CI or two Pi units)
- Cover: app assignment via `assignAppsToEngines()`, CRDT sync convergence, peer discovery via mDNS
- Flagged as hardware-gated where a real LAN is required (skip in CI without `E2E=1`)

### Group R: Interrupted task recovery
- On Engine startup, scan for tasks in `running` state in the Automerge store
- For each: determine if the underlying process is still alive; if not, re-queue or fail gracefully
- Configurable strategy per operation type: `retry` (default) or `fail`
- Tests: simulate crash mid-copyApp, verify recovery on restart

## Affected repos / agents

- `agent-engine-dev` — all implementation work (Axle)
- `agent-engine-dev` tests — Groups Q and R require test infrastructure additions

## Open questions

- Group Q: Do we target Docker Compose two-container CI, or only physical Pi pairs?
- Group R: Should recovery be automatic (silent retry) or surfaced to Console as a notification?
- Sequencing: should these be one MC task each, or one umbrella task with sub-items?
