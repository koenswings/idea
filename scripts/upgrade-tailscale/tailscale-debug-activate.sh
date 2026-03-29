#!/usr/bin/env bash
# tailscale-debug-activate.sh
# Activates Tailscale remote support mode on a school Pi.
# Run as root: sudo /usr/local/bin/tailscale-debug-activate.sh
#
# Requirements:
#   - Pi must have internet access (connect to 4G hotspot before running)
#   - Tailscale must be installed (run upgrade/install.sh first)
#
# What this does:
#   1. Starts the Tailscale daemon
#   2. Joins the IDEA Tailnet using the pre-provisioned ephemeral auth key
#   3. Prints the Pi's Tailscale IP for you to send to IDEA staff
#   4. Waits — press Enter when the support session is done
#   5. Disconnects from the Tailnet and stops the daemon
#
# The Pi returns to fully offline mode after this script ends.
# Design doc: idea/design/tailscale-remote-management.md

set -euo pipefail

AUTH_KEY_FILE="/etc/tailscale/debug-authkey"

# ── Check root ───────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: run as root: sudo /usr/local/bin/tailscale-debug-activate.sh" >&2
  exit 1
fi

# ── Check prerequisites ──────────────────────────────────────────────────────
if [[ ! -x /usr/sbin/tailscaled ]]; then
  echo "ERROR: Tailscale not installed. Contact IDEA technical team." >&2
  exit 1
fi
if [[ ! -f "$AUTH_KEY_FILE" ]]; then
  echo "ERROR: Auth key missing at $AUTH_KEY_FILE. Contact IDEA technical team." >&2
  exit 1
fi

echo ""
echo "============================================"
echo "  IDEA Remote Support Mode"
echo "============================================"
echo ""
echo "Starting Tailscale..."

# ── Start daemon ─────────────────────────────────────────────────────────────
systemctl start tailscaled
sleep 2

# ── Join Tailnet ─────────────────────────────────────────────────────────────
AUTH_KEY=$(cat "$AUTH_KEY_FILE")
/usr/sbin/tailscale up \
  --authkey "$AUTH_KEY" \
  --ephemeral \
  --advertise-tags=tag:school-pi \
  --hostname "$(hostname)" \
  2>&1

sleep 3

# ── Print IP ─────────────────────────────────────────────────────────────────
TS_IP=$(/usr/sbin/tailscale ip -4 2>/dev/null || echo "unknown")

echo ""
echo "--------------------------------------------"
echo "  Remote support is ACTIVE"
echo ""
echo "  This Pi's address: $TS_IP"
echo "  Hostname:          $(hostname)"
echo ""
echo "  Send this address to IDEA staff now."
echo "--------------------------------------------"
echo ""
echo "Press ENTER when the support session is finished..."
read -r

# ── Disconnect ───────────────────────────────────────────────────────────────
echo ""
echo "Ending remote support session..."
/usr/sbin/tailscale down
systemctl stop tailscaled

echo ""
echo "Done. Remote support mode is OFF."
echo "This Pi is offline again."
echo ""
