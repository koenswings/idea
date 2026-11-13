#!/usr/bin/env python3
"""Build idea-school-handover-note-v<version>.pdf with the IDEA house style (docs/house-style).
Usage: python3 build.py
Fails if a 'to confirm' marker is left in the text or the PDF."""
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

NAME = "school-handover-note"
BAD = re.compile(r"to confirm|\bTODO\b|\bTBD\b|FIXME|lorem|placeholder|\[\?\]", re.I)

def fail(msg, lines):
    sys.exit("BUILD FAILED: " + msg + ":\n" + "\n".join(lines))

meta, body = housestyle.split_front_matter(open(os.path.join(HERE, NAME + ".md"), encoding="utf-8").read())
body = STATUS.sub("", body, count=1)
bad = [f"{NAME}.md:{i}: {l.strip()[:90]}" for i, l in enumerate(body.split("\n"), 1) if BAD.search(l)]
if bad: fail("markers left in source", bad)
m = re.search(r"Version (\d+(?:\.\d+)+)", meta.get("audience", ""))
if not m: sys.exit("BUILD FAILED: no 'Version X.Y' in the front matter audience line")
PDF = f"idea-{NAME}-v{m.group(1)}.pdf"
for old in glob.glob(os.path.join(HERE, "*.pdf")):
    if os.path.basename(old) != PDF: os.remove(old)   # old unversioned / older versions
out = os.path.join(HERE, PDF)
housestyle.build(body, meta, out, base_url=HERE, keep_html=False, note="")   # cover: version + date only
txt = subprocess.run(["pdftotext", "-layout", out, "-"], capture_output=True, text=True, check=True).stdout
pages = txt.split("\f")
bad = [f"p{n}: {l.strip()[:90]}" for n, pg in enumerate(pages, 1) for l in pg.split("\n") if BAD.search(l) or "**" in l]
if bad: fail(f"markers in {PDF}", bad)
print("built", PDF, "pages:", len([p for p in pages if p.strip()]))
