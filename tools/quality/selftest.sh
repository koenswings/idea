#!/usr/bin/env bash
# selftest.sh — run quality-scan against tools/quality/testdata fixtures (no Pi required)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAN="${SCRIPT_DIR}/quality-scan.sh"
TD="${SCRIPT_DIR}/testdata"
export BOT_NAME="${BOT_NAME:-selftest}"
export QUALITY_SCAN_DRY_RUN_TESTS=1

fail=0
pass=0

run_expect_fail() {
  local name="$1"
  local repos="$2"
  local rule_grep="$3"
  local out rc=0
  set +e
  out="$("$SCAN" --repo-root "$TD" --repos "$repos" 2>/dev/null)"
  rc=$?
  set -e
  if [[ $rc -eq 2 ]]; then
    echo "FAIL $name: script error (exit 2)"
    echo "$out" | tail -5
    fail=$((fail + 1))
    return
  fi
  if [[ $rc -ne 1 ]]; then
    echo "FAIL $name: expected exit 1, got $rc"
    fail=$((fail + 1))
    return
  fi
  if ! echo "$out" | jq -e --arg r "$rule_grep" '[.findings[].rule] | any(. == $r or startswith($r))' >/dev/null 2>&1; then
    # also allow prefix match via contains
    if ! echo "$out" | jq -e --arg r "$rule_grep" '[.findings[].rule] | map(select(startswith($r) or . == $r)) | length > 0' >/dev/null; then
      echo "FAIL $name: missing expected rule prefix '$rule_grep'"
      echo "$out" | jq '.findings[].rule' 2>/dev/null || echo "$out" | tail -20
      fail=$((fail + 1))
      return
    fi
  fi
  echo "PASS $name (rule~$rule_grep)"
  pass=$((pass + 1))
}

run_expect_pass() {
  local name="$1"
  local repos="$2"
  local out rc=0
  set +e
  out="$("$SCAN" --repo-root "$TD" --repos "$repos" 2>/dev/null)"
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    echo "FAIL $name: expected exit 0, got $rc"
    echo "$out" | jq '{ok,summary,findings}' 2>/dev/null || echo "$out" | tail -40
    fail=$((fail + 1))
    return
  fi
  local viol
  viol="$(echo "$out" | jq '.summary.violations')"
  if [[ "$viol" != "0" ]]; then
    echo "FAIL $name: violations=$viol"
    echo "$out" | jq '.findings'
    fail=$((fail + 1))
    return
  fi
  echo "PASS $name"
  pass=$((pass + 1))
}

bash -n "$SCAN"
bash -n "$SCRIPT_DIR/selftest.sh"

run_expect_pass "fixture-pass" "fixture-pass"
run_expect_pass "fixture-console-pass" "fixture-console-pass"

run_expect_fail "structure.docs_source" "fixture-fail-structure" "structure."
run_expect_fail "hygiene" "fixture-fail-hygiene" "hygiene."
run_expect_fail "docs.index" "fixture-fail-docs" "docs."
run_expect_fail "engine.store_template" "fixture-engine-fail" "engine.store_template"

run_expect_fail "console.bakeins" "fixture-console-fail" "console."

# Direct bake-in unit checks for idea#61 (comment <For> false positive)
bakein_unit() {
  local helper="${SCRIPT_DIR}/lib-console-bakeins.py"
  local tmp rc out
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  cat > "$tmp/fp.tsx" <<'TSX'
// Stable IDs so <For> keys by ID, not array index.
const stepIds = () => Array.from({ length: 3 }, (_, i) => i + 1);
export function Ok() {
  return (
    <>
      {/* <For each={xs}>{(x, i) => <div/>}</For> */}
      <For each={stepIds()}>{(stepId) => <div>{stepId}</div>}</For>
    </>
  );
}
TSX
  out="$(python3 "$helper" "$tmp/fp.tsx" "fp.tsx" 2>/dev/null || true)"
  if echo "$out" | grep -q 'console.for_'; then
    echo "FAIL bakein-unit: comment <For> still flagged"
    echo "$out"
    fail=$((fail + 1))
  else
    echo "PASS bakein-unit: comment <For> not flagged"
    pass=$((pass + 1))
  fi

  cat > "$tmp/bad.tsx" <<'TSX'
export function Bad(props) {
  return (
    <For each={props.items}>
      {(item, index) => <div>{item.name}</div>}
    </For>
  );
}
TSX
  out="$(python3 "$helper" "$tmp/bad.tsx" "bad.tsx" 2>/dev/null || true)"
  if ! echo "$out" | grep -q 'console.for_not_id_keyed'; then
    echo "FAIL bakein-unit: real unkeyed For not detected"
    echo "$out"
    fail=$((fail + 1))
  else
    echo "PASS bakein-unit: real unkeyed For detected"
    pass=$((pass + 1))
  fi
}
bakein_unit


echo "---"
echo "selftest: $pass passed, $fail failed"
if [[ $fail -gt 0 ]]; then
  exit 1
fi
exit 0
