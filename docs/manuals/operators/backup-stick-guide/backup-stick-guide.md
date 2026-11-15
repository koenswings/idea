---
title: "IDEA for Operators: Make a Backup Stick"
subtitle: "Turn a USB stick or an empty IDEA Disk into a Backup Disk from the Console"
audience: "Version 1.0, 15 November 2026"
cover_logo: "yes"
---
**Status:** Draft · **Maintained by:** Marco · 15 November 2026

This short guide is for the **operator**: the person at the school who looks after the IDEA box. It shows you how to turn a USB stick, or an empty IDEA Disk, into a **Backup Disk** in the Console. A Backup Disk keeps a copy of the apps on the IDEA box, so that the school's classes, learners and files can be brought back if the box ever breaks. It takes a few clicks, and the Console tells you what is happening at each step.

*IDEA for Teachers: Tutorial*, chapter 9, explains what a Backup Disk is and what it saves; *IDEA for Operators: Tutorial*, chapter 3, covers the disks and backups in general. The words used here (IDEA box, Console, IDEA Disk, Backup Disk) are explained in chapter 1 of the teacher tutorial.

## 1. Before you start

This section helps you pick a stick and get to the right place in the Console.

**Pick a stick or disk.** Good to know:

- **Size: more than 8 GB.** The Console refuses anything smaller. A stick sold as "8 GB" is a little smaller than that inside, so it is refused too.
- **Larger than all the App data on the IDEA box.** The Backup Disk keeps a full copy of every app on the box, and kit backups are large: on the IDEA kit the apps take about 164 GB together (chapter 9). Choose a stick or disk larger than all the App data on the box, with room to spare, so that it can keep several backups.
- **A USB stick is erased.** Everything on it is removed for good. Use a new stick, or one with nothing anyone needs on it. Don't use a stick that holds lesson material the teachers still want.
- **An empty IDEA Disk is not erased.** If the Console already shows the disk as an empty IDEA Disk, nothing on it is removed (section 3).

**Open the Console and log in.** On a classroom computer, open the browser and go to **http://idea.local** (or **http://&lt;sticker&gt;.local**, using the name on the box's sticker). Log in as operator with the person icon, top right (*IDEA for Operators: Tutorial*, section 2.1).

**Plug in the stick.** Plug the stick into the IDEA box and wait a moment. It appears in the list on the left, under the IDEA box:

- a new shop stick usually shows as **USB stick: … (read-only, …)** with a **read-only** badge;
- other disks show their name and size with an **unformatted** badge;
- an empty IDEA Disk shows as an IDEA Disk with nothing on it yet.

Click the stick to open it on the right.

## 2. Make a Backup Disk from a USB stick

This section walks you through the four steps the IDEA box takes when it turns a stick into a Backup Disk: it checks the stick, erases it, waits for it to come back, and sets it up.

1. On the right, click **Make a Backup Disk**. Under the button the Console says: *"Erases this stick, then makes it a Backup Disk with daily backups at 02:30. Needs a disk larger than 8 GB. Choose a disk larger than all the App data on this Pi."* If the stick is too small, the button stays grey and the Console says: *"Too small: needs more than 8 GB. Choose a disk larger than all the App data on this Pi."*
2. A window opens with the title **Make a Backup Disk from &lt;stick name&gt;?** The Console first says **Reading the disk…**, then shows what it found on the stick: its name, size and anything stored on it.
3. Read the warning: *"This erases everything on the disk. Apps, backups and files cannot be recovered."* Below it the Console says: *"After erasing, backups run every day at 02:30 for every App on this Pi. You can change the time later."* (The Pi is the IDEA box.)
4. The Console asks you to type the stick's name. Type the disk's name as shown; capitals don't matter. The red button **Erase and make a Backup Disk** turns on when the name matches. Click it. If you change your mind, click **Cancel**: nothing has been changed yet.
5. The window now shows the four steps and ticks them off as the box works through them:

| Step | What the Console shows | What happens |
|---|---|---|
| Check | **Checking the disk** | The box checks that this is the stick you confirmed and that it is more than 8 GB. |
| Erase | **Erasing the disk** | Everything on the stick is removed. |
| Re-dock | **Waiting for the disk to come back** | The box picks the erased stick up again as an IDEA Disk. |
| Create | **Setting up the Backup Disk** | The box makes the stick a Backup Disk for every app. |

