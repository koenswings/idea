#!/usr/bin/env python3
"""
Convert Markdown to PDF with a clickable two-level ToC using Chromium headless.
Chromium correctly renders href="#anchor" as internal PDF bookmarks/links.
"""
import sys, re, os, subprocess, tempfile
from pathlib import Path

import markdown
from markdown.extensions.toc import TocExtension

def slugify(text):
    text = re.sub(r'<[^>]+>', '', text)
    text = text.lower().strip()
    text = re.sub(r'[^\w\s-]', '', text)
    text = re.sub(r'[\s]+', '-', text)
    return text

def extract_headings(md_text):
    """Extract H1 and H2 headings, skipping content inside code blocks."""
    headings = []
    in_code = False
    for line in md_text.split('\n'):
        # Toggle code block state on ``` fences
        if line.strip().startswith('```'):
            in_code = not in_code
            continue
        if in_code:
            continue
        m1 = re.match(r'^# (.+)$', line)
        m2 = re.match(r'^## (.+)$', line)
        if m1:
            text = m1.group(1).strip()
            # Skip markdown artifacts like '# anchor' links or image refs
            if text and not text.startswith('!'):
                headings.append((1, text, slugify(text)))
        elif m2:
            text = m2.group(1).strip()
            if text:
                headings.append((2, text, slugify(text)))
    return headings

def build_toc_html(headings):
    lines = ['<nav class="toc"><h2 class="toc-title">Contents</h2><ol class="toc-l1">']
    i = 0
    while i < len(headings):
        level, text, slug = headings[i]
        if level == 1:
            # Collect following H2s
            sub = []
            j = i + 1
            while j < len(headings) and headings[j][0] == 2:
                sub.append(headings[j])
                j += 1
            if sub:
                lines.append(f'  <li><a href="#{slug}">{text}</a>')
                lines.append('    <ol class="toc-l2">')
                for _, st, ss in sub:
                    lines.append(f'      <li><a href="#{ss}">{st}</a></li>')
                lines.append('    </ol></li>')
            else:
                lines.append(f'  <li><a href="#{slug}">{text}</a></li>')
            i = j
        else:
            i += 1
    lines.append('</ol></nav>')
    return '\n'.join(lines)

