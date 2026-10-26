#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2015,SC1091,SC2012  # fixtures use literal $; a && ok || no is intended
# tools/repro/tests/run.sh - fixture tests for the reproducible-image tooling (idea#322). No network, no root.
set -uo pipefail
R=$(cd "$(dirname "$0")/.." && pwd); CI="$R/../client-image"; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok(){ echo "PASS $1"; pass=$((pass+1)); }; no(){ echo "FAIL $1"; fail=$((fail+1)); }
t(){ local n="$1"; shift; if "$@" >"$T/out" 2>&1; then ok "$n"; else no "$n"; sed 's/^/   /' "$T/out" | head -20; fi; }
tf(){ local n="$1"; shift; if "$@" >"$T/out" 2>&1; then no "$n (expected failure)"; else ok "$n"; fi; }

# --- fixture rootfs
mk_root(){ rm -rf "$1"; mkdir -p "$1"/{etc/ssh,usr/bin,var/log,var/lib/dpkg,proc,boot/firmware}
  echo hello > "$1/usr/bin/tool"; chmod 755 "$1/usr/bin/tool"; ln -s tool "$1/usr/bin/alias"
  echo machine-1 > "$1/etc/machine-id"; echo key1 > "$1/etc/ssh/ssh_host_ed25519_key"; echo log1 > "$1/var/log/syslog"
  echo 'admin:$6$salt1$hash1:20000:0:99999:7:::' > "$1/etc/shadow"
  printf 'Package: tool\nVersion: 1.0\n\nPackage: libx\nVersion: 2.1-1\n' > "$1/var/lib/dpkg/status"; }
A="$T/a"; B="$T/b"; mk_root "$A"; mk_root "$B"
echo machine-2 > "$B/etc/machine-id"; echo key2 > "$B/etc/ssh/ssh_host_ed25519_key"; echo log2 > "$B/var/log/syslog"
sed -i 's/salt1\$hash1/salt2$hash2/' "$B/etc/shadow"
export REPRO_NO_OWNER=1
"$R/content-manifest.sh" "$A" > "$T/a.tsv"; "$R/content-manifest.sh" "$B" > "$T/b.tsv"
t "content manifest ignores volatile files and shadow hashes" "$R/compare-manifest.sh" "$T/a.tsv" "$T/b.tsv"
t "manifest lists regular file with hash" grep -q "$(sha256sum "$A/usr/bin/tool" | cut -d' ' -f1)"$'\t'/usr/bin/tool "$T/a.tsv"
t "manifest lists symlink target" grep -q $'\ttool\t/usr/bin/alias' "$T/a.tsv"
t "manifest marks machine-id volatile" grep -q $'\tvolatile\t/etc/machine-id' "$T/a.tsv"
echo changed > "$B/usr/bin/tool"; "$R/content-manifest.sh" "$B" > "$T/b2.tsv"
tf "compare detects changed content" "$R/compare-manifest.sh" "$T/a.tsv" "$T/b2.tsv"
xz -k "$T/a.tsv"; t "compare reads .xz" "$R/compare-manifest.sh" "$T/a.tsv.xz" "$T/a.tsv"

# --- write-manifest + rebuild-check --rootfs
printf 'tool\t1.0\nlibx\t2.1-1\n' > "$T/pk.tsv"; printf 'base\tfile:///x\t%064d\t1\n' 0 > "$T/in.tsv"; echo img > "$T/x.img"
t "write-manifest" env BUILD_KIND=dev BUILD_SHA=abc BUILD_TAG= BUILD_STAMP=dev-abc "$R/write-manifest.sh" --out "$T/m" --kind client --name fx --rootfs "$A" --packages "$T/pk.tsv" --inputs "$T/in.tsv" --image "$T/x.img"
for f in build.env inputs.tsv packages.tsv content.tsv.xz content.sha256 image.sha256; do [ -s "$T/m/$f" ] || no "write-manifest wrote $f"; done
mk_root "$B"; echo machine-3 > "$B/etc/machine-id"
t "rebuild-check passes on equivalent tree" "$R/rebuild-check.sh" --manifest-dir "$T/m" --rootfs "$B" --packages "$T/pk.tsv"
echo extra > "$B/usr/bin/new"
tf "rebuild-check fails on extra file" "$R/rebuild-check.sh" --manifest-dir "$T/m" --rootfs "$B" --packages "$T/pk.tsv"
rm "$B/usr/bin/new"; printf 'tool\t1.1\nlibx\t2.1-1\n' > "$T/pk2.tsv"
tf "rebuild-check fails on package version change" "$R/rebuild-check.sh" --manifest-dir "$T/m" --rootfs "$B" --packages "$T/pk2.tsv"

