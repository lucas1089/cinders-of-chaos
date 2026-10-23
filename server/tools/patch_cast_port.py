#!/usr/bin/env python3
"""Open the live cast port in config.lua (server/README.md "Live spectator", phase 2; engine src-patch 0064).

usage: python3 -I patch_cast_port.py SERVER_DIR [--port N] [--dry-run]

SERVER_DIR is the folder with config.lua. The engine reads `castPort` at startup (default 0: off) and listens on
127.0.0.1:castPort only, never on the network; chaos-ctl.sh cast NAME reads the same line. This sets it to N (default
7179; 1 to 65535), keeping a trailing comment; a config without the key gets it appended. Only that line changes. An
engine without patch 0064 ignores the key. Idempotent: a second run changes nothing. install_all.py step `castport`.
"""
import os
import re
import sys

DEFAULT_PORT = 7179
KEY = 'castPort'
LINE = re.compile(r'^(?P<lead>[ \t]*%s[ \t]*=[ \t]*)(?P<value>[^\r\n]*?)(?P<tail>[ \t]*--[^\r\n]*)?(?P<eol>\r?)$' % KEY, re.M)


def patch(text, port):
    """(new text, old value or None when the key was missing)"""
    m = LINE.search(text)
    if not m:
        sep = '' if text.endswith('\n') or text == '' else '\n'
        return text + sep + '%s = %d -- Cinders of Chaos: the live cast for the admin app, 127.0.0.1 only\n' % (KEY, port), None
    new = m.group('lead') + str(port) + (m.group('tail') or '') + m.group('eol')
    return text[:m.start()] + new + text[m.end():], m.group('value').strip()


def main(argv):
    args = list(argv)
    dry = '--dry-run' in args
    args = [a for a in args if a != '--dry-run']
    port = DEFAULT_PORT
    if '--port' in args:
        i = args.index('--port')
        try:
            port = int(args[i + 1])
        except (IndexError, ValueError):
            print(__doc__)
            return 1
        del args[i:i + 2]
    if len(args) != 1 or not 1 <= port <= 65535:
        print(__doc__)
        return 1
    path = os.path.join(args[0], 'config.lua')
    if not os.path.isfile(path):
        print('%s: no config.lua' % args[0])
        return 1
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        text = f.read()
    new, old = patch(text, port)
    if new == text:
        print('config.lua: %s = %d already' % (KEY, port))
        return 0
    if not dry:
        with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
            f.write(new)
    print('config.lua: %s %s -> %d%s' % (KEY, old if old is not None else '(missing)', port, ' (dry run)' if dry else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