6. When it is finished the Console says: *"Done. This disk is now a Backup Disk."* and *"Backups run every day at 02:30 for every App on this Pi. Apps pause for a moment while a backup runs."* Click **Done**. The Console then shows the stick as a Backup Disk.

Leave the stick plugged into the IDEA box. Please don't unplug it while the steps are running. If a step takes a long time, the Console says *"This is taking longer than expected. Don't unplug the disk."*: that is normal for a big stick, so just give it more time.

If the window waits more than ten minutes on the stick's details before you confirm, the Console asks you to look again (*"The summary is out of date. Check the disk again."*). Click **Check the disk again** and type the disk's name as shown once more; capitals don't matter.

## 3. Make a Backup Disk from an empty IDEA Disk

This section is for a disk the Console already shows as an empty IDEA Disk. Because the disk is already an IDEA Disk with nothing on it, the box skips the Erase and Re-dock steps and nothing is erased.

1. Click the empty disk on the left. On the right, click the card **Make this a Backup Disk** (*"Daily backups at 02:30, nothing erased"*). If the disk is too small, the card is grey and the Console says: *"Too small: needs more than 8 GB. Choose a disk larger than all the App data on this Pi."*
2. The Console asks **Make &lt;disk name&gt; a Backup Disk?** and says: *"Nothing on this disk is erased. Backups run every day at 02:30 for every App on this Pi. You can change the time later."*
3. Click **Make this a Backup Disk**. The Console says the request was sent and is waiting for confirmation, and then shows two steps: **Checking the disk** and **Setting up the Backup Disk**.
4. When it is finished, the Console says *"Done. This disk is now a Backup Disk."* and *"Backups run every day at 02:30 for every App on this Pi. Apps pause for a moment while a backup runs."* Click **← Back**.

If, after step 1, you see a form with **Backup mode** and **Link to instances** instead, the IDEA box has not been updated for this flow yet. Follow *IDEA for Operators: Tutorial*, section 3.5, instead.

## 4. When the backups run

This section tells you when the new Backup Disk does its work, so you know what to expect and can tell the teachers.

- **The Backup Disk backs up every App on the IDEA box**, including apps added later. You don't need to pick the apps.
- **The first backup starts within a minute** of the Console saying *Done*. A first full backup can take a few hours. Leave the stick plugged in until it has finished.
- **After that, a backup runs every day at 02:30**, at night, outside lesson time. Leave the stick plugged into the IDEA box so that it is there at 02:30.
- **Each App pauses only while it is being copied.** The box backs up the apps one after another, so only the app being copied is closed for a short while, and it starts again by itself. The other apps keep working. Because the first backup starts straight away, it is best to make a Backup Disk when no lessons are using the apps. Some apps can be copied while they keep running; if one of them had to be paused after all, the Console says *"Backed up, but the App was briefly stopped"*.
- **A missed backup runs once, as soon as it can.** If the box was switched off at 02:30, the missed backup starts once, usually within a minute of the box starting again. If the stick was unplugged at 02:30, it starts once when you plug the stick back into the same box. After several missed nights there is still only one catch-up backup, and the Console may say, for example, *"1 scheduled backup was missed."*
- **Don't wait for the "Next run" line after a missed night.** The Backup Disk panel may still say *"Next run tomorrow at 02:30"* while the catch-up backup is already about to start.

### Change the backup time

This part shows you how to move the daily backup to another time, for example to the evening when the box is still on.

