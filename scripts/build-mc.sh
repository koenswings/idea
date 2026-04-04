#!/bin/bash
# build-mc.sh — Rebuild Mission Control images from source
#
# Run this on the Pi when:
#   - Pulling upstream MC updates (git pull in platform/mission-control/)
#   - Changing NEXT_PUBLIC_API_URL (e.g. after hostname change)
#   - First-time setup on a new Pi
#
# The MC frontend bakes NEXT_PUBLIC_API_URL at build time (Next.js static export).
# This URL must match the Tailscale hostname of the Pi running the stack.
# Permanent hostname convention: openclaw-pi (Tailscale), openclaw-pi.tail2d60.ts.net
#
# Usage:
#   cd /home/pi/idea
#   sudo bash scripts/build-mc.sh

set -e

PLATFORM_DIR="/home/pi/idea/platform"
MC_DIR="$PLATFORM_DIR/mission-control"
TAILSCALE_HOST="openclaw-pi.tail2d60.ts.net"
API_URL="https://${TAILSCALE_HOST}:8000"

echo "Building Mission Control images for ARM64..."
echo "  NEXT_PUBLIC_API_URL = $API_URL"
echo ""

cd "$MC_DIR"

# Build backend
echo "--- Building backend ---"
docker build -t openclaw-mission-control-backend .

# Build frontend with baked API URL
echo "--- Building frontend ---"
docker build \
  --build-arg NEXT_PUBLIC_API_URL="$API_URL" \
  -t openclaw-mission-control-frontend \
  -f Dockerfile.frontend . 2>/dev/null || \
docker build \
  --build-arg NEXT_PUBLIC_API_URL="$API_URL" \
  -t openclaw-mission-control-frontend \
  ./frontend 2>/dev/null || \
docker compose -f "$PLATFORM_DIR/compose.yaml" build \
  --build-arg NEXT_PUBLIC_API_URL="$API_URL" \
  mission-control-frontend

echo ""
echo "Build complete. Restart containers with:"
echo "  sudo docker compose -f $PLATFORM_DIR/compose.yaml up -d"
