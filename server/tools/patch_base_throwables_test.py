#!/usr/bin/env python3
"""patch_base_throwables.py on a small base data folder: the stackable throwing weapons leave monster loot (XML and Lua),
NPC shops (XML and script) and script rewards; arrows, daggers and other items stay; a second run changes nothing; the
list comes from data/lib/chaos_throwables.lua; install_all.py has the step after archery.
usage: python3 -I server/tools/patch_base_throwables_test.py"""
import os, shutil, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import patch_base_throwables as P  # noqa: E402
import install_all as I  # noqa: E402

failures = 0


def check(cond, label):
    global failures
    if not cond:
        failures += 1
        print('FAIL ' + label)


ids = P.read_ids()
check(ids == [1294, 2389, 2399, 2410, 3965, 7366, 7367, 7368, 7378], 'ids from chaos_throwables.lua: %s' % ids)

MONSTER = ('<?xml version="1.0"?>\n<monster name="Goblin" nameDescription="a goblin">\n\t<loot>\n'
           '\t\t<item id="2148" countmax="9" chance="50000" />\n'
           '\t\t<item id="2389" chance="4000" /><!-- spear -->\n'
           '\t\t<item id="2399" countmax="5" chance="2000" />\n'
           '\t\t<item name="royal spear" chance="100" />\n'
           '\t\t<item id="2379" chance="3000" />\n'
           '\t</loot>\n</monster>\n')
MONSTER_LUA = ('monster.loot = {\n\t{id = 2148, chance = 50000, maxCount = 9},\n\t{id = 7368, chance = 500, maxCount = 4},\n'
               '\t{name = "enchanted spear", chance = 100},\n\t{id = 2379, chance = 3000},\n}\n')
NPC_XML = ('<npc name="Trader"><parameters>\n'
           '<parameter key="shop_buyable" value="spear,2389,9;dagger,2379,5;throwing star,2399,12;" />\n'
           '<parameter key="shop_sellable" value="spear,2389,3;dagger,2379,2;" />\n'
           '</parameters></npc>\n')
NPC_LUA = ("shopModule:addBuyableItem({'spear'}, 2389, 9, 'spear')\n"
           "shopModule:addBuyableItem({'dagger'}, 2379, 5, 'dagger')\n"
           "local rewards = {\n\t{2389, 5},\n\t{2379, 1},\n}\n")
QUEST = "player:addItem(7378, 3)\nplayer:addItem(2379, 1)\n"
ARROW = '<monster name="Archer">\n<loot>\n\t<item id="2544" chance="1000" />\n\t<item id="2399" chance="10" />\n</loot>\n</monster>\n'

root = tempfile.mkdtemp()
try:
    data = os.path.join(root, 'data')
    files = {
        'monster/monsters/goblin.xml': MONSTER, 'monster/lua/boss.lua': MONSTER_LUA, 'npc/trader.xml': NPC_XML,
        'npc/scripts/trader.lua': NPC_LUA, 'actions/scripts/quest.lua': QUEST, 'monster/monsters/archer.xml': ARROW,
        'monster/monsters/chaos/own.xml': MONSTER,  # Chaos monsters are not touched (they are written without them)
    }
    for rel, text in files.items():
        path = os.path.join(data, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        open(path, 'w', encoding='utf-8', newline='').write(text)

    def rd(rel):
        return open(os.path.join(data, rel), encoding='utf-8', newline='').read()

    def run(*extra):
        return P.main([data] + list(extra))

    check(run('--dry-run') == 0, 'dry run answers 0')
    check(rd('monster/monsters/goblin.xml') == MONSTER, 'dry run writes nothing')
    check(run() == 0, 'run answers 0')

    g = rd('monster/monsters/goblin.xml')
    check('2389' not in g and '2399' not in g and 'royal spear' not in g, 'goblin: spear, star and royal spear gone')
    check('id="2148"' in g and 'id="2379"' in g, 'goblin: gold and dagger stay')
    b = rd('monster/lua/boss.lua')
    check('7368' not in b and 'enchanted spear' not in b and 'id = 2148' in b and 'id = 2379' in b, 'lua loot')
    x = rd('npc/trader.xml')
    check('2389' not in x and '2399' not in x and 'dagger,2379,5' in x and 'dagger,2379,2' in x, 'xml shop: only the dagger')
    s = rd('npc/scripts/trader.lua')
    first = s.split('\n')[0]
    check(first.startswith(P.MARK) and 'addBuyableItem({\'dagger\'}' in s.split('\n')[1], 'script shop line commented, dagger stays')
    check('{2389, 5}' not in s and '{2379, 1}' in s, 'script reward entry gone')
    q = rd('actions/scripts/quest.lua')
    check('7378' not in q and 'addItem(2148,' in q and 'addItem(2379, 1)' in q, 'quest: gold coins instead: ' + q)
    a = rd('monster/monsters/archer.xml')
    check('2544' in a and '2399' not in a, 'archer: arrows are the archery patch\'s business, the star is gone')
    check(rd('monster/monsters/chaos/own.xml') == MONSTER, 'monsters/chaos untouched')

    before = {rel: rd(rel) for rel in files}
    check(run() == 0, 'second run answers 0')
    check(all(rd(rel) == before[rel] for rel in files), 'second run changes nothing')
finally:
    shutil.rmtree(root, ignore_errors=True)

check('throwables' in I.STEPS and I.STEPS.index('throwables') == I.STEPS.index('archery') + 1, 'install step after archery')
check(callable(getattr(I, 'step_throwables', None)), 'step_throwables exists')

if failures:
    sys.exit(1)
print('patch_base_throwables_test: OK')
