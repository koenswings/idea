#!/usr/bin/env bash
# md-to-pdf — convert Markdown to PDF using VS Code preview styles
# Runs tsx from engine-dev (for module resolution) while preserving the caller's cwd.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE_DEV="/home/node/workspace/agents/agent-engine-dev"
SCRIPT="$SKILL_DIR/scripts/md-to-pdf.mts"

if [[ ! -d "$ENGINE_DEV/node_modules" ]]; then
  echo "Error: engine-dev node_modules not found at $ENGINE_DEV/node_modules" >&2
  exit 1
fi

export SKILL_DIR
export MD_TO_PDF_INVOKE_CWD="$(pwd)"   # preserved for --all glob

cd "$ENGINE_DEV"
exec node_modules/.bin/tsx "$SCRIPT" "$@"
