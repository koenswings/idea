#!/usr/bin/env bash
# deploy-engine-pi.sh — option-2 Engine deploy on ONE pool Pi: keep the Pi's local config
# AND store identity across a git checkout of a new Engine commit.
#
#   ssh <pi> 'bash -s -- <tip-sha> [--fetch <branch>] [--dry-run|--yes]' < tools/fleet/deploy-engine-pi.sh
#
# Steps: guard host + store -> save config.yaml, pm2.config.cjs and every store-identity/ file
# -> discard those local edits -> git checkout --detach <tip> -> restore the saved files
# -> verify they are byte-identical and store-url.txt is still the expected store
# -> pnpm install + build -> DHCP vendor class (idea#284) -> ./install-root-helpers (flash/app-data/
# erase helpers + sudoers, then sha256 vs the repo and visudo -c) -> verify again -> pm2 restart engine + pm2 save.
# Any failed check aborts BEFORE pm2 restart (exit 3); the running Engine keeps its old store.
# ALWAYS kept, whatever git status says (skip-worktree files included): config.yaml, pm2.config.cjs,
# the whole store-identity/ dir and ~/.idea-local; backed up first, restored byte-for-byte, sha256-checked.
# --dry-run (or no --yes): read-only; prints exactly what it would save, restore and install.
#
# Why: the repo's tracked store-identity/ files hold the defaults (idea02's production store).
# A plain discard + checkout puts those back, and a restarted pool Engine then joins idea02's
# store (idea04, 2026-10-14). See docs/ops/engine-deploy-pool-pi.md.
#
# Env overrides (tests): ENGINE_DIR, HOST_NAME, EXPECT_STORE, BACKUP_ROOT, IDEA_LOCAL, SBIN, POST_RESTART_WAIT.
set -euo pipefail

ENGINE_DIR="${ENGINE_DIR:-/home/pi/idea/agents/agent-engine-dev}"
HOST_NAME="${HOST_NAME:-$(hostname)}"
POOL_STORE="automerge:2VroEUvDkmYsDAwE5oG9YeFNadWH"   # idea01/03/04 since 2026-10-13 (fleet-state.json)
KIT_STORE="automerge:3Vvvigx8bKcuwKALqMVz85GhDqrk"   # ONE shared kit store (sunny-robin, happy-zebra, kind-panda; reset 2026-10-18)
BACKUP_ROOT="${BACKUP_ROOT:-/home/pi/quarantine}"
KEEP="config.yaml pm2.config.cjs"                    # plus every file in store-identity/
IDEA_LOCAL="${IDEA_LOCAL:-$HOME/.idea-local}"        # kit local override, outside the repo; kept too
DEFAULT_STORE_PREFIX="automerge:4GQm"                # repo default (idea02 production): never restored to
HELPERS="idea-flash-card idea-app-data idea-erase-disk"  # script/build_image_assets -> $SBIN
SBIN="${SBIN:-/usr/local/sbin}"

die() { echo "ABORT: $*" >&2; exit 3; }
TIP=""; BRANCH=""; YES=""; DRY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) YES=1 ;;
    --dry-run|-n) YES="" ; DRY=1 ;;
    --fetch) BRANCH="${2:?--fetch needs a branch}"; shift ;;
    -*) die "unknown option $1" ;;
    *) TIP="$1" ;;
  esac; shift
done
[ -n "$TIP" ] || { sed -n '2,20p' "$0" 2>/dev/null; die "usage: <tip-sha> [--fetch <branch>] [--dry-run|--yes]"; }
[ -n "$DRY" ] && YES=""

case "$HOST_NAME" in
  idea01|idea03|idea04) EXPECT_STORE="${EXPECT_STORE:-$POOL_STORE}" ;;
  sunny-robin|happy-zebra|kind-panda) EXPECT_STORE="${EXPECT_STORE:-$KIT_STORE}" ;;  # only after Steve's GO naming the Engine
  *) die "not a pool Pi or kit Engine ($HOST_NAME); never idea02, wizardly-hugle or Milkwise" ;;
