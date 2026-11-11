# Field-usage lockdown flow map (idea#416 / idea#375)

**Status:** Draft for review · **Author:** Atlas · **Date:** 2026-11-11
**Does not edit the live ACL.** Removing allow-all is a later idea#375
item, after T-c has tagged the machines that must stay reachable.

Related: [`field-usage-acl.md`](field-usage-acl.md),
[`field-usage-acl-final.hujson`](field-usage-acl-final.hujson),
[`field-usage-rollout.md`](field-usage-rollout.md),
[`docs/ops/security-overview.md`](../../docs/ops/security-overview.md),
[`docs/grok-bot-setup.md`](../../docs/grok-bot-setup.md).

Legend: **observed** = read from `tailscale status --json` or a connect-only
probe this turn, or quoted from a checked-in doc. **inferred** = needed to
make a checked-in workflow keep working, but not re-proved today.

The live policy text is **not readable from the box** (no Tailscale API or
policy credential in `~/.config/idea/`; that directory has only node join
keys). ACL facts below come from Steve's read-back of Koen's saves, plus
what status/probes can see.

## 1. Why this map exists

Today the tailnet still has an allow-all grant `{src: "*", dst: "*", ip: "*"}`
plus:

- `tagOwners`: `tag:idea` and `tag:idea-hub`, both owned by `autogroup:admin`
- grants: `autogroup:admin → tag:idea` and `autogroup:admin → tag:idea-hub`
- grant: `{src: ["tag:idea-hub"], dst: ["tag:idea"], ip: ["tcp:22"]}`
  (Koen saved this as U-4 at 09:31 Europe/Brussels on 2026-11-11)
- the existing Tailscale SSH `check` rule
  (`autogroup:member → autogroup:self`, users nonroot and root) — leave it
  unchanged; pulls and operator access use plain OpenSSH, not Tailscale SSH

Lockdown means **removing allow-all** and adding the deny `tests` so a later
edit cannot silently re-open Pi-to-Pi paths. It must wait until every
machine that admins and the sidecar need is tagged `tag:idea` (T-c),
because the surviving grants are tag-based. Tagging `idea` /
wizardly-hugle is deferred to idea#374 and Koen's OK; **do not remove
allow-all while production `idea` is still untagged** unless a temporary
host grant is added (see §5).

## 2. Observed tailnet snapshot (2026-11-11 09:33 Europe/Brussels)

From `tailscale status --json` on the box and from `docker exec
idea-hub-sidecar tailscale status --json` on idea03. Hostnames and 100.x
addresses only; no user login names.

### 2.1 `tag:idea` (six nodes; all Zimbabwe kit hardware)

| hostname | IPv4 | online | notes |
|---|---|---|---|
| happy-zebra | 100.102.94.100 | yes | kit Engine |
| happy-zebra-router | 100.110.73.52 | yes | kit router |
| sunny-robin | 100.96.98.10 | yes | kit Engine |
| sunny-robin-router | 100.96.34.29 | yes | kit router |
| kind-panda | 100.80.238.59 | no | kit Engine; not installed yet (docs) |
| kind-panda-router | 100.86.136.9 | no | kit router |

No pool Pi and not `idea` currently carry `tag:idea`. T-c is still open.

### 2.2 `tag:idea-hub`

| hostname | IPv4 | online | notes |
|---|---|---|---|
| idea-hub | 100.75.102.57 | yes | usage-dashboard App on idea03 (re-joined 2026-11-11 12:16; old node 100.69.148.49 removed, old sidecar retired) |

### 2.3 Untagged fleet / production (same tailnet user as the box)

| hostname | IPv4 | online | role (fleet-state) |
|---|---|---|---|
| idea01 | 100.99.231.94 | yes | golden |
| idea02 | 100.85.108.118 | yes | hold / fleet-pending |
| idea03 | 100.126.117.80 | yes | spare (sidecar host) |
| idea04 | 100.108.39.45 | yes | spare |
| openclaw-pi | 100.115.60.6 | yes | production `idea` / wizardly-hugle. MagicDNS used in U-5: `idea.tail2d60.ts.net`. Console port 8081 (fleet-state). |

