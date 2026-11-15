**Status:** Draft · **Maintained by:** Marco · 15 November 2026

# Make a Backup Stick (teacher guide)

`idea-backup-stick-guide-v1.0.pdf` ("IDEA for Teachers: Make a Backup Stick"): a short guide to the Console's **Make a Backup Disk** flow from a USB stick or an empty IDEA Disk (agent-console-dev#187, Engine agent-engine-dev#355, idea#404). It covers the four steps (Check, Erase, Re-dock, Create), what an empty IDEA Disk skips (Erase and Re-dock), the 8 GB minimum, the first backup within a minute and then daily at 02:30, and what to do if the stick is unplugged during Erase.

Every label and message in the guide is taken from the code of console#187 at `ae40516` (`src/store/makeBackupDisk.ts`, `EraseDialog.tsx`, `UnformattedDiskView.tsx`, `EmptyDiskPanel.tsx`, `src/store/erase.ts`). console#187 was not merged when this guide was written. If its wording changes before it merges, update this guide.

This is a standalone guide rather than a section of the teacher tutorial. Chapter 9 of *IDEA for Teachers: Tutorial* will point to it once it is updated. This guide does not yet say whether apps can be opened while a backup runs; that answer comes from the Engine team and goes into chapter 9 first.

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
| BS-05 | **Done. This disk is now a Backup Disk.** with the first-backup line and **Done** |
| BS-06 | An empty IDEA Disk with the card **Make this a Backup Disk** (*Back up every App every day at 02:30*) |
| BS-07 | **Make … a Backup Disk?** for the empty disk |
| BS-08 | The two steps **Checking the disk** and **Setting up the Backup Disk** |
