#!/usr/bin/env python3
"""Install the item price table into a base server (server/README.md "Item prices").

usage: python3 -I install_item_prices.py DATA_DIR [--dry-run]

The prices come from server/data/lib/chaos_item_prices_data.lua (written by tools/gen_item_prices.py), the same file the
Lua side reads, so every NPC pays what ChaosItemPrices says.

1. data/npc: the Loot Buyer (server/data/npc/Loot Buyer.xml and the script it names); only new or different files are
   written. data/scripts/chaos/item_prices.lua places one next to every temple at startup.
2. Every NPC shop of the base server (data/npc/*.xml shop_sellable / shop_buyable, data/npc/scripts/*.lua
   addSellableItem / addBuyableItem and {id = n, buy = n, sell = n} tables of the scripts that trade in gold):
   - what an NPC pays for an item of the table becomes the table's price, at every NPC (one price per item);
     items the table does not price (currency, keys, quest, store, profession materials, anything not lootable) keep
     their entries as they are
   - what an NPC asks for an item is raised to at least price / buyShare (2 x the sell price) where it was lower, so
     no NPC sells an item for less than another one pays (no arbitrage; the base server's unspawned staff NPC "H.L."
     sold gear at 1-720 gold)
   Only the numbers change: names, order, spacing and subtypes stay. Fluid entries (a subtype) are left alone.
Run after the steps that write NPC shops (packitems, fistweapons, runes): install_all.py step `itemprices`.
Idempotent: a second run changes nothing.
"""
import filecmp
import glob
import math
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
DATA_LUA = os.path.join(SERVER, 'data', 'lib', 'chaos_item_prices_data.lua')
REPO_NPC = os.path.join(SERVER, 'data', 'npc')
NPC_NAME = 'Loot Buyer'

XML_PARAM = re.compile(r'(key\s*=\s*"(shop_sellable|shop_buyable)"\s+value\s*=\s*")([^"]*)(")', re.S)
LUA_CALL = re.compile(r'(add(Sellable|Buyable)Item\s*\(\s*(?:\{[^}]*\}|nil|"[^"]*"|\'[^\']*\')\s*,\s*)(\d+)(\s*,\s*)(\d+)')
LUA_TABLE = re.compile(r'\{[^{}]*?\b(?:id|itemId)\s*=\s*(\d+)[^{}]*\}')
LUA_TBUY = re.compile(r'(\b(?:buy|buyPrice)\s*=\s*)(\d+)')
LUA_TSELL = re.compile(r'(\b(?:sell|sellPrice)\s*=\s*)(\d+)')
GOLD = re.compile(r'removeMoney|removeTotalMoney|addMoney')


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape') as f:
        f.write(text)


def load_prices(path=DATA_LUA):
    text = read(path)
    block = re.search(r'\n\tprices = \{(.*?)\n\t\}', text, re.S)
    if not block:
        raise SystemExit('%s: no prices table (run tools/gen_item_prices.py)' % path)
    prices = {int(k): int(v) for k, v in re.findall(r'\[(\d+)\]\s*=\s*(\d+)', block.group(1))}
    share = float(re.search(r'buyShare\s*=\s*([\d.]+)', text).group(1))
    return prices, share


def min_buy(price, share):
    return int(math.ceil(price / share))


def patch_value(value, side, prices, share, stats):
    """one shop_sellable / shop_buyable list: the entries split on ';', only the price number changes"""
    out = []
    for entry in value.split(';'):
        m = re.match(r'^([^,]*,\s*)(\d+)(\s*,\s*)(\d+)(\s*(?:,\s*(\d+))?\s*)$', entry, re.S)
        if not m or (m.group(6) and m.group(6) not in ('0', '1')):
            out.append(entry)
            continue
        iid, price = int(m.group(2)), int(m.group(4))
        new = price
        if iid in prices:
            if side == 'sell':
                new = prices[iid]
            elif price < prices[iid]:
                new = min_buy(prices[iid], share)
        if new != price:
            stats[side] += 1
            entry = m.group(1) + m.group(2) + m.group(3) + str(new) + m.group(5)
        out.append(entry)
    return ';'.join(out)


