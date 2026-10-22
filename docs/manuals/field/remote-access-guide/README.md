**Status:** Authoritative · **Maintained by:** Marco (with Atlas) · 22 October 2026

# Remote access guide (demo server over Tailscale)

`idea-demo-server-remote-access-guide-v1.2.pdf` ("IDEA Demo Server: Remote Access", v1.2, 23 pages): Part A for the IDEA
admin (share the demo server idea (earlier name wizardly-hugle) from the IDEA tailnet), Part B for the field engineer (install Tailscale, accept
the share, open the Console and the demo apps, get help from the IDEA support bot @IDEA_SupportBot). Logins come from the
IDEA Kit: Accounts and Passwords sheet.

| File | What |
|---|---|
| `remote-access-guide.md` | Source text (house-style front matter) |
| `build.py` | `python3 build.py` → `idea-demo-server-remote-access-guide-v<version>.pdf` (version from the front matter); regenerates the diagrams; fails on to-confirm markers, placeholders, run-together bullets or unrendered Markdown in the source or the PDF |
| `diagrams/make_diagrams.py` | Generates `overview.svg`, `flow.svg`, `privacy.svg`, `checks.svg` |

**Deliberate exception to the no-secrets rule (DOCUMENTATION-RULES.md rule 10):** this guide contains idea's
Tailscale address (`100.115.60.6`), its Tailscale machine name and the tailnet name, because the field engineer types them.
They are not credentials: only devices that Koen shares the machine with can reach it. No passwords, keys or tokens are in
this guide; logins are in the private Accounts and Passwords sheet.
