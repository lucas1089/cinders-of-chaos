#!/usr/bin/env python3
"""python3 -I server/tools/patch_npc_currency_test.py : patch_npc_currency.py on synthetic copies of the stock lines.

Three reduced NPC scripts written here with made-up names: one that pays in an item (and says the stock vocation line
and names another currency in its sell message), one that pays in a storage (CRLF line ends, like the base's), one
without the currency lines. Checks: the three lines become the announce call, the shop callbacks are wrapped, the
storage currency's name is read from the script's own message, the sell message names the item's plural, the vocation
line becomes the setsReply call, the ServerOpcodes of global.lua move off 125, a file without the stock lines is left
alone (and reported when it names the opcode), CRLF is kept, a dry run writes nothing, a second run changes nothing,
and every patched script still parses in LuaJIT and Lua 5.3 (when they are installed). No base server needed."""
import os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import patch_npc_currency as T  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL: %s' % what)


ITEM_NPC = '''local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)

local shop = {
	{id=1001, buy=50, sell=25, name='test wand'},
}

local function onBuy(cid, item, subType, amount, ignoreCap, inBackpacks)
	return true
end

local function onSell(cid, item, subType, amount, ignoreCap, inBackpacks)
	local player = Player(cid)
	return player:sendTextMessage(MESSAGE_TRADE,
		"Sell "..amount.."x "..itemsTable[item].name.." for "..amount* itemsTable[item].sell.." Zorbon Coins.")
end

function creatureSayCallback(cid, type, msg)
	if msgcontains(msg, 'trade') then
		npcHandler:say("Do you have any {azure} coin?", cid)
	elseif msgcontains(msg, 'azure') then
		local player = Player(cid)
        player:sendExtendedOpcode(ServerOpcodes.currencyType, "AZ")
        local coinAmount = player:getItemCount(26780) or 0
        player:sendExtendedOpcode(ServerOpcodes.coinAmount, tostring(coinAmount))
		openShopWindow(cid, shop, onBuy, onSell)
		npcHandler:say({"Stuff for all vocations, Alpha and Beta for knights, gamma, for sorcerers and druids and delta for paladins."}, cid)
	end
	return true
end
'''

STORAGE_NPC = '''local function onBuy(cid, item, subType, amount, ignoreCap, inBackpacks)
    player:sendTextMessage(MESSAGE_INFO_DESCR,
        "Bought "..amount.."x "..itemsTable[item].name.." for "..totalCost.." quillfall coins.")
    return true
end

function creatureSayCallback(cid, type, msg)
    if msgcontains(msg, 'trade') then
        local player = Player(cid)
        player:sendExtendedOpcode(ServerOpcodes.currencyType, "Q")
        local coinAmount = player:getStorageValue(48079) or 0
        player:sendExtendedOpcode(ServerOpcodes.coinAmount, tostring(coinAmount))
        openShopWindow(cid, shop, onBuy, onSell)
    end
    return true
end
'''.replace('\n', '\r\n')

NO_BLOCK = '''function creatureSayCallback(cid, type, msg)
	if msgcontains(msg, 'trade') then
		Player(cid):sendExtendedOpcode(ServerOpcodes.currencyType, "ZZ")
	end
end
'''

PLAIN = 'function onThink() end\n'

GLOBAL = 'x = 1\r\n\r\nServerOpcodes = {\r\n\tcurrencyType = 125,\r\n\tcoinAmount = 126\r\n}\r\n\r\ny = 2\r\n'


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(text)


def read(path):
    with open(path, encoding='utf-8', newline='') as f:
        return f.read()


def parses(path):
    for exe in ('luajit', 'lua5.3'):
        if shutil.which(exe):
            code = 'local f, e = loadfile([==[%s]==]); if not f then io.stderr:write(e); os.exit(1) end' % path
            r = subprocess.run([exe, '-e', code], capture_output=True, text=True)
            if r.returncode != 0:
                print('%s: %s' % (exe, r.stderr.strip()))
                return False
    return True


tmp = tempfile.mkdtemp(prefix='npccur_')
try:
    data = os.path.join(tmp, 'data')
    paths = {k: os.path.join(data, 'npc', 'scripts', k + '.lua') for k in ('item', 'storage', 'noblock', 'plain')}
    write(paths['item'], ITEM_NPC)
    write(paths['storage'], STORAGE_NPC)
    write(paths['noblock'], NO_BLOCK)
    write(paths['plain'], PLAIN)
    write(os.path.join(data, 'global.lua'), GLOBAL)

    # dry run writes nothing
    check(T.main([data, '--dry-run']) == 1, 'a script without the stock lines makes the exit status 1')
    check(read(paths['item']) == ITEM_NPC and read(paths['storage']) == STORAGE_NPC, 'dry run: scripts unchanged')
    check(read(os.path.join(data, 'global.lua')) == GLOBAL, 'dry run: global.lua unchanged')

    T.main([data])
    item = read(paths['item'])
    check(item.startswith(T.LOAD + '\n'), 'the library is loaded on the first line')
    check('{code = "AZ", item = 26780}' in item, 'item currency: code and item id')
    check('ChaosNpcCurrency.announce(player, chaosCurrency)' in item, 'item currency: announced')
    check('ServerOpcodes' not in item, 'item currency: no opcode line left')
    check('openShopWindow(cid, shop, ChaosNpcCurrency.wrap(onBuy, chaosCurrency), '
          'ChaosNpcCurrency.wrap(onSell, chaosCurrency))' in item, 'item currency: callbacks wrapped')
    check('ItemType(26780):getPluralName()' in item and 'Zorbon' not in item, 'the sell message names the item plural')
    check('ChaosNpcCurrency.setsReply(cid, "Alpha", "Beta", "gamma", "delta")' in item, 'the sets reply replaces the stock line')
    check('vocations' not in item and 'knights' not in item, 'no stock vocation left')

    st = read(paths['storage'])
    check('\r\n' in st and '\n' not in st.replace('\r\n', ''), 'CRLF kept')
    check('{code = "Q", storage = 48079, name = "quillfall coins"}' in st, 'storage currency: name from its own message: ' + st)
    check('ChaosNpcCurrency.wrap(onSell' in st, 'storage currency: callbacks wrapped')

    check(read(paths['noblock']) == NO_BLOCK, 'a script without the stock lines is left alone')
    check(read(paths['plain']) == PLAIN, 'a script without the opcode is left alone')

    g = read(os.path.join(data, 'global.lua'))
    check('currencyType = 126' in g and 'coinAmount = 127' in g and T.MARK in g, 'global.lua: opcodes moved')
    check(g.count('\r\n') == GLOBAL.count('\r\n') and '\n' not in g.replace('\r\n', ''), 'global.lua: CRLF kept')
    check(g.startswith('x = 1') and g.rstrip().endswith('y = 2'), 'global.lua: the rest untouched')

    for k in ('item', 'storage'):
        check(parses(paths[k]), 'the patched %s script parses' % k)

    # a second run changes nothing
    snap = {k: read(p) for k, p in paths.items()}
    snap_g = read(os.path.join(data, 'global.lua'))
    T.main([data])
    check(all(read(p) == snap[k] for k, p in paths.items()), 'second run: scripts unchanged')
    check(read(os.path.join(data, 'global.lua')) == snap_g, 'second run: global.lua unchanged')
finally:
    shutil.rmtree(tmp, ignore_errors=True)

if failed:
    print('%d check(s) failed' % failed)
    sys.exit(1)
print('patch_npc_currency tests OK')
