#!/usr/bin/env python3
"""Find runs of commented-out code longer than 5 lines.

Skips JSDoc (/** … */), a file's leading header comment (the first comment
block before any code, including after a shebang), and mid-file prose
comments. Line comments (// in JS/TS, # in shell) and non-JSDoc /* … */
blocks are inspected by stripping the comment marker and asking whether
the remainder looks like code.

A stripped line looks like code when:
  - it ends with ';', '{', or '}' (or ')' if the line also contains '('), or
  - it starts with a JS/TS statement keyword (const, let, var, import, export,
    return, function, class, type, interface, enum, await, async, if, for,
    while, switch, case, try, catch, finally, throw, new, typeof, yield, …), or
  - it is an assignment at the start of the line (foo = …) unless a lowercase
    English word follows the value (so “connected=true fires only when…” is
    prose), or
  - it is a call at the start of the line (foo(, foo.bar(), new Foo(), …), or
  - in shell (#), it starts with a common command or flow word, is an
    ENV=value assignment, or contains &&, ||, |, >>, <<, $(, or backticks.

Blank comment lines neither count nor break a run. A prose comment line
breaks a run. A finding is emitted when a run has more than 5 code-like
lines.

CLI: python3 lib-commented-block.py <abs_path> <rel_path>
Prints: FIND\\t<rel>:<line>\\t<message>
Exit 0 always (no findings is empty stdout).
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

JS_EXTS = {".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs"}
SHELL_EXTS = {".sh", ".bash"}

JS_STMT = re.compile(
    r"^(?:const|let|var|import|export|return|function|class|type|interface|enum|"
    r"await|async|if|for|while|switch|case|try|catch|finally|throw|new|typeof|"
    r"yield|default|break|continue|do|else|with|debugger|delete|void|extends|"
    r"implements|package|private|protected|public|static|super|this)\b"
)
# Assignment at the start: foo = … / this.foo = … / exports.foo = …
ASSIGN = re.compile(
    r"^(?:(?:this|exports|module|globalThis|self|window)\.)?"
    r"[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*\s*=(?!=)\s*\S"
)
# “connected=true fires only when…” — English after the value, not code.
ASSIGN_THEN_PROSE = re.compile(
    r"^(?:(?:this|exports|module|globalThis|self|window)\.)?"
    r"[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*\s*=(?!=)\s*\S+\s+[A-Za-z][a-z]+\b"
)
CALL = re.compile(
    r"^(?:await\s+)?(?:new\s+)?(?:[A-Za-z_$][\w$]*\.)*[A-Za-z_$][\w$]*\s*\("
)

SHELL_CMD = re.compile(
    r"^(?:export|set|unset|umask|alias|source|\.|cd|mkdir|rmdir|rm|cp|mv|ln|"
    r"chmod|chown|echo|printf|cat|sed|awk|grep|egrep|fgrep|find|xargs|curl|"
    r"wget|ssh|scp|rsync|git|gh|pnpm|npm|npx|yarn|node|python3?|pip3?|docker|"
    r"podman|systemctl|pm2|jq|make|cmake|tar|unzip|zip|install|test|trap|"
    r"wait|exit|return|read|local|declare|typeset|readonly|shift|eval|exec|"
    r"command|builtin|hash|type|which|true|false|nohup|env|bash|sh|kill|"
    r"sleep|tee|head|tail|cut|tr|sort|uniq|wc|date|hostname|uname|sysctl|"
    r"mount|umount|ls|pwd|pushd|popd|dirs)\b"
)
SHELL_FLOW = re.compile(
    r"^(?:if|then|else|elif|fi|for|do|done|while|until|case|esac|function|select)\b"
)
SHELL_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*\+?=")
SHELL_META = re.compile(r"(&&|\|\||>>|<<|\$\(|`|\|\s*\S)")

LIST_PREFIX = re.compile(r"^(?:[-*•]\s+|\d+\.\s+)")


def _ext_style(path: str) -> str:
    ext = Path(path).suffix.lower()
    if ext in SHELL_EXTS:
        return "shell"
    return "js"


def _strip_list_prefix(s: str) -> str:
    return LIST_PREFIX.sub("", s.lstrip())


def looks_like_js_code(raw: str) -> bool:
    s = _strip_list_prefix(raw.strip())
    if not s:
        return False
    if s.endswith((";", "{", "}")):
        return True
    if s.endswith(")") and "(" in s:
        return True
    if JS_STMT.match(s):
        return True
    if ASSIGN.match(s) and not ASSIGN_THEN_PROSE.match(s):
        return True
    if CALL.match(s):
        return True
    return False


def looks_like_shell_code(raw: str) -> bool:
    s = _strip_list_prefix(raw.strip())
    if not s:
        return False
    if s.endswith(("\\", "{", "}", ";")):
        return True
    if s.endswith(")") and "(" in s:
        return True
    if SHELL_FLOW.match(s) or SHELL_CMD.match(s) or SHELL_ASSIGN.match(s):
        return True
    if SHELL_META.search(s):
        return True
    return False


def looks_like_code(raw: str, style: str) -> bool:
    if style == "shell":
        return looks_like_shell_code(raw)
    return looks_like_js_code(raw)


def _is_shebang(line: str) -> bool:
    return line.startswith("#!")


def _line_comment_body(line: str, style: str) -> str | None:
    """Return the text after // or #, or None if this is not a line comment."""
    stripped = line.lstrip()
    if style == "shell":
        if stripped.startswith("#") and not stripped.startswith("#!"):
            return stripped[1:]
        return None
    if stripped.startswith("//"):
        return stripped[2:]
    return None


