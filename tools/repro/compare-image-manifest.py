#!/usr/bin/env python3
"""compare-image-manifest.py EXPECTED ACTUAL [--max N] [--ignore GLOB ...] - compare two v2 image manifests (idea#322).

Manifests from image-manifest.py (plain or .xz). Entries are keyed by (partition, path); for each key present
on both sides the differing fields are named (type, mode, owner, size, content, rdev). Output:
  summary per partition (added / removed / changed, and which fields), then up to N detail lines per class.
--ignore GLOB drops paths (fnmatch on "/path") from both sides, for ad-hoc triage only; the committed
normalisation lives in volatile.txt / secret.txt so every run uses the same rules.
Exit 0 = content-identical, 1 = differs, 2 = usage / format error.
"""
import fnmatch, lzma, sys
from collections import Counter, defaultdict

FIELDS = ("type", "mode", "owner", "size", "content", "rdev")

def load(path, ignore):
    op = lzma.open if path.endswith(".xz") else open
    d = {}
    with op(path, "rt", encoding="utf-8") as fh:
        first = fh.readline()
        if not first.startswith("#idea-image-manifest/2"):
            sys.stderr.write(f"{path}: not a v2 image manifest\n"); sys.exit(2)
        for line in fh:
            if not line.strip() or line.startswith("#"):
                continue
            f = line.rstrip("\n").split("\t")
            if len(f) != 8:
                sys.stderr.write(f"{path}: bad line: {line[:120]}"); sys.exit(2)
            if any(fnmatch.fnmatchcase(f[7], g) for g in ignore):
                continue
            key = (f[0], f[7]) if f[1] != "P" else (f[0], f[7] + ":" + f[5].split("=", 1)[0])
            d[key] = f[1:7]
    return d

def main(a):
    mx, ignore, files = 40, [], []
    i = 0
    while i < len(a):
        if a[i] == "--max": mx = int(a[i + 1]); i += 2
        elif a[i] == "--ignore": ignore.append(a[i + 1]); i += 2
        elif a[i].startswith("-"): print(__doc__); sys.exit(2)
        else: files.append(a[i]); i += 1
    if len(files) != 2:
        print(__doc__); sys.exit(2)
    e, r = load(files[0], ignore), load(files[1], ignore)
    added = sorted(k for k in r if k not in e); removed = sorted(k for k in e if k not in r)
    changed = []
    for k in sorted(k for k in e if k in r and e[k] != r[k]):
        changed.append((k, [FIELDS[j] for j in range(6) if e[k][j] != r[k][j]]))
    if not (added or removed or changed):
        print(f"IMAGE MANIFEST MATCH: {len(e)} entries content-identical"); return 0
    per = defaultdict(Counter)
    for k in added: per[k[0]]["added"] += 1
    for k in removed: per[k[0]]["removed"] += 1
    for k, fs in changed:
        per[k[0]]["changed"] += 1
        for f in fs: per[k[0]]["field:" + f] += 1
    print(f"IMAGE MANIFEST DIFFERS: {len(added)} added, {len(removed)} removed, {len(changed)} changed")
    for p in sorted(per):
        c = per[p]; fl = ", ".join(f"{k[6:]} {v}" for k, v in sorted(c.items()) if k.startswith("field:"))
        print(f"  {p}: +{c['added']} -{c['removed']} ~{c['changed']}" + (f" ({fl})" if fl else ""))
    def show(title, items, fmt):
        if items:
            print(f"-- {title} ({len(items)}{', first ' + str(mx) if len(items) > mx else ''})")
            for it in items[:mx]: print("  " + fmt(it))
    show("added", added, lambda k: f"+ {k[0]} {k[1]}  {' '.join(r[k][:5])}")
    show("removed", removed, lambda k: f"- {k[0]} {k[1]}  {' '.join(e[k][:5])}")
    def ch(it):
        k, fs = it
        return f"~ {k[0]} {k[1]}  " + "; ".join(f"{f}: {e[k][FIELDS.index(f)]} -> {r[k][FIELDS.index(f)]}" for f in fs)
    show("changed", changed, ch)
    return 1

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
