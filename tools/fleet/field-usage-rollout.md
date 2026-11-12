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

**Status:** written 2026-11-12 ~11:00 CET by Atlas for Steve. Nothing in this
section has been run. It needs Koen's GO on idea#375 (items M-1 to M-6 below). It
does not give anyone permission to touch idea, idea03 or Disk B.

Instance `usage-dashboard-8fhwrslsrq78xtswed4` (App `usage-dashboard-1.1`),
today on **idea03's system disk** (`/instances/…`), store
`automerge:2VroEUvDkmYsDAwE5oG9YeFNadWH`. Target: production `idea`
(`wizardly-hugle` in fleet-state, Tailscale 100.115.60.6,
idea.tail2d60.ts.net).

Identity to keep: `idea-hub`, `tag:idea-hub`, nodekey prefix
`1382c2eab7500ea4`, IPv4 `100.75.102.57`. State lives in the instance's
`./data/tailscale` (tailscaled.state inode 7048947 on idea03). The pull key
is in `./data/keys`. Containers on idea03 today: web `d756a3cd`, collector
`fb5e0d1b`, tailscale `a05c46e4`. Health is on `:58546`.

Evidence for the read-only inventory of idea (2026-11-12 10:53–10:55 CET) is
on the ops box in `/workspace/hub-move-plan-20261112-105047/`.

### 11.1 Findings that shape the plan

1. **Store mismatch is a real blocker for an Engine "backup → restore" move.**
   idea's Engine is on its **own** store `automerge:6f8m5KxzARv9xwv4Lw18LgVUJzu`
   (`curl localhost:8081/api/store-url`, matching fleet-state). The pool
   store is 2VroE. In agent-engine-dev main (537b16d):
   - `restoreApp` runs `resolveInstanceArg(store, …)` first
     (`src/data/Commands.ts` restoreAppWrapper, `src/data/InstanceArg.ts`).
     On idea the 6f8m store has no record for this instance, so the
     command fails with `restoreApp: instance '…' not found` before it
     extracts anything.
   - `moveApp` refuses a target disk on another Engine ("Cross-engine move
     is not supported", `src/data/CopyMoveApp.ts`).
   - A cross-engine `copyApp` needs both Engines in one store. It also mints
     a **new** instance id and leaves the source in place, which would make
     a second copy of the Tailscale state. The runbook forbids that.
   - The #446 archive `2026-11-12T09-19-37-766Z` on Disk B leaves out
     `data/tailscale` and `data/keys` by design, so a restore could not
     carry the identity anyway.

   So **no Engine command restores or moves an instance between two stores
   today.** The one Engine-native path across stores is an **App Disk
   carried between Engines**. When an App Disk docks, `processDisk` →
   `processInstance` → `createOrUpdateInstance` registers its `instances/<id>`
   in the docking Engine's store and auto-starts it (`src/data/Disk.ts`,
   `src/data/AutoStart.ts`). That is how disks already move between kits.
   This plan uses that path. The Disk B borg archive is the data safety net
   and the rollback source, not the transport.
