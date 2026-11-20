#!/usr/bin/env python3
"""No one-argument addHealth in the server Lua (O682).

This engine's Creature:addHealth takes (damage type, amount). A call with one number (`creature:addHealth(100)`,
`creature:addHealth(-100)`) reads the number as the damage type, the amount as 0 and does nothing: a heal that heals
nothing, a hit that hits nothing. Heal with Chaos.heal (chaos_constants.lua; the spells state: ChaosSnares-style local
helper) or `creature:addHealth("healing", n)`, hit with `creature:addHealth("physical", -n)`.

A one-argument call is allowed only as the stock signature fallback right after a two-argument call, in the same
few lines (`addHealth("physical", -n)`, then `if health did not move then addHealth(-n)`): Chaos.heal, raid.lua,
descent.lua, necro_lib.lua, item_mods.lua, unique_passives.lua.
A two-argument call whose first argument is a number is refused too (the arguments the wrong way round).

Scans server/data and server/tools (*.lua; not tests: their mocks follow the engine, tests/*_test.lua).

python3 -I tools/ci/check_addhealth.py   (exit 1 and the lines when one breaks the rule)
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DIRS = ("server/data", "server/tools")
FALLBACK_LINES = 4  # a stock fallback sits at most this many lines below its two-argument call
CALL_RE = re.compile(r"addHealth\b")
NUMBER_RE = re.compile(r"^-?\s*(?:\d|math\.|#)")


def strip_comments(text):
    """The text with Lua comments blanked and string contents masked (same length, same line breaks)."""
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c in "\"'":
            j = i + 1
            while j < n and text[j] != c and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            out.append(c + "_" * (j - i - 1) + text[j:j + 1])  # the string's text is not code
            i = j + 1
        elif text.startswith("--", i):
            m = re.match(r"--\[(=*)\[", text[i:])
            if m:
                end = text.find("]" + m.group(1) + "]", i)
                end = n if end < 0 else end + len(m.group(1)) + 2
            else:
                end = text.find("\n", i)
                end = n if end < 0 else end
            out.append(re.sub(r"[^\n]", " ", text[i:end]))
            i = end
        else:
            out.append(c)
            i += 1
    return "".join(out)


def split_args(text, start):
    """The top-level arguments of the call whose `(` is at text[start]; None when it does not close."""
    depth, args, cur = 0, [], []
    i, n = start, len(text)
    while i < n:
        c = text[i]
        if c in "\"'":
            j = i + 1
            while j < n and text[j] != c and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            cur.append(text[i:j + 1])
            i = j + 1
            continue
        if c in "([{":
            depth += 1
            if depth > 1:
                cur.append(c)
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                tail = "".join(cur).strip()
                if tail or args:
                    args.append(tail)
                return args
            cur.append(c)
        elif c == "," and depth == 1:
            args.append("".join(cur).strip())
            cur = []
        else:
            cur.append(c)
        i += 1
    return None


def calls(text):
    """[(line number, kind, number of amount arguments, first amount argument)] of every addHealth use in comment-free text.

    kind "call": `x:addHealth(a, b)` or `x.addHealth(x, a, b)`; "pcall": `pcall(x.addHealth, x, a, b)`."""
    found = []
    for m in CALL_RE.finditer(text):
        line = text.count("\n", 0, m.start()) + 1
        before = text[max(0, m.start() - 1):m.start()]
        after = text[m.end():]
        if re.match(r"\s*\(", after) and before in (":", "."):
            args = split_args(text, m.end() + after.index("("))
            if args is None:
                continue
            if before == ".":
                args = args[1:]  # x.addHealth(x, ...): the receiver comes first
            found.append((line, "call", len(args), args[0] if args else ""))
        elif before == "." and re.match(r"\s*,", after):
            # pcall(x.addHealth, x, a, b): the arguments after the receiver
            open_at = text.rfind("(", 0, m.start())
            args = split_args(text, open_at) if open_at >= 0 else None
            if args is None or len(args) < 2:
                continue
            rest = args[2:]
            found.append((line, "pcall", len(rest), rest[0] if rest else ""))
    return found


def check_text(text, name="<text>"):
    """The problems of one file's text, [(line, message)]."""
    code = strip_comments(text)
    use = calls(code)
    problems = []
    for idx, (line, kind, amount_args, first) in enumerate(use):
        if amount_args == 2 and NUMBER_RE.match(first):
            problems.append((line, "addHealth(%s, ...): the damage type comes first, then the amount" % first))
        if amount_args != 1:
            continue
        # one argument: the stock signature, allowed only right after a two-argument call
        stock = any(
            other[2] == 2 and 0 < line - other[0] <= FALLBACK_LINES
            for other in use[:idx]
        )
        if not stock:
            problems.append((line, "one-argument addHealth heals or hurts nothing on this engine: Chaos.heal(creature, n), "
                                   "addHealth(\"healing\", n) or addHealth(\"physical\", -n)"))
    return problems


def lua_files():
    for d in DIRS:
        for base, _, names in os.walk(os.path.join(ROOT, d)):
            for name in sorted(names):
                if name.endswith(".lua"):
                    yield os.path.join(base, name)


def main():
    bad = 0
    count = 0
    for path in lua_files():
        with open(path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        if "addHealth" not in text:
            continue
        count += 1
        for line, msg in check_text(text, path):
            print("%s:%d: %s" % (os.path.relpath(path, ROOT), line, msg))
            bad += 1
    if bad:
        print("check_addhealth: %d one-argument addHealth call(s) (O682)" % bad)
        return 1
    print("check_addhealth: ok (%d Lua files use addHealth, none with one argument and no stock-signature pair)" % count)
    return 0


if __name__ == "__main__":
    sys.exit(main())
