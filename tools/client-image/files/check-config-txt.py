#!/usr/bin/env python3
"""idea#202/#304 config.txt checks (run by verify-image.sh in the chroot, and by tests/config-txt.test.sh).
Usage: check-config-txt.py CONFIG_TXT   Prints one 'ok:'/'FAIL:' line per check; exit 1 on any FAIL."""
import sys, hashlib
# sha256 of every line in all [pi4] sections of s15 (291b962) config.txt, concatenated in order. [pi4] must not change (#304).
PI4_S15_SHA256 = "4c7ca35c6133850e70899e013a99a915a0c730952b20cafdf130bf7c6fdf6e2b"
USB = "usb_max_current_enable=1"
sec = "all"; body = {}; kms = {}; fwkms = False; usb = {}
for raw in open(sys.argv[1], newline=""):
    l = raw.strip()
    if l.startswith("[") and l.endswith("]"): sec = l[1:-1]
    body[sec] = body.get(sec, "") + raw
    if l.startswith("dtoverlay=vc4-kms-v3d"): kms.setdefault(sec, []).append(l)
    if l == "disable_fw_kms_setup=1": fwkms = True
    if l.replace(" ", "").startswith("usb_max_current_enable"): usb.setdefault(sec, []).append(l)
res = []
def chk(c, m): res.append(c); print(("ok:   " if c else "FAIL: ") + m)
chk("dtoverlay=vc4-kms-v3d" not in kms.get("all", []) and kms.get("pi4") == ["dtoverlay=vc4-kms-v3d"]
    and kms.get("pi5") == ["dtoverlay=vc4-kms-v3d-pi5"] and fwkms,
    "config.txt: [pi4] vc4-kms-v3d + [pi5] vc4-kms-v3d-pi5, none in [all], disable_fw_kms_setup=1")
chk(usb.get("pi5") == [USB], "config.txt: %s in [pi5] (idea#304), got %s" % (USB, usb.get("pi5")))
other = {k: v for k, v in usb.items() if k != "pi5"}
chk(not other, "config.txt: usb_max_current_enable in no other section, got %s" % (other or "none"))
h = hashlib.sha256(body.get("pi4", "").encode()).hexdigest()
chk(h == PI4_S15_SHA256, "config.txt: [pi4] byte-identical to s15 (sha256 %s)" % h[:12])
sys.exit(0 if all(res) else 1)
