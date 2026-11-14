#!/usr/bin/env bash
# kernel-cmdline.sh ROOT [FLAG...] - append kernel arguments to ROOT/boot/firmware/cmdline.txt, idempotently (idea#518).
# cmdline.txt is ONE line: flags are appended to that line (never a new line) and only when the exact token is not
# there yet. Default flags: KERNEL_CMDLINE_APPEND from engine-image.conf (cgroup_enable=memory: the Raspberry Pi
# firmware passes cgroup_disable=memory, so without it Docker has no memory accounting and `docker stats` shows 0B).
# Exit 0 ok (changed or already present), 1 bad cmdline.txt, 2 usage.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
M="${1:?usage: kernel-cmdline.sh ROOT [FLAG...]}"; shift
if [ $# -eq 0 ]; then
  # shellcheck source=engine-image.conf disable=SC1091
  . "$HERE/engine-image.conf"; read -r -a FLAGS <<<"${KERNEL_CMDLINE_APPEND:-}"
else FLAGS=("$@"); fi
[ "${#FLAGS[@]}" -gt 0 ] || { echo "no flags to append" >&2; exit 2; }
CL="$M/boot/firmware/cmdline.txt"
[ -f "$CL" ] && [ ! -L "$CL" ] || { echo "missing or symlinked: $CL" >&2; exit 1; }
[ "$(grep -c '' "$CL")" = 1 ] || { echo "$CL must be exactly one line" >&2; exit 1; }
has() { tr -s '[:blank:]' '\n' < "$CL" | grep -qxF -- "$1"; }
line=$(head -n1 "$CL" | sed 's/[[:space:]]*$//'); changed=0
for f in "${FLAGS[@]}"; do
  case "$f" in *[[:space:]]*|"") echo "bad flag: '$f'" >&2; exit 2;; esac
  if has "$f"; then echo "cmdline: $f already present"; else line="$line $f"; changed=1; echo "cmdline: appended $f"; fi
done
if [ "$changed" = 1 ]; then printf '%s\n' "$line" > "$CL"; fi
