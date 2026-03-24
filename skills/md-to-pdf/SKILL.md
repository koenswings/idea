---
name: md-to-pdf
description: Convert Markdown files to PDF using VS Code preview styles. Use when asked to export, print, save, or generate a PDF from any .md file. Works from any agent workspace.
---

# md-to-pdf

Converts Markdown to PDF using VS Code preview styles and Chromium headless rendering.

## Usage

```bash
# Single file (PDF written alongside the source by default)
/home/node/workspace/skills/md-to-pdf/scripts/md-to-pdf.sh input.md

# Single file with explicit output path
/home/node/workspace/skills/md-to-pdf/scripts/md-to-pdf.sh input.md output.pdf

# Convert all .md files in the current directory tree
/home/node/workspace/skills/md-to-pdf/scripts/md-to-pdf.sh --all
```

## Setup (one-time, already done on this Pi)

**Chromium** must be installed in the OpenClaw container:
```bash
apt-get install -y chromium
```

**node_modules symlink** must exist in `scripts/` (links to engine-dev deps):
```bash
ln -s /home/node/workspace/agents/agent-engine-dev/node_modules \
  /home/node/workspace/skills/md-to-pdf/scripts/node_modules
```

These are already done. Redo them only if the container is rebuilt.

## Notes

- Run from the directory you want `--all` to scan (globs from cwd)
- Internal heading links work as clickable PDF anchors
- Excludes `node_modules/`, `dist/`, `tmp/`, and `docs/source-bundle.md` from `--all`
- Styles are bundled in `assets/styles/` — no internet required
- Depends on `zx` and `markdown-it` from `agent-engine-dev/node_modules`
