#!/bin/bash
# scan-secrets.sh ROOTFS SECRETS_FILE : secrets may only appear where intended. Prints file names only, never values.
set -u; R="$1"; . "$2"; fail=0
hits(){ grep -rlsF --exclude-dir={proc,sys,dev,run} -e "$1" "$R" 2>/dev/null; }
for f in $(hits "$WIFI_PSK"); do [ "$f" = "$R/etc/NetworkManager/system-connections/IDEA.nmconnection" ] || { echo "FAIL: wifi psk found in $f"; fail=1; }; done
[ -z "${ADMIN_PASSWORD_HASH:-}" ] || for f in $(hits "$ADMIN_PASSWORD_HASH"); do [ "$f" = "$R/etc/shadow" ] || { echo "FAIL: admin hash found in $f"; fail=1; }; done
[ -e "$R/root/.idea-build" ] && { echo "FAIL: build staging left in image"; fail=1; }
find "$R/home" "$R/root" "$R/etc" -name 'id_*' ! -name '*.pub' 2>/dev/null | grep . && { echo "FAIL: private key files"; fail=1; }
[ $fail = 0 ] && echo "secret scan: ok"; exit $fail
