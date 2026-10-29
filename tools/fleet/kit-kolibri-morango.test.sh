#!/usr/bin/env bash
# Unit + mock end-to-end tests for kit-kolibri-morango.sh (no network). Mock also covers a failing stopInstance -> 14.
set -u; D="$(cd "$(dirname "$0")" && pwd)"; T="$D/kit-kolibri-morango-test"; S="$D/kit-kolibri-morango.sh"; F=0; P=0
ok(){ if [ "$2" = "$3" ]; then P=$((P+1)); else F=$((F+1)); echo "FAIL $1: got '$2' want '$3'"; fi; }
KKM_LIB=1 source "$S"
C8="$(cat "$T/compose-pr7.yaml")"
ok expected "$(expected_id sunny-robin 62650)" idea-sunny-robin-62650
ok cs-none "$(printf '%s' "$C8" | compose_state)" none
P8="$(printf '%s\n' "$C8" | patch_compose)"
ok cs-template "$(printf '%s' "$P8" | compose_state)" template
ok patch-line "$(printf '%s\n' "$P8" | grep -c '^      - MORANGO_SYSTEM_ID=idea-\${hostname}-\${port}$')" 1
ok patch-after-listen "$(printf '%s\n' "$P8" | grep -A2 KOLIBRI_LISTEN_PORT | tail -1 | sed 's/^ *//')" '- MORANGO_SYSTEM_ID=idea-${hostname}-${port}'
ok patch-only-adds "$(diff <(printf '%s\n' "$C8") <(printf '%s\n' "$P8") | grep -c '^>')" 2
ok patch-matches-pr8 "$(diff <(grep -v '^ *#' "$T/compose-pr8.yaml") <(printf '%s\n' "$P8" | grep -v '^ *#') >/dev/null && echo same)" same
printf '%s\n' "$C8" | grep -v KOLIBRI_LISTEN_PORT | patch_compose >/dev/null; ok patch-unsupported $? 13
ok cs-literal "$(printf '      - MORANGO_SYSTEM_ID=idea-happy-zebra-62561\n' | compose_state)" literal:idea-happy-zebra-62561
ok cs-map "$(printf '      MORANGO_SYSTEM_ID: "idea-x-1"\n' | compose_state)" literal:idea-x-1
ok cs-multi "$(printf '  - MORANGO_SYSTEM_ID=a\n  - MORANGO_SYSTEM_ID=b\n' | compose_state)" multi
E=idea-h-1
ok d1 "$(decide none '' $E)" PATCH_RESTART
ok d2 "$(decide none $E $E)" PATCH_ONLY
ok d3 "$(decide template $E $E)" SKIP
ok d4 "$(decide template '' $E)" RESTART
ok d5 "$(decide literal:$E $E $E)" SKIP
ok d6 "$(decide literal:$E '' $E)" RESTART
ok d7 "$(decide literal:idea-h-2 '' $E)" CONFLICT
ok d8 "$(decide multi '' $E)" CONFLICT
printf 'a\nb\n' | ids_unique >/dev/null; ok uniq-ok $? 0
printf 'a\na\n' | ids_unique >/dev/null; ok uniq-dup $? 1
printf 'a\n-\n' | ids_unique >/dev/null; ok uniq-missing $? 1
is_kolibri_app kolibri; ok app-kolibri $? 0
is_kolibri_app kolibri-8a1b2c3; ok app-kolibri-ref $? 0
is_kolibri_app kolibri-channel-builder; ok app-builder $? 1
is_kolibri_app nextcloud; ok app-nc $? 1
# --- mock end-to-end (fake Pi in a temp dir) ---
bash "$T/mock-e2e.sh" "$S"; ok mock-e2e $? 0
echo "PASS $P FAIL $F"; [ $F = 0 ]
