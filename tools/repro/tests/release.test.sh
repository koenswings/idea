#!/usr/bin/env bash
# release.test.sh - offline tests for release.sh (idea#322). A throwaway clone of this repo with test tags, a mock build
# (RELEASE_BUILD_CMD) and a mock image manifest (RELEASE_IMAGE_MANIFEST_CMD). No root, no network, no real image.
set -uo pipefail
R=$(cd "$(dirname "$0")/.." && pwd); REPO=$(git -C "$R" rev-parse --show-toplevel)
pass=0; fail=0
check() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS $n"; pass=$((pass+1)); else echo "FAIL $n"; fail=$((fail+1)); fi; }
nope() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "FAIL $n (expected failure)"; fail=$((fail+1)); else echo "PASS $n"; pass=$((pass+1)); fi; }
W=$(mktemp -d); trap 'chmod -R u+w "$W" 2>/dev/null; rm -rf "$W"' EXIT
git clone -q --no-hardlinks "$REPO" "$W/repo"; C="$W/repo"
git -C "$C" -c user.name=t -c user.email=t@t tag -a t-rel1 -m r1 HEAD
cp "$R/release.sh" "$C/tools/repro/release.sh"; cp "$R/compare-image-manifest.py" "$R/compare-manifest.sh" "$C/tools/repro/" 2>/dev/null
echo change >> "$C/README.md"; git -C "$C" -c user.name=t -c user.email=t@t commit -qam c2; git -C "$C" -c user.name=t -c user.email=t@t tag -a t-rel2 -m r2 HEAD
RS="$C/tools/repro/release.sh"; ROOT="$W/releases"
# mock build: image named after the commit; content line depends on README.md (so rel1 != rel2)
export RELEASE_BUILD_CMD='n=$(git -C "$RELEASE_SRC" rev-parse --short HEAD); printf "img-%s\n" "$(sha256sum < "$RELEASE_SRC/README.md")" > "$RELEASE_OUT/idea-client-26.04-x-$n.img.xz"; mkdir -p "$RELEASE_MANIFEST"; echo m > "$RELEASE_MANIFEST/build.env"; [ -z "${MOCK_FAIL:-}" ]'
cat > "$W/imgman" <<'SH'
#!/usr/bin/env bash
{ printf '#idea-image-manifest/2\tpart\ttype\tmode\towner\tsize\tcontent\trdev\tpath\n'
  printf 'root\tf\t644\t0:0\t5\t%s\t-\t/etc/x\n' "$(sha256sum "$1" | cut -d' ' -f1)"; } > "$2"
