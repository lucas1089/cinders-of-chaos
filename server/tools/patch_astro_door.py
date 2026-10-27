#!/usr/bin/env python3
"""Opens the Astro quest door of the base server to everyone (idempotent). install_all.py step `astrodoor`.

usage: python3 -I patch_astro_door.py DATA_DIR [--dry-run]

Owner 2026-10-27: "não dá pra entrar na porta" (a hunt of Bone Warrior, Bone Slicer and Grimbone; the door answers
"You need find the Astro Clock."). DATA_DIR is the base server's data folder. The base map has a closed door (item 1223,
action id 13690) at 31567,33003,7 in the Astro tower. The action script scripts/customs/quests/astro_quest/astro_door.lua
lets a player through only once the quest storage `Quests.astroClock` is 1 (set by clicking the clock, action id 13689, a
clock on 31543,33003,8 and one on 31568,33005,6); it then teleports to 31568,33003,7. The room behind the door is a
15 tile hall (stone floor, tables, a carpet, the blue "Go Back" teleport) that holds the spawns of a Bone Slicer, a Bone
Warrior and a Grimbone: part of the hunt the Chaos server uses for levelling, and the quest it belongs to is not run here.
The patch puts one block at the top of onUse: the door now passes every character, in both directions (from the east of
the door to the tile west of it, else to the tile east of it), and the old body stays below it, unreachable. The
scripts are recognised by the message and by `aid(13690)`. A second run changes nothing. Line endings are kept.
"""
import os
import re
import sys

MARK = 'Chaos (patch_astro_door.py)'
REL = os.path.join('scripts', 'customs', 'quests', 'astro_quest', 'astro_door.lua')
MESSAGE = 'You need find the Astro Clock'
AID = re.compile(r':aid\(\s*13690\s*\)')
ONUSE = re.compile(r'^function ([A-Za-z_]\w*)\.onUse\(([^)\n]*)\)[ \t]*\r?$', re.M)


def patch(text):
    """-> (new text, status): 'patched', 'already patched', 'none' (not the door), 'unrecognised <why>'"""
    if MESSAGE not in text or not AID.search(text):
        return text, 'none'
    if MARK in text:
        return text, 'already patched'
    found = ONUSE.findall(text)
    if len(found) != 1:
        return text, 'unrecognised (onUse x%d)' % len(found)
    m = ONUSE.search(text)
    args = [a.strip() for a in m.group(2).split(',')]
    if len(args) < 2 or not all(args[:2]):
        return text, 'unrecognised (onUse arguments)'
    player, item = args[0], args[1]
    nl = '\r\n' if '\r\n' in text else '\n'
    eol = text.find('\n', m.end())
    eol = len(text) if eol < 0 else eol + 1
    block = nl.join([
        '\tif true then -- %s: the door passes everybody, both ways (the hall behind it is a hunt spawn)' % MARK,
        '\t\tlocal door = %s:getPosition()' % item,
        '\t\tlocal dest = Position(door.x + (%s:getPosition().x > door.x and -1 or 1), door.y, door.z)' % player,
        '\t\t%s:teleportTo(dest, true)' % player,
        '\t\tdest:sendMagicEffect(CONST_ME_TELEPORT)',
        '\t\treturn true',
        '\tend',
        ''])
    return text[:eol] + block + text[eol:], 'patched'


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


def files(data):
    """the door script: its usual place, else any lua under scripts/ that carries the message"""
    fixed = os.path.join(data, REL)
    if os.path.isfile(fixed):
        yield fixed
        return
    for root, _dirs, names in os.walk(os.path.join(data, 'scripts')):
        for name in sorted(names):
            if name.endswith('.lua'):
                path = os.path.join(root, name)
                if MESSAGE in read(path):
                    yield path


def main(argv):
    args = [a for a in argv if a != '--dry-run']
    dry = '--dry-run' in argv
    if len(args) != 1 or args[0].startswith('-'):
        print(__doc__)
        return 1
    data = args[0]
    done = 0
    bad = 0
    for path in files(data):
        rel = os.path.relpath(path, data).replace(os.sep, '/')
        new, status = patch(read(path))
        if status == 'patched':
            done += 1
            if not dry:
                write(path, new)
            print('%s: patched' % rel)
        elif status.startswith('unrecognised'):
            bad += 1
            print('%s: %s (left alone)' % (rel, status))
    if not done and not bad:
        print('astro door: nothing to change')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
