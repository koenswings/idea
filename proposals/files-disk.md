# Proposal: Files Disk — a shared file store on a docked disk

**Author:** Steve (Lead Bot)
**Date:** 2026-09-27
**Status:** Draft
**Refs:** idea#75 (Files Disk). Depends on: idea#121 (new disks never get META.yaml written, bug B1)
**Affects:** `agent-engine-dev` (main work), `agent-console-dev`, `app-nextcloud` (+ `agent-app-dev` harness), Ops (fleet testing only)
**Background research:** `files-disk-findings.md` (research notes, 2026-09-27)

---

## 1. Summary

A **Files Disk** is an ordinary ext4 USB disk or SSD that an operator turns into a shared file store from the Console. When it is docked, the Engine mounts its `files/` folder into every App on that Engine that says it can use one. Nextcloud comes first. Teachers and students then reach the files through Nextcloud in the browser, over the school's local Wi-Fi.

The Engine never formats the disk. Creating a Files Disk only writes two small files (`META.yaml` and `FILES.yaml`) and an empty `files/` folder. This is the same way a Backup Disk is created today.

Koen has approved the design decisions in §5 (2026-09-27). This proposal turns them into a plan per domain and lists the questions the Dev Bots need to answer in the design review.

## 2. Why

- The Console already has a "Files Disk" option for empty disks. The Engine has no `createFilesDisk` command, so clicking it does nothing, and the Console still says "Command sent. The Engine is configuring the disk." The disk stays empty and no error appears anywhere.
- The original design (`agent-engine-dev/proposals/solution-description.md`, lines 81, 89, 138, 210–216, 682) promises Files Disks: "Contains a File System that is automatically network mounted when docked" and "auto-mounted into Apps that have been created with the ability to work with Files Disks … Examples: A file store into Nextcloud".
- Schools need somewhere to keep and share documents (worksheets, photos, student work) that doesn't depend on a single App's internal storage. It should be possible to move that store to another Pi by moving the disk.

## 3. What a Files Disk is

- **A disk with a role.** Like App Disks and Backup Disks, a Files Disk is recognised by what is on it, here a `FILES.yaml` file in the disk root. The Engine checks for it every time the disk is docked.
- **A folder of files, not an App.** The shared content lives in `files/`. The Engine doesn't serve it itself. Apps that opt in get the folder mounted inside their container.
- **Local to one Pi.** Only the Engine it is docked to uses it. To use the files on another Pi, you move the disk.
- **Stable identity.** Every Files Disk has a permanent ID in `META.yaml`, so a later Backup Disk feature can refer to it.

## 4. User flow in the Console

1. The operator docks an empty ext4 disk. It appears in the network tree with the **empty** badge.
2. They select it and choose **Files Disk**. The form explains: *"This disk becomes a shared file store. Apps that support Files Disks (such as Nextcloud) on this Engine will show its files. Nothing on the disk is erased."*
3. They click **Create Files Disk**. The Console waits for the command's result instead of claiming success straight away:
   - **Success:** the disk's badge changes to **files** and the right pane shows the Files Disk view.
   - **Failure:** the Engine's message is shown, for example "This disk is not ext4 (found exfat). Files Disks must be ext4." or "This disk is not empty."
4. **Files Disk view:** name, free space, and "Available in: Nextcloud (nextcloud-01)", or "No App on this Engine uses Files Disks yet". There is also an **Eject** button.
5. In Nextcloud, users see a folder named after the disk (for example **School Files**) and can open, upload and share files according to their Nextcloud accounts.
6. **Eject** (or pulling the disk): Nextcloud restarts briefly and the folder disappears. Re-docking brings it back.

## 5. Design decisions (approved by Koen, 2026-09-27)

