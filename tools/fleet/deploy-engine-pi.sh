#!/usr/bin/env bash
# deploy-engine-pi.sh — option-2 Engine deploy on ONE pool Pi: keep the Pi's local config
# AND store identity across a git checkout of a new Engine commit.
#
#   ssh <pi> 'bash -s -- <tip-sha> [--fetch <branch>] [--yes]' < tools/fleet/deploy-engine-pi.sh
#
# Steps: guard host + store -> save config.yaml, pm2.config.cjs and every store-identity/ file
# -> discard those local edits -> git checkout --detach <tip> -> restore the saved files
# -> verify they are byte-identical and store-url.txt is still the expected store
# -> pnpm install + build -> verify again -> pm2 restart engine.
# Any failed check aborts BEFORE pm2 restart (exit 3); the running Engine keeps its old store.
# Without --yes it only runs the read-only checks and prints the plan.
#
# Why: the repo's tracked store-identity/ files hold the defaults (idea02's production store).
# A plain discard + checkout puts those back, and a restarted pool Engine then joins idea02's
# store (idea04, 2026-10-14). See docs/ops/engine-deploy-pool-pi.md.
#
# Env overrides (tests): ENGINE_DIR, HOST_NAME, EXPECT_STORE, BACKUP_ROOT.
set -euo pipefail

ENGINE_DIR="${ENGINE_DIR:-/home/pi/idea/agents/agent-engine-dev}"
HOST_NAME="${HOST_NAME:-$(hostname)}"
POOL_STORE="automerge:2VroEUvDkmYsDAwE5oG9YeFNadWH"   # idea01/03/04 since 2026-10-13 (fleet-state.json)
BACKUP_ROOT="${BACKUP_ROOT:-/home/pi/quarantine}"
KEEP="config.yaml pm2.config.cjs"                    # plus every file in store-identity/

die() { echo "ABORT: $*" >&2; exit 3; }
TIP=""; BRANCH=""; YES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) YES=1 ;;
    --fetch) BRANCH="${2:?--fetch needs a branch}"; shift ;;
    -*) die "unknown option $1" ;;
    *) TIP="$1" ;;
  esac; shift
done
[ -n "$TIP" ] || { sed -n '2,17p' "$0" 2>/dev/null; die "usage: <tip-sha> [--fetch <branch>] [--yes]"; }

case "$HOST_NAME" in
  idea01|idea03|idea04) EXPECT_STORE="${EXPECT_STORE:-$POOL_STORE}" ;;
  *) die "not a pool Pi ($HOST_NAME); never idea02, wizardly-hugle or Milkwise" ;;
esac
cd "$ENGINE_DIR"
store_now() { tr -d '[:space:]' < store-identity/store-url.txt; }
check_store() { [ "$(store_now)" = "$EXPECT_STORE" ] || die "$1: store-url.txt is $(store_now), expected $EXPECT_STORE"; }

# 1. Guards (read-only)
check_store "before deploy"
mods="$(git status --porcelain --untracked-files=no | awk '{print $2}')"
for f in $mods; do
  case " $KEEP " in *" $f "*) continue ;; esac
  case "$f" in store-identity/*) continue ;; esac
  die "unexpected tracked local modification: $f"
done
echo "HOST $HOST_NAME HEAD $(git rev-parse --short HEAD) STORE $(store_now) local mods: $(echo $mods)"
[ -n "$YES" ] || { echo "DRY RUN: would save $KEEP store-identity/*, checkout $TIP, restore, verify, build, pm2 restart engine"; exit 0; }

# 2. Save
BK="$BACKUP_ROOT/engine-deploy-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BK"
cp -a $KEEP store-identity "$BK/"
git rev-parse HEAD > "$BK/HEAD"
echo "saved to $BK: $KEEP $(cd store-identity && ls -A | sed 's|^|store-identity/|' | xargs)"

# 3. Discard (tracked local edits of the kept files only), 4. check out
[ -n "$BRANCH" ] && git fetch -q origin "$BRANCH"
git cat-file -e "$TIP^{commit}" 2>/dev/null || die "tip $TIP not present (use --fetch <branch>)"
git checkout -q -- $KEEP store-identity
git checkout -q --detach "$TIP"

# 5. Restore every saved file (including untracked ones), 6. verify
cp -a "$BK/config.yaml" "$BK/pm2.config.cjs" .
cp -a "$BK/store-identity/." store-identity/
for f in $KEEP $(cd "$BK" && find store-identity -type f); do
  cmp -s "$f" "$BK/$f" || die "$f differs from the saved copy after checkout (backup: $BK)"
done
check_store "after checkout"
echo "restored: config.yaml sha $(sha256sum config.yaml | cut -c1-16), store $(store_now)"

# 7. Build, verify again, restart
pnpm install --frozen-lockfile
pnpm build
check_store "before pm2 restart"
pm2 restart engine --update-env
echo "DEPLOYED $HOST_NAME HEAD $(git rev-parse --short HEAD) store $(store_now) backup $BK"
