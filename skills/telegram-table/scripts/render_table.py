#!/usr/bin/env python3
"""
Render a data table as a PNG image using ImageMagick.
Requires: ImageMagick (convert) — available in the IDEA sandbox.

Usage:
    python3 render_table.py --out /tmp/table.png \
        --headers "Tool,Used for,How often" \
        --rows "Telegram,All agent interaction,Daily" \
               "GitHub,PR review and merge,Per task"

    # With explicit column widths:
    python3 render_table.py --out /tmp/table.png \
        --headers "Name,Value" \
        --rows "Key,Val" \
        --col-widths "200,300"
"""

import argparse
import subprocess
import sys
import os


def measure_text_width(text, font_size):
    """Rough character-based width estimate (DejaVu Sans, px per char at given pt)."""
    px_per_char = font_size * 0.6
    return int(len(text) * px_per_char)


def build_table_image(headers, rows, out_path, col_widths=None, font_size=16):
    pad = 16
    row_height = 36
    header_height = 42

    # Auto-size columns if not specified
    if col_widths is None:
        col_widths = []
        for col_i in range(len(headers)):
            max_text = headers[col_i]
            for row in rows:
                if col_i < len(row):
                    if len(row[col_i]) > len(max_text):
                        max_text = row[col_i]
            col_widths.append(max(80, measure_text_width(max_text, font_size) + pad * 2))

    total_w = sum(col_widths) + pad * 2
    total_h = header_height + row_height * len(rows) + pad

    cmds = []

    # White background
    cmds += ["-fill", "white", "-draw", f"rectangle 0,0 {total_w},{total_h}"]

    # Header background
    cmds += ["-fill", "#2d2d2d", "-draw", f"rectangle 0,0 {total_w},{header_height}"]

    # Header text
    x = pad
    cmds += [
        "-fill", "white",
        "-font", "DejaVu-Sans-Bold",
        "-pointsize", str(font_size),
    ]
    for i, h in enumerate(headers):
        safe = h.replace("'", "\\'")
        cmds += ["-draw", f"text {x},{header_height - 14} '{safe}'"]
        x += col_widths[i]

    # Rows
    for ri, row in enumerate(rows):
        y_top = header_height + ri * row_height
        y_bottom = y_top + row_height

        # Row background (alternating)
        bg = "#f0f0f0" if ri % 2 == 1 else "white"
        cmds += ["-fill", bg, "-draw", f"rectangle 0,{y_top} {total_w},{y_bottom}"]

        # Row separator
        cmds += ["-fill", "#dddddd", "-draw", f"line 0,{y_bottom} {total_w},{y_bottom}"]

        # Cell text
        x = pad
        cmds += [
            "-fill", "#222222",
            "-font", "DejaVu-Sans",
            "-pointsize", str(font_size),
        ]
        for i, cell in enumerate(row):
            if i < len(col_widths):
                safe = cell.replace("'", "\\'")
                cmds += ["-draw", f"text {x},{y_top + row_height - 11} '{safe}'"]
                x += col_widths[i]

    # Outer border
    cmds += [
        "-fill", "none",
        "-stroke", "#cccccc",
        "-strokewidth", "1",
        "-draw", f"rectangle 0,0 {total_w - 1},{total_h - 1}",
    ]

    full_cmd = (
        ["convert", "-size", f"{total_w}x{total_h}", "xc:white"]
        + cmds
        + [out_path]
    )
    result = subprocess.run(full_cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"ImageMagick error: {result.stderr}", file=sys.stderr)
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description="Render a table as a PNG using ImageMagick.")
    parser.add_argument("--out", required=True, help="Output PNG path (e.g. /tmp/table.png)")
    parser.add_argument("--headers", required=True, help="Comma-separated column headers")
    parser.add_argument("--rows", nargs="+", required=True,
                        help="One or more rows, each as a comma-separated string")
    parser.add_argument("--col-widths", help="Optional comma-separated column widths in px")
    parser.add_argument("--font-size", type=int, default=16, help="Font size in pt (default: 16)")
    args = parser.parse_args()

    headers = [h.strip() for h in args.headers.split(",")]
    rows = [[c.strip() for c in r.split(",")] for r in args.rows]
    col_widths = (
        [int(w.strip()) for w in args.col_widths.split(",")]
        if args.col_widths else None
    )

    build_table_image(headers, rows, args.out, col_widths, args.font_size)
    print(f"OK: {args.out} ({os.path.getsize(args.out)} bytes)")


if __name__ == "__main__":
    main()
