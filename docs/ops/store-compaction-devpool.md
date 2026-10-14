# Runbook: dev-pool store compaction (3zoqd → new doc)

**Status:** Authoritative (executed 2026-10-13) · **Maintained by:** Atlas (executor); plan by Axle
Design and reasoning: [proposals/2026-10-13-store-growth.md](../../proposals/2026-10-13-store-growth.md). References to /workspace paths are ops-box evidence.

## Result record (2026-10-13)
- Dev-pool store **3zoqd compacted to 2VroE** (`automerge:2VroEUvDkmYsDAwE5oG9YeFNadWH`) on idea01/03/04, 2026-10-13 **14:54-15:14 CEST** (freeze to Engine start). 175,189 changes → 1; 26 MB → 322 KB. Gates G1-G4 GO, verify steps 13-18 PASS, no rollback. idea02 and wizardly-hugle unchanged.
- Evidence (ops box): `duration-evidence/path-a-stage2/compaction-devpool/RESULT.md`.
- Afterwards: cover-all **r86t PASSED 128/128** on 2VroE.

## Plan (as written by Axle before execution; executed as below)
Background: store-growth proposal (Q2), /workspace/r86q-diag/NOTES.md (173,991 changes, 2.90 MB saved, load(full) ~10 s on the box; compacted 322 KB, 0.39 s).

## 0. Facts confirmed read-only (14:40 CEST)
- Pool Pis idea01 10.99.0.11, idea03 .13, idea04 .14. Engine dir `/home/pi/idea/agents/agent-engine-dev` (D below), pm2 app `engine`.
  config.yaml: `mdns: true`, no static peers, `storeDataFolder: store-data`, `storeIdentityFolder: store-identity`.
- `D/store-identity/store-url.txt` = `automerge:3zoqdSVsEtj4ygNJPNcDyKWvdxo6` on all 3. Also there: `store-template.json`, `command-log-url.txt` (idea01 also has a stray nested `store-identity/store-identity/`; leave it).
- Doc dir: `D/store-data/3z/oqdSVsEtj4ygNJPNcDyKWvdxo6` (idea01 26 MB, idea03 8.0 MB, idea04 6.7 MB). Other docs in store-data (CommandLog, a stale `4G` = 4GQm copy, etc.) are NOT touched.
- Engine start (src/start.ts:89-113, Store.ts:45): reads store-url.txt → if `store-data/<id[0:2]>/<id[2:]>` exists it `repo.find()`s it; else it imports store-template.json under that id. So we must pre-place the new doc's storage dir on every Pi BEFORE start, otherwise a Pi seeds a template doc (different root history; merges with peers but ends up with template junk).
- Peering is store-scoped: Repo peerId = `idea-engine/<storeTag(docId)>/...`; peers with another tag are REFUSED, and the doc guard refuses foreign doc ids (repo.ts ~100-135, StoreScope.ts).
- idea02 production: store-url `automerge:4GQmEZehPDfryGDxkFo9XixbvmAC` (also the Engine code fallback FLEET_STORE_URL, StoreIdentity.ts:18). idea02 has an (empty-expected) `store-data/3z/oqdSVs…` dir (D10 check). wizardly-hugle (100.115.60.6): own store `automerge:6f8m5KxzARv9xwv4Lw18LgVUJzu`, Console :8081.
- Walker browser: playwrightDriver.ts:295 uses `chromium.launch()` + `browser.newContext()` per run → no persistent profile, so no localStorage/IndexedDB survives a run. Walker Node store sessions (storeDocSession.mjs) use no storage adapter (in-memory). Box/walker could not list /home/walker as pi (permission), so step 14 checks it as user walker.

