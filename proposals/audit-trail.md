# IDEA Grok Bot: Audit Trail Design Options

**Author:** Atlas  
**Date:** 2026-09-20  
**Status:** Design options — not yet decided or implemented

This document explores options for tracing all agent activities from trigger to outcome in the IDEA Grok Bot setup. The goal: Koen can inspect what happened at any time, even when not watching in real time.

---

## What Needs Tracing

**Already captured by GitHub (no extra work):**
- Every issue: creation, agreed-approach comment, PR link, merge, close — full timestamp trail
- Every PR: diff, review comments, merge commit
- Every proposal: the full design review discussion in the proposal PR comments

**Not captured today:**
- Which Bot triggered which action and when
- What Grok Build actually did inside a run (files read, commands tried, errors before success)
- QC gate results per PR (pass/fail, retry count, what failed)
- Fleet deployment events (which Pi, deploy time, health check outcome)
- Routine run outcomes (weekly quality scan findings, version check results)
- Bot-to-Bot messages in Design Review group chats (these live in Grok Bot's cloud)

---

## Option A — GitHub Actions Logs (coding work only)

Every Grok Build invocation runs via a GitHub Actions workflow on a Pi runner. GitHub retains the full console output per run.

**Pros:**
- Already exists — no setup needed
- Full detail: every file Grok Build read, every command it ran, every test result, every error
- Tied to the PR and commit — traceable forward and backward
- Searchable from the GitHub Actions UI

**Cons:**
- Default 90-day retention (configurable, up to unlimited on paid plans)
- Only covers coding work — does not capture deployments, quality scans, version monitoring, or Bot coordination
- GitHub Actions UI is not the most convenient for casual browsing

**Implementation effort:** zero — already available.

---

## Option B — Structured JSONL Audit Log in koenswings/idea

A file `audit/audit.jsonl` in `koenswings/idea`, appended to by Bots after every action that changes system state. One JSON line per event.

Example events:
```json
{"ts":"2026-09-19T18:30:00Z","bot":"Ops Bot","action":"deployed","pr":47,"pi":"idea01","result":"healthy"}
{"ts":"2026-09-19T18:05:00Z","bot":"Lead Bot","action":"quality_scan","issues_filed":2}
{"ts":"2026-09-19T08:00:00Z","bot":"App Dev Bot","action":"version_check","app":"kolibri","found":"v0.17.3"}
{"ts":"2026-09-19T18:35:00Z","bot":"Engine Dev Bot","action":"qc_gate","pr":47,"result":"pass","retries":0}
```

**Pros:**
- Permanent, in GitHub — inspectable from anywhere without SSH
- Covers non-coding events that Actions logs miss
- Machine-readable — could drive a status dashboard later
- Simple to implement in Bot descriptions

**Cons:**
- Adds commit noise to koenswings/idea (one commit per event, or batched)
- Bots must reliably append — a failed Bot run may miss its log entry
- File grows without bound — needs rotation strategy

**Implementation effort:** medium. Requires adding audit instructions to every Bot description and a structured append step after every significant action.

---

## Option C — Dedicated GitHub Repo: koenswings/idea-audit

Same JSONL approach as Option B but in a separate repo that exists only for audit purposes.

**Pros:**
- No commit noise in the main idea repo
- Can be public or private independently
- Clean separation of concerns

**Cons:**
- Another repo to maintain
- Bots need write access to a second repo
- No benefit over Option B unless commit noise is a real problem

**Implementation effort:** same as B, plus repo creation.

---

## Option D — GitHub Issues as Audit Events

Each Bot action files a GitHub issue (label: `audit`) in `koenswings/idea` with a structured title and description.

**Pros:**
- Very visible — shows up in the issue tracker
- Searchable and filterable by label
- No custom tooling needed

**Cons:**
- Pollutes the issue tracker unless carefully filtered
- Issues are designed for human-readable tasks, not machine-readable events
- Auto-closing would require extra steps

**Implementation effort:** low, but creates ongoing maintenance burden.

---

## Option E — Grok Bot Built-In History

Grok Bot retains conversation history per Bot. All Bot actions that involve a conversation message are implicitly logged in Grok Bot's cloud.

**Pros:**
- Zero implementation effort
- Covers all chat-based coordination including Design Review group chats
- Accessible from the Grok Bot app

**Cons:**
- Not accessible outside Grok Bot (no API, no export today)
- Retention policy unclear
- Does not cover actions that happen without a chat message (background routines)
- Not structured — natural language only

**Implementation effort:** zero, but coverage and accessibility are limited.

---

## Recommended Approach (when ready to implement)

**Combine A + B:**

- GitHub Actions logs handle all coding work (already free and detailed)
- JSONL audit log in `koenswings/idea/audit/` handles non-coding events

The JSONL file is the lightweight operational ledger; GitHub Actions is the detailed technical record. Together they cover the full picture.

**Rotation:** rotate annually — `audit-2026.jsonl`, `audit-2027.jsonl`. Keep all years in the repo.

**Bot instruction template (to add to each Bot description when implementing):**

```
AUDIT LOG:
After every action that changes system state, append one JSON line to
koenswings/idea/audit/audit-<YYYY>.jsonl via the GitHub connector:
{"ts":"<ISO timestamp>","bot":"<Bot name>","action":"<action>","<key>":"<value>",...}
Batch multiple events from the same run into a single commit.
```

---

## Decision Criteria

| Question | Answer affects |
|----------|---------------|
| Is 90-day Actions log retention enough? | Whether to implement B at all |
| How important is tracing Bot coordination (group chats)? | Whether to invest in E or accept the gap |
| Is commit noise in koenswings/idea acceptable? | B vs C |
| Do you want machine-readable data for future dashboards? | B/C over D/E |

---

## Status

Not implemented. The migration phases do not include audit trail setup. This will be a separate task initiated after the migration is complete and the Grok Bot setup is stable.
