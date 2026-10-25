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
# Fake sudo/systemctl/nmcli: log only. FAKE_SUDO_FAIL=<regex> makes matching sudo calls fail.
cat > "$WORK/bin/sudo" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$WORK/sudo.log"
[ -n "${FAKE_SUDO_FAIL:-}" ] && [[ "$*" =~ $FAKE_SUDO_FAIL ]] && exit 1
exit 0
SH
cat > "$WORK/bin/systemctl" <<'SH'
#!/usr/bin/env bash
[ -n "${FAKE_NM_ACTIVE:-}" ]
SH
chmod +x "$WORK/bin/"*; export PATH="$WORK/bin:$PATH" WORK

setup() {  # repo with defaults committed, then the Pi's local edits on top
  R="$WORK/repo-$1"; rm -rf "$R" "$WORK/pm2.log" "$WORK/sudo.log"; mkdir -p "$R/store-identity"; cd "$R" || exit 1
  git init -q; git config user.email t@t; git config user.name t
  echo "mdns: true" > config.yaml; echo "module.exports={}" > pm2.config.cjs
  echo "$DEFAULT" > store-identity/store-url.txt; echo "automerge:cmdlogDefault" > store-identity/command-log-url.txt
  git add -A; git commit -qm base; echo v2 > engine.txt
  if [ -n "${WITH_VC:-}" ]; then mkdir -p script/build_image_assets; echo '#!/bin/bash' > script/build_image_assets/idea-dhcp-vendor-class; fi
  if [ -n "${WITH_HELPERS:-}" ]; then mkdir -p script/build_image_assets; echo flash-v2 > script/build_image_assets/idea-flash-card
    printf '#!/bin/sh\n[ -n "$FAKE_HELPER_BAD" ] && { echo old > "$SBIN/idea-flash-card"; exit 0; }\ncp script/build_image_assets/idea-flash-card "$SBIN/"\n' > install-root-helpers; chmod +x install-root-helpers; fi
  git add -A; git commit -qm tip
  TIP=$(git rev-parse HEAD); git checkout -q HEAD~1
  echo "mdns: true # local" > config.yaml; echo "module.exports={local:1}" > pm2.config.cjs
  echo "$POOL" > store-identity/store-url.txt; echo "automerge:cmdlogPool" > store-identity/command-log-url.txt
  echo "{}" > store-identity/store-template.json   # untracked, must survive
  cd "$WORK" || exit 1
}
run() { export POST_RESTART_WAIT=0 LOCK_FILE="$WORK/lock-$1"; mkdir -p "$WORK/sbin-$1"; ENGINE_DIR="$R" HOST_NAME="${H:-idea04}" BACKUP_ROOT="$WORK/bk-$1" IDEA_LOCAL="$WORK/idea-local-$1" SBIN="$WORK/sbin-$1" bash "$SCRIPT" "$TIP" "${@:2}" > "$WORK/out" 2>&1; }

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
check "abort names the store" grep -q "before pm2 restart: store-identity/store-url.txt" "$WORK/out"
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

# DHCP vendor class (idea#284)
setup noasset; run noasset --yes; rc=$?
check "no asset: deploy ok and step skipped" [ "$rc" = 0 ] && grep -q "not in this Engine commit, skipped" "$WORK/out" && [ ! -e "$WORK/sudo.log" ]
WITH_VC=1 setup vc; FAKE_NM_ACTIVE=1 run vc --yes; rc=$?
check "vc: deploy succeeds" [ "$rc" = 0 ]
check "vc: helper installed root-owned 0755" grep -qx -- "-n install -o root -g root -m 0755 script/build_image_assets/idea-dhcp-vendor-class /usr/local/sbin/idea-dhcp-vendor-class" "$WORK/sudo.log"
check "vc: helper run after install" [ "$(sed -n 2p "$WORK/sudo.log")" = "-n /usr/local/sbin/idea-dhcp-vendor-class" ]
check "vc: only NM config reloaded" [ "$(sed -n 3p "$WORK/sudo.log")" = "-n nmcli general reload conf" ] && ! grep -Eq "restart|connection (up|down)|device (disconnect|reapply)" "$WORK/sudo.log"
check "vc: pm2 restarted afterwards" grep -q "restart engine" "$WORK/pm2.log"
WITH_VC=1 setup vcnonm; run vcnonm --yes; rc=$?
check "vc without NetworkManager: no nmcli" [ "$rc" = 0 ] && ! grep -q nmcli "$WORK/sudo.log"
WITH_VC=1 setup vcfail; FAKE_SUDO_FAIL='idea-dhcp-vendor-class$' run vcfail --yes; rc=$?
check "vc failure only warns, deploy completes" [ "$rc" = 0 ] && grep -q "WARN: DHCP vendor class not applied" "$WORK/out" && grep -q "restart engine" "$WORK/pm2.log"

