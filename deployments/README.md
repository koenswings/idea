# Deployment records (#322)

Layout: `deployments/{clients,routers,engines}/<name>/<label>/record.txt` (`engines/` belongs to the Engine side,
agent-engine-dev#252). `<name>` is the sticker or card name, and `<label>` is `retro-YYYY-MM-DD` or a capture/install label.
A record may also hold a capture (`capture.txt` from `tools/repro/capture-device.sh`) or package lists. Records never
contain secrets: they name the flash-time inputs only.

## Record schema `idea-deployment-record/1` (to be agreed with the Engine records of agent-engine-dev#252)

This is the same format as the Engine records: `record.txt`, with `#` comment lines and then one `key=value` per line.
`UNKNOWN` means the value is not recoverable and must be filled in from a capture. In a compare, `UNKNOWN` never counts
as a difference.

| key | required | meaning |
|---|---|---|
| `schema` | yes | `idea-deployment-record/1` |
| `batch` | yes | e.g. `zimbabwe-2026-10` |
| `deviceType` | yes | `client-card`, `router` (Engine: hostname/stickerName keys of #252) |
| `hostname` / `stickerName` / `cardId` | one of | device identity (client cards: Engine disk id of the card) |
| `arch`, `model`, `osRelease` | yes | hardware/OS |
| `imageCommit`, `imageBranch`, `imageTag`, `imageVersion` | yes | source of the image (`imageTag` empty = not a release) |
| `imageFile`, `imageSha256`/`imageXzSha256`, `readBackSha256` | yes | the bytes that were flashed |
| `imageManifest`, `contentSha256` | yes | `manifests/<kind>/<name>/` (content manifest for `rebuild-check.sh`) |
| `baseImageSha256`, `imageBuilderSha256`, `setupRef`, `cudyIntermediate`, `aptPins` | per type | pinned inputs |
| `postInstall.<id>` | if any | field changes after flashing (script and effect); Engine uses `manualEdit.<id>` |
| `packageArchive` | yes | box path and release asset of the exact packages |
| `secrets` | yes | which secrets were given at flash time (names only, never values) |
| `deployedAt`, `evidence`, `confidence`, `open` | yes | provenance and gaps |

Unknown keys are allowed, so the Engine and image sides can grow independently.

## Archive step for every release build

1. `build.sh` (release mode: clean tree, tag on main) writes `manifests/<kind>/<name>/`.
2. Archive the exact inputs and packages:
   * client: `tools/repro/archive-debs.py --manifest manifests/client/<name>/packages.tsv --out <archive>/client/<name>`,
     plus the base image and Chrome deb from `inputs.tsv`;
   * router: copy `$WORK/<IB>/packages/*.apk`, the IB tarball, `feeds/*.adb` and the image to `<archive>/router/<name>`.
   * Write `SHA256SUMS` in each archive directory.
3. Upload the archive as a release asset (see recommendation below) and record its URL and SHA256SUMS hash in the deployment record.
4. Before a batch ships, add `deployments/<type>/<name>/<label>/record.txt` for each device and capture one device with `capture-device.sh`.

## Durable storage recommendation

Decision (Steve, 2026-10-26): GitHub release assets plus a box copy under `/workspace/idea-archive/`. Proposed: release assets on `koenswings/idea`, one release per field tag
(e.g. `field/zimbabwe-2026-10/client-s15`), holding the image `.xz`, `debs.tar` and `SHA256SUMS`.
Assets are limited to 2 GiB each, so split the debs if needed. Not yet published: needs Koen's approval.
Also tag the field commits (`f00748e`, `291b962`, `b2f00bc`) so that GC cannot remove them.
