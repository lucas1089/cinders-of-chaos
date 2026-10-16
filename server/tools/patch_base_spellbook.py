#!/usr/bin/env python3
"""Using a stock spellbook item opens the client's Spellbook window instead of the stock text window.

usage: python3 -I patch_base_spellbook.py DATA_DIR [--dry-run]

The base server's spellbook action (data/scripts/actions/others/spellbook.lua, a revscript on the stock spellbook ids
2175, 6120, 8900-8904, ...) shows "Spells for Level n / words - name : mana" with showTextDialog. Every base action
script with that text (data/scripts/actions/**.lua and data/actions/scripts/**.lua) gets a first statement in its onUse:
ChaosSpellbook.openWindow(player) (data/scripts/chaos/spellbook.lua) sends `show` on extended opcode 219 to a client
that has the Spellbook window and the use ends there; a client without it (it never spoke opcode 219) still gets the
text. The engine refuses a second registration of an item id, so a Chaos revscript on the same ids could not take over.
The Chaos set spellbooks are registered by spellbook.lua itself.

Idempotent: a patched script carries a marker and is not changed again. Run it again after replacing the base files.
install_all.py step `events`.
"""
import os
import re
import sys

MARKER = 'Chaos: the Spellbook window (patch_base_spellbook.py)'
TEXT = 'Spells for Level'
ONUSE = re.compile(r'^(?P<lead>[ \t]*)(?:local[ \t]+)?function[ \t]+(?:[\w.:]+[.:])?onUse[ \t]*\((?P<args>[^)]*)\)'
                   r'[^\r\n]*(?P<eol>\r?\n)', re.M)


def patch(text):
    """(new text, status): status 'patched', 'already', or a reason it was left alone"""
    if MARKER in text:
        return text, 'already'
    if TEXT not in text:
        return text, 'not a spellbook script'
    m = ONUSE.search(text)
    if not m:
        return text, 'no onUse function'
    args = [a.strip() for a in m.group('args').split(',') if a.strip()]
    if not args:
        return text, 'onUse without arguments'
    player = args[0]
    rest = text[m.end():]
    nxt = re.match(r'([ \t]*)\S', rest)
    indent = nxt.group(1) if nxt and len(nxt.group(1)) > len(m.group('lead')) else m.group('lead') + '\t'
    eol = m.group('eol')
    block = (
        '{i}-- {mark}: a client with the window opens it (opcode 219);{e}'
        '{i}-- the text below stays for a client without it (data/scripts/chaos/spellbook.lua){e}'
        '{i}if ChaosSpellbook and ChaosSpellbook.openWindow and ChaosSpellbook.openWindow({p}) then{e}'
        '{i}\treturn true{e}'
        '{i}end{e}'
    ).format(i=indent, mark=MARKER, e=eol, p=player)
    return text[:m.end()] + block + rest, 'patched'


def scripts(data):
    for sub in (('scripts', 'actions'), ('actions', 'scripts')):
        root = os.path.join(data, *sub)
        for dirpath, dirnames, files in os.walk(root):
            dirnames.sort()
            for name in sorted(files):
                if name.endswith('.lua'):
                    yield os.path.join(dirpath, name)


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    dry = '--dry-run' in argv
    if len(args) != 1:
        print(__doc__.strip().splitlines()[2])
        return 2
    data = args[0]
    if not os.path.isdir(data):
        print('%s: not a folder' % data)
        return 1
    found = 0
    for path in scripts(data):
        with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
            text = f.read()
        if TEXT not in text and MARKER not in text:
            continue
        new, st = patch(text)
        rel = os.path.relpath(path, data)
        if st not in ('patched', 'already'):
            print('%s: %s, left alone' % (rel, st))
            continue
        found += 1
        if st == 'patched' and not dry:
            with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
                f.write(new)
        print('%s: %s%s' % (rel, st, ' (dry run, not written)' if dry and st == 'patched' else ''))
    if not found:
        print('no stock spellbook action script found: nothing to do')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