## 1. Hardcoded '3zoqd' / store URL: places to change
Decision: the doc id IS the store id (store tag, store-url.txt, D10 path all derive from it). It cannot stay "3zoqd"; the new id is a fresh random base58 id (call it NEWID, prefix NEW5 = first 5 chars). "3zoqd" survives only as a name in prose.
Must change (before r86s):
1. harness `script/idea02-walker/launch.sh:19` STORE_DOC default `3zoqdSVsEtj4ygNJPNcDyKWvdxo6` → NEWID.
2. harness `script/idea02-walker/launch.sh:34` `export DURATION_EXPECTED_STORE_ID=3zoqd` → NEW5 (hard export in run.sh, not overridable → needs a pushed harness commit; launch.sh refuses dirty/unpushed trees).
3. box `/workspace/duration-evidence/stage2-plan/scripts/stage2-common.sh:11` POOL_STORE → `automerge:NEWID`.
4. box `stage2-d10-check.sh:6,34` path `store-data/3z/oqdSVs…` → new path (and keep checking old one: idea02 must hold neither).
5. idea repo `fleet-state.json` notes for idea01/03/04 ("shared store automerge:3zoqd…") → NEWID (+ "compacted from 3zoqd 2026-10-xx").
Should change (defaults/comments, not blocking): harness `test/duration/storePreflight.ts:28` DEFAULT_EXPECTED_STORE_ID='3zoqd'; comments in cli.ts:105/485, realFleetOps.ts:1333/1397, automergeTimeoutGuard.ts; stage2-store-fix.sh messages.
No change: Engine FLEET_STORE_URL (it is 4GQm, not 3zoqd); Console (no hardcode, uses /api/store-url + localStorage `storeUrl`); store-scoped-peering.test.ts (3zoqd is a fixture literal); old evidence scripts (pi-deploy-*.sh, restart-one.sh) are historical.
Caveat to record: a pool Pi that loses store-url.txt falls back to 4GQm (production id) — pre-existing risk, checked in step 5.

## 2. Why old history can't come back
- Automerge sync is per document id. NEWID shares no id and no change hashes with 3zoqd; nothing can "merge" old history into it — a peer would have to request NEWID and hold changes for it, which no old holder has.
- Any Engine/walker/Console still on 3zoqd has store tag `3zoqd-…`; new Engines have tag `NEW5-…` → mutual REFUSE at WS handshake (StoreScope), and the doc guard refuses a foreign doc id. So an old holder can't even join.
- Only real resurrection path: a human/script writes the old URL back into store-url.txt, or leaves the old dir and restarts on it. Mitigated by quarantining the old dir (Engine on 3zoqd would then seed a template doc, harmless and visible) and by verification step 16.
- Data written into 3zoqd after the snapshot is lost → that's why Engines are stopped first and queues must be 0 (go/no-go G2).

## 3. Go / no-go gates (all must be GO)
- G1 Steve clearance; no walk running on idea02 (`run.pid` absent/dead); Atlas reset done (3 Running, empties empty).
- G2 Store x3: queues 0/0/0, no operation in Running/Pending state, 3 Running instances (kolibri-grade5a-001 idea01, nextcloud-grade5a-001 + kiwix idea03).
- G3 All 3 pool Pis online (ssh + :8080 200 + /api/store-url = 3zoqd); mDNS true, no staticPeers in config.yaml; no `store-url.restored` file.
- G4 Free space ≥1 GB on /home of each Pi and on the box.
- G5 Baselines of idea02 and wizardly-hugle recorded (step 2).
- G6 Box tooling: node + automerge 3.1.1-alpha.0 / automerge-repo 2.3.1 / storage-nodefs 2.x installed in /workspace/compaction-devpool (step 3).
- Abort rule: any NO-GO before step 8 → just stop, nothing changed. Any failure after step 8 → rollback (section 6).

## 4. Steps (Q = /home/pi/quarantine/20261013-compaction-3zoqd on each Pi; E = /workspace/duration-evidence/path-a-stage2/compaction-devpool on the box; DOC=store-data/3z/oqdSVsEtj4ygNJPNcDyKWvdxo6)
Prep (no change to Pis) — ~20 min
1. `mkdir -p E`. Run G1–G4 checks, save output to E/gates.txt. Store-check: `STORE_DOC=3zoqdSVsEtj4ygNJPNcDyKWvdxo6 npx tsx script/idea02-walker/store-check.ts` on idea02 (as walker) → E/store-check-before.txt.
2. Baselines (read-only): for idea02 (`ssh idea02`) and wh (`ssh pi@100.115.60.6`): `cat D/store-identity/store-url.txt; curl -s localhost:<8080|8081>/api/store-url; pm2 jlist | python3 -c '…name,status,pm_uptime,restart_time'; ls -la D/store-data/3z/` → E/baseline-{idea02,wh}.txt.
3. Box tooling: `mkdir -p /workspace/compaction-devpool && cd $_ && npm init -y && npm i @automerge/automerge@3.1.1-alpha.0 @automerge/automerge-repo@2.3.1 @automerge/automerge-repo-storage-nodefs@^2.2.0`; write compact.mjs (section 5). Dry-run it on /workspace/r86q-diag/store-idea01 + store-idea04 (old copies) → must print a NEWID and load the result < 1 s on the box.
4. Pre-build the harness commit for section 1 items 1–2 on a branch with a placeholder; do NOT push until NEWID exists (step 10).

