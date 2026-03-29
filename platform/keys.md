# IDEA Key Registry

All SSH keys and Tailscale auth keys in the IDEA system. One entry per key.

See [`design/ssh-key-management.md`](../design/ssh-key-management.md) for the full key
management policy, wrapper script convention, and rotation procedures.

---

## Rotation Policy

- **Machine keys** (no passphrase, automated): rotate annually or whenever the source
  machine is rebuilt or decommissioned.
- **Human keys**: rotate when a device is lost, replaced, or access is no longer needed.
- **Tailscale auth keys**: set to "no expiry" for school Pi keys (ACL and SSH key are the
  primary security boundary); rotate if key is compromised or on major platform rebuild.

Record all rotations in this file: mark old entry as `Revoked` with date, add new entry.

---

## Active Keys

### `openclaw-container→pi-host-tests`

| Field | Value |
|---|---|
| **Purpose** | OpenClaw container runs engine test suite on Pi host |
| **From** | OpenClaw container (`idea-net`, `172.20.0.x`) |
| **To** | Pi host — `pi@openclaw-pi.tail2d60.ts.net` |
| **Key type** | Ed25519, no passphrase (automated) |
| **Private key location** | `/home/node/workspace/.ssh/id_ed25519` (container) |
| **`authorized_keys` restriction** | `command="/home/pi/idea/scripts/run-tests.sh"` + `from="172.20.0.0/24"` + `restrict` |
| **Wrapper script** | `/home/pi/idea/scripts/run-tests.sh` |
| **Created** | 2026-03-28 |
| **Status** | Active — ⚠ `command=` restriction not yet applied (Axle task 904feb39) |
| **Env var** | `TEST_SSH_KEY=/home/node/workspace/.ssh/id_ed25519` in Axle's `.env` |

> **Note:** The existing key was generated before this registry. Its current comment is
> `openclaw-axle@idea` — to be corrected to `openclaw-container→pi-host-tests [2026-03-28]`
> when the `command=` restriction is applied.

---

### `id_ed25519_koen` _(inferred — not managed by IDEA)_

| Field | Value |
|---|---|
| **Purpose** | Koen's personal laptop SSH access to Pi host |
| **From** | Koen's laptop |
| **To** | Pi host — full shell |
| **Key type** | Ed25519, passphrase-protected (human key) |
| **Restriction** | None — full shell (Koen is system owner) |
| **Created** | ~2026-03-01 |
| **Status** | Active |

---

## Planned Keys

### `openclaw-container→pi-host-app-tests`

| Field | Value |
|---|---|
| **Purpose** | OpenClaw container runs Kit 🎒 app compatibility tests on Pi host |
| **From** | OpenClaw container (`idea-net`, `172.20.0.x`) |
| **To** | Pi host |
| **Key type** | Ed25519, no passphrase (automated) |
| **`authorized_keys` restriction** | `command="/home/pi/idea/scripts/run-app-tests.sh"` + `from="172.20.0.0/24"` + `restrict` |
| **Wrapper script** | `/home/pi/idea/scripts/run-app-tests.sh` |
| **Status** | Planned — to be created during Kit bootstrap |
| **Note** | Separate key from engine test key — independent revocation, separate audit trail |

---

### `id_ed25519_field_debug`

| Field | Value |
|---|---|
| **Purpose** | IDEA staff SSH to school Pi during a remote support session |
| **From** | IDEA ops devices (Koen's laptop, OpenClaw Pi) via Tailscale |
| **To** | School Pi — full shell |
| **Key type** | Ed25519, no passphrase (machine key stored on IDEA ops devices) |
| **`authorized_keys` restriction** | `from=<IDEA-Tailnet-IP-range>` — full shell (Tailscale ACL provides isolation) |
| **Status** | Planned — to be created when Tailscale debug mode is implemented |
| **Design ref** | [`design/tailscale-remote-management.md`](../design/tailscale-remote-management.md) |

---

### `tailscale-school-pi-authkey`

| Field | Value |
|---|---|
| **Purpose** | Allows a school Pi to join the IDEA Tailnet during a debug session |
| **Type** | Tailscale reusable ephemeral auth key |
| **Tags** | `tag:school-pi` |
| **Expiry** | No expiry (ACL + SSH key are primary security boundary) |
| **Storage on Pi** | `/etc/tailscale/debug-authkey` (permissions: 600, root-owned) |
| **Status** | Planned — to be provisioned when Tailscale debug mode is implemented |
| **Design ref** | [`design/tailscale-remote-management.md`](../design/tailscale-remote-management.md) |

---

## Revoked Keys

_(None yet.)_
