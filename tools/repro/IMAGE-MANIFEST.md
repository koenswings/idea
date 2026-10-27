# Image manifest v2 (idea#322)

Content-identical (not byte-identical) check for IDEA images, automated. Approach: see idea#322.

```
tools/repro/image-manifest.sh IMAGE.img[.xz] OUT.tsv           # needs sudo; read-only on IMAGE
tools/repro/compare-image-manifest.py EXPECTED[.xz] ACTUAL[.xz]  # exit 0 identical, 1 differs, 2 usage
tools/repro/rebuild-check.sh --manifest-dir manifests/client/<name> --image IMAGE.img.xz   # or --rebuild
tools/repro/tests/image-manifest.sh                             # fixture + tiny-image tests
```

Line format (TAB): `part type mode uid:gid size content rdev /path`, sorted by part then path; partition-table
lines have type `P`. Normalisation rules: `volatile.txt`, `image-volatile.txt` (incl. `omit:`), `secret.txt`.
Secret files: content normalised then hashed (`sha256n:`), or `secret`; size `-`. No secret value is written.

## Evidence (2026-10-27, box)
- s16 (`13f6917`, raw sha256 3f1315e5…, matches published) manifest: 175636 entries, generated twice: identical.
- s15 (`291b962`) vs s16: 0 added, 0 removed, 14 changed, all real:
  `boot/config.txt` (Pi 5 USB current, #304/#316) and zlib1g, libprotobuf32t64/-lite, libminizip1t64
  (libraries, changelogs, dpkg md5sums/triggers). Before the normalisation lists were complete it also showed
  the random `tmpkbd.*` name, initrd, shadow lastchg, update-notifier and command-not-found stamps; those are
  now in `image-volatile.txt` / the shadow normaliser.
