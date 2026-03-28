#!/usr/bin/env bash
# mc-refresh — fetch the Mission Control OpenAPI spec and generate the agent-lead TSV.
# Run from your agent workspace root before any API-heavy session.
set -euo pipefail

BASE_URL="${BASE_URL:-http://mission-control-backend:8000}"
SPEC_DIR="${1:-api}"   # optional: pass a different output dir

mkdir -p "$SPEC_DIR"

echo "Fetching OpenAPI spec from $BASE_URL..."
curl -fsS "$BASE_URL/openapi.json" -o "$SPEC_DIR/openapi.json"

echo "Generating agent-lead operations TSV..."
jq -r '
  .paths | to_entries[] as $p |
  $p.value | to_entries[] |
  select((.value.tags // []) | index("agent-lead")) |
  "\(.key|ascii_upcase)\t\($p.key)\t\(.value.operationId // "-")\t\(.value["x-llm-intent"] // "-")\t\(.value["x-when-to-use"] // [] | join(" | "))\t\(.value["x-routing-policy"] // [] | join(" | "))"
' "$SPEC_DIR/openapi.json" | sort > "$SPEC_DIR/agent-lead-operations.tsv"

COUNT=$(wc -l < "$SPEC_DIR/agent-lead-operations.tsv")
echo "Done — $COUNT agent-lead operations written to $SPEC_DIR/agent-lead-operations.tsv"
