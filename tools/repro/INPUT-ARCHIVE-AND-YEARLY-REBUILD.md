# Input archive and yearly rebuild (idea#322)

Koen's decisions (29 Oct 2026): pin input versions now, keep the full input archive (about 2 GB per image type) later,
and do a clean rebuild **yearly and before a handover**. This page is the bot-side procedure for both.

## 1. Input archive

Every `build.sh` (client, router, Engine) writes `inputs.tsv` (label, URL, sha256, size) for the files it fetched.
`tools/repro/archive-inputs.sh` copies those inputs, plus anything else the build needs, into one archive folder and
checks each file against its pinned sha256.

What goes in, per image type:

| Image | Inputs |
|---|---|
| Engine | pinned Raspberry Pi OS Lite base (`tools/engine-image/engine-image.conf`), the Engine lock file, the Engine build cache (Docker image tars by digest, pnpm store), the `.deb`s from the image's `MANIFEST.txt` |
| Client | the pinned base / `.deb`s from `manifests/client/<name>/packages.tsv` (via `archive-debs.py`), pinned extra `.deb`s |
| Router | the OpenWrt imagebuilder and package files named in its `inputs.tsv` |

Example (Engine, on the build computer, after a release build):

```sh
tools/repro/archive-inputs.sh --out /srv/idea-archive/engine/<release-name> \
  --inputs ~/.cache/idea-engine-image/inputs.tsv \
  --file engine-lock=<the Engine lock file> \
  --dir  engine-cache=<engine build cache dir> \
  --debs out/engine/<release-name>.MANIFEST.txt
tools/repro/archive-inputs.sh --verify /srv/idea-archive/engine/<release-name>
```

- `--offline` uses only local caches (no download); a missing input is then an error, not a silent skip.
- Output: `<label>/<file>`, `ARCHIVE.tsv`, `SHA256SUMS`, `SIZE` (bytes). Directory inputs are stored as deterministic tars.
- **Where it lives:** on the bot computer and on an IDEA disk copy. Never in git and never as a GitHub release asset.
- **Secrets:** the script refuses any input holding a Tailscale auth key or a private key. Identity files and the
  fleet key are never inputs; they go into the private identity file at flash time.
- Re-running is idempotent; temporary copies are quarantined (moved), never deleted.

## 2. Yearly rebuild (and before a handover)

Goal: from the old release tag and the archive alone, rebuild each image and show its **content** matches the
published manifest. Byte-identical images are not required (Koen 2026-10-26).

1. Pick the latest release of each type (client, router, Engine) and its `manifests/<kind>/<name>/` folder.
2. `tools/repro/archive-inputs.sh --verify <archive>` for each one. A failure is a finding: record it on the issue.
3. On a clean computer (fresh checkout, empty `~/.cache/idea-*-image`), restore the archive into the cache folder
   and run the build with `--offline` inputs only:
   `tools/repro/rebuild-check.sh --manifest-dir manifests/<kind>/<name> --rebuild`
   (client/Engine need root and an arm64 host; router needs x86_64). Engine rebuild support in `rebuild-check.sh`
   follows the first real Engine release.
4. Exit 0 = content-identical. Any difference: open an issue with the `compare` output, fix the pin, rebuild.
5. Post the result (date, tags, pass/fail per type, archive sizes) on the reproducibility tracking issue and add a
   line to `docs/RELEASES.md`.

Schedule: once a year and before any handover of the project. Bots run it;
it needs no manual step from Koen unless a pin can no longer be fetched or a build host is missing.