# Always keep store-identity even when git hides it (skip-worktree, kits) and ~/.idea-local
setup skip; git -C "$R" update-index --skip-worktree store-identity/store-url.txt store-identity/command-log-url.txt
echo "local=1" > "$WORK/idea-local-skip"; run skip --yes; rc=$?
check "skip-worktree: deploy succeeds" [ "$rc" = 0 ]
check "skip-worktree: store-url kept" [ "$(cat "$R/store-identity/store-url.txt")" = "$POOL" ]
check "idea-local kept and backed up" [ "$(cat "$WORK/idea-local-skip")" = local=1 ] && ls "$WORK"/bk-skip/engine-deploy-*/idea-local >/dev/null 2>&1
check "pm2 save after restart" grep -q "^save" "$WORK/pm2.log"
# --dry-run flag
setup dry2; run dry2 --dry-run; rc=$?
check "--dry-run lists kept sha256 and changes nothing" [ "$rc" = 0 ] && grep -q "store-identity/store-url.txt" "$WORK/out" && [ ! -e "$WORK/pm2.log" ] && [ ! -d "$WORK/bk-dry2" ]
# Root helpers
WITH_HELPERS=1 setup rh; run rh --yes; rc=$?
check "helpers: installed and verified" [ "$rc" = 0 ] && grep -q "helper idea-flash-card sha" "$WORK/out" && grep -q -- "-n visudo -c" "$WORK/sudo.log"
WITH_HELPERS=1 setup rhbad; FAKE_HELPER_BAD=1 run rhbad --yes; rc=$?
check "helpers: sha mismatch aborts before restart" [ "$rc" = 3 ] && [ ! -e "$WORK/pm2.log" ]
setup norh; run norh --yes; rc=$?
check "helpers: missing install-root-helpers only warns" [ "$rc" = 0 ] && grep -q "WARN: ./install-root-helpers not in" "$WORK/out"

# Kit Engines: shared kit store 3Vvvig, never the pool store or the repo default
KIT=automerge:3Vvvigx8bKcuwKALqMVz85GhDqrk
setup kit; echo "$KIT" > "$R/store-identity/store-url.txt"; H=sunny-robin run kit --yes; rc=$?
check "kit: matching kit store deploys" [ "$rc" = 0 ] && [ "$(git -C "$R" rev-parse HEAD)" = "$TIP" ] && [ "$(cat "$R/store-identity/store-url.txt")" = "$KIT" ] && grep -q "store $KIT" "$WORK/out"
setup kitpool; H=kind-panda run kitpool --yes; rc=$?
check "kit: pool store on a kit aborts before any change" [ "$rc" = 3 ] && [ "$(git -C "$R" rev-parse HEAD)" != "$TIP" ] && [ ! -e "$WORK/pm2.log" ] && [ ! -d "$WORK/bk-kitpool" ]
setup kitdef; echo "$DEFAULT" > "$R/store-identity/store-url.txt"; H=happy-zebra run kitdef --yes; rc=$?
check "kit: 4GQm default store aborts before any change" [ "$rc" = 3 ] && [ "$(git -C "$R" rev-parse HEAD)" != "$TIP" ] && [ ! -e "$WORK/pm2.log" ]
setup unk; H=wizardly-hugle run unk --yes; rc=$?
check "unknown host refused" [ "$rc" = 3 ] && grep -q "not a pool Pi or kit Engine" "$WORK/out"

