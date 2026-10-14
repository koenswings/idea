# Design note: per-Pi Engine ssh keys, exchanged through the store

> Imported from the ops box (duration-evidence) on 2026-10-13 for the audit; text unchanged.

Status: Koen's decision, 2026-10-06. This replaces design-school-engine-key.md (a per-school key). Nothing is built yet. All refs are to agent-engine-apphelper @ 474a529.

**Goal.** Each Engine has its own key. Peers learn it from the shared Automerge store, so there are no per-school key lists, and a Pi can move between schools with no ops step.

**Trust.** Anyone who can write the store can already make an Engine run commands: `engineDB[x].commands` is executed by `storeMonitor.ts:47-80`. That includes erase, delete and copy. Taking ssh keys from the same store therefore opens no new door, and the gate (§1d) limits what a key can do.

## 1. Where each piece lives

**a. Key generation.** `ensurePeerKey()` in a new `src/utils/peerSsh.ts`, called in `start.ts` right after `assertAppDataHelper()` (`start.ts:61`) and before `createOrUpdateEngine` (`start.ts:109`).
- If `/home/pi/.ssh/idea_engine_ed25519` (pi:pi, 0600) is missing, it runs `ssh-keygen -t ed25519 -N '' -C idea-engine-<engineId>`.
- It reads the host key from `/etc/ssh/ssh_host_ed25519_key.pub`.
- The image, `install.sh` and `provision-fleet.sh` stay key-free.

**b. Store schema.** Add an optional field to `interface Engine` (`Engine.ts:11-29`):
`peerAccess?: { sshKey: string; hostKey: string; publishedAt: Timestamp; authorized: string[] }`.
- `initialiseLocalEngine` (`Engine.ts:85-108`) and `createOrUpdateEngine` (`Engine.ts:113-140`) rewrite it on every start from the files on disk, never from the store.
- The heartbeat (`start.ts:229-232`, `timeMonitor.ts:75-84`, every 50 s) re-adds it if it is missing.
- `authorized` lists the `engineId:keyFingerprint` entries this Engine has written into its own authorized file. That lets the sender see that the target has accepted its key.

**c. Helper subcommand.** `idea-app-data sync-peers` goes in the subcommand case at `idea-app-data:474-625`. It bumps `APP_DATA_HELPER_VERSION` (`appDataHelper.ts:35`, `idea-app-data:74`). No sudoers change is needed, because `11-engine-files.sudoers:39` already allows the whole helper.
- **Input:** the FULL set of peers on stdin, one line per peer: `<engineId> <ssh-ed25519 key> <ssh-ed25519 hostkey>`.
- **Checks, line by line:** the engineId matches a strict regex; the key type is ed25519 only; the base64 is valid; `ssh-keygen -l` parses it; there are no duplicates; there are at most 256 lines.
- **Output:** the helper writes the line prefix itself: `restrict,command="/usr/local/sbin/idea-peer-gate <engineId>"`. It writes two files:
  - `/etc/ssh/idea_authorized_keys/pi` (root:root, 0644; directory root, 0755)
  - `/etc/idea/peer_known_hosts` (root:root, 0644), lines of the form `<engineId> ssh-ed25519 …`
- **Writes:** mktemp in the same directory, fsync, then `mv`. Nothing is written when the content is unchanged, so the call is idempotent. An empty set empties both files.

**d. The idea-peer-gate script.** `/usr/local/sbin/idea-peer-gate` (root, 0755) runs as pi. It parses `$SSH_ORIGINAL_COMMAND` with no shell eval, logs through `logger` with the peer's engineId, and execs argv. It allows only:
- `sudo -n idea-app-data receive <root> <newId> --server …`: a new instance folder, rrsync `-wo`, no `--sender` (`idea-app-data:492-509`). `receive` writes a root-owned marker recording which peer created the folder.
- `receive-app`, `receive-service` and `receive-files`: app master, service tars, and compose.yaml/.env only. Each uses rrsync `-wo` into that exact folder.
- `ensure-dirs <root>`.
- `version`.
- `delete <root> <id>`, only if the marker for that folder names the same calling peer.

