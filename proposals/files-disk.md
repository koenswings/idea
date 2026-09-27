# Proposal: Files Disk — a shared file store on a docked disk

**Author:** Steve (Lead Bot)
**Date:** 2026-09-27
**Revised:** 2026-09-27 (Design Review by Atlas, Kid, Axle and Pixel applied); 2026-09-27 (Koen: add ext4 formatting, merged in from idea#125); 2026-09-27 (formatting design review by Atlas, Kid, Axle and Pixel applied)
**Status:** Proposed (design reviewed)
**Refs:** idea#75 (Files Disk), idea#125 (formatting sketch, merged into this proposal). Depends on: idea#121 (new disks never get META.yaml written, bug B1)
**Affects:** `agent-engine-dev` (main work), `agent-console-dev`, `app-nextcloud` (+ `agent-app-dev` conventions and harness), Ops (sudoers rollout, hardware test)
**Background research:** `files-disk-findings.md` (research notes, 2026-09-27)

---

## 1. Summary

A **Files Disk** is an ordinary ext4 USB disk or SSD that an operator turns into a shared file store from the Console. A disk with any other filesystem (a new exFAT stick, for example) can be **formatted as ext4 by the Engine first**, through an explicit Console action with a typed confirmation. When it is docked, the Engine mounts its `files/` folder into every App on that Engine that says it can use one. Nextcloud comes first. Teachers and students then reach the files through Nextcloud in the browser, over the school's local Wi-Fi.

There are two ways to create one:

- **An empty ext4 disk:** `createFilesDisk` writes two small files (`META.yaml` and `FILES.yaml`) and an empty `files/` folder, the same way a Backup Disk is created today. Nothing is erased.
- **A disk without an ext4 filesystem** (a new exFAT stick, or one with no partition table): it shows up under its Engine as a **format candidate**. `formatDisk` erases it and creates one ext4 partition that already contains those files, so it comes up as a Files Disk straight away (§7.4).

The Engine never formats anything on its own. There are two new root permissions: changing the owner of the **disk root folder only** (`chown`), and running **one root-owned format script** that re-checks the device itself (§10).

Koen approved the design decisions in §5 (2026-09-27) and later that day reversed decision 2 to add formatting (idea#125). The Design Review (§14) filled in the implementation details of the first version. The formatting part (§7.4) was design-reviewed the same evening (§14).

## 2. Why

- The Console already has a "Files Disk" option for empty disks. The Engine has no `createFilesDisk` command, so clicking it does nothing, and the Console still says "Command sent. The Engine is configuring the disk." The disk stays empty and no error appears anywhere.
- The original design (`agent-engine-dev/proposals/solution-description.md`, lines 81, 89, 138, 210–216, 682) promises Files Disks: "Contains a File System that is automatically network mounted when docked" and "auto-mounted into Apps that have been created with the ability to work with Files Disks … Examples: A file store into Nextcloud".
- New USB sticks and SSDs almost always come as exFAT or FAT32. Without formatting in the Engine, every Files Disk would have to be prepared on a Linux machine first, which is hard to ask of a school (idea#125).
- Schools need somewhere to keep and share documents (worksheets, photos, student work) that doesn't depend on a single App's internal storage. It should be possible to move that store to another Pi by moving the disk.

## 3. What a Files Disk is

- **A disk with a role.** Like App Disks and Backup Disks, a Files Disk is recognised by what is on it, here a `FILES.yaml` file in the disk root. The Engine checks for it every time the disk is docked.
- **A folder of files, not an App.** The shared content lives in `files/`. The Engine doesn't serve it itself. Apps that opt in get the folder mounted inside their container.
- **Local to one Pi.** Only the Engine it is docked to uses it. To use the files on another Pi, you move the disk.
- **Stable identity.** Every Files Disk has a permanent ID in `META.yaml`, so a later Backup Disk feature can refer to it.
- **Plain files.** Everything in `files/` is ordinary files and folders. They are owned by uid 33 (Nextcloud's `www-data`), but any Linux machine can read them without Nextcloud. **Note for Koen:** on a laptop, that means a `sudo` copy or a chown to read-write them; reading is enough for a rescue copy.

## 4. User flow in the Console

1. The operator docks a disk that isn't an IDEA disk yet. If it is ext4, it appears in the network tree with the **empty** badge. (If it isn't ext4, it appears as an unformatted disk; see *Formatting* below.)
2. They select it and choose **Files Disk**. The form explains: *"This disk becomes a shared file store. Apps that support Files Disks (such as Nextcloud) on this Engine will show its files. Nothing on the disk is erased."*
3. They click **Create Files Disk**. The Console waits for the Engine's answer (§8):
   - **Success:** the disk's badge changes to **files** and the right pane shows the Files Disk view.
   - **Failure:** the Engine's message appears in the Empty Disk panel, for example "School Files is not empty."
   - **No answer after 15 seconds:** "The Engine didn't respond. It may not support Files Disks yet."
4. **Files Disk view:** name, size and free space, plus one of three lines:
   - "Available in: Nextcloud (nextcloud-01)"
   - "Nextcloud supports Files Disks but isn't running"
   - "No App on this Engine uses Files Disks yet"
   If the disk can't be used (password-protected, or an earlier unmount got stuck), the view shows **Not mounted** with the reason. There is an **Eject** button.
5. In Nextcloud, users see a folder named after the disk (for example **School Files**) and can open, upload and share files according to their Nextcloud accounts.
**Formatting (a disk without an ext4 filesystem, for example a new exFAT stick):**

- The disk is **not mounted**. It appears under its Engine's row as an **unformatted disk**, labelled for example **"Intenso 32 GB"**, with the action **Format as School Files**.
- The dialog shows the Engine, model, size, current filesystem (for example "exfat") and an erase warning: *"Everything on this disk will be erased."* When the Engine can't read the disk, it says **"contents unknown"**. When files are visible, it warns that they will be erased.
- The operator types the label exactly ("Intenso 32 GB") to confirm. The button stays disabled until it matches.
- The Console shows progress: *checking → partitioning → creating filesystem → mounting*. After 5 minutes it says "This is taking longer than expected. Don't unplug the disk." and keeps watching. There is no cancel.
- On success, the unformatted disk disappears and a Files Disk with the same ID appears; the Console opens it. If the disk is unplugged while the dialog is open, the dialog closes and says the disk was removed.
- ext4 disks (App, Backup, Files, system disks, and ext4 disks holding other files) are never offered for formatting. The Engine and the script refuse IDEA data and the Pi's own disks.

6. **Eject** (or pulling the disk): Nextcloud restarts briefly and the folder disappears. Re-docking brings it back. If the Pi can't unmount the disk cleanly, that Engine's row shows a warning such as "School Files couldn't be unmounted cleanly. Restart this Pi." This works for every disk type, not only Files Disks.

## 5. Design decisions (approved by Koen, 2026-09-27; decisions 2 and 3 changed by Koen on 2026-09-27)

| # | Decision | Reason |
|---|---|---|
| 1 | **Purpose:** a shared teacher/student file store reached **through Apps over HTTP**, Nextcloud first. **No host-level SMB/NFS** in v1. | Clients are browsers on the school Wi-Fi, and Nextcloud is already IDEA's file-sharing App. SMB/NFS would add packages, root configuration and user accounts to an unattended Pi. |
| 2 | **Changed 2026-09-27 (Koen, idea#125):** the Engine **can format a disk as ext4, only through an explicit Console action** (typed name confirmation; never automatically on dock). Without formatting, `createFilesDisk` still writes `META.yaml`, `FILES.yaml` and `files/` onto an existing ext4 filesystem without erasing anything. *(Was: "Don't format.")* | New drives come as exFAT/FAT, and schools can't prepare disks on a Linux machine. Safety comes from the explicit action, the typed confirmation, the Engine's refusals, and a root script that re-checks the device itself (§7.4). |
| 3 | **Changed 2026-09-27 (Koen):** disks that are **already empty ext4** work straight away (`createFilesDisk`). **Any disk without an ext4 filesystem** (FAT, exFAT, NTFS, no partition table) is offered as a **format candidate** and can be **formatted first** (`formatDisk`). An ext4 disk that holds other files is not offered in v1 (§14, open question 4). Disks with IDEA data are always refused. **No combined disks.** *(Was: "Only empty ext4 disks; reject FAT, exFAT and NTFS.")* | Files Disks are still always ext4, because the ownership model and container binds rely on ext4 permissions. One role per disk keeps behaviour easy to predict. |
| 4 | **Apps opt in** through compose metadata (`x-app.filesMount`). **Every** Files Disk on an Engine is mounted into **every** opted-in App on that Engine. Choosing Apps per disk comes later. | Creation stays one click and there are no per-disk links to manage. |
| 5 | **No password in v1.** Nextcloud accounts give access control. A `password` field is reserved in `FILES.yaml`. | Reserving the field avoids a format change later. |
| 6 | **Served only by the Engine it is docked to.** No mounts across Pis. | Network mounts between Pis create fragile dependencies. |
| 7 | **On undock or eject**, restart the affected Apps **without** the mount, then unmount. **Remount on dock.** | A disk can't be unmounted while a container holds it. A dangling mount could make an App write to the Pi's own SD card or SSD. |
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

- **idea#121:** write `META.yaml` for new disks. For a non-system disk whose root isn't writable by `pi`, first run the new sudoers entry `chown pi:pi /disks/<dev>` (§10).
- **Never delete a mounted path.** `undockDisk` (`usbDeviceMonitor.ts:305`) must never `rm -fr` a mount point that is still mounted. Unmount with a plain `umount` and a few retries. If it's still busy, record an error trace, update the store anyway (disk undocked), set **`Disk.unmountError`** (`{ engineId, mountPoint, fsUuid, message }`, for example `mountPoint: /disks/sdb1`). **`fsUuid`** is the filesystem UUID that the Engine records **at mount time** with `lsblk -no UUID /dev/<dev>` and copies into the error and leave the mount point alone. This applies to **every disk type, App Disks included**. `unmountError` survives the undock (when `dockedTo` becomes `null`). It is cleared on the next successful mount of that disk, **or at Engine startup** (next bullet).
- **Clear stale unmount errors at startup.** When the Engine cleans up its old mount points in `/disks` at startup (`usbDeviceMonitor.ts:269–291`), it also clears every `Disk.unmountError` whose `engineId` is its own, when `findmnt -no UUID <unmountError.mountPoint>` shows **nothing mounted** there, **or a different UUID** than `unmountError.fsUuid`. Only the same filesystem still mounted there keeps the error. Device names get reused, so after a restart a different disk can be mounted at the same `/disks/sdX`; only the same filesystem still being there keeps the error. `Disk.id` can't be used for this comparison because it is **not** the filesystem UUID. `readHardwareId` (`src/data/Meta.ts:145`) uses a hardware serial for two USB stick models (Samsung FIT, INTENSO), and every other disk gets a random `uuid()` stored only in `META.yaml`. Neither `lsblk` nor `findmnt` needs sudo, so this adds **no new sudoers entry**. Without this, the "Restart this Pi" warning would stay after the restart itself if the disk isn't docked again.
- **Check before mounting.** Before mounting a newly docked disk, the Engine checks with `findmnt` that nothing is still mounted at `/disks/<dev>`. If something is, it refuses with an error trace instead of mounting on top.

### 7.1 `createFilesDisk <diskId>` command

Add an entry in `src/data/Commands.ts`: scope `engine`, one argument named `diskId`. The **Console sends the disk ID** (changed from the name). The trace records `args.diskId`, and error messages show the disk's **name**. The handler checks the following in order and **throws** on the first failure, so the trace closes as an error:

1. **Found here:** the disk exists, is **docked to this Engine** (`dockedTo === localEngineId`) and has a device.
2. **Not the system disk.**
3. **Empty:** `diskTypes` is exactly `['empty']`, no instance is stored on it, and the root has nothing except `META.yaml` and `lost+found`.
4. **ext4:** `findmnt -no FSTYPE /disks/<dev>` returns `ext4`.
5. **Owner:** if `pi` can't write the disk root, run `sudo chown pi:pi /disks/<dev>` (root folder only, not recursive). If the Pi doesn't have the new sudoers entry yet, this fails with a clear error ("this Engine is missing a permission update; ask Ops to install the new 10-engine sudoers file"), and **nothing has been written to the disk yet**, so it is never half-created.
6. **Writable:** `pi` can now write the disk root.
7. **Not busy:** no resource lock on the disk.

It then writes `META.yaml` if missing, writes `FILES.yaml`, creates `files/`, and runs `processDisk` again. Document it in `docs/COMMANDS.md`.

### 7.2 Detection and disk details (`src/data/Disk.ts`)

- `isFilesDisk(disk)`: `FILES.yaml` exists in the disk root. This replaces the stub at `Disk.ts:435–439`.
- `processDisk` branch (`Disk.ts:197–201`): add `'files'` and call `processFilesDisk`. Replace the TODO that links to #46 with #75.
- `processFilesDisk`: read `FILES.yaml` and set `disk.filesConfig`. If `password` isn't null, set `passwordProtected: true`, set `filesConfig.error` ("password-protected Files Disks are not supported yet") and don't mount. Otherwise schedule a remount of opted-in instances (7.3).
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

### 7.4 Formatting a disk as ext4 (`formatDisk`)

This part came in on 2026-09-27 (idea#125, merged into this proposal) and was design-reviewed the same evening by Atlas, Kid, Axle and Pixel (§14).

**Safety model**

| | Rule |
|---|---|
| (a) **Explicit only** | Formatting happens only through the Console action **Format as School Files** on a *format candidate*, confirmed by typing the candidate's label exactly. The Engine never formats automatically when a disk is plugged in. |
| (b) **Refusals** | Refused: the Pi's own **boot or root disk** (found by lookup, never by name, connection type or model); a disk with **any mounted partition** or one **in use as swap**; a disk with **IDEA data**. The **script is the authoritative check**. The Engine's own checks only decide what the Console may offer. |
| (c) **Informed confirmation** | The dialog shows the Engine, model, size, current filesystem and an erase warning. It says "contents unknown" when the Engine can't read the disk, and shows a files warning when files are visible. Existing files don't block formatting; the typed label is the safeguard. IDEA data is always refused. |
| (d) **One root script** | Root access goes through **one small script**, `/usr/local/sbin/idea-format-disk` (source `script/build_image_assets/idea-format-disk`), allowed by **one sudoers entry for that script only, with no argument list**. There is no general `mkfs`, `sfdisk` or `wipefs` rule. The script is an installed root-owned **copy** that `pi` can't write, and it **re-validates the device itself**. |
| (e) **Comes up as a Files Disk** | The new filesystem already contains `META.yaml` (with the candidate's ID), `FILES.yaml` and `files/` from the moment it is created, so the normal mount path picks it up as a Files Disk with the same ID. |
| (f) **Progress and failure** | `formatProgress` on the candidate and the `formatDisk` command trace. The Console uses a 15-second "no response" check and a 5-minute "taking longer" message, measured on its own clock. |

**Behaviour change: ext4-only mounting.** Today the Engine runs `sudo mount` without `-t`, so exFAT and FAT sticks get mounted, and idea#121 could then write `META.yaml` onto them. From step 3 on:

- The Engine mounts **only with `-t ext4`**. Anything else stays unmounted and never gets `META.yaml`.
- Non-ext4 sticks that used to mount (and showed as "empty") will no longer do so. This fits the IDEA disk format: every IDEA disk is ext4.
- The sudoers mount entry changes to match (§10).

**Format candidates: how new sticks reach the Console.** Today a new stick often never reaches the Console at all:

- The udev rule `90-docking.rules` only links `sd?`, `sd?1` and `sd?2`.
- `validDevice` skips whole disks (`usbDeviceMonitor.ts:95–100`).
- A stick without a partition table, or with an unsupported filesystem, doesn't show up.

In step 3:

- `90-docking.rules` is updated so the Engine sees every whole USB disk, not only through its first two partitions. The exact rule goes in the step 3 PR.
- **Which disks are candidates:** a **whole, non-system disk** with **no ext4 filesystem** on it (by `lsblk` FSTYPE), no mounted partition and no swap. It is published as a **format candidate** on its Engine, read with `lsblk -J -b -o NAME,TYPE,FSTYPE,SIZE,MODEL,SERIAL` (no sudo). A disk with an ext4 filesystem is never a candidate, even when it is unmounted (for example an ejected App Disk).
- **`Engine.formatCandidates`**, an array of `{ candidateId, device, sizeBytes, model, fsType, label, hasFiles, formatProgress }`:
    - `candidateId` comes from the disk's serial (`readHardwareId` for the two known models, otherwise `lsblk` SERIAL). If there is no serial, the Engine generates an ID that stays the same for as long as the disk stays plugged in. The Engine writes this **same ID** into the new `META.yaml` (`isHardwareId: true` only when it came from `readHardwareId`), so the Files Disk keeps the candidate's ID.
    - `label` is what the operator types to confirm, for example **"Intenso 32 GB"** (model plus rounded size, or "USB disk" when there is no model). The Engine keeps labels unique on that Engine by adding " (2)", " (3)" and so on when two candidates would look the same.
    - `hasFiles` is `true`, `false` or `null` (unknown). In v1 the Engine never mounts a candidate, so it is `null` and the dialog says "contents unknown".
    - `formatProgress` is `{ step }` or `null`, where `step` is `checking`, `partitioning`, `creating filesystem` or `mounting`.
- Candidates are added and removed as disks come and go, and rebuilt at Engine startup.

**System-disk helper.** One shared Engine helper finds the system disks by lookup: `findmnt -no SOURCE /` and `findmnt -no SOURCE /boot/firmware`, each mapped to its parent disk with `lsblk -no PKNAME`.

- It replaces the guess in `usbDeviceMonitor.ts:57–75` ("root's parent + 1", `sdX` only).
- It never uses names, connection type or model. On the IDEA Pis the system disk is itself a USB SSD at `/dev/sda` (`/` on `sda2`, `/boot/firmware` on `sda1`, `TRAN=usb`), and on idea02 it is an Intenso, a model `readHardwareId` treats specially.
- The helper also flags disks with a mounted partition or in use as swap. The script repeats all of this itself.

**Command:** `formatDisk <candidateId> <confirmName…>` (scope `engine`). `confirmName` is the last argument and **variadic** (like `createBackupDisk`'s instance list), so a label with spaces arrives as several tokens that the Engine joins with single spaces. It must **exactly match** the candidate's `label`. The trace records `args.candidateId`. The handler throws on the first failure so the trace closes as `error`, and messages show the label.

**Engine steps**

1. **Checks:**
    - the candidate exists on this Engine;
    - `confirmName` equals its `label`;
    - the helper says it is not a system disk and has no mounted partition or swap;
    - **no other format is running on this Engine**. A second concurrent `formatDisk` gets a refusal trace, which the Console shows as an error.
2. **Lock:** lock the device for the whole format. `addDevice` skips locked devices, so **nothing auto-mounts during a format**.
3. **Staging (as `pi`):** write `~/.local/state/idea-engine/format-staging/<candidateId>/` with `META.yaml` (`diskId = candidateId`, `diskName` "School Files"), `FILES.yaml` and an empty `files/`. It is built as `pi` because `mkfs.ext4 -d` copies the owners, while `root_owner` only sets the top folder.
4. **Format:** `sudo /usr/local/sbin/idea-format-disk /dev/sdX <serial|-> <sizeBytes> "School Files" <stagingDir>`. The script prints step markers, which the Engine copies into `formatProgress`.
5. **Mount:** the script ends with `udevadm settle`. The Engine then calls `addDevice` for the new partition itself (still holding the lock, so no udev-triggered duplicate), mounts it with `-t ext4`, finds `META.yaml` with the candidate's ID, and `processDisk` sees `FILES.yaml`. The disk becomes a Files Disk and the Apps get their mount (7.3).
6. **Finish:** remove the candidate from the list, unlock, delete the staging folder. The trace closes `ok` once the disk's `diskTypes` includes `'files'`, otherwise `error`.

**The script `idea-format-disk <device> <serial|-> <sizeBytes> <label> <stagingDir>`** (runs as root; `set -eu`; calls every tool **by full path**, for example `/usr/bin/lsblk`, `/usr/bin/findmnt`, `/usr/sbin/wipefs`, `/usr/sbin/sfdisk`, `/usr/sbin/mkfs.ext4`, `/usr/bin/udevadm`, `/usr/bin/mount`, `/usr/bin/umount`):

- **Arguments:**
    - `device` matches `^/dev/sd[a-z]$` (whole disk only);
    - `serial` is `-` or a short safe string;
    - `sizeBytes` is digits;
    - `label` matches `^[A-Za-z0-9 _-]{1,16}$`;
    - `stagingDir` is exactly `/home/pi/.local/state/idea-engine/format-staging/<id>`, a real directory owned by `pi`. A symlink anywhere in the path is refused.
- **Re-verifies the device (authoritative):**
    - `lsblk` says `TYPE=disk`, and its **serial and size match** the arguments (not the name alone);
    - it is **not** a system disk (same `findmnt` + `lsblk -no PKNAME` lookup as the Engine helper);
    - **no partition is mounted** and none is **in use as swap**.
- **Role-marker check:** for any ext4 filesystem on the disk, mount it read-only (`-o ro,noexec,nosuid,nodev`) on a temporary folder and look for `apps/`, `instances/`, `BACKUP.yaml` or `FILES.yaml` (`META.yaml` alone doesn't count, because idea#121 writes it onto every disk). Unmount, then refuse if any is found.
- **Then:**
    1. `wipefs -a` on the device;
    2. a **GPT** table with **one partition** (`sfdisk`). A filesystem on the whole disk wouldn't match the udev rule and the device conventions;
    3. `udevadm settle`;
    4. `mkfs.ext4 -F -L <label> -E root_owner=1000:1000 -d <stagingDir> /dev/sdX1` (e2fsprogs 1.47.2 on both Pis supports `-d`);
    5. `udevadm settle`.
- **Messages:** clear exit messages, for example "refused: /dev/sda holds the root filesystem". The Engine passes them into the trace unchanged.

**Failure:** if the script refuses or fails before partitioning, the disk is untouched and stays a candidate. If it fails later, the disk stays a candidate (it has no ext4 filesystem yet), so the operator can simply format again. The trace carries the script's message. The Engine never kills the script halfway, because an interrupted `mkfs` is worse than a slow one.

**Why a 5-minute "taking longer" message:** `mkfs.ext4` with its default lazy initialisation takes seconds even on large disks, but slow USB 2.0 sticks, large spinning disks, `udevadm settle` and the mount can add a minute or two. Five minutes leaves a wide margin without hiding a hung format for long.

### 7.5 Store schema

| Where | Field | Notes |
|---|---|---|
| `Disk` | `filesConfig: { shareName: string; readOnly: boolean; passwordProtected: boolean; error: string }` or `null` | `error` is a string or `null` and is **only** used for a password-protected disk. Set by `processFilesDisk`. Reset to `null` in `createOrUpdateDisk` and `undockDisk`, like `backupConfig`. The password never goes into the store. |
| `Disk` | `unmountError: { engineId: EngineID; mountPoint: string; fsUuid: string; message: string }` or `null` | **All disk types.** Set when an unmount is still busy after the retries. `mountPoint` is where the disk was mounted (for example `/disks/sdb1`); it's needed because `device` is `null` after undock. `fsUuid` is the filesystem UUID recorded at mount time (`lsblk -no UUID /dev/<dev>`), so the startup check can tell this disk apart from a different disk later mounted at the same path. Kept after undock (`dockedTo` becomes `null`), so `engineId` says which Pi has the stuck mount. Cleared on the next successful mount of that disk, or at Engine startup unless `mountPoint` is still mounted with the same `fsUuid` (7.0). Added in step 0. |
| `Disk` | `sizeBytes: number` or `null`, `freeBytes: number` or `null` | All docked disks. `fs.statfs` on dock and every 10 minutes, rounded, written only on a change of more than 1% or 100 MB. Cleared on undock. |
| `Engine` | `formatCandidates: { candidateId: string; device: string; sizeBytes: number; model: string or null; fsType: string or null; label: string; hasFiles: boolean or null; formatProgress: { step: 'checking' or 'partitioning' or 'creating filesystem' or 'mounting' } or null }[]` | Whole non-system disks without an ext4 filesystem, on this Engine (§7.4). Updated as disks come and go, rebuilt at startup. Labels are unique per Engine. |
| `App` | `filesMount: { path: string; services: string[] }` or `null` | From `x-app.filesMount` |
| `Instance` | `filesMounts: DiskID[]` | Written only after a successful `compose up` |
| `DiskType` | `'files'` | Already exists in `CommonTypes.ts:39` |

`diskDB`, `appDB` and `instanceDB` are maps, so `store-template.json` stays untouched.

## 8. Console changes (agent-console-dev)

- **Empty Disk panel** (`EmptyDiskPanel.tsx:277–289`): replace "The Engine will format this disk…" with the wording in §4, rename the button to "Create Files Disk", and send `createFilesDisk <diskId>`.
- **One reusable helper to wait for a command's result:**
    1. Before sending, record the IDs of the traces that already exist.
    2. The result is the first **new** `createFilesDisk` trace whose `args.diskId` matches. It doesn't use timestamps, because a school Pi may have no NTP.
    3. **Error:** show the trace's `errorMessage` in the Empty Disk panel.
    4. **Success:** the trace is `ok` **and** the disk's `diskTypes` includes `'files'`.
    5. **Timeout (15 s):** "The Engine didn't respond. It may not support Files Disks yet."
    Backup Disk and Install App can reuse it later.
- **Files Disk view:** add a `'files'` case to `rightPanelFor` (`App.tsx:46–58`) and a panel showing name, size and free space, and the three "available in" states:
    - **mounted:** instances whose `filesMounts` contains the disk;
    - **opted in but not running:** Apps with `filesMount` whose instances on this Engine aren't running;
    - **none.**
    It also has a **Not mounted** state: for the password case (`passwordProtected` / `filesConfig.error`) and for a busy unmount (`unmountError`). All of this uses derived signals only, with no extra state. **Eject** reuses the existing `ejectDisk` command.
- **Format candidates (§7.4):**
    - Show `Engine.formatCandidates` under the Engine's row as **unformatted disks**, keyed by `candidateId`, each with a **Format as School Files** action.
    - **Dialog:** Engine, model, size, current filesystem, erase warning; "contents unknown" when `hasFiles` is `null`, and a files warning when it is `true`. The confirm field must **exactly** match the candidate's `label`. It sends `formatDisk <candidateId> <label>`.
    - **Progress** comes from `formatProgress.step` (checking, partitioning, creating filesystem, mounting).
    - **The result** is the first new `formatDisk` trace with that `args.candidateId`, found with the same trace-ID helper.
    - **Timing, on the Console's own clock:** 15 s with no progress and no trace → "The Engine didn't respond." After 5 minutes → "This is taking longer than expected. Don't unplug the disk." It keeps watching, and there is no cancel.
    - **Success:** the candidate leaves the list and a Files Disk with the same ID appears; the Console opens it. **Error:** show the trace's message (this includes a refused second concurrent format). **Candidate disappears** while the dialog is open → close the dialog and say the disk was removed.
- **Unmount warning (all disk types):** when a disk has `unmountError`, show a warning on **that Engine's row** in the network tree (found by `unmountError.engineId`, because an undocked disk has `dockedTo: null` and would otherwise appear nowhere). Example: "School Files couldn't be unmounted cleanly. Restart this Pi." While the disk is docked, show the same warning on the disk's own view.
- **Types and commands:** new commands `createFilesDisk <diskId>` and `formatDisk <candidateId> <confirmName…>` (confirmName = the candidate's `label`). Add `filesConfig`, `unmountError` (`{ engineId; mountPoint; fsUuid; message }`), `sizeBytes`/`freeBytes`, `Engine.formatCandidates` (`{ candidateId; device; sizeBytes; model; fsType; label; hasFiles; formatProgress }[]`), `App.filesMount`, `Instance.filesMounts` and the missing `'system'` DiskType to `src/types/store.ts`. Update `docs/ARCHITECTURE.md`.
- **Mock store fixtures and tests:** a Files Disk in each state, format candidates (including two with the same model and size, labelled " (2)"), the panel routing, the helper (error, success, timeout), and the format dialog (exact label match, contents unknown, progress steps, 5-minute message, candidate removed mid-dialog, refused second format).

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
- **Formatted disks need no App changes (Kid):** a disk made by `formatDisk` has `files/` owned by uid 1000, and the entrypoint wrapper changes it to uid 33 as for any other Files Disk.
- **Testing:** Kid tests the hook offline against a fake `occ` first, then with the harness (a Files Disk fixture next to a Nextcloud instance).

## 10. Ops and permissions

**Sudoers: one new entry** in `script/build_image_assets/10-engine.sudoers`:

```
/usr/bin/chown pi\:pi /disks/sd[a-z][12]
```

- It applies to the **disk root folder only**. It is not recursive and it doesn't cover subfolders.
- `createFilesDisk` uses it after the empty and ext4 checks and before the writable check. idea#121 uses it only on non-system disks whose root isn't writable.
- No `umount -l`, no recursive chown.
- The PR must add the code-mapping comment in the file header (like the existing `ENGINE_*` aliases) and pass `visudo -cf`.

**Rollout to existing Pis (Atlas):**

- The Engine PR that adds the entry ships the updated `10-engine.sudoers` as a **file that can be installed on its own**. Its description names the **first Engine commit that needs it**.
- Before deploying that commit, Atlas installs the file on each Pi: `visudo -cf` on the new file, then an **atomic move** into `/etc/sudoers.d/10-engine`. idea03 first, then idea02.
- Without the entry, `createFilesDisk` fails with a clear error and never half-creates a disk (§7.1). Everything else keeps working.

**Sudoers changes for formatting (step 3)** in `10-engine.sudoers`:

```
/usr/local/sbin/idea-format-disk
/usr/bin/mount -t ext4 /dev/sd[a-z][12] /disks/sd[a-z][12]    (replaces the mount entry without -t)
```

- **The script entry has no argument list** (not `""`, which would allow only a call with no arguments). The script validates all its arguments itself. There is no general `mkfs`, `sfdisk` or `wipefs` rule.
- The entry points at the installed copy in `/usr/local/sbin`, **never into the git checkout**.
- The mount entry changes because the Engine now mounts only with `-t ext4` (§7.4).
- The code-mapping comment and `visudo -cf` rules apply as before.

**The script is installed as a copy (Atlas):**

- Source: `script/build_image_assets/idea-format-disk` in the Engine repo.
- `build-engine` installs a **copy** with `install -o root -g root -m 0755` into `/usr/local/sbin` (root-owned, not writable by `pi`), **never a symlink**. If `pi` could change it, the sudoers entry would amount to full root.
- It lives on the Pi's root filesystem and `build-engine` puts it back on every install, so it **survives a reboot and a reinstall**.
- Atlas's pre-deploy diff **reinstalls it whenever it differs** from the installed copy, before the Engine commit that needs it.
- No new packages: e2fsprogs 1.47.2 (with `mkfs.ext4 -d`), `sfdisk` and `wipefs` are already on both Pis.

**Rollout per Pi, idea03 first, then idea02:**

1. Install the script (copy).
2. Install the sudoers file (`visudo -cf` + atomic move).
3. **Post-checks:** `sudo -l -U pi /usr/local/sbin/idea-format-disk` must match **through `10-engine`**, and `visudo -cf` passes.
4. Deploy the Engine commit.

**Rollback** runs in reverse order. **Format tests run on idea03 only.**

- **The blanket rule is still there.** `pi ALL=(ALL) NOPASSWD: ALL` (`010_pi-nopasswd`) is still installed, so a hardware test alone can't prove the narrow entry works; the `sudo -l` post-check is what proves it. Removing the blanket rule stays a separate decision.
- **Without the new entries** (or before step 3 ships), `formatDisk` fails with a clear error before touching the disk.

**Engine state folder:** `~/.local/state/idea-engine/` (compose overrides and `format-staging/` folders) is added to **Atlas's pre-deploy backup list**. It can always be rebuilt from the store, but backing it up makes a rollback easier to inspect.

**No new packages.** `sfdisk`, `wipefs`, `lsblk` (util-linux) and `mkfs.ext4` (e2fsprogs 1.47.2) are already on both Pis. No Samba or NFS.

## 11. Tests

**Engine (`test/automated/`):**

- **Step 0:** a new disk gets `META.yaml` and keeps its ID on re-dock. The root-owned disk path calls chown. Undock never removes a still-mounted path; a busy unmount gives an error trace, the store is still updated, and `unmountError` is set with the Engine ID, the mount point and the `fsUuid` recorded at mount time. It survives undock and is cleared on the next successful mount (tested for an App Disk as well as a Files Disk). **Startup cleanup:** an `unmountError` with this Engine's `engineId` whose `mountPoint` is no longer mounted (mocked `findmnt`) is cleared at startup. **A different disk mounted at the same `mountPoint`** (`findmnt -no UUID` returns another UUID than `fsUuid`) → the error is cleared. The same filesystem still mounted there (same `fsUuid`) → the error is kept. The `fsUuid` recorded at mount time (mocked `lsblk -no UUID`) ends up in the error, and one with another Engine's `engineId` is never touched. Mounting refuses when `findmnt` shows something already mounted.
- **Command:** `createFilesDisk` success; errors for unknown ID, disk docked elsewhere, system disk, non-empty disk, disk with instances, non-ext4, unwritable after chown, and locked disk. Each error closes the trace as `error`, and the trace carries `args.diskId`.
- **Detection:** `processDisk` sets `['files']`, `filesConfig`, size and free space. A non-null `password` → not mounted.
- **Override:** long bind syntax, `create_host_path: false`, only the listed services, slug sanitising, always-suffixed paths, display-name JSON, rebuilt every time.
- **Status handling:** Running recreated, Stopped untouched, Paused `--no-start --force-recreate`. `filesMounts` only written after success. Boot order (Files Disks before instances) and grouping of runtime docks.
- **Formatting (step 3 PR):**
    - Candidate detection from mocked `lsblk -J` output: whole non-system disks without ext4 become candidates; ext4 disks (also when unmounted), system disks (found via mocked `findmnt`/`PKNAME`, including a USB system disk and an Intenso model), disks with a mounted partition and swap disks don't. IDs come from the serial or a generated ID that stays stable while plugged in. Labels get " (2)" on a clash.
    - ext4-only mounting: a FAT or exFAT partition is not mounted and gets no `META.yaml`.
    - `formatDisk` refusals: unknown candidate, label mismatch, system disk, a second concurrent format. The success path with a fake script: device locked for the whole format, `addDevice` skips the locked device, staging built as `pi` with `diskId = candidateId`, `formatProgress` steps, the Engine calls `addDevice` itself, and the result is a Files Disk with the same ID. A script failure gives an error trace with its message.
    - **An unmounted App Disk (Kid):** a mocked **unmounted** disk with `apps/` or `instances/` is not a candidate, and the script refuses it through its read-only role-marker check.
- **Script tests** (shell, with fake `lsblk`, `findmnt`, `mount`, `wipefs`, `sfdisk`, `mkfs.ext4`, `udevadm`): refuses a partition path, a serial or size mismatch, a system disk, a mounted partition, swap, role markers on an ext4 filesystem (mounted `ro,noexec,nosuid,nodev` and unmounted again), a bad label, and a bad or symlinked staging path. It calls tools by full path and runs the steps in order with the right flags.
- **Fixture:** `test/fixtures/disk-files/` plus an opted-in sample App.

**Console:** the helper (error, success, timeout; matching by new trace ID and `args.diskId`), panel routing, the three "available in" states, Not mounted, and the format dialog.

**App:** the hook against a fake `occ` (create, keep admin storages, delete only its own, idempotent), the wrapper (chown only when wrong), then the harness.

**Hardware (idea03, isolated with `mdns: false`, a person at the Pi, like idea#110).** Test setup:

- a **partitioned** ext4 disk made with default `mkfs.ext4`, so the root-owned case is tested (unpartitioned disks aren't mounted);
- a FAT stick;
- an **exFAT stick with some files on it** (the format test);
- a **throwaway App Disk** that Kid builds with the harness on a spare stick (the refusal test). Refusal tests **never** target MilkWise's disk or idea02;
- Nextcloud installed from an App Disk.

Eight steps:

1. Dock the FAT stick → clear rejection when trying to create a Files Disk.
2. Dock the root-owned ext4 disk → create the Files Disk → **files** badge, root now `pi:pi`.
3. Nextcloud shows the folder → upload a file.
4. Eject → Nextcloud recreated, folder gone, clean unmount.
5. Reboot with both disks docked → Nextcloud starts once with the folder, file still there.
6. Pull the Files Disk without Eject → Nextcloud recreated without it, unmount clean or a recorded error, nothing deleted.
7. **Format the exFAT stick (idea03 only):** before formatting, the stick is not mounted and has no `META.yaml`. It appears under idea03 as an unformatted disk (for example "SanDisk 32 GB"). The dialog shows the Engine, model, size, `exfat` and "contents unknown". A wrong label keeps the button disabled. With the right label, the progress steps run, the candidate disappears and a Files Disk with the **same ID** appears on a GPT partition. The Console opens it and Nextcloud shows it.
8. **Refusal on an unmounted App Disk (idea03 only):** eject Kid's throwaway App Disk so it stays plugged in but unmounted. It is not offered as a candidate. Run the script directly (`sudo /usr/local/sbin/idea-format-disk …` with its real serial and size) → refused on the role-marker check. `formatDisk` with a made-up candidate ID → refused. Re-dock the App Disk: unchanged, and its instance starts.

**After every step:** the Pi's own boot and root disk untouched, nothing new under `/disks` on the SD card, no leftover mounts, 0 Engine restarts. **Then idea02** (golden), with MilkWise up the whole time.

## 12. Rollout: implementation issues per domain

| Step | Domain | Issue | Depends on |
|---|---|---|---|
| 0 | Engine + Ops | **idea#121** (write `META.yaml`) + **Q5 safety fix** (never `rm -fr` a mounted path; retry umount; `Disk.unmountError` (`engineId`, `mountPoint`, `fsUuid`, `message`) for every disk type, cleared at startup unless the same filesystem (`fsUuid`) is still mounted at `mountPoint`; `findmnt` check before mount) + **sudoers `chown` entry** (code-mapping comment, `visudo -cf`, shipped as a standalone file; PR names the first Engine commit that needs it; Atlas installs it with `visudo -cf` + atomic move on idea03, then idea02, before deploying) | — |
| 1 | Engine | Files Disk type: `FILES.yaml` detection, `createFilesDisk <diskId>` with checks, `filesConfig`, `sizeBytes`/`freeBytes`, tests, `COMMANDS.md` | 0 |
| 1b | Console | *(in parallel with 1, on the mock store)* Wording, result helper, Files Disk view, types, fixtures | — (merge after 1) |
| 2 | Engine | Mounting: per-service `x-app.filesMount`, override helper (`COMPOSE_FILE`), status handling, locks, boot order, grouping of runtime docks, undock/eject path, `Instance.filesMounts`, tests | 1 |
| 3 | Engine + Ops | **Formatting:** udev rule sees whole disks; mount only with `-t ext4` (behaviour change, new sudoers mount entry); system-disk helper (`findmnt` + `lsblk -no PKNAME`) replacing the guess in `usbDeviceMonitor.ts:57–75`; `Engine.formatCandidates` from `lsblk -J`; device lock (`addDevice` skips locked devices); `idea-format-disk` script (copy installed by `build-engine`, full tool paths, serial and size re-check, read-only role-marker check); sudoers entry without an argument list; `formatDisk <candidateId> <confirmName…>`; tests (Engine + script, including an unmounted App Disk). Atlas: install script, sudoers, `sudo -l` post-check, then Engine commit, idea03 then idea02 | 1 (can run alongside 2) |
| 3b | Console | Unformatted disks under the Engine's row; format dialog (exact label, contents unknown, erase warning); `formatProgress` steps; 15 s / 5 min on the Console clock; open the new Files Disk; candidate removed mid-dialog | 3 (can start on the mock store) |
| 4 | App | Nextcloud opt-in, `before-starting` hook, entrypoint wrapper, convention doc (`restart: no`, Files Disk binds allowed), fake-occ tests, harness | 2 (hook can start earlier; alongside 3) |
| 5 | Ops | Hardware test on idea03 (8 steps, including formatting an exFAT stick and the refusal on Kid's unmounted throwaway App Disk; post-checks), then idea02 with MilkWise running. Format and refusal tests **never** run on idea02 | 0–4 |

## 13. Out of scope (v1)

- SMB, NFS or any host-level network share.
- Password-protected Files Disks (field reserved only). `readOnly` (field reserved, ignored).
- Choosing Apps per Files Disk.
- Backing up Files Disks (only the stable ID is prepared now).
- Using a Files Disk from another Pi.
- Files Disks on FAT, exFAT or NTFS (they must be formatted as ext4 first). Combined disks.
- Automatic formatting, formatting without the typed confirmation, formatting disks with IDEA data, filesystems other than ext4, cancelling a running format, choosing a custom filesystem label (always "School Files" in v1).
- Formatting ext4 disks that hold other files (§14, open question 4).
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
| Q7 Sudoers | One entry: `chown pi:pi /disks/sd[a-z][12]`, root folder only; no `umount -l`; code-mapping comment and `visudo -cf`; roll out idea03 → idea02 | Atlas |
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
| Koen change: formatting (2026-09-27) | Decisions 2 and 3 changed: the Engine can format as ext4 through an explicit Console action with typed confirmation; empty ext4 disks work straight away, other non-IDEA disks can be formatted first. Koen's choices on idea#125: **GPT with one partition**; **META.yaml written immediately**; existing files don't block formatting (typed confirmation + visible warning instead), **IDEA data always refused**; the hardware test covers formatting an exFAT stick and the refusal on an App Disk | Koen |
| Formatting review: Ops | System disks found by lookup only (`findmnt` for `/` and `/boot/firmware` + `lsblk -no PKNAME`), because the Pis boot from a USB SSD at `/dev/sda` and idea02's is an Intenso. The script is installed as a copy (`install -o root -g root -m 0755`), never a symlink, from `script/build_image_assets/idea-format-disk`, with full tool paths. `-d` is fine (e2fsprogs 1.47.2); symlinked staging refused. The sudoers entry has no argument list; post-check `sudo -l -U pi` matches through `10-engine`, because the blanket rule still exists. Per-Pi order: script, sudoers, post-checks, Engine commit; rollback in reverse; format tests on idea03 only | Atlas |
| Formatting review: App | The refusal test covers an **unmounted** App Disk (unit test + idea03). Refusal tests use a throwaway App Disk from the harness, never MilkWise or idea02. Formatted disks need no App changes | Kid |
| Formatting review: Engine | Mount only with `-t ext4` (behaviour change); whole non-system disks without ext4 become format candidates via `lsblk -J` (no sudo); candidate ID from the serial or a generated ID kept while plugged in, written into `META.yaml`; udev rule sees whole disks. The device is locked for the whole format, `addDevice` skips it, and the Engine calls `addDevice` after `udevadm settle`. The script re-checks serial and size. Shared system-disk helper; refuse mounted partitions and swap; the script is authoritative. Staging built as `pi` in `format-staging/`; GPT with one partition kept. Read-only role-marker check in the script | Axle |
| Formatting review: Console | `Engine.formatCandidates` shown under the Engine's row. **Pixel decided:** `confirmName` must exactly match the Engine-published `label`, kept unique per Engine with " (2)", so the command is `formatDisk <candidateId> <confirmName…>`. The dialog shows Engine, model, size, filesystem, erase warning, "contents unknown". `formatProgress` steps; result by the first new trace for the `candidateId`; 15 s / 5 min on the Console clock, no cancel; on success open the new Files Disk; a second concurrent format is refused | Pixel |
| Formatting open questions resolved | Script location: `script/build_image_assets`, installed by `build-engine`. `-d`: accepted. System-disk detection: the lookup helper. Disks the Engine can't mount: format candidates | Atlas, Axle, Pixel |
| Follow-up: App rule | Files Disk binds are simply allowed, not an "exception"; reconciling the general App volume convention is a separate issue for Kid | Kid |

### Remaining open questions (to settle during implementation, not blocking)

1. **How the Engine recognises Nextcloud's first start or an upgrade** so it can hold back a recreate. For example, wait until the container is healthy and Nextcloud reports installed and not in maintenance mode. Axle and Kid agree the check in step 2.
2. **Exact numbers:** the grouping window for runtime docks ("a few seconds") and the unmount retry count. Engine Dev Bot picks them in steps 0–2 and documents them in `docs/ARCHITECTURE.md`.
3. **The App volume convention** ("named volumes only" versus today's `./data` binds) is a separate issue for Kid. It doesn't block this work.
4. **Formatting ext4 disks that hold other files (for Koen).** Koen's decision allowed formatting "any other non-IDEA disk". Under the reviewed candidate model, an ext4 disk that holds non-IDEA files mounts and shows as "empty", `createFilesDisk` refuses it as not empty, and it is never a format candidate. Should v1 also offer "Format as School Files" for such disks (the Engine would unmount it and treat it as a candidate)? Recommendation: not in v1. It's rare, and the operator can empty the disk on another computer; adding it later reuses the same script and dialog.
5. **The exact udev rule change** (step 3, Axle). The current rule already links whole disks (`sd?`). The gap is mostly that `validDevice` skips whole disks and only partitions 1–2 are linked. The step 3 PR settles the exact rule and how whole-disk events reach the candidate list.
