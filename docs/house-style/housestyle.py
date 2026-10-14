"""IDEA house style for project PDFs: Markdown -> HTML -> PDF (WeasyPrint).
Shared by docs/tutorial-justice/build.py and the install guides' build.py.
Provides: cover page, contents, page footer, headings, callouts (.note/.warn/.confirm
divs and > blockquotes), TO CONFIRM badges, figure captions from image alt text."""
import os, re, markdown
from weasyprint import HTML
HERE = os.path.dirname(os.path.abspath(__file__))
CSS = os.path.join(HERE, "house.css")

def fix_lists(md):
    """Insert the blank line Markdown needs before a list that follows a paragraph line."""
    out, fence = [], False
    for line in md.split("\n"):
        if line.lstrip().startswith("```"): fence = not fence
        if (not fence and out and out[-1].strip() and re.match(r"^(\s*)([-*+]|\d+\.)\s", line)
                and not re.match(r"^\s*([-*+]|\d+\.)\s", out[-1]) and not out[-1].startswith(("    ", "\t", "|", ">", "<"))
                and not re.match(r"^\s+\S", out[-1])):
            out.append("")
        out.append(line)
    return "\n".join(out)

def to_html(body, toc_depth="1-2"):
    md = markdown.Markdown(lazy_ol=False, extensions=["extra", "toc", "sane_lists"], extension_configs={"toc": {"toc_depth": toc_depth}})
    h = md.convert(fix_lists(body))
    h = re.sub(r"<b>(TO CONFIRM[^<]*|TEST FIRST)</b>", r'<span class="tc">\1</span>', h)
    h = re.sub(r"<strong>(to confirm|TO CONFIRM)</strong>", r'<span class="tc">TO CONFIRM</span>', h)
    h = re.sub(r'<ol start="(\d+)">', lambda m: f'<ol start="{m.group(1)}" style="counter-reset: list-item {int(m.group(1))-1}">', h)
    # images that are alone in a paragraph become captioned figures
    h = re.sub(r'<p>\s*(<img[^>]*alt="([^"]*)"[^>]*>)\s*</p>', r'<figure>\1<figcaption>\2</figcaption></figure>', h)
    h = re.sub(r'(?<!<figure>)(<img[^>]*alt="([^"]+)"[^>]*>)', r'<figure>\1<figcaption>\2</figcaption></figure>', h)
    h = h.replace("<h1", '<h1 class="nobreak"', 1)
    return h, md.toc

def build(body, meta, out_pdf, base_url, extra_css="", note=None, toc_depth="1-2", keep_html=True):
    note = note if note is not None else ("IDEA - offline school computing. Prepared for Koen Swings's team.<br>"
        "No real passwords, keys or tokens are included; values in &lt;ANGLE BRACKETS&gt; are placeholders.")
    h, toc = to_html(body, toc_depth)
    html = f"""<!doctype html><html><head><meta charset="utf-8"><title>{meta['title']}</title>
<link rel="stylesheet" href="file://{CSS}"><style>{extra_css}</style></head><body>
<div class="cover"><h1 class="title">{meta['title']}</h1><div class="subtitle">{meta.get('subtitle','')}</div>
<div class="bar"></div><div class="audience">{meta.get('audience','')}</div>
<div class="audience" style="margin-top:6mm">{note}</div></div>
<div class="toc"><h1 class="nobreak" style="page-break-before:avoid">Contents</h1>{toc}</div>
{h}</body></html>"""
    if keep_html: open(out_pdf[:-4] + ".html", "w", encoding="utf-8").write(html)
    HTML(string=html, base_url=base_url).write_pdf(out_pdf)
    return out_pdf

def split_front_matter(src):
    fm, body = re.match(r"^---\n(.*?)\n---\n(.*)$", src, re.S).groups()
    return dict(re.findall(r'^(\w+):\s*"(.*)"\s*$', fm, re.M)), body
