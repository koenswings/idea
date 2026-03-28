---
name: mc-api
description: Interact with the Mission Control API. Use when reading tasks, updating task status, posting comments, checking board state, or fetching approvals. Run the OpenAPI refresh before any API-heavy session.
---

# mc-api — Mission Control API

Gives agents a consistent, discoverable way to use the Mission Control REST API.
Credentials and agent-specific IDs live in each agent's `TOOLS.md` and `.env`.

## Quick start

```bash
# 1. Load credentials
source .env                    # loads AUTH_TOKEN
BASE_URL=http://mission-control-backend:8000

# 2. Refresh the OpenAPI spec (do this at the start of any API-heavy session)
/home/node/workspace/skills/mc-api/scripts/mc-refresh.sh

# 3. Discover operations
cat api/agent-lead-operations.tsv   # METHOD | PATH | OP_ID | INTENT | WHEN | POLICY
```

## Discovery policy

- Use only operations tagged `agent-lead` (in the TSV).
- Match the operation whose `X_WHEN_TO_USE` best fits your current objective.
- Derive exact method, path, and request schema from `api/openapi.json` at runtime.
- **Do not hardcode endpoint paths** in markdown files or scripts.

## Safety rule

If no operation confidently matches your intent, ask the CEO one clarifying question
before making any API call. Do not guess at endpoints.

## Credentials reference

Each agent stores their own values in `TOOLS.md`:

| Key | Description |
|-----|-------------|
| `BASE_URL` | `http://mission-control-backend:8000` (Docker service name — all agents) |
| `AUTH_TOKEN` | Agent-specific token — load from `.env`, never commit |
| `AGENT_ID` | UUID identifying this agent in Mission Control |
| `BOARD_ID` | UUID of this agent's task board |

## Common operations (examples only — always derive from spec)

```bash
# Fetch your board
curl -s -H "Authorization: Bearer $AUTH_TOKEN" \
  "$BASE_URL/api/v1/agent/boards/$BOARD_ID"

# List tasks on your board
curl -s -H "Authorization: Bearer $AUTH_TOKEN" \
  "$BASE_URL/api/v1/agent/boards/$BOARD_ID/tasks"

# Update a task status
curl -s -X PATCH \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"status":"done"}' \
  "$BASE_URL/api/v1/agent/boards/$BOARD_ID/tasks/$TASK_ID"
```
