---
title: "IDEA Field Support Channel – Design"
subtitle: "One contact point, two customer-facing agents, no autonomy to change anything"
audience: "Proposal · Status: Approved (Koen Swings, 14 October 2026)"
---

**Author:** Steve (Lead Bot)
**Date:** 2026-10-14
**Status:** Approved (Koen agreed in chat 2026-10-14; merging this PR confirms it)

# Concept in one page

People in the field (local support engineers, teachers, and first of all Justice) get **one contact point** for IDEA. They write to it in plain language. Two agents read every message:

- **Support Engineer** (new): technical questions. Pis, Engine, Console, apps, Tailscale, disks, backups.
- **Marco** (existing Programme Manager): the tutorial, the manuals, teacher use, field feedback, requests for new apps.

A small **router** step decides by topic who answers. The field person never has to choose.

The agents can **only filter**. They answer obvious questions, say politely when a question is not about IDEA, and point to the documented way of doing something when no change is needed. They **never change anything**: no deploys, no writes over SSH, no merges, no configuration. Everything else becomes a report to **Steve**, who passes it to **Koen**. Steve and Koen decide; the dev bots (Axle, Pixel, Kid, Atlas) do the work.

![The support channel at a glance](2026-10-14-field-support-channel/concept.svg)

**Recommendation in short**

- **This week (phase 0):** Justice writes to one email address, `support@mail.grokbot.com` (name to be chosen by Koen). Inbound email wakes the router. Nothing to buy, no verification, usable from his phone in Zimbabwe.
- **Phase 1 (2 to 4 weeks):** one WhatsApp Business number through the Meta Cloud API directly (or Twilio if Koen prefers one bill and a simpler console). Same router, same agents.
- **Phase 2:** more schools, an allowlist per school, local languages if needed.
- **No system access for the agents at first.** The Support Engineer answers from documents and from what the field person tells it (sticker name, what the screen shows). A read-only status page per Pi comes later, after Koen approves it.

# Who does what

| Role | Talks to the field | May do | May never do |
|---|---|---|---|
| Router | No | Classify the message, pick an agent, check the allowlist | Answer, change anything |
| Support Engineer | Yes | Answer from the knowledge base, ask for the sticker name and symptoms, read status (phase 1+, if approved), escalate | Deploy, SSH write, restart, merge, change config, send passwords |
| Marco | Yes | Answer about docs and teaching, collect feedback, log app requests, escalate | Same as above; promise features or dates |
| Steve | No (internal) | Turn escalations into issues, batch reports to Koen, assign dev bots | Reply to the field without Koen's decision on changes |
| Koen | Optional | Decide, approve changes | |
| Dev bots | No | Do the approved work | Talk to the field directly |

# Channel options (researched 14 October 2026)

## WhatsApp Business Platform

All providers sit on top of Meta's WhatsApp Business Platform, so the rules are the same everywhere:

