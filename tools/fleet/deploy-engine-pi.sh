#!/usr/bin/env bash
# deploy-engine-pi.sh — option-2 Engine deploy on ONE pool Pi: keep the Pi's local config
# AND store identity across a git checkout of a new Engine commit.
#
#   ssh <pi> 'bash -s -- <tip-sha> [--fetch <branch>] [--dry-run|--yes] [--allow-midnight]' < tools/fleet/deploy-engine-pi.sh
#
# Steps: guard host + store -> save config.yaml, pm2.config.cjs and every store-identity/ file
# -> discard those local edits -> git checkout --detach <tip> -> restore the saved files
# -> verify store-url.txt is still the expected store (command-log-url/day may rotate; never restore the old URL)
# -> pnpm install + build -> DHCP vendor class (idea#284) -> ./install-root-helpers (flash/app-data/
# erase/usage-settings/usage-export helpers + sudoers, then sha256 vs the repo and visudo -c) -> verify again -> pm2 restart engine + pm2 save.
# Any failed check aborts BEFORE pm2 restart (exit 3); the running Engine keeps its old store.
# ALWAYS kept, whatever git status says (skip-worktree files included): config.yaml, pm2.config.cjs,
# the whole store-identity/ dir and ~/.idea-local; backed up first, restored byte-for-byte, sha256-checked.
# --dry-run (or no --yes): read-only; prints exactly what it would save, restore and install.
# --production: required for production idea (hostname idea / wizardly-hugle), store fixed to 6f8m,
#   DHCP vendor class skipped; refused on every other host (idea#416 W1).
#
# Why: the repo's tracked store-identity/ files hold the image default (the kit store
# 3Vvv…, idea#452). A plain discard + checkout puts that default back, and a restarted
# pool Engine would then join the kit store. (When the default was 4GQm this happened
# on idea04, 2026-10-14, joining idea02's store.) See docs/ops/engine-deploy-pool-pi.md.
#
# Lock: one deploy per Pi at a time (flock on $LOCK_FILE, default /tmp/idea-deploy.lock, non-blocking;
# busy -> exit 75). Box side: tools/fleet/deploy-engine-remote.sh also locks per host on the box.
# Already on target (HEAD = tip, helpers in HELPERS = repo assets, pm2 engine online, and the
# running process sha equals the tip): "already on <sha>, skipping", exit 0. The running sha is
# dist/build-info.json's commit only when the pm2 engine process started at or after that file
# was written (idea#512). If HEAD and dist are already the tip but the running process is older,
# do not skip: continue so the Engine is restarted. If a helper in HELPERS is missing or differs, do not skip: run install-root-helpers.
# Midnight window: refuse to start between 23:55 and 00:05 local time unless --allow-midnight
# (daily command-log rotation can land in that window). Tests may set DEPLOY_CLOCK_HM=HH:MM.
# Temperature guard: before each build/install step, above TEMP_PAUSE (75 C) it pauses and polls every
# TEMP_POLL s (30) until below TEMP_RESUME (65 C); the peak per step is logged and summarised at the end.
# This script does not deploy the Console (see docs/ops/engine-deploy-pool-pi.md).
# Env overrides (tests): ENGINE_DIR, HOST_NAME, EXPECT_STORE, BACKUP_ROOT, IDEA_LOCAL, SBIN, POST_RESTART_WAIT,
# LOCK_FILE, TEMP_PAUSE, TEMP_RESUME, TEMP_POLL, DEPLOY_CLOCK_HM.
set -euo pipefail