**e. sshd drop-in, installed by build-engine.** A new `installPeerAccess` step, called next to `installUdev` (`Engine.ts:274`; the helper install is at `Engine.ts:526-532`). It installs the gate and `/etc/ssh/sshd_config.d/20-idea-peer.conf`, which says `AuthorizedKeysFile .ssh/authorized_keys /etc/ssh/idea_authorized_keys/%u`, then runs `sshd -t` and reloads sshd. Operator keys stay in `~pi/.ssh/authorized_keys` and are not restricted.

**f. Engine ssh options builder.** `peerSshArgs(engineId)` in `peerSsh.ts` returns:
`-i /home/pi/.ssh/idea_engine_ed25519 -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/etc/idea/peer_known_hosts -o HostKeyAlias=<engineId> -o ConnectTimeout=10`.
The alias is the engineId, which stays stable while the IP from `Network.ts:170-178` changes. It replaces these calls:
- the plain mkdir and sudo mkdir in `CopyMoveApp.ts:172-186` → `ensure-dirs`
- `rsync.ts:121` (used at `CopyMoveApp.ts:307,340`) → `receive-app` / `receive-files`
- `CopyMoveApp.ts:365` → `receive-service`
- `appDataHelper.ts:86` → `delete`
- `idea-app-data:486` (`send`): the helper hardcodes the same options and takes the alias as a checked argument

**Peer-key sync.** A small monitor runs at startup, on `engineDB` patches (`storeMonitor.ts`, debounced 5 s) and on each heartbeat.
- **Set:** every Engine in THIS Engine's own store document, minus itself, that has `peerAccess` and is not stale (§4). The result goes through `sudo -n idea-app-data sync-peers`.
- **Copy check:** `validate()` (`CopyMoveApp.ts:115-121`) refuses a cross-Pi copy if the target's `peerAccess.authorized` does not include this Engine's fingerprint. The error is: "Engine X has not accepted this Engine's key yet; try again in a minute." It then runs a 5 s `version` check through the gate before the copy starts.

## 2. Effort
About **8–10 working days**:
- helper `sync-peers`, receive markers, the 3 receive-* subcommands, ensure-dirs: 2.5 d
- gate script: 1 d
- Engine key, schema, sync monitor, `validate()` check, builder and the call sites: 2.5 d
- build-engine `installPeerAccess`: 0.5 d
- tests (gate and helper shell tests, argv unit tests, cross-engine sshd fixture): 2 d
- pool rollout and retiring the May key: 1 d

That is about 3 days more than the per-school key, mostly for the sync and the self-healing.

## 3. Risks
- **Store-poisoning peer.** Anything that can write the store can:
  - add its own key everywhere. The gate limits it to filling disks with new folders and deleting only its own folders, so the receive side should also refuse when free space is below a threshold.
  - swap a real Engine's `hostKey`/`sshKey` and so intercept a copy meant for that Engine. That is no worse than `StrictHostKeyChecking=no` today, but it is a step back from pinning at provisioning.

  Mitigation: every key change is logged and shown in the Console ("key of X changed"). Signing the new entry with the old key (`ssh-keygen -Y sign`) can come later.
- **Delay between join and first copy.** It is one sync round plus the 5 s debounce, so seconds when the Pis are connected. If mDNS discovery is slow, the `validate()` check gives a clear "not accepted yet" error rather than a half-finished copy.
- **Key wiped on reimage.** The Engine makes a new key on start, and `boot.sh:19-20` makes a new host key. Both are re-published and peers re-pin on the next sync, so no `ssh-keygen -R` is needed. If the reimaged Pi gets a new engineId, phantom cleanup (`Engine.ts:166-175`) removes the old entry and its key. Planned copies to that Pi fail closed until it has re-published.
- **mDNS cross-store replication on a shared LAN.**
  - The mDNS record (TXT) carries only name, id and version (`mdnsMonitor.ts:30-34`), and `manageDiscoveredPeers` connects to every Engine it discovers (`Network.ts:58-84`). Peers with storage get every document announced (`path-a-ready-r34/post-burst-cpu-rootcause.md:42`).
  - So idea02 or another school on the same LAN holds and relays our store document, and could write to it.
  - A Pi whose `store-url.txt` is missing is put back on the shared fleet store URL (`start.ts:84-88`, `StoreIdentity.ts:71`), so its key is published there.
  - Keys come only from our own document, which limits the damage. The fix is to add the store id to the TXT record and skip peers from other stores; that is small and should be a separate issue before rollout.
