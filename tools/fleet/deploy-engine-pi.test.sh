#!/usr/bin/env bash
# deploy-engine-pi.test.sh — offline tests for deploy-engine-pi.sh with a temp git repo and
# fake pnpm/pm2. No Pi touched. Usage: tools/fleet/deploy-engine-pi.test.sh  (exit 0 = all pass)
set -uo pipefail
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/deploy-engine-pi.sh"
pass=0; fail=0
check() { local n="$1"; shift; if "$@"; then echo "PASS $n"; pass=$((pass+1)); else echo "FAIL $n"; fail=$((fail+1)); fi; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
# Committed/image default in the fixture repo: the kit store (idea#452).
DEFAULT=automerge:3Vvvigx8bKcuwKALqMVz85GhDqrk
POOL=automerge:2VroEUvDkmYsDAwE5oG9YeFNadWH
# idea02's actual store; no longer the repo default. Used as a wrong-store fixture.
IDEA02=automerge:4GQmEZehPDfryGDxkFo9XixbvmAC
mkdir -p "$WORK/bin"
cat > "$WORK/bin/pm2" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$WORK/pm2.log"
SH
cat > "$WORK/bin/pnpm" <<'SH'
#!/usr/bin/env bash
# FAKE_BUILD_CLOBBER=1 simulates a build step that resets the store id.
# FAKE_BUILD_ROTATE=1 simulates a midnight command-log rotation during the build (idea#512).
[ "$1" = build ] && [ -n "${FAKE_BUILD_CLOBBER:-}" ] && git checkout -q -- store-identity/store-url.txt
if [ "$1" = build ] && [ -n "${FAKE_BUILD_ROTATE:-}" ]; then
  echo "automerge:cmdlogRotated" > store-identity/command-log-url.txt
  echo "2026-11-14" > store-identity/command-log-day.txt
fi
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
  if [ -n "${WITH_HELPERS:-}" ]; then mkdir -p script/build_image_assets
    echo flash-v2 > script/build_image_assets/idea-flash-card
    echo appdata-v2 > script/build_image_assets/idea-app-data
    echo erase-v2 > script/build_image_assets/idea-erase-disk
    echo settings-v2 > script/build_image_assets/idea-usage-settings
    echo export-v2 > script/build_image_assets/idea-usage-export
    cat > install-root-helpers <<'IRH'
#!/bin/sh
for a in script/build_image_assets/idea-flash-card script/build_image_assets/idea-app-data script/build_image_assets/idea-erase-disk script/build_image_assets/idea-usage-settings script/build_image_assets/idea-usage-export; do
  [ -f "$a" ] || continue
  b=$(basename "$a")
  if [ -n "$FAKE_HELPER_BAD" ] && [ "$b" = idea-flash-card ]; then echo old > "$SBIN/$b"; continue; fi
  cp "$a" "$SBIN/$b"
done
IRH
    chmod +x install-root-helpers; fi
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
check "pool: kit/default store 3Vvv aborts before any change" [ "$rc" = 3 ] && [ "$(git -C "$R" rev-parse HEAD)" != "$TIP" ] && [ ! -e "$WORK/pm2.log" ]
check "pool: 3Vvv abort names the expected 2VroE store" grep -q "expected $POOL" "$WORK/out"
setup wrong4; echo "$IDEA02" > "$R/store-identity/store-url.txt"; run wrong4 --yes; rc=$?
check "pool: idea02 4GQm store aborts before any change" [ "$rc" = 3 ] && [ "$(git -C "$R" rev-parse HEAD)" != "$TIP" ] && [ ! -e "$WORK/pm2.log" ]
setup wrong01; echo "$DEFAULT" > "$R/store-identity/store-url.txt"; H=idea01 run wrong01 --yes; rc=$?
check "idea01: kit/default store 3Vvv aborts before any change" [ "$rc" = 3 ] && [ "$(git -C "$R" rev-parse HEAD)" != "$TIP" ] && [ ! -e "$WORK/pm2.log" ]
setup over; EXPECT_STORE="$DEFAULT" run over --yes; rc=$?
check "pool: EXPECT_STORE override to 3Vvv still refused" [ "$rc" = 3 ] && [ "$(git -C "$R" rev-parse HEAD)" != "$TIP" ] && [ ! -e "$WORK/pm2.log" ]
check "pool: override abort names the required 2VroE store" grep -q "pool deploy requires $POOL" "$WORK/out"
# After the prefix assignment on a function, leave EXPECT_STORE unset for later cases.
unset EXPECT_STORE || true

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
check "helpers: installed and verified" [ "$rc" = 0 ] && grep -q "helper idea-flash-card sha" "$WORK/out" && grep -q "helper idea-usage-settings sha" "$WORK/out" && grep -q "helper idea-usage-export sha" "$WORK/out" && grep -q -- "-n visudo -c" "$WORK/sudo.log"
WITH_HELPERS=1 setup rhbad; FAKE_HELPER_BAD=1 run rhbad --yes; rc=$?
check "helpers: sha mismatch aborts before restart" [ "$rc" = 3 ] && [ ! -e "$WORK/pm2.log" ]
setup norh; run norh --yes; rc=$?
check "helpers: missing install-root-helpers only warns" [ "$rc" = 0 ] && grep -q "WARN: ./install-root-helpers not in" "$WORK/out"

# Kit Engines: shared kit store 3Vvvig, which is also the repo/image default.
# Never the pool store or idea02's 4GQm store.
KIT=$DEFAULT
setup kit; echo "$KIT" > "$R/store-identity/store-url.txt"; H=sunny-robin run kit --yes; rc=$?
check "kit: matching kit store deploys" [ "$rc" = 0 ] && [ "$(git -C "$R" rev-parse HEAD)" = "$TIP" ] && [ "$(cat "$R/store-identity/store-url.txt")" = "$KIT" ] && grep -q "store $KIT" "$WORK/out"
setup kitpool; H=kind-panda run kitpool --yes; rc=$?
check "kit: pool store on a kit aborts before any change" [ "$rc" = 3 ] && [ "$(git -C "$R" rev-parse HEAD)" != "$TIP" ] && [ ! -e "$WORK/pm2.log" ] && [ ! -d "$WORK/bk-kitpool" ]
setup kitdef; echo "$IDEA02" > "$R/store-identity/store-url.txt"; H=happy-zebra run kitdef --yes; rc=$?
check "kit: idea02 4GQm store aborts before any change" [ "$rc" = 3 ] && [ "$(git -C "$R" rev-parse HEAD)" != "$TIP" ] && [ ! -e "$WORK/pm2.log" ]
setup unk; H=idea02 run unk --yes; rc=$?
check "unknown host refused" [ "$rc" = 3 ] && grep -q "not a pool Pi or kit Engine" "$WORK/out"
# Production idea (idea#416 W1): --production required, store fixed to 6f8m
PROD=automerge:6f8m5KxzARv9xwv4Lw18LgVUJzu
setup pnf; echo "$PROD" > "$R/store-identity/store-url.txt"; H=wizardly-hugle run pnf --yes; rc=$?
check "prod: without --production refused, nothing changed" [ "$rc" = 3 ] && grep -q "needs --production" "$WORK/out" && [ "$(git -C "$R" rev-parse HEAD)" != "$TIP" ] && [ ! -e "$WORK/pm2.log" ]
setup pok; echo "$PROD" > "$R/store-identity/store-url.txt"; H=idea run pok --yes --production; rc=$?
check "prod: 6f8m with --production deploys and keeps the store" [ "$rc" = 0 ] && [ "$(git -C "$R" rev-parse HEAD)" = "$TIP" ] && [ "$(cat "$R/store-identity/store-url.txt")" = "$PROD" ] && grep -q "DHCP vendor class: skipped on production" "$WORK/out"
setup ppool; H=idea run ppool --yes --production; rc=$?
check "prod: pool store on idea aborts before any change" [ "$rc" = 3 ] && [ "$(git -C "$R" rev-parse HEAD)" != "$TIP" ] && [ ! -e "$WORK/pm2.log" ]
setup povr; echo "$PROD" > "$R/store-identity/store-url.txt"; EXPECT_STORE=$POOL H=idea run povr --yes --production; rc=$?
check "prod: EXPECT_STORE override refused" [ "$rc" = 3 ] && grep -q "production deploy requires" "$WORK/out"
setup pother; run pother --yes --production; rc=$?
check "prod: --production on a pool Pi refused" [ "$rc" = 3 ] && grep -q "only for production idea" "$WORK/out" && [ ! -e "$WORK/pm2.log" ]

# Pi-side lock: busy -> exit 75, nothing changed
setup lk; ( flock -x 9; sleep 5 ) 9>>"$WORK/lock-lk" & LKPID=$!; sleep 0.5
run lk --yes; rc=$?; kill $LKPID 2>/dev/null; wait $LKPID 2>/dev/null
check "lock busy exits 75" [ "$rc" = 75 ] && grep -q "BUSY" "$WORK/out"
check "lock busy changes nothing" [ "$(git -C "$R" rev-parse HEAD)" != "$TIP" ] && [ ! -e "$WORK/pm2.log" ]
setup lk2; run lk2 --yes; rc=$?
check "lock free deploys" [ "$rc" = 0 ]
# Box-side lock (deploy-engine-remote.sh)
REMOTE="$(dirname "$SCRIPT")/deploy-engine-remote.sh"
export HEALTH_DIR="$WORK/health-none"   # never the box's real PAUSED/HOLD (deploy-engine-remote.sh honours them)
( flock -x 8; sleep 5 ) 8>>"$WORK/idea-deploy-idea04.lock" & LKPID=$!; sleep 0.5
BOX_LOCK_DIR="$WORK" SSH_CMD=true bash "$REMOTE" idea04 abc --dry-run > "$WORK/out" 2>&1; rc=$?; kill $LKPID 2>/dev/null; wait $LKPID 2>/dev/null
check "box lock busy exits 75" [ "$rc" = 75 ]
BOX_LOCK_DIR="$WORK" SSH_CMD=true bash "$REMOTE" idea04 abc --dry-run > "$WORK/out" 2>&1; rc=$?
check "box lock free runs ssh" [ "$rc" = 0 ]
# Fleet-wide pause: deploy-engine-remote.sh honours PAUSED/HOLD like the fleet-lib scripts
printf '#!/usr/bin/env bash\ncat >/dev/null; echo "$*" >> "%s/remote-ssh.log"\n' "$WORK" > "$WORK/logssh"; chmod +x "$WORK/logssh"
mkdir -p "$HEALTH_DIR"; echo "paused by test" > "$HEALTH_DIR/PAUSED"
BOX_LOCK_DIR="$WORK" SSH_CMD="$WORK/logssh" bash "$REMOTE" idea04 abc --yes > "$WORK/out" 2>&1; rc=$?
check "remote: PAUSED refuses (exit 1, no ssh)" [ "$rc" = 1 ] && grep -q "REFUSED: fleet changes are paused" "$WORK/out" && [ ! -e "$WORK/remote-ssh.log" ]
BOX_LOCK_DIR="$WORK" SSH_CMD="$WORK/logssh" bash "$REMOTE" idea04 abc --dry-run > "$WORK/out" 2>&1; rc=$?
check "remote: PAUSED refuses a dry run too (same as update-golden)" [ "$rc" = 1 ]
BOX_LOCK_DIR="$WORK" SSH_CMD="$WORK/logssh" bash "$REMOTE" idea04 abc --yes --ignore-fleet-hold > "$WORK/out" 2>&1; rc=$?
check "remote: --ignore-fleet-hold proceeds with a warning" [ "$rc" = 0 ] && grep -q "WARNING: --ignore-fleet-hold" "$WORK/out"
check "remote: --ignore-fleet-hold is not forwarded to the Pi" grep -q -- "--yes" "$WORK/remote-ssh.log" && ! grep -q -- "--ignore-fleet-hold" "$WORK/remote-ssh.log"
check "remote: PAUSED file untouched" [ "$(cat "$HEALTH_DIR/PAUSED")" = "paused by test" ]
rm -f "$HEALTH_DIR/PAUSED"; touch "$HEALTH_DIR/HOLD"
BOX_LOCK_DIR="$WORK" SSH_CMD="$WORK/logssh" bash "$REMOTE" idea04 abc --yes > "$WORK/out" 2>&1; rc=$?
check "remote: HOLD refuses too" [ "$rc" = 1 ]
rm -f "$HEALTH_DIR/HOLD"

# Already on target
cat > "$WORK/bin/pm2" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$WORK/pm2.log"
if [ "$1" = pid ]; then echo "${FAKE_PM2_PID:-}"; exit 0; fi
if [ "$1" = jlist ]; then
  # pm_uptime is ms-since-epoch when the process started (pm2).
  printf '[{"name":"engine","pid":%s,"pm2_env":{"status":"online","pm_uptime":%s}}]\n' "${FAKE_PM2_PID:-0}" "${FAKE_PM2_UPTIME_MS:-0}"
  exit 0
fi
exit 0
SH
chmod +x "$WORK/bin/pm2"
install_repo_helpers() {  # copy every HELPERS asset from $1 (repo) into $2 (sbin)
  local src="$1/script/build_image_assets" dest="$2"
  mkdir -p "$dest"
  for h in idea-flash-card idea-app-data idea-erase-disk idea-usage-settings idea-usage-export; do
    [ -f "$src/$h" ] && cp "$src/$h" "$dest/$h"
  done
}
# Write dist/build-info.json for $R at HEAD and set FAKE_PM2_UPTIME_MS relative to its mtime.
# offset_ms > 0: process started after the dist (running sha can be trusted).
# offset_ms < 0: process started before the dist (running process is older, idea#512).
stamp_build_info() {
  local offset_ms="${1:-5000}" commit
  commit=$(git -C "$R" rev-parse HEAD)
  mkdir -p "$R/dist"
  printf '{"commit":"%s","commitTimeMs":1}\n' "$commit" > "$R/dist/build-info.json"
  FAKE_PM2_UPTIME_MS=$(python3 -c "import os; print(int(os.path.getmtime('$R/dist/build-info.json')*1000)+int('$offset_ms'))")
  export FAKE_PM2_UPTIME_MS
}
WITH_HELPERS=1 setup on; git -C "$R" checkout -q "$TIP"; install_repo_helpers "$R" "$WORK/sbin-on"
stamp_build_info 5000
FAKE_PM2_PID=4242 run on --yes; rc=$?
check "already on target skips" [ "$rc" = 0 ] && grep -q "already on .*, skipping" "$WORK/out" && ! grep -q "restart" "$WORK/pm2.log" && [ ! -d "$WORK/bk-on" ]
WITH_HELPERS=1 setup onh; git -C "$R" checkout -q "$TIP"; install_repo_helpers "$R" "$WORK/sbin-onh"; echo old > "$WORK/sbin-onh/idea-flash-card"
FAKE_PM2_PID=4242 run onh --yes; rc=$?
check "on target but old helper: deploys" [ "$rc" = 0 ] && grep -q "differs from the repo: not skipping" "$WORK/out" && grep -q "restart engine" "$WORK/pm2.log"
WITH_HELPERS=1 setup onp; git -C "$R" checkout -q "$TIP"; install_repo_helpers "$R" "$WORK/sbin-onp"
FAKE_PM2_PID=0 run onp --yes; rc=$?
check "on target but engine offline: deploys" [ "$rc" = 0 ] && grep -q "not online: not skipping" "$WORK/out"
# idea#412: already-on-tip must not skip when usage helpers are missing or stale
WITH_HELPERS=1 setup onmiss; git -C "$R" checkout -q "$TIP"; install_repo_helpers "$R" "$WORK/sbin-onmiss"; rm -f "$WORK/sbin-onmiss/idea-usage-settings"
FAKE_PM2_PID=4242 run onmiss --yes; rc=$?
check "on target but idea-usage-settings missing: not skip, install-root-helpers runs" [ "$rc" = 0 ] && grep -q "idea-usage-settings differs from the repo: not skipping" "$WORK/out" && grep -q "helper idea-usage-settings sha" "$WORK/out" && [ -f "$WORK/sbin-onmiss/idea-usage-settings" ] && grep -q "restart engine" "$WORK/pm2.log"
WITH_HELPERS=1 setup onexp; git -C "$R" checkout -q "$TIP"; install_repo_helpers "$R" "$WORK/sbin-onexp"; echo stale-export > "$WORK/sbin-onexp/idea-usage-export"
FAKE_PM2_PID=4242 run onexp --yes; rc=$?
check "on target but idea-usage-export differs: not skip, helper refreshed" [ "$rc" = 0 ] && grep -q "idea-usage-export differs from the repo: not skipping" "$WORK/out" && grep -q "helper idea-usage-export sha" "$WORK/out" && [ "$(cat "$WORK/sbin-onexp/idea-usage-export")" = export-v2 ]
WITH_HELPERS=1 setup dryusage; git -C "$R" checkout -q "$TIP"; install_repo_helpers "$R" "$WORK/sbin-dryusage"; rm -f "$WORK/sbin-dryusage/idea-usage-settings"
FAKE_PM2_PID=4242 run dryusage --dry-run; rc=$?
check "dry-run lists idea-usage-settings WOULD CHANGE and does not install" [ "$rc" = 0 ] && grep -q "idea-usage-settings" "$WORK/out" && grep -q "WOULD CHANGE" "$WORK/out" && [ ! -f "$WORK/sbin-dryusage/idea-usage-settings" ] && [ ! -e "$WORK/pm2.log" ] && [ ! -d "$WORK/bk-dryusage" ]

# idea#512: command-log rotation, running-sha skip, midnight window
setup rot; FAKE_BUILD_ROTATE=1 run rot --yes; rc=$?
check "command-log rotation during build does not abort" [ "$rc" = 0 ]
check "command-log rotation is logged and live URL is kept" grep -q "treating as command-log rotation" "$WORK/out" && [ "$(cat "$R/store-identity/command-log-url.txt")" = automerge:cmdlogRotated ]
check "command-log rotation leaves store-url unchanged and still restarts" [ "$(cat "$R/store-identity/store-url.txt")" = "$POOL" ] && grep -q "restart engine" "$WORK/pm2.log"
check "command-log rotation never restores the old URL" [ "$(cat "$R/store-identity/command-log-url.txt")" = automerge:cmdlogRotated ]
check "command-log rotation leaves the new day file in place" [ "$(cat "$R/store-identity/command-log-day.txt")" = "2026-11-14" ]

setup rotstore; FAKE_BUILD_CLOBBER=1 FAKE_BUILD_ROTATE=1 run rotstore --yes; rc=$?
check "store-url change still aborts even if the command log also rotated" [ "$rc" = 3 ] && grep -q "before pm2 restart: store-identity/store-url.txt" "$WORK/out" && [ ! -e "$WORK/pm2.log" ]

# HEAD + dist already the tip, but the running process started before this dist was written.
WITH_HELPERS=1 setup stale; git -C "$R" checkout -q "$TIP"; install_repo_helpers "$R" "$WORK/sbin-stale"
stamp_build_info -600000
FAKE_PM2_PID=4242 run stale --yes; rc=$?
check "on target but running Engine is older: does not skip, restarts" [ "$rc" = 0 ] && grep -q "running Engine is older" "$WORK/out" && grep -q "restart engine" "$WORK/pm2.log" && ! grep -q "skipping" "$WORK/out"

# No build-info: cannot prove the running sha, so do not skip on HEAD alone.
WITH_HELPERS=1 setup nobi; git -C "$R" checkout -q "$TIP"; install_repo_helpers "$R" "$WORK/sbin-nobi"
unset FAKE_PM2_UPTIME_MS || true
FAKE_PM2_PID=4242 run nobi --yes; rc=$?
check "on target but no build-info: does not skip, restarts" [ "$rc" = 0 ] && grep -q "running Engine is older" "$WORK/out" && grep -q "restart engine" "$WORK/pm2.log" && ! grep -q "skipping" "$WORK/out"

setup mid; DEPLOY_CLOCK_HM=00:00 run mid --yes; rc=$?
check "midnight 00:00 refuses without --allow-midnight" [ "$rc" = 3 ] && grep -q "refusing to deploy between 23:55 and 00:05" "$WORK/out" && [ "$(git -C "$R" rev-parse HEAD)" != "$TIP" ] && [ ! -e "$WORK/pm2.log" ] && [ ! -d "$WORK/bk-mid" ]
setup mid55; DEPLOY_CLOCK_HM=23:55 run mid55 --yes; rc=$?
check "midnight 23:55 refuses" [ "$rc" = 3 ] && grep -q "refusing to deploy between 23:55 and 00:05" "$WORK/out" && [ ! -e "$WORK/pm2.log" ]
setup mid05; DEPLOY_CLOCK_HM=00:05 run mid05 --yes; rc=$?
check "midnight 00:05 refuses" [ "$rc" = 3 ] && grep -q "refusing to deploy between 23:55 and 00:05" "$WORK/out" && [ ! -e "$WORK/pm2.log" ]
setup midgo; DEPLOY_CLOCK_HM=00:00 run midgo --yes --allow-midnight; rc=$?
check "--allow-midnight deploys at 00:00" [ "$rc" = 0 ] && grep -q "restart engine" "$WORK/pm2.log" && [ "$(git -C "$R" rev-parse HEAD)" = "$TIP" ]
setup mid54; DEPLOY_CLOCK_HM=23:54 run mid54 --yes; rc=$?
check "23:54 is outside the window and deploys" [ "$rc" = 0 ] && grep -q "restart engine" "$WORK/pm2.log"
setup mid06; DEPLOY_CLOCK_HM=00:06 run mid06 --yes; rc=$?
check "00:06 is outside the window and deploys" [ "$rc" = 0 ] && grep -q "restart engine" "$WORK/pm2.log"
# remote forwards --allow-midnight in $*
BOX_LOCK_DIR="$WORK" SSH_CMD=true bash "$REMOTE" idea04 abc --yes --allow-midnight > "$WORK/out" 2>&1; rc=$?
check "box remote forwards --allow-midnight" [ "$rc" = 0 ]

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
