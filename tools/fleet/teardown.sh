#!/usr/bin/env bash
# teardown.sh <pi>
# Reverse deploy: restore main under nested checkout
#   agent-*-dev → /home/pi/idea/agents/<repo>
#   app-*       → /home/pi/idea/agents/agent-app-dev/<repo>
# mark Pi idle in fleet-state.json.
# Runs on review Pis only (role: review). The golden Pi is never torn down; after a
# merge it is moved to main by update-golden.sh (idea#118).
# Paths: see proposals/pi-checkout-layout.md
#
# TODO: implement in Phase 2
echo "stub: teardown.sh not yet implemented" >&2
exit 1
