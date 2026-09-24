#!/usr/bin/env python3
"""Emit TSV findings for Console domain bake-ins. Args: abs_path rel_path"""
import re, sys

path, rel = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8", errors="replace").read()
seen = set()

def emit(rule, line, msg):
    key = (rule, line, msg)
    if key in seen:
        return
    seen.add(key)
    print(f"FIND\t{rule}\t{rel}:{line}\t{msg}")

def mask_js_comments(src):
    """Replace // and /* */ comments with spaces; keep newlines for line numbers.

    Skips string / template contents so comment markers inside them are left alone.
    JSX `{/* ... */}` is covered by the block-comment path.
    """
    out = list(src)
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            j = i
            while j < n and src[j] != "\n":
                out[j] = " "
                j += 1
            i = j
            continue
        if c == "/" and i + 1 < n and src[i + 1] == "*":
            j = i
            while j + 1 < n:
                if src[j] == "*" and src[j + 1] == "/":
                    out[j] = " "
                    out[j + 1] = " "
                    j += 2
                    break
                if src[j] != "\n":
                    out[j] = " "
                j += 1
            else:
                while j < n:
                    if src[j] != "\n":
                        out[j] = " "
                    j += 1
            i = j
            continue
        if c in ("'", '"', "`"):
            quote = c
            i += 1
            while i < n:
                if src[i] == "\\":
                    i += 2
                    continue
                if src[i] == quote:
                    i += 1
                    break
                i += 1
            continue
        i += 1
    return "".join(out)

# Mask comments so literal `<For>` inside //, /* */, or JSX {/* */} cannot open a match.
scan = mask_js_comments(text)

for m in re.finditer(r"<For\b([^>]*)>([\s\S]*?)</For>", scan):
    attrs, body = m.group(1), m.group(2)
    start = text[: m.start()].count("\n") + 1
    if re.search(r"key=\{(index|i)\}", body) or re.search(r"key=\{(index|i)\}", attrs):
        emit("console.for_index_key", start, "<For> uses index as key; use stable ID key")
    elif re.search(r"\(\s*\w+\s*,\s*(index|i)\s*\)", body):
        if not re.search(r"key=\{[^}\n]*\.(id|uuid|_id|key)\b", body):
            if not re.search(r"key=\{(?!\s*(index|i)\s*\})[^}]+\}", body):
                emit(
                    "console.for_not_id_keyed",
                    start,
                    "<For> callback uses index without stable ID key",
                )

for m in re.finditer(r"\buseStore\s*\(\s*([A-Za-z_][\w.]*)\s*\)", text):
    start = text[: m.start()].count("\n") + 1
    emit(
        "console.broad_store",
        start,
        "useStore() without selector — broad subscription",
    )

for m in re.finditer(
    r"(?:href|src)=['\"]https?://[^'\"]+['\"]|from\s+['\"]https?://[^'\"]+['\"]|"
    r"unpkg\.com|jsdelivr\.net|cdn\.jsdelivr|cdnjs\.cloudflare|fonts\.googleapis",
    text,
    re.I,
):
    start = text[: m.start()].count("\n") + 1
    emit(
        "console.cdn_external_css",
        start,
        "CDN / external CSS or remote asset reference",
    )
