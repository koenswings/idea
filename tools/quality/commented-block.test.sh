#!/usr/bin/env bash
# commented-block.test.sh — unit tests for lib-commented-block.py
# Run: tools/quality/commented-block.test.sh
# Also invoked from tools/quality/selftest.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="${SCRIPT_DIR}/lib-commented-block.py"

fail=0
pass=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

scan() {
  local file="$1" rel="$2"
  python3 "$HELPER" "$file" "$rel" 2>/dev/null || true
}

expect_none() {
  local name="$1" file="$2" rel="$3"
  local out
  out="$(scan "$file" "$rel")"
  if [[ -n "$out" ]]; then
    echo "FAIL $name: expected no findings, got:"
    echo "$out"
    fail=$((fail + 1))
  else
    echo "PASS $name"
    pass=$((pass + 1))
  fi
}

expect_find() {
  local name="$1" file="$2" rel="$3"
  local out
  out="$(scan "$file" "$rel")"
  if ! echo "$out" | grep -q '^FIND'; then
    echo "FAIL $name: expected a commented-out-code finding, got:"
    echo "${out:-<empty>}"
    fail=$((fail + 1))
  else
    echo "PASS $name"
    pass=$((pass + 1))
  fi
}

# 1) JSDoc skipped (/** … */, lines starting with *)
cat > "$TMP/jsdoc.ts" <<'EOF'
/**
 * EmptyDiskPanel — shown in the right pane when an operator selects an empty disk.
 *
 * Lets the operator choose what to do with the disk:
 *   1. Make this a Files Disk
 *   2. Make this a Backup Disk
 *   3. Install App
 *
 * Disk arguments go through diskArgFor (idea#129).
 */
export const x = 1;

export function setUser(user: string): void {
  /**
   * Mid-file JSDoc is also skipped, even when it is long:
   * line two of the doc
   * line three of the doc
   * line four of the doc
   * line five of the doc
   * line six of the doc
   * line seven of the doc
   */
  return;
}
EOF
expect_none "JSDoc skipped" "$TMP/jsdoc.ts" "src/jsdoc.ts"

# 2) File leading header skipped (// and /*), including after a shebang
cat > "$TMP/header.ts" <<'EOF'
/**
 * File header — quality-scan.sh style documentation for this module.
 * Second header line
 * Third header line
 * Fourth header line
 * Fifth header line
 * Sixth header line
 * Seventh header line
 */
import { x } from './x';
export const y = x;
EOF
expect_none "/* header skipped" "$TMP/header.ts" "src/header.ts"

cat > "$TMP/header-slashes.ts" <<'EOF'
// ---------------------------------------------------------------------------
// Bootstrap candidates (idea#184)
// ---------------------------------------------------------------------------
//
// Pis have free, unique sticker names (e.g. `brave-otter`); there is no
// number scheme to guess and no shared alias. A browser cannot browse mDNS,
// so the Console bootstraps from ONE known host.
//
export const isLoopback = (h: string) => h === 'localhost';
EOF
expect_none "// header skipped" "$TMP/header-slashes.ts" "src/header-slashes.ts"

cat > "$TMP/header.sh" <<'EOF'
#!/usr/bin/env bash
# quality-scan.sh — IDEA platform quality gate (PR + full/scheduled scan)
# Spec: proposals/quality-scan-implementation.md / docs/grok-bot-setup.md §5
# Layout: agent-*-dev at ${IDEA_ROOT}/agents/<name>
# See proposals/pi-checkout-layout.md
# Exit: 0 clean, 1 violations, 2 script error
set -euo pipefail
echo ok
EOF
expect_none "shell header after shebang skipped" "$TMP/header.sh" "scripts/header.sh"

# 3) Commented-out JS/TS code still flagged
cat > "$TMP/dead.ts" <<'EOF'
export const keep = 1;
// const a = 1;
// const b = 2;
// const c = 3;
// function f() { return 4; }
// const e = f();
// export const g = e;
export const after = 2;
EOF
expect_find "commented-out JS/TS still flagged" "$TMP/dead.ts" "src/dead.ts"

# 4) Mid-file prose // run is not flagged
cat > "$TMP/prose.ts" <<'EOF'
export const x = 1;
// NOTE: BrowserWebSocketClientAdapter.whenReady() is NOT a reliable signal
// of actual connectivity — the adapter calls forceReady() after just 1 second
// regardless of whether the WebSocket handshake actually succeeded. Waiting
// on it would cause us to incorrectly set connected=true and cancel the
// fallback timer even when the engine is unreachable.
//
// Instead we use document data as the connectivity signal:
//   • connected=true fires only when the first real document data arrives
//   • The 30 s fallback timer in App.tsx handles the "never connected" case
export const y = 2;
EOF
expect_none "prose // mid-file not flagged" "$TMP/prose.ts" "src/prose.ts"

# 5) Five commented-out lines is not more than 5 — not flagged
cat > "$TMP/five.ts" <<'EOF'
export const keep = 1;
// const a = 1;
// const b = 2;
// const c = 3;
// const d = 4;
// const e = 5;
export const after = 2;
EOF
expect_none "exactly 5 commented-out lines not flagged" "$TMP/five.ts" "src/five.ts"

# 6) Shell: commented-out commands flagged
cat > "$TMP/dead.sh" <<'EOF'
#!/usr/bin/env bash
# header line one
# header line two
set -euo pipefail
echo start
# git fetch origin main
# pnpm test
# pnpm typecheck
# pnpm build
# mkdir -p /tmp/out
# cp -a dist/* /tmp/out
echo done
EOF
expect_find "commented-out shell commands still flagged" "$TMP/dead.sh" "scripts/dead.sh"

# 7) Shell: mid-file prose # not flagged
cat > "$TMP/prose.sh" <<'EOF'
#!/usr/bin/env bash
# short header
set -euo pipefail
# The scan writes one JSON object to stdout and an audit line under
# audit/audit-YYYY.jsonl. Warnings do not fail the scan. A teacher who
# thought they had moved the backup time and typoed the file will get
# the default 02:30 run plus a warning, which is deliberate, not a bug.
# Leave the golden Pi alone. Never SSH to idea as a jump host.
echo ok
EOF
expect_none "shell prose # mid-file not flagged" "$TMP/prose.sh" "scripts/prose.sh"

# 8) Mid-file non-JSDoc /* block of commented-out code is flagged
cat > "$TMP/block.ts" <<'EOF'
export const keep = 1;
/*
const a = 1;
const b = 2;
const c = 3;
const d = 4;
const e = 5;
const f = 6;
*/
export const after = 2;
EOF
expect_find "non-JSDoc /* commented-out code flagged" "$TMP/block.ts" "src/block.ts"

echo "---"
echo "commented-block.test.sh: $pass passed, $fail failed"
if [[ $fail -gt 0 ]]; then
  exit 1
fi
exit 0
