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

**Status:** revision 5, 2026-11-12 ~11:50 CET, by Atlas. Steve's decisions of
11:13 are in, along with Axle's review (11:20). It follows Steve's 11:04
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
3. **`deploy-engine-pi.sh` and production idea: done.** #463 is squash-merged
   (idea main `e427aed`). The new `idea|wizardly-hugle` case needs
   `--production`, fixes the store to 6f8m with no override, refuses
   `--production` on every other host, and skips the DHCP vendor-class step
   on production. Steve confirmed that skip on 11:13.
4. **Ports and resources on idea.**
   - The fresh install gets an Engine-allocated `port=`, never 80, 8080, a
     listening port, or a port another instance owns. The web entrypoint
     refuses 80, 3333, 3334 and 8081.
   - Listening ports at the inventory: 22, 3333, 3334, 8081, 9980, 50065,
     53503, 53677, 54189, 54225, 60758, 61312.
   - 58546 was free at the inventory. Step 4 writes `port=58546` into the
     new `.env` before the first real start (S-5), and the Engine keeps it
     because it is free. Koen's dashboard URL becomes
     `http://idea.tail2d60.ts.net:58546/`. The admin → `tag:idea` grant (flow
     F2/F3) covers it.
   - The collector shares the sidecar's network namespace, and the sidecar does
     not mount the host `tailscaled.sock`, so there is no clash with idea's
     tailscaled.
   - Resources: Pi 500, 16 GB RAM (11.3 GB available), 60 GB free on root,
     36.7 °C.
5. **Copy route: S-4 = R1, a tar stream relayed by the box** (Steve, 11:13).
   - The live ACL denies `tag:idea` → `tag:idea` (flow F8), and Pi SSH key
     changes are a standing no. So the copy never goes Pi to Pi.
   - The ops box (`autogroup:admin`, flow F1) reaches both Pis on :22. It
     streams `ssh idea03 sudo tar … | ssh idea sudo tar …`.
   - The stream is never stored: no temp file on the box, nothing on the box
     disk. The pull key and node key are never printed.
   - If a temp file ever proves unavoidable, wipe it with `shred -u` right
     after step 9 and record that in the evidence.
   - The exact pipeline is in §11.4 step 8.

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

### 11.3 Window W1 (M-2): Engine main (`f1c7c0e` or later) + helper v10 on idea

**Gates, all required:**
- idea#462 (1.2 on idea03) has landed;
- the idea#444 case B has passed;
- #463 has merged (done: `e427aed`).

**Engine sha:** deploy agent-engine-dev main **as it is at window time**,
`f1c7c0e` or later, so it includes the #459 fix. Pin it when W1 starts by
reading `git rev-parse origin/main` in a fresh box clone, check that it
contains `f1c7c0e` (`git merge-base --is-ancestor f1c7c0e <sha>`), and
record the full sha in the W1 evidence and in fleet-state.

**Pre-checks (read-only; Atlas sends the output to Steve before W1 starts):**

| # | Check |
|---|---|
| W1-P1 | fleet-state wizardly-hugle has `claim: null` and status `production`. Atlas claims it for W1; status stays `production`. |
| W1-P2 | `docker ps -a` saved: IDs, StartedAt, ports. Especially `milkwise-wizardly-hugle-001-milkwise-1` and `milkwise-test`. |
| W1-P3 | HTTP status only: :3333 = 200, :3334 = 200, Console :8081 = 200. |
| W1-P4 | `curl localhost:8081/api/store-url` returns 6f8m. sha256 of `store-identity/*` and `config.yaml`: hashes only, contents never printed. |
| W1-P5 | Engine rev `27e355a`. sha256 of `/usr/local/sbin/idea-*`, `/etc/sudoers.d/10-engine` and `11-engine-files` (if present). Helper v3 `3f06f298…`. |
| W1-P6 | `df -h` (≥ 5 GB free), temperature < 65 °C, `pm2 jlist` name/status only, `systemctl --failed`, `sudo -n true` (the deploy and the §11.4 copy both need passwordless sudo for `pi`). |
| W1-P7 | `deploy-engine-pi.sh <W1-sha> --fetch main --production --dry-run` shows store 6f8m kept, and the files it would save, restore and install. |

