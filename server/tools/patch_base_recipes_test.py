#!/usr/bin/env python3
"""Test of patch_base_recipes.py (run: python3 -I server/tools/patch_base_recipes_test.py) on a small data folder: the
Seraphic and Dawnforged recipes take their own charged stone and emblem (Myst recipes, belts and gloves untouched, CRLF
kept), the jewelsmith's Myst amulet and ring make the amulet and ring, the boss material recipes appended to the
general crafting book (the book still loads in LuaJIT and Lua 5.3 when they are installed), the materials' item
descriptions, a second run and --check, the economy of the added recipes against the price table (no gold loop, no
craft floor that moves a price), the committed snapshot base_recipes.csv and the install_all.py step."""
import csv
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import patch_base_recipes as P  # noqa: E402

failed = 0


def check(cond, label):
    global failed
    if not cond:
        failed += 1
        print('FAIL: ' + label)


def recipe(pid, name, mats, level=35, cost=60000):
    lines = ['    {', '        id = %d,' % pid, '        name = "%s",' % name, '        level = %d,' % level,
             '        cost = %d,' % cost, '        count = 1,', '        storage = 0,', '        storageText = "",',
             '        materials = {']
    lines += ['            {id = %d, count = %d},' % m for m in mats]
    lines += ['        }', '    },']
    return lines


MYST = [(29902, 20), (29901, 3), (29920, 1), (29921, 15), (29924, 2), (29895, 2)]


def book(name, recipes):
    lines = ['Crafting.%s = {' % name]
    for r in recipes:
        lines += recipe(*r)
    lines += ['}', '']
    return '\r\n'.join(lines)


ARMOR = book('armorsmith', [(29861, 'Myst Regalia Helmet', MYST), (29915, 'Seraphic Belt', MYST),
                            (29869, 'Seraphic Helmet', MYST), (29878, 'Dawnforged Helmet', MYST)])
WEAPON = book('weaponsmith', [(29865, 'Myst Regalia Spellbook', MYST), (29873, 'Seraphic Quiver', MYST),
                              (29888, 'Dawnforged Skull Crusherr', MYST)])
JEWEL = book('jewelsmith', [(2207, 'Sword Ring', [(26595, 1), (26729, 1)], 10, 100),
                            (29865, 'Myst Regalia Amulet', MYST), (29866, 'Myst Regalia Ring', MYST),
                            (29876, 'Seraphic Necklace', MYST), (29890, 'Dawnforged Ring', MYST)])
GENERAL = book('generalcrafting', [(28120, 'Some Cloth', [(26795, 2), (5944, 10)], 10, 1200)])
ITEMS = '''<items>
\t<item id="29900" article="a" name="Runic Stone Shard">
\t\t<attribute key="weight" value="350" />
\t</item>
\t<item id="29922" article="a" name="Seraphic Charged Stone">
\t\t<attribute key="description" value="It hums." />
\t\t<attribute key="weight" value="150" />
\t</item>
\t<item id="29923" article="a" name="Dawnforged Charged Stone">
\t\t<attribute key="weight" value="150" />
\t</item>
\t<item id="2160" article="a" name="crystal coin">
\t\t<attribute key="weight" value="10" />
\t</item>
</items>
'''


def mats_of(text, pid, name=None):
    """the materials {id: count} of the first recipe of `pid` (and `name`) in a book's text"""
    for m in P.RECIPE.finditer(text):
        n = P.NAME.search(m.group(2))
        if int(m.group(1)) == pid and (name is None or (n and n.group(1) == name)):
            return {int(a): int(b) for a, b in re.findall(r'id\s*=\s*(\d+)\s*,\s*count\s*=\s*(\d+)', m.group(3))}
    return None


def lua_runs(path, code):
    """True/False when an interpreter ran (and every one passed), None when none is installed"""
    ran = None
    for exe in ('luajit', 'lua5.3'):
        if not shutil.which(exe):
            continue
        r = subprocess.run([exe, '-e', 'Crafting = {} dofile(%r) %s' % (path, code)], stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, universal_newlines=True)
        ok = r.returncode == 0 and r.stdout.strip() == 'ok'
        if not ok:
            print('  %s: %s' % (exe, r.stdout.strip()))
        ran = ok if ran is None else (ran and ok)
    return ran


