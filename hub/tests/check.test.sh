#!/usr/bin/env bash
# shellcheck disable=SC2015  # pass() always returns 0, so "A && pass || fail" is safe here
# Tests for hub/check.sh (idea#483). Runs on the box: builds a fake deployed tree with
# hub/services/telegram-relay/install.sh (fake HOME, stub systemctl), then checks that
# check.sh reports no drift, reports each deliberate difference, and clears when undone.
# Never touches a Pi or a real ~/.config file.
set -u
HUB=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/hub-check-test.XXXXXX")
# Run against a copy of hub/ whose host placeholders are replaced by fake "captured" files,
# so a fully matching tree is possible; section 13 also checks the real repo's placeholders.
cp -a "$HUB/." "$T/hubcopy/" 2>/dev/null || { mkdir -p "$T/hubcopy" && cp -a "$HUB/." "$T/hubcopy/"; }
printf '#!/bin/sh\necho captured boot\n' > "$T/hubcopy/host/boot.sh"
printf ':80 {\n  respond "captured"\n}\n' > "$T/hubcopy/host/caddy/Caddyfile"
CHECK=$T/hubcopy/check.sh
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
# Stub crontab (-l reads $STATE/crontab; anything else writes it) and loginctl (linger from $STATE/linger).
cat > "$BIN/crontab" <<STUB
#!/bin/sh
if [ "\$1" = -l ]; then cat "$STATE/crontab" 2>/dev/null; else cat "\$1" > "$STATE/crontab"; fi
STUB
cat > "$BIN/loginctl" <<STUB
#!/bin/sh
cat "$STATE/linger" 2>/dev/null || echo no
STUB
chmod 755 "$BIN/crontab" "$BIN/loginctl"
# Root crontab: the stub reads $STATE/crontab.root for "-u root". Pi crontab = cron.pi (comments only).
cat > "$BIN/crontab" <<STUB
#!/bin/sh
f=$STATE/crontab; [ "\$*" = "-l -u root" ] && f=$STATE/crontab.root
if [ "\$1" = -l ]; then cat "\$f" 2>/dev/null; else cat "\$1" > "$STATE/crontab"; fi
STUB
echo yes > "$STATE/linger"; cp "$HUB/host/cron.pi" "$STATE/crontab"; grep -v '^#' "$HUB/host/cron.root" > "$STATE/crontab.root"
export HUB_CHECK_CRONTAB=$BIN/crontab HUB_CHECK_LOGINCTL=$BIN/loginctl HUB_CHECK_SUDO=""
mkdir -p "$T/usr/local/bin" "$T/etc/caddy"
cp "$T/hubcopy/host/boot.sh" "$T/usr/local/bin/boot.sh"; cp "$T/hubcopy/host/caddy/Caddyfile" "$T/etc/caddy/Caddyfile"

# Build the matching fake tree the same way the hub gets it (fake kit-watch env first).
mkdir -p "$FH/.config/kit-watch"; printf 'KIT_WEBHOOK_URL=http://hook.invalid\nKIT_WEBHOOK_KEY=fake\n' > "$FH/.config/kit-watch/env"
HOME=$FH PATH=$BIN:$PATH sh "$HUB/services/telegram-relay/install.sh" >/dev/null
SECRET=fake-token-$RANDOM$RANDOM
printf 'TELEGRAM_BOT_TOKEN=%s\nKIT_WEBHOOK_URL=http://hook.invalid/%s\nKIT_WEBHOOK_KEY=%s\n' "$SECRET" "$SECRET" "$SECRET" > "$FH/.config/tg-relay/env"
chmod 600 "$FH/.config/tg-relay/env"
echo '{}' > "$FH/tg-relay/state.json"; : > "$FH/tg-relay/relay.log"
HOME=$FH PATH=$BIN:$PATH sh "$HUB/services/kit-watch/install.sh" >/dev/null
HOME=$FH sh "$HUB/services/graphify/install.sh" --stage >/dev/null
mkdir -p "$FH/graphify-out"
printf 'KIT_WEBHOOK_URL=http://hook.invalid/%s\nKIT_WEBHOOK_KEY=%s\nAGENTMAIL_API_KEY=%s\n' "$SECRET" "$SECRET" "$SECRET" > "$FH/.config/kit-watch/env"
echo '{}' > "$FH/kit-watch/state.json"; echo '{}' > "$FH/kit-watch/mail-state.json"; : > "$FH/kit-watch/watch.log"; : > "$FH/kit-watch/.lock"

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
[ "$("$CHECK" --list | tr '\n' ' ')" = "telegram-relay kit-watch graphify host " ] && pass "--list" || fail "--list"
echo disabled > "$STATE/enabled"; run --no-state
[ $RC = 0 ] && grep -q '^skip' <<<"$OUT" && pass "--no-state skips unit state" || { fail "--no-state (rc=$RC)"; echo "$OUT"; }
echo enabled > "$STATE/enabled"
run --service telegram-relay; [ $RC = 0 ] && pass "--service telegram-relay" || fail "--service telegram-relay (rc=$RC)"

