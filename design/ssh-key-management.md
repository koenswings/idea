# SSH Key Authentication — How It Works and How IDEA Uses It

**Author:** Atlas 🗺️
**Date:** 2026-03-28
**Status:** Draft

---

## Part 1 — How SSH Key Authentication Works

### The core idea

SSH key authentication is based on **asymmetric cryptography**: a pair of mathematically
linked keys where anything encrypted by one can only be decrypted by the other.

- The **private key** is secret. It stays on the machine that initiates the connection and
  never leaves it.
- The **public key** is safe to share. It is placed on any machine you want to access. It
  cannot be used to impersonate you — it can only verify that you hold the matching private key.

The server never sees your private key. Authentication works by proving you possess it,
not by transmitting it.

---

### The handshake, step by step

```
Client (OpenClaw container)          Server (Pi host)
──────────────────────────           ────────────────

1. "I want to connect as user pi"  →
                                   ← 2. "Prove it. Here's a random challenge."
3. Signs challenge with            →
   private key, sends signature
                                   ← 4. Looks up client's public key in
                                        authorized_keys, verifies signature.
                                        "Signature valid — welcome in."
```

In step 4, the server runs a mathematical check: does the signature match the public key
on file? If yes, only someone holding the corresponding private key could have produced
that signature. No password, no secret transmitted over the wire.

---

### The files involved

**On the client (the machine initiating the connection):**

```
~/.ssh/
  id_ed25519          ← private key  (permissions: 600 — only you can read it)
  id_ed25519.pub      ← public key   (safe to share)
  config              ← optional: hostname aliases, port overrides, key assignments
  known_hosts         ← fingerprints of servers you've connected to before
```

**On the server (the machine being connected to):**

```
~/.ssh/
  authorized_keys     ← one public key per line; any key here can log in as this user
```

**Permissions matter.** SSH refuses to work if permissions are too open — it interprets
loose permissions as a security error.

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
chmod 600 ~/.ssh/id_ed25519      # private key
chmod 644 ~/.ssh/id_ed25519.pub  # public key (readable is fine)
```

---

### Key types

| Type | Recommendation | Notes |
|------|---------------|-------|
| Ed25519 | ✅ Use this | Modern, compact, fast, strong. Default since OpenSSH 6.5. |
| RSA 4096 | ✅ Acceptable | Older, widely compatible. Larger keys than necessary. |
| RSA 2048 | ⚠️ Marginal | Acceptable for now but ageing. |
| DSA | ❌ Do not use | Deprecated, weak. |
| ECDSA | ⚠️ Avoid | Concerns about NIST curve backdoors. Ed25519 is better. |

---

### Generating a key pair

```bash
# On the client machine:
ssh-keygen -t ed25519 -C "openclaw-container→pi-host [2026-03-28]"
#           ↑ type     ↑ comment — use this to document purpose and date
```

The `-C` comment appears inside the public key file and in `authorized_keys`. Use it to
record what the key is for and when it was created — this is your key registry in a file.

You will be prompted for a **passphrase**. For interactive human use, always set one. For
automated/machine use (agent → server), leave it empty so the connection can happen
unattended. Document this decision.

---

### Installing the public key on the server

**Option A — ssh-copy-id (easiest, requires password auth first):**
```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub pi@openclaw-pi.tail2d60.ts.net
```

**Option B — Manual (if ssh-copy-id is unavailable):**
```bash
# On the server, append the public key:
echo "ssh-ed25519 AAAA... openclaw-container→pi-host [2026-03-28]" >> ~/.ssh/authorized_keys
```

**Option C — Pipe over SSH (useful when you already have some access):**
```bash
cat ~/.ssh/id_ed25519.pub | ssh pi@server "cat >> ~/.ssh/authorized_keys"
```

---

### Restricting what a key can do

An entry in `authorized_keys` is not just a key — it can carry **options** that limit the
key's permissions. This is how you give a machine access to run one specific command
without giving it a full interactive shell.

```
# Full unrestricted access (for human users):
ssh-ed25519 AAAA... koen-laptop [2026-03-28]

# Restricted to a wrapper script (preferred for machine-to-machine):
command="/home/pi/idea/scripts/run-tests.sh",no-pty,no-agent-forwarding,no-x11-forwarding,restrict ssh-ed25519 AAAA... openclaw-container→pi-host-tests [2026-03-28]

