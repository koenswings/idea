**Status:** Authoritative · **Maintained by:** Marco (with Atlas) · 14 November 2026

# SCREENSHOTS — IDEA tutorial

**Password rule:** a password field may show its masked dots (as in NA-04), but no shot may show a password in readable text, typed out or revealed with the eye icon.

Kolibri shots (CON-03, K*, E1–E3, S1–S2 as used in chapters 3 and 4) were taken with headless Playwright (Chromium, viewport 1280×800) on the shared agent box, from the Kolibri Demo test instance (Kolibri 0.19.5, IDEA Demo School, class Grade 5). The welcome window was dismissed in the browser and the page reloaded; forms for create, enroll and edit were filled and then cancelled, without saving. No passwords are visible. Console and Nextcloud shots are unchanged from earlier captures.

v2.2 (14 November 2026): NA-01 to NA-05 (chapter 5, *Before you start*) were taken with headless Playwright (Chromium, viewport 1280×800, light theme) on the shared agent box, from a test Nextcloud 31 instance with the school seed (`admin`, `teacher1`, `learner1`; groups `teachers` and `learners`). Signed in as `admin`; the first-run welcome window was closed. NA-01: sign-in page with only the account name typed, cropped to the sign-in box. NA-02: user menu, cropped. NA-03 and NA-05: Accounts page, cropped below the list. NA-04: New account form for `teacher2` in group `teachers`; the password field shows only dots, email left empty. The demo account `teacher2` was created for NA-05 and deleted again afterwards. No error or warning messages, no addresses or device names in any shot.

v2.1.1 (13 November 2026): E1-03 / S1-05 retaken after the **Correct** pop-up faded; E2-01 / S2-01 recropped so a full quiz question is visible and no heading is cut (the seed title **IDEA demo quiz** was cropped out of the frame). S2-02 was removed (unused). K5-04 was kept: cropping the hidden fourth lesson would have left a misleading **0 of 4**, so the appendix now names that hidden lesson.

Skipped (a save or a new learner attempt would have been needed, or the headless browser did not paint the item): the Manage resources topic and Fractions-item lists (the channel list is shown instead); the Create new quiz form and question list; an in-progress quiz with **SUBMIT QUIZ**; and the **Cake in quarters** activity itself. Unused older files for those IDs may still be in `screenshots/`.

Earlier capture notes (12–16 October 2026) follow for the non-Kolibri shots.


Captured with Playwright (Python, Chromium), viewport 1280×800. No passwords visible in any shot.
Earlier non-Kolibri retakes (15–16 October 2026) used the demo school **IDEA Demo School**, class **Grade 5**, and the accounts admin, teacher1, teacher2, learner1–3. Console shots were opened from the Console Apps card (CON-03).

| ID | Chapter | Login | File present |
|---|---|---|---|
| CON-01 | 02-getting-connected.md | none | yes |
| CON-03 | 02-getting-connected.md | none | yes |
| K1-01 | 03-kolibri-teachers.md | teacher1 | yes |
| K1-02 | 03-kolibri-teachers.md | admin | yes |
| K1-03 | 03-kolibri-teachers.md | admin | yes |
| K2-01 | 03-kolibri-teachers.md | admin | yes |
| K2-02 | 03-kolibri-teachers.md | admin | yes |
| K2-03 | 03-kolibri-teachers.md | admin | yes |
| K3-01a | 03-kolibri-teachers.md | teacher1 | yes |
| K3-01 | 03-kolibri-teachers.md | teacher1 | yes |
| K3-02 | 03-kolibri-teachers.md | teacher1 | yes |
| K3-03a | 03-kolibri-teachers.md | teacher1 | yes |
| K3-03 (unused in v2.1) | 03-kolibri-teachers.md | teacher1 | yes |
| K3-04 (unused in v2.1) | 03-kolibri-teachers.md | teacher1 | yes |
| K3-05 | 03-kolibri-teachers.md | teacher1 | yes |
| K4-01 | 03-kolibri-teachers.md | teacher1 | yes |
| K4-02 (unused in v2.1) | 03-kolibri-teachers.md | teacher1 | yes |
| K4-03a (unused in v2.1) | 03-kolibri-teachers.md | teacher1 | yes |
| K4-03 | 03-kolibri-teachers.md | teacher1 | yes |
| K5-01 | 03-kolibri-teachers.md | teacher1 | yes |
| K5-02 | 03-kolibri-teachers.md | teacher1 | yes |
| K5-03 | 03-kolibri-teachers.md | teacher1 | yes |
| K5-04 | 03-kolibri-teachers.md | teacher1 | yes |
| S1-01 | 04-kolibri-learners.md | learner1 | yes |
| S1-03 | 04-kolibri-learners.md | learner1 | yes |
| S1-04 (unused in v2.1) | 04-kolibri-learners.md | learner1 | yes |
| S1-05 | 04-kolibri-learners.md | learner3 | yes |
| S2-01 | 04-kolibri-learners.md | learner3 | yes |
| S2-03a (unused in v2.1) | 04-kolibri-learners.md | learner1 | yes |
| S2-03 | 04-kolibri-learners.md | learner1 | yes |
| NA-01 | 05-nextcloud-teachers.md | admin (sign-in page) | yes |
| NA-02 | 05-nextcloud-teachers.md | admin | yes |
| NA-03 | 05-nextcloud-teachers.md | admin | yes |
| NA-04 | 05-nextcloud-teachers.md | admin | yes |
| NA-05 | 05-nextcloud-teachers.md | admin | yes |
| N0-01 | 05-nextcloud-teachers.md | teacher1 | yes |
| N1-01 | 05-nextcloud-teachers.md | teacher1 | yes |
| N1-03 | 05-nextcloud-teachers.md | teacher1 | yes |
| N2-01 | 05-nextcloud-teachers.md | teacher1 | yes |
| N2-02 | 05-nextcloud-teachers.md | teacher1 | yes |
| N2-03a | 05-nextcloud-teachers.md | teacher1 | yes |
| N2-03 | 05-nextcloud-teachers.md | teacher1 | yes |
| N2-04 | 05-nextcloud-teachers.md | teacher1 | yes |
| N3-00 | 05-nextcloud-teachers.md | teacher1 | yes |
| N3-01 | 05-nextcloud-teachers.md | teacher1 | yes |
| N3-02 | 05-nextcloud-teachers.md | teacher1 | yes |
| N3-03 | 05-nextcloud-teachers.md | teacher1 | yes |
| S3-01 | 06-nextcloud-learners.md | learner1 | yes |
| S3-02 | 06-nextcloud-learners.md | learner1 | yes |
| S3-03 | 06-nextcloud-learners.md | learner1 | yes |
| S4-01 | 06-nextcloud-learners.md | anonymous link | yes |
| S4-02 | 06-nextcloud-learners.md | anonymous link | yes |
| W1-01 | 07-wikipedia-offline.md | none | yes |
| W1-02 | 07-wikipedia-offline.md | none | yes |
| W1-03a | 07-wikipedia-offline.md | none | yes |
| W1-03 | 07-wikipedia-offline.md | none | yes |
| W1-04 | 07-wikipedia-offline.md | none | yes |
| CON-01 | 10-console-basics.md | none | yes |

