#!/usr/bin/env bash
# router-packages.sh ROOT - installed packages of an unpacked OpenWrt root as "name<TAB>version<TAB>arch" (apk or opkg db).
set -euo pipefail
R="${1:?usage: router-packages.sh ROOT}"
if [ -f "$R/lib/apk/db/installed" ]; then awk -F: '$1=="P"{p=$2} $1=="V"{v=$2} $1=="A"{print p"\t"v"\t"$2}' "$R/lib/apk/db/installed"
elif [ -f "$R/usr/lib/opkg/status" ]; then awk '/^Package:/{p=$2} /^Version:/{v=$2} /^Architecture:/{print p"\t"v"\t"$2}' "$R/usr/lib/opkg/status"
else echo "no apk/opkg database under $R" >&2; exit 1; fi | LC_ALL=C sort -u
