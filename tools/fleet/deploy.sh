#!/usr/bin/env bash
# deploy.sh <pi> <component> <repo> <branch> [--yes] [--ignore-fleet-hold]   (idea#107)
# Full deploy of a review branch onto ONE review/spare Pi, from the box. JSON result on stdout.
#   component engine   : repo agent-engine-dev; reuses deploy-engine-remote.sh (keeps config.yaml,
#                        pm2.config.cjs and store-identity/, pi's pm2 restart + save, 75/65 C guard)
#   component console  : repo agent-console-dev; detached checkout + build-console-pi.sh (keeps the hide list)
#   component app-disk : repo app-*; detached checkout under /home/pi/idea/agents/agent-app-dev/<repo>
# Without --yes it is a dry run: guards + plan only, nothing on the Pi or in fleet-state changes.
# Refuses: unknown Pis, FLEET_DENY (idea02), the wh production host, role golden/production/kit-engine/
# fleet-pending, status hold/paused/kit/production, a claim by another bot, fleet PAUSED/HOLD, > 75 C.
# Never runs pnpm test:full (idea#105). Never uses sudo pm2.
# State: claim=$BOT_NAME, status=deployed, repo/branch/pr set via update-fleet-state.sh (audited).
# After the deploy: Engine online under pi's pm2, Console HTTP 200, every live instance answers (MilkWise).
# Idempotent: a Pi already on the branch tip is reported "already" and re-checked.
# Exit: 0 ok · 1 refused/failed · 2 usage.   Canonical layout: proposals/pi-checkout-layout.md
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/fleet-lib.sh"
YES=0; ARGS=()
for a in "$@"; do case "$a" in --yes) YES=1 ;; --ignore-fleet-hold) IGNORE_FLEET_HOLD=1 ;; -h|--help) fl_usage 15 ;; *) ARGS+=("$a") ;; esac; done
[ ${#ARGS[@]} -eq 4 ] || fl_usage 15
PI="${ARGS[0]}"; COMP="${ARGS[1]}"; REPO="${ARGS[2]}"; BRANCH="${ARGS[3]}"
SLUG="$REPO"; [[ "$SLUG" == */* ]] || SLUG="koenswings/$REPO"; NAME="${SLUG##*/}"
case "$COMP" in
  engine)   [ "$NAME" = agent-engine-dev ]  || fl_die "component engine needs repo agent-engine-dev, got $NAME" usage 2 ;;
  console)  [ "$NAME" = agent-console-dev ] || fl_die "component console needs repo agent-console-dev, got $NAME" usage 2 ;;
  app-disk) [[ "$NAME" == app-* ]]          || fl_die "component app-disk needs an app-* repo, got $NAME" usage 2 ;;
  *) fl_die "component must be engine, console or app-disk" usage 2 ;;
esac
fl_fleet_hold_check
fl_guard_pi "$PI" review
HOST="$(fl_host "$PI")"
SHA="$(fl_remote_sha "$SLUG" "$BRANCH")"; [ -n "$SHA" ] || fl_die "branch $BRANCH not found on $SLUG" resolve
fl_step resolve true "$SLUG $BRANCH = $SHA"
EXTRA="$(jq -nc --arg pi "$PI" --arg c "$COMP" --arg r "$SLUG" --arg b "$BRANCH" --arg s "$SHA" '{pi:$pi,component:$c,repo:$r,branch:$b,sha:$s}')"
[ $YES = 1 ] || fl_finish 0 true "dry run: would deploy $COMP $SLUG@$BRANCH ($SHA) to $PI; add --yes" "$EXTRA"

fl_temp_ok "$HOST" || fl_finish 1 false "$PI above 75 C; retry once below 65 C" "$EXTRA"
fl_set "$PI" claim "$BOT_NAME deploy $COMP $BRANCH" || fl_die "could not claim $PI in fleet-state" claim
fl_set "$PI" status deployed; fl_set "$PI" repo "$SLUG"; fl_set "$PI" branch "$BRANCH"
fl_set "$PI" pr "$NAME@$BRANCH"
fl_step claim true "$PI claimed by $BOT_NAME"
case "$COMP" in
  engine)   fl_engine_deploy "$HOST" "$BRANCH" "$SHA" ;;
  console)  fl_checkout_remote "$HOST" "$CONSOLE_DIR" "$SLUG" "$BRANCH" console ;;
  app-disk) fl_checkout_remote "$HOST" "$APP_DIR/$NAME" "$SLUG" "$BRANCH" ;;
esac || fl_finish 1 false "deploy step failed on $PI; Pi stays claimed for inspection (teardown.sh restores main)" "$EXTRA"
sleep "${POST_WAIT}"
fl_post_check "$HOST" "$(fl_get "$PI" console_port)" || fl_finish 1 false "deployed, but the post-check failed on $PI" "$EXTRA"
fl_finish 0 true "deployed $COMP $SLUG@$BRANCH ($SHA) to $PI" "$EXTRA"
