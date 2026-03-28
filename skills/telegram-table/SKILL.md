---
name: telegram-table
description: Render a data table as a PNG image and send it via Telegram. Use whenever you need to display a table in a Telegram message — raw markdown tables and ASCII art tables both render poorly on Telegram (Mac desktop app and iPhone). Always use this skill instead of markdown or ASCII tables when sending to Telegram.
---

# telegram-table

Renders a table as a PNG using ImageMagick and sends it via the `message` tool.

## When to use image vs plain text

- **Image**: data has multiple columns where layout aids comprehension
- **Bullets/bold labels**: simple two-column lists (label + value) — no image needed

## Quick start

```python
# scripts/render_table.py — run with: python3 /path/to/render_table.py
python3 /home/node/workspace/skills/telegram-table/scripts/render_table.py \
    --out /tmp/my-table.png \
    --headers "Col A,Col B,Col C" \
    --rows "R1A,R1B,R1C" "R2A,R2B,R2C"
```

Then send with the `message` tool:
```
message(action=send, channel=telegram, target=<chat_id>, media=/tmp/my-table.png, message="Optional caption")
```

## Column widths

The script auto-sizes columns to fit content (min 80px). For wide tables, pass `--col-widths` to override:

```
--col-widths 200,300,120
```

## Styling

Defaults: dark header (#2d2d2d), alternating row shading, 16pt DejaVu Sans. Override with `--font-size` if needed. Do not change the font family — DejaVu Sans is the only font guaranteed available in the sandbox.