Freeze + snapshot — ~10 min (pool down from here)
5. On each Pi: `cat D/config.yaml | grep -E 'mdns|static'` (mdns true, no static); `ls D/store-identity/store-url.restored` must not exist.
6. Stop Engines in order idea04 → idea03 → idea01, 20 s apart (idea01 last: largest, longest-lived copy; the other two finish syncing to it): `ssh $P 'cd D && pm2 stop engine && sleep 3 && pm2 jlist | …status'` → must be `stopped`. Don't `pm2 delete`, don't touch containers (apps keep running; instance state lives in the doc).
7. Snapshot: on each Pi `tar -C D -czf /tmp/3zoqd-$P.tgz $DOC store-identity` then `scp $P:/tmp/3zoqd-$P.tgz E/`. Also `sha256sum` into E/snap.sha.

Build new doc on the box — ~5 min
8. `cd /workspace/compaction-devpool && node compact.mjs E/snap/idea01 E/snap/idea03 E/snap/idea04 E/new` (untar each first). It:
   a) loads each copy (snapshot + incremental chunks, as analyze.mjs), prints changes + heads per Pi;
   b) GO only if all 3 heads equal (they should, after a synced stop). If not equal: merges the three (A.merge, CRDT-safe, union of all changes) and logs it — still GO, since the merged doc is the strict superset;
   c) refuses (exit 3) if the doc contains Counter / ImmutableString / RawString values (A.from(toJS) would change their type) — none expected; if hit, NO-GO and come back to Steve;
   d) builds `A.from(A.toJS(merged))` → one change, no history; asserts `JSON.stringify(toJS(new)) === JSON.stringify(toJS(merged))`;
   e) NEWID: `generateAutomergeUrl()` from automerge-repo (random UUID → base58 doc id), writes `E/new/store-url.txt` = `automerge:NEWID`;
   f) writes storage via a Repo with `NodeFSStorageAdapter(E/new/store-data)`: `repo.import(A.save(new), {docId: NEWID})`, `await repo.flush()`; then re-opens a fresh Repo on that dir, `find(NEWID)`, times the load (<1 s on box) and compares JSON again;
   g) prints NEWID, heads, size, counts (engines, disks, instances, Running instances, operations, queue lengths) → E/compact.json.
9. `tar -C E/new/store-data -czf E/new-doc.tgz <NEWID[0:2]>/<NEWID[2:]>`; sha256.
10. Push the harness commit (items 1–2 with NEWID) and update stage2-common.sh / stage2-d10-check.sh (items 3–4). fleet-state.json update (item 5) via normal idea-repo PR afterwards.

Swap on the Pis — ~10 min
11. On each Pi (any order, Engines are stopped):
```
ssh $P 'set -e; D=/home/pi/idea/agents/agent-engine-dev; Q=/home/pi/quarantine/20261013-compaction-3zoqd
mkdir -p $Q/store-data/3z $Q/store-identity
mv $D/store-data/3z/oqdSVsEtj4ygNJPNcDyKWvdxo6 $Q/store-data/3z/
cp -a $D/store-identity/store-url.txt $Q/store-identity/store-url.txt
ls -la $Q $Q/store-data/3z > $Q/MANIFEST.txt; du -sh $Q >> $Q/MANIFEST.txt'
scp E/new-doc.tgz $P:/tmp/ && ssh $P 'cd D/store-data && tar -xzf /tmp/new-doc.tgz && sha256sum -c … ; printf "automerge:NEWID" > D/store-identity/.store-url.tmp && mv D/store-identity/.store-url.tmp D/store-identity/store-url.txt && chown -R pi:pi D/store-data D/store-identity'
```
   Check: `cat store-url.txt` = new URL; new dir present; `3z/oqdSVs…` absent from store-data; quarantine has it (move = no copy, no delete; the tarball in E is the second copy). Identical bytes on all 3 Pis → identical heads, no template seeding, nothing to sync at start.
