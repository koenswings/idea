#!/usr/bin/env bash
# update-golden.sh <component> <version>
# Deploy merged main of a component onto the golden Pi.
# Golden Pi = the one Pi with role: golden in fleet-state.json (today idea02,
# dedicated since idea#118; it is never a review Pi). After the deploy and health
# check, update its version field ("engine main@<sha>, console main@<sha>") with
# update-fleet-state.sh. Its status stays idle. Until implemented (idea#107), Ops
# does these steps by hand.
# Operates under nested checkout:
#   engine/console/app-dev → /home/pi/idea/agents/<agent-*-dev>
#   app-disk / app-*       → /home/pi/idea/agents/agent-app-dev/<app-*>
# See: proposals/pi-checkout-layout.md
#
# TODO: implement in Phase 2
echo "stub: update-golden.sh not yet implemented" >&2
exit 1
