#!/usr/bin/env bash
# identity-flash.test.sh - offline tests for idea-identity.sh, identity-lib.sh and idea-flash.sh (idea#322).
# Temp identity dir + temp zoneinfo + a regular file as "device" (IDEA_FLASH_ALLOW_FILE) and a dir as its boot
# partition (IDEA_FLASH_MOUNT). No root, no real card, no real key. Usage: tools/identity/tests/identity-flash.test.sh
set -uo pipefail
D=$(cd "$(dirname "$0")/.." && pwd); REPO=$(cd "$D/../.." && pwd)
pass=0; fail=0
check() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS $n"; pass=$((pass+1)); else echo "FAIL $n"; fail=$((fail+1)); fi; }
nope() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "FAIL $n (expected failure)"; fail=$((fail+1)); else echo "PASS $n"; pass=$((pass+1)); fi; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
export HOME="$W/home"; mkdir -p "$HOME"; export IDEA_IDENTITY_DIR="$HOME/.config/idea-identities"
export IDEA_ZONEINFO="$W/zi"; mkdir -p "$IDEA_ZONEINFO/Africa"; for z in Africa/Harare Africa/Lusaka UTC; do printf 'TZif2fake' > "$IDEA_ZONEINFO/$z"; done
ID="$D/idea-identity.sh"; FL="$D/idea-flash.sh"
KEY="$HOME/.config/idea-identities/keys/ts.key"; mkdir -p "$(dirname "$KEY")"; FAKEKEY="tskey-auth-TESTONLY$RANDOM$RANDOM"
printf '%s\n' "$FAKEKEY" > "$KEY"; chmod 600 "$KEY"
# --- identity files
check "new identity" "$ID" new --name idea-pc-5b4c --timezone Africa/Harare --home idea01 --tailscale-key-ref "$KEY"
F="$IDEA_IDENTITY_DIR/idea-pc-5b4c.identity"
check "identity file mode 0600" bash -c "[ \$(stat -c %a '$F') = 600 ]"
check "identity dir mode 0700" bash -c "[ \$(stat -c %a '$IDEA_IDENTITY_DIR') = 700 ]"
check "identity holds key reference, not key" bash -c "grep -q '^TAILSCALE_KEY_REF=$KEY\$' '$F' && ! grep -q tskey- '$F'"
check "check ok" "$ID" check idea-pc-5b4c
check "show never prints the key" bash -c "out=\$('$ID' show idea-pc-5b4c 2>&1); ! grep -q '$FAKEKEY' <<<\"\$out\" && grep -q '^tailscale_key=set' <<<\"\$out\""
check "list" bash -c "[ \"\$('$ID' list)\" = idea-pc-5b4c ]"
nope "never overwrites" "$ID" new --name idea-pc-5b4c --timezone UTC
nope "raw key as reference refused" "$ID" new --name x1 --timezone UTC --tailscale-key-ref "$FAKEKEY"
nope "bad name refused" "$ID" new --name 'Bad_Name' --timezone UTC
nope "bad zone refused" "$ID" new --name x2 --timezone Africa/Nowhere
nope "path-traversal zone refused" "$ID" new --name x3 --timezone ../../etc/passwd
nope "bad home refused" "$ID" new --name x4 --timezone UTC --home 'a b'
chmod 644 "$KEY"; nope "key file not 0600 refused" "$ID" new --name x5 --timezone UTC --tailscale-key-ref "$KEY"; chmod 600 "$KEY"
check "router identity, no key" "$ID" new --name idea-router-3 --type router --timezone UTC
chmod 644 "$F"; nope "identity not 0600 refused" "$ID" check idea-pc-5b4c; chmod 600 "$F"
cp "$F" "$W/raw.identity"; echo "TAILSCALE_KEY=$FAKEKEY" >> "$W/raw.identity"; chmod 600 "$W/raw.identity"
nope "identity with raw key refused (and key not echoed)" "$ID" check "$W/raw.identity"
check "refusal message does not echo key" bash -c "! '$ID' check '$W/raw.identity' 2>&1 | grep -q '$FAKEKEY'"
printf 'IDEA_IDENTITY=1\nTYPE=client\nNAME=a\nTIMEZONE=UTC\nHOME_MODE=none\nTAILSCALE_KEY_REF=none\nEVIL=$(touch %s/pwned)\n' "$W" > "$W/evil.identity"; chmod 600 "$W/evil.identity"
nope "unknown key refused" "$ID" check "$W/evil.identity"
check "identity is parsed, never sourced" test ! -e "$W/pwned"
git init -q "$W/gitrepo"; cp "$F" "$W/gitrepo/x.identity"; chmod 600 "$W/gitrepo/x.identity"
nope "identity inside a git repo refused" "$ID" check "$W/gitrepo/x.identity"
# --- flash: identity onto a boot dir
B="$W/boot"; mkdir -p "$B"; : > "$B/config.txt"
check "flash --boot writes identity" "$FL" --boot "$B" --identity idea-pc-5b4c
check "boot: idea-timezone.txt (idea#208 pattern)" bash -c "[ \"\$(cat '$B/idea-timezone.txt')\" = Africa/Harare ]"
check "boot: idea-home.txt" bash -c "[ \"\$(cat '$B/idea-home.txt')\" = idea01 ]"
check "boot: idea-hostname.txt" bash -c "[ \"\$(cat '$B/idea-hostname.txt')\" = idea-pc-5b4c ]"
check "boot: tailscale key in idea-secrets" cmp "$KEY" "$B/idea-secrets/tailscale-authkey"
check "boot: idea-identity.txt has no key" bash -c "grep -q '^tailscale_key=set$' '$B/idea-identity.txt' && ! grep -q tskey- '$B/idea-identity.txt'"
check "flash output never prints the key" bash -c "! '$FL' --boot '$B' --identity idea-pc-5b4c 2>&1 | grep -q '$FAKEKEY'"
mkdir -p "$W/notboot"; nope "refuses dir without config.txt" "$FL" --boot "$W/notboot" --identity idea-pc-5b4c
nope "router identity refused by client flash" "$FL" --boot "$B" --identity idea-router-3
"$ID" new --name idea-pc-new1 --timezone Africa/Lusaka >/dev/null
B2="$W/boot2"; mkdir -p "$B2"; : > "$B2/config.txt"
check "home none -> empty idea-home.txt, no secrets dir" bash -c "'$FL' --boot '$B2' --identity idea-pc-new1 && [ ! -s '$B2/idea-home.txt' ] && [ ! -e '$B2/idea-secrets' ]"
# --- full flash onto a file "device"
IMG="$W/idea-client-26.04-20261029-abc1234.img"; head -c 65536 /dev/urandom > "$IMG"; xz -k "$IMG"; (cd "$W" && sha256sum "$(basename "$IMG").xz" > "$(basename "$IMG").xz.sha256")
DEV="$W/card.bin"; : > "$DEV"; B3="$W/boot3"; mkdir -p "$B3"; : > "$B3/config.txt"
export IDEA_FLASH_ALLOW_FILE=1 IDEA_FLASH_MOUNT="MNT='$B3'" IDEA_FLASH_UMOUNT=true
nope "full flash needs --yes" "$FL" --image "$IMG.xz" --device "$DEV" --identity idea-pc-5b4c
check "full flash (twin from saved identity)" "$FL" --image "$IMG.xz" --device "$DEV" --identity idea-pc-5b4c --yes
check "device holds the image bytes" cmp <(head -c 65536 "$DEV") "$IMG"
check "boot record has image sha256" grep -q "^image_sha256=$(sha256sum "$IMG.xz" | cut -d' ' -f1)$" "$B3/idea-identity.txt"
echo corrupt >> "$IMG.xz"; nope "image sha256 mismatch refused" "$FL" --image "$IMG.xz" --device "$DEV" --identity idea-pc-5b4c --yes
cp "$IMG" "$W/idea-client-26.04-x-dev.img"; nope "dev image refused" "$FL" --image "$W/idea-client-26.04-x-dev.img" --device "$DEV" --identity idea-pc-5b4c --yes
unset IDEA_FLASH_ALLOW_FILE; nope "regular file refused as device without test hook" "$FL" --image "$IMG" --device "$DEV" --identity idea-pc-5b4c --yes
nope "usage: --boot with --device" "$FL" --boot "$B" --device "$DEV" --identity idea-pc-5b4c
# --- first boot applies the flash-time name
FB="$REPO/tools/client-image/files/idea-firstboot"
check "idea-firstboot reads idea-hostname.txt" grep -q 'idea-hostname.txt' "$FB"
check "idea-firstboot removes idea-hostname.txt" grep -q 'rm -f "$H"' "$FB"
check "sh -n idea-firstboot" sh -n "$FB"
check "no identity files in the repo" bash -c "[ -z \"\$(git -C '$REPO' ls-files '*.identity')\" ]"
echo "identity/flash tests: $pass passed, $fail failed"; [ "$fail" = 0 ]
