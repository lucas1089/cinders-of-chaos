#!/usr/bin/env python3
"""Test of patch_base_idle_kick.py on a copy of the stock config.lua text (the lines around the key as the base server
ships them): the value set, the comment kept, the rest unchanged, idempotent, CRLF, a missing key, --dry-run, bad args.
Run: python3 -I server/tools/patch_base_idle_kick_test.py"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, 'patch_base_idle_kick.py')
sys.path.insert(0, HERE)
import patch_base_idle_kick as P  # noqa: E402

STOCK = '''-- Combat settings
-- NOTE: valid values for worldType are: "pvp", "no-pvp" and "pvp-enforced"
worldType = "pvp"
hotkeyAimbotEnabled = true
protectionLevel = 1
killsToRedSkull = 3

-- Connection Config
-- NOTE: maxPlayers set to 0 means no limit
ip = "127.0.0.1"
maxPlayers = 0
motd = "Welcome!"
onePlayerOnlinePerAccount = true
allowClones = false
statusTimeout = 5000
replaceKickOnLogin = true
maxPacketsPerSecond = 25

-- Deaths
-- NOTE: Leave deathLosePercent as -1 if you want to use the default
-- death penalty formula. For the old formula, set it to 10. For
-- no skill/experience loss, set it to 0.
deathLosePercent = -1

-- Houses
housePriceEachSQM = 1000
houseRentPeriod = "never"

-- Item Usage
timeBetweenActions = 200
timeBetweenExActions = 1000

-- Map
-- NOTE: set mapName WITHOUT .otbm at the end
mapName = "world"
mapAuthor = "author"

-- Misc.
allowChangeOutfit = true
freePremium = false
kickIdlePlayerAfterMinutes = 15
maxMessageBuffer = 4
emoteSpells = false
'''

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


def run(folder, *extra):
    p = subprocess.run([sys.executable, '-I', TOOL, folder] + list(extra), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return p.returncode, p.stdout.decode()


new, old = P.patch(STOCK, 1440)
check(old == '15', 'the stock value read')
check('kickIdlePlayerAfterMinutes = 1440\n' in new, 'the value set')
check(new.replace('kickIdlePlayerAfterMinutes = 1440', 'kickIdlePlayerAfterMinutes = 15') == STOCK, 'nothing else changed')
check(P.patch(new, 1440)[0] == new, 'idempotent')
commented = STOCK.replace('kickIdlePlayerAfterMinutes = 15', 'kickIdlePlayerAfterMinutes = 15 -- minutes')
check('kickIdlePlayerAfterMinutes = 1440 -- minutes\n' in P.patch(commented, 1440)[0], 'a trailing comment kept')
crlf = STOCK.replace('\n', '\r\n')
out = P.patch(crlf, 600)[0]
check('kickIdlePlayerAfterMinutes = 600\r\n' in out and out.count('\r\n') == crlf.count('\r\n'), 'CRLF kept')
missing = STOCK.replace('kickIdlePlayerAfterMinutes = 15\n', '')
out, old = P.patch(missing, 1440)
check(old is None and out.startswith(missing) and 'kickIdlePlayerAfterMinutes = 1440' in out, 'a missing key appended')
check(P.patch(out, 1440)[0] == out, 'appended once')
check(P.patch('maxkickIdlePlayerAfterMinutes = 3\n', 9)[0].count('= 9') == 1, 'only the exact key at a line start')

with tempfile.TemporaryDirectory() as d:
    cfg = os.path.join(d, 'config.lua')
    with open(cfg, 'w', encoding='utf-8', newline='') as f:
        f.write(STOCK)
    code, text = run(d, '--dry-run')
    check(code == 0 and 'dry run' in text, 'dry run reports')
    check(open(cfg, encoding='utf-8').read() == STOCK, 'dry run writes nothing')
    code, text = run(d)
    check(code == 0 and '15 -> 1440' in text, 'first run sets it: ' + text)
    after = open(cfg, encoding='utf-8').read()
    code, text = run(d)
    check(code == 0 and 'already' in text and open(cfg, encoding='utf-8').read() == after, 'second run changes nothing')
    code, text = run(d, '--minutes', '120')
    check(code == 0 and 'kickIdlePlayerAfterMinutes = 120\n' in open(cfg, encoding='utf-8').read(), '--minutes')
    check(run(d, '--minutes', '0')[0] == 1, '0 refused (the engine kicks after a minute)')
    check(run(d, '--minutes', 'x')[0] == 1, 'a bad number refused')
    check(run(os.path.join(d, 'nope'))[0] == 1, 'no config.lua')

print('patch_base_idle_kick_test:', 'OK' if not fails else '%d failure(s)' % fails)
sys.exit(1 if fails else 0)
