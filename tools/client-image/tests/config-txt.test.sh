#!/bin/bash
# idea#304: customise.sh config.txt step + files/check-config-txt.py against the stock Ubuntu 26.04.1 raspi config.txt
# and the s15 (291b962) one. No root, no image build.
set -u; H="$(cd "$(dirname "$0")/.." && pwd)"; F="$H/tests/fixtures"; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; f=0
CHK="$H/files/check-config-txt.py"
# the config.txt python step from customise.sh, verbatim (heredoc after the "boot config" comment)
awk '/^# --- boot config: KMS overlay per model/{g=1;next} g&&/^python3 - \/boot\/firmware\/config.txt <<.P.$/{p=1;next} p&&/^P$/{exit} p' \
  "$H/customise.sh" > "$T/step.py"
grep -q usb_max_current_enable "$T/step.py" || { echo "FAIL: could not extract config.txt step from customise.sh"; exit 1; }
pass(){ echo "ok:   $*"; }; fail(){ echo "FAIL: $*"; f=1; }
cp "$F/config.txt.ubuntu-26.04.1-base" "$T/c"; python3 "$T/step.py" "$T/c"
python3 "$CHK" "$T/c" >"$T/out" && pass "stock -> customise -> all checks pass" || { fail "stock -> customise"; cat "$T/out"; }
# vs s15: exactly one added line, directly under dtoverlay=vc4-kms-v3d-pi5
d=$(diff "$F/config.txt.s15" "$T/c"); [ "$d" = $'68a69\n> usb_max_current_enable=1' ] && pass "diff vs s15 is only +usb_max_current_enable=1 in [pi5]" || { fail "diff vs s15:"; echo "$d"; }
cp "$T/c" "$T/c2"; python3 "$T/step.py" "$T/c2"; [ "$(grep -c usb_max_current_enable "$T/c2")" = 1 ] && pass "step idempotent for the usb line" || fail "usb line duplicated on re-run"
neg(){ python3 "$CHK" "$T/n" >"$T/out"; [ $? -ne 0 ] && grep -q "FAIL: .*$2" "$T/out" && pass "rejects: $1" || { fail "accepted: $1"; cat "$T/out"; }; }
cp "$F/config.txt.s15" "$T/n"; neg "s15 (line missing)" "in \[pi5\]"
cp "$T/c" "$T/n"; printf 'usb_max_current_enable=1\n' >> "$T/n"; neg "line also in [all]" "no other section"
sed 's/^\[pi5\]$/[pi4]/' "$T/c" > "$T/n"; neg "line in [pi4]" "no other section"
sed 's/^arm_boost=1$/arm_boost=0/' "$T/c" > "$T/n"; neg "[pi4] changed" "byte-identical"
sed '/^usb_max_current_enable=1$/s/1$/0/' "$T/c" > "$T/n"; neg "=0 in [pi5]" "in \[pi5\]"
exit $f
