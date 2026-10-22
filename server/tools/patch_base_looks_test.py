#!/usr/bin/env python3
"""Tests for patch_base_looks.py on a synthetic monster folder (no base server needed).

usage: python3 -I server/tools/patch_base_looks_test.py
"""
import csv
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import patch_base_looks as P  # noqa: E402

fails = 0


def check(cond, msg):
    global fails
    if not cond:
        fails += 1
        print('FAIL', msg)


def mon(name, look):
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<monster name="%s" nameDescription="a x" race="blood" '
            'experience="10" speed="100">\n\t<health now="50" max="50"/>\n\t%s\n</monster>\n' % (name, look))


# the real table: every base row names a look of the live pair, sheet rows have their tint
want = P.wanted()
check(len(want) >= 9, 'base rows in picks.csv')
sheets = {r['look_type']: r for r in csv.DictReader(open(P.SHEETS, newline=''))}
for name, (look, colours) in want.items():
    if colours:
        check(str(look) in sheets, '%s: a pair 30 sheet look' % name)
        check(set(colours) == set(P.SHEET_COLOURS), '%s: four colours' % name)
    else:
        check(2658 <= look <= 2667, '%s: a pair 33 kit look' % name)

tmp = tempfile.mkdtemp()
try:
    m = os.path.join(tmp, 'monster', 'monsters')
    own = os.path.join(m, 'chaos')
    os.makedirs(own)
    sheet_name = next(n for n, (_, c) in want.items() if c)
    kit_name = next(n for n, (_, c) in want.items() if not c)
    open(os.path.join(m, 'a.xml'), 'w').write(mon(sheet_name, '<look type="95" corpse="6027" />'))
    open(os.path.join(m, 'b.xml'), 'w').write(mon(kit_name, '<look type="129" head="1" body="2" legs="3" feet="4" '
                                                            'addons="3" corpse="5993" />'))
    open(os.path.join(m, 'c.xml'), 'w').write(mon('Somebody Else', '<look type="5" corpse="1" />'))
    open(os.path.join(own, 'd.xml'), 'w').write(mon(sheet_name, '<look type="7" corpse="1" />'))
    logs = []
    changed, missing = P.patch(tmp, want, dry_run=True, log=logs.append)
    check(changed == 2, 'dry run: two to update, got %d' % changed)
    check('look type="95"' in open(os.path.join(m, 'a.xml')).read(), 'dry run writes nothing')
    changed, missing = P.patch(tmp, want, log=logs.append)
    a = open(os.path.join(m, 'a.xml')).read()
    look, colours = want[sheet_name]
    check('<look type="%d" head="%s" body="%s" legs="%s" feet="%s" corpse="6027" />' % (
        look, colours['head'], colours['body'], colours['legs'], colours['feet']) in a, 'sheet look with tint: ' + a)
    b = open(os.path.join(m, 'b.xml')).read()
    check('<look type="%d" corpse="5993" />' % want[kit_name][0] in b, 'kit look without colours: ' + b)
    check('type="5"' in open(os.path.join(m, 'c.xml')).read(), 'other monsters untouched')
    check('type="7"' in open(os.path.join(own, 'd.xml')).read(), 'the Chaos folder untouched')
    check(len(missing) == len(want) - 2, 'the others are reported missing')
    changed, _ = P.patch(tmp, want, log=logs.append)
    check(changed == 0, 'idempotent')
    check(P.main([tmp, '--dry-run', '--strict']) == 1, '--strict fails on a missing name')
finally:
    shutil.rmtree(tmp)

print('patch_base_looks_test: %s' % ('OK' if not fails else '%d FAILED' % fails))
sys.exit(1 if fails else 0)
