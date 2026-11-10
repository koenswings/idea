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
- `usageMonitoring` toggle script waits on Axle's idea#411 interface.
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

Same claim rules as §2. This is also where helper v8 and the restricted
export key are proved (`prove-usage-export-key.sh`, idea#412):

- Throwaway key generated on the box, `from=` pinned to the **box**
  Tailscale IPv4 (stand-in for the sidecar IP).
- Use Axle's helper v8 and `/usr/local/sbin/idea-usage-export` if a
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

Helper v8 must extend **that same line** (Debian reads `sshd_config.d`
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

## 6. Helper v8 pool rollout

After Axle's helper v8 has merged and the pool-Pi proof in §4 passed.
One Pi at a time. Never two down. Pause above 75 °C, resume below 65 °C.
pm2 always as `pi`. No `pkill` / `pgrep -f`.

Order:

1. An idle, unclaimed spare: idea03 or idea04 (whichever the proof did
   not leave dirty; prefer a fresh idle Pi). Claim as Atlas, install
   helper v8 (including the drop-in and `idea-usage-export`), health
   check, release.
2. The other spare, same way.
3. **idea01 (golden) only from merged main**, after the helper v8 PR
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
- helper v8, `/etc/ssh/idea_usage_keys/%u`, the updated
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
   with the `tools/fleet` toggle (once idea#411 defines the verb).
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

Not written yet. It waits on Axle (idea#411) for the persistent
`usageMonitoring: off | on` setting and the SSH or helper verb that
flips it without restarting the Engine or the Apps. When that verb
exists, the script will:

- take one kit (or pool Pi) at a time
- refuse kits outside an approved window, golden-as-test, idea, and
  claimed Pis
- print JSON (`ok`, previous value, new value)
- be covered by an offline test with fake ssh

## 10. Health-check checklist (copy per Pi)

```
tools/fleet/check-fleet-health.sh --origin --pi <name>
```

Read `claimed_with_problems` as well as failures. Release only when
ssh works, `engine` is online as `pi`, and Console HTTP 200 on the
Pi's `console_port`. On idea, also confirm MilkWise was not touched.