2. **idea's Engine is old.** The tree is `/home/pi/idea/agents/agent-engine-dev`
   at `27e355a` (2026-10-15), not `745f2c3` as fleet-state says (that
   record is stale). Helper `idea-app-data` is **v3**
   (`IDEA_APP_DATA_VERSION=3`, sha `3f06f298…516b`). That version has no
   `listBackup` or `verifyBackup`. It also lacks the
   `x-app.backup.exclude` pass-through (v8), the backup hook (#444), the
   pre-update method fix (#458), the restore quarantine (v4), and the
   service-tar pin check (#445). The 1.1 App's backup hook and
   exclude contract need main. **Prerequisite:** deploy Engine main and
   helpers v10 to idea in its own Koen-approved window (M-2), before the
   move.
3. **No conflicts on idea for ports or resources.** Listening ports are 22,
   3333 (MilkWise), 3334 (milkwise-test), 8081 (Console), 50065, 53503, 9980
   (Nextcloud), 54189 (Kolibri), 61312 (Kiwix), 60758 (channel builder),
   53677, and 54225 on the tailnet IP. **58546 is free**, so the Engine keeps
   the instance's `.env` `port=58546` (startInstance keeps it unless it is
   listening, reserved, or owned in the store). Only the web service
   publishes a host port (`${port}:8080`). The collector shares the
   sidecar's network namespace, so its SOCKS port 1055 is inside that
   namespace and does not clash with idea's host tailscaled. The sidecar
   does not mount the host `tailscaled.sock`. Resources: Pi 500 with
   16 GB RAM (11.3 GB available), root disk 60 GB free (47%), 36.7 °C,
   load 0.39. The hub is about 7 MB of data plus about 120 MB of images.
4. **No usage-dashboard, tailscale or python images or tars on idea.** See §12.
5. **Other disks on idea, which this plan leaves alone:** `sdb1` is a vfat
   "Flash Drive FIT" (serial 0373219120013886), mounted read-only at
   `/run/idea-usb/sdb1`. It is not an IDEA disk. `nvme0n1` (Samsung 256 GB,
   serial S73YNXMX102912) has an unmounted bootfs and rootfs. Neither is a
   move target. `/disks` has only the empty `sda` and `sda2` dirs, so
   no App Disk is docked on idea.
6. **Do not dock Disk B on idea.** It is an App, Files and Backup disk with
   `nextcloud-files-b-001`. Docking it on production would register and
   auto-start that instance in store 6f8m and rewrite `META.yaml`
   `lastDocked`. Disk B also stays hands-off (§0, standing rules).

### 11.2 Identity: Option A (move the state), recommended

- **Option A (recommended): carry the existing `./data/tailscale` and
  `./data/keys` inside the instance folder on a carrier App Disk, with the
  source stopped first.** The app-usage-dashboard `docs/runbook.md`
  ("idea-hub identity") says to hand the identity "later to another
  host" by **moving** the state directory, never copying it. It also says to
  leave `TS_AUTHKEY` empty and open no login URL, and to install with the
  moved state already in `./data/tailscale` so the sidecar never starts
  empty. `moveApp` moves the instance folder as root through
  `idea-app-data copy`, which keeps owners and modes and the same instance
  id. It then deletes the source folder. The nodekey, the IPv4
  `100.75.102.57`, the pull key and the `from=` pins all stay the same.
- **Option B (fallback only): re-key with a fresh single-use `tag:idea-hub`
  key from Koen.** This gives a new nodekey and usually a new 100.x
  address. Koen would then have to reassign `100.75.102.57` in the admin
  console (U-6), or every consumer would need updating:
  - idea03's `/etc/ssh/idea_usage_keys/pi` `from=` line
  - the planned kit `from=` lines (§6 of the #416 status: "keep `from=` at
    `100.75.102.57`")
  - the flows in `field-usage-lockdown-flows.md` (F6, F7)
  - the box ACL probes

  It also leaves a stale `idea-hub` node to delete, and a rejected key is
  burned (runbook "One-join"). Use B only if the moved state fails the
  nodekey check on idea and cannot be rolled back (§11.6).

Nothing in the repos points at the hub's **hostname**, apart from the test
fixtures (`idea-hub.tail2d60.ts.net` in app-usage-dashboard tests). Consumers
pin the **IPv4**. Koen's dashboard URL changes from idea03:58546 to
`http://idea.tail2d60.ts.net:58546/` because the web port is published on the
host, not on the sidecar.

### 11.3 Pre-checks (all read-only; T-1 day and T-0)

| # | Check | Owner |
|---|---|---|
| P-1 | fleet-state: idea03 and wizardly-hugle both have `claim: null`. Kid's #159 run 3 is finished. | Atlas |
| P-2 | idea: `docker ps -a`, `ss -ltn` (58546 still free), `df -h` (> 5 GB free), temperature < 65 °C. HTTP status only: MilkWise :3333/:3334 = 200, Console :8081 = 200. `pm2 jlist` shows `engine online`. Store URL is still 6f8m. | Atlas |
| P-3 | idea is on Engine main and helpers v10 (M-2 done), and `check-fleet-health.sh --pi wizardly-hugle` is ok. | Atlas |
| P-4 | idea03 hub identity: nodekey `1382c2eab7500ea4`, IP `100.75.102.57`, `BackendState=Running`, no `AuthURL` (`script/check-idea-hub-nodekey.py`, public prefixes only). `:58546/api/v1/health` = 200. Record the container IDs and the state inode. | Kid |
| P-5 | idea03 `/services` holds the three 1.1 tars and they match §12's reference shas. Web `6beeb1e0…` (index `9b5501f0`), python `217bc5fb…`, tailscale `af9d4f86…`. If idea03 still has the old `ef48f1fa` web tar, refresh it first per the pin-change runbook (`docs/packaging.md`). Otherwise moveApp carries a MISMATCH tar that the new Engine on idea quarantines. Also confirm where the app master `apps/usage-dashboard-1.1` lives for this system-disk instance (system disk vs Disk B), because moveApp copies the app master from the source disk. | Atlas |
| P-6 | A fresh backup exists: `backupApp usage-dashboard-8fhwrslsrq78xtswed4 diskb202610301247` (1.1 hook method, no stop), then `listBackup` and `verifyBackup`, all via Console or engine-ctl on idea03. Record the archive name. This is the data rollback source. It does not carry identity. | Atlas (after Kid releases idea03) |
| P-7 | Carrier disk (M-3) is docked on idea03 as an **App Disk** (Engine `createAppDisk`/initialise flow on idea03, by disk id, matched by serial). It is empty apart from META.yaml. It is not Disk B, not the WD 20070Q450002, and not any protected fixture. | Atlas |

### 11.4 Timed step list (move window, about 45 min; T = Koen's GO time)

Never two hub containers with this state at once: the source is stopped
before the target starts at every hand-over (steps 3, 6, 8).

| Step | T+ | Owner | Action | Pass condition |
|---|---|---|---|---|
| 1 | 0 | Atlas | Claim idea03 and wizardly-hugle in fleet-state (`claim "Atlas idea#416 hub move"`; wizardly-hugle `status` stays `production`). Run P-1 to P-6 again. | All green |
| 2 | 5 | Kid | Snapshot the hub identity and health on idea03 (P-4). Collector status is ok, with no pull in flight. | Same as P-4 |
| 3 | 8 | Atlas | On idea03, Engine `moveApp usage-dashboard-8fhwrslsrq78xtswed4 <idea03-system-disk-id> <carrier-disk-id>`. The Engine stops the hub (`post-move`), copies the app master, the instance (as root, modes kept, same id) and the service tars, registers the instance on the carrier and starts it there. It then removes the source folder (Engine-native, `idea-app-data delete`). | Operation Done. The hub runs from `<carrier>/instances/<id>` on idea03. Nodekey `1382c2eab7500ea4`, IP unchanged, health 200. No `/instances/<id>` left on the idea03 system disk. |
| 4 | 15 | Kid | Run `check-idea-hub-nodekey.py` against the carrier copy: `match=true`. One collector pull of idea03 succeeds. | match=true |
| 5 | 18 | Atlas | Run `stopInstance <id> <carrier-disk-id>` on idea03 (an operator stop, so idea03's store keeps it Stopped if the disk ever comes back). Then `ejectDisk <carrier-disk-id>`. Check `docker ps -a` on idea03: no usage-dashboard container is running. | No hub container Up on idea03. The tailnet shows idea-hub offline. |
| 6 | 20 | Koen | Unplug the carrier disk from idea03 and plug it into a free USB port on **idea**. Leave the "Flash Drive FIT" and the NVMe alone. | Physical |
| 7 | 22 | Atlas | Watch idea: the Engine docks the disk and registers instance `<id>` in store 6f8m. It auto-starts the hub, because there is no operator stop in 6f8m. The Engine loads the service tars, which must be `MATCH` (§12), and keeps port 58546. | Instance Running on idea, `:58546/api/v1/health` 200 from idea's localhost |
| 8 | 25 | Kid | On idea, check identity: `BackendState=Running`, no `AuthURL`, nodekey `1382c2eab7500ea4`, IP `100.75.102.57`, `match=true`. Record the new container IDs and the new state inode (both are expected to change, being a new host and filesystem). Run one collector pull of idea03. | match=true, pull ok |
| 9 | 30 | Atlas | Check idea is unaffected, using HTTP status only: MilkWise :3333 and :3334 = 200, Console :8081 = 200. `docker ps` shows the MilkWise containers keep their IDs and StartedAt. `pm2 jlist` shows `engine online`. Run `check-fleet-health.sh --pi wizardly-hugle`. Temperature < 75 °C. | All unchanged |
| 10 | 35 | Koen | Log in at `http://idea.tail2d60.ts.net:58546/`. Confirm MilkWise and the Console still work (as in U-5). | Koen OK |
| 11 | 40 | Atlas | Release the claims. Write the fleet-state notes: the hub is on idea on carrier `<disk-id>`, and idea03 no longer hosts it. Correct the wizardly-hugle `version` field. Send the evidence to Steve. | Pushed |

Later, optional, in a separate change: `moveApp` from the carrier to
idea's system disk, which is the §2 "preferred" location (same Engine, same
store). Until then the carrier stays docked. §2 allows that as the
fallback, and it survives the 05:00 reboot because docking re-registers the
disk. Backups on idea need their own Backup Disk decision (M-6). Disk B
stays on idea03.

### 11.5 What must stay untouched

- MilkWise `milkwise-wizardly-hugle-001` (:3333) and `milkwise-test` (:3334):
  HTTP status only, with no inspect, restart or compose action.
- Console :8081 and the other instances on idea (Nextcloud, Kolibri, Kiwix,
  channel builder).
- idea's host Tailscale (`tag:idea`, 100.115.60.6). No tags or ACL changes.
- No hand edits to either Automerge store. No hand-placed compose files.
  No copy of `./data/tailscale` anywhere (no `cp`, `rsync` or `docker cp`).

### 11.6 Rollback

- **Before step 6** (the disk is still on idea03): `startInstance <id> <carrier>`
  on idea03, or `moveApp` back to idea03's system disk. The state never
  left idea03.
- **After step 7, if the hub misbehaves on idea:** `stopInstance <id> <carrier>`
  on idea (operator stop) and `ejectDisk`. Koen moves the disk back to
  idea03. idea03 re-docks it. The record in 2VroE carries the step-5
  operator stop, so it does not auto-start. Then run `startInstance` on
  idea03 and check the nodekey. There is still only one copy of the state,
  and it is always the newest.
- **Data loss or corruption:** `restoreApp` on idea03 from Disk B (archive
  from P-6). That archive has no `data/tailscale`, so keep the carrier's
  state dir as the identity. **Never start an older copy of the Tailscale
  state** (the 2026-11-11 Expired incident).
- **State lost:** Option B (§11.2) with M-5.
- MilkWise or Console affected at any step: stop the hub on idea first
  (`stopInstance`), then report to Steve. Do not touch MilkWise.

### 11.7 Koen actions to add to idea#375

| Item | Ask |
|---|---|
| M-1 | GO for moving the usage-dashboard hub onto production `idea`, with a window (about 45 min, step list in §11.4). |
| M-2 | GO, in a separate earlier window, to deploy Engine main (537b16d or later) and helpers v10 to idea. It is on `27e355a` with helper v3 today. The Engine restarts as `pi`. MilkWise is checked by HTTP status before and after. |
| M-3 | Provide one spare USB disk (≥ 8 GB is enough) to become the hub's carrier App Disk. Plug it into idea03 before the window. Not Disk B and not the WD 20070Q450002. |
| M-4 | Step 6: move the carrier from idea03 to idea (any free USB port; leave the "Flash Drive FIT" and the NVMe in place). Step 10: log in to the dashboard at idea:58546 and confirm MilkWise and the Console. |
| M-5 | Only if rollback fails and the state is lost: one single-use `tag:idea-hub` key, and reassign `100.75.102.57` to the new node (U-6). |
| M-6 | Decide where idea's encrypted hub backups go (§3 "idea's encrypted Borg repo" does not exist yet; idea has no Backup Disk). |

## 12. Service-tar audit of production idea (read-only, 2026-11-12 10:54 CET)

Reference is the 1.1 bundle on the ops box,
`/workspace/deliverables/usage-dashboard-1.1-release/services-docker-save/`.
These are OCI layouts, and each `index.json` entry is the image index that
the compose pin names:

| Tar | sha256 | Top-level digest | Compose pin (1.1) |
|---|---|---|---|
| `ghcr.io_koenswings_usage-dashboard-web:1.0.tar` | `6beeb1e0…6af477af571` | `9b5501f0690f…` | `…usage-dashboard-web:1.0@sha256:9b5501f0…8139` ✔ |
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

**Clashes:** none on idea itself, because nothing is there to clash. The
known risk is on the **source**. #327 / #445: the pre-1.1 web tar was the
single-manifest `ef48f1fa`, and the 1.1 pin is the index `9b5501f0`. If the
tar that `moveApp` copies from idea03 is still the `ef48f1fa` one, the
Engine's tar check calls it `MISMATCH` (no override) and quarantines it. The
hub would then not start offline on idea. P-5 must confirm that idea03's
`services/ghcr.io_koenswings_usage-dashboard-web:1.0.tar` has sha
`6beeb1e0…` before step 3. The same applies to the local tag on idea03
(Steve's 22:15 tag fix: `1.0-ba869399813e` → `ef48f1fa`, quarantine tag
`5c1e7215`). Those are idea03 local tags and do not travel. idea loads from
the tars.
