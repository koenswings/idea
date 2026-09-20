---
name: md-to-pdf
description: Convert Markdown files to PDF with a clickable two-level table of contents and clean styling. Use when asked to export, print, save, or generate a PDF from any .md file. Works from any agent workspace.
---

# md-to-pdf

Converts Markdown to a styled PDF with:
- **Clickable two-level table of contents** (H1 + H2, page 1)
- Clean typography — headings, code blocks, tables, blockquotes
- Internal links that work in PDF readers

**Stack:** Python + Chromium headless (pre-installed on Pi).  
Fallback: `python3-markdown` + `weasyprint` (no ToC links, but no Chromium needed).

## Usage

```bash
# Primary renderer (Chromium — clickable ToC, full styling)
python3 /home/node/workspace/skills/md-to-pdf/scripts/md-to-pdf-chromium.py input.md

# With explicit output path
python3 /home/node/workspace/skills/md-to-pdf/scripts/md-to-pdf-chromium.py input.md output.pdf

# Fallback renderer (WeasyPrint — simpler, no clickable ToC)
/home/node/workspace/skills/md-to-pdf/scripts/md-to-pdf.sh input.md
```

## How the Chromium renderer works

1. Strips the plain-text `## Contents` table from the Markdown (replaced by the generated ToC)
2. Scans all H1 and H2 headings outside code blocks, generates slug IDs
3. Builds a styled HTML ToC page with `href="#slug"` links
4. Converts Markdown to HTML with anchor `id` attributes on headings
5. Inlines all CSS (typography, code, tables, ToC styling)
6. Renders to PDF via `chromium --headless --print-to-pdf`
7. Chromium correctly maps `href="#anchor"` → internal PDF links

## Requirements

- `chromium` — pre-installed on Pi (`which chromium`)
- `python3-markdown` — `apt-get install -y python3-markdown`

## Notes

- Code block contents are skipped when scanning for headings (prevents bash `# comment` lines appearing in ToC)
- Images with relative paths are resolved to absolute paths before rendering
- The `## Contents` table (plain text) in the source Markdown is stripped automatically — the generated ToC replaces it
- Chromium runs with `--no-sandbox` (required on Pi)
- Output is a single-page PDF with fonts, colours, and layout matching the style in `assets/styles/`

## Fallback (WeasyPrint)

If Chromium is unavailable, use the WeasyPrint fallback:

```bash
/home/node/workspace/skills/md-to-pdf/scripts/md-to-pdf.sh input.md [output.pdf]
/home/node/workspace/skills/md-to-pdf/scripts/md-to-pdf.sh --all
```

WeasyPrint produces correct output but internal ToC links are not clickable.

## Grok Build usage

Grok Build does not have skill invocation built in. To use this in a Grok Build
run on a Pi, invoke it directly:

```bash
python3 /home/node/workspace/skills/md-to-pdf/scripts/md-to-pdf-chromium.py \
  /path/to/document.md \
  /path/to/output.pdf
```

The script is self-contained and has no external dependencies beyond Chromium and
python3-markdown.
