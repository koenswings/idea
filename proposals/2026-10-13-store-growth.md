# Store growth: heartbeats and metrics out of the store history

**Author:** Axle (Engine Dev)
**Date:** 2026-10-13
**Status:** Approved

Executed dev-pool compaction: [docs/ops/store-compaction-devpool.md](../docs/ops/store-compaction-devpool.md). References to /workspace paths are ops-box evidence.
 Evidence: /workspace/r86q-diag/NOTES.md, breakdown.json; code read at Engine main 31b82f4, Console main, harness feat/stage2-harness-rehome, idea repo main (clones under /workspace/store-design).

## Summary for Koen
- The shared store slows down because every 30 s each Pi writes "I'm alive" into it and every 15 s it writes container stats. Every write is kept forever: about 18k of the ~23k changes per day.
- **Heartbeat:** "is this Pi online?" can come from a short "I'm here" message sent over the existing connection, which is never saved. Only two places need a stored time, and a coarse one is enough there: the 7-day peer-key expiry, and Console clock-skew protection. For those, the Engine writes `lastSeen` at most once an hour (24/day per Pi instead of 2,880).
- **Metrics:** each Pi sends its latest container stats every 15 s as an unsaved message on the same connection. Automerge-repo 2.3.1 already forwards these messages from Pi to Pi, so a Console connected to any Pi sees every Pi. A Pi that goes quiet gets marked "stale" after 45 s. Traffic is about 1 KB/s for the whole fleet.
- **Operation pruning** is still worth doing, but it's a separate, smaller fix. Operation records are 916 KB of the 925 KB of current data. They speed up snapshots and the Console, but they aren't what makes history grow.
- Net effect: about 23k changes/day becomes about 3–5k/day. Add a one-time compaction and loading goes from about 60 s to about 2 s on a Pi.

## automerge-repo support (verified in the source)
- Versions: Engine `@automerge/automerge-repo` 2.3.1 (+ websocket 2.3.1); Console ^2.2.0.
- `DocHandle.broadcast(msg)` sends a CBOR-encoded message to every peer that syncs that doc. The receiver gets `handle.on('ephemeral-message', {senderId, message})`. Nothing is stored.
- **Relay works:** `DocSynchronizer.receiveEphemeralMessage` re-emits the message to every other peer of the doc (dist/synchronizer/DocSynchronizer.js ~l.236). `NetworkSubsystem` drops duplicates by `senderId:sessionId:count` (dist/network/NetworkSubsystem.js l.55). So Pi A → Pi B → Console works with no Engine re-broadcast code. Each Pi forwards once, so it is a flood with dedupe.
- Engine path check: `wsServerThread.ts:170` special-cases only sync/request (foreign-doc guard). Ephemeral messages are enqueued normally. Still to verify in a test: the StoreScope share policy and the worker relay forward `type:'ephemeral'` for 3zoqd, and a peer that hasn't synced 3zoqd yet does not get them (it isn't in `#peers`).
- Caveat: an ephemeral message reaches only peers connected *at that moment*. That's fine for "latest value" data. A newly connected Console sees everything within one interval (≤15 s).

