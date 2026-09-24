#!/usr/bin/env bash
# idea-setup.sh — enrol a Pi into the IDEA fleet
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
# See: proposals/pi-checkout-layout.md, docs/grok-bot-setup.md §2.3.1
#
# TODO: implement in Phase 2
echo "stub: idea-setup.sh not yet implemented" >&2
exit 1
