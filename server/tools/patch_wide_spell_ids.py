#!/usr/bin/env python3
"""config.lua key chaosWideSpellIds: 16-bit spell ids on the wire (engine src-patch 0079, server/README.md "Wide spell ids").

usage: python3 -I patch_wide_spell_ids.py SERVER_DIR [--on | --off] [--dry-run]

SERVER_DIR is the folder with config.lua. The engine reads `chaosWideSpellIds` (default false when the key is missing).
With true, a client that asks for it (login capability bit 6, set by every build of our client) is announced feature 152
and reads the spell id of the 0xA4 cooldown packet as 16 bits, so spell ids above 255 work. Without a flag this only
makes the key visible: a config without it gets `chaosWideSpellIds = false` appended with a comment; a key that is there
keeps its value (the owner's choice is never overwritten by an install). --on / --off set it. Turn it on only with an
engine that has 0079 and a client build that is shipped (client/BASE.md "Wide spell ids"); an older client keeps working
either way, it simply never asks. Idempotent: a second run changes nothing. install_all.py step `widespellids`.
"""
import os
import re
import sys

KEY = 'chaosWideSpellIds'
LINE = re.compile(r'^(?P<lead>[ \t]*%s[ \t]*=[ \t]*)(?P<value>[^\r\n]*?)(?P<tail>[ \t]*--[^\r\n]*)?(?P<eol>\r?)$' % KEY, re.M)
COMMENT = ' -- Cinders of Chaos: 16-bit spell ids for clients that ask (server/README.md "Wide spell ids"); false until the client ships'


def parse(text):
    """True / False as written, or None when the key is missing or is not a boolean"""
    m = LINE.search(text)
    if not m:
        return None
    v = m.group('value').strip()
    return {'true': True, 'false': False}.get(v)


def patch(text, want=None):
    """(new text, old value as written or None when the key was missing). want: None keeps a key that is there,
    True / False sets it; a missing key is added as false (or want)"""
    m = LINE.search(text)
    value = 'true' if want else 'false'
    if not m:
        eol = '\r\n' if '\r\n' in text else '\n'
        sep = '' if text.endswith('\n') or not text else eol
        return text + sep + KEY + ' = ' + value + COMMENT + eol, None
    old = m.group('value').strip()
    if want is None or old == value:
        return text, old
    new = m.group('lead') + value + (m.group('tail') or '') + m.group('eol')
    return text[:m.start()] + new + text[m.end():], old


def main(argv):
    args = list(argv)
    dry = '--dry-run' in args
    on, off = '--on' in args, '--off' in args
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1 or (on and off):
        print(__doc__)
        return 1
    path = os.path.join(args[0], 'config.lua')
    if not os.path.isfile(path):
        print('%s: no config.lua' % args[0])
        return 1
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        text = f.read()
    new, old = patch(text, True if on else False if off else None)
    if new == text:
        print('config.lua: %s = %s already' % (KEY, old))
        return 0
    if not dry:
        with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
            f.write(new)
    print('config.lua: %s %s -> %s%s' % (KEY, old if old is not None else 'missing', parse(new), ' (dry run)' if dry else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
