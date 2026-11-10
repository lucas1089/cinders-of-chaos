#!/usr/bin/env python3
"""Tests of tools/patch_stock_weapon_growth.py (O472): the stock weapons grow with the level on synthetic items.xml / weapons.xml /
movements.xml, the marker comments, idempotence, a server installed before O472 (no marker) and a change of the table, the survey
reading the numbers before back, and the Lua audit (tools/weapon_coverage.lua --stock) applying the same rule as the step to every row
of data/items/base_weapons.csv.

usage: python3 -I server/tools/patch_stock_weapon_growth_test.py
"""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import patch_stock_weapon_growth as P  # noqa: E402
import survey_base_weapons as SV  # noqa: E402
import weapon_growth as WG  # noqa: E402

fails = 0


def check(cond, msg):
    global fails
    if not cond:
        fails += 1
        print('FAIL: ' + msg)


ITEMS = '''<?xml version="1.0"?>
<items>
\t<item id="2399" article="a" name="a rope" />
\t<item id="2400" name="a sword" article="a">
\t\t<attribute key="weaponType" value="sword" />
\t\t<attribute key="attack" value="55" />
\t\t<attribute key="defense" value="30" />
\t</item>
\t<item id="2401" name="a flame axe" article="a">
\t\t<attribute key="weaponType" value="axe" />
\t\t<attribute key="attack" value="40" />
\t\t<attribute key="elementFire" value="12" />
\t</item>
\t<item id="2402" name="a low club" article="a">
\t\t<attribute key="weaponType" value="club" />
\t\t<attribute key="attack" value="30" />
\t</item>
\t<item id="2403" name="a charged blade" article="a">
\t\t<attribute key="weaponType" value="sword" />
\t\t<attribute key="attack" value="60" />
\t\t<attribute key="charges" value="30" />
\t</item>
\t<item id="2404" name="a wand" article="a">
\t\t<attribute key="weaponType" value="wand" />
\t</item>
\t<item id="2405" name="a rod" article="a">
\t\t<attribute key="weaponType" value="wand" />
\t</item>
\t<item id="2406" name="a long bow" article="a">
\t\t<attribute key="weaponType" value="distance" />
\t\t<attribute key="slotType" value="two-handed" />
\t\t<attribute key="attack" value="90" />
\t\t<attribute key="hitChance" value="93" />
\t</item>
\t<item id="2407" article="a" name="a plain stick" />
\t<item id="36700" name="a chaos blade" article="a">
\t\t<attribute key="weaponType" value="sword" />
\t\t<attribute key="attack" value="55" />
\t</item>
</items>
'''
WEAPONS = '''<?xml version="1.0"?>
<weapons>
\t<melee id="2400" level="300" unproperly="1" />
\t<melee id="2401" level="500" />
\t<melee id="2402" level="60" />
\t<melee id="2403" level="400" />
\t<wand id="2404" level="400" mana="20" min="100" max="140" type="fire" />
\t<wand id="2405" level="50" mana="8" min="20" max="30" type="ice" />
\t<distance id="2406" level="200" />
\t<melee id="36700" level="300" />
</weapons>
'''
MOVES = '<movements>\n</movements>\n'


def make(td, items=ITEMS, weapons=WEAPONS):
    for sub, name, text in (('items', 'items.xml', items), ('weapons', 'weapons.xml', weapons), ('movements', 'movements.xml', MOVES)):
        os.makedirs(os.path.join(td, sub), exist_ok=True)
        open(os.path.join(td, sub, name), 'w').write(text)


def read(td, sub, name):
    return open(os.path.join(td, sub, name)).read()


def attrs(text, wid):
    i = text.index('id="%d"' % wid)
    return dict((k, v) for k, v in SV.KEYVAL.findall(text[i:text.index('</item>', i)]))


def run(td, *extra):
    return P.main([td] + list(extra))


