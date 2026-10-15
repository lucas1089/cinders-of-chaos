#!/usr/bin/env python3
"""Raise the base server's idle kick so idle characters stay online (owner decision 2026-10-15: idle characters earn
Candlemarks; server/README.md "Candlemarks").

usage: python3 -I patch_base_idle_kick.py SERVER_DIR [--minutes N] [--dry-run]

SERVER_DIR is the folder with config.lua. The stock config has `kickIdlePlayerAfterMinutes = 15`: the engine warns a
character 15 minutes after its last action and kicks it a minute later (Player::onThink; only staff and no-logout
tiles are spared). 0 is no "off": the engine then kicks after one minute. This sets it to N minutes (default 1440, one
day; at most 100000), keeping a trailing comment; a config without the key gets it appended. Only that line changes.
Idempotent: a second run changes nothing. install_all.py step `idlekick`.
"""
import os
import re
import sys

DEFAULT_MINUTES = 1440
KEY = 'kickIdlePlayerAfterMinutes'
LINE = re.compile(r'^(?P<lead>[ \t]*%s[ \t]*=[ \t]*)(?P<value>[^\r\n]*?)(?P<tail>[ \t]*--[^\r\n]*)?(?P<eol>\r?)$' % KEY, re.M)


def patch(text, minutes):
    """(new text, old value or None when the key was missing)"""
    m = LINE.search(text)
    if not m:
        sep = '' if text.endswith('\n') or text == '' else '\n'
        return text + sep + '%s = %d -- Cinders of Chaos: idle characters stay online (Candlemarks)\n' % (KEY, minutes), None
    new = m.group('lead') + str(minutes) + (m.group('tail') or '') + m.group('eol')
    return text[:m.start()] + new + text[m.end():], m.group('value').strip()


def main(argv):
    args = list(argv)
    dry = '--dry-run' in args
    args = [a for a in args if a != '--dry-run']
    minutes = DEFAULT_MINUTES
    if '--minutes' in args:
        i = args.index('--minutes')
        try:
            minutes = int(args[i + 1])
        except (IndexError, ValueError):
            print(__doc__)
            return 1
        del args[i:i + 2]
    if len(args) != 1 or not 1 <= minutes <= 100000:
        print(__doc__)
        return 1
    path = os.path.join(args[0], 'config.lua')
    if not os.path.isfile(path):
        print('%s: no config.lua' % args[0])
        return 1
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        text = f.read()
    new, old = patch(text, minutes)
    if new == text:
        print('config.lua: %s = %d already' % (KEY, minutes))
        return 0
    if not dry:
        with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
            f.write(new)
    print('config.lua: %s %s -> %d%s' % (KEY, old if old is not None else '(missing)', minutes, ' (dry run)' if dry else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
