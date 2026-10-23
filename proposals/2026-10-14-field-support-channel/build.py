#!/usr/bin/env python3
"""Build idea-field-support-channel-design-v<version>.pdf from proposals/2026-10-14-field-support-channel.md.

House style module: set IDEA_HOUSE_STYLE to the folder holding housestyle.py.
Default: ./house-style next to this file, then <repo>/docs/house-style
(see docs/DOCUMENTATION-RULES.md).
"""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
for p in [os.environ.get("IDEA_HOUSE_STYLE"), os.path.join(HERE, "house-style"),
          os.path.join(HERE, "..", "..", "docs", "house-style")]:
    if p and os.path.exists(os.path.join(p, "housestyle.py")):
        sys.path.insert(0, p); break
import housestyle
NAME = "2026-10-14-field-support-channel"
PARENT = os.path.dirname(HERE)  # proposals/
meta, body = housestyle.split_front_matter(open(os.path.join(PARENT, NAME + ".md"), encoding="utf-8").read())
import re, glob
v = re.search(r"Version (\d+(?:\.\d+)+)", meta.get("audience", "")).group(1)
OUT = os.path.join(HERE, f"idea-field-support-channel-design-v{v}.pdf")
for old in glob.glob(os.path.join(HERE, "*.pdf")):
    if old != OUT: os.remove(old)
housestyle.build(body, meta, OUT, base_url=PARENT, keep_html=False, note="")   # cover: version + date only
print("built", OUT)
