#!/usr/bin/env python3
"""Switch off the engine's armour for players (O464, server/README.md "Player defence (O464)").

usage: python3 -I patch_base_armor_percent.py SERVER_DIR [--dry-run]

SERVER_DIR is the folder with config.lua. Engine patch 0016 gives a player's armour A a share A / (A + armorPercentConstant)
of every physical hit that checks armour, at most armorPercentMax percent (default 80 when the key is missing). Since O464 the
player defence layer (data/scripts/chaos/player_defence.lua) works the armour out by hit size, so the engine must not take
it as well. This sets `armorPercentMax = 0` (the cap of the engine's share becomes 0, so it takes nothing), keeping a
trailing comment, and appends the line when the key is missing (the engine default is 80, not off). `armorPercent` stays
`true`: false would bring the stock flat armour back. A monster as a defender keeps the stock formula, untouched.
Idempotent: a second run changes nothing. install_all.py step `armourlayer`.
"""
import os
import re
import sys

KEY = 'armorPercentMax'
LINE = re.compile(r'^(?P<lead>[ \t]*%s[ \t]*=[ \t]*)(?P<value>[^\r\n]*?)(?P<tail>[ \t]*--[^\r\n]*)?(?P<eol>\r?)$' % KEY, re.M)
ADDED = '%s = 0 -- Chaos O464: armour is the player defence layer\'s (tools/patch_base_armor_percent.py)' % KEY


def patch(text):
    """(new text, old value, or None when the key was missing)"""
    m = LINE.search(text)
    if not m:
        eol = '\r\n' if '\r\n' in text else '\n'
        sep = '' if text.endswith('\n') or not text else eol
        return text + sep + ADDED + eol, None
    old = m.group('value').strip()
    if old == '0':
        return text, old
    new = m.group('lead') + '0' + (m.group('tail') or '') + m.group('eol')
    return text[:m.start()] + new + text[m.end():], old


def main(argv):
    args = list(argv)
    dry = '--dry-run' in args
    args = [a for a in args if a != '--dry-run']
    if len(args) != 1:
        print(__doc__)
        return 1
    path = os.path.join(args[0], 'config.lua')
    if not os.path.isfile(path):
        print('%s: no config.lua' % args[0])
        return 1
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        text = f.read()
    new, old = patch(text)
    if new == text:
        print('config.lua: %s = 0 already' % KEY)
        return 0
    if not dry:
        with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
            f.write(new)
    print('config.lua: %s %s -> 0%s' % (KEY, 'missing (engine default 80)' if old is None else old, ' (dry run)' if dry else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
