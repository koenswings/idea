#!/usr/bin/env python3
"""content-manifest.py ROOT [VOLATILE_FILE] - content manifest of a file tree on stdout (idea#322).

One line per entry, sorted by path:  <type>\t<mode>\t<uid>:<gid>\t<content>\t/<path>
  type f (content = sha256), l (content = link target), d / other (content = -).
Volatile paths (volatile.txt globs) keep their line but content becomes "volatile".
/etc/shadow and /etc/gshadow are normalised (crypt hash field -> "<hash>"): salts are random per build.
With REPRO_NO_OWNER=1 the uid:gid column is "-" (router trees unpacked without root).
Read-only: never writes into ROOT. Skips proc/, sys/, dev/, run/ at the top level (live mounts in a build chroot).
"""
import fnmatch, hashlib, os, stat, sys

def main():
    if len(sys.argv) < 2:
        sys.exit("usage: content-manifest.py ROOT [VOLATILE_FILE]")
    root = sys.argv[1]
    vol = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "volatile.txt")
    globs = [l.strip() for l in open(vol) if l.strip() and not l.lstrip().startswith("#")]
    if not os.path.isdir(root):
        sys.exit(f"not a directory: {root}")
    no_owner = os.environ.get("REPRO_NO_OWNER") == "1"
    out = []
    for dp, dns, fns in os.walk(root):
        rel = os.path.relpath(dp, root)
        if rel == ".":
            dns[:] = [d for d in dns if d not in ("proc", "sys", "dev", "run")]
        for n in dns + fns:
            full = os.path.join(dp, n); p = os.path.normpath(os.path.join(rel, n)) if rel != "." else n
            st = os.lstat(full); m = st.st_mode
            t = "f" if stat.S_ISREG(m) else "l" if stat.S_ISLNK(m) else "d" if stat.S_ISDIR(m) else "o"
            if t == "o" and no_owner:
                continue  # device nodes are not created without root
            if any(fnmatch.fnmatchcase(p, g) for g in globs):
                c = "volatile"
            elif t == "f":
                if p in ("etc/shadow", "etc/gshadow"):
                    lines = []
                    for line in open(full, encoding="utf-8", errors="replace").read().splitlines():
                        f = line.split(":")
                        if len(f) > 1 and f[1].startswith("$"):
                            f[1] = "<hash>"
                        lines.append(":".join(f))
                    c = hashlib.sha256(("\n".join(lines) + "\n").encode()).hexdigest()
                else:
                    h = hashlib.sha256()
                    with open(full, "rb") as fh:
                        for b in iter(lambda: fh.read(1 << 20), b""):
                            h.update(b)
                    c = h.hexdigest()
            elif t == "l":
                c = os.readlink(full)
            else:
                c = "-"
            out.append((p, f"{t}\t{stat.S_IMODE(m):o}\t{"-" if no_owner else f"{st.st_uid}:{st.st_gid}"}\t{c}\t/{p}"))
    out.sort(key=lambda x: x[0].encode())
    sys.stdout.write("".join(l + "\n" for _, l in out))

if __name__ == "__main__":
    main()
