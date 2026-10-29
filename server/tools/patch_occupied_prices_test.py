#!/usr/bin/env python3
"""Test of patch_occupied_prices.py on the stock ShopModule lines it reads: patched once, idempotent, CRLF, a changed
base refused, and the patched Lua (run under luajit / lua5.3 when present) charges and pays the scaled prices in the
window, the trade, a part buy and the talk trade, and the stock prices without invasion.lua; the install_all.py step is
wired.
Run: python3 -I server/tools/patch_occupied_prices_test.py"""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import patch_occupied_prices as P  # noqa: E402

# the stock lines the patch reads, in a small runnable ShopModule (the bodies cut to what the anchors need)
STOCK = '''SHOPMODULE_SELL_ITEM = 1
SHOPMODULE_BUY_ITEM = 2
shop_cost = {}
shop_amount = {}
ShopModule = {}
if Modules == nil then
	function ShopModule:callbackOnBuy(cid, itemid, subType, amount, ignoreCap, inBackpacks)
		local shopItem = self.items[itemid]
		local totalCost = amount * shopItem.buy
		local a, b = self.fits, 0
		if a < amount then
			if not player:removeTotalMoney((a * shopItem.buy) + (b * 20)) then
				return false
			end
			return true
		end
		return player:removeTotalMoney(totalCost)
	end

	function ShopModule:callbackOnSell(cid, itemid, subType, amount, ignoreEquipped, _)
		local shopItem = self.items[itemid]
		local parseInfo = {
			[TAG_TOTALCOST] = amount * shopItem.sell,
		}
		if true then
			player:addMoney(amount * shopItem.sell)
		end
		return parseInfo
	end

	function ShopModule.requestTrade(cid, message, keywords, parameters, node)
		local itemWindow = {}
		for i = 1, #parameters.items do
			itemWindow[#itemWindow + 1] = parameters.items[i]
		end
		openShopWindow(cid, itemWindow,
			nil, nil)
		return true
	end

	function ShopModule.tradeItem(cid, message, keywords, parameters, node)
		local module = {amount = 1}
		shop_amount[cid] = module.amount
		shop_cost[cid] = parameters.cost
		return true
	end
end
'''

RUN = '''
TAG_TOTALCOST = 3
player = {paid = {}, got = {}}
function player:removeTotalMoney(n) self.paid[#self.paid + 1] = n; return true end
function player:addMoney(n) self.got[#self.got + 1] = n end
local npcPos = {x = 1, y = 1, z = 7}
function getNpcCid() return 77 end
function Creature(id) return {getPosition = function() return npcPos end} end
local shown
function openShopWindow(cid, items) shown = items end
local shop = {items = {[10] = {buy = 100, sell = 40}}, fits = 5}
local out = {}
local function run()
	player.paid, player.got = {}, {}
	ShopModule.callbackOnBuy(shop, 1, 10, 0, 5)
	shop.fits = 2
	ShopModule.callbackOnBuy(shop, 1, 10, 0, 5)
	shop.fits = 5
	local info = ShopModule.callbackOnSell(shop, 1, 10, 0, 3)
	ShopModule.requestTrade(1, "", nil, {items = {{id = 10, buy = 100, sell = -1}, {id = 11, buy = 0, sell = 40}}})
	ShopModule.tradeItem(1, "", nil, {cost = 100, eventType = SHOPMODULE_BUY_ITEM})
	local talkBuy = shop_cost[1]
	ShopModule.tradeItem(1, "", nil, {cost = 40, eventType = SHOPMODULE_SELL_ITEM})
	out[#out + 1] = table.concat({player.paid[1], player.paid[2], info[TAG_TOTALCOST], player.got[1],
		shown[1].buy, shown[1].sell, shown[2].buy, shown[2].sell, talkBuy, shop_cost[1]}, ",")
end
run()
ChaosInvasion = {npcPrice = function(price, pos, kind)
	if pos ~= npcPos then return price end
	return math.floor(price * (kind == "buy" and 1.25 or 0.75) + 0.5)
end}
run()
ChaosInvasion.npcPrice = function() error("boom") end
run()
print(table.concat(out, "|"))
'''

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


new, note = P.patch(STOCK)
check(note == 'patched', 'patched: ' + note)
check(new.count(P.MARK) == 1, 'one marker')
again, note = P.patch(new)
check(note == 'already patched' and again == new, 'idempotent')
crlf, note = P.patch(STOCK.replace('\n', '\r\n'))
check(note == 'patched' and '\r\n' in crlf and '\n' not in crlf.replace('\r\n', ''), 'CRLF kept')
bad, note = P.patch(STOCK.replace('local totalCost = amount * shopItem.buy', 'local totalCost = shopItem.buy'))
check(bad == STOCK.replace('local totalCost = amount * shopItem.buy', 'local totalCost = shopItem.buy')
      and 'not found' in note, 'a changed base is refused whole: ' + note)

lua = shutil.which('luajit') or shutil.which('lua5.3')
if lua:
    with tempfile.TemporaryDirectory() as d:
        f = os.path.join(d, 'run.lua')
        with open(f, 'w') as fh:
            fh.write(new + RUN)
        res = subprocess.run([lua, f], capture_output=True, text=True)
    got = res.stdout.strip().split('|')
    stock = '500,200,120,120,100,-1,0,40,100,40'
    check(len(got) == 3, 'three runs: %r %s' % (res.stdout, res.stderr[-300:]))
    if len(got) == 3:
        check(got[0] == stock, 'no invasion.lua: stock prices ' + got[0])
        check(got[1] == '625,250,90,90,125,-1,0,30,125,30', 'occupied: scaled everywhere ' + got[1])
        check(got[2] == stock, 'a failing call: stock prices ' + got[2])
else:
    print('no luajit / lua5.3: Lua run skipped')

with tempfile.TemporaryDirectory() as d:
    path = os.path.join(d, P.REL)
    os.makedirs(os.path.dirname(path))
    with open(path, 'w') as fh:
        fh.write(STOCK)
    tool = os.path.join(HERE, 'patch_occupied_prices.py')
    r = subprocess.run([sys.executable, '-I', tool, d, '--dry-run'], capture_output=True, text=True)
    check(r.returncode == 0 and open(path).read() == STOCK, 'dry run writes nothing')
    r = subprocess.run([sys.executable, '-I', tool, d], capture_output=True, text=True)
    check(r.returncode == 0 and P.MARK in open(path).read(), 'run patches the file')
    r = subprocess.run([sys.executable, '-I', tool, d], capture_output=True, text=True)
    check(r.returncode == 0 and 'already' in r.stdout, 'second run: already')
    r = subprocess.run([sys.executable, '-I', tool], capture_output=True, text=True)
    check(r.returncode == 1, 'no folder: usage')

with open(os.path.join(HERE, 'install_all.py'), encoding='utf-8') as f:
    ia = f.read()
check("'occupiedprices'" in ia and 'patch_occupied_prices.py' in ia and 'def step_occupiedprices' in ia,
      'install_all.py step wired')

if fails:
    sys.exit(1)
print('patch_occupied_prices_test: OK')
