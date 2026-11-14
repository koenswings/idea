# move-79.sh: two-Engine Move proof on loop-file scratch App Disks

`tools/fleet/move-79.sh` runs the cross-Engine `moveApp` (agent-engine-dev#289, idea#79) between two **claimed
pool Pis**. It uses loop-file scratch App Disks instead of physical disks. The default for the #289 proof is
**source idea03 (100.126.117.80) → target idea04 (100.108.39.45)**. Override with `--source/--target` or
`MOVE_SOURCE/MOVE_TARGET`; hosts come from fleet-state (`tailscale`), or from `SRC_HOST/TGT_HOST`.

Files: `move-79.sh` (box side), `move-79-remote.sh` (Pi side, sent over ssh as `bash -s`, never installed),
`move-79-engine.ts` (store reader uploaded as the untracked `script/.zz-move-79.ts`), and `move-79.test.sh`
(offline tests).

## Modes

| Mode | Changes | What it does |
|---|---|---|
| `--preflight` | no Pi state (only the untracked `.zz-move-79.ts` upload, skipped when identical) | Checks claims, protected-Pi list, live store-url.txt still 2VroE, fixture store **not** 2VroE (scratch), Engine HEAD (`--engine-sha`, default the #289 tip `10ee458`), pm2 engine online as pi, **fixture mode**, the three **window prerequisites** (below; `TODO` = `--setup-window` does it, `FAIL` = setup refuses), a read-only `sudo -n -l` (below), `nginx:alpine` present on both Pis **with the same image ID** (and equal to `--image-id` if given), the scratch fs on the root disk (not Disk B/WD), free space, temperature ≤ 75 °C, `kid-kolibri-demo` running on idea03, and `moveAppCrossEngine` |
| `--setup-window` | yes (reversible, restored by `--teardown`) | Runs preflight; any blocking FAIL stops it. Per Pi: records the originals box-side, backs them up on the Pi to `$SCRATCH/quarantine-window-<stamp>/`, then makes `/home/pi/idea/duration-disks` root-owned and not group/other writable, creates the slot dir, appends **only** the slot line to `/etc/idea/app-data-roots`, and sets `peerAccess: true` in the Engine `config.yaml`. Each change is written to `$SCRATCH/window.win` *before* it is made. Saves the `kid-kolibri-demo` baseline for the release check. **Never touches an SSH key** |
| `--start-fixture` | yes (pm2 env; reversible by `--stop-fixture`) | After `--setup-window`. Writes `<engine>/store-identity-scratch/` (copy of `store-template.json` + a fresh Automerge URL shared by both Pis) and `<engine>/config.fixture.yaml` (`storeIdentityFolder` / `storeDataFolder` pointed at the scratch dirs). Restarts `engine` with `IDEA_TEST_MODE=true`, `IDEA_DISKS_ROOT`, `IDEA_WATCH_DIR`, `IDEA_CONFIG_FILE=./config.fixture.yaml`, `IDEA_STORE_DIR=./store-data-scratch`. **Refuses to start if that store URL is `automerge:2VroE…` (or 3Vvv/6f8m).** Never rewrites the live `store-identity/store-url.txt`. |
| `--load-image` | image only (optional) | `docker save nginx:alpine` on the source piped into `docker load` on the target, then `docker image inspect nginx:alpine` on the target must show the source's image ID. Skipped if the target already has `nginx:alpine` with the same ID. If the target has `nginx:alpine` with a **different** ID it stops and reports, and never overwrites the tag. Only a plain `repo:tag` is accepted. Nothing is restarted, and the hands-off guard runs before and after |
| `--create-disks` | yes | Needs `--setup-window` on both Pis, then runs preflight (it must pass). Per Pi: uses the slot recorded by `--setup-window`, creates a sparse image `$SCRATCH/img/<id>.img` (default 4 GB), formats it ext4 (pi-owned root), attaches it with `sudo -n losetup -f --show` and checks that its BACK-FILE is our image, mounts it on the slot, writes META.yaml (`diskId: mv289-src` / `mv289-dst`, `isHardwareId: false`), and fires the testMode sentinel. The source also gets the throwaway App `mv79web` with instance `mv289-web` (compose `image: nginx:alpine`, `pull_policy: never`; image IDs are only compared by preflight and never written to compose, `./data` bind only, 16 MB payload). The script then waits until the disk is docked and the instance is Running |
| `--move` | yes | Sends `moveApp <id> mv289-src mv289-dst` to the source Engine. It verifies the op code (MOVED / SOURCE_NOT_REMOVED / SOURCE_CHANGED), checks the new instance is Running on `mv289-dst`, compares the file list **and** sha256 of every file, and checks HTTP 200 on the instance port |
| `--move-back` | yes | The same check in the other direction: `moveApp <newId> mv289-dst mv289-src`, sent to the target Engine |
| `--teardown` | yes | Removes the sentinel (the Engine undocks) and waits for the undock. It then unmounts our slot, runs `sudo -n losetup -d` on **our own recorded /dev/loopN**, but only if that device still backs our image, and runs `mv` on image + state into `$SCRATCH/quarantine-<stamp>/`. It reports leftover `org.idea.mv79` containers and does not remove them. It then runs the window restore on each Pi (removes the slot dir only if the window created it and it is empty and unmounted, restores the fixture root owner/mode, copies the backup over app-data-roots, writes `config.orig` back over `config.yaml` in place), verifies sha256 + `owner:group mode type` against the originals both on the Pi and from a fresh box-side probe, and stops on any mismatch. Evidence: `winrestore-<pi>.txt`, `probe-<pi>-after.txt` |
| `--stop-fixture` | yes (pm2 env) | After `--teardown`. `pm2 delete` + `pm2 start pm2.config.cjs` so fixture env is cleared. Live `store-url.txt` must still be 2VroE and is not written. Scratch identity/data dirs are left in place (not deleted). |
| `--release-check` | no (read-only) | After `--stop-fixture` (normal mode). Per Pi: pm2 engine online as pi; **normal mode** (no `IDEA_TEST_MODE`/`IDEA_DISKS_ROOT`/`IDEA_WATCH_DIR`); Engine HEAD contains `9569e72` (main or newer); app-data-roots, fixture root and `config.yaml` equal the originals; no window state; no scratch disk state. On idea03: **Disk B (`diskb202610301247`) docked and `nextcloud-files-b-001` Running on it**, and `kid-kolibri-demo` is **unchanged** (same id, state, StartedAt as the `--setup-window` baseline) and running. Writes `evidence-*-release-check/release-check.txt`. Exit 0 = PASS |

Every mode except `--preflight` and `--release-check` needs `--ref "<who authorised, time + link>"`. Each step writes a marker in
`~/.local/state/idea-move-79/<run>/`, so re-runs skip finished steps. Evidence goes to `evidence-<stamp>-<mode>/`.

## Guards (all modes, before any ssh)
- Both Pis are claimed by `$BOT_NAME` in fleet-state. Otherwise the script stops **before contacting any Pi**.
- Never wizardly-hugle/idea (100.115.60.6, 192.168.0.231), idea01 (golden), idea02, or any golden, production,
  kit-engine or kit Pi. Source ≠ target.
- Disk ids and the instance must carry the scratch prefix (`mv289-`). An instance name that looks like
  `kid-`, `kolibri`, `i159`, `idea166` or `nextcloud` is refused.
- On the Pi: the live `store-url.txt` stays `automerge:2VroE…`. In fixture mode the Engine opens a scratch store instead. The image file sits on the Pi's own root fs, never on Disk B
  (3813430-532011020), the WD (20070Q450002) or another external disk. Only `/dev/loopN` devices this script
  created are ever mounted or detached. The script never runs `losetup -D` or `rm -r`, and the boot disks (serials in
  field-usage-rollout.md) are never selected.
- The hands-off containers (`kid-kolibri-demo*`, `idea166-*`, `nextcloud-files-b-001`, `idea-hub-sidecar`)
  are snapshotted (id|name|state|StartedAt) at the start of each mode, and that snapshot must be identical after every step.
  `kid-kolibri-demo` must be running on idea03. The script never runs docker stop/rm/compose against them.
- Temperature: pause above 75 °C and resume below 65 °C. A watcher logs the temperature every 60 s during a move.

## Window prerequisites (checked by `--preflight`, set by `--setup-window`, restored by `--teardown`)
1. **`/etc/idea/app-data-roots` on both Pis.** It must be a regular file (not a symlink), `root:root 0644`. It must list
   the slot as an absolute path, e.g. `/home/pi/idea/duration-disks/idea-test-N`: no trailing slash, no `.`/`..`, no
   symlink anywhere in the path. `/home/pi/idea/duration-disks` must be root-owned and not group/other writable. If the file
   is missing, a symlink or has the wrong owner/mode, preflight FAILs and setup refuses: the script never creates
   or replaces that file. Setup appends only the slot line (and a newline first if the file lacks a trailing one). Teardown
   copies the backup back and restores the exact content, mode and owner, plus the original owner/mode of the
   fixture root.
2. **`peerAccess: true`** in the Engine `config.yaml` (testMode defaults it to off). Setup backs the file up and sets the
   value: it replaces an existing `peerAccess:` line or inserts one under `settings:`, writing in place so the inode, owner
   and mode stay the same. Teardown writes the exact original back. If pm2 sets `IDEA_CONFIG_FILE` to another file,
   preflight FAILs, except `--start-fixture`'s own `./config.fixture.yaml`.
3. **Peer keys between idea03 and idea04: checked only.** Through the store helper, each Engine's
   `peerAccess.authorized` must list the other Engine, and each Pi's `/etc/ssh/idea_authorized_keys/pi` (if readable
   as pi) must hold the other Engine's `idea_engine_ed25519.pub` key. **The script never adds or changes an SSH key.** If
   the keys are missing, preflight FAILs with "peer keys between idea03 and idea04 are NOT in place: … ask Steve".
   (While `peerAccess` is on, the Engine syncs peer keys itself. That is Engine behaviour, not the script.)

Setup and restore need `sudo -n` for `/usr/bin/{chown,chmod,tee,cp,install,rmdir}`. Preflight runs a read-only `sudo -n -l` as pi on
both Pis and saves it as `sudo-l-<pi>.txt`. An `ALL` command rule with `NOPASSWD`, runnable as root/ALL, passes. Otherwise every needed command must appear
in a `NOPASSWD` entry with no arguments or `*`. If any are missing, preflight FAILs and lists them, marking `(only with fixed arguments)` and
`(negated)` where that applies. `PASSWD:` entries and rules for other run-as users don't count. `winsetup` checks each command again with
`sudo -n -l <cmd>`. **The script never adds or changes sudoers.**
A half-finished setup stops with a message, is recorded on the Pi, and `--teardown` restores it. A re-run of `--setup-window`
refuses until then.

## Fixture mode (needed before `--create-disks`)
A live Engine (testMode off) only docks `/dev/engine` sd* devices. It ignores loop devices and `idea-test-N`
(deviceNames.ts, idea#105). Loop App Disks dock only on an Engine started with
`IDEA_TEST_MODE=true IDEA_DISKS_ROOT=/home/pi/idea/duration-disks IDEA_WATCH_DIR=/home/pi/idea/duration-watch`.

`--start-fixture` turns that mode on **and** points the Engine at a scratch Automerge store via
`IDEA_CONFIG_FILE=./config.fixture.yaml` (identity folder `store-identity-scratch`, data folder
`store-data-scratch`). Both Pis in the run share the same new store URL so cross-Engine `moveApp` still
works. The live `store-identity/store-url.txt` stays `automerge:2VroE…` and is never rewritten. The
script **refuses to start fixture mode** if the store the Engine would open is 2VroE (or another known
fleet store). That is the 13 Nov 2026 lesson: a fixture-mode Engine on idea03 that kept 2VroE treated
Disk B as gone (`usbDeviceMonitor.ts` forces `actualDevices=[]` in testMode and
`reconcileStartupDocks` then undocks every non-system disk into the shared store).

`--stop-fixture` returns each Engine to `pm2.config.cjs` (normal mode, live 2VroE). `--release-check`
then verifies Disk B (`diskb202610301247`) and `nextcloud-files-b-001` are docked/Running again.

## Run order (after Kid's #159 run 3 releases both Pis; scenario A + the reverse only)
```
BOT_NAME=Atlas tools/fleet/update-fleet-state.sh idea03 claim "Atlas #289 move-79 loop proof" && \
BOT_NAME=Atlas tools/fleet/update-fleet-state.sh idea04 claim "Atlas #289 move-79 loop proof"   # + status testing, push
# 1. Atlas, Engines still in normal mode:
BOT_NAME=Atlas tools/fleet/move-79.sh --preflight    --source idea03 --target idea04 --engine-sha 10ee458   # expect TODOs + the HEAD/fixture-mode FAILs only
BOT_NAME=Atlas tools/fleet/move-79.sh --setup-window --source idea03 --target idea04 --engine-sha 10ee458 --ref "<ref>"
# 2. Atlas: start fixture mode against a scratch store (refuses 2VroE). Deploy the Engine SHA first if needed.
BOT_NAME=Atlas tools/fleet/move-79.sh --start-fixture --source idea03 --target idea04 --engine-sha 10ee458 --ref "<ref>"
# 3. Atlas:
BOT_NAME=Atlas tools/fleet/move-79.sh --preflight    --source idea03 --target idea04 --engine-sha 10ee458   # must be ALL PASS (except the image on idea04, see --load-image)
BOT_NAME=Atlas tools/fleet/move-79.sh --load-image   --source idea03 --target idea04 --ref "<ref>"          # optional
BOT_NAME=Atlas tools/fleet/move-79.sh --create-disks --source idea03 --target idea04 --engine-sha 10ee458 --ref "<ref>"
BOT_NAME=Atlas tools/fleet/move-79.sh --move         --source idea03 --target idea04 --ref "<ref>"
BOT_NAME=Atlas tools/fleet/move-79.sh --move-back    --source idea03 --target idea04 --ref "<ref>"
BOT_NAME=Atlas tools/fleet/move-79.sh --teardown     --source idea03 --target idea04 --ref "<ref>"          # disks out + window restored exactly
# 4. Atlas: back to normal mode (live 2VroE). Engines should be on 9569e72 or newer for the release check.
BOT_NAME=Atlas tools/fleet/move-79.sh --stop-fixture  --source idea03 --target idea04 --ref "<ref>"
# 5. Atlas:
BOT_NAME=Atlas tools/fleet/move-79.sh --release-check --source idea03 --target idea04
```
Then release the claims and set status idle. Attach `release-check.txt`, the `winsetup-*`/`winrestore-*` files and the
move evidence to #289.

## Not reversed by the script
- A loaded image (`--load-image`) stays on idea04 as `nginx:alpine`. Removing it is a separate, explicit step.
- What the Engine does itself while `peerAccess` is on (peer-key sync into `/etc/ssh/idea_authorized_keys/pi` and
  `/etc/idea/peer_known_hosts`, and the Engine key it publishes). The script only checks it.
- Engine code deploys (this script still does not checkout an Engine SHA). `--start-fixture` / `--stop-fixture` only
  change pm2 env and write the scratch identity/config; they never rewrite the live `store-url.txt`.
- Kept on purpose: the `quarantine-<stamp>/` and `quarantine-window-<stamp>/` dirs, the untracked `script/.zz-move-79.ts`, and any
  leftover `org.idea.mv79` containers (reported).

Tests: `tools/fleet/move-79.test.sh` (fake ssh/Engine sandbox; covers guards, preflight failures, and a full
setup-window → start-fixture → create → move → move-back → teardown → stop-fixture → release-check, plus a 2VroE refusal and a preflight FAIL when fixture mode would use the shared store, plus a guard trip when kid-kolibri-demo's StartedAt changes
mid-move). Each window prerequisite has pass and fail cases (symlink/missing/wrong-mode app-data-roots, symlinked
fixture root, `sudo -n -l` pass/partial/fail/negated, foreign `IDEA_CONFIG_FILE`, missing peer keys in the store or in authorized_keys). There are also exact-restore checks
(sha256 + stat, a file with no trailing newline, a config with no `peerAccess` line, a half-finished setup), image-ID compare and pin, and `--load-image` (load, same-ID skip, different-ID refusal). The
owner part of the restore runs as the test user; a real root:root restore needs a Pi.
