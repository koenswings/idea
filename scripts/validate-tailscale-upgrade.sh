#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# validate-tailscale-upgrade.sh — Validate a Tailscale upgrade on a school Pi
#
# USAGE (Atlas runs this remotely):
#   ssh pi@<test-pi-ip> 'bash -s' < scripts/validate-tailscale-upgrade.sh
#
# WHAT THIS CHECKS:
#   - Tailscale binaries present and executable
#   - systemd service file installed and DISABLED (must not auto-start)
#   - Auth key present with correct permissions (600, root-owned)
#   - Activation script installed
#   - Upgrade log written
#   - Docker still running and Engine containers up
#   - wlan0 configured (if Starlink was in range during install)
#
# EXIT CODE: 0 if all checks pass, 1 if any fail.
# ─────────────────────────────────────────────────────────────────────────────

set -uo pipefail

PASS=0
FAIL=0
WARN=0

pass() { echo "  ✓ PASS  $1"; ((PASS++)); }
fail() { echo "  ✗ FAIL  $1"; ((FAIL++)); }
warn() { echo "  ⚠ WARN  $1"; ((WARN++)); }
section() { echo ""; echo "── $1 ──"; }

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Tailscale upgrade validation — $(hostname)"
echo " $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Binaries ──────────────────────────────────────────────────────────────────
section "Binaries"

if [[ -x /usr/sbin/tailscale ]]; then
  pass "tailscale binary present and executable"
else
  fail "tailscale binary missing or not executable at /usr/sbin/tailscale"
fi

if [[ -x /usr/sbin/tailscaled ]]; then
  pass "tailscaled binary present and executable"
else
  fail "tailscaled binary missing or not executable at /usr/sbin/tailscaled"
fi

if /usr/sbin/tailscale version &>/dev/null; then
  TS_VERSION=$(/usr/sbin/tailscale version | head -1)
  pass "tailscale version: $TS_VERSION"
else
  fail "tailscale version command failed"
fi

# ── systemd service ───────────────────────────────────────────────────────────
section "systemd service"

if [[ -f /etc/systemd/system/tailscaled.service ]]; then
  pass "tailscaled.service file present"
else
  fail "tailscaled.service not found at /etc/systemd/system/tailscaled.service"
fi

if ! systemctl is-enabled tailscaled &>/dev/null; then
  pass "service is DISABLED (correct — must not auto-start)"
else
  fail "service is ENABLED — it should be disabled to prevent auto-start on boot"
fi

if ! systemctl is-active tailscaled &>/dev/null; then
  pass "service is not running (correct)"
else
  fail "service is currently RUNNING — it should not be active after install"
fi

# ── Auth key ──────────────────────────────────────────────────────────────────
section "Auth key"

if sudo test -f /etc/tailscale/debug-authkey 2>/dev/null; then
  pass "auth key present at /etc/tailscale/debug-authkey"
else
  fail "auth key missing at /etc/tailscale/debug-authkey"
fi

if [[ "$(sudo stat -c '%a' /etc/tailscale/debug-authkey 2>/dev/null)" == "600" ]]; then
  pass "auth key permissions are 600"
else
  fail "auth key permissions are not 600"
fi

if [[ "$(sudo stat -c '%U' /etc/tailscale/debug-authkey 2>/dev/null)" == "root" ]]; then
  pass "auth key owned by root"
else
  fail "auth key not owned by root"
fi

# ── Activation script ─────────────────────────────────────────────────────────
section "Activation script"

if [[ -x /usr/local/bin/tailscale-debug-activate.sh ]]; then
  pass "activation script present and executable"
else
  fail "activation script missing or not executable at /usr/local/bin/tailscale-debug-activate.sh"
fi

# ── Upgrade log ───────────────────────────────────────────────────────────────
section "Upgrade log"

if [[ -f /home/pi/upgrade-tailscale.log ]]; then
  pass "upgrade log present at /home/pi/upgrade-tailscale.log"
  LAST_STATUS=$(grep "Status:" /home/pi/upgrade-tailscale.log | tail -1)
  if [[ "$LAST_STATUS" == *"SUCCESS"* ]]; then
    pass "last upgrade status: SUCCESS"
  else
    fail "last upgrade status not SUCCESS: $LAST_STATUS"
  fi
else
  fail "upgrade log missing at /home/pi/upgrade-tailscale.log"
fi

# ── Docker / Engine ───────────────────────────────────────────────────────────
section "Docker and Engine"

if docker ps &>/dev/null; then
  pass "Docker is running"
  CONTAINERS=$(docker ps --format '{{.Names}}' | wc -l)
  pass "Docker containers running: $CONTAINERS"
else
  fail "Docker is not running or pi user cannot access it"
fi

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "engine\|openclaw\|idea"; then
  pass "Engine/IDEA containers are up"
else
  warn "No Engine/IDEA containers detected — check docker ps manually"
fi

# ── wlan0 ─────────────────────────────────────────────────────────────────────
section "wlan0 (Starlink)"

WLAN_STATE=$(nmcli -t -f DEVICE,STATE device status 2>/dev/null | grep "^wlan0:" | cut -d: -f2 || echo "unknown")
case "$WLAN_STATE" in
  connected)
    WLAN_SSID=$(nmcli -t -f ACTIVE-CONNECTION,SSID device wifi list 2>/dev/null | grep "^\*" | head -1 | awk '{print $2}' || echo "unknown")
    pass "wlan0 connected (SSID: $WLAN_SSID)"
    ;;
  disconnected)
    warn "wlan0 not connected — Starlink may not be in range (OK if Tapiwa took it)"
    ;;
  *)
    warn "wlan0 state: $WLAN_STATE — check manually with: nmcli device status"
    ;;
esac

# Check if a Starlink connection profile exists (even if not currently connected)
if nmcli connection show 2>/dev/null | grep -q "wlan0"; then
  pass "wlan0 has a saved connection profile (will auto-connect when Starlink is in range)"
else
  warn "No saved wlan0 connection profile found — starlink.conf may not have been on the USB"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Result: $PASS passed   $FAIL failed   $WARN warnings"
echo ""
if [[ $FAIL -eq 0 ]]; then
  echo " STATUS: ✓ PASS — upgrade package cleared for field distribution"
else
  echo " STATUS: ✗ FAIL — fix the failures above before distributing"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

[[ $FAIL -eq 0 ]]
