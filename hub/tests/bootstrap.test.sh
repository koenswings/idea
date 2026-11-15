#!/usr/bin/env bash
# shellcheck disable=SC2015  # pass() always returns 0, so "A && pass || fail" is safe here
# Tests for hub/bootstrap.sh (idea#487). Box only: plan mode, --stage into scratch HOME/root,
# refusals. Stub systemctl/loginctl/crontab/sudo record any call; none may be called by
# plan or stage. Never touches a Pi, the box's own user session, crontab or /etc.
set -u
HUB=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
B=$HUB/bootstrap.sh
T=$(mktemp -d "${TMPDIR:-/tmp}/hub-bootstrap-test.XXXXXX")
BIN=$T/bin; mkdir -p "$BIN"
PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "PASS $*"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL $*"; }
for c in systemctl loginctl crontab sudo; do
  printf '#!/bin/sh\necho "%s $*" >> "%s/calls"\nexit 0\n' "$c" "$T" > "$BIN/$c"; chmod 755 "$BIN/$c"
done
export PATH=$BIN:$PATH
repo_snap() { (cd "$HUB/.." && git status --porcelain=v1 --untracked-files=all -- hub; find hub -type f -newer "$T/stamp" 2>/dev/null); }
touch "$T/stamp"; sleep 1

# 1. Plan: read-only, lists the steps and the capture blocker.
R0=$(repo_snap); OUT=$("$B" 2>&1); RC=$?
[ $RC = 0 ] && grep -q "PLAN only" <<<"$OUT" && grep -q "BLOCKER for --apply: not captured yet: host/boot.sh host/caddy/Caddyfile" <<<"$OUT" && pass "plan: steps + capture blocker" || { fail "plan (rc=$RC)"; echo "$OUT"; }
[ ! -e "$T/calls" ] && pass "plan: no systemctl/loginctl/crontab/sudo calls" || { fail "plan made calls"; cat "$T/calls"; }
[ "$R0" = "$(repo_snap)" ] && pass "plan: repo unchanged" || fail "plan: repo unchanged"
"$B" --dry-run >/dev/null 2>&1 && pass "--dry-run = plan" || fail "--dry-run"

# 2. Stage into scratch HOME + root: every service's files, host plan only, no calls.
SH=$T/home/pi; SR=$T/root
OUT=$("$B" --stage --home "$SH" --root "$SR" 2>&1); RC=$?
[ $RC = 0 ] && pass "stage: rc 0" || { fail "stage (rc=$RC)"; echo "$OUT"; }
for f in kit-watch/kit-watch.py kit-watch/mail-watch.py .config/systemd/user/kit-watch.timer .config/systemd/user/kit-watch.service \
         tg-relay/tg_relay.py .config/systemd/user/tg-relay.service .config/systemd/user/graphify-serve.service; do
  [ -f "$SH/$f" ] || { fail "stage: missing $f"; continue; }
done; pass "stage: service files in scratch HOME"
cmp -s "$SH/.config/systemd/user/kit-watch.timer" "$HUB/services/kit-watch/kit-watch.timer" && pass "stage: units = repo" || fail "stage: units = repo"
[ "$(stat -c %a "$SH/.config/kit-watch/env")" = 600 ] && [ "$(stat -c %a "$SH/.config/tg-relay/env")" = 600 ] && pass "stage: env files mode 600" || fail "stage: env modes"
grep -q "SKIP /usr/local/bin/boot.sh" <<<"$OUT" && grep -q "plan only: nothing was written" <<<"$OUT" && pass "stage: host step is a plan, placeholders skipped" || { fail "stage host plan"; echo "$OUT"; }
[ -z "$(find "$SR" -type f)" ] && pass "stage: nothing written under the scratch root" || fail "stage: files under scratch root"
[ ! -e "$T/calls" ] && pass "stage: no systemctl/loginctl/crontab/sudo calls" || { fail "stage made calls"; cat "$T/calls"; }
# Re-run keeps env + state byte for byte.
printf 'KIT_WEBHOOK_URL=https://x.invalid\nKIT_WEBHOOK_KEY=k\nAGENTMAIL_API_KEY=a\n' > "$SH/.config/kit-watch/env"
echo '{"devices":{}}' > "$SH/kit-watch/state.json"; printf 'TELEGRAM_BOT_TOKEN=t\n' > "$SH/.config/tg-relay/env"
S1=$(cd "$SH" && sha256sum .config/kit-watch/env .config/tg-relay/env kit-watch/state.json)
"$B" --stage --home "$SH" --root "$SR" >/dev/null 2>&1 && [ "$S1" = "$(cd "$SH" && sha256sum .config/kit-watch/env .config/tg-relay/env kit-watch/state.json)" ] \
  && pass "stage re-run: env + state unchanged" || fail "stage re-run: env + state unchanged"

# 3. Stage refuses real or unsafe targets.
ln -s "$T/home" "$T/link"
for bad in "/ $SR" "$HOME $SR" "rel $SR" "$T/link $SR" "$SH /etc"; do
  # shellcheck disable=SC2086
  set -- $bad; "$B" --stage --home "$1" --root "$2" >/dev/null 2>&1; rc=$?
  [ $rc = 2 ] && pass "stage refuses --home $1 --root $2" || fail "stage refuses --home $1 --root $2 (rc=$rc)"
done
"$B" --stage --home "$SH" >/dev/null 2>&1; [ $? = 2 ] && pass "stage needs both paths" || fail "stage needs both paths"

# 4. Apply refuses before changing anything when not run as pi on idea (box user is not pi).
if [ "$(id -un)" != pi ]; then
  OUT=$("$B" --apply 2>&1); RC=$?
  [ $RC = 1 ] && grep -q "REFUSE: run as pi" <<<"$OUT" && [ ! -e "$T/calls" ] && pass "apply: refuses as non-pi, no calls" || { fail "apply refuse (rc=$RC)"; echo "$OUT"; }
fi
"$B" --apply --home "$SH" >/dev/null 2>&1; [ $? = 2 ] && pass "apply rejects --home" || fail "apply rejects --home"
"$B" --bogus >/dev/null 2>&1; [ $? = 2 ] && pass "unknown option exits 2" || fail "unknown option exits 2"

echo "scratch: $T"
echo "passed $PASS, failed $FAIL"
[ $FAIL = 0 ]
