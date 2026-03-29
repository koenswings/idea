# Design Document Index — IDEA (Org Level)

All org-level design documents. Read this index at boot; pull the full doc when working on
something it constrains. See `design/README.md` for scope guidance (org-level vs repo-level).

Update this file whenever a design doc is added, superseded, or its status changes.

---

## virtual-company-design.md
**Status:** Implemented  ·  **Date:** 2026-03-25 (ongoing)
The authoritative org design: agent roles and responsibilities, cross-agent task convention,
MC usage model, output file policy, communication standards, and approved backlog.
→ [design/virtual-company-design.md](virtual-company-design.md)

## ssh-key-management.md
**Status:** Implemented  ·  **Date:** 2026-03-28
SSH key types, the wrapper-script `command=` convention, `authorized_keys` restrictions,
IDEA SSH access map (human + machine-to-machine), key registry format, and Telegram-triggered
rotation procedure. Key registry lives at `platform/keys.md`.
→ [design/ssh-key-management.md](ssh-key-management.md)

## tailscale-remote-management.md
**Status:** Draft (PR #12 — pending merge)  ·  **Date:** 2026-03-29
Latent Tailscale debug mode for school Pis: design principles, ephemeral auth keys, ACL tag
model, Phase 1 USB activation script, Phase 2 Console UI toggle, session flow, key lifecycle.
→ [design/tailscale-remote-management.md](tailscale-remote-management.md) _(not yet on main)_