ENGINE_DIR="${ENGINE_DIR:-/home/pi/idea/agents/agent-engine-dev}"
HOST_NAME="${HOST_NAME:-$(hostname)}"
POOL_STORE="automerge:2VroEUvDkmYsDAwE5oG9YeFNadWH"   # idea01/03/04 since 2026-10-13 (fleet-state.json)
KIT_STORE="automerge:3Vvvigx8bKcuwKALqMVz85GhDqrk"   # ONE shared kit store (sunny-robin, happy-zebra, kind-panda; reset 2026-10-18)
PROD_STORE="automerge:6f8m5KxzARv9xwv4Lw18LgVUJzu"  # production idea (fleet-state wizardly-hugle) OWN store; never 2VroE/3Vvv/4GQm
BACKUP_ROOT="${BACKUP_ROOT:-/home/pi/quarantine}"
KEEP="config.yaml pm2.config.cjs"                    # plus every file in store-identity/
IDEA_LOCAL="${IDEA_LOCAL:-$HOME/.idea-local}"        # kit local override, outside the repo; kept too
DEFAULT_STORE_PREFIX="$KIT_STORE"                    # repo/image default (kit store 3Vvv): pool Pis must never be restored to this
HELPERS="idea-flash-card idea-app-data idea-erase-disk idea-usage-settings idea-usage-export"  # script/build_image_assets -> $SBIN
SBIN="${SBIN:-/usr/local/sbin}"

die() { echo "ABORT: $*" >&2; exit 3; }
LOCK_FILE="${LOCK_FILE:-/tmp/idea-deploy.lock}"
exec 9>>"$LOCK_FILE" || die "cannot open lock $LOCK_FILE"
flock -n 9 || { echo "BUSY: another deploy holds $LOCK_FILE on $(hostname) ($(cat "$LOCK_FILE.pid" 2>/dev/null || echo '?')); not starting" >&2; exit 75; }
echo "$$ $(date '+%F %T')" > "$LOCK_FILE.pid" 2>/dev/null || true

TEMP_PAUSE="${TEMP_PAUSE:-75}"; TEMP_RESUME="${TEMP_RESUME:-65}"; TEMP_POLL="${TEMP_POLL:-30}"
PEAKS=""
temp_now() { command -v vcgencmd >/dev/null 2>&1 || return 1; vcgencmd measure_temp 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)?' | head -1; }
gt() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a>b)}'; }
# temp_guard <step>: wait while hot; record the step's peak (also sampled after the step by temp_mark).
temp_guard() {
  local step="$1" t peak=""
  t=$(temp_now) || { echo "temp: vcgencmd not available, guard skipped ($step)"; return 0; }
  peak=$t
  if gt "$t" "$TEMP_PAUSE"; then
    echo "TEMP PAUSE before $step: ${t} C > ${TEMP_PAUSE} C (throttled $(vcgencmd get_throttled 2>/dev/null | cut -d= -f2)); polling every ${TEMP_POLL}s until < ${TEMP_RESUME} C"
    while gt "$t" "$TEMP_RESUME" || [ "$t" = "$TEMP_RESUME" ]; do
      sleep "$TEMP_POLL"; t=$(temp_now) || break; gt "$t" "$peak" && peak=$t
      echo "  temp ${t} C (waiting)"
    done
    echo "TEMP RESUME $step at ${t} C"
  fi
  PEAKS="$PEAKS $step=$peak"; echo "temp before $step: ${t} C"
}
temp_mark() {  # after a step: raise that step's recorded peak if it got hotter
  local step="$1" t; t=$(temp_now) || return 0; echo "temp after $step: ${t} C"; PEAKS="$PEAKS $step=$t"
}
peak_summary() {
  [ -n "$PEAKS" ] || return 0
  echo "TEMP PEAKS per step (C):"
  for kv in $PEAKS; do echo "$kv"; done | awk -F= '{ if(!($1 in m)){o[++n]=$1; m[$1]=$2} else if($2+0>m[$1]+0) m[$1]=$2 } END{for(i=1;i<=n;i++) printf "  %s %s\n", o[i], m[o[i]]}'
}
TIP=""; BRANCH=""; YES=""; DRY=""; PROD=""; ALLOW_MIDNIGHT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) YES=1 ;;
    --dry-run|-n) YES="" ; DRY=1 ;;
    --fetch) BRANCH="${2:?--fetch needs a branch}"; shift ;;
    --production) PROD=1 ;;
    --allow-midnight) ALLOW_MIDNIGHT=1 ;;
    -*) die "unknown option $1" ;;
    *) TIP="$1" ;;
  esac; shift
