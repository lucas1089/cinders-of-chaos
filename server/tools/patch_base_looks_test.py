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
        # owner 2026-10-22: the pack art looks were bad; the base monsters are back on their stock looks (restore rows).
        # O533: the rows of lib pair50 give a base monster a look of pair 50 (2682-3360) that has an idle animation.
        lib = next(r['lib'] for r in csv.DictReader(open(P.PICKS, newline='')) if r['family'] == 'base' and r['monsters'] == name)
        check(look < 2000 if lib == 'stock' else (lib == 'pair50' and 2682 <= look <= 3360), '%s: a stock look or a pair 50 look' % name)

tmp = tempfile.mkdtemp()
try:
    m = os.path.join(tmp, 'monster', 'monsters')
    own = os.path.join(m, 'chaos')
    os.makedirs(own)
    # the mechanics on a table with one sheet look and one plain look (picks.csv has no sheet row since 2026-10-22)
    row = next(iter(sheets.values()))
    want = {'Sheet Test Monster': (int(row['look_type']), {c: row[c] for c in P.SHEET_COLOURS}),
            'Plain Test Monster': (298, {})}
    sheet_name, kit_name = 'Sheet Test Monster', 'Plain Test Monster'
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
    # Lua monsters of the base (O533): lookType changes, the colour fields go, lookMount and the rest stay
    lua = os.path.join(tmp, 'monster', 'lua', 'soul_war')
    os.makedirs(lua)
    colours_lua = '\tlookHead = 81,\n\tlookBody = 114,\n\tlookLegs = 85,\n\tlookFeet = 83,\n\tlookAddons = 0,\n'
    lua_src = ('local mType = Game.createMonsterType("%s")\nlocal monster = {}\n\nmonster.outfit = {\n\tlookType = 1046,\n'
               + colours_lua + '\tlookMount = 0\n}\n\nmonster.health = 5\n')
    open(os.path.join(lua, 'a.lua'), 'w').write(lua_src % 'Lua Test Monster')
    open(os.path.join(lua, 'b.lua'), 'w').write('local mType = Game.createMonsterType("Lua Plain")\nmonster.outfit = {\n\tlookType = 978\n}\n')
    open(os.path.join(lua, 'c.lua'), 'w').write(lua_src % 'Lua Other')
    lwant = {'Lua Test Monster': (3184, {}), 'Lua Plain': (3349, {})}
    changed, missing = P.patch(tmp, lwant, log=logs.append)
    check(changed == 2 and not missing, 'two Lua monsters updated, got %d %s' % (changed, missing))
    a = open(os.path.join(lua, 'a.lua')).read()
    check(a == (lua_src.replace('1046', '3184').replace(colours_lua, '') % 'Lua Test Monster'), 'Lua colours removed, lookMount kept: ' + a)
    check('lookType = 3349' in open(os.path.join(lua, 'b.lua')).read(), 'Lua monster with one field')
    check('lookType = 1046' in open(os.path.join(lua, 'c.lua')).read(), 'other Lua monsters untouched')
    changed, _ = P.patch(tmp, lwant, log=logs.append)
    check(changed == 0, 'Lua: idempotent')
    tint = {'head': '1', 'body': '2', 'legs': '3', 'feet': '4'}
    open(os.path.join(lua, 'd.lua'), 'w').write(lua_src % 'Lua Sheet')
    P.patch(tmp, {'Lua Sheet': (2300, tint)}, log=logs.append)
    d = open(os.path.join(lua, 'd.lua')).read()
    check('lookType = 2300, lookHead = 1, lookBody = 2, lookLegs = 3, lookFeet = 4,\n\tlookMount = 0' in d, 'Lua sheet look with tint: ' + d)
    changed, _ = P.patch(tmp, {'Lua Sheet': (2300, tint)}, log=logs.append)
    check(changed == 0, 'Lua sheet: idempotent')
    check(P.main([tmp, '--dry-run', '--strict']) == 1, '--strict fails on a missing name')
finally:
    shutil.rmtree(tmp)

print('patch_base_looks_test: %s' % ('OK' if not fails else '%d FAILED' % fails))
sys.exit(1 if fails else 0)
