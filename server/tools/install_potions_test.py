#!/usr/bin/env python3
"""python3 -I server/tools/install_potions_test.py : install_potions.py on a synthetic base server (items.otb with the
stock potion nodes, items.xml with a flask deposit text, a potion seller in XML and one in Lua, a weapon dealer, the
NPC library's ShopModule, the stock potions.lua): the Everfull nodes copied from the stock potions (stackable, stock
look), the items.xml block, no flask made or sold, the deposit texts gone, NO Everfull potion sold by anybody (O273: a
server installed before it gets the shop entries and the ShopModule hook taken out again); idempotent."""
import os, shutil, struct, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_potions as T  # noqa: E402
from install_gems import scan, escape, attr, START, END, A_SERVERID, A_CLIENTID, FLAG_STACKABLE  # noqa: E402

FLAG_ANIMATION = 1 << 24

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
    # the stock great / ultimate / supreme potions the higher Everfull tiers copy (O245)
    # (the ultimate ones are animated in the stock data: the Everfull copies must lose that, their art has one phase)
    nodes += [item_node(sid, 8000 + i, FLAG_STACKABLE | (FLAG_ANIMATION if sid >= 8473 else 0))
              for i, sid in enumerate((7590, 7591, 8472, 8473, 26029, 26030, 26031))]
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
check([r['id'] for r in cfg['everfull']] == [32085, 32086] + list(range(32261, 32271)), 'config: the Everfull ids')
check([r['sourceId'] for r in cfg['everfull']][:2] == [7618, 7620], 'config: the first health and mana potions')
check([r['sourceId'] for r in cfg['everfull']][2:] == [7591, 7590, 8472, 8473, 26029, 26030, 26031, 8472, 26029, 26030],
      'config: the great, ultimate and supreme potions, then the nodes the three new ones copy')
