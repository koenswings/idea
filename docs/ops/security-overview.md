**Status:** Draft (idea#181, ops side) · **Maintained by:** Atlas / Steve · 27 October 2026

# IDEA security overview (ops view)

This page explains how IDEA is secured and which risks are still open. It is written for Koen, the IDEA team and future operators. The decisions it records come from idea#181. **This page contains no secret values**: it names where each one lives, never what it is.

## 1. Remote access: Tailscale

- Tailscale is always on at every school, on the router and on every Pi.
- There is **one fleet tag, `tag:idea`, and one fleet auth key**. There are no tags or keys per school, so a Pi can move to another school without any admin step.
- ACL rules:
  - admins → `tag:idea` (all Pis and routers): allowed;
  - `tag:idea` → anything: **denied**, so there is no Pi-to-Pi or school-to-school traffic over the tailnet.
- Pis talk to each other only over the school LAN (the Engine websocket and mDNS).
- An admin on one Pi or router can reach the rest of that school's LAN. An attacker on a compromised Pi can do the same, but is confined to that one school.
- Tagged devices don't expire and don't belong to a person.
- **The auth key is never written into a document, repo, image or log.** It is entered at install or flash time. Ops boxes keep their copy in a 0600 file outside any repo.
- Ops reaches Pis directly on their Tailscale IP, never through a jump host.

## 2. School network

- **Student Wi-Fi `IDEA`** has its own firewall zone. Students can reach only the Pis: no internet, outside DNS and VPNs blocked, and no client-to-client traffic.
- **Teacher Wi-Fi `IDEA-Teachers`** reaches the Pis, plus the internet through one rule that can be switched on and off.
- The Pis don't forward traffic. The Starlink router runs in bypass mode with its own Wi-Fi off.
- The kit router's SSH port is closed on the Tailscale side. Remote reads use LuCI (80/443) as root.

## 3. Default passwords: the `<account>911!` convention

- Every default account follows one scheme, `<account name>911!` (for example the Nextcloud seed accounts and admin, the Kolibri defaults and the router root). These are **published, non-secret defaults**. Their only job is to make first contact possible without a hard-to-type random value.
- Teachers and operators **change them before real use**. The manuals say so wherever a default appears.
- **Router root and Wi-Fi defaults are baked into the published kit router image. This is Koen's deliberate choice:** an offline school must be able to recover a router without us. The risk is that anyone who has the image (it's public) knows the defaults until they're changed. Mitigations: SSH is closed on the Tailscale side, the student zone is isolated, and changing the defaults is an operator step.
- The client card images carry **no** Wi-Fi key and no admin SSH keys (idea#322). `set-card-secrets.sh` writes them at flash time, and `scan-secrets.sh` checks every built image.
- Internal service secrets (for example the Nextcloud database password) stay **generated** per instance and never follow the convention.

## 4. Access to the Pis

- **SSH is key-only:** `PasswordAuthentication no`, with users restricted by `AllowUsers` (the client image verifies this in `verify-image.sh`). Open item: idea02 still allows SSH password login.
- Per-Pi SSH keys are exchanged automatically between Engines through the store. They are restricted to the app-data helper, and there are no keys per school.
- **pm2 runs as `pi`**, and so does the Engine. The Engine does **not** run as root.
- **sudoers:**
  - The Engine may run only a narrow, named set of root helpers (flash helper, app-data, erase-disk, the read-only mount line).
  - `deploy-engine-pi.sh` installs them and checks them with `visudo -c`.
  - The cloud-init blanket `pi ALL=(ALL) NOPASSWD:ALL` is removed by `tools/fleet/strip-cloud-init-sudoers.sh` (idea#153).
- In the apps, the Console has an Operator Login, and the apps have teacher, learner and admin roles.

## 5. Secrets and code

- **No credentials in any repo, log, issue or PR.** CI uses **GitHub Secrets** only (`DOCUMENTATION-RULES.md` rule 10).
- On hosts, runtime secrets live in env files with mode 0600.
- Lesson learned: a personal access token was once found in a git remote URL. It was rotated, and remotes no longer embed tokens.
- Ops messages and reports never print keys, passwords or Wi-Fi keys, not even the public defaults beyond naming the scheme.
- Data is quarantined (moved aside), never deleted, so a mistake can be undone.

## 6. Backups

- Each app can be backed up to a **Backup Disk** from the Console (operator tutorial, chapter 3). The disk stays at the school.
- To document: whether backups are encrypted (today they are not, as far as ops knows), and the rule for physically storing the Backup Disk.
- Ops keeps deployment records (`deployments/`), with sha256 lists, to prove what was installed.

## 7. Store and Engine

- Store isolation through `storeTag` (#157) separates fleets, but it is self-asserted, so it **isn't a security boundary**.
- Updates are rolled out by ops, one Pi at a time, using scripted deploys with backups (`deploy-engine-pi.sh`).

## 8. Open risks / to do

1. The Engine websocket on the LAN seems to have no authentication. What can any LAN device do?
2. Physical access to Pis and disks (no disk encryption).
3. Published router and client defaults stay valid until someone changes them. We need a check or reminder that they were changed.
4. idea02 SSH password login (section 4).
5. Backup encryption (section 6).
6. Fill in the inventory of other risks with the team.
