#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# install.sh — Install Tailscale debug mode on a school Pi
#
# USAGE (run via SSH from Tapiwa's laptop):
#   ssh pi@engine-1.local
#   sudo mkdir -p /mnt/usb && sudo mount /dev/sda1 /mnt/usb
#   sudo bash /mnt/usb/upgrade-tailscale/install.sh
#
# WHAT THIS DOES:
#   1. Installs tailscale and tailscaled binaries to /usr/sbin/
#   2. Installs the systemd service (disabled — does not start on boot)
#   3. Installs the Tailscale auth key to /etc/tailscale/debug-authkey
#   4. Installs the activation script to /usr/local/bin/
#   5. Configures wlan0 with a persistent connection to Tapiwa's Starlink
#   6. Writes an upgrade receipt to /home/pi/upgrade-tailscale.log
#
# IDEMPOTENT: safe to re-run (key rotation, script updates).
#
# REQUIRES: USB drive mounted at a path discoverable relative to this script.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

USB_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="/home/pi/upgrade-tailscale.log"

info()  { echo -e "\033[1;34m[install]\033[0m $*"; }
ok()    { echo -e "\033[1;32m[install]\033[0m $*"; }
warn()  { echo -e "\033[1;33m[install]\033[0m $*"; }
die()   { echo -e "\033[1;31m[install]\033[0m $*" >&2; exit 1; }

# ── Preflight ─────────────────────────────────────────────────────────────────

[[ $EUID -eq 0 ]] || die "Must run as root (use sudo)"
[[ -f "$USB_DIR/tailscale_arm64.tgz" ]] || die "tailscale_arm64.tgz not found in $USB_DIR"
[[ -f "$USB_DIR/debug-authkey" ]]       || die "debug-authkey not found in $USB_DIR"
[[ -f "$USB_DIR/tailscaled.service" ]]  || die "tailscaled.service not found in $USB_DIR"

info "Starting Tailscale upgrade at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
info "USB package: $USB_DIR"

# ── Step 1: Tailscale binaries ────────────────────────────────────────────────

info "Extracting Tailscale binaries..."
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

tar -xzf "$USB_DIR/tailscale_arm64.tgz" -C "$TMPDIR"
TSDIR=$(ls -d "$TMPDIR"/tailscale_*)
cp "$TSDIR/tailscale"  /usr/sbin/tailscale
cp "$TSDIR/tailscaled" /usr/sbin/tailscaled
chmod 755 /usr/sbin/tailscale /usr/sbin/tailscaled

TSVER=$(tailscale version | head -1)
ok "Binaries installed: $TSVER"

# ── Step 2: systemd service ───────────────────────────────────────────────────

info "Installing tailscaled.service..."
cp "$USB_DIR/tailscaled.service" /etc/systemd/system/tailscaled.service
systemctl daemon-reload
systemctl disable tailscaled 2>/dev/null || true   # ensure it stays disabled
ok "Service installed (disabled — will not start on boot)"

# ── Step 3: Auth key ──────────────────────────────────────────────────────────

info "Installing Tailscale auth key..."
mkdir -p /etc/tailscale
cp "$USB_DIR/debug-authkey" /etc/tailscale/debug-authkey
chmod 600 /etc/tailscale/debug-authkey
chown root:root /etc/tailscale/debug-authkey
ok "Auth key installed at /etc/tailscale/debug-authkey (600 root)"

# ── Step 4: Activation script ─────────────────────────────────────────────────

info "Installing activation script..."
cp "$USB_DIR/tailscale-debug-activate.sh" /usr/local/bin/tailscale-debug-activate.sh
chmod 755 /usr/local/bin/tailscale-debug-activate.sh
ok "Activation script installed at /usr/local/bin/tailscale-debug-activate.sh"

# ── Step 5: wlan0 Starlink connection (persistent) ───────────────────────────

if [[ -f "$USB_DIR/starlink.conf" ]]; then
  info "Configuring wlan0 for Starlink WiFi (persistent)..."
  # shellcheck source=/dev/null
  source "$USB_DIR/starlink.conf"

  # Delete any existing connection with this SSID to avoid conflicts
  nmcli connection delete "$STARLINK_SSID" 2>/dev/null || true

  if nmcli device wifi connect "$STARLINK_SSID" \
       password "$STARLINK_PASSWORD" \
       ifname wlan0 2>/dev/null; then
    STARLINK_IP=$(ip -4 addr show wlan0 | grep -oP '(?<=inet )\d+\.\d+\.\d+\.\d+' || echo "no IP yet")
    ok "wlan0 connected to '$STARLINK_SSID' (IP: $STARLINK_IP)"
    ok "Connection is persistent — Pi will auto-connect whenever Starlink is in range"
  else
    warn "Starlink not in range right now — wlan0 configured but not connected"
    warn "Pi will connect automatically when '$STARLINK_SSID' is available"
    # Add the connection profile so it auto-connects later
    nmcli connection add type wifi ifname wlan0 \
      con-name "$STARLINK_SSID" \
      ssid "$STARLINK_SSID" \
      wifi-sec.key-mgmt wpa-psk \
      wifi-sec.psk "$STARLINK_PASSWORD" \
      connection.autoconnect yes 2>/dev/null || true
  fi
else
  warn "starlink.conf not found — skipping wlan0 configuration"
  warn "wlan0 can be configured manually later with:"
  warn "  nmcli device wifi connect <SSID> password <PASSWORD> ifname wlan0"
fi

# ── Step 6: Upgrade receipt ───────────────────────────────────────────────────

{
  echo "---"
  echo "Date:              $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Tailscale version: $TSVER"
  echo "Hostname:          $(hostname)"
  echo "Status:            SUCCESS"
} >> "$LOG"
chown pi:pi "$LOG"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Tailscale upgrade complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Tailscale: installed (service DISABLED)"
echo "  Normal Pi operation: unchanged"
echo "  Log: $LOG"
echo ""
echo "  To activate remote support: sudo /usr/local/bin/tailscale-debug-activate.sh"
echo ""
