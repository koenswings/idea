# Design Documents — IDEA (Org Level)

This directory contains design proposals that affect **more than one repo** or the
organisation as a whole. Single-repo designs live alongside the code they concern.

| Design location | Use when |
|---|---|
| `idea/design/` (here) | Decision affects Engine + Console, or multiple agents, or org-wide convention |
| `agents/agent-engine-dev/design/` | Engine-only design |
| `agents/agent-console-dev/design/` | Console UI-only design |
| `agents/agent-site-dev/design/` | Website-only design |

When in doubt: if the reader of the design needs to understand another repo to act on it,
it belongs here.

---

## Design doc lifecycle

```
Draft → Proposed → Approved → Implemented
                ↘ Rejected
                ↘ Withdrawn
```

| Status | Meaning |
|---|---|
| `Draft` | Being written; not yet submitted for review |
| `Proposed` | PR open; awaiting CEO decision |
| `Approved` | CEO merged PR; implementation authorised |
| `Implemented` | Feature complete; authoritative docs updated |
| `Rejected` | CEO decided not to proceed; rationale noted in doc |
| `Superseded` | A different design was chosen; link to the winning doc |
| `Withdrawn` | Proposing agent retracted before CEO decision |

---

## Rules

### When proposing
- Open a PR on the `idea` repo; title starts with `design:`
- PR description summarises the proposal and flags open questions for the CEO
- Do not begin implementation before the PR is merged

### When implementing
- Updating the relevant authoritative docs is **part of the same PR as the code change**
- Update the design doc status to `Implemented` in that same PR
- Atlas (COO & Quality Manager) verifies both as part of PR review

### When a design is rejected or superseded
- Add a one-sentence rationale to the status field
- Do not delete rejected or superseded docs — they are the historical record

---

## Documents

| File | Status | Summary |
|---|---|---|
| `virtual-company-design.md` | Approved · Partially Implemented | IDEA virtual company on OpenClaw — agent roster, org structure, workflows, infrastructure |
