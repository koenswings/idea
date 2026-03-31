#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# prepare-usb-stick.sh — Build a Tailscale upgrade USB stick
#
# USAGE (run on Koen's laptop, macOS or Linux):
#   Insert a USB drive, then:
#   bash scripts/prepare-usb-stick.sh
#
# WHAT THIS DOES:
#   1. Detects the mounted USB volume (or prompts for a path)
#   2. Downloads the latest Tailscale ARM64 binaries from pkgs.tailscale.com
#   3. Copies the upgrade scripts from the idea repo
#   4. Prompts for Starlink SSID/password → writes starlink.conf
#   5. Prompts for the Tailscale auth key → writes debug-authkey
#   6. Verifies the USB package is complete
#
# REQUIREMENTS: curl, python3 (both available on macOS by default)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IDEA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UPGRADE_SCRIPTS="$IDEA_DIR/scripts/upgrade-tailscale"

info()    { echo -e "\033[1;34m[usb]\033[0m  $*"; }
ok()      { echo -e "\033[1;32m[usb]\033[0m  $*"; }
warn()    { echo -e "\033[1;33m[usb]\033[0m  $*"; }
die()     { echo -e "\033[1;31m[usb]\033[0m  $*" >&2; exit 1; }
section() { echo ""; echo "── $1 ──────────────────────────────────────────────"; }

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " IDEA — Tailscale upgrade USB stick builder"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Detect USB mount point ────────────────────────────────────────────────────
section "USB drive"

if [[ "$(uname)" == "Darwin" ]]; then
  # macOS: list /Volumes entries that are not the system drive
  VOLUMES=$(ls /Volumes/ | grep -v "^Macintosh HD$" | grep -v "^\..*" || true)
  if [[ -z "$VOLUMES" ]]; then
    die "No USB volume detected. Insert a USB drive and try again."
  fi
  echo "  Detected volumes:"
  while IFS= read -r v; do echo "    /Volumes/$v"; done <<< "$VOLUMES"
  echo ""
  read -rp "  Enter volume name (e.g. IDEA_USB): " VOL_NAME
  USB="/Volumes/$VOL_NAME"
  [[ -d "$USB" ]] || die "Volume not found: $USB"
else
  # Linux: prompt for mount point
  echo "  Enter USB mount point (e.g. /media/pi/IDEA_USB or /mnt/usb):"
  read -rp "  Mount point: " USB
  [[ -d "$USB" ]] || die "Mount point not found: $USB"
fi

OUT="$USB/upgrade-tailscale"
mkdir -p "$OUT"
ok "USB output directory: $OUT"

# ── Download Tailscale ARM64 ──────────────────────────────────────────────────
section "Tailscale binaries (ARM64)"

info "Detecting latest Tailscale stable version..."
TSVER=$(curl -s "https://pkgs.tailscale.com/stable/" \
  | grep -oE 'tailscale_[0-9]+\.[0-9]+\.[0-9]+_arm64\.tgz' \
  | head -1 \
  | sed 's/tailscale_//' \
  | sed 's/_arm64\.tgz//')

[[ -n "$TSVER" ]] || die "Could not detect latest Tailscale version. Check internet connection."
info "Latest version: $TSVER"

