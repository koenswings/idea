#!/bin/bash
# idea#322: shrink-image.sh replaces s16's hand shrink to 14 GB. Plan tests need no root; the fixture-image test
# (tiny 2-partition image, loop device) runs only when passwordless sudo is available, else it is reported as skipped.
set -u; H="$(cd "$(dirname "$0")/.." && pwd)"; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; f=0; n=0; s=0
ok(){ echo "ok:   $*"; n=$((n+1)); }; bad(){ echo "FAIL: $*"; f=1; }
S="$H/shrink-image.sh"; export MAX_IMAGE_BYTES=14000000000 ROOT_FREE_MB=3072 ROOT_FREE_MIN_MB=2048
# 1. s16 numbers (build-full.log: needs 3395276 blocks with +3072M > cap 3286640); O2 of the s16 image
O2=537919488; MINB=$(( 3395276 - 3072*256 ))
r=$("$S" --plan "$MINB" 4096 "$O2"); [ "$r" = "3286640 cap" ] && ok "s16: +3072M does not fit -> cut to cap" || bad "s16 plan '$r'"
[ $(( O2 + 3286640*4096 )) = 13999996928 ] && ok "s16: scripted size = s16 image size 13,999,996,928" || bad "s16 size"
r=$("$S" --plan 1000000 4096 "$O2"); [ "$r" = "$((1000000+3072*256)) headroom" ] && ok "small root keeps +ROOT_FREE_MB" || bad "headroom '$r'"
"$S" --plan 3200000 4096 "$O2" 2>/dev/null && bad "accepted < ROOT_FREE_MIN_MB free" || ok "too little free space -> fails"
"$S" --plan 1 2 2>/dev/null; [ $? = 2 ] && ok "--plan usage error -> exit 2" || bad "usage"
"$S" "$T/nope.img" 2>/dev/null; [ $? = 2 ] && ok "missing image -> exit 2" || bad "missing image"
grep -q '"$HERE/shrink-image.sh" "$IMG"' "$H/build.sh" && ok "build.sh calls shrink-image.sh" || bad "build.sh wiring"
grep -q 'resize2fs "$L2" "$WANT"' "$H/build.sh" && bad "build.sh still has inline shrink" || ok "no inline shrink left in build.sh"
# 2. fixture image (root only)
if sudo -n true 2>/dev/null && PATH="$PATH:/usr/sbin:/sbin" command -v mkfs.ext4 parted sfdisk >/dev/null; then
  P="PATH=$PATH:/usr/sbin:/sbin"; I="$T/f.img"; truncate -s 200M "$I"
  sudo env "$P" parted -s "$I" mklabel msdos mkpart primary fat32 1MiB 9MiB mkpart primary ext4 9MiB 100% >/dev/null
  L=$(sudo losetup -f --show -o $((9*1024*1024)) --sizelimit $((191*1024*1024)) "$I")
  sudo env "$P" mkfs.ext4 -q -L writable -U 11111111-2222-3333-4444-555555555555 "$L"; sudo losetup -d "$L"
  out=$(sudo env "$P" MAX_IMAGE_BYTES=120000000 ROOT_FREE_MB=150 ROOT_FREE_MIN_MB=8 "$S" "$I" 2>&1) && ok "fixture shrink runs" || bad "fixture shrink: $out"
  sz=$(stat -c %s "$I"); [ "$sz" -le 120000000 ] && ok "fixture <= MAX_IMAGE_BYTES ($sz)" || bad "fixture size $sz"
  grep -q 'cap:' <<<"$out" && ok "fixture took the cap path" || bad "fixture mode: $out"
  L=$(sudo losetup -f --show -o $((9*1024*1024)) "$I"); u=$(sudo env "$P" blkid -s UUID -o value "$L"); sudo env "$P" e2fsck -fn "$L" >/dev/null 2>&1; e=$?; sudo losetup -d "$L"
  [ "$u" = 11111111-2222-3333-4444-555555555555 ] && ok "root UUID unchanged" || bad "UUID $u"; [ $e = 0 ] && ok "root fs clean after shrink" || bad "e2fsck $e"
  end=$(sudo env "$P" parted -sm "$I" unit B print | awk -F: '$1==2{sub("B","",$3);print $3}'); [ $((end+1)) = "$sz" ] && ok "partition 2 ends at file end" || bad "p2 end $end vs $sz"
else s=$((s+5)); echo "skip: fixture image tests (no passwordless sudo / e2fsprogs)"; fi
echo "shrink: $n passed, $f failed, $s skipped"; exit $f
