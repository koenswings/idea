#!/usr/bin/env python3
"""compare-record.py - compare two deployment record directories (idea-deployment-record/1, idea#322).

Usage: compare-record.py EXPECTED_DIR ACTUAL_DIR [--volatile tools/repro/volatile.txt] [--ignore-path P ...]
       compare-record.py --check DIR        (schema/required keys + engine contentSha256 consistency)
Shared by clients, routers and Engines (agent-engine-dev uses this copy). Rules:
  record.txt     key=value; keys listed as "key:<name>" in volatile.txt are skipped; UNKNOWN on either side never differs
  packages.tsv   package<TAB>version<TAB>arch  (keyed by package:arch)
  images.tsv     ref<TAB>image id<TAB>digests  (keyed by ref)
  files.sha256 / dist.sha256   sha256sum lines (keyed by path; --ignore-path exact or prefix ending in /)
A sidecar is compared only when the EXPECTED side has it; missing on the actual side is a difference.
Exit 0 = content-identical, 1 = differences (printed), 2 = usage error.
"""
import hashlib, os, sys

SIDECARS = ["packages.tsv", "images.tsv", "files.sha256", "dist.sha256"]
REQUIRED = ["schema", "batch", "deviceType", "arch", "model", "osRelease", "imageCommit", "imageBranch", "imageTag",
            "imageVersion", "packageArchive", "packageArchiveSha256", "packageArchiveUrl", "secrets", "deployedAt", "evidence", "confidence", "open"]
SCHEMA = "idea-deployment-record/1"
DEVICE_TYPES = {"client", "router", "engine"}

def lines(path):
    with open(path, encoding="utf-8") as f:
        return [l.rstrip("\r\n") for l in f if l.strip() and not l.startswith("#")]

def kv(path):
    d = {}
    for l in lines(path):
        if "=" in l:
            k, v = l.split("=", 1); d[k.strip()] = v.strip()
    return d

def volatile_keys(path):
    return {l[4:].strip() for l in lines(path) if l.startswith("key:")}

def sidecar_map(name, path):
    m = {}
    for l in lines(path):
        if name == "packages.tsv":
            p = l.split("\t"); m[f"{p[0]}:{p[2]}" if len(p) > 2 and p[2] else p[0]] = p[1] if len(p) > 1 else ""
        elif name == "images.tsv":
            p = l.split("\t", 1); m[p[0]] = p[1] if len(p) > 1 else ""
        else:
            h, _, p = l.partition("  "); m[p.lstrip("*")] = h
    return m

def unknown(v):
    return v is not None and v.split(" ")[0] == "UNKNOWN"

def diff_maps(label, e, a, skip=lambda k: False):
    out = []
    for k in sorted(set(e) | set(a)):
        if skip(k) or unknown(e.get(k)) or unknown(a.get(k)):
            continue
        if e.get(k) != a.get(k):
            out.append(f"{label}: {k}: expected {e.get(k)!r} actual {a.get(k)!r}")
    return out

def content_sha256(d):
    h = hashlib.sha256()
    for f in ("files.sha256", "dist.sha256"):   # = cat files.sha256 dist.sha256 | sha256sum (capture-engine-record.sh)
        p = os.path.join(d, f)
        if os.path.exists(p):
            h.update(open(p, "rb").read())
    return h.hexdigest()

def check(d):
    errs = []; r = kv(os.path.join(d, "record.txt"))
    errs += [f"missing {k}" for k in REQUIRED if k not in r]
    if r.get("schema") != SCHEMA: errs.append(f"schema is {r.get('schema')}")
    if r.get("deviceType") not in DEVICE_TYPES: errs.append(f"deviceType {r.get('deviceType')} not in {sorted(DEVICE_TYPES)}")
    if not (r.get("hostname") or r.get("stickerName") or r.get("cardId")): errs.append("missing hostname/stickerName/cardId")
    if r.get("deviceType") == "engine":
        for k in ("imageFile", "imageSha256", "imageManifest"):
            if r.get(k, "n/a") != "n/a": errs.append(f"{k} must be n/a for an engine")
        cs = r.get("contentSha256", "UNKNOWN")
        if not unknown(cs) and os.path.exists(os.path.join(d, "files.sha256")) and cs != content_sha256(d):
            errs.append("contentSha256 != sha256(files.sha256 + dist.sha256)")
    p = os.path.join(d, "packages.tsv")
    if os.path.exists(p):
        bad = [l for l in lines(p) if len(l.split("\t")) != 3]
        if bad: errs.append(f"packages.tsv: {len(bad)} lines without 3 tab-separated columns")
    return errs

def main(argv):
    vol = os.path.join(os.path.dirname(os.path.abspath(__file__)), "volatile.txt"); ign = []; pos = []
    it = iter(argv)
    for x in it:
        if x == "--volatile": vol = next(it)
        elif x == "--ignore-path": ign.append(next(it))
        else: pos.append(x)
    if len(pos) == 2 and pos[0] == "--check":
        errs = check(pos[1]); print("\n".join(errs) if errs else f"record ok: {pos[1]}"); return 1 if errs else 0
    if len(pos) != 2:
        print(__doc__, file=sys.stderr); return 2
    e, a = pos; vk = volatile_keys(vol); out = []
    out += diff_maps("record.txt", kv(os.path.join(e, "record.txt")), kv(os.path.join(a, "record.txt")), lambda k: k in vk)
    pi = lambda k: any(k.startswith(p) if p.endswith("/") else k == p for p in ign)
    for s in SIDECARS:
        pe, pa = os.path.join(e, s), os.path.join(a, s)
        if not os.path.exists(pe): continue
        if not os.path.exists(pa): out.append(f"{s}: missing on actual side"); continue
        out += diff_maps(s, sidecar_map(s, pe), sidecar_map(s, pa), pi if s.endswith(".sha256") else (lambda k: False))
    if out:
        print(f"RECORDS DIFFER: {len(out)}"); print("\n".join(out[:300])); return 1
    print("records content-identical"); return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
