# Tailscale Remote Management — Design

**Author:** Atlas 🗺️
**Date:** 2026-03-29
**Status:** Draft

---

## Background

IDEA school Pis have no remote access by design. Offline-first is a foundational constraint,
not a feature to be toggled. Under normal operation, a school Pi is entirely isolated from the
internet and unreachable from outside the school network.

This works well — until something goes wrong in the field and a physical site visit would cost
more time and money than the problem deserves. A Pi that won't boot, an app that's stuck, a
configuration that needs correcting: these are solvable in minutes with a shell, but expensive
if they require driving to a school.

This document designs a **latent remote-access capability**: an SSH-over-Tailscale channel that
is dormant by default, activated only when needed and only by someone physically present at the
school, and cleaned up automatically when the session ends. The school Pi remains fully offline
during normal operation. Nothing phones home.

See also: [`design/ssh-key-management.md`](ssh-key-management.md) — covers SSH key types,
`authorized_keys` restrictions, and the key rotation workflow that applies to the debug access
key described here.

---

## Design Principles

These principles constrain every decision in this document.

**1. Off by default, always.**
A school Pi in normal operation has no Tailscale connection and no exposure to the internet.
Debug mode does not change the Pi's default behaviour — it is an explicit, temporary exception.

**2. Activation requires physical or local presence.**
Debug mode cannot be triggered remotely. A person must be physically at the school (or at
minimum on the school LAN) to activate it. This prevents a compromised auth key from becoming
a silent backdoor.

**3. Sessions are temporary and self-cleaning.**
When a debug session ends, the Pi leaves the Tailnet automatically. No lingering access.
The Pi returns to its normal isolated state without any manual cleanup step.

**4. Minimal footprint.**
Tailscale is installed at imaging time but the service is disabled. It does not run, does not
consume resources, and does not communicate outside the school network during normal operation.

**5. Auditable.**
IDEA should know when debug mode was activated, by whom, and for how long. The activation event
and session duration should be logged and reportable.

---

## Tailscale Plan and Cost

IDEA already uses Tailscale: Koen's laptop and the OpenClaw Pi are on the same Tailnet.
School Pis would join the same Tailnet temporarily when debug mode is activated.

**Plan:** Free Personal tier (3 users, 100 devices).

**Device count stays near zero** because school Pis use **ephemeral auth keys**. An ephemeral
key causes Tailscale to automatically remove the device from the Tailnet when it disconnects.
A school Pi that activates debug mode, completes a support session, and runs `tailscale down`
leaves no trace in the Tailnet device list. The device count contribution is zero when not
in an active session.

This means device count is bounded by the number of *concurrent* support sessions, not the
number of schools. In practice, that is rarely more than one or two.

**When the free tier would become a constraint:**

- More than 3 Tailscale user accounts needed (e.g. multiple field staff with separate admin
  access — unlikely at current IDEA scale)
- More than 100 concurrent active debug sessions (not a realistic scenario)
- Need for audit logging, flow logging, or SSO — none of which IDEA requires now

At current and projected IDEA scale: **£0**.

---

## Ephemeral Auth Keys

A Tailscale **auth key** is a pre-shared secret that allows a device to join a Tailnet without
interactive authentication. It is provisioned via the Tailscale admin console and stored on the
device at imaging time.

An **ephemeral** auth key has one additional property: the device it registers is automatically
removed from the Tailnet when it goes offline. Normal (non-ephemeral) keys leave devices
registered indefinitely, even after the Tailscale service is stopped — those devices accumulate
in the admin panel as inactive entries and count against device limits.

**For IDEA's debug mode, ephemeral is the correct choice:**

| Property | Regular key | Ephemeral key |
|---|---|---|
| Device persists after disconnect | Yes | No — removed automatically |
| Counts against device limit when offline | Yes | No |
| Requires manual cleanup | Yes | No |
| Suitable for temporary access | ✗ | ✓ |

**Reusable vs single-use:**
Tailscale auth keys can be configured as single-use (expires after one device registers) or
reusable (any number of devices can use it, until it expires by date). For school Pis, use
a **reusable ephemeral key**:

- A single key is baked into the disk image at imaging time
- All school Pis share this key (or it can be per-batch if tighter isolation is needed)
- The key has an expiry date (1 year recommended); renewal is an operational task
- When the key expires, a new one is generated and distributed via the next disk imaging cycle
  or an on-site coordinator visit