SH
chmod +x "$W/imgman"; export RELEASE_IMAGE_MANIFEST_CMD="$W/imgman"
nope "usage: no type" "$RS" --tag t-rel1 --root "$ROOT"
nope "unknown tag refused" "$RS" --type client --tag nosuch --root "$ROOT" --prev none
nope "bad tag name refused" "$RS" --type client --tag 'a;b' --root "$ROOT" --prev none
check "first release (--prev none)" "$RS" --type client --tag t-rel1 --root "$ROOT" --prev none
D1="$ROOT/client/t-rel1"
check "release has image + sha256" bash -c "ls '$D1'/idea-client-*.img.xz && cd '$D1' && sha256sum -c --quiet idea-client-*.img.xz.sha256"
check "release has image manifest + build manifest" test -f "$D1/image-manifest.tsv.xz" -a -f "$D1/manifest/build.env"
check "RELEASE.txt names tag, commit, first release" bash -c "grep -q '^tag=t-rel1$' '$D1/RELEASE.txt' && grep -q \"^commit=\$(git -C '$C' rev-parse t-rel1^{commit})\$\" '$D1/RELEASE.txt' && grep -q '^diff=first release' '$D1/RELEASE.txt'"
check "LATEST = t-rel1" bash -c "[ \"\$(cat '$ROOT/client/LATEST')\" = t-rel1 ]"
check "worktree removed after release" bash -c "! git -C '$C' worktree list | grep -q .stage-"
nope "existing release not overwritten" "$RS" --type client --tag t-rel1 --root "$ROOT" --prev none
check "second release diffs against LATEST" "$RS" --type client --tag t-rel2 --root "$ROOT"
D2="$ROOT/client/t-rel2"
check "diff file written, marked differs" bash -c "test -s '$D2/diff-vs-t-rel1.txt' && grep -q '^previous=t-rel1$' '$D2/RELEASE.txt' && grep -q '^diff=differs from t-rel1' '$D2/RELEASE.txt'"
check "LATEST = t-rel2" bash -c "[ \"\$(cat '$ROOT/client/LATEST')\" = t-rel2 ]"
git -C "$C" -c user.name=t -c user.email=t@t tag -a t-rel3 -m r3 "t-rel2^{commit}"
check "same content -> identical" bash -c "'$RS' --type client --tag t-rel3 --root '$ROOT' --prev t-rel2 && grep -q '^diff=identical content to t-rel2' '$ROOT/client/t-rel3/RELEASE.txt'"
nope "missing previous release refused" "$RS" --type client --tag t-rel3 --root "$W/r2" --prev t-rel9
git -C "$C" -c user.name=t -c user.email=t@t tag -a t-fail -m f "t-rel2^{commit}"
MOCK_FAIL=1 "$RS" --type client --tag t-fail --root "$ROOT" --prev none >/dev/null 2>&1; rc=$?
check "failed build exits non-zero" test "$rc" != 0
check "failed build leaves no release folder, LATEST unchanged" bash -c "[ ! -e '$ROOT/client/t-fail' ] && [ \"\$(cat '$ROOT/client/LATEST')\" = t-rel3 ] && ls -d '$ROOT'/client/.stage-t-fail.*.failed-*"
git -C "$C" -c user.name=t -c user.email=t@t tag -a t-dev -m d "t-rel2^{commit}"
RELEASE_BUILD_CMD='echo x > "$RELEASE_OUT/idea-client-26.04-x-abc-dev.img.xz"' "$RS" --type client --tag t-dev --root "$ROOT" --prev none >/dev/null 2>&1; rc=$?
check "dev-stamped image refused" bash -c "[ $rc != 0 ] && [ ! -e '$ROOT/client/t-dev' ]"
# --proof (non-main ref): separate folder, stamped, never LATEST, never --prev, REPRO_MAIN_REF reaches the build
git -C "$C" -c user.name=t -c user.email=t@t tag -a t-proof -m p "t-rel2^{commit}"
PROOFCMD=$RELEASE_BUILD_CMD'; [ "${REPRO_MAIN_REF:-}" = "$(git -C "$RELEASE_SRC" rev-parse HEAD)" ] && [ "$RELEASE_KIND" = proof ]'
check "proof build succeeds, REPRO_MAIN_REF=commit + RELEASE_KIND=proof reach the build" env RELEASE_BUILD_CMD="$PROOFCMD" "$RS" --type client --tag t-proof --root "$ROOT" --proof
DP="$ROOT/client/proof/t-proof"
check "proof stored under <type>/proof/, not as a release" bash -c "test -d '$DP' && [ ! -e '$ROOT/client/t-proof' ]"
check "proof stamped: kind=proof, NOT-FOR-FIELD.txt, image *-proof*, sha256 ok" bash -c "grep -q '^kind=proof$' '$DP/RELEASE.txt' && test -s '$DP/NOT-FOR-FIELD.txt' && ls '$DP'/idea-client-*-proof.img.xz && cd '$DP' && sha256sum -c --quiet idea-client-*-proof.img.xz.sha256"
check "proof does not move LATEST" bash -c "[ \"\$(cat '$ROOT/client/LATEST')\" = t-rel3 ]"
check "normal release is stamped kind=release" grep -q '^kind=release$' "$ROOT/client/t-rel3/RELEASE.txt"
nope "proof cannot be used as --prev" "$RS" --type client --tag t-rel2 --root "$W/r3" --prev proof/t-proof
nope "tag name 'proof' reserved" "$RS" --type client --tag proof --root "$ROOT" --prev none
check "without --proof the build gets no REPRO_MAIN_REF (even if the caller sets one)" env REPRO_MAIN_REF=HEAD bash -c "git -C '$C' -c user.name=t -c user.email=t@t tag -a t-np -m n 't-rel2^{commit}' && RELEASE_BUILD_CMD='$RELEASE_BUILD_CMD; [ -z \"\${REPRO_MAIN_REF:-}\" ] && [ \"\$RELEASE_KIND\" = release ]' '$RS' --type client --tag t-np --root '$W/r4' --prev none"
# router: content.tsv.xz from the build manifest, compare-manifest.sh
mk_router='n=$(git -C "$RELEASE_SRC" rev-parse --short HEAD); echo r > "$RELEASE_OUT/idea-router-1-$n-cudy-squashfs-sysupgrade.bin"; mkdir -p "$RELEASE_MANIFEST"; printf "%s\t/etc/r\n" "$(sha256sum < "$RELEASE_SRC/README.md" | cut -c1-64)" | xz > "$RELEASE_MANIFEST/content.tsv.xz"'
check "router first release" env RELEASE_BUILD_CMD="$mk_router" "$RS" --type router --tag t-rel1 --root "$ROOT" --prev none
check "router second release differs" bash -c "RELEASE_BUILD_CMD='$mk_router' '$RS' --type router --tag t-rel2 --root '$ROOT' && grep -q '^diff=differs from t-rel1' '$ROOT/router/t-rel2/RELEASE.txt' && test -s '$ROOT/router/t-rel2/diff-vs-t-rel1.txt'"
check "client and router LATEST separate" bash -c "[ \"\$(cat '$ROOT/router/LATEST')\" = t-rel2 ] && [ \"\$(cat '$ROOT/client/LATEST')\" = t-rel3 ]"
check "release.sh has no GitHub release / upload" bash -c "! grep -qE 'gh release|gh api|curl .*upload' '$R/release.sh'"
echo "release tests: $pass passed, $fail failed"; [ "$fail" = 0 ]
