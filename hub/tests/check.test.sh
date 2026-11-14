#!/usr/bin/env bash
# shellcheck disable=SC2015  # pass() always returns 0, so "A && pass || fail" is safe here
# Tests for hub/check.sh (idea#483). Runs on the box: builds a fake deployed tree with
# hub/services/telegram-relay/install.sh (fake HOME, stub systemctl), then checks that
# check.sh reports no drift, reports each deliberate difference, and clears when undone.
# Never touches a Pi or a real ~/.config file.
set -u
HUB=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CHECK=$HUB/check.sh
T=$(mktemp -d "${TMPDIR:-/tmp}/hub-check-test.XXXXXX")
H=/home/pi                      # home as the hub sees it
FH=$T$H                         # the same home inside the fake tree
BIN=$T/bin; STATE=$T/unit-state
mkdir -p "$FH" "$BIN" "$STATE"
PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "PASS $*"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL $*"; }

# Stub systemctl: install.sh calls are accepted; is-enabled/is-active answer from $STATE.
cat > "$BIN/systemctl" <<STUB
#!/bin/sh
case "\$2" in
  is-enabled) cat "$STATE/enabled" 2>/dev/null || echo disabled; [ "\$(cat "$STATE/enabled" 2>/dev/null)" = enabled ] ;;
  is-active)  cat "$STATE/active" 2>/dev/null || echo inactive; [ "\$(cat "$STATE/active" 2>/dev/null)" = active ] ;;
  *) exit 0 ;;
esac
STUB
chmod 755 "$BIN/systemctl"
echo enabled > "$STATE/enabled"; echo active > "$STATE/active"
export HUB_CHECK_SYSTEMCTL=$BIN/systemctl

# Build the matching fake tree the same way the hub gets it (fake kit-watch env first).
mkdir -p "$FH/.config/kit-watch"; printf 'KIT_WEBHOOK_URL=http://hook.invalid\nKIT_WEBHOOK_KEY=fake\n' > "$FH/.config/kit-watch/env"
HOME=$FH PATH=$BIN:$PATH sh "$HUB/services/telegram-relay/install.sh" >/dev/null
SECRET=fake-token-$RANDOM$RANDOM
printf 'TELEGRAM_BOT_TOKEN=%s\nKIT_WEBHOOK_URL=http://hook.invalid/%s\nKIT_WEBHOOK_KEY=%s\n' "$SECRET" "$SECRET" "$SECRET" > "$FH/.config/tg-relay/env"
chmod 600 "$FH/.config/tg-relay/env"
echo '{}' > "$FH/tg-relay/state.json"; : > "$FH/tg-relay/relay.log"

OUT=""; RC=0
run() { OUT=$("$CHECK" --root "$T" --home "$H" "$@" 2>&1); RC=$?; }
expect_drift() {  # LABEL PATTERN
  run
  if [ $RC = 1 ] && grep -q "^DRIFT .*$2" <<<"$OUT"; then pass "$1"; else fail "$1 (rc=$RC, want DRIFT matching '$2')"; echo "$OUT"; fi
}
no_secret() {
  if grep -q "$SECRET" <<<"$OUT"; then fail "$1: secret value printed"; else pass "$1: no secret value in output"; fi
}
snapshot() { (cd "$T" && find . -printf '%p %m %s %T@ %l\n' | LC_ALL=C sort && find . -type f -exec sha256sum {} + | LC_ALL=C sort); }

# 1. Matching tree: no drift (and the run changes nothing).
B=$(snapshot)
run; [ $RC = 0 ] && grep -q '^no drift$' <<<"$OUT" && pass "matching tree: no drift" || { fail "matching tree: no drift (rc=$RC)"; echo "$OUT"; }
no_secret "matching tree"
[ "$B" = "$(snapshot)" ] && pass "read-only: tree unchanged after run" || fail "read-only: tree changed after run"

clean() { run; if [ $RC = 0 ] && grep -q '^no drift$' <<<"$OUT"; then pass "$1"; else fail "$1 (rc=$RC)"; echo "$OUT"; fi; }

