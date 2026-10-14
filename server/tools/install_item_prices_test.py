#!/usr/bin/env python3
"""Tests of install_item_prices.py on a small synthetic NPC folder (no game data needed; CI runs it).

    python3 -I server/tools/install_item_prices_test.py

Checks: the Loot Buyer files are copied; XML shop_sellable prices of priced items become the table's price (names,
spacing, the blank last entry and fluid subtypes kept); a buy price under the sell price is raised to twice it; an item
the table does not price keeps its entries; Lua addSellableItem / addBuyableItem and {id, buy, sell} tables of a gold
shop are rewritten, a table shop in another coin is not; a second run changes nothing; afterwards no NPC sells an item
for less than another one pays.
"""
import os
import re
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import install_item_prices as I  # noqa: E402
import item_prices_base as B  # noqa: E402

FAILS = []


def check(cond, label):
    if not cond:
        FAILS.append(label)
        print('FAIL', label)


def main():
    prices, share = I.load_prices()
    # three priced items with different prices and one unpriced id
    ids = sorted(i for i in prices if prices[i] >= 20)[:3]
    a, b, c = ids
    free = 1  # no item 1 in the table
    assert free not in prices
    d = tempfile.mkdtemp(prefix='chaos_itemprices_')
    try:
        npc = os.path.join(d, 'npc')
        os.makedirs(os.path.join(npc, 'scripts'))
        xml = ('<npc name="Trader" script="trader.lua">\n<parameters>\n'
               '\t<parameter key="shop_sellable" value="\n\t\t\tthing a, %d, 1;\n\t\t\tthing b,%d,999999;\n\t\t\tfluid,%d,5,3;\n'
               '\t\t\tfree thing,%d,7;" />\n'
               '\t<parameter key="shop_buyable" value="thing a,%d,1;thing c,%d,%d" />\n</parameters>\n</npc>\n'
               % (a, b, c, free, a, c, prices[c] * 10))
        open(os.path.join(npc, 'Trader.xml'), 'w').write(xml)
        lua_gold = ("shopModule:addSellableItem({'a'}, %d, 3, 'a')\nshopModule:addBuyableItem({'b'}, %d, 1, 1, 'b')\n"
                    "local shop = {{id = %d, buy = 1, sell = 2, name = 'c'}}\nplayer:removeMoney(1)\n" % (a, b, c))
        lua_coin = "local shop = {\n    {id=%d, buy=1, sell=2, name='c'},\n}\nplayer:getStorageValue(48077)\n" % c
        open(os.path.join(npc, 'scripts', 'trader.lua'), 'w').write(lua_gold)
        open(os.path.join(npc, 'scripts', 'coins.lua'), 'w').write(lua_coin)

        notes = I.copy_npc(d, False) + I.patch_shops(d, prices, share, False)
        check(os.path.isfile(os.path.join(npc, 'Loot Buyer.xml')), 'Loot Buyer.xml copied')
        check(os.path.isfile(os.path.join(npc, 'scripts', 'loot_buyer.lua')), 'loot_buyer.lua copied')
        out = open(os.path.join(npc, 'Trader.xml')).read()
        check('thing a, %d, %d;' % (a, prices[a]) in out, 'xml sell price of a set, spacing kept')
        check('thing b,%d,%d;' % (b, prices[b]) in out, 'xml sell price of b lowered to the table')
        check('fluid,%d,5,3;' % c in out, 'a fluid entry (subtype 3) is left alone')
        check('free thing,%d,7;' % free in out, 'an unpriced item keeps its price')
        check('thing a,%d,%d;' % (a, I.min_buy(prices[a], share)) in out, 'a buy price under the sell price is raised')
        check('thing c,%d,%d"' % (c, prices[c] * 10) in out, 'a sane buy price stays')
        lua = open(os.path.join(npc, 'scripts', 'trader.lua')).read()
        check("addSellableItem({'a'}, %d, %d" % (a, prices[a]) in lua, 'lua addSellableItem set')
        check("addBuyableItem({'b'}, %d, %d, 1" % (b, I.min_buy(prices[b], share)) in lua, 'lua addBuyableItem raised, subtype kept')
        check("buy = %d, sell = %d" % (I.min_buy(prices[c], share), prices[c]) in lua, 'lua gold table rewritten')
        check(open(os.path.join(npc, 'scripts', 'coins.lua')).read() == lua_coin, 'a table shop in another coin is untouched')
        check(any('3 sell price' in n or 'sell price(s)' in n for n in notes), 'report line')

        before = {f: open(os.path.join(r, f)).read() for r, _, fs in os.walk(npc) for f in fs}
        again = I.copy_npc(d, False) + I.patch_shops(d, prices, share, False)
        after = {f: open(os.path.join(r, f)).read() for r, _, fs in os.walk(npc) for f in fs}
        check(before == after, 'a second run changes nothing')
        check(any('0 file(s) changed' in n for n in again), 'second run reports no change')

        shops = B.shops(d)
        for iid, s in shops.items():
            if s['sell'] and s['buy']:
                check(max(p for _, p in s['sell']) <= min(p for _, p in s['buy']), 'no arbitrage on item %d' % iid)
        # dry run writes nothing
        shutil.rmtree(d)
        os.makedirs(os.path.join(npc, 'scripts'))
        open(os.path.join(npc, 'Trader.xml'), 'w').write(xml)
        I.copy_npc(d, True)
        I.patch_shops(d, prices, share, True)
        check(open(os.path.join(npc, 'Trader.xml')).read() == xml, 'dry run: the NPC file is unchanged')
        check(not os.path.exists(os.path.join(npc, 'Loot Buyer.xml')), 'dry run: no Loot Buyer written')
    finally:
        shutil.rmtree(d, ignore_errors=True)
    print('install_item_prices_test: %s' % ('OK' if not FAILS else '%d failure(s)' % len(FAILS)))
    return 1 if FAILS else 0


if __name__ == '__main__':
    sys.exit(main())
