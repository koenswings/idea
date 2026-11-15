#!/usr/bin/env bash
# check-app-versions.sh — compare each App's monitors to upstream (idea#88, idea#543).
#
# Reads app-*/app.yaml under an apps directory, queries Docker Hub, GHCR, PyPI,
# GitHub Releases, and http-scrape monitors, and prints a JSON report of
# available updates for Kid to turn into app-update issues
# (docs/grok-bot-setup.md §5.3).
#
# Usage:
#   tools/quality/check-app-versions.sh [--repo-root DIR] [--apps-dir DIR]
#
# Paths:
#   default apps dir → <IDEA_ROOT>/agents/agent-app-dev/
#                       (canonical Pi / local layout: app-* live there)
#   --repo-root DIR  → DIR/agents/agent-app-dev/
#   --apps-dir DIR   → use DIR directly (a folder that contains app-* clones;
#                       fixtures, the Monday scan checkout, selftest)
#
# Requirements:
#   - node (the library is tools/quality/lib-check-app-versions.mjs)
#   - js-yaml, shipped via tools/quality/package.json. Install once from the
#     idea checkout:  (cd tools/quality && npm install)
#     If node_modules is missing, this wrapper tries that install and exits 2
#     with the same command when npm is unavailable or the install fails.
#   - network for Hub / GHCR / PyPI / GitHub / scrape URLs
#
# Exit: 0 scan completed (even when updates, warnings, or monitor errors are
#       present), 2 usage / missing dependency / apps dir missing.
#
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
      sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
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
  echo "Hint: pass --apps-dir /path/to/parent-of-app-* (a directory containing app-kolibri, app-nextcloud, …)," >&2
  echo "      or clone app-* under agents/agent-app-dev/ and use the default path." >&2
  exit 2
fi

command -v node >/dev/null || { echo "ERROR: node not found" >&2; exit 2; }

ensure_js_yaml() {
  if [[ -d "${SCRIPT_DIR}/node_modules/js-yaml" ]]; then
    return 0
  fi
  if [[ -f "${SCRIPT_DIR}/package.json" ]] && command -v npm >/dev/null; then
    echo "check-app-versions: js-yaml missing; running (cd tools/quality && npm install)" >&2
    if (cd "$SCRIPT_DIR" && npm install --omit=dev --no-fund --no-audit); then
      [[ -d "${SCRIPT_DIR}/node_modules/js-yaml" ]] && return 0
    fi
  fi
  echo "ERROR: js-yaml is required but is not installed." >&2
  echo "From the idea checkout run: (cd tools/quality && npm install)" >&2
  echo "The dependency is declared in tools/quality/package.json (idea#543)." >&2
  exit 2
}

ensure_js_yaml

exec node "$SCRIPT_DIR/lib-check-app-versions.mjs" --apps-dir "$APPS_DIR"
