# Console "Set up demo" button: demo Kolibri and Nextcloud on any Engine

**Author:** Steve (Lead Bot)
**Date:** 2026-10-16
**Status:** Draft (design review)
**Issue:** koenswings/idea#233

## Summary

An operator presses **Set up demo** in the Console admin area. The Engine installs two extra, clearly labelled instances, **Kolibri (Demo)** and **Nextcloud (Demo)**, next to any real Kolibri or Nextcloud already on that Engine. It downloads the demo content (internet is allowed), seeds the demo school and accounts, and starts both. **Remove demo** removes only these two demo instances and their data. The real school apps are never touched.

No IDEA-DEMO disk is distributed. A school, a trainer or Justice can turn the demo on with a button and no shell access.

## 1. Koen's decisions (2026-10-16)

1. No demo disk is distributed to schools.
2. A button in the Console admin area creates the demo setup. It may need an internet connection.
3. It installs separate instances **Kolibri (Demo)** and **Nextcloud (Demo)**.
4. They may go **alongside** an existing real Kolibri or Nextcloud on the same Engine.
5. They are clearly marked as demo: the instance name, and inside the app a DEMO banner and facility name.
6. They are preloaded with the demo content and the demo school and accounts.
7. Accounts: Kolibri learners sign in with their username only (`learner_can_login_with_no_password`), with a stored fallback password `<name>911!`. Teacher and admin use `<name>911!`. Nextcloud demo users use `<name>911!`.
8. A **Remove demo** button removes only the demo instances.

## 2. Earlier agreements found

I searched koenswings/idea issues and PRs, `proposals/` and `CONTEXT.md`. There is **no earlier written agreement on a demo button** that installs real instances. What exists:

- **Console demo mode** ([2026-10-14-teacher-usb-sticks.md](2026-10-14-teacher-usb-sticks.md) §8.4): Settings → Demo mode toggle (`SettingsPanel.tsx`, `src/store/demoMode.ts`). It loads a simulated store from `src/mock/mockStore.ts` and **installs nothing on a Pi**; it is never active on the Engine-served production Console. This proposal is a different thing and must not reuse the name "demo mode" for it (see §9, Q1).
- **app-kolibri `demo/README.md`**: "For demos (an IDEA-DEMO disk is docked, or the operator asks for demo mode)". Neither trigger is implemented; the seed is run by hand.
- **#208**: the demo content should become country-independent (Zimbabwe content accepted for now).
- Koen's chat decision of 2026-10-16 (this proposal), which replaces the IDEA-DEMO disk idea.

## 3. How it works today

