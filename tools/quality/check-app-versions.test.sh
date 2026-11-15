#!/usr/bin/env bash
# check-app-versions.test.sh — unit tests for check-app-versions (idea#543).
# Run: tools/quality/check-app-versions.test.sh
# Also invoked from tools/quality/selftest.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SH="${SCRIPT_DIR}/check-app-versions.sh"
LIB="${SCRIPT_DIR}/lib-check-app-versions.mjs"
TEST_JS="${SCRIPT_DIR}/lib-check-app-versions.test.mjs"

fail=0
pass=0

ok() { echo "PASS $1"; pass=$((pass + 1)); }
bad() { echo "FAIL $1"; echo "${2:-}"; fail=$((fail + 1)); }

bash -n "$SH" && ok "bash -n check-app-versions.sh" || bad "bash -n check-app-versions.sh"

help_out="$("$SH" --help 2>&1 || true)"
if echo "$help_out" | grep -q -- '--apps-dir' && echo "$help_out" | grep -q 'js-yaml' && echo "$help_out" | grep -q 'package.json'; then
  ok "help documents --apps-dir and js-yaml"
else
  bad "help documents --apps-dir and js-yaml" "$help_out"
fi

if [[ ! -d "${SCRIPT_DIR}/node_modules/js-yaml" ]]; then
  if ! (cd "$SCRIPT_DIR" && npm install --omit=dev --no-fund --no-audit >/dev/null); then
    bad "npm install js-yaml for tests"
    echo "---"
    echo "check-app-versions.test: $pass passed, $fail failed"
    exit 1
  fi
fi

set +e
node --test "$TEST_JS"
rc=$?
set -e
if [[ $rc -eq 0 ]]; then
  ok "lib-check-app-versions.test.mjs (node --test)"
else
  bad "lib-check-app-versions.test.mjs (node --test)"
fi

echo "---"
echo "check-app-versions.test: $pass passed, $fail failed"
if [[ $fail -gt 0 ]]; then
  exit 1
fi
exit 0