**Key storage on the Pi:**
The auth key is stored in a file readable only by root:

```bash
/etc/tailscale/debug-authkey   # permissions: 600, owned by root
```

The activation script reads this file and passes it to `tailscale up`. It is never exposed
to the Console UI or any web-accessible surface.

---

## Network and Access Control

### Tailscale ACL tags

IDEA uses two ACL tags in the Tailnet:

- `tag:idea-ops` — Koen's laptop, the OpenClaw Pi (already on the Tailnet). These devices
  can initiate SSH connections to school Pis.
- `tag:school-pi` — School Pis when they join in debug mode. These devices accept SSH
  connections from `tag:idea-ops` only.

The Tailscale ACL policy (`/etc/tailscale/acls.json` or the admin console) enforces:

```json
{
  "acls": [
    {
      "action": "accept",
      "src":    ["tag:idea-ops"],
      "dst":    ["tag:school-pi:22"]
    }
  ]
}
```

This means a school Pi on the Tailnet is reachable only on port 22, and only from IDEA ops
devices. It cannot initiate connections or reach other nodes.

### SSH access key

The SSH key that IDEA staff use to connect to a school Pi for debugging is separate from the
Tailscale auth key. It follows the same constraints as all machine-to-machine keys in IDEA
(documented in `design/ssh-key-management.md`):

- Ed25519, no passphrase (machine key)
- Stored in `~/.ssh/` on IDEA ops devices (Koen's laptop, OpenClaw Pi)
- The corresponding public key is in `authorized_keys` on the school Pi

Unlike the agent test keys, the school Pi debug key is **not** restricted to a single command —
a full interactive shell is needed for field debugging. It is instead restricted by:
- `from=` option: only accepts connections from addresses in the IDEA Tailnet IP range
- Tailscale ACL: only `tag:idea-ops` devices can reach port 22

This gives equivalent protection to a `command=` restriction without limiting the shell.

### Current SSH access model (transitional)

**Current state:** Field Pis deployed before this design was implemented are accessible over
SSH using the default `pi` user with password authentication enabled. This is the access model
Tapiwa uses for the field upgrade procedure described in Part 5.

**This is intentional and required for the current upgrade cycle.** The field coordinators
need SSH access to existing engines to run the Tailscale upgrade, and no key infrastructure
is yet in place on those machines.

**Future state:** Once the SSH key management design (`design/ssh-key-management.md`) is
implemented and deployed in a production release, password authentication will be disabled
on all school Pis. The `pi` user password will be rotated. All SSH access will require key
authentication. This is a prerequisite for that release and is tracked as a future work item.

**Until that release, the password access door remains open by design.** IDEA accepts this
risk for the current deployment cohort, mitigated by the fact that school Pis operate on
isolated school LANs with no internet exposure.

---

## Activation Mechanisms

Debug mode must be activatable only by someone physically present at the school or on the
school LAN. Two mechanisms are designed here, in phases.

### Phase 1 — SSH-based activation (immediate, no Console changes needed)

Each field Pi has a well-known mDNS hostname (`engine-1.local`). Tapiwa (or any field
coordinator) can reach it over the school LAN using the default `pi` credentials:

```bash
ssh pi@engine-1.local
```

Once logged in, Tapiwa runs the activation script — either directly from the Pi or after
mounting the USB drive that was used for the Tailscale upgrade:

```bash
sudo /usr/local/bin/tailscale-debug-activate.sh
```

The script:

1. Reads the auth key from `/etc/tailscale/debug-authkey`
2. Starts the Tailscale service: `sudo systemctl start tailscaled`
3. Joins the Tailnet: `sudo tailscale up --authkey "$(cat /etc/tailscale/debug-authkey)" --ephemeral --advertise-tags=tag:school-pi`
4. Prints the Pi's Tailscale IP address to the terminal (visible in Tapiwa's SSH session)
5. Waits for a keypress, then runs `sudo tailscale down && sudo systemctl stop tailscaled`

Tapiwa reads the Tailscale IP from her terminal, relays it to IDEA staff via phone or
WhatsApp, stays present while the session runs, and presses a key to close it when done.

**No physical screen required.** Tapiwa's SSH terminal is the interaction surface — she does
not need to be at the Pi console. The USB drive is only needed if the activation script
wasn't installed directly to the Pi during the upgrade.

