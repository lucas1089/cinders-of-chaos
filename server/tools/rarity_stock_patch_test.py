#!/usr/bin/env python3
"""patch_base_events.py step 21: the stock rarity roll walks ChaosRarity.stockRolls (the seven rarities, 2026-10-18).
Run: python3 -I server/tools/rarity_stock_patch_test.py"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import patch_base_events as P  # noqa: E402

STOCK = (
    "local ec = EventCallback\n"
    "\n"
    "local rarities = {{id = 1, chance = 15.0}, {id = 2, chance = 14.0}}\n"
    "\n"
    "local function rollRarity()\n"
    "    if math.random(100) > 70 then\n"
    "        return 0\n"
    "    end\n"
    "\n"
    "    for _, r in ipairs(rarities) do\n"
    "        local roll = math.random(100)\n"
    "        if roll <= r.chance then\n"
    "            return r.id\n"
    "        end\n"
    "    end\n"
    "    return 0\n"
    "end\n"
    "\n"
    "ec.onDropLoot = function(self, corpse)\n"
    "    for _, lootData in ipairs(mType:getLoot()) do\n"
    "        local roll = getLootRandom()\n"
    "            if roll <= lootData.chance then\n"
    "                local rarityId = rollRarity(player)\n"
    "            end\n"
    "    end\n"
    "end\n")

failures = 0


def check(cond, label):
    global failures
    if not cond:
        failures += 1
        print('FAIL ' + label)


text, st = P.patch_stock_rarities(STOCK)
check(st.startswith('unexpected') and 'step 2' in st, 'a stock file without the step 2 roll is refused: ' + st)
step2, st = P.patch_loot(STOCK)
check(st == 'patched', 'step 2 patches the stock roll')
new, st = P.patch_stock_rarities(step2)
check(st == 'patched', 'step 21 patches: ' + st)
check('ipairs(chaosStockRolls())' in new and 'ipairs(rarities)' not in new.split('local function rollRarity')[1].split('\nend\n')[0],
      'the loop walks the Chaos list')
check('ChaosRarity.stockRolls' in new and 'return rarities' in new, 'with the base rows as the fallback')
check(new.count(P.STOCK_MARKER) == 1, 'one marker')
again, st = P.patch_stock_rarities(new)
check(st == 'already' and again == new, 'idempotent')
if failures:
    sys.exit(1)
print('rarity_stock_patch_test: OK')
