#!/usr/bin/env python3
"""Build the two lesson-manual PDFs with the IDEA house style (docs/house-style).

Writes idea-<slug>-v<version>.pdf from each source's front matter (Version X.Y,
cover_logo). Usage: python3 build.py
Fails if a 'to confirm' marker is left in the source or the PDF.
"""
import glob, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))

def find_house_style(here):
    """docs/house-style, found via $IDEA_HOUSE_STYLE or by walking up to the repo's docs/."""
    p = os.environ.get("IDEA_HOUSE_STYLE")
    if p:
        return p
    d = here
    while d != os.path.dirname(d):
        c = os.path.join(d, "docs", "house-style")
        if os.path.isfile(os.path.join(c, "housestyle.py")):
            return c
        d = os.path.dirname(d)
    sys.exit("BUILD FAILED: docs/house-style not found; set IDEA_HOUSE_STYLE")

STATUS = re.compile(r"^\*\*Status:\*\*.*\n+", re.M)
BAD = re.compile(r"to confirm|\bTODO\b|\bTBD\b|FIXME|<!-- *screenshot", re.I)

sys.path.insert(0, find_house_style(HERE))
import housestyle

# source stem -> versioned PDF slug (full manual name, without version)
MANUALS = [
    ("grade5a-add-and-subtract-fractions", "idea-grade-5a-add-and-subtract-fractions"),
    ("form3-variables-and-expressions", "idea-form-3-variables-and-expressions"),
]

def fail(msg, lines):
    sys.exit("BUILD FAILED: " + msg + ":\n" + "\n".join(lines))

wanted = []
for src_stem, pdf_stem in MANUALS:
    path = os.path.join(HERE, src_stem + ".md")
    meta, body = housestyle.split_front_matter(open(path, encoding="utf-8").read())
    body = STATUS.sub("", body, count=1)
    bad = [f"{src_stem}.md:{i}: {l.strip()[:90]}" for i, l in enumerate(body.split("\n"), 1) if BAD.search(l)]
    if bad:
        fail("markers left in source", bad)
    m = re.search(r"Version (\d+(?:\.\d+)+)", meta.get("audience", ""))
    if not m:
        sys.exit(f"BUILD FAILED: no 'Version X.Y' in the front matter audience line of {src_stem}.md")
    if meta.get("cover_logo", "").lower() != "yes":
        sys.exit(f"BUILD FAILED: {src_stem}.md must set cover_logo: \"yes\"")
    pdf_name = f"{pdf_stem}-v{m.group(1)}.pdf"
    wanted.append(pdf_name)
    out = os.path.join(HERE, pdf_name)
    extra = "figure img, p img { max-height: 95mm; width: auto; max-width: 100%; display: block; margin: 0 auto; }"
    housestyle.build(body, meta, out, base_url=HERE, keep_html=False, extra_css=extra, note="")
    txt = subprocess.run(["pdftotext", "-layout", out, "-"], capture_output=True, text=True, check=True).stdout
    pages = txt.split("\f")
    bad = [f"p{n}: {l.strip()[:90]}" for n, pg in enumerate(pages, 1) for l in pg.split("\n") if BAD.search(l) or "**" in l]
    if bad:
        fail(f"markers in {pdf_name}", bad)
    print("built", pdf_name, "pages:", len([p for p in pages if p.strip()]))

for old in glob.glob(os.path.join(HERE, "*.pdf")):
    if os.path.basename(old) not in wanted:
        os.remove(old)
