#!/usr/bin/env python3
"""An NPC trade window lists only what the NPC really buys or sells (server/README.md "NPC trade windows").

usage: python3 -I patch_shop_prices.py SERVER_DIR [--dry-run]

SERVER_DIR is the folder with data/. The stock ShopModule marks "not bought" and "not sold" with a price of -1
(data/npc/lib/npcsystem/modules.lua: addBuyableItem leaves sell = -1, addSellableItem buy = -1, and callbackOnBuy /
callbackOnSell raise "attempt to buy a non-buyable item" / "attempt to sell a non-sellable item" on it). The engine writes
a price as a u32 with std::max<uint32_t>(price, 0): the -1 goes out as 4294967295. So every window offered every item in
both tabs, and the engine's sale list (it skips only a price of 0) offered a carried buy-only item (a pick at the
Material Broker) for sale. A click raised the Lua error. This changes ShopModule.requestTrade: the window gets a copy of
each entry with a negative price as 0, so a tab holds only the items that price. The shop list itself (-1) stays as the
stock code and getShopItem read it. Marked "Chaos (shop prices)". Idempotent: a second run changes nothing.
install_all.py step `shopprices`.
"""
import os
import sys

REL = os.path.join('data', 'npc', 'lib', 'npcsystem', 'modules.lua')
MARK = '-- Chaos (shop prices)'
OLD = '''		for i = 1, #module.npcHandler.shopItems do
			itemWindow[#itemWindow + 1] = module.npcHandler.shopItems[i]
		end
'''
NEW = '''		for i = 1, #module.npcHandler.shopItems do
			-- Chaos (shop prices): the engine sends a price of -1 as 4294967295; the window gets 0 for "not for sale"
			local entry = module.npcHandler.shopItems[i]
			if (entry.buy or 0) < 0 or (entry.sell or 0) < 0 then
				local copy = {}
				for k, v in pairs(entry) do
					copy[k] = v
				end
				copy.buy, copy.sell = math.max(entry.buy or 0, 0), math.max(entry.sell or 0, 0)
				entry = copy
			end
			itemWindow[#itemWindow + 1] = entry
		end
'''


def patch(text):
    """(new text, note); the note says why nothing changed when the text is returned as it was"""
    if MARK in text:
        return text, 'already patched'
    nl = '\r\n' if '\r\n' in text else '\n'
    old = OLD.replace('\n', nl)
    if text.count(old) != 1:
        return text, 'ShopModule.requestTrade window loop not found (a changed base)'
    return text.replace(old, NEW.replace('\n', nl)), 'patched'


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
