# Field-usage lockdown flow map (idea#416 / idea#375)

**Status:** Draft for review · **Author:** Atlas · **Date:** 2026-11-11
**Does not edit the live ACL.** Removing allow-all is a later idea#375
item. T-c has tagged the four pool Pis; production `idea` is also tagged
(see §5 for what is still pending).

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
edit cannot silently re-open Pi-to-Pi paths. The surviving grants are
tag-based. T-c (pool Pis) and the `tag:idea` tag on production `idea`
are done; **do not remove allow-all until the remaining §5 items are
met** (Disable key expiry on `idea`, the Pi-to-Pi baseline, and the
post-lockdown re-probes).

## 2. Observed tailnet snapshot (updated 2026-11-11 14:13 Europe/Brussels)

From `tailscale status --json` on the box (14:13) and earlier from
`docker exec idea-hub-sidecar tailscale status --json` on idea03.
Hostnames and 100.x addresses only; no user login names. Koen's devices
are described by name and OS only.

### 2.1 `tag:idea`

Kits, the four pool Pis (T-c complete), and production `idea`. T-c
postchecks ran 13:08–13:35 Europe/Brussels: idea01–idea04 each show
`tag:idea` and key expiry disabled. Prerequisite §5.1 is **MET**.

| hostname | IPv4 | online | notes |
|---|---|---|---|
| happy-zebra | 100.102.94.100 | yes | kit Engine |
| happy-zebra-router | 100.110.73.52 | yes | kit router |
| sunny-robin | 100.96.98.10 | yes | kit Engine |
| sunny-robin-router | 100.96.34.29 | yes | kit router |
| kind-panda | 100.80.238.59 | no | kit Engine; not installed yet (docs); offline since 2026-10-18 |
| kind-panda-router | 100.86.136.9 | no | kit router; offline since 2026-10-18 |
| idea01 | 100.99.231.94 | yes | golden; T-c postcheck; key expiry disabled |
| idea02 | 100.85.108.118 | yes | hold / fleet-pending; T-c postcheck; key expiry disabled |
| idea03 | 100.126.117.80 | yes | spare (sidecar host); T-c postcheck; key expiry disabled |
| idea04 | 100.108.39.45 | yes | spare; T-c postcheck; key expiry disabled |
| openclaw-pi | 100.115.60.6 | yes | production `idea` (OS hostname idea) / wizardly-hugle. Koen tagged it 14:12 (decision 14:11). Postcheck 14:13: Console :8081 and MilkWise :3333/:3334 return 200 from the box, pm2 unchanged. Key expiry still 2027-04-06 10:20 CET — Disable key expiry pending. MagicDNS: `idea.tail2d60.ts.net`. |

### 2.2 `tag:idea-hub`

| hostname | IPv4 | online | notes |
|---|---|---|---|
| idea-hub | 100.75.102.57 | yes | usage-dashboard App on idea03 (re-joined 2026-11-11 12:16; old node 100.69.148.49 removed, old sidecar retired) |

### 2.3 Pool / production (now under `tag:idea`)

idea01–idea04 and production `idea` (`openclaw-pi`, `100.115.60.6`)
moved to §2.1 when they received `tag:idea`. No pool Pi remains
untagged. On the four pool Pis, key expiry is disabled. On production
`idea`, the tag is in place but Disable key expiry is still pending
(see §5.2).

### 2.4 Bot computers (untagged, linux)