idea02 and idea03 node-key expiry: 2026-12-02 14:36 Europe/Brussels
(docs / earlier status). T-c also disables key expiry.

### 2.4 Bot computers (untagged, linux)

Observed hostnames, many of them stale offline duplicates of earlier box
instances:

- **this box:** `box-2-1` (`100.64.66.119`). `Self.Online` reported false
  after the 09:28 Europe/Brussels tailscaled restart, but userspace SOCKS
  and SSH to idea03 worked. **inferred:** treat as the live ops box.
- offline linux hostnames also present: `box`, `box-2`, `atlas-box`,
  `atlas-box-1`, `grokbot-box`, `steve`, `steve-box` (several 100.x
  addresses each).

**inferred:** these nodes are logged in as the same tailnet user as Koen's
devices (they share one Tailscale `UserID`, not printed here), so they
match `autogroup:admin` once Koen is an admin of the tailnet (he saved
the ACL, so that is observed in effect).

### 2.5 Koen's own devices (untagged; described by hostname and OS only)

| hostname | OS | online | IPv4 |
|---|---|---|---|
| Macbook Air 15 | macOS | yes | 100.123.145.127 |
| Koen's Z Fold8 | android | no | 100.114.166.88 |
| Z Fold8 van Koen | android | no | 100.85.26.112 |
| Koens-MacBook-Pro2 | macOS | no | 100.77.247.95 |
| localhost | iOS | yes | 100.104.53.17 |
| localhost | iOS | no | 100.72.89.47 |

The two `localhost` iOS nodes are **inferred** to be Koen's personal
devices (same `UserID` as the Mac / phones above; generic hostname).

## 3. Flows that must keep working after allow-all is removed

