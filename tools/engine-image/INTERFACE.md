# Engine offline build: interface between `release.sh --type engine` and agent-engine-dev (idea#322 stage 5)

Status: **draft stub** on our side, written before Axle's PR (engine#291 follow-up) is up. Our build.sh calls exactly
this; when Axle's interface lands, only `ENGINE_BUILD_CMD`'s default in build.sh changes.

## Invocation (on the build host, as root, after we mounted the image)
    <engine-src>/script/build-engine-offline --root <MNT> --boot <MNT>/boot/firmware --report <OUT>/engine-build.json

- `<engine-src>`: clean checkout of agent-engine-dev at the pinned commit (release.sh `--engine-ref`).
- `<MNT>`: the mounted ext4 root of the base image, with /dev /dev/pts /proc /sys /run bind-mounted and a working
  /etc/resolv.conf. The Engine side may `chroot <MNT>` itself; the host is arm64 (idea04) or has qemu-user-static.
- No SSH, no systemd at build time: units are **enabled**, never started; no `pm2 startup` that needs a running
  systemd (write the unit instead); Docker images pinned by digest and **preloaded** (no daemon assumption on our side).
- No device identity: no /META.yaml diskId, hostname = image default, empty machine-id, no SSH host keys,
  no Tailscale state. The Engine side verifies this and fails the build if anything is left.

## Outputs
- `<OUT>/engine-build.json`: `{engine_commit, engine_version, lock_sha256, verify:{passed,failed}}` (we copy it into the release).
- In the image: the Engine lock file at `/etc/idea/engine.lock` and the version at `/etc/idea/engine-version`.
- First-boot units expected: `idea-engine-identity` (from boot.sh @reboot, engine#291), ssh host-key regeneration.

## Exit codes
0 ok - 1 build or verify failed - 2 usage error. Anything else is treated as a failure.

## Our second check (not a duplicate of the Engine's sanitising)
After the Engine build, `sanitise.sh` re-applies the identity rules idempotently and `verify-sanitised.sh` fails the
image if machine-id is non-empty, any /etc/ssh/ssh_host_* key exists, ssh key regeneration is not enabled,
/var/lib/tailscale has state, /etc/tailscale/debug-authkey exists, /META.yaml carries a diskId, or the secret scan hits.