# 2. Code differs, then undone.
cp -p "$FH/tg-relay/tg_relay.py" "$T/tg_relay.py.orig"
echo "# local hot-fix" >> "$FH/tg-relay/tg_relay.py"
expect_drift "code change reported" "differs from repo: $H/tg-relay/tg_relay.py"
cp -p "$T/tg_relay.py.orig" "$FH/tg-relay/tg_relay.py"
clean "code change undone: no drift"

# 3. Unit file differs, then undone.
U=$FH/.config/systemd/user/tg-relay.service; cp -p "$U" "$T/unit.orig"
sed -i 's/RestartSec=10/RestartSec=30/' "$U"
expect_drift "unit file change reported" "differs from repo: $H/.config/systemd/user/tg-relay.service"
cp -p "$T/unit.orig" "$U"; clean "unit file change undone: no drift"

# 4. Unit disabled / inactive, then back.
echo disabled > "$STATE/enabled"; expect_drift "unit disabled reported" "is-enabled=disabled"
echo enabled > "$STATE/enabled"; echo failed > "$STATE/active"; expect_drift "unit not active reported" "is-active=failed"
echo active > "$STATE/active"; clean "unit state restored: no drift"

# 5. Env: extra key and missing key are reported by NAME only, never value.
E=$FH/.config/tg-relay/env; cp -p "$E" "$T/env.orig"
echo "EXTRA_THING=$SECRET" >> "$E"
expect_drift "extra env key reported by name" "env key not in services/telegram-relay/.env.example: EXTRA_THING"; no_secret "extra env key"
cp -p "$T/env.orig" "$E"; sed -i '/^KIT_WEBHOOK_KEY=/d' "$E"
expect_drift "missing env key reported by name" "env key missing: KIT_WEBHOOK_KEY"; no_secret "missing env key"
cp -p "$T/env.orig" "$E"
echo "TELEGRAM_API_BASE=http://x.invalid" >> "$E"; clean "optional env key (TELEGRAM_API_BASE) allowed"
cp -p "$T/env.orig" "$E"; clean "env undone: no drift"

# 6. Env mode loosened, then fixed.
chmod 644 "$E"; expect_drift "env mode reported" "mode 644 (want 600)"
chmod 600 "$E"; clean "env mode fixed: no drift"

# 7. Unexpected file next to the deployed code (the #407 kind of drift), then moved aside.
echo x > "$FH/tg-relay/tg_relay_new.py"
expect_drift "unexpected file reported" "unexpected file in $H/tg-relay: tg_relay_new.py"
mv "$FH/tg-relay/tg_relay_new.py" "$T/"; clean "unexpected file gone: no drift"

# 8. tg-send symlink broken, then restored.
L=$FH/.local/bin/tg-send; T0=$(readlink "$L"); ln -sfn /nowhere "$L"
expect_drift "tg-send link reported" "link $H/.local/bin/tg-send -> /nowhere"
ln -sfn "$T0" "$L"; clean "tg-send link restored: no drift"

# 9. Missing deployed file.
mv "$FH/tg-relay/tg-send" "$T/tg-send.aside"
expect_drift "missing file reported" "missing: $H/tg-relay/tg-send"
mv "$T/tg-send.aside" "$FH/tg-relay/tg-send"; clean "missing file restored: no drift"

# 10. Options.
"$CHECK" --bogus >/dev/null 2>&1; [ $? = 2 ] && pass "unknown option exits 2" || fail "unknown option exits 2"
"$CHECK" --service nope >/dev/null 2>&1; [ $? = 2 ] && pass "unknown service exits 2" || fail "unknown service exits 2"
[ "$("$CHECK" --list)" = telegram-relay ] && pass "--list" || fail "--list"
echo disabled > "$STATE/enabled"; run --no-state
[ $RC = 0 ] && grep -q '^skip' <<<"$OUT" && pass "--no-state skips unit state" || { fail "--no-state (rc=$RC)"; echo "$OUT"; }
echo enabled > "$STATE/enabled"
run --service telegram-relay; [ $RC = 0 ] && pass "--service telegram-relay" || fail "--service telegram-relay (rc=$RC)"

# Scratch is left under $TMPDIR (no rm -rf); it holds only fake values.
echo "scratch: $T"
echo "passed $PASS, failed $FAIL"
[ $FAIL = 0 ]
