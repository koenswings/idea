**Status:** Authoritative · **Maintained by:** Atlas (with Marco) · 14 October 2026

# IDEA house style for project PDFs

`housestyle.py` + `house.css`: Markdown -> HTML -> PDF (WeasyPrint). This is the only copy (DOCUMENTATION-RULES.md rule 7).

It gives a cover page, contents with page numbers, a "title - page N of M" footer, red/blue headings, callouts
(`<div class="note|warn|confirm">` and `>` blockquotes), TO CONFIRM badges, numbered figure captions from image alt text,
and automatic blank lines before lists (`fix_lists`).

Use from a build script: find this folder via `$IDEA_HOUSE_STYLE`, or by walking up from the script to the repo's
`docs/house-style/`; then `sys.path.insert(0, path); import housestyle; housestyle.build(body, meta, out_pdf, base_url)`.
`split_front_matter(src)` reads the `title` / `subtitle` / `audience` front matter.

Needs: `python3-markdown`, `weasyprint`, `poppler-utils` (the builds check the PDF text with `pdftotext`).

Users: every `build.py` under `docs/manuals/`.