**T-d (Koen's decision):** the live ops box `box-2-1` (`100.64.66.119`)
stays untagged. It is an admin-side source (`autogroup:admin`, same
tailnet user as Koen's devices). It rejoined at about 14:09
Europe/Brussels after the earlier NeedsLogin incident, same IP.

**inferred:** `box-2-1` matches `autogroup:admin` once Koen is an admin
of the tailnet (he saved the ACL, so that is observed in effect). It is
a source for F1, F2, F3, F5 and F6. Earlier offline linux hostnames
(`box`, `box-2`, `atlas-box`, and similar) are gone after T-e.

### 2.5 Koen's own devices (untagged; described by name and OS only)

After Koen's stale-node cleanup (T-e), these are the kept devices.
T-e is clean: no stale nodes remain. Koen's Z Fold8 (offline since
2026-10-30) and the iOS `localhost` node (Koen's current iPhone) are
both on the keep list.

| name | OS | online |
|---|---|---|
| Macbook Air 15 | macOS | yes |
| Koen's Z Fold8 | android | no (since 2026-10-30; kept) |
| localhost | iOS | yes (current iPhone; kept) |

### 2.6 T-e machines list (box view, 14:13 Europe/Brussels)

idea01–idea04; happy-zebra and sunny-robin plus their routers;
kind-panda and kind-panda-router (`tag:idea`, offline since 2026-10-18);
idea-hub `100.75.102.57` (`tag:idea-hub`); openclaw-pi; Koen's Macbook
Air 15 (macOS), iOS `localhost` (current iPhone), and Koen's Z Fold8
(Android, offline since 2026-10-30) — all three kept; and box-2-1.
No stale nodes left.

## 3. Flows that must keep working after allow-all is removed

| # | Source | Destination | Ports / path | Why | Evidence |
|---|---|---|---|---|---|
| F1 | `autogroup:admin` (Koen's devices, §2.5, and box-2-1, §2.4) | `tag:idea` Engines (kits, idea01–04, and production `idea`) | tcp/22, plain OpenSSH | Ops SSH, health checks, deploys, quality-scan, kit field checks | **observed:** box SSH to idea03 via userspace SOCKS; `check-fleet-health.sh` probes SSH. **inferred:** same path to every pool Pi and kit Engine. |
| F2 | `autogroup:admin` (Koen's devices and box-2-1) | `tag:idea` Consoles | tcp/8080 on pool Pis and kits (fleet-state default); tcp/8081 on `idea` | Console UI and `check-fleet-health.sh` HTTP 200 | **observed** in `docs/grok-bot-setup.md` § health and fleet-state `console_port: 8081` on wizardly-hugle. Koen confirmed U-5: `http://idea.tail2d60.ts.net:8081/`. Postcheck 14:13: `idea` :8081 returns 200 from the box. Covered by admin → `tag:idea` now that `idea` is tagged. |
| F3 | `autogroup:admin` (Koen's devices and box-2-1) | `idea` `100.115.60.6` | tcp/3333 and tcp/3334 | MilkWise. Must stay up independently of the dashboard App | **observed:** U-5 confirmation (Steve); postcheck 14:13: :3333 and :3334 return 200 from the box, pm2 unchanged. fleet-state: production MilkWise on idea since 2026-10-08. On idea, `:8080` is Kolibri host-net (**inferred** from the same fleet-state note). `idea` now carries `tag:idea`, so admin `*` to `tag:idea` covers MilkWise and Console. |
| F4 | `autogroup:admin` | kit Engine `:22`, then LAN jump to `root@10.42.0.1:22` | Tailscale only needs Engine `:22`. Router dropbear listens on the LAN zone, not on `tailscale0` | Router recovery and read-only captures (idea#288) | **observed** in `docs/ops/security-overview.md` (“SSH port is closed on the Tailscale side”) and Atlas's 2026-10-29 notes: `box → pi@<kit> over Tailscale → root@10.42.0.1`. This is the ProxyJump Steve named. It is **not** a Tailscale grant to the router on `:22`. |
| F5 | `autogroup:admin` (Koen's devices and box-2-1) | kit routers on Tailscale | tcp/80 and tcp/443 (LuCI / ubus) | Remote router reads when LAN jump is inconvenient | **observed** in `docs/ops/security-overview.md`. Covered by admin `→ tag:idea:*` because routers already carry `tag:idea`. |
| F6 | `autogroup:admin` (Koen's devices and box-2-1) | `tag:idea-hub` (`idea-hub` `100.75.102.57`) | at least tcp/22 and the dashboard web port (whatever `${port}` Engine assigns; never 80, 3333, 3334 or 8081) | Koen and ops must still reach the sidecar / future dashboard App | **inferred** from U-2 (“grant admins access to `tag:idea-hub` first”) and `app-usage-dashboard` runbook. Live grant is already `autogroup:admin → tag:idea-hub`. |
| F7 | `tag:idea-hub` | `tag:idea` | tcp/22 only, plain OpenSSH | Usage pull (`restrict,from=<sidecar IPv4>`, forced command `idea-usage-export`). After T-c this is every tagged Engine, including kits | **observed:** U-4 grant saved 09:31; 09:33 connect-only from `idea-hub` opened `:22` on the then-tagged kit Engines. Pre-lockdown baseline (comment on idea#430, allow-all still on) opened `:22` on all `tag:idea` Engines; see §4.1. Under allow-all that proves reachability, **not** that the U-4 grant is what allowed it. After lockdown, only `:22` must stay open from the hub. |
| F8 | `tag:idea` | anything on the tailnet | **none** | Koen's rule: no Pi-to-Pi (and no school-to-school) over Tailscale. Engines talk over the school LAN websocket and mDNS only | **observed** as design in `proposals/2026-10-13-tailscale-single-fleet-tag.md` and `docs/ops/security-overview.md`. Today allow-all still lets pool Pis reach each other (Step 5 idea-to-idea saw idea03→idea01 `:22`/`:80`/`:8080` open). After lockdown those must fail. The fresh Pi-to-Pi baseline is still to come, from the first free pool Pi. |
| F9 | Bot computers | their own Tailscale userspace stack (SOCKS on localhost:1055 on this box) | not an ACL grant | How the box reaches 100.x addresses | **observed:** `docs/grok-bot-setup.md` (`QUALITY_SCAN_SOCKS=127.0.0.1:1055`); this box uses `socks-connect`. |

No flow requires `tag:idea` to initiate anything, or `tag:idea-hub` to open
any port other than `:22` on `tag:idea`. In particular idea-hub must not
need MilkWise `:3333`/`:3334`, Console `:8080`/`:8081`, or LuCI.

## 4. U-4 connect-only check (2026-11-11 09:33 Europe/Brussels)

From `idea-hub` (`docker exec idea-hub-sidecar tailscale nc`, no SSH
login, no other ports). idea03 was not claimed (read-only exec). This
is the earlier pre-T-c probe; the later baseline is in §4.1.

| dest | ip | tag | :22 |
|---|---|---|---|
| happy-zebra | 100.102.94.100 | `tag:idea` (kit Engine) | opened |
| sunny-robin | 100.96.98.10 | `tag:idea` (kit Engine) | opened |
| idea01 | 100.99.231.94 | none (at 09:33) | opened |
| idea03 | 100.126.117.80 | none (at 09:33) | opened |
| idea04 | 100.108.39.45 | none (at 09:33) | opened |

kind-panda was offline and was not contacted. Kit routers were not
contacted (SSH is not exposed on Tailscale; F4 uses the Engine jump).
At 09:33 idea01/03/04 were still untagged, so their `:22` openings were
allow-all reachability, not a proof of the U-4 grant. They now carry
`tag:idea` (T-c).

### 4.1 Baseline vs expected after lockdown

Pre-lockdown baseline (allow-all still on), recorded in
[PR #430 comment](https://github.com/koenswings/idea/pull/430#issuecomment-6796322833),
connect-only from the box and from idea-hub:

- `:22` opens on all `tag:idea` Engines
- `:80` and `:8080` also open on idea01, idea03 and idea04 (kits `:80`)
- production `idea` opens 22, 3333, 3334 and 8081
- everything else is refused (no listener)

Expected after lockdown:

- hub → `tag:idea` opens `:22` only, so `:80` and `:8080` from the hub
  must start failing
- Pi-to-Pi is denied
- admin (Koen's devices plus box-2-1) → `tag:idea` and `tag:idea-hub`
  stays open, including `idea` :8081, :3333 and :3334

The Pi-to-Pi baseline is still to come, from the first free pool Pi.
Re-probe hub-to-idea at lockdown (§5.4).

## 5. Prerequisites before allow-all can go

1. **T-c** tags idea01–idea04 with `tag:idea` and disables key expiry
   (Koen clicks Edit tags; scripts never run `--advertise-tags`).
   **MET** (postchecks 13:08–13:35 Europe/Brussels).
2. **Tagging `idea` / wizardly-hugle / `openclaw-pi` (`100.115.60.6`)**
   (idea#374, Koen's OK at 14:11, saved 14:12). **Tag: MET.**
   **Disable key expiry: pending** (still 2027-04-06 10:20 CET).
   Postcheck 14:13: tag present, Console :8081 and MilkWise :3333/:3334
   return 200 from the box, pm2 unchanged. F2/F3 are now covered by
   admin → `tag:idea`.
3. **Pi-to-Pi probe: pending.** Run `probe-field-usage-acl.sh idea-to-idea`
   from the first free pool Pi (baseline still to come; after lockdown
   Pi-to-Pi over Tailscale must be denied).
4. **Hub-to-idea baseline: done** (PR #430 comment, allow-all still on).
   **Post-lockdown re-probe at lockdown:** repeat
   `probe-field-usage-acl.sh hub-to-idea` from the sidecar; `:22` open,
   `80,443,3333,3334,8080,8081` not open.

## 6. Proposed grants and tests (HuJSON)

Merge these blocks into the live file; do not replace unrelated `hosts`,
`ssh`, or `nodeAttrs`. Admin source is `autogroup:admin` (Koen's devices
and box-2-1). This matches the already-saved U-1/U-2/U-4 grants and adds
the deny tests that cannot be saved while allow-all is present.

The live file uses `grants`. Equivalent classic `acls` are in
[`field-usage-acl-final.hujson`](field-usage-acl-final.hujson).

```hujson
// Lockdown paste — AFTER T-c and after idea is tagged (Disable key
// expiry on idea still pending; see §5). Remove the allow-all
// {src:"*", dst:"*", ip:"*"} grant. Keep the existing ssh check rule.
{
  "tagOwners": {
    "tag:idea": ["autogroup:admin"],
    "tag:idea-hub": ["autogroup:admin"],
  },
  "grants": [
    // F1–F5, F3: Koen's devices and box-2-1 (idea is tagged).
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
