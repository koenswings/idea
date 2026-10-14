# Engine mDNS vs avahi: fix the hostname clash ("<host> (2)")

**Author:** Atlas (Ops), root cause and diff from the r33 investigation
**Date:** 2026-10-13
**Status:** Draft

Sources (ops box): `duration-evidence/path-a-ready-r33/ISSUE-MDNS-SELF-RENAME.md`, `mdns-self-rename-rootcause.md`, `mdns-self-rename-proposal.diff` (2026-10-06).

## Problem or opportunity

### Symptom
On every Engine start with mDNS on, each Engine renames its service once: `idea04` -> `idea04 (2)`, SRV target `idea04-(2).local`. Peers log `No TXT record for idea0x (2). Skipping.` in the first discovery cycles. Seen on idea01/02/03/04.

### Root cause
- The Engine publishes with `@homebridge/ciao` (`src/monitors/mdnsMonitor.ts`) and passes **no `hostname`**, so ciao claims `<host>.local`.
- **avahi-daemon on the same Pi already owns `<host>.local`.** ciao's probe gets avahi's A/AAAA answer, treats it as a conflict and increments both the instance and the hostname.
- The missing TXT is separate: discovery reads TXT only from `additionals`; ciao's unsolicited announcements carry TXT in `answers`.
- Reproduced on the box (a second ciao responder standing in for avahi).

### Impact
- Discovery still works: peers match by TXT `id`/`name` and connect by address. At most a one-cycle (10 s) delay; `MAX_MISSED_DISCOVERIES=3` absorbs it.
- Real cost: names look like a duplicate machine to avahi-browse / dns-sd / a future Console resolver, and a real duplicate hostname would be indistinguishable from this daily false positive.
- The hourly `systemctl restart avahi-daemon` cron on the Pis does not cause or fix this.

## Proposed approach
Proposed diff (tsc clean, 5/5 new tests):
- Publish with `hostname: <host>-engine`, so ciao never claims avahi's `<host>.local`.
- Read TXT from answers + additionals, prefer the TXT matching the PTR instance; log the real FQDN.
- Rejected alternatives: publishing through avahi (D-Bus, larger, Linux-only); `restrictedAddresses` (does not fix the clash).

## User experience / outcome
After a reboot, `avahi-browse -rt _engine._tcp` shows `idea0x` (no `(2)`) on host `idea0x-engine.local`, and the Engine log has no "name changed" / "No TXT".

## Open questions
No Engine PR yet; Koen to approve the approach. Owner: Axle (Engine), with the diff `mdns-self-rename-proposal.diff` (ops box, to be attached to the Engine PR). Ops checks: `avahi active, mdns true` is part of the Path A gate.
