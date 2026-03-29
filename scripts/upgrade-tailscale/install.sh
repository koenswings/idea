#!/usr/bin/env bash
# upgrade-tailscale/install.sh
# Installs Tailscale debug mode on a field Engine Pi (offline, from USB drive).
# Run as root: sudo bash install.sh
#
# What this does:
#   1. Installs tailscale + tailscaled binaries to /usr/sbin/
#   2. Installs systemd service (disabled — does NOT start Tailscale)
#   3. Stores the debug auth key at /etc/tailscale/debug-authkey
#   4. Installs the activation script at /usr/local/bin/tailscale-debug-activate.sh
#
# What this does NOT do:
#   - Start or enable the Tailscale service
#   - Change any Engine, Docker, or network configuration
#   - Require internet access
#
# Idempotent: safe to run again for key rotation or binary update.
#
# Design doc: idea/design/tailscale-remote-management.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/home/pi/upgrade-tailscale.log"
TS_VERSION="unknown"

log() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOG_FILE"; }

log "=== Tailscale debug mode upgrade ==="
log "Started: $(date -u)"

# ── Check running as root ────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: run as root: sudo bash install.sh" >&2
  exit 1
fi

# ── Extract and install Tailscale binaries ───────────────────────────────────
log "Extracting Tailscale binaries..."
TARBALL=$(ls "$SCRIPT_DIR"/tailscale_*.tgz 2>/dev/null | head -1)
if [[ -z "$TARBALL" ]]; then
  log "ERROR: No tailscale_*.tgz found in $(dirname "$0")"
  exit 1
fi

TS_VERSION=$(basename "$TARBALL" | grep -oP '[\d.]+(?=_arm64)')
log "Tailscale version: $TS_VERSION"

TMPDIR=$(mktemp -d)
tar -xzf "$TARBALL" -C "$TMPDIR"
TS_DIR=$(ls -d "$TMPDIR"/tailscale_*/ 2>/dev/null | head -1)

cp "$TS_DIR/tailscale"  /usr/sbin/tailscale
cp "$TS_DIR/tailscaled" /usr/sbin/tailscaled
chmod 755 /usr/sbin/tailscale /usr/sbin/tailscaled
rm -rf "$TMPDIR"
log "Binaries installed to /usr/sbin/"

# ── Install systemd service (disabled) ──────────────────────────────────────
log "Installing systemd service (disabled)..."
cp "$SCRIPT_DIR/tailscaled.service" /etc/systemd/system/tailscaled.service
systemctl daemon-reload
systemctl disable tailscaled 2>/dev/null || true  # ensure disabled; no-op if already
log "Service installed — disabled, will not start automatically"

# ── Store debug auth key ─────────────────────────────────────────────────────
log "Installing debug auth key..."
if [[ ! -f "$SCRIPT_DIR/debug-authkey" ]]; then
  log "ERROR: debug-authkey not found in package. Contact IDEA technical team."
  exit 1
fi
mkdir -p /etc/tailscale
cp "$SCRIPT_DIR/debug-authkey" /etc/tailscale/debug-authkey
chown root:root /etc/tailscale/debug-authkey
chmod 600 /etc/tailscale/debug-authkey
log "Auth key installed at /etc/tailscale/debug-authkey"

# ── Install activation script ────────────────────────────────────────────────
log "Installing activation script..."
cp "$SCRIPT_DIR/tailscale-debug-activate.sh" /usr/local/bin/tailscale-debug-activate.sh
chmod 755 /usr/local/bin/tailscale-debug-activate.sh
log "Activation script installed at /usr/local/bin/tailscale-debug-activate.sh"

# ── Verify ───────────────────────────────────────────────────────────────────
log "Verifying installation..."
/usr/sbin/tailscale version > /dev/null && log "  tailscale binary: OK"
systemctl is-enabled tailscaled | grep -q disabled && log "  service disabled: OK"
[[ "$(stat -c %a /etc/tailscale/debug-authkey)" == "600" ]] && log "  auth key permissions: OK"

# ── Write receipt ────────────────────────────────────────────────────────────
cat >> "$LOG_FILE" << EOF

Upgrade receipt
  Version:   $TS_VERSION
  Date:      $(date -u +%Y-%m-%d)
  Result:    SUCCESS
  Pi model:  $(cat /proc/device-tree/model 2>/dev/null | tr -d '\0' || echo "unknown")
  Hostname:  $(hostname)
EOF

log ""
log "Installation complete."
log "Tailscale is installed but DISABLED — no change to normal Pi operation."
log "To activate remote support: sudo /usr/local/bin/tailscale-debug-activate.sh"
