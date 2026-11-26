#!/usr/bin/env python3
"""The base boss step tile of the Master of the Elements dungeon asks the queue run first (idempotent; O183).
install_all.py step `dungeonbossgate`; server/README.md "dungeons".

usage: python3 -I patch_dungeon_boss_gate.py DATA_DIR [--dry-run] [--check]

DATA_DIR is the base server's data folder. The stock script data/scripts/customs/dungeon/master_of_the_elements/
master_of_the_elements.lua (a MoveEvent on action id 63457) makes the boss 3 s after a player steps on the tile of the
boss room, without a level, and writes storage 248500 = a time (it checks "< 0", so the boss never comes again for that
character). Seen in a client (2026-11-26, V22): inside a queue run the boss stood there at 0% of the monsters.

One line goes first in onStepIn: ChaosDungeons.bossStep(creature, position) answers for a tile inside a running queue
dungeon (before the unlock a refusal with the percent needed; after it the run makes its boss once, at the dungeon's
level: dungeons.lua). Outside a run (nil) and without the Chaos scripts the stock body runs as before. The levers of
dungeons 1, 3 and 4 ask dungeons.lua through instance_limits.lua BR.leverUse (step bossrooms), not here.

A second run changes nothing. --check changes nothing and exits 1 while the file is left to patch. Line endings kept.
"""
import os
import re
import sys

sys.dont_write_bytecode = True

SCRIPT = os.path.join('scripts', 'customs', 'dungeon', 'master_of_the_elements', 'master_of_the_elements.lua')
MARK = '-- Chaos (patch_dungeon_boss_gate.py)'
STEP_RE = re.compile(r'^function ([A-Za-z_]\w*)\.onStepIn\(([A-Za-z_]\w*), [A-Za-z_]\w*, ([A-Za-z_]\w*)'
                     r'(?:, [A-Za-z_]\w*)*\)[ \t]*(\r?)$', re.M)


def read(path):
    with open(path, 'r', encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


def patch(text):
    """-> (new text, note)"""
    if MARK in text:
        return text, 'already patched'
    found = STEP_RE.findall(text)
    if len(found) != 1:
        return text, 'unrecognised: %d onStepIn handlers (a changed base script?)' % len(found)
    m = STEP_RE.search(text)
    creature, position, cr = m.group(2), m.group(3), m.group(4)
    line = ('    if ChaosDungeons and ChaosDungeons.bossStep and ChaosDungeons.bossStep(%s, %s) then return true end %s'
            % (creature, position, MARK))
    # the new line goes after the handler's line break, with the file's own line ending
    return text[:m.end()] + '\n' + line + cr + text[m.end():], 'patched: the boss step asks the queue run first'


def run(data, dry=False):
    """-> (report lines, number of files that change)"""
    path = os.path.join(data, SCRIPT)
    name = SCRIPT.replace(os.sep, '/')
    if not os.path.isfile(path):
        return ['%s: not found, skipped' % name], 0
    text = read(path)
    new, note = patch(text)
    if new != text:
        if not dry:
            write(path, new)
        return ['%s: %s' % (name, note)], 1
    return ['%s: %s' % (name, note if note != 'already patched' else 'nothing to do')], 0


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__.strip().splitlines()[3])
        return 2
    check = '--check' in argv
    report, changed = run(args[0], dry=check or '--dry-run' in argv)
    for line in report:
        print(line)
    if any('unrecognised' in r for r in report):
        return 1
    if check and changed:
        print('%d file(s) still to patch' % changed)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
