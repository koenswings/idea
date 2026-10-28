#!/usr/bin/env bash
# teardown.sh <pi> [--yes]   (idea#107)
# Reverse a deploy on ONE review/spare Pi, from the box. JSON result on stdout.
# Restores merged main in the locked nested layout:
#   Engine  /home/pi/idea/agents/agent-engine-dev   via deploy-engine-remote.sh (keeps config + store identity)
#   Console /home/pi/idea/agents/agent-console-dev  checkout main + build-console-pi.sh
#   App     /home/pi/idea/agents/agent-app-dev/<repo> when the deploy was an app-disk (repo app-*)
# then runs the post-check (Engine online under pi's pm2, Console 200, live instances answer),
# writes version "engine main@<sha>, console main@<sha>" and marks the Pi idle:
# status idle, pr/branch/repo/claim null (update-fleet-state.sh --null, audited).
# The golden Pi is never torn down (update-golden.sh moves it to main). Same refusals as deploy.sh.
# Without --yes: dry run. Idempotent: an idle Pi already on main only gets re-checked.
# Exit: 0 ok · 1 refused/failed · 2 usage.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/fleet-lib.sh"
YES=0; ARGS=()
for a in "$@"; do case "$a" in --yes) YES=1 ;; -h|--help) fl_usage 13 ;; *) ARGS+=("$a") ;; esac; done
[ ${#ARGS[@]} -eq 1 ] || fl_usage 13
PI="${ARGS[0]}"
fl_paused && fl_die "fleet changes are paused ($HEALTH_DIR/PAUSED or HOLD exists)"
fl_guard_pi "$PI" review
HOST="$(fl_host "$PI")"; REPO="$(fl_get "$PI" repo)"
ESHA="$(fl_remote_sha koenswings/agent-engine-dev main)"; CSHA="$(fl_remote_sha koenswings/agent-console-dev main)"
[ -n "$ESHA" ] && [ -n "$CSHA" ] || fl_die "cannot resolve main of agent-engine-dev / agent-console-dev" resolve
fl_step resolve true "engine main=$ESHA console main=$CSHA"
EXTRA="$(jq -nc --arg pi "$PI" --arg e "$ESHA" --arg c "$CSHA" '{pi:$pi,engine_main:$e,console_main:$c}')"
[ $YES = 1 ] || fl_finish 0 true "dry run: would restore $PI to engine main@$ESHA, console main@$CSHA${REPO:+ and $REPO main}; add --yes" "$EXTRA"

fl_temp_ok "$HOST" || fl_finish 1 false "$PI above 75 C; retry once below 65 C" "$EXTRA"
fl_set "$PI" claim "$BOT_NAME teardown" || fl_die "could not claim $PI in fleet-state" claim
fl_engine_deploy "$HOST" main "$ESHA" || fl_finish 1 false "engine restore failed on $PI; left claimed" "$EXTRA"
fl_checkout_remote "$HOST" "$CONSOLE_DIR" koenswings/agent-console-dev main console || fl_finish 1 false "console restore failed on $PI; left claimed" "$EXTRA"
if [[ "${REPO##*/}" == app-* ]]; then
  fl_checkout_remote "$HOST" "$APP_DIR/${REPO##*/}" "$REPO" main || fl_finish 1 false "app restore failed on $PI; left claimed" "$EXTRA"
fi
sleep "${POST_WAIT}"
fl_post_check "$HOST" "$(fl_get "$PI" console_port)" || fl_finish 1 false "restored main, but the post-check failed on $PI; left claimed" "$EXTRA"
fl_set "$PI" version "engine main@$ESHA, console main@$CSHA"
for f in pr branch repo claim; do fl_set --null "$PI" "$f"; done
fl_set "$PI" status idle; fl_set "$PI" idle_since "$(date -u +%FT%TZ)"
fl_step state true "$PI idle, pr/branch/repo/claim null"
fl_finish 0 true "$PI back on main and idle" "$EXTRA"
