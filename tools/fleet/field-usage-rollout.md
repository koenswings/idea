# Field-usage rollout plan (idea#416)

**Status:** Plan plus first live pool-Pi run (idea03, 2026-11-10) · **Maintained by:** Atlas · 2026-11-10
**Source:** [proposal](../../proposals/2026-11-09-field-usage-monitoring.md) §7.5, §10, §12, §14 Atlas;
[idea#416](https://github.com/koenswings/idea/issues/416),
[idea#412](https://github.com/koenswings/idea/issues/412),
[idea#375](https://github.com/koenswings/idea/issues/375) U-1 to U-9,
[idea#374](https://github.com/koenswings/idea/issues/374).

Do not treat this file as permission to touch idea, a kit, golden idea01, or
a Pi another bot has claimed. Kits stay pinned at Engine `adfd9d3` and
read-only until Koen approves idea#374.

ACL paste and tests: [`field-usage-acl.md`](field-usage-acl.md).
Post-U-step checklist and dry-run script: [`field-usage-u-steps.md`](field-usage-u-steps.md), [`field-usage-after-u-steps.sh`](field-usage-after-u-steps.sh).
Runtime probe: [`probe-field-usage-acl.sh`](probe-field-usage-acl.sh).
Restricted-key proof (pool Pi): [`prove-usage-export-key.sh`](prove-usage-export-key.sh).

After **every** Pi that this rollout changes, run
`tools/fleet/check-fleet-health.sh --pi <name>` (and `--origin` when claims
may have moved). A claimed or non-idle Pi is reported but does not fail the
check; still read the report before releasing the claim.

## 0. What is blocked today (2026-11-10)

Recorded so the next run does not rediscover it:

- idea#375 U-1 to U-9 are Koen's. Atlas does not ask him; Steve presents
  them when Koen is ready.
- No agent-engine-dev usage-export helper branch yet. Main and the pool
  Pis are `idea-app-data` v5; open engine PR #307 claims v6; idea#401
  was moved to v7 in that PR's text (no PR yet). The next free helper
  version for idea#412 is **v7**. The proof script uses
  [`idea-usage-export.stub.sh`](idea-usage-export.stub.sh) until Axle's
  binary exists.
- No `app-usage-dashboard` repo or agent-app-dev branch yet (idea#414).
  Sidecar registration waits on Kid's App and on U-3. Do not run sidecar
  install steps until those U-steps exist.
- `usageMonitoring` toggle: `tools/fleet/usage-monitoring.sh` (idea#411; waits on the Engine helper `idea-usage-settings` being installed on the Pi).
- Fleet Pis were still untagged as of 2026-11-10 21:56 Europe/Brussels
  (`tailscale status --json`: idea01–04 and idea user-owned; kits already
  `tag:idea`). T-c runbook and check-only script:
  [`tag-fleet-idea-tc.md`](tag-fleet-idea-tc.md),
  [`tag-fleet-idea.sh`](tag-fleet-idea.sh). Not applied. idea03 and idea02
  expire 2026-12-02 14:36 Europe/Brussels.
- Live ACL text is not in git (T-b). The paste in `field-usage-acl.md`
  is a merge-in block; substitute the live admin source if it is not
  `group:admins`.
- `hub-to-idea` probe waits on the sidecar (U-3) and on Step B (U-4).

Kid released idea03 and idea04 in fleet commit `1787bf6`
(2026-11-10 21:39:57 Europe/Brussels). Atlas claimed only idea03
(`d8b9dbb`, 21:45:51 Europe/Brussels) and released it (`e1f73cc`,
21:50:50 Europe/Brussels). idea04 was not claimed. Kid's scratch on
idea03 at `/home/pi/kid-quarantine/i159-run2-20261110-213804` was left
alone. The WD SSD / Disk B on idea04 was not touched.

### 0.1 Live idea-to-idea probe (idea03, 2026-11-10 21:46:35 Europe/Brussels)

`probe-field-usage-acl.sh idea-to-idea --from-pi idea03` (timeout 3s).
Source idea03 `100.126.117.80`. Default dests: idea01 and idea04
(kits and wizardly-hugle omitted). Expected: every listed port
unreachable. Overall script result: **8 passed, 6 failed** (exit 1).
This is the current baseline, not an ACL regression: the nodes are
still untagged (T-c).

| dest | ip | 22 | 80 | 443 | 3333 | 3334 | 8080 | 8081 |
|---|---|---|---|---|---|---|---|---|
| idea01 | 100.99.231.94 | opened (fail) | opened (fail) | refused (pass) | refused (pass) | refused (pass) | opened (fail) | refused (pass) |
| idea04 | 100.108.39.45 | opened (fail) | opened (fail) | refused (pass) | refused (pass) | refused (pass) | opened (fail) | refused (pass) |

`refused` here means nothing accepted the TCP handshake (likely nothing
listening), not a proven Tailscale deny. `opened` on 22, 80 and 8080
shows pool Pis can still reach each other's SSH, HTTP and Console.
After T-c and the Step A/B ACL, a repeat of this probe should show
every port unreachable, including 22/80/8080.

### 0.2 Live restricted-export proof (idea03, 2026-11-10 21:47–21:48 Europe/Brussels)

`prove-usage-export-key.sh --yes --pi idea03`. `export_kind=stub`
(no `/usr/local/sbin/idea-usage-export` on the Pi). Throwaway ed25519
pinned with `restrict,from="<box Tailscale IPv4>",command="/usr/local/sbin/idea-usage-export"`.
Keys were not printed. Temperature at start 45.2 °C.

| test | result | detail |
|---|---|---|
| operator-ssh-after-reload | pass | normal key still accepted |
| allowed-since | pass | `since 2026-01-01` accepted (stub JSON) |
| refused-other-command | pass | `id` refused, rc=1, stderr `idea-usage-export: refused` |
| refused-shell | pass | empty command refused, rc=1 |
| refused-other-source | pass | sshd: correct key but not from a permitted host (`host=127.0.0.1`, required=box Tailscale IPv4); client `Permission denied (publickey)` |
| restored | pass | drop-in restored to the original three-path `AuthorizedKeysFile`; proof files quarantined |
| operator-ssh-after-restore | pass | normal key works after restore |

The first script JSON marked `refused-other-source` as fail because
`src_rc=$?` was assigned inside `$(...)`, so the parent kept `src_rc=0`.
sshd and the client stderr show the connection was refused. The capture
bug is fixed in `prove-usage-export-key.sh`; the Pi was not mutated a
second time. Corrected score: **7/7 pass**.

After restore (verified): live `10-idea-peer.conf` matches the pre-proof
file (mtime still 2026-10-30); `/etc/ssh/idea_usage_keys` and
`/usr/local/sbin/idea-usage-export` are gone, with
`.quarantine-20261110T204713Z` siblings left in place. Kid's quarantine
path is unchanged. Operator SSH works.

`check-fleet-health.sh --pi idea03` (no `--alert`; HOLD and PAUSED files
left in place) at 21:50 Europe/Brussels: reachable, console HTTP 200 on
8080, engine online as `pi` (0 restarts), disk 35%, dhcp ok, no
problems. Then the claim was cleared and status set to idle.

## 1. Koen's U-steps (idea#375)

Steve presents these; Atlas prepares everything around them.

| Item | What | Atlas around it |
|---|---|---|
| U-1 | Create `tag:idea-hub`. Do not retag idea. | Paste is Step A in `field-usage-acl.md`. |
| U-2 | Grant admins access to `tag:idea-hub` first, before the node exists. | Same Step A save. |
| U-3 | Create one tagged, non-ephemeral auth key for this sidecar only. Store it as a 0600 file; tell Steve only the path. | Atlas never prints or copies the key into git or chat. |
| U-4 | After the sidecar is registered, add `tag:idea-hub → tag:idea` on tcp/22 only (plain OpenSSH). | Step B in `field-usage-acl.md`, including the tests. Then run `probe-field-usage-acl.sh hub-to-idea`. |
| U-5 | After the admin grant (and when the node is registered), confirm Console and MilkWise on 3333 and 3334 still work. | Atlas does not probe those ports on idea (production, MilkWise untouched). Koen confirms. |
| U-6 | Recovery note: if sidecar state is lost, re-register with the U-3 key and give the new node its previous 100.x IPv4. | Atlas records that IPv4 in the runbook once the node exists (not a secret). |
| U-7 | Scorecard thresholds. | No Ops action. |
| U-8 | Who tells the schools. | No Ops action. |
| U-9 | Who besides Koen may open the programme dashboard. | No Ops action. Pin the web port off 80, 3333, 3334 and 8081 regardless. |

Separately, later, on idea#374 (not #375): approve the field update that
moves kits off `adfd9d3`.

Related, not part of U-1–U-9: T-b (read the live ACL so the paste matches
the admin source) and T-c (tag idea01, idea03, idea04 and idea02 with
`tag:idea` via console Edit tags, then disable key expiry; idea02 and
idea03 before 2026-12-02 14:36 Europe/Brussels). Defer tagging `idea`
until Koen's OK / idea#374. See [`tag-fleet-idea-tc.md`](tag-fleet-idea-tc.md).

## 2. Sidecar registration

Only after U-1, U-2 and U-3, and only after Kid's `app-usage-dashboard`
can run as an Engine App (idea#414). Preferred: the Engine runs the App
from idea's system disk (open question for Axle on #414). Fallback: a
small App Disk that stays docked and survives the 05:00 reboot. No
hand-placed compose files.

1. Scratch-install the App on **idea03 or idea04**, whichever is idle and
   unclaimed. Never idea01 (golden, merged main only). Never idea02.
   Never idea / wizardly-hugle first.
2. Claim: `BOT_NAME=Atlas tools/fleet/update-fleet-state.sh <pi> status testing`
   and `BOT_NAME=Atlas tools/fleet/update-fleet-state.sh <pi> claim 'Atlas idea#416 sidecar scratch'`.
3. The sidecar is a userspace Tailscale node, tagged `tag:idea-hub`,
   using the U-3 key from the path Steve was told. State lives under the
   App's `./data` so it survives 05:00. It must not mount the host
   `tailscaled.sock`.
4. Watchdog: if the sidecar does not see itself online, restart it and
   record a `collectorGap`, never kits going dark.
5. Record the sidecar's 100.x IPv4 (runbook + fleet note). That is the
   address written into each kit `from=` line during #374.
6. `check-fleet-health.sh --pi <name>`. Release the Pi (restore, pm2 as
   `pi`, claim cleared, status idle).
7. Prepared only, not run until U-3 exists: the install steps above.
   Do not register a second `tag:idea-hub` node.

## 3. Record the sidecar IP

Once the node exists:

- Write the 100.x IPv4 into this runbook and into a fleet-state note
  (not a secret).
- U-6: if state is lost, Koen assigns that same IPv4 to the replacement
  node in the admin console so existing `from=` lines keep working.
- The node state directory and `./data/keys` are listed in
  `x-app.backup` `exclude: [keys, tailscale]` (idea#389). They go only
  to idea's encrypted Borg repo, restored on idea only. Never restore
  them onto another host (that would mint a second `idea-hub` with the
  same identity).

## 4. Scratch App on idea03 or idea04

Same claim rules as §2. This is also where helper v7 and the restricted
export key are proved (`prove-usage-export-key.sh`, idea#412):

- Throwaway key generated on the box, `from=` pinned to the **box**
  Tailscale IPv4 (stand-in for the sidecar IP).
- Use Axle's helper v7 and `/usr/local/sbin/idea-usage-export` if a
  branch exists; otherwise the marked stub in
  `idea-usage-export.stub.sh`.
- Prove three things: an allowed verb works; any other command or a
  shell is refused; a different source IP is refused.
- `sync-peers` must not wipe `/etc/ssh/idea_usage_keys/pi`.
- Quarantine the key, the stub and any edited drop-in afterwards
  (`.quarantine-<utc-ts>` suffix, never `rm -rf`). Restore the drop-in
  to the exact pre-proof `AuthorizedKeysFile` line. Confirm a fresh
  operator SSH still works before closing the session.
- `check-fleet-health.sh --pi <name>`, then release.

The current image drop-in (`script/build_image_assets/10-idea-peer.conf`
in agent-engine-dev) is:

```
AuthorizedKeysFile .ssh/authorized_keys .ssh/authorized_keys2 /etc/ssh/idea_authorized_keys/%u
```

Helper v7 must extend **that same line** (Debian reads `sshd_config.d`
first and the first `AuthorizedKeysFile` wins; a later drop-in would
replace the peer file and lock operators or peers out):

```
AuthorizedKeysFile .ssh/authorized_keys .ssh/authorized_keys2 /etc/ssh/idea_authorized_keys/%u /etc/ssh/idea_usage_keys/%u
```

## 5. idea (wizardly-hugle, 100.115.60.6) — only with Koen's OK

- Production, read-only to bots until Koen says the dashboard App may
  go on idea.
- MilkWise on 3333 and 3334 is untouched. Console stays on 80 (LAN) /
  8081 (as recorded in fleet-state). The dashboard web port is pinned
  in the instance environment file and kept off 80, 3333, 3334 and 8081.
- Do not mount the host Tailscale socket. idea stays `tag:idea`.
- After install: `check-fleet-health.sh --pi wizardly-hugle` (or
  `--pi idea` if that is the fleet-state key). Confirm MilkWise and
  the Engine are still up. Atlas does not open 3333/3334 as a write.
- Stopping the dashboard App (off-switch level 3) must leave Engine
  and MilkWise running.

## 6. Helper v7 pool rollout

After Axle's helper v7 has merged and the pool-Pi proof in §4 passed.
One Pi at a time. Never two down. Pause above 75 °C, resume below 65 °C.
pm2 always as `pi`. No `pkill` / `pgrep -f`.

Order:

1. An idle, unclaimed spare: idea03 or idea04 (whichever the proof did
   not leave dirty; prefer a fresh idle Pi). Claim as Atlas, install
   helper v7 (including the drop-in and `idea-usage-export`), health
   check, release.
2. The other spare, same way.
3. **idea01 (golden) only from merged main**, after the helper v7 PR
   is on main. Never a review branch. Claim, install, health check,
   release.
4. Do not do idea02 (hold), kits, or idea here.

Do not install the production usage-pull public key on pool Pis as a
standing key. The §4 proof key is throwaway and is quarantined.

## 7. Kits, only in the approved idea#374 window

Kits: sunny-robin, happy-zebra, kind-panda. Pinned at `adfd9d3`,
read-only until then. kind-panda's router is "not yet installed".
Do not contact Justice. Record only what we observe ourselves.

The kit-side pieces travel together, one kit per window (they are
online only a few hours a day over the Johannesburg relay):

- Engine `idea-usage` sampler and hook runner (idea#411), switch left
  **off**
- helper v7, `/etc/ssh/idea_usage_keys/%u`, the updated
  `10-idea-peer.conf` line, `/usr/local/sbin/idea-usage-export`
- the usage-pull public key with
  `restrict,from="<sidecar 100.x IPv4>",command="/usr/local/sbin/idea-usage-export"`
- updated Kolibri, Nextcloud and Kiwix Apps via `updateApp` (idea#413)
- the idea#389 reboot wrapper

Rules for each kit:

1. Steve pinged at START and FINISH.
2. Only when the school has agreed to keep the kit on for the window.
3. One kit at a time. Pause above 75 °C, resume below 65 °C.
4. Claim is not used the same way as pool Pis (status is `kit`); still
   do not overlap another bot's kit work.
5. After the update is confirmed, run `check-fleet-health.sh --pi <kit>`
   (and `--dhcp` when checking vendor class).
6. Leave `usageMonitoring` **off** until it is switched on deliberately
   with `tools/fleet/usage-monitoring.sh` (idea#411).
   Toggling must not restart the Engine or the Apps.
7. Rollback puts Engine `adfd9d3` back (and the matching helper /
   drop-in / key file by quarantining the new files and restoring the
   pinned copies). Do not `rm -rf`.

`from=` is the sidecar IPv4 recorded in §3, not idea's 100.115.60.6.
Atlas fills it in during this window. Changing the key later needs
another field-update window.

## 8. Retiring the watchers

- The idea#288 kit watch ends at its 11-15 deadline anyway.
- The **kit** part of `check-fleet-health.sh` retires only after Phase 1
  (idea uplink history via the sidecar) has run alongside it for a week
  and the two uplink timelines match.
- The pool and idea checks stay.
- Until then, run both: do not delete the kit health checks in the same
  commit that first enables Phase 1.

## 9. `tools/fleet` usageMonitoring toggle

Implemented as [`usage-monitoring.sh`](usage-monitoring.sh) (idea#411).
It calls `/usr/local/sbin/idea-usage-settings` (`on` / `off` / `status`)
over SSH as `pi`. That helper writes only `/var/lib/idea/usage/settings.json`
and never restarts the Engine or any App; `idea-usage` re-reads the file
within a minute. The helper ships in agent-engine-dev (`installRootHelpers`).

```
tools/fleet/usage-monitoring.sh <pi> on|off|status
tools/fleet/usage-monitoring.sh <pi> on|off|status --approve-kit-window
```

- one kit or pool Pi at a time
- refuses kits unless `--approve-kit-window` (approved idea#374 window)
- refuses golden (`role: golden`, including idea01 as a test target), idea /
  wizardly-hugle (`DENY_HOSTS`), idea02 (`FLEET_DENY`), hold/paused/production,
  and Pis claimed by someone else
- prints JSON (`ok`, `previous`, `value`, `unchanged`, `pi`)
- offline tests: [`usage-monitoring.test.sh`](usage-monitoring.test.sh) (fake ssh)

## 10. Health-check checklist (copy per Pi)

```
tools/fleet/check-fleet-health.sh --origin --pi <name>
```

Read `claimed_with_problems` as well as failures. Release only when
ssh works, `engine` is online as `pi`, and Console HTTP 200 on the
Pi's `console_port`. On idea, also confirm MilkWise was not touched.

## 11. Move plan: usage-dashboard hub idea03 → production `idea` (PLAN ONLY)

**Status:** revision 2, 2026-11-12 ~11:15 CET, by Atlas after Steve's review of
PR #461 (10:58) and his 11:00 update. Nothing in this section has been run.
**Koen's GO (M-1) was given in Steve's chat at 10:56 CET:** "Yes, move the
dashboard to production idea when the plan and idea03 checks pass". That GO
also covers the Engine update on idea (M-2, §11.3). Being written here does not
let anyone touch idea, idea03 or Disk B outside a claimed window.

Instance `usage-dashboard-8fhwrslsrq78xtswed4` (App `usage-dashboard-1.1`;
it becomes 1.2 once idea#462 lands) currently sits on **idea03's system disk**
(`/instances/…`), in store `automerge:2VroEUvDkmYsDAwE5oG9YeFNadWH`. The target is
production `idea` (`wizardly-hugle` in fleet-state, 100.115.60.6,
idea.tail2d60.ts.net), whose store is `automerge:6f8m5KxzARv9xwv4Lw18LgVUJzu`.

The identity to keep: `idea-hub`, `tag:idea-hub`, nodekey prefix `1382c2eab7500ea4`,
IPv4 `100.75.102.57`. The Tailscale state is in the instance's `./data/tailscale`
(inode 7048947 on idea03) and the pull key is in `./data/keys`.

**Carrier: Disk B** (`diskb202610301247`, Intenso serial `3813430-532011020`, at
`/disks/sdb1` on idea03), because idea03 has no free USB port. Koen released
Disk B as free to use on 11 Nov at 23:48 CET. Disk B is idea03's App Disk and
its Backup Disk, and it is also a Files Disk. It holds `BACKUP.yaml`,
`backups/` (including the hub borg repo), `instances/`, `apps/`, `files/` and
`FILES.yaml`, and it carries the test fixture `nextcloud-files-b-001`.

The evidence for the read-only inventory of idea (2026-11-12 10:53–10:55 CET) is
in `/workspace/hub-move-plan-20261112-105047/` on the ops box. The code
answers below were read from agent-engine-dev main `537b16d` (box clone, not on
any Pi). Nothing was re-checked over SSH for revision 2.

### 11.1 Findings that shape the plan

1. **Store mismatch: no Engine command restores or moves an instance across
   stores.** idea's Engine is on its own store, 6f8m.
   - `restoreApp` resolves the instance in the local store first
     (`Commands.ts` restoreAppWrapper → `InstanceArg.ts`
     `resolveInstanceArg`). On idea that fails with "not found".
   - `moveApp` refuses a remote target (`CopyMoveApp.ts`: "Cross-engine move
     is not supported").
   - A cross-engine `copyApp` needs a shared store, mints a new instance id
     and leaves the source behind, which would create a second copy of the state.

   The one Engine-native way across stores is to **carry an App Disk**. On dock,
   `processDisk` → `processAppDisk` → `processInstance` registers every
   `instances/<id>` on the disk in the docking Engine's store and auto-starts it
   (`Disk.ts`, `AutoStart.ts`). This plan uses that path, with Disk B as the carrier.
2. **idea's Engine is old.** Its tree is `/home/pi/idea/agents/agent-engine-dev` at
   `27e355a` (2026-10-15), with helper `idea-app-data` **v3**. Fleet-state
   still says `745f2c3`, which is stale (§11.9). v3 has no `listBackup`,
   `verifyBackup`, `clearBackupLock`, exclude pass-through (v8), backup hook,
   pre-update fix (#458) or service-tar pin check (#445). `removeInstance`
   needs v4. So M-2 has to land before the move.
3. **`deploy-engine-pi.sh` refuses idea today.** The host case only allows
   idea01/03/04 (store 2VroE) and the kits (3Vvv). Any other host dies with
   "never idea02, wizardly-hugle or Milkwise". M-2 needs a reviewed script
   change: an explicit `idea` case with `EXPECT_STORE` fixed to 6f8m and a
   required `--production` flag. Atlas writes that PR and Steve merges it
   (**decision S-3**). The store-identity save/restore in the script is
   exactly what protects 6f8m. Never deploy to idea without it.
4. **There are no port or resource conflicts on idea.** Port 58546 is free.
   Only the web service publishes a host port (`${port}:8080`). The collector
   shares the sidecar's network namespace. Resources: Pi 500, 16 GB RAM
   (11.3 GB available), 60 GB free on the root disk, 36.7 °C.
5. **Files role side effect (open, decision S-1).** Disk B keeps `FILES.yaml`
   and `files/`, and no Engine command removes a Files role (the
   `COMMANDS.md` list has only `createFilesDisk`). When a Files Disk docks,
   `processFilesDisk` runs `scheduleFilesRemount` for **opted-in Running
   instances on other disks** (`FilesDisk.ts`, `FilesMount.ts`:
   `Running → docker compose up -d` with a new override). The Nextcloud App
   opts in (`x-app.filesMount` path `/mnt/idea-files`, services
   `nextcloud-app`). If production idea's Nextcloud instance
   `nextcloud-yj8ral61js46bphogbi` (and the two `.backup-2026102x` copies)
   carries that block, docking Disk B **recreates production Nextcloud's app
   container** and mounts Disk B's `files/` into it. MilkWise does not opt in
   and is not touched. See §11.4 (c).
6. **Do not dock Disk B on idea until `nextcloud-files-b-001` is off it**
   (§11.4 c). Otherwise it registers and auto-starts on production, because
   store 6f8m has no operator stop for it (`AutoStart.ts`
   `shouldAutoStart` reads the store only).

### 11.2 Identity: Option A (move the state), recommended

**Option A** is to carry the existing `./data/tailscale` and `./data/keys`
inside the instance folder, with the source stopped before the target starts.
The `app-usage-dashboard` `docs/runbook.md` ("idea-hub identity") covers this:
move the state directory "to another host", never copy it, leave
`TS_AUTHKEY` empty, open no login URL, and install with the moved state
already in place. `moveApp` copies the instance as root through
`idea-app-data copy` (owners and modes kept, same instance id) and then
deletes the source folder. The nodekey, `100.75.102.57`, the pull key and
every `from=` pin stay as they are.

**Option B**, re-keying, stays **rollback-only (M-5)**. It means a new nodekey,
a new 100.x address unless Koen reassigns `100.75.102.57` (U-6), and updates
to idea03's `/etc/ssh/idea_usage_keys/pi` `from=`, the planned kit `from=` lines,
and lockdown flows F6 and F7.

Only the test fixtures pin the hostname. The dashboard URL becomes
`http://idea.tail2d60.ts.net:58546/` because the web port is a host port.

### 11.3 Window W1 (M-2): Engine main and helper v10 on idea

**Ordering gate:** W1 runs only after idea#462 (1.2 landing on idea03) and
the idea#444 case B pass, and after the S-3 script PR has merged.

**Pre-check list (read-only; Atlas sends the output to Steve before W1 starts):**

| # | Check |
|---|---|
| W1-P1 | fleet-state: wizardly-hugle `claim: null`, status `production`. Atlas claims it for W1 (status stays `production`). |
| W1-P2 | `docker ps -a` (IDs, StartedAt, ports) saved, especially `milkwise-wizardly-hugle-001-milkwise-1` and `milkwise-test`. |
| W1-P3 | HTTP status only: :3333 and :3334 = 200, Console :8081 = 200. |
| W1-P4 | `curl localhost:8081/api/store-url` = 6f8m. sha256 of `store-identity/*` and `config.yaml` (hash only, never printed). |
| W1-P5 | Engine rev `27e355a`. sha256 of all `/usr/local/sbin/idea-*` helpers and `/etc/sudoers.d/10-engine`, `11-engine-files` (if present). Helper v3 sha `3f06f298…516b`. |
| W1-P6 | `df -h` (≥ 5 GB free), `vcgencmd measure_temp` (< 65 °C), `pm2 jlist` name/status, `systemctl --failed`. |
| W1-P7 | Read-only `grep -n filesMount /instances/nextcloud-yj8ral61js46bphogbi*/compose.yaml` to answer finding 5 for the move window. |
| W1-P8 | `deploy-engine-pi.sh <main-sha> --fetch main --dry-run` (with the S-3 `idea` case) shows store 6f8m kept and the files to save and restore. |

**Steps:**

1. Copy the helpers and sudoers to `/home/pi/atlas-w1-pre-helpers.quarantine-<ts>`.
2. Run `deploy-engine-pi.sh <main-sha> --fetch main --yes` (backup to
   `/home/pi/quarantine/engine-deploy-<ts>`). It runs `install-root-helpers`
   (v10), then `pm2 restart engine` as `pi`.
3. Post-checks:
   - Repeat W1-P2 to W1-P6. The MilkWise container IDs and StartedAt must be
     unchanged. On idea03 the Engine deploys of 12 Nov left every running
     container untouched, but that has not been proved on idea.
   - :3333 and :3334 = 200, :8081 = 200.
   - Store still 6f8m.
   - `check-fleet-health.sh --pi wizardly-hugle`.
4. Release the claim. Fleet-state version fix (§11.9).

**Rollback:** run `deploy-engine-pi.sh 27e355a…` (full sha) `--yes`, or
`git checkout --detach 27e355a` from the step-2 backup. Restore helper v3 and
the sudoers from the step-1 copy (quarantine the v10 files, never `rm`), run
`visudo -c`, then `pm2 restart engine` as `pi`. Repeat the post-checks. If
MilkWise stops answering at any point, stop and call Steve. Atlas does not touch
MilkWise.

### 11.4 Engine-code answers (3a to 3e), pending Axle confirmation

**(a) `moveApp` onto a disk that already holds the hub's backup repo.**
*Code reading:* it works, with no path clash.
- The instance goes to `<disk>/instances/<id>` and the borg repo is at
  `<disk>/backups/<id>` (`backupMonitor.ts` `backupDir`).
- `validate` refuses only these cases: same disk, undocked disk, remote source
  or target, instance not on the source, app master or instance folder
  missing, external symlinks. Nothing refers to backup links.
- Locks: `moveApp` takes the instance lock and both disk locks, so it is
  refused while a `backupApp` or `verifyBackup` (disk lock) runs on Disk B.
  Run them one after another, never side by side.
- No backup hook runs. `moveApp` stops the hub (`post-move`, not an operator
  stop) and restarts it on Disk B.
- `x-app.backup.exclude` does not apply to `moveApp`, by design: `data/tailscale`
  and `data/keys` travel, which is the point. `data/tailscale-run` (a stale
  socket) travels too.
- Risk: the app master is copied with `rsync` onto Disk B's existing
  `apps/usage-dashboard-1.x`, and every service tar is copied with
  `rsync -a <src>/services/<tar> <disk>/services/`. **The idea03 system-disk
  copies overwrite Disk B's copies.** Pre-check M-P5 has to show they are
  byte-identical, or that the system-disk ones are the correct ones, first.
- After the move the source app master is removed, if no other instance uses it.

> Axle: ______ (confirm, or correct: stale `tailscale-run/tailscaled.sock`
> handling, app-master overwrite)

**(b) Disk B docking on idea: the backup role.** *Code reading:*
- `processDisk` sees `BACKUP.yaml` and runs `processBackupDisk`. That sets
  `backupConfig {mode, links}` from the file, indexes the app bundles on the
  disk into 6f8m's `appDB`, and records stale `.backup-in-progress` locks
  without retrying them (#446).
- Auto-backups happen only for `mode: immediate`. Disk B's `BACKUP.yaml` is
  `on-demand` (#446 evidence), so nothing runs on dock.
- Links are instance ids, and the hub's id does not change, so idea adopts
  Disk B as a Backup Disk with the hub link intact.
- `backupApp <hub> diskb202610301247`, `listBackup` and `verifyBackup` then work
  on idea with helper v10 (after W1).
- No code refuses backing up an instance onto the disk it lives on. But that
  is **not an off-disk backup**: one dead disk loses both. M-6 is answered "for
  now", and a second Backup Disk for idea stays a follow-up (decision S-2).
- `processAppDisk` also registers `apps/` (the 1.x bundle) in 6f8m.

> Axle: ______ (confirm dual-role dock order Files → App → Backup, link
> adoption across stores, no same-disk refusal)

**(c) `nextcloud-files-b-001` and the production auto-start.**
- **Fixture.** Steve's 11:00 pre-carry step settles this: take the fixture off
  Disk B through the Engine before the carry.
  - **Option C1 (recommended): `moveApp nextcloud-files-b-001
    diskb202610301247 <idea03-system-disk-id>`.** It is Engine-native, keeps
    the id and data, and has the Engine itself remove the source folder (and
    `apps/nextcloud-1.0…` if nothing else on Disk B uses it). It leaves no
    fixture data on Disk B, so nothing else auto-starts on production. Cost:
    the fixture then runs on idea03's system disk (space check M-P6; stop it
    afterwards with `stopInstance`, an operator stop).
  - **Option C2: `stopInstance`, then `removeInstance <id>`** (helper v4,
    `docker compose down` without `-v`). It quarantines to **Disk B's**
    `.idea-quarantine/<id>-<stamp>`. Scans ignore `.idea-quarantine`, so
    nothing auto-starts, but the fixture's data would still travel to
    production inside Disk B. A quarantine copy on idea03's boot SSD
    beforehand would be a hand copy, not an Engine step.
  - Not allowed: `removeBackupRole`, or any hand change to META.yaml,
    BACKUP.yaml, backups/, instances/, files/, FILES.yaml or apps/.
  - **Recommendation: C1.** Check `listBackup nextcloud-files-b-001
    diskb202610301247`. If it has a borg repo on Disk B, that repo travels to
    idea as data. Accept that or keep it (decision S-1b).
- **Files role (still open after C1, decision S-1a).** Disk B stays a Files Disk.
  On idea, the dock remounts opted-in Running instances on other disks (§11.1
  finding 5). Options:
  - **F1:** Axle adds an Engine `removeFilesRole <diskId>` (like
    `removeBackupRole`: quarantine `files/` and `FILES.yaml` to
    `.idea-quarantine`, then `processDisk`), and it runs on idea03 before
    the carry. Engine-native, no hand edits. This needs a Steve or Koen OK,
    because it changes FILES.yaml and files/ through the Engine.
  - **F2:** accept the recreate of production Nextcloud's app container
    (Engine `up -d`, gated on `occ status`), with Disk B's `files/` showing up
    as a share in production Nextcloud. Needs Koen's OK.
  - **F3:** if W1-P7 shows production Nextcloud has no `filesMount` block,
    nothing is remounted and no decision is needed.

  **Recommendation:** decide from W1-P7. If production Nextcloud opts in, use F1.
- On idea03, re-docking Disk B after the eject also re-runs `processDisk`, and
  every dock rewrites `META.yaml` `lastDocked` (`Meta.ts`). That is Engine-native.
  It already happened on idea03 at each Engine restart (#447 evidence).

> Axle: ______ (confirm C1 is clean for a Files-opted-in instance whose Files
> Disk is the source disk; and whether removeFilesRole is acceptable)

**(d) Disk B leaving idea03.** Once Disk B is gone:
- idea03 has **no Backup Disk**. Every `backupApp` on idea03, and the pre-update
  backup that `updateApp` takes for a major update (#458), fails until another
  Backup Disk is docked.
- idea03 loses the Files share and the hub (by design).
- So the move comes **after** idea#462 (1.2 on idea03) and the #444 case B pass,
  and after the last idea03 backup and verify of the hub (M-P4).
- Any later idea03 backup work (Kid or Axle) needs a new Backup Disk (**S-2**).
- `nextcloud-files-b-001` (after C1) keeps running on idea03 without `files/`.
  The Engine remounts it without Disk B's share.

> Axle: ______

**(e) Real command names** (Console on idea03 :8080 / idea :8081, or the box's
`engine-ctl.mjs send <command> <args>`). There is no `createAppDisk` or
"initialise" step: Disk B is already an App Disk, so the P-7 guess from
revision 1 is gone.

| Step | Command |
|---|---|
| backup | `backupApp usage-dashboard-8fhwrslsrq78xtswed4 diskb202610301247` |
| list / verify | `listBackup <id> diskb202610301247 [archive]`, `verifyBackup <id> diskb202610301247 [archive]` |
| stale lock (only if listed) | `clearBackupLock <id> diskb202610301247` |
| fixture off | `moveApp nextcloud-files-b-001 diskb202610301247 <idea03-system-disk-id>`, then `stopInstance nextcloud-files-b-001 <idea03-system-disk-id>` |
| hub onto Disk B | `moveApp usage-dashboard-8fhwrslsrq78xtswed4 <idea03-system-disk-id> diskb202610301247` |
| stop / eject | `stopInstance usage-dashboard-8fhwrslsrq78xtswed4 diskb202610301247`, `ejectDisk diskb202610301247` |
| on idea | nothing: the dock auto-starts. If needed, `startInstance <id> diskb202610301247` |
| rollback | `stopInstance`, `ejectDisk` on idea; after the re-dock on idea03, `startInstance` |

The idea03 system-disk id is the record with `diskTypes: ['system']` in 2VroE,
read from the Console at M-P1.

> Axle: ______

### 11.5 Move window W2 (after W1; gates: #462 and #444 case B passed, S-1 decided)

**Pre-checks (read-only, the output goes to Steve before W2):**

| # | Check | Owner |
|---|---|---|
| M-P1 | fleet-state: idea03 and wizardly-hugle `claim: null`. Kid's #159 run 3 is finished, #462 has landed, #444 case B has passed. Note the idea03 system-disk id. | Atlas |
| M-P2 | idea: W1-P2 to W1-P6 again. 58546 is free. Engine is on main with helper v10. | Atlas |
| M-P3 | Hub on idea03: nodekey `1382c2eab7500ea4`, IP `100.75.102.57`, Running, no AuthURL (`check-idea-hub-nodekey.py`), health 200. Record the container IDs and the inode. | Kid |
| M-P4 | `backupApp` hub → Disk B (hook), then `listBackup` and `verifyBackup`. No stale lock. Record the archive. | Atlas |
| M-P5 | sha256 of idea03 `/apps/usage-dashboard-<v>` and `/services/{web,python,tailscale}.tar` against Disk B's copies and the bundle reference (§12). The web tar must be the index-pin tar (1.1: `6beeb1e0…` / `9b5501f0`; use the 1.2 bundle's values if 1.2 lands). If not, refresh it per `docs/packaging.md` first. | Atlas |
| M-P6 | Free space on idea03's system disk for `nextcloud-files-b-001` (instance size via `summariseDisk` or `du` read-only). `listBackup nextcloud-files-b-001 diskb202610301247`. | Atlas |

**Steps (about 60 min; T = start; never two hub copies live):**

| Step | T+ | Owner | Action | Pass |
|---|---|---|---|---|
| 1 | 0 | Atlas | Claim idea03 and wizardly-hugle (`claim "Atlas idea#416 hub move"`, statuses unchanged). Re-run M-P1 to M-P6. | green |
| 2 | 5 | Atlas | Fixture off Disk B: `moveApp nextcloud-files-b-001 diskb202610301247 <sys>`, then `stopInstance` it on `<sys>`. | Done; no `instances/nextcloud-files-b-001` on Disk B |
| 3 | 15 | Kid | Hub snapshot (M-P3). No pull in flight. | same |
| 4 | 17 | Atlas | `moveApp usage-dashboard-8fhwrslsrq78xtswed4 <sys> diskb202610301247` | Done; hub Running from Disk B on idea03, nodekey/IP unchanged, health 200, no `/instances/<id>` on idea03's system disk |
| 5 | 25 | Kid | `check-idea-hub-nodekey.py` on the Disk B copy: `match=true`. One pull of idea03 OK. | match=true |
| 6 | 28 | Atlas | `stopInstance <hub> diskb202610301247` (operator stop), then `ejectDisk diskb202610301247`. Hub `docker ps -a` shows nothing Up. | idea-hub offline on the tailnet |
| 7 | 30 | Koen | Unplug Disk B from idea03 and plug it into a free USB port on **idea**. Leave the "Flash Drive FIT" and the NVMe alone. | physical |
| 8 | 32 | Atlas | Watch idea: the dock registers Disk B in 6f8m (App + Backup + Files), auto-starts the hub, loads the service tars (`MATCH`) and keeps port 58546. Watch the Files remount according to S-1. | hub Running; health 200 on idea localhost |
| 9 | 35 | Kid | On idea: `BackendState=Running`, no AuthURL, nodekey `1382c2eab7500ea4`, IP `100.75.102.57`, `match=true`. New container IDs and inode recorded. One pull of idea03. | match=true |
| 10 | 40 | Atlas | idea unaffected: :3333/:3334 = 200 (HTTP only), :8081 = 200, MilkWise IDs and StartedAt unchanged, `engine online`, `check-fleet-health.sh --pi wizardly-hugle`, temperature < 75 °C. On idea, `listBackup <hub> diskb202610301247` lists the M-P4 archive (proves 3b). | unchanged |
| 11 | 45 | Koen | Log in at `http://idea.tail2d60.ts.net:58546/`. Confirm MilkWise and the Console still work. | Koen OK |
| 12 | 50 | Atlas | Release claims. Fleet-state notes: hub on idea on Disk B; Disk B is idea's App/Backup/Files disk; idea03 has no Backup Disk. Evidence to Steve. | pushed |

### 11.6 What must stay untouched

- MilkWise (:3333 and :3334): HTTP status only.
- Console :8081.
- Other instances on idea, except the S-1 Files remount if it is chosen.
- idea's host Tailscale. No tag or ACL changes.
- Both Automerge stores: no hand edits.
- No hand-placed compose files.
- No copy of `./data/tailscale` (no `cp`, `rsync` or `docker cp`).
- No `removeBackupRole` on Disk B, and no hand edits to Disk B's META.yaml,
  BACKUP.yaml, backups/, instances/, files/, FILES.yaml or apps/.

### 11.7 Rollback

- **Before step 7:** `startInstance` on idea03 from Disk B, or `moveApp` back
  to `<sys>`.
- **After step 8:** on idea, `stopInstance <hub> diskb202610301247`
  (operator stop), then `ejectDisk`. Koen moves Disk B back. idea03 re-docks
  it, and the 2VroE record keeps the step-6 operator stop, so the hub does not
  auto-start. Run `startInstance` and the nodekey check.
- **Data:** `restoreApp` from the Disk B archive (M-P4). It contains no
  `data/tailscale`. **Never start an older copy of the Tailscale state.**
- **State lost:** Option B with M-5.
- **MilkWise or Console affected:** stop the hub first, then report to Steve.

### 11.8 Koen actions for idea#375

| Item | Status / ask |
|---|---|
| M-1 | **DONE**: GO in Steve's chat, 2026-11-12 10:56 CET. |
| M-2 | Covered by the M-1 GO. Window W1 (§11.3), after #462, #444 case B and the S-3 script PR. |
| M-3 | Dropped. Disk B is the carrier. |
| M-4 | W2 step 7: move Disk B (Intenso 3813430-532011020) from idea03 to idea. Step 11: dashboard login on idea:58546, plus the MilkWise and Console check. |
| M-5 | Rollback only: a single-use `tag:idea-hub` key and reassigning `100.75.102.57`. |
| M-6 | Answered for now: Disk B becomes idea's Backup Disk, and the hub repo goes with it. It is on the same disk as the hub, so it is not an off-disk backup (S-2). |

### 11.9 Decisions for Steve, and follow-ups

- **S-1a:** Files role on Disk B → production Nextcloud remount (F1 / F2 / F3,
  §11.4 c), decided from W1-P7.
- **S-1b:** If `nextcloud-files-b-001` has a borg repo on Disk B, does it
  travel to idea?
- **S-2:** A second Backup Disk, for idea (off-disk copy) and for idea03 (no
  Backup Disk after W2).
- **S-3:** Merge a `deploy-engine-pi.sh` `idea` case (store 6f8m,
  `--production`) before W1.
- **Fleet-state version fix:** wizardly-hugle `version` is stale
  (`745f2c3`; live `27e355a`). Per Steve (11:00), it is **not** fixed now. It is
  set through `update-fleet-state.sh` when W1 (M-2) lands, straight to the new
  main sha.

## 12. Service-tar audit of production idea (read-only, 2026-11-12 10:54 CET)

Reference is the 1.1 bundle on the ops box,
`/workspace/deliverables/usage-dashboard-1.1-release/services-docker-save/`.
These are OCI layouts, and each `index.json` entry is the image index that
the compose pin names:

| Tar | sha256 | Top-level digest | Compose pin (1.1) |
|---|---|---|---|
| `ghcr.io_koenswings_usage-dashboard-web:1.0.tar` | `6beeb1e0…230477af571` | `9b5501f0690f…` | `…usage-dashboard-web:1.0@sha256:9b5501f0…8139` ✔ |
| `python:3.12-slim-bookworm.tar` | `217bc5fb…02db306` | `935c3c5b1235…` | `python:3.12-slim-bookworm@sha256:935c3c5b…` ✔ |
| `tailscale_tailscale:v1.88.3.tar` | `af9d4f86…421353a2` | `b2a19f6b6402…` | `tailscale/tailscale:v1.88.3@sha256:b2a19f6b…` ✔ |

On idea:

- `/apps` has kiwix-1.0, kiwix-1.0.1, kolibri-1.0,
  kolibri-channel-builder-2407800/-27f615c, milkwise-1.0.0 and
  nextcloud-1.0-31.0.1. **No `usage-dashboard-*` app master.**
- `/services` has kiwix, kolibri, channel-builder and nextcloud
  (+code, +mariadb) tars. **No usage-dashboard-web, python or tailscale
  tar.**
- No App Disk is docked (`/disks/sda`, `/disks/sda2` are empty dirs). The
  vfat stick at `/run/idea-usb/sdb1` has no `apps/` or `services/`.
- `docker images` has **no** usage-dashboard, tailscale or python image.
  There are 12 images (10.56 GB, 9.9 GB reclaimable; nothing is pruned
  here).

**Clashes:** none on idea itself, because nothing there could clash. The
known risk sits on the **source**, and with Disk B as the carrier it matters
twice. #327 / #445: the pre-1.1 web tar was the single-manifest `ef48f1fa`,
while the 1.1 pin is the index `9b5501f0`.

`moveApp` copies the idea03 system disk's `services/<tar>` over Disk B's copy
(`rsync -a`, §11.4 a). If the system-disk tar is still `ef48f1fa`, it replaces
a good Disk B tar. The Engine then rejects it as `MISMATCH` (no override) and
the hub cannot start offline on idea.

M-P5 checks every copy against the reference before W2 step 4. The idea03
local tags (Steve's 22:15 fix: `1.0-ba869399813e` → `ef48f1fa`, quarantine tag
`5c1e7215`) do not travel, because idea loads from the tars. If 1.2 lands
(#462), the 1.2 bundle becomes the reference.