# Restricted by source subnet as well:
from="172.20.0.0/24",command="/home/pi/idea/scripts/run-tests.sh",restrict ssh-ed25519 AAAA... ...
```

**Key options explained:**

- `command="..."` — the server runs only this command when this key connects, regardless
  of what the client requests. The key cannot be used for anything else.
- `restrict` — disables all forwarding (TCP, X11, agent) and PTY allocation. A safe default
  for machine keys.
- `no-pty` — prevents the connection from allocating a pseudo-terminal (interactive shell).
- `from="subnet"` — only allows connections from the specified IP range. Use a subnet
  (`172.20.0.0/24`) rather than a specific IP — container IPs can change across Docker
  restarts depending on network ordering, and a hardcoded IP will silently break.

**Use a wrapper script as the `command=` target, not an inline command.**
Hardcoding the full command chain in `authorized_keys` (e.g. `command="git pull && pnpm build
&& pnpm test:unit"`) is fragile: any change to the test sequence requires editing
`authorized_keys` on the Pi. Instead, point the key to a script on the Pi:

```
command="/home/pi/idea/scripts/run-tests.sh",restrict ssh-ed25519 AAAA... ...
```

The script handles the full sequence internally. Updating the test steps is a code change to
the script, not an `authorized_keys` change. This is especially important when the sequence
includes a `git pull` step before the build — the wrapper script can handle that cleanly.

**Rule for IDEA:** any key used by a machine (agent container, automation script) must
have a `command=` restriction pointing to a wrapper script. Only human operator keys get
unrestricted shell access.

---

### The SSH config file (client side)

Instead of typing `ssh -i ~/.ssh/id_ed25519 pi@openclaw-pi.tail2d60.ts.net` every time,
use `~/.ssh/config`:

```
Host pi-host
  HostName       openclaw-pi.tail2d60.ts.net
  User           pi
  IdentityFile   ~/.ssh/id_ed25519_pi_host
  ServerAliveInterval 30

Host pi-host-tests
  HostName       openclaw-pi.tail2d60.ts.net
  User           pi
  IdentityFile   ~/.ssh/id_ed25519_tests
```

Then just: `ssh pi-host` or `ssh pi-host-tests`. The right key is selected automatically.

---

## Part 2 — SSH Access Map for IDEA

The following connections exist or will exist across the IDEA system.

### Human access

**Koen → Pi host (`openclaw-pi`)**
- Purpose: Docker management, platform restarts, log inspection, deploying config changes
- Transport: Tailscale (`openclaw-pi.tail2d60.ts.net`)
- Key type: Interactive (passphrase-protected Ed25519)
- Restrictions: None — full shell (Koen is the system owner)
- Status: Active

---

### Machine-to-machine (automated)

**OpenClaw container → Pi host (tests)**
- Purpose: Run engine test suite on the Pi where `docker compose` is available
- Decided: 2026-03-28 (Axle architecture decision)
- Key type: Ed25519, no passphrase (automated)
- Restriction: `command="/home/pi/idea/scripts/run-tests.sh"` + `restrict` + `from="172.20.0.0/24"`
  (subnet rather than specific IP — container IP can shift across Docker restarts)
- Wrapper script `scripts/run-tests.sh` handles `git pull && pnpm build && IDEA_TEST_MODE=true pnpm test:unit`
- Status: Planned — implementation task on Axle's board (task 904feb39)
- Note: existing installed key has comment `openclaw-axle@idea` — to be updated to
  `openclaw-container→pi-host-tests [2026-03-28]` when `command=` restriction is applied

**OpenClaw container → Engine Pi (if separate device)**
- Purpose: Same as above, but when the engine test Pi is a separate device from the Pi
  running OpenClaw (e.g. a dedicated test Pi on Tailscale)
- Transport: Tailscale hostname of the test Pi
- Key type: Same as above (same key can be reused if the same restricted command applies)
- Status: Future — depends on whether a separate engine test Pi is acquired

**OpenClaw container → Pi host (Kit tests, future)**
- Purpose: Run app compatibility tests (Kit 🎒) — same boundary problem as the engine:
  app containers need `docker compose` on the host
- Decision: Kit uses the same SSH **mechanism** as Axle establishes, but with a **separate
  key and separate `command=` restriction** pointing to its own wrapper script
  (`scripts/run-app-tests.sh`). Sharing the engine test key is not acceptable: separate
  keys give separate audit trails and independent revocation. Revoking the engine test key
  must not break Kit tests and vice versa.
- Status: Future — to be addressed during Kit bootstrap

---

### Person-to-system (planned/future)

**School coordinator → Console UI**
- Not SSH. Coordinators access the Console via a browser on the school LAN. No
  shell access, no SSH.

**IDEA technical team → School Pi (field debugging)**
- Currently not available — school Pis have no remote access by design (offline-first).
  Any debugging is done physically, on-site.
- Future consideration: a **Tailscale-enabled field debug mode** — see design sketch below.

**GitHub Actions self-hosted runner → (none)**
- A self-hosted runner on the Pi connects outbound to GitHub — GitHub does not SSH
  into the Pi. No inbound SSH required for CI.

---

### Tailscale debug mode

