#!/usr/bin/env bash
# Offline tests for field-usage ACL snippets, the probe script, and the export stub (idea#416).
# No Pi, no Tailscale, no real fleet-state. Exit 0 if all pass.
set -uo pipefail
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$D" rev-parse --show-toplevel)"
pass=0; fail=0
ok()  { echo "PASS $1"; pass=$((pass+1)); }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
check() { local n="$1"; shift; if "$@"; then ok "$n"; else bad "$n"; fi; }

real_fp() { cat "$REPO_ROOT/fleet-state.json" "$REPO_ROOT"/audit/*.jsonl 2>/dev/null | sha256sum; }
REAL_BEFORE="$(real_fp)"

check "probe script bash -n" bash -n "$D/probe-field-usage-acl.sh"
check "prove script bash -n" bash -n "$D/prove-usage-export-key.sh"
check "stub script bash -n" bash -n "$D/idea-usage-export.stub.sh"

# --- HuJSON parse + required blocks ---
load_hujson() {
  python3 - "$1" <<'PY'
import json, sys
from pathlib import Path

def strip_hujson(text: str) -> str:
    out = []
    i = 0
    n = len(text)
    in_str = False
    esc = False
    while i < n:
        ch = text[i]
        if in_str:
            out.append(ch)
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
            i += 1
            continue
        if ch == '"':
            in_str = True
            out.append(ch)
            i += 1
            continue
        if ch == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if ch == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i = min(n, i + 2)
            continue
        out.append(ch)
        i += 1
    s = "".join(out)
    # Remove trailing commas before } or ]
    cleaned = []
    in_str = False
    esc = False
    i = 0
    n = len(s)
    while i < n:
        ch = s[i]
        if in_str:
            cleaned.append(ch)
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
            i += 1
            continue
        if ch == '"':
            in_str = True
            cleaned.append(ch)
            i += 1
            continue
        if ch == ",":
            j = i + 1
            while j < n and s[j] in " \t\r\n":
                j += 1
            if j < n and s[j] in "}]":
                i += 1
                continue
        cleaned.append(ch)
        i += 1
    return "".join(cleaned)

path = Path(sys.argv[1])
data = json.loads(strip_hujson(path.read_text()))
print(json.dumps(data, separators=(",", ":")))
PY
}

for f in field-usage-acl-step-a.hujson field-usage-acl-final.hujson; do
  if JSON="$(load_hujson "$D/$f")"; then
    check "$f parses" true
  else
    check "$f parses" false
    JSON="{}"
  fi
  check "$f has tag:idea-hub owner" bash -c 'jq -e ".tagOwners[\"tag:idea-hub\"]" >/dev/null <<<"$0"' "$JSON"
  check "$f has admin->idea" bash -c 'jq -e "[.acls[] | select(.src==[\"group:admins\"] and (.dst|index(\"tag:idea:*\")))] | length > 0" >/dev/null <<<"$0"' "$JSON"
  check "$f has idea-cannot-reach-idea test" bash -c 'jq -e "[.tests[] | select(.src==\"tag:idea\" and (.deny|index(\"tag:idea:22\")))] | length > 0" >/dev/null <<<"$0"' "$JSON"
done

STEP="$(load_hujson "$D/field-usage-acl-step-a.hujson")"
FINAL="$(load_hujson "$D/field-usage-acl-final.hujson")"
check "step-a has no hub->idea:22 acl" bash -c 'jq -e "[.acls[] | select((.src==[\"tag:idea-hub\"]) and (.dst|index(\"tag:idea:22\")))] | length == 0" >/dev/null <<<"$0"' "$STEP"
check "step-a denies hub->idea:22" bash -c 'jq -e "[.tests[] | select(.src==\"tag:idea-hub\" and (.deny|index(\"tag:idea:22\")))] | length > 0" >/dev/null <<<"$0"' "$STEP"
check "final has hub->idea:22 acl" bash -c 'jq -e "[.acls[] | select((.src==[\"tag:idea-hub\"]) and (.dst|index(\"tag:idea:22\")))] | length > 0" >/dev/null <<<"$0"' "$FINAL"
check "final accepts hub->idea:22" bash -c 'jq -e "[.tests[] | select(.src==\"tag:idea-hub\" and (.accept|index(\"tag:idea:22\")))] | length > 0" >/dev/null <<<"$0"' "$FINAL"
check "final denies hub->idea:80" bash -c 'jq -e "[.tests[] | select(.src==\"tag:idea-hub\" and (.deny|index(\"tag:idea:80\")))] | length > 0" >/dev/null <<<"$0"' "$FINAL"
check "final denies hub->idea:3333" bash -c 'jq -e "[.tests[] | select(.src==\"tag:idea-hub\" and (.deny|index(\"tag:idea:3333\")))] | length > 0" >/dev/null <<<"$0"' "$FINAL"
check "neither snippet uses wildcard dest in tests" bash -c 'jq -e "[.tests[].accept[]?, .tests[].deny[]?] | map(select(endswith(\":*\") or .==\"*\")) | length == 0" >/dev/null <<<"$0"' "$FINAL"

# --- stub ---
out="$(SSH_ORIGINAL_COMMAND='since 2026-01-01' "$D/idea-usage-export.stub.sh")"
check "stub since exits 0" test $? = 0
check "stub since is JSON stub" bash -c 'jq -e ".stub==true and .verb==\"since\" and .since==\"2026-01-01\"" >/dev/null <<<"$0"' "$out"
SSH_ORIGINAL_COMMAND='id' "$D/idea-usage-export.stub.sh" >/dev/null 2>&1
check "stub id refused" test $? = 1
SSH_ORIGINAL_COMMAND='' "$D/idea-usage-export.stub.sh" >/dev/null 2>&1
check "stub empty command refused" test $? = 1
out="$(SSH_ORIGINAL_COMMAND='archive-and-clear --before 2026-02-02' "$D/idea-usage-export.stub.sh")"
check "stub archive-and-clear does not modify" bash -c 'jq -e ".cleared==false" >/dev/null <<<"$0"' "$out"

# --- probe with fake connector ---
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/fleet-state.json" <<'JSON'
{
  "idea01": {"role":"golden","status":"idle","claim":null,"tailscale":"10.0.0.1"},
  "idea03": {"role":"spare","status":"idle","claim":null,"tailscale":"10.0.0.3"},
  "idea04": {"role":"spare","status":"idle","claim":null,"tailscale":"10.0.0.4"}
}
JSON
export STATE_FILE="$WORK/fleet-state.json" BOT_NAME=Atlas

cat > "$WORK/closed" <<'SH'
#!/usr/bin/env bash
echo timeout; exit 1
SH
cat > "$WORK/open" <<'SH'
#!/usr/bin/env bash
echo opened; exit 0
SH
cat > "$WORK/hubish" <<'SH'
#!/usr/bin/env bash
# open only port 22
if [ "$2" = 22 ]; then echo opened; exit 0; else echo timeout; exit 1; fi
SH
chmod +x "$WORK/closed" "$WORK/open" "$WORK/hubish"

OUT="$(PROBE_CONNECT_CMD="$WORK/closed" "$D/probe-field-usage-acl.sh" idea-to-idea --source-name idea03 --timeout 1 2>/dev/null)"
RC=$?
check "idea-to-idea all-closed exits 0" test "$RC" = 0
check "idea-to-idea all-closed ok=true" bash -c 'jq -e ".ok==true" >/dev/null <<<"$0"' "$OUT"
check "idea-to-idea does not dest itself" bash -c 'jq -e "[.probes[].dest] | index(\"idea03\") | not" >/dev/null <<<"$0"' "$OUT"

OUT="$(PROBE_CONNECT_CMD="$WORK/open" "$D/probe-field-usage-acl.sh" idea-to-idea --source-name idea03 --timeout 1 2>/dev/null)"
RC=$?
check "idea-to-idea all-open exits 1" test "$RC" = 1
check "idea-to-idea all-open ok=false" bash -c 'jq -e ".ok==false" >/dev/null <<<"$0"' "$OUT"

OUT="$(PROBE_CONNECT_CMD="$WORK/hubish" "$D/probe-field-usage-acl.sh" hub-to-idea --i-am-hub --source-name sidecar --dests idea03,idea04 --timeout 1 2>/dev/null)"
RC=$?
check "hub-to-idea 22-only exits 0" test "$RC" = 0
check "hub-to-idea 22-only ok=true" bash -c 'jq -e ".ok==true" >/dev/null <<<"$0"' "$OUT"

OUT="$(PROBE_CONNECT_CMD="$WORK/open" "$D/probe-field-usage-acl.sh" hub-to-idea --i-am-hub --source-name sidecar --dests idea03 --ports 22,80 --timeout 1 2>/dev/null)"
RC=$?
check "hub-to-idea extra-open-port exits 1" test "$RC" = 1

"$D/probe-field-usage-acl.sh" >/dev/null 2>&1
check "missing mode exits 2" test $? = 2

check "real fleet-state untouched" test "$(real_fp)" = "$REAL_BEFORE"

echo "probe-field-usage-acl.test.sh: $pass passed, $fail failed"
[ "$fail" = 0 ]
