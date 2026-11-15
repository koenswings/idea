---
title: "Nextcloud update for schools"
subtitle: "A same-major patch update to App version 1.8-31.0.14"
audience: "Version 1.8-31.0.14, 15 November 2026"
cover_logo: "yes"
version: "1.8-31.0.14"
---
**Status:** Draft · **Maintained by:** Marco · 15 November 2026

# Nextcloud update for schools

This short note is for school operators and teachers. It explains a small Nextcloud update that you can run from the Console when it is offered. It says what changes, what stays the same, and what to do while the update runs.

## For operators

This section is for the person who looks after the IDEA box. It tells you what this update is, what it does, and how to run it safely.

### What this update is

This section says which Nextcloud version you are moving to.

This is a **same-major patch update**. Nextcloud stays on version 31. Only the small number at the end changes, from **31.0.1** to **31.0.14**. The App version becomes **1.8-31.0.14** (from 1.7-31.0.1). It is not a jump to a new Nextcloud generation (32 or later).

### What changes

This section says what the update does, and what stays the same.

Nextcloud itself moves to a later 31.0 patch. On the first start of the new version, Nextcloud upgrades its own database. Files and accounts are kept. Nextcloud stays in maintenance mode until that upgrade has finished, so people cannot use Nextcloud during the update.

The database software (MariaDB) and Office (Collabora) stay on the same versions as before. The bundled Office connector and the IDEA usage app also stay as they are.

### The backup it takes first

This section explains the copy the box makes before it updates Nextcloud.

Before the update starts, the box makes a safety copy of Nextcloud (your files, accounts and settings) on the same disk as Nextcloud. You do not need a Backup Disk for this update. Your usual nightly backups continue as they are. If a Backup Disk is already plugged in, you can leave it.

The box checks there is enough free space for the safety copy before it starts. If there is not, the update does not begin and Nextcloud stays as it is.

Keep the IDEA box switched on, and do not unplug any disks while the update runs.

### How long Nextcloud is unavailable

This section says how long teachers and learners may have to wait.

Nextcloud is unavailable for a few minutes while the update runs. On one test, on an IDEA box with a small school, this was about 3¼ minutes. A school with more files and accounts may need a little longer. Choose a time with no lessons.

### What to do

This section is a short checklist for the person who runs the update.

1. Choose a time with no lessons, so teachers and learners are not in the middle of work.
2. You do not need a Backup Disk for this update. If one is already plugged in for your usual nightly backups, you can leave it.
3. Keep the IDEA box switched on for the whole update. Do not switch it off and do not unplug the power.
4. Do not unplug any disks while the update runs.
5. Wait until the Console shows that the update has finished, and check that you can open Nextcloud.

### If something goes wrong

This section says what the box does if the update does not finish, and what you should do.

If the update goes wrong, the box goes back to the old Nextcloud by itself, with your files and accounts as they were. You may notice Nextcloud is away for a few minutes. This has been tested.

If the box cannot go back, Nextcloud is left stopped and the safety copy is kept. Leave the IDEA box switched on, and do not unplug any disks. Then get help, using the contacts below. Do not try to fix it by unplugging disks or switching the box off.

### How to get help

This section says how to reach IDEA if you need a hand.

Email [idea-support@agentmail.to](mailto:idea-support@agentmail.to) or message the IDEA support bot on Telegram: [@IDEA_SupportBot](https://t.me/IDEA_SupportBot). You do not need to telephone anyone.

## For teachers

This section is for teachers. It says, in plain words, what you and your class may notice.

Nextcloud is getting a small safety and maintenance update. Your files and accounts are kept. While the update runs, Nextcloud is unavailable, so you cannot open files or Office. On our test this wait was about 3¼ minutes; a school with more files may need a little longer. If you try to open Nextcloud during that time, you may see a page that says it is being maintained, or it may simply not open. When the update has finished, Nextcloud works as before, including Office.

If the update does not finish, the box goes back to the previous Nextcloud by itself, with your files and accounts as they were.
