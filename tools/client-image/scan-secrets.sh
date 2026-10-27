#!/bin/bash
# shellcheck disable=SC1090  # sources a user-supplied config path
# scan-secrets.sh ROOTFS [SECRETS_FILE] : the image must carry NO secrets (idea#322: injected at flash time).
# Prints file names only, never values. With SECRETS_FILE (flash-time secrets.env), also greps for those values.
set -u; R="$1"; fail=0
hits(){ grep -rlsF --exclude-dir={proc,sys,dev,run} -e "$1" "$R" 2>/dev/null; }
if [ -n "${2:-}" ] && [ -f "$2" ]; then
  set +x; . "$2"
  if [ -n "${WIFI_PSK_FILE:-}" ] && [ -s "$WIFI_PSK_FILE" ]; then k=$(head -n1 "$WIFI_PSK_FILE" | tr -d '\r\n')
    for f in $(hits "$k"); do echo "FAIL: wifi psk found in $f"; fail=1; done; unset k; fi
  if [ -n "${ADMIN_AUTHORIZED_KEYS_FILE:-}" ] && [ -s "$ADMIN_AUTHORIZED_KEYS_FILE" ]; then
    while read -r _ b _; do [ -n "${b:-}" ] || continue; for f in $(hits "$b"); do echo "FAIL: admin public key found in $f"; fail=1; done
    done < "$ADMIN_AUTHORIZED_KEYS_FILE"; fi
fi
N="$R/etc/NetworkManager/system-connections/IDEA.nmconnection"
[ -e "$N" ] && { echo "FAIL: Wi-Fi profile baked into the image ($N); it is written at first boot from the flash-time key"; fail=1; }
for f in "$R"/etc/NetworkManager/system-connections/*; do [ -f "$f" ] && grep -qE '^psk=.+' "$f" && { echo "FAIL: psk in $f"; fail=1; }; done
[ -s "$R/home/admin/.ssh/authorized_keys" ] && { echo "FAIL: admin authorized_keys baked into the image"; fail=1; }
[ -e "$R/root/.idea-build" ] && { echo "FAIL: build staging left in image"; fail=1; }
[ -e "$R/boot/firmware/idea-secrets" ] && { echo "FAIL: idea-secrets on the boot partition of the image"; fail=1; }
find "$R/home" "$R/root" "$R/etc" -name 'id_*' ! -name '*.pub' 2>/dev/null | grep . && { echo "FAIL: private key files"; fail=1; }
grep -rlsE --exclude-dir={proc,sys,dev,run,usr} 'tskey-(auth|client)-' "$R" 2>/dev/null | grep . && { echo "FAIL: Tailscale key in image"; fail=1; }
[ $fail = 0 ] && echo "secret scan: ok (no secrets in image)"; exit $fail
