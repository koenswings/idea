# Field-usage U-item checklist (idea#375 → idea#416)

**Status:** Prepared, not applied · **Maintained by:** Atlas · 2026-11-11
**Do not treat this file as permission to tag a node, edit the live ACL, or
install a key.** Default is `--dry-run`. Do not pass `--apply` while a Pi
is claimed, while idea04 is mid-monitoring work, or before Koen finishes
the matching U-item.

Related: [idea#375](https://github.com/koenswings/idea/issues/375),
[idea#416](https://github.com/koenswings/idea/issues/416),
[idea#412](https://github.com/koenswings/idea/issues/412),
[`field-usage-acl.md`](field-usage-acl.md),
[`field-usage-rollout.md`](field-usage-rollout.md),
[`tag-fleet-idea-tc.md`](tag-fleet-idea-tc.md),
[`tag-fleet-idea.sh`](tag-fleet-idea.sh),
[`field-usage-after-u-steps.sh`](field-usage-after-u-steps.sh).

**Never paste a key or token into chat or GitHub.** Point at a 0600 path.

## What runs after Koen's U-steps, and what we need from him

Once Steve says the U-items below are done, Atlas runs (one Pi at a time,
order **idea03, idea04, idea02, idea01**), starting with a dry-run:

```
tools/fleet/field-usage-after-u-steps.sh plan
tools/fleet/field-usage-after-u-steps.sh preflight
```

Then, only when the target Pi is idle and unclaimed (idea02 stays `hold`):

```
tools/fleet/field-usage-after-u-steps.sh precheck --pi idea03
tools/fleet/field-usage-after-u-steps.sh --apply tag --pi idea03
# Koen clicks Edit tags + Disable key expiry; the script waits and post-checks.
tools/fleet/field-usage-after-u-steps.sh --apply probe-acl --from-pi idea03
```

After the sidecar exists and U-4 is live, a forced-command proof uses paths
Steve was told (never the key values):

```
USAGE_PULL_PUBKEY_FILE=… USAGE_PULL_PRIVKEY_FILE=… SIDECAR_IPV4=100.x.y.z \
  tools/fleet/field-usage-after-u-steps.sh --dry-run install-key --pi idea03
# --apply install-key is refused until a follow-up apply window is agreed.
tools/fleet/field-usage-after-u-steps.sh --dry-run verify --pi idea03
tools/fleet/field-usage-after-u-steps.sh --dry-run rollback-key --pi idea03
```

This script **never** applies a tag, never prints credentials, and never
touches idea / wizardly-hugle or the kits (those wait on idea#374).

## U-item → script step map

| Item | Who | What | What it unblocks |
|---|---|---|---|
| **T-b** | Koen (console) | Read the live ACL. Confirm the admin source (`group:admins` or whatever is already defined) and that `tagOwners` includes `tag:idea` with `admins → tag:idea`. | Safe merge of the Step A/B paste in `field-usage-acl.md`. `field-usage-after-u-steps.sh preflight` then records the observable tag state via read-only `tailscale status` / `whois`. status/whois cannot see unused `tagOwners`; T-b remains the console confirmation. |
| **U-1** | Koen | Create `tag:idea-hub`. Do **not** retag idea (`100.115.60.6`). | Step A paste (`field-usage-acl-step-a.hujson`). Sidecar registration can use the tag. `preflight` will only *see* the tag once a node carries it (U-3). |
| **U-2** | Koen | Grant admins access to `tag:idea-hub` **first**, before the sidecar exists. | Safe to register the sidecar. Koen can still reach it later. Not observable from status/whois until a node exists. |
| **U-3** | Koen | Create one tagged, non-ephemeral auth key for this sidecar only. Store it as a **0600** file; tell Steve **only the path**. | Sidecar registration (scratch App on idea03 or idea04 first, never idea first, never idea01). The script checks `IDEA_HUB_AUTHKEY_FILE` exists, is non-empty and 0600; it does not print or copy the key. |
| *(sidecar register)* | Atlas, after U-1..U-3 and Kid's App | Userspace Tailscale sidecar, state under the App `./data`, record its 100.x IPv4. | U-4, U-5, and every kit `from=` line. `preflight` discovers `SIDECAR_IPV4` from `tag:idea-hub` once the node is up. |
| **U-5** | Koen | After the admin grant and registration, confirm Console and MilkWise still work on **3333** and **3334**. | Atlas does not probe those ports on idea. This confirmation is what allows U-4. |
| **U-4** | Koen | Add `tag:idea-hub → tag:idea` on **tcp/22 only** (plain OpenSSH, not Tailscale SSH). Keep `tag:idea` unable to initiate anything. | `probe-field-usage-acl.sh hub-to-idea` (tcp/22 open; 80, 3333, 3334, 8080, 8081 denied) and the install-usage-key verification: idea-hub can reach `tag:idea` on tcp/22. Rollback of this rule is `field-usage-acl.md` § Rollback (remove the Step B line only). |
| **U-6** | Koen (note) | If sidecar state is lost, re-register with the U-3 key and assign the **previous** 100.x IPv4. | Existing `from=` lines keep working. Atlas records the IPv4 in the runbook once the node exists (not a secret). |
| **U-7, U-8, U-9** | Koen (decisions) | Scorecard thresholds; who tells the schools; who besides Koen may open the dashboard. | No Ops script step. Not a blocker for T-c or the ACL matrix. |
| **T-c** | Koen clicks, Atlas pre/post-checks | Tag fleet Pis as `tag:idea` in order **idea03, idea04, idea02, idea01**. After each Edit tags, also **Disable key expiry**. Do not run `tailscale up --advertise-tags`. Defer idea / wizardly-hugle until Koen's OK / idea#374. | `field-usage-after-u-steps.sh tag --pi <name>` (delegates to `tag-fleet-idea.sh`). After a Pi is tagged, `probe-acl idea-to-idea --from-pi <that-pi>` must show Pi-to-Pi over Tailscale denied. Rollback: `tag-fleet-idea-tc.md` §7 (restore `admins → tag:idea` if SSH is lost; do not take the last tag off in the console). idea02 stays `hold`; do not deploy to it. |

## Verification matrix (after the unblocking U-item)

1. **idea-hub → tag:idea tcp/22** — unblocked by U-4. `probe-acl` / `probe-field-usage-acl.sh hub-to-idea`.
2. **Forced-command export through `install-usage-key`** — unblocked by U-3 (sidecar IP / key path) and U-4 (tcp/22). Public key and auth key are read from box paths only. Undo is `rollback-key` (quarantine, never `rm -rf`).
3. **Pi-to-Pi over Tailscale denied** — unblocked by T-c (fleet nodes actually carry `tag:idea`) plus the standing “no `src` `tag:idea`” ACL. `probe-acl idea-to-idea`.

## Rollbacks (per step)

| Step | Rollback |
|---|---|
| T-c tag change, SSH lost | Restore `admins → tag:idea:*` in the ACL (T-b / Step A). Do not try to remove the last tag. Do not tag the next Pi. |
| T-c tag change, SSH still works and the tag must come off | Open session: `sudo tailscale up --force-reauth` *without* `--advertise-tags`, then Koen's browser login (`tag-fleet-idea-tc.md` §7). |
| U-4 tcp/22 grant | Remove only the Step B `tag:idea-hub → tag:idea:22` line; put the Step A tests back (`field-usage-acl.md`). |
| install-usage-key | `rollback-key`: quarantine `/etc/ssh/idea_usage_keys/pi` and any edited drop-in as `.quarantine-<utc>`; restore the pre-install `10-idea-peer.conf`; confirm operator SSH; `check-fleet-health.sh --pi <name>` with no `--alert`. |

## What we need from Koen (short list)

1. Tick T-b (live ACL admin source, `tag:idea` owners and admin grant).
2. Tick U-1 and U-2 (create `tag:idea-hub`, admin grant, do not retag idea).
3. Tick U-3 and tell Steve **only the 0600 auth-key path**.
4. After Atlas registers the sidecar and records its 100.x IPv4: tick U-5 (Console / MilkWise 3333 and 3334), then tick U-4 (tcp/22 only).
5. For T-c, click **Edit tags → tag:idea** and **Disable key expiry** on one machine at a time, in the order idea03, idea04, idea02, idea01, when Atlas says that Pi's precheck is green. Do not tag idea / wizardly-hugle in this pass.
6. Keep U-6 as a standing recovery note. U-7..U-9 are decisions, not blockers for the scripts above.
