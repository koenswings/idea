#!/usr/bin/env python3
"""Build remote-access-guide.pdf with the IDEA house style (docs/house-style).
Usage: python3 build.py   (regenerates the diagrams too)
Fails if a 'to confirm' marker, a placeholder or a run-together bullet is left in the text or the PDF."""
import os, re, subprocess, sys
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
sys.path.insert(0, find_house_style(HERE)); import housestyle
SRC, OUT = os.path.join(HERE, "remote-access-guide.md"), os.path.join(HERE, "remote-access-guide.pdf")
WORDS = re.compile(r"to confirm|\bTODO\b|\bTBD\b|FIXME|\bXXX\b|lorem|placeholder|\[\?\]", re.I)
ANGLE = re.compile(r"<[A-Z][A-Z0-9_-]{2,}>|&lt;[A-Z][A-Z0-9_-]{2,}&gt;")   # <ANGLE-BRACKET> placeholders (case-sensitive)
class _Bad:
    def search(self, l): return WORDS.search(l) or ANGLE.search(l)
BAD = _Bad()
subprocess.run([sys.executable, os.path.join(HERE, "diagrams", "make_diagrams.py")], check=True)
meta, body = housestyle.split_front_matter(open(SRC, encoding="utf-8").read())
body = STATUS.sub("", body, count=1)
bad = [f"md:{i}: {l.strip()[:90]}" for i, l in enumerate(body.split("\n"), 1) if BAD.search(l)]
if bad: sys.exit("BUILD FAILED: markers left in source:\n" + "\n".join(bad))
extra = """figure img { max-height: 92mm; width: auto; max-width: 100%; display: block; margin: 0 auto; }
figure { page-break-inside: avoid; }
li { page-break-inside: avoid; }
h2 + p, h2 + ol, h2 + ul { page-break-before: avoid; }
.part h1 { margin-top: 0; }
.part { page-break-before: always; page-break-after: always; padding-top: 80mm; }
h1.parttitle { page-break-before: avoid; border: none; font-size: 24pt; }
.toc li { margin: 0.2mm 0; }"""
housestyle.build(body, meta, OUT, base_url=HERE, extra_css=extra, keep_html=False,
    note="IDEA - offline school computing. Prepared for Koen Swings's team.<br>"
         "No passwords, keys or tokens are included. Koen sends the passwords separately.")
txt = subprocess.run(["pdftotext", "-layout", OUT, "-"], capture_output=True, text=True, check=True).stdout
pages = txt.split("\f")
problems = []
for n, pg in enumerate(pages, 1):
    for l in pg.split("\n"):
        if BAD.search(l): problems.append(f"p{n}: marker: {l.strip()[:90]}")
        if re.search(r"\S.*•", l): problems.append(f"p{n}: run-together bullet: {l.strip()[:90]}")
        if re.search(r"\S\s+\d+\.\s+\*\*Do", l) or "**" in l: problems.append(f"p{n}: unrendered markdown: {l.strip()[:90]}")
if problems: sys.exit("BUILD FAILED: PDF checks:\n" + "\n".join(problems))
print("built", OUT, "pages:", len([p for p in pages if p.strip()]))
