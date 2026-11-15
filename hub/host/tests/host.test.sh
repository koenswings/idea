#!/usr/bin/env bash
# shellcheck disable=SC2015  # pass() always returns 0, so "A && pass || fail" is safe here
# shellcheck disable=SC2016,SC2012  # stub bodies are literal; backup dir names are our own stamps
# Tests for hub/host/install.sh and hub/host/capture.sh (idea#486). Box only: a fake host tree
# (--root / HUB_CAPTURE_ROOT) and stub crontab/systemctl/caddy/sudo. Never touches a Pi, the
# box's own crontab, its systemd, or /etc.
set -u
HOST=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/hub-host-test.XXXXXX")
R=$T/root; BIN=$T/bin; ST=$T/state
mkdir -p "$R/usr/local/bin" "$R/etc/caddy" "$BIN" "$ST/cron"
PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "PASS $*"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL $*"; }

# crontab stub: "-l -u U" prints $ST/cron/U, "-u U FILE" writes it, plain "-l" = user pi.
cat > "$BIN/crontab" <<STUB
#!/bin/sh
u=pi; l=0; f=""
while [ \$# -gt 0 ]; do case "\$1" in -l) l=1;; -u) u=\$2; shift;; *) f=\$1;; esac; shift; done
echo "crontab u=\$u l=\$l f=\$f" >> "$ST/calls"
if [ \$l = 1 ]; then [ -e "$ST/cron/\$u" ] && cat "$ST/cron/\$u" || { echo "no crontab for \$u" >&2; exit 1; }
else cat "\$f" > "$ST/cron/\$u"; fi
STUB
printf '#!/bin/sh\necho "systemctl $*" >> "%s/calls"\nexit 0\n' "$ST" > "$BIN/systemctl"
printf '#!/bin/sh\n# caddy stub: validate fails when the config contains BAD\nfor a; do c=$a; done\nif grep -q BAD "$c"; then echo invalid >&2; exit 1; fi\nexit 0\n' > "$BIN/caddy"
printf '#!/bin/sh\n[ "$1" = -n ] && shift\nexec "$@"\n' > "$BIN/sudo"
chmod 755 "$BIN"/*
export HUB_HOST_CRONTAB=$BIN/crontab HUB_HOST_SYSTEMCTL=$BIN/systemctl HUB_HOST_CADDY=$BIN/caddy

# The live host as captured: same active lines as cron.root, and the pi crontab after #484.
cp "$HOST/cron.root" "$ST/cron/root"; sed -i '/^# hub\/host/,/^# check.sh/d' "$ST/cron/root"
cp "$HOST/cron.pi" "$ST/cron/pi"
printf '#!/bin/sh\necho live boot\n' > "$R/usr/local/bin/boot.sh"; chmod 755 "$R/usr/local/bin/boot.sh"
printf ':80 {\n  respond "live"\n}\n' > "$R/etc/caddy/Caddyfile"
snap() { (cd "$T" && find root state/cron -type f -exec sha256sum {} + | LC_ALL=C sort); }
OUT=""; RC=0
run() { OUT=$("${INST:-$HOST/install.sh}" --root "$R" "$@" 2>&1); RC=$?; }
has() { grep -q -- "$1" <<<"$OUT"; }

# 1. Plan on a matching host: nothing to do, placeholders skipped, nothing written.
B=$(snap); run
[ $RC = 0 ] && has "ok   crontab root" && has "ok   crontab pi" && pass "plan: crontabs match" || { fail "plan: crontabs match (rc=$RC)"; echo "$OUT"; }
has "SKIP /usr/local/bin/boot.sh: repo copy boot.sh is still a placeholder" && has "SKIP /etc/caddy/Caddyfile" && pass "plan: placeholders skipped" || { fail "plan: placeholders skipped"; echo "$OUT"; }
[ "$B" = "$(snap)" ] && pass "plan: nothing written" || fail "plan: nothing written"
run --apply; [ $RC = 0 ] && [ "$B" = "$(snap)" ] && [ ! -d "$R/var/backups" ] && pass "apply on matching host: no change, no backup" || { fail "apply on matching host (rc=$RC)"; echo "$OUT"; }

# 2. Live root crontab lost the avahi line: plan reports ADD, apply installs with a backup.
grep -v avahi "$ST/cron/root" > "$T/r" && cp "$T/r" "$ST/cron/root"
B=$(snap); run
[ $RC = 0 ] && has "+ 0 \* \* \* \* systemctl restart avahi-daemon" && [ "$B" = "$(snap)" ] && pass "plan: missing line reported, nothing written" || { fail "plan: missing line (rc=$RC)"; echo "$OUT"; }
run --apply
if [ $RC = 0 ] && grep -q avahi "$ST/cron/root" && ls "$R"/var/backups/idea-hub/host/*/crontab.root >/dev/null 2>&1; then pass "apply: root crontab installed, backup taken"; else fail "apply: root crontab (rc=$RC)"; echo "$OUT"; fi
cmp -s "$(ls "$R"/var/backups/idea-hub/host/*/crontab.root | head -1)" "$T/r" && pass "backup = the live crontab before" || fail "backup = the live crontab before"
run --apply; [ $RC = 0 ] && has "ok   crontab root" && pass "re-run after apply: ok" || fail "re-run after apply"

# 3. Live root has an extra active job: refused unless --allow-remove.
cp "$ST/cron/root" "$T/root.good"; echo '15 1 * * * /usr/local/bin/someone-elses-job' >> "$ST/cron/root"
B=$(snap); run --apply
[ $RC = 1 ] && has "REFUSE crontab root: would remove" && [ "$B" = "$(snap)" ] && pass "extra live line: refused, untouched" || { fail "extra live line refused (rc=$RC)"; echo "$OUT"; }
run --apply --allow-remove; [ $RC = 0 ] && cmp -s "$ST/cron/root" "$HOST/cron.root" && pass "--allow-remove: installed" || { fail "--allow-remove (rc=$RC)"; echo "$OUT"; }

# 4. pi crontab still has the kit-watch lines: refused even with --allow-remove.
cp "$ST/cron/pi" "$T/pi.good"
echo '* * * * * flock -n /home/pi/kit-watch/.cron-kit.lock timeout 90 /usr/bin/python3 /home/pi/kit-watch/kit-watch.py >/dev/null 2>&1' >> "$ST/cron/pi"
B=$(snap); run --apply --allow-remove
[ $RC = 1 ] && has "removed by hub/services/kit-watch/install.sh --remove-cron" && [ "$B" = "$(snap)" ] && pass "kit-watch cron lines: host step refuses" || { fail "kit-watch cron refuse (rc=$RC)"; echo "$OUT"; }
cp "$T/pi.good" "$ST/cron/pi"

# 5. Real (non-placeholder) Caddyfile in a copy of hub/host: invalid = refused; valid = installed + reload.
C=$T/hostcopy; mkdir -p "$C"; cp -a "$HOST/." "$C/"; INST=$C/install.sh
printf ':80 {\n  BAD\n}\n' > "$C/caddy/Caddyfile"; B=$(snap); run --apply
[ $RC = 1 ] && has "REFUSE /etc/caddy/Caddyfile: validation failed" && [ "$B" = "$(snap)" ] && pass "invalid Caddyfile: refused, live untouched" || { fail "invalid Caddyfile (rc=$RC)"; echo "$OUT"; }
printf ':80 {\n  respond "new"\n}\n' > "$C/caddy/Caddyfile"; : > "$ST/calls"; run
[ $RC = 0 ] && has "plan /etc/caddy/Caddyfile differs" && ! has 'respond' && pass "plan: Caddyfile diff by size/sha only (no contents)" || { fail "Caddyfile plan (rc=$RC)"; echo "$OUT"; }
run --apply
[ $RC = 0 ] && cmp -s "$C/caddy/Caddyfile" "$R/etc/caddy/Caddyfile" && grep -q "systemctl reload caddy" "$ST/calls" && ! grep -q "caddy-api\|restart" "$ST/calls" && pass "valid Caddyfile: installed, caddy reloaded, caddy-api untouched" || { fail "valid Caddyfile (rc=$RC)"; echo "$OUT"; cat "$ST/calls"; }
grep -rqx '  respond "live"' "$R"/var/backups/idea-hub/host/*/Caddyfile && pass "old Caddyfile backed up" || fail "old Caddyfile backed up"
[ "$(stat -c %a "$R/etc/caddy/Caddyfile")" = 644 ] && pass "Caddyfile mode 644" || fail "Caddyfile mode 644"

# 6. A cron.root with no active line is never installed for root.
grep '^#' "$HOST/cron.root" > "$C/cron.root"; cp "$C/caddy/Caddyfile" "$R/etc/caddy/Caddyfile"; B=$(snap); run --apply
[ $RC = 1 ] && has "REFUSE crontab root: cron.root has no active line" && [ "$B" = "$(snap)" ] && pass "empty cron.root refused" || { fail "empty cron.root (rc=$RC)"; echo "$OUT"; }
unset INST

# 7. Options.
"$HOST/install.sh" --bogus >/dev/null 2>&1; [ $? = 2 ] && pass "unknown option exits 2" || fail "unknown option exits 2"
if [ "$(id -u)" != 0 ]; then "$HOST/install.sh" --apply >/dev/null 2>&1; [ $? = 2 ] && pass "--apply on the real host refuses without root" || fail "--apply without root"; fi
"$HOST/install.sh" --help | grep -q "Default is a PLAN" && pass "--help" || fail "--help"

# 8. capture.sh: read-only copy into a private folder; counts secret-like lines, never prints them.
CR=$T/caproot; mkdir -p "$CR/usr/local/bin" "$CR/etc/caddy" "$CR/etc/cron.d" "$CR/etc/cron.weekly" "$T/cahome/kit-watch" "$T/cahome/.config/systemd/user"
SECRET=fake-secret-$RANDOM$RANDOM
printf '#!/bin/sh\necho boot\n' > "$CR/usr/local/bin/boot.sh"
printf ':80 {\n  basic_auth { admin %s }\n}\n' "$SECRET" > "$CR/etc/caddy/Caddyfile"
echo x > "$CR/etc/cron.d/some-job"; echo 'tailscale cert x' > "$CR/etc/cron.weekly/renew-tailscale-cert"
echo 'print(1)' > "$T/cahome/kit-watch/kit-watch.py"; echo '[Service]' > "$T/cahome/.config/systemd/user/graphify-serve.service"
B=$( (cd "$CR" && find . -type f -exec sha256sum {} + | LC_ALL=C sort) )
CO=$(HOME=$T/cahome PATH=$BIN:$PATH HUB_CAPTURE_ROOT=$CR "$HOST/capture.sh" "$T/capout" 2>&1); CRC=$?
[ $CRC = 0 ] && [ -f "$T/capout/boot.sh" ] && [ -f "$T/capout/caddy/Caddyfile" ] && [ -f "$T/capout/SHA256SUMS" ] && pass "capture: files copied" || { fail "capture: files copied (rc=$CRC)"; echo "$CO"; }
[ "$(stat -c %a "$T/capout")" = 700 ] && pass "capture: folder mode 700" || fail "capture: folder mode 700"
grep -q "./caddy/Caddyfile: 1" <<<"$CO" && pass "capture: secret-like line counted" || { fail "capture: secret count"; echo "$CO"; }
grep -q "$SECRET" <<<"$CO" && fail "capture: secret printed" || pass "capture: secret value never printed"
grep -q "missing or unreadable.*mail-watch.py" <<<"$CO" && [ ! -e "$T/capout/kit-watch/mail-watch.py" ] && pass "capture: missing file noted, no partial copy" || fail "capture: missing file"
[ ! -e "$T/capout/cron.d/some-job" ] && grep -q some-job "$T/capout/cron.d-names.txt" && pass "capture: /etc/cron.d names only" || fail "capture: cron.d names only"
[ "$B" = "$( (cd "$CR" && find . -type f -exec sha256sum {} + | LC_ALL=C sort) )" ] && pass "capture: host tree unchanged" || fail "capture: host tree unchanged"

echo "scratch: $T"
echo "passed $PASS, failed $FAIL"
[ $FAIL = 0 ]