- **authorized_keys growth.** One line of about 200 B per live Engine in the store. The stale rule keeps it small; if the fleet shares one store, the file is still only hundreds of lines. The helper caps it at 256 lines (refuses and logs above that), and it rewrites only when the set changes. sshd reads the file on each connection, so no reload is needed.

## 4. Open points, with a recommendation each
- **Stale-key rule.** Drop a peer whose `lastRun` is older than **7 days**, or whose `engineDB` entry is deleted. A peer that comes back writes `lastRun` at boot and is re-added within seconds, so the rule costs nothing. For a lost or stolen Pi, ops deletes its Engine entry, which revokes it everywhere right away.
- **Store reset.** Accept the gap. Each Engine re-publishes at start and on the heartbeat. `sync-peers` with an empty set removes every key, and keys come back as peers re-publish, within about 50 s. Log "peer set went from N to 0" so the gap is visible.
- **Host key rotation.** No separate process: the Engine re-reads the ed25519 host key at start and on the heartbeat and re-publishes it if it changed. Only ed25519 host keys are published and pinned. A change triggers the "key changed" notice.
- **The hand-placed May key on idea02/idea03.** Retire it once the pool passes. Note its fingerprint, then remove it from `~pi/.ssh/authorized_keys` and remove the private key from `~pi/.ssh`. Keep the operator key. idea02 needs Koen's go-ahead (the verification plan keeps it off-limits).

## 5. Pool mirror (idea01/03/04), after Atlas fixes idea01 sudo
1. Atlas gives pi passwordless sudo on idea01 (blocker, `apphelper-onpi-plan.md:145`).
2. Install the branch on all three with build-engine. That installs helper v2, the gate and the sshd drop-in; check that `sshd -t` passes.
3. Start the Engines. Check that each pool store entry has `peerAccess`, and that each Pi's authorized file and known_hosts list exactly the other two Pis, with the gate prefix.
4. Acceptance:
   - a cross-Pi copy and move in both directions, through the Console, between bridged slots;
   - `ssh -i idea_engine_ed25519 pi@peer id` is refused and logged;
   - a delete of a folder that receive did not create is refused;
   - stop idea04 with a low stale threshold set in config: its key disappears from the other Pis, then comes back after a restart.
5. Confirm that idea02 (same LAN?) does not appear in the pool's peer set. Then retire the May key on idea03, and on idea02 if Koen agrees. The test harness keeps using the operator key (`realFleetOps.ts:169-174`).

## 6. Implementation (2026-10-06): feat/app-data-root-helper 0c9200d + 46d4d57
Differences from the note above:
- The drop-in is `10-idea-peer.conf`, not 20: on Debian the first value wins. It keeps `.ssh/authorized_keys2`.
- `authorized` entries are `<engineId> <sshKey fp> <hostKey fp>`. validate() checks both directions against the current keys.
- The key is made and published by `PeerAccess.ts` (startPeerAccess), after the phantom cleanup in start.ts. initialiseLocalEngine is not used for this, so `authorized` survives restarts.
- The helper checks keys with a strict regex for the ed25519 blob, not `ssh-keygen -l`. The Engine also checks the blob structure. Writes use mktemp + mv, with no explicit fsync.
- The gate maps receive / receive-files / delete to the `peer-receive` / `peer-receive-files` / `peer-delete` subcommands. The peer id comes from the root-owned key line. The ledger is `/var/lib/idea-app-data/received` (24 h).
- The free-space floor is 1 GiB, on every receive. The stale threshold is `settings.peerStaleHours` (default 168).
- Fail closed uses the marker `store-identity/store-url.restored`.
- Deferred:
  - the 5 s `version` probe before a copy;
  - a Console notice of key changes (Engine log only for now);
  - the store id in the mDNS TXT record (separate issue).
- Cross-Engine move stays unsupported (moveApp refuses remote targets).
