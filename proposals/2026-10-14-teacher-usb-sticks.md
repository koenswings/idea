# Teacher USB sticks: use a teacher's own FAT/exFAT stick without preparing a Files Disk

**Author:** Steve (Lead Bot)
**Date:** 2026-10-14
**Status:** Draft

## Summary

A teacher plugs a normal USB stick (FAT32 or exFAT, filled at home or in town) into an IDEA Pi. Within a few seconds it shows up in Nextcloud as a folder **"USB: &lt;stick name&gt;"**, and as a source in the Kolibri channel builder. It is **read-only**: teachers browse it and copy what they need into their own folders or into a Kolibri channel. Nothing is ever written to the stick, so it can't be corrupted and needs no preparation, and it still works on any Windows laptop afterwards.

The Files Disk ([files-disk.md](files-disk.md), ext4) stays the place for permanent, writable, backed-up storage. A writable "marker" mode for sticks is **deferred** (§8).

**Out of scope:** backing up Files Disk content. That is a later, separate proposal.

Source: Steve's conceptual discussion with Koen on 2026-10-11. Nothing in it has been decided yet.

## 1. Problem

- Teachers already carry material on sticks: videos, PDFs, e-books from a town internet café or a colleague. Today an IDEA Pi ignores such a stick: since Files Disk step 3 the Engine mounts **only ext4** and lists anything else as an unformatted disk that can only be erased.
- The only way to get the files in is to copy them on a laptop into Nextcloud over the network, or to erase the stick into a Files Disk, which destroys exactly the files the teacher brought.
- The Kolibri channel builder (app-kolibri-channel-builder #1, draft) can turn a folder into a channel, but its sources are a Files Disk or a Nextcloud folder. "My stick from town" is the most natural source, and it isn't one.

## 2. What the teacher experiences

1. Plug the stick into the school Pi (any free USB port).
2. Open Nextcloud. A folder **USB: MARY-STICK** is there, with a small lock icon (read-only).
3. Open, view or play files directly; select files and **Copy** them into "My course" or into School Files.
4. Or: open the channel builder, pick **USB: MARY-STICK / Grade 5 Science**, build, then import the channel in Kolibri.
5. Pull the stick out when done. The folder disappears; anything already copied stays.

No erase, no dialog, no preparation.

## 3. Design: Engine (Axle)

### 3.1 Detection

`usbDeviceMonitor` already sees every `sd?`, `sd?1`, `sd?2` link from `90-docking.rules`. For a partition (or a whole disk without a partition table), the Engine reads `lsblk -no FSTYPE,LABEL,UUID,SIZE /dev/<dev>`:

- `ext4` → unchanged (IDEA disk path, `safeMount`, `processDisk`).
- `vfat` or `exfat` → **USB stick path** (new, below). Only on a non-system disk (the system-disk helper from step 3 still runs first).
- anything else (NTFS, no filesystem) → unchanged: listed in `Engine.unformattedDisks`, erase only.

NTFS is left out on purpose (needs `ntfs3`/FUSE, journal replay questions); it can be added later the same way.

### 3.2 Mount

- **Separate mount root:** `/run/idea-usb/<dev>` (e.g. `/run/idea-usb/sdb1`), **not** `/disks`. Nothing that walks `/disks` (processDisk, META, backups, erase staging) can ever see a stick. `/run` is tmpfs, so stale mount points vanish at reboot.
- **Exact command**, through a new sudoers line in `11-engine-files` (same "typed, exact order" rule as the ext4 entry, pinned by a unit test):

  ```
  /usr/bin/mount -t vfat  -o ro,nosuid,nodev,noexec,uid=1000,gid=1000,fmask=0222,dmask=0222,iocharset=utf8,shortname=mixed /dev/sd[a-z][12] /run/idea-usb/sd[a-z][12]
  /usr/bin/mount -t exfat -o ro,nosuid,nodev,noexec,uid=1000,gid=1000,fmask=0222,dmask=0222,iocharset=utf8 /dev/sd[a-z][12] /run/idea-usb/sd[a-z][12]
  /usr/bin/umount /run/idea-usb/sd[a-z][12]
  /usr/bin/mkdir /run/idea-usb/sd[a-z][12]  (or created by a tmpfiles.d entry + one root-owned parent owned by pi)
  ```

  Pi OS Bookworm kernels have the in-kernel `exfat` driver; no `exfat-fuse` package is needed (the hardware test checks this). Whole-disk sticks (no partition table) use `sd[a-z]` and get the same entries.
- `ro` means the kernel never writes: no FAT dirty bit, no access times. `uid/gid=1000` + masks make every file readable by `pi` (and through the bind by Nextcloud's `www-data`, see §4) without any `chown`.
- If the filesystem is marked dirty (pulled out of a Windows PC), a read-only mount still works; the Engine never runs `fsck` on it.

### 3.3 Store

A stick is **not an IDEA disk**: no `Disk` entry, no disk ID from `META.yaml`, no roles. It goes into a new list on the Engine:

```ts
Engine.usbSticks?: UsbStickPublic[]
interface UsbStickPublic {
  stickId: string        // 'usb-' + filesystem UUID (FAT serial), stable per stick
  device: DeviceName     // sdb1
  label: string          // filesystem label, or model, or 'USB stick'
  displayName: string    // 'USB: MARY-STICK' (unique per Engine: ' (2)' added on a clash)
  fsType: 'vfat' | 'exfat'
  sizeBytes: number; usedBytes: number
  mountedAt: Timestamp
  readOnly: true
}
```

Written only by its own Engine, removed on unplug and at startup (like `unformattedDisks`). Older Consoles ignore the unknown field.

### 3.4 Unplug

The udev `unlink` event, or a mount whose device is gone, triggers: remove from `usbSticks` → tell Nextcloud (§4) → `umount` (lazy `-l` only if busy; safe because nothing was written) → `rmdir`. A read-only FAT mount has no dirty data, so a pull-out without "eject" can't corrupt the stick. Startup cleanup unmounts and removes leftovers under `/run/idea-usb`.

### 3.5 What changes in files-disk.md, and why it stays safe

files-disk.md §"Behaviour change: ext4-only mounting" and §"unformatted disk" say the Engine **never** mounts FAT, exFAT or NTFS. This proposal changes that to:

> The Engine mounts IDEA disks only as ext4 under `/disks`. It mounts FAT and exFAT sticks **only read-only** under `/run/idea-usb`, never as an IDEA disk.

The reason for the original rule still holds: the danger was idea#121 writing `META.yaml` onto a foreign stick and the Engine treating it as an IDEA disk. That is impossible here:

- read-only mount (`ro`), plus `nosuid,nodev,noexec` (no programs or device files from a stick);
- a separate mount root outside `/disks`, so `processDisk`, `writeMetaFile`, backups, app install and restore never touch it; the `/disks` sudoers lines don't match `/run/idea-usb`;
- never a `META.yaml`, never offered as an App, Backup or Files Disk target;
- fixed `uid/gid` mapping, no `chown`;
- **erase still possible**: the stick also stays in `unformattedDisks`, so an operator can still choose "Erase this disk…" (the eject path first unmounts the read-only mount). Nothing else in the erase flow changes.

## 4. Design: Nextcloud (Kid)

Today a Files Disk reaches Nextcloud through `x-app.filesMount` (`/mnt/idea-files`): the Engine writes a compose override with one bind per disk and **recreates the container**, and the hook `10-idea-files.sh` creates a Local external storage per folder.

Recreating Nextcloud for every stick plugged in is too heavy (sticks come and go, it would cut off everyone mid-upload). So sticks use **one static bind** instead:

- New opt-in in `compose.yaml`: `x-app.usbMount: { path: /mnt/idea-usb, services: [nextcloud-app] }`. The Engine binds host `/run/idea-usb` → `/mnt/idea-usb`, **read-only, with `bind.propagation: rslave`**. Sticks mounted later appear inside the running container by themselves; no recreate.
- A small **reconcile** runs on every change: the Engine calls `docker exec -u www-data <nextcloud> /idea/usb-sync.sh` (new script in app-nextcloud, same logic as `10-idea-files.sh`) after each plug and unplug, and once at start. It:
  - creates a Local storage `USB: <label>` → `/mnt/idea-usb/<dev>` with options `readonly=true`, `filesystem_check_changes=1`, `idea_usb=1` (own-storage marker), `enable_sharing=false`;
  - deletes only storages with `idea_usb=1` whose folder is gone. Deleting a storage removes only Nextcloud config, never files.
  - display names come from a read-only JSON written by the Engine (like `.idea-files.json`).
- **Who sees it:** applicable group **teachers** (plus admin), not learners. See open question 1.
- **Vanishing folder:** after unplug the storage is deleted within seconds. A user who had it open sees "folder not found" and goes back to Files; there are no half-written files because the storage was read-only. Files already copied out are normal Nextcloud files, and are backed up with Nextcloud.

## 5. Design: Console (Pixel)

- In the network tree under each Engine: a light row **"USB stick: MARY-STICK (read-only, 3.2 GB)"**, with a short line "Visible in Nextcloud for teachers on this Pi". No actions in v1 except the existing **Erase this disk…** (it is still in `unformattedDisks`). Hide the "contents unknown" text for such a stick; show "FAT32/exFAT stick, used read-only".
- No eject button needed: pulling a read-only stick is safe.

## 6. Multiple sticks and multiple Pis

- **Several sticks at once:** each gets its own mount and folder; duplicate labels get " (2)". Limit: none beyond USB ports.
- **Which Pi:** a stick shows on the Engine it is plugged into, in that Pi's Nextcloud (and builder). There is no cross-Pi sharing in v1. The Console shows which Pi has it. In a school with one server Pi this is a non-issue.

## 7. Using a USB stick with the Kolibri channel builder

Two ways to reach the stick:

| | A. Direct mount (recommended) | B. Via Nextcloud "USB:" WebDAV |
|---|---|---|
| How | Builder opts into `x-app.usbMount` like Nextcloud; lists `/mnt/idea-usb/*` as sources next to `/mnt/idea-files` | Builder already speaks WebDAV; the stick is just another Nextcloud folder |
| Login | none (same as Files Disk source) | the teacher's Nextcloud login |
| Speed | local read, fast for large videos | every video streamed through Nextcloud's PHP, slow on a Pi |
| Depends on | Engine only | Engine + Nextcloud + teacher being in the right group |

**Recommendation: A.** Code change in the builder (`builder/channel_builder/server.py`):

- add `USB_ROOT=/mnt/idea-usb`; the folder list returns sources from both roots, labelled "Files Disk: …" and "USB: …" (names from the Engine's JSON);
- the path check (`realpath` under the root) applies to both roots;
- **channel id for USB sources** from the stick's filesystem UUID plus the relative path (`usb:<uuid>:<path>`), so rebuilding from the same stick updates the same channel instead of creating a second one;
- the builder copies what it needs into its export volume during the build, so the stick can be pulled out after "Build finished"; pulling it out mid-build fails the build with a clear message and leaves the previous channel version intact;
- `compose.yaml`: add `usbMount`. Tests: a fixture folder as fake USB root.

Option B keeps working anyway for teachers who use Nextcloud, without extra code.

**Full teacher flow:**

1. In town, the teacher copies videos and PDFs onto a stick, one folder per topic ("Plants", "Water cycle").
2. At school, she plugs the stick into the IDEA Pi.
3. On a laptop or tablet she opens the channel builder from the Console (or its bookmark), picks **USB: MARY-STICK / Grade 5 Science**, types a channel name, and clicks **Build**.
4. When the builder shows "Build finished", she can pull the stick out.
5. In Kolibri: Device → Channels → Import → Local network → the builder → pick the channel → Import.
6. She adds it to a lesson or lets learners browse it. Learners see it next to the other channels.
7. Next term she adds files to the same folder on the stick and builds again; Kolibri offers the update.

## 8. The writable "marker" bridge: deferred

Idea from 2026-10-11: a stick with an `idea-files` folder or `idea.json` gets mounted **writable** as the teacher's own disk.

Risks, honestly:

- **No permissions on FAT:** every file belongs to one uid. Any Nextcloud user with access could change or delete anything. Per-teacher privacy is impossible.
- **Corruption on unplug:** writable FAT pulled out mid-write corrupts the FAT table, often the whole folder. Teachers will pull sticks out; we can't force "eject". Nextcloud's own cache would also go out of sync.
- **FAT32 4 GB file limit:** a long HD video upload fails with a confusing error. exFAT has no such limit, but its kernel driver has had fewer years in production for writes.
- **Marker spoofing:** any stick with that folder gets write access; a learner could bring one.
- **Not backed up:** it would look like storage but isn't safe storage.

What it would bring (writing back to the stick to take files home) is real but small, and the same goal is mostly met by "download from Nextcloud to a laptop" or a Files Disk.

**Recommendation: no writable mode in v1.** Read-only sticks + Files Disk cover the need. Revisit after field feedback; if it comes back, it should be exFAT only, `sync` mount, a Console-confirmed opt-in per stick (not a file anyone can create), and still never an IDEA role.

## 9. Pros and cons

- **Pros:** what teachers already do; nothing to prepare or erase; stick stays readable on Windows; no corruption possible; no Nextcloud restart; works as a source for the channel builder.
- **Cons:** read-only, so a teacher can't save onto the stick from IDEA; sticks come and go, so folders appear and disappear (handled in §3.4, §4); FAT32 files over 4 GB can't exist on the stick anyway; a malicious stick could hold harmful files (mitigated: `noexec`, read-only, only teachers see it; Nextcloud doesn't run uploaded files); a second mount path in the Engine to maintain; changes a decided rule in files-disk.md.

## 10. Alternatives considered

1. **Keep ext4-only; teachers copy over the network.** Zero code, but slow for videos, needs a laptop, and doesn't match how teachers work.
2. **Automatically copy every stick into a "USB imports" folder.** Fills disks unasked, duplicates data, unclear ownership. Rejected.
3. **Show sticks through the Files Disk `filesMount` (recreate Nextcloud per plug).** Reuses code, but restarts Nextcloud for every stick. Rejected in favour of one propagated bind.
4. **Writable sticks with a marker.** Deferred (§8).
5. **udisks2 / automount.** Another daemon with its own policy and paths under `/media`; less control than one typed sudoers line. Rejected.

## 11. Changes to the teacher tutorial (Marco)

The tutorial (`docs/manuals/teachers/teacher-tutorial/`) describes only what is live (DOCUMENTATION-RULES). So these chapters land in the **same release PRs** as the features, after the hardware tests, not before. Screenshots come from the demo Pi, and never show errors.

**Channel builder** (new, not in the tutorial yet; still untested on a Pi):

- **New chapter "Make your own Kolibri channel"** after 4 (Kolibri for learners), or as 3.x if Marco prefers. Scenarios:
  - *Build a channel from School Files:* put folders in School Files → open the builder → pick folder, name, author → Build → "finished". Screenshots: builder start page, folder picker, finished page.
  - *Import it into Kolibri:* Device → Channels → Import → Local network → builder → channel → Import. One screenshot per screen (this is the step that needs the most help).
  - *Update the channel:* add files, build again, import the update.
- **Chapter 8.3 "Can I put my own files into Kolibri?"** changes from "not yet / ask" to a pointer to the new chapter.

**USB sticks:**

- **Chapter 8 (Your own files)** gets a new section **"8.x Use your own USB stick"**: plug in → "USB: name" folder in Nextcloud → open or copy files into your course folder → pull out when done. Note: read-only, nothing is changed on your stick; copy what you want to keep. Screenshots: Nextcloud Files with the USB folder and lock icon; the Copy dialog.
- **New channel-builder scenario "From a stick to a channel":** the full flow from §7. Screenshot: folder picker showing a "USB:" source.
- **Chapter 11 (Operator: disks)**: a short note that FAT/exFAT sticks show as "USB stick (read-only)" and don't need erasing; erase is only for turning a stick into an IDEA disk.
- **FAQ lines:** "My stick doesn't show up" (NTFS or not on this Pi), "I saved a file but it's not on my stick" (read-only, use Download).

## 12. Implementation plan

| Step | Repo / bot | Work | Depends on |
|---|---|---|---|
| 0 | idea / Steve | Approve this proposal; one-line amendment note in files-disk.md's index entry pointing here | Koen |
| 1 | agent-engine-dev / Axle | fstype branch in `usbDeviceMonitor`; `/run/idea-usb` mount/umount with exact typed commands; `Engine.usbSticks`; unplug + startup cleanup; `x-app.usbMount` (static rslave read-only bind); reconcile `docker exec` call; display-name JSON; sticks stay in `unformattedDisks` for erase; unit tests incl. sudoers string pin | 0 |
| 2 | idea ops / Atlas | sudoers lines in `11-engine-files` + `build-engine` install, `visudo -cf` and `sudo -ll` proof; confirm `exfat` module on Pi OS image; two test sticks (FAT32, exFAT) on a test Pi | 1 |
| 3 | app-nextcloud / Kid | `usbMount` opt-in; `usb-sync.sh` (create/delete `idea_usb=1` storages, read-only, teachers group); tests with a fake root | 1 |
| 4 | app-kolibri-channel-builder / Kid | USB_ROOT sources, `usb:<uuid>:<path>` channel id, pull-out handling; merge after builder #1 | 1, builder #1 |
| 5 | agent-console-dev / Pixel | "USB stick (read-only)" row; text change for the unformatted entry; mock-store fixtures | 1 (store type) |
| 6 | idea / Marco | Tutorial chapters (§11), in the release PR, after step 7 passes | 3, 4, 5, 7 |
| 7 | Atlas + Axle | hardware tests (§13), then normal batch to the pool | 1–5 |

## 13. Test plan (automated; no manual tests for Koen)

- **Unit (Engine):** fstype routing (ext4 / vfat / exfat / ntfs / none); exact mount and umount strings match the sudoers lines; system disk never routed; label clash naming; unplug and startup cleanup; nothing ever written under `/run/idea-usb` (mock fs asserts no writes); stick never appears in `disks`.
- **Unit (Nextcloud script):** create/delete reconcile with a fake `occ`; admin-created storages never deleted; read-only option set; group set.
- **Unit (builder):** both roots listed; path escape refused; stable channel id from UUID; stick removed mid-build → build fails cleanly, old version kept.
- **Console:** fixtures with sticks; snapshot of the row; no erase change.
- **Hardware (scripted, on a claimed test Pi, never golden):** a FAT32 and an exFAT stick, each with a known file set (including a > 4 GB file on exFAT, a dirty-bit FAT image, non-ASCII names). Script: plug (or `udevadm trigger`), wait for `usbSticks`, check `findmnt` options (`ro,nosuid,nodev,noexec`), checksum files via Nextcloud WebDAV as a teacher, check a learner can't see it, write attempt via WebDAV fails, build a channel from the stick, unplug, check storage gone and mount gone, compare stick image checksum before/after (**bit-identical**), erase still offered.
- **Walks:** the cover-all walk gains a USB step, run only from idea02 on Steve's GO.

## 14. Open questions for Koen (with recommendations)

1. **Who sees the stick folder in Nextcloud?** Recommend: **teachers group + admin only**, not learners. A stick can hold anything; teachers decide what to copy into shared folders.
2. **What happens on unplug?** Recommend: folder disappears within seconds, no warning needed; read-only means nothing open can be lost. Files already copied stay.
3. **Several sticks at once?** Recommend: yes, each its own "USB: name" folder, " (2)" on duplicate names.
4. **Which Pi shows it?** Recommend: only the Pi it is plugged into (its Nextcloud and builder). No cross-Pi sharing in v1.
5. **Should the Console show it?** Recommend: yes, a read-only info row per stick, no new actions (erase stays available).
6. **Writable marker mode?** Recommend: **not in v1** (§8).
7. **NTFS sticks?** Recommend: not in v1; they stay erase-only. Add if field schools report many NTFS sticks.
8. **Should a stick be backed up?** Recommend: no (part of the later backup proposal); copied files are backed up with Nextcloud.
