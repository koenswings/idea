#!/usr/bin/env bash
# idea-setup.sh — enrol a Pi into the IDEA fleet
#
# Usage:
#   tools/fleet/idea-setup.sh [--with-grok-build] [-h|--help]
#
# Options:
#   --with-grok-build   Also install Grok Build and register the GitHub Actions
#                       self-hosted runner. OFF by default: that coding path is
#                       parked (idea#147, docs/grok-bot-setup.md §2.2). Pis are
#                       test/review/golden hardware; Dev Bots test over SSH.
#   -h, --help          Show this help.
#
# Default (no flags): platform install only. Discover idea* Pis via Tailscale,
# verify dependencies, initialise fleet-state.json. No Grok Build, no runner;
# new Pis get runner "none" and grok_build null in fleet-state.json.
#
# Canonical checkout layout (Koen locked 2026-09-24; apps under agent-app-dev):
#   Clone idea → /home/pi/idea
#   Clone agent repos into /home/pi/idea/agents/<name>:
#     agent-engine-dev, agent-console-dev, agent-app-dev
#   Clone App GitHub repos as direct children of agent-app-dev:
#     …/agents/agent-app-dev/app-kolibri, app-nextcloud, app-kiwix, app-milkwise, …
#   (Not under agent-app-dev/apps/ — that is in-repo harness content.)
# Retired paths (do not use as primary): /home/pi/projects/engine,
#   /home/pi/console-dist, /home/pi/agent-*-dev as siblings of idea,
#   app-* as siblings of agent-*-dev under idea/agents/.
# See: proposals/pi-checkout-layout.md, proposals/dev-bot-workflow.md,
#      docs/grok-bot-setup.md §2.2 and §2.3.1

set -euo pipefail

usage() { sed -n '2,/^# Default/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

WITH_GROK_BUILD=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-grok-build) WITH_GROK_BUILD=1; shift ;;
    -h|--help)         usage; exit 0 ;;
    *)                 echo "ERROR: unknown option: $1 (see --help)" >&2; exit 2 ;;
  esac
done

if [[ $WITH_GROK_BUILD -eq 1 ]]; then
  echo "Plan: platform install + Grok Build + GitHub Actions runner (opt-in, parked path)" >&2
else
  echo "Plan: platform install only (Grok Build and runner skipped; use --with-grok-build to add them)" >&2
fi

# TODO(idea#147): implement the platform install steps in Phase 2
echo "stub: idea-setup.sh not yet implemented" >&2
exit 1
