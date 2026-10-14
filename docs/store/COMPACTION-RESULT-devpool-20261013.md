# Dev-pool store compaction: result (2026-10-13)

**Status:** Done, no rollback · **Operator:** Atlas Ops · **Plan:** [COMPACTION-PLAN-devpool.md](COMPACTION-PLAN-devpool.md) · **Design:** [STORE-GROWTH-PROPOSAL.md](STORE-GROWTH-PROPOSAL.md)

Scope: dev pool idea01, idea03, idea04 only. idea02 and wizardly-hugle were baselined and checked read-only before and after: identical.

| | Old | New |
|---|---|---|
| Store | `3zoqd` (automerge:3zoqdSVsEtj4ygNJPNcDyKWvdxo6) | `2VroE` (automerge:2VroEUvDkmYsDAwE5oG9YeFNadWH) |
| Changes | 175,189 | 1 |
| Size per Pi | 26 / 8.7 / 7.4 MB | 322 KB |
| Load | 17-42 s (box) | 0.89 s reopen (box) |

- Content: JSON of old and new documents equal. Heads differed between Pis at the freeze, so the replicas were merged first (superset, idea01 heads).
- Timeline (CEST): freeze 14:54-14:55, swap 15:12, Engine start 15:12-15:14. ~20 min downtime.
- Gates G1-G4: GO.
- Verify: step 13 PASS; 14 PASS (remote load 2.6-3.8 s; local idea01/03 2.2 s, idea04 7.4 s - watch item); 15 PASS (queues 0, 3 instances Running, Kolibri/Nextcloud/Kiwix HTTP 200, D10 v2 PASS, fleet-health ok); 16 PASS; 17 PASS; 18 PASS (idea02 + wizardly-hugle identical).
- Old 3zoqd store: tarball per Pi kept on the box, plus a quarantine copy on each Pi.
- Harness default store switched to 2VroE (c096fc9 -> 58a144c on main). Fleet record: see the fleet-state PR for 2VroE.
- Follow-up runs on 2VroE: r86s (failed step 128, test timing, fixed), r86t PASS 128/128, r87b PASS 128/128.
