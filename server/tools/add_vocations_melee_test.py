#!/usr/bin/env python3
"""Melee items serve every melee class (owner debug item 46; add_vocations.py step 3): a small synthetic items.xml,
weapons.xml and movements.xml (no game data; CI runs it).

    python3 -I server/tools/add_vocations_melee_test.py

A sword, an axe and a club of any size, one- or two-handed, that list vocations get the Thief, Monk and Templar lines
(the Warrior line is what the Knight's list converts to; the Berserker stays two-handed only); a throwing weapon only the
Thief line; a bow none of them; the hand equip events follow the weapons; a second run changes nothing; a list that named
the Thief line already (an old install) gets the other two lines and keeps its own.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import add_vocations as A  # noqa: E402

ITEMS = '''<items>
	<item id="100" name="sabre"><attribute key="weaponType" value="sword" /></item>
	<item id="101" name="great sword"><attribute key="weaponType" value="sword" /><attribute key="slotType" value="two-handed" /></item>
	<item id="102" name="hand axe"><attribute key="weaponType" value="axe" /></item>
	<item id="103" name="war axe"><attribute key="weaponType" value="axe" /><attribute key="slotType" value="two-handed" /></item>
	<item id="104" name="mace"><attribute key="weaponType" value="club" /></item>
	<item id="105" name="staff"><attribute key="weaponType" value="club" /><attribute key="slotType" value="two-handed" /></item>
	<item id="106" name="throwing star"><attribute key="weaponType" value="distance" /></item>
	<item id="107" name="short bow"><attribute key="weaponType" value="distance" /><attribute key="slotType" value="two-handed" /><attribute key="ammoType" value="arrow" /></item>
</items>
'''


def weapon(tag, item, voc='Knight'):
    return ('\t<%s id="%d" level="10" action="removecount">\n\t\t<vocation name="%s" />\n\t</%s>\n'
            % (tag, item, voc, tag))


def movement(item):
    return ('\t<movevent event="Equip" itemid="%d" slot="hand" level="10" function="onEquipItem">\n'
            '\t\t<vocation name="Knight" />\n\t</movevent>\n' % item)


WEAPONS = '<weapons>\n' + ''.join(weapon('melee', i) for i in (100, 101, 102, 103, 104, 105)) + \
    weapon('distance', 106) + weapon('distance', 107, 'Paladin') + '</weapons>\n'
MOVEMENTS = '<movements>\n' + ''.join(movement(i) for i in (100, 101, 102, 103, 104, 105)) + '</movements>\n'
LINES = {'thief': A.LINE, 'monk': A.MONK_LINE, 'templar': A.TEMPLAR_LINE}

fails = []


def check(cond, what):
    if not cond:
        fails.append(what)


def names_of(text, item, tag):
    m = re.search(r'<%s\b[^>]*\b(?:id|itemid)="%d".*?</%s>' % (tag, item, tag), text, re.S)
    return A.names_in(m.group(0))


info = A.item_info(ITEMS)
for item in (100, 101, 102, 103, 104, 105):
    check('melee' in info[item], 'item %d is a melee weapon' % item)
check('melee' not in info.get(106, set()) and 'melee' not in info.get(107, set()), 'throwing star and bow are no melee weapons')

converted, _ = A.convert_file(WEAPONS, 'weapons', info)
weapons, count = A.patch_weapons(converted, info)
for item in (100, 101, 102, 103, 104, 105):
    got = names_of(weapons, item, 'melee')
    for line in LINES.values():
        check(set(line) <= set(got), 'item %d: %s in %s' % (item, line, got))
    check(('Berserker' in got) == (item in (101, 103, 105)), 'item %d: the Berserker only with two hands (%s)' % (item, got))
star = names_of(weapons, 106, 'distance')
check(set(A.LINE) <= set(star) and not set(A.MONK_LINE) & set(star) and not set(A.TEMPLAR_LINE) & set(star),
      'a throwing star: the Thief line only (%s)' % star)
bow = names_of(weapons, 107, 'distance')
check(not (set(A.LINE) | set(A.MONK_LINE) | set(A.TEMPLAR_LINE)) & set(bow), 'a bow: none of the melee lines (%s)' % bow)
again, count2 = A.patch_weapons(weapons, info)
check(again == weapons and not any(count2.values()), 'weapons: a second run changes nothing')

moves, _ = A.convert_file(MOVEMENTS, 'movements', info)
moves, count = A.patch_movements(moves, info)
for item in (100, 101, 102, 103, 104, 105):
    got = names_of(moves, item, 'movevent')
    for line in LINES.values():
        check(set(line) <= set(got), 'equip event %d: %s in %s' % (item, line, got))
again, count2 = A.patch_movements(moves, info)
check(again == moves and not any(count2.values()), 'movements: a second run changes nothing')

# an old install: the Thief line named already (a one-handed sword), the others not
old = A.convert_file(weapon('melee', 100), 'weapons', info)[0].replace(
    '</melee>', '\t<vocation name="Thief" />\n\t<vocation name="Ninja" showInDescription="0" />\n\t'
    '<vocation name="Samurai" showInDescription="0" />\n</melee>')
new, _ = A.patch_weapons(old, info)
got = names_of(new, 100, 'melee')
check(set(A.MONK_LINE) <= set(got) and set(A.TEMPLAR_LINE) <= set(got), 'an old install gets the Monk and Templar lines')
check(got.count('Thief') == 1, 'and keeps one Thief entry (%s)' % got)

if fails:
    for f in fails:
        print('FAIL ' + f)
    sys.exit(1)
print('add_vocations_melee_test: OK')
