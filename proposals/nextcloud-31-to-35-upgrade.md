---
title: "Upgrading the Nextcloud App from 31 to 35"
subtitle: "A step-by-step path after the field update, with a backup before every step"
audience: "Proposal · Status: Draft · Design Review and Ops review folded · Ops review: done (approve with changes, folded in) · 15 November 2026"
cover_logo: "yes"
---

**Author:** Steve · IDEA Lead Bot

**Date:** 2026-11-15

**Status:** Draft. Not posted and not opened as a PR. Written for [app-nextcloud#32](https://github.com/koenswings/app-nextcloud/issues/32). Research is Marco's official-sources note of 15 November 2026. Related items, both held until after the field update: [app-nextcloud#31](https://github.com/koenswings/app-nextcloud/issues/31) (MariaDB 11.8) and [app-nextcloud#34](https://github.com/koenswings/app-nextcloud/issues/34) (Collabora CODE 26.04). This upgrade is **not** part of [idea#374](https://github.com/koenswings/idea/issues/374).

This revision folds in the 15 November 2026 Design Review inputs from App (Kid), Engine (Axle), Console (Pixel) and Docs (Marco), and Atlas's Ops review of 15 November 2026, 21:29 (Europe/Brussels), verdict **approve with changes**.

Code read: `koenswings/app-nextcloud` `origin/main` at `696a299` (15 November 2026, Brussels time); Engine `updateApp` on `koenswings/agent-engine-dev` `origin/main` at `da08956`.

# Review status

| Domain | Status |
|---|---|
| App (Kid) | Review received. Hop-32 prep, hop-33 prep, hop-34 prep (including the Q4 admin-changes note and the explicit 34.0.6 pin), contract gaps 1–14, and a pool test plan for UNCONFIRMED items 2, 3, 5 and 6, 15 November 2026. |
| Engine (Axle) | Review received, plus an addendum answering Kid's contract gaps 1–14 and folding Steve's backup and engine#442 decisions, 15 November 2026 (evening, Europe/Brussels). No objections to option C. |
| Console (Pixel) | Review received. Full Console section, then a review of Marco's wording, then an updated Console section (15 November 2026, about 20:43, Europe/Brussels): backup before every step with the archive id recorded per step; `restartFailed` in both the step result and the command result; no "Keep going", so Resume is the only way forward after a stop. |
| Docs (Marco) | Review received. Operator-facing wording updated 15 November 2026, 20:41 (Europe/Brussels), with Pixel's fixes and the paused `migrationsPending` state applied. The only wording marker left is the duration TBD. |
| Ops (Atlas) | **Ops review: done (approve with changes, folded in).** Desk review received 15 November 2026, 21:29 (Europe/Brussels). Required changes R1–R6 are folded into the body; R7–R14 are folded where cheap and otherwise listed as follow-ups. Time and disk figures for a field plan remain unmeasured until the pool timing runs. |

Agreed during this Design Review (Steve, 15 November 2026):

- Console: one confirmation button, no typed name; "Stop after this step" uses the same role as Update; the path is allowed with no uplink.
- Wording: no operator-facing duration string until Atlas's pool timing runs measure real times (TBD); a backup is taken before every step, including the first small one; the operator line is "Nextcloud is unavailable while the update runs"; Resume is offered only after a stop (a stop request is final); Get help includes a small `Code:` line; a short guide page is added only after the path is proven.
- Path runner: a fresh pre-update backup is forced before every step, with no one-hour skip. Plain `updateApp` keeps today's rule (majors only, with the one-hour skip).
- Hop 33 decisions: no MariaDB 11.8 in the 3.0 hop; 11.8 is a separate hop after 33 is healthy, using `MARIADB_AUTO_UPGRADE=1`. `serverid` stays unset in 3.0; a stable `NC_serverid` is a later item. `updatesFrom` lists only the previous App major.

Agreed after the Ops review (Steve, 15 November 2026, evening, Europe/Brussels):

- **(a) R9 accepted.** The path runner **releases the instance lock** while a path is paused or in `migrationsPending`, so scheduled backups can run. On Resume it re-acquires the lock and takes the forced fresh backup before the next step, as already decided.
- **(b)** The pool proof is allowed to **force a reboot** of a claimed pool test Pi (idea03 or idea04 only; never golden idea01 or client idea02).
- **(c)** The real **power-cut** test needs someone at the pool, so it is a Koen item on [idea#375](https://github.com/koenswings/idea/issues/375), presented only when he is ready.
- **(d)** Koen's approval of this proposal waits for Atlas's first pool timing run (**Run 1:** 31.0.1 → 31.0.14 → 32.0.15, without prepare). Any kit plan stays blocked until the full path is measured.

<div class="note">

<strong>Ops review: done (approve with changes, folded in).</strong> Atlas reviewed this draft on 15 November 2026 at 21:29 (Europe/Brussels). Koen's approval of the proposal waits for Atlas's Run 1 (31.0.1 → 31.0.14 → 32.0.15, without prepare). Any kit plan stays blocked until the full path is measured. Time, disk and heat figures remain TBD until those runs exist.

</div>

# 1. What and why

`app-nextcloud` `main` today is **1.7-31.0.1**. Field kits are **not** on that tagged release. A read-only check of sunny-robin under claim (15 November 2026, 17:34 Europe/Brussels) found `koenswings/nextcloud:1.0-31.0.1`, MariaDB `1.0-11.7.2`, CODE `1.0-24.04.13.2`, an **unversioned SHA `x-app.version`**, and Engine **`adfd9d3` with root helper v2**. That Engine has no `updateApp`, and `updateApp` needs helper v14 or newer. No kit has a Backup Disk docked, so a major hop would refuse `NEEDS_BACKUP`.

Nextcloud 31 and 32 are already past end of life. They no longer receive bug or security fixes. Official guidance is to leave an end-of-life major as soon as possible.

- 31 (Hub 10) was released on 25 February 2025 and reached end of life in February 2026. Its last maintenance release is 31.0.14 (12 February 2026).
- 32 (Hub 25 Autumn) was released on 27 September 2025 and reached end of life in September 2026. Its last maintenance release is 32.0.15 (10 September 2026).
- 33, 34 and 35 are released and still supported (wiki page dated 13 November 2026). The current point releases, all dated 12 November 2026, are 33.0.11, 34.0.6 and 35.0.3.

Sources: [Maintenance and Release Schedule](https://github.com/nextcloud/server/wiki/Maintenance-and-Release-Schedule), [admin release schedule](https://docs.nextcloud.com/server/stable/admin_manual/release_schedule.html), [changelog](https://nextcloud.com/changelog/).

The exact calendar day of end of life for 31 and 32 is **UNCONFIRMED**. The wiki table gives only a year-month. The admin manual says maintenance ends on the one-year anniversary of the initial release, which would be 25 February 2026 and 27 September 2026 if applied literally, but those day dates are not printed in the wiki end-of-life table.

The risk is real, but it is not urgent. Schools run offline, so an unpatched Nextcloud is not exposed to the public internet in normal use. A teacher network with an uplink is the exception, not the rule. The jump is four major versions plus the small 31.0.14 step first: **five** `updateApp` runs, five backups, five snapshots and five image changes. A later MariaDB 11.8 hop adds a **sixth** step and a sixth backup; count it in any field timing. Do not describe this as "4 hops". A failed upgrade on a school kit would be worse than staying on 31 for a while longer. So we design the path, prove it on the pool, and only then talk about kits.

This work is not part of the [idea#374](https://github.com/koenswings/idea/issues/374) field update. The path can start on a kit only after **all** of the following:

- idea#374 has landed with Koen's OK: a new Engine and helpers, and Nextcloud on a tagged 1.7.
- A Backup Disk is linked and docked on that kit (an open [idea#375](https://github.com/koenswings/idea/issues/375) question, presented only when Koen is ready).
- The path-runner Engine is deployed by the kit path.

Koen's approval of this proposal waits for Atlas's Run 1. Any kit plan stays blocked until the full path is measured. The proposal must not assume that `updatesFrom: [1]` matches a kit that is still on a SHA `x-app.version`; what the path offers in that case is still open (section 13).

# 2. Affected domains

| Domain | What this asks of them |
|---|---|
| **App (Kid)** | One App release per Nextcloud major, with `updatesFrom` listing only the previous App major; retag the official `N-apache` image; ship the matching `richdocuments` tarball and an `idea_usage` **1.0.0** build whose `info.xml` range is widened for that major (any version bump is decided at release); idempotent hook scripts in the new bundle (`prepare`, and after Health the optional `verify`, `work` and read-only `settle`); measure first-start time, disk use and the health timeout on a pool Pi (suggested major-hop `healthTimeout` and `start_period` is 600 s, as an estimate to recheck after a timed 31→32 hop); release tests for each new `x-app.version`. Kid's pool test plan covers UNCONFIRMED items 2, 3, 5 and 6. MariaDB 11.8 and a stable `NC_serverid` are later items, not part of 3.0. |
| **Engine (Axle)** | `updateApp` already takes a Borg backup first on a major (or refuses `NEEDS_BACKUP` when no Backup Disk is linked). For this path: the runner forces a fresh backup before every step, with no one-hour skip; optional hook steps **prepare**, **verify**, **work** and **settle** as declared in the new bundle; a stored path record (`updatePathDB`) so the Console can show one confirmation and resume after a stop. [engine#442](https://github.com/koenswings/agent-engine-dev/issues/442) lands first and puts `restartFailed` in the path step result and the command result, as well as on the op and the Error. Each path step also records `backupArchive` (Backup Disk id and archive name). Host-side root hooks are ruled out. The Engine adds or strips no service env, and never copies env into logs, the store or progress. The instance lock is released while a path is paused or in `migrationsPending` (R9, agreed). The offer lists only steps whose image tars and bundles are present and pass their checksums. A 05:00 cron-reboot policy (hold the reboot, or refuse to start a step that would run past a cutoff) is still open (Axle, Steve). Engine deploys must refuse while a path or journal is active. |
| **Console (Pixel)** | One confirmation for the whole 31→35 path, then a live view of which step is running and a plain end state if it stops. Today's single-step Update flow stays as it is. Stop uses the same role as Update. The path is allowed with no uplink. Operator wording follows Marco's draft, with the decisions listed under Review status. The Console keeps no state of its own: it reads the Engine's path record. After any stop, Resume is the only way forward (no "Keep going"). |
| **Ops (Atlas)** | Pool proofs only: claim idea03 or idea04, never golden idea01, never idea02. Throwaway instance, no production, no kits. Run 1 (31.0.1 → 31.0.14 → 32.0.15, without prepare) is the first timing run, and Koen's approval of this proposal waits for it. A forced reboot of a claimed pool Pi is allowed for the hard-reset proof; a real power cut is an idea#375 item for Koen, presented only when he is ready. Measure time, free disk, heat and `/var/lib/docker` on the system disk. Keep a linked Backup Disk docked for every hop. Images are removed by digest, never by prune. |
| **Docs (Marco)** | Teacher and operator guides, and any Office or files chapter that names the Nextcloud version or the Office screens, are updated only after the path is proven. A short "if the update stops" page, if it is added, comes after that proof, not before. Nothing in the field-update runbook changes for this. |

# 3. What we run today

From `app-nextcloud` `main` at `696a299`:

| Piece | Pin today | Notes |
|---|---|---|
| App release | `x-app.version` **1.7-31.0.1** | Tags follow `<IDEA major>.<minor>-<Nextcloud version>`. `updatesFrom` is empty, because 1.x is the first App major. The compose already says a release that moves to the next Nextcloud major must list only the App major directly before it. |
| Nextcloud | `koenswings/nextcloud:1.0-31.0.1`, upstream `31-apache` | Official image, retagged, digest-pinned, linux/arm64. |
| MariaDB (`nextcloud-db`) | `1.0-11.7.2-MariaDB-ubu2404`, upstream `11.7` | `MARIADB_AUTO_UPGRADE=1`. **11.7.2 is not on any official Nextcloud 31–35 MariaDB list.** |
| Collabora CODE | `1.0-24.04.13.2` | On the documented floor (CODE ≥ 21.11) this pin is **COMPATIBLE** with `richdocuments` 9.2.3, 10.3.3, 11.1.3 and 12.0.2. That verdict is desk research only and is **unproven on a Pi**. The pin also lags the 24.04 branch's security releases (24.04.20.4, 23 October 2026). |
| `richdocuments` | bundled tarball **8.8.3** | Nextcloud **31 only** (`min-version` and `max-version` 31). |
| `idea_usage` | bundled tarball **1.0.0** | Nextcloud **31 only** in `idea_usage/appinfo/info.xml` today. The app stays at **1.0.0** with a widened range for later majors; any version bump is decided at release. |
| `files_external` | stock app, enabled by hooks | Still present in Nextcloud 35. No official admin-manual break was found; undocumented behaviour changes remain **UNCONFIRMED**. |
| Update health | `/status.php` must contain `"maintenance":false,"needsDbUpgrade":false` | `healthTimeout` 300 seconds today. Measured on idea04 (28 October 2026): 30.0.6 → 31.0.1 first start was 66–69 seconds on a small data set. For a major hop, 600 seconds (`healthTimeout` and Docker `start_period`) is the suggested estimate, to be rechecked after a timed 31→32 hop on a pool Pi. |
| Backup | `x-app.backup` method `hook`, fallback `stop` | Live backup: maintenance on, MariaDB dump, Borg, maintenance off. |

# 4. The required path

Major versions cannot be skipped. That rule is in the [admin upgrade manual](https://docs.nextcloud.com/server/stable/admin_manual/maintenance/upgrade.html) and in the [official Docker README](https://github.com/nextcloud/docker/blob/master/README.md). The official image starts the upgrade when the image major does not match the data volume, and it refuses a skip. Jumping the compose tag from `31-apache` to `35-apache` in one step is the skip the image is written to refuse. Downgrades are not supported and risk corrupting data.

The official image runs `occ upgrade` in its entrypoint when the container starts, before this App's `before-starting` hooks. New `custom_apps` tarballs therefore have to be in place after Swap and **before Start**. That is why the Engine needs the Prepare phase in section 7.2. After Health, optional **verify**, **work** and read-only **settle** steps (section 7.2) close the remaining hop checks without putting `cron.php` inside a read-only probe.

The supported path from IDEA's 31.0.1, using the last or current point release of each major as of 15 November 2026, is:

1. 31.0.1 → **31.0.14** (latest and last 31; already end of life, but still the documented first step)
2. 31.0.14 → **32.0.15** (latest and last 32)
3. 32.0.15 → **33.0.11** (current 33)
4. 33.0.11 → **34.0.6** (current 34)
5. 34.0.6 → **35.0.3** (current 35)

That is **five** App releases and **five** `updateApp` runs, five backups, five snapshots and five image changes (the small 31.0.14 step first, then four major hops). Any estimate that says "4 hops" undercounts the backups and downtime. A later MariaDB 11.8 hop, after 33 is healthy (section 8.2), adds a **sixth** step and a sixth backup to the field path; count it in any field timing. Do not move to MariaDB 12.3.

If 33, 34 or 35 have a newer point release when the work is done, we land on the latest point of the major we are leaving, then the latest point of the next major. After each *major* hop, background migrations must be allowed to finish. Official advice is to run `cron.php` two or three times and wait before starting the next major. That wait is the optional work and settle contract in section 7.2.

The matching official image tags are the fully pinned point releases (`31.0.14-apache`, `32.0.15-apache`, `33.0.11-apache`, `34.0.6-apache`, `35.0.3-apache`), not only the floating `N-apache` tags. On 15 November 2026, `31-apache` was still on Docker Hub and pointed at `31.0.14-apache` (same digest; arm64 is published). The `31/` Dockerfiles have been removed from the git repo after end of life ([commit dc4b5bc](https://github.com/nextcloud/docker/commit/dc4b5bc546777e5ce22a25c66eb3df415a9d0a42)), but the Hub tags remain pullable.

**4.0 pins the explicit `34.0.6-apache` index.** Kid inspected Docker Hub on 15 November 2026 at 20:39 (Europe/Brussels): the intended compose pin, until a `koenswings/nextcloud:4.0-34.0.6` retag is published, is `nextcloud:34.0.6-apache@sha256:3031e7f87baaceb863a755921ebf463bc26ea71855c07ad7858e2ae25a5a0ad7` (arm64 manifest `sha256:f01db3987605b0d69905b13e88f55fc84e68a5c202aaa3985af861aad19d5354`, image version 34.0.6-apache, base `php:8.5-apache-trixie`, created 13 November 2026, 23:14 Europe/Brussels). The floating tags `34-apache` and `34.0-apache` currently point at a *different* index digest (`sha256:25d07d3091844c87c5f812037f5281b5d61fbb47f2c3f125274baabfe6f3ed1b`), because that floating index still lists a `linux/riscv64` variant at 34.0.5-apache. The platform manifests for amd64 and arm64 inside the floating index match 34.0.6-apache, but the hop still pins the explicit `34.0.6-apache` tag and its own index digest, matching 1.8, 2.0 and 3.0.

A suggested numbering, following the existing tag scheme, is `1.8-31.0.14` (same App major, a minor `updateApp`), then `2.0-32.0.15`, `3.0-33.0.11`, `4.0-34.0.6` and `5.0-35.0.3`, each with `updatesFrom` set to **only** the App major before it (`[1]`, `[2]`, `[3]`, `[4]`). 3.0 therefore lists `[2]`, and 4.0 lists `[3]`, never an earlier major: Nextcloud cannot skip majors, and listing one would let plain `updateApp` offer a skip the image would refuse. The exact minor numbers can move if a fix release is needed in between. Lead sets the tags on the merged release commit, as today.

# 5. Approach options

## 5.1 Option A — one App major per Nextcloud major

Ship five App releases. A kit steps through them with five ordinary `updateApp` runs, one confirmation each. The first hop (31.0.1 → 31.0.14) is a minor update. The other four are major updates, so each one needs `--allow-major`, a matching `updatesFrom`, and a fresh Borg backup.

This is what `updateApp` and the Nextcloud compose already describe, once the Prepare phase is available (it also works in plain `updateApp`, so the pool can prove each hop before the path-runner exists). Each hop has its own health gate. A failure rolls that hop back and leaves the school on the last good release, not halfway through a hidden chain.

The cost is operational: a teacher or a visiting operator would confirm five times, and a Backup Disk must be linked and docked for every step. Five separate evenings is a lot to ask of a school with no IT staff.

## 5.2 Option B — one App release that chains the upgrades internally

Ship a single App release whose update hook walks the data through 31.0.14, 32, 33, 34 and 35 by itself, swapping intermediate images and running `occ` inside the instance.

This is rejected. The official `N-apache` image will not start a 35 image on 31 data. A hook that carries five images and drives the chain would reimplement `updateApp` without its backup gate, health check or rollback journal. If a hop in the middle fails, the only clean restore is the Borg backup taken at the start; intermediate data may already have been migrated, and Nextcloud cannot go backwards. Background migrations need time between majors, which a single long maintenance window on a Pi is a poor place to hide. The bundle would also be very large, because it would have to carry every intermediate Nextcloud image (and likely every matching Office tarball) at once.

## 5.3 Option C — staged hybrid

Package the work exactly as in A: one App release per Nextcloud major, each proven on its own with ordinary `updateApp`. For a school, add an Engine and Console *path* that runs those releases in order after **one** confirmation.

The path is not a new kind of upgrade. It is a planned sequence of the same `updateApp` steps, with a fresh backup forced at the start of every step (no one-hour skip): Fetch, Check, Snapshot, Swap, **prepare**, Start, Health, **verify**, **work**, **settle**. The steps in bold run only when the new bundle declares them. If hop N fails in a rolling-back step (including prepare and verify), roll back hop N and stop. A work or settle timeout or error does not roll back: the path pauses with `migrationsPending` and can be resumed. The school stays on the last good major. The operator can resume later, only after the path has stopped.

This needs new Engine and Console work, so it does not delay proving each hop on the pool. It is the field experience we should have before any kit is updated.

# 6. Recommendation

**Recommend option C.** We ship one App release per Nextcloud major and prove each hop on the pool with ordinary `updateApp`. Before any kit is updated, the Engine and Console add a path that runs those releases in order after one confirmation, with a fresh Borg backup forced before every step and a health check between steps. The prepare, verify, work and settle contracts below are part of that path; prepare, verify, work and settle also work in plain `updateApp`, so the option A pool proofs can use them before the path-runner exists.

Option B is out: the official image refuses a skip, and a chain inside one hook hides failures that we already know how to handle. Option A alone is the right way to build and test, but five separate confirmations is the wrong experience for an unattended school. The path in C is what answers "how a field kit gets several majors in one update." Ops has approved option C with the changes folded in. Koen's approval of this proposal waits for Atlas's Run 1 (31.0.1 → 31.0.14 → 32.0.15, without prepare). Any kit plan stays blocked until the full path is measured.

# 7. Backup, failure, rollback and the Engine path contract

## 7.1 What `updateApp` already does

`updateApp` already does the important parts (Engine main `da08956`, idea#448 and idea#351):

- A **major** update without a Borg backup less than one hour old is refused with `NEEDS_BACKUP`, unless a Backup Disk linked to the instance is docked on this Engine. In that case `updateApp` takes the backup itself, as a `backupApp` with reason `pre-update`, using the *current* compose's hook (maintenance on, dump, Borg, maintenance off). A failed hook refuses `HOOK_FAILED` and does not fall back to a stop-mode backup. Nothing is stopped or changed.
- **Plain `updateApp` keeps that rule unchanged:** majors only, with the one-hour skip. The **path runner** is different: it forces a fresh pre-update backup before **every** step, including the first minor hop (31.0.1 → 31.0.14), and it ignores the less-than-an-hour-old skip. A clock that is not trusted can therefore never cause a skip or a refusal on the path. No Backup Disk linked and docked is still `refused`, `NEEDS_BACKUP` or `backupDiskMissing`, before anything changes.
- After the backup, `updateApp` writes a journal, takes a local snapshot of `data/` and the named volumes, swaps the bundle, starts the new version, and waits on the health check (`/status.php` with maintenance off and no database upgrade pending), within `healthTimeout` (300 seconds today; 600 seconds is the suggested estimate for a major hop).
- If the swap or the health check fails, the Engine restores the old bundle and the data copy from the snapshot, starts the old version, and reports `ROLLED BACK`. Nextcloud does not support downgrades, so rollback must restore data, not just the old image. If rollback itself fails, the instance is left Stopped with the snapshot intact.
- If the disk is pulled or the Engine restarts mid-update, the journal on the disk is the source of truth. The next Engine to dock that disk rolls back before anything starts.

Today there is **no** hook between Swap and Start. The new container's entrypoint then runs `occ upgrade`. That is the gap prepare closes.

## 7.2 Hook steps — prepare, verify, work and settle

The final step order is:

**Fetch → Check → Snapshot → Swap → prepare → Start → Health → verify → work → settle.**

The steps in bold run only when the **NEW** bundle declares them. An App without a given field skips that step, so every other App and update is unchanged.

**Fields.** `prepare`, `verify` and `work` each take `{ service, user?, command, timeout }`. `settle` takes `{ service, user?, command, interval, timeout }`. `timeout` is required for prepare, verify and work; Check refuses with `UPDATE_CONTRACT_INVALID` if it is missing, before anything changes. Kid adds the same `x-app.update` checks to check-compose. The Engine runs those checks at Check (refused, nothing changed). Unknown `x-app` keys stay allowed.

**`service`.** The Engine uses `service` verbatim from the new bundle. If that is not a compose service, Check refuses with `UPDATE_CONTRACT_INVALID` before anything stops. The example for this App is `nextcloud-app`, not `nextcloud`.

**`user`.** An optional `user` on all four hook steps, the same shape as the `x-app.backup` hook steps. The value is passed verbatim as `run --user` / `exec -u`, numeric (`"0"`, `"33"`) or a name. When it is omitted, the default is the service's own user (root for the official image). The Engine never defaults any step to 33.

**`command`.** One absolute path that the swapped compose must already mount (this App bind-mounts `./hooks:/idea/hooks:ro`). It is run in exec form, with no `sh -c`, and is never copied to the host. Exit 126 or 127 is logged as "command not found or not executable in container."

**Rollback line.** prepare and verify failures roll back. work and settle failures never roll back; the path stops with `stopReason` `migrationsPending`.

**Environment.** The Engine adds or overrides nothing, and it strips nothing. `docker compose run` gets the swapped service env (with `.env` interpolation) from compose. `docker compose exec` inherits the running container's env. A later `NC_serverid` set on the service therefore reaches Apache, occ, work and settle alike. The Engine never copies service env into the log, the store, progress or arguments. Scripts must not print secrets.

**Errors.** The Engine captures stdout and stderr. The last `ERROR:` or `not yet:` line (capped at 200 characters) goes to the step's `errorText` / `phaseNote` and to `idea/updateProgress`; the last 20 lines go to the Engine log. Codes: `PREPARE_FAILED` and `VERIFY_FAILED` (rolled back); `SETTLE_FAILED` and `migrationsPending` (stopped on the new major). Each hook step has its own timer (no shared 600 s). `docker compose exec -T` is used for the exec steps.

### Prepare (between Swap and Start)

Kid is right: the official image runs `occ upgrade` in its entrypoint, and `updateApp` runs nothing between Swap and Start, so new `custom_apps` tarballs cannot land before the upgrade. `before-starting` hooks run only after `occ upgrade`, which is too late. The current extract hook also refuses to overwrite an existing `custom_apps/<app>` folder.

- **Example:** `x-app.update.prepare: { service: nextcloud-app, user: "0", command: /idea/hooks/prep-custom-apps-for-upgrade.sh, timeout: 600 }`.
- **How it runs:** as a one-off container from the swapped compose, with no ports. Host-side root hooks are ruled out. The Engine uses a generated override that sets that service's `entrypoint: [command]` and an empty `command`, so Prepare gets **no leftover argv** (it is not invoked as `prep-custom-apps-for-upgrade.sh apache2-foreground`). A pool test asserts the argv is exactly `[command]`. Apps must not rely on ignoring `apache2-foreground`.
- **What it sees:** the swapped compose's service volumes and env, plus the same Engine-injected mounts as Start (unused, harmless). The instance's existing `./data/...` is used, never a fresh one. `--no-deps` is a hard rule. Images are never pulled (Fetch/Swap must already have them); a missing image is `PREPARE_FAILED`.
- **Order:** it runs after Snapshot, so the snapshot holds the old `custom_apps`, and after Swap, so the new tarballs are on disk. The App script moves an existing app folder into a backup subfolder (for example `data/nextcloud/custom_apps/.idea-upgrade-backup/…`) and extracts the new tarball. It must not delete the old app tree. `.idea-upgrade-backup/` is instance data, inside the snapshot; the Engine never scans or cleans it.
- **Timeout:** on expiry the Engine sends SIGTERM, then SIGKILL after 10 s, removes the one-off container, then `PREPARE_FAILED` and rollback. The log says "timed out after Ns", kept apart from "exited N", plus the last 20 lines of output.
- **Failure and interruption:** a non-zero exit, a timeout, or an Engine restart mid-prepare always restores the snapshot. Resume starts the hop again from Swap on the old tree. The Engine cannot tell "exited 0 but not journalled" from "interrupted", so a retry without rollback is rejected. Idempotence stays a defensive App rule only.
- **It also works in plain `updateApp`,** so the option A pool proof can use it before the path-runner exists.

### Verify (after Health)

An optional **verify** step runs once after Health passes: exit 0 passes, anything else is `VERIFY_FAILED`, which rolls back like a Health failure. A wrong or disabled `richdocuments` goes there, not into settle. It also works in plain `updateApp`.

### Work and settle (Q12)

Waiting for background migrations stays Nextcloud-agnostic and is split so settle can be read-only.

- **work** (optional) runs once after verify and before settle. For Nextcloud it can run `cron.php`. A non-zero exit or timeout means the step is `done` and the path stops with `migrationsPending`, with no rollback. Resume can run work and settle again before the next step.
- **settle** stays a read-only probe (for this App: `status.php` plus optional `occ` reads). It is polled with `docker compose exec -T` in the running service. Exit 0 means settled, exit 3 means not yet (poll again), and any other exit counts as `SETTLE_FAILED`. A timeout or error is not a rollback. The step is `done`, and the path stops with `stopReason` `migrationsPending`. Settle gets no rollback mode.
- Official advice is still to run `cron.php` two or three times and wait before the next major. That write sits in **work**, not in settle. This wait is after `needsDbUpgrade:false` and is not part of `healthTimeout`.
- The Console phase `migrations` covers work and settle together.
- An App without `work` or `settle` skips that step. The proposal still wants this wait after each *major* hop (steps 2 to 5 on the full path). The first, small step need not declare them.

This resolves open question 12, as tightened after Kid's contract gaps 8 and 9.

## 7.3 Path record — `updatePathDB`

The Console keeps no path state of its own. The Engine stores one path record so every browser, another laptop, or an Engine restart shows the same truth. Pixel's fields are accepted as listed in section 11.7, with these Engine-side choices:

- **Store:** `updatePathDB[pathId]`, stored. The Engine keeps only the latest path per instance and overwrites the older one when a new path starts (no needless history).
- **Writes:** the Engine writes only on step and phase transitions. Live bytes and percentages stay on the ephemeral `idea/updateProgress`.
- **Who writes:** only the Engine that runs the path. Each step's `operationId` links to the existing `updateApp` op, and `backupOperationId` links to the backup op.
- **Start path:** the Engine refuses with `STALE_OFFER` if the list sent differs from its current offer, and it re-runs all pre-checks on Resume.
- **Locking (R9, agreed):** the instance lock is held while a step is running. The path runner **releases** the lock while a path is paused or in `migrationsPending`, so scheduled backups can run. On Resume the Engine re-acquires the lock, re-runs every pre-check, and takes the forced fresh backup before the next step.
- **The offer** is computed only by the Engine the disk is docked to, and stored on the instance next to `updateAvailable`, so every Engine's Console can show it. The offer lists **only** steps whose image tars and bundles are present and pass their checksums (R4). "Or a fetchable one" must not apply to kits.
- **Backup** is phase `backup` of the step. On the path, that backup is always taken, including step 1, with no one-hour skip. Each step records `backupOperationId` and `backupArchive` (Backup Disk id and archive name) so Details and Get help can name the archive that protects that step.
- **`clockTrusted: false` never skips a backup or refuses a path step.** The one-hour rule does not apply on the path. No Backup Disk linked and docked gives `refused`, `NEEDS_BACKUP` or `backupDiskMissing`, before anything changes.
- **Restart mid-path:** the path ends `stopped` with `stopReason` `interrupted`. The hop that was in progress is recovered by the existing journal rollback, and the path never continues on its own.
- **Stop request:** final. Resume is offered only after the path has stopped. There is no "Keep going" withdrawal.
- **Phases** the Console reads: `backup`, `fetch`, `check`, `snapshot`, `swap`, `prepare`, `start`, `health`, `verify`, `migrations`, `rollback`. `migrations` covers work and settle together. Kid's tarball step runs in `prepare`, between `swap` and `start`.

## 7.4 Dependency: engine#442 lands first

[engine#442](https://github.com/koenswings/agent-engine-dev/issues/442) must land before the path-runner. Today, a failed restart after a pre-snapshot failure can leave the App stopped with no Error, which would break `refused` and `rollbackFailed`.

After #442: the instance is set to **Error**, with a status condition that the update failed and the old version could not be restarted. The original code is kept (`BACKUP_FAILED`, `NO_SPACE`, `ROLLED_BACK`, and so on). **`restartFailed: true` goes in the path step result and in the command result, as well as on the op and the Error**, so the Console can show that state from either place, including when a refusal or a quick failure leaves no operation to read. The version and the files are unchanged: nothing was swapped or restored, and the backup only reads. Nextcloud is down, so operator text must not say that it works or that nothing changed in the sense a teacher reads it.

The path uses the same rollback rules between hops. It does not start hop N+1 until hop N has passed health and, where declared, verify, and work and settle have finished (or the path has paused with `migrationsPending` so it can be resumed). A later hop's backup is the rollback point for that hop, not a jump all the way back to 31, unless an operator chooses a full `restoreApp` from an earlier archive.

## 7.5 Time windows and deploys (R2)

The Engine reboots kits at **05:00** by cron (kit clock is Brussels time, Europe/Brussels), and deploys refuse from 23:55 to 00:05. A path started in the evening can be cut by that reboot. Today a reboot gives `interrupted` plus a rollback of the running hop, which is safe but wastes a backup and a migration.

Axle is asked to choose one of these (still open; see section 13):

- **(a)** the Engine holds or defers the cron reboot while any update or path holds an instance lock; or
- **(b)** the path runner refuses to *start* a step whose measured worst case would end after a cutoff, and then stops cleanly with a new `stopReason` such as `window`.

Either way, **Engine deploys must refuse while a path or journal is active** (reinstall-safe). Measured per-hop worst cases, once they exist, also feed this window check and the Console duration line (R13).

# 8. Time, disk, MariaDB, PHP, Office and idea_usage

## 8.1 Time and disk on a Pi

The only measured hop we have is 30.0.6 → 31.0.1: 66–69 seconds to a healthy `status.php` on idea04, with 6 users, 1,203 files and a 163 MB database. The 300 second health timeout was set with about 4× margin. School data, Office apps and four further majors will be slower.

For a **major** hop, Kid suggests `healthTimeout: 600` (10 minutes) and the same 600 s for Docker `healthcheck.start_period`. That is an estimate, not a measured figure: it is about 9× the 30→31 time, in the documented "few minutes" band for `occ upgrade`, and it is not sized for background migrations or `db:add-missing-*` (those sit in settle, after Health). It should be rechecked after a timed 31→32 hop on a pool Pi with a representative fixture. If that hop lands well under 150 s, 300 s can stay; if it approaches 300 s, 600 s is the safer compose value.

Each hop's first-start time, the wait for background migrations, and the backup window must be measured on a pool Pi with a realistic data set before any field plan names a duration. Operator-facing duration stays **TBD until Atlas's pool timing runs measure real times** (Run 1 first, then the full path). Until then the Console shows no duration string — not "several hours", "this can take a while", or "not yet known". Once those figures exist, they feed the Engine (any start-window check in 7.5) and the Console duration line (R13). The App may declare a per-step expected duration, or the Engine may record the actual time per step in `updatePathDB`.

Disk: every `updateApp` refuses `NO_SPACE` unless the App Disk can hold the instance folder plus named volumes, plus 10%, and at least 1 GiB. The pre-update snapshot is a full copy of `data/` plus the named volumes on the **same** App Disk (`/disks/<dev>/.pre-update/<id>/`, or `/.pre-update/` on a system-disk kit), so a hop is about **2×** the instance size while the snapshot is present.

**Snapshot retention (R5).** Five snapshots must not pile up. After a hop is healthy, its snapshot must not be kept for the rest of the path. The exact rule — delete, or quarantine with `mv` — is still open (Axle; section 13). The growth of `.idea-upgrade-backup/` per hop must be measured: the Engine never cleans it, and it sits inside every later snapshot and backup. Backup Disk growth per forced backup must also be recorded (the DB dump is new each time; the files deduplicate). The field pre-check must compare all of this against the **real instance size on each kit**, not against the pool fixture.

**Images and tars (R4).** `updateApp` never pulls (`pull_policy: never`). Images load from `services/*.tar` on the instance's disk, or the digest is already local; a missing tar is a hard fail. On a kit, every hop's bundle, image tars (Nextcloud is about 457 MB per hop) and `SHA256SUMS` are pre-staged by the kit path and checked with `verify-all.sh` **before** the path is offered. The offer lists only steps whose tars and bundles are present and pass their checksums. Keep at least the image and tar of the last good major until the next hop is healthy and its backup exists (rollback, and `restoreApp` of an earlier archive, need that previous image). Superseded images are removed only by targeted `docker image rm <ref@digest>`, and superseded tars by a quarantine `mv`. **Never `docker image prune` or `system prune`.** Who does that cleanup — the Engine after a healthy path, or an Ops step under claim — is still open (Axle, Steve).

Budget `/var/lib/docker` on the **system disk** (SD or USB) separately from the App Disk. Kid estimates a peak of about 4 GB of images; that figure is unmeasured and must be recorded in the pool run. These sizes are not yet measured; the pool proof records them before any field plan names a duration or a disk size. Kid's test-plan estimates (unmeasured) are in section 10. A settle `timeout` of 3600 s and a prepare `timeout` of 600 s are fine for the small fixture; both must be rechecked against a larger fixture before a field plan (R14).

## 8.2 MariaDB and PHP

Official MariaDB and PHP lists, from each major's [system requirements](https://docs.nextcloud.com/server/35/admin_manual/installation/system_requirements.html) and upgrade notes:

| Nextcloud | PHP supported (recommended) | MariaDB listed (recommended) |
|---|---|---|
| 31–32 | 8.1 (deprecated) – 8.4 (8.3) | 10.6 / 10.11 / 11.4 (10.11) |
| 33 | 8.2 (deprecated) – 8.5 (8.4); 8.1 dropped | 10.6 / 10.11 / 11.4 / **11.8** (**11.8**) |
| 34 | 8.2 (deprecated) – 8.5 (8.5) | same as 33 |
| 35 | **8.3** – 8.5 (8.5); 8.2 dropped | **10.11** / 11.4 / 11.8 / 12.3 (12.3); 10.6 dropped |

PHP comes with the official `N-apache` images: 8.3 on 31 and 32, 8.4 on 33, 8.5 on 34 and 35. There is no separate PHP package to bump. Those versions sit inside the supported range of each major.

MariaDB 11.7.2 is already what we run, and it is **not on any official 31–35 list**. Nextcloud 33's setup check uses a min/max range (10.6–11.8), so 11.7.2 should not produce a database-version warning, but whether it is accepted in practice on each hop is still **UNCONFIRMED** and remains a pool test item. 11.8, the LTS line and the recommended version from 33, is [app-nextcloud#31](https://github.com/koenswings/app-nextcloud/issues/31). 11.8 is also absent from the 31 and 32 lists.

**Decided (Q9):** there is **no MariaDB 11.8 in the 33 hop**. Keep 11.7.2 through 1.8, 2.0 and 3.0. 11.8 becomes a **separate hop after 33 is healthy**, still on Nextcloud 33 (or with 34), using `MARIADB_AUTO_UPGRADE=1`, and a new App major if the stateful-series rule requires it. That lands on the documented recommended LTS before 35. This 11.8 hop is a **sixth** step and a sixth backup on the field path; count it in any field timing. Do not move to MariaDB 12.3 in this path. Time taken, whether `mariadb-upgrade` from 11.7.2 to 11.8 is clean, and whether Nextcloud stays healthy remain **UNCONFIRMED** test items for that later hop.

## 8.3 richdocuments, CODE and idea_usage

Each Nextcloud major needs a matching Nextcloud Office (`richdocuments`) tarball. The App Store stable line is one major per Nextcloud major: 8.8.3 (31), 9.2.3 (32), 10.3.3 (33), 11.1.3 (34), 12.0.2 (35). Sources: [App Store](https://apps.nextcloud.com/apps/richdocuments) and the `info.xml` for [v8.8.3](https://raw.githubusercontent.com/nextcloud/richdocuments/v8.8.3/appinfo/info.xml), [v9.2.3](https://raw.githubusercontent.com/nextcloud/richdocuments/v9.2.3/appinfo/info.xml), [v10.3.3](https://raw.githubusercontent.com/nextcloud/richdocuments/v10.3.3/appinfo/info.xml), [v11.1.3](https://raw.githubusercontent.com/nextcloud/richdocuments/v11.1.3/appinfo/info.xml), [v12.0.2](https://raw.githubusercontent.com/nextcloud/richdocuments/v12.0.2/appinfo/info.xml). The 8.8.3 tarball we ship cannot accompany the 32 hop. Each release ships a new checksummed tarball in `bundled-apps/`.

**CODE 24.04.13.2 desk research (Kid, 15 November 2026).** On the documented floor — "Nextcloud Office is available since CODE 21.11" in the Nextcloud 32, 33, 34 and 35 Office migration manuals — this pin is **COMPATIBLE** with `richdocuments` 9.2.3, 10.3.3, 11.1.3 and 12.0.2. None of those tags declare a Collabora version in `info.xml`, release notes, CHANGELOG or the App Store. Feature gates in all four tags treat branding as available from CODE 21.11 and form filling from 24.04.5.2; 24.04.13.2 meets both. Nothing in those sources marked the pin **INCOMPATIBLE**.

That verdict does **not** replace a Pi proof. It is unproven on a Pi that 9.2.3 (and the later tarballs) actually open a document against this pin. CI on those tags uses `collabora/code:latest`, which is not evidence for or against 24.04.13.2. The 24.04 branch is still receiving security updates (24.04.20.4 released 23 October 2026); our pin lags that branch. That is a security lag, not an incompatibility. Collabora CODE 26.04.6.1.1 remains [app-nextcloud#34](https://github.com/koenswings/app-nextcloud/issues/34). If 24.04.13.2 fails on a hop, we consider 26.04 (or another proven CODE) at that hop, after a pool check against that hop's Nextcloud and `richdocuments`. We do not bump CODE on 31 unless the pool shows we must.

`idea_usage` 1.0.0 declares `min-version="31" max-version="31"` today, so Nextcloud will treat it as incompatible from 32 until the range is widened and the app is tested. This is an IDEA-owned app; there is no upstream 32–35 release. **The app stays at version 1.0.0 with a widened range** as majors are proven. Any version bump is decided at release. Each release still ships a checksummed tarball in `bundled-apps/` (the checksum changes when the range changes, even if the version does not). The 34 developer-manual API removals may affect it; that is part of the pool test, not an assumption.

## 8.4 Nextcloud 33 Snowflake server ID

**Decided (Q5):** `serverid` stays **unset in 3.0**. Nextcloud 33 introduces Snowflake IDs and recommends a configured `serverid`, but it does not require one to upgrade or to run a standalone instance. Leaving it unset is an admin-overview info message, not an error, and is not a hard fail of `occ upgrade`. The official Docker image does not set it. 3.0 does not write `-1` into `config.php` and does not set `serverid` in Prepare (Prepare must not run `occ` or rewrite `config.php`).

A stable `NC_serverid` is a **later item**. If it is set later, it must be an integer **1–511**, never 0 (the generator treats values below 1 as unset) and never -1 (the setup check returns an error). A single stable value such as `NC_serverid=1` on the `nextcloud-app` service is enough, because IDEA instances do not share a database. The Engine must keep service env on `compose exec` / `compose run` (section 7.2), so Apache and CLI see the same value. A unique-per-instance field is not required.

Live confirmation on a Pi that a 32→33 upgrade with `serverid` unset is not blocked remains **UNCONFIRMED** and is a test item.

## 8.5 Admin-facing changes in Nextcloud 34 (Q4)

Kid's hop-34 desk research (15 November 2026, evening, Europe/Brussels) found **no documented admin-facing breaking changes** for Nextcloud 34. The 34 Administration Manual [release-notes index](https://docs.nextcloud.com/server/34/admin_manual/release_notes/index.html) lists critical-change pages for 33, 32, 31, 30, 28, 27 and 26, but there is no "Upgrade to Nextcloud 34" page. A docs issue asked whether the page was missing; a Nextcloud maintainer said it is intentional: "Its not missing there are no critical changes. Similar with 29 for which also no entry exists" (susnux, 8 October 2026, [nextcloud/documentation#15244](https://github.com/nextcloud/documentation/issues/15244)). The community 34 update-issues thread says the same: "no breaking changes this time!" ([Frequent Nextcloud 34 "Hub 26 Spring" update issues](https://help.nextcloud.com/t/frequent-nextcloud-34-hub-26-spring-update-issues/244554), 17 May 2026).

There is therefore no documented admin action this hop must take beyond Nextcloud's own `occ upgrade` on first start, which is already in the path. The official 34.0.6-apache image already runs PHP 8.5, the recommended version. MariaDB stays on 11.7.2 in this hop (section 8.2). The [developer upgrade notes](https://docs.nextcloud.com/server/34/developer_manual/release_notes/previous/upgrade_to_34.html) remove front-end and old back-end APIs that `idea_usage` 1.0.0 does not use (desk review, 15 November 2026). This App never set `blacklisted_files`. No admin-manual critical change was found for sharing or user management, and no removal or rename was found for the `occ` commands this App uses.

Compared `core/shipped.json` at v33.0.11 and v34.0.6, nothing was removed. Nextcloud 34 adds `office` (an Office overview / switcher, **not** `richdocuments`; [server#60776](https://github.com/nextcloud/server/pull/60776)), `files_lock` (temporary collaborative locking used by Text and Office), and extracts `appstore` as its own **always-enabled** shipped app. Prepare and settle still stage and check `richdocuments` 11.1.3 plus `idea_usage` 1.0.0; the new `office` app does not replace that bundle. Impact is low, but two behaviours are **UNCONFIRMED** on a Pi and stay test items: how the `office` overview sits next to our Collabora / `richdocuments` setup (including the `30-idea-office.sh` hook), and whether the always-enabled `appstore` is noisy on an offline kit (an error in the UI, not an upgrade block).

A live 33→34 upgrade, enabling `idea_usage` on 34, a full `occ` command diff versus 33, and how much background work remains after Health are also unconfirmed on a Pi, and can be recorded in the hop-34 pool run. This does not change the 4.0 pin: `4.0-34.0.6` with `updatesFrom: [3]`, official `34.0.6-apache` index as in section 4.

# 9. How this fits after the field update

This path is not part of idea#374. Field Engines stay pinned at `adfd9d3` until Koen approves that update. Kits today are **not** on tagged 1.7-31.0.1: they still run 1.0-31.0.1 with a SHA `x-app.version` on Engine `adfd9d3` and helper v2, and they have no Backup Disk docked (section 1). MariaDB 11.8 and CODE 26.04 stay held with this work, not folded into the field kit.

The path can start on a kit only after **all** of the idea#374, Backup Disk, and path-runner preconditions in section 1 are met. What the path offers on a kit that is still on a SHA `x-app.version` is still open (section 13).

After #374 is proven and, if Koen approves, applied, the pool can install later Engine and Console builds that include the path-runner if we need it. [engine#442](https://github.com/koenswings/agent-engine-dev/issues/442) lands first, with `restartFailed` in the command result as well as on the op and the Error. The prepare, verify, work and settle steps can be used in plain `updateApp` for the hop proofs before the path-runner exists. App releases for 31.0.14 and the later majors are built and proven only on the pool.

**Koen's approval of this proposal waits for Atlas's first pool timing run (Run 1:** 31.0.1 → 31.0.14 → 32.0.15, without prepare, on today's Engine main). **Any kit plan stays blocked until the full path is measured.** No production Pi and no field kit is updated as part of this proposal. A later field plan, with measured times and disk figures, is a separate decision, and it still needs Koen's own OK per kit.

**Later rollout order, named now so that "proven" is not read as "go" (R12):**

1. The pool, one Pi at a time (idea03 or idea04, never both down).
2. Then, only if they host a Nextcloud instance and with Koen's OK naming them, production `idea` and then golden `idea01`, as with Engine rollouts. Whether either hosts a Nextcloud instance in scope is still open (Steve; section 13). Golden is the image source for new kits, so it moves only once the kit decision is made.
3. Kits last, only by the kit path, one kit per evening, each with its own Koen OK, with a Backup Disk docked and the pre-checks passed.
4. Kit order follows the #374 runbook (happy-zebra, sunny-robin after its power check, kind-panda after first contact).

idea02 is client-only and is never in scope.

# 10. Test plan (pool only)

All of this runs on a claimed pool Pi (idea03 or idea04), never golden idea01, never idea02, never a kit, never production. One Pi down at a time. The instance is throwaway. The shared pool store is not used as the test store. If any real fleet data appears, the test stops.

Kid's pool test plan of 15 November 2026 covers UNCONFIRMED items 2 (CODE and Office), 3 (MariaDB 11.7.2), 5 (Nextcloud 33 Snowflake server ID) and 6 (bundled core apps). Items 1 and 8 are documentation-only. Items 4 and 7 are only partly covered (what our hooks, tests and roles hit). The plan is one Pi, under a fresh fleet-state claim. Hop images are the official digests, tagged locally on the Pi, so the pool proof does **not** wait on a `koenswings/nextcloud:*` retag (that retag still needs Koen's YES, as for #36). Hop bundles live on a scratch branch. Nothing from that plan is published as a release.

**Atlas's pool timing runs, and Koen's approval.** Atlas offered to run the timing, with Kid owning the hop bundles and Axle the Engine build for the functional proof.

- **Run 1** (Atlas's Phase M1), **before Koen's approval of this proposal:** timing only, on today's Engine main, plain `updateApp`. Steps 31.0.1 → 31.0.14 (1.8) and 31.0.14 → 32.0.15 (2.0, `--allow-major`), **without prepare**. Nextcloud may disable the out-of-range `richdocuments` and `idea_usage` during `occ upgrade`; that is recorded and they are re-enabled or replaced by hand afterwards. Timing is still valid, and it is labelled "without prepare". Atlas also records the Pi model, RAM and swap, so later kit timings can be compared. About 2 hours.
- **The rest of the timing** (Atlas's Phase M2): the same method for 33.0.11, 34.0.6 and 35.0.3, then a repeat of 31→32 on a larger fixture if one is agreed (section 13). Any kit plan stays blocked until the full path is measured.
- **Functional proof** (Atlas's Phase F), after Axle's prepare, verify, work and settle build is on a pool branch: the items below, plus the hard-reset proof (item 10), the per-hop health gate (item 11), the cross-major restore (item 3) and maintenance-marker hygiene (item 10). Then the path-runner run (item 9) on a fresh instance.

**Setup (from that plan, once).** A throwaway App Disk (not the WD 20070Q450002, the demo or nextcloud-files-b-001), plus a Backup Disk linked only for the run, with the link removed afterwards. Both disks are named in the claim text. Any change to a disk record (new throwaway disks, role changes) goes as a PR for Koen's OK. After any later real rollout, the Nextcloud App version per Pi or kit is recorded the same way, by PR (R11). Install 1.7-31.0.1 and seed it: admin, teacher1 and learner1, around 300 small files, one `.odt`, one `.ods` and one `.odp`, and some `idea_usage` counts (this fixture is for functional checks; a larger timing fixture is still open, section 13). Hop bundles: 31.0.14, 32.0.15, 33.0.11, 34.0.6, 35.0.3 (official `N-apache` digests, arm64 checked), each with its `richdocuments` tarball (8.8.3 / 9.2.3 / 10.3.3 / 11.1.3 / 12.0.2) and an `idea_usage` 1.0.0 build whose max-version is widened for the test. Each hop is an ordinary `updateApp`. Once Prepare exists, that is how the tarballs are placed in `custom_apps` before the new container starts. After each major, settle (`cron.php` until background jobs are idle) runs before the next hop.

1. **Baseline.** As in the setup above. Link a Backup Disk and leave it docked. Include a Files Disk or USB sync path if that is in the hook tests.
2. **Each hop in order**, as an ordinary `updateApp` to the next App release: 31.0.14, then 32.0.15, 33.0.11, 34.0.6, 35.0.3. Record wall-clock time (backup, Prepare, first start, health, background migrations), peak disk, image sizes, and `healthTimeout` headroom. Recheck the 600 s major-hop estimate after the timed 31→32 hop.
3. **Failure and rollback, including a cross-major restore (R7).** On at least one major hop, force a health-check failure and confirm automatic rollback to the previous release with data intact. On another hop, restore from the Borg archive taken at the start of that hop (`restoreApp`) and confirm the same. Also confirm `PREPARE_FAILED` rolls back to the snapshot. Add the case a school really hits: hop N+1 has already migrated, and we go back to step N's archive with `restoreApp`. PASS means the old compose and image come back, the DB dump is re-imported into an empty datadir by `00-idea-restore.sh`, and the instance is healthy on major N. Record how long the restore takes (the dump import on a Pi is the slow part). Nextcloud cannot downgrade, so this restore is the **only** way back once a hop's snapshot is gone.
4. **MariaDB (item 3).** At every hop, including 33: check the `occ` upgrade output, `occ setupchecks` for database-version warnings, `occ db:add-missing-indices` / `columns` as a dry run, and `nextcloud.log` errors. Confirm 11.7.2 is accepted on 31.0.14, 32 and 33, or stop and rethink if a hop refuses it. **Do not put 11.8 inside the 33 hop.** After 33 is healthy, a **separate** 11.8 hop (using `MARIADB_AUTO_UPGRADE=1`) is proven on a throwaway copy: data upgrade, login and Office. Time taken, whether `mariadb-upgrade` from 11.7.2 to 11.8 is clean, and whether Nextcloud stays healthy are **UNCONFIRMED** test items for that later hop.
5. **CODE and Office (item 2).** At every major, check that `richdocuments` discovery / activate-config succeeds, then do a headless open-edit-save round trip of the `.odt`, `.ods` and `.odp`. Also check `nextcloud.log` and the CODE log for WOPI errors. If 24.04.13.2 fails, trial CODE 26.04.6.1.1 on that hop only and record the result.
6. **idea_usage.** After every major, including 34, confirm the bundled 1.0.0 app enables, migrates, and still reports role-level counts. Widen `info.xml` only for majors that pass; keep the version at 1.0.0 unless a release decision says otherwise.
7. **Nextcloud 33 Snowflake server ID (item 5).** 3.0 leaves `serverid` unset. After the 33 start, confirm it is unset, that setupchecks show only an info (not an error), and that upgrade, login and Office still work. Do not set `NC_serverid` in 3.0, and do not write `-1` into `config.php`. Live confirmation that the upgrade is not blocked with `serverid` unset remains an **UNCONFIRMED** test item. A later item may set a stable `NC_serverid=1`; when that is tested, confirm it reaches both Apache and `occ` and persists across a restart and a backup/restore.
8. **Bundled core apps (item 6), including Nextcloud 34 additions.** Before and after each hop, save `occ app:list --output=json` and the image's `/var/www/html/apps` listing, then diff them per hop. Flag anything disabled, removed or newly enabled by default (for example AppAPI on 32). `files_external` must still be enabled at the end. On the 34 hop, also record the new shipped apps `office` and `files_lock`, and that `appstore` is always-enabled. **UNCONFIRMED test items:** how the `office` overview sits next to Collabora / `richdocuments` (including the `30-idea-office.sh` hook), and whether the always-enabled `appstore` is noisy on an offline kit.
9. **Path-runner (option C).** Only after hops 1–8 pass one by one: run the same sequence as a single path on a fresh throwaway instance, including a mid-path failure and resume, a work or settle timeout that pauses with `migrationsPending` (no rollback) and Resume, a `VERIFY_FAILED` rollback, a `PREPARE_FAILED` rollback, a start with `restartFailed`, a stale offer, and a stop request that finishes the current step and then waits for Resume. Confirm the path runner takes a fresh backup on every step, including a minor and a step that already has a backup from the last hour, while plain `updateApp` still skips in those cases.
10. **Interruptions, including a hard reset (R3, R8).** Pull the disk or restart the Engine mid-hop and confirm journal rollback before start. Confirm the path record ends `stopped` with `interrupted` and never auto-continues. That is not enough: kits lose power, so extend the item to a **hard reset** of the claimed pool Pi at each of these points: (i) during the pre-update Borg backup (a stale Borg lock; the next backup must still work); (ii) during the snapshot copy; (iii) during prepare; (iv) during the entrypoint `occ upgrade` (the worst case); (v) during rollback, a double fault where the snapshot must stay intact and the instance end Stopped/Error, never half-restored; (vi) during work or settle. A **forced reboot** of a claimed pool Pi (idea03 or idea04 only; never golden idea01 or client idea02) is allowed (Steve, 15 November 2026). A real power cut needs someone at the pool, so it is a Koen item on idea#375, presented only when he is ready. PASS for each point: the Pi comes back and pm2 (running as pi, from `pm2 save`) starts the Engine; `recoverInterruptedUpdates` rolls back before anything starts; MariaDB starts clean; the path record shows `stopped` / `interrupted` and does not continue on its own; the next backup succeeds; and both the rollback path and the next start have cleared maintenance mode and any leftover `.idea-backup-pending` marker (the healthcheck tolerates that marker only for −300 s to 7200 s). "Nextcloud is unavailable" must not quietly become "stuck in maintenance" after a power cut.

11. **Per-hop Ops health gate (R6).** After each hop, and before the next step's backup, check: containers up, with restart count 0; the Engine log has no new errors, and pm2 shows 0 restarts for the engine; login works for admin, teacher1 and learner1; the Office round trip works (item 5); `files_external` is enabled, and `idea_usage` counts still come in; **a backup on the new major's hook succeeds** (maintenance on, dump, Borg, maintenance off) — if the hook breaks on major N, step N+1 refuses `HOOK_FAILED` and the school is stuck with no fresh backup; temperature is under 70 °C, and the current under-voltage and throttle bits are 0; `df` is recorded on the App Disk, the system disk (`/var/lib/docker`) and the Backup Disk. The path runner should refuse to start a step if the thermal or under-voltage bits are set, just as Fetch already pauses for heat.

**Time and disk (Kid's estimates only — unmeasured; the run records real figures).** Setup and seed: about 45 minutes. Per hop: about 25–40 minutes (pull ~460 MB, backup, upgrade with migrations, cron, and the item 2/3/5/6 checks), or about 2.5–3.5 hours for five hops. MariaDB 11.8 side checks: about 30 minutes. CODE 26.04 fallback: about +30 minutes per failing hop. Cleanup: about 20 minutes. Total: about 4–5 hours on one Pi, splittable after any hop. Disk estimates: Docker images on the Pi peaking around 4 GB (current 1.7 set ~1.06 GB, plus five Nextcloud hop images ~2.3 GB, plus optional MariaDB 11.8 and CODE 26.04); throwaway App Disk at least 5 GB free; Backup Disk at least 6 GB free; box-side hop bundles about 60 MB. These numbers are planning estimates for the pool run, not operator-facing duration and not a field-plan figure.

**PASS per hop (Atlas).** Healthy within the timeout; the item 11 checks are green; the new major's backup hook succeeds; restart counts are 0; App Disk free space never drops below the Engine's own floor (instance + 10% + 1 GiB); temperature stays under 75 °C with no new throttle bits.

**Stop rule.** Any real fleet data, any non-throwaway disk, under-voltage or throttling during a hop, or less than 2 GB free on the system disk: stop, roll back or restore, and report to Steve.

**Cleanup.** `removeInstance` of the throwaway instance through the Engine; remove test images by explicit `ref@digest` only, with **no prune**; quarantine scratch folders with `mv`; unlink the Backup Disk; restore Engine main and restart it as pi, then `pm2 save`; release the claim flag-first (`--null` claim, check that it is JSON null), then status idle.

Kid owns the App releases and the hop proofs. Axle owns `updateApp` behaviour, Prepare, settle and the path-runner. Pixel owns the one-confirmation Console flow. Atlas claims the Pi, watches disk and heat, runs the timing (Run 1 first), and keeps the proof off the fleet store. Marco records anything a teacher or operator will need to be told, but does not publish guides until the path is proven.

# 11. Console

The Console offers the whole Nextcloud 31→35 path as **one update with one confirmation**. It then shows which step is running, and it shows plainly where the path stopped if it stops. The Console keeps no state of its own: everything it shows is read from the Engine's path record (section 7.3 and 11.7). A reload, another laptop or an Engine restart always shows the same truth.

Today's single-step Update flow stays as it is. Its words, phases and refusal texts are reused for each step. Read from `agent-console-dev` `origin/main` (`src/store/updateApp.ts`, `src/components/UpdateAppControl.tsx`) and Engine `origin/main` `da08956` (`src/data/UpdateApp.ts`, `docs/COMMANDS.md`). Anything marked **NEW** does not exist yet. Operator wording is Marco's draft, with the agreed decisions applied. Placeholders the Console fills in are in angle brackets.

## 11.1 When the Console offers the path

The Console shows the path offer only when all of these are true:

- The Engine advertises a path capability (**NEW**, for example `updatePath`). Without it, the Console shows today's one-step Update badge, unchanged.
- The instance runs Nextcloud 31.x.
- The Engine reports a path offer for this instance (**NEW**): the ordered list of App releases whose image tars and bundles are present on a docked App Disk and pass their checksums (R4). "Or a fetchable one", as `updateAvailable` does today, **must not apply to kits**: a kit offer lists only steps already pre-staged and verified on that kit's disk.

The badge reads: **`Update available: 31.0.1 to 35.0.3 (5 steps)`** (`Update available: <from> to <to> (<N> steps)`).

If the Engine only has some of the releases (for example up to 33.0.11), the offer covers only those steps. The Console never works out the path itself. It shows what the Engine offers. After a mid-path stop, the badge comes back with the remaining path, for example `Update available: 32.0.15 to 35.0.3 (3 steps)`.

**No uplink needed (agreed).** The path is allowed on a Pi with no uplink. Everything it needs comes from the App Disk, so it is offline-first like every other update. The Console does not check for an uplink.

## 11.2 The confirmation screen

One screen, one button, no typed name (agreed). Typed-name confirms stay for destructive actions only (Erase Disk, Make Backup Disk). The confirmation names the whole path and states the downtime clearly before the button.

```
+-------------------------------------------------------------------+
| Update Nextcloud from 31.0.1 to 35.0.3?                           |
|                                                                   |
| This runs 5 updates, one after the other:                         |
|   1. 31.0.14   small update   backup first                        |
|   2. 32.0.15   major update   backup first                        |
|   3. 33.0.11   major update   backup first                        |
|   4. 34.0.6    major update   backup first                        |
|   5. 35.0.3    major update   backup first                        |
|                                                                   |
| Nextcloud is unavailable while the update runs. Teachers and      |
| learners can't open files or Office during that time. Pick a      |
| time with no lessons.                                             |
|                                                                   |
| Your learners' work is kept. IDEA makes a backup on               |
| "Backup Disk A" before every step. If a step doesn't work,        |
| IDEA switches that step back by itself and stops there.           |
| Nextcloud then keeps working on the last good version.            |
|                                                                   |
| Keep this IDEA box switched on, and leave the Backup Disk         |
| plugged in, until the update is finished. Don't unplug any disk.  |
|                                                                   |
| [v] Backup Disk "Backup Disk A" is plugged into this Pi           |
| [v] Nextcloud is running                                          |
| [v] No other update or backup is running                          |
|                                                                   |
|                      [ Update in 5 steps ]   [ Not now ]          |
+-------------------------------------------------------------------+
```

**Wording (Marco, with agreed decisions applied).**

- Title: `Update Nextcloud from <from> to <to>?`
- Intro: `This runs <N> updates, one after the other:`
- Step list: "small update" or "major update" from each step's `major` flag, and **`backup first` on every step**, including the first small one.
- Unavailable: **`Nextcloud is unavailable while the update runs. Teachers and learners can't open files or Office during that time. Pick a time with no lessons.`**
- Duration: **TBD (Atlas's pool timing runs will measure real times).** No operator-facing duration string for now. Do not show "several hours", "this can take a while", or "not yet known." When a measured figure exists, this is where it will go (`NC35-CONFIRM-DURATION`).
- Backup and rollback: `Your learners' work is kept. IDEA makes a backup on "<Backup Disk name>" before every step. If a step doesn't work, IDEA switches that step back by itself and stops there. Nextcloud then keeps working on the last good version.`
- Stay on: `Keep this IDEA box switched on, and leave the Backup Disk plugged in, until the update is finished. Don't unplug any disk.`
- Buttons: `Update in <N> steps` and `Not now`.

**Pre-checks, done before the button is enabled.** Each failed check disables the button and shows one plain reason under the list.

| Check | Read from | Blocked wording |
|---|---|---|
| A Backup Disk linked to this instance is docked to **this** Engine | `diskDB`: a Backup Disk whose `backupConfig.links` lists the instance, or is empty (engine#424: empty means "every App on this Pi"), with `dockedTo` = this Engine | "Plug in the Backup Disk for Nextcloud first, then try again. IDEA makes a backup before every step, and can't start without the disk." |
| No path, update, backup or restore already running on this instance | the path record (NEW) and `operationDB` | "Something else is running on Nextcloud. Try again when it is done." (today's `BUSY` text) |
| The Engine that runs Nextcloud is online | `engineDB` connection state | "The Pi that runs Nextcloud is switched off or out of reach. Switch it on to update." |
| Backup method is not `none` | `isBackupMethodNone` | Not expected for Nextcloud. If it happens, the path is not offered at all. |

The Engine still makes the final decision. If it refuses at the start (for example `NEEDS_BACKUP`), the Console shows that refusal with today's wording and nothing has changed.

**Backup freshness.** Today a major update needs a backup from the last hour (`BACKUP_MAX_AGE_MS`), and the Console shows "Make a backup first" until there is one. That is still how plain `updateApp` works. On the path that pre-check is replaced by "a linked Backup Disk is docked", because the path runner forces a fresh backup before every step and ignores the one-hour skip. No manual backup click is needed. A clock that is not trusted can never cause a skip or a refusal on the path.

**Clock.** The path does not need a trusted clock: each step takes a fresh backup, so no time window has to be judged. The Console shows elapsed times measured from the Engine's own timestamps, and never shows a date it can't trust. If the Engine reports `clockTrusted: false`, the Console adds the existing note "Backup time unknown: this Pi's clock may be wrong" on the Backup Disk, as today. That does not block the path.

## 11.3 The progress view

Shown in place of the badge on the Nextcloud row, for every Console user who opens the page.

```
+-------------------------------------------------------------------+
| Updating Nextcloud: step 3 of 5, to 33.0.11                       |
| Started 1 h 12 min ago                                            |
|                                                                   |
|  [done]     1. 31.0.14   updated (6 min)                          |
|  [done]     2. 32.0.15   updated (24 min)                         |
|  [running]  3. 33.0.11   Nextcloud is finishing its background    |
|                          work. This can take a while. (9 min)     |
|  [waiting]  4. 34.0.6                                             |
|  [waiting]  5. 35.0.3                                             |
|                                                                   |
| Nextcloud is unavailable while the update runs. Keep this IDEA    |
| box switched on, and leave the Backup Disk plugged in.            |
|                                                                   |
|                                  [ Stop after this step ]         |
+-------------------------------------------------------------------+
```

**Headline.** `Updating Nextcloud: step <n> of <N>, to <version>`. Elapsed: `Started <elapsed> ago`.

**Phase line for the running step.** Today's labels (`STEP_LABEL`) are reused, with the new phases below. The `backup` phase runs at the start of every path step, including step 1. The Console phase `migrations` covers **work** and **settle** together. Operator labels for `prepare` and `verify` are not in Marco's wording yet and stay to be set.

| Engine phase | Shown as | Exists today? |
|---|---|---|
| Backup (pre-update backup) | `"Making a backup on <Backup Disk name>"` | Yes, as a separate `backupApp` op (idea#448). Linked to the step as phase `backup` plus `backupOperationId` (NEW). Forced on every path step, with no one-hour skip. |
| Fetch | `"Copying from <box name>: <done> of <total> GB"` (or `"Copying from <box name>"` when there is no byte count) | Yes |
| Fetch paused (thermal) | `"Paused while <box name> cools down. The copy continues by itself."` | Yes, today's `pausedText` |
| Fetch paused (other) | `"The copy from <box name> is paused. It continues by itself."` | Yes, today's `pausedText` |
| Check | "Checking" | Yes |
| Snapshot | "Saving a safety copy" | Yes |
| Swap | "Installing" | Yes |
| Prepare | (operator wording still to be set) | **NEW** — between Swap and Start |
| Start | "Starting" | Yes |
| Health | "Checking it works" | Yes |
| Verify | (operator wording still to be set) | **NEW** — once after Health; failure rolls back |
| Migrations (work and settle) | "Nextcloud is finishing its background work. This can take a while." | **NEW** |
| Between steps (`currentPhase` = `null`) | "Getting the next step ready." | **NEW** |
| Rollback | `"This step didn't work. Switching back to <last good>."` | **NEW** as a visible phase (today the Console only sees the end state) |

**No fake percentages.** Only Fetch has a real byte count. Every other phase shows the time spent in that phase, for example "(9 min)". The migrations wait never shows a bar. The elapsed time keeps ticking so the screen doesn't look frozen.

**Finished steps** stay listed with their result and duration. Waiting steps are grey.

**Who sees what.** Every browser and every laptop sees the same view, because it is drawn from the Engine's path record. Only one person can start a path. "Stop after this step" is shown to anyone who can start an Update, with the same check as today's Update control (agreed). The button is then replaced by "Stopping after this step" for everyone.

**Reload, other laptop, Engine restart.** Nothing lives in the browser except "Not now" for the offer, which is already per-browser today. After an Engine restart, the view shows whatever the Engine's recovery wrote.

**Progress messages.** The Console keeps listening to `idea/updateProgress` for the live phase and the bytes count. The path record is the fallback after a reload, and the source of truth for anything that isn't live.

**Maintenance line during progress:** `Nextcloud is unavailable while the update runs. Keep this IDEA box switched on, and leave the Backup Disk plugged in.`

## 11.4 End and failure states

Wording is Marco's, for a teacher or a visiting operator. `<last good>` is the version Nextcloud is running on after the stop. `N` is the step number.

| State | Headline | Body | Buttons |
|---|---|---|---|
| All done | Nextcloud updated to 35.0.3 | All 5 steps worked. Your files are kept. Teachers and learners can use Nextcloud again. | OK |
| Step failed and rolled back (`ROLLED BACK:`, including `PREPARE_FAILED` and `VERIFY_FAILED`) | Stopped at step N. Nextcloud is safe on `<last good>` | The update to `<target>` didn't work, so IDEA switched it back. All files are kept, and Nextcloud works as before. Reason: `<plain reason>`. Step line: `<n>. <version>    didn't work, switched back`. | Resume, Details, OK |
| Rollback failed (`ROLLBACK FAILED:`, instance Stopped) | Nextcloud is stopped. Ask for help | Step N didn't work, and IDEA couldn't switch it back by itself. Nothing was deleted: the safety copy and the backup are kept. Don't unplug any disk. Step line: `<n>. <version>    didn't work, couldn't switch back`. | Get help, Details, OK (OK hides the panel in this browser only; the headline stays) |
| Refused before anything changed (`NEEDS_BACKUP`, `NO_SPACE`, `NOT_DOCKED`, `MAJOR_NOT_ALLOWED`, `NO_SUMS`, `UPDATE_CONTRACT_INVALID`, …), and `restartFailed` is not set | Step N didn't start. Nothing changed | Today's `REFUSAL_TEXT` for that code. If N > 1: "Nextcloud is on `<last good>` and works." Step line: `<n>. <version>    didn't start, nothing changed`. | Resume (when the cause is fixed), OK |
| Restart failed (`restartFailed: true` on a refused step; engine#442) | Step N didn't start. Nextcloud is stopped | The update to `<version>` didn't start, and IDEA couldn't start Nextcloud `<last good>` again. Its version and files are not changed, and nothing was deleted. Try starting Nextcloud again. If it doesn't start, ask IDEA for help. Reason: `<plain reason>`. Step line: `<n>. <version>    didn't start, Nextcloud is stopped`. Tone is red. | Get help, Details, OK. **No Resume** until Nextcloud is `Running` again. |
| Backup hook failed (`HOOK_FAILED`) | Step N didn't start. Nothing changed | IDEA couldn't make the backup, because Nextcloud's backup step failed. Nextcloud was not stopped and works on `<last good>`. Try again later, or ask for help if it happens again. (`HOOK_FAILED` cannot reach `restartFailed`, because that hook runs before the stop.) | Resume, Details |
| Backup failed (`BACKUP_FAILED`), unless `restartFailed` | Step N didn't start. Nothing changed | The backup on `<Backup Disk>` didn't finish, so IDEA didn't update. Nextcloud works on `<last good>`. Check that the Backup Disk is plugged in and has room. | Resume, Details |
| Backup Disk unplugged mid-path (`backupDiskMissing`) | Stopped at step N. Nextcloud is safe on `<last good>` | The Backup Disk was unplugged, so IDEA can't make the backup for this step. Nextcloud is safe and works on `<last good>`. Plug the Backup Disk back in, then press Resume. | Resume (disabled until docked), Details, OK |
| Engine restarted or App Disk pulled mid-step (`INTERRUPTED:`, `stopReason` `interrupted`) | Stopped at step N. Nextcloud is safe on `<last good>` | The Pi restarted (or a disk was unplugged) during step N. IDEA switched that step back when it came back. All files are kept. | Resume, Details |
| Same, but the rollback failed | as "Rollback failed" | as "Rollback failed" | as "Rollback failed" |
| Stopped by request (`stopReason` `requested`) | Stopped after step N, as asked. Nextcloud is on `<last good>` | Nextcloud works. The remaining steps (`<list>`) can run later. | Resume, OK |
| Paused, waiting for background work (`stopReason` `migrationsPending`: a work or settle timeout or `SETTLE_FAILED`) | Paused after step N. Nextcloud is finishing its background work | Nextcloud is on `<last good>` and works. Nothing was undone. Press Resume later to continue. Keep this IDEA box switched on, and leave the Backup Disk plugged in. Step line: `<n>. <version>    done, waiting for background work`. Neutral tone; not a rollback. `<last good>` is the version this step just reached. | Resume, Details, OK (OK hides the panel only; the paused headline stays) |
| Offer out of date (`STALE_OFFER`) | (confirm is dismissed) | The updates on offer changed. Nothing changed. Close this and open the update again. | OK (closes the confirm only; the badge comes back with whatever the Engine now offers. No Resume of the stale list.) |
| Start refused because a path is already running | (reuses the busy pre-check, then the progress view) | Something else is running on Nextcloud. Try again when it is done. | then the progress view |
| Resume | Continue updating Nextcloud from `<last good>` to `<to>?` | Only the remaining steps are listed. Done steps show "updated". The same pre-checks run. The same unavailable and stay-on lines are shown. No duration string until times are measured. Each remaining step still shows `backup first`. | Update in M steps, Not now |
| Path already running (second browser) | Updating Nextcloud: step N of 5 | (the progress view) | Stop after this step |
| Instance on another Engine, or that Engine offline | Can't reach the Pi that runs Nextcloud | The update is run by `<box name>`. Its last news: step N, `<phase line>`. The update carries on by itself. This page shows it again when the Pi is back. | none |

Notes on the table:

- **Ending partway is not an error.** "Stopped at step N" and "Paused after step N" use the neutral (grey/amber) tone. Only "Rollback failed" and `restartFailed` use red.
- **Today's gaps.** `HOOK_FAILED` and `BACKUP_FAILED` are real Engine codes, but they have no Console text today. They fall through to the generic `plainEngineText`. Console PR #214 adds them to `REFUSAL_TEXT` for the one-step Update, and the path reuses that wording. PR #214 needs no change before engine#442 lands. After #442, one Console override for every one-step Update code shows the stopped wording when `restartFailed` is true.
- **"Details"** opens today's History entry for that step's operation: the error text, the snapshot path and the backup used (`backupOperationId` and `backupArchive`, the Backup Disk id and archive name recorded for every step).
- **The resume confirm** title is `Continue updating Nextcloud from <last good> to <to>?`. It shows the same maintenance warning, with the remaining steps only. Resume is offered only after the path has stopped, and not while `restartFailed` has left Nextcloud down.
- **Get help "OK"** hides the panel in this browser only. The headline comes from the Engine (`needsHelp`) and stays for every browser.
- Step-list labels, the between-steps phase, the Resume title, OK on Get help, `restartFailed`, a stale offer, a path already running, Fetch paused, and the paused `migrationsPending` state are now worded as above (Marco, 15 November 2026, 20:41, Europe/Brussels, after Pixel's review). The only wording marker left is the duration TBD.

```
+-------------------------------------------------------------------+
| Stopped at step 3. Nextcloud is safe on 32.0.15                   |
|                                                                   |
|  [done]     1. 31.0.14   updated                                  |
|  [done]     2. 32.0.15   updated                                  |
|  [back]     3. 33.0.11   didn't work, switched back               |
|  [waiting]  4. 34.0.6                                             |
|  [waiting]  5. 35.0.3                                             |
|                                                                   |
| The update to 33.0.11 didn't work, so IDEA switched it back.      |
| All files are kept, and Nextcloud works as before.                |
| Reason: Nextcloud didn't start in time.                           |
|                                                                   |
|                         [ Resume ]  [ Details ]  [ OK ]           |
+-------------------------------------------------------------------+
```

"OK" only hides the panel. The offer badge comes back as "Update available: 32.0.15 to 35.0.3 (3 steps)".

## 11.5 Stop and resume

- There is **one** stop control: **"Stop after this step"**. It asks the Engine to finish the current step (including its health check and, on a major, the migrations wait) and then not start the next one.
- There is **no** cancel in the middle of a step. Stopping a Nextcloud database upgrade halfway is the exact risk the path is designed to avoid. The existing `cancelOperation` is not offered for path steps.
- After pressing it, the button becomes "Stopping after this step" for everyone. The request is **final**. There is no "Keep going" control: after any stop, **Resume is the only way forward** (agreed, Steve 15 November 2026). Resume is offered only after the path has stopped, and not while `restartFailed` has left Nextcloud down.
- During the Fetch phase (before anything is stopped), stopping could end the step at once. The Console still says "after this step", to keep one simple rule.
- "Stop after this step" uses the same role as Update (agreed).

## 11.6 Get help

"Get help" shows a short block to copy or photograph. It does not send anything.

Intro: `Copy or photograph the details below and send them to IDEA by email (idea-support@agentmail.to) or on Telegram (@IDEA_SupportBot). This does not send anything by itself. Please don't telephone. Leave the IDEA box switched on, and don't unplug any disk.`

```
IDEA box: <box name>
App: Nextcloud
Step: <n> of <N>
Version: <version>
Nextcloud is on: <last good> (stopped)
What the Console reported: <plain reason>
Code: <error code>
Backup: <Backup Disk> / <archive name>
```

The `Code:` line is small, for support. The `Backup:` line is the `backupArchive` recorded for that step (Backup Disk id and archive name). It does not replace the plain-reason sentence. A short "if the update stops" page that this block could point to is added to the operator (and, if useful, teacher) guide only after the path is proven.

## 11.7 What the Console needs from the Engine

This is the agreed contract (Pixel's fields, with Axle's answers applied). How the Engine stores or runs it is in section 7.3.

**Read: one path record per running or last-finished path** (NEW), in `updatePathDB[pathId]`, so every browser sees it and it survives reloads and restarts. Only the latest path per instance is kept.

| Need | Why |
|---|---|
| `pathId` | To tell one path apart from an earlier one on the same instance, and to key the view. |
| `instanceId` and App name | To put the view on the right row. |
| `engineId` that runs it | To show "the Pi that runs it is offline" and send commands to the right Engine. |
| `fromVersion`, `toVersion` | For the headline and the badge. |
| Ordered `steps[]`, each with `index`, `appId`, `targetVersion`, `major` | To draw the list, the "small/major" labels, and key the `<For>` loop by a stable id. |
| `currentStepIndex` | "Step N of 5". |
| `currentPhase`: one of `backup`, `fetch`, `check`, `snapshot`, `swap`, `prepare`, `start`, `health`, `verify`, `migrations`, `rollback` (or `null` between steps) | To pick the phase line. `prepare`, `verify`, `migrations` and `rollback` are NEW. `migrations` covers work and settle together. Operator labels for `prepare` and `verify` are still to be set. |
| Per step: `result` = `pending`, `running`, `done`, `rolledBack`, `rollbackFailed`, `refused`, `skipped` | To mark each line and choose the end state. `refused` = stopped before anything changed. A settle timeout leaves the step `done`. |
| Per step: `errorCode` and `errorText` (same `CODE: text` as today) | To reuse `REFUSAL_TEXT` and the ROLLED BACK / ROLLBACK FAILED / INTERRUPTED checks. Includes `PREPARE_FAILED`, `VERIFY_FAILED` and `SETTLE_FAILED`. |
| Per step: `restartFailed` (true, or absent) | engine#442: the old version could not be started again after a failure before the swap, so Nextcloud is stopped (`Error`). When this flag is set on the step result, the Console must not say "Nothing changed" or "works on", and must hide Resume until the instance is `Running`. |
| Per step: `operationId` of its `updateApp` op, and `backupOperationId` of its `backupApp` op | To open the existing History entry from "Details", and read Fetch bytes from today's op. |
| Per step: `backupArchive` (Backup Disk id and archive name), set for **every** step, including step 1 | To say which backup protects that step, in "Details" and "Get help". The path backs up before every step. |
| Timestamps: path `startedAt`, step `startedAt` and `endedAt`, `phaseStartedAt`, path `endedAt` | For elapsed times and per-step durations. If the clock is untrusted, the Console only shows durations, so the Engine's own times must be consistent with each other. |
| `stopRequested` (true or false) | To show "Stopping after this step" in every browser. The flag is final. |
| `status` = `running`, `done`, `stopped`, `failed`, `needsHelp` | One field for the overall view. `stopped` covers "by request", "rolled back", "refused", "interrupted", "backup disk missing" and `migrationsPending`; the per-step result and `stopReason` say which. `needsHelp` = a rollback failed. A `migrationsPending` pause keeps the step `done`. |
| `stopReason` (`requested`, `rolledBack`, `refused`, `interrupted`, `backupDiskMissing`, `migrationsPending`) | To pick the right end-state wording without parsing text. `migrationsPending` is NEW. |

**Read: the command result** for start, stop and resume, and for today's one-step `updateApp` (agreed, Steve 15 November 2026): `restartFailed: true` when it applies. The Console needs it in the command result *and* in the path step result, as well as on the operation, because a refusal or a quick failure may leave no operation or path record to read.

**Read: the offer** (NEW, like today's `updateAvailable`): the ordered list of steps the Engine can run now, each with `appId`, `targetVersion`, `major`, `sourceDiskId`/`sourceEngineId` and `estimatedMinutes`. Computed only by the Engine the disk is docked to, and stored on the instance next to `updateAvailable`, so every Engine's Console can show the badge. The Console never works out an upgrade path itself. Duration remains TBD until Atlas's pool timing runs measure real times; `estimatedMinutes` is filled in only then, and until then the Console shows no duration string. The offer lists only steps whose tars and bundles are present and pass their checksums; a kit offer must not include a merely fetchable step.

**Send: three commands** (NEW names are placeholders):

| Command | Why |
|---|---|
| Start path: instance id, the list of step app ids as offered | One confirmation starts all steps. Sending the list makes sure the Engine runs exactly what the person saw. A mismatch is `STALE_OFFER`. |
| Request stop: path id | "Stop after this step". Safe to send twice. Final; it cannot be withdrawn. |
| Resume path: path id (or start again with the remaining steps) | Resume only after a stop, and not while `restartFailed` has left Nextcloud down. The same pre-checks run on the Engine. If the previous stop was `migrationsPending`, work and settle run again before the next step. |

**Refusal and stop codes the Console must word.** All of today's `updateApp` codes, used per step: `NOT_FOUND`, `AMBIGUOUS`, `NOT_DOCKED`, `INVALID_INSTANCE_ID`, `HELPER_OUTDATED`, `BUSY`, `SOURCE_MISSING`, `NO_SUMS`, `DIFFERENT_APP`, `NOT_NEWER`, `MAJOR_NOT_ALLOWED`, `NEEDS_BACKUP`, `BAD_BACKUP_SPEC`, `HOOK_FAILED`, `BACKUP_FAILED`, `INVALID_EXCLUDE`, `BUNDLE_CONTAINS_EXCLUDED`, `NO_SPACE`, `TRANSFER_FAILED`. Plus the error prefixes `ROLLED BACK:`, `ROLLBACK FAILED:` and `INTERRUPTED:`. New codes: `PREPARE_FAILED` and `VERIFY_FAILED` (then snapshot rollback), `SETTLE_FAILED` and `migrationsPending` (paused on the new major, not a rollback), `STALE_OFFER`, `UPDATE_CONTRACT_INVALID`, path already running, `backupDiskMissing`, and `restartFailed` (a flag, not a code: it rides on the existing codes, on the path step result and on the command result).

## 11.8 Console implementation notes

- **Where.** A new adapter `src/store/updatePath.ts` (the only file that knows the path shapes, like `updateApp.ts` today), and a new `UpdatePathControl.tsx` used on the instance row in place of `UpdateAppControl` when the path capability and offer are present.
- **Reuse.** `REFUSAL_TEXT`, `friendlyUpdateError`, `stepLabel`, `isRollbackFailed`, `confirmText` sentences, the `idea/updateProgress` listener and the History entry for "Details".
- **Solid.js rules.** All step lists use `<For>` keyed by step index plus target version (never by array position alone). Every view value (headline, phase line, durations, end state) is a derived signal or `createMemo` from the store. No copied state, except "Not now" in localStorage as today. Elapsed time uses the existing `liveNow()` ticker.
- **Styles** in `main.css` only, reusing the `update-app__*` classes and adding `update-path__*`. No new dependencies.
- **Tests to add.** Unit: path record to view model, one case per row of the end-state table, the `HOOK_FAILED` / `BACKUP_FAILED` / `PREPARE_FAILED` / `VERIFY_FAILED` / `SETTLE_FAILED` / `migrationsPending` / `restartFailed` / `STALE_OFFER` wording, and pre-checks (no linked disk, disk on another Engine, empty `links` meaning "all", busy, Engine offline). Component: confirmation lists 5 steps, each marked `backup first`, with no duration line; button disabled per failed check; progress view after reload from the record only; "Stop after this step" shared across two renders. e2e (Playwright on the pool, idea03/idea04 only): a 2-step path with a forced health failure on step 2, then Resume; a work or settle timeout that pauses with Resume and no rollback.
- **Size.** About 2–3 days of Console work once the Engine shapes are fixed: adapter ~250 lines, component ~300 lines, tests ~400 lines, plus wording review. The `HOOK_FAILED` / `BACKUP_FAILED` texts already ship separately in console PR #214 (issue #213).
- **Order.** Console path work starts after the Engine path record and the prepare / verify / work / settle contracts are fixed, and after [engine#442](https://github.com/koenswings/agent-engine-dev/issues/442) has landed. Until then, today's Update flow can already step through the five releases one at a time (option A), using those hook steps in plain `updateApp`. That can be confirmed on the pool.

# 12. Follow-ups from Ops review

These Ops items are recorded here when they are not already fully decided in the body. They do not change option C, and they do not reopen R1–R6.

- **R10. Stuck-path visibility for Ops.** A path left in `migrationsPending` or `stopped` on a kit that is offline for weeks must be visible to Ops: fleet-state, or a field in the Engine status that the checks read. Otherwise a kit can sit on 33 with pending jobs and nobody knows. A small Ops follow-up is enough; it should not block the work. Owner: Atlas, with Axle if a new Engine status field is needed.
- **R2 policy still open (Axle, Steve):** hold or defer the 05:00 cron reboot while a path holds a lock, or refuse to start a step that would run past a cutoff (`stopReason` such as `window`). Engine deploys already must refuse while a path or journal is active (section 7.5).
- **R5 exact snapshot lifetime (Axle):** after a healthy hop, delete or quarantine the snapshot. The body already requires that five snapshots must not pile up (section 8.1).
- **R7 / R8 / R11 / R13 / R14** are already in sections 8.1, 9 and 10 (cross-major restore and its duration; maintenance-marker hygiene; claim and disk-record rules; measured timings feeding the Engine and the Console; recheck settle and prepare timeouts on a larger fixture before a field plan).
- **R9** is decided (lock released while paused or in `migrationsPending`; re-acquired on Resume, with the forced backup).
- **R12** is named in section 9 as later rollout order, not as approval to go.

# 13. Open questions

Questions 1–8 are Marco's **UNCONFIRMED** list from the 15 November 2026 research, carried forward where they are still test or documentation items. Questions 4, 5 and 9 are decided or answered at desk, with the remaining UNCONFIRMED facts kept as test items. Question 10 and 11 are still decisions this proposal needs. Questions 12 and 13, and the matching Console questions they covered, are resolved as noted. Atlas's Ops §3 questions are answered below where an existing decision already covers them; the rest stay open with an owner.

1. **Exact calendar-day end of life for Nextcloud 31 and 32.** Wiki table: 2026-02 and 2026-09. Admin manual: maintenance ends on the one-year anniversary of the initial release (which would be 25 February 2026 and 27 September 2026 if applied literally), but those day dates are not printed in the wiki end-of-life table. Timeline day dates are published only for 33–35. *(Documentation-only; not covered by the pool test plan.)*
2. **Compatibility of Collabora CODE 24.04.13.2** with `richdocuments` 9.2.3 / 10.3.3 / 11.1.3 / 12.0.2 and Nextcloud 32–35, **on a Pi**. Desk research (Kid, 15 November 2026): **COMPATIBLE** on the documented CODE ≥ 21.11 floor; no source marked the pin incompatible. Still **unproven on a Pi**. The pin lags 24.04.20.4 (23 October 2026). Covered by Kid's pool test plan, item 2.
3. **Whether MariaDB 11.7.2 is accepted in practice** on Nextcloud 31–35. It is not in any official supported list. Covered by Kid's pool test plan, item 3.
4. **ANSWERED at desk (Kid's hop-34 note, 15 November 2026).** No admin-facing breaking changes are documented for Nextcloud 34. The missing "Upgrade to Nextcloud 34" critical-changes page is intentional (susnux, 8 October 2026, [nextcloud/documentation#15244](https://github.com/nextcloud/documentation/issues/15244): there are no critical changes, as with 29). See section 8.5. **UNCONFIRMED test items:** how the new `office` overview sits next to Collabora, and whether the always-enabled `appstore` is noisy on an offline kit. A live 33→34 upgrade is still unconfirmed on a Pi.
5. **DECIDED.** `serverid` stays unset in 3.0. The official Docker image does not set it. Nextcloud 33 recommends a configured server ID but does not require one to upgrade or to run a standalone instance; leaving it unset is an info message, not a hard fail of `occ upgrade`. A stable `NC_serverid` (integer 1–511, not 0, not -1) is a later item. Live confirmation on a Pi that the 32→33 upgrade is not blocked with `serverid` unset remains **UNCONFIRMED** and is a test item. See section 8.4 and Kid's hop-33 prep.
6. **Complete list of default bundled core apps**, and any additions or removals between 31 and 35, other than the AppAPI default noted in the 32 upgrade page and the continued presence of `files_external`. Covered by Kid's pool test plan, item 6. For 34, the shipped-json comparison is already done at desk (`office`, `files_lock`, and `appstore` always-enabled; nothing removed); their live behaviour on a Pi is still a test item (section 8.5).
7. **Undocumented `files_external` occ or behaviour changes** across 32–35. None were found in official upgrade notes. Only partly covered by the pool test plan (what our hooks, tests and roles hit).
8. **31.0.0 and 32.0.0 headings on nextcloud.com/changelog** were not present on the 15 November 2026 fetch (end-of-life majors appear to have been dropped from the page). Their release dates are taken from the wiki, not re-confirmed on the changelog. *(Documentation-only.)*
9. **DECIDED.** No MariaDB 11.8 in the 33 hop; keep 11.7.2 through 3.0. 11.8 becomes a separate hop after 33 is healthy, using `MARIADB_AUTO_UPGRADE=1` (and a new App major if the series rule requires it). See section 8.2. Time taken, whether `mariadb-upgrade` from 11.7.2 to 11.8 is clean, and whether Nextcloud stays healthy remain **UNCONFIRMED** test items for that later hop.
10. **When, if at all, to take Collabora CODE 26.04** ([app-nextcloud#34](https://github.com/koenswings/app-nextcloud/issues/34)). Only if 24.04.13.2 fails a hop, or as a planned bump at a chosen major? The security lag on 24.04.13.2 versus 24.04.20.4 is noted, and is not by itself a decision to bump.
11. **Is option C accepted for the field**, or is five separate `updateApp` confirmations (option A alone) enough? This proposal recommends C, and the Design Review inputs above are written for C. Work on the path-runner still waits on this being accepted for the field. The hop proofs can start without it, using prepare, verify, work and settle in plain `updateApp`.
12. **RESOLVED.** After Health, an optional **verify** runs once (exit 0 passes; anything else is `VERIFY_FAILED` and rolls back like Health). An optional **work** step may then run `cron.php`; a non-zero exit or timeout leaves the step `done` and pauses the path with `migrationsPending`, with no rollback. **settle** stays a read-only probe, polled with `docker compose exec -T` (exit 0 settled, exit 3 poll again, any other exit is `SETTLE_FAILED`). A settle timeout or error also pauses with `migrationsPending` and does not roll back. Resume runs work and settle again before the next step. The Console phase `migrations` covers work and settle together. See section 7.2.
13. **RESOLVED.** `idea_usage` stays at **1.0.0** with a widened Nextcloud range as majors are proven. Any version bump is decided at release.

Also resolved, matching the questions above and the Console / wording review:

- Pixel's questions 1, 2, 3, 4, 6 and 7 on the path record, backup phase, migrations timeout, untrusted clock, mid-path restart, prepare phase name, and where the offer is computed: answered in sections 7.3 and 11.7. The path runner forces a fresh backup on every step, with no one-hour skip; plain `updateApp` is unchanged.
- engine#442: `restartFailed` is in both the path step result and the command result, as well as on the op and the Error.
- After any stop, Resume is the only way forward (no "Keep going"). Each path step records `backupArchive` (Backup Disk id and archive name).
- One button, no typed name; Stop uses the same role as Update; the path is allowed with no uplink.
- A backup before every step, including the first small one.
- Duration: **TBD (Atlas's pool timing runs will measure real times).** No operator-facing duration string until then.
- "Nextcloud is unavailable while the update runs" (the whole path, not only the current step).
- Resume only after a stop; a stop request is final (no "Keep going"). A work or settle timeout pauses with Resume rather than rolling back (`Paused after step <n>. Nextcloud is finishing its background work.`; step line `done, waiting for background work.`).
- A small `Code:` line in Get help. OK on Get help hides the panel in this browser only.
- A short guide page only after the path is proven.
- Fixed labels: refused `didn't start, nothing changed`; rollback-failed `didn't work, couldn't switch back`; Resume title `Continue updating Nextcloud from <last good> to <to>?`; between steps `Getting the next step ready.` The `restartFailed`, stale-offer, path-already-running, and Fetch-paused strings are in section 11.

Pixel's current open questions (updated Console section, 15 November 2026), with answers already given in this Design Review where they exist:

1. Is the pre-update backup shown as a phase of the step, or a separate `backupApp` op the Console must link by id? **Already answered (Axle):** it is phase `backup` of the step, and the step also carries `backupOperationId` and `backupArchive` (disk id and archive name) for every step, including step 1.
2. Is there a visible `migrations` phase, and what code does a timeout end with? **Already answered (Axle / Q12):** yes; work and settle share the Console phase `migrations`. A timeout or error leaves the step `done` and pauses the path with `migrationsPending`, with no rollback.
3. After an Engine restart mid-path, does the path record end as `stopped` with `interrupted`, so Resume is offered, and never auto-continue? **Already answered (Axle):** yes.
4. Where does Kid's `custom_apps` tarball step run? **Already answered (Axle):** in the `prepare` phase, between Swap and Start.
5. Is the offer computed for every Engine that sees the instance, like `updateAvailable`? **Already answered (Axle):** it is computed only by the Engine the disk is docked to, and stored on the instance next to `updateAvailable`, so every Engine's Console can show the badge.
6. Once pool timings exist, should the duration line be one total, or "about X per step"? **Still open.** Until those timings exist, the Console shows no duration string.
7. Do the teacher and operator guides need a short "if the update stops" page that Get help can point to? **Already decided:** yes, but only after the path is proven.

Atlas's Ops review §3, answered where an existing decision already covers them:

- **§3.5 Hard-reset testing. ANSWERED (Steve).** A forced reboot of a claimed pool Pi (idea03 or idea04 only; never golden idea01 or client idea02) is allowed. A real power cut needs someone at the pool, so it is a Koen item on idea#375, presented only when he is ready. See section 10, item 10.
- **§3.9 Hop images. ANSWERED.** The pool proof uses the official digests, tagged locally, as section 10 already says, and does not wait on a `koenswings/nextcloud:*` retag. That retag still needs Koen's YES, as for #36.
- **§3.8 Pi model and memory.** Not left open as a product question: Atlas records the model, RAM and swap in Run 1, so later kit timings can be compared.

Still open from Atlas's Ops §3, with owners (nothing here is invented):

- **§3.1 Kit entry version (Kid, Axle).** What does the path offer on a kit that still has a SHA `x-app.version`? Does it refuse, or put 1.7 first as step 0? The proposal must not assume that `updatesFrom: [1]` matches a SHA version.
- **§3.2 Fixture size (Steve).** 300 small files and 3 users is fine for functional checks, but not for timing. Atlas proposes a second timing fixture of about 5–10 GB, 30 users and about 20k files. The real figure would come from a read-only `du` of a kit's Nextcloud data, which only happens under claim with Koen's OK (idea#375, presented only when he is ready).
- **§3.3 05:00 reboot (Axle, Steve).** Option (a) hold or defer the cron reboot while a path holds a lock, or (b) refuse to start a step that would run past a cutoff? See section 7.5.
- **§3.4 Snapshot lifetime after a healthy hop (Axle).** Delete, or quarantine with `mv`? Five kept snapshots are a disk risk. See section 8.1.
- **§3.6 Production and golden (Steve).** Does production `idea` or golden `idea01` host a Nextcloud instance that would be in scope at all?
- **§3.7 Image cleanup owner (Axle, Steve).** The Engine after a healthy path, or an Ops step under claim? Removal is by digest only, never by prune (section 8.1).

Still open, and not invented here:

- Operator wording for the new `prepare` and `verify` phases (not yet in Marco's phase list).
- The duration line, until Atlas's pool timing runs measure real times, and then whether that line is one total or also "about X per step" (Pixel's question 6).
- Option C is approved from the Ops side; whether it is accepted **for the field** remains Q11.

# 14. Sources

1. [Maintenance and Release Schedule (nextcloud/server wiki)](https://github.com/nextcloud/server/wiki/Maintenance-and-Release-Schedule) — fetched 15 November 2026; page dated 13 November 2026.
2. [Maintenance and release schedule — Nextcloud 35 admin manual](https://docs.nextcloud.com/server/stable/admin_manual/release_schedule.html)
3. [How to upgrade — Nextcloud 35 admin manual](https://docs.nextcloud.com/server/stable/admin_manual/maintenance/upgrade.html)
4. [nextcloud.com/changelog](https://nextcloud.com/changelog/) — fetched 15 November 2026.
5. System requirements: [31 HTML](https://docs.nextcloud.com/server/31/admin_manual/installation/system_requirements.html), [31 source (`stable31`)](https://raw.githubusercontent.com/nextcloud/documentation/stable31/admin_manual/installation/system_requirements.rst), [32](https://docs.nextcloud.com/server/32/admin_manual/installation/system_requirements.html), [33](https://docs.nextcloud.com/server/33/admin_manual/installation/system_requirements.html), [34](https://docs.nextcloud.com/server/34/admin_manual/installation/system_requirements.html), [35](https://docs.nextcloud.com/server/35/admin_manual/installation/system_requirements.html)
6. Upgrade notes: [to 31](https://docs.nextcloud.com/server/31/admin_manual/release_notes/upgrade_to_31.html), [to 32](https://docs.nextcloud.com/server/32/admin_manual/release_notes/upgrade_to_32.html), [to 33](https://docs.nextcloud.com/server/33/admin_manual/release_notes/upgrade_to_33.html), [to 35](https://docs.nextcloud.com/server/35/admin_manual/release_notes/upgrade_to_35.html). 34 admin page missing; [34 release-notes index](https://docs.nextcloud.com/server/34/admin_manual/release_notes/index.html); [34 developer upgrade notes](https://docs.nextcloud.com/server/stable/developer_manual/release_notes/previous/upgrade_to_34.html)
7. [Official Nextcloud Docker image README](https://github.com/nextcloud/docker/blob/master/README.md) and [raw](https://raw.githubusercontent.com/nextcloud/docker/master/README.md); [versions.json](https://raw.githubusercontent.com/nextcloud/docker/master/versions.json); Dockerfiles for [32](https://github.com/nextcloud/docker/blob/master/32/apache/Dockerfile), [33](https://github.com/nextcloud/docker/blob/master/33/apache/Dockerfile), [34](https://github.com/nextcloud/docker/blob/master/34/apache/Dockerfile), [35](https://github.com/nextcloud/docker/blob/master/35/apache/Dockerfile) and historical [31](https://github.com/nextcloud/docker/blob/614be285/31/apache/Dockerfile); [remove EOL 31](https://github.com/nextcloud/docker/commit/dc4b5bc546777e5ce22a25c66eb3df415a9d0a42)
8. Docker Hub tags for `library/nextcloud`: [31-apache](https://hub.docker.com/_/nextcloud/tags?name=31-apache), [31.0.14-apache](https://hub.docker.com/_/nextcloud/tags?name=31.0.14-apache), [32-apache](https://hub.docker.com/_/nextcloud/tags?name=32-apache), [32.0.15-apache](https://hub.docker.com/_/nextcloud/tags?name=32.0.15-apache) (API checked 15 November 2026)
9. [Nextcloud Office on the App Store](https://apps.nextcloud.com/apps/richdocuments); [richdocuments README](https://github.com/nextcloud/richdocuments/blob/main/README.md); info.xml for [v8.8.3](https://raw.githubusercontent.com/nextcloud/richdocuments/v8.8.3/appinfo/info.xml), [v9.2.3](https://raw.githubusercontent.com/nextcloud/richdocuments/v9.2.3/appinfo/info.xml), [v10.3.3](https://raw.githubusercontent.com/nextcloud/richdocuments/v10.3.3/appinfo/info.xml), [v11.1.3](https://raw.githubusercontent.com/nextcloud/richdocuments/v11.1.3/appinfo/info.xml), [v12.0.2](https://raw.githubusercontent.com/nextcloud/richdocuments/v12.0.2/appinfo/info.xml)
10. Office admin docs: [installation](https://docs.nextcloud.com/server/stable/admin_manual/office/installation.html), [migration](https://docs.nextcloud.com/server/stable/admin_manual/office/migration.html) (the 21.11 floor is also in the 32, 33, 34 and 35 Office migration pages)
11. IDEA App pins: `koenswings/app-nextcloud` `origin/main` `696a299` — `app.yaml`, `compose.yaml`, `bundled-apps/SHA256SUMS`, `idea_usage/appinfo/info.xml`, `docs/releases.md`, and the install hooks.
12. Engine `updateApp`: `koenswings/agent-engine-dev` `origin/main` `da08956` — `src/data/UpdateApp.ts`, `src/data/UpdateAppPolicy.ts`, `docs/COMMANDS.md`; design: `proposals/2026-10-28-update-app.md` (idea#351). [engine#442](https://github.com/koenswings/agent-engine-dev/issues/442) (`restartFailed` when the old version cannot be restarted, also in the command result).
13. Marco's research note, 15 November 2026, official Nextcloud sources only.
14. Design Review, 15 November 2026: Axle's Engine review and addendum (contract gaps 1–14); Kid's hop-32, hop-33 and hop-34 prep (including the Q4 admin-changes note and the explicit 34.0.6 index pin), contract gaps, and pool test plan for items 2, 3, 5 and 6; Pixel's Console section (updated 15 November 2026, about 20:43, Europe/Brussels) and wording review; Marco's operator-facing wording (updated 15 November 2026, 20:41, Europe/Brussels).
15. Ops review, Atlas, 15 November 2026, 21:29 (Europe/Brussels): verdict approve with changes (R1–R14). Sunny-robin read-only check under claim, 15 November 2026, 17:34 (Europe/Brussels), for the field starting point.

Date drafted: **15 November 2026** (Europe/Brussels). This revision: **15 November 2026**, 21:34 (Europe/Brussels): Ops review folded (approve with changes).
