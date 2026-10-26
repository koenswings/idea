#!/usr/bin/env bash
# capture-device.sh - read-only capture of one field device for its deployment record (idea#322).
# Usage: capture-device.sh <device-name> <ssh-target> [OUTDIR]
#   device-name  sticker name, e.g. sunny-robin, sunny-robin-router, idea-pc-1a2b
#   ssh-target   user@tailscale-ip (Engine/client: pi@100.x.y.z or admin@...; router: root@100.x.y.z)
#   OUTDIR       default /workspace/idea-archive/captures
# Writes OUTDIR/<device-name>-<UTC stamp>.txt (+ .sha256) and prints the path. Never changes the device: the remote
# side is device-probe.sh fed through 'sh -s' (no files written there). Direct ssh over the Tailscale IP through the
# box SOCKS proxy (CAPTURE_PROXY, default 127.0.0.1:1055; set CAPTURE_PROXY=none for no proxy). No jump host.
# Env: CAPTURE_SSH (ssh command override, tests), ENGINE_DIRS / HASH_DIRS (passed to the probe).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
NAME="${1:-}"; TGT="${2:-}"; OUT="${3:-/workspace/idea-archive/captures}"
[[ "$NAME" =~ ^[a-z0-9][a-z0-9-]*$ ]] && [ -n "$TGT" ] || { echo "usage: capture-device.sh <device-name> <user@ip> [OUTDIR]" >&2; exit 2; }
mkdir -p "$OUT"; F="$OUT/$NAME-$(date -u +%Y%m%dT%H%M%SZ).txt"
PROXY="${CAPTURE_PROXY:-127.0.0.1:1055}"
if [ -n "${CAPTURE_SSH:-}" ]; then read -r -a SSHC <<< "$CAPTURE_SSH"
else SSHC=(ssh -o BatchMode=yes -o ConnectTimeout=15)
  [ "$PROXY" = none ] || SSHC+=(-o "ProxyCommand=nc -X 5 -x $PROXY %h %p"); fi
envs=""; for v in ENGINE_DIRS HASH_DIRS; do [ -n "${!v:-}" ] && envs+="$v=$(printf %q "${!v}") "; done
{ echo "# capture of $NAME via $TGT at $(date -u +%Y-%m-%dT%H:%M:%SZ) (box $(hostname)), probe sha256 $(sha256sum "$HERE/device-probe.sh" | cut -d' ' -f1)"
  "${SSHC[@]}" "$TGT" "${envs:+env $envs}sh -s" < "$HERE/device-probe.sh"; } > "$F.part" \
  || { echo "capture failed for $NAME ($TGT); partial output kept in $F.part" >&2; exit 3; }
grep -q '^=== end' "$F.part" || { echo "capture incomplete for $NAME; kept in $F.part" >&2; exit 3; }
mv "$F.part" "$F"; (cd "$OUT" && sha256sum "$(basename "$F")" > "$(basename "$F").sha256")
echo "$F"