**Steps:**
1. Copy the helpers and sudoers to
   `/home/pi/atlas-w1-pre-helpers.quarantine-<ts>`.
2. Run `deploy-engine-pi.sh <W1-sha> --fetch main --production --yes`. This
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
- W1 is done.
- #462 and the #444 case B pass on idea03.
- **The usage-dashboard 1.2 release is tagged.** Steve handles the tag.

**Steve's decisions (11:13):**
- S-4 = R1.
- S-5, S-6 and S-7 are approved.
- S-8 = V1: a fresh 1.2 install. The V2 route (1.1, then `updateApp`) is dropped.

**Before W2:** every App-side point Axle reviewed against 1.1 (`88944fd`) is
re-checked against the 1.2 tag:
- the empty-state guard in `sidecar-wrap.sh`;
- the `.env` keys;
- the `data/` layout;
- any 1.1 → 1.2 schema migration on first start, which is **pending Kid**.

**Pre-checks (read-only; the output goes to Steve first):**

| # | Check | Owner |
|---|---|---|
| M-P1 | fleet-state: idea03 and wizardly-hugle have `claim: null`. Kid's #159 run 3 is finished. Note idea's system-disk id and idea03's (the store record with `diskTypes: ['system']`). | Atlas |
| M-P2 | idea: repeat W1-P2 to W1-P6. Engine on main, helper v10. `id pi` shows uid 1000 on idea and on idea03. Port 58546 is not listening. | Atlas |
| M-P3 | idea03 hub: nodekey `1382c2eab7500ea4`, IP `100.75.102.57`, Running, no AuthURL (`script/check-idea-hub-nodekey.py`, public prefixes only), health 200. Record the version, container IDs and inode. `data/tailscale/authkey-join-blocked` is **absent**. | Kid |
| M-P4 | Last backup on idea03: `backupApp usage-dashboard-8fhwrslsrq78xtswed4 diskb202610301247`, then `listBackup` and `verifyBackup`. Record the archive. | Atlas |
| M-P5 | idea03 instance `.env`, **key names only, never values**: `port`, `port_zip` (if present), `IDEA_USAGE_KOEN_PASSWORD`, `IDEA_USAGE_MARCO_PASSWORD`, `IDEA_USAGE_SESSION_SECRET`. Also confirm there is no `TS_AUTHKEY` line. | Atlas |
| M-P6 | Service tars on idea (`pull_policy: never`; no install route copies `services/`): idea's `/services` holds the three tars for the chosen version. They match the release sha256 values and `verify-service-tar.sh` says `MATCH` against the compose pins (§12). If they are missing, the copy from the box's verified release dir is S-7. | Atlas |

**Steps (about 60 min; T = start; never two hubs running):**

