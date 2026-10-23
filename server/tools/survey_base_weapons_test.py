#!/usr/bin/env python3
"""Test of survey_base_weapons.py on a made-up data folder: kinds, hands, levels, classes, charges, chaos ids left out.
usage: python3 -I server/tools/survey_base_weapons_test.py"""
import csv
import io
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import survey_base_weapons as S  # noqa: E402

ITEMS = """<items>
<item id="100" name="plain sword"><attribute key="weaponType" value="sword" /><attribute key="attack" value="20" /><attribute key="defense" value="10" /></item>
<item id="101" name="big axe"><attribute key="weaponType" value="axe" /><attribute key="slotType" value="two-handed" /><attribute key="attack" value="40" /><attribute key="elementFire" value="5" /></item>
<item id="102" name="long bow"><attribute key="weaponType" value="distance" /><attribute key="slotType" value="two-handed" /><attribute key="attack" value="35" /><attribute key="hitChance" value="95" /><attribute key="range" value="6" /></item>
<item id="103" name="heavy crossbow"><attribute key="weaponType" value="distance" /><attribute key="slotType" value="two-handed" /><attribute key="attack" value="38" /></item>
<item id="104" name="spear"><attribute key="weaponType" value="distance" /><attribute key="attack" value="12" /></item>
<item id="105" name="fire wand"><attribute key="weaponType" value="wand" /></item>
<item id="106" name="one shot blade"><attribute key="weaponType" value="sword" /><attribute key="attack" value="60" /><attribute key="charges" value="1" /></item>
<item id="107" name="no entry club"><attribute key="weaponType" value="club" /><attribute key="attack" value="25" /></item>
<item id="108" name="wand without entry"><attribute key="weaponType" value="wand" /></item>
<item id="109" name="blunt stick"><attribute key="weaponType" value="club" /><attribute key="attack" value="0" /></item>
<item id="110" name="a shield"><attribute key="weaponType" value="shield" /><attribute key="defense" value="30" /></item>
<item id="36654" name="chaos fist"><attribute key="weaponType" value="fist" /><attribute key="attack" value="30" /></item>
<item id="36700" name="chaos sword"><attribute key="weaponType" value="sword" /><attribute key="attack" value="30" /></item>
</items>"""
WEAPONS = """<weapons>
<melee id="100" level="20" unproperly="1"><vocation name="Warrior"/><vocation name="Templar"/></melee>
<melee id="101" level="40" />
<distance id="102" level="30"><vocation name="Ranger"/></distance>
<distance id="103" level="50" />
<distance id="104" level="0" />
<wand id="105" level="26" mana="8" min="40" max="50"><vocation name="Mystic"/><vocation name="Elementalist"/></wand>
<melee id="106" level="1" />
</weapons>"""
MOVEMENTS = """<movements>
<movevent event="Equip" itemid="100" slot="hand" level="25"><vocation name="Warrior"/></movevent>
<movevent event="Equip" itemid="107" slot="hand" level="15"><vocation name="Thief"/></movevent>
<movevent event="Equip" itemid="101" slot="hand" level="99" script="chaos_unique_equip.lua"><vocation name="Monk"/></movevent>
</movements>"""

n = 0


def eq(a, b, m):
    global n
    n += 1
    if a != b:
        raise SystemExit('FAIL %s: %r != %r' % (m, a, b))


with tempfile.TemporaryDirectory() as d:
    for sub, name, text in (('items', 'items.xml', ITEMS), ('weapons', 'weapons.xml', WEAPONS), ('movements', 'movements.xml', MOVEMENTS)):
        os.makedirs(os.path.join(d, sub))
        with open(os.path.join(d, sub, name), 'w', encoding='utf-8') as f:
            f.write(text)
    text, rows = S.survey(d)
    by = {r['id']: r for r in rows}
    eq(sorted(by), [100, 101, 102, 103, 104, 105, 106, 107], 'ids kept: no shield, no wand without an entry, no zero attack, no chaos ids')
    eq(by[100]['kind'], 'sword', 'sword')
    eq(by[100]['level'], 25, 'level: the higher of weapons.xml and the equip rule')
    eq(by[100]['classes'], 'Warrior', 'classes: weapon list against the equip list')
    eq(by[100]['defense'], 10, 'defense')
    eq(by[101]['hands'], 2, 'two-handed')
    eq(by[101]['element'], 5, 'element damage')
    eq(by[101]['level'], 40, 'the unique equip rule is not the stock rule')
    eq(by[101]['classes'], '*', 'no class list = every class')
    eq(by[102]['kind'], 'bow', 'bow')
    eq(by[102]['hit'], 95, 'hit chance')
    eq(by[102]['range'], 6, 'range')
    eq(by[103]['kind'], 'crossbow', 'a crossbow word in the name')
    eq(by[104]['kind'], 'throw', 'one-handed launcher is a throwing weapon')
    eq(by[105]['kind'], 'wand', 'wand')
    eq((by[105]['wmin'], by[105]['wmax'], by[105]['mana']), (40, 50, 8), 'wand damage and mana')
    eq(by[105]['classes'], 'Mystic|Elementalist', 'wand classes')
    eq(by[106]['charges'], 1, 'charges are kept (the audit skips them)')
    eq(by[107]['level'], 15, 'no weapons.xml entry: level of the equip rule')
    eq(by[107]['classes'], 'Thief', 'no weapons.xml entry: classes of the equip rule')
    got = list(csv.DictReader(io.StringIO(text)))
    eq(list(got[0].keys()), S.COLS, 'columns')
    eq(len(got), len(rows), 'csv rows')

# the committed snapshot is well formed
with open(S.OUT, encoding='utf-8') as f:
    committed = list(csv.DictReader(f))
eq(list(committed[0].keys()), S.COLS, 'committed columns')
eq(len(committed) > 400, True, 'committed snapshot has the weapons')
eq(all(int(r['id']) < S.FIRST_CHAOS_ID for r in committed), True, 'committed: stock ids only')
eq(len({r['id'] for r in committed}), len(committed), 'committed: no duplicate id')
eq({r['kind'] for r in committed} <= {'sword', 'axe', 'club', 'bow', 'crossbow', 'throw', 'wand'}, True, 'committed: known kinds')

print('survey_base_weapons_test: %d checks ok' % n)
