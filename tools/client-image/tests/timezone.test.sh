#!/bin/bash
# idea#208: no hardcoded country zone in the image build; set-card-timezone.sh validates + writes; idea-timezone applies.
# Temp dirs only, no root, no image. Uses the host tz database (/usr/share/zoneinfo).
set -u; H="$(cd "$(dirname "$0")/.." && pwd)"; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; f=0; n=0
ok(){ echo "ok:   $*"; n=$((n+1)); }; bad(){ echo "FAIL: $*"; f=1; }
# 1. build inputs carry no country zone
. "$H/client-image.conf"; [ "$TIMEZONE" = UTC ] && ok "client-image.conf TIMEZONE=UTC" || bad "TIMEZONE=$TIMEZONE"
hits=$(grep -rnE 'Africa/|Harare|CAT-2' "$H"/*.sh "$H"/*.conf "$H/files" 2>/dev/null | grep -v '^.*set-card-timezone.sh:.*e\.g\.' || true)
[ -z "$hits" ] && ok "no country zone in build scripts/files" || bad "hardcoded zone: $hits"
# 2. flash-time writer: validation
S="$H/set-card-timezone.sh"; mkdir -p "$T/boot"; : > "$T/boot/config.txt"
for z in Africa/Harare Africa/Lusaka UTC America/Argentina/Buenos_Aires Etc/GMT+2; do
  "$S" --check "$z" 2>/dev/null && ok "valid: $z" || bad "rejected valid $z"; done
for z in '' Africa/Nowhere '../../etc/passwd' '/etc/passwd' 'Africa/Harare;rm -rf /' 'Africa Harare' zone.tab right; do
  "$S" --check "$z" 2>/dev/null && bad "accepted invalid '$z'" || ok "rejected: $(printf %q "$z")"; done
"$S" --timezone Africa/Harare --boot "$T/boot" >/dev/null && [ "$(cat "$T/boot/idea-timezone.txt")" = Africa/Harare ] && ok "written to boot partition" || bad "write"
"$S" --timezone Bogus/Zone --boot "$T/boot" 2>/dev/null; [ $? = 2 ] && [ "$(cat "$T/boot/idea-timezone.txt")" = Africa/Harare ] && ok "invalid zone: exit 2, file untouched" || bad "invalid write"
mkdir -p "$T/notboot"; "$S" --timezone UTC --boot "$T/notboot" 2>/dev/null && bad "wrote to non-boot dir" || ok "refuses dir without config.txt"
"$S" --boot "$T/boot" 2>/dev/null && bad "no --timezone accepted" || ok "--timezone required"
# 3. boot step applies it (IDEA_TZ_ETC set -> symlink path, no timedatectl)
B="$H/files/idea-timezone"
app(){ rm -rf "${T:?}/etc"; mkdir -p "$T/etc"; ln -s /usr/share/zoneinfo/UTC "$T/etc/localtime"; echo UTC > "$T/etc/timezone"
  printf '%b' "$1" > "$T/tz.txt"; IDEA_TZ_SRC="$T/tz.txt" IDEA_TZ_ETC="$T/etc" sh "$B" >/dev/null 2>&1; echo "$(cat "$T/etc/timezone") $(readlink "$T/etc/localtime")"; }
chk(){ g=$(app "$1"); [ "$g" = "$2" ] && ok "boot $(printf %q "$1") -> $2" || bad "boot $(printf %q "$1") -> '$g' (want '$2')"; }
chk 'Africa/Harare\n' 'Africa/Harare /usr/share/zoneinfo/Africa/Harare'
chk ' Africa/Lusaka\r\nextra\n' 'Africa/Lusaka /usr/share/zoneinfo/Africa/Lusaka'
chk 'Bogus/Zone\n' 'UTC /usr/share/zoneinfo/UTC'
chk '../../../etc/passwd\n' 'UTC /usr/share/zoneinfo/UTC'
chk '' 'UTC /usr/share/zoneinfo/UTC'
rm -f "$T/tz.txt"; IDEA_TZ_SRC="$T/tz.txt" IDEA_TZ_ETC="$T/etc" sh "$B"; [ $? = 0 ] && [ "$(cat "$T/etc/timezone")" = UTC ] && ok "missing file -> UTC kept, exit 0" || bad "missing file"
app 'Africa/Harare' >/dev/null; app 'Africa/Harare' >/dev/null; [ "$(cat "$T/etc/timezone")" = Africa/Harare ] && ok "idempotent re-run (every boot)" || bad "rerun"
grep -q '^WantedBy=multi-user.target' "$H/files/idea-timezone.service" && grep -q 'RequiresMountsFor=/boot/firmware' "$H/files/idea-timezone.service" && ok "unit: boot partition mounted, every boot" || bad "unit"
grep -q 'files/idea-timezone ' "$H/customise.sh" && grep -q 'enable idea-timezone.service' "$H/customise.sh" && ok "customise.sh installs + enables unit" || bad "customise.sh"
echo "timezone.test: $n passed, fail=$f"; exit $f
