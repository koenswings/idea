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

**Status:** revision 3, 2026-11-12 ~11:30 CET, by Atlas. It follows Steve's 11:04
change (made on Koen's question) and replaces the Disk B carrier plan from
revision 2. Nothing here has been run.

- **Koen's GO (M-1):** given in Steve's chat at 10:56 CET: "Yes, move the
  dashboard to production idea when the plan and idea03 checks pass". The same
  GO covers the Engine update on idea (M-2, window W1).
- **No physical step:** Disk B stays on idea03, untouched.
- **Not a permission:** this section does not let anyone touch idea or idea03
  outside a claimed window.

**Source:** `usage-dashboard-8fhwrslsrq78xtswed4` on **idea03's system disk**,
store `automerge:2VroEUvDkmYsDAwE5oG9YeFNadWH`. It will be version 1.2 after
idea#462.

**Target:** a **new** instance of usage-dashboard 1.2 on idea's **internal
system disk**. idea is `wizardly-hugle` in fleet-state, 100.115.60.6, store
`automerge:6f8m5KxzARv9xwv4Lw18LgVUJzu`.

**Identity to keep:**
- `idea-hub`, `tag:idea-hub`
- nodekey prefix `1382c2eab7500ea4`
- IPv4 `100.75.102.57`
- the state in `./data/tailscale` and the pull key in `./data/keys`

**Evidence:**
- Read-only idea inventory (10:53–10:55 CET):
  `/workspace/hub-move-plan-20261112-105047/` on the ops box.
- Code reading: agent-engine-dev main `537b16d` and app-usage-dashboard on
  the box. No SSH since revision 1.

### 11.1 Findings that shape the plan

1. **No Engine command moves or restores an instance across stores.**
   - `restoreApp` resolves the instance in the local store, so it says "not
     found" on 6f8m.
   - `moveApp` refuses a remote target.
   - Cross-engine `copyApp` needs a shared store.

   So the move is: a fresh Engine install on idea, plus a copy of the source
   instance's `data/`. Each Engine stays in its own store, and no store is
   edited by hand.
2. **idea's Engine is old.**
   - It runs `27e355a` (2026-10-15) with `idea-app-data` **v3** (sha
     `3f06f298…516b`).
   - Fleet-state still says `745f2c3`. That is stale and is fixed when W1
     lands (§11.8).
   - v3 has none of these: `listBackup`/`verifyBackup` (v10), backup excludes
     (v8), the backup hook (#444), the #458 fix, the #445 tar pin check, or
     `removeInstance` (v4).
   - The 1.2 install has to wait for W1.
3. **`deploy-engine-pi.sh` refused idea.**
   - The host case ended in `die "… never idea02, wizardly-hugle or Milkwise"`.
   - The fix is up for review as **koenswings/idea#463** (branch
     `atlas/416-deploy-idea-production`). It adds an `idea|wizardly-hugle`
     case that needs `--production`, fixes the store to 6f8m (no override),
     refuses `--production` on any other host, and skips the DHCP
     vendor-class step on production (Steve to confirm).
   - Tests: 62/62. W1 waits for that PR to merge.
4. **Ports and resources on idea.**
   - The fresh install gets an Engine-allocated `port=`, never 80, 8080, a
     listening port, or a port another instance owns. The web entrypoint
     refuses 80, 3333, 3334 and 8081.
   - Listening ports at the inventory: 22, 3333, 3334, 8081, 9980, 50065,
     53503, 53677, 54189, 54225, 60758, 61312.
   - 58546 was free, but the new port can be any free one. Koen's dashboard
     URL becomes `http://idea.tail2d60.ts.net:<new port>/`. The admin →
     `tag:idea` grant (flow F2/F3) covers any port.
   - The collector shares the sidecar's network namespace, and the sidecar does
     not mount the host `tailscaled.sock`, so there is no clash with idea's
     tailscaled.
   - Resources: Pi 500, 16 GB RAM (11.3 GB available), 60 GB free on root,
     36.7 °C.
5. **The direct idea03 → idea copy over Tailscale conflicts with the
   lockdown (decision S-4).**
   - The live ACL denies `tag:idea` → `tag:idea` (flow F8, PASS after L-1).
     idea and idea03 are both `tag:idea`.
   - A temporary Pi-to-Pi SSH key would also break the standing rule "no SSH
     key changes on Pis".
   - Options, in the order I'd pick them:
     - **R1 (recommended): box-relayed stream.** The ops box is
       `autogroup:admin` and already reaches both Pis on :22 (flow F1). Run
       `ssh idea03 'sudo tar …' | ssh idea 'sudo tar …'`. It needs no Pi key,
       no ACL change and nothing written to the box disk. The bytes pass
       through the box in memory only, and the pull key and node key are
       never printed.
     - **R2: home LAN, idea03 192.168.0.228 → idea 192.168.0.231.** No ACL
       change, but it needs a temporary key on idea (rule exception) and
       wiping it afterwards.
     - **R3: what Steve asked for, direct over Tailscale.** It needs Koen to
       add a temporary ACL grant idea03 → idea tcp/22 and remove it
       afterwards, plus the temporary key. Bots never change the ACL.

### 11.2 Identity: Option A, recommended

Move the state, never copy it. The `app-usage-dashboard` runbook ("idea-hub
identity") says:
- hand the identity "to another host" by moving `./data/tailscale`;
- whichever container last starts with a copy owns the node key, and a
  leftover copy goes stale;
- never start an older copy after the new one has run.

Here, "move" means a byte copy while the source is **stopped by the
operator** (§11.4 step 2), followed by exactly one start, on idea. The idea03
copy is never started again unless we roll back, and in that case idea's copy
is stopped first (§11.6). The nodekey, `100.75.102.57`, the pull key and
every `from=` pin stay the same.

**Option B (re-key) is rollback-only (M-5).** It means a fresh single-use
`tag:idea-hub` key and Koen reassigning `100.75.102.57` (U-6), or updating
every `from=` pin.

### 11.3 Window W1 (M-2): Engine main `537b16d` + helper v10 on idea

**Gates, all required:**
- idea#462 (1.2 on idea03) has landed;
- the idea#444 case B has passed;
- #463 has merged.

**Pre-checks (read-only; Atlas sends the output to Steve before W1 starts):**

| # | Check |
|---|---|
| W1-P1 | fleet-state wizardly-hugle has `claim: null` and status `production`. Atlas claims it for W1; status stays `production`. |
| W1-P2 | `docker ps -a` saved: IDs, StartedAt, ports. Especially `milkwise-wizardly-hugle-001-milkwise-1` and `milkwise-test`. |
| W1-P3 | HTTP status only: :3333 = 200, :3334 = 200, Console :8081 = 200. |
| W1-P4 | `curl localhost:8081/api/store-url` returns 6f8m. sha256 of `store-identity/*` and `config.yaml`: hashes only, contents never printed. |
| W1-P5 | Engine rev `27e355a`. sha256 of `/usr/local/sbin/idea-*`, `/etc/sudoers.d/10-engine` and `11-engine-files` (if present). Helper v3 `3f06f298…`. |
| W1-P6 | `df -h` (≥ 5 GB free), temperature < 65 °C, `pm2 jlist` name/status only, `systemctl --failed`, `sudo -n true` (the deploy and the §11.4 copy both need passwordless sudo for `pi`). |
| W1-P7 | `deploy-engine-pi.sh 537b16d… --fetch main --production --dry-run` shows store 6f8m kept, and the files it would save, restore and install. |

**Steps:**
1. Copy the helpers and sudoers to
   `/home/pi/atlas-w1-pre-helpers.quarantine-<ts>`.
2. Run `deploy-engine-pi.sh 537b16d… --fetch main --production --yes`. This
   backs up to `/home/pi/quarantine/engine-deploy-<ts>`, runs
   `install-root-helpers` (v10), then `pm2 restart engine` as `pi`.
3. Post-checks:
   - repeat W1-P2 to W1-P6: MilkWise container IDs and StartedAt unchanged
     (the 12 Nov idea03 deploys left running containers alone; not yet proved
     on idea);
   - :3333, :3334 and :8081 = 200;
   - store still 6f8m;
   - `check-fleet-health.sh --pi wizardly-hugle`.
4. Fleet-state version fix (§11.8), then release.

**Rollback:**
- Run `deploy-engine-pi.sh 27e355a… --production --yes`, or check out
  `27e355a` from the step-2 backup.
- Restore helper v3 and the sudoers from the step-1 copy. Quarantine the v10
  files, never `rm`.
- Run `visudo -c`, then `pm2 restart engine` as `pi`, then redo the
  post-checks.
- If MilkWise stops answering, stop and call Steve. Atlas never touches
  MilkWise.

### 11.4 Window W2: the hub move (after W1)

**Gates:**
- W1 is done;
- #462 and the #444 case B pass on idea03;
- S-4 is decided;
- the Axle points in §11.5 are answered.

**Pre-checks (read-only; the output goes to Steve first):**

| # | Check | Owner |
|---|---|---|
| M-P1 | fleet-state: idea03 and wizardly-hugle `claim: null`. Kid's #159 run 3 is finished. Note idea's system-disk id (store record with `diskTypes: ['system']`). | Atlas |
| M-P2 | idea: W1-P2 to W1-P6 again. Engine on main, helper v10. | Atlas |
| M-P3 | idea03 hub: nodekey `1382c2eab7500ea4`, IP `100.75.102.57`, Running, no AuthURL (`script/check-idea-hub-nodekey.py`, public prefixes only), health 200. Record the version, container IDs and inode. | Kid |
| M-P4 | Last backup on idea03: `backupApp usage-dashboard-8fhwrslsrq78xtswed4 diskb202610301247`, then `listBackup` and `verifyBackup`. Record the archive. | Atlas |
| M-P5 | Names only, never values: the keys in idea03's instance `.env`, for example whether `IDEA_USAGE_SESSION_SECRET` is set. They have to be matched on idea (§11.5 Q1). | Atlas |

**Steps (about 60 min; T = start; never two hubs running):**

| Step | T+ | Owner | Action | Pass |
|---|---|---|---|---|
| 1 | 0 | Atlas | Claim idea03 and wizardly-hugle (`claim "Atlas idea#416 hub move"`; statuses unchanged). Re-run M-P1 to M-P5. | green |
| 2 | 5 | Atlas | On idea, from Console :8081 or `engine-ctl.mjs send`: `installApp usage-dashboard-1.2 <idea-sys-disk-id> --name usage-dashboard`. Online, this takes the GitHub route and pulls the digest-pinned images. It **does start** the instance (§11.5 Q2). With an empty `./data/tailscale` and no `TS_AUTHKEY`, `sidecar-wrap.sh` refuses to start ("no persisted node key … and TS_AUTHKEY is empty"), so no tailscaled runs and **no node registers**. Record the new instance id `<new>` and the port. | install Done; `docker logs` of the new sidecar shows the refusal; the tailnet has no new node |
| 3 | 10 | Atlas | `stopInstance <new> <idea-sys-disk-id>` (operator stop). | all `<new>` containers Exited |
| 4 | 12 | Kid | Snapshot of the idea03 hub (M-P3). No pull in flight. | same as M-P3 |
| 5 | 14 | Atlas | On idea03: `stopInstance usage-dashboard-8fhwrslsrq78xtswed4 <idea03-sys-disk-id>` (operator stop, so it stays stopped across reboots; §11.5 Q3). | no hub container Up on idea03; idea-hub offline on the tailnet |
| 6 | 16 | Atlas | **Manifest before:** on idea03, `sudo find data -path data/tailscale-run -prune -o -printf '%m %U:%G %s %p\n'` and the matching `sudo sha256sum` of every file, run from `/instances/usage-dashboard-8fhwrslsrq78xtswed4`. The files stay on the Pi; Atlas reads the hashes only. | manifest saved |
| 7 | 18 | Atlas | On idea, under `/instances/<new>`, quarantine the fresh install's `data/` with `sudo mv data data.fresh.quarantine-<ts>` (no `rm`). | moved |
| 8 | 19 | Atlas | Copy (route from S-4; R1 shown): `ssh idea03 "sudo tar --numeric-owner --xattrs -cpf - -C /instances/usage-dashboard-8fhwrslsrq78xtswed4 --exclude=data/tailscale-run data" \| ssh idea "sudo tar --numeric-owner --xattrs -xpf - -C /instances/<new>"`. Then create an empty `data/tailscale-run` with the fresh install's owner and mode. Nothing is written on the box. | exit 0 on both ends |
| 9 | 22 | Atlas | **Manifest after** on idea (same command). The diff must be empty: mode, uid:gid, size, path and sha256 of every file, including `data/tailscale/*` and `data/keys/*`. | identical |
| 10 | 24 | Atlas | `startInstance <new> <idea-sys-disk-id>`. | Running; `/api/v1/health` 200 on idea localhost |
| 11 | 27 | Kid | On idea: `BackendState=Running`, no AuthURL, nodekey `1382c2eab7500ea4`, IP `100.75.102.57`, `check-idea-hub-nodekey.py` → `match=true`. Collector pull of idea03 OK. That proves the `from=` pin in `/etc/ssh/idea_usage_keys/pi` on idea03, `restrict,from="100.75.102.57"`, still accepts the hub. | match=true, pull ok |
| 12 | 32 | Atlas | idea unaffected: :3333 and :3334 = 200 (HTTP only), :8081 = 200, MilkWise IDs and StartedAt unchanged, `engine online`, `check-fleet-health.sh --pi wizardly-hugle`, temperature < 75 °C. | unchanged |
| 13 | 36 | Koen | Log in at `http://idea.tail2d60.ts.net:<new port>/`. Check MilkWise and the Console. | Koen OK |
| 14 | 40 | Atlas | If R2 or R3 was used, remove the temporary key and ask Koen to drop the ACL grant. Release both claims. Fleet-state notes: hub on idea as `<new>`; idea03's `8fhwrslsrq78xtswed4` stopped as the rollback source. Evidence to Steve. | pushed |

**The idea03 instance stays stopped and untouched**, data included, as the
rollback source. Do not remove it until Steve and Koen decide to, after a
soak.

**`data/tailscale-run`: leave it out.** It holds only the LocalAPI socket
`tailscaled.sock`. The runbook calls it runtime only, and it is excluded from
backups (`exclude: tailscale-run`). A copied socket is stale. tailscaled
creates a new one at start, and the collector reaches the sidecar through
that same bind mount. Copying `data/tailscale/authkey-join-blocked` is fine,
because it only exists after a failed keyed join. M-P3 should show that
idea03 has none.

### 11.5 Engine and App points: code-based answers, pending Axle confirmation

**Q1. Is `data/` tied to the instance id or `.env`, old `8fhwrslsrq78xtswed4`
versus `<new>`?**

My reading of the code: **no id coupling in `data/`.**
- The collector reads `DATA_DIR=/data`, `REGISTRY_PATH`, `PULL_KEY=/data/keys/pull_key`,
  `TS_SOCKET`, `IDEA_USAGE_*` and `IDENTITY_*` from compose and env.
- Neither the App code nor `compose.yaml` refers to the instance id. The
  compose project, and with it the container names, uses the id, but that
  stays on the Engine side.
- `data/` holds `usage.sqlite`, `registry.json`, `operators.json`,
  `known_hosts`, `backup/`, `keys/` and `tailscale/`. None of them depends on
  the id.
- **`.env` is not in `data/`.** The Engine writes `port=` (new on idea).
  App keys such as `IDEA_USAGE_SESSION_SECRET` default to empty. If idea03
  sets it, the sessions on idea won't match, and users just log in again.
  M-P5 lists the key names, which are then matched through the Console's
  instance env and not by hand-copying `.env`.
- The new instance has its own `x-app` backup links. Backups of `<new>` start
  a new repo (§11.7).

> Axle: ______

**Q2. Can the install run without autostart?**

My reading: **no.** `InstallApp.ts` always ends in `processInstance` →
`tracedStartInstance`, on both the GitHub and the disk route, and
`installApp` has no `--no-start` flag. The `shouldAutoStart` gate only holds
back a store-recorded operator stop or a Stopped status, and a fresh record
has neither.

**Safe anyway.** The App's `sidecar-wrap.sh` exits before containerboot when
there is no persisted node key and `TS_AUTHKEY` is empty, so tailscaled never
starts and no node can register. The compose `restart: unless-stopped`
re-runs the same refusal. We stop it in step 3.

> Axle: ______ (a `--no-start` for installApp would be cleaner)

**Q3. Is the stop persistent?**

My reading: **yes.**
- `stopInstance` (`Instance.ts`) stops each container through the Docker
  API, so Docker's `unless-stopped` won't restart them when the daemon starts.
- It records a `stopApp` operation with an operator cause
  (`console-command`/`cli-command`).
- `AutoStart.ts` `userStopInForce` / `isUserStopped` keep the instance
  Stopped at Engine start, at the 05:00 reboot and on re-dock, until an
  operator start.
- This applies both to idea03's `8fhwrslsrq78xtswed4` (store 2VroE) and to
  idea's `<new>` between steps 3 and 10.

> Axle: ______

**Q4. Does anything depend on the store?**

My reading: **none blocking.** Each instance lives only in its own Engine's
store. 2VroE keeps `8fhwrslsrq78xtswed4` (Stopped), and 6f8m gets `<new>`.
Nothing crosses stores, so neither store needs a hand edit. Side effects:
- idea03's Disk B `BACKUP.yaml` links stay on the old id;
- the old Disk B repo is a rollback source for idea03 only;
- Consoles on the pool still show the stopped hub. That is expected.

> Axle: ______

**Q5. Real command names**, from `docs/COMMANDS.md` and `Commands.ts`. They
are sent from the Console (idea03 :8080, idea :8081) or with the box's
`engine-ctl.mjs send <command> <args>`.

| Command | Used in |
|---|---|
| `installApp <appId> <targetDiskId> [--name …]` | step 2 |
| `stopInstance <id> <diskId>` | steps 3, 5, rollback |
| `startInstance <id> <diskId>` | step 10, rollback |
| `backupApp`, `listBackup`, `verifyBackup` | M-P4 |

`createBackupDisk <diskId> <mode> <instance…>` is for M-6. There is no
`createAppDisk`.

> Axle: ______

### 11.6 Rollback (one hub at a time)

1. On idea: `stopInstance <new> <idea-sys-disk-id>` (operator stop). Check
   that no `<new>` container is Up and that idea-hub shows offline.
2. On idea03: `startInstance usage-dashboard-8fhwrslsrq78xtswed4 <idea03-sys-disk-id>`.
   Kid checks nodekey `1382c2eab7500ea4`, `match=true` and health 200.

**Data after the copy.** Usage pulled on idea after step 10 is not on idea03.
- To keep it: stop both, run steps 6–9 in reverse (idea → idea03), then start
  only idea03.
- Never start an older copy of the Tailscale state while a newer one has run
  elsewhere. Before rolling back after long hours on idea, copy `data/`
  back first (the 2026-11-11 Expired incident).

**Other cases:**
- State lost or rejected: Option B with M-5.
- MilkWise or the Console affected at any step: stop `<new>` first, then
  report to Steve.

### 11.7 M-6: backups on idea (open, proposal)

The Engine refuses the system disk as a Backup target, and Disk B stays on
idea03. idea needs its own Backup Disk.

| Option | How (Engine-native) | For | Against |
|---|---|---|---|
| **B1 (recommended): one dedicated USB SSD on idea** | Koen plugs a spare SSD into a free USB port on idea. `summariseDisk`, then `eraseDisk` it to an IDEA disk, then `createBackupDisk <id> scheduled <new>` (or `on-demand` plus a routine). Later add `milkwise-wizardly-hugle-001` with Koen's OK. | Off the system disk, so a failed boot SSD is survivable. Helper v10 can list, verify and clean it. Same flow as idea03. | A physical step for Koen and a disk to find. Same site, so no off-site copy. Archives are unencrypted, as the helper makes them. Keys and Tailscale state are excluded, so losing all of idea means M-5. |
| B2: idea's internal NVMe (Samsung 256 GB, serial S73YNXMX102912, unmounted bootfs and rootfs today) | `summariseDisk`, `eraseDisk`, `createBackupDisk` | No purchase or plug. Fast. | Wipes what is on it now (it may be Koen's spare OS disk; his call). Same machine, so a power or PSU fault can take both. |
| B3: off-box copy of the hook dump | A box routine pulls the `data/backup/usage.sqlite` hook dump read-only over SSH, without keys or state. | Off-site. Costs nothing. | Not an Engine backup, so no restore path through `restoreApp`. Data passes through the ops box. Needs Steve's OK and a routine. |

**Recommendation: B1** with mode `scheduled`, plus B3 later if Koen wants an
off-site copy. Until M-6 lands, idea03's last Disk B archive (M-P4) and the
stopped idea03 instance are the only copies.

### 11.8 Koen actions (idea#375), decisions for Steve, fleet-state

| Item | Status / ask |
|---|---|
| M-1 | **DONE** (Steve's chat, 10:56 CET). |
| M-2 | Covered by M-1. Window W1 (§11.3), after #462, #444 case B and #463. |
| M-3, M-4 | **Dropped.** No physical step. Disk B stays on idea03. |
| Step 13 | Koen logs in on idea's new dashboard port and checks MilkWise and the Console. |
| M-5 | Rollback only: a single-use `tag:idea-hub` key and reassigning `100.75.102.57`. |
| M-6 | Open: B1, B2 or B3 (§11.7). B1 needs a spare USB SSD from Koen. |
| S-4 | Steve picks the copy route: R1 (box relay, recommended), R2 (LAN with a temporary key) or R3 (direct over Tailscale; Koen adds a temporary ACL grant and a temporary key). |
| #463 | Steve reviews and merges the `deploy-engine-pi.sh --production` case, and confirms the DHCP vendor-class skip. |

**Fleet-state:** the wizardly-hugle `version` field is stale (`745f2c3`,
live `27e355a`). Per Steve (11:00) it is **not** fixed now. It is set through
`tools/fleet/update-fleet-state.sh` when W1 (M-2) lands, straight to the
deployed main sha. Claim and status are not changed outside the windows.

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

**Clashes:** none on idea itself; there is nothing there to clash. With
revision 3 the hub on idea is a fresh `installApp` of 1.2. Online, that takes
the GitHub route and pulls the digest-pinned images, so no idea03 tar
travels. The #327 / #445 web-pin issue (old single-manifest `ef48f1fa` against
the 1.1 index pin `9b5501f0`) then only matters in two cases:

- the install falls back to the offline or tar route; or
- a later App Disk carries an old `services/` tar, which the Engine then
  refuses as `MISMATCH`.

After the install, read-only on idea, confirm two things:

- `docker image inspect` RepoDigests match the 1.2 compose pins;
- no `services/ghcr.io_koenswings_usage-dashboard-web:1.0.tar` is `ef48f1fa`.

When 1.2 lands (#462), the 1.2 bundle replaces the 1.1 reference above.
