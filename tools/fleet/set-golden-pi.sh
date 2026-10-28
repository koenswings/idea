#!/usr/bin/env bash
# set-golden-pi.sh [--yes] [--ignore-fleet-hold]   (idea#107, dedicated golden model idea#118)
# Keep exactly one golden Pi. If the current role: golden Pi answers ssh, nothing changes ("healthy").
# If there is none, or it is unreachable, designate the most recently idle Pi as golden:
#   candidates: role review|spare, status idle, no claim, not in FLEET_DENY, not the wh host, reachable;
#   "most recently idle" = newest idle_since (written by teardown.sh); Pis without it rank last, by name.
# The old golden Pi (if any) gets role "golden-unavailable" so it is never picked for review until Ops
# looks at it. The new one gets role golden (out of review allocation). Then run
#   update-golden.sh engine main --yes && update-golden.sh console main --yes
# to move it to merged main (printed in next_steps; not run here). JSON result on stdout.
# Without --yes: dry run. Exit: 0 ok/no change · 1 refused or no candidate · 2 usage.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/fleet-lib.sh"
YES=0
for a in "$@"; do case "$a" in --yes) YES=1 ;; --ignore-fleet-hold) IGNORE_FLEET_HOLD=1 ;; -h|--help) fl_usage 12 ;; *) fl_usage 12 ;; esac; done
fl_fleet_hold_check
mapfile -t GOLD < <(jq -r 'to_entries[] | select((.key|startswith("_")|not) and (.value|type=="object") and .value.role=="golden") | .key' "$STATE_FILE")
[ ${#GOLD[@]} -le 1 ] || fl_die "more than one Pi has role golden (${GOLD[*]}); fix fleet-state by hand"
OLD="${GOLD[0]:-}"
if [ -n "$OLD" ]; then
  if fl_ssh "$(fl_host "$OLD")" true >/dev/null 2>&1; then
    fl_step current_golden true "$OLD reachable"
    fl_finish 0 true "golden Pi $OLD is available; no change" "$(jq -nc --arg g "$OLD" '{golden:$g,changed:false}')"
  fi
  fl_step current_golden false "$OLD unreachable"
else fl_step current_golden false "no Pi has role golden"; fi
DENY_JSON="$(printf '%s\n' $FLEET_DENY | jq -R . | jq -sc .)"; DH_JSON="$(printf '%s\n' $DENY_HOSTS | jq -R . | jq -sc .)"
mapfile -t CANDS < <(jq -r --argjson deny "$DENY_JSON" --argjson dh "$DH_JSON" '
  [to_entries[] | select((.key|startswith("_")|not) and (.value|type=="object"))
   | select((.value.role // "review") as $r | $r=="review" or $r=="spare")
   | select(.value.status=="idle" and (.value.claim // null)==null)
   | select(.key as $k | $deny | index($k) | not)
   | select((.value.tailscale // .value.host // "") as $h | $dh | index($h) | not)]
  | (map(select(.value.idle_since != null)) | sort_by(.value.idle_since) | reverse)
    + (map(select(.value.idle_since == null)) | sort_by(.key)) | .[].key' "$STATE_FILE")
NEW=""
for c in "${CANDS[@]}"; do
  if fl_ssh "$(fl_host "$c")" true >/dev/null 2>&1; then NEW="$c"; break; fi
  fl_step "candidate $c" false "unreachable"
done
[ -n "$NEW" ] || fl_die "no idle, unclaimed, reachable review/spare Pi to make golden" select
fl_step select true "$NEW (idle_since $(fl_get "$NEW" idle_since))"
EXTRA="$(jq -nc --arg o "$OLD" --arg n "$NEW" '{old_golden:(if $o=="" then null else $o end),golden:$n,changed:true,next_steps:["update-golden.sh engine main --yes","update-golden.sh console main --yes"]}')"
[ $YES = 1 ] || fl_finish 0 true "dry run: would make $NEW golden${OLD:+ (old $OLD -> golden-unavailable)}; add --yes" "$EXTRA"
[ -n "$OLD" ] && { fl_set "$OLD" role golden-unavailable || fl_die "could not update $OLD" state; }
fl_set "$NEW" role golden || fl_die "could not update $NEW" state
fl_set "$NEW" status idle
fl_step state true "$NEW role golden${OLD:+, $OLD golden-unavailable}"
fl_finish 0 true "$NEW is now the golden Pi; run update-golden.sh to move it to main" "$EXTRA"