TARBALL="$OUT/tailscale_arm64.tgz"
if [[ -f "$TARBALL" ]]; then
  EXISTING=$(tar -tzf "$TARBALL" 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
  if [[ "$EXISTING" == "$TSVER" ]]; then
    ok "Tailscale $TSVER already downloaded — skipping"
  else
    info "Updating from $EXISTING to $TSVER..."
    curl -L "https://pkgs.tailscale.com/stable/tailscale_${TSVER}_arm64.tgz" -o "$TARBALL"
    ok "Downloaded tailscale_${TSVER}_arm64.tgz"
  fi
else
  info "Downloading tailscale_${TSVER}_arm64.tgz..."
  curl -L "https://pkgs.tailscale.com/stable/tailscale_${TSVER}_arm64.tgz" -o "$TARBALL"
  ok "Downloaded tailscale_${TSVER}_arm64.tgz ($(du -sh "$TARBALL" | cut -f1))"
fi

# ── Copy upgrade scripts from repo ────────────────────────────────────────────
section "Scripts from idea repo"

[[ -d "$UPGRADE_SCRIPTS" ]] || die "Upgrade scripts not found at $UPGRADE_SCRIPTS — is this repo up to date?"

for f in install.sh tailscale-debug-activate.sh tailscaled.service; do
  [[ -f "$UPGRADE_SCRIPTS/$f" ]] || die "$f not found in $UPGRADE_SCRIPTS"
  cp "$UPGRADE_SCRIPTS/$f" "$OUT/$f"
  ok "Copied $f"
done
chmod +x "$OUT/install.sh" "$OUT/tailscale-debug-activate.sh"

# ── Starlink credentials ──────────────────────────────────────────────────────
section "Starlink WiFi credentials"

if [[ -f "$OUT/starlink.conf" ]]; then
  warn "starlink.conf already exists — overwrite? (y/N)"
  read -rp "  " OVERWRITE
  [[ "${OVERWRITE,,}" == "y" ]] || { info "Keeping existing starlink.conf"; goto_authkey=1; }
fi

if [[ -z "${goto_authkey:-}" ]]; then
  read -rp "  Starlink WiFi SSID: " SSID
  read -rsp "  Starlink WiFi password: " PASS; echo ""
  printf 'STARLINK_SSID="%s"\nSTARLINK_PASSWORD="%s"\n' "$SSID" "$PASS" > "$OUT/starlink.conf"
  ok "starlink.conf written"
fi

# ── Tailscale auth key ────────────────────────────────────────────────────────
section "Tailscale auth key"

echo "  Paste the Tailscale auth key from the admin console."
echo "  (Must be: reusable, ephemeral, tag:school-pi)"
echo "  Input is hidden."
echo ""
if [[ -f "$OUT/debug-authkey" ]]; then
  warn "debug-authkey already exists — overwrite? (y/N)"
  read -rp "  " OVERWRITE_KEY
  [[ "${OVERWRITE_KEY,,}" == "y" ]] || { info "Keeping existing debug-authkey"; AUTH_KEY=""; }
fi

if [[ -z "${AUTH_KEY:-}" && ! -f "$OUT/debug-authkey" ]] || \
   [[ "${OVERWRITE_KEY:-}" == "y" ]]; then
  read -rsp "  Auth key: " AUTH_KEY; echo ""
  printf '%s' "$AUTH_KEY" > "$OUT/debug-authkey"
  chmod 600 "$OUT/debug-authkey"
  ok "debug-authkey written"
fi

# ── Verify package ────────────────────────────────────────────────────────────
section "Package verification"

REQUIRED=(tailscale_arm64.tgz install.sh tailscale-debug-activate.sh tailscaled.service debug-authkey starlink.conf)
ALL_OK=true

for f in "${REQUIRED[@]}"; do
  if [[ -f "$OUT/$f" ]]; then
    SIZE=$(du -sh "$OUT/$f" | cut -f1)
    ok "$f ($SIZE)"
  else
    warn "MISSING: $f"
    ALL_OK=false
  fi
done

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if $ALL_OK; then
  echo " ✓  USB stick is ready"
  echo ""
  echo "  Contents: $OUT"
  echo ""
  echo "  Hand USB to Tapiwa. His procedure:"
  echo "    1. ssh pi@engine-1.local"
  echo "    2. sudo mkdir -p /mnt/usb && sudo mount /dev/sda1 /mnt/usb"
  echo "    3. sudo bash /mnt/usb/upgrade-tailscale/install.sh"
else
  echo " ✗  USB stick is INCOMPLETE — fix warnings above before distributing"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
