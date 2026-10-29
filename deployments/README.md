# Deployment records (idea#322)

This README is owned by the image side (#323). The Engine records (#324, agent-engine-dev#252) follow it.

## Layout

    deployments/clients/<card-id>/<label>/      client cards
    deployments/routers/<name>/<label>/         routers (sticker name)
    deployments/engines/<host>/<label>/         Engines (records written by agent-engine-dev tooling)

`<label>` is `retro-YYYY-MM-DD` for a record reconstructed from evidence, or a capture or install label otherwise.
Batch names follow `<place>-<YYYY-MM>`, e.g. `zimbabwe-2026-10`. **Records never contain secret values**: they name
which secrets were given, and nothing more.

## Files in a record directory (the same for every device type)

| file | required | format |
|---|---|---|
| `record.txt` | yes | `#` comments, then one `key=value` per line (schema below) |
| `packages.tsv` | yes (when known) | `package<TAB>version<TAB>arch`, sorted. Clients: `dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n'`. Routers: apk `P/V/A` (`tools/repro/router-packages.sh`). Engines: dpkg-query as for clients |
| `images.tsv` | optional | `ref<TAB>image id<TAB>repo digests` (Docker images; Engines). A capture that only sees image ids writes `UNKNOWN` in the digests column; compare treats an `UNKNOWN` column as never differing (same rule as `record.txt`) |
| `files.sha256` | optional | `sha256sum` lines, sorted by path, of **git-tracked Engine files only**. System file hashes from a probe capture never go here |
| `dist.sha256` | optional | `sha256sum` lines of a compiled `dist/`, sorted by path (Engines) |
| `helpers.sha256` | optional | `sha256sum` lines, sorted by path, of every `/usr/local/sbin/idea-*` file on an Engine. Compared keyed by path, only when the expected record has it |
| `capture.txt` | optional | raw output of `tools/repro/capture-device.sh` |

System file hashes from a probe capture get their own sidecar: `helpers.sha256` for `/usr/local/sbin/idea-*`;
any other system file hash stays in the raw `capture.txt` and is not copied into `files.sha256`.

`tools/client-image/client.lock` and `tools/router-image/router.lock` are **build inputs** (lock files made by `tools/repro/make-lock.sh`; older records name the earlier `apt-pins.tsv`).
Records always use `packages.tsv`.

## record.txt schema `idea-deployment-record/1`

`UNKNOWN` (optionally followed by an explanation) means the value is not recoverable yet; it never counts as a
difference in a compare. `n/a` means the key does not apply. Unknown extra keys are allowed.

| key | required | meaning |
|---|---|---|
| `schema` | yes | `idea-deployment-record/1` |
| `batch` | yes | e.g. `zimbabwe-2026-10` |
| `deviceType` | yes | `client` \| `router` \| `engine` |
| `hostname` / `stickerName` / `cardId` | at least one | device identity (client cards: the Engine disk id of the card) |
| `arch`, `model`, `osRelease` | yes | hardware and OS |
| `imageCommit`, `imageBranch`, `imageTag`, `imageVersion` | yes | source (`imageTag` empty = untagged; field builds use `field/<batch>/<id>`) |
| `imageFile`, `imageSha256`, `readBackSha256` | yes (client/router) | the bytes that were flashed; link the release asset when published; for images not published, say so (e.g. "box only, not published") |
| `imageManifest` | yes (client/router) | `manifests/<kind>/<name>/` (content manifest for `tools/repro/rebuild-check.sh`) |
| `contentSha256` | yes | client/router: sha256 of the image's `content.tsv`. Engine: see below |
| `baseImageSha256`, `chromeDebSha256`, `imageBuilder`, `cudyIntermediate`, `setupRef`, `aptPins` | per type | pinned build inputs (URL and sha256) |
| `postInstall.<id>` | if any | each change made in the field after flashing or installing: date, script/procedure, effect (e.g. `postInstall.cardpatch`, `postInstall.morango`) |
| `packageArchive` | yes | box path of the exact package/input archive (the directory always has a `SHA256SUMS`) |
| `packageArchiveSha256` | yes | sha256 of the archive asset, or of its `SHA256SUMS` |
| `packageArchiveUrl` | yes | release asset URL, or `not published yet (Koen 2026-10-26)` |
| `packageArchiveParts`, `packageArchiveTarSha256` | optional | number/names of split tar parts and the sha256 of each tar (when the archive is split) |
| `secrets` | yes | which secrets were given and when (names only) |
| `deployedAt`, `evidence`, `confidence`, `open` | yes | provenance and gaps |

### Engines (`deviceType=engine`)

An Engine is installed on the device and has no image, so `imageFile=n/a`, `imageSha256=n/a` and `imageManifest=n/a`.
`imageCommit` and friends refer to the Engine commit. Its content hash is computed exactly as
`capture-engine-record.sh` does it:

    contentSha256 = $(cat files.sha256 dist.sha256 | sha256sum | cut -d' ' -f1)

`tools/repro/compare-record.py --check <dir>` verifies this.

## Tools (shared, in koenswings/idea `tools/repro/`)

* `volatile.txt`: the single volatile list. It holds path globs for content manifests, plus `key:<name>` lines for
  record keys that are never compared.
* `compare-record.py EXPECTED ACTUAL`: compares two record directories (record.txt minus volatile keys, plus the
  sidecars). `--check DIR` validates a record.
* `compare-manifest.sh` and `rebuild-check.sh`: image content manifests.
* `capture-device.sh <name> <user@ip>`: read-only capture (dpkg/apk, uname, os-release, file hashes, Engine git SHA).
* `archive-debs.py`: exact .deb versions, checked against the mirror's Packages sha256, with `--launchpad` for
  superseded versions.

Engine-specific capture (`capture-engine-record.sh`) stays in agent-engine-dev, but it should use this
`volatile.txt` and `compare-record.py`.

## Archives

Every record states the box path and sha256 of its archive, and the release URL where one exists.

* **Box copies (authoritative for now):** `/workspace/idea-archive/` for clients and routers, and
  `/workspace/idea322-archive/` for Engines. Each archive directory has a `SHA256SUMS`.
* **Release assets (per repo of origin):** client and router inputs go on `koenswings/idea` releases, and Engine inputs
  on `koenswings/agent-engine-dev` releases. Each release is attached to the field tag (`field/<batch>/<id>`) and holds
  the package tars (each under 2 GB), the inputs, `SHA256SUMS` and the missing-packages list.
  **Never** publish an image that holds a secret (client images: Wi-Fi PSK; router images up to b2f00bc: baked root password).
* State on 2026-10-26: the tags `field/zimbabwe-2026-10/client-s14` (f00748eb), `client-s15` (291b9625) and
  `router-b2f00bc` (b2f00bcf) are pushed. The router prerelease is published (ImageBuilder, Cudy intermediate,
  `router-b2f00bc-apk.tar`, `SHA256SUMS`; the kit image was removed). The client release is not published yet (Koen 2026-10-26);
  its assets are prepared in `/workspace/idea-archive/release-assets/field-zimbabwe-2026-10-client-291b962/`.

## Archive step for every release build

1. A release-mode `build.sh` (clean tree, tag on main) writes `manifests/<kind>/<name>/`.
2. Archive the exact inputs and packages:
   * client: `tools/repro/archive-debs.py --launchpad --manifest manifests/client/<name>/packages.tsv --out <archive>`;
   * router: the build writes `$WORK/archive/<name>/` (the .apk files used, with `SHA256SUMS`). `PKG_ARCHIVE=<dir>`
     rebuilds offline from it.
3. Tar the archive (under 2 GB per part), write `SHA256SUMS`, scan for secrets, and attach it to the tag's release on the repo of origin.
4. Add a record for each device (`deployments/<type>/<name>/<label>/`), and capture one device with `capture-device.sh`.

`gen-retro-zimbabwe-2026-10.py` regenerates the retro records of the first field batch.