| Step | T+ | Owner | Action | Pass |
|---|---|---|---|---|
| 1 | 0 | Atlas | Claim idea03 and wizardly-hugle (`claim "Atlas idea#416 hub move"`; statuses unchanged). Re-run M-P1 to M-P6. | green |
| 2 | 5 | Atlas | On idea (Console :8081 or `engine-ctl.mjs send`): `installApp usage-dashboard-1.2 <idea-sysDiskId> --name usage-dashboard`. Online it takes the GitHub route; no `--fresh`. **It always starts** (Axle). The sidecar refuses to start because `data/tailscale` and `TS_AUTHKEY` are both empty, so no node registers and no login URL is used. The collector and web start briefly with empty data. Record `<newId>` and its port. | Install Done. The new sidecar log shows the refusal. No new tailnet node. |
| 3 | 8 | Atlas | `stopInstance <newId> <idea-sysDiskId>`. Commands run one at a time, so this runs after the install's start. | `docker ps -a`: all `<newId>` containers Exited |
| 4 | 10 | Atlas (S-5) | Into `/instances/<newId>/.env`: write `port=58546`. Copy over `IDEA_USAGE_KOEN_PASSWORD`, `IDEA_USAGE_MARCO_PASSWORD` and `IDEA_USAGE_SESSION_SECRET` by key name from idea03, values never printed (piped over the S-4 route). Never copy the old `.env` whole, and never add `TS_AUTHKEY`. This is a **hand edit of an Engine file and needs Steve's OK**. | `.env` key names match M-P5; no `TS_AUTHKEY` |
| 5 | 13 | Kid | Snapshot the idea03 hub (M-P3). No pull in flight. | as M-P3 |
| 6 | 15 | Atlas | On idea03: `stopInstance usage-dashboard-8fhwrslsrq78xtswed4 <idea03-sysDiskId>`. Then `docker ps -a` and `docker inspect -f '{{.State.Status}} {{.RestartCount}}'` on all three hub containers. The `kill()` fallback path has not been verified. | No hub container Up on idea03; idea-hub offline on the tailnet. **From here on nobody presses Start on 2VroE.** |
| 7 | 17 | Atlas | **Manifest before**, on idea03, from `/instances/usage-dashboard-8fhwrslsrq78xtswed4`: `sudo find data -path data/tailscale-run -prune -o -printf '%m %U:%G %s %p\n'` and `sudo sha256sum` of every file. Only hashes leave the Pi. | saved |
| 8 | 19 | Atlas (S-6, S-4 = R1) | **Root copy outside the Engine, as a tar stream relayed by the box and never stored.** No Engine command copies across stores (Axle). (a) On idea: `ssh idea "sudo mv /instances/<newId>/data /instances/<newId>/data.fresh.quarantine-<ts>"` (no `rm`). (b) From the box, with `set -o pipefail`: `ssh pi@100.126.117.80 "sudo tar --numeric-owner --acls --xattrs --exclude=data/tailscale-run -cpf - -C /instances/usage-dashboard-8fhwrslsrq78xtswed4 data" \| ssh pi@100.115.60.6 "sudo tar --numeric-owner --acls --xattrs --same-owner -xpf - -C /instances/<newId>"`. Both legs go through the box's usual Tailscale SOCKS `ProxyCommand` (`nc -x 127.0.0.1:1055`). Nothing is written on the box. (c) On idea: `sudo install -d -o <uid> -g <gid> -m <mode> /instances/<newId>/data/tailscale-run`, with uid, gid and mode taken from `data.fresh.quarantine-<ts>/tailscale-run`. | Both ends exit 0 (pipefail). No file was created on the box. |
| 9 | 22 | Atlas | **Manifest after**, on idea, with the same command. Diff against step 7. `authkey-join-blocked` is absent. | Identical: mode, uid:gid, size, path and sha256 of every file, including `data/tailscale/*` and `data/keys/*` |
| 10 | 24 | Atlas | `startInstance <newId> <idea-sysDiskId>`. `TS_AUTHKEY` stays empty. | Running, on `:58546`. `/api/v1/health` 200 on idea localhost. |
| 11 | 27 | Kid | On idea: `BackendState=Running`, no AuthURL, nodekey `1382c2eab7500ea4`, IP `100.75.102.57`, `check-idea-hub-nodekey.py` gives `match=true`. A collector pull of idea03 works, which proves the `from=` pin (`restrict,from="100.75.102.57"` in idea03's `/etc/ssh/idea_usage_keys/pi`). V2 only: `updateApp` to 1.2 on idea, then repeat this check. | match=true, pull ok |
| 12 | 32 | Atlas | idea unaffected: :3333 and :3334 = 200 (HTTP only), :8081 = 200, MilkWise container IDs and StartedAt unchanged, `engine online`, `check-fleet-health.sh --pi wizardly-hugle`, temperature < 75 °C. | unchanged |
| 13 | 36 | Koen | Log in at `http://idea.tail2d60.ts.net:58546/` (same port, same logins). Check MilkWise and the Console. | Koen OK |
| 14 | 40 | Atlas | Confirm no temp file on the box (and `shred -u` any that had to be made). Release both claims. Fleet-state notes: the hub is on idea as `<newId>`. idea03's `8fhwrslsrq78xtswed4` is stopped, as the rollback source. Evidence goes to Steve. | pushed |
| 15 | ≥ 24 h after step 10, with a clean `from=` pull in that time, and only after M-6 (§11.7) | Atlas (S-9, approved by Steve) | On idea03: `removeInstance usage-dashboard-8fhwrslsrq78xtswed4`. It runs `compose down` without `-v`, moves the folder to `/.idea-quarantine/<id>-<stamp>` and drops the 2VroE record. Steve approved it at 11:13 under these conditions (it behaves like a deletion, but nothing is deleted). After this, no Engine path can start the old identity. Until then, the stopped instance is the rollback source. | quarantine path logged |

**`data/tailscale-run`: leave it out.** It holds only the LocalAPI socket and
the `restart-requested` flag, which are runtime-only. The backup contract also
excludes it, and a copied socket would be stale. tailscaled makes a new one,
and the wrapper clears the old in-state flag (Axle).

**Nothing in `data/` depends on the old id, on idea03 or on the store**
(Axle, §11.5).

### 11.5 Engine and App points (Axle, 2026-11-12 ~11:20 CET, `/workspace/axle-461-hubmove/REVIEW-461.md`)

Axle reviewed Engine main `537b16d` and App `88944fd` (1.1). He did **not**
review 1.2, because it doesn't exist yet. Every App-side point needs a
re-check against 1.2.

**Q1. Is `data/` tied to the instance id, the host or the store?** No.
- `collector/`, `compose.yaml`, `web/` and `app.yaml` contain no instance id,
  no host name and no store id.
- `registry.json` lists the kits, not the hub's own host.
- The compose project and container names come from the id (new id → new
  containers). The App uses only bind mounts and a tmpfs: no named volumes,
  no Engine labels.
- **`.env` is the one coupling.** It holds the Engine-written `port=` (and
  `port_zip=` if present) and the App keys `IDEA_USAGE_KOEN_PASSWORD`,
  `IDEA_USAGE_MARCO_PASSWORD` and `IDEA_USAGE_SESSION_SECRET`. Carry those
  over by key name, plus `port=58546`, before the first real start. Step 4
  covers this (S-5). On start the Engine keeps a `.env` port unless that port
  is listening, reserved or owned in the store.

**Q2. Can the install skip the start?** No.
- Every route ends in `processInstance` → `tracedStartInstance`, and there
  is no `--no-start` flag.
- The new id is minted during the install, so nothing can be pre-seeded.
- It is safe for identity because of the empty-state guard in
  `sidecar-wrap.sh`: no `tailscaled`, it sleeps for 3600 s, then exits with 1.
- Conditions:
  - no `TS_AUTHKEY` in the new `.env`;
  - 1.2 keeps the guard;
  - the brief start of the collector and web on empty data is accepted.
- Service tars: `pull_policy: never`, and **no install route copies
  `services/`**. The tars for the chosen version must already be in idea's
  `/services` (M-P6 / S-7), or the start ends in `Error`.

**Q3. Does the stop on idea03 persist?** Yes.
- `stopInstance` stops the containers through the Docker API (`kill()` if
  that fails), keeps them (no `down`), sets the status to `Stopped` and
  records an operator `stopApp` in 2VroE.
- At Engine start or a reboot, `checkAndSetUndockedApps` and the
  `processSystemInstance` gate both keep it Stopped.
- Docker's `unless-stopped` does not restart containers that were stopped
  explicitly. This is not verified for the `kill()` path, so step 6 checks it
  with `docker ps -a` and `docker inspect`.
- **Things that can still revive it:** an explicit `startInstance` or
  `runInstance` from any Console or CLI on 2VroE, or an `updateApp`. A backup
  of a stopped hub does not restart it.
- Hence the step-15 `removeInstance`.

**Q4. Does anything depend on the store?** No blocker.
- The new instance is a fresh 6f8m record (`lastBackup: null`, no history).
- The 2VroE record stays until step 15. The stores never sync, so nothing
  clashes.
- Disk B's `BACKUP.yaml` still links the old id (see §11.7).

**Q5. Real commands:**
- step 2: `installApp <appId> <targetDiskId> [--source <diskId>] [--name …]`
- steps 3, 6 and the rollback: `stopInstance <id> <diskId>`
- step 10 and the rollback: `startInstance <id> <diskId>`
- M-P4: `backupApp`, `listBackup`, `verifyBackup`
- step 15: `removeInstance <id>`
- M-6: `summariseDisk`, `eraseDisk`, `createBackupDisk <diskId> <mode> <instance…>`

**Copy (S-6): an ops root step that needs its own approval.**
- No Engine command can do it. Cross-engine `copyApp` needs a shared store
  and mints a new id, `moveApp` refuses remote targets, and Engines on
  different stores refuse to peer at all.
- Keep numeric owners (the Engine's own copy uses `-aHAX --numeric-ids`).
- `pi` is uid 1000 on both Pis (M-P2). The container uids are the same,
  because the images are the same.

**Other notes:**
- The `/.pre-update/<id>` snapshot from #443 on idea03 excludes
  `data/tailscale`, so it cannot revive the identity. It is never deleted
  automatically.
- 1.1 → 1.2 schema: **pending Kid**. Re-check it at the 1.2 tag, before W2 (§11.4).

### 11.6 Rollback (one hub at a time)

Only possible before step 15:

1. On idea: `stopInstance <newId> <idea-sysDiskId>`. Then `docker ps -a`
   shows no `<newId>` container Up, and idea-hub is offline.
2. On idea03: `startInstance usage-dashboard-8fhwrslsrq78xtswed4 <idea03-sysDiskId>`.
   Kid checks nodekey `1382c2eab7500ea4`, `match=true` and health 200.

**Data written after step 10.** Usage pulled on idea after step 10 is not on
idea03. If it matters, stop both instances, repeat steps 7–9 in the other
direction (idea → idea03), then start only idea03.

**Never start an older copy of the Tailscale state after a newer one has
run.** idea03's copy is older once idea has run. After a long run on idea,
copy `data/` back before you start idea03 (the 2026-11-11 Expired incident).

**Other cases:**
- After step 15: the only way back is to move the folder back out of
  `.idea-quarantine` by hand, with Koen's OK, or Option B (M-5).
- State lost or rejected: Option B with M-5.
- MilkWise or Console affected at any step: stop `<newId>` first, then report
  to Steve.

### 11.7 M-6: backups on idea, B1 decided (Steve, 11:13)

**B1: one dedicated USB SSD on idea, used as its Backup Disk.** It can come
after the move, but **must be done before step 15 (S-9)**.

The Engine refuses the system disk as a Backup target, and Disk B stays on
idea03.

**Disk: Intenso 256 GB, serial `532609003NA000324`.** *Pending Koen
plug-in (#375).* For the evidence and the second choice, see the table below.

**Steps:**
1. Koen plugs the SSD into a free USB port on idea. Leave the "Flash Drive
   FIT" and the NVMe where they are. One #375 item.
2. Atlas confirms it read-only by **serial** (`lsblk -o NAME,SERIAL,SIZE`,
   `smartctl -H`), never by device name, and checks it is not the root SSD
   `AA000000000000000724`.
3. `summariseDisk <id>`, then `eraseDisk <id> <summaryTraceId> <confirmName>`
   within 10 minutes. The disk comes back as an IDEA disk, `['empty']`.
4. `createBackupDisk <id> scheduled <newId>`.
5. First backup and checks: `backupApp <newId> <id>`, then `listBackup` and
   `verifyBackup`. The keys and Tailscale state must be absent from the
   archive.

**Trade-offs:**
- *For:* the backup lives off the system disk, so a failed boot SSD can be
  survived. Helper v10 can list, verify and clean it, the same flow as on
  idea03. MilkWise can be added later, with Koen's OK.
- *Against:* it needs one physical step from Koen. It is on the same site,
  so there is no off-site copy. The archives are unencrypted, as the helper
  makes them. Keys and Tailscale state are excluded, so losing all of idea
  means M-5.
- *Later, optional:* a box routine that pulls the hook dump off-site (B3).

**Picking the disk by serial.** Excluded: Disk B `3813430-532011020`, the WD
`20070Q450002`, the protected fixture `AA000000000000005638`,
`AA000000000000001430`, every `refuseSerials`, every App/Files/Backup
fixture, and every Pi boot disk.

| Serial | What the evidence shows | Verdict |
|---|---|---|
| **`532609003NA000324`** (Intenso, 256 GB / 238.5 G) | idea#139 "Final disk roles" (Atlas, 2026-10-30 10:50 CET): on **idea02**, role **Spare**, "SMART PASSED, untouched, unpartitioned". Box `disks139/state.md` and `i2-1109.txt` show it as idea02 `sdb` with no partitions next to the root SSD `AA000000000000055060`. Not in fleet-state, the disk docs, any `refuseSerials`, or any later issue or note. | **Recommended.** Medium-high confidence: last seen 2026-10-30 as an unused spare. idea02 is on hold, so taking out a non-root USB disk does not touch its OS or MilkWise. Koen confirms by the serial on the label. |
| `2026080400771` (Intenso, 128 GB) | idea#139 10-30: on idea01, the **#79 Move target**, made an empty IDEA App disk (diskId `cd8787b352df466b86d91975fe3a372b`). `tools/fleet/move-79.sh` pins `TGT_SERIAL=2026080400771`. The #79 run (PR #390) is queued. | **Second choice**, only after #79 has run and Steve releases it. |
| `AA000000000000001278` (Intenso, 232.9 G) | Box `duration-evidence/stage2-plan/README.md`: **⛔ DO-NOT-USE (2026-10-09)**: "silently drops writes, UAS disconnects, partition table does not persist". Same in `stage2-ssd-20261009/SUMMARY.md`. Removed by Koen. | **Excluded.** This contradicts the "worked" note. A later retest might clear it, but none was found. |
| `AA000000000000009991` (Intenso, 111.8 G) | The idea01 Stage 2 duration SSD: `DUR-KOLIBRI` sda1 and `ADDFILES01` sda2 (DURATION_TESTS / `READY.md`, still on idea01 in the 10-14 hw193 log). The #139 read-only poll on 10-30 saw idea01 with "system SSD only", so it has been unplugged and its whereabouts are unknown. It still holds fixture data. | **Excluded**, unless Koen says the Stage 2 fixture is retired. |
| `1642504001002428` (Intenso, 119.2 G) | idea04 sda1 is the FAT32 **IDEA-DEMO** stick (the idea#193 stick in agent-engine-dev `script/hw-usb-sticks.json` for idea04). sda2 is `DUR-EMPTY003` (DURATION_TESTS, 2026-10-15). | **Excluded**: in use as a fixture. |
| `AA000000000000055000`, `AA000000000000055060`, `AA000000000000010473`, `AA000000000000003120`, `AA202000000000004820`, `AA202000000000002167`, `AA000000000000000724` | Boot disks: idea01, idea02, happy-zebra, sunny-robin, idea03, idea04 and idea itself (fleet-state, the #139 survey, this run's inventory). | Excluded. |

**Disk B's link to the old id.** Disk B's `BACKUP.yaml` on idea03 still links
`usage-dashboard-8fhwrslsrq78xtswed4`. Links are keyed only by instance id,
and the Engine has no per-link remove: `createBackupDisk` rewrites the whole
list. So the link stays. It is harmless while the old instance is stopped,
and once it is removed (step 15) it points at nothing. Per S-10, leave it alone. Disk B
stays idea03's test Backup Disk. Either
way, Disk B's hub repo stays idea03-side history only.

### 11.8 Koen actions (idea#375), decisions for Steve, fleet-state

| Item | Status / ask |
|---|---|
| M-1 | **DONE** (Steve's chat, 10:56 CET). |
| M-2 | Covered by M-1. Window W1 (§11.3), after #462, #444 case B and #463. |
| M-3, M-4 | **Dropped.** No physical step. Disk B stays on idea03. |
| Step 13 | Koen logs in at idea:58546 and checks MilkWise and the Console. |
| M-5 | Rollback only: a single-use `tag:idea-hub` key and reassigning `100.75.102.57`. |
| M-6 | **B1** (§11.7): Koen moves the Intenso 256 GB `532609003NA000324` from idea02 to a free USB port on idea. *Pending Koen plug-in (#375).* After the move, before S-9. |

| Decision | Steve, 2026-11-12 11:13 CET |
|---|---|
| W1 sha | Engine main at window time, `f1c7c0e` or later (#459 fix included). Pinned and recorded at W1. |
| #463 | Squash-merged (`e427aed`). DHCP vendor-class skip on production confirmed. |
| S-4 | R1: a tar stream relayed by the box, never stored (§11.4 step 8). |
| S-5, S-6, S-7 | Approved. |
| S-8 | V1: fresh 1.2, waiting on the 1.2 release tag (Steve). V2 dropped. |
| S-9 | Approved after ≥ 24 h of soak with a clean `from=` pull, and after M-6. |
| S-10 | Leave Disk B's link alone. It goes with `removeInstance` at S-9. Disk B stays idea03's test Backup Disk. |

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