- **24-hour window.** When a user writes, a customer-service window opens for 24 hours after their last message. Inside it we may send free-form replies. Outside it we may only send a pre-approved **template** message (for example "We have an update on your question, reply to see it").
- **Prices since 1 October 2026** (Meta, Zimbabwe is in "Rest of Africa"): inbound messages are free; free-form service replies are free for the first 1,000 per number per month, then about USD 0.004 each; utility templates about USD 0.004; marketing templates about USD 0.0225. Belgian numbers (+32) are priced differently but our volume is tiny.
- **Number.** It must be a number that can receive one SMS or voice call for verification, and that is **not** in use in the normal WhatsApp app (or is migrated off it). A cheap new SIM or a virtual number works.
- **Business verification.** Meta verification of the business (IDEA or Koen's company) is free but "can take several weeks"; Twilio estimates 1 to 2 weeks. Before verification, a number can still be used with limits (small number of new contacts per day), which is enough for a pilot.

| Provider | Extra cost on top of Meta | Lead time | Notes |
|---|---|---|---|
| **Meta Cloud API direct** | None | Hours for a test number; 1 to 3 weeks for verification and display name | Cheapest. Webhook straight to us. We maintain the integration. |
| **Twilio** | USD 0.005 per message, in and out | Self sign-up in about an hour; Meta verification 1 to 2 weeks | Simplest console, good docs, free trial sandbox (shared number, not for real users). |
| Bird, Infobip, Sinch | Platform fees or monthly plans, quote-based | Similar, plus sales contact | Aimed at large contact centres. No benefit at our size. |

At our size (tens of messages a week) WhatsApp costs **well under USD 5 a month** with any of these. Cost is not the deciding factor; lead time and simplicity are.

**Recommendation:** Meta Cloud API direct, with Twilio as the fallback if Meta's onboarding blocks us. Start business verification **now**, because it is the slowest step and costs nothing.

## Fast interim channels (this week)

| Option | Set-up time | Pros | Cons |
|---|---|---|---|
| **Email to a claimed bot inbox** | Minutes, once Koen picks the address | Built in; inbound mail can wake a routine; attachments (screenshots, PDFs) work; full written record; nothing to buy | Less immediate than chat; Justice must use email on his phone |
| Telegram bot | About an hour | Free, instant, easy bot API, works on weak connections | Another app for Justice; needs a bot token and a small webhook service; not the long-term channel |
| Slack | About an hour | Already familiar for the team | Justice needs to be invited to a workspace; heavy on a phone; mixes field and internal talk |

**Recommendation:** **email** for phase 0. It needs no new infrastructure, it is the same pattern the agents already use, and the router logic carries over unchanged to WhatsApp later. Telegram is the backup if Justice prefers chat.

# How a message flows

1. **Arrive.** Email arrives in the support inbox (phase 0), or a WhatsApp webhook arrives (phase 1). Either way it becomes one normalised record: sender, channel, thread, text, attachments, time.
2. **Check identity.** The sender must be on the **allowlist** (email address or phone number). Unknown senders get one polite fixed reply ("This channel is for IDEA field partners. Please ask your IDEA contact to add you.") and are logged; no agent reads further.
3. **Route.** The router classifies the topic:
    - technical (Pi, Engine, Console, app not starting, disk, backup, Tailscale, network) goes to the **Support Engineer**;
    - documents, tutorial, teaching, feedback, new app ideas go to **Marco**;
    - mixed or unclear goes to the agent whose topic is most urgent (technical first), who may hand over;
    - "urgent" words (school cannot work, data lost, security, password leaked) are flagged.
4. **Answer or escalate.** The agent answers only if the answer is in the knowledge base and needs no change. Otherwise it tells the field person "I have passed this to the team" and writes an **escalation** to Steve.
5. **Reply** goes back through the same channel and thread, signed with the agent's name ("Support Engineer, IDEA" or "Marco, IDEA").
6. **Report.** Steve gets each escalation with a short summary. Steve reports to Koen in a **daily batch**; urgent ones go to Koen **at once**.

## Escalation message to Steve (format)

```
ESCALATION  [urgent | normal]
From: Justice (allowlisted, email)   Pi: wizardly-hugle
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

- the teacher tutorial PDF (agent-app-dev #14);
- install manuals 1 and 2, the Justice access guide, the lesson manuals (agent-app-dev #15);
- the agent-app-dev `docs/` folder and the IDEA design docs on `main`;
- a short **FAQ** file that grows from real answers (each new FAQ entry approved by Koen or Steve).

Rules:

- If the answer is not in these documents, the agent does not invent it. It escalates.
- Answers quote the document and page or step ("Manual 1, step 12"), so the field person can check.
- Only material merged on `main` is used, so a draft never reaches the field.
- Documents with secrets are never in the knowledge base. The Justice guide's Tailscale IP and tailnet name are fine for Justice only; the agents do not repeat them to other senders.

# Read-only system inspection

The Support Engineer will often need to know "what state is that Pi in". The field person reports the **sticker name** (unique per Pi, idea#184), for example `brave-otter`.

Current network setup: one Tailscale fleet with `tag:idea` and one fleet auth key; ACL `admins -> tag:idea`, `tag:idea -> nothing`.

| Option | How | Risk | Verdict |
|---|---|---|---|
| **A. No access (phase 0)** | Agent asks the field person what they see; Steve/Atlas look if needed | None | **Start here** |
| B. Read-only status endpoint | Engine serves `GET /api/status` (version, uptime, disks, app states, last error; no secrets), reachable only over Tailscale. New ACL tag `tag:support` may reach only that port on `tag:idea` | Low. Needs an Engine change (Axle) and an ACL change (Atlas, Koen approves) | **Recommended for phase 1** |
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

Justice's own access stays as it is: wizardly-hugle's Console and the demo apps only. **Passwords are never sent through the channel and never written in documents.** If someone sends a password, the agent replies that it has not stored it, advises changing it, and flags the message as urgent to Steve; the password is redacted from the log.

# Logging and tracking

- Every conversation is kept in the bot inbox (phase 0) or a message log (phase 1), with a thread id.
- Each **real problem** becomes one GitHub issue in `koenswings/idea` with label `field-support` plus `support:tech` or `support:docs`, and `urgent` when needed. The issue holds the summary and the thread link, not personal data or phone numbers.
- Feedback on documents goes to issues labelled `field-feedback`, which Marco works through.
- New app requests get the label `app-request`.
- Steve's daily batch to Koen lists: new issues, answered-only threads (count), urgent items.

# Identity and privacy

- **Allowlist** of who may write: email addresses (phase 0) and phone numbers (phase 1), kept in one private file in the box store, edited only by Steve on Koen's approval. Start: Justice only.
- Each allowlist entry has a name, role, school or Pi it belongs to.
- Messages from unknown senders get the fixed reply and are dropped after 30 days.
- Phone numbers and email addresses never go into GitHub issues or public documents.
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
| Router or bot down | Messages wait in the inbox / provider queue | Atlas health check on the routine; Steve alerted after 2 hours without processing |
| Wrong agent picked | Handover protocol | Weekly review of routing errors |
| Agent unsure | Escalates instead of guessing | Default rule: when in doubt, escalate |
| WhatsApp 24h window closed | Free-form reply not allowed | Approved utility template "We have an update, please reply to see it" |
| Meta verification delayed or refused | Phase 1 slips | Email keeps working; Twilio as fallback |
| Escalation storm | Koen flooded | Batching; only urgent goes direct |
| Bad advice given | Field person acts on it | Answers only cite merged docs; every answer logged; Koen can review |
| Secret posted in channel | Leak | Redact, advise rotation, urgent flag |

# Implementation steps

## Phase 0: Justice by email (this week, target before 19 October)

1. Koen chooses one address, for example `idea-support@mail.grokbot.com`. Steve claims it (one approval card). The Support Engineer and Marco may get their own addresses later; phase 0 uses one shared address for the single contact point.
2. Create the **Support Engineer** agent with a fixed instruction set: role, the knowledge base list, the no-change rules, the escalation format.
3. Give Marco the same customer-facing rules for his field role.
4. Create the **router routine**: triggered by inbound email to the support inbox; checks the allowlist; classifies; wakes the chosen agent with the thread.
5. Replies: the agent drafts the reply; **for the first two weeks Koen or Steve approves each outgoing reply** before it is sent. After that, answers that only cite documents go out directly; escalation notices stay automatic.
6. Escalations go to Steve via agent message; Steve opens the GitHub issue and adds it to Koen's batch.
7. Labels `field-support`, `support:tech`, `support:docs`, `field-feedback`, `app-request` created in `koenswings/idea`.
8. Knowledge base: point the agents at merged agent-app-dev #14 and #15 (merge needed first) and the FAQ file.
9. Send Justice a short welcome note (Koen approves): the address, what to send (sticker name, what he sees, a photo), what not to send (passwords).
10. Test: three test emails (technical, documents, out of scope) before Justice uses it.

## Phase 1: one WhatsApp number (start now, live in 2 to 4 weeks)

1. Get a dedicated SIM or virtual number not used in the WhatsApp app.
2. Create a Meta Business portfolio and start **business verification** (slowest step).
3. Create the WhatsApp Business Account in Meta Cloud API; verify the number by SMS; set display name "IDEA Support".
4. Small webhook receiver (HTTPS) that turns Meta webhooks into the same normalised record and wakes the router; replies via the Cloud API send endpoint.
5. Submit two utility templates: "update on your question" and "we received your message".
6. Add Justice's phone number to the allowlist; keep email working in parallel.
7. Option B status endpoint: Axle builds `GET /api/status`, Atlas adds `tag:support`; both after Koen approves.

## Phase 2: more schools

1. Allowlist per school with the sticker names of its Pis.
2. Local support engineers onboarded with a one-page guide.
3. FAQ reviewed monthly; local-language answers if needed.
4. Monthly cost and usage report from Steve.

# Open decisions for Koen

| # | Decision | Recommended default |
|---|---|---|
| 1 | Interim channel for Justice | Email to one bot inbox |
| 2 | Address name | `idea-support@mail.grokbot.com` |
| 3 | WhatsApp provider | Meta Cloud API direct; Twilio as fallback |
| 4 | Which legal entity does Meta verification | Koen's organisation behind IDEA |
| 5 | Number for WhatsApp | New dedicated SIM or virtual number, not a personal one |
| 6 | Human approval of outgoing replies at start | Yes, for the first two weeks |
| 7 | Read-only Pi access | None in phase 0; status endpoint + `tag:support` in phase 1 |
| 8 | Separate email addresses for each agent | Not now; one contact point first |
| 9 | Report rhythm to Koen | Daily batch; urgent immediately |
| 10 | Message retention | 12 months |
| 11 | Who may edit the allowlist | Steve, after Koen's OK |
| 12 | Merge agent-app-dev #14 and #15 so the agents can use them | Yes, before Justice leaves |
