# Telegram relay for IDEA field support

Option (e) of `proposals/2026-10-20-telegram-field-support.md`: field staff chat privately with the bot @IdeaSupportBot, and Koen follows every conversation in his "IDEA Support Monitor" Topics group, with one topic per person.

- `tg_relay.py` is the long-poll daemon (`getUpdates`, 50 s). It is stdlib only and uses no AI.
- `tg-send` is the CLI used by the support bot:
  - `tg-send --to <user_id> --text '...' [--as-koen]` sends to the field person and mirrors the message to their topic as "Bot: ...".
  - `tg-send --to <user_id> --escalate --text '<summary>' --draft '<answer>'` posts an escalation card in the topic (Approve draft / Reply myself). Nothing goes to the field person.
- `tg-relay.service` is a systemd **user** unit (pi has linger). It is skipped by `ExecCondition` until the token is set.
- `install.sh` deploys to `~/tg-relay` (mode 700) and creates `~/.config/tg-relay/env` (mode 600). The env file has an empty `TELEGRAM_BOT_TOKEN` and copies `KIT_WEBHOOK_URL` and `KIT_WEBHOOK_KEY` from kit-watch.

## Behaviour

- **Admin:** the first private `/start` registers the admin (Koen) and is logged.
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

    python3 -m unittest discover -s tests -v

The tests run against a local fake Telegram API and a fake webhook.
