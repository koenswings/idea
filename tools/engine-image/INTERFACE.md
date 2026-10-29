# Engine offline build: interface between `release.sh --type engine` and agent-engine-dev (idea#322 stage 5)

Status: implemented on the Engine side by agent-engine-dev#292 (`script/build-engine-offline`, docs/ENGINE_IMAGE.md).
`ENGINE_BUILD_CMD` still overrides the whole step (tests); `ENGINE_BUILD_ARGS` adds the optional flags below.

## Invocation (on the build host, as root, after we mounted the image)
    <engine-src>/script/build-engine-offline --root <MNT> --boot <MNT>/boot/firmware --report <OUT>/engine-build.json

- `<engine-src>`: clean checkout of agent-engine-dev at the pinned commit (release.sh `--engine-ref`).
- `<MNT>`: the mounted ext4 root of the base image, with /dev /dev/pts /proc /sys /run bind-mounted and a working
  /etc/resolv.conf. The Engine side may `chroot <MNT>` itself; the host is arm64 (idea04) or has qemu-user-static.
- No SSH, no systemd at build time: units are **enabled**, never started; no `pm2 startup` that needs a running
  systemd (write the unit instead); Docker images pinned by digest and **preloaded** (no daemon assumption on our side).
- No device identity: no /META.yaml diskId, hostname = image default, empty machine-id, no SSH host keys,
  no Tailscale state. The Engine side verifies this and fails the build if anything is left.

## Optional flags (agent-engine-dev#292)
`--cache DIR` (archive-engine-inputs.sh output; without it the pinned inputs are downloaded first: network needed),
`--lock FILE` (without it the lock is generated from the clean checkout), `--image name[:tag]@sha256:<d>` (repeatable),
`--pm2-env production|development`, `--dry-run` (runs nothing). Host: node 22 + pnpm; the wrapper runs
`pnpm install --frozen-lockfile` in the Engine checkout (local node_modules only) when its build tools are missing.

## Outputs
- `<OUT>/engine-build.json`: `{engine_commit, engine_version, lock_sha256, verify:{passed: 9|0, failed: [strings]}}`.
  A "build did not finish" report is written before the build starts. `engine-report.sh` accepts it only with
  `failed == []`, `passed > 0`, a 64-hex `lock_sha256` and `engine_commit` = the engine source HEAD.
- In the image: the Engine lock file at `/etc/idea/engine.lock` and the version at `/etc/idea/engine-version`.
- First-boot units: Raspberry Pi OS `regenerate_ssh_host_keys.service` (the Engine build fails if the base lacks it),
  `idea-engine-firstboot.service`, `pm2-pi.service`, `cron.service` (enabled in the pinned 2026-10-06 trixie lite base);
  tailscaled installed, **not** enabled (engine#291 enables it at first boot only when the card carries a key).
  Identity (engine#291): `/usr/local/sbin/idea-engine-identity` (0755 root), run every boot by `boot.sh` from a root
  `@reboot` crontab line, not a systemd unit. The Engine's verify fails if it is missing; `firstboot-units.sh` records it.

## Exit codes
0 ok - 1 build or verify failed - 2 usage error. Anything else is treated as a failure.

## Our second check (not a duplicate of the Engine's sanitising)
After the Engine build, `sanitise.sh` re-applies the identity rules idempotently and `verify-sanitised.sh` fails the
image if machine-id is non-empty, any /etc/ssh/ssh_host_* key exists, ssh key regeneration is not enabled,
/var/lib/tailscale has state, /etc/tailscale/debug-authkey exists, /META.yaml carries a diskId, or the secret scan hits.
