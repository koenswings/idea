**Status:** Draft (feature not yet live: lands with the idea#193 release) · **Maintained by:** Marco (with Atlas) · 14 October 2026

# 5. Make your own Kolibri channel: the channel builder and your USB stick

This is the most useful chapter for teachers. The **channel builder** turns your own videos, PDFs and pictures into a **Kolibri channel**. Your learners then find it in Kolibri next to the Khan Academy lessons, and you can put it in lessons and quizzes (chapter 3).

You do not need internet or an account. Bring your files on a normal **USB stick**, filled at home, in town or from a colleague.

Good to know:

- **IDEA only reads your stick.** It never writes to it, so nothing on the stick changes, and the stick still works in any Windows laptop afterwards. You do not have to prepare or erase it.
- The stick must be **FAT32 or exFAT**. Almost all sticks are, unless someone formatted them as NTFS.
- **Building is not publishing.** A channel reaches learners only after someone imports it in Kolibri (5.2).

## 5.1 From your USB stick to a channel (automatic)

**At home or in town (any computer):**

1. Open the stick and make a folder named **`kolibri`** at the top level of the stick.
2. Inside `kolibri`, make **one folder per channel**, for example `Grade 5 Science`. The folder name becomes the channel name.
3. Inside the channel folder, make **one folder per topic**, for example `Plants` and `Water cycle`, and copy your videos and PDFs into them.

[[pending-shot: C5-01 | The stick in Windows File Explorer: kolibri > Grade 5 Science > Plants, Water cycle]]

> **Optional: `channel.json`.** To set the channel's name, author, description or licence yourself, put a small text file `channel.json` into the channel folder (your IDEA contact can give you an example). Without it, the channel gets the folder name, the stick's name as author, and the standard licence.

**At school:**

4. Plug the stick into a free USB port of the IDEA box.
5. The IDEA box starts the channel builder by itself, if the channel builder is on this box. It then builds **one channel for each folder inside `kolibri`**, one after the other. You do not have to click anything.
6. To watch it, open the Console. Under the IDEA box you see the row **USB stick: (your stick's name) (read-only)**. Click the link to the channel builder, or open **Channel builder** in the app list.

[[pending-shot: C5-02 | Console: the USB stick row under the IDEA box, with the link to the channel builder]]

7. On the builder's start page the box **From USB sticks** shows each channel: **Waiting**, then **Building** with the number of files done, then **Built**.

[[pending-shot: C5-03 | Channel builder, From USB sticks box: Building (files done out of total)]]

8. When it says **Built, you can pull the stick out**, you can take your stick out. The channel stays on the IDEA box.

[[pending-shot: C5-04 | Channel builder, From USB sticks box: Built, you can pull the stick out]]

> **Don't pull the stick out while it says Building.** If you do, nothing breaks: the build stops with the message "stick removed before the build finished; plug it in again". Plug the stick in again and the build starts over.

## 5.2 Import the channel into Kolibri

Your channel is built, but learners cannot see it yet. A Kolibri admin imports it once. On the demo school, `demo_teacher1` is a Kolibri admin.

1. Open Kolibri from the Console and sign in as a Kolibri admin.
2. Open **Device**, then **Channels**, and click **IMPORT**.

[[pending-shot: C5-05 | Kolibri Device > Channels with the IMPORT button]]

3. Choose **Local network** (not Internet, not a local drive).

[[pending-shot: C5-06 | Kolibri import: choose Local network]]

4. Pick the **channel builder** from the list of devices on the network.

[[pending-shot: C5-07 | Kolibri import: the channel builder in the list of network devices]]

5. Pick your channel (for example **Grade 5 Science**) and click **Import**.

[[pending-shot: C5-08 | Kolibri import: the built channel listed, Import button]]

6. Choose the topics (or everything) and click **IMPORT**. Wait until the task says it is finished.

[[pending-shot: C5-09 | Kolibri import finished; the channel in the Channels list]]

7. Now use it like any other channel: add its videos and PDFs to a lesson (3.4) or a quiz (3.5). Learners also find it under **Explore** (or **Library**).

[[pending-shot: C5-10 | Learner view: the new channel next to the other channels]]

## 5.3 Update the channel

1. Next term, add or change files **in the same folder** on your stick (for example a new topic folder `Soil`).
2. Plug the stick in again. The builder sees what changed and builds a new version of the **same channel**. If nothing changed, it does nothing.
3. In Kolibri, open **Device > Channels**. Your channel shows that an update is available. Import the update the same way as in 5.2. Lessons that use the channel keep working.

[[pending-shot: C5-11 | Kolibri Device > Channels: update available for the channel]]

## 5.4 Build a channel by hand

Use this when your stick has **no `kolibri` folder**, or when your files are in **School Files** (chapter 9) or in your Nextcloud folders.

1. Open **Channel builder** from the Console.
2. Pick the folder to build from. Folders on a stick start with **USB:**, folders on the Files Disk with **Files Disk:**.

[[pending-shot: C5-12 | Channel builder: folder picker with a USB: source]]

3. Type the channel name and the author, and click **Build**.
4. Wait until the page says **Build finished**. Then import the channel in Kolibri (5.2).

[[pending-shot: C5-13 | Channel builder: Build finished]]

Building from the same folder again updates the same channel (5.3).

## 5.5 Use your stick in Nextcloud

Your stick also appears in Nextcloud, so you can open its files or copy them into your own folders, without building a channel.

1. Plug the stick in. Open Nextcloud and sign in as a teacher. In **Files** you see a folder **USB: (your stick's name)** with a lock icon: it is read-only.

[[pending-shot: C5-14 | Nextcloud Files: the USB: folder with the lock icon]]

2. Open the folder to view or play a file. To keep a file, select it, choose **Copy**, and copy it into one of your own folders (for example a course folder, or **School Files**).

[[pending-shot: C5-15 | Nextcloud: the Copy dialog, copying from the USB folder into a course folder]]

3. Pull the stick out when you are done. The **USB:** folder disappears; the files you copied stay in Nextcloud.

Only teachers see the **USB:** folder. Learners do not.

## 5.6 Questions

| Question | Answer |
|---|---|
| **My stick doesn't show up.** | Is it plugged into **this** IDEA box? A stick only shows on the box it is plugged into. Is it NTFS? NTFS sticks are not read; copy the files onto a FAT32 or exFAT stick, or ask the operator. |
| **Nothing was built.** | Check that the stick has a folder named `kolibri` at the top, with one folder per channel inside it. Check that the channel builder is on this IDEA box and was not stopped by the operator (the Console row says so). A stick with more than 8 GB of files is not built automatically: build it by hand (5.4). |
| **I saved a file, but it's not on my stick.** | IDEA never writes to your stick. Download the file from Nextcloud onto a laptop and copy it to the stick there. |
| **My learners can't see my channel.** | Building is not publishing. Import the channel in Kolibri first (5.2), then add it to a lesson. |
| **I changed my files, but the channel is the same.** | Plug the stick in again, wait for **Built**, then import the update in Kolibri (5.3). |
