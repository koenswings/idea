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
BASE_URL=http://127.0.0.1:8000

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

Each agent stores their own values in `TOOLS.md` and `.env`:

| Key | Description |
|-----|-------------|
| `BASE_URL` | `http://127.0.0.1:8000` (Docker service name — all agents) |
| `AUTH_TOKEN` | Agent-specific token — write access to **own board only** |
| `MC_PLATFORM_TOKEN` | Platform admin token — write access to **any board** (cross-agent tasks) |
| `AGENT_ID` | UUID identifying this agent in Mission Control |
| `BOARD_ID` | UUID of this agent's task board |

## Cross-board writes (cross-agent tasks)

Agent tokens (`AUTH_TOKEN`) are **board-scoped** — they only allow writes to the agent's own board.
To post a task on **another agent's board**, use `MC_PLATFORM_TOKEN` and the admin route:

```bash
# POST a task to another agent's board
python3 -c "
import urllib.request, json, os
token = os.environ['MC_PLATFORM_TOKEN']
base = 'http://127.0.0.1:8000'
board_id = '<TARGET_BOARD_ID>'
payload = json.dumps({
    'title': '[From YourName] Type: Short description',
    'description': '...',
    'status': 'inbox',
    'tags': ['cross-agent']
}).encode()
req = urllib.request.Request(
    f'{base}/api/v1/boards/{board_id}/tasks',
    data=payload,
    headers={'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'},
    method='POST')
with urllib.request.urlopen(req) as r:
    print(json.load(r).get('id'))
"
```

Key differences from the agent route:
- Path: `/api/v1/boards/{board_id}/tasks` (not `/api/v1/agent/boards/...`)
- Auth: `MC_PLATFORM_TOKEN` (not `AUTH_TOKEN`)

Follow the cross-agent task convention in `mc-native-platform-design.md` for title format and
description header (`[From Atlas]`, type, date, self-contained body, depth-1 guard).

## Work cycle — task polling and execution

This is the standard pattern for picking up and completing tasks from Mission Control.

### 1. Poll your board

```bash
source .env
curl -s -H "Authorization: Bearer $AUTH_TOKEN" \
  "$BASE_URL/api/v1/agent/boards/$BOARD_ID/tasks" \
  | python3 -m json.tool
```

Identify tasks that are `inbox` or `in_progress` and not yet started.

### 2. Acknowledge and move to in_progress

Post an acknowledgement comment and set status to `in_progress`.
Use `MC_PLATFORM_TOKEN` + admin route (agent-lead token may not allow `inbox` → `in_progress`):

```bash
curl -s -X PATCH \
  -H "Authorization: Bearer $MC_PLATFORM_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"status":"in_progress","comment":"Picked up by <AgentName>. Starting work."}' \
  "$BASE_URL/api/v1/boards/$BOARD_ID/tasks/$TASK_ID"
```

### 3. Spawn isolated sub-session for implementation

Do the actual work in an isolated sub-session (never inline in a Telegram/cron session).
Use the `coding-agent` skill for code changes.

### 4. Post branch name as task comment

When a feature branch is created, immediately post its name as a task comment so Koen
can find the diff:

```bash
# Branch name convention: feature/<short-description>
# Koen's diff URL: https://github.com/koenswings/<repo>/compare/main...<branch>
curl -s -X PATCH \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"comment":"Branch: feature/my-feature — diff at github.com/koenswings/<repo>/compare/main...feature/my-feature"}' \
  "$BASE_URL/api/v1/agent/boards/$BOARD_ID/tasks/$TASK_ID"
```

### 5. Move task to review when work is ready

```bash
curl -s -X PATCH \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"status":"review","comment":"PR ready for review: <PR URL>"}' \
  "$BASE_URL/api/v1/agent/boards/$BOARD_ID/tasks/$TASK_ID"
```

### 6. Merge detection on approval

When a task moves to `done` (Koen approves), the agent that owned the task should:

1. Detect the status change (via board poll or MC webhook/event)
2. Merge the feature branch:
   ```bash
   git checkout main
   git pull origin main
   git merge --no-ff <branch>
   git push origin main
   ```
3. Post merge confirmation as a task comment:
   ```bash
   curl -s -X PATCH \
     -H "Authorization: Bearer $AUTH_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"comment":"Merged feature/<branch> into main. Commit: <hash>"}' \
     "$BASE_URL/api/v1/agent/boards/$BOARD_ID/tasks/$TASK_ID"
   ```

## Heartbeat

Each agent calls the heartbeat endpoint at the start of **every Telegram-triggered session**
(not cron sessions). This signals liveness to Mission Control.

```bash
curl -s -X POST \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  "$BASE_URL/api/v1/agents/$MC_AGENT_ID/heartbeat"
```

`MC_AGENT_ID` is stored in each agent's `TOOLS.md`. See also `AGENTS.md` for the
full session startup checklist.

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
