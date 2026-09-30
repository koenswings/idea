#!/usr/bin/env bash
# strip-cloud-init-sudoers.sh — remove cloud-init's blanket NOPASSWD ALL for pi (idea#153).
#
# On some images (seen on idea01) /etc/sudoers.d/90-cloud-init-users grants
#   pi ALL=(ALL) NOPASSWD:ALL
# and sorts after 10-engine / 11-engine-files, so the scoped Engine rules never win.
# The rest of the fleet only has the Engine sudoers. This script makes a Pi match.
#
# Usage (on the Pi as pi, or via: ssh pi@idea01 'bash -s' < tools/fleet/strip-cloud-init-sudoers.sh):
#   tools/fleet/strip-cloud-init-sudoers.sh [--dry-run] [--host user@host]
#
# What it does (idempotent):
#   1. Backs up 90-cloud-init-users under ~/backups/ if present
#   2. Removes /etc/sudoers.d/90-cloud-init-users (via sudo)
#   3. Disables cloud-init's users-groups module so reboot does not recreate it
#      (writes /etc/cloud/cloud.cfg.d/99-disable-users.cfg when cloud-init exists)
#   4. Runs visudo -c; prints sudo -ll summary for pi
#
# Exit: 0 ok / already clean, 1 failure, 2 usage.
set -euo pipefail

DRY=0
REMOTE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --host) REMOTE="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1 (see --help)" >&2; exit 2 ;;
  esac
done

run_local() {
  local file="/etc/sudoers.d/90-cloud-init-users"
  local backup_dir="${HOME}/backups"
  local stamp
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"

  # /etc/sudoers.d is often 750 root:root — pi cannot see the file without sudo (idea#153 false-clean).
  if ! sudo test -e "$file"; then
    echo "{\"status\":\"clean\",\"host\":\"$(hostname)\",\"message\":\"$file already absent\"}"
    return 0
  fi

  if [[ $DRY -eq 1 ]]; then
    echo "{\"status\":\"would_strip\",\"host\":\"$(hostname)\",\"file\":\"$file\",\"dry_run\":true}"
    return 0
  fi

  mkdir -p "$backup_dir"
  local backup="$backup_dir/90-cloud-init-users.$stamp"
  sudo cp -a "$file" "$backup"
  sudo rm -f "$file"

  # Stop cloud-init recreating users/sudoers on reboot (image already provisioned).
  if [[ -d /etc/cloud/cloud.cfg.d ]]; then
    sudo tee /etc/cloud/cloud.cfg.d/99-disable-users.cfg >/dev/null <<'CFG'
# idea#153 — do not recreate 90-cloud-init-users after we remove it
users: []
cloud_init_modules:
  - [users-groups, none]
CFG
  fi

  if ! sudo visudo -c >/dev/null; then
    echo "ERROR: visudo -c failed after remove; restoring backup" >&2
    sudo cp -a "$backup" "$file"
    sudo visudo -c >/dev/null || true
    exit 1
  fi

  # Soft checks (do not fail the script if sudo -ll wording differs)
  local ll
  ll="$(sudo -ll -U pi 2>/dev/null || true)"

  echo "{\"status\":\"stripped\",\"host\":\"$(hostname)\",\"backup\":\"$backup\",\"sudo_ll_has_engine\":$(echo "$ll" | grep -q '11-engine-files\|10-engine' && echo true || echo false)}"
}

if [[ -n "$REMOTE" ]]; then
  # Stream this script to the remote host (without --host) so Atlas can run it from a laptop.
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE" "DRY=$DRY bash -s" <<'REMOTE_EOF'
set -euo pipefail
file="/etc/sudoers.d/90-cloud-init-users"
backup_dir="${HOME}/backups"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
# /etc/sudoers.d is often 750 root:root — pi cannot see the file without sudo (idea#153 false-clean).
if ! sudo test -e "$file"; then
  echo "{\"status\":\"clean\",\"host\":\"$(hostname)\",\"message\":\"$file already absent\"}"
  exit 0
fi
if [[ "${DRY:-0}" == "1" ]]; then
  echo "{\"status\":\"would_strip\",\"host\":\"$(hostname)\",\"file\":\"$file\",\"dry_run\":true}"
  exit 0
fi
mkdir -p "$backup_dir"
backup="$backup_dir/90-cloud-init-users.$stamp"
sudo cp -a "$file" "$backup"
sudo rm -f "$file"
if [[ -d /etc/cloud/cloud.cfg.d ]]; then
  sudo tee /etc/cloud/cloud.cfg.d/99-disable-users.cfg >/dev/null <<'CFG'
# idea#153 — do not recreate 90-cloud-init-users after we remove it
users: []
cloud_init_modules:
  - [users-groups, none]
CFG
fi
if ! sudo visudo -c >/dev/null; then
  echo "ERROR: visudo -c failed; restoring" >&2
  sudo cp -a "$backup" "$file"
  exit 1
fi
ll="$(sudo -ll -U pi 2>/dev/null || true)"
echo "{\"status\":\"stripped\",\"host\":\"$(hostname)\",\"backup\":\"$backup\",\"sudo_ll_has_engine\":$(echo "$ll" | grep -q '11-engine-files\|10-engine' && echo true || echo false)}"
REMOTE_EOF
else
  run_local
fi