# Pi-side lock: busy -> exit 75, nothing changed
setup lk; ( flock -x 9; sleep 5 ) 9>>"$WORK/lock-lk" & LKPID=$!; sleep 0.5
run lk --yes; rc=$?; kill $LKPID 2>/dev/null; wait $LKPID 2>/dev/null
check "lock busy exits 75" [ "$rc" = 75 ] && grep -q "BUSY" "$WORK/out"
check "lock busy changes nothing" [ "$(git -C "$R" rev-parse HEAD)" != "$TIP" ] && [ ! -e "$WORK/pm2.log" ]
setup lk2; run lk2 --yes; rc=$?
check "lock free deploys" [ "$rc" = 0 ]
# Box-side lock (deploy-engine-remote.sh)
REMOTE="$(dirname "$SCRIPT")/deploy-engine-remote.sh"
( flock -x 8; sleep 5 ) 8>>"$WORK/idea-deploy-idea04.lock" & LKPID=$!; sleep 0.5
BOX_LOCK_DIR="$WORK" SSH_CMD=true bash "$REMOTE" idea04 abc --dry-run > "$WORK/out" 2>&1; rc=$?; kill $LKPID 2>/dev/null; wait $LKPID 2>/dev/null
check "box lock busy exits 75" [ "$rc" = 75 ]
BOX_LOCK_DIR="$WORK" SSH_CMD=true bash "$REMOTE" idea04 abc --dry-run > "$WORK/out" 2>&1; rc=$?
check "box lock free runs ssh" [ "$rc" = 0 ]

# Already on target
cat > "$WORK/bin/pm2" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$WORK/pm2.log"
[ "$1" = pid ] && echo "${FAKE_PM2_PID:-}"
exit 0
SH
chmod +x "$WORK/bin/pm2"
WITH_HELPERS=1 setup on; git -C "$R" checkout -q "$TIP"; mkdir -p "$WORK/sbin-on"; cp "$R/script/build_image_assets/idea-flash-card" "$WORK/sbin-on/"
FAKE_PM2_PID=4242 run on --yes; rc=$?
check "already on target skips" [ "$rc" = 0 ] && grep -q "already on .*, skipping" "$WORK/out" && ! grep -q "restart" "$WORK/pm2.log" && [ ! -d "$WORK/bk-on" ]
WITH_HELPERS=1 setup onh; git -C "$R" checkout -q "$TIP"; mkdir -p "$WORK/sbin-onh"; echo old > "$WORK/sbin-onh/idea-flash-card"
FAKE_PM2_PID=4242 run onh --yes; rc=$?
check "on target but old helper: deploys" [ "$rc" = 0 ] && grep -q "differs from the repo: not skipping" "$WORK/out" && grep -q "restart engine" "$WORK/pm2.log"
WITH_HELPERS=1 setup onp; git -C "$R" checkout -q "$TIP"; mkdir -p "$WORK/sbin-onp"; cp "$R/script/build_image_assets/idea-flash-card" "$WORK/sbin-onp/"
FAKE_PM2_PID=0 run onp --yes; rc=$?
check "on target but engine offline: deploys" [ "$rc" = 0 ] && grep -q "not online: not skipping" "$WORK/out"

# Temperature guard (mocked vcgencmd reads a queue of temps; last value repeats)
cat > "$WORK/bin/vcgencmd" <<'SH'
#!/usr/bin/env bash
[ "$1" = get_throttled ] && { echo throttled=0x0; exit 0; }
q="$WORK/temps"; t=$(head -1 "$q"); [ "$(wc -l < "$q")" -gt 1 ] && sed -i 1d "$q"; echo "temp=${t}'C"
SH
chmod +x "$WORK/bin/vcgencmd"
setup hot; printf '%s\n' 80.1 78.0 70.0 64.0 60.0 > "$WORK/temps"; TEMP_POLL=0 run hot --yes; rc=$?
check "temp: hot pauses then resumes" [ "$rc" = 0 ] && grep -q "TEMP PAUSE before engine-install: 80.1" "$WORK/out" && grep -q "TEMP RESUME engine-install at 64.0" "$WORK/out"
check "temp: 70 C is not enough to resume" grep -q "temp 70.0 C (waiting)" "$WORK/out"
check "temp: peak summary per step" grep -q "TEMP PEAKS" "$WORK/out" && grep -qE "^  engine-install 80.1" "$WORK/out" && grep -qE "^  engine-build 60.0" "$WORK/out"
setup cool; printf '%s\n' 50.0 > "$WORK/temps"; TEMP_POLL=0 run cool --yes; rc=$?
check "temp: cool never pauses" [ "$rc" = 0 ] && ! grep -q "TEMP PAUSE" "$WORK/out"
rm -f "$WORK/bin/vcgencmd"

echo "passed $pass, failed $fail"; [ "$fail" = 0 ]
