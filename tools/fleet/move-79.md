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
| `--preflight` | no Pi state (only the untracked `.zz-move-79.ts` upload, skipped when identical) | Checks claims, protected-Pi list, store 2VroE, Engine HEAD (`--engine-sha`), pm2 engine online as pi, **fixture mode**, `/etc/idea/app-data-roots`, `sudo -n losetup`, the scratch image on both Pis, the scratch fs on the root disk (not Disk B/WD), free space, temperature ≤ 75 °C, `kid-kolibri-demo` running on idea03, and `moveAppCrossEngine` |
| `--create-disks` | yes | Runs preflight (it must pass). Per Pi: picks a free `idea-test-N` slot, creates a sparse image `$SCRATCH/img/<id>.img` (default 4 GB), formats it ext4 (pi-owned root), attaches it with `sudo -n losetup -f --show` and checks that its BACK-FILE is our image, mounts it on the slot, writes META.yaml (`diskId: mv289-src` / `mv289-dst`, `isHardwareId: false`), and fires the testMode sentinel. The source also gets the throwaway App `mv79web` with instance `mv289-web` (pinned `nginx:alpine` digest, `./data` bind only, 16 MB payload). The script then waits until the disk is docked and the instance is Running |
| `--move` | yes | Sends `moveApp <id> mv289-src mv289-dst` to the source Engine. It verifies the op code (MOVED / SOURCE_NOT_REMOVED / SOURCE_CHANGED), checks the new instance is Running on `mv289-dst`, compares the file list **and** sha256 of every file, and checks HTTP 200 on the instance port |
| `--move-back` | yes | The same check in the other direction: `moveApp <newId> mv289-dst mv289-src`, sent to the target Engine |
| `--teardown` | yes | Removes the sentinel (the Engine undocks) and waits for the undock. It then unmounts our slot, runs `sudo -n losetup -d` on **our own recorded /dev/loopN**, but only if that device still backs our image, and runs `mv` on image + state into `$SCRATCH/quarantine-<stamp>/`. It reports leftover `org.idea.mv79` containers and does not remove them |

Every mutating mode needs `--ref "<who authorised, time + link>"`. Each step writes a marker in
`~/.local/state/idea-move-79/<run>/`, so re-runs skip finished steps. Evidence goes to `evidence-<stamp>-<mode>/`.

## Guards (all modes, before any ssh)
- Both Pis are claimed by `$BOT_NAME` in fleet-state. Otherwise the script stops **before contacting any Pi**.
- Never wizardly-hugle/idea (100.115.60.6, 192.168.0.231), idea01 (golden), idea02, or any golden, production,
  kit-engine or kit Pi. Source ≠ target.
- Disk ids and the instance must carry the scratch prefix (`mv289-`). An instance name that looks like
  `kid-`, `kolibri`, `i159`, `idea166` or `nextcloud` is refused.
- On the Pi: the store is `automerge:2VroE…`. The image file sits on the Pi's own root fs, never on Disk B
  (3813430-532011020), the WD (20070Q450002) or another external disk. Only `/dev/loopN` devices this script
  created are ever mounted or detached. The script never runs `losetup -D` or `rm -r`, and the boot disks (serials in
  field-usage-rollout.md) are never selected.
- The hands-off containers (`kid-kolibri-demo*`, `idea166-*`, `nextcloud-files-b-001`, `idea-hub-sidecar`)
  are snapshotted (id|name|state|StartedAt) at the start of each mode, and that snapshot must be identical after every step.
  `kid-kolibri-demo` must be running on idea03. The script never runs docker stop/rm/compose against them.
- Temperature: pause above 75 °C and resume below 65 °C. A watcher logs the temperature every 60 s during a move.

## Fixture mode (needed before `--create-disks`)
A live Engine (testMode off) only docks `/dev/engine` sd* devices. It ignores loop devices and `idea-test-N`
(deviceNames.ts, idea#105). Loop App Disks dock only on an Engine started with
`IDEA_TEST_MODE=true IDEA_DISKS_ROOT=/home/pi/idea/duration-disks IDEA_WATCH_DIR=/home/pi/idea/duration-watch`,
which is how the duration pool and Axle's #343 loop fixtures did it. **This script never changes the Engine or its pm2 env.**
Preflight reports the mode, and switching is Axle's call. Note that on idea03 a fixture-mode Engine no longer
watches `/dev/engine`, so Disk B (`diskb202610301247`, `nextcloud-files-b-001`) would drop out of the store
while that mode is on.

## Run order (after Kid's #159 run 3 releases both Pis)
```
BOT_NAME=Atlas tools/fleet/update-fleet-state.sh idea03 claim "Atlas #289 move-79 loop proof" && \
BOT_NAME=Atlas tools/fleet/update-fleet-state.sh idea04 claim "Atlas #289 move-79 loop proof"   # + status testing, push
BOT_NAME=Atlas tools/fleet/move-79.sh --preflight    --source idea03 --target idea04 --engine-sha <#289 sha>
BOT_NAME=Atlas tools/fleet/move-79.sh --create-disks --source idea03 --target idea04 --engine-sha <#289 sha> --ref "<ref>"
BOT_NAME=Atlas tools/fleet/move-79.sh --move         --source idea03 --target idea04 --ref "<ref>"
BOT_NAME=Atlas tools/fleet/move-79.sh --move-back    --source idea03 --target idea04 --ref "<ref>"
BOT_NAME=Atlas tools/fleet/move-79.sh --teardown     --source idea03 --target idea04 --ref "<ref>"
```
Then: Engines back to main and out of fixture mode (Axle), release the claims, set status idle.

Tests: `tools/fleet/move-79.test.sh` (fake ssh/Engine sandbox; covers guards, preflight failures, and a full
create → move → move-back → teardown, plus a guard trip when kid-kolibri-demo's StartedAt changes mid-move).
