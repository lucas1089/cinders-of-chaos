#!/usr/bin/env python3
"""python3 -I server/tools/install_potions_test.py : install_potions.py on a synthetic base server (items.otb with the
stock potion nodes, items.xml with a flask deposit text, a potion seller in XML and one in Lua, a weapon dealer, the
NPC library's ShopModule, the stock potions.lua): the Everfull nodes copied from the stock potions (stackable, stock
look), the items.xml block, no flask made or sold, the deposit texts gone, the Everfull potions sold by the potion
sellers only, the ShopModule hook; idempotent; a missing hook place stops it with nothing written."""
import os, shutil, struct, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_potions as T  # noqa: E402
from install_gems import scan, escape, attr, START, END, A_SERVERID, A_CLIENTID, FLAG_STACKABLE  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def item_node(sid, cid, flags=FLAG_STACKABLE):
    body = struct.pack('<I', flags) + attr(A_SERVERID, struct.pack('<H', sid)) + attr(A_CLIENTID, struct.pack('<H', cid))
    return bytes([START]) + escape(bytes([0])) + escape(body) + bytes([END])


def otb(nodes):
    root = bytes([START, 0]) + escape(struct.pack('<I', 0))
    return b'\x00\x00\x00\x00' + root + b''.join(nodes) + bytes([END])


ITEMS_XML = '''<?xml version="1.0"?>
<items>
\t<item id="7618" article="a" name="health potion" />
\t<item id="7636" article="an" name="empty potion flask">
\t\t<attribute key="description" value="Return it to a potion store for your deposit." />
\t</item>
</items>
'''
SELLER_XML = '''<npc name="Morora" script="default.lua">
\t<parameters>
\t\t<parameter key="message_greet" value="Hello |PLAYERNAME|. Potions! Bring your empty vials back for the deposit." />
\t\t<parameter key="shop_buyable" value="health potion,7618,45;mana potion,7620,50;empty potion flask,7636,20;" />
\t\t<parameter key="shop_sellable" value="empty potion flask,7636,5;" />
\t</parameters>
</npc>
'''
DEALER_XML = '''<npc name="Smith" script="default.lua">
\t<parameters>
\t\t<parameter key="shop_buyable" value="sword,2376,85;" />
\t</parameters>
</npc>
'''
SELLER_LUA = '''local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)
local shopModule = ShopModule:new()
npcHandler:addModule(shopModule)
shopModule:addBuyableItem({'health potion'}, 7618, 45, 1, 'health potion')
shopModule:addBuyableItem({'mana potion'}, 7620, 50, 1, 'mana potion')
shopModule:addBuyableItem({'flask'}, 7636, 20, 1, 'empty potion flask')
shopModule:addSellableItem({'flask'}, 7636, 5, 'empty potion flask')
keywordHandler:addKeyword({'deposit'}, StdModule.say, {npcHandler = npcHandler, text = 'We have a deposit on every potion flask.'})
local list = {{name = 'strong flask', id = 7634, buy = 25, sell = 5}}
'''
MODULES = '''\tfunction ShopModule:callbackOnBuy(cid, itemid, subType, amount, ignoreCap, inBackpacks)
\t\tlocal shopItem = self:getShopItem(itemid, subType)
\tend
'''
POTIONS = '''function onUse(player, item, fromPosition, target, toPosition, isHotkey)
\tif potion.health then
\t\tdoTargetCombat(player, target, COMBAT_HEALING, potion.health[1], potion.health[2])
\tend
\tif potion.mana then
\t\tdoTargetCombat(player, target, COMBAT_MANADRAIN, potion.mana[1], potion.mana[2])
\tend
\tplayer:addItem(potion.flask, 1)
\titem:remove(1)
\treturn true
end
'''


def make_base(root):
    data = os.path.join(root, 'data')
    for d in ('items', 'npc/scripts', 'npc/lib/npcsystem', 'actions/scripts/other', 'scripts/chaos'):
        os.makedirs(os.path.join(data, d), exist_ok=True)
    nodes = [item_node(7618, 7477), item_node(7620, 7478), item_node(7636, 7479), item_node(2376, 3264, 0)]
    open(os.path.join(data, 'items', 'items.otb'), 'wb').write(otb(nodes))
    files = {'items/items.xml': ITEMS_XML, 'npc/Morora.xml': SELLER_XML, 'npc/Smith.xml': DEALER_XML,
             'npc/scripts/potions.lua': SELLER_LUA, 'npc/lib/npcsystem/modules.lua': MODULES,
             'actions/scripts/other/potions.lua': POTIONS,
             'scripts/chaos/own.lua': 'player:addItem(potion.flask, 1)\n'}
    for rel, text in files.items():
        open(os.path.join(data, rel), 'w', newline='').write(text)
    return data


def snapshot(data):
    out = {}
    for d, _dirs, files in os.walk(data):
        for f in files:
            p = os.path.join(d, f)
            out[os.path.relpath(p, data)] = open(p, 'rb').read()
    return out


