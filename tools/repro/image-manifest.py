#!/usr/bin/env python3
"""image-manifest.py - content manifest v2 of one or more partition trees (idea#322).

Usage: image-manifest.py [--layout FILE] [--volatile FILE] [--secret FILE] [--no-owner] NAME=[fat:]DIR [...]
  fat:DIR = a FAT partition copied out with mtools: mode and owner columns are "-" (FAT has neither).

One line per entry, TAB separated, sorted by (partition, path):
  part  type  mode  uid:gid  size  content  rdev  /path
  type: f file (content = sha256), l symlink (content = target), d dir, c/b device (rdev = major:minor),
        p fifo, s socket.  size: bytes for f, "-" otherwise.
Normalised / excluded (never compared, so content-identical rebuilds match):
  - timestamps (atime/mtime/ctime are never read), inode numbers, link counts, directory sizes;
  - omit:GLOB entries in image-volatile.txt (random mktemp names): no line at all;
  - volatile paths (volatile.txt + image-volatile.txt): line kept so a missing/extra file is caught, size+content -> "volatile";
  - secret paths (secret.txt): content hashed after normalisation, or "secret"; secrets never appear in output.
--layout FILE adds partition-table lines (written by image-manifest.sh, from sfdisk/blkid): part "-", type "P".
Read-only: never writes into a DIR. Directories that are mount points (proc/, sys/ of a live chroot) are not descended.
"""
import fnmatch, hashlib, os, re, stat, sys

HERE = os.path.dirname(os.path.abspath(__file__))
KEYVAL = re.compile(r'^(\s*(?:psk|password|wep-key\d*|private-key-password|leap-password|key|secret)\s*[=\s]\s*)(.*)$', re.I)

def load_globs(path, secret=False):
    out = []
    for line in open(path, encoding="utf-8"):
        line = line.split("#", 1)[0].strip() if line.lstrip().startswith("#") else line.strip()
        if not line or line.startswith("key:"):
            continue
        parts = line.split()
        if not secret and parts[0].startswith("omit:"):
            out.append((parts[0][5:], "omit")); continue
        norm = parts[1][5:] if secret and len(parts) > 1 and parts[1].startswith("norm:") else None
        out.append((parts[0], norm))
    return out

def sha_file(full):
    h = hashlib.sha256()
    with open(full, "rb") as fh:
        for b in iter(lambda: fh.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()

def norm_text(full, how):
    text = open(full, encoding="utf-8", errors="replace").read().splitlines()
    out = []
    for line in text:
        if how == "shadow":
            f = line.split(":")
            if len(f) > 1 and f[1] not in ("", "*", "!", "!!", "!*", "x"):
                f[1] = "<hash>"
            if len(f) > 2 and full.endswith("/shadow") and f[2].isdigit():
                f[2] = "<lastchg>"  # days since epoch of the build: a timestamp
            line = ":".join(f)
        elif how == "keyval":
            m = KEYVAL.match(line)
            if m:
                line = m.group(1) + "<secret>"
        out.append(line)
    return "sha256n:" + hashlib.sha256(("\n".join(out) + "\n").encode()).hexdigest()

def match(p, globs):
    for g, n in globs:
        if fnmatch.fnmatchcase(p, g):
            return True, n
    return False, None

def walk(part, root, vol, sec, no_owner, fat=False):
    out = []
    for dp, dns, fns in os.walk(root):
        rel = os.path.relpath(dp, root)
        if rel == ".":
            dns[:] = [d for d in dns if not os.path.ismount(os.path.join(dp, d))]
        dns.sort(); fns.sort()
        for n in dns + fns:
            full = os.path.join(dp, n)
            p = n if rel == "." else os.path.join(rel, n)
            st = os.lstat(full); m = st.st_mode
            t = ("f" if stat.S_ISREG(m) else "l" if stat.S_ISLNK(m) else "d" if stat.S_ISDIR(m) else
                 "c" if stat.S_ISCHR(m) else "b" if stat.S_ISBLK(m) else "p" if stat.S_ISFIFO(m) else "s")
            size, rdev = "-", "-"
            if t in ("c", "b"):
                rdev = f"{os.major(st.st_rdev)}:{os.minor(st.st_rdev)}"
            is_vol, how_v = match(p, vol)
            if how_v == "omit":
                continue  # random file NAME (mktemp): the entry itself is not reproducible
            is_sec, how = match(p, sec)
            if is_vol:
                c = "volatile"
            elif t == "f":
                size = str(st.st_size)
                if is_sec:
                    c = norm_text(full, how) if how else "secret"
                    size = "-"  # length of a secret-bearing file is not recorded either
                else:
                    c = sha_file(full)
            elif t == "l":
                c = "secret" if is_sec else os.readlink(full)
            else:
                c = "-"
            own = "-" if no_owner else f"{st.st_uid}:{st.st_gid}"
            out.append(((part, p.encode()), "\t".join([part, t, "-" if fat else f"{stat.S_IMODE(m):o}", own, size, c, rdev, "/" + p])))
    return out

def main(argv):
    vol_f = os.path.join(HERE, "volatile.txt"); sec_f = os.path.join(HERE, "secret.txt")
    layout = None; no_owner = os.environ.get("REPRO_NO_OWNER") == "1"; parts = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--layout", "--volatile", "--secret"):
            v = argv[i + 1]; i += 2
            if a == "--layout": layout = v
            elif a == "--volatile": vol_f = v
            else: sec_f = v
            continue
        if a == "--no-owner":
            no_owner = True; i += 1; continue
        if "=" not in a or a.startswith("-"):
            sys.exit(__doc__)
        name, d = a.split("=", 1)
        fat = d.startswith("fat:")
        d = d[4:] if fat else d
        if not os.path.isdir(d):
            sys.exit(f"not a directory: {d}")
        parts.append((name, d, fat)); i += 1
    if not parts:
        sys.exit(__doc__)
    vol = load_globs(vol_f)
    extra = os.path.join(os.path.dirname(os.path.abspath(vol_f)), "image-volatile.txt")
    if os.path.exists(extra):
        vol += load_globs(extra)
    sec = load_globs(sec_f, secret=True)
    w = sys.stdout.write
    w("#idea-image-manifest/2\tpart\ttype\tmode\towner\tsize\tcontent\trdev\tpath\n")
    if layout:
        for line in open(layout, encoding="utf-8"):
            if line.strip():
                w(line.rstrip("\n") + "\n")
    rows = []
    for name, d, fat in parts:
        rows += walk(name, d, vol, sec, no_owner or fat, fat)
    rows.sort(key=lambda r: r[0])
    w("".join(r[1] + "\n" for r in rows))

if __name__ == "__main__":
    main(sys.argv[1:])
