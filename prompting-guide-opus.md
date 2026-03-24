# Prompting Guide — Claude (Opus / Sonnet)

This file captures Anthropic's prompting best practices for Claude's current models (Opus 4.6,
Sonnet 4.6). Reference it when writing or updating any `AGENTS.md` file to ensure role
definitions follow Claude's documented conventions.

Source: https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-prompting-best-practices

---

## Core Principles

### Be clear and direct
Claude responds to precise, explicit instructions. Think of Claude as a new but brilliant
employee: it lacks context on your norms and workflows. The more precisely you explain what
you want, the better the result.

**Golden rule:** Show the prompt to a colleague with no project context. If they'd be confused,
Claude will be too.

- Be specific about desired output format and constraints.
- Use numbered lists or bullets when the order or completeness of steps matters.

### Add context and motivation
Explain *why* a rule exists, not just what it is. Claude generalises from explanations.

| Less effective | More effective |
|---|---|
| `NEVER use ellipses` | `Never use ellipses — the text-to-speech engine cannot pronounce them` |
| `Keep responses short` | `Responses go to a phone UI — long messages are hard to read on mobile` |

### Use examples
Few-shot examples are the most reliable way to steer output format, tone, and structure.

- **Relevant:** Mirror the actual use case.
- **Diverse:** Cover edge cases; vary enough that Claude doesn't pick up unintended patterns.
- **Structured:** Wrap examples in `<example>` tags; multiple examples in `<examples>` tags.

Aim for 3–5 examples for best results.

### Structure prompts with XML tags
XML tags help Claude parse complex prompts unambiguously when mixing instructions, context,
examples, and variable inputs. Use consistent, descriptive tag names:

```xml
<instructions>…</instructions>
<context>…</context>
<examples>…</examples>
<input>…</input>
```

Nest tags for hierarchical content (e.g. `<documents>` → `<document index="n">`).

### Give Claude a role
A single sentence in the system prompt focuses Claude's behaviour and tone:

> "You are the Engine software developer for IDEA. Your work runs unattended in rural schools
> with no IT support — reliability is paramount."

---

## Output and Formatting

### Verbosity
Claude's latest models are more concise and direct than earlier versions. They may skip
summaries after tool calls and jump to the next action. If you need more visibility into
reasoning, prompt for it explicitly:

> "After completing a task that involves tool use, provide a quick summary of what you did."

### Prose over bullets
For `AGENTS.md` role definitions, prefer flowing prose for narrative sections. Reserve lists
for genuinely discrete, order-sensitive steps.

To minimise excessive markdown in agent responses, include this in AGENTS.md:

```
Write responses in clear prose. Use bullet lists only for genuinely discrete items.
Do not use bold, headers, or markdown decoration in chat responses.
```

### Tell Claude what to do, not what to avoid
- Instead of: "Do not use markdown"
- Try: "Write responses as smoothly flowing prose paragraphs."

### Long context inputs
When passing large files (20k+ tokens):
- Put long documents **at the top** of the prompt, before queries and instructions.
- Place queries and instructions **at the end** — this can improve quality by up to 30%.
- Use `<document>` XML tags with `<source>` and `<document_content>` subtags.
- Ask Claude to quote relevant passages before analysing them.

---

## Agentic Systems (most relevant for IDEA)

### Scope instructions precisely
Each agent's `AGENTS.md` should state what is explicitly in scope and out of scope. Claude
follows explicit constraints reliably. Ambiguity leads to scope creep.

### Constrain output types
Name the exact deliverables expected from a task:

> "Your output is a PR. A PR for a code change contains: code diff, tests, updated
> documentation. Nothing is done until the PR is open."

### Inject shared knowledge by reference
Don't duplicate facts across `AGENTS.md` files. Reference `../../CONTEXT.md` for shared
product knowledge. This avoids drift when facts change.

### One source of truth per concern
- Values and behaviour → `SOUL.md`
- Role-specific instructions → `AGENTS.md` (per agent)
- Product and mission knowledge → `CONTEXT.md` (org root)

Updating one file updates the relevant agents automatically.

### Prevent unintended chaining
When an agent's output triggers another agent (e.g. auto-review), use explicit stop conditions
in the triggered agent's instructions:

> "This is a depth-1 auto-review task. Do not create further tasks, proposals, or PRs."

### Security: external content ingestion
Agents that read external sources (grant databases, websites, partner materials) must:
1. **Summarise, never parrot** — restate findings in own words; never paste raw external content.
2. **No external writes** — produce documents for CEO review; CEO takes any external action.
3. **No secrets in documents** — no API keys, tokens, or credentials in any markdown or git commit.

---

## Writing AGENTS.md — Practical Checklist

When proposing an update to any `AGENTS.md`:

- [ ] Role sentence is a single clear statement of purpose
- [ ] Scope section lists what is explicitly IN scope and OUT of scope
- [ ] Tech stack or domain knowledge is listed, not assumed
- [ ] Deliverable format is named explicitly (PR, design doc, proposal, report)
- [ ] External action constraints are present if the agent touches external services
- [ ] Security rules are present if the agent ingests external content
- [ ] `CONTEXT.md` is referenced for shared product knowledge (not duplicated)
- [ ] Instructions use positive framing ("do X") not just prohibitions ("don't do Y")
- [ ] Long step-by-step flows use numbered lists; narrative sections use prose

---

*Last updated: 2026-03-24. Source: Anthropic Claude prompting best practices (claude-opus-4-6).*
