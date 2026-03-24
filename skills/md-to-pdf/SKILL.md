---
name: md-to-pdf
description: Convert Markdown files to PDF using VS Code preview styles. Use when asked to export, print, save, or generate a PDF from any .md file. Works from any agent workspace.
---

# md-to-pdf

Converts Markdown to PDF using VS Code preview styles.

**Stack:** `python3-markdown` (Markdown → HTML) + `weasyprint` (HTML → PDF).
Both are Python packages. `weasyprint` ships in the base OpenClaw image.
`python3-markdown` must be present — see Container Setup below.

## Usage

```bash
# Single file (PDF written alongside the source by default)
/home/node/workspace/skills/md-to-pdf/scripts/md-to-pdf.sh input.md

# Single file with explicit output path
/home/node/workspace/skills/md-to-pdf/scripts/md-to-pdf.sh input.md output.pdf

# Convert all .md files in the current directory tree
/home/node/workspace/skills/md-to-pdf/scripts/md-to-pdf.sh --all
```

## Container setup

`python3-markdown` is not in the base OpenClaw image. Add it to the OpenClaw
container build by setting in `/home/pi/openclaw/.env`:

```
OPENCLAW_DOCKER_APT_PACKAGES=python3-markdown
```

This bakes it into the image at build time so it survives container rebuilds.
It is currently installed manually in the running container (`apt-get install -y python3-markdown`).

## Notes

- No npm dependencies, no symlinks, no post-clone setup steps
- Run from the directory you want `--all` to scan (globs from cwd)
- Internal heading links work as clickable PDF anchors
- Excludes `node_modules/`, `dist/`, `tmp/`, and `docs/source-bundle.md` from `--all`
- Styles are bundled in `assets/styles/` — no internet required

## Previous approach (Node.js / TypeScript)

The skill was originally implemented in TypeScript (`md-to-pdf.mts`), using
`zx` + `markdown-it` (from `agent-engine-dev/node_modules`) and Chromium for rendering.
It was replaced by this Python implementation to eliminate all external dependencies.
The `.mts` file is preserved alongside `md-to-pdf.py` as a fallback reference.
See `md-to-pdf.sh` comments for how to revert.
