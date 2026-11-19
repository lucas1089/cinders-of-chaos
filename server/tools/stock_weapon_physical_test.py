#!/usr/bin/env python3
"""Tests of tools/stock_weapon_physical.py (O673) and of its use in tools/patch_stock_weapon_growth.py: the rule, the install step on
synthetic items.xml files (an element-heavy sword is split, an item without an attack line gets one, a bow, a charged weapon and a
plain one are left alone, the marker keeps the numbers before, a second run changes nothing), the shared share (install_gear_sets.py),
the Lua audit (tools/weapon_coverage.lua --stock) and the table of chaos_weapon_growth.lua.

usage: python3 -I server/tools/stock_weapon_physical_test.py
"""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_gear_sets as GS  # noqa: E402
import patch_stock_weapon_growth as PG  # noqa: E402
import stock_weapon_physical as SP  # noqa: E402
import survey_base_weapons as SV  # noqa: E402
import weapon_growth as WG  # noqa: E402

fails = 0


def check(cond, msg):
    global fails
    if not cond:
        fails += 1
        print('FAIL: ' + msg)


# ------------------------------------------------------------------------------------------------ the rule
check(SP.ELEMENT_SHARE == GS.ELEMENT_SHARE, 'the share is the sets\' (install_gear_sets.py ELEMENT_SHARE)')
check(SP.split(13, {'e': 73}) == (56, {'e': 30}), 'a level 600 soul sword 13 + 73: total 86 kept, element 30, attack 56: %r' % (SP.split(13, {'e': 73}),))
check(SP.split(0, {'e': 67}) == (44, {'e': 23}), 'an attack of 0 + 67: 44 + 23')
check(SP.split(85, {}) == (85, {}), 'no element: left alone')
check(SP.split(40, {'e': 17}) == (40, {'e': 17}), 'an element under the cap (30%): left alone')
check(SP.split(38, {'e': 20}) == (38, {'e': 20}), 'exactly at the cap: left alone')
check(SP.split(29, {'e': 29}) == (38, {'e': 20}), 'half and half: 58 -> 38 + 20')
a, e = SP.split(10, {'fire': 60, 'ice': 20})
check(a + sum(e.values()) == 90 and sum(e.values()) == int(90 * 0.35 + 0.5) and e['fire'] > 2 * e['ice'], 'two keys: the cap shared by size: %r %r' % (a, e))
a, e = SP.split(0, {'a': 1, 'b': 1, 'c': 1})
check(a + sum(e.values()) == 3 and sum(e.values()) == 1, 'the rounding drift lands on one key: %r %r' % (a, e))
for total in range(1, 400):
    for el in range(0, total + 1):
        a, e = SP.split(total - el, {'e': el})
        if a + e['e'] != total or e['e'] > int(total * 0.35 + 0.5) or (el <= int(total * 0.35 + 0.5) and e['e'] != el):
            check(False, 'the rule on %d + %d: %r %r' % (total - el, el, a, e))
            break
    else:
        continue
    break
check(SP.applies('sword', 101, 0) and SP.applies('axe', 600, 0) and SP.applies('club', 2000, 0), 'melee kinds above level 100 are read')
check(not SP.applies('sword', 100, 0) and not SP.applies('sword', 300, 5) and not SP.applies('bow', 300, 0)
      and not SP.applies('crossbow', 300, 0) and not SP.applies('wand', 300, 0), 'level 100, charges, a launcher and a wand are not')

# ------------------------------------------------------------------------------------------------ the snapshot
rows = SP.rows()
check(len(rows) > 100, 'the stock melee rows of base_weapons.csv (%d)' % len(rows))
check(SP.check() == [], 'the rule holds on every row: %r' % SP.check()[:3])
heavy_before = [r for r in rows if SP.applies(r['kind'], r['level'], r['charges']) and r['grown'][1] > 0
                and r['grown'][0] < 0.6 * sum(r['grown'])]
heavy_after = [r for r in rows if SP.applies(r['kind'], r['level'], r['charges']) and r['after'][1] > 0
               and r['after'][0] < 0.6 * sum(r['after'])]