done
[ -n "$TIP" ] || { sed -n '2,20p' "$0" 2>/dev/null; die "usage: <tip-sha> [--fetch <branch>] [--dry-run|--yes] [--allow-midnight]"; }
[ -n "$DRY" ] && YES=""

case "$HOST_NAME" in
  idea01|idea03|idea04)
    EXPECT_STORE="${EXPECT_STORE:-$POOL_STORE}"
    # Pool deploys always require 2VroE, including when EXPECT_STORE is overridden (tests/env).
    [ "$EXPECT_STORE" = "$POOL_STORE" ] || die "pool deploy requires $POOL_STORE, not $EXPECT_STORE"
    ;;
  sunny-robin|happy-zebra|kind-panda) EXPECT_STORE="${EXPECT_STORE:-$KIT_STORE}" ;;  # only after Steve's GO naming the Engine
  idea|wizardly-hugle)
    # Production idea (idea#416 W1): only with --production, and only after Koen's GO via Steve.
    # The store is fixed to 6f8m; an EXPECT_STORE override to anything else is refused.
    [ -n "$PROD" ] || die "production idea ($HOST_NAME) needs --production (Koen's GO via Steve); MilkWise is never touched"
    EXPECT_STORE="${EXPECT_STORE:-$PROD_STORE}"
    [ "$EXPECT_STORE" = "$PROD_STORE" ] || die "production deploy requires $PROD_STORE, not $EXPECT_STORE"
    ;;
  *) die "not a pool Pi or kit Engine ($HOST_NAME); never idea02, wizardly-hugle or Milkwise" ;;
esac
case "$HOST_NAME" in idea|wizardly-hugle) ;; *) [ -z "$PROD" ] || die "--production is only for production idea, not $HOST_NAME" ;; esac
cd "$ENGINE_DIR"
store_now() { tr -d '[:space:]' < store-identity/store-url.txt; }
# Every kept file, relative to ENGINE_DIR (store-identity/ listed from disk, not from git).
kept_files() { echo $KEEP; find store-identity -type f | sort; }
sums() { for f in $(kept_files); do sha256sum "$f"; done; [ -f "$IDEA_LOCAL" ] && sha256sum "$IDEA_LOCAL"; true; }
check_store() { [ "$(store_now)" = "$EXPECT_STORE" ] || die "$1: store-url.txt is $(store_now), expected $EXPECT_STORE"; }

