#!/usr/bin/env bash
# deploy.sh <pi> <component> <repo> <branch>
# Full deploy sequence for engine | console | app-disk.
#
# Canonical paths on Pi (Koen locked 2026-09-24):
#   Engine:  cwd /home/pi/idea/agents/agent-engine-dev
#            ENGINE_CWD / ENGINE_BIN under that tree; pm2 restart engine
#   Console: build in /home/pi/idea/agents/agent-console-dev → dist/
#            Engine config consolePath =
#            /home/pi/idea/agents/agent-console-dev/dist
#            (no separate /home/pi/console-dist as primary)
#   App Disk: rsync under agents trees as needed
# See: proposals/pi-checkout-layout.md, docs/grok-bot-setup.md §4.3
#
# TODO: implement in Phase 2
echo "stub: deploy.sh not yet implemented" >&2
exit 1
