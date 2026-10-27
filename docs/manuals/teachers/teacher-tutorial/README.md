**Status:** Authoritative · **Maintained by:** Marco (with Atlas) · 27 October 2026

> v1.7 (27 October 2026): `idea-for-teachers-tutorial-v1.7.pdf`. Chapter 7 (Wikipedia offline) rewritten to match its Wikipedia (Demo) screenshots (idea#295).
> The v1.6 and v1.5 PDFs are kept in `superseded/`.

# Teacher tutorial

`teacher-tutorial.pdf` ("IDEA for Teachers: Tutorial", 75 pages, v1.1 of 19 October 2026 for the Zimbabwe kit): Kolibri, Nextcloud, Wikipedia offline, Files Disk and
Backup Disk. The text follows the kit (Engines sunny-robin, happy-zebra, kind-panda; apps Kolibri Demo, Nextcloud Demo and Wikipedia (Demo) for practice); most screenshots still come from the demo server, see `SCREENSHOTS.md` for the retake list. Part A for teachers (chapters 01-10, including chapter 05 on the channel builder and USB sticks), Part B for the school
operator (11-13, including chapter 13 on resetting student computers), appendix with the demo accounts (14).

Build: `python3 build.py` (uses `docs/house-style`; fails if a "to confirm" marker is left).
Sources: `teacher-tutorial.md` (front matter: title on the cover), `chapters/*.md`, `screenshots/` (only the shots used in
the text; Milkwise cut out, the admin name masked and the Tailscale address blurred), `SCREENSHOTS.md` (how they were taken).

Demo passwords follow the public IDEA default (account name followed by `911!`, for example `teacher1911!`) and may appear in the text. No other passwords.