# Clock used by the midnight window (Pi local time). Tests set DEPLOY_CLOCK_HM=HH:MM.
clock_hm() { echo "${DEPLOY_CLOCK_HM:-$(date +%H:%M)}"; }
# True between 23:55 and 00:05 inclusive (the daily command-log rotation window, idea#512).
in_midnight_window() {
  local hm hh mm n
  hm=$(clock_hm)
  hh=${hm%%:*}; mm=${hm##*:}
  hh=$((10#$hh)); mm=$((10#$mm))
  n=$((hh * 60 + mm))
  [ "$n" -ge 1435 ] || [ "$n" -le 5 ]
}

# Running Engine sha (idea#512). dist/build-info.json is written at `pnpm build` and is
# overwritten by a later build, so it is the *built* sha, not always the *running* sha.
# Trust it only when the pm2 `engine` process started at or after the file was written
# (2s slack for mtime granularity). Otherwise the process is older than this dist.
read_dist_commit() {
  python3 -c 'import json, re, sys
try:
    c = json.load(open("dist/build-info.json")).get("commit", "")
except Exception:
    sys.exit(1)
if not re.fullmatch(r"[0-9a-f]{40}", c or ""):
    sys.exit(1)
print(c)'
}
running_engine_start_ms() {
  python3 -c 'import json, subprocess, sys
try:
    raw = subprocess.check_output(["pm2", "jlist"], text=True, stderr=subprocess.STDOUT)
except Exception:
    sys.exit(1)
i = raw.find("[")
if i < 0:
    sys.exit(1)
try:
    data = json.loads(raw[i:])
except Exception:
    sys.exit(1)
if not isinstance(data, list):
    sys.exit(1)
for a in data:
    if not isinstance(a, dict) or a.get("name") != "engine":
        continue
    u = (a.get("pm2_env") or {}).get("pm_uptime")
    if u in (None, "", 0, "0"):
        sys.exit(1)
    print(int(u))
    sys.exit(0)
sys.exit(1)'
}
dist_mtime_ms() {
  python3 -c 'import os, sys
p = "dist/build-info.json"
try:
    print(int(os.path.getmtime(p) * 1000))
except Exception:
    sys.exit(1)'
}
# Prints the running sha when it can be proven; otherwise returns 1.
running_engine_sha() {
  local commit start dist_ms
  commit=$(read_dist_commit) || return 1
  start=$(running_engine_start_ms) || return 1
  dist_ms=$(dist_mtime_ms) || return 1
  # Process started more than 2s before this dist was written: not this build.
  if [ $((start + 2000)) -lt "$dist_ms" ]; then
    return 1
  fi
  printf '%s
' "$commit"
}

# 1. Guards (read-only)
if in_midnight_window && [ -z "$ALLOW_MIDNIGHT" ]; then
  die "refusing to deploy between 23:55 and 00:05 local time (now $(clock_hm)); pass --allow-midnight to override (idea#512)"
fi
check_store "before deploy"
mods="$(git status --porcelain --untracked-files=no | awk '{print $2}')"
for f in $mods; do
  case " $KEEP " in *" $f "*) continue ;; esac
  case "$f" in store-identity/*) continue ;; esac
  die "unexpected tracked local modification: $f"
done
# Pool only: refuse the tracked/image default (kit store 3Vvv). Kits are meant to be
# on that default, so they are not checked here. check_store already requires 2VroE
# for pool hosts; this is belt-and-suspenders if that check is ever skipped.
case "$HOST_NAME" in
  idea01|idea03|idea04)
    case "$(store_now)" in "$DEFAULT_STORE_PREFIX"*) die "store-url.txt is the repo default ($(store_now)); refusing";; esac
    ;;
esac
echo "HOST $HOST_NAME HEAD $(git rev-parse --short HEAD) STORE $(store_now) local mods: $(echo $mods)"
# Already on target: same commit, helpers equal to the repo assets, Engine online,
# and the running process sha equals the tip (not just checkout HEAD / dist) -> nothing to do.
if git cat-file -e "$TIP^{commit}" 2>/dev/null && [ "$(git rev-parse HEAD)" = "$(git rev-parse "$TIP^{commit}")" ]; then
  same=1
  for h in $HELPERS; do
    a="script/build_image_assets/$h"; [ -f "$a" ] || continue
    [ "$(sha256sum < "$a" | cut -c1-64)" = "$(sha256sum < "$SBIN/$h" 2>/dev/null | cut -c1-64)" ] || { same=""; echo "on $TIP but $h differs from the repo: not skipping"; }
  done
  pid=$(pm2 pid engine 2>/dev/null | tail -1)
  case "$pid" in ''|0) same=""; echo "on $TIP but pm2 engine is not online: not skipping" ;; esac
  if [ -n "$same" ]; then
    tip_full=$(git rev-parse "$TIP^{commit}")
    run_sha=$(running_engine_sha) || run_sha=""
    if [ "$run_sha" = "$tip_full" ]; then
      echo "already on $(git rev-parse --short HEAD), skipping (helpers match, pm2 engine pid $pid, running sha ${run_sha:0:12})"
      exit 0
    fi
    echo "HEAD and dist already $TIP but the running Engine is older (pid $pid${run_sha:+ sha $run_sha}): not skipping, will restart"
  fi
fi
if [ -z "$YES" ]; then
  echo "DRY RUN (nothing changed). Target $TIP$([ -n "$BRANCH" ] && echo " (would fetch origin $BRANCH first)")"
  git cat-file -e "$TIP^{commit}" 2>/dev/null && echo "  tip present: $(git log -1 --format='%h %s' "$TIP")" || echo "  tip NOT present locally (needs --fetch <branch>)"
  echo "  would save to $BACKUP_ROOT/engine-deploy-<ts>/ and restore byte-for-byte (sha256):"
  sums | sed 's/^/    /'
  [ -f "$IDEA_LOCAL" ] || echo "    ($IDEA_LOCAL not present: nothing to keep)"
  echo "  would run: git checkout --detach $TIP; pnpm install --frozen-lockfile; pnpm build; $([ -n "$PROD" ] && echo 'DHCP vendor class SKIPPED (production)' || echo 'DHCP vendor class')"
  if git cat-file -e "$TIP:install-root-helpers" 2>/dev/null; then
    echo "  would run ./install-root-helpers, then expect in /usr/local/sbin (repo sha256 at $TIP vs installed now):"
    for h in $HELPERS; do
      want=$(git show "$TIP:script/build_image_assets/$h" 2>/dev/null | sha256sum | cut -c1-16) || want=-
      have=$(sha256sum "$SBIN/$h" 2>/dev/null | cut -c1-16) || have=missing
      echo "    $h repo $want installed ${have:-missing}$([ "$want" = "$have" ] && echo ' (same)' || echo ' (WOULD CHANGE)')"
    done
    echo "  then: sudo -n visudo -c"
  else
    echo "  WARN: install-root-helpers not in $TIP: helpers would be left as they are"
  fi
  echo "  then: pm2 restart engine --update-env; pm2 save"
  exit 0
fi

# 2. Save
BK="$BACKUP_ROOT/engine-deploy-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BK"
cp -a $KEEP store-identity "$BK/"
[ -f "$IDEA_LOCAL" ] && cp -a "$IDEA_LOCAL" "$BK/idea-local"
git rev-parse HEAD > "$BK/HEAD"
sums > "$BK/SHA256SUMS"
echo "saved to $BK: $KEEP $(cd store-identity && ls -A | sed 's|^|store-identity/|' | xargs)"

# 3. Discard (tracked local edits of the kept files only), 4. check out
[ -n "$BRANCH" ] && git fetch -q origin "$BRANCH"
git cat-file -e "$TIP^{commit}" 2>/dev/null || die "tip $TIP not present (use --fetch <branch>)"
# Discard only what git reports as modified: a skip-worktree path (kits) is invisible to
# "git checkout -- store-identity" (pathspec error). The backup restores everything below anyway.
# shellcheck disable=SC2086
[ -z "$mods" ] || git checkout -q -- $mods
git checkout -q --detach "$TIP"

# 5. Restore every saved file (including untracked ones), 6. verify
cp -a "$BK/config.yaml" "$BK/pm2.config.cjs" .
cp -a "$BK/store-identity/." store-identity/
# Daily command-log identity files that may change at midnight while store-url stays put (idea#512).
is_command_log_rotation_path() {
  case "$1" in
    store-identity/command-log-url.txt|store-identity/command-log-day.txt) return 0 ;;
    *) return 1 ;;
  esac
}
verify_kept() {  # byte-for-byte against the backup, then sha256 against SHA256SUMS.
  # A command-log rotation (url/day differ, store-url unchanged) is logged and accepted;
  # the live files are kept and the old URL is never restored. A store-url change still aborts.
  local label="$1" rotation="" f
  if ! cmp -s store-identity/store-url.txt "$BK/store-identity/store-url.txt"; then
    die "$label: store-identity/store-url.txt differs from the saved copy (backup: $BK)"
  fi
  for f in $KEEP $(cd "$BK" && find store-identity -type f); do
    [ "$f" = store-identity/store-url.txt ] && continue
    if cmp -s "$f" "$BK/$f"; then continue; fi
    if is_command_log_rotation_path "$f"; then
      echo "$label: $f differs from the saved copy; treating as command-log rotation (store-url unchanged $(store_now)); keeping the live file, not restoring the old URL"
      rotation=1
      continue
    fi
    die "$label: $f differs from the saved copy (backup: $BK)"
  done
  if [ -f "$BK/idea-local" ]; then cmp -s "$IDEA_LOCAL" "$BK/idea-local" || die "$label: $IDEA_LOCAL changed (backup: $BK)"; fi
  if [ -n "$rotation" ]; then
    # Exclude the rotated command-log files from the backup sums; everything else must still match.
    grep -Ev '[[:space:]]store-identity/command-log-(url|day)\.txt$' "$BK/SHA256SUMS" | sha256sum --quiet -c -       || die "$label: sha256 mismatch on kept files (backup: $BK)"
  else
    sha256sum --quiet -c "$BK/SHA256SUMS" || die "$label: sha256 mismatch on kept files (backup: $BK)"
  fi
}
verify_kept "after checkout"
check_store "after checkout"
echo "restored: config.yaml sha $(sha256sum config.yaml | cut -c1-16), store $(store_now)"

# 7. Build, verify again, restart
temp_guard engine-install
pnpm install --frozen-lockfile
temp_mark engine-install
temp_guard engine-build
pnpm build
temp_mark engine-build
# DHCP option 60 "idea-engine" (idea#209 D8, idea#284): same step as the Engine's
# installRootHelpers. Idempotent; never restarts NetworkManager or touches a link.
# A failure only warns: check-fleet-health.sh reports a missing drop-in.
VC_ASSET=script/build_image_assets/idea-dhcp-vendor-class
VC_HELPER=/usr/local/sbin/idea-dhcp-vendor-class
if [ -n "$PROD" ]; then
  echo "DHCP vendor class: skipped on production idea (home LAN, not a kit router; idea#284)"
elif [ -f "$VC_ASSET" ]; then
  if sudo -n install -o root -g root -m 0755 "$VC_ASSET" "$VC_HELPER" && sudo -n "$VC_HELPER"; then
    if systemctl is-active --quiet NetworkManager; then sudo -n nmcli general reload conf || echo "WARN: nmcli general reload conf failed" >&2; fi
  else
    echo "WARN: DHCP vendor class not applied (idea#284); check-fleet-health.sh will report it" >&2
  fi
else
  echo "DHCP vendor class: $VC_ASSET not in this Engine commit, skipped"
fi
# Root helpers (flash, app-data, erase-disk, usage-settings, usage-export, sudoers): no Engine runs new code with an old helper.
# install-root-helpers calls sudo itself (passwordless sudo, as pi) and runs visudo -cf on the sudoers files.
temp_guard root-helpers
if [ -x ./install-root-helpers ]; then
  ./install-root-helpers || die "install-root-helpers failed (code is updated, Engine NOT restarted; backup $BK)"
  for h in $HELPERS; do
    a="script/build_image_assets/$h"; [ -f "$a" ] || continue
    [ "$(sha256sum < "$a" | cut -c1-64)" = "$(sha256sum < "$SBIN/$h" | cut -c1-64)" ] \
      || die "$SBIN/$h sha256 differs from $a after install-root-helpers"
    echo "helper $h sha $(sha256sum < "$a" | cut -c1-16) ok"
  done
  sudo -n visudo -c >/dev/null || die "visudo -c failed after install-root-helpers"
else
  echo "WARN: ./install-root-helpers not in this Engine commit; root helpers NOT updated" >&2
fi
temp_mark root-helpers
temp_guard pm2-restart
verify_kept "before pm2 restart"
check_store "before pm2 restart"
pm2 restart engine --update-env
pm2 save
sleep "${POST_RESTART_WAIT:-5}"
check_store "after pm2 restart"
peak_summary
echo "DEPLOYED $HOST_NAME HEAD $(git rev-parse --short HEAD) store $(store_now) backup $BK"