| # | Decision | Reason |
|---|---|---|
| 1 | **Purpose:** a shared teacher/student file store reached **through Apps over HTTP**, Nextcloud first. **No host-level SMB/NFS** in v1. | Clients are browsers on the school Wi-Fi, and Nextcloud is already IDEA's file-sharing App. SMB/NFS would add packages, root configuration and user accounts to an unattended Pi. |
| 2 | **Don't format.** Write `META.yaml`, a `FILES.yaml` marker and a `files/` folder onto the existing ext4 filesystem, like Backup Disks. Remove the Console's "will format" wording. | Formatting needs root access to block devices, and one wrong click would destroy data. Empty Disks are already ext4 by definition. |
| 3 | **Only empty ext4 disks.** Reject FAT, exFAT and NTFS with a clear message. **No combined disks** (a disk can't also be an App or Backup Disk). | The ownership model and container bind mounts rely on ext4 permissions. One role per disk keeps behaviour easy to predict. |
| 4 | **Apps opt in** through compose metadata (`x-app.filesMount`). **Every** Files Disk on an Engine is mounted into **every** opted-in App on that Engine. Choosing Apps per disk comes later. | Creation stays one click and there are no per-disk links to manage. |
| 5 | **No password in v1.** Nextcloud accounts give access control. A `password` field is reserved in `FILES.yaml`. | A disk-level password only makes sense with a host share or an App that enforces it. Reserving the field avoids a format change later. |
| 6 | **Served only by the Engine it is docked to.** No mounts across Pis. | Network mounts between Pis create fragile dependencies, and reliability is the first design constraint. |
| 7 | **On undock or eject**, restart the affected Apps **without** the mount, then unmount. **Remount on dock.** | A disk can't be unmounted while a container holds it. A dangling mount could make an App write to the Pi's own SD card or SSD. |
| 8 | **Backup is out of scope**, but every Files Disk gets a **stable ID now**. | Later Backup Disk links need to refer to the Files Disk by ID. |
| 9 | A quick **Console-only fix** (disable or label the Files Disk button until the Engine is ready) was offered but **not chosen**. It stays available as a separate step if the rollout takes long (§13). | Koen prefers to do the real feature. |

## 6. On-disk format

```
/                      (disk root, ext4)
├── META.yaml          disk identity (existing format)
├── FILES.yaml         marker + Files Disk settings (new)
├── files/             the shared content — the only folder Apps see
└── lost+found/        created by mkfs; ignored
```

**`META.yaml`** (existing format from `src/data/Meta.ts`, written if missing):

| Field | Meaning |
|---|---|
| `diskId` | Permanent ID: the hardware serial if the Engine can read it, otherwise a generated uuid. Must not change between docks (depends on bug B1 being fixed). |
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
readOnly: false          # reserved; v1 always false (Apps get read-write)
password: null           # RESERVED for a future password option; v1 must be null.
                         # If an Engine finds a non-null value it does not mount the disk
                         # and reports "password-protected Files Disks are not supported yet".
```

**`files/`**: an empty folder when created. Everything users store goes here. `META.yaml` and `FILES.yaml` stay outside it, so users can't delete them from inside an App.

## 7. Engine changes (agent-engine-dev)

**7.1 `createFilesDisk <diskName>` command** (`src/data/Commands.ts`, scope `engine`, one argument named `diskName`)

The Console already sends this command. With one argument, the whole rest of the line becomes the name, so names with spaces work. The handler checks the following, in order, and **throws** a clear error on the first failure, so the Console's command trace shows it:

1. **Name:** exactly one disk with this name is **docked to this Engine** (`dockedTo === localEngineId`, `device` set). Zero matches → "not found on this Engine". More than one → "several disks are called X; rename one".
2. **Not the system disk.**
3. **Empty:** `diskTypes` is exactly `['empty']`, no instance is stored on it, and the root has nothing except `META.yaml` and `lost+found`. Otherwise → "This disk is not empty".
4. **ext4:** `findmnt -no FSTYPE /disks/<dev>` returns `ext4` (no root access needed). Otherwise → "This disk is <type>. Files Disks must be ext4."
5. **Writable:** the Engine user can write to the disk root.
6. **Not busy:** no resource lock on the disk (`resourceLock`).

It then writes `META.yaml` if missing, writes `FILES.yaml`, creates `files/`, and runs `processDisk` again. Document it in `docs/COMMANDS.md`.

**7.2 Detection** (`src/data/Disk.ts`)
- `isFilesDisk(disk)`: `FILES.yaml` exists in the disk root. This replaces the stub at `Disk.ts:435–439`.
- `processDisk` branch (`Disk.ts:197–201`): add `'files'` and call `processFilesDisk`. Replace the TODO that links to #46.
- `processFilesDisk`: read `FILES.yaml` and set `disk.filesConfig`. If `password` isn't null, record an error trace and don't mount. Otherwise trigger the remount of opted-in instances on this Engine (7.3).

**7.3 Mounting into opted-in Apps**
- When an App's `compose.yaml` has `x-app.filesMount: <path in container>`, store it as `App.filesMount`.
- When the Engine creates or starts an instance of such an App (`Instance.ts:1009` `docker compose create`, `:1074` `docker compose up -d`), it generates a small **compose override file** that adds one bind mount per Files Disk docked to this Engine:
  `/disks/<dev>/files` → `<filesMount>/<shareName>`
  It then runs compose with `-f compose.yaml -f <override>`. The override lives on the Engine (for example under the Engine's run directory), not on the App Disk, so moving an App Disk never carries stale mounts.
- **Dock a Files Disk:** recreate the running opted-in instances on this Engine so they pick up the new mount (`compose up -d` with the new override).
- **Eject or undock a Files Disk:** first recreate the affected instances without that mount, then unmount (`undockDisk` in `usbDeviceMonitor.ts:305`). If a physically pulled disk still can't be unmounted because it is busy, record an error trace and don't leave the store half-updated.
- Record which Files Disks each instance has mounted (`Instance.filesMounts`) so the Console can show it.

**7.4 Store schema**

| Where | Field | Notes |
|---|---|---|
| `Disk` | `filesConfig: { shareName: string; readOnly: boolean; passwordProtected: boolean }` or `null` | Set by `processFilesDisk`. Reset to `null` in `createOrUpdateDisk` and `undockDisk`, like `backupConfig`. The password itself never goes into the shared store. |
| `App` | `filesMount: string` or `null` | From `x-app.filesMount` |
| `Instance` | `filesMounts: DiskID[]` | Files Disks currently mounted into this instance |
| `DiskType` | `'files'` | Already exists in `CommonTypes.ts:39` |

`diskDB`, `appDB` and `instanceDB` are maps, so `store-template.json` shouldn't need changes. The quality scan requires it to stay untouched.

**7.5 Prerequisite: bug B1 (idea#121).** Today a new disk's `META.yaml` is never written (`usbDeviceMonitor.ts:174` logs "Creating one now" but doesn't). Disks without a recognised hardware serial get a new ID on every dock. `createFilesDisk` writes `META.yaml` itself, but B1 should be fixed first so that identity works the same way for every disk type.

## 8. Console changes (agent-console-dev)

- **Empty Disk panel** (`EmptyDiskPanel.tsx:277–289`): replace "The Engine will format this disk…" with the wording in §4. Rename the button to "Create Files Disk".
- **Wait for the result:** follow the command's trace, or watch for `diskTypes` to become `['files']`, and show the Engine's error message on failure, instead of an immediate "Command sent". Backup Disk and Install App have the same weakness and can reuse this.
- **Files Disk view:** add a `'files'` case to `rightPanelFor` (`App.tsx:46–58`) and a small panel showing name, free space, "Available in: <Apps>" (from `Instance.filesMounts`) and Eject.
- **Types:** add `filesConfig`, `App.filesMount`, `Instance.filesMounts` and the missing `'system'` type to `src/types/store.ts`. Update `docs/ARCHITECTURE.md`.
- **Mock store and tests:** a Files Disk entry, the panel routing, and the error and success states.

## 9. App changes (app-nextcloud, agent-app-dev)

**Opt-in:** add `filesMount: /mnt/idea-files` to `x-app` in `app-nextcloud/compose.yaml`. Document the field in the App compose conventions in `agent-app-dev`.

**How the files appear inside Nextcloud: options**

| Option | How it works | Pros | Cons |
|---|---|---|---|
| **A. External storage (recommended)** | Enable Nextcloud's *External storage* app. For each folder under `/mnt/idea-files/`, create a **Local** external storage mount (`occ files_external:create`) named after the share, available to all users (or a group). | The official way. Files stay plain files on the disk, readable without Nextcloud. Removing the disk just makes the folder unavailable. Admins can limit it to groups. | Needs an `occ` step whenever the set of disks changes. Nextcloud needs "check for changes" enabled to see files added outside it. |
| B. Bind mount into the data folder | Mount into `/var/www/html/data/<user>/files/…` and run `occ files:scan`. | No extra Nextcloud app. | Tied to one user, and Nextcloud's file database gets out of step when the disk is removed. Fragile. |
| C. Group Folders app | Nextcloud-managed shared folders. | Nice permissions. | Stores data in Nextcloud's own format and location, not on the Files Disk. Doesn't meet the goal. |

**Recommendation:** Option A. Who runs the `occ` step is an open question (§14). The preferred answer is an **App-side startup hook** in the Nextcloud image that scans `/mnt/idea-files/*` and adds or removes external storages on every container start. The Engine then stays generic and knows nothing about Nextcloud. Because the Engine recreates the container whenever Files Disks change (§7.3), the hook always sees the current set.

**File ownership:** the disk is written by the Engine user (`pi`, uid 1000), and Nextcloud runs as `www-data` (uid 33). The folder must be writable by the App. See §14.

**Harness:** add a test in `agent-app-dev` that docks a Files Disk fixture next to a Nextcloud instance and checks that the folder appears and is writable.

## 10. Ops and permissions

- **Sudoers:** **no change is expected for v1.** Writing `FILES.yaml` and `files/` happens as the Engine user on the mounted disk, which is how `BACKUP.yaml` works today. Filesystem detection (`findmnt`) and compose need no root. Two possible additions, to be decided in review: `umount -l` (lazy unmount for a pulled, busy disk) and a narrow `chown` on `/disks/sd[a-z][12]/files` if the ownership solution needs root. Any addition goes into `10-engine.sudoers` together with its code-mapping comment.
- **No new packages.** No Samba or NFS.
- **Fleet testing:** needs a spare ext4 USB disk (plus a FAT stick for the rejection test) on review Pi idea03 before the golden Pi idea02 gets it.

## 11. Tests

**Engine (`test/automated/`):**
- `isFilesDisk` true or false. `processDisk` sets `['files']` and `filesConfig`. Undock clears them.
- `createFilesDisk`: success on an empty ext4 fixture. Errors for unknown name, duplicate name, disk docked to another Engine, system disk, non-empty disk, disk with instances, non-ext4 (mock `findmnt`) and locked disk. Each error closes the trace as **error**.
- A non-null `password` → not mounted, error trace.
- Override generation: an opted-in App gets one bind per Files Disk. A non-opted-in App gets none.
- Dock, undock and eject order: instances are recreated before unmount.
- New fixture `test/fixtures/disk-files/` (`META.yaml`, `FILES.yaml`, `files/readme.txt`) and an opted-in sample App.

**Console:** panel routing for `'files'`, the new wording, success and error states, the Files Disk view.

**App:** harness test from §9.

**On hardware (review Pi):** create a Files Disk from the Console, see it in Nextcloud, upload a file, eject (Nextcloud restarts, folder gone), re-dock (folder back, file still there), try a FAT stick (clear rejection).

## 12. Rollout: implementation issues per domain

| Order | Domain | Issue | Depends on |
|---|---|---|---|
| 0 | Engine | **Fix B1 (idea#121):** write `META.yaml` for new disks | — |
| 1 | Engine | `FILES.yaml` detection, `createFilesDisk` with checks, `filesConfig` in the store, tests, `COMMANDS.md` | 0 |
| 2 | Console | New wording, wait for the result, Files Disk view, types | 1 (can start on the mock store in parallel) |
| 3 | Engine | `x-app.filesMount` → `App.filesMount`; compose override; remount on dock; restart-then-unmount on eject/undock; `Instance.filesMounts`; tests | 1 |
| 4 | App | Nextcloud opt-in + external-storage startup hook + ownership; harness test; convention doc | 3 (can be developed alongside) |
| 5 | Ops | Hardware test on idea03, then golden idea02 after merge | 1–4 |

## 13. Out of scope (v1)

- SMB, NFS or any host-level network share.
- Password-protected Files Disks (field reserved only).
- Choosing Apps per Files Disk.
- Backing up Files Disks (only the stable ID is prepared now).
- Using a Files Disk from another Pi.
- FAT, exFAT and NTFS disks. Formatting disks. Combined disks (Files + App/Backup).
- Kolibri, Kiwix or other Apps as Files Disk users (possible later with the same opt-in).
- Quotas and per-user folders beyond what Nextcloud offers.
- **Optional separate step, not chosen:** a Console-only change that disables or labels the Files Disk button until the Engine side ships. It can be picked up if the rollout takes long.

## 14. Open questions for the design review

**For App Dev Bot and Engine Dev Bot: the Nextcloud mount mechanism**
1. Is Option A (external storage, **Local** backend) workable in our Nextcloud image, and should the `occ` step be an **App startup hook** (preferred) or Engine code? Doc line 685 of the old design allows Nextcloud-specific Engine code, but a hook keeps the Engine generic.
2. **Ownership:** how do we make `files/` writable for `www-data` (uid 33) while the Engine writes as `pi` (uid 1000)? The options are group-writable with a shared group id, the container fixing ownership at start, or the Engine chowning `files/` (would need sudoers). Which is safest?
3. Mount path naming inside the container: `<filesMount>/<shareName>`, but what happens if two docked disks have the same share name (add a short ID suffix)?

**For Engine Dev Bot: App restart on eject**
4. Is **recreating the container with a new compose override** (`compose up -d`) the right way to add or remove a mount? Where should the override file live, and how does it interact with the existing start and stop logic and the "Stopped" status (don't start a stopped instance just to change mounts)?
5. **Pulled disk:** if the disk is removed without Eject, the kernel may keep the mount busy until the container is recreated. Is recreate-then-`umount` enough, or do we need `umount -l`? Today `undockDisk` aborts before updating the store when umount fails.
6. **Dock order at boot:** if the App Disk is processed before the Files Disk, Nextcloud starts and is then recreated a moment later. Is that acceptable, or should instance start wait briefly for all disks?

**For Engine Dev Bot and Ops: sudoers**
7. Confirm that v1 needs **no sudoers change**. If `umount -l` or a `chown` turns out to be needed, agree the exact narrow patterns.

**Smaller points**
8. Should `createFilesDisk` take the **disk ID** instead of the name, like `copyApp`/`moveApp`? Names aren't unique, and IDs avoid the space-in-name problem for later extra arguments.
9. Should `readOnly` stay reserved, or be usable in v1 (for example a read-only resources disk prepared by project admins)?
