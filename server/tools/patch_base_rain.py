#!/usr/bin/env python3
"""Switch off the base server's rain, so the Chaos weather (data/scripts/chaos/weather.lua, client game_chaosweather) is the
only weather (server/README.md "Weather on the client (O208)").

usage: python3 -I patch_base_rain.py SERVER_DIR [--dry-run]

SERVER_DIR is the folder with config.lua. The base weather script (data/scripts/customs/globalevents/rain.lua) wraps
everything it registers (the startup roll, the five-minute dice, the rain tick that sent a map effect and a distance
effect to every player every 100 ms) in `if configManager.getBoolean(configKeys.WEATHER_RAIN)`, and the engine reads that
from the config.lua key `weatherRain` (default false when the key is missing). This sets `weatherRain = false`, keeping a
trailing comment; a config without the key is left alone (the engine's default is already off). Nothing else changes, the
base script is not edited. `thunderEffect` stays as it is: only that script reads it, and the Chaos weather has no
thunder damage. Idempotent: a second run changes nothing. install_all.py step `baserain`.
"""
import os
import re
import sys

KEY = 'weatherRain'
LINE = re.compile(r'^(?P<lead>[ \t]*%s[ \t]*=[ \t]*)(?P<value>[^\r\n]*?)(?P<tail>[ \t]*--[^\r\n]*)?(?P<eol>\r?)$' % KEY, re.M)


def patch(text):
    """(new text, old value or None when the key is missing)"""
    m = LINE.search(text)
    if not m:
        return text, None
    old = m.group('value').strip()
    if old == 'false':
        return text, old
    new = m.group('lead') + 'false' + (m.group('tail') or '') + m.group('eol')
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
        if old is None:
            print('config.lua: no %s key (the engine default is off), nothing to do' % KEY)
        else:
            print('config.lua: %s = false already' % KEY)
        return 0
    if not dry:
        with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
            f.write(new)
    print('config.lua: %s %s -> false%s' % (KEY, old, ' (dry run)' if dry else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