| # | Source | Destination | Ports / path | Why | Evidence |
|---|---|---|---|---|---|
| F1 | `autogroup:admin` (Koen's devices and bot computers, §2.4–2.5) | `tag:idea` Engines (kits now; idea01–04 and eventually `idea` after T-c) | tcp/22, plain OpenSSH | Ops SSH, health checks, deploys, quality-scan, kit field checks | **observed:** box SSH to idea03 via userspace SOCKS; `check-fleet-health.sh` probes SSH. **inferred:** same path to every pool Pi and kit Engine. |
| F2 | `autogroup:admin` | `tag:idea` Consoles | tcp/8080 on pool Pis and kits (fleet-state default); tcp/8081 on `idea` | Console UI and `check-fleet-health.sh` HTTP 200 | **observed** in `docs/grok-bot-setup.md` § health and fleet-state `console_port: 8081` on wizardly-hugle. Koen confirmed U-5: `http://idea.tail2d60.ts.net:8081/`. |
| F3 | `autogroup:admin` | `idea` `100.115.60.6` | tcp/3333 and tcp/3334 | MilkWise. Must stay up independently of the dashboard App | **observed:** U-5 confirmation (Steve). fleet-state: production MilkWise on idea since 2026-10-08. On idea, `:8080` is Kolibri host-net (**inferred** from the same fleet-state note); admin `*` to `tag:idea` covers it once `idea` is tagged. |
| F4 | `autogroup:admin` | kit Engine `:22`, then LAN jump to `root@10.42.0.1:22` | Tailscale only needs Engine `:22`. Router dropbear listens on the LAN zone, not on `tailscale0` | Router recovery and read-only captures (idea#288) | **observed** in `docs/ops/security-overview.md` (“SSH port is closed on the Tailscale side”) and Atlas's 2026-10-29 notes: `box → pi@<kit> over Tailscale → root@10.42.0.1`. This is the ProxyJump Steve named. It is **not** a Tailscale grant to the router on `:22`. |
| F5 | `autogroup:admin` | kit routers on Tailscale | tcp/80 and tcp/443 (LuCI / ubus) | Remote router reads when LAN jump is inconvenient | **observed** in `docs/ops/security-overview.md`. Covered by admin `→ tag:idea:*` because routers already carry `tag:idea`. |
| F6 | `autogroup:admin` | `tag:idea-hub` (`idea-hub` `100.75.102.57`) | at least tcp/22 and the dashboard web port (whatever `${port}` Engine assigns; never 80, 3333, 3334 or 8081) | Koen and ops must still reach the sidecar / future dashboard App | **inferred** from U-2 (“grant admins access to `tag:idea-hub` first”) and `app-usage-dashboard` runbook. Live grant is already `autogroup:admin → tag:idea-hub`. |
| F7 | `tag:idea-hub` | `tag:idea` | tcp/22 only, plain OpenSSH | Usage pull (`restrict,from=<sidecar IPv4>`, forced command `idea-usage-export`). After T-c this is every tagged Engine, including kits | **observed:** U-4 grant saved 09:31; connect-only `tailscale nc` from `idea-hub` opened `:22` on happy-zebra and sunny-robin (the only online `tag:idea` Engines) at 09:33 Europe/Brussels. Under allow-all that proves reachability, **not** that the new grant is what allowed it. |
| F8 | `tag:idea` | anything on the tailnet | **none** | Koen's rule: no Pi-to-Pi (and no school-to-school) over Tailscale. Engines talk over the school LAN websocket and mDNS only | **observed** as design in `proposals/2026-10-13-tailscale-single-fleet-tag.md` and `docs/ops/security-overview.md`. Today allow-all still lets pool Pis reach each other (Step 5 idea-to-idea saw idea03→idea01 `:22`/`:80`/`:8080` open). After lockdown + T-c those must fail. |
| F9 | Bot computers | their own Tailscale userspace stack (SOCKS on localhost:1055 on this box) | not an ACL grant | How the box reaches 100.x addresses | **observed:** `docs/grok-bot-setup.md` (`QUALITY_SCAN_SOCKS=127.0.0.1:1055`); this box uses `socks-connect`. |

No flow requires `tag:idea` to initiate anything, or `tag:idea-hub` to open
any port other than `:22` on `tag:idea`. In particular idea-hub must not
need MilkWise `:3333`/`:3334`, Console `:8080`/`:8081`, or LuCI.

## 4. U-4 connect-only check (2026-11-11 09:33 Europe/Brussels)

From `idea-hub` (`docker exec idea-hub-sidecar tailscale nc`, no SSH
login, no other ports). idea03 was not claimed (read-only exec).

| dest | ip | tag | :22 |
|---|---|---|---|
| happy-zebra | 100.102.94.100 | `tag:idea` (kit Engine) | opened |
| sunny-robin | 100.96.98.10 | `tag:idea` (kit Engine) | opened |
| idea01 | 100.99.231.94 | none | opened |
| idea03 | 100.126.117.80 | none | opened |
| idea04 | 100.108.39.45 | none | opened |

kind-panda was offline and was not contacted. Kit routers were not
contacted (SSH is not exposed on Tailscale; F4 uses the Engine jump).
idea01/03/04 are still untagged, so their `:22` openings are allow-all
reachability, not a proof of the U-4 grant.

## 5. Prerequisites before allow-all can go

1. **T-c** tags idea03, idea04, idea02, idea01 with `tag:idea` and disables
   key expiry (Koen clicks Edit tags; scripts never run
   `--advertise-tags`). Order: idea03, idea04, idea02, idea01.
2. **Tagging `idea` / wizardly-hugle / `openclaw-pi` (`100.115.60.6`)** is
   **not** part of that pass (idea#374, Koen's OK). Until it is tagged,
   F2/F3 for production depend on allow-all or on the node still being
   user-owned **and** some user-to-user grant. **inferred:** lockdown
   without tagging `idea` would risk isolating Console `:8081` and
   MilkWise `:3333`/`:3334` from `autogroup:admin` once allow-all is gone,
   unless a temporary host-scoped grant is added. Prefer: tag `idea` as
   `tag:idea` (the host stays `tag:idea`; only the sidecar is
   `tag:idea-hub`) before removing allow-all.
3. Repeat `probe-field-usage-acl.sh idea-to-idea` after each T-c tag:
   Pi-to-Pi over Tailscale must then be denied.
4. Repeat `probe-field-usage-acl.sh hub-to-idea` from the sidecar after
   T-c: `:22` open, `80,443,3333,3334,8080,8081` not open.

## 6. Proposed grants and tests (HuJSON)

Merge these blocks into the live file; do not replace unrelated `hosts`,
`ssh`, or `nodeAttrs`. Admin source is `autogroup:admin`. This matches the
already-saved U-1/U-2/U-4 grants and adds the deny tests that cannot be
saved while allow-all is present.

The live file uses `grants`. Equivalent classic `acls` are in
[`field-usage-acl-final.hujson`](field-usage-acl-final.hujson).

```hujson
// Lockdown paste — AFTER T-c (and after idea is tagged, or with a
// temporary host grant for 100.115.60.6). Remove the allow-all
// {src:"*", dst:"*", ip:"*"} grant. Keep the existing ssh check rule.
{
  "tagOwners": {
    "tag:idea": ["autogroup:admin"],
    "tag:idea-hub": ["autogroup:admin"],
  },
  "grants": [
    // F1–F5, F3 once idea is tagged: Koen and bot computers.
    { "src": ["autogroup:admin"], "dst": ["tag:idea"], "ip": ["*"] },
    // F6: reach the sidecar / dashboard.
    { "src": ["autogroup:admin"], "dst": ["tag:idea-hub"], "ip": ["*"] },
    // F7: usage pull only.
    { "src": ["tag:idea-hub"], "dst": ["tag:idea"], "ip": ["tcp:22"] },
  ],
  "tests": [
    {
      "src": "autogroup:admin",
      "proto": "tcp",
      "accept": [
        "tag:idea:22",
        "tag:idea:80",
        "tag:idea:443",
        "tag:idea:3333",
        "tag:idea:3334",
        "tag:idea:8080",
        "tag:idea:8081",
        "tag:idea-hub:22",
        "tag:idea-hub:80",
      ],
    },
    {
      "src": "tag:idea",
      "proto": "tcp",
      "deny": [
        "tag:idea:22",
        "tag:idea:80",
        "tag:idea:443",
        "tag:idea:3333",
        "tag:idea:3334",
        "tag:idea:8080",
        "tag:idea:8081",
        "tag:idea-hub:22",
        "tag:idea-hub:80",
        "tag:idea-hub:443",
      ],
    },
    {
      "src": "tag:idea-hub",
      "proto": "tcp",
      "accept": ["tag:idea:22"],
      "deny": [
        "tag:idea:80",
        "tag:idea:443",
        "tag:idea:3333",
        "tag:idea:3334",
        "tag:idea:8080",
        "tag:idea:8081",
        "tag:idea-hub:22",
        "tag:idea-hub:80",
      ],
    },
  ],
}
```

Notes:

- Admin destinations stay `ip: ["*"]`, matching the grants Koen already
  saved. That covers Console, MilkWise, LuCI, SSH, and any Engine-side
  port (idea03's `config.yaml` also mentions `port: 4321` — **inferred**,
  not probed). Narrowing admins to an explicit port list can wait; the
  important lock is “`tag:idea` initiates nothing” and “idea-hub gets
  only `:22`”.
- Tests cannot use `*` wildcards (Tailscale policy-file syntax), so the
  listed ports are explicit. A new listening port that must stay denied
  to idea-hub or to other Pis has to be added to the deny lists.
- There is still **no** grant whose `src` is `tag:idea` (F8).
- Do not add Tailscale SSH access rules.

## 7. Rollback of lockdown

Put the allow-all grant back (`{src: ["*"], dst: ["*"], ip: ["*"]}`) if
someone loses SSH. That is broader than restoring only
`autogroup:admin → tag:idea:*`, but it matches how the tailnet works
today. The tighter rollback (restore the admin grant, do not take the
last tag off a node) is already in [`tag-fleet-idea-tc.md`](tag-fleet-idea-tc.md) §7
for a failed T-c tag.

Removing only the U-4 line (`tag:idea-hub → tag:idea:22`) remains the
fleet-wide usage-pull off switch and is independent of allow-all.