12. Start Engines idea01 → idea03 → idea04, 30 s apart: `pm2 start engine`. Each: wait for :8080 200 (≤120 s), log line `Using document ID: NEWID` and `Store document found in storage`, NOT `Creating from template`.

## 5. Verification — ~15 min
13. `/api/store-url` on 10.99.0.11/.13/.14 → `automerge:NEWID` x3. `pm2 logs engine --lines 200 --nostream | grep -E 'store-scope|REFUSED'` shows tag NEW5 and peers connecting among the 3 (mDNS).
14. Load time: from the box `IDEA_HOST=<ip> npx tsx /workspace/storefix-node/.sync-timing-r86b.mts` adapted to NEWID, 3 runs per Pi → full sync < ~3 s (expect < 1 s). On one Pi: Engine log time from "Initialising store" to "loaded successfully" < 3 s.
15. Store contents x3: queues 0/0/0, the 3 Running instances present and Running, disk docks as before (diff E/compact.json counts vs store-check-before). Kolibri/NC/Kiwix HTTP 200. D10 v2 (updated) PASS, fleet-health --origin ok. Each Engine's engineDB entry has a fresh lastRun (writes work) and Console :8080 on each Pi lists 3 Engines.
16. No old doc anywhere live: on each Pi `test ! -e D/store-data/3z/oqdSVsEtj4ygNJPNcDyKWvdxo6`; idea02's `store-data/3z/` unchanged vs baseline (no files).
17. Walker (idea02, as user walker): confirm no persistent browser profile in harness (`rg -n launchPersistentContext` = none) and remove any Console cache dirs if they exist (`~/.cache/ms-playwright/*-profile*`, `~/.config/chromium` — move to quarantine, don't delete); then store-check with new STORE_DOC → PASS (3 Running, queues 0, idea02 absent). Walker launches with new harness SHA (DURATION_EXPECTED_STORE_ID=NEW5). Any human Console tab on the pool: reload with DevTools → Application → Clear site data (localStorage `storeUrl` + IndexedDB).
18. Untouched check: re-run step 2 for idea02 and wh; store-url identical (4GQm / 6f8m), pm_uptime and restart_time identical to baseline → PASS. Any difference = stop and report (do not "fix" production).
19. Write E/RESULT.md (NEWID, before/after sizes and load times, all checks). Then Atlas READY/GO r86s.

## 6. Rollback (≤10 min; any time after step 8)
R1. Stop Engines idea04 → idea03 → idea01 (`pm2 stop engine`).
R2. On each Pi: move the new doc dir to `$Q/rolled-back-NEWID/` (no delete); `mv $Q/store-data/3z/oqdSVsEtj4ygNJPNcDyKWvdxo6 D/store-data/3z/`; `cp $Q/store-identity/store-url.txt D/store-identity/store-url.txt` (= 3zoqd). If the quarantine copy is damaged, restore from E/3zoqd-$P.tgz.
R3. Start idea01 → idea03 → idea04; /api/store-url = 3zoqd x3; store-check PASS with old id; revert the harness commit / scripts (or keep launch on the previous harness SHA).
R4. Note: any change made while on NEWID (e.g. a short walk) is lost on rollback — acceptable for the dev pool.

## 7. Time estimate
Prep 20 min (no downtime) · freeze+snapshot 10 · build 5 · swap 10 · start+verify 25 → ~70 min total, ~50 min pool downtime. Rollback ≤10 min.

## 8. What this rehearses for production
Same steps with idea02 production store: needs FLEET_STORE_URL change in Engine (else a Pi missing store-url.txt rejoins the old doc), Console users clearing cached `storeUrl`, and a quiet window. Record actual timings here in E/RESULT.md.
