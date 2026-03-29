#!/usr/bin/env bash
# run-tests.sh — Engine test wrapper for restricted SSH key
#
# This script is the target of the `command=` restriction in authorized_keys for the
# openclaw-container→pi-host-tests key. The OpenClaw container connects to the Pi host
# via SSH and this script runs automatically — the caller cannot execute anything else.
#
# Usage (from authorized_keys):
#   command="/home/pi/idea/scripts/run-tests.sh",from="172.20.0.0/24",restrict ssh-ed25519 ...
#
# Design doc: design/ssh-key-management.md

set -euo pipefail

ENGINE_DIR="/home/pi/idea/agent-engine-dev"

echo "[run-tests] Starting engine test run on $(hostname) at $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Pull latest engine code
echo "[run-tests] Pulling latest code..."
cd "$ENGINE_DIR"
git pull --ff-only

# Install dependencies if needed
echo "[run-tests] Installing dependencies..."
pnpm install --frozen-lockfile

# Build
echo "[run-tests] Building..."
pnpm build

# Run tests
echo "[run-tests] Running unit tests..."
IDEA_TEST_MODE=true pnpm test:unit

echo "[run-tests] Done."
