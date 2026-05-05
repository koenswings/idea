# Graph Report - .  (2026-05-05)

## Corpus Check
- Corpus is ~37,411 words - fits in a single context window. You may not need a graph.

## Summary
- 79 nodes · 109 edges · 10 communities
- Extraction: 88% EXTRACTED · 12% INFERRED · 0% AMBIGUOUS · INFERRED: 13 edges (avg confidence: 0.84)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Offline Product Core|Offline Product Core]]
- [[_COMMUNITY_Agent Team & Governance|Agent Team & Governance]]
- [[_COMMUNITY_Platform Infrastructure|Platform Infrastructure]]
- [[_COMMUNITY_OpenClaw & Skills|OpenClaw & Skills]]
- [[_COMMUNITY_Backlog & Task Management|Backlog & Task Management]]
- [[_COMMUNITY_Agent Identity & Memory|Agent Identity & Memory]]
- [[_COMMUNITY_Table Rendering Script|Table Rendering Script]]
- [[_COMMUNITY_PDF Conversion Script|PDF Conversion Script]]
- [[_COMMUNITY_IDEA Mission & Values|IDEA Mission & Values]]
- [[_COMMUNITY_Nightly Backup System|Nightly Backup System]]

## God Nodes (most connected - your core abstractions)
1. `Atlas (Operations Manager)` - 16 edges
2. `Engine (Raspberry Pi App)` - 9 edges
3. `Koen (CEO)` - 6 edges
4. `OpenClaw Platform` - 6 edges
5. `AGENTS.md Role File` - 6 edges
6. `Kit (App Dev Agent Proposal)` - 6 edges
7. `Axle (Engine Dev)` - 5 edges
8. `Mission Control` - 5 edges
9. `platform/compose.yaml` - 5 edges
10. `convert()` - 4 edges

## Surprising Connections (you probably didn't know these)
- `Claude Prompting Best Practices` --references--> `Atlas (Operations Manager)`  [INFERRED]
  prompting-guide-opus.md → ROLES.md
- `telegram-table Skill` --semantically_similar_to--> `telegram-table Skill (node)`  [INFERRED] [semantically similar]
  PROCESS.md → skills/telegram-table/SKILL.md
- `Atlas (Operations Manager)` --conceptually_related_to--> `Engine (Raspberry Pi App)`  [INFERRED]
  ROLES.md → CONTEXT.md
- `Atlas (Operations Manager)` --implements--> `PR Review Cycle`  [INFERRED]
  ROLES.md → PROCESS.md
- `Identity Drift Detection` --references--> `Atlas (Operations Manager)`  [EXTRACTED]
  design/agent-identity-memory-architecture.md → ROLES.md

## Hyperedges (group relationships)
- **CEO Approval Triad** — plan_permission_mode, pr_review_cycle, ceo_approval [EXTRACTED 1.00]
- **Offline System Core** — engine, app_disk, offline_first [EXTRACTED 0.95]
- **Agent Coordination Layer** — agents_md, soul_md, agent_memory_layer [INFERRED 0.85]

## Communities (10 total, 0 thin omitted)

### Community 0 - "Offline Product Core"
Cohesion: 0.14
Nodes (17): App Disk, App Compatibility Test Harness, Automerge State Sync, Console UI, DockerHub Image Registry, Engine (Raspberry Pi App), Infrastructure Discipline Rules, Kit (App Dev Agent Proposal) (+9 more)

### Community 1 - "Agent Team & Governance"
Cohesion: 0.21
Nodes (14): Atlas (Operations Manager), Axle (Engine Dev), Beacon (Site Dev), CEO Approval Loop, Cross-Agent Communication via Koen, idea/ Org Root Repo, Koen (CEO), Plan Permission Mode (+6 more)

### Community 2 - "Platform Infrastructure"
Cohesion: 0.25
Nodes (11): platform/compose.yaml, idea-net Docker Network, mc-api Skill, MC Backend Service, MC PostgreSQL DB, MC Frontend Service, MC Kanban Board, Mission Control (+3 more)

### Community 3 - "OpenClaw & Skills"
Cohesion: 0.32
Nodes (8): Agent Skills System, Heartbeat Polling, md-to-pdf Skill, OpenClaw Platform, openclaw.json Config, Telegram Communication, telegram-table Skill (node), telegram-table Skill

### Community 4 - "Backlog & Task Management"
Cohesion: 0.29
Nodes (7): BACKLOG.md, Console Dev Backlog Tasks, Engine Dev Backlog Tasks, Marco (Programme Manager), Pixel (Console Dev), Programme Manager Backlog Tasks, WhatsApp Outbound Communication

### Community 5 - "Agent Identity & Memory"
Cohesion: 0.4
Nodes (6): Agent Memory Layer, AGENTS.md Role File, Identity Files (Atlas-governed), Memory Files (Agent-governed), Claude Prompting Best Practices, SOUL.md Persona File

### Community 6 - "Table Rendering Script"
Cohesion: 0.6
Nodes (4): build_table_image(), main(), measure_text_width(), Rough character-based width estimate (DejaVu Sans, px per char at given pt).

### Community 7 - "PDF Conversion Script"
Cohesion: 0.7
Nodes (4): add_heading_ids(), build_html(), convert(), main()

### Community 8 - "IDEA Mission & Values"
Cohesion: 0.67
Nodes (3): IDEA Mission, Rural African Schools, Teacher-Friendly Principle

### Community 9 - "Nightly Backup System"
Cohesion: 0.67
Nodes (3): agent-identities Backup Repo, Identity Drift Detection, Nightly Backup Cron (03:00 UTC)

## Knowledge Gaps
- **22 isolated node(s):** `Rough character-based width estimate (DejaVu Sans, px per char at given pt).`, `IDEA Mission`, `Automerge State Sync`, `Reliability Over Features`, `Teacher-Friendly Principle` (+17 more)
  These have ≤1 connection - possible missing edges or undocumented components.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Atlas (Operations Manager)` connect `Agent Team & Governance` to `Offline Product Core`, `Nightly Backup System`, `Backlog & Task Management`, `Agent Identity & Memory`?**
  _High betweenness centrality (0.367) - this node is a cross-community bridge._
- **Why does `Engine (Raspberry Pi App)` connect `Offline Product Core` to `Agent Team & Governance`?**
  _High betweenness centrality (0.161) - this node is a cross-community bridge._
- **Why does `idea/ Repo README` connect `Platform Infrastructure` to `Agent Team & Governance`, `OpenClaw & Skills`?**
  _High betweenness centrality (0.132) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `Atlas (Operations Manager)` (e.g. with `Engine (Raspberry Pi App)` and `PR Review Cycle`) actually correct?**
  _`Atlas (Operations Manager)` has 4 INFERRED edges - model-reasoned connections that need verification._
- **What connects `Rough character-based width estimate (DejaVu Sans, px per char at given pt).`, `IDEA Mission`, `Automerge State Sync` to the rest of the system?**
  _22 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Offline Product Core` be split into smaller, more focused modules?**
  _Cohesion score 0.14 - nodes in this community are weakly interconnected._