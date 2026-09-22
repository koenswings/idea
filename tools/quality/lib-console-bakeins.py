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

for m in re.finditer(r"<For\b([^>]*)>([\s\S]*?)</For>", text):
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
