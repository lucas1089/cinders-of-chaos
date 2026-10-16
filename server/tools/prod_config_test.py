#!/usr/bin/env python3
"""Test of prod_config.py on a temporary config.lua (stock lines around the settings it writes): every setting written
once, a second run changes nothing, and the respawn near players options of engine patch 0041 (spawnNearPlayers,
spawnMinPlayerDistance): true / 2 on a first run, a value already in config.lua kept, --spawn-near-players and
--spawn-min-distance set it, bad values refused with nothing written. Also the cropped test map refusal.
Run: python3 -I server/tools/prod_config_test.py (standard library only)."""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, 'prod_config.py')

STOCK = '''-- Combat settings
worldType = "pvp"
protectionLevel = 1

-- Connection Config
ip = "127.0.0.1"
maxPlayers = 0
motd = "Welcome!"

-- Map
mapName = "world"

-- Rates
rateExp = 5
rateSpawn = 1
'''

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL: ' + what)


def run(folder, *args):
    p = subprocess.run([sys.executable, '-I', TOOL, folder, '--public-host', 'play.example.com'] + list(args),
                       capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def value(text, key):
    m = re.search(r'^%s = (.*?) -- Chaos production' % re.escape(key), text, re.M)
    return m.group(1) if m else None


def config(folder):
    with open(os.path.join(folder, 'config.lua'), encoding='utf-8') as f:
        return f.read()


def fresh(folder, text=STOCK):
    with open(os.path.join(folder, 'config.lua'), 'w', encoding='utf-8') as f:
        f.write(text)


with tempfile.TemporaryDirectory() as d:
    # first run: the production values, the spawn options at their defaults
    fresh(d)
    rc, out = run(d)
    text = config(d)
    check(rc == 0, 'first run exit 0: ' + out)
    check(value(text, 'spawnNearPlayers') == 'true', 'spawnNearPlayers = true on a first run')
    check(value(text, 'spawnMinPlayerDistance') == '2', 'spawnMinPlayerDistance = 2 on a first run')
    check(value(text, 'rateSpawn') == '3', 'rateSpawn = 3')
    check(text.count('spawnNearPlayers') == 1 and text.count('rateSpawn') == 1, 'each key written once')
    check('rateExp = 5\n' in text and 'mapName = "world"\n' in text, 'other settings unchanged')

    # second run: nothing changes
    rc, out = run(d)
    check(rc == 0 and 'already the production settings' in out, 'second run changes nothing: ' + out)
    check(config(d) == text, 'second run leaves the file as it was')

    # an owner's own tuning in config.lua is kept by a later run without the options
    fresh(d, text.replace('spawnMinPlayerDistance = 2', 'spawnMinPlayerDistance = 4')
              .replace('spawnNearPlayers = true', 'spawnNearPlayers = false'))
    rc, out = run(d)
    text = config(d)
    check(value(text, 'spawnMinPlayerDistance') == '4', 'a tuned distance is kept')
    check(value(text, 'spawnNearPlayers') == 'false', 'a stock rule set by hand is kept')

    # the options set it, and a second run with the same options changes nothing
    rc, out = run(d, '--spawn-near-players', 'yes', '--spawn-min-distance', '3')
    text = config(d)
    check(rc == 0, 'options exit 0: ' + out)
    check(value(text, 'spawnNearPlayers') == 'true', '--spawn-near-players yes')
    check(value(text, 'spawnMinPlayerDistance') == '3', '--spawn-min-distance 3')
    rc, out = run(d, '--spawn-near-players', 'yes', '--spawn-min-distance', '3')
    check(config(d) == text, 'same options twice: no change')
    rc, out = run(d, '--spawn-near-players', 'off')
    check(value(config(d), 'spawnNearPlayers') == 'false', '--spawn-near-players off')

    # bad values: refused, nothing written
    before = config(d)
    for args in (('--spawn-near-players', 'maybe'), ('--spawn-min-distance', '9'), ('--spawn-min-distance', 'x'),
                 ('--spawn-min-distance', '-1')):
        rc, out = run(d, *args)
        check(rc != 0, 'refused: %s' % ' '.join(args))
        check(config(d) == before, 'nothing written for %s' % ' '.join(args))

    # a cropped test map is refused before anything is written
    fresh(d, STOCK.replace('mapName = "world"', 'mapName = "zcrop_test"'))
    rc, out = run(d)
    check(rc == 1 and 'spawnNearPlayers' not in config(d), 'cropped test map refused')

print('prod_config_test: %s' % ('OK' if not fails else '%d failure(s)' % fails))
sys.exit(1 if fails else 0)
