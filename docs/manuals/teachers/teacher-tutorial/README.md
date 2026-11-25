**Status:** Authoritative · **Maintained by:** Marco (with Atlas) · 25 November 2026

> v2.2.2 (25 November 2026): `idea-for-teachers-tutorial-v2.2.2.pdf`. Chapter 2.3: apps of an IDEA box that is not here are still listed, but their **Open** button is greyed out (Console #175); the old "known problem, no fix yet" note is gone. Chapter 9: from version 1.3 of the Wikipedia app, Wikipedia itself is not copied to the Backup Disk. Numbered v2.2.2 because v2.3 and v2.3.1 are taken by the open PRs #530 and #536.
>
> v2.2.1 (16 November 2026): `idea-for-teachers-tutorial-v2.2.1.pdf`. Chapter 3 has a new section after 3.2, *Make a teacher the coach of the class*: the admin opens the class, clicks **ASSIGN COACHES**, ticks the teacher and confirms (the steps are the same on Kolibri 0.19.5, which this tutorial follows, and on the older 0.15.5). New screenshot K1-04. Numbered v2.2.1 because v2.3 and v2.3.1 are taken by the open PRs #530 and #536.
>
> v2.2 (14 November 2026): `idea-for-teachers-tutorial-v2.2.pdf`. Chapter 5 opens with an explicit first step: sign in to Nextcloud as `admin`, open **Accounts** and create the teacher and learner accounts (`<account name>911!`); Nextcloud has no self-signup. New screenshots NA-01 to NA-05.
>
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
> The v2.2.1, v2.2, v2.1.1, v2.1, v2.0, v1.9, v1.8, v1.7, v1.6 and v1.5 PDFs are kept in `superseded/`.

# Teacher tutorial

`idea-for-teachers-tutorial-v2.2.2.pdf` ("IDEA for Teachers: Tutorial", 55 pages, v2.2.2 of 25 November 2026, written for the Zimbabwe kit): Kolibri, Nextcloud, Wikipedia offline, Files Disk and
Backup Disk. The text follows the kit (Engines sunny-robin, happy-zebra, kind-panda; apps Kolibri Demo, Nextcloud Demo and Wikipedia (Demo) for practice); most screenshots still come from the demo server, see `SCREENSHOTS.md` for the retake list. Chapters 01–09 for teachers and an appendix with the demo accounts. Operator tasks (Console, disks, backups, card reset) are in *IDEA for Operators: Tutorial*.

Build: `python3 build.py` (uses `docs/house-style`; fails if a "to confirm" marker is left).
Sources: `teacher-tutorial.md` (front matter: title on the cover), `chapters/*.md`, `screenshots/` (only the shots used in
the text; the admin name masked and the Tailscale address blurred), `SCREENSHOTS.md` (how they were taken).

Demo passwords follow the public IDEA default (account name followed by `911!`, for example `teacher1911!`) and may appear in the text. No other passwords.
