#!/usr/bin/env python3
"""Reject Windows SDK macro names used as identifiers in the C++ code of the client base patches.

The Windows SDK defines some short lowercase words as macros (rpcndr.h: `#define small char`, `hyper`; minwindef.h:
`near`, `far`; combaseapi.h: `interface`). A local variable with such a name compiles on Linux and breaks only the
MSVC build of the Windows package, half an hour into the run (base patch 0132 named a Size `small`; fixed by 0150).

Checked: the added lines of every .cpp / .h file in client/base-patches, without comments and string literals (GLSL
shader text inside strings may use these words).

  python3 -I client/tools/check_win_macros.py
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(os.path.dirname(HERE), "base-patches")

WORDS = re.compile(r"\b(small|hyper|near|far|interface|pascal|cdecl)\b")
# lines a later base patch replaces: patch file -> the fixing patch
FIXED_LATER = {"0132-map-bloom.patch": "0150"}


def code_of(text):
    text = re.sub(r'"(?:[^"\\]|\\.)*"', '""', text)
    text = re.sub(r"'(?:[^'\\]|\\.)*'", "''", text)
    text = re.sub(r"/\*.*?\*/", "", text)
    text = re.sub(r"//.*", "", text)
    stripped = text.strip()
    if stripped.startswith("*") or stripped.startswith("/*"):
        return ""
    return text


def check():
    found = []
    for name in sorted(os.listdir(PATCHES)):
        if not name.endswith(".patch") or name in FIXED_LATER:
            continue
        current = None
        with open(os.path.join(PATCHES, name), encoding="utf-8", errors="replace") as fh:
            for n, line in enumerate(fh, 1):
                line = line.rstrip("\r\n")
                if line.startswith("+++ "):
                    current = line[4:].split("\t")[0]
                    continue
                if not current or not re.search(r"\.(cpp|h|hpp)$", current):
                    continue
                if line.startswith("+") and not line.startswith("+++"):
                    if line.rstrip().endswith("\\"):
                        continue  # inside a string continued over lines (shader text)
                    m = WORDS.search(code_of(line[1:]))
                    if m:
                        found.append("%s:%d (%s): '%s' in %s" % (name, n, current, m.group(1), line[1:].strip()[:80]))
    return found


def main():
    found = check()
    for f in found:
        print("Windows SDK macro name used in code:", f)
    if found:
        print("win macros: %d bad (MSVC sees these words as macros; rename the identifier)" % len(found))
        return 1
    print("win macros: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
