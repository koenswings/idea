# Proposal: Files Disk — a shared file store on a docked disk

**Author:** Steve (Lead Bot)
**Date:** 2026-09-27
**Revised:** 2026-09-27 (Design Review by Atlas, Kid, Axle and Pixel applied); 2026-09-27 (Koen: add ext4 formatting, merged in from idea#125); 2026-09-27 (formatting design review by Atlas, Kid, Axle and Pixel applied); 2026-09-28 (Koen: combined disks allowed, formatting only inside the Files Disk flow and for any non-system disk); 2026-09-28 (design re-review R1–R9 by Atlas, Axle, Kid and Pixel applied, accepted by Steve); **2026-09-28 11:08 (Koen: Erase becomes a general disk action that leaves an empty IDEA disk — pending design re-review)**
**Status:** Proposed (design reviewed). **The general Erase change of 2026-09-28 11:08 is pending design re-review** (§14, points E1–E10); everything else is final.
**Refs:** idea#75 (Files Disk), idea#125 (formatting sketch, merged into this proposal). Depends on: idea#121 (new disks never get META.yaml written, bug B1)
**Affects:** `agent-engine-dev` (main work), `agent-console-dev`, `app-nextcloud` (+ `agent-app-dev` conventions and harness), Ops (sudoers rollout, hardware test)
**Background research:** `files-disk-findings.md` (research notes, 2026-09-27)

---

## 1. Summary

A **Files Disk** is an ordinary ext4 USB disk or SSD that an operator turns into a shared file store from the Console. A disk with any other filesystem (a new exFAT stick, for example) can be **erased by the Engine first** into an empty ext4 IDEA disk, through an explicit Console action with a content summary and a typed confirmation. When it is docked, the Engine mounts its `files/` folder into every App on that Engine that says it can use one. Nextcloud comes first. Teachers and students then reach the files through Nextcloud in the browser, over the school's local Wi-Fi.

The operator starts from the disk in the Console. What it offers depends on the disk (§4):

- **Add Files to this disk (keeps everything):** for an **empty ext4 disk** (shown as **Make this a Files Disk**), or an ext4 disk that is **already an App Disk and/or a Backup Disk**. `createFilesDisk` writes `FILES.yaml` and an empty `files/` folder next to what is already there, plus `META.yaml` if it is missing. The disk keeps its ID and gets `'files'` as an extra role. Nothing on the disk is changed.
- **Erase first, then make it a Files Disk:** a **shortcut** in the Files flow for any non-system disk, and the only way for a disk without an ext4 filesystem (a new exFAT stick, for example) or an ext4 disk with other files. It is the general **Erase** (below) followed by `createFilesDisk`, behind **one** summary and **one** typed confirmation.

**Erase is a general disk action (Koen, 2026-09-28 11:08; pending re-review).** Every non-system disk (App, Backup, Files, combined, and not-yet-IDEA sticks such as exFAT, NTFS or no partition table) can be erased with `eraseDisk`. The result is an **empty IDEA disk**: GPT with one partition, ext4 with only `META.yaml` (the same disk ID when one exists, otherwise a new one), and the neutral filesystem label **"IDEA Disk"**. The Engine first shows a **summary of everything on the disk** (Apps, instances with their data sizes, backups, files, other files, space), and the operator types the disk's label to confirm (§7.4). Giving the empty disk a role is a separate step: **Make this a Files Disk**, **Make this a Backup Disk**, or installing an App, exactly as for any empty disk today. *(Was: formatting only inside the Files flow, always ending as a Files Disk.)*

**Combined disks are allowed (Koen, 2026-09-28):** one disk can be an App Disk, a Backup Disk and a Files Disk at the same time, as the Solution Description and `backup-disk.md` already allow (`Disk.diskTypes` is a list). *(Was: "No combined disks.")*

The Engine never erases anything on its own. There are two new root permissions: changing the owner of the **disk root folder only** (`chown -h`), and running **one root-owned erase script** that re-checks the device itself (§10).

Koen approved the design decisions in §5 (2026-09-27) and later that day reversed decision 2 to add formatting (idea#125). The Design Review (§14) filled in the implementation details of the first version. The formatting part (§7.4) was design-reviewed the same evening (§14). On 2026-09-28 Koen allowed combined disks, moved formatting inside the Files Disk flow, and allowed formatting any non-system disk after a content summary. The Design Review answered the follow-up points R1–R9 the same morning, and Steve accepted all answers (§14).

## 2. Why

- The Console already has a "Files Disk" option for empty disks. The Engine has no `createFilesDisk` command, so clicking it does nothing, and the Console still says "Command sent. The Engine is configuring the disk." The disk stays empty and no error appears anywhere.
- The original design (`agent-engine-dev/proposals/solution-description.md`, lines 81, 89, 138, 210–216, 682) promises Files Disks: "Contains a File System that is automatically network mounted when docked" and "auto-mounted into Apps that have been created with the ability to work with Files Disks … Examples: A file store into Nextcloud".
- New USB sticks and SSDs almost always come as exFAT or FAT32. Without formatting in the Engine, every Files Disk would have to be prepared on a Linux machine first, which is hard to ask of a school (idea#125).
- Schools need somewhere to keep and share documents (worksheets, photos, student work) that doesn't depend on a single App's internal storage. It should be possible to move that store to another Pi by moving the disk.

## 3. What a Files Disk is

- **A role on a disk.** Like App Disks and Backup Disks, a Files Disk is recognised by what is on it, here a `FILES.yaml` file in the disk root. The Engine checks for it every time the disk is docked. The role **can be combined** with the App and Backup roles on the same disk (`diskTypes` for example `['app', 'files']`).
- **A folder of files, not an App.** The shared content lives in `files/`. The Engine doesn't serve it itself. Apps that opt in get the folder mounted inside their container.
- **Local to one Pi.** Only the Engine it is docked to uses it. To use the files on another Pi, you move the disk.
- **Stable identity.** Every Files Disk has a permanent ID in `META.yaml`, so a later Backup Disk feature can refer to it.
- **Plain files.** Everything in `files/` is ordinary files and folders. They are owned by uid 33 (Nextcloud's `www-data`), but any Linux machine can read them without Nextcloud. **Note for Koen:** on a laptop, that means a `sudo` copy or a chown to read-write them; reading is enough for a rescue copy.

## 4. User flow in the Console

1. The operator docks a disk. An ext4 disk appears in the network tree with its role badges (**empty**, **app**, **backup**, or several). A disk without ext4 appears under its Engine as an **unformatted disk**, for example **"Intenso 32 GB"**.
2. They select it. The **role buttons** depend on the disk:
    - **Empty ext4 disk** (a new ext4 disk, or one that was just erased): the **Empty disk** state with **Make this a Files Disk**, **Make this a Backup Disk** and **Install App**, as in today's Empty Disk panel. For Files: *"This disk becomes a shared file store. Apps that support Files Disks (such as Nextcloud) on this Engine will show its files. Nothing on the disk is erased."*
    - **App and/or Backup Disk:** **Add Files to this disk**, with a short confirmation: *"Nothing on this disk is changed. Your Apps and backups stay as they are, and the disk also becomes a shared file store."* The Files flow also offers the **erase first** shortcut.
    - **Unformatted disk, or an ext4 disk with other (non-IDEA) files:** **Make this a Files Disk**, which offers only the **erase first** shortcut.
    - **Files Disk (alone or combined):** no Files button; the general Erase applies.
    - In addition, **every non-system disk view** has a quieter secondary action, **Erase this disk**, less prominent than the role buttons. It leaves an empty IDEA disk (see *Erase* below).
3. For the add path they click **Add Files**. The Console waits for the Engine's answer (§8):
    - **Success:** the disk gets the **files** badge next to its other badges, and the right pane shows the Files section. Nextcloud is recreated with the new folder exactly as when a new Files Disk is docked (not during its first start or an upgrade).
    - **Failure:** the Engine's message appears in the flow, for example "School Files already has other files on it."
    - **No answer after 15 seconds:** "The Engine didn't respond. It may not support Files Disks yet."
4. **Files Disk view:** name, size and free space, plus one of three lines:
    - "Available in: Nextcloud (nextcloud-01)"
    - "Nextcloud supports Files Disks but isn't running"
    - "No App on this Engine uses Files Disks yet"
    If the disk can't be used (password-protected, or an earlier unmount got stuck), the view shows **Not mounted** with the reason. There is an **Eject** button. On a combined disk this is a **Files section** next to the disk's Apps and backups. When space runs low on a combined disk, the warning says that **the Apps on this disk need space too**, because a full disk can break Nextcloud outright.
5. In Nextcloud, users see a folder named after the disk (for example **School Files**) and can open, upload and share files according to their Nextcloud accounts.

**Erase (a general disk action, pending re-review):**

- **Erase this disk** is on every non-system disk view, as a quiet secondary action. The Files flow keeps an **erase first** shortcut (erase, then `createFilesDisk`) behind the same single summary and typed confirmation. There is still no action called "Format".
- The Engine first computes a **content summary**, and the dialog shows it:
    - the disk's label, model, size, current filesystem, and used and total space;
    - the **Apps** on it (name and version);
    - the **instances**, their **data size**, and which are **running** (they will be stopped). The App can be installed again, but the data can't be recovered;
    - the **backups** on it (which instances, last backup);
    - the **Files** content (file count, total size);
    - **other files** (count, size).
    - Counts that hit the limit are shown as **"at least"**. Then comes the warning *"Everything on this disk will be erased."* For a disk without ext4, it says **"contents unknown"**.
- The operator types the label exactly (for example "MilkWise Apps" or "Intenso 32 GB") to confirm. The button stays disabled until it matches. After 10 minutes the typed-name box is replaced by **"The summary is out of date. Check the disk again."**
- The Console shows progress: *checking → stopping and unmounting → partitioning → creating filesystem → mounting* (and *making a Files Disk* for the shortcut). After 5 minutes it says "This is taking longer than expected. Don't unplug the disk." and keeps watching. There is no cancel.
- On success, the disk comes back as an **empty IDEA disk** with the **same ID** (a new ID for a disk that had none), and the Console opens its Empty disk state with the role buttons. With the Files shortcut, the Console then sends `createFilesDisk` and opens the new Files Disk. The result lists the **removed instances with their data sizes**. If the disk held backups, the backup view says plainly that those backups were erased. If the disk is unplugged while the dialog is open, the dialog closes and says the disk was removed.
- The Pi's own disks and swap disks are never offered. A running backup, an instance being started, stopped or upgraded, or Nextcloud in its first start or an upgrade blocks the erase with "try again later". If the disk can't be unmounted, nothing is erased and the disk comes back as it was.

6. **Eject** (or pulling the disk): Nextcloud restarts briefly and the folder disappears. Re-docking brings it back. For a **combined disk**, the eject confirmation lists **everything affected**: the instances on the disk that will stop, the Apps that lose its files (for example "Nextcloud (nextcloud-01) loses School Files"), and the backups on it that become unavailable. Eject is hidden only on a **pure** Backup Disk; on a combined disk it is shown, and the Engine refuses it while a backup is running. If the Pi can't unmount the disk cleanly, that Engine's row shows a warning such as "School Files couldn't be unmounted cleanly. Restart this Pi." This works for every disk type, not only Files Disks.

## 5. Design decisions (approved by Koen, 2026-09-27; decisions 2 and 3 changed by Koen on 2026-09-27 and again on 2026-09-28)

| # | Decision | Reason |
|---|---|---|
| 1 | **Purpose:** a shared teacher/student file store reached **through Apps over HTTP**, Nextcloud first. **No host-level SMB/NFS** in v1. | Clients are browsers on the school Wi-Fi, and Nextcloud is already IDEA's file-sharing App. SMB/NFS would add packages, root configuration and user accounts to an unattended Pi. |
| 2 | **Changed 2026-09-27 (Koen, idea#125); refined 2026-09-28; changed again 2026-09-28 11:08 (pending re-review):** the Engine **can erase any non-system disk** through an explicit Console action (**Erase this disk**, or the Files flow's erase-first shortcut), after a content summary and a typed name confirmation, never automatically on dock. The result is an **empty IDEA disk** (ext4, only `META.yaml`, label "IDEA Disk"); roles are added separately. Without erasing, `createFilesDisk` still writes `META.yaml`, `FILES.yaml` and `files/` onto an existing ext4 filesystem without erasing anything. *(Was: "Don't format" (2026-09-27 morning); then "format only inside the Files Disk flow, ending as a Files Disk" (2026-09-28).)* | New drives come as exFAT/FAT, and schools can't prepare disks on a Linux machine. Erasing is useful for any role, not only Files, so it leaves a neutral empty disk. Safety comes from the explicit action, the content summary, the typed confirmation, the never-overridable refusals (system disk, swap), and a root script that re-checks the device itself (§7.4). |
| 3 | **Changed 2026-09-28 (Koen): combined disks allowed.** **Add Files** (`createFilesDisk`, nothing erased) works on an **empty ext4 disk** or an ext4 disk that is **already an App and/or Backup Disk**. It refuses a disk that is already a Files Disk, and a disk with non-IDEA files in its root. **Erase** (`eraseDisk`) works on **any non-system disk**: ext4 or not, empty, IDEA or with other files, and leaves an empty IDEA disk. It is the only path for disks without ext4 and for ext4 disks with other files. *(Was, 2026-09-27: "Empty ext4 disks work straight away; disks without ext4 are format candidates; ext4 disks with other files are not offered; disks with IDEA data are always refused; **no combined disks**.")* | The Solution Description (`agent-engine-dev/proposals/solution-description.md`) and `proposals/backup-disk.md` (~lines 329–334) explicitly allow multi-purpose disks, and the Engine already has `Disk.diskTypes` as a list. Files Disks are still always ext4, because the ownership model and container binds rely on ext4 permissions. Formatting erases everything, so its safeguard is an exact summary plus the typed label, not a refusal. |
| 4 | **Apps opt in** through compose metadata (`x-app.filesMount`). **Every** Files Disk on an Engine is mounted into **every** opted-in App on that Engine. Choosing Apps per disk comes later. | Creation stays one click and there are no per-disk links to manage. |
| 5 | **No password in v1.** Nextcloud accounts give access control. A `password` field is reserved in `FILES.yaml`. | Reserving the field avoids a format change later. |
| 6 | **Served only by the Engine it is docked to.** No mounts across Pis. | Network mounts between Pis create fragile dependencies. |
| 7 | **On undock or eject**, restart the affected Apps **without** the mount, then unmount. **Remount on dock.** On a combined disk, the disk's own instances are stopped as for any App Disk. | A disk can't be unmounted while a container holds it. A dangling mount could make an App write to the Pi's own SD card or SSD. |
| 8 | **Backup is out of scope**, but every Files Disk gets a **stable ID now**. | Later Backup Disk links need to refer to the Files Disk by ID. |
| 9 | A quick **Console-only fix** (disable or label the Files Disk button until the Engine is ready) was offered but **not chosen**. It stays available as a separate step if the rollout takes long. | Koen prefers to do the real feature. |

## 6. On-disk format

```
/                      (disk root, ext4; owner pi:pi, set by the Engine if needed)
├── META.yaml          disk identity (existing format)
├── FILES.yaml         marker + Files Disk settings (new)
├── files/             the shared content — the only folder Apps see
└── lost+found/        created by mkfs; ignored
```

**Combined disk** (for example an App Disk that also has the Files role): `apps/`, `services/`, `instances/` (and `backups/`, `BACKUP.yaml` on a Backup Disk) stay exactly as they were. `FILES.yaml` and `files/` sit next to them in the same root. Apps only ever see `files/`.

**`META.yaml`** (existing format from `src/data/Meta.ts`, written if missing):

| Field | Meaning |
|---|---|
| `diskId` | Permanent ID: the hardware serial if the Engine can read it, otherwise a generated uuid. Must not change between docks (idea#121). |
| `isHardwareId` | `true` if `diskId` is a hardware serial |
| `diskName` | Display name (the volume label, or what the operator chose) |
| `created` | Timestamp (ms) when the disk was first registered |
| `lastDocked` | Timestamp (ms), updated on every dock |

**`FILES.yaml`** (new):

```yaml
version: 1               # format version of this file
created: 1790500000000   # ms timestamp when the disk became a Files Disk
createdBy: <engineId>    # Engine that ran createFilesDisk (informational)
shareName: School Files  # name Apps show for this disk; defaults to diskName
readOnly: false          # RESERVED and ignored in v1 (Apps always get read-write)
password: null           # RESERVED for a future password option; v1 must be null.
                         # A non-null value → the disk is not mounted, the Console
                         # shows "Not mounted: password-protected Files Disks are
                         # not supported yet".
```

**`files/`**: an empty folder when created. Everything users store goes here. `META.yaml` and `FILES.yaml` stay outside it, so users can't delete them from inside an App.

## 7. Engine changes (agent-engine-dev)

### 7.0 Safety fixes first (step 0, together with idea#121)

These protect App Disks today, so they ship before any Files Disk code:

- **idea#121:** write `META.yaml` for new disks. For a non-system disk whose root isn't writable by `pi`, first run the new sudoers entry `chown -h pi:pi /disks/<dev>` (§10).
- **Never delete a mounted path.** `undockDisk` (`usbDeviceMonitor.ts:305`) must never `rm -fr` a mount point that is still mounted. Unmount with a plain `umount` and a few retries. If it's still busy, record an error trace, update the store anyway (disk undocked), set **`Disk.unmountError`** (`{ engineId, mountPoint, fsUuid, message }`, for example `mountPoint: /disks/sdb1`). **`fsUuid`** is the filesystem UUID that the Engine records **at mount time** with `lsblk -no UUID /dev/<dev>` and copies into the error and leave the mount point alone. This applies to **every disk type, App Disks included**. `unmountError` survives the undock (when `dockedTo` becomes `null`). It is cleared on the next successful mount of that disk, **or at Engine startup** (next bullet).
- **Clear stale unmount errors at startup.** When the Engine cleans up its old mount points in `/disks` at startup (`usbDeviceMonitor.ts:269–291`), it also clears every `Disk.unmountError` whose `engineId` is its own, when `findmnt -no UUID <unmountError.mountPoint>` shows **nothing mounted** there, **or a different UUID** than `unmountError.fsUuid`. Only the same filesystem still mounted there keeps the error. Device names get reused, so after a restart a different disk can be mounted at the same `/disks/sdX`; only the same filesystem still being there keeps the error. `Disk.id` can't be used for this comparison because it is **not** the filesystem UUID. `readHardwareId` (`src/data/Meta.ts:145`) uses a hardware serial for two USB stick models (Samsung FIT, INTENSO), and every other disk gets a random `uuid()` stored only in `META.yaml`. Neither `lsblk` nor `findmnt` needs sudo, so this adds **no new sudoers entry**. Without this, the "Restart this Pi" warning would stay after the restart itself if the disk isn't docked again.
- **Backups hold the disk lock too (Axle).** Every backup takes the **Backup Disk's lock and the instance lock together** via `resourceLock.acquireAll`, as restore already does (`backupMonitor.ts:392`); today `backupInstance` takes only the instance lock (`backupMonitor.ts:100–106`). Console-triggered **eject and erase checks** look for a running `backupApp` operation by its **`backupDiskId`** (`backupMonitor.ts:108–111`), which also covers scheduled backups.
- **Check before mounting.** Before mounting a newly docked disk, the Engine checks with `findmnt` that nothing is still mounted at `/disks/<dev>`. If something is, it refuses with an error trace instead of mounting on top.

### 7.1 `createFilesDisk <diskId>` command

Add an entry in `src/data/Commands.ts`: scope `engine`, one argument named `diskId`. The **Console sends the disk ID** (changed from the name). The trace records `args.diskId`, and error messages show the disk's **name**. The handler checks the following in order and **throws** on the first failure, so the trace closes as an error:

1. **Found here:** the disk exists, is **docked to this Engine** (`dockedTo === localEngineId`) and has a device.
2. **Not the system disk.**
3. **Allowed roles:** `diskTypes` is `['empty']`, or contains only `'app'` and/or `'backup'`. It refuses a disk that is **already a Files Disk** (`FILES.yaml` present: "School Files is already a Files Disk") and, in v1, an Upgrade Disk.
4. **No non-IDEA files in the root:** the root may contain only `META.yaml`, `lost+found`, and the IDEA entries of its roles (`apps/`, `services/`, `instances/` for an App Disk; `BACKUP.yaml`, `backups/` for a Backup Disk). Anything else, including a stray `files/` folder without `FILES.yaml`, refuses with "School Files has other files on it. Use Make this a Files Disk to erase it, or empty it on another computer." This keeps Steve's v1 rule that the add path never adopts unknown content. The format path now covers such disks.
5. **ext4:** `findmnt -no FSTYPE /disks/<dev>` returns `ext4`.
6. **Owner:** if `pi` can't write the disk root, run exactly `sudo /usr/bin/chown -h pi:pi /disks/<dev>` (the step-0 entry: root folder only, not recursive, `-h` so a symlink is never followed; `apps/`, `instances/` and `backups/` are untouched). Before changing it, the trace records the root folder's **previous uid:gid and mode**, so the change can be undone by hand. Root-owned App and Backup Disks are **not** refused (Atlas, Axle). If the Pi doesn't have the sudoers entry yet, this fails with a clear error ("this Engine is missing a permission update; ask Ops to install the new 10-engine sudoers file"), and **nothing has been written to the disk yet**, so it is never half-created. On App and Backup Disks the root is normally already `pi`-writable (the Engine creates `apps/` and `instances/`, and writes `BACKUP.yaml` and `META.yaml`, as `pi`), so this is the rare case (§14, R2).
7. **Writable:** `pi` can now write the disk root.
8. **Not busy:** no resource lock on the disk (for example a backup running to or from it).

It then writes `META.yaml` if missing (an existing disk ID is **always kept**), writes `FILES.yaml` (`shareName` defaults to the disk name, except that an erased disk still called "IDEA Disk" gets "School Files"; §14, E6), creates `files/` as `pi` (1000:1000, default mode from pi's umask, as for any Files Disk; Nextcloud's wrapper later sets the top-level owner to uid 33, §9), and runs `processDisk` again. `processDisk` adds `'files'` next to the existing roles, for example `['app', 'files']`. Existing instances keep running. Opted-in instances (Nextcloud) are recreated with the new mount exactly as when a new Files Disk is docked, including the rule not to recreate during Nextcloud's first start or an upgrade (7.3; Kid). `apps/`, `instances/` and backup data are never touched. Document it in `docs/COMMANDS.md`.

### 7.2 Detection and disk details (`src/data/Disk.ts`)

- `isFilesDisk(disk)`: `FILES.yaml` exists in the disk root. This replaces the stub at `Disk.ts:435–439`.
- `processDisk` branch (`Disk.ts:197–201`): add `'files'` and call `processFilesDisk`. Replace the TODO that links to #46 with #75. The existing code already appends every detected type, so combined disks get several (`['app', 'backup', 'files']`).
- **Processing order (Axle, Kid):** `processDisk` runs **Files first, then App, Backup and Upgrade**. Today `Disk.ts:177–201` runs App, Backup, Upgrade, Files, and `processAppDisk` auto-starts the disk's instances before the Files check. With the new order, an opted-in App on the same disk (Nextcloud) starts once with its own files mounted.
    - The recreate triggered by the Files role **skips instances on the same disk** that `processAppDisk` is about to start, so they aren't started twice.
    - A Files-role error (for example an unreadable `FILES.yaml`) is **recorded and doesn't stop** App or Backup processing.
- `processFilesDisk`: read `FILES.yaml` and set `disk.filesConfig`. If `password` isn't null, set `passwordProtected: true`, set `filesConfig.error` ("password-protected Files Disks are not supported yet") and don't mount. Otherwise schedule a remount of opted-in instances (7.3).
- **Empty IDEA disk (after an erase, pending re-review):** an ext4 disk with only `META.yaml` (and `lost+found`) and no role. Today `processDisk` already handles it cleanly: no role check matches, so it pushes `'empty'` (`Disk.ts:203–206`), and the Console's Empty Disk panel keys on `'empty'` (`App.tsx:56`, `EmptyDiskPanel.tsx`). The Engine publishes it as a normal `Disk` entry, **docked and mounted**, with `diskTypes: ['empty']`. Koen's note described this state as `diskTypes []`; the proposal keeps `['empty']` because `[]` already means "not processed yet or undocked" (`backup-disk.md`), and the existing Empty Disk panel depends on it. **No Engine change is needed**, apart from the ID and name handling on erase (7.4). (§14, E3.)
- **`filesConfig.error`** now covers **only the password-protected case** (a Files Disk problem while docked). Busy unmounts go into `Disk.unmountError` (7.0), for every disk type.
- **Size (decided for v1):** every docked disk gets `sizeBytes` and `freeBytes` on `Disk` (not in `filesConfig`).
    - They are read with Node's `fs.statfs` on the mount point (no sudo), on dock and every 10 minutes.
    - To keep the Automerge document small, the values are rounded, and the Engine writes to the store only when free space changed by more than 1% or 100 MB.
    - Both are cleared on undock.

### 7.3 Mounting into opted-in Apps

**Opt-in per service.** An App opts in in its compose file, naming the services that get the mount:

```yaml
x-app:
  filesMount:
    path: /mnt/idea-files
    services: [nextcloud-app]   # never the database
```

The Engine stores this as `App.filesMount`.

**Paths inside the container.** Each Files Disk appears at `<path>/<slug>-<id6>`, for example `/mnt/idea-files/school-files-3f9a2c`. The suffix is always added: `id6` is the first six characters of the disk ID. The Engine makes the slug from `shareName` and sanitises it (no `/`, no `..`, no leading dot). The display names travel to the App as a small **read-only JSON file** mounted by the same override (for example `/mnt/idea-files/.idea-files.json`: slug-id → share name). The App shows the plain name and only adds the suffix when two names clash.

**Compose override.**

- For every create, start or remount of an opted-in instance, the Engine writes a fresh override file with **long bind syntax** (`type: bind`, `bind.create_host_path: false`, so Docker never creates a missing folder on the SD card).
- The file lives in the Engine-owned state folder **`~/.local/state/idea-engine/`** under pi's home, which needs no sudo. This is on the system disk, outside the git checkout and outside `/tmp`, **not** on the App Disk. There is one file per instance ID. The Engine creates the folder at startup if it's missing.
- It is rebuilt from the store every time and never reused.
- One helper sets `COMPOSE_FILE=compose.yaml:<override>` for **every** compose call on that instance (`Instance.ts:1009` create, `:1074` up, stop and down) and keeps the same project name, so stop and down see the same configuration.

**Which instances are touched.**

| Instance status | What happens when Files Disks change |
|---|---|
| Running | Recreated (`compose up -d`) with the new override |
| Stopped | Left alone; it gets the current override at its next start |
| Paused / created but not started | `compose up --no-start --force-recreate` |

- A remount takes the per-instance lock and reuses the idea#109 `stillStartable` checks.
- `Instance.filesMounts` is written only after `compose up` succeeds.
- The Engine doesn't recreate Nextcloud while it is doing its first start or an upgrade (§14, open question 1).

**Dock, boot and undock.**

- **Boot:** the Engine processes Files Disks **before** starting any App Disk instances, so Nextcloud starts once with its mounts.
- **Runtime docks** are grouped over a few seconds, so docking several disks causes one recreate.
- **Eject or pulled disk:** clear `filesConfig`, mark the affected instances, recreate them without the bind, then unmount as in 7.0 (retries; if still busy: error trace, store updated anyway, `Disk.unmountError` set, mount point left alone).
- **Combined disks:** the eject path does both jobs before the single unmount. It stops the disk's own instances (as today, `usbDeviceMonitor.ts:345`) and recreates opted-in instances **on other disks** without the bind. There is still one mount and one `unmountError`, so nothing changes there. If the unmount fails, the Console's warning names the disk once, whatever its roles.
- **Nextcloud on the same disk as its files** (an App Disk with Nextcloud plus the Files role): there is **no cross-disk dependency**.
    - The files are available as soon as the disk mounts. `processFilesDisk` runs first (7.2), so Nextcloud's override already contains its own disk's `files/`.
    - On eject, Nextcloud is simply stopped with the disk. There is no recreate-without-bind for it, and its hook needs no special case.
    - When the disk moves to another Pi, Nextcloud and its files move together.
    - Nextcloud's own data (`instances/<id>/data`) and `files/` share the disk's free space. This is acceptable, but a full combined disk can break Nextcloud outright, so the Console's low-space warning on a combined disk says the Apps on this disk need space too (Kid, Pixel).

### 7.4 Erasing a disk (`eraseDisk`)

This part came in on 2026-09-27 as formatting (idea#125, merged into this proposal) and was design-reviewed the same evening by Atlas, Kid, Axle and Pixel (§14). Koen changed it on 2026-09-28 and it was re-reviewed (R1–R9). **Changed again by Koen on 2026-09-28 11:08 (pending design re-review, E1–E10):**

- **Erase is a general disk action** on every non-system disk. It is no longer only inside the Files flow.
- The result is an **empty IDEA disk**: GPT with one partition, ext4 with only `META.yaml`, filesystem label "IDEA Disk". Roles are added afterwards (`createFilesDisk`, `createBackupDisk`, `installApp`).
- The Files flow keeps an **erase first** shortcut: `eraseDisk`, then `createFilesDisk`, behind one summary and one typed confirmation.
- The command is renamed `formatDisk` → **`eraseDisk`**, the script `idea-format-disk` → **`idea-erase-disk`**, and `Engine.formatInProgress` → **`Engine.eraseInProgress`**.

**Safety model**

| | Rule |
|---|---|
| (a) **Explicit** | Erasing happens only through **Erase this disk** (a quiet secondary action on every non-system disk view) or the Files flow's **erase first** shortcut. It always goes through the summary and is confirmed by typing the disk's label exactly. The Engine never erases automatically when a disk is plugged in. *(Was: "only as a Files Disk choice".)* |
| (b) **Never overridable** | These are always refused: the Pi's own **boot or root disk** (found by lookup, never by name, connection type or model), and a disk with a partition **in use as swap** (`sd*` disks). A disk with a **foreign mount** (any mount not made by the Engine under `/disks`) is also refused. The **script is the authoritative check**. |
| (c) **Informed confirmation instead of a role-marker refusal** | *(Was: "refuse a disk with `apps/`, `instances/`, `BACKUP.yaml` or `FILES.yaml`".)* Any other disk can be erased, including ext4 disks, App Disks, Backup Disks, Files Disks, combined IDEA disks and ext4 disks with non-IDEA files. Because erasing **removes everything**, the Engine first computes a **content summary** that says exactly what will be lost. The dialog shows it, then asks for the typed label. |
| (d) **Mounted disks are ejected first (Axle)** | For a disk the Engine has mounted, `eraseDisk` goes through the normal **eject path** under one device lock: recreate Apps on **other** disks without its files, stop the disk's instances, unmount with the step-0 undock, remove the `Disk` entry, and **only then erase**. Running instances are simply stopped; the summary listed them and the typed name confirmed it. If the unmount fails, **nothing is erased**, `processDisk` runs again to restore the disk and its previously Running instances, and the trace explains why. |
| (e) **Blockers (Axle)** | Refused with "try again later" while a **backup is running** to or from the disk, while an **instance lock** is held (a start, stop or upgrade in progress), while a **Nextcloud is in its first start or an upgrade**, or while **another erase** is running on this Engine. A Nextcloud on another disk that uses this disk's files is **not** a blocker; it is recreated without the mount (rule d). *(Was: "blocked while Nextcloud uses its files".)* |
| (f) **One root script** | Root access goes through **one small script**, `/usr/local/sbin/idea-erase-disk` (source `script/build_image_assets/idea-erase-disk`). It is allowed by **one sudoers entry for that script only, with no argument list**. There is no general `mkfs`, `sfdisk` or `wipefs` rule. The script is an installed root-owned **copy** that `pi` can't write, and it **re-checks the device itself** at erase time. |
| (g) **Comes up as an empty IDEA disk** | The new filesystem contains only `META.yaml` (and `lost+found`), with the root owned by `pi` (`root_owner=1000:1000`), so no `chown` is ever needed on an erased disk. The normal mount path picks it up as an empty disk. `FILES.yaml` and `files/` come later from `createFilesDisk`, running as `pi`. *(Was: "comes up as a Files Disk" with `FILES.yaml` and `files/` baked in.)* |
| (h) **Progress and failure** | `Engine.eraseInProgress` and the `eraseDisk` command trace. The Console uses a 15-second "no response" check and a 5-minute "taking longer" message, measured on its own clock. |

**Behaviour change: ext4-only mounting.** Today the Engine runs `sudo mount` without `-t`, so exFAT and FAT sticks get mounted, and idea#121 could then write `META.yaml` onto them. From step 3 on:

- The Engine mounts **only with `-t ext4`**. Anything else stays unmounted and never gets `META.yaml`.
- Non-ext4 sticks that used to mount (and showed as "empty") will no longer do so. This fits the IDEA disk format, because every IDEA disk is ext4.
- A new sudoers entry matches the exact typed command, `mount -t ext4 <device> <mount point>`, in that order (§10).

**Unformatted disks: how new sticks reach the Console.** Today a new stick often never reaches the Console at all:

- The udev rule `90-docking.rules` already links the whole disk `sd?`, plus `sd?1` and `sd?2`.
- But `validDevice` skips whole disks (`usbDeviceMonitor.ts:95–100`).
- So a stick without a partition table, or with an unsupported filesystem, doesn't show up.

In step 3:

- **No udev change (Axle).** Step 3 changes neither `90-docking.rules` nor the `[12]` pattern in sudoers. The whole disk `sdX` is already linked. `validDevice` now accepts whole disks **only so the Engine can run `lsblk` on them**; whole disks are **never mounted**. Partitions 3 and higher stay out of scope, as today.
- **Unformatted disks:** a **whole, non-system disk** with **no ext4 filesystem on any partition** (by `lsblk` FSTYPE; ext4 on partition 3 or higher also counts) isn't a `Disk` in the store, because it can't be mounted. The Engine publishes it in **`Engine.unformattedDisks`**, read with `lsblk -J -b -o NAME,TYPE,FSTYPE,SIZE,MODEL,SERIAL` (no sudo), so that the Console can show it and offer **Make this a Files Disk**. Disks with ext4 are ordinary `Disk` entries and are formatted by their disk ID. *(Was: `Engine.formatCandidates`, a separate list of disks with a Format action.)*
- **`Engine.unformattedDisks`**, an array of `{ id, device, sizeBytes, model, fsType, label }`:
    - `id` comes from the disk's serial (`readHardwareId` for the two known models, otherwise `lsblk` SERIAL). If there is no serial, the Engine generates an ID that stays the same for as long as the disk stays plugged in. The Engine writes this **same ID** into the new `META.yaml` (`isHardwareId: true` only when it came from `readHardwareId`).
    - `label` is the text to type to confirm, for example **"Intenso 32 GB"** (model plus rounded size, or "USB disk" when there is no model).
- Entries are added and removed as disks come and go, and rebuilt at Engine startup.

**Format target and confirmation label.** `eraseDisk` takes a **target ID**: either an `unformattedDisks[].id`, or the ID of a `Disk` docked to this Engine (any type except `system`). For a `Disk`, the Engine finds its whole disk with `lsblk -no PKNAME`. The label is the disk's **name** for a `Disk` (for example "MilkWise Apps") and the model-and-size label for an unformatted disk. The Engine keeps labels unique among its disks by adding " (2)", " (3)" and so on, and returns the label with the summary.

**Disk ID and name after an erase.** An IDEA disk **keeps its disk ID**: the ID from its `META.yaml`, or its hardware serial. A disk without one gets the `unformattedDisks` ID (serial or a new ID). The new `META.yaml` carries the ID over, so the Console shows the same disk, now empty. Its `diskName` becomes **"IDEA Disk"**, made unique among the disks in the store with " (2)", " (3)" and so on, because `installApp` and `createBackupDisk` take a disk **name** (`Commands.ts:170`, `EmptyDiskPanel.tsx:102, 127`) (§14, E7). `META.yaml` is used **only** to carry over the ID; it never blocks a format. **Store cleanup after erasing an IDEA disk (Axle, Pixel, Kid):**

- The erase itself **removes that disk's instance entries** (`storedOn` = that disk) from the store. They are not marked Missing and leave no ghost rows. Their IDs, names and data sizes go into the trace, and the Console shows them in the erase result.
- `appDB` is unchanged. **Backups on other disks stay**, because they are how to restore.
- If the erased disk was a **Backup Disk**, the erase **clears every backup setting or link that points at that disk ID** (`Disk.backupConfig`, and any link held for an instance). The ID may be a hardware serial (Samsung FIT, Intenso), so it can't change. A later backup must never create a new repository there without being asked. The Console's backup view says plainly that the backups on that disk were erased. Making the empty disk a Backup Disk again is a separate, explicit `createBackupDisk`.

**Content summary (computed on request).** A new command **`summariseDisk <targetId>`** (scope `engine`) computes the summary. The result is returned in that command's trace, in a new optional **`CommandTrace.result`** field (a JSON string; `null` for other commands).

- **Why on request, and not a field in the store:** the summary is only needed while the dialog is open. Counting files on a large disk takes time, and the numbers change constantly while Nextcloud is in use. Keeping them in the synced store would add churn to the Automerge document for every docked disk. Traces live in the separate command-log document, a ring buffer that prunes itself.

**Summary schema** (`contentSummary`, in `CommandTrace.result`):

```
{ targetId, label, model, sizeBytes, usedBytes | null, fsType | null,
  apps: { name, version }[],
  instances: { id, name, running: boolean, dataBytes: number | null }[],
  backups: { instanceId, instanceName, lastBackup: number | null, snapshots: number | null }[],
  files: { fileCount, totalBytes, partial: boolean } | null,
  other: { entryCount, totalBytes, partial: boolean } | null,
  otherPartitions: { device, fsType | null }[],
  readable: boolean,
  serial: string | null,
  computedAt }
```

**How the Engine computes the summary:**

- **A mounted `Disk`** (the normal case): as `pi`, **no sudo**.
    - `apps` and `instances` (with running state) come from the store (`storedOn`). Each instance's `dataBytes` comes from walking `instances/<id>` (Kid: the App can be rebuilt, the data can't).
    - `backups` come from `BACKUP.yaml` and the store (`backupConfig`), **not** `borg list`, so `snapshots` is normally `null`. If `borg list --short` is ever needed, it runs with a **20 s timeout** and sets `partial` on timeout (Axle, Pixel).
    - `files` and `other` come from walking `files/` and the root entries that aren't IDEA entries (`META.yaml`, `FILES.yaml`, `BACKUP.yaml`, `apps/`, `services/`, `instances/`, `backups/`, `lost+found`).
    - `usedBytes` comes from `fs.statfs`.
    - Entries that `pi` can't read are skipped and the section is marked `partial: true` (for example files that Nextcloud made private to uid 33).
- **An unformatted disk** (no ext4): **no mount at all**. The summary has only the label, model, size and `fsType`, with `readable: false`, and the dialog says **"contents unknown"**. The Engine never mounts FAT, exFAT or NTFS.
- **An ext4 disk that is plugged in but not mounted** (after an eject, or ext4 only on partition 3 or higher): **not a format target**, so no summary. The operator re-plugs it first, and it is docked and summarised as a mounted `Disk`. There is **no `--summarise` mode** in the script (Atlas, Axle): a second root code path would add the risk of a stray read-only mount that the Engine doesn't track.
- **Limits (Axle, Pixel):** the walk stops after **100,000 entries or 10 seconds** and sets `partial: true`; the Console then shows the counts as "at least".

**System-disk helper.** One shared Engine helper finds the system disks by lookup: `findmnt -no SOURCE /` and `findmnt -no SOURCE /boot/firmware`, each mapped to its parent disk with `lsblk -no PKNAME`.

- It replaces the guess in `usbDeviceMonitor.ts:57–75` ("root's parent + 1", `sdX` only).
- It never uses names, connection type or model. On the IDEA Pis the system disk is itself a USB SSD at `/dev/sda` (`/` on `sda2`, `/boot/firmware` on `sda1`, `TRAN=usb`), and on idea02 it is an Intenso, a model `readHardwareId` treats specially.
- The helper also flags disks with a foreign mount or (for `sd*` disks) a partition in use as swap. The script repeats all of this itself.

**Command:** `eraseDisk <targetId> <summaryTraceId> <confirmName…>` (scope `engine`). *(Was: `formatDisk`.)*

**The Files shortcut is two commands, sent by the Console** (proposed; §14, E1): after the `eraseDisk` trace closes `ok`, the Console sends `createFilesDisk <diskId>` straight away, with no second confirmation.

- **Why not one command or a flag:** the erase and the role step are already separate commands with their own checks, and `createFilesDisk` on an empty disk is exactly the normal path. A combined command would duplicate it inside the erase and give the script a Files-specific mode again.
- **Atomicity isn't needed:** between the two commands the disk is a valid empty IDEA disk. If `createFilesDisk` fails or the Console goes away, the operator just sees an empty disk and presses **Make this a Files Disk**; nothing is lost or half-made.
- **Nextcloud recreate and timing:** the count is unchanged from the single-command design.
    - The eject step recreates a Nextcloud on another disk without the old files (only if the erased disk had the Files role).
    - `createFilesDisk` then recreates it with the new mount, like docking a new Files Disk.
    - The empty disk itself triggers no recreate.
    - If the first recreate put Nextcloud into its first start or an upgrade, the second is held back by the existing no-recreate rule (7.3) and happens once Nextcloud is ready. The Files section shows "Nextcloud supports Files Disks but isn't running" or the mounted state as usual.
- **The Console's success rule for the shortcut:** `eraseDisk` `ok`, then the `createFilesDisk` trace `ok` with `'files'` in `diskTypes`. The progress shows a final "making a Files Disk" step.

- `summaryTraceId` is **required** (Axle, Pixel). It is the trace ID of a `summariseDisk` run. The Engine checks that the summary is for the **same disk ID and serial** and is **less than 10 minutes old**; otherwise it refuses ("The summary is out of date. Check the disk again.").

- `confirmName` is the last argument and **variadic** (like `createBackupDisk`'s instance list). A label with spaces arrives as several tokens, which the Engine joins with single spaces.
- It must **exactly match** the target's current label.
- The trace records `args.targetId`.
- The handler throws on the first failure, so the trace closes as `error`. Messages show the label.

**Engine steps**

1. **Checks:**
    - the target exists on this Engine;
    - `confirmName` equals its label, and `summaryTraceId` names a `summariseDisk` trace for this disk ID and serial, less than 10 minutes old;
    - the helper says it is not a system disk, has no swap and no foreign mount;
    - no blocker (safety rule e): no running backup, no held instance lock, no Nextcloud in first start or upgrade;
    - **no other erase is running on this Engine**. A second concurrent `eraseDisk` gets a refusal trace, which the Console shows as an error.
2. **Lock:** lock the device for the whole erase, and set `Engine.eraseInProgress = { targetId, label, step: 'checking' }`. `addDevice` skips locked devices, so **nothing auto-mounts during an erase**.
3. **Eject if mounted** (`Disk` targets only), reusing the eject path under the same lock:
    - recreate Nextcloud (and any opted-in App) on **other** disks without this disk's Files mount, exactly as when a Files Disk is undocked (7.3); otherwise the unmount fails as busy;
    - stop the disk's instances;
    - unmount every Engine mount of that whole disk under `/disks` with the step-0 undock (plain `umount` with retries, never `rm -fr` while mounted);
    - remove the `Disk` entry.
    - If an unmount fails: **nothing is erased**. Unlock, clear `eraseInProgress`, run `processDisk` again to restore the disk and its previously Running instances, and close the trace as `error` ("School Files couldn't be unmounted, so nothing was erased: <reason>").
4. **Staging (as `pi`):** write `~/.local/state/idea-engine/erase-staging/<id>/` with **only `META.yaml`** (the kept or new disk ID, `diskName` "IDEA Disk" made unique). *(Was: also `FILES.yaml` and `files/`.)* `FILES.yaml` and `files/` now come from `createFilesDisk` afterwards, running as `pi`, which avoids any `root_owner` or copied-owner issue on `files/`.
5. **Erase:** `sudo /usr/local/sbin/idea-erase-disk /dev/sdX <serial|-> <sizeBytes> "IDEA Disk" <stagingDir>`. The script prints step markers, which the Engine copies into `eraseInProgress.step`.
6. **Mount:** the script ends with `udevadm settle`. The Engine then calls `addDevice` for the new partition itself. It still holds the lock, so there is no udev-triggered duplicate. It mounts the partition with `-t ext4`, finds `META.yaml` with the disk's ID, and `processDisk` finds no role, so the disk is published as **empty** (`['empty']`, 7.2).
7. **Finish:**
    - remove the entry from `unformattedDisks` (if it was one);
    - remove the old instances stored on the disk from the store (IDs, names and data sizes into the trace) and clear backup settings and links pointing at the disk ID;
    - unlock, clear `eraseInProgress`, delete the staging folder.
    - The trace closes `ok` once the disk is docked again with `diskTypes` exactly `['empty']`, otherwise `error`.

**The script `idea-erase-disk <device> <serial|-> <sizeBytes> <label> <stagingDir>`** *(was `idea-format-disk`)* (runs as root; `set -eu`; calls every tool **by full path**, for example `/usr/bin/lsblk`, `/usr/bin/findmnt`, `/usr/sbin/wipefs`, `/usr/sbin/sfdisk`, `/usr/sbin/mkfs.ext4`, `/usr/bin/udevadm`):

- **Arguments:**
    - `device` matches `^/dev/sd[a-z]$` (whole disk only);
    - `serial` is `-` or a short safe string;
    - `sizeBytes` is digits;
    - `label` matches `^[A-Za-z0-9 _-]{1,16}$`;
    - `stagingDir` is exactly `/home/pi/.local/state/idea-engine/erase-staging/<id>`, a real directory owned by `pi`. A symlink anywhere in the path is refused.
- **Re-checks the device at erase time (authoritative, never overridable):**
    - `lsblk` says `TYPE=disk`, and its **serial and size match** the arguments (not the name alone);
    - it is **not** a system disk (the same `findmnt` + `lsblk -no PKNAME` lookup as the Engine helper);
    - **nothing on it is mounted** (the Engine has already ejected it) and no partition is **in use as swap** (checked for `sd*` disks).
- **No role-marker refusal any more** *(Was: a read-only mount looking for `apps/`, `instances/`, `BACKUP.yaml` or `FILES.yaml`, then refuse)*. The content summary and the typed label take its place. The script no longer mounts anything.
- **Then** (from here on, a `trap` runs `wipefs -a` on the device if the script exits with an error, so a half-made disk always shows up as unformatted; Axle):
    1. `wipefs -a` on the device;
    2. a **GPT** table with **one partition** (`sfdisk`). A filesystem on the whole disk wouldn't match the udev rule and the device conventions;
    3. `udevadm settle`;
    4. `mkfs.ext4 -F -L <label> -E root_owner=1000:1000 -d <stagingDir> /dev/sdX1`, where `<label>` is "IDEA Disk" and the staging folder holds only `META.yaml` (e2fsprogs 1.47.2 on both Pis supports `-d`). `root_owner` keeps the root `pi`-owned, so the `chown -h` step is never needed on an erased disk;
    5. `udevadm settle`.
- **Messages:** clear exit messages, for example "refused: /dev/sda holds the root filesystem". The Engine passes them into the trace unchanged.

**Failure:**

- If the unmount fails, nothing is erased and `processDisk` restores the disk and its previously Running instances (step 3).
- If the script refuses before the erase starts, the disk's contents are untouched. It was already ejected, so the Engine re-adds it when it unlocks.
- If it fails after the erase started, the script's exit `trap` runs `wipefs -a`, so the disk shows up as an unformatted disk and the operator can simply erase it again (or use the Files shortcut).
- The trace carries the script's message.
- The Engine never kills the script halfway, because an interrupted `mkfs` is worse than a slow one.

**Why a 5-minute "taking longer" message:** `mkfs.ext4` with its default lazy initialisation takes seconds even on large disks. Slow USB 2.0 sticks, large spinning disks, stopping instances, `udevadm settle` and the mount can add a minute or two. Five minutes leaves a wide margin without hiding a hung format for long.

### 7.5 Store schema

| Where | Field | Notes |
|---|---|---|
| `Disk` | `filesConfig: { shareName: string; readOnly: boolean; passwordProtected: boolean; error: string }` or `null` | `error` is a string or `null` and is **only** used for a password-protected disk. Set by `processFilesDisk`. Reset to `null` in `createOrUpdateDisk` and `undockDisk`, like `backupConfig`. The password never goes into the store. |
| `Disk` | `unmountError: { engineId: EngineID; mountPoint: string; fsUuid: string; message: string }` or `null` | **All disk types.** Set when an unmount is still busy after the retries. `mountPoint` is where the disk was mounted (for example `/disks/sdb1`); it's needed because `device` is `null` after undock. `fsUuid` is the filesystem UUID recorded at mount time (`lsblk -no UUID /dev/<dev>`), so the startup check can tell this disk apart from a different disk later mounted at the same path. Kept after undock (`dockedTo` becomes `null`), so `engineId` says which Pi has the stuck mount. Cleared on the next successful mount of that disk, or at Engine startup unless `mountPoint` is still mounted with the same `fsUuid` (7.0). Added in step 0. |
| `Disk` | `sizeBytes: number` or `null`, `freeBytes: number` or `null` | All docked disks. `fs.statfs` on dock and every 10 minutes, rounded, written only on a change of more than 1% or 100 MB. Cleared on undock. |
| `Engine` | `unformattedDisks: { id: string; device: string; sizeBytes: number; model: string or null; fsType: string or null; label: string }[]` | Whole non-system disks without an ext4 filesystem, on this Engine (§7.4). The Console shows them so it can offer **Erase this disk** and the Files flow's erase-first shortcut on non-IDEA sticks. Updated as disks come and go, rebuilt at startup. *(Was: `formatCandidates` with `hasFiles` and `formatProgress`.)* |
| `Engine` | `eraseInProgress: { targetId: string; label: string; step: 'checking' or 'stopping and unmounting' or 'partitioning' or 'creating filesystem' or 'mounting' }` or `null` | At most one per Engine. Set for the whole `eraseDisk` run, so progress also works for `Disk` targets, which undock during the erase. Renamed from `formatInProgress` because the command is now `eraseDisk` and nothing has shipped yet, so the rename costs nothing. |
| `CommandTrace` (command log) | `result: string` or `null` | New optional field: a JSON result for commands that return data. Used by `summariseDisk` for the `contentSummary` (§7.4). `null` for all other commands. |
| `App` | `filesMount: { path: string; services: string[] }` or `null` | From `x-app.filesMount` |
| `Instance` | `filesMounts: DiskID[]` | Written only after a successful `compose up` |
| `DiskType` | `'files'` | Already exists in `CommonTypes.ts:39` |

`diskDB`, `appDB` and `instanceDB` are maps, so `store-template.json` stays untouched.

## 8. Console changes (agent-console-dev)

- **Several roles per disk (Pixel):** **one badge per role** (app, backup, files) in that **fixed order**, in both the tree row and the disk header (today `NetworkTree.tsx:29–30` shows only `diskTypes[0]`). The right pane shows a section per role (instances, backups, Files) instead of choosing one panel (`rightPanelFor`, `App.tsx:46–58`, today picks the Backup panel whenever `'backup'` is present).
- **Role buttons (Pixel, approved by Steve; empty-disk state pending re-review):**
    - **Empty disk state** (`diskTypes` `['empty']`, including a freshly erased disk): the existing Empty Disk panel (`EmptyDiskPanel.tsx`) with its three options: **Make this a Files Disk** (`createFilesDisk <diskId>`), **Make this a Backup Disk** (`createBackupDisk`, `EmptyDiskPanel.tsx:102`) and **Install App** (`installApp`, `EmptyDiskPanel.tsx:127`). It replaces "The Engine will format this disk…" (`EmptyDiskPanel.tsx:277–289`).
    - **Add Files to this disk** on a disk with Apps or backups, with a short confirmation that nothing on the disk is changed (sends `createFilesDisk <diskId>`).
    - **Make this a Files Disk** on unformatted or other-files disks: the **erase first** shortcut only.
    - **Erase first** is also offered inside the Files flow on App and Backup Disks. It is `eraseDisk` then `createFilesDisk`, behind one summary and one typed name.
- **Erase this disk (pending re-review):** a **quieter secondary action on every non-system disk view** (for example a text button or an overflow menu item below the role buttons), less prominent than the role buttons. It goes through the same summary, typed name and out-of-date rule, and leaves an empty disk. *(Was: "Erase the disk and start fresh" and "Erase and start again" as Files choices.)*
- **Eject on combined disks:** `canEject` (`NetworkTree.tsx:41`) hides eject only on a **pure** Backup Disk. On combined disks eject is shown, and the Engine refuses it while a backup is running.
- **Low space on a combined disk:** the low-space warning says that the Apps on this disk need space too (Kid, Pixel).
- **One reusable helper to wait for a command's result:**
    1. Before sending, record the IDs of the traces that already exist.
    2. The result is the first **new** trace of that command whose ID argument matches (`args.diskId` or `args.targetId`). It doesn't use timestamps, because a school Pi may have no NTP.
    3. **Error:** show the trace's `errorMessage` in the flow.
    4. **Success:** the trace is `ok` **and** the disk's `diskTypes` includes `'files'`.
    5. **Timeout (15 s):** "The Engine didn't respond. It may not support Files Disks yet."
    `summariseDisk` reads its answer from the trace's `result`. Backup Disk and Install App can reuse the helper later.
- **Files section:** add a `'files'` case to the disk's right pane and a section showing name, size and free space, and the three "available in" states:
    - **mounted:** instances whose `filesMounts` contains the disk;
    - **opted in but not running:** Apps with `filesMount` whose instances on this Engine aren't running;
    - **none.**
    It also has a **Not mounted** state: for the password case (`passwordProtected` / `filesConfig.error`) and for a busy unmount (`unmountError`). All of this uses derived signals only, with no extra state. **Eject** reuses the existing `ejectDisk` command.
- **Erase dialog (§7.4):**
    - Unformatted disks appear as disks under their Engine's row, keyed by `id`, with **Make this a Files Disk** (erase first) and **Erase this disk**. There is no separate candidates list.
    - **Summary:** the flow sends `summariseDisk <targetId>` and shows the `contentSummary` from the trace's `result`: label, model, size, filesystem, used and total space, Apps (name, version), instances with their data sizes (running ones marked "will be stopped"), backups (instance, last backup), Files (count, size), other files (count, size), and "at least" where the walk hit its limit or couldn't read everything. "contents unknown" when `readable` is false. Then the erase warning.
    - **Confirm:** the field must **exactly** match the summary's `label`. It sends `eraseDisk <targetId> <summaryTraceId> <label>`. **After 10 minutes** (Console clock) the typed-name box is replaced by "The summary is out of date. Check the disk again."
    - **Progress** comes from `Engine.eraseInProgress.step` (checking, stopping and unmounting, partitioning, creating filesystem, mounting).
    - **The result** is the first new `eraseDisk` trace with that `args.targetId`, found with the same trace-ID helper.
    - **Timing, on the Console's own clock:** 15 s with no progress and no trace → "The Engine didn't respond." After 5 minutes → "This is taking longer than expected. Don't unplug the disk." It keeps watching, and there is no cancel.
    - **Success:** the disk appears as an empty disk with the same ID and the Console opens its Empty disk state; with the Files shortcut the Console then sends `createFilesDisk` and opens the Files Disk. The result lists the **removed instances with their data sizes**. If the disk held backups, the backup view says plainly that they were erased. **Error:** show the trace's message ("try again later" for a blocker, an out-of-date summary, a refused second format, a failed unmount "nothing was erased"). **Disk disappears** while the dialog is open → close the dialog and say the disk was removed.
- **Eject confirmation on combined disks:** list all roles and what is affected: instances on the disk that stop, Apps that lose its files, and backups that become unavailable.
- **Unmount warning (all disk types):** when a disk has `unmountError`, show a warning on **that Engine's row** in the network tree (found by `unmountError.engineId`, because an undocked disk has `dockedTo: null` and would otherwise appear nowhere). Example: "School Files couldn't be unmounted cleanly. Restart this Pi." While the disk is docked, show the same warning on the disk's own view.
- **Types and commands:** new commands `createFilesDisk <diskId>`, `summariseDisk <targetId>` and `eraseDisk <targetId> <summaryTraceId> <confirmName…>` (confirmName = the target's `label`). Add `filesConfig`, `unmountError` (`{ engineId; mountPoint; fsUuid; message }`), `sizeBytes`/`freeBytes`, `Engine.unformattedDisks` (`{ id; device; sizeBytes; model; fsType; label }[]`), `Engine.eraseInProgress`, `CommandTrace.result`, the `contentSummary` type, `App.filesMount`, `Instance.filesMounts` and the missing `'system'` DiskType to `src/types/store.ts`. Update `docs/ARCHITECTURE.md`.
- **Mock store fixtures and tests:** a Files Disk in each state, combined disks (`['app', 'files']`, `['app', 'backup', 'files']`) with all badges in fixed order and all sections, eject shown on combined disks and hidden on a pure Backup Disk, the low-space warning on a combined disk, unformatted disks (including two with the same model and size, labelled " (2)"), the Empty disk state after an erase ("IDEA Disk", "IDEA Disk (2)"), Erase this disk on every disk kind, the Files erase-first shortcut (two commands, one confirmation, a failed `createFilesDisk` leaving an empty disk), the Files actions (which appear for empty, App/Backup, Files, unformatted and other-files disks), the helper (error, success, timeout), the summary display (running instances, data sizes, "at least", contents unknown), and the erase dialog (exact label match, out-of-date summary after 10 minutes, progress steps, 5-minute message, removed instances in the result, disk removed mid-dialog, refused second format, failed unmount).

## 9. App changes (app-nextcloud, agent-app-dev)

**Opt-in:** `app-nextcloud/compose.yaml` gets `x-app.filesMount: { path: /mnt/idea-files, services: [nextcloud-app] }`. The service keeps `restart: no`.

**How the files appear inside Nextcloud: Option A, external storage (decided).** Nextcloud's *External storage* app, **Local** backend. The other options (a bind into Nextcloud's data folder, Group Folders) were rejected: they tie the files to one user or store them in Nextcloud's own format.

- **The hook.** A script in `/docker-entrypoint-hooks.d/before-starting/` (a standard hook folder of the official Nextcloud image) runs at every container start:
    - It enables `files_external` once.
    - It reconciles storages with the folders under `/mnt/idea-files/`: it creates any storage that's missing, using the display name from `.idea-files.json`, and deletes only storages **it created** whose folder is gone. Storages an admin made by hand are never touched.
    - It sets "check for changes on direct access", so files added outside Nextcloud show up.
    - Deleting a storage only removes Nextcloud's setting, **never files**.
- **Ownership: a small root entrypoint wrapper.**
    - The wrapper is kept on the App Disk and mounted read-only. There is **no custom image**.
    - It changes the owner of each top-level `/mnt/idea-files/<x>` folder to uid 33 **only when it is wrong**, and not recursively. It then `exec`s the image's normal `/entrypoint.sh`.
    - Result: new files on the disk belong to uid 33 (see the note in §3).
- **Convention doc** (`agent-app-dev`):
    - Document `x-app.filesMount`.
    - Apps using `filesMount` must keep `restart: no`, so Docker never restarts them on its own with a stale mount; the Engine decides when they start.
    - State that **Engine-generated Files Disk binds are allowed**. (Kid: the current "named volumes only" wording already doesn't match reality, since today's Apps use binds relative to the App Disk such as `./data/...`. Reconciling the general App convention is a **separate issue for Kid**, not part of this work.)
- **Erased disks need no App changes (Kid):** an erased disk made into a Files Disk gets `files/` from `createFilesDisk` as `pi` (uid 1000), and the entrypoint wrapper changes it to uid 33 as for any other Files Disk. An erased App Disk is an ordinary empty disk and can be a target for **Install App** (`installApp`, by disk name) or copy/move (§14, E9).
- **Nextcloud on its own Files Disk (combined disk):** Nextcloud installed on an App Disk that also has the Files role sees that disk's `files/` like any other Files Disk (7.3). The wrapper only touches the top-level `/mnt/idea-files/<x>` folders, never Nextcloud's own `instances/<id>/data`. The hook and wrapper need **no special case** (Kid, R6). **Add Files to this disk** triggers the same Nextcloud recreate as docking a new Files Disk, with the same no-recreate rule during first start or an upgrade. Sharing space with `files/` is acceptable; the Console warns on low space (§8).
- **Testing:** Kid tests the hook offline against a fake `occ` first, then with the harness (a Files Disk fixture next to a Nextcloud instance).

## 10. Ops and permissions

**Sudoers: one new entry** in `script/build_image_assets/10-engine.sudoers`:

```
/usr/bin/chown -h pi\:pi /disks/sd[a-z][12]
```

- It applies to the **disk root folder only**. It is not recursive and it doesn't cover subfolders. **`-h`** (Atlas, Axle) means a symlink is changed itself and never followed. The Engine runs **exactly** `/usr/bin/chown -h pi:pi /disks/<dev>`, in that argument order.
- Before changing it, the Engine records the root folder's previous uid:gid and mode in the trace, so the change can be undone by hand.
- `createFilesDisk` uses it after the role, root-content and ext4 checks and before the writable check. On an App or Backup Disk it changes only the owner of the root folder itself; `apps/`, `instances/` and `backups/` keep their owners. idea#121 uses it only on non-system disks whose root isn't writable. Root-owned App and Backup Disks are not refused. The combined-disk change adds **no new sudoers entry** (§14, R2).
- No `umount -l`, no recursive chown.
- The PR must add the code-mapping comment in the file header (like the existing `ENGINE_*` aliases) and pass `visudo -cf`.

**Rollout to existing Pis (Atlas):**

- The Engine PR that adds the entry ships the updated `10-engine.sudoers` as a **file that can be installed on its own**. Its description names the **first Engine commit that needs it**.
- Before deploying that commit, Atlas installs the file on each Pi: `visudo -cf` on the new file, then an **atomic move** into `/etc/sudoers.d/10-engine`. idea03 first, then idea02. The `chown -h` entry ships in **step 0** in this standalone file.
- **Post-install checks (step 0):** `sudo -l -U pi /usr/bin/chown -h pi:pi /disks/sdb1` (the exact command) matches through `10-engine`, `visudo -cf` passes, and **`/disks` is still `root:root 755`**.
- Without the entry, `createFilesDisk` fails with a clear error and never half-creates a disk (§7.1). Everything else keeps working.

**Sudoers changes for erasing (step 3)** in `10-engine.sudoers`:

```
/usr/local/sbin/idea-erase-disk        (was idea-format-disk; renamed before anything shipped)
/usr/bin/mount -t ext4 /dev/sd[a-z][12] /disks/sd[a-z][12]    (added to ENGINE_MOUNT; the old untyped entry stays during the changeover)
```

- **The script entry has no argument list** (not `""`, which would allow only a call with no arguments). The script validates all its arguments itself. There is no general `mkfs`, `sfdisk` or `wipefs` rule.
- The entry points at the installed copy in `/usr/local/sbin`, **never into the git checkout**.
- **The typed mount entry (Atlas).** The Engine now mounts only with `-t ext4` (§7.4). Sudoers matches arguments **exactly and in order**, so the entry spells out exactly what the Engine runs: `/usr/bin/mount -t ext4 /dev/sd[a-z][12] /disks/sd[a-z][12]`. The Engine code must use **exactly that argument order** (`-t ext4`, then the device, then the mount point).
- **Changeover:** the old untyped entry (`/usr/bin/mount /dev/sd[a-z][12] /disks/sd[a-z][12]`) stays **alongside** the new one. Atlas installs the file on idea03 and then idea02 before the deploy. A **follow-up PR removes the old entry** once both Pis run the new commit.
- **The `[12]` pattern stays (Axle).** Step 3 doesn't support partitions 3 and higher (out of scope, as today), so the `[12]` pattern in the mount and unmount entries is unchanged. Step 3 adds a **unit test that compares the Engine's mount command** against exactly `/usr/bin/mount -t ext4 /dev/sd[a-z][12] /disks/sd[a-z][12]`.
- The code-mapping comment and `visudo -cf` rules apply as before.

**The script is installed as a copy (Atlas):**

- Source: `script/build_image_assets/idea-erase-disk` in the Engine repo.
- `build-engine` installs a **copy** with `install -o root -g root -m 0755` into `/usr/local/sbin` (root-owned, not writable by `pi`), **never a symlink**. If `pi` could change it, the sudoers entry would amount to full root.
- It lives on the Pi's root filesystem and `build-engine` puts it back on every install, so it **survives a reboot and a reinstall**.
- Atlas's pre-deploy diff **reinstalls it whenever it differs** from the installed copy, before the Engine commit that needs it.
- No new packages: e2fsprogs 1.47.2 (with `mkfs.ext4 -d`), `sfdisk` and `wipefs` are already on both Pis.

**Rollout per Pi, idea03 first, then idea02:**

1. Install the script (copy).
2. Install the sudoers file (`visudo -cf` + atomic move).
3. **Post-checks:** `sudo -l -U pi /usr/local/sbin/idea-erase-disk` and `sudo -l -U pi /usr/bin/mount -t ext4 /dev/sdb1 /disks/sdb1` (the exact typed command) must both match **through `10-engine`**, `visudo -cf` passes, and `/disks` is still `root:root 755`.
4. Deploy the Engine commit.

**udev rule.** Step 3 doesn't change `90-docking.rules` (Axle). If a later change does, Atlas installs it through `build-engine` and runs `udevadm control --reload`, one Pi at a time (idea03, then idea02).

**Rollback** runs in reverse order. **Erase tests run on idea03 only.**

- **The blanket rule is still there.** `pi ALL=(ALL) NOPASSWD: ALL` (`010_pi-nopasswd`) is still installed, so a hardware test alone can't prove the narrow entry works; the `sudo -l` post-check is what proves it. Removing the blanket rule stays a separate decision.
- **Without the new entries** (or before step 3 ships), `eraseDisk` fails with a clear error before touching the disk.
- **Script rename (pending re-review):** `idea-format-disk` becomes `idea-erase-disk`, and its sudoers entry changes name with it (still exact, still no argument list). Neither has been installed on any Pi yet, so there is **no changeover**: the step-3 sudoers file simply ships with the new name (§14, E10).
- **The 2026-09-28 changes add no sudoers entry.** The content summary runs as `pi` on mounted disks. Stopping instances and unmounting before an erase reuse the existing eject path (existing `umount` entry). The script no longer mounts anything, because the role-marker check is gone. There is **no** read-only `--summarise` mode (Atlas, Axle, R3): an unmounted ext4 disk must be re-plugged before it can be summarised.

**Engine state folder:** `~/.local/state/idea-engine/` (compose overrides and `erase-staging/` folders) is added to **Atlas's pre-deploy backup list**. It can always be rebuilt from the store, but backing it up makes a rollback easier to inspect.

**No new packages.** `sfdisk`, `wipefs`, `lsblk` (util-linux) and `mkfs.ext4` (e2fsprogs 1.47.2) are already on both Pis. No Samba or NFS.

## 11. Tests

**Engine (`test/automated/`):**

- **Step 0:** a new disk gets `META.yaml` and keeps its ID on re-dock. The root-owned disk path calls chown. Undock never removes a still-mounted path; a busy unmount gives an error trace, the store is still updated, and `unmountError` is set with the Engine ID, the mount point and the `fsUuid` recorded at mount time. It survives undock and is cleared on the next successful mount (tested for an App Disk as well as a Files Disk). **Startup cleanup:** an `unmountError` with this Engine's `engineId` whose `mountPoint` is no longer mounted (mocked `findmnt`) is cleared at startup. **A different disk mounted at the same `mountPoint`** (`findmnt -no UUID` returns another UUID than `fsUuid`) → the error is cleared. The same filesystem still mounted there (same `fsUuid`) → the error is kept. The `fsUuid` recorded at mount time (mocked `lsblk -no UUID`) ends up in the error, and one with another Engine's `engineId` is never touched. Mounting refuses when `findmnt` shows something already mounted.
- **Command:** `createFilesDisk` success on an empty disk, an App Disk, a Backup Disk and an App + Backup disk (existing ID kept, `apps/`/`instances/`/`backups/` untouched, `diskTypes` gains `'files'`, Nextcloud recreated as for a docked Files Disk and not during first start or upgrade); a root-owned App Disk is accepted and the exact `chown -h` command runs, with the previous uid:gid and mode in the trace; errors for unknown ID, disk docked elsewhere, system disk, a disk that is already a Files Disk, an Upgrade Disk, non-IDEA root entries (including a stray `files/`), non-ext4, unwritable after chown, and locked disk. Each error closes the trace as `error`, and the trace carries `args.diskId`.
- **Detection:** `processDisk` sets `['files']`, `filesConfig`, size and free space. A non-null `password` → not mounted. A combined disk gets `['app', 'files']` (and `['app', 'backup', 'files']`). `processDisk` runs Files, then App, Backup, Upgrade. On an App + Files disk an opted-in instance on the same disk starts **once**, with its own disk's mount (the Files recreate skips it). A Files-role error is recorded and App and Backup processing still run. Ejecting a combined disk stops its instances, recreates other-disk opted-in instances without the bind, and unmounts once.
- **Override:** long bind syntax, `create_host_path: false`, only the listed services, slug sanitising, always-suffixed paths, display-name JSON, rebuilt every time.
- **Status handling:** Running recreated, Stopped untouched, Paused `--no-start --force-recreate`. `filesMounts` only written after success. Boot order (Files Disks before instances) and grouping of runtime docks.
- **Erase (step 3 PR):**
    - Unformatted-disk detection from mocked `lsblk -J` output: whole non-system disks without ext4 are listed; ext4 disks, system disks (found via mocked `findmnt`/`PKNAME`, including a USB system disk and an Intenso model) and swap disks aren't. IDs come from the serial or a generated ID that stays stable while plugged in. Labels get " (2)" on a clash.
    - ext4-only mounting: a FAT or exFAT partition is not mounted and gets no `META.yaml`. Whole disks pass `validDevice` for `lsblk` only and are never mounted. A disk with ext4 on partition 3 or higher is not listed.
    - **Mount command string (Axle):** the Engine's mount command matches exactly `/usr/bin/mount -t ext4 /dev/sd[a-z][12] /disks/sd[a-z][12]` (same arguments, same order as the sudoers entry).
    - `summariseDisk`: Apps, instances with running state and data sizes, backups from `BACKUP.yaml` and the store (no `borg list`), Files and other counts and sizes, `partial` on unreadable entries and at 100,000 entries or 10 seconds, `readable: false` and no mount for an unformatted disk; the result arrives in `CommandTrace.result`.
    - `eraseDisk` refusals: unknown target, label mismatch, missing summary trace, a summary for another disk ID or serial, a summary older than 10 minutes, system disk, swap, foreign mount, running backup, held instance lock, Nextcloud in first start or upgrade, a second concurrent erase. A failed unmount: the script is never called, `processDisk` restores the disk and its previously Running instances, and the trace explains why. The success path with a fake script, for an unformatted disk, a mounted App Disk, a mounted Backup Disk and a Files Disk: device locked for the whole erase, a Nextcloud on another disk recreated without the Files mount first, instances stopped, the disk unmounted through the step-0 undock and the `Disk` entry removed before the erase, `addDevice` skips the locked device, staging built as `pi` with **only `META.yaml`** (kept disk ID, `diskName` "IDEA Disk" made unique), `eraseInProgress` steps, the Engine calls `addDevice` itself, the old instances are removed from the store (IDs, names and data sizes in the trace; `appDB` unchanged; no ghost rows), backup settings and links pointing at an erased Backup Disk's ID are cleared and **no backup recreates a repository there** on the next scheduled run, and the result is an **empty disk** with the same ID and `diskTypes` `['empty']`. Then `createFilesDisk` and `createBackupDisk` each work on that empty disk exactly as on any empty disk. The Files shortcut (two commands) ends as `['files']`; a failing `createFilesDisk` leaves a valid empty disk.
    - **Backup locks (step 0, Axle):** a backup takes the disk lock and the instance lock together via `acquireAll`; eject and erase are refused while a `backupApp` operation with that `backupDiskId` is running, including a scheduled one. A script failure gives an error trace with its message.
- **Script tests** (shell, with fake `lsblk`, `findmnt`, `wipefs`, `sfdisk`, `mkfs.ext4`, `udevadm`): refuses a partition path, a serial or size mismatch, a system disk, a mounted partition, swap, a bad label, and a bad or symlinked staging path. It **no longer** refuses a disk with IDEA role markers (a fake App Disk is erased) and never calls `mount`. A failure after the erase started runs `wipefs -a` from the exit trap. `mkfs.ext4` gets `-L "IDEA Disk"`, `root_owner=1000:1000`, and a staging folder with only `META.yaml`. It calls tools by full path and runs the steps in order with the right flags.
- **Fixture:** `test/fixtures/disk-files/` plus an opted-in sample App.

**Console:** the helper (error, success, timeout; matching by new trace ID and `args.diskId` or `args.targetId`), role badges in fixed order and sections, the Files actions per disk kind, `canEject`, the out-of-date summary, the three "available in" states, Not mounted, the summary, the Empty disk state after an erase, Erase this disk on every disk view, the Files erase-first shortcut, and the erase dialog.

**App:** the hook against a fake `occ` (create, keep admin storages, delete only its own, idempotent), the wrapper (chown only when wrong), then the harness, including Nextcloud on an App Disk that also has the Files role.

**Hardware (idea03, isolated with `mdns: false`, a person at the Pi, like idea#110).** Test setup:

- a **partitioned** ext4 disk made with default `mkfs.ext4`, so the root-owned case is tested (unpartitioned disks aren't mounted);
- a FAT stick;
- an **exFAT stick with some files on it** (the Files shortcut test);
- **two throwaway disks (Kid)**, built as images with the harness and written onto spare sticks **on idea03 by Atlas**. Nothing touches idea02 or MilkWise:
    - **Disk A** (step 8, erase an App Disk, then Make this a Backup Disk): a small test App (ARM64, health check, port 3000 or higher, a little data in a named volume);
    - **Disk B** (step 9, add Files): Nextcloud from `app-nextcloud` with the Files opt-in, to test the combined case and the recreate for real;
- Nextcloud installed from an App Disk.

Ten steps (erase and combined-disk steps on **idea03 only**):

1. Dock the FAT stick → not mounted; it appears as an unformatted disk with **Make this a Files Disk** (erase first only) and **Erase this disk** (cancel here).
2. Dock the root-owned ext4 disk → create the Files Disk → **files** badge, root now `pi:pi`.
3. Nextcloud shows the folder → upload a file.
4. Eject → Nextcloud recreated, folder gone, clean unmount.
5. Reboot with both disks docked → Nextcloud starts once with the folder, file still there.
6. Pull the Files Disk without Eject → Nextcloud recreated without it, unmount clean or a recorded error, nothing deleted.
7. **Files shortcut on the exFAT stick (idea03 only):** before erasing, the stick is not mounted and has no `META.yaml`. It appears under idea03 as an unformatted disk (for example "SanDisk 32 GB"). Choose **Make this a Files Disk** → erase first. The summary shows the model, size, `exfat` and "contents unknown". A wrong label keeps the button disabled. With the right label, `eraseDisk` runs (progress steps), the disk appears briefly as an empty disk, then `createFilesDisk` runs with no second confirmation, and a Files Disk with the **same ID** appears on a GPT partition (filesystem label "IDEA Disk", root `pi:pi`, `files/` owned by `pi` until Nextcloud's wrapper changes it). The Console opens it and Nextcloud shows it.
8. **Erase Disk A, then Make this a Backup Disk (idea03 only)** *(Was: "refusal on an unmounted App Disk", then "erase Disk A into a Files Disk")*: dock Disk A with its test App running. Use **Erase this disk** (the quiet secondary action). The summary shows the right App (name and version), the instance marked running with its data size, used and total space, and the other sections. A wrong label keeps the button disabled. With the right label, the instance is stopped, the disk unmounted and erased, and it comes back as an **empty disk** (`['empty']`, name "IDEA Disk", filesystem label "IDEA Disk", root `pi:pi`, only `META.yaml` and `lost+found`) with the **same ID**. The result lists the removed instance with its size, and the instance is gone from the store with no ghost row. Also check that the erase is refused ("try again later") while the instance is starting, and that a summary older than 10 minutes is refused. Then choose **Make this a Backup Disk** on the empty disk → it becomes a Backup Disk as today.
9. **Add Files to Disk B (idea03 only):** dock Disk B with Nextcloud running. Choose **Add Files to this disk** and confirm. `diskTypes` becomes `['app', 'files']`, `apps/` and `instances/` are unchanged, and Nextcloud is recreated and **shows the disk's own files right after Add Files**. Eject lists all affected roles, and eject is shown for the combined disk. After an eject and re-dock, Nextcloud starts **once** and shows the files again.
10. **Erase a Backup Disk (idea03 only):** use the Backup Disk from step 8 after one backup to it has run. **Erase this disk** → the summary lists the backups. Check that the erase is refused while a backup to it is running (including a scheduled one), then erase it. Afterwards, every backup setting or link pointing at that disk ID is cleared, the backup view says the backups on it were erased, the disk is empty (`['empty']`), and **no repository is recreated** on it at the next scheduled backup time.

**After every step:** the Pi's own boot and root disk untouched, nothing new under `/disks` on the SD card, no leftover mounts, 0 Engine restarts. **Then idea02** (golden), with MilkWise up the whole time.

## 12. Rollout: implementation issues per domain

| Step | Domain | Issue | Depends on |
|---|---|---|---|
| 0 | Engine + Ops | **idea#121** (write `META.yaml`) + **backup locks** (every backup takes the disk and instance locks via `acquireAll`; eject/erase checks use the running `backupApp` operation's `backupDiskId`) + **Q5 safety fix** (never `rm -fr` a mounted path; retry umount; `Disk.unmountError` (`engineId`, `mountPoint`, `fsUuid`, `message`) for every disk type, cleared at startup unless the same filesystem (`fsUuid`) is still mounted at `mountPoint`; `findmnt` check before mount) + **sudoers `chown -h` entry** (exactly `/usr/bin/chown -h pi\:pi /disks/sd[a-z][12]`, `sudo -l` check against the exact command, `/disks` still `root:root 755`; code-mapping comment, `visudo -cf`, shipped as a standalone file; PR names the first Engine commit that needs it; Atlas installs it with `visudo -cf` + atomic move on idea03, then idea02, before deploying) | — |
| 1 | Engine | Files Disk type: `FILES.yaml` detection, processing order Files → App → Backup → Upgrade, `createFilesDisk <diskId>` with checks (empty or App/Backup disks, root-owned accepted with `chown -h` and the old owner/mode in the trace, combined roles, existing ID kept), `filesConfig`, `sizeBytes`/`freeBytes`, tests, `COMMANDS.md` | 0 |
| 1b | Console | *(in parallel with 1, on the mock store)* Make this a Files Disk / Add Files to this disk, one badge per role in fixed order (tree row and header), sections per role, `canEject` only hidden on a pure Backup Disk, low-space wording on combined disks, result helper, Files section, types, fixtures | — (merge after 1) |
| 2 | Engine | Mounting: per-service `x-app.filesMount`, override helper (`COMPOSE_FILE`), status handling, locks, boot order, grouping of runtime docks, undock/eject path (including combined disks), Files before instances on the same disk, `Instance.filesMounts`, tests | 1 |
| 3 | Engine + Ops | **Erase** *(was "Formatting")*, Engine issue: no udev change (`validDevice` accepts whole disks for `lsblk` only, never mounts them); mount only with `-t ext4` (behaviour change, new sudoers mount entry); system-disk helper (`findmnt` + `lsblk -no PKNAME`) replacing the guess in `usbDeviceMonitor.ts:57–75`; `Engine.unformattedDisks` from `lsblk -J`; `summariseDisk` + `CommandTrace.result` (100,000 entries / 10 s, instance data sizes, backups from `BACKUP.yaml`); **`eraseDisk`** of any non-system disk with a required summary trace ID (same disk and serial, under 10 minutes), the eject path first (other-disk Nextcloud recreated, instances stopped, `Disk` removed, restore on a failed unmount), blockers (backup, instance lock, Nextcloud first start or upgrade), instances removed from the store and Backup Disk links cleared after success; result an **empty IDEA disk** (only `META.yaml`, label "IDEA Disk", unique name, `['empty']`); `Engine.eraseInProgress`; device lock (`addDevice` skips locked devices); **`idea-erase-disk`** script (renamed; copy installed by `build-engine`, full tool paths, serial and size re-check, no role-marker refusal, `wipefs -a` exit trap, no `--summarise` mode); sudoers entry for the script without an argument list, plus the typed mount entry `/usr/bin/mount -t ext4 /dev/sd[a-z][12] /disks/sd[a-z][12]` (exact argument order in the code, checked by a unit test against that string; old untyped entry kept until a follow-up PR removes it once both Pis run the new commit; `[12]` unchanged, partitions 3+ out of scope); tests (Engine + script: erasing a mounted App Disk, a Backup Disk, a Files Disk; erase then role). Atlas: install script, sudoers, `sudo -l` post-checks (script and the exact typed mount command), then Engine commit, one Pi at a time, idea03 then idea02 | 1 (can run alongside 2) |
| 3b | Console | **Erase**, Console issue: **Erase this disk** as a quiet secondary action on every non-system disk view; the Empty disk state after an erase (Make this a Files Disk, Make this a Backup Disk, Install App, from `EmptyDiskPanel.tsx`); the Files flow's erase-first shortcut (`eraseDisk` then `createFilesDisk`, one confirmation); summary with instance data sizes and "at least"; out of date after 10 minutes; removed instances in the result; backup view says erased backups; unformatted disks under the Engine's row; erase dialog (exact label, contents unknown, erase warning); `eraseInProgress` steps; 15 s / 5 min on the Console clock; disk removed mid-dialog | 3 (can start on the mock store) |
| 4 | App | Nextcloud opt-in, `before-starting` hook, entrypoint wrapper, convention doc (`restart: no`, Files Disk binds allowed), fake-occ tests, harness | 2 (hook can start earlier; alongside 3) |
| 5 | Ops | Hardware test on idea03 (10 steps, including the Files shortcut on an exFAT stick, erasing Kid's Disk A into an empty disk and making it a Backup Disk, erasing that Backup Disk (links cleared, no repository recreated), and adding Files to Kid's Disk B with Nextcloud; both disks written onto sticks on idea03 by Atlas; post-checks), then idea02 with MilkWise running. Erase and combined-disk tests **never** run on idea02 | 0–4 |

## 13. Out of scope (v1)

- SMB, NFS or any host-level network share.
- Password-protected Files Disks (field reserved only). `readOnly` (field reserved, ignored).
- Choosing Apps per Files Disk.
- Backing up Files Disks (only the stable ID is prepared now). This includes `files/` on a disk that is **also a Backup Disk**: backups only ever cover `instances/<id>` (`borg create …/instances/<id>`, `backupMonitor.ts:186`), so `files/` is **not** included in any backup, and the Backup role doesn't back up the disk it sits on.
- Using a Files Disk from another Pi.
- Files Disks on FAT, exFAT or NTFS (they must be formatted as ext4 first). *(Combined disks were out of scope until 2026-09-28; they are now allowed.)* Adding the Files role to an Upgrade Disk.
- Automatic erasing, erasing without the content summary and the typed confirmation, erasing the Pi's own disks or swap disks, filesystems other than ext4, cancelling a running erase, choosing a custom filesystem label (always "IDEA Disk"), erasing or summarising an ext4 disk that is plugged in but not mounted (re-plug it first; no `--summarise` mode).
- Removing the blanket `pi NOPASSWD: ALL` rule (a separate decision).
- Kolibri, Kiwix or other Apps as Files Disk users (possible later with the same opt-in).
- Quotas and per-user folders beyond what Nextcloud offers.
- **Optional separate step, not chosen:** a Console-only change that disables or labels the Files Disk button until the Engine side ships.

## 14. Design review outcome

The Design Review (Atlas, Kid, Axle, Pixel, 2026-09-27) answered the draft's nine open questions:

| Draft question | Outcome | Main voice |
|---|---|---|
| Q1 Nextcloud mechanism | Option A (external storage, Local) via a `before-starting` hook that reconciles only its own storages | Kid |
| Q2 Ownership | Read-only root entrypoint wrapper on the App Disk; non-recursive chown to uid 33 only when wrong; no custom image | Kid, Axle |
| Q3 Path naming | `<path>/<slug>-<id6>`, always suffixed; Engine sanitises; display names via read-only JSON | Axle, Kid |
| Q4 Recreate via override | Yes: long bind syntax, `create_host_path: false`, per-instance file in Engine state folder, `COMPOSE_FILE` helper, status table, locks, `filesMounts` after success | Axle |
| Q5 Pulled disk | Retry plain umount; on failure error trace + store updated + `Disk.unmountError`; never `rm -fr` a mounted path; `findmnt` check before mount. Moved to step 0 | Axle, Atlas |
| Q6 Boot order | Files Disks before App Disk instances at boot; group runtime docks; `restart: no`; no recreate during Nextcloud first start or upgrade | Axle, Kid |
| Q7 Sudoers | One entry: `chown pi:pi /disks/sd[a-z][12]` (later `chown -h`, R2), root folder only; no `umount -l`; code-mapping comment and `visudo -cf`; roll out idea03 → idea02 | Atlas |
| Q8 ID or name | Disk ID in the command and trace; name in messages | Pixel, Axle |
| Q9 readOnly | Stays reserved and ignored | all |
| Console result | Trace-ID matching with `args.diskId`, no timestamps; success = `ok` + `'files'` type; 15 s timeout; three "available in" states; Not mounted | Pixel |
| Extra | Steve decided: `sizeBytes`/`freeBytes` and `filesConfig.error` (password case) are in v1. Hardware plan with post-checks | Steve, Atlas |
| Follow-up: size | `fs.statfs`, on dock and every 10 min, rounded, write only on a change of more than 1% or 100 MB; on `Disk`, cleared on undock | Axle |
| PR review: unmount error | New `Disk.unmountError: { engineId, mountPoint, fsUuid, message }` for **every** disk type: set on a busy unmount, kept after undock, cleared on the next successful mount; the Console warns on that Engine's row and on the disk's view. `filesConfig.error` now only covers the password case | Axle, Pixel |
| PR review: startup cleanup | At startup the Engine clears every `unmountError` with its own `engineId` whose `mountPoint` is no longer mounted (`findmnt`), so the "Restart this Pi" warning goes away after the restart | Axle |
| Decision: mount point in the error | `unmountError` also stores `mountPoint` (for example `/disks/sdb1`), because `device` is `null` after undock; the startup cleanup checks it with `findmnt` (resolved the former open question 3) | Koen, on Steve's suggestion |
| PR review: same disk, not just same path | Device names get reused, so the startup check keeps the error only if `mountPoint` is mounted **and** its UUID matches. `Disk.id` isn't the filesystem UUID (`Meta.ts:145`: hardware serial for two stick models, otherwise a random ID in `META.yaml`), so the error stores `fsUuid`, recorded at mount time with `lsblk -no UUID /dev/<dev>` and checked with `findmnt -no UUID <mountPoint>`. No sudo, so no new sudoers entry. Test for a different disk at the same mount point | Atlas, Axle |
| Follow-up: deploy | Standalone sudoers file, PR names the first commit needing it, `visudo -cf` + atomic move on idea03 then idea02; clear error without it; state folder `~/.local/state/idea-engine/` created at startup and added to the pre-deploy backup | Atlas |
| Koen change: formatting (2026-09-27) | Decisions 2 and 3 changed: the Engine can format as ext4 through an explicit Console action with typed confirmation; empty ext4 disks work straight away, other non-IDEA disks can be formatted first. Koen's choices on idea#125: **GPT with one partition**; **META.yaml written immediately**; existing files don't block formatting (typed confirmation + visible warning instead), **IDEA data always refused**; the hardware test covers formatting an exFAT stick and the refusal on an App Disk *(Candidates, the role-marker refusal and "IDEA data always refused" were superseded by Koen on 2026-09-28; see the rows below.)* | Koen |
| Formatting review: Ops | System disks found by lookup only (`findmnt` for `/` and `/boot/firmware` + `lsblk -no PKNAME`), because the Pis boot from a USB SSD at `/dev/sda` and idea02's is an Intenso. The script is installed as a copy (`install -o root -g root -m 0755`), never a symlink, from `script/build_image_assets/idea-format-disk`, with full tool paths. `-d` is fine (e2fsprogs 1.47.2); symlinked staging refused. The sudoers entry has no argument list; post-check `sudo -l -U pi` matches through `10-engine`, because the blanket rule still exists. Per-Pi order: script, sudoers, post-checks, Engine commit; rollback in reverse; format tests on idea03 only | Atlas |
| Formatting review: App | The refusal test covers an **unmounted** App Disk (unit test + idea03). Refusal tests use a throwaway App Disk from the harness, never MilkWise or idea02. Formatted disks need no App changes *(Candidates, the role-marker refusal and "IDEA data always refused" were superseded by Koen on 2026-09-28; see the rows below.)* | Kid |
| Formatting review: Engine | Mount only with `-t ext4` (behaviour change); whole non-system disks without ext4 become format candidates via `lsblk -J` (no sudo); candidate ID from the serial or a generated ID kept while plugged in, written into `META.yaml`; whole disks must reach the Engine (settled in the udev follow-up below). The device is locked for the whole format, `addDevice` skips it, and the Engine calls `addDevice` after `udevadm settle`. The script re-checks serial and size. Shared system-disk helper; refuse mounted partitions and swap; the script is authoritative. Staging built as `pi` in `format-staging/`; GPT with one partition kept. Read-only role-marker check in the script *(Candidates, the role-marker refusal and "IDEA data always refused" were superseded by Koen on 2026-09-28; see the rows below.)* | Axle |
| Formatting review: Console | `Engine.formatCandidates` shown under the Engine's row. **Pixel decided:** `confirmName` must exactly match the Engine-published `label`, kept unique per Engine with " (2)", so the command is `formatDisk <candidateId> <confirmName…>`. The dialog shows Engine, model, size, filesystem, erase warning, "contents unknown". `formatProgress` steps; result by the first new trace for the `candidateId`; 15 s / 5 min on the Console clock, no cancel; on success open the new Files Disk; a second concurrent format is refused *(Candidates, the role-marker refusal and "IDEA data always refused" were superseded by Koen on 2026-09-28; see the rows below.)* | Pixel |
| Formatting open questions resolved | Script location: `script/build_image_assets`, installed by `build-engine`. `-d`: accepted. System-disk detection: the lookup helper. Disks the Engine can't mount: format candidates | Atlas, Axle, Pixel |
| Formatting follow-up: Ops (sudoers mount entry) | Sudoers matches arguments exactly and in order, so the new mount entry is `/usr/bin/mount -t ext4 /dev/sd[a-z][12] /disks/sd[a-z][12]` and the Engine uses exactly that order. The old untyped entry stays during the changeover (installed on idea03, then idea02, before the deploy), and a follow-up PR removes it once both Pis run the new commit. The post-check runs `sudo -l -U pi` against the exact typed command. Any future change to `90-docking.rules` is installed via `build-engine` + `udevadm control --reload`, one Pi at a time | Atlas |
| Formatting follow-up: Engine (udev and markers) | Step 3 changes neither `90-docking.rules` nor the `[12]` pattern: the whole disk `sdX` is already linked, and `validDevice` accepts whole disks only so the Engine can run `lsblk` for candidate detection (never mounted). Partitions 3+ stay out of scope. A unit test compares the Engine's mount command against the exact sudoers string. The refusal uses only `apps/`, `instances/`, `BACKUP.yaml` and `FILES.yaml`; `META.yaml` only carries over the disk ID. The swap check applies to `sd*` disks. A disk with ext4 on any partition (even 3+) is not a candidate (resolved the former open question 5) *(Candidates, the role-marker refusal and "IDEA data always refused" were superseded by Koen on 2026-09-28; see the rows below.)* | Axle |
| ~~Decision: ext4 disks with other files~~ **Superseded by Koen, 2026-09-28** | *Was:* v1 does **not** offer formatting for ext4 disks that already hold non-IDEA files. v1 only offers disks with **no ext4 filesystem** as format candidates. Such a disk mounts, `createFilesDisk` refuses it as not empty, and the operator empties it on another computer. It can be added later with the same script and dialog (resolved the former open question 4). *Now:* any non-system disk can be formatted after a content summary and the typed label (row below) | Steve (Lead); superseded by Koen |
| **Combined disks allowed (Koen, 2026-09-28)** | One disk can be App, Backup and Files at once. `createFilesDisk` adds `FILES.yaml` and `files/` to an empty disk or an App/Backup Disk, keeps the disk ID, and `processDisk` adds `'files'`; it refuses a disk that is already a Files Disk or has non-IDEA root files. Eject lists all roles; files on a Backup + Files disk aren't backed up. *Was:* "**No combined disks** / one role per disk" (decision 3, §13), which contradicted the Solution Description and `backup-disk.md` (~lines 329–334) and `Disk.diskTypes` being a list | Koen |
| ~~Formatting only as a Files Disk choice~~ **(Koen, 2026-09-28; superseded by Koen 2026-09-28 11:08, see the Erase row below)** | No standalone Format action and no candidates list: the "Make this a Files Disk" flow offers "Add Files to this disk (keeps everything)" and/or "Erase and format as a Files Disk" (labels refined in R7). Any non-system disk can be formatted (ext4, IDEA, combined, other files). The role-marker refusal is replaced by a content summary (`summariseDisk`, result in the trace) and the typed label. Mounted disks go through the eject path first; a failed unmount, a running backup or a lock stop the format. System disk and swap refusals are never overridable. *Was:* format candidates for disks without ext4 only; the script refused disks with `apps/`, `instances/`, `BACKUP.yaml` or `FILES.yaml` | Koen |
| Follow-up: App rule | Files Disk binds are simply allowed, not an "exception"; reconciling the general App volume convention is a separate issue for Kid | Kid |
| Re-review R1: erase of a mounted disk | One device lock for the whole operation. The normal eject path: recreate a Nextcloud on **another** disk without this disk's Files mount (as when undocking a Files Disk; otherwise umount fails as busy), stop the disk's instances, unmount with the step-0 undock, remove the `Disk` entry, then erase. Running instances are simply stopped (listed in the summary, confirmed by the typed name). Blockers ("try again later"): a running backup, a held instance lock, Nextcloud in first start or upgrade. *Replaces* "blocked while Nextcloud uses its files". Failed unmount: nothing erased, `processDisk` restores the disk and its Running instances, and the trace explains why. Failure after the erase started: the script's exit trap runs `wipefs -a`, so the disk shows up as unformatted | Axle |
| Re-review R2: ownership | Reuse the root-folder chown with `-h`: exactly `/usr/bin/chown -h pi\:pi /disks/sd[a-z][12]`, and the Engine runs exactly that. Ships in step 0 in the standalone sudoers file, checked with `sudo -l -U pi` against the exact command. The trace records the previous uid:gid and mode. Root-owned App and Backup Disks are not refused. Post-install check adds "`/disks` is still `root:root 755`" | Atlas, agreed by Axle |
| Re-review R3: unmounted ext4 | No `--summarise` mode. An unmounted ext4 disk must be re-plugged before it can be summarised, because a second root code path would add the risk of a stray read-only mount that the Engine doesn't track | Atlas, Axle |
| Re-review R4: store after an erase | The format removes the disk's instance entries (not marked Missing, no ghost rows), with IDs, names and data sizes in the trace. `appDB` is unchanged, and backups on other disks stay. A formatted Backup Disk's ID may be a hardware serial, so every backup setting or link pointing at that ID is cleared, and a later backup never creates a repository there unasked. The summary shows each instance's data size. The Console shows the removed instances with sizes in the result, and the backup view says when erased disks held backups | Axle, Pixel, Kid |
| Re-review R5: processing order | `processDisk` runs Files, then App, Backup, Upgrade (was App, Backup, Upgrade, Files at `Disk.ts:177–201`). The Files recreate skips same-disk instances that `processAppDisk` is about to start. A Files-role error is recorded and doesn't stop App or Backup processing | Axle, Kid |
| Re-review R6: Nextcloud on its own Files Disk | No special case in the hook or wrapper. Add Files triggers the same recreate as docking a Files Disk, with the same no-recreate rule during first start or upgrade. Step 9 checks the files right after Add Files and after an eject and re-dock. Shared space is acceptable, but the low-space warning on a combined disk says the Apps on this disk need space too | Kid (Pixel agreed on the warning) |
| Re-review R7: multi-role UI | One badge per role (app, backup, files) in fixed order in the tree row and the disk header. "Add Files to this disk" on disks with Apps or backups, with a short confirmation that nothing changes. Erasing is a separate second choice, "Erase the disk and start fresh", always with the summary and typed name; a Files Disk offers "Erase and start again" the same way. `canEject` (`NetworkTree.tsx:41`) hides eject only on a pure Backup Disk; the Engine refuses eject while a backup is running | Pixel, approved by Steve |
| Re-review R8: summary details | The walk stops at 100,000 entries or 10 seconds with `partial: true` ("at least" in the Console). Backups come from `BACKUP.yaml` and the store, not `borg list`; if `borg list --short` is ever needed, it has a 20 s timeout and sets `partial`. `formatDisk` requires the summary trace ID, for the same disk ID and serial and less than 10 minutes old. After 10 minutes the Console replaces the typed-name box with "The summary is out of date. Check the disk again." | Axle, Pixel |
| Re-review R9: test disks | Two throwaway disks built as images with the harness and written onto spare sticks on idea03 by Atlas. Disk A (step 8, erase): a small test App (ARM64, health check, port 3000 or higher, a little data in a named volume). Disk B (step 9, Add Files): Nextcloud from `app-nextcloud` with the Files opt-in. Nothing touches idea02 or MilkWise | Kid |
| **Erase is a general disk action (Koen, 2026-09-28 11:08)** — pending re-review | Erase is available on every non-system disk (App, Backup, Files, combined, and non-IDEA sticks such as exFAT, NTFS or no partition table). The result is an **empty IDEA disk**: GPT with one partition, ext4 with only `META.yaml` (same disk ID when one exists, otherwise a new one), filesystem label "IDEA Disk". Roles are a separate step (`createFilesDisk`, `createBackupDisk`, `installApp`). The Files flow keeps an erase-first shortcut (erase + `createFilesDisk` behind one summary and one typed confirmation). `formatDisk` → `eraseDisk`, `idea-format-disk` → `idea-erase-disk`, `formatInProgress` → `eraseInProgress`; staging holds only `META.yaml`, `root_owner=1000:1000` kept. All R1–R8 safety rules stay (system disk and swap refusal, eject first, blockers, `wipefs` trap, serial and size re-check, instance removal, clearing backup links, 10-minute summary). *Was:* "formatting only inside the Files Disk flow, always ending as a Files Disk" (Koen, 2026-09-28 morning; R7 labels "Erase the disk and start fresh" and "Erase and start again") | Koen |
| Late point: backup locks (step 0) | Every backup takes the disk lock and the instance lock together via `acquireAll`, like restore. Console eject and erase checks use the running backup operation's `backupDiskId` (`backupMonitor.ts:108–111`), which also covers scheduled backups | Axle |


### Pending design re-review (Erase as a general action, 2026-09-28 11:08)

Koen's decision is written in above but **not yet reviewed**. Questions for the room:

- **E1 (Axle): command shape of the Files shortcut.** The proposal has the Console send `eraseDisk`, then `createFilesDisk` (two commands, one confirmation) instead of a flag on `eraseDisk`. Between them the disk is a valid empty disk, and the Nextcloud recreate count is unchanged. Is there any atomicity need, for example another command grabbing the disk between the two, that argues for one command?
- **E2 (Axle): lock handover.** Should `eraseDisk` keep the device lock until the disk is docked as `['empty']` and then release it, with `createFilesDisk` taking the normal resource lock? Or should the shortcut hold one lock across both commands?
- **E3 (Axle, Pixel): empty-disk processing.** Koen described the state as `diskTypes []`. Today `processDisk` pushes `'empty'` when no role matches (`Disk.ts:203–206`), the Console's Empty Disk panel keys on it (`App.tsx:56`), and `[]` means "not processed yet or undocked". The proposal keeps `['empty']`, so no Engine change is needed. Agree?
- **E4 (Axle): script rename.** `idea-format-disk` → `idea-erase-disk`, with the same arguments; `<label>` is now always "IDEA Disk". Any reason to keep the old name?
- **E5 (Pixel): where Erase sits.** **Erase this disk** as a quiet secondary action (a text button or an overflow item below the role buttons) on every non-system disk view, including unformatted sticks. Is that the right weight and place? Should the Files shortcut be labelled "Erase first" inside Make this a Files Disk?
- **E6 (Pixel, Axle): Files share name after an erase.** `shareName` defaults to the disk name. After an erase the disk is called "IDEA Disk", so `createFilesDisk` uses "School Files" when the disk still has the neutral name. Keep that rule, or give `createFilesDisk` an optional name?
- **E7 (Pixel, Kid, Axle): disk names after an erase.** Erased disks are named "IDEA Disk", made unique with " (2)", because `installApp` and `createBackupDisk` take a disk **name**. Is that enough, or should those commands move to disk IDs (separate issue)?
- **E8 (Pixel): the Empty disk state.** Reuse today's Empty Disk panel (Make this a Files Disk, Make this a Backup Disk, Install App) for a freshly erased disk, opened automatically after an erase?
- **E9 (Kid): App side.** An erased App Disk becomes an ordinary empty disk and a target for **Install App** or copy/move. Anything App-side that expects an App Disk to keep its ID, or catalogue entries tied to that disk, that the erase should handle? (`appDB` is unchanged.)
- **E10 (Atlas): renamed entry and rollout.** The sudoers entry becomes `/usr/local/sbin/idea-erase-disk` (exact, no argument list). Nothing has been installed yet, so there is no changeover. The step-3 file ships with the new name, and the post-check becomes `sudo -l -U pi /usr/local/sbin/idea-erase-disk`. Anything else in `build-engine` or the pre-deploy diff (`erase-staging/` in the backup list) to adjust?

### Remaining open questions (to settle during implementation, not blocking)

1. **How the Engine recognises Nextcloud's first start or an upgrade** so it can hold back a recreate. For example, wait until the container is healthy and Nextcloud reports installed and not in maintenance mode. Axle and Kid agree the check in step 2.
2. **Exact numbers:** the grouping window for runtime docks ("a few seconds") and the unmount retry count. Engine Dev Bot picks them in steps 0–2 and documents them in `docs/ARCHITECTURE.md`.
3. **The App volume convention** ("named volumes only" versus today's `./data` binds) is a separate issue for Kid. It doesn't block this work.