School Pis are offline by design — no Tailscale running, no remote access. But field
support occasionally requires a shell on the Pi without physically traveling to the school.
The Tailscale debug mode is a **latent remote-access capability**: installed but dormant,
activated only on demand, and reverted cleanly afterwards.

The full design is in [`design/tailscale-remote-management.md`](tailscale-remote-management.md).
Key points relevant to SSH key management:

**Auth key type: reusable ephemeral.**
School Pis use a Tailscale **ephemeral** auth key. When the Pi disconnects (`tailscale down`),
Tailscale automatically removes it from the Tailnet — no manual cleanup, no device count
accumulation. A **reusable** ephemeral key is baked into the disk image at imaging time so the
same key works for any number of future support sessions without reprovisioning.

```bash
# Joining the Tailnet (activation step):
sudo tailscale up \
  --authkey "$(cat /etc/tailscale/debug-authkey)" \
  --ephemeral \
  --advertise-tags=tag:school-pi

# Ending the session (cleanup step — Pi leaves Tailnet automatically):
sudo tailscale down
```

**SSH access key for debug sessions.**
The SSH key used by IDEA staff to connect to a school Pi in debug mode is:
- Ed25519, no passphrase (machine key — stored on IDEA ops devices)
- Restricted in `authorized_keys` with `from=<IDEA-Tailnet-IP-range>` (no `command=`
  restriction — a full shell is needed for debugging)
- Recorded in `platform/keys.md` with purpose: `field-debug`

The Tailscale ACL (`tag:idea-ops` → `tag:school-pi:22` only) provides equivalent isolation
to a `command=` restriction: the key is only reachable via Tailscale from IDEA devices.

**Key storage on the Pi:**
```bash
/etc/tailscale/debug-authkey   # permissions: 600, owned by root
```

**Status:** Designed — see `design/tailscale-remote-management.md`. Phase 1 (USB script)
implementable without Engine or Console changes.

---

### Summary map

```
Koen
  │── Tailscale SSH ──────────────────────► Pi host (full shell, passphrase-protected key)

OpenClaw container
  │── SSH (restricted command key) ────────► Pi host: run engine tests
  │── SSH (restricted command key, future)► Pi host: run app tests (Kit)
  │── SSH (restricted command key, future)► Separate engine test Pi (Tailscale)

School Pi
  │── No inbound SSH (by design)
  │── Debug mode: Tailscale (ephemeral, activation-only) → IDEA ops SSH in via tag:idea-ops

GitHub
  │── HTTPS/token (current) ───────────────► github.com (git push/pull from Pi)
  │── Future: self-hosted runner connects outbound to GitHub (no inbound SSH)
```

---

## Part 3 — Managing and Deploying SSH Keys

### The problem

Keys are security credentials. They have a lifecycle:
- Created
- Deployed (public key installed on server)
- Used
- Rotated or revoked (when a machine is replaced, compromised, or decommissioned)

Without a system for this, keys accumulate in `authorized_keys` files, orphaned keys
remain active long after the machine they belong to is gone, and there is no record of
what key grants access to what.

---

### Option A — Manual with a key registry (recommended for IDEA now)

For a small system like IDEA, a structured manual approach is the right level of complexity.

**How it works:**
- Every key has a descriptive comment in the key itself: `who→what [YYYY-MM-DD]`
- A single `keys.md` file in `idea/platform/` documents every key: purpose, source
  machine, target machine, restriction, date created, and current status
- The `authorized_keys` file on the Pi is committed to the idea repo (for the restricted
  machine keys — never for the platform private keys)
- Rotation is manual but triggered by a documented checklist

**Key registry format** (`platform/keys.md`):

```markdown
| Key name | From | To | Restriction | Created | Status |
|---|---|---|---|---|---|
| `id_ed25519_koen` | Koen's laptop | Pi host | None (full shell) | 2026-03-01 | Active |
| `openclaw-container→pi-host-tests` | OpenClaw container | Pi host | `command=run-tests.sh` + `from=172.20.0.0/24` + `restrict` | 2026-03-28 | Active (⚠ restriction pending) |
| `openclaw-container→pi-host-app-tests` | OpenClaw container | Pi host | `command=run-app-tests.sh` + `from=172.20.0.0/24` + `restrict` | TBD | Planned (Kit bootstrap) |
| `id_ed25519_field_debug` | IDEA ops devices | School Pi | `from=<Tailnet-range>` (full shell) | TBD | Planned |
| `tailscale-school-pi-authkey` | School Pi | IDEA Tailnet | Ephemeral, `tag:school-pi`, reusable | TBD | Planned |
```

**Pros:** Simple. No new infrastructure. Works well for 1–3 machines.
**Cons:** Manual rotation; no automatic expiry; relies on discipline.