# 11. kit-watch (idea#484).
K=$FH/kit-watch
cp -p "$K/mail-watch.py" "$T/mail-watch.py.orig"; echo "# hot-fix" >> "$K/mail-watch.py"
expect_drift "kit-watch: code change reported" "differs from repo: $H/kit-watch/mail-watch.py"
cp -p "$T/mail-watch.py.orig" "$K/mail-watch.py"; clean "kit-watch: code change undone"
TU=$FH/.config/systemd/user/kit-watch.timer; cp -p "$TU" "$T/timer.orig"; sed -i 's/AccuracySec=1s/AccuracySec=1min/' "$TU"
expect_drift "kit-watch: timer unit change reported" "differs from repo: $H/.config/systemd/user/kit-watch.timer"
cp -p "$T/timer.orig" "$TU"; clean "kit-watch: timer unit undone"
cp "$STATE/crontab" "$T/crontab.orig"
echo '* * * * * flock -n /home/pi/kit-watch/.cron-kit.lock timeout 90 /usr/bin/python3 /home/pi/kit-watch/kit-watch.py >/dev/null 2>&1' >> "$STATE/crontab"
expect_drift "kit-watch: old cron line reported" "crontab still has: kit-watch/mail-watch"
cp "$T/crontab.orig" "$STATE/crontab"; echo '#* * * * * /usr/bin/python3 /home/pi/kit-watch/mail-watch.py' >> "$STATE/crontab"
clean "kit-watch: commented-out cron line is not drift"
cp "$T/crontab.orig" "$STATE/crontab"
echo no > "$STATE/linger"; expect_drift "kit-watch: linger off reported" "linger=no for pi"
echo yes > "$STATE/linger"; clean "kit-watch: linger back on"
: > "$K/.cron-kit.lock"; expect_drift "kit-watch: leftover cron lock reported" "unexpected file in $H/kit-watch: .cron-kit.lock"
mv "$K/.cron-kit.lock" "$T/"; clean "kit-watch: leftover moved aside"
sed -i '/^AGENTMAIL_API_KEY=/d' "$FH/.config/kit-watch/env"
expect_drift "kit-watch: missing env key reported" "env key missing: AGENTMAIL_API_KEY"; no_secret "kit-watch env"
echo "AGENTMAIL_API_KEY=$SECRET" >> "$FH/.config/kit-watch/env"; clean "kit-watch: env restored"
run --service kit-watch; [ $RC = 0 ] && ! grep -q '\[telegram-relay\]' <<<"$OUT" && pass "--service kit-watch" || fail "--service kit-watch (rc=$RC)"

# 12. graphify (idea#485).
GU=$FH/.config/systemd/user/graphify-serve.service; cp -p "$GU" "$T/graphify.orig"
sed -i 's/--bind 0.0.0.0/--bind 127.0.0.1/' "$GU"
expect_drift "graphify: unit change reported" "differs from repo: $H/.config/systemd/user/graphify-serve.service"
cp -p "$T/graphify.orig" "$GU"; clean "graphify: unit undone"
mv "$FH/graphify-out" "$T/graphify-out.aside"
expect_drift "graphify: missing served dir reported" "missing served dir: $H/graphify-out"
mv "$T/graphify-out.aside" "$FH/graphify-out"; clean "graphify: served dir back"
run --service graphify; [ $RC = 0 ] && grep -q '\[graphify\] ok    *\|ok    \[graphify\]' <<<"$OUT" && pass "--service graphify" || { fail "--service graphify (rc=$RC)"; echo "$OUT"; }

# 13. host (idea#486).
echo '30 4 * * * /usr/local/bin/hand-added.sh' >> "$STATE/crontab.root"
expect_drift "host: extra root cron job reported" "crontab root: active lines differ from host/cron.root"
sed -i '/hand-added/d' "$STATE/crontab.root"; clean "host: root crontab back"
echo '# 0 1 * * * a comment only' >> "$STATE/crontab.root"; clean "host: comment-only change is not drift"
mv "$STATE/crontab.root" "$T/crontab.root.aside"
expect_drift "host: unreadable root crontab reported" "cannot read root crontab"
mv "$T/crontab.root.aside" "$STATE/crontab.root"; clean "host: root crontab readable again"
echo "echo hand-edit" >> "$T/usr/local/bin/boot.sh"
expect_drift "host: boot.sh change reported" "differs from repo: /usr/local/bin/boot.sh"
cp "$T/hubcopy/host/boot.sh" "$T/usr/local/bin/boot.sh"; clean "host: boot.sh undone"
mv "$T/etc/caddy/Caddyfile" "$T/Caddyfile.aside"
expect_drift "host: missing Caddyfile reported" "missing: /etc/caddy/Caddyfile"
mv "$T/Caddyfile.aside" "$T/etc/caddy/Caddyfile"; clean "host: Caddyfile back"
echo failed > "$STATE/active"; expect_drift "host: caddy inactive reported" "caddy.service is-active=failed"; echo active > "$STATE/active"
O2=$("$HUB/check.sh" --root "$T" --home "$H" --service host 2>&1); R2=$?
[ $R2 = 1 ] && grep -q "repo copy not captured yet: host/boot.sh" <<<"$O2" && grep -q "repo copy not captured yet: host/caddy/Caddyfile" <<<"$O2" && pass "host: real repo placeholders reported as drift" || { fail "host: placeholders (rc=$R2)"; echo "$O2"; }
grep -q "captured boot" <<<"$O2" && fail "host: live contents printed" || pass "host: live contents never printed"

# Scratch is left under $TMPDIR (no rm -rf); it holds only fake values.
echo "scratch: $T"
echo "passed $PASS, failed $FAIL"
[ $FAIL = 0 ]
