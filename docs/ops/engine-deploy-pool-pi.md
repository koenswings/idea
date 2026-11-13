# Engine deploy on a pool Pi (option 2: keep local config and store identity)

**Status:** Authoritative (procedure in use since 2026-10-13; store-identity step added 2026-10-14) · **Maintained by:** Atlas (Ops)
Script: [`tools/fleet/deploy-engine-pi.sh`](../../tools/fleet/deploy-engine-pi.sh), tests: `tools/fleet/deploy-engine-pi.test.sh`.

## 1. What option 2 is
A pool Pi (idea03, idea04; golden idea01 runs the same way and stays on the shared store) runs the Engine from a git checkout in
`/home/pi/idea/agents/agent-engine-dev` with **local, uncommitted edits** to tracked files:
`config.yaml`, `pm2.config.cjs` and the files in `store-identity/`. Option 2 (Axle, 2026-10-13)
keeps those edits across a checkout of a new Engine commit: save, discard, check out, restore.
Never on idea02, wizardly-hugle or Milkwise; the script refuses other hosts.

## 2. Why store-identity must be saved too
The repo's tracked `store-identity/store-url.txt` and `store-identity/command-log-url.txt`
hold the image defaults, which are the **kit store (`3Vvv…`, idea#452)**. Discarding local edits
(or `git checkout -f`) before a checkout puts those defaults back. A restarted pool Engine
would then join the kit store. (When the default was still 4GQm, this happened on idea04 on
2026-10-14, joining idea02's store for about one minute; fixed by restoring the files and
restarting; idea02's Engine was stopped.)
The pool store is `automerge:2VroE…` (see `fleet-state.json`) for idea01/03/04. A pool deploy
requires that store and refuses anything else, including 3Vvv.

## 3. Procedure
Run from the ops box, one Pi at a time:

    ssh idea04 'bash -s -- <tip-sha> --fetch <branch>'        < tools/fleet/deploy-engine-pi.sh   # checks only
    ssh idea04 'bash -s -- <tip-sha> --fetch <branch> --yes'  < tools/fleet/deploy-engine-pi.sh

`--dry-run` (same as leaving out `--yes`) is read-only and lists the sha256 of every file it would keep and the
helper changes it would make. Kept always, whatever `git status` shows (skip-worktree included): `config.yaml`,
`pm2.config.cjs`, all of `store-identity/` and `~/.idea-local`, restored byte-for-byte and sha256-checked; a repo
default store (`3Vvv…`) on a pool Pi aborts (kits are expected to be on that default). After the build it runs `./install-root-helpers` (flash/app-data/erase,
`idea-usage-settings` and `idea-usage-export` helpers and sudoers), checks each helper's sha256
against `script/build_image_assets/` and `visudo -c`, then `pm2 restart engine`
and `pm2 save`, and re-checks the store after the restart. An Engine commit without `install-root-helpers` only warns.

Hosts: pool Pis idea01/03/04 expect `automerge:2VroE…`; kit Engines sunny-robin, happy-zebra, kind-panda expect the one
shared kit store `automerge:3Vvvigx8bKcuwKALqMVz85GhDqrk` (kits only after Steve's GO naming the Engine). Any other
host is refused; a store mismatch aborts before anything changes.

From the box, prefer `tools/fleet/deploy-engine-remote.sh <ts-ip> <tip-sha> [--fetch main] [--dry-run|--yes] [--allow-midnight]`: it holds a
per-host box lock (`/tmp/idea-deploy-<host>.lock`) and the script holds `/tmp/idea-deploy.lock` on the Pi; either busy
exits 75 without changing anything (two routines or two bots can no longer deploy the same Pi at once). If HEAD already
equals the tip, the helpers (including `idea-usage-settings` and `idea-usage-export`) match the
repo assets, pm2 `engine` is online, **and the running process sha equals the tip**, it prints `already on <sha>, skipping` and exits 0.
The running sha is `dist/build-info.json`'s commit only when that process started at or after the file was written
(idea#512). If HEAD and dist are already the tip but the running Engine is older, the script does not skip: it continues and restarts.
A command-log rotation during the build (`store-identity/command-log-url.txt` or `command-log-day.txt` changes while
`store-url.txt` is unchanged) is logged and accepted; the live URL is kept and the old one is never restored. A change
to the store URL itself still aborts before `pm2 restart`. Deploys between 23:55 and 00:05 local time are refused unless
`--allow-midnight` is passed (the window in which the daily command log rotates).
A missing or stale usage helper (the idea03 idea#412 case) is not skipped: `install-root-helpers`
runs and each helper is sha256-checked against the tip.
Temperature guard: before each step (install, build, root helpers, restart) above 75 C it pauses, polling every 30 s
until below 65 C, and prints the peak per step at the end. The Console is not deployed by this script (build it
separately with `tools/fleet/build-console-pi.sh`, which keeps `dist/hidden-instances.json`, with the same 75/65 C rule).

1. **Guard:** host is a pool Pi; `store-url.txt` is the expected store (2VroE); only
   `config.yaml`, `pm2.config.cjs` and `store-identity/*` have tracked local edits.
2. **Save** `config.yaml`, `pm2.config.cjs` and the whole `store-identity/` folder
   (`store-url.txt`, `command-log-url.txt`, `store-template.json`, anything else) to
   `/home/pi/quarantine/engine-deploy-<ts>/`, plus the old `HEAD`.
3. **Discard** the local edits of exactly those files (`git checkout -- …`).
4. **Check out** the tip (`git checkout --detach <tip>`; no `-f`, no reset).
5. **Restore** every saved file and check each one is byte-identical to the saved copy.
6. **Verify the store:** `store-url.txt` must equal the expected store, otherwise abort.
7. `pnpm install --frozen-lockfile`, `pnpm build`, then the **DHCP vendor class**
   (idea#284): when the tip has `script/build_image_assets/idea-dhcp-vendor-class`, install
   it to `/usr/local/sbin/idea-dhcp-vendor-class` (root, 0755), run it (idempotent) and, if
   NetworkManager is active, `nmcli general reload conf` (no NM restart, no link change).
   A failure there only warns; `check-fleet-health.sh` reports a missing drop-in.
8. **Verify the store again**, then `pm2 restart engine --update-env`.

Any failed check aborts with exit 3 **before** `pm2 restart`, so the running Engine keeps its
store. The backup folder stays for a manual restore.

## 4. After the deploy
- `cat store-identity/store-url.txt` and the Engine log (`~/.pm2/logs/engine-*.log`, lines
  `Store: 2VroE-…`) show 2VroE.
- `tools/fleet/check-fleet-health.sh` is healthy for the Pi (including `checks.dhcp`).

## 5. Rollback
`git checkout --detach $(cat <backup>/HEAD)`, copy the backup's `config.yaml`,
`pm2.config.cjs` and `store-identity/` back, check `store-url.txt`, rebuild, `pm2 restart engine`.
