---
type: community
cohesion: 0.67
members: 3
---

# Nightly Backup System

**Cohesion:** 0.67 - moderately connected
**Members:** 3 nodes

## Members
- [[Identity Drift Detection]] - document - design/agent-identity-memory-architecture.md
- [[Nightly Backup Cron (0300 UTC)]] - document - design/agent-identity-memory-architecture.md
- [[agent-identities Backup Repo]] - document - design/agent-identity-memory-architecture.md

## Live Query (requires Dataview plugin)

```dataview
TABLE source_file, type FROM #community/Nightly_Backup_System
SORT file.name ASC
```

## Connections to other communities
- 1 edge to [[_COMMUNITY_Agent Team & Governance]]

## Top bridge nodes
- [[Identity Drift Detection]] - degree 2, connects to 1 community