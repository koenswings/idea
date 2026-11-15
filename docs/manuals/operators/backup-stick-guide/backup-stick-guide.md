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

- **Size: more than 8 GB; 16 GB or more recommended.** The IDEA box checks the size before it changes anything. A stick sold as "8 GB" is a little smaller than that inside, so the box turns it down. A **16 GB stick or bigger** works.
- **Bigger is better.** The Backup Disk keeps a full copy of the apps it backs up. On the IDEA kit the apps take about 164 GB together (chapter 9), so a large stick or disk gives the backup room to grow.
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

1. On the right, click **Make a Backup Disk**. Under the button the Console says: *"Erases this stick, then sets it up to back up every App every day at 02:30."*
2. A window opens with the title **Make a Backup Disk from &lt;stick name&gt;?** The Console first says **Reading the disk…**, then shows what it found on the stick: its name, size and anything stored on it.
3. Read the warning: *"This erases everything on the disk. Apps, backups and files cannot be recovered."* Below it the Console says that, after erasing, the stick will back up every App on this IDEA box every day at 02:30, that the first backup starts right after, and that you can change the time later.
4. The Console asks you to type the stick's name. Type it in the box exactly as it is shown in bold. The red button **Erase and make a Backup Disk** turns on when the name matches. Click it. If you change your mind, click **Cancel**: nothing has been changed yet.
5. The window now shows the four steps and ticks them off as the box works through them:

| Step | What the Console shows | What happens |
|---|---|---|
| Check | **Checking the disk** | The box checks that this is the stick you confirmed and that it is more than 8 GB. |
| Erase | **Erasing the disk** | Everything on the stick is removed. |
| Re-dock | **Waiting for the disk to come back** | The box picks the erased stick up again as an IDEA Disk. |
| Create | **Setting up the Backup Disk** | The box makes the stick a Backup Disk for every app. |

6. When it is finished the Console says: *"Done. This disk is now a Backup Disk. The first backup starts within a minute. After that, it runs every day at 02:30."* Click **Done**. The Console then shows the stick as a Backup Disk.

Leave the stick plugged into the IDEA box. Please don't unplug it while the steps are running. If a step takes a long time, the Console says *"This is taking longer than expected. Don't unplug the disk."*: that is normal for a big stick, so just give it more time.

If the window waits more than ten minutes on the stick's details before you confirm, the Console asks you to look again (*"The summary is out of date. Check the disk again."*). Click **Check the disk again** and type the name once more.

## 3. Make a Backup Disk from an empty IDEA Disk

This section is for a disk the Console already shows as an empty IDEA Disk. Because the disk is already an IDEA Disk with nothing on it, the box skips the Erase and Re-dock steps and nothing is erased.

1. Click the empty disk on the left. On the right, click the card **Make this a Backup Disk** (*"Back up every App every day at 02:30"*).
2. The Console asks **Make &lt;disk name&gt; a Backup Disk?** and says: *"Nothing on this disk is erased. It will back up every App on this Pi every day at 02:30. The first backup starts right after. You can change the time later."* (The Pi is the IDEA box.)
3. Click **Make this a Backup Disk**. The Console says the request was sent and is waiting for confirmation, and then shows two steps: **Checking the disk** and **Setting up the Backup Disk**.
4. When it is finished, the Console says *"Done. This disk is now a Backup Disk."* and *"The first backup starts within a minute. After that, it runs every day at 02:30."* Click **← Back**.

If, after step 1, you see a form with **Backup mode** and **Link to instances** instead, the IDEA box has not been updated for this flow yet. Follow *IDEA for Operators: Tutorial*, section 3.5, instead.

## 4. When the backups run

This section tells you when the new Backup Disk does its work, so you know what to expect and can tell the teachers.

- **The first backup starts within a minute** of the Console saying *Done*. A first full backup can take a few hours. Leave the stick plugged in until it has finished.
- **After that, a backup runs every day at 02:30**, at night, outside lesson time. Leave the stick plugged into the IDEA box so that it is there at 02:30.
- **Apps pause for a moment while a backup runs.** The nightly backup at 02:30 is outside lesson time; the first backup starts straight away, so it is best to make a Backup Disk when no lessons are using the apps.
- The Console says the Backup Disk backs up **every App** on the IDEA box, and you don't pick the apps. **(PENDING: which apps a new Backup Disk backs up is waiting on a decision.)**
- The Console says you can change the time later.

## 5. If the stick was unplugged during Erase

This section tells you how to carry on if the stick came out while the box was erasing it or waiting for it to come back. Nothing is broken: you simply start again.

1. The Console says: *"The disk was unplugged during setup. Plug it back in and try again."* Click **Close**.
2. Plug the stick back into the same IDEA box and wait until it shows in the list on the left again.
3. Start again from the way the stick now shows:
   - shown as a **USB stick** or **unformatted**: follow section 2 again. The box checks the stick again, so you type its name once more;
   - shown as an **empty IDEA Disk** (the erase had already finished): follow section 3. Nothing more is erased.

What was on the stick before may already be gone, because the erase had started. The box doesn't pick up where it stopped; it always starts again from the beginning.

If the Console says *"The disk was erased but didn't come back. Unplug it, plug it back in and try again."*, the erase finished but the box didn't pick the stick up again. Unplug the stick, plug it back in, and then carry on with step 3 above.

## 6. Other messages you may see

This section lists the other messages the Console may show, and what to do.

| The Console says | What to do |
|---|---|
| This stick is too small to be a Backup Disk. It needs at least 8 GB. | Use a bigger stick (16 GB or more). |
| The name you typed doesn't match the disk's name. | Type the name exactly as it is shown in bold. |
| This is not the disk that was checked. Check the disk again. | Another stick was plugged in. Close the window and start again with the stick you want. |
| Something else is running on this Pi. Wait for it to finish, then try again. | Wait a few minutes, then try again. |
| This disk is already a Backup Disk. | Nothing to do: it is already a Backup Disk. |
| Setting up the Backup Disk failed. Try again. | Try again. If it happens again, write to your IDEA contact. |

If you would like a hand, write to your IDEA contact, or send a message to the IDEA support bot on Telegram (@IDEA_SupportBot). You do not need to telephone anyone.
