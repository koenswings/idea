#!/usr/bin/env bash
# enable-memory-cgroup.sh — idea#518: turn on the memory cgroup on ONE Engine Pi by appending
# `cgroup_enable=memory` to /boot/firmware/cmdline.txt (overrides the firmware's cgroup_disable=memory).
#
#   tools/fleet/enable-memory-cgroup.sh <host-or-ip> [--yes]
#
# Without --yes: dry run (prechecks + the line that would be written; nothing changed).
# With --yes: timestamped backup cmdline.txt.bak-<ts> next to the original, idempotent append to the single
# line (never a new line, never twice), diff, sync, then ONE reboot. If the flag is already in cmdline.txt
# it changes nothing and reboots only when the running kernel lacks it.
# Claim the Pi in fleet-state first (one Pi down at a time). Verify after boot: `memory` in
# /sys/fs/cgroup/cgroup.controllers. Restore: sudo cp -p <backup> /boot/firmware/cmdline.txt && sync, reboot.
# SSH goes straight to the Tailscale IP through the box SOCKS proxy. Env overrides (tests): SSH_CMD, PROXY,
# CMDLINE_PATH (remote cmdline.txt path; default /boot/firmware/cmdline.txt).
set -euo pipefail
HOST="${1:-}"; MODE="${2:---dry-run}"
case "$HOST" in ""|-h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2;; esac
case "$MODE" in --yes|--dry-run) ;; *) echo "unknown arg $MODE" >&2; exit 2;; esac
PROXY="${PROXY:-127.0.0.1:1055}"
read -r -d '' REMOTE <<'RS' || true
set -euo pipefail
MODE="$1"; CL="${2:-/boot/firmware/cmdline.txt}"; FLAG=cgroup_enable=memory
[ -f "$CL" ] || { echo "FAIL: $CL missing (not a Raspberry Pi OS bookworm/trixie layout)"; exit 1; }
sudo -n true 2>/dev/null || { echo "FAIL: passwordless sudo needed"; exit 1; }
n=$(grep -c '' "$CL"); [ "$n" = 1 ] || { echo "FAIL: $CL has $n lines, expected exactly 1"; exit 1; }
grep -q 'root=' "$CL" || { echo "FAIL: $CL has no root= (refusing)"; exit 1; }
echo "host: $(hostname)  running: $(grep -o 'cgroup_[a-z]*=memory' /proc/cmdline 2>/dev/null | tr '\n' ' ')"
echo "controllers: $(cat /sys/fs/cgroup/cgroup.controllers 2>/dev/null)"
echo "before: $(cat "$CL")"
if tr -s '[:blank:]' '\n' < "$CL" | grep -qxF "$FLAG"; then
  echo "already present in $CL: no change"
  if tr -s '[:blank:]' '\n' < /proc/cmdline 2>/dev/null | grep -qxF "$FLAG"; then echo "OK: running kernel already has $FLAG; nothing to do"; exit 0; fi
  [ "$MODE" = --yes ] || { echo "DRY RUN: would reboot once (running kernel lacks $FLAG)"; exit 0; }
else
  line=$(head -n1 "$CL" | sed 's/[[:space:]]*$//'); new="$line $FLAG"
  echo "after:  $new"
  [ "$MODE" = --yes ] || { echo "DRY RUN: nothing changed (add --yes to write, sync and reboot)"; exit 0; }
  ts=$(date +%Y%m%d-%H%M%S); BAK="$CL.bak-$ts"
  sudo cp -p "$CL" "$BAK"; echo "backup: $BAK"
  printf '%s\n' "$new" | sudo tee "$CL" >/dev/null
  [ "$(grep -c '' "$CL")" = 1 ] && [ "$(tr -s '[:blank:]' '\n' < "$CL" | grep -cxF "$FLAG")" = 1 ] || { sudo cp -p "$BAK" "$CL"; sync; echo "FAIL: write check failed, restored $BAK"; exit 1; }
  diff -u "$BAK" "$CL" || true
fi
sync; echo "rebooting $(hostname) at $(date '+%F %T %Z')"
sudo systemd-run --on-active=3 --timer-property=AccuracySec=1s /bin/systemctl reboot >/dev/null || { echo "FAIL: could not schedule the reboot (cmdline.txt already written)"; exit 1; }
exit 0
RS
if [ -n "${SSH_CMD:-}" ]; then
  # shellcheck disable=SC2086
  $SSH_CMD "$HOST" "bash -s -- $MODE ${CMDLINE_PATH:-}" <<<"$REMOTE"
else
  ssh -o BatchMode=yes -o ConnectTimeout=15 -o ProxyCommand="nc -X 5 -x $PROXY %h %p" "pi@$HOST" "bash -s -- $MODE ${CMDLINE_PATH:-}" <<<"$REMOTE"
fi
