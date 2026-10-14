#!/usr/bin/env python3
"""Superseded: data/scripts/chaos/sell_prices.lua (the Auto Seller's prices) is written by tools/gen_item_prices.py
from the item price table now (server/README.md "Item prices"), so the Auto Seller, the Loot Buyer and every NPC shop
pay the same price.

usage: python3 -I gen_sell_prices.py [DATA_DIR] [OUT_FILE]

Runs gen_item_prices.py (the arguments are ignored: the table is built from the repo's snapshot of the base server,
data/items/base_item_values.csv; `gen_item_prices.py survey BASE_DATA` refreshes that snapshot).
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    print('gen_sell_prices.py is superseded by gen_item_prices.py (README "Item prices"); running it')
    return subprocess.call([sys.executable, '-I', os.path.join(HERE, 'gen_item_prices.py')])


if __name__ == '__main__':
    sys.exit(main())