with tempfile.TemporaryDirectory() as td:
    make(td)
    check(run(td) == 0, 'the step runs')
    it, wp = read(td, 'items', 'items.xml'), read(td, 'weapons', 'weapons.xml')
    a300, a500, a200 = WG.weapon_a(300), WG.weapon_a(500), WG.weapon_a(200)
    check(int(attrs(it, 2400)['attack']) == int(55 * a300 + 0.5), 'a sword of level 300: attack x a(300) = %s' % attrs(it, 2400)['attack'])
    check(attrs(it, 2400)['defense'] == '30', 'defense stays')
    check(int(attrs(it, 2401)['attack']) == int(40 * a500 + 0.5) and int(attrs(it, 2401)['elementFire']) == int(12 * a500 + 0.5),
          'an axe of level 500: attack and element damage grow')
    check(attrs(it, 2402)['attack'] == '30', 'level 60: stays (a level of 100 or less does not grow)')
    check(attrs(it, 2403)['attack'] == '60', 'charges: stays')
    check(int(attrs(it, 2406)['attack']) == int(90 * a200 + 0.5) and attrs(it, 2406)['hitChance'] == '93', 'a launcher: attack only')
    check(attrs(it, 36700)['attack'] == '55', 'a weapon of the Chaos tools (id 36654 and up): stays')
    check('<item id="2399" article="a" name="a rope" />' in it and '<item id="2407" article="a" name="a plain stick" />' in it,
          'a self-closing item is left as it is and does not swallow the next weapon')
    check('min="%d" max="%d"' % (int(100 * WG.weapon_a(400) + 0.5), int(140 * WG.weapon_a(400) + 0.5)) in wp, 'a wand of level 400: min and max grow')
    check('min="20" max="30"' in wp, 'a rod of level 50: stays')
    check(it.count('Chaos weapon growth O472') == 1 and wp.count('Chaos weapon growth O472') == 1, 'one marker comment in each file')
    check(P.read_items_block(it)[2400] == (55, {}) and P.read_items_block(it)[2401] == (40, {'elementFire': 12}), 'the marker keeps the numbers before')
    check(P.read_wands_block(wp) == {2404: (100, 140)}, 'the marker of the wands')

    # a second run changes nothing
    before_it, before_wp = it, wp
    run(td)
    check(read(td, 'items', 'items.xml') == before_it and read(td, 'weapons', 'weapons.xml') == before_wp, 'a second run changes nothing')
    # --dry-run writes nothing
    open(os.path.join(td, 'items', 'items.xml'), 'w').write(ITEMS)
    run(td, '--dry-run')
    check(read(td, 'items', 'items.xml') == ITEMS, 'dry run writes nothing')
    open(os.path.join(td, 'items', 'items.xml'), 'w').write(before_it)

    # the survey reads the numbers before back: the snapshot stays the stock one
    _t, rows = SV.survey(td)
    by = {r['id']: r for r in rows}
    check(by[2400]['attack'] == 55 and by[2401]['attack'] == 40 and by[2401]['element'] == 12, 'survey: attack and element before the growth')
    check(by[2404]['wmin'] == 100 and by[2404]['wmax'] == 140, 'survey: wand damage before the growth')
    check(by[2406]['attack'] == 90, 'survey: a launcher before the growth')

    # a change of the table moves the install again (the numbers come from the marker, not from what the file holds)
    saved = WG.WEAPON_GROWTH
    WG.WEAPON_GROWTH = tuple((lv, 1 + (w - 1) * 2) for lv, w in saved)
    run(td)
    it2 = read(td, 'items', 'items.xml')
    check(int(attrs(it2, 2400)['attack']) == int(55 * WG.weapon_a(300) + 0.5) and attrs(it2, 2400)['attack'] != attrs(before_it, 2400)['attack'],
          'a changed table: grown again from the numbers before')
    WG.WEAPON_GROWTH = saved
    run(td)
    check(read(td, 'items', 'items.xml') == before_it, 'the table back: the same numbers again')

# a server installed BEFORE O472 has no marker: the first run moves it to the new numbers (the case above), and a server with the
# old numbers of a Chaos weapon is not touched by this step (the install tools rewrite those blocks)
with tempfile.TemporaryDirectory() as td:
    make(td)
    check(P.read_items_block(read(td, 'items', 'items.xml')) == {}, 'an old install has no marker')
    run(td)
    check(P.read_items_block(read(td, 'items', 'items.xml')) != {}, 'the first run writes it')

# the Lua audit applies the same rule to every row of the committed snapshot
if shutil.which('luajit'):
    out = subprocess.run(['luajit', 'tools/weapon_coverage.lua', '--stock'], cwd=os.path.dirname(HERE), stdout=subprocess.PIPE,
                         universal_newlines=True, check=True).stdout
    lua = {}
    for line in out.splitlines():
        i, a, e, lo, hi = line.split()
        lua[int(i)] = (int(a), int(e), int(lo), int(hi))
    csv_rows = {}
    import csv
    with open(os.path.join(HERE, '..', 'data', 'items', 'base_weapons.csv'), newline='') as f:
        for r in csv.DictReader(f):
            csv_rows[int(r['id'])] = r
    check(set(lua) == set(csv_rows) and len(lua) > 400, 'the audit lists every row of base_weapons.csv (%d)' % len(lua))
    bad = []
    for wid, r in csv_rows.items():
        level, kind, charges = int(r['level']), r['kind'], int(r['charges'])
        attack, element, wmin, wmax = int(r['attack']), int(r['element']), int(r['wmin']), int(r['wmax'])
        a = WG.weapon_a(level)
        if P.grows(kind, level, charges):
            attack = int(attack * a + 0.5) if attack > 0 else attack
            element = int(element * a + 0.5) if element > 0 else element
        if kind == 'wand' and P.wand_grows(level):
            wmin, wmax = int(wmin * a + 0.5), int(wmax * a + 0.5)
        if lua[wid] != (attack, element, wmin, wmax):
            bad.append((wid, lua[wid], (attack, element, wmin, wmax)))
    check(not bad, 'the Lua rule equals the step\'s on every row: %r' % bad[:3])
    grown = sum(1 for r in csv_rows.values() if P.grows(r['kind'], int(r['level']), int(r['charges'])))
    check(grown > 100, 'a good part of the snapshot grows (%d weapons)' % grown)
else:
    print('luajit not found: the Lua audit comparison is skipped')

print('patch_stock_weapon_growth_test: ' + ('%d failed' % fails if fails else 'ok'))
sys.exit(1 if fails else 0)
