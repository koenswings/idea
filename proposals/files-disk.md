# Proposal: Files Disk — a shared file store on a docked disk

**Author:** Steve (Lead Bot)
**Date:** 2026-09-27
**Revised:** 2026-09-27 (Design Review by Atlas, Kid, Axle and Pixel applied); 2026-09-27 (Koen: add ext4 formatting, merged in from idea#125)
**Status:** Proposed (design reviewed)
**Refs:** idea#75 (Files Disk), idea#125 (formatting sketch, merged into this proposal). Depends on: idea#121 (new disks never get META.yaml written, bug B1)
**Affects:** `agent-engine-dev` (main work), `agent-console-dev`, `app-nextcloud` (+ `agent-app-dev` conventions and harness), Ops (sudoers rollout, hardware test)
**Background research:** `files-disk-findings.md` (research notes, 2026-09-27)

---

## 1. Summary

A **Files Disk** is an ordinary ext4 USB disk or SSD that an operator turns into a shared file store from the Console. A disk with any other filesystem (a new exFAT stick, for example) can be **formatted as ext4 by the Engine first**, through an explicit Console action with a typed confirmation. When it is docked, the Engine mounts its `files/` folder into every App on that Engine that says it can use one. Nextcloud comes first. Teachers and students then reach the files through Nextcloud in the browser, over the school's local Wi-Fi.

There are two ways to create one:

- **An empty ext4 disk:** `createFilesDisk` writes two small files (`META.yaml` and `FILES.yaml`) and an empty `files/` folder, the same way a Backup Disk is created today. Nothing is erased.
- **Any other non-IDEA disk:** `formatDisk` erases it and creates one ext4 partition that already contains those files, so it comes up as a Files Disk straight away (§7.4).

The Engine never formats anything on its own. There are two new root permissions: changing the owner of the **disk root folder only** (`chown`), and running **one root-owned format script** that re-checks the device itself (§10).

Koen approved the design decisions in §5 (2026-09-27) and later that day reversed decision 2 to add formatting (idea#125). The Design Review (§14) filled in the implementation details of the first version. The formatting part (§7.4) needs a short design review of its own (§14, open questions 4–6).

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

1. The operator docks a disk that isn't an IDEA disk yet. It appears in the network tree with the **empty** badge. (If it isn't ext4, or it holds someone's files, see *Formatting* below.)
2. They select it and choose **Files Disk**. The form explains: *"This disk becomes a shared file store. Apps that support Files Disks (such as Nextcloud) on this Engine will show its files. Nothing on the disk is erased."*
3. They click **Create Files Disk**. The Console waits for the Engine's answer (§8):
   - **Success:** the disk's badge changes to **files** and the right pane shows the Files Disk view.
   - **Failure:** the Engine's message appears in the Empty Disk panel, for example "School Files is exfat. Files Disks must be ext4. Use Format as School Files to erase and format it." or "School Files is not empty."
   - **No answer after 15 seconds:** "The Engine didn't respond. It may not support Files Disks yet."
4. **Files Disk view:** name, size and free space, plus one of three lines:
   - "Available in: Nextcloud (nextcloud-01)"
   - "Nextcloud supports Files Disks but isn't running"
   - "No App on this Engine uses Files Disks yet"
   If the disk can't be used (password-protected, or an earlier unmount got stuck), the view shows **Not mounted** with the reason. There is an **Eject** button.
5. In Nextcloud, users see a folder named after the disk (for example **School Files**) and can open, upload and share files according to their Nextcloud accounts.
**Formatting (any non-IDEA disk, for example a new exFAT stick):**

- In the Empty Disk panel the operator chooses **Format as School Files**.
- The dialog shows what will be erased: size, model, current filesystem (for example "exfat"), and, if it holds files, a clear warning: *"This disk contains files. They will be erased."*
- The operator types the disk's name to confirm (the button stays disabled until it matches).
- The Console shows progress steps (checking, unmounting, partitioning, formatting, mounting). After a few seconds to a few minutes, the disk comes back with the **files** badge.
- App, Backup, Files and system disks never offer this action. The Engine refuses them too.

6. **Eject** (or pulling the disk): Nextcloud restarts briefly and the folder disappears. Re-docking brings it back. If the Pi can't unmount the disk cleanly, that Engine's row shows a warning such as "School Files couldn't be unmounted cleanly. Restart this Pi." This works for every disk type, not only Files Disks.

## 5. Design decisions (approved by Koen, 2026-09-27; decisions 2 and 3 changed by Koen on 2026-09-27)

| # | Decision | Reason |
|---|---|---|
| 1 | **Purpose:** a shared teacher/student file store reached **through Apps over HTTP**, Nextcloud first. **No host-level SMB/NFS** in v1. | Clients are browsers on the school Wi-Fi, and Nextcloud is already IDEA's file-sharing App. SMB/NFS would add packages, root configuration and user accounts to an unattended Pi. |
| 2 | **Changed 2026-09-27 (Koen, idea#125):** the Engine **can format a disk as ext4, only through an explicit Console action** (typed name confirmation; never automatically on dock). Without formatting, `createFilesDisk` still writes `META.yaml`, `FILES.yaml` and `files/` onto an existing ext4 filesystem without erasing anything. *(Was: "Don't format.")* | New drives come as exFAT/FAT, and schools can't prepare disks on a Linux machine. Safety comes from the explicit action, the typed confirmation, the Engine's refusals, and a root script that re-checks the device itself (§7.4). |
| 3 | **Changed 2026-09-27 (Koen):** disks that are **already empty ext4** work straight away (`createFilesDisk`). **Any other non-IDEA disk** (FAT, exFAT, NTFS, or ext4 with files) can be **formatted first** (`formatDisk`). Disks with IDEA data are always refused. **No combined disks.** *(Was: "Only empty ext4 disks; reject FAT, exFAT and NTFS.")* | Files Disks are still always ext4, because the ownership model and container binds rely on ext4 permissions. One role per disk keeps behaviour easy to predict. |
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

This part came in on 2026-09-27 (idea#125, merged into this proposal). It needs a short design review of its own (§14, open questions 4–6).

**Safety model**

| | Rule |
|---|---|
| (a) **Explicit only** | Formatting happens only through the Console action **Format as School Files**, confirmed by typing the disk's name. The Engine never formats automatically when a disk is plugged in. |
| (b) **Engine refusals** | The Engine refuses if the target is the Pi's own **boot or root device**, is **mounted** anywhere other than the Engine's own `/disks/<dev>` mount (which it unmounts first), or holds **IDEA data**. |
| (c) **Informed confirmation** | Before confirming, the Console shows size, model, current filesystem and whether the disk holds files. Existing files don't block formatting; the typed name plus the visible warning is the safeguard. IDEA data is always refused. |
| (d) **One root script** | Root access goes through **one small wrapper script**, `/usr/local/sbin/idea-format-disk`, allowed by **one sudoers entry for that script only**. There is no general `mkfs`, `sfdisk` or `wipefs` rule. The script is root-owned and not writable by `pi`, and it **re-validates the device itself**. |
| (e) **Comes up as a Files Disk** | The new filesystem already contains `META.yaml` (with the disk's stable ID), `FILES.yaml` and `files/` from the moment it is created, so the normal mount path picks it up as a Files Disk. |
| (f) **Progress and failure** | Reported through the existing command trace and an Operation with steps. The Console waits longer than 15 seconds (see below). |

**What counts as IDEA data.** Any of these makes the Engine refuse:

- `diskTypes` includes `app`, `backup`, `files` or `system`;
- an instance is stored on the disk;
- the disk root has `apps/`, `instances/`, `BACKUP.yaml` or `FILES.yaml`.

`META.yaml` alone doesn't count. Once idea#121 lands, the Engine writes `META.yaml` onto every new writable disk, so "has META.yaml" would block ordinary disks that were only ever docked. *(This refines the idea#125 sketch, which used META.yaml as the IDEA-data signal.)*

**Command:** `formatDisk <diskId> <confirmName…>` (scope `engine`). `diskId` follows the proposal's convention of disk IDs in commands and traces (`args.diskId`). `confirmName` is the typed name. It is the last argument and **variadic**, like `createBackupDisk`'s instance list, so names with spaces arrive as several tokens that the Engine joins with single spaces. It is then compared with the disk's name, with whitespace collapsed and case-sensitive. The handler throws on the first failure so the trace closes as `error`, and messages show the disk's name.

**Engine steps**

1. **Checks:** the disk is docked to this Engine; it is not the system disk; it has no IDEA data; `confirmName` matches; no resource lock (the handler then takes the disk lock).
2. **Resolve the whole device:** find the parent device of the docked partition (for example `sdb` for `sdb1`) with `lsblk -no PKNAME`. Refuse if it is the parent of the root or boot filesystem (see open question 5).
3. **Prepare the content:** write a staging folder `~/.local/state/idea-engine/format/<diskId>/` containing:
   - `META.yaml`, **keeping the disk's current ID**: a hardware serial stays the same; a generated ID is carried over, so the Console's selection and any history stay attached;
   - `FILES.yaml` (share name "School Files");
   - an empty `files/`.
4. **Unmount:** the Engine's own `/disks/<dev>` mount, using the existing `umount` entry and the 7.0 rules (never `rm -fr` a mounted path). The disk is marked undocked in the store.
5. **Format:** `sudo /usr/local/sbin/idea-format-disk /dev/sdb "School Files" <stagingDir>`.
6. **Hand back to the normal path:** after the script, udev reports the new partition `sdb1`. The usual `addDevice` path (`usbDeviceMonitor.ts:88`) mounts it and finds `META.yaml` with the same ID. `processDisk` sees `FILES.yaml`, the disk becomes a Files Disk, and the Apps get their mount (7.3). The command's trace closes `ok` once `diskTypes` includes `'files'`, or `error` if that doesn't happen within the timeout.
7. **Clean up:** remove the staging folder.

**The wrapper script `idea-format-disk <device> <label> <stagingDir>`** (runs as root; `set -eu`; no shell tricks with its arguments):

- **Arguments:**
    - `device` must match `^/dev/sd[a-z]$` (a whole disk, never a partition);
    - `label` must match `^[A-Za-z0-9 _-]{1,16}$` (ext4 labels are at most 16 bytes);
    - `stagingDir` must be exactly `/home/pi/.local/state/idea-engine/format/<id>` with a safe `<id>`, a real directory (not a symlink) owned by `pi`.
- **Re-validates the device itself:**
    - `lsblk` says it is a **disk** on the **USB** transport (`TYPE=disk`, `TRAN=usb`);
    - it is **not** the device holding `/` or the boot partition (derived with `findmnt` and `lsblk -no PKNAME`, not guessed from names);
    - **nothing** on it is mounted (no `MOUNTPOINTS` on the disk or any partition).
- **Then:**
    1. `wipefs -a` on the device;
    2. a **GPT** table with **one partition** covering the disk (`sfdisk`, part of util-linux, so no new package);
    3. `udevadm settle`;
    4. `mkfs.ext4 -F -L <label> -E root_owner=1000:1000 -d <stagingDir> /dev/sdX1`. `root_owner` makes the disk root belong to `pi`, so the `chown` step isn't needed. `-d` copies the prepared files in while the filesystem is created, so no extra mount is needed.
- **Exit codes and messages** are clear, for example "refused: /dev/sda holds the root filesystem". The Engine passes them into the trace unchanged.

**Timeout: 5 minutes.**

- The trace (status `running`) appears at once, so the normal 15-second "Engine didn't respond" check still applies to the start.
- After that, the Console follows the Operation's steps and allows **5 minutes** before saying "This is taking longer than expected; the Engine is still working", without failing the operation.
- Why 5 minutes: `mkfs.ext4` with its default lazy initialisation takes seconds even on large disks, but slow USB 2.0 sticks, large spinning disks, `udevadm settle` and the remount can add up to a minute or two. Five minutes leaves a wide margin without leaving a hung operation unnoticed for long.
- The Engine never kills the script halfway: an interrupted `mkfs` is worse than a slow one.

**Progress:** add `'formatDisk'` to `OperationKind`, with steps *Checking → Unmounting → Partitioning → Formatting → Mounting* (`currentStep`/`stepLabel`, as other operations already use).

**Failure:** if the script fails before partitioning, the disk is re-mounted as it was. If it fails after, the disk is left for the operator to retry. It shows up as unrecognised or unmountable (see open question 6). The trace carries the script's message.

**New `Disk` fields for the confirmation dialog** (all disks, published on dock, no sudo):

- `fsType: string` or `null` (from `lsblk -no FSTYPE`);
- `model: string` or `null` (`lsblk -no MODEL` of the parent device);
- `hasFiles: boolean` or `null` (the root has anything besides `lost+found`, `META.yaml` and common system folders such as `System Volume Information`).

They are cleared on undock like `sizeBytes`/`freeBytes`.

### 7.5 Store schema

| Where | Field | Notes |
|---|---|---|
| `Disk` | `filesConfig: { shareName: string; readOnly: boolean; passwordProtected: boolean; error: string }` or `null` | `error` is a string or `null` and is **only** used for a password-protected disk. Set by `processFilesDisk`. Reset to `null` in `createOrUpdateDisk` and `undockDisk`, like `backupConfig`. The password never goes into the store. |
| `Disk` | `unmountError: { engineId: EngineID; mountPoint: string; fsUuid: string; message: string }` or `null` | **All disk types.** Set when an unmount is still busy after the retries. `mountPoint` is where the disk was mounted (for example `/disks/sdb1`); it's needed because `device` is `null` after undock. `fsUuid` is the filesystem UUID recorded at mount time (`lsblk -no UUID /dev/<dev>`), so the startup check can tell this disk apart from a different disk later mounted at the same path. Kept after undock (`dockedTo` becomes `null`), so `engineId` says which Pi has the stuck mount. Cleared on the next successful mount of that disk, or at Engine startup unless `mountPoint` is still mounted with the same `fsUuid` (7.0). Added in step 0. |
| `Disk` | `sizeBytes: number` or `null`, `freeBytes: number` or `null` | All docked disks. `fs.statfs` on dock and every 10 minutes, rounded, written only on a change of more than 1% or 100 MB. Cleared on undock. |
| `Disk` | `fsType: string` or `null`, `model: string` or `null`, `hasFiles: boolean` or `null` | All docked disks, for the format dialog (§7.4). Published on dock, cleared on undock. |
| `Operation` | `kind: 'formatDisk'` | New `OperationKind` with steps (§7.4) |
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
- **Format as School Files (§7.4):**
    - Offered in the Empty Disk panel for any disk without IDEA data, including non-ext4 disks and disks with files. It is the only Files Disk option when the disk isn't ext4, and an extra option next to "Create Files Disk" when it is.
    - The dialog shows size, model, `fsType` and, when `hasFiles` is true, the warning "This disk contains files. They will be erased."
    - The operator types the disk's name; the button is disabled until it matches.
    - It sends `formatDisk <diskId> <typed name>` and uses the same result helper, with the 5-minute progress rule, showing the Operation's steps.
- **Unmount warning (all disk types):** when a disk has `unmountError`, show a warning on **that Engine's row** in the network tree (found by `unmountError.engineId`, because an undocked disk has `dockedTo: null` and would otherwise appear nowhere). Example: "School Files couldn't be unmounted cleanly. Restart this Pi." While the disk is docked, show the same warning on the disk's own view.
- **Types and commands:** new commands `createFilesDisk <diskId>` and `formatDisk <diskId> <confirmName…>`. Add `filesConfig`, `unmountError` (`{ engineId; mountPoint; fsUuid; message }`), `sizeBytes`/`freeBytes`, `fsType`/`model`/`hasFiles`, `OperationKind` `'formatDisk'`, `App.filesMount`, `Instance.filesMounts` and the missing `'system'` DiskType to `src/types/store.ts`. Update `docs/ARCHITECTURE.md`.
- **Mock store fixtures and tests:** a Files Disk in each state, an exFAT disk with files, the panel routing, the helper (error, success, timeout), and the format dialog (confirmation matching, warning, disabled for IDEA disks).

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

**Sudoers: a second new entry for formatting** (§7.4):

```
/usr/local/sbin/idea-format-disk
```

- This entry allows **only this script**. There is no general `mkfs`, `sfdisk` or `wipefs` rule. The script validates all its arguments itself, so the entry doesn't need argument patterns (a `*` in sudoers arguments would match too much anyway).
- The script is installed **root-owned, mode 0755**, in root-owned `/usr/local/sbin`, and must not be writable by `pi`. If `pi` could edit it, the entry would amount to full root.
- The same code-mapping comment and `visudo -cf` rules apply.

**Deploy notes for formatting (Atlas):**

- The Engine PR ships the script and the updated `10-engine.sudoers` as files that can be installed on their own, and names the first Engine commit that needs them.
- Atlas installs the script with `install -o root -g root -m 0755` and the sudoers file with `visudo -cf` + atomic move, idea03 first, then idea02, before deploying that commit.
- Both must **survive a reboot and a reinstall**: they live on the Pi's root filesystem (not `/tmp`, not the git checkout), and `build-engine` installs them in the same step that installs the sudoers file today (`installEngineSudoers`), so a fresh install or reinstall puts them back.
- Without them, `formatDisk` fails with a clear error before touching the disk.

**Engine state folder:** `~/.local/state/idea-engine/` (compose overrides and format staging folders) is added to **Atlas's pre-deploy backup list**. It can always be rebuilt from the store, but backing it up makes a rollback easier to inspect.

**No new packages.** `sfdisk`, `wipefs`, `lsblk` (util-linux) and `mkfs.ext4` (e2fsprogs) are already on Raspberry Pi OS. No Samba or NFS.

## 11. Tests

**Engine (`test/automated/`):**

- **Step 0:** a new disk gets `META.yaml` and keeps its ID on re-dock. The root-owned disk path calls chown. Undock never removes a still-mounted path; a busy unmount gives an error trace, the store is still updated, and `unmountError` is set with the Engine ID, the mount point and the `fsUuid` recorded at mount time. It survives undock and is cleared on the next successful mount (tested for an App Disk as well as a Files Disk). **Startup cleanup:** an `unmountError` with this Engine's `engineId` whose `mountPoint` is no longer mounted (mocked `findmnt`) is cleared at startup. **A different disk mounted at the same `mountPoint`** (`findmnt -no UUID` returns another UUID than `fsUuid`) → the error is cleared. The same filesystem still mounted there (same `fsUuid`) → the error is kept. The `fsUuid` recorded at mount time (mocked `lsblk -no UUID`) ends up in the error, and one with another Engine's `engineId` is never touched. Mounting refuses when `findmnt` shows something already mounted.
- **Command:** `createFilesDisk` success; errors for unknown ID, disk docked elsewhere, system disk, non-empty disk, disk with instances, non-ext4, unwritable after chown, and locked disk. Each error closes the trace as `error`, and the trace carries `args.diskId`.
- **Detection:** `processDisk` sets `['files']`, `filesConfig`, size and free space. A non-null `password` → not mounted.
- **Override:** long bind syntax, `create_host_path: false`, only the listed services, slug sanitising, always-suffixed paths, display-name JSON, rebuilt every time.
- **Status handling:** Running recreated, Stopped untouched, Paused `--no-start --force-recreate`. `filesMounts` only written after success. Boot order (Files Disks before instances) and grouping of runtime docks.
- **Formatting:** `formatDisk` refusals (not docked here, system disk, parent of root or boot, each kind of IDEA data, name mismatch including extra spaces, locked disk). The success path runs with a fake script: it unmounts first, passes the right arguments, writes a staging folder with the same `diskId`, reports Operation steps, and the re-added partition becomes `['files']` with the same ID. A script failure ends as an error trace with the script's message.
- **Wrapper script** (shell tests with fake `lsblk`, `findmnt`, `wipefs`, `sfdisk` and `mkfs.ext4`): refuses a partition path, a non-USB disk, the root or boot disk, a mounted disk, a bad label and a bad or symlinked staging path. It runs the steps in order with the right flags.
- **Fixture:** `test/fixtures/disk-files/` plus an opted-in sample App.

**Console:** the helper (error, success, timeout; matching by new trace ID and `args.diskId`), panel routing, the three "available in" states, Not mounted, and the format dialog.

**App:** the hook against a fake `occ` (create, keep admin storages, delete only its own, idempotent), the wrapper (chown only when wrong), then the harness.

**Hardware (idea03, isolated with `mdns: false`, a person at the Pi, like idea#110).** Test setup:

- a **partitioned** ext4 disk made with default `mkfs.ext4`, so the root-owned case is tested (unpartitioned disks aren't mounted);
- a FAT stick;
- an **exFAT stick with some files on it** (the format test);
- an App Disk (for the refusal test);
- Nextcloud installed from an App Disk.

Eight steps:

1. Dock the FAT stick → clear rejection when trying to create a Files Disk.
2. Dock the root-owned ext4 disk → create the Files Disk → **files** badge, root now `pi:pi`.
3. Nextcloud shows the folder → upload a file.
4. Eject → Nextcloud recreated, folder gone, clean unmount.
5. Reboot with both disks docked → Nextcloud starts once with the folder, file still there.
6. Pull the Files Disk without Eject → Nextcloud recreated without it, unmount clean or a recorded error, nothing deleted.
7. **Format the exFAT stick:** the dialog shows size, model, `exfat` and the files warning. A wrong typed name keeps the button disabled. With the right name it comes back as a Files Disk on a GPT partition with the same disk ID, and Nextcloud shows it.
8. **Refusal:** send `formatDisk` for the App Disk (directly, since the Console doesn't offer it) → refused with a clear error, the disk stays mounted and unchanged, and its instances keep running.

**After every step:** the Pi's own boot and root disk untouched, nothing new under `/disks` on the SD card, no leftover mounts, 0 Engine restarts. **Then idea02** (golden), with MilkWise up the whole time.

## 12. Rollout: implementation issues per domain

| Step | Domain | Issue | Depends on |
|---|---|---|---|
| 0 | Engine + Ops | **idea#121** (write `META.yaml`) + **Q5 safety fix** (never `rm -fr` a mounted path; retry umount; `Disk.unmountError` (`engineId`, `mountPoint`, `fsUuid`, `message`) for every disk type, cleared at startup unless the same filesystem (`fsUuid`) is still mounted at `mountPoint`; `findmnt` check before mount) + **sudoers `chown` entry** (code-mapping comment, `visudo -cf`, shipped as a standalone file; PR names the first Engine commit that needs it; Atlas installs it with `visudo -cf` + atomic move on idea03, then idea02, before deploying) | — |
| 1 | Engine | Files Disk type: `FILES.yaml` detection, `createFilesDisk <diskId>` with checks, `filesConfig`, `sizeBytes`/`freeBytes`, tests, `COMMANDS.md` | 0 |
| 1b | Console | *(in parallel with 1, on the mock store)* Wording, result helper, Files Disk view, types, fixtures | — (merge after 1) |
| 2 | Engine | Mounting: per-service `x-app.filesMount`, override helper (`COMPOSE_FILE`), status handling, locks, boot order, grouping of runtime docks, undock/eject path, `Instance.filesMounts`, tests | 1 |
| 3 | Engine + Ops | **Formatting:** `idea-format-disk` script, its sudoers entry (standalone files, deploy notes, survives reboot and reinstall), `formatDisk <diskId> <confirmName…>`, `Disk.fsType`/`model`/`hasFiles`, `OperationKind` `'formatDisk'`, tests (Engine + script) | 1 (can run alongside 2) |
| 3b | Console | Format dialog: size, model, filesystem, files warning, typed name, progress with the 5-minute rule | 3 (can start on the mock store) |
| 4 | App | Nextcloud opt-in, `before-starting` hook, entrypoint wrapper, convention doc (`restart: no`, Files Disk binds allowed), fake-occ tests, harness | 2 (hook can start earlier; alongside 3) |
| 5 | Ops | Hardware test on idea03 (8 steps including formatting an exFAT stick and the App Disk refusal, post-checks), then idea02 with MilkWise running | 0–4 |

## 13. Out of scope (v1)

- SMB, NFS or any host-level network share.
- Password-protected Files Disks (field reserved only). `readOnly` (field reserved, ignored).
- Choosing Apps per Files Disk.
- Backing up Files Disks (only the stable ID is prepared now).
- Using a Files Disk from another Pi.
- Files Disks on FAT, exFAT or NTFS (they must be formatted as ext4 first). Combined disks.
- Automatic formatting, formatting without the typed confirmation, formatting disks with IDEA data, filesystems other than ext4, choosing a custom label in the dialog (always "School Files" in v1).
- Disks the Engine doesn't mount today (whole-device "superfloppy" sticks without a partition table, filesystems without a kernel driver); see open question 6.
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
| Follow-up: App rule | Files Disk binds are simply allowed, not an "exception"; reconciling the general App volume convention is a separate issue for Kid | Kid |

### Remaining open questions (to settle during implementation, not blocking)

1. **How the Engine recognises Nextcloud's first start or an upgrade** so it can hold back a recreate. For example, wait until the container is healthy and Nextcloud reports installed and not in maintenance mode. Axle and Kid agree the check in step 2.
2. **Exact numbers:** the grouping window for runtime docks ("a few seconds") and the unmount retry count. Engine Dev Bot picks them in steps 0–2 and documents them in `docs/ARCHITECTURE.md`.
3. **The App volume convention** ("named volumes only" versus today's `./data` binds) is a separate issue for Kid. It doesn't block this work.

### Open questions on formatting (for the design review of §7.4)

4. **Where does the wrapper script live, and who installs it?** Recommendation: keep it in the Engine repo next to the sudoers file (`script/build_image_assets/idea-format-disk`), so script and Engine code change together and are tested in the same PR. `build-engine` installs it root-owned, and Atlas installs it on existing Pis. The alternative is the install script only. Also: is `mkfs.ext4 -d` (copying the staging folder in while formatting) acceptable, or should the Engine instead mount the new partition and write the files (simpler script, one more step)? (Axle, Atlas)
5. **How do the Engine and the script identify the root and boot device reliably?** Today `usbDeviceMonitor.ts:64–71` guesses the boot partition as "root's parent + 1" and only handles `sdX` roots. Proposal: resolve the root filesystem's source with `findmnt -no SOURCE /` and the boot partition with `findmnt -no SOURCE /boot/firmware`, map both to their parent disks with `lsblk -no PKNAME`, and refuse either parent. This also works when the Pi boots from an SD card (`mmcblk0`), where no `sdX` device is the root. (Axle)
6. **Disks the Engine can't mount today.** A stick without a partition table (whole-device filesystem) is skipped (`usbDeviceMonitor.ts:95–100`), and a filesystem whose driver is missing fails to mount, so neither appears in the Console and neither can be formatted. Should the Engine register such disks as "unrecognised, can be formatted" (with `fsType`, size and model, but no mount)? Recommendation: yes, as a small follow-up after step 3, because these are exactly the disks schools will bring. (Axle, Pixel)
