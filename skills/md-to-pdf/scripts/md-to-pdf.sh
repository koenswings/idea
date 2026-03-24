#!/usr/bin/env bash
# md-to-pdf — convert Markdown to PDF using VS Code preview styles
#
# Current approach: pure Python (python3-markdown + weasyprint)
#   - Both packages are pre-installed in the OpenClaw container
#   - No npm dependencies, no system-level extras, no post-clone setup
#
# ------------------------------------------------------------------------
# PREVIOUS APPROACH (Node.js / TypeScript) — kept for fallback reference
# ------------------------------------------------------------------------
# The original implementation used tsx + md-to-pdf.mts:
#
#   ENGINE_DEV="/home/node/workspace/agents/agent-engine-dev"
#   export SKILL_DIR
#   export MD_TO_PDF_INVOKE_CWD="$(pwd)"
#   cd "$ENGINE_DEV"
#   exec node_modules/.bin/tsx "$SKILL_DIR/scripts/md-to-pdf.mts" "$@"
#
# Requirements for the old approach:
#   1. agent-engine-dev cloned and pnpm install run
#   2. node_modules symlink:
#        ln -s $ENGINE_DEV/node_modules $SKILL_DIR/scripts/node_modules
#   3. chromium installed in container:
#        apt-get install -y chromium
#
# To revert: replace the exec line below with the block above.
# ------------------------------------------------------------------------
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$SKILL_DIR/scripts/md-to-pdf.py"

export SKILL_DIR
export MD_TO_PDF_INVOKE_CWD="$(pwd)"

exec python3 "$SCRIPT" "$@"
