# Stage 1 release script (idea#322)

`tools/repro/release.sh --type client|router --tag TAG [--prev TAG|none] [--root DIR]`

Builds the generic image from a clean `git worktree` of TAG (never the caller's tree), compares it with the
previous release and stores the result on the bot computer. **No GitHub Releases, no upload.**

**Release folder:** `~/idea-releases/` (override with `IDEA_RELEASES` or `--root`), on the bot computer only.

```
~/idea-releases/<type>/LATEST            newest tag (default --prev)
~/idea-releases/<type>/<tag>/
  <image>  <image>.sha256                client .img.xz / router squashfs-sysupgrade.bin
  manifest/                              build manifest dir (build.env, inputs.tsv, packages.tsv, content.tsv.xz, ...)
  image-manifest.tsv.xz                  client: v2 image manifest (image-manifest.sh)
  diff-vs-<prev>.txt                     client: compare-image-manifest.py; router: compare-manifest.sh on content.tsv.xz
  build-out/                             other build outputs (package list, logs)
  RELEASE.txt                            type, tag, commit, image, sha256, previous, diff result, built_at (UTC)
~/idea-releases/.work-client/            client download cache (base image, Chrome .deb)
```

Rules: a release folder is never overwritten; a failed build leaves only `<type>/.stage-<tag>.*.failed-*`;
a `-dev` image is refused. Order: client first, then router. The client build needs root (sudo), qemu-user-static
and network (or the later input archive); the tag must pass `repro_release_guard` (clean, on origin/main).
Tests: `tools/repro/tests/release.test.sh` (mock build, no root/network).
