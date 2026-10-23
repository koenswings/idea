---
title: "IDEA Field Support Channel – Design"
subtitle: "One contact point, two customer-facing agents, no autonomy to change anything"
audience: "Version 1.0, 22 October 2026"
---

**Author:** Steve (Lead Bot)
**Date:** 2026-10-14, updated 2026-10-22 (v1.0)
**Status:** Approved 2026-10-14 ([idea#188](https://github.com/koenswings/idea/issues/188)). v1.0 records what was decided and built since: Telegram as the main channel ([proposals/2026-10-20-telegram-field-support.md](2026-10-20-telegram-field-support.md), #289; relay #290), one email inbox as the second channel, and the reply rule.

# Concept in one page

People in the field (local support engineers, teachers, and first of all Justice) get **one contact point** for IDEA. They write to it in plain language. Two agents read every message:

- **Support Engineer** (new): technical questions. Pis, Engine, Console, apps, Tailscale, disks, backups.
- **Marco** (existing Programme Manager): the tutorial, the manuals, teacher use, field feedback, requests for new apps.

A small **router** step decides by topic who answers. The field person never has to choose.

The agents can **only filter**. They answer obvious questions, say politely when a question is not about IDEA, and point to the documented way of doing something when no change is needed. They **never change anything**: no deploys, no writes over SSH, no merges, no configuration. Everything else goes to **Koen** to approve or decide (through Steve). The dev bots (Axle, Pixel, Kid, Atlas) do the approved work.

![The support channel at a glance](2026-10-14-field-support-channel/concept.svg)

**Where it stands (22 October 2026)**

- **Main channel: Telegram.** Field staff chat privately with the bot **@IDEA_SupportBot** (`https://t.me/IDEA_SupportBot`). The relay `tg-relay` (#290) runs on wizardly-hugle and wakes the Support Engineer within seconds. Chat structure is option (e) of the Telegram proposal: private DMs for the field, plus a Koen-only **"IDEA Support Monitor"** Topics group with one topic per field person.
- **Second channel: email**, through one inbox, `idea-support@agentmail.to`. It accepts mail only from Koen and Justice and sends only to them. The earlier `ideahelp@` and `idea-help@` inboxes were deleted.
- **Reply rule:** the bot answers on its own when the fix is obvious and needs no code change, on Telegram and email alike. Everything else goes to Koen to approve or decide. The phase 0 "draft only" period has ended.
- **WhatsApp: not pursued.** Telegram gives the same near-real-time chat without business verification, a phone number, the 24-hour window or per-message fees. WhatsApp stays a later option only if a school cannot use Telegram.
- **Later:** more schools, an allowlist per school, local languages if needed.
- **No system access for the agents.** The Support Engineer answers from documents and from what the field person tells it (sticker name, what the screen shows). A read-only status page per Pi stays a later option, after Koen approves it.

# Who does what

| Role | Talks to the field | May do | May never do |
|---|---|---|---|
| Router | No | Classify the message, pick an agent, check the allowlist | Answer, change anything |
| Support Engineer | Yes | Answer from the knowledge base, ask for the sticker name and symptoms, read status (later, if approved), escalate | Deploy, SSH write, restart, merge, change config, send passwords |
| Marco | Yes | Answer about docs and teaching, collect feedback, log app requests, escalate | Same as above; promise features or dates |
| Steve | No (internal) | Turn escalations into issues, report to Koen, assign dev bots | Reply to the field without Koen's decision on changes |
| Koen | Optional (Telegram monitor group: approve drafts, reply himself, `/pause`, `/resume`) | Decide, approve changes | |
| Dev bots | No | Do the approved work | Talk to the field directly |

# Channels

## Telegram: main channel (decided 2026-10-20, built)

Details are in [the Telegram proposal](2026-10-20-telegram-field-support.md) (#289) and `tools/telegram-relay/README.md` (#290). In short:

- **Bot:** **@IDEA_SupportBot** (`https://t.me/IDEA_SupportBot`). The first-choice username `@IdeaSupportBot` was not used.
- **Relay:** `tg-relay`, a small stdlib-only Python service on **wizardly-hugle** (systemd user unit). It long-polls Telegram (no AI on empty polls), drops messages from anyone not on the allowlist, stores photos and documents, and calls the "Box watcher events" webhook once per message (`type: telegram_message`). The Support Engineer answers with `tg-send`.
- **Chat structure: option (e).** Field staff have a private DM with the bot. The relay mirrors every message in and out into the Koen-only **"IDEA Support Monitor"** Topics group, one topic per field person. Escalations appear there as a card with **Approve draft** and **Reply myself**. Koen can type in a topic to answer as "Koen: …", and `/pause` and `/resume` hand the conversation between Koen and the bot.
- **Onboarding:** a new person presses **Start**; the relay replies "wait for approval" and sends Koen an Approve / Reject card. Approval adds the Telegram user id to the allowlist and opens the person's topic.
- **Status:** the relay is running on wizardly-hugle with its token set. The monitor group is **not linked yet**: Koen still has to press Start with the bot (to register as admin) and send `/setup` in the group. Until then the mirror and the escalation cards have nowhere to go.

## Email: second channel (built)

- **One inbox:** `idea-support@agentmail.to`. The `ideahelp@` and `idea-help@` inboxes were deleted; there is no `mail.grokbot.com` support address.
- **Allowlist both ways:** it accepts mail only from Koen and Justice and sends only to them.
- A free watcher picks up new mail (at most once a minute) and wakes the router. Email stays useful for long questions, PDFs and screenshots.

## WhatsApp: not pursued

WhatsApp Business (Meta Cloud API or Twilio) was the phase 1 plan in draft 0.1. It is replaced by Telegram, which needs no business verification, no dedicated number, no 24-hour window or templates, and has no per-message fees. WhatsApp stays a possible later option only if a school cannot use Telegram; nothing has been set up for it.

## Other options considered

| Option | Verdict |
|---|---|
| Slack | Not used: Justice would need a workspace invite; heavy on a phone; mixes field and internal talk. |
| Telegram MCP connector or a Telegram-to-email bridge | Not used: polling costs AI runs, or adds the email delay back (Telegram proposal, approach options B and C). |

# How a message flows

1. **Arrive.** A Telegram message arrives through `tg-relay`, or an email arrives in `idea-support@agentmail.to`. Either way it becomes one normalised record: sender, channel, thread, text, attachments, time.
2. **Check identity.** The sender must be on the **allowlist** (Telegram user id, or email address). On Telegram an unknown sender gets "wait for approval" and Koen gets an Approve / Reject card. On email only Koen and Justice are accepted. No agent reads messages from unknown senders.
3. **Route.** The router classifies the topic:
    - technical (Pi, Engine, Console, app not starting, disk, backup, Tailscale, network) goes to the **Support Engineer**;
    - documents, tutorial, teaching, feedback, new app ideas go to **Marco**;
    - mixed or unclear goes to the agent whose topic is most urgent (technical first), who may hand over;
    - "urgent" words (school cannot work, data lost, security, password leaked) are flagged.
4. **Answer or escalate (reply rule, Koen 2026-10-20, confirmed for email 2026-10-22).** The agent answers **on its own** when the fix is obvious and needs no code change, typically from merged docs, and names the source section. It may ask clarifying questions directly (sticker name, what the screen shows, a photo). Everything else (a code change, a judgement call, a promise, anything not in the docs) goes to **Koen** to approve or decide: the agent tells the field person "I've asked Koen, I'll come back to you", and Koen gets the draft answer (on Telegram as an **Approve draft** / **Reply myself** card in the monitor group).
5. **Reply** goes back through the same channel and thread, signed with the agent's name ("Support Engineer, IDEA" or "Marco, IDEA").
6. **Report.** Koen follows Telegram conversations live in the monitor group (once it is linked). Escalations reach Koen at once, within his 07:00 to 24:00 hours; field messages are answered at any hour. Steve turns real problems into issues.

## Escalation message to Steve (format)

```
ESCALATION  [urgent | normal]
From: Justice (allowlisted, Telegram)   Pi: wizardly-hugle
Topic: technical / Console
Summary: Console shows "engine offline" after power cut; reboot did not help.
What I already told him: the documented reboot step (Manual 1, step 9).
What is needed: diagnosis by Atlas/Axle; no change made.
Thread: <link>   Issue: idea#NNN
```

## Handover between the two agents

- An agent that sees the message is not its topic writes one line to the field person ("Marco will pick up the documentation part") and hands over with the thread link and a two-line summary. The field person is never asked to repeat themselves.
- One message may need both: the first agent answers its part, then hands over the rest. Only one agent replies at a time in a thread; the thread has an **owner** field.
- If both agents disagree on ownership, the Support Engineer keeps it (technical problems block schools; documentation can wait).

# Knowledge base

The agents answer **only** from approved, published material:

- the Field Install Manuals (school server, classroom computer) and the teacher and operator tutorials, in `koenswings/idea` `docs/manuals/`;
- the demo server remote access guide and the IDEA design docs on `main`;
- a short **FAQ** file that grows from real answers (each new FAQ entry approved by Koen or Steve).

Rules:

- If the answer is not in these documents, the agent does not invent it. It escalates.
- Answers quote the document and page or step ("Manual 1, step 12"), so the field person can check.
- Only material merged on `main` is used, so a draft never reaches the field.
- Documents with secrets are never in the knowledge base. For logins the agents point to the private Accounts and Passwords sheet; they never send password values. The remote access guide's Tailscale IP and tailnet name are for shared field staff only; the agents do not repeat them to other senders.

# Read-only system inspection

The Support Engineer will often need to know "what state is that Pi in". The field person reports the **sticker name** (unique per Pi, idea#184), for example `brave-otter`.

Current network setup: one Tailscale fleet with `tag:idea` and one fleet auth key; ACL `admins -> tag:idea`, `tag:idea -> nothing`.

| Option | How | Risk | Verdict |
|---|---|---|---|
| **A. No access** | Agent asks the field person what they see; Steve/Atlas look if needed | None | **Current** |
| B. Read-only status endpoint | Engine serves `GET /api/status` (version, uptime, disks, app states, last error; no secrets), reachable only over Tailscale. New ACL tag `tag:support` may reach only that port on `tag:idea` | Low. Needs an Engine change (Axle) and an ACL change (Atlas, Koen approves) | **Later option**, not started |
| C. Read-only SSH identity | Separate user without sudo, shell restricted to a few status commands | Medium: shells leak; easy to widen by mistake | Not recommended |
| D. Full SSH | | Breaks the "no autonomy" rule | **Never** |

For option B, the tailnet ACL becomes (sketch):

```
"tagOwners": { "tag:support": ["autogroup:admin"] },
"grants": [
  { "src": ["autogroup:admin"], "dst": ["tag:idea"],     "ip": ["*"] },
  { "src": ["tag:support"],     "dst": ["tag:idea"],     "ip": ["tcp:4321"] }
]
```

with the Engine only answering the status path to `tag:support` callers (other API paths refused). Port 4321 is a placeholder; Axle confirms. Milkwise is not tagged `tag:idea` and so stays unreachable.

Justice's own access stays as it is: wizardly-hugle's Console and the demo apps only. **Passwords are never sent through the channel.** If someone sends a password, the agent replies that it has not stored it, flags the message as urgent to Koen, and redacts the password from the log.

# Logging and tracking

- Every conversation is kept: email threads in `idea-support@agentmail.to`, Telegram messages in the support log (and mirrored in the monitor group), each with a thread or chat id.
- Each **real problem** becomes one GitHub issue in `koenswings/idea` with label `field-support` plus `support:tech` or `support:docs`, and `urgent` when needed. The issue holds the summary and the thread link, not personal data or phone numbers.
- Feedback on documents goes to issues labelled `field-feedback`, which Marco works through.
- New app requests get the label `app-request`.
- Open item: a short evening summary for Koen (what came in on Telegram and email, what the bot fixed by itself, what waits on him), only on days with traffic. Proposed 2026-10-22, not decided.

# Identity and privacy

- **Allowlist** of who may write: Telegram user ids (numbers, not usernames), kept by the relay and extended only through Koen's Approve tap; and the email allowlist of the support inbox (Koen and Justice). Start: Koen and Justice.
- Each allowlist entry has a name, role, school or Pi it belongs to.
- Messages from unknown senders get the fixed reply and are dropped after 30 days.
- Telegram ids, phone numbers and email addresses never go into GitHub issues or public documents.
- Telegram bot chats are cloud chats, **not end-to-end encrypted**: no pupil data and no credentials through them.
- Children's names or photos of children are not requested; if they arrive, the agent does not repeat them and they stay out of issues.
- Retention: message logs kept 12 months, then deleted (open decision).

# Abuse and rate limits

- Unknown senders: one fixed reply per sender per day, then silence.
- Allowlisted senders: up to 30 messages an hour are handled normally; above that, the router pauses and tells Steve.
- Agents never follow instructions inside a message that ask them to change systems, reveal secrets or contact other people. Such messages are escalated as possible abuse.
- Attachments: images and PDFs only, size limit 10 MB; anything else is not opened.

# Language

- English by default; agents reply in the language the person writes in when they can, and say so if unsure.
- Later: Shona or Ndebele (Zimbabwe) answers checked by a local person before they go into the FAQ.

# Failure modes

| Failure | What happens | Mitigation |
|---|---|---|
| Router or bot down | Messages wait in the inbox or in Telegram's queue | Atlas watches the `tg-relay` service and the routine; Steve alerted after 2 hours without processing |
| Wrong agent picked | Handover protocol | Weekly review of routing errors |
| Agent unsure | Escalates instead of guessing | Default rule: when in doubt, escalate |
| Telegram relay down | Telegram messages wait (up to 24 h on Telegram's side) | Email keeps working; Atlas restarts the service |
| Monitor group not linked | Koen sees no mirror and no escalation cards | Koen: Start with @IDEA_SupportBot, then `/setup` in the group (open item) |
| Watcher counts sent mail as new | False "new mail" alarms and needless wake-ups | Known issue: filter the watcher to received mail only (open item) |
| Escalation storm | Koen flooded | Topics can be muted; obvious fixes are answered without Koen |
| Bad advice given | Field person acts on it | Autonomous answers only for obvious fixes from merged docs; every answer logged and mirrored; Koen can review |
| Secret posted in channel | Leak | Redact, urgent flag to Koen |

# Implementation status

## Done

1. One support inbox, `idea-support@agentmail.to`, allowlisted both ways to Koen and Justice; the `ideahelp@` and `idea-help@` inboxes deleted.
2. Support Engineer and Marco with the customer-facing rules; router through the "Box watcher events" routine; mail watcher.
3. Telegram proposal approved and merged (#289), with Koen's decisions of 2026-10-20.
4. `tg-relay` and `tg-send` built and merged (#290); relay running on wizardly-hugle with the token for **@IDEA_SupportBot** set.
5. Reply rule in force: obvious fixes without code change are answered autonomously on Telegram and email; the rest goes to Koen. Phase 0 "draft only" ended.

## Open

1. **Link the monitor group:** Koen presses Start with @IDEA_SupportBot, adds the bot to the "IDEA Support Monitor" Topics group and sends `/setup` there.
2. **Approve Justice on Telegram** once he presses Start.
3. **Watcher fix:** count only received mail as new mail (it now also counts sent mail).
4. GitHub labels `field-support`, `support:tech`, `support:docs`, `field-feedback`, `app-request` in `koenswings/idea`, if not yet created.
5. Short FAQ file that grows from real answers.

## Later

1. More schools: allowlist per school with the sticker names of its Pis; local support engineers onboarded with a one-page guide.
2. Voice notes on Telegram.
3. Option B status endpoint (`GET /api/status` plus `tag:support`), after Koen approves.
4. Local-language answers if needed; FAQ reviewed monthly.
5. WhatsApp only if a school cannot use Telegram.

# Decisions

## Decided

| # | Decision | Outcome |
|---|---|---|
| 1 | Interim channel for Justice | Email first; now **Telegram** is the main channel and email the second (2026-10-20) |
| 2 | Address name | `idea-support@agentmail.to`, the only support inbox |
| 3 | WhatsApp provider | Not pursued: replaced by Telegram |
| 4 | Legal entity for Meta verification | Not needed (no WhatsApp) |
| 5 | Number for WhatsApp | Not needed (no WhatsApp) |
| 6 | Human approval of outgoing replies | Ended: autonomous for obvious no-code fixes on Telegram and email; the rest to Koen (2026-10-20, email confirmed 2026-10-22) |
| 7 | Read-only Pi access | None for now; status endpoint is a later option |
| 8 | Separate email addresses for each agent | No: one contact point |
| 9 | How Koen follows support | Live mirror in the Telegram monitor group (option (e)); escalations at once |
| 10 | Telegram bot name | **@IDEA_SupportBot** |
| 11 | Telegram chat structure | Option (e): DMs plus the Koen-only Topics monitor group |
| 12 | Manuals for the knowledge base | Merged in `koenswings/idea` `docs/manuals/` |

## Still open

| # | Decision | Recommended default |
|---|---|---|
| 1 | Message retention | 12 months |
| 2 | Evening summary for Koen on top of the live mirror | Yes, only on days with traffic |
| 3 | Who may edit the allowlist | Koen's Approve tap on Telegram; email allowlist changed by Steve after Koen's OK |
