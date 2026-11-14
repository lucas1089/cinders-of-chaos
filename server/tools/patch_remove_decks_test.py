#!/usr/bin/env python3
"""Tests of patch_remove_decks.py (O570): synthetic base files, idempotence, CRLF, the loot / trade / reward cuts, the warning."""
import io
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import patch_remove_decks as P  # noqa: E402

fails = [0]
n = [0]


def ok(cond, label):
    n[0] += 1
    if not cond:
        fails[0] += 1
        print('FAIL ' + label)


def put(root, rel, text):
    path = os.path.join(root, *rel.split('/'))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(text)
    return path


LUA_MON = 'monster = {\n  loot = {\n    {id = 2160, chance = 100},\n    {id = 27632, chance = 80, maxCount = 1}, -- bronze deck\n    {name = "Golden Deck", chance = 10},\n    {id = 27633, chance = 5}\n  }\n}\n'
XML_MON = '<monster name="a">\n  <loot>\n    <item id="2160" chance="1000"/>\n    <item id="27634" chance="50" countmax="1"/> <!-- golden -->\n    <item name="silver deck" chance="5"/>\n  </loot>\n</monster>\n'
XML_NPC = '<npc name="x">\n <parameters>\n  <parameter key="shop_buyable" value="rope,2120,50;bronze deck,27632,1000;torch,2050,2;golden deck,27634,30000" />\n  <parameter key="shop_sellable" value="silver deck,27633,300" />\n </parameters>\n</npc>\n'
LUA_NPC = 'shopModule:addBuyableItem({"rope"}, 2120, 50)\nshopModule:addBuyableItem({"bronze deck"}, 27632, 1000, "bronze deck")\nshopModule:addSellableItem({"golden deck"}, 27634, 100)\n'
LUA_TASK = 'local rewards = {\n  {itemid = 2160, count = 5},\n  {itemid = 27633, count = 1},\n  {id = 27632, count = 1}, -- a deck\n}\nlocal cards = {27482, 27483}\n'
LUA_LIST = 'local retired = {27632, 27633, 27634}\n'

with tempfile.TemporaryDirectory() as d:
    mon = put(d, 'monster/a.lua', LUA_MON)
    mox = put(d, 'monster/b.xml', XML_MON)
    npx = put(d, 'npc/x.xml', XML_NPC)
    npl = put(d, 'npc/scripts/y.lua', LUA_NPC)
    task = put(d, 'scripts/t.lua', LUA_TASK)
    lst = put(d, 'lib/l.lua', LUA_LIST)
    crlf = put(d, 'monster/c.lua', LUA_MON.replace('\n', '\r\n'))
    cmd = [sys.executable, '-I', os.path.join(HERE, 'patch_remove_decks.py'), d]
    dry = subprocess.run(cmd + ['--dry-run'], capture_output=True, text=True).stdout
    ok(P.read(mon) == LUA_MON, 'a dry run writes nothing')
    ok('dry run' in dry and 'loot line(s)' in dry, 'a dry run says what it would do: ' + dry)
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    m = P.read(mon)
    ok('27632' not in m and '27633' not in m and 'Golden Deck' not in m and '{id = 2160, chance = 100}' in m, 'Lua loot: the three decks are cut, gold stays')
    ok(m.count('\n') == LUA_MON.count('\n') - 3, 'Lua loot: three lines')
    x = P.read(mox)
    ok('27634' not in x and 'silver deck' not in x and 'id="2160"' in x, 'XML loot: id and name entries cut')
    s = P.read(npx)
    ok('rope,2120,50;torch,2050,2' in s and '27632' not in s and '27634' not in s, 'XML trade: the buyable entries are cut, the rest kept')
    ok('value=""' in s, 'XML trade: an emptied sellable list stays a list')
    nl = P.read(npl)
    ok('2120' in nl and '27632' not in nl and '27634' not in nl, 'Lua trade lines cut')
    t = P.read(task)
    ok('2160' in t and '27633' not in t and '27632' not in t and '27482' in t, 'reward lines cut, other rewards and the cards stay')
    ok(P.read(lst) == LUA_LIST, 'a list of ids on one line is left alone')
    ok('WARNING' in out and 'lib/l.lua' in out, 'what still names a deck is warned about: ' + out)
    c = P.read(crlf)
    ok('\r\n' in c and '27632' not in c and '\n' not in c.replace('\r\n', ''), 'CRLF is kept')
    snapshot = {p: P.read(p) for p in (mon, mox, npx, npl, task, lst, crlf)}
    out2 = subprocess.run(cmd, capture_output=True, text=True).stdout
    ok(all(P.read(p) == snapshot[p] for p in snapshot), 'a second run changes nothing')
    ok('already done' in out2, 'and says so: ' + out2)
    empty = tempfile.mkdtemp()
    out3 = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'patch_remove_decks.py'), empty], capture_output=True, text=True).stdout
    ok('already done' in out3 and 'WARNING' not in out3, 'an empty data folder is fine')

# the ids are the ones of the config
cfg = open(os.path.join(HERE, '..', 'data', 'scripts', 'chaos', 'cards_config.lua'), encoding='utf-8').read()
for i in P.DECK_IDS:
    ok('id = %d' % i in cfg, 'cards_config.lua names the deck %d' % i)
inst = open(os.path.join(HERE, 'install_all.py'), encoding='utf-8').read()
ok("'removedecks'" in inst and 'patch_remove_decks.py' in inst, 'install_all.py has the step')

print('patch_remove_decks_test: %d checks, %d failures' % (n[0], fails[0]))
sys.exit(1 if fails[0] else 0)