## (A) Heartbeat: every consumer of lastRun (there is no `lastSeen` field today)
| file:line | what it decides | history-free replacement |
|---|---|---|
| Engine src/monitors/timeMonitor.ts:75-82 (generateHeartBeat, via start.ts:246-252 every heartbeatIntervalMs = 30 s, config.yaml:10) | the writer: 8.6k changes/day for 3 Pis | `storeHandle.broadcast({t:'hb', engineId, now, bootedAt})` every 10 s. Write the stored `lastSeen` only if more than 1 h old. Keep the timer for `peerAccess.onHeartbeat()` (start.ts:252), which doesn't need the write. |
| Engine src/data/Engine.ts:120,153 (set at boot = booted) | initial value | keep (1 write per boot) |
| Engine src/data/Engine.ts:235 (rebootEngine) | marks halt time | keep (rare) |
| Engine src/monitors/storeMonitor.ts:85-93,128 | log line only | delete |
| Engine src/data/PeerAccess.ts:47,87-89 | **peer-key expiry**: drop a peer's SSH key after 7 days without a heartbeat (peerStaleHours) | read the hourly `lastSeen` (hour resolution is plenty for 7 days). peer-verify's test with peerStaleHours 0.05 (3 min) then needs the fast path: also treat "pinged in the last N min" from an in-memory map of ephemeral pings as alive. Proposal: `max(lastSeen, lastPingSeen)`. |
| Console src/store/signals.ts:24-27 → components/NetworkTree.tsx:105 | **online dot** (lastRun < 90 s) | `liveness` signal in Console store/engine.ts: map engineId → last `hb` receipt time on the Console clock. Online = received in the last 30 s (3 × 10 s). This also removes the Pi-clock-vs-browser-clock skew the current check has. |
| Console src/store/remoteConfirm.ts:114-142 (snapshotAtSend.engineClock) | **clock-skew guard** for command confirmation: compares op timestamps with the same Engine's clock | use `now` from that Engine's latest `hb` ping (better: current within 10 s, not 30 s). Fall back to `lastSeen` and then null (the check is already skipped when null). |
| Console src/types/store.ts:44, mock/mockStore.ts:54,68, mock/filesFixtures.ts:43 | type + fixtures | rename to `lastSeen?`, mocks feed the liveness map |
| harness test/duration/ui/playwrightDriver.ts:108-116 | walk asserts the online dot | unchanged selector; it follows the Console fix |
| harness test/duration/realFleetOps.ts:1458-1473 | fleet snapshot (peerAccess, lastRun) for preflight/evidence | report `lastSeen` + "pinged" from a listener on the walker's store session |
| harness test/duration/realFleetOps.ts:2424-2441 + duration-walker.test.ts:3446,3564 | **reboot verification**: lastBooted advanced and Engine back | lastBooted alone (already written per boot) + an `hb` received after reboot |
| harness test/duration/peerPreflight.ts:149 | preflight: each pool Engine present/recent | hb received within 30 s |
| Engine script/peer-verify.sh:304 | "entry exists" check | `lastBooted` / `hostname` present |
| Engine script/peer-verify.sh:350 | picks the newest of duplicate ids per hostname (sort by lastRun) | sort by `lastBooted` |
| Engine script/peer-verify.sh:684-709 (+ peer-verify-store.ts:57) | stop/return test: "B's heartbeat reached A within 240 s" | peer-verify-store.ts listens for `hb` for N s (or reads `lastSeen`, which is written on boot) |
| Engine script/dump-store.ts:170 | display | show `lastSeen` |
| idea repo tools/fleet/* | **none**: check-fleet-health.sh uses pm2 status and HTTP, not lastRun | — |
| Engine test/* (largeStoreDoc, peer-access, engine-network, stop-persists, startup-engine-scope, legacy e2e) | fixtures | follow the rename |

## (B) Metrics: latest per Pi, no history
**Mechanism:** ephemeral broadcast on the 3zoqd handle over the existing sync WS. No new port or endpoint, and it works through the Console's single connection because of the built-in relay.
- **Engine** `src/monitors/dockerMetricsMonitor.ts:172-190`: replace `storeHandle.change(... inst.metrics = m)` with `storeHandle.broadcast({t:'metrics', engineId, sampledAt, instances:{[id]: DockerMetrics}})` every 15 s (POLL_INTERVAL_MS, l.23).
  - Keep one stored write only when an instance leaves Running: set `metrics = null`, or better, drop the `metrics` field from Instance altogether (and from usbDeviceMonitor.ts:467-470).
  - One-time migration: delete `instanceDB.*.metrics` (one change).
  - Also add `src/data/Liveness.ts`, which sends `hb` (A) and keeps the in-memory map of peer pings for PeerAccess.
- **Console** `src/store/engine.ts` (where the Repo + handle live, ~l.194-220): `handle.on('ephemeral-message')` → a Solid signal `liveMetrics: Map<engineId, {receivedAt, sampledAt, instances}>` and `liveness: Map<engineId, receivedAt>`. Clear both on reconnect.
  - `components/InstanceRow.tsx:139-175,655` and `components/MobileAppList.tsx:148` read `liveMetrics()[inst.engine]?.instances[inst.id]` instead of `inst.metrics`.
  - `types/store.ts:186-246`: move DockerMetrics out of Instance.
- **Pis the Console isn't connected to:** Pi C broadcasts → its peer Pi A forwards to all its other 3zoqd peers, including the Console. Duplicates via other paths are dropped by the count/session dedupe. This needs no code.
- **Offline/stale marker:** Console clock only.
  - Metrics older than 45 s (3 × 15 s) show greyed "stale — last update hh:mm:ss".
  - No `hb` for 30 s → Pi offline, metrics hidden.
  - Never compare against the Pi's `sampledAt` (school Pis have no RTC).
- **Bandwidth (real numbers):**
  - One instance's DockerMetrics is ~260 B as JSON (9 numbers; CBOR is smaller). A Pi with 3 running apps sends ~0.9 KB per message with envelope; `hb` is ~150 B.
  - Per Pi: 0.9 KB / 15 s + 0.15 KB / 10 s ≈ 75 B/s.
  - Pool (3 Pis + 1 Console, full mesh): each message crosses every link about once each way before dedupe, so ≈ 4 × 3 × 75 B/s ≈ 1 KB/s fleet-wide.
  - A 10-Pi school ≈ 10 KB/s on the LAN. Negligible, and nothing hits disk.
  - Today the same data costs ~9.8k stored changes/day and 55 % of history bytes.

## (C) Is operation pruning (option 3) still needed after A+B?
Yes, but for state size, not history growth. It's lower priority than A+B.
- **Live state:** operationDB is 916 KB of 925 KB (breakdown.json). It holds 2,089 ops (2,059 Done, 30 Failed), averaging 439 B, and 1,017 of them are older than 7 days. Every Console render, toJS and snapshot carries all of it.
- **History rate:** op progress/status was 1.2k–2.4k changes/day plus "other" (op create, instances, disks) 1.7k–3.4k/day. That is ~3–6k/day, about 15–25 % of today's rate, and this is what's left after A+B. Pruning deletes records but doesn't remove their past changes, so it doesn't shrink history.
- **Recommendation:**
  1. Prune Done/Failed ops older than 7 days, moving them to the daily CommandLog (#183 rotation already exists). That's −50 % of live state now and it stays bounded.
  2. Cut progress writes to step changes only (no per-percent updates).
  3. Pair A+B+C with a one-time compaction (option 4, store epoch). Compacted today: 322 KB, 0.39 s load on the box (~2 s on a Pi). With A+B the remaining ~4k changes/day add only ~1 s of Pi load per month, versus ~7 s per day now.

## Open checks before building
1. Unit test: an ephemeral message relays Engine→Engine→Console through wsServerThread worker + StoreScope share policy.
2. The Console connects to just one Engine. Confirm that one Engine is peered to all others (mesh via mDNS/connectEngine). Otherwise metrics from an unpeered Pi can't arrive. That limitation is the same as for sync today.
3. Mixed fleet during rollout: an old Console reads `inst.metrics`/`lastRun`. Ship the Console first, with a fallback to the stored fields.

---
# Follow-up answers for Koen (2026-10-13 14:00)

## Short version
- **7-day key expiry:** it was a recommendation from the per-Pi key design note, which is headed "Koen's decision 2026-10-06". It shipped in commit 46d4d57 / PR #151, merged by koenswings on 2026-10-07. I found no comment where Koen discusses the 7-day number itself.
  - It protects against old Pis keeping SSH access to the others forever.
  - A Pi back after the holidays already works: it is re-trusted within seconds of booting.
  - It can stay with an hourly `lastSeen`, or be removed and leave revocation to deleting the Pi's entry.
- **Weekly night-time reset:** possible, but it's the riskiest of the options.
  - A store reset means a new store URL for every Pi and every Console at once.
  - Pis on different URLs refuse each other today, so a Pi that is off during the switch is cut off.
  - With no leader, nobody owns "it's time".
  - The load still climbs to ~45-55 s on a Pi before each reset.
- **Recommendation:** ephemeral heartbeats/metrics plus pruning, and a rare *manual* compaction during a planned store migration (Path A style). No automatic weekly reset.

## Q1. The 7-day peer-key expiry (PeerAccess.ts:47,87-89)
- **Origin:**
  - `git log -L` on PeerAccess.ts lines 40-95 gives one commit: **46d4d57**, "feat(peer-keys): each Engine makes, publishes and syncs its own Engine key through the store". The author is shown as koenswings (agents commit through Koen's account, so this was an agent).
  - It is in **PR #151**, "Engine 2/3 (draft): app data copied as root via idea-app-data, per-Pi peer keys…", merged by koenswings on 2026-10-07 01:43 CEST, and **#154** catch-up to main.
  - The commit message says: "Stale expiry: a peer without a heartbeat for 7 days (settings.peerStaleHours, default 168) … loses its key at the next sync."
- **Design source:** /workspace/duration-evidence/design-per-pi-engine-key.md ("Status: Koen's decision, 2026-10-06").
  - §4 "Open points, with a recommendation each" proposes the **stale-key rule**: drop a peer whose `lastRun` is older than 7 days.
  - It argues that a returning peer re-adds itself within seconds, and that a lost or stolen Pi is revoked at once by deleting its engineDB entry.
  - There is no GitHub issue for it. `gh search` finds only idea#181 (security overview docs), which doesn't define it.
- **Agreed with Koen?** Only indirectly. The note's header says the per-Pi key design was Koen's decision, and Koen merged #151. But 7 days was an agent recommendation listed under "open points".
  - On PR #151, the koenswings-authored comments are agent status notes (unit leftovers, helper v3).
  - None of them mentions stale, 7 days or 168. I found no evidence that Koen discussed or approved the 7-day number specifically.
- **What it protects against:** keys of Pis that are gone piling up in every Pi's `authorized_keys`: retired or reimaged Pis, or a Pi moved to another school that still sits in the store. With it, an abandoned Pi loses SSH access to its peers after a week without anyone acting.
  - It is *not* the revocation path for a stolen Pi. That is deleting its engineDB entry.
  - The helper also caps the file at 256 lines.
- **A Pi offline > 7 days (holidays), today:**
  1. While it's off, the other Pis drop its key at their next heartbeat after day 7.
  2. Nothing else is affected: apps, store data and the disks it holds stay as they are.
  3. When it boots, it writes `lastRun` (Engine.ts:120/153) and re-publishes peerAccess.
  4. Peers see a fresh heartbeat and re-add its key at their next sync, within about 5-30 s.
  5. Meanwhile it may briefly drop *their* keys on its own first heartbeat, because its copy of the store is old until sync completes. Then it re-adds them.
  6. The only visible effect is that a cross-Pi copy started in those first seconds is refused with "not accepted yet".
  
  So the expiry is harmless for holidays.
- **If removed:** nothing breaks functionally. Keys of dead Pis stay authorized until ops deletes their entry (phantom cleanup already removes old entries when a reimaged Pi gets a new engineId).
  - Cost: less automatic hygiene. A forgotten, sold or stolen Pi that nobody deletes keeps SSH reach to the fleet's restricted gate forever.
  - Options:
    - keep the rule on the hourly `lastSeen` (my proposal: same behaviour, 24 writes/day instead of 2,880);
    - or remove it and rely on explicit deletion from the Console.
  
  Either is fine. It's Koen's call.

## Q2. Weekly night-time clear/compaction of the store doc
Automerge can't throw away history inside a document that other peers also hold. Any peer that still has the old changes sends them back on sync. So a "weekly clear" really means **creating a new document from the current state (`A.from(toJS(doc))`) and moving everyone to its new URL.** That's an epoch switch, not a cleanup.

- **How peers agree on the new doc today:**
  - The URL lives in each Pi's `store-identity/store-url.txt`. A compiled-in `FLEET_STORE_URL` (StoreIdentity.ts:18) writes it back when it's missing, and a test checks the two match.
  - Engines dial each other with `readStoreDocId()` (Network.ts:85, StaticPeers). Peering is **store-scoped** (StoreScope.ts, repo.ts sharePolicy): an Engine refuses or backs off from peers tagged with a different store id.
  - The Console gets the URL from `GET /api/store-url` during discovery (discovery.ts:62) and caches it in localStorage `storeUrl` (engine.ts:22,142-155).
  - A switch therefore needs:
    1. a way to tell every Pi "the new URL is X". That would be a new field in the *old* doc, e.g. `nextStore: {url, at}`.
    2. each Pi writing store-url.txt and restarting its repo;
    3. a new FLEET_STORE_URL constant (or the restore path breaks it, since a Pi missing its file goes back to the old doc);
    4. Consoles noticing and dropping their cached URL.
- **Old history coming back:** a Pi or Console still on the old URL can't push old changes into the new doc, because they're different documents. The old doc simply lives on with it.
  - Risk: a Pi that never learns the new URL keeps writing to the old one, so the fleet splits into two stores that don't talk.
  - Hardest case: a backup or reimage restores an old store-url.txt, or the restore path (FLEET_STORE_URL) puts a Pi on the old doc.
- **A Pi offline during the switch:** when it comes back it is on the old URL. Its peers refuse it, because of the store-scoped peering.
  - It can only find the new URL if someone still serves the old doc with the `nextStore` pointer. That means every Pi keeps the old doc loaded and relaying, which is permanent extra load.
  - Otherwise it stays cut off until ops fixes it by hand.
  - For holidays (over 7 days off) this happens to every Pi that was off on the switch night.
- **Console URL:** the cached `storeUrl` points at the old doc. The Console must re-read /api/store-url after every reconnect or on `nextStore`, and handle "doc changed": drop the handle and re-subscribe. A teacher tab left open sees a frozen old store until then.
- **Data loss in the window:** a change written to the old doc after the snapshot and before that Pi switches is lost unless replayed. That includes commands in `engineDB.*.commands`, op progress, disk docks, or a copy/backup running at night.
  - A safe switch needs a quiet period: no running ops, command queues empty, all Pis online and synced to the same heads. Then snapshot, then switch.
  - That's a fleet-wide barrier, which is exactly what is hard with no leader.
- **Who decides (leaderless):** there's no coordinator. Possible approaches:
  - a deterministic rule, "lowest engineId online at 03:00 Sunday creates the new doc". It fails when that Pi is off, and two Pis can disagree about who is online, which gives two new docs.
  - "first `nextStore` written wins" (Automerge conflict resolution on one key is deterministic, so later readers converge). But a Pi that already switched to the losing URL has to switch again.
  - Doable, but it is new distributed-systems code on the most critical document.
- **Comparison** (box load 10 s per 174k changes ≈ 0.057 ms/change, Pi ×5-6):

| | weekly reset, heartbeats + metrics kept | ephemeral (A+B) + op pruning (C) |
|---|---|---|
| growth | ~23k changes/day | ~3-6k changes/day |
| state right after reset/compaction | 322 KB, ~0.4 s box / ~2 s Pi | same if compacted once |
| after 6 days | ~138k changes → ~8 s box, **~40-48 s Pi** (just under today's 58 s failure) | ~24-36k → ~1.4-2 s box, **~7-12 s Pi** |
| needs compaction | every week, fully automatic | rarely (e.g. once a year or at a planned Path A migration, by hand) |
| complexity | URL switch protocol, leader choice, quiet barrier, offline-Pi recovery, Console re-subscribe, FLEET_STORE_URL handling | 2 broadcasts + 2 listeners, an hourly lastSeen, a prune job; no protocol |
| risk | fleet split or lost writes if anything goes wrong at night, unattended, in a school | low: worst case a stale metrics or online badge; the store stays one doc |
| live metrics | stored (also replayed to new peers) | in memory only; a new Console sees them within 15 s |

- **Recommendation:** don't automate a weekly reset.
  - Do A+B (ephemeral heartbeat and metrics) and C (prune finished ops older than 7 days into the CommandLog, write progress only on step change).
  - Then do **one manual compaction as a planned migration**, the way Path A switches stores today: all Pis online, Koen or ops present, new URL in store-url.txt and FLEET_STORE_URL, Consoles re-discover.
  - Repeat it only if the store grows again (with A+B+C, roughly yearly at most).
  - If Koen wants to keep heartbeats/metrics in the store anyway, a lower-risk alternative to a reset is to throttle them: heartbeat every 5 min, metrics only on more than 10 % change. That cuts ~90 % with no protocol, and still needs only a rare manual compaction.

---
# Koen decision 2026-10-13: approved as is
Build order (separate PRs to main, none merged; no automated weekly reset; the manual compaction is only a later plan for Steve):
1. Engine: relay unit test, ephemeral messages through the WS worker and store scope, forwarded along a 3-repo chain. If it fails, stop.
2. Console: liveMetrics + hb liveness (online 30 s, metrics stale 45 s), fallback to stored lastRun/metrics for old Engines.
3. Engine: broadcast hb (10 s) and metrics (15 s); stop the store writes; hourly lastSeen for PeerAccess (7-day expiry kept); prune Done/Failed ops older than 7 days into the CommandLog; progress written only on step change; harness consumers updated.