check([r['tier'] for r in cfg['everfull']] == [1, 1, 2, 2, 2, 3, 3, 3, 4, 1, 4, 4], 'config: tiers')
check([r['upgrade'] for r in cfg['everfull']] == [False, False] + [True] * 10, 'config: ten are made from another (spirit tier 1 too)')
check([r['clientId'] for r in cfg['everfull']] == [38645, 38649, 38646, 38650, 38654, 38647, 38651, 38655, 38648, 38653, 38652, 38656],
      'config: the client ids of pair 44')

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
    check(32085 in by and by[32085][3] == 38645, 'everfull health potion: its own look (client 38645)')
    check(32086 in by and by[32086][3] == 38649, 'everfull mana potion: its own look (client 38649)')
    check(bool(by[32085][5] & FLAG_STACKABLE), 'stackable like the stock node (the client reads a count)')
    for r in cfg['everfull']:
        check(r['id'] in by and by[r['id']][3] == r['clientId'], '%s: client id %d' % (r['name'], r['clientId']))
        check(bool(by[r['id']][5] & FLAG_STACKABLE), '%s: stackable' % r['name'])
        check(not by[r['id']][5] & FLAG_ANIMATION, '%s: no animation flag (one phase)' % r['name'])
    check(len({by[r['id']][3] for r in cfg['everfull']}) == 12, 'twelve client ids')
    check(bool(by[8473][5] & FLAG_ANIMATION), 'the stock nodes themselves are not touched')
    check(os.path.exists(os.path.join(data, 'items', 'items.otb.bak')), 'items.otb.bak kept')

    xml = first['items/items.xml'].decode()
    check(xml.count(T.XML_BEGIN) == 1 and 'name="everfull health potion"' in xml, 'items.xml block')
    check('value="A flask that never empties. Heals like a health potion. Cannot be traded or sold."' in xml, 'the description')
    check('name="everfull supreme health potion"' in xml and 'Heals like a supreme health potion (level 200)' in xml,
          'items.xml: the supreme tier, its name and description')
    check('A flask that never empties. Restores mana like a supreme mana potion (level 200). Cannot be traded or sold.' in xml,
          'items.xml: the supreme mana potion, the owner\'s example text')
    check('Heals and restores mana like an ultimate spirit potion (level 130). Cannot be traded or sold.' in xml,
          'items.xml: the spirit description')
    check('charge' not in xml.lower() and 'refill' not in xml.lower(), 'items.xml: nothing about charges or refills')
    check(xml.count('<item id="32') == 12, 'items.xml: twelve Everfull entries')
    check('name="everfull supreme mana potion"' in xml and 'name="everfull spirit potion"' in xml
          and 'name="everfull supreme spirit potion"' in xml, 'items.xml: the three new potions')
    check('deposit' not in xml.lower(), 'no flask deposit text in items.xml')
    check(cfg['flaskText'] in xml, 'the flask text')

    morora = first['npc/Morora.xml'].decode()
    check('everfull' not in morora and '3208' not in morora and '3226' not in morora, 'the XML seller sells no Everfull potion')
    check('health potion,7618,45;mana potion,7620,50;' in morora, 'its stock potions stay')
    check('empty potion flask,7636,20' not in morora, 'no flask for sale')
    check('shop_sellable" value="empty potion flask,7636,5;' in morora, 'old flasks still bought')
    check('deposit' not in morora.lower() and 'Hello |PLAYERNAME|. Potions!' in morora, 'the greeting loses its deposit')
    check('everfull' not in first['npc/Smith.xml'].decode(), 'a weapon dealer sells no Everfull potion')

    lua = first['npc/scripts/potions.lua'].decode()
    check('32085' not in lua and '32086' not in lua and 'everfull' not in lua and '3226' not in lua,
          'the Lua seller sells no Everfull potion')
    check("shopModule:addBuyableItem({'health potion'}, 7618, 45, 1, 'health potion')" in lua, 'its stock potions stay')
    check('-- ' + T.FLASK_MARK + "shopModule:addBuyableItem({'flask'}, 7636" in lua, 'no flask for sale (Lua)')
    check("shopModule:addSellableItem({'flask'}, 7636, 5" in lua, 'old flasks still bought (Lua)')
    check("{name = 'strong flask', id = 7634, sell = 5}" in lua, 'a table row loses its buy price')
    check('deposit on' not in lua and cfg['flaskText'] in lua, 'the deposit keyword reply replaced')

    check(first['npc/lib/npcsystem/modules.lua'].decode() == MODULES, 'no ShopModule hook is written any more: modules.lua untouched')

    pot = first['actions/scripts/other/potions.lua'].decode()
    check('-- ' + T.FLASK_MARK + 'player:addItem(potion.flask, 1)' in pot, 'the stock potions.lua makes no flask')
    check('\titem:remove(1)' in pot, 'potions are still used up')
    check(pot.startswith('if ChaosPotions == nil') and pot.count('ChaosPotions.amount(player, target, "health"') == 1
          and pot.count('ChaosPotions.amount(player, target, "mana"') == 1 and 'potion.health[1], potion.health[2])' not in
          pot.replace('math.random(potion.health[1], potion.health[2])', ''), 'the potion rolls: fixed + percent of the maximum')
    check(first['scripts/chaos/own.lua'] == b'player:addItem(potion.flask, 1)\n', 'the Chaos folders are not touched')

    # a server installed before the looks (nodes with the stock look, the ultimate ones animated): the step moves them
    shutil.rmtree(tmp)
    tmp = tempfile.mkdtemp()
    data = make_base(tmp)
    path = os.path.join(data, 'items', 'items.otb')
    kids0, root_end0 = scan(open(path, 'rb').read())
    raw0 = open(path, 'rb').read()
    stock_look = {7618: 7477, 7620: 7478}
    stock_look.update({sid: 8000 + i for i, sid in enumerate((7590, 7591, 8472, 8473, 26029, 26030, 26031))})
    olds = b''.join(item_node(r['id'], stock_look[r['sourceId']], FLAG_STACKABLE | (FLAG_ANIMATION if r['sourceId'] >= 8473 else 0))
                    for r in cfg['everfull'][:9])
    open(path, 'wb').write(raw0[:root_end0] + olds + raw0[root_end0:])
    sys.stdout = devnull
    try:
        rc = T.main([data])
        once = snapshot(data)
        rc2 = T.main([data])
    finally:
        sys.stdout = old
    check(rc == 0 and rc2 == 0, 'an installed server: runs twice')
    check(snapshot(data) == once, 'an installed server: the second run changes nothing')
    kids2, _ = scan(once['items/items.otb'])
    by2 = {k[2]: k for k in kids2}
    check(all(by2[r['id']][3] == r['clientId'] for r in cfg['everfull']),
          'an installed server: the nine old nodes moved to their new look, the three new ones added')
    check(all(not by2[r['id']][5] & FLAG_ANIMATION for r in cfg['everfull']), 'an installed server: no animation flag left')
    check(len(kids2) == len(kids0) + 12, 'an installed server: no node twice')

    # a server id that belongs to a client id that is neither the stock look nor the new one, and a client id another item has
    for label, nodes_extra in (('a foreign client id', [item_node(32085, 5555)]), ('a taken client id', [item_node(9999, 38645)])):
        shutil.rmtree(tmp)
        tmp = tempfile.mkdtemp()
        data = make_base(tmp)
        path = os.path.join(data, 'items', 'items.otb')
        raw0 = open(path, 'rb').read()
        _k, end0 = scan(raw0)
        open(path, 'wb').write(raw0[:end0] + b''.join(nodes_extra) + raw0[end0:])
        before = snapshot(data)
        sys.stdout = devnull
        try:
            try:
                rc = T.main([data])
            except SystemExit as e:
                rc = 1 if e.code else 0
        finally:
            sys.stdout = old
        check(rc == 1 and snapshot(data) == before, label + ': stops, nothing written')

    # a server installed BEFORE O273: the Everfull potions sold by the potion sellers (XML entries, marked Lua lines), a hand-made
    # Lua sale, a table row with a buy price, the ShopModule hook, the old charge descriptions in items.xml
    shutil.rmtree(tmp)
    tmp = tempfile.mkdtemp()
    data = make_base(tmp)
    OLD_HOOK = (T.HOOK_MARK + ': one store-bound copy (data/lib/chaos_potions.lua)\n'
                '\t\tif ChaosPotions == nil then pcall(dofile, "data/lib/chaos_potions.lua") end\n'
                '\t\tif ChaosPotions and ChaosPotions.everfull and ChaosPotions.everfull(itemid) then\n'
                '\t\t\treturn ChaosPotions.npcBuy(cid, itemid)\n'
                '\t\tend\n')
    legacy = {
        'npc/Morora.xml': SELLER_XML.replace('mana potion,7620,50;', 'mana potion,7620,50;everfull health potion,32085,100;'
                                             'everfull mana potion,32086,100;'),
        'npc/lib/npcsystem/modules.lua': MODULES.replace('\t\tlocal shopItem', '\t\t' + OLD_HOOK + '\t\tlocal shopItem'),
        'npc/scripts/potions.lua': SELLER_LUA.replace(
            "shopModule:addBuyableItem({'mana potion'}, 7620, 50, 1, 'mana potion')\n",
            "shopModule:addBuyableItem({'mana potion'}, 7620, 50, 1, 'mana potion')\n"
            "shopModule:addBuyableItem({'everfull health potion'}, 32085, 100, 1, 'everfull health potion') " + T.SELL_MARK + "\n"
            "shopModule:addBuyableItem({'everfull mana potion'}, 32086, 100, 1, 'everfull mana potion') " + T.SELL_MARK + "\n"
            "shopModule:addBuyableItem({'hand made'}, 32086, 90, 1, 'everfull mana potion')\n") +
            "local rows = {{name = 'everfull health potion', id = 32085, buy = 100, sell = 0}}\n",
    }
    for rel, text in legacy.items():
        open(os.path.join(data, rel), 'w', newline='').write(text)
    old_items = open(os.path.join(data, 'items', 'items.xml')).read().replace(
        '</items>', T.XML_BEGIN + '\t<item id="32085" article="an" name="everfull health potion" plural="everfull health potions">\n'
        '\t\t<attribute key="description" value="A flask: kills and the temple refill its charges, each drink costs one." />\n'
        '\t\t<attribute key="weight" value="180" />\n\t</item>\n' + T.XML_END + '</items>')
    open(os.path.join(data, 'items', 'items.xml'), 'w', newline='').write(old_items)
    sys.stdout = devnull
    try:
        rc = T.main([data])
        cleaned = snapshot(data)
        rc2 = T.main([data])
    finally:
        sys.stdout = old
    check(rc == 0 and rc2 == 0, 'an earlier install: runs twice')
    check(snapshot(data) == cleaned, 'an earlier install: the second run changes nothing')
    m2 = cleaned['npc/Morora.xml'].decode()
    check('everfull' not in m2 and '3208' not in m2 and 'mana potion,7620,50;' in m2, 'an earlier install: the XML entries are gone, the stock ones stay')
    l2 = cleaned['npc/scripts/potions.lua'].decode()
    check("addBuyableItem({'everfull" not in l2 and T.SELL_MARK not in l2, 'an earlier install: the marked Lua lines are deleted')
    check('-- ' + T.EVER_MARK + "shopModule:addBuyableItem({'hand made'}, 32086, 90" in l2, 'an earlier install: a hand-made sale is commented out')
    check("{name = 'everfull health potion', id = 32085, sell = 0}" in l2, 'an earlier install: a table row loses its buy price')
    check("shopModule:addBuyableItem({'mana potion'}, 7620, 50, 1, 'mana potion')" in l2, 'an earlier install: the stock lines stay')
    check(cleaned['npc/lib/npcsystem/modules.lua'].decode() == MODULES, 'an earlier install: the ShopModule hook is taken out, the rest is as it was')
    x2 = cleaned['items/items.xml'].decode()
    check('charge' not in x2.lower() and 'A flask that never empties.' in x2, 'an earlier install: the item descriptions are rewritten')

    # a hook this script did not write (changed by hand): reported, left alone, the rest still done
    shutil.rmtree(tmp)
    tmp = tempfile.mkdtemp()
    data = make_base(tmp)
    odd = MODULES.replace('\t\tlocal shopItem', '\t\t' + T.HOOK_MARK + ': edited by hand\n\t\tlocal shopItem')
    open(os.path.join(data, 'npc', 'lib', 'npcsystem', 'modules.lua'), 'w').write(odd)
    sys.stdout = devnull
    try:
        rc = T.main([data])
    finally:
        sys.stdout = old
    check(rc == 0 and open(os.path.join(data, 'npc', 'lib', 'npcsystem', 'modules.lua')).read() == odd, 'an unknown hook: left alone, no error')
    check(T.patch_shop_module(odd)[2] is False, 'an unknown hook: reported')

    # no modules.lua at all: fine (nothing to clean)
    shutil.rmtree(tmp)
    tmp = tempfile.mkdtemp()
    data = make_base(tmp)
    os.remove(os.path.join(data, 'npc', 'lib', 'npcsystem', 'modules.lua'))
    sys.stdout = devnull
    try:
        rc = T.main([data])
    finally:
        sys.stdout = old
    check(rc == 0, 'no modules.lua: not an error')

    # a base server without any potion seller: not an error either (nothing sells the Everfull potions anyway)
    shutil.rmtree(tmp)
    tmp = tempfile.mkdtemp()
    data = make_base(tmp)
    os.remove(os.path.join(data, 'npc', 'Morora.xml'))
    os.remove(os.path.join(data, 'npc', 'scripts', 'potions.lua'))
    sys.stdout = devnull
    try:
        rc = T.main([data])
    finally:
        sys.stdout = old
    check(rc == 0, 'no potion seller at all: not an error')
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print('install_potions_test: %s' % ('ok' if not failed else '%d failure(s)' % failed))
sys.exit(1 if failed else 0)