check(len(heavy_before) == 44, 'the snapshot has 44 element-heavy stock melee weapons before the rule (%d)' % len(heavy_before))
check(not heavy_after, 'and none after it: %r' % [r['id'] for r in heavy_after][:5])
lvl600 = [r for r in rows if r['level'] == 600]
check(len(lvl600) == 12 and min(r['after'][0] for r in lvl600) >= 56, 'the twelve weapons of level 600 read an attack of 56 or more (was 13 to 16)')
check('band' in SP.table(), 'the table prints')

# ------------------------------------------------------------------------------------------------ the install step
ITEMS = '''<?xml version="1.0"?>
<items>
\t<item id="3001" article="a" name="a soul blade">
\t\t<attribute key="weaponType" value="sword" />
\t\t<attribute key="attack" value="8" />
\t\t<attribute key="elementFire" value="46" />
\t\t<attribute key="defense" value="32" />
\t</item>
\t<item id="3002" article="a" name="an elemental axe">
\t\t<attribute key="weaponType" value="axe" />
\t\t<attribute key="elementIce" value="50" />
\t\t<attribute key="defense" value="30" />
\t</item>
\t<item id="3003" article="a" name="a plain club">
\t\t<attribute key="weaponType" value="club" />
\t\t<attribute key="attack" value="60" />
\t</item>
\t<item id="3004" article="a" name="a flame bow">
\t\t<attribute key="weaponType" value="distance" />
\t\t<attribute key="slotType" value="two-handed" />
\t\t<attribute key="attack" value="8" />
\t\t<attribute key="elementFire" value="46" />
\t</item>
\t<item id="3005" article="a" name="a charged sword">
\t\t<attribute key="weaponType" value="sword" />
\t\t<attribute key="attack" value="8" />
\t\t<attribute key="elementFire" value="46" />
\t\t<attribute key="charges" value="10" />
\t</item>
\t<item id="3006" article="a" name="a low blade">
\t\t<attribute key="weaponType" value="sword" />
\t\t<attribute key="attack" value="8" />
\t\t<attribute key="elementFire" value="46" />
\t</item>
\t<item id="3007" article="a" name="a two element sword">
\t\t<attribute key="weaponType" value="sword" />
\t\t<attribute key="attack" value="10" />
\t\t<attribute key="elementFire" value="40" />
\t\t<attribute key="elementEarth" value="20" />
\t</item>
</items>
'''
WEAPONS = '''<?xml version="1.0"?>
<weapons>
\t<melee id="3001" level="600" />
\t<melee id="3002" level="330" />
\t<melee id="3003" level="400" />
\t<distance id="3004" level="600" />
\t<melee id="3005" level="600" />
\t<melee id="3006" level="100" />
\t<melee id="3007" level="500" />
</weapons>
'''


def attrs(text, wid):
    i = text.index('id="%d"' % wid)
    return dict(SV.KEYVAL.findall(text[i:text.index('</item>', i)]))