def convert(input_path, output_path):
    md_text = Path(input_path).read_text(encoding='utf-8')
    
    # Strip the Contents table (our plain-text ToC) from the markdown
    # so it doesn't appear as a table in the body
    md_text = re.sub(r'## Contents\n\n\|[^\n]+\|\n\|[^\n]+\|\n(\|[^\n]+\|\n)*', '', md_text)
    
    # Extract headings before converting
    headings = extract_headings(md_text)
    toc_html = build_toc_html(headings)
    
    # Convert markdown to HTML with anchor IDs on headings
    md = markdown.Markdown(extensions=[
        'fenced_code', 'tables', 'codehilite',
        TocExtension(permalink=False)
    ])
    body = md.convert(md_text)
    
    # Ensure headings have id attributes matching our slugs
    def add_id(m):
        tag = m.group(1)
        inner = m.group(2)
        slug = slugify(re.sub(r'<[^>]+>', '', inner))
        return f'<{tag} id="{slug}">{inner}</{tag}>'
    body = re.sub(r'<(h[12])(?: [^>]*)?>(.*?)</h[12]>', add_id, body, flags=re.DOTALL)
    
    # Resolve image paths: replace markdown image relative paths with absolute ones
    # so Chromium can load them as file:// URLs
    base_dir = str(Path(input_path).resolve().parent)
    body = re.sub(
        r'<img([^>]*)src="(?!http|file|data)([^"]+)"',
        lambda m: f'<img{m.group(1)}src="{os.path.join(base_dir, m.group(2))}"',
        body
    )

    html = f"""<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>{Path(input_path).stem}</title>
<style>
/* Page setup */
@page {{ margin: 20mm 18mm 20mm 18mm; }}
body {{
  font-family: 'Segoe UI', Arial, sans-serif;
  font-size: 11pt;
  line-height: 1.55;
  color: #1e293b;
  max-width: 900px;
  margin: 0 auto;
}}

/* Table of contents */
.toc {{
  background: #f8fafc;
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  padding: 20px 28px;
  margin-bottom: 40px;
  page-break-after: always;
}}
.toc-title {{
  font-size: 15pt;
  font-weight: bold;
  color: #0f172a;
  margin: 0 0 16px 0;
  border-bottom: 2px solid #e2e8f0;
  padding-bottom: 8px;
}}
.toc-l1 {{
  list-style: none;
  padding: 0;
  margin: 0;
  counter-reset: none;
}}
.toc-l1 > li {{
  margin: 6px 0;
}}
.toc-l1 > li > a {{
  color: #1d4ed8;
  text-decoration: none;
  font-size: 11pt;
  font-weight: 600;
}}
.toc-l1 > li > a:hover {{ text-decoration: underline; }}
.toc-l2 {{
  list-style: none;
  padding: 4px 0 4px 20px;
  margin: 4px 0;
}}
.toc-l2 > li {{ margin: 3px 0; }}
.toc-l2 > li > a {{
  color: #2563eb;
  text-decoration: none;
  font-size: 10.5pt;
  font-weight: normal;
}}
.toc-l2 > li > a:hover {{ text-decoration: underline; }}

/* Headings */
h1 {{ font-size: 18pt; color: #0f172a; margin-top: 32px; border-bottom: 2px solid #e2e8f0; padding-bottom: 6px; }}
h2 {{ font-size: 14pt; color: #1e293b; margin-top: 24px; }}
h3 {{ font-size: 12pt; color: #334155; margin-top: 18px; }}
h4 {{ font-size: 11pt; color: #475569; margin-top: 14px; }}

/* Code */
code {{
  font-family: 'Cascadia Code', 'Fira Mono', monospace;
  font-size: 9.5pt;
  background: #f1f5f9;
  padding: 2px 5px;
  border-radius: 3px;
  color: #1e293b;
}}
pre {{
  background: #1e293b;
  color: #e2e8f0;
  padding: 14px 16px;
  border-radius: 6px;
  overflow-x: auto;
  font-size: 9pt;
  line-height: 1.45;
}}
pre code {{
  background: none;
  padding: 0;
  color: inherit;
  font-size: inherit;
}}

/* Tables */
table {{ border-collapse: collapse; width: 100%; margin: 12px 0; font-size: 10.5pt; }}
th {{ background: #1e40af; color: white; padding: 8px 12px; text-align: left; }}
td {{ padding: 7px 12px; border-bottom: 1px solid #e2e8f0; }}
tr:nth-child(even) td {{ background: #f8fafc; }}

/* Blockquote */
blockquote {{
  border-left: 4px solid #93c5fd;
  margin: 12px 0;
  padding: 8px 16px;
  background: #eff6ff;
  color: #1e40af;
  border-radius: 0 4px 4px 0;
}}

/* HR */
hr {{ border: none; border-top: 1px solid #e2e8f0; margin: 24px 0; }}

/* Lists */
ul, ol {{ padding-left: 24px; }}
li {{ margin: 3px 0; }}
</style>
</head>
<body>
{toc_html}
{body}
</body>
</html>"""
    
    with tempfile.NamedTemporaryFile(suffix='.html', delete=False, mode='w', encoding='utf-8') as f:
        f.write(html)
        tmp_path = f.name
    
    try:
        result = subprocess.run([
            'chromium', '--headless', '--no-sandbox',
            '--print-to-pdf=' + str(output_path),
            '--print-to-pdf-no-header',
            '--no-pdf-header-footer',
            'file://' + tmp_path
        ], capture_output=True, timeout=60)
        if result.returncode == 0:
            print(f'\033[32m  ✓ {output_path}\033[0m')
        else:
            print(f'\033[31m  ✗ chromium failed\033[0m')
            print(result.stderr.decode()[:500])
    finally:
        os.unlink(tmp_path)

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: md_to_pdf_toc.py input.md [output.pdf]")
        sys.exit(1)
    inp = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else inp.replace('.md', '.pdf')
    convert(inp, out)
