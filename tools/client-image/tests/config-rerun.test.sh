#!/bin/bash
# customise.sh config.txt step must be idempotent: a second run gives byte-identical output. No root, no image build.
set -u; H="$(cd "$(dirname "$0")/.." && pwd)"; F="$H/tests/fixtures"; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; f=0
awk '/^# --- boot config: KMS overlay per model/{g=1;next} g&&/^python3 - \/boot\/firmware\/config.txt <<.P.$/{p=1;next} p&&/^P$/{exit} p' \
  "$H/customise.sh" > "$T/step.py"
grep -q 'per-model KMS' "$T/step.py" || { echo "FAIL: could not extract config.txt step from customise.sh"; exit 1; }
for fx in ubuntu-26.04.1-base s15; do
  cp "$F/config.txt.$fx" "$T/a"; python3 "$T/step.py" "$T/a"; cp "$T/a" "$T/b"; python3 "$T/step.py" "$T/b"
  if cmp -s "$T/a" "$T/b"; then echo "ok:   $fx: second run byte-identical"; else echo "FAIL: $fx: second run differs"; diff "$T/a" "$T/b"; f=1; fi
  if [ "$(grep -cx 'dtoverlay=vc4-kms-v3d' "$T/b")" = 1 ]; then echo "ok:   $fx: [pi4] overlay line kept"; else echo "FAIL: $fx: [pi4] overlay line count"; f=1; fi
done
# s15 is already customised: the step on s15 must converge with the step on stock (same file either way)
cp "$F/config.txt.s15" "$T/c"; python3 "$T/step.py" "$T/c"; cp "$F/config.txt.ubuntu-26.04.1-base" "$T/d"; python3 "$T/step.py" "$T/d"
if cmp -s "$T/c" "$T/d"; then echo "ok:   step(s15) == step(stock)"; else echo "FAIL: step(s15) != step(stock)"; diff "$T/c" "$T/d"; f=1; fi
exit $f
