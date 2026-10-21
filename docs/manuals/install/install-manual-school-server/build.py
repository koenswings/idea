#!/usr/bin/env python3
"""Build idea-field-install-manual-school-server-v<version>.pdf with the IDEA house style (docs/house-style).
Usage: python3 build.py      (regenerates the install diagrams too, via ../scripts/make-install-diagrams.py)
Fails if a 'to confirm' marker or a school-numbering leftover is in the source, a diagram or the PDF."""
import glob, os, re, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
def find_house_style(here):
    """docs/house-style, found via $IDEA_HOUSE_STYLE or by walking up to the repo's docs/."""
    p = os.environ.get("IDEA_HOUSE_STYLE")
    if p: return p
    d = here
    while d != os.path.dirname(d):
        c = os.path.join(d, "docs", "house-style")
        if os.path.isfile(os.path.join(c, "housestyle.py")): return c
        d = os.path.dirname(d)
    sys.exit("BUILD FAILED: docs/house-style not found; set IDEA_HOUSE_STYLE")
STATUS = re.compile(r"^\*\*Status:\*\*.*\n+", re.M)   # status line on top of each source; not printed

sys.path.insert(0, find_house_style(HERE))
import housestyle

NAME = "install-manual-school-server"
BAD = re.compile(r"to confirm|\bTODO\b|\bTBD\b|FIXME|10\.N\.|school-N|tag:school|idea<N>|school number\b", re.I)

def fail(msg, lines):
    sys.exit("BUILD FAILED: " + msg + ":\n" + "\n".join(lines))

subprocess.run([sys.executable, os.path.join(HERE, "..", "scripts", "make-install-diagrams.py")], check=True)
meta, body = housestyle.split_front_matter(open(os.path.join(HERE, NAME + ".md"), encoding="utf-8").read())
body = STATUS.sub("", body, count=1)
# @@INCLUDE path@@ pulls in a file (path relative to this folder), e.g. ../scripts/school-router-setup.sh
body = re.sub(r"@@INCLUDE (\S+)@@", lambda m: open(os.path.join(HERE, m.group(1))).read().rstrip(), body)
bad = [f"{NAME}.md:{i}: {l.strip()[:90]}" for i, l in enumerate(body.split("\n"), 1) if BAD.search(l)]
for svg in sorted(os.listdir(os.path.join(HERE, "diagrams"))):
    if svg.endswith(".svg") and BAD.search(open(os.path.join(HERE, "diagrams", svg)).read()):
        bad.append(f"diagrams/{svg}")
if bad: fail("markers left in source", bad)
m = re.search(r"Version (\d+(?:\.\d+)+)", meta.get("audience", ""))
if not m: sys.exit("BUILD FAILED: no 'Version X.Y' in the front matter audience line")
PDF = f"idea-field-install-manual-{NAME.removeprefix('install-manual-')}-v{m.group(1)}.pdf"
for old in glob.glob(os.path.join(HERE, "*.pdf")):
    if os.path.basename(old) != PDF: os.remove(old)   # old unversioned / older versions
out = os.path.join(HERE, PDF)
housestyle.build(body, meta, out, base_url=HERE, keep_html=False, note="")   # cover: version + date only (Koen review 21 Oct 2026)
txt = subprocess.run(["pdftotext", "-layout", out, "-"], capture_output=True, text=True, check=True).stdout
pages = txt.split("\f")
bad = [f"p{n}: {l.strip()[:90]}" for n, pg in enumerate(pages, 1) for l in pg.split("\n") if BAD.search(l) or "**" in l]
if bad: fail(f"markers in {PDF}", bad)
print("built", PDF, "pages:", len([p for p in pages if p.strip()]))
