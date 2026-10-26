# Deployment records (#322)

One JSON file per device type and batch, e.g. `zimbabwe-2026-10-client-cards.json`.
These files record what actually went into the field. They never contain secrets
(Wi-Fi PSKs, root passwords, keys): only the *names* of the flash-time secret
inputs and, where useful, a sha256 of a secret for later verification.

## Format (`idea-deployment/1`)

| field | meaning |
|---|---|
| `format` | `idea-deployment/1` |
| `batch`, `device_type`, `recorded_at`, `recorded_by` | identification |
| `images[]` | `{id, git_sha, git_tag, on_main, build_log, image_file, image_sha256, read_back_sha256?, manifest_dir}`; `manifest_dir` points to `manifests/<kind>/<name>/` |
| `inputs[]` | `{name, url, sha256}`: base image, IB, debs, firmware |
| `post_install_changes[]` | field patches applied after flashing: `{script, script_sha256, date, effect[]}` |
| `devices[]` | `{id, image, patches[], evidence}`; `id` is a hardware or Engine disk id |
| `unaccounted` | devices in the batch with no evidence |
| `package_archive` | where the exact packages are archived (outside git) and its SHA256SUMS hash |
| `verification` | how to check a device: `tools/repro/capture-device.sh` + `compare-manifest.sh` |
| `open` | known gaps |

## Archive step for every release build

1. `build.sh` (release mode: clean tree, tag on main) writes `manifests/<kind>/<name>/`.
2. Archive the exact inputs and packages:
   * client: `tools/repro/archive-debs.py --manifest manifests/client/<name>/packages.tsv --out <archive>/client/<name>`,
     plus the base image and Chrome deb from `inputs.tsv`;
   * router: copy `$WORK/<IB>/packages/*.apk`, the IB tarball, `feeds/*.adb` and the image to `<archive>/router/<name>`.
   * Write `SHA256SUMS` in each archive directory.
3. Upload the archive as a release asset (see recommendation below) and record its URL and SHA256SUMS hash in the deployment record.
4. Before a batch ships, add or update `deployments/<batch>-<type>.json` and capture one device with `capture-device.sh`.

## Durable storage recommendation

Recommendation: GitHub release assets on `koenswings/idea`, one release per field tag
(e.g. `field/zimbabwe-2026-10/client-s15`), holding the image `.xz`, `debs.tar` and `SHA256SUMS`.
Assets are limited to 2 GiB each, so split the debs if needed. Not yet published: needs Koen's approval.
Also tag the field commits (`f00748e`, `291b962`, `b2f00bc`) so that GC cannot remove them.
