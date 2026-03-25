# docs/ — Authoritative Company Documentation

This directory contains authoritative descriptions of IDEA's organisation, infrastructure, and
operations **as they currently exist** — not as they are intended or planned.

## What belongs here

| Document | Describes |
|---|---|
| (to be created) | The org as implemented — agents deployed, workflows active, infrastructure running |

## The rule

**Authoritative docs describe only what is implemented.** No `[planned]` sections, no
future-tense descriptions. If it is not live, it is not here.

Design intent belongs in `design/`. Product knowledge (Engine, Console, App Disks) belongs in
`CONTEXT.md`. This directory is for the org itself: who is deployed, how we work, what is
running.

## When to update

An authoritative doc must be updated in the **same PR** as the change that makes it true.
When a design reaches `Implemented` status, its content moves here — the design doc records
the decision, this doc records the result.

Atlas is responsible for maintaining this directory.
