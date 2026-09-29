#!/usr/bin/env bash
# check-app-versions.sh — compare each App's app.yaml monitors to upstream (idea#88).
#
# Reads app-*/app.yaml under the App Disk checkout tree, queries DockerHub (and
# http-scrape monitors), and prints a JSON report of available updates for Kid
# to turn into app-update issues (docs/grok-bot-setup.md §5.3).
#
# Usage:
#   tools/quality/check-app-versions.sh [--repo-root DIR] [--apps-dir DIR]
#
# Paths (same nesting as quality-scan.sh):
#   default apps dir → <IDEA_ROOT>/agents/agent-app-dev/
#   --repo-root DIR  → DIR/agents/agent-app-dev/
#   --apps-dir DIR   → use DIR directly (fixtures / selftest)
#
# Exit: 0 scan completed (even when updates or monitor errors are present),
#       2 usage / missing dependency / apps dir missing.
#
# Needs: node, js-yaml (resolvable from this machine — Cursor box and Pis that
# already run Console tooling have it), network for Hub / scrape URLs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IDEA_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "${IDEA_ROOT}" ]] || { echo "ERROR: cannot resolve idea repo root" >&2; exit 2; }

REPO_ROOT=""
APPS_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root) REPO_ROOT="${2:-}"; shift 2 ;;
    --apps-dir)  APPS_DIR="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$APPS_DIR" ]]; then
  if [[ -n "$REPO_ROOT" ]]; then
    APPS_DIR="${REPO_ROOT}/agents/agent-app-dev"
  else
    APPS_DIR="${IDEA_ROOT}/agents/agent-app-dev"
  fi
fi

if [[ ! -d "$APPS_DIR" ]]; then
  echo "ERROR: apps dir not found: $APPS_DIR" >&2
  echo "Hint: clone app-* under agents/agent-app-dev/, or pass --apps-dir /path/to/parent-of-app-*" >&2
  exit 2
fi

command -v node >/dev/null || { echo "ERROR: node not found" >&2; exit 2; }

# Prefer js-yaml next to a known Console install, then NODE_PATH, then bare require.
export NODE_PATH="${NODE_PATH:-}${NODE_PATH:+:}/workspace/agent-console-dev/node_modules:${IDEA_ROOT}/agents/agent-console-dev/node_modules:${HOME}/idea/agents/agent-console-dev/node_modules"

exec node "$SCRIPT_DIR/lib-check-app-versions.mjs" --apps-dir "$APPS_DIR"
