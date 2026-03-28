# Proposal: Initial Data Storage for App Disk Deployments

**Proposed by:** Atlas (operations-manager)
**Date:** 2026-03-28
**Status:** Proposed
**Parent:** `2026-03-28-app-dev-agent.md` (Kit agent proposal)

---

## Problem

Some IDEA apps require initial data to function or to be useful from the moment a teacher
first plugs in an App Disk. Examples:

- **Nextcloud** — Marco's presentations must be present in a designated folder on every
  deployment so teachers and coordinators can access them immediately
- **Kolibri** — may include a pre-loaded channel with curriculum content
- **Kiwix** — the ZIM file (offline Wikipedia, etc.) is the entire content; it is data,
  not just configuration

The question is: where does this initial data live, who owns it, and how does it get onto
a deployed disk?

---

## Approaches

### Option A — Baked into the Docker image

Initial data is included in the Docker image itself. The image ships with the data already
in place; no separate step is needed at disk-build time.

**Pros:** Simple deployment; data is always in sync with the image version; no extra files
on the disk.

**Cons:** Images become very large (impractical for large datasets like ZIM files or media
libraries); rebuilding the image is required every time data changes (e.g. new presentations
from Marco); data is not easily inspected or updated without rebuilding.

**Suitable for:** Small, stable, code-like data (configuration defaults, static assets
already needed by the app).

---

### Option B — Init container on first start

A separate Docker service in `compose.yaml` runs once on first startup, seeds the volume
with initial data, then exits. The init container pulls data from a known location on the
disk (e.g. `apps/<appId>/init-data/`).

**Pros:** Clean separation of app and data; init logic is versioned alongside the app;
can be conditional (only runs if volume is empty).

**Cons:** Adds a service to the compose file; requires careful ordering and health checks;
data still has to come from somewhere (the disk or the image).

**Suitable for:** Database seed data, structured initial state (e.g. Nextcloud user and
folder setup).

---

### Option C — Disk-level data directory (recommended for most cases)

Initial data lives on the App Disk, in a known directory alongside `compose.yaml`. At
first start, the app (or an init container) copies it into the persistent volume. After
that, the disk copy is no longer needed and the volume is the live state.

```
apps/
  kolibri-1.0/
    compose.yaml
    init-data/          ← initial data; copied to volume on first start
      channels/
      ...
  nextcloud-1.0/
    compose.yaml
    init-data/
      presentations/    ← Marco's presentations; present on every deployment
      ...
```

**Pros:** Data travels with the disk — the disk is the complete, self-contained unit;
no network access required; Kit controls what is on the disk at build time; inspectable
and replaceable by coordinators in the field.

**Cons:** Disk capacity must accommodate the data; Kit must include data when building the
disk, which requires a handoff from Marco for presentation files.

**Suitable for:** Marco's presentations (Nextcloud), pre-loaded curriculum content (Kolibri),
any data that should be present at the first plug-in.

---

### Option D — ZIM / large binary files as top-level disk assets

For very large files (ZIM files for Kiwix, which can be multiple GB), they are too large
to embed in `init-data/` alongside the compose files. They live at the top level of the
disk or in a dedicated `content/` directory, and the app is configured to read from that
path directly.

```
/disks/sda/
  META.yaml
  content/
    wikipedia-en-2026.zim   ← Kiwix reads this directly; no copy step
  apps/
    kiwix-1.0/
      compose.yaml           ← mounts content/ as read-only volume
```

**Pros:** No copy step needed; disk is the authoritative location; works for files of any size.

**Cons:** Requires the app to read from a path controlled by IDEA rather than its own volume;
less portable.

**Suitable for:** ZIM files, large media libraries, any content too large to copy into a volume.

---

## Recommendation

Use **Option C** as the default for all apps. Use **Option D** for very large content files
(Kiwix ZIM files and similar). Option B only where an app genuinely requires database seeding
that cannot be done via file copy (assess per app). Avoid Option A for data — reserve it
for small static assets that are truly part of the application code.

### Marco's presentations (Nextcloud)

Apply Option C. Kit's `build-instance` script for Nextcloud includes a step that copies
the current set of Marco's presentations from a designated location in the `agent-programme-manager`
repo (or a dedicated folder in the idea org root) into `apps/nextcloud-<version>/init-data/presentations/`.

Marco is responsible for keeping that source folder current. Kit picks them up at
build time — no manual step for Kit beyond running `build-instance`.

**Open question for this proposal:** Where exactly does Marco's canonical presentation
folder live? Options:
- `agent-programme-manager/presentations/` (Marco's workspace, already version-controlled)
- `idea/content/presentations/` (org root, more neutral)

Recommendation: `agent-programme-manager/presentations/` — Marco owns the content; the
path makes that ownership explicit.

---

## Impact

- **Kit:** implements the init-data convention in each app repo; `build-instance` includes
  data packaging
- **Marco:** maintains `presentations/` folder; notifies Kit when it changes so Kit can
  rebuild the Nextcloud disk
- **Axle:** no change — engine processes the disk as normal; it does not need to know
  about init-data
- **Each app repo:** gains an `init-data/` directory (where applicable)
