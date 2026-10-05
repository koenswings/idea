# Duration-tests Ops checklist (idea#166)

Atlas Ops gates for unified Markov duration walks (Design Review; proposal
[agent-engine-dev#144](https://github.com/koenswings/agent-engine-dev/pull/144) /
`proposals/duration-tests.md`).

**Hard rules**

1. **Multi-Pi claim for the whole walk** — every participating pool Pi is claimed
   before the walker starts and stays claimed until teardown.
2. **Golden never selected** — `idea02` / `role: golden` is refused by the claim
   and release hooks.
3. **Teardown → unique store + mDNS off** — after release, each Pi keeps its own
   Automerge store and `mdns: false` (isolation from golden).
4. **Health around intentional reboots** — push claims, then
   `check-fleet-health.sh --origin` (and optional PAUSED) before/after reboot churn.

Pool Pis: `idea01`, `idea03`, `idea04`. Scripts wrap `update-fleet-state.sh` and
`check-fleet-health.sh`; they do not reimplement fleet-state I/O.

## Scripts

| Script | Role |
|--------|------|
| `duration-test-claim.sh` | Claim N idle pool Pis (or `--pis`) for a walk id |
| `duration-test-release.sh` | Clear claims → idle; print store/mDNS restore checklist |
| `duration-test-health-wrap.sh` | `before` / `after` `--origin` (+ optional PAUSED) |
| `DURATION_TESTS.md` | This checklist |

Offline selftest (no Pi / no Tailscale): `duration-test-ops.test.sh`.

## Walk sequence

### 1. Claim

```bash
# Default: first 2 idle pool Pis
BOT_NAME="Atlas Ops" tools/fleet/duration-test-claim.sh walk-2026-10-01a

# Or explicit set for a 3-Pi walk
BOT_NAME="Atlas Ops" tools/fleet/duration-test-claim.sh \
  --pis idea01,idea03,idea04 walk-2026-10-01a
```

- Sets `status=testing` and
  `claim="<BOT_NAME>: duration-walk <walk-id> idea#166"`.
- Refuses golden / busy Pis; rolls back partial claims on failure.
- **Commit + push** `fleet-state.json` (and audit) so
  `check-fleet-health.sh --origin` sees the claims.

### 2. Run the walker

Engine owns the YAML walker (Axle). Ops does not start the walker from these
hooks — hand the claimed hostnames to the Engine run.

### 3. Reboot baseline (before intentional churn)

```bash
tools/fleet/duration-test-health-wrap.sh before --pause \
  --pis idea01,idea03
```

- `--origin` loads claims from `origin/main` (claimed Pis never fail / alert).
- `--pause` writes `$HEALTH_DIR/PAUSED` with a duration-test marker so fleet
  changes stay paused during expected reboot noise.

### 4. After reboot churn

```bash
tools/fleet/duration-test-health-wrap.sh after --clear-pause \
  --pis idea01,idea03
```

Re-baselines pm2 restart counts and removes our PAUSED marker only.

### 5. Teardown / release

```bash
BOT_NAME="Atlas Ops" tools/fleet/duration-test-release.sh \
  --walk-id walk-2026-10-01a
# optional: --run-teardown  (calls stub teardown.sh until idea#107)
```

Then, when Tailscale/SSH is available, confirm per Pi:

1. Unique Automerge store (not golden's).
2. `mdns: false` in Engine config; fleet-state `.mdns` stays false.
3. Pi `note` / isolation `config.yaml` untouched.
4. pm2 `engine` online as `pi`.
5. Optional: `tools/fleet/check-fleet-health.sh --origin --pi <pi>`.

### 6. Health clear

After release + restore, push idle fleet-state and run:

```bash
tools/fleet/check-fleet-health.sh --origin --alert
```

Confirm no `PAUSED` left from the walk
(`duration-test-health-wrap.sh status`).

## Tailscale / box note

These hooks are **offline-safe** (jq + fleet-state only for claim/release;
health-wrap calls `check-fleet-health.sh --origin`). Live Pi verify needs
Tailscale SSH from the Atlas box. If Tailscale is missing, ship the scripts +
checklist and skip live smoke; re-verify when the box rejoins the tailnet.


## Fixture packs (App#10)

Restored fixture disks for duration walks (Path A on idea01: Kolibri Grade 5A,
Nextcloud Grade 5A, empties) must be seeded from **versioned packs** on
[agent-app-dev](https://github.com/koenswings/agent-app-dev) `main` @
`da291d5a9aa3cd59dec6aa55940194dacc202dbf` (App
[#10](https://github.com/koenswings/agent-app-dev/pull/10)) — **never ad-hoc
copies**.

| Pack tree (`tests/duration-tests/fixtures/…`) | diskId |
|-----------------------------------------------|--------|
| `empty/` | `duration-empty-001` |
| `empty-002/` | `duration-empty-002` |
| `kolibri/` (instance `kolibri-grade5a-001`) | `duration-kolibri-grade5a-001` |
| `nextcloud/` (instance `nextcloud-grade5a-001`) | `duration-nextcloud-grade5a-001` |

- App docs: `tests/duration-tests/README.md` on that tip.
- Live copies on idea01: `IDEA_DISKS_ROOT=/home/pi/idea/duration-disks` (derived
  from the packs above).
- After dock, Kid’s `tests/duration-tests/scripts/post-dock-restore-running.sh`
  brings Kolibri `:18080` and Nextcloud `:18280` to running.
- `kolibri-form3/` is for sidecars/manuals — do **not** dock Form3 on idea01
  Path A (collides with empty-fixture / sidecar ports).

Sync packs from **agent-app-dev `main`**, not stale branch SHAs.

## Related

- Claim protocol: `docs/grok-bot-setup.md` §4.6
- Health: `docs/grok-bot-setup.md` §4.5 / `check-fleet-health.sh`
- Parent issue: https://github.com/koenswings/idea/issues/166
