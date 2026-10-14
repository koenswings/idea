> Superseded by design-per-pi-engine-key.md (Koen chose per-Pi keys, 2026-10-06)

> Imported from the ops box (duration-evidence) on 2026-10-13 for the audit; text unchanged.

# Design note: per-school Engine ssh key for cross-Pi copy/move

Status: proposal for Koen to decide. No code changed. Refs are to agent-engine-apphelper @ 474a529 (feat/app-data-root-helper).

**Today.** Cross-Pi copy runs `ssh pi@<peer>` in five places. All of them use `StrictHostKeyChecking=no` and pi's default identity:
- `CopyMoveApp.ts:186` (remote ensure-dirs, plain mkdir or sudo mkdir/chown)
- `rsync.ts:121` (app master and the prepared compose/.env, `CopyMoveApp.ts:307,340`)
- `CopyMoveApp.ts:365` (service image tars)
- `appDataHelper.ts:86` (remote `sudo -n idea-app-data delete`)
- `idea-app-data:486` (`send`: `runuser -u pi -- ssh` into the peer's `receive`, which runs `rrsync -wo`, `:492-509`)

No provisioning path creates a pi-to-pi key, so production works only through the shared key placed by hand in May.

## 1. Where the key is created and placed
- **Created once per school, on the operator machine, by `provision-fleet.sh`.** Add a `--school <id>` option. If `~/.idea/schools/<id>/engine_ed25519` is missing, run `ssh-keygen -t ed25519 -N '' -C idea-engine-<id>-<yyyymm>`. The key never goes into the image (`create_image`), because the image is shared across schools. Keep `boot.sh:19-20` regenerating host keys on first boot. `install.sh` and `build-engine` stay key-agnostic.
- **Pushed over stdin, like the Tailscale key.** Add a new step between `[3/5]` (`provision-fleet.sh:178-188`) and build-engine (`:198`). It writes:
  - `/home/pi/.ssh/idea_engine_ed25519`: pi:pi, 0600, via `install -m600 -o pi -g pi /dev/stdin`. The `.pub` file next to it is 0644.
  - `/etc/ssh/idea_authorized_keys/pi`: root:root, 0644, directory 0755. This is the school pubkey with the restrictions from §2. Because it is root-owned, a compromised Engine (pi) cannot widen its own entry.
  - `/etc/idea/school_known_hosts`: root:root, 0644 (see §2).
- **Installed by build-engine, with no secrets.** Add `installPeerAccess`, called next to `installUdev` (`Engine.ts:274`, helper install at `:526-532`). It installs:
  - the gate script `/usr/local/sbin/idea-peer-gate` (root, 0755);
  - the sshd drop-in `/etc/ssh/sshd_config.d/20-idea-peer.conf`: `AuthorizedKeysFile .ssh/authorized_keys /etc/ssh/idea_authorized_keys/%u`, then reloads sshd.
- **One key per school, never across schools.** Each school has its own directory on the operator machine. Pis installed by hand (`install.sh`) get the key with a small `script/school-key.sh push <school> <pi>` that does the same step. Until then the Engine reports that the key is missing (§3).

## 2. Locking the key down
- The line in the root-owned authorized file is: `restrict,command="/usr/local/sbin/idea-peer-gate" ssh-ed25519 AAAA… idea-engine-<id>-<yyyymm>`. You can also add `from="<school LAN CIDR>"`. `restrict` turns off pty, forwarding, agent forwarding and X11.
- **The gate** is a short bash script, root-owned, that runs as pi. It parses `$SSH_ORIGINAL_COMMAND` with no shell eval and execs argv. It allows only:
  - `sudo -n /usr/local/sbin/idea-app-data receive <root> <id> --server …` (already rrsync `-wo` and refuses `--sender`)
  - `… delete <root> <id>`
  - the new subcommands below, plus `version` as a probe

  Anything else is refused and logged with `logger`. The helper still checks every token, including the test-only bridged slots in `/etc/idea/app-data-roots`.
- **This conflicts with today's plain calls.** `mkdir` (`CopyMoveApp.ts:172-180`) and the two plain pi rsyncs (`rsync.ts:121`, `CopyMoveApp.ts:365`) would be refused. The Engine changes to route everything through the helper:
  - `idea-app-data ensure-dirs <root>`: root creates apps/instances/services, owned by pi. This replaces `SYSTEM_DISK_ENSURE_DIRS` over ssh.
  - `receive-app <root> <appId>`, `receive-service <root> <tar>`, `receive-files <root> <id>` (compose.yaml/.env only): rrsync `-wo` into that exact folder, written as pi.
  - The sender keeps running rsync as pi with `--rsync-path="sudo -n idea-app-data receive-… R X"`, the same pattern as `send`.
  - Bump `APP_DATA_HELPER_VERSION` (`appDataHelper.ts:35`, `idea-app-data:74`).
- **The weakest spot is `delete`.** Anyone holding the key can delete any instance on any peer in the school. To tighten it, `receive` writes a root-owned marker for `<root>/<id>`, and a remote `delete` is allowed only while that marker exists (partial-copy cleanup only).
- **known_hosts.** Drop `StrictHostKeyChecking=no` and `accept-new`. After step 5 (once the Pi is up), `provision-fleet.sh` collects each Pi's `/etc/ssh/ssh_host_ed25519_key.pub`. It writes one school file keyed by hostname and re-pushes it to every Pi of the school. The Engine connects by IP (`Network.ts:170-178`), so it passes `-o HostKeyAlias=<peer hostname>` taken from the peer's Engine record. `send` gets the alias as a checked argument. Later option: a per-school host CA (`@cert-authority`), so adding a Pi does not mean re-pushing the file to every Pi. `accept-new` is only an interim fallback: it trusts on first use, and a reimaged Pi shows up as "host key changed".

## 3. What the Engine needs
- **One builder**, `src/utils/peerSsh.ts`: `peerSshArgs(host, alias)` returns
  `-i /home/pi/.ssh/idea_engine_ed25519 -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/etc/idea/school_known_hosts -o HostKeyAlias=<alias> -o ConnectTimeout=10`.
  - Used at `CopyMoveApp.ts:186,365`, `rsync.ts:121` and `appDataHelper.ts:86`.
  - The helper hardcodes the same constants at `idea-app-data:486`. It never takes ssh options from its caller.
- **Startup check** next to `assertAppDataHelper` (`start.ts:61`).
  - It checks that the key exists with pi ownership and mode 0600, and that the known_hosts file exists.
  - If either is missing, it logs a warning and sets `crossEngineCopy=unavailable`. It does not refuse to start, because local copy/move and backup still work.
  - `validate()` (`CopyMoveApp.ts:115-121`) then refuses a cross-Pi copy with: "This Engine has no school Engine key (/home/pi/.ssh/idea_engine_ed25519); ask Ops to run provision-fleet.sh --school …".
  - A 5 s `version` probe through the gate before the copy starts gives "peer does not accept this school's key" up front, not halfway through.
- **Test hooks**:
  - `config.settings.peerSshKey` / `peerKnownHosts` overrides for fixtures.
  - Pure argv tests in the style of `app-data-helper.test.ts:115-201`.
  - Gate tests: feed `SSH_ORIGINAL_COMMAND` samples (`;`, `$( )`, `--sender`, an unknown subcommand, extra args, a plain `mkdir`) with a fake sudo, and assert allow or refuse.
  - A test/cross-engine sshd fixture that uses the root-owned authorized file.

## 4. Rotation, revocation, ops access
- **Rotate a school:** `provision-fleet.sh --school <id> --rotate-key`.
  1. Add the new pubkey to every school Pi, so old and new are both accepted.
  2. Push the new private key. The Engine reads the path on each copy, so no restart is needed.
  3. Remove the old pubkey.

  The key comment carries the school and the date. sshd logs the key fingerprint, and the gate logs every command.
- **Revoke:** delete the line from `/etc/ssh/idea_authorized_keys/pi` on the school's Pis. For a lost or stolen Pi, rotate the school key and drop its host key from the school known_hosts.
- **Ops access stays separate.**
  - Operator keys stay unrestricted in `~pi/.ssh/authorized_keys`. That is what `provision-fleet.sh` and `check-fleet.sh` use today, and the Tailscale debug path is separate as well.
  - The operator private key never sits on a Pi.
  - The Engine key is never used by ops or by test harnesses. `realFleetOps.ts:169-174` uses the operator key and keeps doing so.

## 5. Alternative: Engine-to-Engine transfer with no ssh
The receiving Engine would expose an authenticated transfer endpoint: mTLS, or an HMAC with a per-school secret. The sender streams a tar, and the receiver pipes it into a new `sudo idea-app-data receive-tar <root> <id>`. That removes sshd exposure, sudo-over-ssh, known_hosts and the gate.

Trade-offs:
- It still needs a per-school secret, provisioned exactly as in §1.
- It loses rsync's delta and resume, so progress, resume and partial cleanup have to be rebuilt.
- Unpacking a tar as root is a new hardened surface.
- Rough effort is 1.5–2 weeks, against about 4–6 days for the ssh plan (gate, 4 helper subcommands, peerSsh, provisioning step, tests).

## 6. What the duration pool (idea01/03/04) needs to mirror it
- Treat the pool as school `duration`: generate its own key, separate from the May key and from the box/operator key. Push it with the new step (or `school-key.sh`), and push the school known_hosts with hostname aliases.
- Install the gate, the sshd drop-in and the helper version that has the new subcommands (build-engine or Atlas).
- Remove the hand-placed May key from pi's `authorized_keys` and `~/.ssh` on all three Pis.
- Known blockers (from `apphelper-onpi-plan.md:145`): idea01's pi has no passwordless sudo, and neither idea01 nor idea04 has a pi ssh key today. Both must be fixed before any cross-Pi step.
- The bridged slots in `/etc/idea/app-data-roots` work unchanged, because the gate passes root tokens through to the helper.
- Acceptance checks on the pool:
  - a cross-Pi copy and move through the Console succeed;
  - with the Engine key, `ssh -i idea_engine_ed25519 pi@peer id` is refused and logged by the gate;
  - a remote `delete` without a receive marker is refused;
  - a spoofed host key (wrong alias) fails closed.
