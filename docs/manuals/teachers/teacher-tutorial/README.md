**Status:** Authoritative · **Maintained by:** Marco (with Atlas) · 14 October 2026

# Teacher tutorial

`teacher-tutorial.pdf` ("IDEA for Teachers: Tutorial", 55 pages): Kolibri, Nextcloud, Wikipedia offline, Files Disk and
Backup Disk on the demo server wizardly-hugle. Part A for teachers (chapters 01-10, including chapter 05 on the channel builder and USB sticks), Part B for the school
operator (11-13, including chapter 13 on resetting student computers), appendix with the demo usernames (14).

Build: `python3 build.py` (uses `docs/house-style`; fails if a "to confirm" marker is left).
Sources: `teacher-tutorial.md` (front matter: title on the cover), `chapters/*.md`, `screenshots/` (only the shots used in
the text; Milkwise cut out, the admin name masked and the Tailscale address blurred), `SCREENSHOTS.md` (how they were taken).

No passwords. The demo-account passwords are in an internal note outside `docs/`.
