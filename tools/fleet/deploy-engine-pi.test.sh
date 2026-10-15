#!/usr/bin/env bash
# deploy-engine-pi.test.sh — offline tests for deploy-engine-pi.sh with a temp git repo and
# fake pnpm/pm2. No Pi touched. Usage: tools/fleet/deploy-engine-pi.test.sh  (exit 0 = all pass)
set -uo pipefail
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/deploy-engine-pi.sh"
pass=0; fail=0
check() { local n="$1"; shift; if "$@"; then echo "PASS $n"; pass=$((pass+1)); else echo "FAIL $n"; fail=$((fail+1)); fi; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
DEFAULT=automerge:4GQmDefaultIdea02Production
POOL=automerge:2VroEUvDkmYsDAwE5oG9YeFNadWH
mkdir -p "$WORK/bin"
cat > "$WORK/bin/pm2" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$WORK/pm2.log"
SH
cat > "$WORK/bin/pnpm" <<'SH'
#!/usr/bin/env bash
# FAKE_BUILD_CLOBBER=1 simulates a build step that resets the store id.
[ "$1" = build ] && [ -n "${FAKE_BUILD_CLOBBER:-}" ] && git checkout -q -- store-identity/store-url.txt
exit 0
SH
chmod +x "$WORK/bin/"*; export PATH="$WORK/bin:$PATH" WORK

setup() {  # repo with defaults committed, then the Pi's local edits on top
  R="$WORK/repo-$1"; rm -rf "$R" "$WORK/pm2.log"; mkdir -p "$R/store-identity"; cd "$R" || exit 1
  git init -q; git config user.email t@t; git config user.name t
  echo "mdns: true" > config.yaml; echo "module.exports={}" > pm2.config.cjs
  echo "$DEFAULT" > store-identity/store-url.txt; echo "automerge:cmdlogDefault" > store-identity/command-log-url.txt
  git add -A; git commit -qm base; echo v2 > engine.txt; git add -A; git commit -qm tip
  TIP=$(git rev-parse HEAD); git checkout -q HEAD~1
  echo "mdns: true # local" > config.yaml; echo "module.exports={local:1}" > pm2.config.cjs
  echo "$POOL" > store-identity/store-url.txt; echo "automerge:cmdlogPool" > store-identity/command-log-url.txt
  echo "{}" > store-identity/store-template.json   # untracked, must survive
  cd "$WORK" || exit 1
}
run() { ENGINE_DIR="$R" HOST_NAME="${H:-idea04}" BACKUP_ROOT="$WORK/bk-$1" bash "$SCRIPT" "$TIP" "${@:2}" > "$WORK/out" 2>&1; }

setup ok; run ok --yes; rc=$?
check "deploy succeeds" [ "$rc" = 0 ]
check "HEAD is the tip" [ "$(git -C "$R" rev-parse HEAD)" = "$TIP" ]
check "store-url.txt kept" [ "$(cat "$R/store-identity/store-url.txt")" = "$POOL" ]
check "command-log-url.txt kept" [ "$(cat "$R/store-identity/command-log-url.txt")" = automerge:cmdlogPool ]
check "untracked store-template.json kept" [ -f "$R/store-identity/store-template.json" ]
check "config.yaml kept" grep -q "# local" "$R/config.yaml"
check "pm2.config.cjs kept" grep -q "local:1" "$R/pm2.config.cjs"
check "pm2 restarted" grep -q "restart engine" "$WORK/pm2.log"
check "backup holds store-identity" [ -f "$WORK"/bk-ok/engine-deploy-*/store-identity/store-url.txt ]

setup clob; FAKE_BUILD_CLOBBER=1 run clob --yes; rc=$?
check "store reset before restart aborts" [ "$rc" = 3 ]
check "abort names the store" grep -q "before pm2 restart: store-url.txt" "$WORK/out"
check "no pm2 restart after abort" [ ! -e "$WORK/pm2.log" ]

setup wrong; echo "$DEFAULT" > "$R/store-identity/store-url.txt"; run wrong --yes; rc=$?
check "wrong store before deploy aborts" [ "$rc" = 3 ]
check "nothing checked out" [ "$(git -C "$R" rev-parse HEAD)" != "$TIP" ]

setup host; H=idea02 run host --yes; rc=$?
check "idea02 refused" [ "$rc" = 3 ]
setup mod; echo x >> "$R/engine.txt" 2>/dev/null; echo y > "$R/other.txt"; git -C "$R" add other.txt; run mod --yes; rc=$?
check "unexpected tracked change aborts" [ "$rc" = 3 ]

setup dry; run dry; rc=$?
check "dry run exits 0" [ "$rc" = 0 ]
check "dry run changes nothing" [ "$(git -C "$R" rev-parse HEAD)" != "$TIP" ] && [ ! -e "$WORK/pm2.log" ]

echo "passed $pass, failed $fail"; [ "$fail" = 0 ]
