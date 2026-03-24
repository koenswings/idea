---
name: md-to-pdf
description: Convert Markdown files to PDF using VS Code preview styles. Use when asked to export, print, save, or generate a PDF from any .md file. Works from any agent workspace.
---

# md-to-pdf

Converts Markdown to PDF using VS Code preview styles. Uses `weasyprint` (already in the
OpenClaw container) for rendering — no extra system dependencies required.

## Usage

```bash
# Single file (PDF written alongside the source by default)
/home/node/workspace/skills/md-to-pdf/scripts/md-to-pdf.sh input.md

# Single file with explicit output path
/home/node/workspace/skills/md-to-pdf/scripts/md-to-pdf.sh input.md output.pdf

# Convert all .md files in the current directory tree
/home/node/workspace/skills/md-to-pdf/scripts/md-to-pdf.sh --all
```

## One-time setup (after fresh clone)

The `node_modules` symlink must exist in `scripts/` (links to engine-dev's JS deps for
Markdown parsing). Create it once after cloning the `idea` repo:

```bash
ln -s /home/node/workspace/agents/agent-engine-dev/node_modules \
  /home/node/workspace/skills/md-to-pdf/scripts/node_modules
```

This is the only setup step. Weasyprint and all other dependencies are already in the container.

## Notes

- Run from the directory you want `--all` to scan (globs from cwd)
- Internal heading links work as clickable PDF anchors
- Excludes `node_modules/`, `dist/`, `tmp/`, and `docs/source-bundle.md` from `--all`
- Styles are bundled in `assets/styles/` — no internet required
- Depends on `zx` and `markdown-it` from `agent-engine-dev/node_modules` (via symlink)
