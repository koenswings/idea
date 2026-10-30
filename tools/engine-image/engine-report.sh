#!/usr/bin/env bash
# engine-report.sh REPORT.json [ENGINE_SRC] - check the Engine's engine-build.json (INTERFACE.md): exit 1 unless the build
# finished and its verify passed. Shape: {engine_commit, engine_version, lock_sha256, verify:{passed:N, failed:[strings], total?:M}}.
# passed counts named checks with no problems; the number of checks is never hardcoded: if verify.total is present,
# passed must equal it; otherwise failed must be empty and passed > 0.
# The Engine writes a "build did not finish" report before it starts, so a stale/partial report fails here too.
set -euo pipefail
J="${1:?usage: engine-report.sh REPORT.json [ENGINE_SRC]}"; SRC="${2:-}"
[ -s "$J" ] || { echo "engine report missing: $J" >&2; exit 1; }
jq -e 'type=="object"' "$J" >/dev/null 2>&1 || { echo "engine report is not a JSON object: $J" >&2; exit 1; }
P=$(jq -r '.verify.passed // empty' "$J"); T=$(jq -r '.verify.total // empty' "$J"); NF=$(jq -r '(.verify.failed // ["(no verify.failed)"]) | length' "$J")
EC=$(jq -r '.engine_commit // empty' "$J"); EV=$(jq -r '.engine_version // empty' "$J"); LS=$(jq -r '.lock_sha256 // empty' "$J")
echo "engine report: commit=${EC:-?} version=${EV:-?} lock_sha256=${LS:-?} verify passed=${P:-?}${T:+/$T} failed=$NF"
jq -r '(.verify.failed // [])[] | "engine verify FAIL: \(.)"' "$J"
ok=1
[ "$NF" = 0 ] || ok=0
[[ "${P:-0}" =~ ^[0-9]+$ ]] && [ "${P:-0}" -gt 0 ] || { echo "engine verify passed count is ${P:-missing} (build did not finish?)" >&2; ok=0; }
if [ -n "$T" ]; then [[ "$T" =~ ^[0-9]+$ ]] && [ "${P:-x}" = "$T" ] || { echo "engine verify passed ${P:-missing} of total $T" >&2; ok=0; }; fi
[ -n "$EC" ] && [ ${#LS} = 64 ] || { echo "engine report lacks engine_commit or lock_sha256" >&2; ok=0; }
if [ -n "$SRC" ] && [ -n "$EC" ] && [ "$EC" != "$(git -C "$SRC" rev-parse HEAD)" ]; then echo "engine report commit $EC != engine source HEAD" >&2; ok=0; fi
[ "$ok" = 1 ]
