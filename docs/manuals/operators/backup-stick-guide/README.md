**Status:** Draft · **Maintained by:** Marco · 15 November 2026

# Make a Backup Stick (operator guide)

`idea-backup-stick-guide-v1.0.pdf` ("IDEA for Operators: Make a Backup Stick"): a short guide for the **operator**, the person at the school who looks after the IDEA box. It covers the Console's **Make a Backup Disk** flow from a USB stick or an empty IDEA Disk (agent-console-dev#187, Engine agent-engine-dev#355, idea#404): the four steps (Check, Erase, Re-dock, Create), what an empty IDEA Disk skips (Erase and Re-dock), the size (more than 8 GB, and larger than all the App data on the Pi; a kit is about 164 GB), the first backup within a minute and then daily at 02:30, that each App pauses only while it is being copied, missed backups (one catch-up after the box starts again), changing the time on the Backup Disk panel, automatic clean-up when the stick gets full and "Backup Disk full", and what to do if the stick is unplugged during Erase. The Engine answers come from Axle (idea#529 review).

Every label and message in the guide is taken from the code of console#187 at `91e5d95`, plus `BackupModeControls.tsx`, `setBackupMode.ts` and `backupStatus.ts` at the same commit (`src/store/makeBackupDisk.ts`, `EraseDialog.tsx`, `UnformattedDiskView.tsx`, `EmptyDiskPanel.tsx`, `src/store/erase.ts`). console#187 was not merged when this guide was written. If its wording changes before it merges, update this guide. Once it merges, *IDEA for Operators: Tutorial* section 3.5 (the older Backup mode / Link to instances form) needs to point here too.

A new Backup Disk backs up every App on its IDEA box, including Apps added later (Koen's decision, agent-engine-dev#424).

This is a standalone guide next to the operator tutorial. Chapter 9 of *IDEA for Teachers: Tutorial* can point to it.

Build: `python3 build.py` (uses `docs/house-style`).
Source: `backup-stick-guide.md`.

## Screenshots to add later

v1.0 is text only, because console#187 was not running on a test instance. Take these on a test instance with headless Playwright once it runs there. They must show no error or warning messages, and no addresses, ports or device names (crop the IDEA box name in the list and in "Sent to …, waiting for confirmation…").

| ID | Shows |
|---|---|
| BS-01 | A plugged-in stick in the list on the left (read-only USB stick row) |
| BS-02 | The stick's right pane with **Make a Backup Disk** and its hint |
| BS-03 | The window **Make a Backup Disk from …?** with the stick's details, the erase warning, the 02:30 text and the name typed (button on) |
| BS-04 | The four steps, with **Erasing the disk** current |
| BS-05 | **Done. This disk is now a Backup Disk.** with "Backups run every day at 02:30 for every App on this Pi. Apps pause for a moment while a backup runs." and **Done** |
| BS-06 | An empty IDEA Disk with the card **Make this a Backup Disk** (*Daily backups at 02:30, nothing erased*) |
| BS-07 | **Make … a Backup Disk?** for the empty disk |
| BS-08 | The two steps **Checking the disk** and **Setting up the Backup Disk** |