# --- release guard
G="$T/g"; git init -q -b main "$G"; git -C "$G" -c user.email=t@t -c user.name=t commit -q --allow-empty -m one
git -C "$G" update-ref refs/remotes/origin/main HEAD
guard(){ ( cd "$G" && . "$R/lib.sh" && repro_release_guard "$G" "${1:-0}" && echo "$BUILD_KIND $BUILD_STAMP" ); }
tf "guard refuses untagged commit" guard
git -C "$G" tag v1; t "guard accepts tagged commit on main" guard
[ "$(guard)" = "release v1" ] && ok "guard stamps release with tag" || no "guard stamps release with tag"
echo x > "$G/dirty"; tf "guard refuses dirty tree" guard
[[ "$(guard 1 2>/dev/null)" == "dev dev-"*-dirty ]] && ok "--dev stamps dirty dev build" || no "--dev stamps dirty dev build"
rm "$G/dirty"; git -C "$G" checkout -q -b side; git -C "$G" -c user.email=t@t -c user.name=t commit -q --allow-empty -m two; git -C "$G" tag v2
tf "guard refuses tag not on main" guard

# --- repro_fetch
echo payload > "$T/src.bin"; S=$(sha256sum "$T/src.bin" | cut -d' ' -f1)
t "repro_fetch verifies good hash" bash -c ". '$R/lib.sh'; repro_fetch 'file://$T/src.bin' $S '$T/dl1'"
tf "repro_fetch fails on mismatch" bash -c ". '$R/lib.sh'; repro_fetch 'file://$T/src.bin' $(printf '%064d' 1) '$T/dl2'"
[ -f "$T/dl2.bad" ] && [ ! -f "$T/dl2" ] && ok "mismatched download moved to .bad" || no "mismatched download moved to .bad"
tf "repro_fetch refuses missing pin" bash -c ". '$R/lib.sh'; repro_fetch 'file://$T/src.bin' '' '$T/dl3'"

# --- flash-time secrets (client)
BT="$T/boot"; mkdir -p "$BT"; touch "$BT/config.txt"; FAKE='fixture-psk-not-real-123'
printf '%s\n' "$FAKE" > "$T/psk"; echo 'ssh-ed25519 AAAAfixture test@fixture' > "$T/ak"
t "set-card-secrets writes boot files" env IDEA_SECRETS_CONF=/nonexistent "$CI/set-card-secrets.sh" --boot "$BT" --wifi-psk-file "$T/psk" --authorized-keys "$T/ak"
tf "set-card-secrets output never shows the psk" grep -q "$FAKE" "$T/out"
RT="$T/croot"; mkdir -p "$RT"
t "idea-secrets-apply installs secrets" env IDEA_SECRETS_DIR="$BT/idea-secrets" IDEA_ROOT="$RT" IDEA_NM_TEMPLATE="$CI/files/IDEA.nmconnection.template" IDEA_CHOWN=0 "$CI/files/idea-secrets-apply"
t "Wi-Fi profile has the psk" grep -qx "psk=$FAKE" "$RT/etc/NetworkManager/system-connections/IDEA.nmconnection"
[ "$(stat -c %a "$RT/etc/NetworkManager/system-connections/IDEA.nmconnection")" = 600 ] && ok "Wi-Fi profile mode 600" || no "Wi-Fi profile mode 600"
t "authorized_keys installed" cmp "$T/ak" "$RT/home/admin/.ssh/authorized_keys"
[ ! -e "$BT/idea-secrets" ] && ok "boot secrets removed" || no "boot secrets removed"
tf "apply output never shows the psk" grep -q "$FAKE" "$T/out"
mkdir -p "$BT/idea-secrets"; echo short > "$BT/idea-secrets/wifi-psk"
tf "idea-secrets-apply rejects short psk" env IDEA_SECRETS_DIR="$BT/idea-secrets" IDEA_ROOT="$T/croot2" IDEA_NM_TEMPLATE="$CI/files/IDEA.nmconnection.template" IDEA_CHOWN=0 "$CI/files/idea-secrets-apply"

# --- capture-device with a mock ssh (runs the probe locally against nothing remote)
printf '#!/bin/sh\nshift\nexec sh -c "$*"\n' > "$T/fakessh"; chmod +x "$T/fakessh"
t "capture-device writes a capture" env CAPTURE_SSH="$T/fakessh" HASH_DIRS="$A/usr" "$R/capture-device.sh" fixture-dev local@test "$T/cap"
C=$(ls "$T"/cap/fixture-dev-*.txt 2>/dev/null | head -1)
[ -n "$C" ] && grep -q '^=== end' "$C" && (cd "$T/cap" && sha256sum -c --quiet "$(basename "$C").sha256") && ok "capture complete with sha256" || no "capture complete with sha256"
tf "capture-device rejects bad name" "$R/capture-device.sh" 'Bad Name' x@y "$T/cap"

