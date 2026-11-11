#!/usr/bin/env python3
"""A failing command of a multi-line workflow `run: |` block must fail its step.

The runner starts a block with `bash -e`. bash -e does not stop on a command that fails on the left of `&&`:
`a --check && b --check` in the middle of a block goes on to the next line when `a` fails, and the step is green.
Only the last line of a block is safe, because the status of the list is then the status of the step.

Rule: no `&&` list on a line of a multi-line run block, but
  - on the last line of the block,
  - inside quotes, `$( )`, a `( )` group closed on the same line (the group fails as one command), `${{ }}`, a here-document,
  - in the condition of `if`, `elif`, `while`, `until`,
  - in a list that names its own failure branch: `a && b || c`.
Write one command per line. A guard and its action become `if guard; then action; fi`.

python3 -I tools/ci/check_workflow_steps.py   (exit 1 and the lines when one breaks the rule)
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RUN_RE = re.compile(r"^(\s*)(?:- )?run:\s*[|>][-+]?\s*$")
HEREDOC_RE = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
CONDITION_RE = re.compile(r"^(?:if|elif|while|until)\b")


def run_blocks(text):
    """[(line number of the first body line, [body lines])] of every multi-line run block of a workflow file."""
    lines = text.split("\n")
    blocks = []
    i = 0
    while i < len(lines):
        m = RUN_RE.match(lines[i])
        if not m:
            i += 1
            continue
        indent = len(m.group(1)) + (2 if lines[i].lstrip().startswith("- ") else 0)
        body = []
        j = i + 1
        while j < len(lines) and (not lines[j].strip() or len(lines[j]) - len(lines[j].lstrip()) > indent):
            body.append(lines[j])
            j += 1
        while body and not body[-1].strip():
            body.pop()
        if body:
            blocks.append((i + 2, body))
        i = j
    return blocks


def mask(body):
    """The block with everything that is not shell list syntax of the block itself turned into spaces.
    Line count and line lengths stay, so a position in the result is a position in the block."""
    out = []
    quote = None        # "'" or '"'
    depth = []          # open "(" of the current line: the positions in `out` where each one starts
    heredoc = None
    pending = None
    for line in body:
        if heredoc is not None:
            if line.strip() == heredoc:
                heredoc = None
            out.append(" " * len(line))
            continue
        chars = list(line)
        if quote is None:
            depth = []  # a group left open at the end of a line is not masked: its lines are judged like the block's
        k = 0
        n = len(chars)
        while k < n:
            c = chars[k]
            if quote == "'":
                if c == "'":
                    quote = None
                chars[k] = " "
            elif quote == '"':
                if c == "\\" and k + 1 < n:
                    chars[k] = chars[k + 1] = " "
                    k += 1
                else:
                    if c == '"':
                        quote = None
                    chars[k] = " "
            elif c == "\\" and k + 1 < n:
                chars[k] = chars[k + 1] = " "
                k += 1
            elif c in "'\"":
                quote = c
                chars[k] = " "
            elif c == "#" and (k == 0 or chars[k - 1] in " \t;(") and not (k > 0 and line[k - 1] == "$"):
                for q in range(k, n):
                    chars[q] = " "
                break
            elif line.startswith("${{", k):
                end = line.find("}}", k)
                end = n if end < 0 else end + 2
                for q in range(k, end):
                    chars[q] = " "
                k = end - 1
            elif c == "<" and line.startswith("<<", k) and not line.startswith("<<<", k):
                m = HEREDOC_RE.match(line, k)
                if m:
                    pending = m.group(2)
            elif c == "(":
                depth.append(k)
            elif c == ")" and depth:
                start = depth.pop()
                for q in range(start, k + 1):
                    chars[q] = " "
            k += 1
        out.append("".join(chars))
        if pending is not None and quote is None:
            heredoc, pending = pending, None
    return out


def statements(masked):
    """[(index of the first line, text)]: the masked lines, joined over a trailing `&&`, `||` or `|`."""
    result = []
    start, text = None, ""
    for idx, line in enumerate(masked):
        s = line.strip()
        if start is None:
            if not s:
                continue
            start, text = idx, s
        else:
            text += " " + s
        if not text.endswith(("&&", "||", "|")):
            result.append((start, text))
            start, text = None, ""
    if start is not None:
        result.append((start, text))
    return result


def join_backslash(body):
    """Body lines with a trailing backslash joined to the next line; the joined lines keep their place as empty lines."""
    out = list(body)
    i = 0
    while i < len(out):
        j = i
        while out[i].rstrip().endswith("\\") and j + 1 < len(out):
            j += 1
            out[i] = out[i].rstrip()[:-1] + " " + out[j].strip()
            out[j] = ""
        i = j + 1
    return out


def swallowed(body):
    """[(index of the line in the block, the statement)] of every `&&` list that can hide a failure."""
    stmts = statements(mask(join_backslash(body)))
    bad = []
    for n, (idx, text) in enumerate(stmts):
        if "&&" not in text:
            continue
        if n == len(stmts) - 1:
            continue
        if CONDITION_RE.match(text):
            continue
        if "||" in text[text.rfind("&&"):]:
            continue
        bad.append((idx, body[idx].strip()))
    return bad


def check_file(path):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    found = []
    for first, body in run_blocks(text):
        if len(body) < 2:
            continue
        for idx, line in swallowed(body):
            found.append((first + idx, line))
    return found


def main():
    paths = sorted(glob.glob(os.path.join(ROOT, ".github", "workflows", "*.yml")))
    total = 0
    for path in paths:
        for lineno, line in check_file(path):
            total += 1
            print("%s:%d: a failure left of && does not fail the step: %s" % (os.path.relpath(path, ROOT), lineno, line[:160]))
    if total:
        print("%d line(s). One command per line; a guard becomes `if guard; then action; fi`." % total)
        return 1
    print("workflow run blocks: ok (%d files)" % len(paths))
    return 0


if __name__ == "__main__":
    sys.exit(main())