tmp = tempfile.mkdtemp()
try:
    data = os.path.join(tmp, 'data')
    books = os.path.join(data, P.BOOKS)
    os.makedirs(books)
    os.makedirs(os.path.join(data, 'items'))
    for name, text in (('armorsmith', ARMOR), ('weaponsmith', WEAPON), ('jewelsmith', JEWEL),
                       ('generalcrafting', GENERAL)):
        with open(os.path.join(books, name + '.lua'), 'w', newline='') as f:
            f.write(text)
    with open(os.path.join(data, P.ITEMS), 'w', newline='') as f:
        f.write(ITEMS)

    report, changed = P.run(data)
    check(changed == 5, 'five files change (four books, items.xml): %d' % changed)

    def read(name):
        with open(os.path.join(books, name + '.lua'), newline='') as f:
            return f.read()

    armor, weapon, jewel, general = read('armorsmith'), read('weaponsmith'), read('jewelsmith'), read('generalcrafting')
    for text, name in ((armor, 'armorsmith'), (weapon, 'weaponsmith'), (jewel, 'jewelsmith')):
        check('\n' not in text.replace('\r\n', ''), '%s keeps its CRLF line ends' % name)
    sera = mats_of(armor, 29869)
    check(sera and sera.get(29922) == 15 and sera.get(29925) == 2 and 29921 not in sera and 29924 not in sera,
          'Seraphic Helmet: the Seraphic stone and emblem, same counts: %s' % sera)
    check(sera and sera.get(29920) == 1 and sera.get(29902) == 20, 'Seraphic Helmet: the other materials stay')
    dawn = mats_of(armor, 29878)
    check(dawn and dawn.get(29923) == 15 and dawn.get(29926) == 2, 'Dawnforged Helmet: the Dawnforged ones: %s' % dawn)
    check(mats_of(armor, 29861) == dict(MYST), 'Myst Regalia Helmet untouched')
    check(mats_of(armor, 29915) == dict(MYST), 'the retired Seraphic Belt untouched (patch_badges.py retires it)')
    check(mats_of(weapon, 29865) == dict(MYST), 'the Myst spellbook of the weaponsmith untouched')
    check(mats_of(weapon, 29873).get(29922) == 15, 'weaponsmith: the Seraphic Quiver takes Seraphic stones')
    check(mats_of(weapon, 29888).get(29926) == 2, 'weaponsmith: the Dawnforged Skull Crusher takes Dawnforged emblems')
    check(mats_of(jewel, 29867, 'Myst Regalia Amulet') == dict(MYST), 'jewelsmith: the Myst amulet recipe makes 29867')
    check(mats_of(jewel, 29868, 'Myst Regalia Ring') == dict(MYST), 'jewelsmith: the Myst ring recipe makes 29868')
    check(mats_of(jewel, 29865) is None and mats_of(jewel, 29866) is None, 'jewelsmith: no spellbook or wand any more')
    check(mats_of(jewel, 29876).get(29922) == 15 and mats_of(jewel, 29890).get(29926) == 2,
          'jewelsmith: the Seraphic necklace and the Dawnforged ring')
    check(mats_of(jewel, 2207) == {26595: 1, 26729: 1}, 'jewelsmith: other recipes untouched')

    check(general.startswith(GENERAL), 'generalcrafting: the stock book stays as it was, the block is appended')
    check(general.count(P.CRAFT_MARK) == 1, 'generalcrafting: one marked block')
    added = [m for m in P.RECIPE.finditer(general[len(GENERAL):])]
    check(len(added) == len(P.ADDED), 'generalcrafting: every added recipe reads as a recipe: %d' % len(added))
    check('\n' not in general.replace('\r\n', ''), 'generalcrafting keeps its CRLF line ends')
    ran = lua_runs(os.path.join(books, 'generalcrafting.lua'),
                   'local l = Crafting.generalcrafting assert(#l == %d, #l) assert(l[2].id == %d) '
                   'assert(l[#l].materials[2].id == %d) print("ok")' % (1 + len(P.ADDED), P.ADDED[0][0], P.ADDED[-1][4][1][0]))
    check(ran is not False, 'generalcrafting.lua loads and holds the stock recipe and the added ones')

    with open(os.path.join(data, P.ITEMS), newline='') as f:
        xml = f.read()
    check('<attribute key="description" value="%s" />' % P.DESCRIPTIONS[29900] in xml, 'items.xml: a description added')
    check('value="It hums. %s"' % P.DESCRIPTIONS[29922] in xml, 'items.xml: an existing description extended')
    check(xml.count('description') == 3, 'items.xml: no other item touched')

    again, n = P.run(data)
    check(n == 0, 'a second run changes nothing: %s' % again)
    with open(os.path.join(books, 'generalcrafting.lua'), newline='') as f:
        check(f.read() == general, 'the second run leaves the general crafting book as it was')
    check(P.main([data, '--check']) == 0, '--check passes after the run')

    fresh = os.path.join(tmp, 'fresh')
    os.makedirs(os.path.join(fresh, P.BOOKS))
    with open(os.path.join(fresh, P.BOOKS, 'armorsmith.lua'), 'w', newline='') as f:
        f.write(ARMOR)
    check(P.main([fresh, '--check']) == 1, '--check fails on an unpatched book')
    with open(os.path.join(fresh, P.BOOKS, 'armorsmith.lua'), newline='') as f:
        check(f.read() == ARMOR, '--check writes nothing')
    check(P.main([os.path.join(tmp, 'nothing')]) == 0, 'a server without the books: skipped')
