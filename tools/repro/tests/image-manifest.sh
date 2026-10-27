#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2015  # fixtures use literal $; a && ok || no is intended
# tools/repro/tests/image-manifest.sh - tests for the v2 image manifest tools (idea#322). No network.
# Tree tests need no root. The image test builds a tiny 2-partition image (FAT + ext4) and needs sudo -n,
# mkfs.vfat, mkfs.ext4 and mtools; it is skipped (not failed) without them.
set -uo pipefail
R=$(cd "$(dirname "$0")/.." && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0; skip=""
ok(){ echo "PASS $1"; pass=$((pass+1)); }; no(){ echo "FAIL $1"; fail=$((fail+1)); }
t(){ local n="$1"; shift; if "$@" >"$T/out" 2>&1; then ok "$n"; else no "$n"; sed 's/^/   /' "$T/out" | head -20; fi; }
tf(){ local n="$1"; shift; if "$@" >"$T/out" 2>&1; then no "$n (expected failure)"; else ok "$n"; fi; }
M="$R/image-manifest.py"; C="$R/compare-image-manifest.py"
PSK='Sup3rSecretPsk!'

mk(){ rm -rf "$1"; mkdir -p "$1"/{etc/ssh,etc/NetworkManager/system-connections,usr/bin,var/log,var/lib/dracut/console-setup-dir/etc/console-setup,home/admin/.ssh}
  echo hello > "$1/usr/bin/tool"; chmod 755 "$1/usr/bin/tool"; ln -s tool "$1/usr/bin/alias"; mkfifo "$1/usr/bin/fifo"
  echo machine-1 > "$1/etc/machine-id"; echo key1 > "$1/etc/ssh/ssh_host_ed25519_key"; echo log1 > "$1/var/log/syslog"
  echo 'admin:$6$salt1$hash1:20000:0:99999:7:::' > "$1/etc/shadow"
  printf '[wifi-security]\nkey-mgmt=wpa-psk\npsk=%s\n' "$PSK" > "$1/etc/NetworkManager/system-connections/IDEA.nmconnection"
  echo 'ssh-ed25519 AAAA admin' > "$1/home/admin/.ssh/authorized_keys"
  echo kbd > "$1/var/lib/dracut/console-setup-dir/etc/console-setup/tmpkbd.AAAA"; }
A="$T/a"; B="$T/b"; mk "$A"; mk "$B"; mkdir -p "$T/fa" "$T/fb"; echo cfg > "$T/fa/config.txt"; cp "$T/fa/config.txt" "$T/fb/"
# B differs only in things that must be normalised away
echo machine-2 > "$B/etc/machine-id"; echo key2 > "$B/etc/ssh/ssh_host_ed25519_key"; echo log2 > "$B/var/log/syslog"
echo 'admin:$6$salt2$hash2:20391:0:99999:7:::' > "$B/etc/shadow"
mv "$B/var/lib/dracut/console-setup-dir/etc/console-setup/tmpkbd.AAAA" "$B/var/lib/dracut/console-setup-dir/etc/console-setup/tmpkbd.BBBB"
touch -d '2001-01-01' "$B/usr/bin/tool"
man(){ python3 "$M" --no-owner root="$1" boot=fat:"$2"; }
man "$A" "$T/fa" > "$T/a.tsv"; man "$B" "$T/fb" > "$T/b.tsv"
t "header is v2" grep -q '^#idea-image-manifest/2' "$T/a.tsv"
t "equivalent trees match (timestamps, machine-id, host keys, logs, shadow salt+lastchg, random tmpkbd.* name)" python3 "$C" "$T/a.tsv" "$T/b.tsv"
tf "omitted random-name file has no line" grep -q tmpkbd "$T/a.tsv"
t "file line has part, size and sha256" grep -qP "^root\tf\t755\t-\t6\t$(sha256sum "$A/usr/bin/tool" | cut -d' ' -f1)\t-\t/usr/bin/tool$" "$T/a.tsv"
t "symlink target recorded" grep -qP '^root\tl\t777\t-\t-\ttool\t-\t/usr/bin/alias$' "$T/a.tsv"
t "fifo recorded" grep -qP '^root\tp\t.*\t/usr/bin/fifo$' "$T/a.tsv"
t "fat partition has no mode/owner" grep -qP '^boot\tf\t-\t-\t4\t' "$T/a.tsv"
t "volatile keeps the line" grep -qP '\t-\tvolatile\t-\t/etc/machine-id$' "$T/a.tsv"
tf "PSK never appears in a manifest" grep -q "$PSK" "$T/a.tsv"
t "PSK file is normalised-hashed, size hidden" grep -qP '\t-\tsha256n:[0-9a-f]{64}\t-\t/etc/NetworkManager/system-connections/IDEA.nmconnection$' "$T/a.tsv"
tf "shadow hash never appears" grep -q 'hash1' "$T/a.tsv"
t "unknown-format secret file is omitted" grep -qP '\t-\tsecret\t-\t/home/admin/.ssh/authorized_keys$' "$T/a.tsv"
# a different PSK must not change the manifest (secrets are injected at flash time)
sed -i 's/^psk=.*/psk=other/' "$B/etc/NetworkManager/system-connections/IDEA.nmconnection"; man "$B" "$T/fb" > "$T/b2.tsv"
t "PSK value change is ignored" python3 "$C" "$T/a.tsv" "$T/b2.tsv"
# ... but a non-secret change in that file is caught
echo 'autoconnect=false' >> "$B/etc/NetworkManager/system-connections/IDEA.nmconnection"; man "$B" "$T/fb" > "$T/b3.tsv"
tf "non-secret change in a secret file is caught" python3 "$C" "$T/a.tsv" "$T/b3.tsv"
mk "$B"; echo changed > "$B/usr/bin/tool"; man "$B" "$T/fb" > "$T/b4.tsv"
tf "content change is caught" python3 "$C" "$T/a.tsv" "$T/b4.tsv"
grep -q 'content: ' "$T/out" && grep -q 'size: 6 -> 8' "$T/out" && ok "diff names the changed fields" || no "diff names the changed fields"
t "--ignore drops a path for triage" python3 "$C" --ignore /usr/bin/tool "$T/a.tsv" "$T/b4.tsv"
mk "$B"; chmod 700 "$B/usr/bin/tool"; man "$B" "$T/fb" > "$T/b5.tsv"
tf "mode change is caught" python3 "$C" "$T/a.tsv" "$T/b5.tsv"
mk "$B"; rm "$B/usr/bin/alias"; echo x > "$B/usr/bin/new"; man "$B" "$T/fb" > "$T/b6.tsv"
tf "added/removed files are caught" python3 "$C" "$T/a.tsv" "$T/b6.tsv"
grep -q '+0 -0' "$T/out" && no "added/removed counted" || ok "added/removed counted"
echo cfg2 > "$T/fb/config.txt"; mk "$B"; man "$B" "$T/fb" > "$T/b7.tsv"
tf "boot partition change is caught" python3 "$C" "$T/a.tsv" "$T/b7.tsv"
xz -k "$T/a.tsv"; t "compare reads .xz" python3 "$C" "$T/a.tsv.xz" "$T/a.tsv"
printf 'x\ty\n' > "$T/bad.tsv"; python3 "$C" "$T/bad.tsv" "$T/a.tsv" >/dev/null 2>&1; [ $? = 2 ] && ok "non-v2 input -> exit 2" || no "non-v2 input -> exit 2"
man "$A" "$T/fa" > "$T/a2.tsv"; t "generator is deterministic" cmp "$T/a.tsv" "$T/a2.tsv"

# --- tiny real image: partition table + FAT + ext4 via image-manifest.sh (needs sudo)
export PATH="$PATH:/usr/sbin:/sbin"
if sudo -n true 2>/dev/null && command -v mkfs.vfat >/dev/null && command -v mkfs.ext4 >/dev/null && command -v mcopy >/dev/null; then
  mkimg(){ local img="$1" uuid="$2"; truncate -s 40M "$img"
    printf 'label: dos\nstart=2048, size=16384, type=c, bootable\nstart=18432, type=83\n' | sfdisk -q "$img"
    truncate -s 8M "$T/p1"; mkfs.vfat -n system-boot "$T/p1" >/dev/null 2>&1; echo cfg | MTOOLS_SKIP_CHECK=1 mcopy -i "$T/p1" - ::/config.txt
    rm -rf "$T/r"; mkdir -p "$T/r/etc"; echo hi > "$T/r/etc/motd"; echo "m-$uuid" > "$T/r/etc/machine-id"
    truncate -s 20M "$T/p2"; mkfs.ext4 -q -F -L writable -U "$uuid" -d "$T/r" "$T/p2"
    dd if="$T/p1" of="$img" bs=512 seek=2048 conv=notrunc status=none; dd if="$T/p2" of="$img" bs=512 seek=18432 conv=notrunc status=none; }
  mkimg "$T/i1.img" 11111111-1111-1111-1111-111111111111; mkimg "$T/i2.img" 22222222-2222-2222-2222-222222222222
  t "image-manifest.sh on image 1" "$R/image-manifest.sh" "$T/i1.img" "$T/i1.tsv"
  "$R/image-manifest.sh" "$T/i2.img" "$T/i2.tsv" >/dev/null 2>&1
  t "partition table lines present" grep -qP '^p1\tP\t.*start=2048,size=16384,type=c,bootable' "$T/i1.tsv"
  t "filesystem lines present" grep -qP '^p2\tP\t.*fs=ext4,label=writable' "$T/i1.tsv"
  t "two images differing only in fs UUID + machine-id match" python3 "$C" "$T/i1.tsv" "$T/i2.tsv"
  xz -T1 -k "$T/i1.img"; t "image-manifest.sh reads .img.xz" "$R/image-manifest.sh" "$T/i1.img.xz" "$T/i1x.tsv"
  t ".img.xz gives the same manifest" cmp "$T/i1.tsv" "$T/i1x.tsv"
else echo "SKIP image tests (need sudo -n, mkfs.vfat, mkfs.ext4, mtools)"; skip=1; fi
echo "image-manifest tests: $pass passed, $fail failed${skip:+, image tests skipped=$skip}"; [ $fail = 0 ]
