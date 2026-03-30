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

ENGINE_DIR="/home/pi/idea/agents/agent-engine-dev"

echo "[run-tests] Starting engine test run on $(hostname) at $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Pull latest engine code
echo "[run-tests] Pulling latest code..."
cd "$ENGINE_DIR"
git pull --ff-only origin $(git rev-parse --abbrev-ref HEAD)

# Clear any root-owned build artefacts left by sandbox builds.
# The OpenClaw sandbox runs as root and shares the Pi's filesystem. When a sandbox
# build leaves dist/ owned by root, pnpm clean (rm -fr dist/*) fails as the pi user.
# sudo rm -rf is safe here: dist/ is gitignored and always rebuilt fresh.
echo "[run-tests] Cleaning dist/..."
sudo rm -rf "$ENGINE_DIR/dist/"

# Install dependencies if needed.
# CI=true: allows pnpm to remove/reinstall node_modules without a TTY. Required when
# the lockfile changed since the last install (e.g. a new devDependency was added in
# the sandbox and the updated pnpm-lock.yaml was pushed to the branch).
echo "[run-tests] Installing dependencies..."
CI=true pnpm install --frozen-lockfile

# Build
echo "[run-tests] Building..."
pnpm build

# Run tests
echo "[run-tests] Running unit tests..."
IDEA_TEST_MODE=true pnpm test:unit

echo "[run-tests] Done."
