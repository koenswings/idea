**Status:** Authoritative · **Maintained by:** Marco (with Atlas) · 13 November 2026

> v2.1.1 (13 November 2026): `idea-for-teachers-tutorial-v2.1.1.pdf`. Review fixes: quiz and exercise screenshots recropped or retaken; the hidden Demo lesson is named in the appendix; S2-02 removed.
>
> v2.1 (13 November 2026): `idea-for-teachers-tutorial-v2.1.pdf`. Chapters 3 and 4 and the appendix rewritten for Kolibri 0.19.5, with every Kolibri screenshot retaken from the Kolibri Demo test instance.
>
> v2.0 (11 November 2026): `idea-for-teachers-tutorial-v2.0.pdf`. Chapter 1.4: how IDEA looks after the kit (counts how it is used, not who uses it or what they write).
>
> v1.9 (27 October 2026): `idea-for-teachers-tutorial-v1.9.pdf`. Combines v1.7 and v1.8.
>
> v1.8 (27 October 2026): chapter 2.1: a classroom computer can join IDEA-Teachers from its Wi-Fi menu (idea#285).
>
> v1.7 (27 October 2026): chapter 7 (Wikipedia offline) rewritten to match its Wikipedia (Demo) screenshots (idea#295).
>
> v1.6 (25 October 2026): teaching one class period, reading Reports and troubleshooting added to chapter 3 (3.6, 3.7).
> The v2.1, v2.0, v1.9, v1.8, v1.7, v1.6 and v1.5 PDFs are kept in `superseded/`.

# Teacher tutorial

`teacher-tutorial.pdf` ("IDEA for Teachers: Tutorial", 75 pages, v1.1 of 19 October 2026 for the Zimbabwe kit): Kolibri, Nextcloud, Wikipedia offline, Files Disk and
Backup Disk. The text follows the kit (Engines sunny-robin, happy-zebra, kind-panda; apps Kolibri Demo, Nextcloud Demo and Wikipedia (Demo) for practice); most screenshots still come from the demo server, see `SCREENSHOTS.md` for the retake list. Part A for teachers (chapters 01-10, including chapter 05 on the channel builder and USB sticks), Part B for the school
operator (11-13, including chapter 13 on resetting student computers), appendix with the demo accounts (14).

Build: `python3 build.py` (uses `docs/house-style`; fails if a "to confirm" marker is left).
Sources: `teacher-tutorial.md` (front matter: title on the cover), `chapters/*.md`, `screenshots/` (only the shots used in
the text; the admin name masked and the Tailscale address blurred), `SCREENSHOTS.md` (how they were taken).

Demo passwords follow the public IDEA default (account name followed by `911!`, for example `teacher1911!`) and may appear in the text. No other passwords.
