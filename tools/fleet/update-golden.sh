#!/usr/bin/env bash
# update-golden.sh <component> <version> [--yes] [--ignore-fleet-hold]   (idea#107, dedicated golden model idea#118)
# Deploy merged main of engine|console onto the ONE Pi with role: golden, from the box.
#   <version>  a commit SHA on main, or "main" for the current tip. A SHA that is not on main is refused.
# Engine via deploy-engine-remote.sh, Console via checkout + build-console-pi.sh; then the post-check
# (Engine online under pi's pm2, Console 200, every live instance incl. MilkWise answers), then the
# component's part of .version ("engine main@<sha>, console main@<sha>") is updated with
# update-fleet-state.sh. Status stays idle. JSON result on stdout.
# Refuses when no Pi or more than one Pi has role golden, and for FLEET_DENY / the wh host.
# Without --yes: dry run. Idempotent: a golden Pi already on <version> is only re-checked.
# Exit: 0 ok · 1 refused/failed · 2 usage.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/fleet-lib.sh"
YES=0; ARGS=()
for a in "$@"; do case "$a" in --yes) YES=1 ;; --ignore-fleet-hold) IGNORE_FLEET_HOLD=1 ;; -h|--help) fl_usage 12 ;; *) ARGS+=("$a") ;; esac; done
[ ${#ARGS[@]} -eq 2 ] || fl_usage 12
COMP="${ARGS[0]}"; VER="${ARGS[1]}"
case "$COMP" in engine) SLUG=koenswings/agent-engine-dev ;; console) SLUG=koenswings/agent-console-dev ;;
  *) fl_die "component must be engine or console" usage 2 ;; esac
mapfile -t GOLD < <(jq -r 'to_entries[] | select((.key|startswith("_")|not) and (.value|type=="object") and .value.role=="golden") | .key' "$STATE_FILE")
[ ${#GOLD[@]} -eq 1 ] || fl_die "need exactly one Pi with role golden, found ${#GOLD[@]} (${GOLD[*]:-none}); see set-golden-pi.sh"
PI="${GOLD[0]}"
fl_fleet_hold_check
fl_guard_pi "$PI" golden
HOST="$(fl_host "$PI")"
TIP="$(fl_remote_sha "$SLUG" main)"; [ -n "$TIP" ] || fl_die "cannot resolve $SLUG main" resolve
if [ "$VER" = main ]; then SHA="$TIP"; else
  [[ "$VER" =~ ^[0-9a-f]{7,40}$ ]] || fl_die "version must be a commit SHA or 'main'" usage 2
  # Must be on main: ask GitHub whether main contains it.
  st="$(gh api "repos/$SLUG/compare/$VER...main" --jq .status 2>/dev/null)"
  case "$st" in identical|ahead) ;; *) fl_die "$VER is not on $SLUG main (compare: ${st:-error})" resolve ;; esac
  SHA="$(gh api "repos/$SLUG/commits/$VER" --jq .sha 2>/dev/null)"; [ -n "$SHA" ] || fl_die "cannot resolve $VER" resolve
fi
fl_step resolve true "$SLUG main@$SHA"
EXTRA="$(jq -nc --arg pi "$PI" --arg c "$COMP" --arg s "$SHA" '{pi:$pi,component:$c,sha:$s}')"
[ $YES = 1 ] || fl_finish 0 true "dry run: would move golden $PI $COMP to main@$SHA; add --yes" "$EXTRA"

fl_temp_ok "$HOST" || fl_finish 1 false "$PI above 75 C; retry once below 65 C" "$EXTRA"
case "$COMP" in
  engine)  fl_engine_deploy "$HOST" main "$SHA" ;;
  console) fl_checkout_remote "$HOST" "$CONSOLE_DIR" "$SLUG" "$SHA" console ;;
esac || fl_finish 1 false "golden $COMP deploy failed on $PI; version not updated" "$EXTRA"
sleep "${POST_WAIT}"
fl_post_check "$HOST" "$(fl_get "$PI" console_port)" || fl_finish 1 false "golden deployed but post-check failed on $PI; version not updated" "$EXTRA"
OLD="$(fl_get "$PI" version)"
E="$(sed -n 's/.*engine [^@,]*@\([0-9a-f]\{7,40\}\).*/\1/p' <<<"$OLD")"; C="$(sed -n 's/.*console [^@,]*@\([0-9a-f]\{7,40\}\).*/\1/p' <<<"$OLD")"
[ "$COMP" = engine ] && E="$SHA"; [ "$COMP" = console ] && C="$SHA"
NEW="engine main@${E:-unknown}, console main@${C:-unknown}"
fl_set "$PI" version "$NEW" || fl_die "could not write version" state
fl_step state true "$PI version = $NEW"
fl_finish 0 true "golden $PI $COMP on main@$SHA" "$EXTRA"
