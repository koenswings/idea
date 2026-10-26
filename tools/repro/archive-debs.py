#!/usr/bin/env python3
"""archive-debs.py - download the exact .deb versions named in a package manifest and archive them with sha256 (idea#322).

Usage: archive-debs.py --manifest PKGLIST.txt --out DIR [--mirror URL] [--suite S ...] [--arch arm64] [--index-only]
PKGLIST: lines "<package>\t<version>" (dpkg-query -W -f='${Package}\t${Version}\n'), e.g. manifests/client/*/packages.tsv.
Writes DIR/<file>.deb, DIR/SHA256SUMS (our own hash of what we stored), DIR/index.tsv
(package, version, arch, mirror filename, archive sha256 from Packages, status) and DIR/missing.tsv.
Every downloaded file is checked against the mirror's Packages SHA256; a mismatch is fatal.
Packages not installed from a mirror (e.g. google-chrome-stable from a pinned .deb) appear in missing.tsv.
"""
import argparse, gzip, hashlib, json, lzma, os, sys, urllib.parse, urllib.request

def fetch(url, timeout=120):
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return r.read()

def parse_packages(text):
    for stanza in text.split("\n\n"):
        d = {}
        for line in stanza.splitlines():
            if line and not line[0].isspace() and ":" in line:
                k, v = line.split(":", 1); d[k] = v.strip()
        if "Package" in d:
            yield d

def load_index(mirror, suites, comps, arch):
    idx = {}
    for s in suites:
        for c in comps:
            for a in (arch, "all"):
                base = f"{mirror}/dists/{s}/{c}/binary-{a}/Packages"
                data = None
                for ext, dec in ((".xz", lzma.decompress), (".gz", gzip.decompress)):
                    try:
                        data = dec(fetch(base + ext)).decode("utf-8", "replace"); break
                    except Exception:
                        continue
                if data is None:
                    continue
                for d in parse_packages(data):
                    idx.setdefault((d["Package"], d.get("Version", "")), d)
    return idx

LP = "https://api.launchpad.net/devel/ubuntu/+archive/primary"

def launchpad_lookup(pkg, ver, arch, series):
    """Superseded versions drop out of the mirror's Packages; Launchpad keeps them with their sha256."""
    q = urllib.parse.urlencode({"ws.op": "getPublishedBinaries", "binary_name": pkg, "version": ver, "exact_match": "true"})
    for e in json.loads(fetch(f"{LP}?{q}"))["entries"]:
        das = e.get("distro_arch_series_link", "")
        if not das.endswith(f"/{series}/{arch}") and not (e.get("architecture_specific") is False and f"/{series}/" in das):
            continue
        meta = json.loads(fetch(e["self_link"] + "?ws.op=binaryFileUrls&include_meta=true"))
        for m in meta:
            if m["url"].endswith(".deb") and m.get("sha256"):
                return {"Filename": m["url"], "SHA256": m["sha256"], "Architecture": "all" if m["url"].endswith("_all.deb") else arch}
    return None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", required=True); ap.add_argument("--out", required=True)
    ap.add_argument("--mirror", default="https://ports.ubuntu.com/ubuntu-ports")
    ap.add_argument("--suite", action="append"); ap.add_argument("--comp", action="append")
    ap.add_argument("--arch", default="arm64"); ap.add_argument("--index-only", action="store_true")
    ap.add_argument("--launchpad", action="store_true", help="look up versions missing from the mirror on Launchpad (sha256 from its API)")
    ap.add_argument("--series", default="resolute")
    a = ap.parse_args()
    suites = a.suite or ["resolute", "resolute-updates", "resolute-security"]
    comps = a.comp or ["main", "restricted", "universe", "multiverse"]
    want = []
    for line in open(a.manifest):
        p = line.rstrip("\n").split("\t")
        if len(p) >= 2 and p[0] and not p[0].startswith("#"):
            want.append((p[0].split(":")[0], p[1]))
    os.makedirs(a.out, exist_ok=True)
    idx = load_index(a.mirror, suites, comps, a.arch)
    if not idx:
        sys.exit("no package index could be read from " + a.mirror)
    rows, missing, sums = [], [], []
    for pkg, ver in want:
        d = idx.get((pkg, ver)); src = "mirror"
        if not d and a.launchpad:
            try:
                d = launchpad_lookup(pkg, ver, a.arch, a.series); src = "launchpad"
            except Exception as ex:
                print(f"launchpad lookup failed for {pkg} {ver}: {ex}", file=sys.stderr)
        if not d:
            missing.append(f"{pkg}\t{ver}\tnot in {a.mirror} {' '.join(suites)}"); continue
        fn = d["Filename"]; exp = d.get("SHA256", ""); dest = os.path.join(a.out, os.path.basename(fn))
        status = "indexed"
        if not a.index_only:
            if not (os.path.exists(dest) and hashlib.sha256(open(dest, "rb").read()).hexdigest() == exp):
                blob = fetch(fn if src == "launchpad" else f"{a.mirror}/{fn}", timeout=600)
                got = hashlib.sha256(blob).hexdigest()
                if got != exp:
                    sys.exit(f"sha256 mismatch for {fn}: got {got} expected {exp}")
                with open(dest + ".part", "wb") as f:
                    f.write(blob)
                os.replace(dest + ".part", dest)
            sums.append(f"{exp}  {os.path.basename(fn)}"); status = "archived" if src == "mirror" else "archived-launchpad"
        rows.append(f"{pkg}\t{ver}\t{d.get('Architecture','')}\t{fn}\t{exp}\t{status}")
    open(os.path.join(a.out, "index.tsv"), "w").write("package\tversion\tarch\tfilename\tsha256\tstatus\n" + "\n".join(rows) + "\n")
    open(os.path.join(a.out, "missing.tsv"), "w").write("\n".join(missing) + ("\n" if missing else ""))
    if sums:
        open(os.path.join(a.out, "SHA256SUMS"), "w").write("\n".join(sorted(sums)) + "\n")
    print(f"wanted={len(want)} found={len(rows)} missing={len(missing)} out={a.out}")

if __name__ == "__main__":
    main()
