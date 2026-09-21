# IDEA Platform: Migration to Grok Bot — V4

**Author:** Atlas  
**Date:** 2026-09-19  
**Supersedes:** grok-bot-migration-v3.md
**Key additions vs V3:** fleet scripts as first-class design, variable Pi count, tools/ structure, audit trail design (see design/audit-trail-design.md)  
**Status:** Current migration plan — complements `docs/grok-bot-setup.md`

This document records the migration steps from the OpenClaw setup to the Grok Bot setup described in `docs/grok-bot-setup.md`.

---

## Rollback

Before any migration changes, tag the current state of `koenswings/idea`:

```bash
cd /home/pi/idea
git tag v-openclaw-final
git push origin v-openclaw-final
```

To restore the prior setup at any time: `git checkout v-openclaw-final`, restart OpenClaw.

---

## Scripts and Tools

**Core design principle:** all deterministic logic (Pi allocation, deployment, health checking, quality scanning, version monitoring) lives in scripts — not in Bot descriptions or LLM reasoning. Bots call scripts and act on the output.

Scripts live in `koenswings/idea/tools/`:

```
koenswings/idea/
  tools/
    fleet/
      idea-setup.sh              — install Grok Build, register runner, init fleet-state.json
      find-available-pi.sh       — return idle Pi matching domain from fleet-state.json
      deploy.sh                  — full deploy sequence (engine/console/app-disk)
      teardown.sh                — reverse deploy, restore main, mark Pi idle
      update-golden.sh           — update golden Pi to new version of a component
      set-golden-pi.sh           — designate new golden Pi if current unavailable
      check-fleet-health.sh      — HTTP check all deployed Pis, return JSON
      update-fleet-state.sh      — atomic read-modify-write of fleet-state.json
    quality/
      quality-scan.sh            — structural checks across all repos, return JSON report
      check-app-versions.sh      — compare app.yaml versions vs upstream, return JSON diff
    pdf/
      md-to-pdf.py               — Chromium-based Markdown → PDF with clickable ToC
    README.md                    — script inventory and installation
```

**Installation on each Pi runner (done in Phase 2):**
```bash
apt-get install -y python3-markdown jq   # jq for JSON parsing in scripts
# chromium already installed
```

The runner clones `koenswings/idea` as part of workflow setup — tools are always available.

---
---

> **Audit trail:** Design options documented separately in `design/audit-trail-design.md`. Not part of this migration — to be implemented after the setup is stable.

---

## Phase 0 — Prepare (Atlas)

**koenswings/idea cleanup PR:**
- Rewrite `CONTEXT.md` for Grok Bot (condensed mission + team structure)
- Delete `ROLES.md` — content absorbed into CONTEXT.md
- Delete `platform/`, `skills/`, `standups/`, `graphify-out/`, stale backup scripts, `prompting-guide-opus.md`
- Create `fleet-state.json` (all Pis idle)
- Add `docs/grok-bot-setup.md` to `docs/INDEX.md`

**Dev repo cleanup:**
- Commit all outstanding identity/memory files across all agent repos
- Final MC pg_dump archived to agent-identities repo
- `agent-engine-dev`: create `design/`, move `docs/SOLUTION_DESCRIPTION.md` → `design/SOLUTION_DESCRIPTION.md`, update `docs/INDEX.md`
- `agent-console-dev`: create `design/` folder
- `agent-app-dev`: `design/` already exists

**MilkWise extraction:**
- Move MilkWise design docs from `agent-app-dev/design/milkwise/` → `baby-milk-tracker/design/`
- Move `apps/app-milkwise/` from `agent-app-dev` to new repo `koenswings/app-milkwise`
- Update App Dev Bot description to list `koenswings/app-milkwise` in its maintained repos

**deploy-fleet.sh update:**
- Remove wizardly-hugle as a deploy target (it is being retired)

**Tools setup:**
- Add `tools/pdf/md-to-pdf.py` to `koenswings/idea`
- Add `tools/README.md` documenting available scripts

OpenClaw continues running throughout Phase 0.

---

## Phase 1 — SuperGrok Link ✅ Done

SuperGrok Heavy linked to Cursor. Grok Bot active at Heavy+ tier.

---

## Phase 2 — Grok Build + Runners on Pis (Atlas, ~1 hour)

On each Pi (idea01–idea04):

```bash
curl -fsSL https://x.ai/cli/install.sh | bash
grok auth login   # Koen authenticates via browser once
```

GitHub Actions self-hosted runner: Atlas generates registration tokens via GitHub API. Runners run as systemd services, labelled `idea01`–`idea04`.

Create initial `fleet-state.json` in `koenswings/idea` (all Pis idle).

Test: trigger a workflow targeting `idea01`, verify Grok Build runs.

---

## Phase 3 — Grok Bot Setup (Koen, ~1 hour)

1. Create 5 Bots in Grok Bot: Lead, Engine Dev, Console Dev, App Dev, Ops
2. Paste Bot descriptions from `docs/grok-bot-setup.md` Section 7 into each Bot
3. Install GitHub connector → connect koenswings account
4. Create **IDEA Design Review** group chat (all 5 Bots)
5. Create **IDEA Programme** group chat (Lead + Marco + App Dev)
6. Test:
   - *Bug path:* tell Lead Bot a bug → issue created → Dev Bot triggers runner → QC → Ops deploys → URL
   - *Feature path:* tell Lead Bot a feature → Design Review group → proposal PR → koenswings/idea

---

## Phase 4 — Parallel Run (~1 week)

OpenClaw stays on as fallback. Koen uses Grok Bot for new work. Lead Bot documents any gaps as GitHub issues.

---

## Phase 5 — wizardly-hugle Retirement (when Koen says go)

- [ ] All GitHub repos committed and clean
- [ ] Final MC pg_dump archived
- [ ] ANTHROPIC_API_KEY noted → add to Grok Build config on each Pi
- [ ] XAI_API_KEY → add to Grok Build config on each Pi
- [ ] Tailscale node removed from tailnet admin console
- [ ] `systemctl --user stop openclaw`
- [ ] `docker compose -f /home/pi/idea/platform/compose.yaml down`
- [ ] Machine powered off or repurposed

---

## What Goes Away vs What Stays

| Item | Status |
|------|--------|
| wizardly-hugle | Gone |
| OpenClaw | Gone |
| Mission Control | Gone |
| Telegram groups | Gone |
| Graphify | Gone |
| ROLES.md, BACKLOG.md, standups/ | Gone (content in CONTEXT.md or archived) |
| platform/, skills/ in idea repo | Gone |
| Daily memory files, /flush | Gone — Grok Bot handles memory |
| Nightly backup cron | Gone — GitHub is source of truth |
| | |
| SuperGrok Heavy | ✓ Keep |
| Pi fleet (idea01–04) | ✓ Keep |
| GitHub repos | ✓ Keep |
| Tailscale | ✓ Keep |
| AGENTS.md files | ✓ Keep — Grok Build operational manuals |
| koenswings/idea (cleaned up) | ✓ Keep |
