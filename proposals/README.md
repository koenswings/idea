# Proposals

A proposal is a request for a decision. It captures what you want to change, why, and what the options are — before any implementation work starts.

---

## When to open a proposal

Open a proposal when:

- A feature or change touches more than one repo
- A decision has architectural implications
- You want to explore alternatives before committing to one
- Koen should approve the direction before work begins

For small bug fixes and isolated changes, Lead Bot's agreed-approach comment on the GitHub issue is sufficient. No proposal needed.

---

## What a proposal contains

```markdown
# Title: short description of what is being proposed

**Author:** <Bot or Koen>
**Date:** YYYY-MM-DD
**Status:** Draft

## What
What is being proposed. One clear paragraph.

## Why
The problem it solves or the opportunity it creates.

## Affected areas
Which repos, components, or workflows are affected.

## Approach
The proposed solution. If there are meaningful alternatives, describe them briefly and explain why this one is preferred.

## Open questions
What still needs input or decision before implementation starts.
```

---

## How it works

1. Lead Bot drafts the proposal and posts it to the **IDEA Design Review** group chat. All Dev Bots review from their domain perspective and respond.
2. Lead Bot synthesises the feedback and refines the proposal.
3. Lead Bot opens a PR to this folder (`proposals/<YYYY-MM-DD>-<topic>.md`).
4. Koen reviews the PR. Merging it means the proposal is approved.
5. Lead Bot creates implementation GitHub issues based on the merged proposal.

A declined proposal is closed with a comment explaining why. It stays in the PR history as a record.

---

## Relationship to `design/`

`proposals/` is for decisions not yet made. `design/` is for reasoning already captured — past decisions, alternatives considered, ideas explored. A merged proposal may or may not produce a design doc; simple proposals don't need one.
