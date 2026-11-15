**Status:** Authoritative · **Maintained by:** Marco (with Atlas) · 15 November 2026 (v2.3: Engine answers on pausing, missed backups, a full disk and the backup time, idea#529; every app on the box is backed up, engine#424)

# 9. Keeping data safe: the Backup Disk

This chapter tells you what the Backup Disk keeps safe, what you notice while a backup runs, and what the operator can do when a backup is missed or the disk gets full. The operator looks after backups (*IDEA for Operators: Tutorial*); sections 9.4 and 9.5 are written for the operator, and are useful for any teacher who wants to know how it works.

## 9.1 What the Backup Disk keeps

This section explains what is copied, so you know what you can get back after a breakdown.

- A **Backup Disk** is a separate **IDEA Disk**, a USB stick or disk with the **backup** badge in the Console.
- A Backup Disk backs up **every app on its IDEA box**, including apps added later. Nobody has to pick the apps one by one.
- On an IDEA box that has not had this update yet, the Backup Disk keeps the apps that were ticked under **LINK TO INSTANCES** when it was made. The operator ticks every app there (*IDEA for Operators: Tutorial*, chapter 3.5).
- Every app is saved **in full**: Kolibri (classes, learners, progress, and the channels), Nextcloud (accounts, and the files inside Nextcloud) and Wikipedia. On the kit that is about 164 GB per IDEA box, which fits on its 240 GB Backup Disk.
- It does **not** save the **School Files** folder (chapter 8).
- If the IDEA box breaks, the operator restores the latest backup onto a spare disk. Only the work done after the last backup is lost.

## 9.2 What you notice while a backup runs

This section helps you plan lessons around backups.

- **Each app pauses only while it is being copied.** For that short time it can't be opened; it starts again by itself when its copy is done. The other apps stay open.
- The apps are copied one after another, so each one pauses only during its own turn. How long that takes depends on how much is in the app: a small app is quick, a big one takes longer. The very first backup of all apps takes about 2 h 15 min, so plan it outside lesson time.
- Some apps can be copied while they keep running. If that does not work, the app pauses for a moment instead, and the Console says "Backed up, but the App was briefly stopped". Nothing is wrong.
- An app that was already stopped is copied as it is and stays stopped.
- A backup you start with **Back up** and a backup that runs on its own work the same way.
- Never unplug the Backup Disk while a backup is running. A backup that is cut off (by unplugging or a power cut) is not repeated by itself; the Console says "The backup was interrupted." and the operator starts a new one with **Back up**.

## 9.3 When backups run

This section explains the backup times, so you know when an app may pause.

- The operator chooses how the Backup Disk works: **On demand** (only when someone presses **Back up**), **Immediate** (when the disk is next plugged in) or **Scheduled** (every day at a set time).
- A new scheduled Backup Disk backs up **every day at 02:30**, in the IDEA box's own time. The operator can change that time (section 9.4).
- **A missed backup runs once, after the box starts again.** If the IDEA box was switched off at the backup time, the backup starts by itself, usually within a minute after the box is switched on again, as long as the Backup Disk is plugged in.
- If the Backup Disk was unplugged at the backup time, the missed backup runs once when it is plugged back into the same IDEA box.
- After several missed nights there is still only **one** catch-up backup, not one per night. The Console may say "1 scheduled backup was missed." or, for example, "3 scheduled backups were missed."
- After 02:30 the Console's next-run line says "Next run tomorrow at 02:30", even when a catch-up backup is about to start. If the box was off at 02:30, expect the backup soon after it is switched on.
- If the IDEA box is usually switched off at night, its backup therefore runs soon after it is switched on in the morning, and each app pauses for a moment then. A backup time when the box is on, outside lesson time, avoids this (section 9.4).
- If the IDEA box's clock could not be set (for example after a start without internet), the Console says "Backup time unknown: this Pi's clock may be wrong". Backups still run, but not at a fixed time.

## 9.4 Change the backup time (operator)

This section lets the operator choose a backup time that suits the school, for example in the evening while the box is still on.

1. Open the Console (`http://idea.local`, or the address on the second line of the box's sticker) and open the **Backup Disk**.
2. Under **Backup mode**, choose **Scheduled**.
3. In **Daily time (24-hour, this Pi's local time)**, type the time, for example `21:00`.
4. Click **Save backup settings**. The Console confirms: "Saved. This disk will back up every day at 21:00 (this Pi's local time)." On a disk that has never made a scheduled backup it says "A first backup starts now, then daily at 21:00."

Good to know:

- The time is saved on the Backup Disk itself, so it stays the same when the disk is plugged in again.
- If the saved time can't be read, the disk still backs up at 02:30 and the Console says "The saved backup time is not valid, so this disk runs at 02:30 until it is fixed." Type the time again and click **Save backup settings**.
- On an IDEA box that has not had this update yet, these controls may not be shown. The backup mode was then chosen when the disk was made (*IDEA for Operators: Tutorial*, chapter 3.5).

## 9.5 When the Backup Disk gets full (operator)

This section tells the operator what the Console shows when space runs low, and what to do about it.

- **Old backups are cleaned up automatically.** Before and after each backup the IDEA box checks the free space. When it gets low, it deletes the oldest extra backups, but always keeps the newest three backups of every app.
- The Backup Disk shows how much space is left, for example "18% free", and "Cleaning up old backups" while it makes room.
- If there is still no room after the clean-up, the backup is not made and the Console says **"Backup Disk full: add a bigger disk"**. Replace the Backup Disk with a bigger stick or disk. A very first backup that runs out of room may instead stop with "The backup did not finish."; that also means the disk is too small.
- Kit backups are large: about 164 GB per IDEA box (section 9.1). Choose a Backup Disk that is big enough for all the apps of your school, with room to spare.
- On an IDEA box that has not had its update yet, the Console may say "Cleanup paused: Pi needs an update". Backups still run, but old ones are not cleaned up, so the disk fills up sooner.

A step-by-step operator guide for turning a USB stick into a Backup Disk in the Console, *IDEA for Operators: Make a Backup Stick*, is being prepared.
