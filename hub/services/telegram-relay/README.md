# Telegram relay for IDEA field support

Option (e) of `proposals/2026-10-20-telegram-field-support.md`: field staff chat privately with the bot [@IDEA_SupportBot](https://t.me/IDEA_SupportBot), and Koen follows every conversation in his "IDEA Support Monitor" Topics group, with one topic per person.

- `tg_relay.py` is the long-poll daemon (`getUpdates`, 50 s). It is stdlib only and uses no AI.
- `tg-send` is the CLI used by the support bot:
  - `tg-send --to <user_id> --text '...' [--as-koen]` sends to the field person and mirrors the message to their topic as "Bot: ...".
  - `tg-send --to <user_id> --escalate --text '<summary>' --draft '<answer>'` posts an escalation card in the topic (Approve draft / Reply myself). Nothing goes to the field person.
- `tg-relay.service` is a systemd **user** unit (pi has linger). It is skipped by `ExecCondition` until the token is set.
- The relay reads `TELEGRAM_BOT_TOKEN` (and the kit webhook keys) itself from `~/.config/tg-relay/env` via `load_env()` in `tg_relay.py` (override with `TG_RELAY_ENV`); the unit has no `EnvironmentFile=`, it only checks the same file in `ExecCondition`.
- `install.sh` deploys to `~/tg-relay` (mode 700) and creates `~/.config/tg-relay/env` (mode 600). The env file has an empty `TELEGRAM_BOT_TOKEN` and copies `KIT_WEBHOOK_URL` and `KIT_WEBHOOK_KEY` from kit-watch.
- `.env.example` lists the env key names only (no values).

This folder moved from `tools/telegram-relay/` to `hub/services/telegram-relay/` (idea#482, proposal #408). `tools/telegram-relay/README.md` is a pointer to here.

## Service checklist (proposal #408)

- **What it does:** relays field-support chats between [@IDEA_SupportBot](https://t.me/IDEA_SupportBot) and Koen's monitor group (see Behaviour below).
- **How it runs:** systemd **user** unit `tg-relay.service` as `pi` (linger on), `Restart=always`; installed to `~/.config/systemd/user/tg-relay.service`.
- **Code on the hub:** `~/tg-relay/tg_relay.py` and `~/tg-relay/tg-send`; `~/.local/bin/tg-send` is a symlink to the latter.
- **State:** `~/tg-relay/state.json` (mode 600; admin, monitor group, allowlist, offset, pending cards, drafts) and `~/tg-relay/files/` (saved photos and documents). Override the base with `TG_RELAY_HOME`.
- **Env keys:** `~/.config/tg-relay/env` (mode 600; override with `TG_RELAY_ENV`): `TELEGRAM_BOT_TOKEN`, `KIT_WEBHOOK_URL`, `KIT_WEBHOOK_KEY`, optional `TELEGRAM_API_BASE`. Key names only in `.env.example`.
- **Logs:** `~/tg-relay/relay.log` (+ `relay.log.1`), and `journalctl --user -u tg-relay.service`.
- **Install / update:** on the hub as `pi`, after a merged PR: `sh ~/idea/hub/services/telegram-relay/install.sh` (it `cd`s to its own folder, so any cwd works). Safe to re-run: it refreshes code and unit and restarts the service, and it never rewrites an existing `~/.config/tg-relay/env`, so the real token is never replaced by empty or example values.
- **Roll back:** check out the previous commit of this folder and re-run `install.sh`.

## Behaviour

- **Admin:** the first private `/start` registers the admin (Koen) and is logged.
- **Admin as field person:** Koen's private (non-command) messages to the bot are treated like a field person's. The first one auto-enrols him (no approval card) and creates a topic under his name; after that they are mirrored, POSTed to the webhook and answered like anyone else's. His admin powers in the monitor group are unchanged, so he can relay field messages from his own account.
- **Monitor group:** Koen sends `/setup` in the group to make it the monitor group. Only the admin can do this.
- **New field person:** an unknown `/start` gets a "wait for approval" reply, and Koen gets a card with Approve / Reject. Approve adds the person to the allowlist and runs `createForumTopic` with their name.
- **Messages from approved people:** each one is mirrored as "Name: ..." into their topic. Photos and documents are saved to `~/tg-relay/files/`. Each message is also POSTed to the webhook as:
  `{type:"telegram_message", from_id, from_name, chat_id, text, message_id, topic_id, ts, paused, files}`
- **In a topic, Koen can:**
  - type plain text: the person receives "Koen: ...", and the topic shows "✓ sent to Name";
  - send `/pause` or `/resume`: this sets `paused` in the payload, so the routine only mirrors and does not answer;
  - tap **Reply myself** on an escalation card: this pauses the person;
  - tap **Approve draft**: this sends the draft once.
- **Ignored:** messages from people who are not on the allowlist, and callbacks or group messages from anyone but the admin.
- **Rate limits:** `retry_after` from Telegram is respected.
- **Logs:** `~/tg-relay/relay.log`, capped at about 1 MB (2 × 500 KB). Message texts and secrets are never logged.

## Tests

    cd hub/services/telegram-relay && python3 -m unittest discover -s tests -v

`test_relay.py` runs against a local fake Telegram API and a fake webhook. `test_install.py` runs `install.sh` against a fake `$HOME` with a stub `systemctl`, and checks that a re-run keeps an existing env file byte for byte. Neither touches a Pi or a real env file.