**Pros:** No Engine or Console changes required. Can be deployed immediately. Works without
a screen attached to the Pi.
**Cons:** Requires SSH access to the school LAN (Tapiwa must be on-site or on the school
network). Coordinator must remain present (can't walk away and leave it active).

**The SSH approach is the standard for early deployments.** It is simple, auditable (the
session is visible in Tapiwa's terminal), and makes activation intentional.

### Phase 2 — Console UI button (better UX, requires Engine API work)

A "Remote support" toggle in the Console UI. Visible only to users with coordinator role or
above. Clicking it:

1. Sends a request to the Engine local API: `POST /api/debug/remote-support {enable: true}`
2. The Engine runs the same steps as the USB script (via a restricted `sudoers` rule)
3. The Console displays the Pi's Tailscale IP and a session timer
4. A "Stop remote support" button (or automatic timeout after N hours) calls
   `POST /api/debug/remote-support {enable: false}`

**The sudo model:**
The Engine process runs as a non-root user. To start/stop Tailscale and run `tailscale up`,
it needs `sudo`. A narrow `sudoers` entry limits this to exactly the required commands:

```
engine-user ALL=(root) NOPASSWD: /usr/bin/systemctl start tailscaled, \
                                  /usr/bin/systemctl stop tailscaled, \
                                  /usr/bin/tailscale up --ephemeral *, \
                                  /usr/bin/tailscale down
```

This is the minimal privilege needed. The Engine cannot run any other privileged command.

**Pros:** Better UX. No USB stick needed. Session visible in the Console.
**Cons:** Requires Engine API work (Axle) and Console UI work (Pixel). Phase 2 item.

---

## Session Flow (end to end)

```
Coordinator (Tapiwa)          IDEA staff (remote)            School Pi
────────────────────          ──────────────────             ─────────
1. Notices a problem.
   Contacts IDEA.
                              ← 2. Asks Tapiwa to
                                    activate debug mode.
3. ssh pi@engine-1.local
   (default credentials,
   school LAN).
   Runs activation script.
                                                              4. tailscaled starts.
                                                                 tailscale up --ephemeral
                                                                 Pi joins Tailnet as
                                                                 tag:school-pi.
5. Reads Tailscale IP
   from SSH terminal.
   Sends IP to IDEA staff
   via phone / WhatsApp.
                              6. ssh pi@<tailscale-ip>  →
                                                              7. Shell session open.
                                                                 Staff diagnose/fix.
                              8. Logs off.
9. Presses Enter in her
   SSH terminal (or Console
   "Stop" button in Phase 2).
                                                             10. tailscale down.
                                                                 tailscaled stops.
                                                                 Device removed from
                                                                 Tailnet (ephemeral).
                                                                 Pi is isolated again.
```

---

## Key Lifecycle

```
Imaging time
  │  Generate reusable ephemeral auth key in Tailscale admin console
  │  Set expiry: 1 year from imaging date
  │  Tag: tag:school-pi
  │  Store in /etc/tailscale/debug-authkey (600, root-owned)
  │  Record in platform/keys.md: key name, purpose, expiry, batch
  │
Active deployment
  │  Key is dormant on Pi — service disabled, no network activity
  │
Debug session (when needed)
  │  Coordinator activates → Pi joins Tailnet (ephemeral)
  │  Session ends → Pi leaves Tailnet automatically
  │  Key remains valid for future sessions
  │
Key rotation (annual or on compromise)
  │  Generate new reusable ephemeral key in Tailscale admin console
  │  Revoke old key in admin console
  │  Distribute new key to school Pis:
  │    Option A: Bake into next disk image (schools get it with next app update)
  │    Option B: Coordinator visits (run key-update script on USB stick)
  │  Update platform/keys.md
```

**On key expiry before first use:**
A pre-provisioned key that expires before the school ever needs remote support is a real
scenario. The resolution is either:
- Set expiry to "no expiry" in Tailscale (acceptable for a reusable ephemeral key if the
  Tailnet ACL and SSH key provide the primary access control)
- Or: accept that the key needs to be refreshed at the next coordinator visit if it expires

Recommendation: set key expiry to "no expiry" for school Pi auth keys. The security boundary
is the Tailscale ACL (restricts which devices can reach the Pi) and the SSH key (restricts who
can authenticate). The auth key only proves the Pi is allowed to join the Tailnet — it doesn't
grant shell access on its own.

---

## Open Questions

These were identified during design and are not yet resolved:

1. **Coordinator IP relay**: ~~Resolved.~~ Tapiwa SSHes into the Pi via `engine-1.local` and
   runs the activation script in her terminal. The Tailscale IP is printed there. She relays
   it to IDEA staff via phone call or WhatsApp. No screen on the Pi is required.

2. **Per-Pi vs per-batch auth keys**: Using one shared key for all school Pis is simpler but
   means revoking the key removes debug access from all Pis simultaneously. Per-batch keys
   (one key per imaging run) are a reasonable middle ground — isolated enough, not too complex.

3. **Automatic timeout**: Should debug mode auto-disable after N hours even if the coordinator
   forgets to end the session? Yes — the Phase 2 Console implementation should include an
   automatic timeout (e.g. 4 hours). The USB script version relies on the coordinator being
   present.

4. **MagicDNS hostnames**: With ephemeral devices, MagicDNS hostnames may or may not be
   stable between sessions. IDEA staff should connect by Tailscale IP, not hostname, to
   avoid DNS resolution surprises.

5. **Multiple Pis at one school**: If a school has multiple Pis (engine Pi + a separate device),
   each would have its own auth key and its own Tailscale IP. The activation procedure needs
   to handle this clearly — which Pi is being debugged?

---

## Part 5 — Field Upgrade: Retrofitting Existing Engines

Field engines deployed before this design was implemented (tagged `Zimbabwe26012026` and
earlier) do not have Tailscale installed. This section covers how to bring them up to the
design without reimaging, using a physical USB upgrade package that a field coordinator can
apply on-site.

### What the upgrade adds

Each field Pi needs:
- Tailscale binaries (`tailscale` + `tailscaled`) installed to `/usr/sbin/`
- A systemd service file for `tailscaled` (service disabled and not started by default)
- The IDEA Tailnet auth key stored at `/etc/tailscale/debug-authkey` (600, root)
- The USB activation script installed at `/usr/local/bin/tailscale-debug-activate.sh`

None of this affects normal Pi operation. The Engine, Docker, and all apps continue as before.
Tailscale is dormant until a coordinator explicitly activates it.

---

### Internet connectivity requirement

**Important:** `tailscale up` requires internet access at the time of activation — it must
reach Tailscale's coordination server to register on the Tailnet. School Pis are normally
offline.

**Resolution for activation:** the field coordinator brings a **4G mobile hotspot** to the
school when remote support is needed. They connect the Pi to the hotspot via USB-C tethering
or ethernet adapter, then activate Tailscale. IDEA staff SSH in. When done, the Pi returns to
its normal offline state.

The **upgrade itself** (installing the binaries) requires no internet — everything is on the
USB drive.

---

### Preparing the upgrade USB drive

Done once by Koen (or IDEA technical staff) on an internet-connected machine, then shared
with field coordinators.

**Step 1 — Download Tailscale for ARM64:**
```bash
# Find the current stable version
TSVER=$(curl -s https://pkgs.tailscale.com/stable/ | grep -oP 'tailscale_\K[\d.]+(?=_arm64.tgz)' | head -1)
curl -L "https://pkgs.tailscale.com/stable/tailscale_${TSVER}_arm64.tgz" -o tailscale_arm64.tgz
```

**Step 2 — Structure the USB drive:**
```
/upgrade-tailscale/
  install.sh                  ← runs the upgrade
  tailscale_arm64.tgz         ← Tailscale static binaries
  tailscaled.service          ← systemd service file
  debug-authkey               ← provisioned Tailscale auth key (reusable ephemeral)
  tailscale-debug-activate.sh ← the activation script (Phase 1)
```

The `install.sh`, `tailscaled.service`, and `tailscale-debug-activate.sh` are in the idea
repo at `scripts/upgrade-tailscale/`. The `debug-authkey` is provisioned in the Tailscale
admin console (see key registry at `platform/keys.md`) and added by Koen before handing
the USB to the coordinator.

**Step 3 — Sign the USB (optional, future):** A SHA256 checksum file can verify the package
was not tampered with in transit. Not required for Phase 1.

---

### What the install.sh does

`scripts/upgrade-tailscale/install.sh` (field version):

1. Extracts `tailscale_arm64.tgz` → copies `tailscale` and `tailscaled` binaries to `/usr/sbin/`
2. Installs `tailscaled.service` to `/etc/systemd/system/`
3. Runs `systemctl daemon-reload` — does NOT enable or start the service
4. Copies `debug-authkey` to `/etc/tailscale/debug-authkey` with permissions 600, owner root
5. Copies `tailscale-debug-activate.sh` to `/usr/local/bin/` with permissions 755
6. Writes an upgrade receipt to `/home/pi/upgrade-tailscale.log` (date, version, success/fail)
7. Prints "Tailscale debug mode installed. Service is disabled — no change to normal operation."

**Idempotent:** running the script a second time (e.g., for a key rotation) overwrites the
existing files cleanly without side effects.

---

### Test procedure (run on Koen's Pi before distributing to field)

Run the full upgrade on the current OpenClaw Pi to validate the script before handing USB
to Tapiwa. The OpenClaw Pi is internet-connected, making it ideal for a full end-to-end test.

```bash
# On the Pi host (via SSH):

# 1. Mount the USB drive
sudo mkdir -p /mnt/usb && sudo mount /dev/sda1 /mnt/usb

# 2. Run the install script
sudo bash /mnt/usb/upgrade-tailscale/install.sh

# 3. Verify: binaries present, service disabled, key stored
ls -la /usr/sbin/tailscale /usr/sbin/tailscaled
systemctl is-enabled tailscaled   # should print "disabled"
sudo ls -la /etc/tailscale/debug-authkey  # should be 600 root

# 4. Run the activation script (simulates Tapiwa activating debug mode over SSH)
#    This is run from the SSH terminal — no screen on the Pi needed
sudo /usr/local/bin/tailscale-debug-activate.sh
# Expected: prints Tailscale IP in terminal; Pi appears in Tailscale admin console

# 5. From Koen's laptop: SSH in via Tailscale
ssh pi@<tailscale-ip>  # or ssh pi@openclaw-pi.tail2d60.ts.net (already known)

# 6. Confirm normal ops unaffected
docker ps   # all containers still running
curl -s http://localhost:8000/health  # MC still responding

# 7. End the session (coordinator presses Enter on activation script)
# Tailscale down; Pi leaves Tailnet; verified in admin console

# 8. Verify the service is stopped and disabled
systemctl is-active tailscaled   # should print "inactive"
```

**Pass criteria:**
- Install completes without errors
- Service is disabled and does not start on its own
- Activation connects to Tailnet and Pi appears with `tag:school-pi`
- SSH session works from IDEA ops device
- Deactivation removes Pi from Tailnet (ephemeral key)
- Docker and Engine unaffected throughout

---

### Field coordinator upgrade procedure (Tapiwa)

See `field/tailscale-debug-upgrade-tapiwa.md` in the programme manager workspace for the
plain-language guide written for Tapiwa. It covers: what the upgrade does, step-by-step
installation, what to say to school staff, what to do if something looks wrong.

**Access model for the upgrade:** Tapiwa connects to each Pi via `ssh pi@engine-1.local`
using the default credentials. No screen or keyboard needs to be attached to the Pi. She
runs the install script over SSH from her laptop while connected to the school WiFi.

The upgrade changes nothing about how Tapiwa accesses the Pi — she continues using the same
default SSH credentials for any follow-up visits. The Tailscale capability is dormant until
Koen asks her to activate it for a specific support session.

---

## Implementation Plan

### Phase 1 (no Engine/Console changes required)

- [ ] Generate reusable ephemeral auth key in Tailscale admin console; tag `tag:school-pi`
- [ ] Set ACL in Tailscale admin console: `tag:idea-ops` → `tag:school-pi:22` only
- [ ] Write USB activation script (`scripts/tailscale-debug-activate.sh`)
- [ ] Generate SSH debug key pair; install public key in school Pi image's `authorized_keys`
      (with `from=` restriction to IDEA Tailnet IP range)
- [ ] Add auth key storage to Pi image build: `/etc/tailscale/debug-authkey`
- [ ] Document activation procedure for field coordinators (plain language, in coordinator handbook)
- [ ] Add key entries to `platform/keys.md` registry

### Phase 2 (Engine + Console work, cross-agent)

- [ ] Engine: add `POST /api/debug/remote-support` endpoint (Axle task)
- [ ] Engine: add narrow `sudoers` rule for Tailscale commands (Axle task)
- [ ] Console: add "Remote support" toggle with status display (Pixel task)
- [ ] Console: automatic session timeout with configurable duration (Pixel task)
- [ ] Cross-agent tasks to be created at Phase 2 kickoff (Atlas → Axle, Atlas → Pixel)
