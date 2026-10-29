# Device identity + flash tool (idea#322, Stage 2)

A release image is generic. Each device gets a small **identity file**, written to the card's boot partition at flash time.

* **Where:** on the bot computer only, `~/.config/idea-identities/<name>.identity` (dir 0700, file 0600). Never in git:
  the tools refuse files inside a git repository and files holding a raw `tskey-*` key.
* **Format** (plain `KEY=VALUE`, parsed, never sourced; see `identity-lib.sh`): `IDEA_IDENTITY=1`, `TYPE` (client|router),
  `NAME`, `TIMEZONE`, `HOME_MODE` (home Engine name or `none`), `TAILSCALE_KEY_REF` (path to a 0600 key file, or `none`).
* `idea-identity.sh new|check|show|list` manages them; `show` prints only whether a key is set.
* `idea-flash.sh --image <release image> --device /dev/sdX --identity <name> --yes` writes the image and then the identity
  (`--boot DIR` writes the identity only). A **new** identity = new device; a **saved** one = exact twin / replacement.
  Boot-partition files: `idea-timezone.txt` (idea#208 pattern, every boot), `idea-home.txt` (idea#203),
  `idea-hostname.txt` (idea-firstboot sets the name, then deletes it), `idea-secrets/tailscale-authkey` (wiped by
  idea-secrets-apply on first boot), `idea-identity.txt` (non-secret record incl. image sha256).
* Routers: identity format shared; flashing stays `tools/router-image/idea-router-flash` (network chain, key via `IDEA_FLEET_KEY`).
* Tests: `tools/identity/tests/identity-flash.test.sh` (no root, no card, fake key).
