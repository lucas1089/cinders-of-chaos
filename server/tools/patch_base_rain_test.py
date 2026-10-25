#!/usr/bin/env python3
"""Test of patch_base_rain.py on a copy of the stock config.lua lines around the key: the value set, the comment kept,
nothing else changed, idempotent, CRLF, a missing key left alone, --dry-run, bad args; and the install_all.py step is wired.
Run: python3 -I server/tools/patch_base_rain_test.py"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, 'patch_base_rain.py')
sys.path.insert(0, HERE)
import patch_base_rain as P  # noqa: E402

STOCK = '''-- Item Usage
timeBetweenActions = 200
timeBetweenExActions = 1000

--- Rain
weatherRain = true
thunderEffect = true
-- Map
-- NOTE: set mapName WITHOUT .otbm at the end
mapName = "world"
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


new, old = P.patch(STOCK)
check(old == 'true', 'the stock value read')
check('\nweatherRain = false\n' in new, 'the value set')
check(new.replace('weatherRain = false', 'weatherRain = true') == STOCK, 'nothing else changed (thunderEffect too)')
check(P.patch(new) == (new, 'false'), 'idempotent')
commented = STOCK.replace('weatherRain = true', 'weatherRain = true -- rain')
check('weatherRain = false -- rain\n' in P.patch(commented)[0], 'a trailing comment kept')
crlf = STOCK.replace('\n', '\r\n')
out = P.patch(crlf)[0]
check('weatherRain = false\r\n' in out and out.count('\r\n') == crlf.count('\r\n'), 'CRLF kept')
missing = STOCK.replace('weatherRain = true\n', '')
check(P.patch(missing) == (missing, None), 'a missing key is left alone (the engine default is off)')
check(P.patch('myweatherRain = true\n')[0] == 'myweatherRain = true\n', 'only the exact key at a line start')
check(P.patch('--weatherRain = true\n')[0] == '--weatherRain = true\n', 'a commented-out key is not touched')

with tempfile.TemporaryDirectory() as d:
    cfg = os.path.join(d, 'config.lua')
    with open(cfg, 'w', encoding='utf-8', newline='') as f:
        f.write(STOCK)
    code, text = run(d, '--dry-run')
    check(code == 0 and 'dry run' in text, 'dry run reports')
    check(open(cfg, encoding='utf-8').read() == STOCK, 'dry run writes nothing')
    code, text = run(d)
    check(code == 0 and 'true -> false' in text, 'first run sets it: ' + text)
    after = open(cfg, encoding='utf-8').read()
    check(after == P.patch(STOCK)[0], 'the file is the patched text')
    code, text = run(d)
    check(code == 0 and 'already' in text and open(cfg, encoding='utf-8').read() == after, 'second run changes nothing')
    check(run(os.path.join(d, 'nope'))[0] == 1, 'no config.lua')
    check(run(d, 'extra')[0] == 1, 'bad args')

with open(os.path.join(HERE, 'install_all.py'), encoding='utf-8') as f:
    inst = f.read()
check("def step_baserain(" in inst and "patch_base_rain.py" in inst, 'install_all.py has the step')
check("'baserain'" in inst and "  baserain " in inst, 'the step is in the docstring and the order')

print('patch_base_rain_test:', 'OK' if not fails else '%d failure(s)' % fails)
sys.exit(1 if fails else 0)
