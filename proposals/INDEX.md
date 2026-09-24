# Proposals Index — IDEA (Org Level)

Ideas seeking or having sought a decision. See `proposals/README.md` for format and lifecycle.

Update this file whenever a proposal is added, approved, declined, or superseded.

---

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
