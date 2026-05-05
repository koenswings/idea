---
type: community
cohesion: 0.40
members: 6
---

# Agent Identity & Memory

**Cohesion:** 0.40 - moderately connected
**Members:** 6 nodes

## Members
- [[AGENTS.md Role File]] - document - design/virtual-company-design.md
- [[Agent Memory Layer]] - document - design/virtual-company-design.md
- [[Claude Prompting Best Practices]] - document - prompting-guide-opus.md
- [[Identity Files (Atlas-governed)]] - document - design/agent-identity-memory-architecture.md
- [[Memory Files (Agent-governed)]] - document - design/agent-identity-memory-architecture.md
- [[SOUL.md Persona File]] - document - design/virtual-company-design.md

## Live Query (requires Dataview plugin)

```dataview
TABLE source_file, type FROM #community/Agent_Identity__Memory
SORT file.name ASC
```

## Connections to other communities
- 3 edges to [[_COMMUNITY_Agent Team & Governance]]
- 1 edge to [[_COMMUNITY_OpenClaw & Skills]]

## Top bridge nodes
- [[AGENTS.md Role File]] - degree 6, connects to 2 communities
- [[Identity Files (Atlas-governed)]] - degree 3, connects to 1 community
- [[Claude Prompting Best Practices]] - degree 2, connects to 1 community