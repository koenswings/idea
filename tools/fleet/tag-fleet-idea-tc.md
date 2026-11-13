# T-c: tag the fleet Pis as `tag:idea` (idea#375)

**Status:** Ready to run, not yet applied · **Maintained by:** Atlas · 2026-11-10
**Do not treat this file as permission to tag a node.** Atlas does not apply
the tag. Koen (or Steve walking him through #375) clicks Edit tags; this
runbook and [`tag-fleet-idea.sh`](tag-fleet-idea.sh) are the pre-check, wait,
post-check and rollback.

Related: [idea#375 T-c](https://github.com/koenswings/idea/issues/375),
[idea#117](https://github.com/koenswings/idea/issues/117),
[idea#416](https://github.com/koenswings/idea/issues/416),
[`field-usage-acl.md`](field-usage-acl.md),
[`probe-field-usage-acl.sh`](probe-field-usage-acl.sh),
[`field-usage-after-u-steps.sh`](field-usage-after-u-steps.sh) (dry-run wrapper around this runbook).

## 1. Mechanism

`idea-setup.sh` was removed (idea#273). New Pis join through the Engine's
`installTailscale` (`build-engine` / `provision-fleet.sh`), which stores the
fleet key at `/etc/tailscale/debug-authkey` (0600, root, via stdin) and
installs `tailscale-debug-activate.sh`. That activate script still uses the
latent-debug start/stop model, but it no longer passes `--ephemeral` (an
ephemeral node vanishes after it has been offline, and the D-2 key is
non-ephemeral):

```
tailscale up --auth-key=file:/etc/tailscale/debug-authkey \
  --advertise-tags=tag:idea --hostname="$(hostname)"
```

The 2026-10-13 design (always-on, one `tag:idea`, one fleet auth key) is
decided (idea#117 D-2 option 3). Always-on first-boot join is engine#291.
Whether the fleet key itself is tagged is T-a.

How nodes on this tailnet actually look (box `tailscale status --json`,
2026-11-10 21:56 Europe/Brussels):

| Node | IP | Tags | Key expiry (Europe/Brussels) |
|---|---|---|---|
| idea01 | 100.99.231.94 | (none, user-owned) | 2027-03-27 15:01 |
| idea02 | 100.85.108.118 | (none, user-owned) | **2026-12-02 14:36** |
| idea03 | 100.126.117.80 | (none, user-owned) | **2026-12-02 14:36** |
| idea04 | 100.108.39.45 | (none, user-owned) | 2027-03-27 15:01 |
| idea / wizardly-hugle (`openclaw-pi`) | 100.115.60.6 | (none, user-owned) | 2027-04-06 10:20 |
| kits + kit routers | (various) | `tag:idea` | none |

Kits and kit routers joined with `--advertise-tags=tag:idea` (router enrol:
`tools/router-image/idea-router-enrol`). The pool Pis and idea joined as
Koen's user and never received the tag.

There are three ways to put `tag:idea` on an already-joined node
([Tailscale: Group devices with tags](https://tailscale.com/docs/features/tags)):

1. **Admin console → Machines → ⋯ → Edit tags** (Owner / Admin / Network
   admin). The tag must already exist in `tagOwners`. **No re-authentication.**
   This is the safe path and is what T-c already describes.
2. **CLI** `sudo tailscale up --advertise-tags=tag:idea` (or
   `tailscale login --advertise-tags=tag:idea`). The caller must be a
   tagOwner, or the auth key must already carry the tag. **This
   re-authenticates, mints a new node key, and can drop an SSH session
   that is itself over Tailscale.** The Tailscale IP does not change.
   Do not use this on a live fleet Pi.
3. **Tagged auth key** at first join. Useful for new images (engine#291),
   not for retagging these four nodes. T-a has not confirmed the fleet
   key is tagged; driving `tailscale up --auth-key=file:/etc/tailscale/debug-authkey
   --advertise-tags=tag:idea` on an already-joined user-owned node is the
   same re-auth risk as (2), and fails if the key is untagged.

Applying a tag removes the user identity. After that, ACL matching uses
`tag:idea`, not `swings.koen@`. That is why admins → `tag:idea` must already
work (it does for the kits) before any fleet Pi is tagged.

Console Edit tags does **not** by itself disable key expiry. Tailscale
disables expiry when a node is tagged **and re-authenticated** (for example
joined with a tagged auth key). After a console-only tag change, also click
**Disable key expiry**. idea02 and idea03 drop off the tailnet on
**2026-12-02 14:36 Europe/Brussels** if neither tagging-with-reauth nor
Disable key expiry happens.

## 2. Who this run covers

Do now (T-c, this script's allow-list):

- idea01, idea03, idea04 (pool)
- idea02 — not a pool Pi (`status: hold`, fleet deny for deploy) but
  **named by #375 T-c** and it shares the 2 December expiry. Tag it; do
  not run deploy/teardown tools on it and do not lift the hold.

Do later (refused by the script):

- idea / wizardly-hugle (`100.115.60.6`) — production, MilkWise 3333/3334.
  Current T-c text also lists `idea`; Steve should narrow T-c to defer it
  until Koen's OK / idea#374.
- Kits (sunny-robin, happy-zebra, kind-panda) and their routers — already
  `tag:idea`, pinned at Engine `adfd9d3`, read-only until #374.

## 3. Order: idea03 first

1. **idea03** (spare). Shares the 2 December expiry; SSH and health were
   proved earlier today after the idea#416 export proof; if anything about
   the tag change surprised us (ACL lock-out, brief Tailscale blip) the
   blast radius is a spare, not golden and not idea04's extra disks.
2. **idea04** (spare). Do not touch the WD SSD or Disk B.
3. **idea02** (hold). Expiry-critical; no deploy scripts; leave status
   `hold`.
4. **idea01** (golden) last, only after the three above kept their IP and
   SSH.

One Pi at a time. Keep an existing SSH session open to the Pi being tagged
until post-check from a *new* session succeeds. Pause above 75 °C, resume
below 65 °C. Do not use a Pi another bot has claimed.

idea03 goes first even if someone later considered the CLI path: that path
can drop SSH, and we would rather learn that on a spare.

## 4. Pre-check (ACL Step A / `tag:idea`)

`tailscale status --json` can see `Tags` on nodes. It cannot see unused
`tagOwners` entries, so **`tag:idea-hub` will not appear until the U-3
sidecar exists.** Step A (U-1 + U-2) can be live without any node showing
that tag. The safety property we can prove from the box is:

- at least one peer already shows `Tags: ["tag:idea"]` — the tag exists;
- the SSH canary is an **online tagged Engine**, not a `*-router`. Kit
  routers have no sshd on Tailscale, so a TCP 22 probe to them always
  fails and must not be treated as a lock-out. The script skips those
  names (hostname or DNS label ending in `-router`), tries up to three
  online tagged Engines (short timeout each) until one answers TCP 22, and
  reports the canary used plus the routers skipped. A successful probe
  means `admins → tag:idea:22` works, so tagging a fleet Pi should not
  lock us out of SSH from this box.
- On the box, Tailscale is userspace, so a plain socket connect to a
  tailnet IP fails. When `~/.local/bin/socks-connect` is executable, the
  canary probes through it (`timeout 6 socks-connect <ip> 22 </dev/null`,
  SOCKS port 1055) and treats an `SSH-2.0-` banner as opened — banner
  only, no SSH login. Override the helper with `SOCKS_CONNECT_BIN` (for
  tests). If that path is not executable, the probe falls back to a
  plain socket connect. `TCP_PROBE_CMD`, when set, still takes
  precedence over both. `TCP_PROBE_PORT` (default 22) is a test hook
  for the socks and plain paths.
- if no non-router tagged node is online, preflight reports `canary:
  null` with a distinct `no_online_tagged_engine` reason. That is **not**
  a lock-out claim. `ok` is false until an Engine canary is available.
  If a canary Engine is online but TCP 22 fails, that *is* a possible
  lock-out and is reported separately as `tcp22_failed`.

Kits were offline at the 21:56 Europe/Brussels snapshot; later the first
online `tag:idea` peer from the box's `tailscale status --json` was
happy-zebra-router, which produced a false `ok:false` lock-out warning.
T-b (read the live ACL) remains the console confirmation that
`tagOwners` includes `tag:idea` and that admins may reach it. Do not
tag the first fleet Pi if T-b shows no `admins → tag:idea` rule, or if
preflight reports `tcp22_failed` against a tagged Engine.

```
tools/fleet/tag-fleet-idea.sh preflight
tools/fleet/tag-fleet-idea.sh precheck --pi idea03
```

`precheck` also refuses idea/wh/kits, refuses a Pi claimed by someone
else, and checks the Tailscale IPv4 still matches `fleet-state.json`.

After a Pi *is* tagged, `probe-field-usage-acl.sh idea-to-idea --from-pi
<that-pi>` should show every listed dest/port unreachable (a `tag:idea`
source may initiate nothing). That is the runtime proof the 21:46
Europe/Brussels baseline (22/80/8080 still open from untagged idea03)
could not give.

## 5. Apply (Koen, one Pi)

Atlas does not do this. For each Pi, in the order above:

1. Claim if you will SSH (not required for idea02's hold status —
   leave `status: hold`):
   `BOT_NAME=Atlas tools/fleet/update-fleet-state.sh <pi> status testing`
   and `… claim 'Atlas idea#375 T-c tag:idea'`. Skip the status change
   on idea02.
2. `tools/fleet/tag-fleet-idea.sh run --pi <name>`
   (prints the console steps and waits until `Tags` contains `tag:idea`).
3. In https://login.tailscale.com/admin/machines, open that machine,
   ⋯ → **Edit tags** → add `tag:idea` → Save.
4. **Disable key expiry** on the same machine.
5. Do not run `tailscale up --advertise-tags` on the Pi.

## 6. Post-check

The `run` / `postcheck` modes confirm:

- `tailscale status --json` shows `tag:idea` on that node;
- the Tailscale IPv4 is unchanged versus fleet-state;
- a fresh SSH session from the box still works;
- KeyExpiry is empty (warns if not);
- `tools/fleet/check-fleet-health.sh --pi <name>` (never `--alert`;
  HOLD and PAUSED files stay in place).

Then release the claim (`--null claim`, `status idle`) except idea02,
which stays `hold`. Only then start the next Pi.

## 7. Rollback

- **SSH lost after the tag:** do **not** try to remove the last tag in
  the console (Tailscale will not allow a tagged node to have zero
  tags). Restore `admins → tag:idea:*` in the ACL if it is missing
  (T-b / Step A). That is the preferred recovery.
- **SSH still works and the tag must come off:** from the open session,
  `sudo tailscale up --force-reauth` *without* `--advertise-tags`, then
  complete the browser login as Koen. This re-authenticates, returns a
  user identity, and **can drop the SSH session**. The IP should stay
  the same. Reconnect and run `postcheck` (it will report untagged).
- Do not use `tailscale up --advertise-tags=` (empty) if the node was
  joined with an auth key — Tailscale will not remove tags that way.
- Do not use a new auth key or `--reset` unless Steve has agreed: that
  is a bigger identity change than T-c needs.
- After a failed Pi, do not tag the next one.

## 8. What Steve should update on #375

No new U-step. T-c already describes Edit tags. Suggested wording
change (not a new item):

- Scope T-c to idea01, idea03, idea04, and idea02. Defer `idea`
  (100.115.60.6) until Koen's OK / idea#374.
- After each Edit tags, also Disable key expiry (console tagging does
  not turn expiry off by itself). idea02 and idea03 remain the
  2026-12-02 14:36 Europe/Brussels deadline.
- Atlas runs `tag-fleet-idea.sh` before and after each click; Koen
  does one machine at a time in the order idea03, idea04, idea02,
  idea01.
