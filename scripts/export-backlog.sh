#!/usr/bin/env bash
# export-backlog.sh — Regenerate BACKLOG.md from Mission Control task data
#
# Reads task data directly from the Mission Control PostgreSQL database.
# Writes BACKLOG.md to the idea org root.
#
# Usage: bash scripts/export-backlog.sh
# Run from any directory; resolves paths relative to script location.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
BACKLOG_FILE="$REPO_ROOT/BACKLOG.md"
DB_CONTAINER="openclaw-mission-control-db-1"
TIMESTAMP=$(date -u '+%Y-%m-%d %H:%M UTC')

echo "Querying Mission Control tasks..."

# Status ordering: in_progress first, then inbox, then done
TASKS_JSON=$(docker exec "$DB_CONTAINER" psql -U postgres -d mission_control -t -A -c "
SELECT json_agg(row_to_json(t) ORDER BY
    CASE t.status
        WHEN 'in_progress' THEN 1
        WHEN 'inbox'       THEN 2
        WHEN 'review'      THEN 3
        WHEN 'done'        THEN 4
        ELSE 5
    END,
    t.title
)
FROM (
    SELECT b.name as board, t.status, t.title
    FROM tasks t
    JOIN boards b ON b.id = t.board_id
    WHERE t.status NOT IN ('done', 'cancelled')
    ORDER BY b.name, t.status, t.title
) t;
")

python3 - "$TASKS_JSON" "$TIMESTAMP" "$BACKLOG_FILE" << 'PYEOF'
import sys, json

tasks_json, timestamp, outfile = sys.argv[1], sys.argv[2], sys.argv[3]

if not tasks_json or tasks_json.strip() == 'null':
    tasks = []
else:
    tasks = json.loads(tasks_json)

# Group by board
boards = {}
for t in tasks:
    board = t['board']
    boards.setdefault(board, []).append(t)

# Board display order and agent mapping
BOARD_ORDER = ['Engine Dev', 'Console Dev', 'Site Dev', 'Programme Manager', 'Quality Manager']
BOARD_LABELS = {
    'Engine Dev':        'Engine Dev (Axle)',
    'Console Dev':       'Console Dev (Pixel)',
    'Site Dev':          'Site Dev (Beacon)',
    'Programme Manager': 'Programme Manager (Marco)',
    'Quality Manager':   'Quality Manager (Atlas)',
}

STATUS_LABELS = {
    'in_progress': 'In Progress',
    'inbox':       'Inbox',
    'review':      'In Review',
}

lines = [
    f'<!-- Auto-exported from Mission Control {timestamp}. Do not edit manually. -->',
    '',
    '# BACKLOG.md — IDEA Agent Task Board',
    '',
    'All items here are approved by the CEO and tracked in Mission Control.',
    'To propose a new item, follow the process in `PROCESS.md`.',
    '',
    '---',
    '',
]

for board_name in BOARD_ORDER:
    if board_name not in boards:
        continue
    label = BOARD_LABELS.get(board_name, board_name)
    lines.append(f'## {label}')
    lines.append('')

    # Group by status
    by_status = {}
    for t in boards[board_name]:
        by_status.setdefault(t['status'], []).append(t['title'])

    for status in ['in_progress', 'review', 'inbox']:
        if status not in by_status:
            continue
        lines.append(f'### {STATUS_LABELS[status]}')
        for title in by_status[status]:
            lines.append(f'- [ ] {title}')
        lines.append('')

with open(outfile, 'w') as f:
    f.write('\n'.join(lines))

total = sum(len(v) for v in boards.values())
print(f"Written {total} tasks across {len(boards)} boards to {outfile}")
PYEOF

echo "Done. BACKLOG.md updated."
