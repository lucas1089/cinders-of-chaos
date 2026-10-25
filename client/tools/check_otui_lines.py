#!/usr/bin/env python3
"""Reject OTML lines that start at column 0 but are not a top-level style line.

A real line break inside a quoted value (for example a two-line tr('...') tooltip) puts the second line at
column 0. OTML then fails with "invalid indentation depth", the style is never defined and the module that
needs it fails to load: the client can stop at start (base patch 0139, fixed by 0145). Write a two-line text
with the escape \\n inside the string instead.

Checked: every .otui file under client/overlay, and every added line of an .otui file in client/base-patches.
A top-level line is a style name (`Name` or `Name < Base`), a variable (`&name: value`) or a comment.

  python3 -I client/tools/check_otui_lines.py
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CLIENT = os.path.dirname(HERE)

TOP = re.compile(r"^(?:[A-Za-z_][\w-]*(?:\s*<\s*[\w-]+)?\s*|&[\w-]+\s*:.*|//.*|#.*)$")
# lines a later base patch replaces: (patch file, line text start) -> the fixing patch
FIXED_LATER = {
    ("0139-death-fade.patch", "The corpse still appears at once"): "0145",
}


def bad_line(text):
    return bool(text) and not text[0].isspace() and not TOP.match(text)


def check_overlay():
    found = []
    root = os.path.join(CLIENT, "overlay")
    for d, _, files in os.walk(root):
        for f in sorted(files):
            if not f.endswith(".otui"):
                continue
            path = os.path.join(d, f)
            with open(path, encoding="utf-8", errors="replace") as fh:
                for n, line in enumerate(fh, 1):
                    if bad_line(line.rstrip("\r\n")):
                        found.append("%s:%d: %s" % (os.path.relpath(path, CLIENT), n, line.strip()[:80]))
    return found


def check_patches():
    found = []
    root = os.path.join(CLIENT, "base-patches")
    for name in sorted(os.listdir(root)):
        if not name.endswith(".patch"):
            continue
        current = None
        with open(os.path.join(root, name), encoding="utf-8", errors="replace") as fh:
            for n, line in enumerate(fh, 1):
                line = line.rstrip("\r\n")
                if line.startswith("+++ "):
                    current = line[4:].split("\t")[0]
                    continue
                if current is None or not current.endswith(".otui"):
                    continue
                if line.startswith("+") and not line.startswith("+++"):
                    text = line[1:]
                    if bad_line(text):
                        if any(name == p and text.startswith(t) for p, t in FIXED_LATER):
                            continue
                        found.append("base-patches/%s:%d (%s): %s" % (name, n, current, text.strip()[:80]))
    return found


def main():
    found = check_overlay() + check_patches()
    for f in found:
        print("OTML line at column 0 that is not a style:", f)
    if found:
        print("otui lines: %d bad (a line break inside a quoted value? write \\n inside the string)" % len(found))
        return 1
    print("otui lines: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