esac
cd "$ENGINE_DIR"
store_now() { tr -d '[:space:]' < store-identity/store-url.txt; }
# Every kept file, relative to ENGINE_DIR (store-identity/ listed from disk, not from git).
kept_files() { echo $KEEP; find store-identity -type f | sort; }
sums() { for f in $(kept_files); do sha256sum "$f"; done; [ -f "$IDEA_LOCAL" ] && sha256sum "$IDEA_LOCAL"; true; }
check_store() { [ "$(store_now)" = "$EXPECT_STORE" ] || die "$1: store-url.txt is $(store_now), expected $EXPECT_STORE"; }

# 1. Guards (read-only)
check_store "before deploy"
mods="$(git status --porcelain --untracked-files=no | awk '{print $2}')"
for f in $mods; do
  case " $KEEP " in *" $f "*) continue ;; esac
  case "$f" in store-identity/*) continue ;; esac
  die "unexpected tracked local modification: $f"
done
case "$(store_now)" in "$DEFAULT_STORE_PREFIX"*) die "store-url.txt is the repo default ($(store_now)); refusing";; esac
echo "HOST $HOST_NAME HEAD $(git rev-parse --short HEAD) STORE $(store_now) local mods: $(echo $mods)"
if [ -z "$YES" ]; then
  echo "DRY RUN (nothing changed). Target $TIP$([ -n "$BRANCH" ] && echo " (would fetch origin $BRANCH first)")"
  git cat-file -e "$TIP^{commit}" 2>/dev/null && echo "  tip present: $(git log -1 --format='%h %s' "$TIP")" || echo "  tip NOT present locally (needs --fetch <branch>)"
  echo "  would save to $BACKUP_ROOT/engine-deploy-<ts>/ and restore byte-for-byte (sha256):"
  sums | sed 's/^/    /'
  [ -f "$IDEA_LOCAL" ] || echo "    ($IDEA_LOCAL not present: nothing to keep)"
  echo "  would run: git checkout --detach $TIP; pnpm install --frozen-lockfile; pnpm build; DHCP vendor class"
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
verify_kept() {  # byte-for-byte against the backup, then sha256 against SHA256SUMS
  for f in $KEEP $(cd "$BK" && find store-identity -type f); do
    cmp -s "$f" "$BK/$f" || die "$1: $f differs from the saved copy (backup: $BK)"
  done
  if [ -f "$BK/idea-local" ]; then cmp -s "$IDEA_LOCAL" "$BK/idea-local" || die "$1: $IDEA_LOCAL changed (backup: $BK)"; fi
  sha256sum --quiet -c "$BK/SHA256SUMS" || die "$1: sha256 mismatch on kept files (backup: $BK)"
}
verify_kept "after checkout"
check_store "after checkout"
echo "restored: config.yaml sha $(sha256sum config.yaml | cut -c1-16), store $(store_now)"

# 7. Build, verify again, restart
pnpm install --frozen-lockfile
pnpm build
# DHCP option 60 "idea-engine" (idea#209 D8, idea#284): same step as the Engine's
# installRootHelpers. Idempotent; never restarts NetworkManager or touches a link.
# A failure only warns: check-fleet-health.sh reports a missing drop-in.
VC_ASSET=script/build_image_assets/idea-dhcp-vendor-class
VC_HELPER=/usr/local/sbin/idea-dhcp-vendor-class
if [ -f "$VC_ASSET" ]; then
  if sudo -n install -o root -g root -m 0755 "$VC_ASSET" "$VC_HELPER" && sudo -n "$VC_HELPER"; then
    if systemctl is-active --quiet NetworkManager; then sudo -n nmcli general reload conf || echo "WARN: nmcli general reload conf failed" >&2; fi
  else
    echo "WARN: DHCP vendor class not applied (idea#284); check-fleet-health.sh will report it" >&2
  fi
else
  echo "DHCP vendor class: $VC_ASSET not in this Engine commit, skipped"
fi
# Root helpers (flash helper, app-data, erase-disk, sudoers): no Engine runs new code with an old helper.
# install-root-helpers calls sudo itself (passwordless sudo, as pi) and runs visudo -cf on the sudoers files.
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
verify_kept "before pm2 restart"
check_store "before pm2 restart"
pm2 restart engine --update-env
pm2 save
sleep "${POST_RESTART_WAIT:-5}"
check_store "after pm2 restart"
echo "DEPLOYED $HOST_NAME HEAD $(git rev-parse --short HEAD) store $(store_now) backup $BK"