def _block_start(line: str, style: str) -> str | None:
    """'jsdoc', 'block', or None. JS/TS only."""
    if style == "shell":
        return None
    stripped = line.lstrip()
    if stripped.startswith("/**"):
        return "jsdoc"
    if stripped.startswith("/*"):
        return "block"
    return None


def find_commented_blocks(text: str, rel: str) -> list[tuple[int, int]]:
    """Return (start_lineno, code_line_count) for each flagged run."""
    style = _ext_style(rel)
    lines = text.splitlines()
    findings: list[tuple[int, int]] = []

    def emit(start: int, count: int) -> None:
        if count > 5:
            findings.append((start, count))

    return _scan_body(lines, style, _header_end_index(lines, style), emit, findings)


def _header_end_index(lines: list[str], style: str) -> int:
    """First line index that is not shebang, leading blank, or the first header comment."""
    n = len(lines)
    i = 0
    if n and _is_shebang(lines[0]):
        i = 1
    while i < n and lines[i].strip() == "":
        i += 1
    if i >= n:
        return i
    kind = _block_start(lines[i], style)
    if kind is not None:
        # Walk until */ is seen
        for k in range(i, n):
            if "*/" in lines[k]:
                return k + 1
        return n
    if _line_comment_body(lines[i], style) is not None:
        i += 1
        while i < n:
            if lines[i].strip() == "":
                j = i + 1
                while j < n and lines[j].strip() == "":
                    j += 1
                if j < n and _line_comment_body(lines[j], style) is not None:
                    i = j
                    continue
                return i
            if _line_comment_body(lines[i], style) is not None:
                i += 1
                continue
            return i
        return i
    return i


def _scan_body(lines, style, start, emit, findings):
    n = len(lines)
    i = start
    run = 0
    run_start = 0

    def flush():
        nonlocal run, run_start
        emit(run_start, run)
        run = 0

    while i < n:
        line = lines[i]
        lineno = i + 1
        kind = _block_start(line, style)
        if kind == "jsdoc":
            flush()
            # skip until */
            while i < n and "*/" not in lines[i]:
                i += 1
            i += 1
            continue
        if kind == "block":
            flush()
            # Collect inner lines until */
            inner: list[tuple[int, str]] = []
            first = lineno
            while i < n:
                raw = lines[i]
                closed = "*/" in raw
                # Strip /* on first, */ on last, leading * on middle
                body = raw
                if i + 1 == first:  # first line of this block — wait lineno is first
                    pass
                # Use a cleaner strip:
                tmp = raw
                if tmp.lstrip().startswith("/*"):
                    tmp = tmp.lstrip()[2:]
                    if tmp.startswith("*") and not tmp.startswith("*/"):
                        # /* * foo  — unusual
                        pass
                    if tmp.startswith("*/"):
                        tmp = ""
                    elif "*/" in tmp:
                        tmp = tmp.split("*/", 1)[0]
                elif "*/" in tmp:
                    tmp = tmp.split("*/", 1)[0]
                    tmp = tmp.lstrip()
                    if tmp.startswith("*"):
                        tmp = tmp[1:]
                else:
                    tmp = tmp.lstrip()
                    if tmp.startswith("*"):
                        tmp = tmp[1:]
                inner.append((i + 1, tmp))
                i += 1
                if closed:
                    break
            # Count code-like inner lines (same run rules)
            b_run = 0
            b_start = first
            for ln, body in inner:
                if not body.strip():
                    continue
                if looks_like_code(body, style):
                    if b_run == 0:
                        b_start = ln
                    b_run += 1
                else:
                    emit(b_start, b_run)
                    b_run = 0
            emit(b_start, b_run)
            continue

        body = _line_comment_body(line, style)
        if body is not None:
            if not body.strip():
                i += 1
                continue
            if looks_like_code(body, style):
                if run == 0:
                    run_start = lineno
                run += 1
            else:
                flush()
            i += 1
            continue

        flush()
        i += 1

    flush()
    return findings


def format_findings(findings: list[tuple[int, int]], rel: str) -> list[str]:
    out = []
    for start, count in findings:
        msg = f"Commented-out block longer than 5 lines ({count} lines of commented-out code)"
        out.append(f"FIND\t{rel}:{start}\t{msg}")
    return out


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: lib-commented-block.py <abs_path> <rel_path>", file=sys.stderr)
        return 2
    abs_path, rel = argv[1], argv[2]
    text = Path(abs_path).read_text(encoding="utf-8", errors="replace")
    findings = find_commented_blocks(text, rel)
    for row in format_findings(findings, rel):
        print(row)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
