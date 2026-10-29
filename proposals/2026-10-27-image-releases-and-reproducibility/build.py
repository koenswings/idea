#!/usr/bin/env python3
"""Build 2026-10-27-image-releases-and-reproducibility.pdf from proposals/2026-10-27-image-releases-and-reproducibility.md.

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
NAME = "2026-10-27-image-releases-and-reproducibility"
PARENT = os.path.dirname(HERE)  # proposals/
meta, body = housestyle.split_front_matter(open(os.path.join(PARENT, NAME + ".md"), encoding="utf-8").read())
housestyle.build(body, meta, os.path.join(HERE, NAME + ".pdf"), base_url=PARENT, keep_html=False, extra_css="h1:not(.title){page-break-before:auto !important; break-before:auto !important}")