1. In the list on the left, click the Backup Disk. The right side shows the Backup Disk panel, with the **Backup Disk** badge and the text *"Choose how this disk backs up its Apps."*
2. Under **Backup mode**, keep **Scheduled** chosen.
3. In **Daily time (24-hour, this Pi's local time)**, type the new time, for example 21:00.
4. Click **Save backup settings**. The Console confirms: *"Saved. This disk will back up every day at 21:00 (this Pi's local time)."* If the disk has not made a scheduled backup yet, it says *"A first backup starts now, then daily at 21:00."* instead.

If the Console says *"That isn't a valid time. Use 24-hour time, for example 02:30."*, type the time with a colon, from 00:00 to 23:59.

## 5. When the Backup Disk gets full

This section explains how the Backup Disk makes room for new backups, and what to do when it can't.

- **Old backups are cleaned up automatically.** Before and after each backup, the box checks how much room is left. When the stick gets full, it removes the oldest backups by itself, but it always keeps the newest three backups of each app. While it does this, the Backup Disk panel says *"Cleaning up old backups"*. The panel also shows how much room is left, for example *"18% free"*.
- **If the Console says "Backup Disk full: add a bigger disk"**, the newest three backups of each app already fill the stick and the next backup doesn't fit. Get a bigger stick or disk and make it the Backup Disk.
- **The first backup on a stick that is too small** can stop half-way with *"The backup did not finish."* That also means the stick is too small for the school's apps: use a bigger one.
- **If the Console says "Cleanup paused: Pi needs an update"** or *"This Pi needs an update before backups can clean up old copies"*, backups still run but old ones are not removed, so the stick fills up faster. Write to your IDEA contact so the box can be updated.

## 6. If the stick was unplugged during Erase

This section tells you how to carry on if the stick came out while the box was erasing it or waiting for it to come back. Nothing is broken: you simply start again.

1. The Console says: *"The disk was unplugged during setup. Plug it back in and try again."* Click **Close**.
2. Plug the stick back into the same IDEA box and wait until it shows in the list on the left again.
3. Start again from the way the stick now shows. If it shows as a **USB stick** or **unformatted**, follow section 2 again: the box checks the stick again, so you type its name once more. If it shows as an **empty IDEA Disk** (the erase had already finished), follow section 3: nothing more is erased.

What was on the stick before may already be gone, because the erase had started. The box doesn't pick up where it stopped; it always starts again from the beginning.

If the Console says *"The disk was erased but didn't come back. Unplug it, plug it back in and try again."*, the erase finished but the box didn't pick the stick up again. Unplug the stick, plug it back in, and then carry on with step 3 above.

## 7. Other messages you may see

This section lists the other messages the Console may show, and what to do.

| The Console says | What to do |
|---|---|
| Too small: needs more than 8 GB. Choose a disk larger than all the App data on this Pi. | Use a bigger stick or disk, larger than all the App data on the IDEA box (section 1). |
| The name you typed doesn't match the disk's name. | Type the disk's name as shown; capitals don't matter. |
| This is not the disk that was checked. Check the disk again. | Another stick was plugged in. Close the window and start again with the stick you want. |
| The check of this disk is too old. Check the disk again. | Click **Check the disk again**, or close the window and start again. |
| This disk is no longer available. Check that it is plugged in. | Check the stick is plugged into the IDEA box, then try again. |
| This disk is not plugged into this Pi. | Plug the stick into this IDEA box and try again. |
| Something else is running on this Pi. Wait for it to finish, then try again. | Wait a few minutes, then try again. |
| An app is using this disk. Stop or move the app first. | In the Console, stop or move the app that is on this disk, then try again. |
| This disk is already a Backup Disk. | Nothing to do: it is already a Backup Disk. |
| This is the Pi's own system disk, so it can't be a Backup Disk. | This is the box's own disk, not a stick you can use. Choose a USB stick or an empty IDEA Disk instead. |
| This disk has hidden parts, so it was not erased. | The stick was left as it is. Write to your IDEA contact; don't try to erase it yourself. |
| This disk holds an operating system, so it was not erased. | The stick was left as it is, so that what is on it is kept. Use a different stick. |
| Setting up the Backup Disk failed. Try again. | Try again. If it happens again, write to your IDEA contact. |
| Something went wrong sending this. Close this window and try again. | Close the window and try again. |
| The Engine didn't respond. Check History for this command. | Wait a moment and look at History for this IDEA box. If it didn't finish, try again, or write to your IDEA contact. |

The Backup Disk panel can also show these lines about the backups themselves:

| The Console says | What to do |
|---|---|
| The backup was interrupted. | A backup stopped half-way, for example because of a power cut. It is not started again by itself. Write to your IDEA contact so it can be finished. |
| Backup time unknown: this Pi's clock may be wrong | The box doesn't know the time, so it can't use 02:30. It then makes a backup after about every 24 hours that it has been switched on. Keep the box switched on, and write to your IDEA contact if the line stays. |
| The saved backup time is not valid, so this disk runs at 02:30 until it is fixed. | Set the time again (section 4, Change the backup time). |

If you would like a hand, write to your IDEA contact, or send a message to the IDEA support bot on Telegram (@IDEA_SupportBot). You do not need to telephone anyone.
