---
type: community
cohesion: 0.25
members: 11
---

# Platform Infrastructure

**Cohesion:** 0.25 - loosely connected
**Members:** 11 nodes

## Members
- [[MC Backend Service]] - document - platform/compose.yaml
- [[MC Frontend Service]] - document - platform/compose.yaml
- [[MC Kanban Board]] - document - design/virtual-company-design.md
- [[MC PostgreSQL DB]] - document - platform/compose.yaml
- [[Mission Control]] - document - PROCESS.md
- [[Tailscale Network]] - document - design/tailscale-remote-management.md
- [[Tailscale Serve Proxy]] - document - platform/compose.yaml
- [[idea-net Docker Network]] - document - platform/compose.yaml
- [[idea Repo README]] - document - README.md
- [[mc-api Skill]] - document - skills/mc-api/SKILL.md
- [[platformcompose.yaml]] - document - platform/compose.yaml

## Live Query (requires Dataview plugin)

```dataview
TABLE source_file, type FROM #community/Platform_Infrastructure
SORT file.name ASC
```

## Connections to other communities
- 2 edges to [[_COMMUNITY_OpenClaw & Skills]]
- 1 edge to [[_COMMUNITY_Agent Team & Governance]]
- 1 edge to [[_COMMUNITY_Backlog & Task Management]]
- 1 edge to [[_COMMUNITY_Offline Product Core]]

## Top bridge nodes
- [[idea Repo README]] - degree 4, connects to 2 communities
- [[Mission Control]] - degree 5, connects to 1 community
- [[Tailscale Network]] - degree 3, connects to 1 community
- [[mc-api Skill]] - degree 2, connects to 1 community