cfg = T.read_config()
check([r['id'] for r in cfg['everfull']] == [32085, 32086], 'config: the Everfull ids')
check([r['sourceId'] for r in cfg['everfull']] == [7618, 7620], 'config: the first health and mana potions')

tmp = tempfile.mkdtemp()
try:
    data = make_base(tmp)
    devnull = open(os.devnull, 'w')
    old = sys.stdout
    sys.stdout = devnull
    try:
        rc = T.main([data])
        first = snapshot(data)
        rc2 = T.main([data])
    finally:
        sys.stdout = old
    check(rc == 0 and rc2 == 0, 'runs')
    check(snapshot(data) == first, 'a second run changes nothing')

    raw = first['items/items.otb']
    kids, _ = scan(raw)
    by = {k[2]: k for k in kids}
    check(32085 in by and by[32085][3] == 7477, 'everfull health potion: the stock look')
    check(32086 in by and by[32086][3] == 7478, 'everfull mana potion: the stock look')
    check(bool(by[32085][5] & FLAG_STACKABLE), 'stackable like the stock node (the client reads a count)')
    check(os.path.exists(os.path.join(data, 'items', 'items.otb.bak')), 'items.otb.bak kept')

    xml = first['items/items.xml'].decode()
    check(xml.count(T.XML_BEGIN) == 1 and 'name="everfull health potion"' in xml, 'items.xml block')
    check('value="Never runs out.' in xml, 'the description')
    check('deposit' not in xml.lower(), 'no flask deposit text in items.xml')
    check(cfg['flaskText'] in xml, 'the flask text')

    morora = first['npc/Morora.xml'].decode()
    check('everfull health potion,32085,100;everfull mana potion,32086,100;' in morora, 'the XML seller sells both')
    check('empty potion flask,7636,20' not in morora, 'no flask for sale')
    check('shop_sellable" value="empty potion flask,7636,5;' in morora, 'old flasks still bought')
    check('deposit' not in morora.lower() and 'Hello |PLAYERNAME|. Potions!' in morora, 'the greeting loses its deposit')
    check('everfull' not in first['npc/Smith.xml'].decode(), 'a weapon dealer sells no Everfull potion')

    lua = first['npc/scripts/potions.lua'].decode()
    check("shopModule:addBuyableItem({'everfull health potion'}, 32085, 100, 1, 'everfull health potion')" in lua,
          'the Lua seller sells the health one')
    check("32086, 100, 1, 'everfull mana potion')" in lua, 'and the mana one')
    check(lua.index('32086') > lua.index("7620, 50"), 'after its mana potion line')
    check('-- ' + T.FLASK_MARK + "shopModule:addBuyableItem({'flask'}, 7636" in lua, 'no flask for sale (Lua)')
    check("shopModule:addSellableItem({'flask'}, 7636, 5" in lua, 'old flasks still bought (Lua)')
    check("{name = 'strong flask', id = 7634, sell = 5}" in lua, 'a table row loses its buy price')
    check('deposit on' not in lua and cfg['flaskText'] in lua, 'the deposit keyword reply replaced')

    mod = first['npc/lib/npcsystem/modules.lua'].decode()
    check(T.HOOK_MARK in mod and 'return ChaosPotions.npcBuy(cid, itemid)' in mod, 'ShopModule hook')
    check(mod.index(T.HOOK_MARK) < mod.index('getShopItem'), 'before the stock purchase')

    pot = first['actions/scripts/other/potions.lua'].decode()
    check('-- ' + T.FLASK_MARK + 'player:addItem(potion.flask, 1)' in pot, 'the stock potions.lua makes no flask')
    check('\titem:remove(1)' in pot, 'potions are still used up')
    check(pot.startswith('if ChaosPotions == nil') and pot.count('ChaosPotions.amount(player, target, "health"') == 1
          and pot.count('ChaosPotions.amount(player, target, "mana"') == 1 and 'potion.health[1], potion.health[2])' not in
          pot.replace('math.random(potion.health[1], potion.health[2])', ''), 'the potion rolls: fixed + percent of the maximum')
    check(first['scripts/chaos/own.lua'] == b'player:addItem(potion.flask, 1)\n', 'the Chaos folders are not touched')

    # no ShopModule:callbackOnBuy: an error, nothing written
    shutil.rmtree(tmp)
    tmp = tempfile.mkdtemp()
    data = make_base(tmp)
    open(os.path.join(data, 'npc', 'lib', 'npcsystem', 'modules.lua'), 'w').write('-- nothing here\n')
    before = snapshot(data)
    sys.stdout = devnull
    try:
        rc = T.main([data])
    finally:
        sys.stdout = old
    check(rc == 1, 'no hook place: exit 1')
    check(snapshot(data) == before, 'and nothing written')
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print('install_potions_test: %s' % ('ok' if not failed else '%d failure(s)' % failed))
sys.exit(1 if failed else 0)
