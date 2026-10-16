# Authoritative Documentation Index — IDEA (Org Level)

Authoritative descriptions of IDEA's organisation, infrastructure, and operations **as they
currently exist** — not as they are intended or planned (that's `proposals/`).

Update this file whenever an authoritative doc is added or significantly revised.

---

## grok-bot-setup.md
**Status:** Authoritative  ·  **Maintained by:** Atlas / Steve
IDEA development setup on Grok Bot: platform, fleet scripts, workflows (Dev Bot + SSH;
Grok Build runner path parked, idea#147), fleet-Pi test claim protocol (§4.6), quality
control (§5), routines, team structure, and Bot descriptions.
→ [docs/grok-bot-setup.md](grok-bot-setup.md)

## README.md
**Status:** Authoritative  ·  **Maintained by:** Koen / Steve
Short orientation for the `docs/` folder.
→ [docs/README.md](README.md)

## DOCUMENTATION-RULES.md
**Status:** Approved (#189)  ·  **Maintained by:** Steve / Atlas
Extends proposals/README.md and docs/README.md: adds docs/manuals/<audience>/<name>/ and docs/house-style/; naming, build and secrets rules; inventory with current locations.
→ [docs/DOCUMENTATION-RULES.md](DOCUMENTATION-RULES.md)

## Manuals and house style (docs/manuals/, docs/house-style/)

### House style module
**Status:** Authoritative  ·  **Maintained by:** Atlas / Marco
The single IDEA house style for project PDFs (housestyle.py, house.css). Build scripts find it by walking up to docs/house-style or via IDEA_HOUSE_STYLE.
→ [docs/house-style/](house-style/)

Files: `house-style/README.md`, `house-style/house.css`, `house-style/housestyle.py`, `house-style/idea-logo.svg`

### Teacher tutorial (teacher-tutorial.pdf)
**Status:** Authoritative  ·  **Maintained by:** Marco / Atlas
"IDEA for Teachers: Tutorial": Kolibri, the channel builder and teacher USB sticks (chapter 5, draft pending idea#193 release), Nextcloud, Wikipedia offline, Files Disk, Backup Disk; Part B for the school operator.
→ [docs/manuals/teachers/teacher-tutorial/](manuals/teachers/teacher-tutorial/)

Files: `manuals/teachers/teacher-tutorial/README.md`, `manuals/teachers/teacher-tutorial/SCREENSHOTS.md`, `manuals/teachers/teacher-tutorial/build.py`, `manuals/teachers/teacher-tutorial/chapters/01-what-idea-is.md`, `manuals/teachers/teacher-tutorial/chapters/02-getting-connected.md`, `manuals/teachers/teacher-tutorial/chapters/03-kolibri-teachers.md`, `manuals/teachers/teacher-tutorial/chapters/04-kolibri-learners.md`, `manuals/teachers/teacher-tutorial/chapters/05-channel-builder-usb-sticks.md`, `manuals/teachers/teacher-tutorial/chapters/06-nextcloud-teachers.md`, `manuals/teachers/teacher-tutorial/chapters/07-nextcloud-learners.md`, `manuals/teachers/teacher-tutorial/chapters/08-wikipedia-offline.md`, `manuals/teachers/teacher-tutorial/chapters/09-files-disk.md`, `manuals/teachers/teacher-tutorial/chapters/10-backup-concepts.md`, `manuals/teachers/teacher-tutorial/chapters/11-operator-console.md`, `manuals/teachers/teacher-tutorial/chapters/12-operator-disks.md`, `manuals/teachers/teacher-tutorial/chapters/13-operator-student-computers.md`, `manuals/teachers/teacher-tutorial/chapters/14-appendix-demo-accounts.md`, `manuals/teachers/teacher-tutorial/chapters/15-appendix-activating-demo.md`, `manuals/teachers/teacher-tutorial/screenshots/B2-00.png`, `manuals/teachers/teacher-tutorial/screenshots/B2-01.png`, `manuals/teachers/teacher-tutorial/screenshots/B2-10.png`, `manuals/teachers/teacher-tutorial/screenshots/B2-11.png`, `manuals/teachers/teacher-tutorial/screenshots/B2-12.png`, `manuals/teachers/teacher-tutorial/screenshots/B2-13.png`, `manuals/teachers/teacher-tutorial/screenshots/B3-10a.png`, `manuals/teachers/teacher-tutorial/screenshots/B4-20.png`, `manuals/teachers/teacher-tutorial/screenshots/B4-21.png`, `manuals/teachers/teacher-tutorial/screenshots/B4-22.png`, `manuals/teachers/teacher-tutorial/screenshots/B4-23a.png`, `manuals/teachers/teacher-tutorial/screenshots/B4-28.png`, `manuals/teachers/teacher-tutorial/screenshots/B4-31.png`, `manuals/teachers/teacher-tutorial/screenshots/B4-33.png`, `manuals/teachers/teacher-tutorial/screenshots/C5-02.png`, `manuals/teachers/teacher-tutorial/screenshots/C5-03.png`, `manuals/teachers/teacher-tutorial/screenshots/C5-04.png`, `manuals/teachers/teacher-tutorial/screenshots/C5-05.png`, `manuals/teachers/teacher-tutorial/screenshots/C5-06.png`, `manuals/teachers/teacher-tutorial/screenshots/C5-07.png`, `manuals/teachers/teacher-tutorial/screenshots/C5-08.png`, `manuals/teachers/teacher-tutorial/screenshots/C5-10.png`, `manuals/teachers/teacher-tutorial/screenshots/C5-11.png`, `manuals/teachers/teacher-tutorial/screenshots/C5-12.png`, `manuals/teachers/teacher-tutorial/screenshots/C5-13.png`, `manuals/teachers/teacher-tutorial/screenshots/C5-14.png`, `manuals/teachers/teacher-tutorial/screenshots/C5-15.png`, `manuals/teachers/teacher-tutorial/screenshots/CON-01.png`, `manuals/teachers/teacher-tutorial/screenshots/CON-03.png`, `manuals/teachers/teacher-tutorial/screenshots/CON-04.png`, `manuals/teachers/teacher-tutorial/screenshots/F1-11.png`, `manuals/teachers/teacher-tutorial/screenshots/F1-12.png`, `manuals/teachers/teacher-tutorial/screenshots/F1-14.png`, `manuals/teachers/teacher-tutorial/screenshots/F2-01.png`, `manuals/teachers/teacher-tutorial/screenshots/F2-02.png`, `manuals/teachers/teacher-tutorial/screenshots/F2-03.png`, `manuals/teachers/teacher-tutorial/screenshots/F2-06.png`, `manuals/teachers/teacher-tutorial/screenshots/F2-07.png`, `manuals/teachers/teacher-tutorial/screenshots/IDEA-01.png`, `manuals/teachers/teacher-tutorial/screenshots/IDEA-02.png`, `manuals/teachers/teacher-tutorial/screenshots/K1-01.png`, `manuals/teachers/teacher-tutorial/screenshots/K1-02.png`, `manuals/teachers/teacher-tutorial/screenshots/K1-03.png`, `manuals/teachers/teacher-tutorial/screenshots/K2-01.png`, `manuals/teachers/teacher-tutorial/screenshots/K2-02.png`, `manuals/teachers/teacher-tutorial/screenshots/K2-03.png`, `manuals/teachers/teacher-tutorial/screenshots/K3-01.png`, `manuals/teachers/teacher-tutorial/screenshots/K3-01a.png`, `manuals/teachers/teacher-tutorial/screenshots/K3-02.png`, `manuals/teachers/teacher-tutorial/screenshots/K3-03.png`, `manuals/teachers/teacher-tutorial/screenshots/K3-03a.png`, `manuals/teachers/teacher-tutorial/screenshots/K3-04.png`, `manuals/teachers/teacher-tutorial/screenshots/K3-05.png`, `manuals/teachers/teacher-tutorial/screenshots/K4-01.png`, `manuals/teachers/teacher-tutorial/screenshots/K4-02.png`, `manuals/teachers/teacher-tutorial/screenshots/K4-03.png`, `manuals/teachers/teacher-tutorial/screenshots/K4-03a.png`, `manuals/teachers/teacher-tutorial/screenshots/K5-01.png`, `manuals/teachers/teacher-tutorial/screenshots/K5-02.png`, `manuals/teachers/teacher-tutorial/screenshots/K5-03.png`, `manuals/teachers/teacher-tutorial/screenshots/K5-04.png`, `manuals/teachers/teacher-tutorial/screenshots/N0-01.png`, `manuals/teachers/teacher-tutorial/screenshots/N1-01.png`, `manuals/teachers/teacher-tutorial/screenshots/N1-03.png`, `manuals/teachers/teacher-tutorial/screenshots/N2-01.png`, `manuals/teachers/teacher-tutorial/screenshots/N2-02.png`, `manuals/teachers/teacher-tutorial/screenshots/N2-03.png`, `manuals/teachers/teacher-tutorial/screenshots/N2-03a.png`, `manuals/teachers/teacher-tutorial/screenshots/N2-04.png`, `manuals/teachers/teacher-tutorial/screenshots/N3-00.png`, `manuals/teachers/teacher-tutorial/screenshots/N3-01.png`, `manuals/teachers/teacher-tutorial/screenshots/N3-02.png`, `manuals/teachers/teacher-tutorial/screenshots/N3-03.png`, `manuals/teachers/teacher-tutorial/screenshots/O1-01.png`, `manuals/teachers/teacher-tutorial/screenshots/O2-00.png`, `manuals/teachers/teacher-tutorial/screenshots/O2-01.png`, `manuals/teachers/teacher-tutorial/screenshots/O2-03.png`, `manuals/teachers/teacher-tutorial/screenshots/O3-01.png`, `manuals/teachers/teacher-tutorial/screenshots/O4-01.png`, `manuals/teachers/teacher-tutorial/screenshots/S1-01.png`, `manuals/teachers/teacher-tutorial/screenshots/S1-03.png`, `manuals/teachers/teacher-tutorial/screenshots/S1-04.png`, `manuals/teachers/teacher-tutorial/screenshots/S1-05.png`, `manuals/teachers/teacher-tutorial/screenshots/S2-01.png`, `manuals/teachers/teacher-tutorial/screenshots/S2-02.png`, `manuals/teachers/teacher-tutorial/screenshots/S2-03.png`, `manuals/teachers/teacher-tutorial/screenshots/S2-03a.png`, `manuals/teachers/teacher-tutorial/screenshots/S3-01.png`, `manuals/teachers/teacher-tutorial/screenshots/S3-02.png`, `manuals/teachers/teacher-tutorial/screenshots/S3-03.png`, `manuals/teachers/teacher-tutorial/screenshots/S4-01.png`, `manuals/teachers/teacher-tutorial/screenshots/S4-02.png`, `manuals/teachers/teacher-tutorial/screenshots/SC-01.png`, `manuals/teachers/teacher-tutorial/screenshots/SC-02.png`, `manuals/teachers/teacher-tutorial/screenshots/SC-03.png`, `manuals/teachers/teacher-tutorial/screenshots/SC-04.png`, `manuals/teachers/teacher-tutorial/screenshots/W1-01.png`, `manuals/teachers/teacher-tutorial/screenshots/W1-02.png`, `manuals/teachers/teacher-tutorial/screenshots/W1-03.png`, `manuals/teachers/teacher-tutorial/screenshots/W1-03a.png`, `manuals/teachers/teacher-tutorial/screenshots/W1-04.png`, `manuals/teachers/teacher-tutorial/teacher-tutorial.md`, `manuals/teachers/teacher-tutorial/teacher-tutorial.pdf`

### Lesson manuals (Grade 5A fractions, Form 3 variables)
**Status:** Authoritative  ·  **Maintained by:** Marco / Tapiwa
Step-by-step Kolibri lesson manuals for class teachers, with screenshots.
→ [docs/manuals/teachers/lesson-manuals/](manuals/teachers/lesson-manuals/)

Files: `manuals/teachers/lesson-manuals/README.md`, `manuals/teachers/lesson-manuals/SCREENSHOTS.md`, `manuals/teachers/lesson-manuals/build.py`, `manuals/teachers/lesson-manuals/form3-variables-and-expressions.md`, `manuals/teachers/lesson-manuals/form3-variables-and-expressions.pdf`, `manuals/teachers/lesson-manuals/grade5a-add-and-subtract-fractions.md`, `manuals/teachers/lesson-manuals/grade5a-add-and-subtract-fractions.pdf`, `manuals/teachers/lesson-manuals/shots/f3-04-sign-in.png`, `manuals/teachers/lesson-manuals/shots/f3-05-classes.png`, `manuals/teachers/lesson-manuals/shots/f3-06-lessons.png`, `manuals/teachers/lesson-manuals/shots/f3-07-resources.png`, `manuals/teachers/lesson-manuals/shots/f3-08-recipients.png`, `manuals/teachers/lesson-manuals/shots/f3-09-visible.png`, `manuals/teachers/lesson-manuals/shots/f3-10-student-lesson.png`, `manuals/teachers/lesson-manuals/shots/f3-11-student-video.png`, `manuals/teachers/lesson-manuals/shots/f3-12-student-exercise.png`, `manuals/teachers/lesson-manuals/shots/f3-13-reports-lesson.png`, `manuals/teachers/lesson-manuals/shots/f3-14-reports-progress.png`, `manuals/teachers/lesson-manuals/shots/g5a-01-network.png`, `manuals/teachers/lesson-manuals/shots/g5a-02-disk-apps.png`, `manuals/teachers/lesson-manuals/shots/g5a-03-app-open.png`, `manuals/teachers/lesson-manuals/shots/g5a-04-sign-in.png`, `manuals/teachers/lesson-manuals/shots/g5a-05-classes.png`, `manuals/teachers/lesson-manuals/shots/g5a-06-lessons.png`, `manuals/teachers/lesson-manuals/shots/g5a-07-resources.png`, `manuals/teachers/lesson-manuals/shots/g5a-08-recipients.png`, `manuals/teachers/lesson-manuals/shots/g5a-09-visible.png`, `manuals/teachers/lesson-manuals/shots/g5a-10-student-lesson.png`, `manuals/teachers/lesson-manuals/shots/g5a-11-student-video.png`, `manuals/teachers/lesson-manuals/shots/g5a-12-student-exercise.png`, `manuals/teachers/lesson-manuals/shots/g5a-13-reports-lesson.png`, `manuals/teachers/lesson-manuals/shots/g5a-14-reports-progress.png`

### Install manuals: school server and client Pi 400
**Status:** Authoritative (follows idea#184; not yet run on hardware)  ·  **Maintained by:** Marco / Atlas
School server (Starlink, Cudy/OpenWrt, PoE switch, 2x Pi 5 Engines, sticker names, tag:idea) and classroom Pi 400 manuals, plus the router scripts.
→ [docs/manuals/install/](manuals/install/)

Files: `manuals/install/README.md`, `manuals/install/install-manual-classroom-computer/build.py`, `manuals/install/install-manual-classroom-computer/diagrams/m2-budget.svg`, `manuals/install/install-manual-classroom-computer/diagrams/m2-cards.svg`, `manuals/install/install-manual-classroom-computer/diagrams/m2-wiring.svg`, `manuals/install/install-manual-classroom-computer/install-manual-classroom-computer.md`, `manuals/install/install-manual-classroom-computer/install-manual-classroom-computer.pdf`, `manuals/install/install-manual-school-server/build.py`, `manuals/install/install-manual-school-server/diagrams/m1-flash.svg`, `manuals/install/install-manual-school-server/diagrams/m1-tailscale.svg`, `manuals/install/install-manual-school-server/diagrams/m1-where.svg`, `manuals/install/install-manual-school-server/diagrams/m1-wiring.svg`, `manuals/install/install-manual-school-server/diagrams/m1-zones.svg`, `manuals/install/install-manual-school-server/install-manual-school-server.md`, `manuals/install/install-manual-school-server/install-manual-school-server.pdf`, `manuals/install/scripts/make-install-diagrams.py`, `manuals/install/scripts/router-starlink-cgnat-exception.sh`, `manuals/install/scripts/router-tailscale-zone.sh`, `manuals/install/scripts/school-router-setup.sh`

### Remote access guide (demo server over Tailscale)
**Status:** Authoritative  ·  **Maintained by:** Marco / Atlas
How Koen shares wizardly-hugle and how the field engineer reaches it over Tailscale. Contains the demo server's Tailscale IP on purpose (see its README).
→ [docs/manuals/field/remote-access-guide/](manuals/field/remote-access-guide/)

Files: `manuals/field/remote-access-guide/README.md`, `manuals/field/remote-access-guide/build.py`, `manuals/field/remote-access-guide/diagrams/checks.svg`, `manuals/field/remote-access-guide/diagrams/flow.svg`, `manuals/field/remote-access-guide/diagrams/make_diagrams.py`, `manuals/field/remote-access-guide/diagrams/overview.svg`, `manuals/field/remote-access-guide/diagrams/privacy.svg`, `manuals/field/remote-access-guide/remote-access-guide.md`, `manuals/field/remote-access-guide/remote-access-guide.pdf`
## ops/boot-recovery.md
**Status:** Authoritative  ·  **Maintained by:** Atlas
What comes back after a reboot, fstab loop mounts for fixture disks (rules, rollback), the 05:00 reboot hold, after-reboot checklist.
→ [docs/ops/boot-recovery.md](ops/boot-recovery.md)

## ops/engine-deploy-pool-pi.md
**Status:** Authoritative  ·  **Maintained by:** Atlas
Option-2 Engine deploy on a pool Pi: save, discard, check out and restore config.yaml, pm2.config.cjs and every store-identity file; abort before pm2 restart unless store-url.txt is still 2VroE. Script `tools/fleet/deploy-engine-pi.sh`.
→ [docs/ops/engine-deploy-pool-pi.md](ops/engine-deploy-pool-pi.md)

## ops/store-compaction-devpool.md
**Status:** Authoritative (executed 2026-10-13)  ·  **Maintained by:** Atlas
Runbook for compacting the dev-pool Automerge store into a fresh document (freeze, merge heads, swap, verify 13-18, rollback), with the result record: 3zoqd -> 2VroE on 2026-10-13 14:54-15:14 CEST, cover-all r86t 128/128 afterwards.
→ [docs/ops/store-compaction-devpool.md](ops/store-compaction-devpool.md)
