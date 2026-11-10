# Field-usage Tailscale ACL (idea#416)

**Status:** Ready to paste, not yet applied · **Maintained by:** Atlas · 2026-11-10
**Waits on:** Koen's idea#375 U-1 to U-5 (admin console). Nobody else edits the live ACL.

This is the paste-ready ACL change for field-usage monitoring
([proposal](../../proposals/2026-11-09-field-usage-monitoring.md) §7.5 and §14 Atlas,
[idea#416](https://github.com/koenswings/idea/issues/416),
[idea#375](https://github.com/koenswings/idea/issues/375) U-1 to U-6).
HuJSON snippets sit next to this file:

- [`field-usage-acl-step-a.hujson`](field-usage-acl-step-a.hujson) — U-1 and U-2
- [`field-usage-acl-final.hujson`](field-usage-acl-final.hujson) — after U-4

The live runtime probe is [`probe-field-usage-acl.sh`](probe-field-usage-acl.sh).
The ordered rollout is [`field-usage-rollout.md`](field-usage-rollout.md).

**Contains no secret values.** Do not paste an auth key, token or private key
anywhere in these files or in GitHub.

## What is known of the current policy

There is **no checked-in copy** of the live tailnet policy. idea#375 item T-b
(read the ACL) is still open.

The last approved sketch
([`proposals/2026-10-13-tailscale-single-fleet-tag.md`](../../proposals/2026-10-13-tailscale-single-fleet-tag.md))
is:

```json
{
  "tagOwners": { "tag:idea": ["group:admins"] },
  "acls": [
    { "action": "accept", "src": ["group:admins"], "dst": ["tag:idea:*"] }
  ]
}
```

With no rule whose `src` is `tag:idea`, tagged Pis cannot initiate any
connection on the tailnet. That is the property we must keep.

A read-only ops audit on 2026-10-29 ([idea#117](https://github.com/koenswings/idea/issues/117),
recorded in `docs/ops/security-overview.md`) found that the live picture
still differs from that design:

- Kit Pis and kit routers already carry `tag:idea`.
- The five fleet nodes (idea01–04 and `idea` / wizardly-hugle, 100.115.60.6)
  were **untagged**, with node-key expiry still on. Tagging them is idea#375 T-c
  and is separate from this change.
- It was not confirmed in the console whether the live admin source is
  `group:admins`, `autogroup:admin`, or another existing group.

**Before pasting anything:** do T-b (or re-read Access controls) and replace
every `group:admins` in the snippets with the live admin source if it differs.
Do not invent a `group:admins` that is not already defined. Unknown group
names make Tailscale reject the save.

Merge the blocks into the live file. Do **not** replace the whole policy:
keep every unrelated rule (`hosts`, `ssh`, `nodeAttrs`, other `grants`/`acls`,
… ) unchanged. Do **not** add Tailscale SSH rules. Pulls use plain OpenSSH.

If the live file already uses `grants` instead of (or as well as) `acls`,
use the equivalent grants at the end of each step rather than adding a
second, conflicting `acls` section.

## What we are adding

- A new tag, `tag:idea-hub`, owned by the same admins who own `tag:idea`.
- Admin access to `tag:idea-hub` **before** the sidecar node exists.
- After the sidecar is registered and Console / MilkWise on 3333 and 3334
  still work: `tag:idea-hub` may reach `tag:idea` on **tcp/22 only**.
- ACL `tests` that Tailscale evaluates on every save:
  - `tag:idea` still cannot reach `tag:idea` (or `tag:idea-hub`) on the
    ports that matter (SSH, Console, MilkWise, common HTTP).
  - `tag:idea-hub` accepts only `tag:idea:22` and is denied on the other
    listed ports.
  - Admins can still reach both tags.

idea itself stays `tag:idea`. Only the dashboard sidecar is `tag:idea-hub`.
Do not retag idea (100.115.60.6).

Tests cannot use `*` wildcards in `src`, `accept` or `deny` (Tailscale
policy-file syntax). The listed ports are therefore explicit: 22, 80, 443,
3333, 3334, 8080, 8081. Adding a new listening port later means adding it
to the deny lists too.

## Order to apply

Follow idea#375. Do not skip ahead.

### Step A — U-1 and U-2 (before the sidecar exists)

1. Open https://login.tailscale.com/admin → Access controls, signed in as
   the IDEA tailnet owner (tail2d60.ts.net).
2. Confirm the live admin source (T-b) and substitute it in the snippet
   if needed.
3. In `tagOwners`, **add** `"tag:idea-hub": ["<same admin source as tag:idea>"]`.
   Leave the existing `tag:idea` entry untouched. Creating the tag this
   way is U-1; do not retag idea.
4. In `acls` (or `grants`), **add** admin access to `tag:idea-hub:*`
   (U-2). Keep the existing admin → `tag:idea:*` rule.
5. **Add** the Step A `tests` from `field-usage-acl-step-a.hujson`.
   At this stage `tag:idea-hub` must still be **denied** on `tag:idea:22`
   — the collector must not be able to dial kits until the node exists
   and U-5 has been confirmed.
6. Save. If any test fails, Tailscale rejects the save; fix the snippet
   rather than deleting the tests.
7. U-3 (create the tagged, non-ephemeral auth key for this sidecar only)
   happens in the Keys page, not in this file. Store the key as a 0600
   file; tell Steve only the path, never the key.
8. Atlas then registers the sidecar (scratch App on idea03 or idea04
   first, never idea first, never idea01). Record its 100.x IPv4.
9. U-5: confirm Console and MilkWise still answer on ports 3333 and 3334
   on idea.

Equivalent grant if the live file uses `grants`:

```json
{
  "src": ["group:admins"],
  "dst": ["tag:idea-hub"],
  "ip": ["*"]
}
```

### Step B — U-4 (only after the sidecar is registered and U-5 passed)

1. Add this rule (classic `acls` form):

```json
{ "action": "accept", "src": ["tag:idea-hub"], "proto": "tcp", "dst": ["tag:idea:22"] }
```

   Equivalent grant:

```json
{ "src": ["tag:idea-hub"], "dst": ["tag:idea"], "ip": ["tcp:22"] }
```

2. Replace the Step A `tag:idea-hub` test (all-deny, including port 22)
   with the Final test in `field-usage-acl-final.hujson`: accept
   `tag:idea:22`, deny the other listed ports.
3. Save. The tests now refuse a save that accidentally grants
   `tag:idea-hub` anything except tcp/22, or that lets `tag:idea` dial
   `tag:idea`.
4. Atlas runs `probe-field-usage-acl.sh hub-to-idea` from the sidecar
   (port 22 must open; 80, 3333, 3334, 8080, 8081 must not) and
   `probe-field-usage-acl.sh idea-to-idea` from a pool Pi. The
   idea-to-idea run is only a true `tag:idea` proof after T-c has tagged
   the fleet Pis; until then it still records whether those nodes can
   reach each other.

### Diff against the known sketch (Final)

```diff
   "tagOwners": {
     "tag:idea": ["group:admins"],
+    "tag:idea-hub": ["group:admins"]
   },
   "acls": [
     { "action": "accept", "src": ["group:admins"], "dst": ["tag:idea:*"] },
+    { "action": "accept", "src": ["group:admins"], "dst": ["tag:idea-hub:*"] },
+    { "action": "accept", "src": ["tag:idea-hub"], "proto": "tcp", "dst": ["tag:idea:22"] }
   ]
+  // plus the tests in field-usage-acl-final.hujson
```

No other sources gain new destinations. In particular there is still no
rule with `src` `tag:idea`.

## Rollback

### Immediate fleet-wide off switch (§10 level 1)

Remove the single `tag:idea-hub → tag:idea:22` rule (the Step B line).
Keep `tagOwners` and the admin → `tag:idea-hub` grant so Koen can still
reach the sidecar. Change the `tag:idea-hub` test back to deny
`tag:idea:22` (the Step A test) so a later edit cannot silently re-add
the path. Save. No kit can be pulled from any more.

### Full rollback of the new tag

Only after the sidecar node has been removed or untagged:

1. Remove the admin → `tag:idea-hub` rule.
2. Remove `tag:idea-hub` from `tagOwners`.
3. Remove the `tag:idea-hub` tests.

Do not remove `tag:idea` or the admin → `tag:idea` rule.

### Other off-switch levels (not ACL)

2. Per kit: `usageMonitoring` off (idea#411; `tools/fleet` toggle once Axle defines the verb).
3. On idea: stop the dashboard App.
4. Emergency: quarantine `/etc/ssh/idea_usage_keys/%u` on the kit (never `rm -rf`).

## Recovery of the sidecar 100.x address (U-6)

If the sidecar's Tailscale state volume is lost, re-register the node
with the U-3 key and set its **previous** 100.x IPv4 in the Tailscale
admin console (Machines → the new node → edit IP). Do not invent a new
address: every kit `from=` line pins that address. The IP itself is not
a secret and should be written in the runbook once the node exists.

The node state and the pull key stay out of normal Borg App backups
(`x-app.backup` `exclude: [keys, tailscale]`). They are not restored
onto any other host.

## Validating the snippets

From the repo, without talking to Tailscale:

```bash
tools/fleet/probe-field-usage-acl.test.sh
```

That parses both HuJSON files (comments and trailing commas stripped)
and checks that the required `tagOwners`, `acls` and `tests` blocks are
present. Tailscale itself will also run the `tests` when the file is
saved in the admin console.
