#!/usr/bin/env bash
# archive-inputs.test.sh - offline tests for tools/repro/archive-inputs.sh (idea#322 input archive). No root, no network.
set -uo pipefail
R=$(cd "$(dirname "$0")/.." && pwd); A="$R/archive-inputs.sh"
pass=0; fail=0
check() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS $n"; pass=$((pass+1)); else echo "FAIL $n"; fail=$((fail+1)); fi; }
nope() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "FAIL $n (expected failure)"; fail=$((fail+1)); else echo "PASS $n"; pass=$((pass+1)); fi; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/cache" "$W/ec/sub"; echo base-image > "$W/cache/base.img.xz"; echo '{"lock":1}' > "$W/engine.lock.json"
echo a > "$W/ec/sub/x"; echo b > "$W/ec/y"
S=$(sha256sum "$W/cache/base.img.xz" | cut -d' ' -f1)
printf 'base\thttps://example.invalid/img/base.img.xz\t%s\t11\n' "$S" > "$W/inputs.tsv"
printf 'base\thttps://example.invalid/img/base.img.xz\t%064d\t11\n' 0 > "$W/bad.tsv"
printf 'fw\thttps://example.invalid/fw.bin\t%064d\t1\n' 0 > "$W/missing.tsv"
run(){ "$A" --cache-dir "$W/cache" --offline "$@"; }
check "archives a cached pinned input + lock file + cache dir" run --out "$W/o" --inputs "$W/inputs.tsv" --file engine-lock="$W/engine.lock.json" --dir engine-cache="$W/ec"
check "ARCHIVE.tsv has 3 rows" bash -c "[ \$(wc -l < '$W/o/ARCHIVE.tsv') = 3 ]"
check "base copied under its label with pinned sha" grep -q "^base	base.img.xz	$S	" "$W/o/ARCHIVE.tsv"
check "SIZE is the byte total" bash -c "[ \$(cat '$W/o/SIZE') = \$(awk -F'\t' '{s+=\$4}END{print s}' '$W/o/ARCHIVE.tsv') ]"
check "verify passes" "$A" --verify "$W/o"
check "rerun is idempotent (same SHA256SUMS)" bash -c "cp '$W/o/SHA256SUMS' '$W/s1' && '$A' --cache-dir '$W/cache' --offline --out '$W/o' --inputs '$W/inputs.tsv' --file engine-lock='$W/engine.lock.json' --dir engine-cache='$W/ec' && cmp '$W/s1' '$W/o/SHA256SUMS'"
check "dir tar is deterministic across mtimes" bash -c "touch -d 2001-01-01 '$W/ec/y' && '$A' --offline --out '$W/o2' --dir engine-cache='$W/ec' && [ \"\$(cut -f3 '$W/o2/ARCHIVE.tsv')\" = \"\$(grep ^engine-cache '$W/o/ARCHIVE.tsv' | cut -f3)\" ]"
check "no temp copies left in the archive root" bash -c "! ls -d '$W/o/.dl' '$W/o/.tar' 2>/dev/null | grep -q ."
echo tampered >> "$W/o/engine-lock/engine.lock.json"; nope "verify fails on a changed file" "$A" --verify "$W/o"
nope "sha256 mismatch is fatal" run --out "$W/o3" --inputs "$W/bad.tsv"
nope "missing input offline is fatal" run --out "$W/o4" --inputs "$W/missing.tsv"
printf "auth=%s-%s-kFAKE0000\n" tskey auth > "$W/leak.txt"; nope "refuses a file holding a Tailscale key" run --out "$W/o5" --file x="$W/leak.txt"
mkdir -p "$W/ec2"; printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\n' > "$W/ec2/id"; nope "refuses a dir holding a private key" run --out "$W/o6" --dir c="$W/ec2"
nope "bad label refused" run --out "$W/o7" --file '../x'="$W/engine.lock.json"
nope "nothing to archive refused" "$A" --out "$W/o8"
check "engine.conf base pin is archivable (label row shape)" bash -c ". '$R/../engine-image/engine-image.conf' && printf 'base\t%s/%s\t%s\t0\n' \"\$BASE_URL\" \"\$BASE_IMAGE\" \"\$BASE_SHA256\" | awk -F'\t' 'NF==4 && length(\$3)==64' | grep -q ."
echo "archive-inputs tests: $pass passed, $fail failed"; [ $fail = 0 ]