Not captured (skipped by rule): F1 files disk, B2–B4 backup/restore, C3–C4 operator disk view (needs Operator Login). Files Disk F2 shots not taken (no Files Disk on wh).

## To retake for IDEA Demo School (2026-10-15)

The text now uses the demo school **IDEA Demo School**, class **Grade 5** and the accounts `admin`, `teacher1`, `teacher2`, `learner1`–`learner3` (staff passwords follow `<name>911!`; learners sign in with their username only; see the appendix). Shots that show the old `demo-…` / `demo_…` names, `demo-Grade5A` or `demo-School` must be retaken on the Kolibri Demo test instance (this is now done for the Kolibri shots in chapters 3 and 4). No error messages and no readable passwords in any shot (see the password rule at the top).

- Kolibri teacher (ch. 3): K1-01–K1-03, K2-01–K2-03, K3-01a, K3-01–K3-05, K3-03a, K4-01–K4-03, K4-03a, K5-01–K5-04 (sign in as `teacher1`; K1-03/K2 class creation and enrolment as `admin`).
- Kolibri learner (ch. 4): S1-01, S1-03–S1-05, S2-01, S2-03, S2-03a (S2-02 was removed in v2.1.1; S2-03a is unused since v2.1) (sign in as `learner1` with the username only, then **NEXT**; learners have no password. An earlier version of this note said the learner sign-in asks for a password; that no longer applies).
- Nextcloud teacher (ch. 6): N0-01, N1-01, N1-03, N2-01–N2-04, N2-03a, N3-00–N3-03 (`teacher1`; folders Worksheets, Drop Zone, document Lesson plan, groups Grade 5 and teachers).
- Nextcloud learner (ch. 7): S3-01–S3-03 (`learner1`), S4-01, S4-02 (Drop Zone name visible).
- Files Disk (ch. 9): F2-06 (shared with group Grade 5).
- Channel builder (ch. 5, PR idea#205): C5-12–C5-15 if they show the Kolibri import as `demo_teacher1` (now `admin`).

## To retake for the Zimbabwe kit (2026-10-19)

The text (v1.1) follows the kit handed over on 18 October 2026. These shots still show the demo server or older content. Retake them on a kit Engine (one switched on at a time), with no error messages on screen.

- Console Apps page / Network view without the Demo apps or the "on <Engine>" label, or showing a lab Engine name or `kiwix-1.0.1`: CON-01, CON-04, O2-01, O2-03, O3-01, O4-01 (check), B2-00, B2-01, B2-10, B2-11, B2-12 (only Kolibri and Nextcloud ticked; the kit backs up all six apps), B2-13, B3-10a, B4-20–B4-28, F1-11, F1-12, F1-14, F2-01, C5-02.
- Channel builder shots that show an Engine name (ch. 5, builder not on the kit): SC-01–SC-04.
- Nextcloud shots with the group "Grade 5" (Nextcloud Demo has the groups teachers and learners): N1-01, N1-03, F2-06, F2-07.
- F2-02: old "demo-" folder names (now Worksheets, Teacher Notes).
- Khan Academy (not on the kit): K4-02, K4-03a, K4-03, K5-03, S1-05, S2-*.
- W1-01: "Powered by Kiwix" footer (minor; caption now "The library page").
