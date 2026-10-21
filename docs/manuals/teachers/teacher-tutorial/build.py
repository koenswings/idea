#!/usr/bin/env python3
"""Build idea-for-teachers-tutorial-v<version>.pdf with the IDEA house style (docs/house-style).
Usage: python3 build.py   Fails if any 'to confirm' marker is left in the text."""
import os, re, sys, glob
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
meta, _ = housestyle.split_front_matter(open(os.path.join(HERE, "teacher-tutorial.md"), encoding="utf-8").read())
PARTS = {1: ("Part A", "For teachers"), 10: ("Part B", "For the school operator")}
# [[pending-shot: ID | caption]] = a screenshot still to be taken; rendered as a box, listed at the end of the build
PENDING = re.compile(r"^\[\[pending-shot: *([A-Z0-9-]+) *\| *(.+?) *\]\]$", re.M)
pending = []
parts, bad = [], []
for f in sorted(glob.glob(os.path.join(HERE, "chapters", "*.md"))):
    t = STATUS.sub("", open(f, encoding="utf-8").read(), count=1)
    t = re.sub(r"<!--.*?-->", "", t, flags=re.S)
    for i, line in enumerate(t.split("\n"), 1):
        if re.search(r"to confirm", line.replace("TYPE IDEA DISK TO CONFIRM", ""), re.I):
            bad.append(f"{os.path.basename(f)}:{i}: {line.strip()[:90]}")
    num = re.match(r"(\d+)-", os.path.basename(f))
    if num and int(num.group(1)) in PARTS:
        a, b = PARTS[int(num.group(1))]
        parts.append(f'<div class="part"><h1 class="parttitle" id="part-{a[-1].lower()}">{a}: {b}</h1></div>')
    for m in PENDING.finditer(t): pending.append(f"{m.group(1)} ({os.path.basename(f)}): {m.group(2)}")
    t = PENDING.sub(lambda m: f'<div class="confirm"><b>Screenshot pending retake ({m.group(1)}):</b> {m.group(2)}.</div>', t)
    parts.append(t.replace("](../screenshots/", "](screenshots/").strip())
if bad:
    sys.exit("BUILD FAILED: 'to confirm' markers left:\n" + "\n".join(bad))
extra = """figure img { max-height: 92mm; width: auto; max-width: 100%; display: block; margin: 0 auto; }
figure { page-break-inside: avoid; }
li { page-break-inside: avoid; }
h2 + p, h2 + ol, h2 + ul { page-break-before: avoid; }
.part h1 { margin-top: 0; }
.part { page-break-before: always; page-break-after: always; padding-top: 80mm; }
h1.parttitle { page-break-before: avoid; border: none; font-size: 24pt; }"""
m = re.search(r"Version (\d+(?:\.\d+)+)", meta.get("audience", ""))
if not m: sys.exit("BUILD FAILED: no 'Version X.Y' in the front matter audience line")
PDF = f"idea-for-teachers-tutorial-v{m.group(1)}.pdf"
for old in glob.glob(os.path.join(HERE, "*.pdf")):
    if os.path.basename(old) != PDF: os.remove(old)   # old unversioned / older versions
housestyle.build("\n\n".join(parts), meta, os.path.join(HERE, PDF), base_url=HERE, extra_css=extra, keep_html=False,
    note="")   # cover: version + date only
print("built", PDF)
if pending: print(f"{len(pending)} screenshots pending retake:\n  " + "\n  ".join(pending))