def patch_xml(text, prices, share, stats):
    def sub(m):
        side = 'sell' if m.group(2) == 'shop_sellable' else 'buy'
        return m.group(1) + patch_value(m.group(3), side, prices, share, stats) + m.group(4)
    return XML_PARAM.sub(sub, text)


def patch_lua(text, prices, share, stats):
    def call(m):
        side = 'sell' if m.group(2) == 'Sellable' else 'buy'
        iid, price = int(m.group(3)), int(m.group(5))
        new = price
        if iid in prices:
            if side == 'sell':
                new = prices[iid]
            elif price < prices[iid]:
                new = min_buy(prices[iid], share)
        if new == price:
            return m.group(0)
        stats[side] += 1
        return m.group(1) + m.group(3) + m.group(4) + str(new)

    text = LUA_CALL.sub(call, text)
    if not GOLD.search(text):
        return text  # a table shop in a coin of its own: not gold prices

    def table(m):
        iid = int(m.group(1))
        if iid not in prices:
            return m.group(0)
        body = m.group(0)

        def sell(s):
            if int(s.group(2)) == prices[iid]:
                return s.group(0)
            stats['sell'] += 1
            return s.group(1) + str(prices[iid])

        def buy(b):
            if int(b.group(2)) >= prices[iid]:
                return b.group(0)
            stats['buy'] += 1
            return b.group(1) + str(min_buy(prices[iid], share))
        return LUA_TBUY.sub(buy, LUA_TSELL.sub(sell, body))
    return LUA_TABLE.sub(table, text)


def patch_shops(data_dir, prices, share, dry):
    notes, files = [], 0
    total = {'sell': 0, 'buy': 0}
    paths = sorted(glob.glob(os.path.join(data_dir, 'npc', '*.xml'))) + sorted(glob.glob(os.path.join(data_dir, 'npc', 'scripts', '*.lua')))
    for path in paths:
        if os.path.basename(path) == NPC_NAME + '.xml' or os.path.basename(path) == 'loot_buyer.lua':
            continue
        text = read(path)
        stats = {'sell': 0, 'buy': 0}
        new = patch_xml(text, prices, share, stats) if path.endswith('.xml') else patch_lua(text, prices, share, stats)
        if new != text:
            files += 1
            total['sell'] += stats['sell']
            total['buy'] += stats['buy']
            if not dry:
                write(path, new)
    notes.append('npc shops: %d file(s) changed, %d sell price(s) set to the table, %d buy price(s) raised to the floor%s'
                 % (files, total['sell'], total['buy'], ' (dry run)' if dry else ''))
    return notes


def copy_npc(data_dir, dry):
    notes = []
    xml = os.path.join(REPO_NPC, NPC_NAME + '.xml')
    script = re.search(r'script="([^"]+)"', read(xml)).group(1)
    for src, rel in ((xml, NPC_NAME + '.xml'), (os.path.join(REPO_NPC, 'scripts', script), os.path.join('scripts', script))):
        dst = os.path.join(data_dir, 'npc', rel)
        if os.path.isfile(dst) and filecmp.cmp(src, dst, shallow=False):
            notes.append('npc/%s: up to date' % rel)
            continue
        if not dry:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(src, dst)
        notes.append('npc/%s: copied%s' % (rel, ' (dry run)' if dry else ''))
    return notes


def main():
    args = sys.argv[1:]
    dry = '--dry-run' in args
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    if not os.path.isdir(os.path.join(data_dir, 'npc')):
        print('%s: no npc folder (is this a server data folder?)' % data_dir)
        return 1
    prices, share = load_prices()
    for note in copy_npc(data_dir, dry) + patch_shops(data_dir, prices, share, dry):
        print(note)
    if dry:
        print('dry run: nothing written')
    return 0


if __name__ == '__main__':
    sys.exit(main())