finally:
    shutil.rmtree(tmp)

# the economy of the added recipes: by the price table (gen_item_prices.py), the materials sell for at most what the
# product sells for (the craft floor leaves the price where it is) and materials + gold are worth more (no loop)
with open(os.path.join(SERVER, 'data', 'lib', 'chaos_item_prices_data.lua'), encoding='utf-8') as f:
    text = f.read()
prices = {int(a): int(b) for a, b in re.findall(r'\[(\d+)\] = (\d+)', text.split('prices = {', 1)[1].split('\n\t}', 1)[0])}
for pid, name, level, cost, mats in P.ADDED:
    value = sum(prices.get(m, 0) * n for m, n in mats)
    check(all(prices.get(m, 0) > 0 for m, _ in mats), '%s: every material has a price' % name)
    check(value <= prices.get(pid, 0), '%s: materials %d sell for at most the product %d' % (name, value, prices.get(pid, 0)))
    check(value + cost > prices.get(pid, 0), '%s: materials + gold %d above the product (no loop)' % (name, value + cost))
    check(level <= 35 and cost > 0, '%s: a level gate the set crafters reach, a gold cost' % name)
made = {(pid, m) for pid, _n, _l, _c, mats in P.ADDED for m, _ in mats}
check(not any((m, pid) in made for pid, m in made), 'no added recipe turns its product back into its material')

# the committed snapshot has the recipes as installed (gen_item_prices.py survey reads the books through patch_book)
rows = list(csv.DictReader(open(os.path.join(SERVER, 'data', 'items', 'base_recipes.csv'), encoding='utf-8')))
have = {(int(r['id']), r['book'], r['materials']) for r in rows}
for pid, name, level, cost, mats in P.ADDED:
    want = (pid, P.ADDED_BOOK, ' '.join('%dx%d' % (n, m) for m, n in mats))
    check(want in have, 'base_recipes.csv lists %s from %s' % (name, want[2]))
for r in rows:
    mats = {int(x.split('x')[1]) for x in r['materials'].split()}
    pid = int(r['id'])
    if pid in P.SERAPHIC or pid in P.DAWNFORGED:
        check(not mats & {P.MYST_STONE, P.MYST_EMBLEM}, 'base_recipes.csv: %d takes no Myst stone or emblem' % pid)

# install_all.py runs the tool
sys.argv = ['install_all.py']
import install_all as I  # noqa: E402
check('baserecipes' in I.STEPS, 'install_all.py has the baserecipes step')
check(hasattr(I, 'step_baserecipes'), 'install_all.py step_baserecipes')
check(I.STEPS.index('baserecipes') > I.STEPS.index('basecrafting'), 'baserecipes after basecrafting')

print('patch_base_recipes_test: %s' % ('ok' if not failed else '%d failed' % failed))
sys.exit(1 if failed else 0)
