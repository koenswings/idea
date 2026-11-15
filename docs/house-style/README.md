**Status:** Authoritative · **Maintained by:** Marco (with Atlas) · 15 November 2026

# IDEA house style for project PDFs

This folder is the single IDEA house style for project PDFs (DOCUMENTATION-RULES.md rule 7). There is no other copy. `housestyle.py` and `house.css` turn Markdown into HTML and then into a PDF with WeasyPrint.

## What the style gives you

This section lists what every PDF built with this module gets.

- A cover page with the title, subtitle and audience line, and an optional IDEA logo
- A contents page with page numbers
- A footer on later pages: "title - page N of M"
- Red chapter headings and blue section headings
- Callouts: `<div class="note">`, `<div class="warn">`, `<div class="confirm">`, and `>` blockquotes
- TO CONFIRM (and TEST FIRST) badges
- Numbered figure captions, taken from each image's alt text
- Automatic blank lines before lists that follow a paragraph (`fix_lists`)

## Files

This section names what lives in this folder.

| File | Role |
|---|---|
| `housestyle.py` | Shared Markdown → HTML → PDF module |
| `house.css` | Shared stylesheet (A4, fonts, cover, contents, headings, tables, callouts, figures, cover logo) |
| `idea-logo.svg` | Cover logo (logo C: book + server, no tagline), used when the source sets `cover_logo: "yes"` |
| `README.md` | This page |

Build scripts find this folder in the repo and import it. It stays in `docs/house-style/`; official manuals and proposal builds look for it there.

## How a build script finds this folder

This section explains how `build.py` locates `housestyle.py`.

Every official `build.py` under `docs/manuals/` does the same lookup:

1. If the environment variable `IDEA_HOUSE_STYLE` is set, use that path.
2. Otherwise walk up from the script's directory until `docs/house-style/housestyle.py` exists.
3. If it is not found, the script exits with `BUILD FAILED: docs/house-style not found; set IDEA_HOUSE_STYLE`.

Then it does `sys.path.insert(0, path); import housestyle`.

Proposal builds under `proposals/<date>-<topic>/` also honour `IDEA_HOUSE_STYLE`, then try `./house-style` next to the script, then `<repo>/docs/house-style`.

## Front matter and the build API

This section describes the functions a build script calls, and the YAML front matter they read.

`split_front_matter(src)` reads a leading block of `key: "value"` lines (the key is a word; the value is in double quotes) and returns `(meta, body)`:

```yaml
---
title: "IDEA Field Install Manual: School Server"
subtitle: "Raspberry Pi 5 Engines + Cudy router + PoE switch + Starlink"
audience: "Version 1.8, 25 October 2026"
cover_logo: "yes"
---
```

`title`, `subtitle` and `audience` appear on the cover. `cover_logo: "yes"` places `idea-logo.svg` above the title. Official manuals put `Version X.Y` in the audience line; that is how each `build.py` names the PDF.

`housestyle.build(body, meta, out_pdf, base_url, extra_css="", note=None, toc_depth="1-2", keep_html=True)` writes the PDF.

- `base_url` is the folder that holds images and diagrams (usually the manual folder).
- `extra_css` is optional extra stylesheet text for that manual (for example a maximum image height).
- `note` is a second line under the audience on the cover. The module default is a short IDEA disclaimer about placeholders. Official manuals pass `note=""` so the cover shows only the audience line (the version and date).
- `toc_depth` defaults to `"1-2"`.
- `keep_html=True` also writes a `.html` file next to the PDF. Official manuals pass `keep_html=False`. Intermediate HTML is not committed (DOCUMENTATION-RULES.md rule 6).

A typical call from an official manual:

```python
housestyle.build(body, meta, out_pdf, base_url=HERE, keep_html=False, note="")
```

## How official manuals are built today

This section is the recipe used by every `build.py` under `docs/manuals/`.

Run `python3 build.py` in the manual's folder. The script reads the version from the audience line (`Version X.Y`) and writes a versioned PDF with a full descriptive name, for example `idea-field-install-manual-school-server-v1.8.pdf`.

Official conventions that the scripts themselves apply:

- Almost every official source sets `cover_logo: "yes"`. The lesson-manuals build fails if it is missing. The remote access guide is the exception: it has no `cover_logo` line, so its cover has no logo.
- Official builds pass `note=""` and `keep_html=False`, as above.
- They strip a leading `**Status:** …` line from the Markdown so it does not appear in the PDF.
- They fail if leftover markers remain in the source, and most of them also check the PDF text with `pdftotext`. The usual markers are "to confirm", `TODO`, `TBD` and `FIXME`. Some manuals add their own checks (for example school-numbering leftovers, placeholders, unrendered `**`, or an HTML `<!-- screenshot` comment). The teacher and operator tutorials make an exception for the typed confirm phrase `TYPE IDEA DISK TO CONFIRM`.
- The three install-folder builds (school server, classroom computer, and accounts and passwords) support `@@INCLUDE path@@` (the path is relative to the manual folder). The two field install manuals also regenerate the shared install diagrams.
- The teacher and operator tutorials assemble `chapters/*.md` and rewrite screenshot links.

Pending-shot markers: in the teacher and operator tutorials, a line of the form `[[pending-shot: ID | caption]]` is turned into a confirm box ("Screenshot pending retake (ID): caption.") and listed at the end of the build. Those two official builds do not fail because of it. Other official `build.py` scripts do not treat this marker specially, so a leftover one would be printed as ordinary text (it only fails the build if it also matches one of that script's marker checks).

Versioned PDFs and `superseded/`: each official `build.py` deletes any other `*.pdf` left in the manual folder (it does not touch `superseded/`). Before you bump a version, `git mv` the previous versioned PDF into that folder's `superseded/`, then run the build. If you leave the old PDF in the folder, the script will remove it. In the same change, update the folder README, [`docs/README.md`](../README.md) and [`docs/INDEX.md`](../INDEX.md) so they name the new current PDF.

| Folder | PDF the build writes |
|---|---|
| `docs/manuals/install/install-manual-school-server/` | `idea-field-install-manual-school-server-v<version>.pdf` |
| `docs/manuals/install/install-manual-classroom-computer/` | `idea-field-install-manual-classroom-computer-v<version>.pdf` |
| `docs/manuals/install/accounts-and-passwords/` | `idea-accounts-and-passwords-v<version>.pdf` |
| `docs/manuals/teachers/teacher-tutorial/` | `idea-for-teachers-tutorial-v<version>.pdf` |
| `docs/manuals/teachers/lesson-manuals/` | `idea-grade-5a-add-and-subtract-fractions-v<version>.pdf` and `idea-form-3-variables-and-expressions-v<version>.pdf` |
| `docs/manuals/operators/operator-tutorial/` | `idea-for-operators-tutorial-v<version>.pdf` |
| `docs/manuals/field/remote-access-guide/` | `idea-demo-server-remote-access-guide-v<version>.pdf` |
| `docs/manuals/field/school-handover-note/` | `idea-school-handover-note-v<version>.pdf` |

## Proposal PDFs

This section notes the other in-repo users of the same module.

Six proposal folders under `proposals/` have a `build.py` that imports this house style. They write an unversioned PDF named after the proposal (for example `2026-10-14-field-support-channel.pdf`) and do not apply the official-manual checks or versioned-PDF naming above.

## Dependencies

Builds need `python3-markdown` and `weasyprint`. Official manuals that check the PDF text also need `poppler-utils` (`pdftotext`).