---

### Option B — SSH Certificate Authority (for future scale)

Instead of distributing individual public keys, you run a Certificate Authority (CA). The
CA signs keys to produce certificates. Servers trust the CA rather than individual keys.

**How it works:**
1. Generate a CA key pair (kept very safe — this is the root of trust)
2. Each user or machine key is signed by the CA: `ssh-keygen -s ca_key -I identity user.pub`
3. On each server, `authorized_keys` is replaced with one line in `sshd_config`:
   `TrustedUserCAKeys /etc/ssh/ca.pub`
4. To revoke a key: add it to a `RevokedKeys` file — no need to touch `authorized_keys`
   on every server

**Pros:** Centralised; revocation is immediate; scales to many servers and users easily.
**Cons:** The CA key itself becomes a high-value target; needs careful protection.
         More complex to set up. Overkill for one Pi.

---

### Option C — Secrets manager (for future enterprise scale)

Store private keys in a secrets manager (HashiCorp Vault, AWS Secrets Manager). Machines
retrieve the key at connection time rather than storing it permanently.

**Pros:** Full audit trail; automatic rotation; zero long-lived secrets on disk.
**Cons:** Requires internet access for the secrets manager — incompatible with IDEA's
         offline-first philosophy for anything on school Pis. Could work for the OpenClaw
         Pi (internet-connected), but adds significant infrastructure for marginal gain
         at this scale.

---

### Recommendation for IDEA

Use **Option A** now. Implement it properly with a `platform/keys.md` registry and
the `authorized_keys` file version-controlled in the idea repo.

Introduce a rotation policy: machine keys (no passphrase, automated) are rotated
annually or whenever the source machine is rebuilt. Human keys are rotated when a
device is lost, replaced, or access is no longer needed.

Move to **Option B** (CA) when IDEA operates more than one Pi with shared access —
for example, if field coordinators are given SSH access to their school Pi for remote
support. At that point, distributing individual keys becomes unmanageable.

---

### Rotating or revoking a key via Telegram command

IDEA's operational agents (Atlas and others) can be commanded directly via Telegram to
assist with SSH key rotation. The work is split between what the agent can do autonomously
and what requires Koen to run a command on the Pi.

**What Atlas can do from a Telegram command:**
- Generate a new Ed25519 key pair inside the OpenClaw container (`ssh-keygen`)
- Output the ready-to-paste `authorized_keys` line — with `command=`, `restrict`, and
  `from=` options already formatted correctly for the key's purpose
- Prepare the exact line to remove from `authorized_keys` when revoking a key
- Update the relevant `.env` file (e.g. `TEST_SSH_KEY` path in Axle's workspace)
- Update `platform/keys.md` (the key registry) with the new or removed entry

**What Koen must do on the Pi:**
- Append the new public key to `/home/pi/.ssh/authorized_keys`
- Remove the old or revoked line from that file

Atlas cannot modify files on the Pi host directly. However, the agent delivers the exact
command to run — typically a single `echo "..." >> ~/.ssh/authorized_keys` or an `sed -i`
line — so the Pi-side step is copy-paste.

**Example Telegram commands:**
- "Rotate the engine test SSH key"
- "Revoke the `openclaw-container→pi-host-tests` key"
- "Generate a new Kit test key"

**Scope note:** This covers *machine-to-machine* keys (OpenClaw container → Pi host).
Koen's personal laptop key is outside Atlas's scope — that is managed by Koen directly.

---

## Part 4 — Immediate Action Items for IDEA

In priority order:

1. **Set up the OpenClaw container → Pi host key** for test execution (Axle task 904feb39)
   - Key already generated; stored at `/home/pi/idea/.ssh/` on the Pi and in Axle's workspace
   - **Remaining steps:**
     a. Write `scripts/run-tests.sh` on the Pi (wrapper: `git pull && pnpm build && IDEA_TEST_MODE=true pnpm test:unit`)
     b. Update `authorized_keys` on the Pi: add `command="/home/pi/idea/scripts/run-tests.sh"`,
        `from="172.20.0.0/24"`, `restrict` to the existing key entry; update key comment
        from `openclaw-axle@idea` to `openclaw-container→pi-host-tests [2026-03-28]`
     c. Add `TEST_SSH_KEY=/home/node/workspace/.ssh/id_ed25519` to Axle's `.env`

2. **Create `platform/keys.md`** — the key registry
   - Document all existing keys (starting with Koen's laptop key)
   - Commit to the idea repo

3. **Document the Kit test key** (placeholder) — record the planned key in the registry
   with status `Planned` before Kit is bootstrapped, so it's not forgotten

4. **Establish rotation policy** — one paragraph in `platform/keys.md` stating the rule:
   machine keys rotated annually; human keys rotated on device change or role change