with tempfile.TemporaryDirectory() as td:
    for sub, name, text in (('items', 'items.xml', ITEMS), ('weapons', 'weapons.xml', WEAPONS), ('movements', 'movements.xml', '<movements>\n</movements>\n')):
        os.makedirs(os.path.join(td, sub), exist_ok=True)
        open(os.path.join(td, sub, name), 'w').write(text)
    check(PG.main([td]) == 0, 'the step runs')
    it = open(os.path.join(td, 'items', 'items.xml')).read()
    a600 = WG.weapon_a(600)
    total = int(8 * a600 + 0.5) + int(46 * a600 + 0.5)
    cap = int(total * 0.35 + 0.5)
    at = attrs(it, 3001)
    check(int(at['attack']) == total - cap and int(at['elementFire']) == cap and at['defense'] == '32',
          'a soul blade of level 600: total %d, element %d, attack %d: %r' % (total, cap, total - cap, at))
    at = attrs(it, 3002)
    t330 = int(50 * WG.weapon_a(330) + 0.5)
    check(int(at['attack']) == t330 - int(t330 * 0.35 + 0.5) and int(at['elementIce']) == int(t330 * 0.35 + 0.5),
          'an element only axe (no attack line) gets one: %r' % at)
    at = attrs(it, 3003)
    check(int(at['attack']) == int(60 * WG.weapon_a(400) + 0.5) and 'elementFire' not in at, 'a plain club only grows: %r' % at)
    at = attrs(it, 3004)
    check(int(at['attack']) == int(8 * a600 + 0.5) and int(at['elementFire']) == int(46 * a600 + 0.5), 'a bow grows and is not split: %r' % at)
    at = attrs(it, 3005)
    check(at['attack'] == '8' and at['elementFire'] == '46', 'a weapon with charges stays: %r' % at)
    at = attrs(it, 3006)
    check(at['attack'] == '8' and at['elementFire'] == '46', 'a weapon of level 100 stays: %r' % at)
    at = attrs(it, 3007)
    a500 = WG.weapon_a(500)
    t7 = int(10 * a500 + 0.5) + int(40 * a500 + 0.5) + int(20 * a500 + 0.5)
    c7 = int(t7 * 0.35 + 0.5)
    check(int(at['attack']) + int(at['elementFire']) + int(at['elementEarth']) == t7 and int(at['elementFire']) + int(at['elementEarth']) == c7
          and int(at['elementFire']) > int(at['elementEarth']), 'two elements: the cap %d shared, the total %d kept: %r' % (c7, t7, at))
    # the marker keeps the numbers before: the survey reads them back
    kept = PG.read_items_block(it)
    check(kept[3001] == (8, {'elementFire': 46}) and kept[3002] == (0, {'elementIce': 50}), 'the marker holds the numbers before: %r' % kept)
    _t, srows = SV.survey(td)
    by = {r['id']: r for r in srows}
    check(by[3001]['attack'] == 8 and by[3001]['element'] == 46 and by[3002]['attack'] == 0 and by[3002]['element'] == 50,
          'the survey reads the numbers before')
    # a second run changes nothing
    before = it
    PG.main([td])
    check(open(os.path.join(td, 'items', 'items.xml')).read() == before, 'a second run changes nothing')

# ------------------------------------------------------------------------------------------------ the Lua audit and the table
if shutil.which('luajit'):
    out = subprocess.run(['luajit', 'tools/weapon_coverage.lua', '--stock'], cwd=os.path.dirname(HERE), stdout=subprocess.PIPE,
                         universal_newlines=True, check=True).stdout
    lua = {int(l.split()[0]): (int(l.split()[1]), int(l.split()[2])) for l in out.splitlines()}
    bad = [(r['id'], lua.get(r['id']), r['after']) for r in rows if lua.get(r['id']) != r['after']]
    check(not bad, 'the Lua audit applies the same rule on every stock melee row: %r' % bad[:3])
    out = subprocess.run(['luajit', 'tools/weapon_coverage.lua', '--phys'], cwd=os.path.dirname(HERE), stdout=subprocess.PIPE,
                         universal_newlines=True, check=True).stdout
    check('Juggernaut' in out and '!' not in out.split('\n\n')[0], 'the physical audit prints and flags nothing')
else:
    print('luajit not found: the Lua comparison is skipped')

# the table of the upgrade on touch follows the rule (a stock row = the attack before the growth and after the rule)
sys.path.insert(0, HERE)
import gen_weapon_growth as GG  # noqa: E402
st = GG.stock_rows()
for r in rows:
    if SP.applies(r['kind'], r['level'], r['charges']) and (r['before'][0] > 0 or r['before'][1] > 0) and r['after'][0] != r['before'][0]:
        check(st.get(r['id']) == (r['before'][0], r['after'][0]), 'chaos_weapon_growth row %d: %r against %r' % (r['id'], st.get(r['id']), (r['before'][0], r['after'][0])))
check(st[27458] == (8, 56), 'the sanguine blade: attack 8 before, 56 after (was 8 -> 13)')

print('stock_weapon_physical_test: ' + ('%d failed' % fails if fails else 'ok'))
sys.exit(1 if fails else 0)
