#!/usr/bin/env python3
"""NPC shops of an occupied town charge more and pay less (server/README.md "Invasions and world events").

usage: python3 -I patch_occupied_prices.py SERVER_DIR [--dry-run]

SERVER_DIR is the folder with data/. A lost invasion occupies its town for 30 minutes (invasion.lua). The NPC trade code
is the base server's ShopModule (data/npc/lib/npcsystem/modules.lua), so this patch makes it ask
ChaosInvasion.npcPrice(price, npc position, "buy" / "sell") at every place a price is read:
  * a helper chaosOccupiedPrice before ShopModule:callbackOnBuy (the price unchanged when invasion.lua is not loaded,
    the NPC is unknown or the call fails);
  * callbackOnBuy: the total and the part paid when the backpack had room for some only;
  * callbackOnSell: the message total and the money given;
  * requestTrade: the window shows the same prices (a copy of each entry that changed);
  * tradeItem: the talk trade ("buy 5 torches") keeps the scaled price for its confirmation.
invasion_config.lua occupation.buyMult / sellMult are the factors (1.25 / 0.75). Marked "Chaos (occupied prices)".
Idempotent: a second run changes nothing. install_all.py step `occupiedprices`, after `shopprices`.
"""
import os
import sys

REL = os.path.join('data', 'npc', 'lib', 'npcsystem', 'modules.lua')
MARK = '-- Chaos (occupied prices)'

HELPER = '''	-- Chaos (occupied prices): an NPC inside an occupied town charges more and pays less (invasion.lua)
	local function chaosOccupiedPrice(price, kind)
		if type(price) ~= "number" or price <= 0 or not ChaosInvasion or not ChaosInvasion.npcPrice then
			return price
		end
		local ok, value = pcall(function()
			local npc = Creature(getNpcCid())
			return npc and ChaosInvasion.npcPrice(price, npc:getPosition(), kind) or price
		end)
		return ok and value or price
	end

'''

# (anchor, replacement, count): each anchor must occur exactly `count` times in the stock text
EDITS = [
    ('	function ShopModule:callbackOnBuy(cid, itemid, subType, amount, ignoreCap, inBackpacks)\n',
     HELPER + '	function ShopModule:callbackOnBuy(cid, itemid, subType, amount, ignoreCap, inBackpacks)\n', 1),
    ('		local totalCost = amount * shopItem.buy\n',
     '		local chaosBuy = chaosOccupiedPrice(shopItem.buy, "buy")\n'
     '		local totalCost = amount * chaosBuy\n', 1),
    ('removeTotalMoney((a * shopItem.buy) + (b * 20))', 'removeTotalMoney((a * chaosBuy) + (b * 20))', 1),
    ('			[TAG_TOTALCOST] = amount * shopItem.sell,\n',
     '			[TAG_TOTALCOST] = amount * chaosOccupiedPrice(shopItem.sell, "sell"),\n', 1),
    ('			player:addMoney(amount * shopItem.sell)\n',
     '			player:addMoney(amount * chaosOccupiedPrice(shopItem.sell, "sell"))\n', 1),
    ('		openShopWindow(cid, itemWindow,\n',
     '		for i = 1, #itemWindow do\n'
     '			local entry = itemWindow[i]\n'
     '			local buy, sell = chaosOccupiedPrice(entry.buy, "buy"), chaosOccupiedPrice(entry.sell, "sell")\n'
     '			if buy ~= entry.buy or sell ~= entry.sell then\n'
     '				local copy = {}\n'
     '				for k, v in pairs(entry) do\n'
     '					copy[k] = v\n'
     '				end\n'
     '				copy.buy, copy.sell = buy, sell\n'
     '				itemWindow[i] = copy\n'
     '			end\n'
     '		end\n'
     '		openShopWindow(cid, itemWindow,\n', 1),
    ('		shop_amount[cid] = module.amount\n		shop_cost[cid] = parameters.cost\n',
     '		shop_amount[cid] = module.amount\n'
     '		shop_cost[cid] = chaosOccupiedPrice(parameters.cost,\n'
     '			parameters.eventType == SHOPMODULE_SELL_ITEM and "sell" or "buy")\n', 1),
]


def patch(text):
    """(new text, note); the note says why nothing changed when the text is returned as it was"""
    if MARK in text:
        return text, 'already patched'
    nl = '\r\n' if '\r\n' in text else '\n'
    out = text
    for old, new, count in EDITS:
        old, new = old.replace('\n', nl), new.replace('\n', nl)
        if out.count(old) != count:
            return text, 'ShopModule text not found: %r (a changed base)' % old.strip()[:60]
        out = out.replace(old, new)
    return out, 'patched'


def main(argv):
    args = [a for a in argv if a != '--dry-run']
    dry = len(args) != len(argv)
    if len(args) != 1:
        print(__doc__)
        return 1
    path = os.path.join(args[0], REL)
    if not os.path.isfile(path):
        print('%s: not found' % REL)
        return 1
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        text = f.read()
    new, note = patch(text)
    if new != text and not dry:
        with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
            f.write(new)
    print('modules.lua: %s%s' % (note, ' (dry run)' if dry and new != text else ''))
    return 0 if new != text or note == 'already patched' else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
