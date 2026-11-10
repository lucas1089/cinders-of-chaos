#!/usr/bin/env python3
"""Test of patch_base_armor_percent.py: the value set, the comment kept, a missing key added (the engine default is 80),
nothing else changed, idempotent, CRLF, --dry-run, bad args, and the install_all.py step is wired.
Run: python3 -I server/tools/patch_base_armor_percent_test.py"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, 'patch_base_armor_percent.py')
sys.path.insert(0, HERE)
import patch_base_armor_percent as P  # noqa: E402

STOCK = '''-- Combat settings
armorPercent = true
armorPercentConstant = 250
armorPercentMax = 80
hotkeyAimbotEnabled = true
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
check(old == '80', 'the stock value read')
check('\narmorPercentMax = 0\n' in new, 'the value set')
check(new.replace('armorPercentMax = 0', 'armorPercentMax = 80') == STOCK, 'nothing else changed (armorPercent stays true)')
check('armorPercent = true' in new and 'armorPercentConstant = 250' in new, 'the other two armour keys are left alone')
check(P.patch(new) == (new, '0'), 'idempotent')
commented = STOCK.replace('armorPercentMax = 80', 'armorPercentMax = 80 -- cap')
check('armorPercentMax = 0 -- cap\n' in P.patch(commented)[0], 'a trailing comment kept')
crlf = STOCK.replace('\n', '\r\n')
out = P.patch(crlf)[0]
check('armorPercentMax = 0\r\n' in out and out.count('\r\n') == crlf.count('\r\n'), 'CRLF kept')
missing = STOCK.replace('armorPercentMax = 80\n', '')
added, old2 = P.patch(missing)
check(old2 is None and added.endswith(P.ADDED + '\n') and added.count('armorPercentMax') == 1, 'a missing key is added (engine default 80)')
check(P.patch(added) == (added, '0'), 'the added line is stable')
check(P.patch('myarmorPercentMax = 80\n')[0].count('\narmorPercentMax = 0') == 1, 'only the exact key at a line start counts')
check(P.patch('--armorPercentMax = 80\n')[0].count('armorPercentMax = 0') == 1, 'a commented-out key is not the key')
nonl = 'armorPercent = true'
check(P.patch(nonl)[0] == nonl + '\n' + P.ADDED + '\n', 'a file without a final newline gets one')

with tempfile.TemporaryDirectory() as d:
    cfg = os.path.join(d, 'config.lua')
    with open(cfg, 'w', encoding='utf-8', newline='') as f:
        f.write(STOCK)
    code, text = run(d, '--dry-run')
    check(code == 0 and 'dry run' in text, 'dry run reports')
    check(open(cfg, encoding='utf-8').read() == STOCK, 'dry run writes nothing')
    code, text = run(d)
    check(code == 0 and '80 -> 0' in text, 'first run sets it: ' + text)
    after = open(cfg, encoding='utf-8').read()
    check(after == P.patch(STOCK)[0], 'the file is the patched text')
    code, text = run(d)
    check(code == 0 and 'already' in text and open(cfg, encoding='utf-8').read() == after, 'second run changes nothing')
    check(run(os.path.join(d, 'nope'))[0] == 1, 'no config.lua')
    check(run(d, 'extra')[0] == 1, 'bad args')

with open(os.path.join(HERE, 'install_all.py'), encoding='utf-8') as f:
    inst = f.read()
check('def step_armourlayer(' in inst and 'patch_base_armor_percent.py' in inst, 'install_all.py has the step')
check("'armourlayer'" in inst and '  armourlayer ' in inst, 'the step is in the docstring and the order')

print('patch_base_armor_percent_test:', 'OK' if not fails else '%d failure(s)' % fails)
sys.exit(1 if fails else 0)
