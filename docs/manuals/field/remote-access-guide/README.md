**Status:** Authoritative · **Maintained by:** Marco (with Atlas) · 14 October 2026

# Remote access guide (demo server over Tailscale)

`remote-access-guide.pdf` ("IDEA Demo Server: Remote Access for Justice", 22 pages): Part A for Koen (share the demo
server wizardly-hugle from his tailnet), Part B for the field engineer (install Tailscale, accept the share, open the Console
and apps).

| File | What |
|---|---|
| `remote-access-guide.md` | Source text (house-style front matter) |
| `build.py` | `python3 build.py` → `remote-access-guide.pdf`; regenerates the diagrams; fails on to-confirm markers, placeholders, run-together bullets or unrendered Markdown in the source or the PDF |
| `diagrams/make_diagrams.py` | Generates `overview.svg`, `flow.svg`, `privacy.svg`, `checks.svg` |

**Deliberate exception to the no-secrets rule (DOCUMENTATION-RULES.md rule 10):** this guide contains wizardly-hugle's
Tailscale address (`100.115.60.6`), its Tailscale machine name and the tailnet name, because the field engineer types them.
They are not credentials: only devices that Koen shares the machine with can reach it. No passwords, keys or tokens are in
this guide; Koen sends the passwords separately.
