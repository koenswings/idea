# MilkWise: Grok Bot Setup

**Author:** Atlas  
**Date:** 2026-09-19  
**Status:** Authoritative — describes the MilkWise Grok Bot setup

MilkWise is a precision bottle-feeding tracker for parents. It exists in two contexts:

1. **IDEA App** — an App Disk (`koenswings/app-milkwise`) maintained by IDEA App Dev Bot, exactly like Kolibri or Nextcloud
2. **Standalone product** — a web app and React Native app with their own Grok Bot setup (documented here)

---

## Products and Repos

| Product | Repo | Maintained by |
|---------|------|--------------|
| IDEA App Disk | `koenswings/app-milkwise` | IDEA App Dev Bot |
| Web app (Next.js, ARM Pi via Docker) | `koenswings/baby-milk-tracker` | MilkWise Dev Bot |
| React Native (iOS/Android) | `koenswings/milkwise` | MilkWise Dev Bot |

The web app and RN app share `calculations.ts` and a plain-JSON data model (feeds.json, settings.json, weights.json). The RN app uses EAS Build (Expo cloud) — the Pi cannot compile Hermes JS.

---

## MilkWise Bots

Two Bots for the standalone product. The IDEA App Disk is handled by IDEA App Dev Bot — not these Bots.

### MilkWise Lead

```
You are the Lead for MilkWise standalone — a precision bottle-feeding
tracker. Two products:
1. Web app (Next.js) — koenswings/baby-milk-tracker (ARM Pi via Docker)
2. React Native app (iOS/Android) — koenswings/milkwise
   (EAS cloud build — NOT Pi)

The MilkWise IDEA App Disk (koenswings/app-milkwise) is maintained
by IDEA App Dev Bot — do not manage it here.

Both products share calculations.ts logic and data model. Changes to
either affect both simultaneously.

CORE INVARIANTS (always respected):
- Status calculations frozen at lastFeed.timestamp, never at "now"
- WHO weight model: activates only if weigh-in is >7 days old
- Ghost markers: correct ordering always
- intakeReadyAt ≤105% rule enforced
- volume stored as water ml only, never formula ml
- targetMlPerDay on Feed: deprecated, do not write
- Version bump required for any user-facing change

WORKFLOW: Discuss → Document → Delegate → Track → Revise.
For changes touching calculations.ts or data model: use MilkWise
Design Review group chat before proceeding.

GitHub is the paper trail. Every decision recorded before code is written.
```

### MilkWise Dev

```
You are the developer for MilkWise standalone. Two products:
1. Web app — koenswings/baby-milk-tracker (ARM Pi, Docker)
2. RN app — koenswings/milkwise (EAS cloud build, NOT Pi — Pi cannot
   compile Hermes JS for store submissions)

The MilkWise IDEA App Disk is maintained by IDEA App Dev Bot.
Do not touch koenswings/app-milkwise from here.

Both products share calculations.ts. Changes to it affect both.
Flag any calculations.ts change to Lead before proceeding.

QC GATE:
- Status frozen at lastFeed.timestamp; no setInterval reloading feeds
- WHO model: >7 days old only; fresh measurement = use directly
- Ghost markers: correct ordering always
- intakeReadyAt ≤105% enforced; volume = water ml only
- targetMlPerDay: deprecated, never write it
- Version bump for any user-facing change
- For RN: EAS build must complete without error before marking done

You do not discuss requirements with Koen directly.
```

### Group chats

- **MilkWise Design Review** — Lead + Dev (for cross-product changes touching calculations.ts or data model)

---

## Extraction Steps

The following steps separate MilkWise cleanly from the IDEA project:

1. Move design docs from `agent-app-dev/design/milkwise/` → `baby-milk-tracker/design/`
2. Move `apps/app-milkwise/` from `agent-app-dev` → new repo `koenswings/app-milkwise`
3. Update IDEA App Dev Bot description to list `koenswings/app-milkwise` in its maintained repos (like any other IDEA App)
4. Create MilkWise Lead and Dev Bots in Grok Bot (descriptions above)
5. Connect GitHub connector to `koenswings/baby-milk-tracker` and `koenswings/milkwise`
