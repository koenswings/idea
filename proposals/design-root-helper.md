# Design note: a root helper for app data (copy, move, backup, restore)

> Imported from the ops box (duration-evidence) on 2026-10-13 for the audit; text unchanged.

For Koen. From Engine Dev (idea#168), 2026-10-06. This is a proposal only: no code and no commits.
Code references are to `agent-engine-durability` at HEAD c14e4d2.

## Recommendation

Add **one small root-owned program, `/usr/local/sbin/idea-app-data`**. It has a fixed set of
subcommands: `size`, `copy`, `send`, `receive`, `delete`, `borg-init`, `borg-info`, `borg-create` and
`borg-extract`.

The Engine calls it with `sudo -n` for app *instance data* only. App masters and service tars are
Engine-written and owned by pi, so they stay as they are.

It is allowed by **one sudoers line with no argument list**. The program itself checks every argument and
only ever touches:
- `/disks/<sdX>/instances/<id>` on a mounted Engine disk;
- `/instances/<id>` on the system disk;
- `/disks/<sdX>/backups/<id>` on a Backup Disk.

This copies the pattern Koen already approved for `idea-erase-disk` (idea#134).

## 1. The problem

The Engine runs as **pi** under pm2 on every Pi, so on **every school Pi**. App containers write their data
as other users.

| Who writes it | What we see |
|---|---|
| Kolibri runs as root | Session files `-rw------- root root` (`data/kolibri/sessions/`) |
| Nextcloud's MariaDB | `999:999`, folders 0700 (`data/db/mysql`, `data/db/nextcloud`) |
| Nextcloud itself | `www-data`; `data/` is 0770, `config.php` is 0640 |

All of these were seen on idea01 today. pi cannot read them, so:
- **copyApp and moveApp fail.**
  - r36 @43: `copyApp Failed … rsync code 23 on a root-0600 Kolibri session file`
    (DIAGNOSIS-r36-98.md).
  - r37, idea01 Engine log about 10:00: `rsync exited with code 23 … sessions/kolibri1xtj…:
    Permission denied (13)`, for 3 files.
  - The walk still reported "ok", and the half-finished copy was registered as a ghost instance.
  - The data copy is plain `rsync -a` as pi (`rsync.ts:47,60`, called from `CopyMoveApp.ts:307` copy and
    `:543` move).
  - Even where pi *can* read the files, the copy ends up owned by pi, which MariaDB and Nextcloud do not
    expect.
  - moveApp's source delete as pi already admits it leaves root files behind (`CopyMoveApp.ts:579-589`).
- **The free-space check and link check are blind.**
  - `du -sk` as pi (`CopyMoveApp.ts:52-53`) hits unreadable folders.
  - `findExternalLinks` skips folders it cannot read (`InstanceCopy.ts:59-63`).
- **Backup and restore fail.**
  - `borg create` runs as pi (`backupMonitor.ts:189`), so it hits the same files.
  - `borg info`/`extract` also run as pi (`:420-421`, `:448-452`), and a restore as pi cannot bring the
    owners back.
  - Not yet seen on the pool only because testMode skipped borg until b6dc1e7.

This is a product bug, not a test artifact. Production uses the same images, the same bind mounts and the
same Engine user (app-kolibri `compose.yaml` has no `user:`).

## 2. Proposed design

**One helper, not several.** Reasons:
- one sudoers line;
- one place for the path checks every verb needs;
- one log format;
- one version shipped with the Engine.

Splitting it would not reduce privilege, because every verb is confined the same way. It is a bash script
like `idea-erase-disk`, about 300 lines.

**Subcommands.** Arguments are positional with an exact count. The helper builds all paths itself.

| Subcommand | What it runs (as root) | Replaces (Engine) |
|---|---|---|
| `size <root> <id>` | `du -sk -x -- <inst>` | `directoryBytes` `CopyMoveApp.ts:52` (instance part) |
| `copy <srcRoot> <srcId> <dstRoot> <dstId>` | `rsync -aHAX --numeric-ids -x --info=progress2 --no-inc-recursive -- <src>/ <dst>/` | instance rsync `:307` (copy), `:543` (move) |
| `send <srcRoot> <srcId> <host> <dstRoot> <dstId>` | the same rsync to `pi@<host>:.` (cross-Pi, below) | cross-engine `:305` mkdir and `:307`/`:543` |
| `receive <dstRoot> <dstId> <rsync server args…>` | creates `<dst>`, then `rrsync -wo <dst>` | receiving side only, run through `--rsync-path` |
| `delete <root> <id>` | `rm -rf --one-file-system -- <inst>` | move source removal `:587`; partial cleanup `:431-432` (remote: `ssh pi@host sudo -n … delete`) |
| `borg-init <bdev> <id>` | `borg init --encryption=none -- <repo>` | `backupMonitor.ts:167` |
| `borg-info <bdev> <id>` | `borg info --json --last 1 -- <repo>` (JSON on stdout) | `:420-421`/`:449`; repo-exists checks `:162`, `:490` |
| `borg-create <bdev> <id> <archive> <srcRoot>` | `borg create --numeric-ids -- <repo>::<archive> <inst>` | `:189` |
| `borg-extract <bdev> <id> <archive> <strip> <dstRoot>` | `borg extract --numeric-ids --strip-components N` into a fresh staging folder on the target disk, check that only `<id>` came out, then `mv` into place | `:451` |

Every borg call sets `BORG_RELOCATED_REPO_ACCESS_IS_OK=yes` and
`BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes`. Backup Disks move between Pis and change sdX letters, and
non-interactive borg aborts on those prompts (the current code has the same latent problem) [M].

`--numeric-ids` keeps uid 999 as 999 on every Pi. By name it would map to the host's `systemd-journal`.

**How the Engine calls it.**
- It uses an argv array, never a shell string: `sudo -n /usr/local/sbin/idea-app-data copy sdb1
  kolibri-grade5a-001 sdc1 vqex2m781czu104tzkp`.
- `rsync.ts` gets a helper mode: `spawn('sudo', ['-n', HELPER, 'copy' | 'send', …])`.
  - Progress parsing stays the same.
  - `registerProcess` cancel still works, because sudo passes SIGTERM on to the child.
- backupMonitor swaps its existing `BorgRunner` (`:418`) for a helper runner.
- Cross-Pi `send` runs this, built entirely inside the helper from checked tokens:
  ```
  rsync -aHAX --numeric-ids -x --info=progress2 --no-inc-recursive \
    -e 'runuser -u pi -- ssh -o StrictHostKeyChecking=no -o BatchMode=yes' \
    --rsync-path='sudo -n /usr/local/sbin/idea-app-data receive sdc1 <newId>' \
    -- /disks/sdb1/instances/<srcId>/ pi@<host>:.
  ```
  - `runuser -u pi` keeps pi's ssh key and known hosts.
  - On the target, the helper hands rsync's server arguments to **`rrsync -wo <dst>`**. That is rsync's own
    restricted mode, already at `/usr/bin/rrsync` on idea01/03/04. It allows only a receiving server
    confined to `<dst>`, which rules out `--sender`, other paths and `-e`.

**The sudoers line** goes in `11-engine-files`, next to `pi ALL=(root) NOPASSWD:
/usr/local/sbin/idea-erase-disk` (`11-engine-files.sudoers:34`):
```
#   app data     /usr/local/sbin/idea-app-data (idea#168): no argument list; the helper
#                validates subcommand, device, instance id, archive, host and paths itself
pi ALL=(root) NOPASSWD: /usr/local/sbin/idea-app-data
```

Why the arguments are checked inside the helper and not as sudoers wildcards:
- In sudoers, `*` also matches spaces, `/` and `..` (the file's own header says so). A pattern cannot
  express "one instance id".
- rsync and borg accept options that run arbitrary commands (`-e`, `--rsync-path`, `--files-from`, borg
  `--rsh`). Any wildcarded rsync or borg line is therefore full root.

**How it refuses bad input.** It exits 2 with `refused: <reason>` on stderr. The Engine copies that into the
Operation error.
- Exact argument count per subcommand. No options are accepted from the caller.
- Regexes:
  - root: `^(sd[a-z][12]|system)$`
  - id: `^[a-z0-9][a-z0-9-]{0,63}$`. Engine ids use the alphabet `0-9a-z` (`utils.ts:328`); names look like
    `kolibri-grade5a-001`.
  - archive: `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9-]{8,16}Z$`, the format backupInstance produces.
  - strip: `^[1-9]$`
  - host: an IPv4 address or `^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$`.

  None of these can start with `-` or contain `/` or `..`.
- **The disk must be a real, mounted Engine disk.**
  - `findmnt --mountpoint /disks/<sdX>` must show source `/dev/<sdX>` and type ext4.
  - It must not be the device of `/`, and `META.yaml` must be at its root.
  - borg verbs also need `BACKUP.yaml` on `<bdev>`.
  - `system` means `/instances/<id>`.
- **Containment.** `realpath -e <path>` must equal the path the helper built. That refuses any symlink in
  any part of the path. A copy or extract destination must not exist yet, or must be empty.
- **No links out of the slot.** The helper walks the source as root and refuses any symlink whose target,
  lexical or real, is outside `<inst>`. This is the r35 rule, now enforced where pi cannot see.
- **No shell.** Commands run as bash arrays, with `--` before every path, a fixed `PATH`, `umask 022` and
  `LC_ALL=C`. Every binary is called by its absolute path. sudo's `env_reset` strips the caller's
  environment.
- **Logging.** Every call goes to the journal: `logger -t idea-app-data -p auth.notice` with SUDO_USER, the
  subcommand, the arguments, the exit code and the duration. That includes refusals.
- A per-instance `flock` in `/run/lock` stops two helper runs on the same folder at once.

**Why this is not full root.**
- The verbs are fixed (copy, delete, borg on one repo), and every path is built from checked tokens and
  confined to instance or backup folders on mounted Engine disks.
- There is no generic exec and no caller-supplied options.
- The file is root-owned, 0755, in root-owned `/usr/local/sbin`, and installed as a copy, never a symlink.
  pi cannot edit it.

The honest leftover risk:
- pi can have root copy, delete or back up *any instance* on a docked disk. The Engine already decides those
  operations, so this adds nothing.
- `send` can push instance data to any host pi can reach by ssh. pi is in the `docker` group, which is
  already root-equivalent.

**Packaging.**
- Asset `script/build_image_assets/idea-app-data`.
- Installed by build-engine next to idea-erase-disk with `sudo install -o root -g root -m 0755 …`
  (`Engine.ts:521-524`). `installEngineSudoers` (`Engine.ts:577`) validates the sudoers line with
  `visudo -cf`.
- `script/install.sh` runs the same provisioning in local mode.
- Versioned with the Engine: `idea-app-data version` prints the Engine commit, and the Engine refuses at
  startup with a clear "ask Ops to update" message on a mismatch, as CreateFilesDisk already does for
  sudoers (`CreateFilesDisk.ts:44`).

**Test plan.**
- **Unit, script:** like `test/automated/idea-erase-disk-script.test.ts`, with fake
  rsync/borg/findmnt/rrsync on PATH and a test-only root folder that the helper ignores when EUID is 0.
  Cover every regex refusal, plus:
  - `..` and a leading `-`;
  - a symlinked `instances/`;
  - a destination that already exists;
  - a disk that is not mounted, and the system disk device;
  - an external link inside the data;
  - the wrong argument count;
  - `receive` given `--sender`;
  - `-oProxyCommand=…` as the host.
- **Unit, Engine:** argv checks at every call site (`copy-move-app.test.ts`, `copy-app-isolation.test.ts`,
  `skip-borg.test.ts`, `borg-latest-archive.test.ts`).
- **On-Pi, idea01:** idea01 has no blanket NOPASSWD, so a missing sudoers line shows up there.
  - Set up a scratch ext4 USB stick at `/disks/sdX1` with an instance holding root 0600 files, a 999 0700
    folder and www-data 0640 files.
  - Run a local copy, a cross-Pi copy idea01→idea04, a move, the partial cleanup, a backup, and a restore
    onto another disk.
  - Compare `find -printf '%U:%G %m %p'` as root between source and result.
  - Start the copied Kolibri, and Nextcloud with MariaDB.
  - Confirm rsync through `sudo` over a non-tty ssh is binary-clean (sudo `use_pty` is set on the pool).
  - Never idea02.

## 3. Rejected alternatives

- **Bare `rsync` or `borg` sudoers lines:** wildcards plus `-e`/`--rsync-path`/`--rsh` make them full root.
- **A docker-run copy helper** (`docker run -v src -v dst <rsync image>`): needs an image that is always
  available offline. The docker group is root-equivalent anyway, so it is less visible, not safer.
- **Running the whole Engine as root:** gives up the narrow sudoers model (idea#80). Every Engine bug becomes
  a root bug.
- **App copy excludes only** (e.g. skip `sessions/`): fixes Kolibri sessions only. MariaDB, Nextcloud and
  ownership stay broken.
- **chown or chmod app data to pi:** MariaDB (999) and Nextcloud (www-data) refuse to run or misbehave with
  the wrong owner or mode.
- **Forcing `user:` in compose:** most upstream images (MariaDB, Nextcloud, Kolibri) expect to start as root
  and drop privileges themselves.
- **POSIX ACLs or a shared group:** container entrypoints chown/chmod their data on start and reset them.
  It is also fragile across disks moved between Pis.

## 4. Effort, risk, and what changes in the walk

**Effort, about one developer week:**
- helper: 1.5–2 days;
- Engine call sites (rsync.ts, CopyMoveApp.ts, backupMonitor.ts, version check): 1.5–2 days;
- tests: 1–1.5 days;
- on-Pi verification: 0.5–1 day;
- Atlas rollout of the helper and sudoers line: 0.5 day.

**Risk: medium.**
- It adds a root surface, mitigated by the checks and the journal log.
- Borg repos become root-owned, so an Engine rolled back to before the helper can no longer append.
- Borg's cache moves to `/root`, so the first backup after the switch is slower once.

**What changes in the walk:**
- copy_app@43 should end Done, with no ghost instance. The harness must check that the copyApp Operation
  ended Done.
- backup_instance@98 and restore@100 run real borg (`skipBorg: false`).
- Copying, moving and backing up Nextcloud becomes possible.
- The pool needs the helper and the sudoers line installed by Atlas.
- **Blocker:** pool fixtures live under `~/idea/duration-disks` and are not mounted sd devices, so the
  helper refuses them (see the testMode audit and Q2).

## 5. Open questions for Koen

1. Do you approve **one helper with a sudoers line that has no argument list**, the same pattern as
   idea-erase-disk?
2. Pool bridge until real USB disks (testmode-audit Stage 2): should the helper also accept the pool's
   fixture root through a root-owned `/etc/idea/app-data-roots` file (Atlas sets it on the pool only; same
   code path, different root)? Or should the pool keep failing copy_app until real disks arrive?
3. Should cross-Pi `send` go to any host pi can ssh to, or only to Engine peers (a root-owned allowlist, or
   Tailscale and LAN ranges only)?
4. Is it OK that existing pi-owned borg repos turn root-owned, with the rollback limit above? Should we
   also turn on the two `BORG_*_IS_OK` settings for Backup Disks that moved between Pis?
5. Bash (like idea-erase-disk) or Python (rrsync is Python already) for the helper?
6. Should Pi OS's blanket `NOPASSWD: ALL` eventually come off production Pis? This helper is what would keep
   copy and backup working then, and idea01 already runs that way.
