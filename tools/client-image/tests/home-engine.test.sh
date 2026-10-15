#!/bin/bash
# Tests files/idea-home-engine (boot step copying idea-home.txt) against temp dirs. No root needed.
set -u; H="$(cd "$(dirname "$0")/.." && pwd)"; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; f=0
run(){ printf '%b' "$1" > "$T/idea-home.txt"; IDEA_HOME_SRC="$T/idea-home.txt" IDEA_ETC="$T/etc" sh "$H/files/idea-home-engine" 2>/dev/null; cat "$T/etc/home-engine"; }
chk(){ got=$(run "$1"); [ "$got" = "$2" ] && echo "ok:   $(printf %q "$1") -> '$2'" || { echo "FAIL: $(printf %q "$1") -> '$got' (want '$2')"; f=1; }; }
chk 'brave-otter\n' brave-otter;  chk 'Brave-Otter.local\r\n' brave-otter;  chk ' calm-heron \nextra\n' calm-heron
chk '-otter' '';  chk 'a_b' '';  chk '"; alert(1); "' '';  chk "$(printf 'a%.0s' {1..64})" '';  chk '' ''
rm -f "$T/idea-home.txt"; IDEA_HOME_SRC="$T/idea-home.txt" IDEA_ETC="$T/etc" sh "$H/files/idea-home-engine"; [ ! -s "$T/etc/home-engine" ] && echo "ok:   missing file -> empty" || f=1
run 'brave-otter' >/dev/null; grep -qx 'window.IDEA_HOME_ENGINE = "brave-otter";' "$T/etc/home-engine.js" && echo "ok:   home-engine.js" || { echo "FAIL: home-engine.js"; f=1; }
exit $f