# --- archive-debs against a local mirror
M="$T/mirror"; mkdir -p "$M/dists/resolute/main/binary-arm64" "$M/pool"; echo deb1 > "$M/pool/tool_1.0_arm64.deb"
DS=$(sha256sum "$M/pool/tool_1.0_arm64.deb" | cut -d' ' -f1)
printf 'Package: tool\nVersion: 1.0\nArchitecture: arm64\nFilename: pool/tool_1.0_arm64.deb\nSHA256: %s\n\n' "$DS" | gzip > "$M/dists/resolute/main/binary-arm64/Packages.gz"
printf 'tool\t1.0\nghost\t9\n' > "$T/want.tsv"
python3 "$R/archive-debs.py" --manifest "$T/want.tsv" --out "$T/arch" --mirror "file://$M" --suite resolute --comp main >"$T/out" 2>&1
[ -f "$T/arch/tool_1.0_arm64.deb" ] && grep -q ghost "$T/arch/missing.tsv" && grep -q tool_1.0 "$T/arch/SHA256SUMS" && ok "archive-debs downloads, hashes and lists missing" || { no "archive-debs downloads, hashes and lists missing"; cat "$T/out"; }
printf 'Package: tool\nVersion: 1.0\nArchitecture: arm64\nFilename: pool/tool_1.0_arm64.deb\nSHA256: %064d\n\n' 7 | gzip > "$M/dists/resolute/main/binary-arm64/Packages.gz"
tf "archive-debs fails on sha256 mismatch" python3 "$R/archive-debs.py" --manifest "$T/want.tsv" --out "$T/arch2" --mirror "file://$M" --suite resolute --comp main

# --- deployment records (compare-record.py)
RE="$T/rec/e"; RA="$T/rec/a"; mkdir -p "$RE" "$RA"
cat > "$RE/record.txt" <<'R'
schema=idea-deployment-record/1
batch=b1
deviceType=engine
hostname=h1
arch=aarch64
model=m
osRelease=os
imageCommit=abc
imageBranch=main
imageTag=
imageVersion=1
imageFile=n/a
imageSha256=n/a
imageManifest=n/a
nodeVersion=UNKNOWN
packageArchive=/x
packageArchiveSha256=UNKNOWN
packageArchiveUrl=not published yet
secrets=none
deployedAt=d1
evidence=e
confidence=c
open=o
R
printf 'tool\t1.0\tarm64\n' > "$RE/packages.tsv"; printf '%064d  a.js\n' 1 > "$RE/files.sha256"; printf '%064d  d.js\n' 2 > "$RE/dist.sha256"
echo "contentSha256=$(cat "$RE/files.sha256" "$RE/dist.sha256" | sha256sum | cut -d' ' -f1)" >> "$RE/record.txt"
cp "$RE"/* "$RA/"; sed -i 's/^hostname=h1/hostname=h2/; s/^deployedAt=d1/deployedAt=d2/; s/^nodeVersion=UNKNOWN/nodeVersion=v22/' "$RA/record.txt"
t "record check passes (engine contentSha256)" python3 "$R/compare-record.py" --check "$RE"
t "records equal apart from volatile keys and UNKNOWN" python3 "$R/compare-record.py" "$RE" "$RA"
printf 'tool\t1.1\tarm64\n' > "$RA/packages.tsv"
tf "record compare detects package change" python3 "$R/compare-record.py" "$RE" "$RA"
cp "$RE/packages.tsv" "$RA/"; sed -i 's/^imageCommit=abc/imageCommit=def/' "$RA/record.txt"
tf "record compare detects commit change" python3 "$R/compare-record.py" "$RE" "$RA"
printf '%064d  d.js\n' 3 > "$RE/dist.sha256"
tf "record check catches stale contentSha256" python3 "$R/compare-record.py" --check "$RE"
printf 'tool\t1.0\n' > "$RE/packages.tsv"; sed -i '/^contentSha256/d' "$RE/record.txt"
tf "record check requires 3-column packages.tsv" python3 "$R/compare-record.py" --check "$RE"
grep -v '^packageArchiveUrl=' "$RA/record.txt" > "$T/rec/nourl.txt"; mkdir -p "$T/rec/n"; cp "$T/rec/nourl.txt" "$T/rec/n/record.txt"
tf "record check requires packageArchiveUrl" python3 "$R/compare-record.py" --check "$T/rec/n"
t "volatile.txt holds record keys" grep -qx 'key:capturedUtc' "$R/volatile.txt"
for d in "$R"/../../deployments/*/*/*/; do [ -f "$d/record.txt" ] || continue
  python3 "$R/compare-record.py" --check "$d" >/dev/null || no "committed record valid: $d"; done; ok "committed records valid"

# --- router-packages 3 columns
RR="$T/rr"; mkdir -p "$RR/lib/apk/db"; printf 'P:busybox\nV:1.37.0-r6\nA:aarch64_cortex-a53\n\nP:base-files\nV:1711\nA:aarch64_cortex-a53\n' > "$RR/lib/apk/db/installed"
t "router-packages prints package, version, arch" bash -c "[ \"\$('$R/router-packages.sh' '$RR' | head -1)\" = \"\$(printf 'base-files\t1711\taarch64_cortex-a53')\" ]"

echo "repro tests: $pass passed, $fail failed"; [ $fail = 0 ]
