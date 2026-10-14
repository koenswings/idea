# Tailscale at schools: one fleet tag, one fleet key

**Author:** Atlas (decision by Koen)
**Date:** 2026-10-13
**Status:** Approved

Supersedes the per-school / `tag:school-pi` / ephemeral debug-mode parts of [tailscale-remote-management.md](tailscale-remote-management.md) and [ssh-key-management.md](ssh-key-management.md). Both are kept.

## Problem or opportunity
The earlier proposals used per-school tags and per-school (ephemeral, debug-mode) keys. That ties a Pi to one school: moving a Pi needs an ops step, and every school adds keys and ACL entries.

## Proposed approach
1. **Tailscale is always on** on school Pis (not a debug mode switched on per visit).
2. **No per-school tags and no per-school keys.** Pis must move freely between schools with no ops step.
3. **One fleet tag: `tag:idea`.** Every IDEA Pi joins with it.
4. **One fleet auth key**, tagged `tag:idea`. The key itself is a secret: it is never committed, never put in docs, manuals or issues; it lives root-only on the Pi (mode 600) and in the ops secret store.
5. **ACL:**
   - admins -> `tag:idea`: allowed (IDEA ops/admin devices reach the Pis, SSH).
   - `tag:idea` -> anything: **denied**. No Pi-to-Pi traffic over Tailscale, no Pi-to-admin traffic.
6. **Pis talk to each other only over the LAN websocket** (Engine peering on the school LAN). Tailscale is for remote admin only.

## User experience / outcome
Admins reach every school Pi over Tailscale at any time; a Pi can be moved to another school without re-keying or retagging. Pis cannot reach each other or anything else over the tailnet.

## Implementation notes
Sketch of the ACL (illustrative; group names to match the tailnet):
```json
{
  "tagOwners": { "tag:idea": ["group:admins"] },
  "acls": [
    { "action": "accept", "src": ["group:admins"], "dst": ["tag:idea:*"] }
  ]
}
```
With no rule whose `src` is `tag:idea`, tagged Pis cannot initiate any connection on the tailnet.

## Open questions
Follow-ups:
- Install manual 1 (box: `teacher-manuals/install-guides`) still describes per-school tags: must change to `tag:idea` before it is checked in.
- Old proposals keep their history; their INDEX entries point here.
- Revoking a leaked fleet key: rotate the one key and re-auth (existing nodes stay joined); per-node removal is in the admin console.
