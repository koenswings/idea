# Proposals Index — IDEA (Org Level)

Ideas seeking or having sought a decision. See `proposals/README.md` for format and lifecycle.

Update this file whenever a proposal is added, approved, declined, or superseded.

---

## files-disk.md
**Status:** Proposed (design reviewed; the general Erase change of 2026-09-28 11:08 is pending design re-review) · **Author:** Steve (Lead Bot)
Files Disk (idea#75): a shared file store on a docked ext4 disk. Its `files/` folder is mounted into opted-in Apps (Nextcloud first) on the Engine it is docked to. **Combined disks are allowed**: "Add Files to this disk" adds the Files role to an empty disk or an App/Backup Disk without changing anything, and keeps the disk ID. `processDisk` runs Files first. **Erase is a general disk action** (Koen, 2026-09-28 11:08, pending re-review): "Erase this disk" on every non-system disk shows a summary of what will be lost. `eraseDisk <targetId> <summaryTraceId> <confirmName>` then needs a fresh summary (under 10 minutes) and the typed label, and leaves an **empty IDEA disk** (GPT, ext4, only `META.yaml`, label "IDEA Disk", same ID). Roles are added separately (Files, Backup, Install App). The Files flow keeps an erase-first shortcut (`eraseDisk` then `createFilesDisk`, one confirmation). Mounted disks go through the eject path first. Blockers: a running backup, an instance lock, or a Nextcloud first start or upgrade. The erased disk's instances leave the store, and links to an erased Backup Disk are cleared. Every backup takes the disk and instance locks together. The system disk and swap are never erased, and the Engine mounts only ext4 (a behaviour change). One root-owned script, `idea-erase-disk`. Tests on idea03 only. No SMB/NFS. Depends on idea#121 plus an unmount safety fix. Reviewed by Atlas, Kid, Axle and Pixel.

## pi-checkout-layout.md
**Status:** Decided · **Author:** Steve
Koen locked 2026-09-24: nest agent checkouts under `idea/agents/`; App repos (`app-*`) nest under `agents/agent-app-dev/`. Retires `/home/pi/projects/engine`, `/home/pi/console-dist`, sibling `/home/pi/agent-*` heuristics, and `app-*` as agents siblings. Fixes quality-scan remote path assumption behind #62/#63.

## quality-scan-implementation.md
**Status:** Draft · **Author:** Steve
Implement `tools/quality/quality-scan.sh` from grok-bot-setup §5 (d05695a): one script for PR gate and scheduled scan; JSON report; audit line. Design Review complete; open questions resolved with Koen except as noted in the draft.

## app-dev-agent.md
**Status:** Approved · **Author:** Atlas
Proposes Kit as the App Developer agent. Covers role definition, app repos, harness, monitoring, Docker builds on Pi, data storage.

## kit-compatibility-matrix.md
**Status:** Approved · **Author:** Atlas
App compatibility matrix for the Kit agent — which apps are compatible with which engine versions.

## kit-data-storage.md
**Status:** Approved · **Author:** Atlas
Data storage approach for IDEA Apps managed by Kit.

## virtual-company-design.md
**Status:** Implemented · **Author:** Atlas
Original virtual company design: agent roles, cross-agent task convention, output file policy, communication standards.

## ssh-key-management.md
**Status:** Implemented · **Author:** Atlas
SSH key types, command= convention, authorized_keys restrictions, IDEA SSH access map.

## openclaw-native-migration.md
**Status:** Implemented · **Author:** Atlas
Trade-off analysis for OpenClaw Docker vs native install. Option B (native) selected and executed 2026-04-06.

## tailscale-remote-management.md
**Status:** Implemented · **Author:** Atlas
Latent Tailscale debug mode for school Pis: ephemeral auth keys, ACL tag model, USB activation.

## agent-identity-memory-architecture.md
**Status:** Implemented · **Author:** Atlas
Separates identity, memory, and code into distinct layers. Nightly backup to agent-identities repo.

## mc-native-platform-design.md
**Status:** Implemented · **Author:** Atlas
MC-native platform design: agents connect directly to MC without Docker proxy.

## grok-bot-migration.md
**Status:** Active · **Author:** Atlas
Migration plan from OpenClaw to Grok Bot — phases, scripts, tools structure, audit trail.

## audit-trail.md
**Status:** Decided (A+B) · **Author:** Atlas
Options for tracing all agent activity. Decision: GitHub Actions logs for coding work + structured JSONL for non-coding events.

## milkwise-grok-bot.md
**Status:** Pending · **Author:** Atlas
MilkWise standalone product Grok Bot setup — Lead and Dev Bots, extraction steps.
