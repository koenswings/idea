#!/usr/bin/env python3
"""Build architecture-v2.pdf.

The Markdown source keeps its diagrams as ```mermaid blocks (GitHub renders them).
tools/pdf/md-to-pdf.py does not render Mermaid, so this script:
  1. renders every mermaid block to diagrams/fig-NN.svg with mermaid-cli (mmdc),
  2. writes a temporary copy of the Markdown with each block replaced by an image,
  3. runs tools/pdf/md-to-pdf.py on that copy and removes it.

mmdc: set MMDC to a mermaid-cli binary, else `npx -y @mermaid-js/mermaid-cli` is used.
Chrome: set PUPPETEER_EXECUTABLE_PATH if puppeteer has no bundled browser.
"""
import json, os, re, shlex, subprocess, sys, tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
SRC = HERE / 'architecture-v2.md'
PDF = HERE / 'idea-architecture-v2.pdf'
DIAG = HERE / 'diagrams'

def mmdc_cmd():
    return shlex.split(os.environ.get('MMDC', 'npx -y @mermaid-js/mermaid-cli'))

def render(blocks):
    DIAG.mkdir(exist_ok=True)
    cfg = {'args': ['--no-sandbox']}
    exe = os.environ.get('PUPPETEER_EXECUTABLE_PATH')
    if exe:
        cfg['executablePath'] = exe
    theme = {'theme': 'neutral', 'themeVariables': {'fontFamily': 'Arial, sans-serif', 'fontSize': '15px'}}
    with tempfile.TemporaryDirectory() as td:
        pcfg = Path(td) / 'puppeteer.json'; pcfg.write_text(json.dumps(cfg))
        mcfg = Path(td) / 'mermaid.json'; mcfg.write_text(json.dumps(theme))
        for i, code in enumerate(blocks, 1):
            src = Path(td) / f'fig-{i:02d}.mmd'; src.write_text(code)
            out = DIAG / f'fig-{i:02d}.svg'
            subprocess.run(mmdc_cmd() + ['-q', '-i', str(src), '-o', str(out), '-b', 'white',
                                         '-p', str(pcfg), '-c', str(mcfg)], check=True)

STYLE = ('<style>table td:first-child, table th:first-child { white-space: nowrap; }\n'
         '.figure { text-align: center; margin: 14px 0; page-break-inside: avoid; }\n'
         '.figure img { max-width: 100%; max-height: 540px; }</style>\n\n')

def main():
    md = SRC.read_text(encoding='utf-8')
    pat = re.compile(r'```mermaid\n(.*?)```', re.DOTALL)
    blocks = [m.group(1) for m in pat.finditer(md)]
    render(blocks)
    n = iter(range(1, len(blocks) + 1))
    pdf_md = pat.sub(lambda m: f'<p class="figure"><img src="diagrams/fig-{next(n):02d}.svg"></p>\n', md)
    pdf_md = STYLE + pdf_md
    tmp = HERE / '_pdf-source.md'
    tmp.write_text(pdf_md, encoding='utf-8')
    try:
        subprocess.run([sys.executable, str(REPO / 'tools/pdf/md-to-pdf.py'), str(tmp), str(PDF)], check=True)
    finally:
        tmp.unlink(missing_ok=True)
    print(f'wrote {PDF}')

if __name__ == '__main__':
    main()
