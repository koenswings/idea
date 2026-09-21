# Proposals

A proposal is any document that develops an idea — from a brief requirements sketch to a detailed implementation analysis — up to the point where Koen can decide to proceed.

Proposals are how the team thinks on paper before acting. They are always optional: a simple change can go straight from conversation to code. But when a change is complex, cross-domain, or uncertain, writing it down first makes the decision better.

---

## What a proposal can be

A proposal can sit anywhere on this spectrum — the level of detail should match the complexity and risk of the change:

**Requirements only** — *"Should we add X? Here's the problem it solves, here's the user experience after the change, here are the tradeoffs."* Koen approves the direction; implementation details come later.

**Implementation analysis** — *"We want to do X. Here are the two ways we could implement it, the tradeoffs, and which one we recommend."* Koen approves the approach; execution follows.

**Full specification** — *"We want to do X this way for these reasons."* Everything needed to start coding is in the doc. Koen approves and work begins immediately.

The same document can start at requirements level, get refined through discussion, and end up at full specification — all before the PR is merged.

---

## What proposals cover

- New features or changes to existing behaviour
- Architecture decisions with significant implications
- Ideas that span multiple repos or domains
- Anything the team wants to think through before committing

Bots can open proposals too — for operational improvements, new app candidates, quality issues, or anything they believe is worth Koen's attention. The format is the same.

---

## Format

```markdown
# Title: short description

**Author:** <Bot or Koen>
**Date:** YYYY-MM-DD
**Status:** Draft | Approved | Declined | Superseded by <link>

## Problem or opportunity
What situation prompted this proposal.

## Proposed approach
What we want to do. If there are meaningful alternatives, describe them briefly and explain the recommendation.

## User experience / outcome
What the system or user experience looks like after this is implemented.

## Implementation notes (optional)
How it would be built, at whatever level of detail is needed for the decision.

## Open questions
What still needs input before work starts.
```

---

## Lifecycle

1. An agent or Koen drafts a proposal and opens a PR to this folder (`proposals/<YYYY-MM-DD>-<topic>.md`)
2. For changes affecting multiple domains: Lead Bot posts it to the Design Review group chat for domain assessment
3. Lead Bot synthesises feedback and refines the proposal
4. Koen reviews the PR and either merges (approved) or closes with a comment (declined)
5. Merged: Lead Bot creates implementation GitHub issues. Work begins.
6. Declined: PR closes. The proposal stays in the PR history as a permanent record of what was considered and why it was declined.

---

## After approval

Once implemented, the proposal stays in this folder unchanged. It is the permanent record of the reasoning behind the decision — useful for anyone who later asks *"why does the system work this way?"*

A proposal that supersedes an earlier one notes this at the top (`**Status:** Supersedes <link>`). Both are kept.

---

## Relationship to `docs/`

`docs/` describes what the system *is now*. `proposals/` captures the reasoning behind *how it got there* and *where it might go next*. They serve different questions: docs answer "what does this do?", proposals answer "why was this decided?".
