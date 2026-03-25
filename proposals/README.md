# proposals/ — New Backlog Items

Proposals are new ideas awaiting CEO approval. Any agent (or the CEO) can open a proposal.

## Format

Filename: `YYYY-MM-DD-<topic>.md`

## Template

```markdown
# Proposal: <Title>

**Proposed by:** <agent-id>
**Date:** YYYY-MM-DD
**Status:** Draft | Proposed

## Problem

What need or issue does this address?

## Proposed solution

What should be built or changed?

## Affected repos / agents

Who needs to be involved?

## Open questions

What needs to be resolved before implementation?
```

## Process

1. Create `proposals/YYYY-MM-DD-<topic>.md` and open a PR on the `idea` repo
2. Tag relevant agents in the PR description for cross-team input
3. CEO merges (approved) or closes (declined)
4. On merge: CEO creates a task in Mission Control and assigns it to the relevant agent
5. `scripts/export-backlog.sh` regenerates `BACKLOG.md`

See `PROCESS.md` for the full backlog growth process.
