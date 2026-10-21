#!/usr/bin/env python3
"""Test of patch_badges.py (run: python3 -I server/tools/patch_badges_test.py) on a small data folder: boss loot by
name and by id (Lua and XML), a roulette prize pool, task rewards, the catalyst action and Player:onMoveItem hooks
(CRLF kept), items.xml descriptions (replaced or added), a second run that changes nothing, --check, and the ids
against data/scripts/chaos/badges_core.lua."""
import os
import re
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import patch_badges as P  # noqa: E402

ITEMS = '''<items>
	<item id="27811" article="a" name="Raging Moon Badge">
		<attribute key="weight" value="350" />
		<attribute key="slotType" value="deckbadge" />
	</item>
	<item id="27808" article="a" name="Furious Fury Badge">
		<attribute key="weight" value="500" />
		<attribute key="description" value="Life +50" />
	</item>
	<item id="27849" article="a" name="Moon Amplifier Catalyst [1]">
		<attribute key="weight" value="200"/>
		<attribute key="description" value="Use this Amplifier on Moon Badge to upgrade it to the next tier."/>
	</item>
	<item id="27850" article="a" name="Moon Amplifier Catalyst [2]"/>
	<item id="2160" article="a" name="crystal coin">
		<attribute key="description" value="Keep me." />
	</item>
</items>
'''
BOSS = '''local monster = {}
monster.loot = {
	{id = "rare essence", chance = 50000, maxCount = 5},
	{id = "raging moon badge", chance = 3500},
	{id = "Moon Amplifier Catalyst [1]", chance = 8000, maxCount = 2},
	{id = 27850, chance = 6200},
	{name = "furious fury badge", chance = 100},
	{id = "golden deck", chance = 10000},
	{id = 29623, chance = 20000} --- the last line
}
'''
BOSS_OUT = '''local monster = {}
monster.loot = {
	{id = "rare essence", chance = 50000, maxCount = 5},
	{id = "golden deck", chance = 10000},
	{id = 29623, chance = 20000} --- the last line
}
'''
XML_MONSTER = '''<monster name="X">
	<loot>
		<item id="2148" chance="100000" countmax="5"/>
		<item name="raging moon badge" chance="3500"/>
		<item id="27873" chance="10"/><!-- daybreak [4] -->
	</loot>
</monster>
'''
ROULETTE = '''local config = {
    prizePool = {
        {itemId = 27633, count = {1, 1},    chance = 7000},
        {itemId = 27822, count = {1, 1},    chance = 6800 },
        {itemId = 27839, count = {1, 1},    chance = 2500  },
        {itemId = 27547, count = {1, 1},    chance = 800  },
    },
}
'''
TASKS = '''Rewards = {
          {Type = RewardType.Gold, BaseValue = 180000},
          {Type = RewardType.Item, Id = 27803, Amount = 1},
          {Type = RewardType.Item, Id = 27843, Amount = 1},
          {Type = RewardType.Item, Id = 27699, Amount = 2},
        }
'''
ACTION = '''local config = { gear = { [27849] = {tier = 2, upgraderType = 'amplifier', chance = 35} } }
function action.onUse(player, item, fromPosition, target, toPosition, isHotkey)
    local pos = target:getPosition()
    item:remove(1)
    return true
end
'''
PLAYER = ('function Player:onBrowseField(position)\r\n\treturn true\r\nend\r\n\r\n'
          'function Player:onMoveItem(item, count, fromPosition, toPosition, fromCylinder, toCylinder)\r\n'
          '\treturn RETURNVALUE_NOERROR\r\nend\r\n')
CHAOS = '{itemId = 27811, count = 1}\n'  # data/scripts/chaos is ours: never touched


def put(root, rel, text):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(text)
    return path


def get(path):
    with open(path, encoding='utf-8', newline='') as f:
        return f.read()


d = tempfile.mkdtemp()
try:
    put(d, 'items/items.xml', ITEMS)
    boss = put(d, 'monster/lua/bosses/boss.lua', BOSS)
    xmlm = put(d, 'monster/monsters/x.xml', XML_MONSTER)
    roul = put(d, 'scripts/customs/roulette/roulette.lua', ROULETTE)
    tasks = put(d, 'scripts/customs/tasks/tasks.lua', TASKS)
    act = put(d, 'scripts/customs/badges/badges_upgrade.lua', ACTION)
    player = put(d, 'events/scripts/player.lua', PLAYER)
    ours = put(d, 'scripts/chaos/x.lua', CHAOS)

    assert P.main([d, '--check']) == 1, 'work to do'
    assert get(boss) == BOSS, '--check writes nothing'
    assert P.main([d]) == 0

    assert get(boss) == BOSS_OUT, get(boss)
    out = get(xmlm)
    assert '2148' in out and 'raging moon badge' not in out and '27873' not in out, out
    out = get(roul)
    assert '27633' in out and '27547' in out and '27822' not in out and '27839' not in out, out
    out = get(tasks)
    assert 'RewardType.Gold' in out and '27699' in out and '27803' not in out and '27843' not in out, out
    out = get(act)
    assert out.count(P.MARK) == 1 and out.index(P.MARK) < out.index('local pos'), out
    assert 'ChaosBadges.onCatalystUse(player, item, target)' in out
    out = get(player)
    assert out.count(P.MARK) == 1 and '\n' not in out.replace('\r\n', ''), 'hook added, CRLF kept'
    assert out.index('function Player:onMoveItem') < out.index(P.MARK) < out.index('return RETURNVALUE_NOERROR')
    assert get(ours) == CHAOS, 'the Chaos scripts are ours'
    out = get(os.path.join(d, 'items', 'items.xml'))
    descs = {}
    for iid, body in re.findall(r'<item id="(\d+)"[^>]*[^/]>(.*?)</item>', out, re.S):
        m = re.search(r'description" value="([^"]*)"', body)
        descs[iid] = m and m.group(1)
    assert descs['27811'] == P.BADGE_DESC and descs['27808'] == P.BADGE_DESC, descs
    assert descs['27849'] == P.CATALYST_DESC, descs
    assert descs['2160'] == 'Keep me.', descs
    assert 'Life +50' not in out and '<item id="27850" article="a" name="Moon Amplifier Catalyst [2]"/>' in out

    snap = {p: get(p) for p in (boss, xmlm, roul, tasks, act, player)}
    assert P.main([d, '--check']) == 0, 'nothing left'
    assert P.main([d]) == 0
    assert all(get(p) == t for p, t in snap.items()), 'a second run changes nothing'
finally:
    shutil.rmtree(d)

# the ids match the Lua rules
core = open(os.path.join(os.path.dirname(HERE), 'data', 'scripts', 'chaos', 'badges_core.lua'), encoding='utf-8').read()
first_b, last_b = map(int, re.search(r'K\.FIRST_BADGE, K\.LAST_BADGE = (\d+), (\d+)', core).groups())
first_c, last_c = map(int, re.search(r'K\.FIRST_CATALYST, K\.LAST_CATALYST = (\d+), (\d+)', core).groups())
assert (P.BADGES.start, P.BADGES.stop - 1, P.CATALYSTS.start, P.CATALYSTS.stop - 1) == (first_b, last_b, first_c, last_c)
assert len(P.IDS) == 71
for text in (P.BADGE_DESC, P.CATALYST_DESC):
    assert '—' not in text and '"' not in text and '<' not in text and len(text) < 150
print('patch_badges_test: ok')
