#!/usr/bin/env python3
"""
md-to-pdf — Convert Markdown files to PDF using VS Code preview styles.

Dependencies (all pre-installed in the OpenClaw container):
  - python3-markdown  (apt: python3-markdown)
  - weasyprint        (apt: weasyprint)

Usage:
  md-to-pdf.py <input.md> [output.pdf]
  md-to-pdf.py --all

--------------------------------------------------------------------------------
PREVIOUS APPROACH (Node.js / TypeScript) — kept for reference / fallback
--------------------------------------------------------------------------------
The original implementation used:
  - zx + markdown-it (npm, from agent-engine-dev/node_modules via symlink)
  - chromium --headless (apt) for PDF rendering
  - tsx (from agent-engine-dev/node_modules/.bin/tsx) as the runner

It was replaced because:
  - chromium is a large system dep not present in the base OpenClaw image
  - the node_modules symlink created a hidden dependency on agent-engine-dev
  - weasyprint + python3-markdown are already in the container

The original script is preserved as md-to-pdf.mts alongside this file.
To revert: update md-to-pdf.sh to call tsx + md-to-pdf.mts instead of this script,
and restore the node_modules symlink pointing to agent-engine-dev/node_modules.
--------------------------------------------------------------------------------
"""

import sys
import os
import re
import glob as globmod
import argparse
import tempfile
from pathlib import Path

import markdown
from weasyprint import HTML, CSS


# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SKILL_DIR  = Path(__file__).resolve().parent.parent
STYLES_DIR = SKILL_DIR / "assets" / "styles"

EXCLUDE = {
    "docs/source-bundle.md",   # generated source dump, not a readable document
}


# ---------------------------------------------------------------------------
# HTML template
# ---------------------------------------------------------------------------
def build_html(body: str, title: str) -> str:
    def read_css(name: str) -> str:
        return (STYLES_DIR / name).read_text()

    return f"""<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>{title}</title>
<style>{read_css("markdown.css")}</style>
<style>{read_css("tomorrow.css")}</style>
<style>{read_css("markdown-pdf.css")}</style>
</head>
<body class="vscode-body">
{body}
</body>
</html>"""


# ---------------------------------------------------------------------------
# Heading anchor IDs (GitHub-compatible)
# ---------------------------------------------------------------------------
def add_heading_ids(html: str) -> str:
    def to_anchor(text: str) -> str:
        text = re.sub(r"&amp;", "&", text)
        text = re.sub(r"&lt;",  "<", text)
        text = re.sub(r"&gt;",  ">", text)
        text = re.sub(r"<[^>]+>", "", text)     # strip HTML tags
        text = text.lower()
        text = re.sub(r"[^\w\s-]", "", text)
        text = re.sub(r"\s+",     "-", text.strip())
        return text

    def replace(m: re.Match) -> str:
        tag, inner = m.group(1), m.group(2)
        anchor = to_anchor(inner)
        return f'<{tag} id="{anchor}">{inner}</{tag}>'

    return re.sub(r"<(h[1-6])>(.*?)</\1>", replace, html, flags=re.IGNORECASE | re.DOTALL)


# ---------------------------------------------------------------------------
# Core conversion
# ---------------------------------------------------------------------------
def convert(input_path: Path, output_path: Path) -> None:
    md_text  = input_path.read_text(encoding="utf-8")
    md_parser = markdown.Markdown(
        extensions=["fenced_code", "tables", "toc", "nl2br"],
        extension_configs={"toc": {"permalink": False}},
    )
    body     = add_heading_ids(md_parser.convert(md_text))
    html_str = build_html(body, input_path.name)

    # Use a temp file so WeasyPrint resolves relative URLs correctly
    with tempfile.NamedTemporaryFile(
        suffix=".html", delete=False, mode="w", encoding="utf-8"
    ) as tmp:
        tmp.write(html_str)
        tmp_path = tmp.name

    try:
        print(f"\033[34mGenerating: {output_path}\033[0m")
        HTML(filename=tmp_path).write_pdf(str(output_path))
        print(f"\033[32m  ✓ {output_path}\033[0m")
    finally:
        os.unlink(tmp_path)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert Markdown to PDF using VS Code preview styles."
    )
    parser.add_argument("input",   nargs="?", help="Input .md file")
    parser.add_argument("output",  nargs="?", help="Output .pdf file (default: alongside input)")
    parser.add_argument("--all",   action="store_true", help="Convert all .md files in cwd tree")
    args = parser.parse_args()

    if args.all:
        invoke_cwd = Path(os.environ.get("MD_TO_PDF_INVOKE_CWD", os.getcwd()))
        patterns   = ["**/*.md"]
        files: list[Path] = []
        for pat in patterns:
            for p in invoke_cwd.glob(pat):
                rel = str(p.relative_to(invoke_cwd))
                if rel in EXCLUDE:
                    continue
                if any(part in ("node_modules", "dist", "tmp") for part in p.parts):
                    continue
                files.append(p)
        files.sort()
        print(f"\033[34mConverting {len(files)} Markdown files...\033[0m")
        for f in files:
            convert(f, f.with_suffix(".pdf"))
        print(f"\n\033[32mDone. {len(files)} PDFs generated.\033[0m")

    elif args.input:
        input_path  = Path(args.input).resolve()
        output_path = Path(args.output).resolve() if args.output else input_path.with_suffix(".pdf")
        convert(input_path, output_path)

    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