**Kolibri seed** (koenswings/app-kolibri `demo/provision-demo.sh`, main 5833a12, and PR #6 at bf86413, Ready for review, not merged):

- Run by hand on the Pi: `docker compose stop kolibri`, `demo/provision-demo.sh ./data/kolibri`, `docker compose start kolibri`.
- One-shot `docker run --rm --network none` of the Kolibri image against the stopped instance's data dir. Refuses (exit 3) if a running container mounts that dir. Never uses `kolibri manage shell`.
- `provisiondevice` creates **IDEA Demo School** (preset `formal`, admin `admin`/`admin911!`); PR #6 adds `--facility_settings {"learner_can_login_with_no_password": true}`.
- `bulkexportusers` + `build_users_csv.py` + `bulkimportusers` create class Grade 5, `teacher1` (coach) and `learner1..3` from `demo/users.csv`. Idempotent, never deletes.
- Caveat in the README: on a device already provisioned with another facility, it **adds** IDEA Demo School and makes it the default facility. This is why the demo must be a **separate instance**, never a seed into the real Kolibri.
- Lessons are not seeded (no safe command in 0.15.5); a teacher creates them by hand.

**Kolibri content:** `agent-app-dev demo/idea-demo/` (`MANIFEST.json`, `fetch.sh`/`fetch.py`, `build.py`, `CREDITS.txt`) fetches publisher sources and builds the demo channels; the IDEA-DEMO stick carries the result, imported through the channel builder.

**Nextcloud accounts:** app-nextcloud `docker-entrypoint-hooks.d/before-starting/20-idea-accounts.sh` already creates seed users with `<user>911!` (`IDEA_NC_SEED_USERS`, default `teacher1:teachers learner1:learners`) in **every** instance, sets password policy minLength 9, and never resets existing passwords. There is no demo content seeding for Nextcloud.

**Engine install** (agent-engine-dev `src/data/InstallApp.ts`, `Commands.ts`): `installApp <appId> <targetDiskId> [--source <diskId>] [--name <instanceName>]`. It routes to a local bundle on a docked disk or a GitHub clone when online (`hasInternet()` probe), and builds the instance via `buildInstance`. Instance names are already free, so multiple instances of one app are possible.

**Console** (agent-console-dev): `EmptyDiskPanel.tsx` offers Install App (appDB → `installApp`, 5-minute result timeout); `OperatorManagement.tsx` and `SettingsPanel.tsx` are the admin area.

## 4. What the operator experiences

1. Console → Settings (admin) → **Demo** → **Set up demo**. A dialog says what will happen: "Installs Kolibri (Demo) and Nextcloud (Demo) on *engine*, disk *X*. Your school's apps are not changed. Needs internet for about N MB." The operator picks the target disk (default: the disk with most free space).
2. A progress view shows the steps: install apps, download content, create demo school and accounts, start.
3. The app list shows **Kolibri (Demo)** and **Nextcloud (Demo)** with an orange DEMO badge. Inside Kolibri the facility is **IDEA Demo School (DEMO)** and Nextcloud shows a DEMO banner.
4. **Remove demo** (same place, confirm dialog naming exactly the two instances) stops and deletes only them.

## 5. Approach options

**Option A: Engine command `setupDemo` running app-provided demo hooks (recommended).**
The Console sends one command, `setupDemo <targetDiskId>` (and `removeDemo`). The Engine:
1. `installApp kolibri-1.0 <disk> --name kolibri-demo` and `installApp nextcloud-1.0 <disk> --name nextcloud-demo` (online GitHub route or local bundle).
2. Marks both instances `demo: true` in the Store (new field), with display names "Kolibri (Demo)" / "Nextcloud (Demo)".
3. Runs each app's declared demo hook, e.g. `app.yaml: demo: { hook: demo/provision-demo.sh, needsStopped: true }`. Kolibri: fetch content, import channels, provision. Nextcloud: env `IDEA_NC_SEED_USERS` for the demo users plus a DEMO theming name and banner.
4. Starts both and reports progress per step to the Console.

Pro: one atomic, resumable operation; works from any Console; apps own their own demo knowledge; reuses `installApp`. Con: new Engine command and a new `app.yaml` field.

**Option B: Console-driven sequence.** The Console chains existing commands (`installApp` twice, then a generic `runAppScript` command, then `startInstance`). Pro: less Engine code. Con: the sequence breaks if the browser closes halfway; a generic "run script" command is a larger security surface than a dedicated demo hook; harder to make Remove demo safe.

**Option C: separate "IDEA Demo" app** that bundles both. Rejected: it duplicates the Kolibri and Nextcloud apps and drifts from them.

Recommendation: **A**.

## 6. Where the demo content comes from

- **Internet download (recommended for v1):** the Kolibri hook downloads a prebuilt, versioned, checksummed demo channel export (the output of `agent-app-dev demo/idea-demo`, published as a GitHub release asset) and imports it with `kolibri manage importchannel/importcontent disk` in a one-shot container. Fast and deterministic.
- **Channel builder on the Pi:** run `fetch.sh` + the builder on the Engine. Rejected for v1: slow, depends on many publisher sites staying up, and needs the builder installed.
- **Optional local source:** if a disk or USB stick already holds the export (e.g. an existing IDEA-DEMO stick), the hook uses it with no internet, just as `installApp` already prefers a local bundle. This keeps a technician's offline path without distributing disks.
- Nextcloud demo files (a few sample documents in a "Demo class" folder) come from the same release asset.
- #208 (country-independent content) applies to this pack.

## 7. Offline behaviour

- The Console checks the Engine's internet probe before starting. With no internet and no local source, the button is disabled with: "Set up demo needs internet. Connect the Engine, or insert a disk with the IDEA demo pack."
- Every step is idempotent (as `provision-demo.sh` already is), so a step that fails mid-way can be retried with **Set up demo** again; it resumes rather than duplicating.
- Once set up, the demo runs fully offline, like any other instance.

## 8. Separation and safety

- **Separate instances only.** The demo never seeds into a real Kolibri or Nextcloud, because `provisiondevice` on a provisioned device makes the demo facility the default (README caveat).
- **Hooks are scoped to the demo instance's own data dir**, and the Engine refuses to run a demo hook on an instance without `demo: true`.
- **Remove demo** deletes only instances with `demo: true` created by `setupDemo`, by instance id, after a confirm dialog that names them. It never deletes by app type or name pattern.
- Ports and hostnames come from normal instance allocation, so they can't collide with the real apps.
- Clear marking everywhere: instance name, Console badge, Kolibri facility name "IDEA Demo School (DEMO)", Nextcloud theming name "Nextcloud (Demo)" and a banner.
- Demo passwords are the public `<name>911!` defaults. They are never written into the Console UI or documents; the tutorial appendix lists account names only, as today.
- Remove demo also cleans up the downloaded demo pack.
- The real Nextcloud's default seed users (`teacher1`, `learner1`, created by `20-idea-accounts.sh` in every instance) are not part of this proposal, but see Q6.

## 9. Affected domains and work

| # | Domain / bot | Work |
|---|---|---|
| 1 | Engine (agent-engine-dev) | `setupDemo` / `removeDemo` commands, `demo: true` instance field, step progress, demo-hook runner (stopped instance, one-shot, scoped data dir), refuse on non-demo instances. |
| 2 | App (app-kolibri, Kid) | `app.yaml` demo hook; `provision-demo.sh` gains content import from the demo pack; facility name with "(DEMO)"; PR #6 behaviour (no-password learners, `<name>911!` fallback). |
| 3 | App (app-nextcloud) | Demo hook: seed `admin`, `teacher1`, `learner1..3` with `<name>911!`, DEMO theming and banner, sample files. |
| 4 | Content (agent-app-dev) | Publish the demo pack as a versioned, checksummed release asset (#208 applies). |
| 5 | Console (agent-console-dev, Pixel) | Settings → Demo section: Set up demo (target disk, internet check, progress), Remove demo, DEMO badge on instances. Not to be confused with the mock "Demo mode" toggle. |
| 6 | Docs (Marco) | Replace the tutorial's "Appendix: activating the demo setup" (script) with the button, once live. |

## 10. Tests

- Engine unit: `setupDemo` is idempotent; `removeDemo` touches only `demo: true` instances; hook refused on a non-demo instance.
- App integration: on an Engine with a real Kolibri holding its own facility, set up the demo; the real facility, users and default facility are unchanged; demo logins work (admin/teacher1 with `911!`, learner1 username only).
- Offline: button disabled without internet and without a local pack; works with a local pack.
- Remove demo leaves the real instances running and unchanged.

## 11. Open questions

1. **Naming:** the Console already has a mock "Demo mode" toggle. Rename that (e.g. "Preview mode") or call this feature "Demo apps"?
2. **One demo per Engine or per network?** Should the button refuse if a demo already exists on another Engine in the network?
3. **Who may press it:** any operator, or admin only?
4. **Lessons:** Kolibri 0.15.5 has no safe command to seed lessons. Accept "teacher creates lessons" in the demo, or find a supported route?
5. **Content host:** GitHub release asset on agent-app-dev, or another host? Size budget for school internet?
6. **Real Nextcloud seed users:** `20-idea-accounts.sh` creates `teacher1`/`learner1` with `911!` in every real Nextcloud too. Keep that, or limit seed users to the demo instance?
7. **Existing demo setups** (wizardly-hugle, idea03 `kolibri-demo`): convert them to `demo: true` instances, or remove and recreate with the button once it ships?
8. **Kiwix (Wikipedia):** include a small demo Kiwix instance too, or only Kolibri and Nextcloud?
9. **Demo expiry:** should the demo remind the operator to remove it after some days, or stay until removed?

Timing: not built before Justice's trip. For Monday the tutorial says the demo was prepared in advance.
