#!/usr/bin/env python3
"""Loot of the hunting bands, the input of the loot-by-monster-level model (tools/loot_model.lua; server/README.md
"Pack combat (pace)", "Loot by monster level").

    python3 -I server/tools/loot_bands.py BASE_DATA [--out PATH] [--check]

BASE_DATA is the data folder of an installed base server (items/items.xml, monster/monsters.xml and monster/lua; the
loot tables are not in this repository). For every bounty pool monster (data/scripts/chaos/bounty_pool.lua, the hunt
list) whose level on the hunting scale (pace_core.lua P.entryLevel: its own level for a level-scaled monster, else
the pool level; 2 x before O285) is within a band's range (BANDS), and for the two widows of the beta report, it writes the stock
loot table as rows {item id, chance per 100000, max count, class, NPC price}:

  coin   gold, platinum and crystal coins (value 1 / 100 / 10000)
  gear   a non-stackable item with an equipment slot or a weapon type (items.xml), not ammunition
  junk   anything else an NPC buys (data/lib/chaos_item_prices_data.lua prices), not on the unsellable list
  other  orbs, gems, keys, tokens and everything without a price (ChaosItemPrices.unsellable)

Weights are the pool's spawn counts. The output (default server/tools/loot_bands_data.lua) is sorted and has no date,
so a rerun on the same base data gives the same file; --check compares instead of writing. Only ids, numbers and the
pool's monster names are written.
"""
import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import respec_income as R  # noqa: E402  (its monster and item parsers)

# band level -> (lowest, highest) level on the hunting scale of the monsters it hunts: every base monster of the pool from
# level 40 (tools/loot_model.lua reads +-15% of a band, 100 to 650; the pool has no base monster above 657, O285: hunting
# level = pool level, so the old bands 800 to 1500 are gone)
BANDS = {40: (40, 100000)}
EXTRA = ["Nightfang Widow", "Shadowcrystal Widow"]
COINS = {2148: 1, 2152: 100, 2160: 10000}
GEAR_SLOTS = {"head", "body", "legs", "feet", "ring", "necklace", "two-handed", "shield", "hand"}
GEAR_WEAPONS = {"sword", "club", "axe", "distance", "wand", "shield", "fist"}
OUT = os.path.join(HERE, "loot_bands_data.lua")


def read(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def gear_ids(items_xml):
    """ids of items.xml entries with an equipment slot or a weapon type (ammunition left out)"""
    out = set()
    for m in re.finditer(r'<item\s+(?:id="(\d+)"|fromid="(\d+)"\s+toid="(\d+)")[^>]*?(/>|>(.*?)</item>)', items_xml, re.S):
        body = m.group(5) or ""
        st = re.search(r'key="slotType"\s+value="([^"]+)"', body)
        wt = re.search(r'key="weaponType"\s+value="([^"]+)"', body)
        if re.search(r'key="ammoType"', body) or (wt and wt.group(1) == "ammunition"):
            continue
        if (st and st.group(1).lower() in GEAR_SLOTS) or (wt and wt.group(1).lower() in GEAR_WEAPONS):
            ids = [int(m.group(1))] if m.group(1) else range(int(m.group(2)), int(m.group(3)) + 1)
            out.update(ids)
    return out


def price_tables(text):
    """(prices {id: gold}, unsellable ids) of chaos_item_prices_data.lua"""
    head, _, tail = text.partition("unsellable = {")
    prices = {int(a): int(b) for a, b in re.findall(r"\[(\d+)\]\s*=\s*(\d+)", head.partition("prices = {")[2])}
    return prices, set(int(a) for a in re.findall(r"\[(\d+)\]\s*=", tail))


def pool_entries(text):
    """(name, pool level, exp, health, spawns, minLevel, maxLevel) of the hunt list"""
    hunt = text.partition("bosses = {")[0]
    out = []
    for body in re.findall(r"\{(name = [^{}]*)\}", hunt):
        def num(k):
            m = re.search(r"\b%s = (\d+)" % k, body)
            return int(m.group(1)) if m else 0
        out.append((re.search(r'name = "([^"]+)"', body).group(1), num("level"), num("exp"), num("health"),
                    num("spawns"), num("minLevel"), num("maxLevel")))
    return out


def estimate_level(exp, health):
    """pace_core.lua P.estimateLevel (gen_bounty_pool.estimate_level)"""
    by_exp = 1.6 * (max(exp, 1) ** 0.5)
    by_hp = health / 60.0
    return max(1, int(max(by_exp, min(by_hp, by_exp * 1.5)) + 0.5))


def hunt_level(level, exp, health, min_l, max_l):
    """pace_core.lua P.entryLevel with baseLevelMult 1 (O285): (level on the hunting scale, level-scaled)"""
    if min_l > 0 and max_l >= min_l:
        return (min_l + max_l) // 2, True
    if level > 0 and estimate_level(exp, health) != level:
        return level, True
    return level or estimate_level(exp, health), False


def classify(iid, cmax, prices, unsellable, gear):
    if iid in COINS:
        return "coin", COINS[iid]
    price = prices.get(iid, 0)
    if iid in gear and cmax <= 1:
        return "gear", price
    if iid in unsellable or price <= 0:
        return "other", 0
    return "junk", price


def in_band(level):
    return any(lo <= level <= hi for lo, hi in BANDS.values())


def build(data, pool_text, prices_text):
    names = R.item_names(data)
    files = R.monster_files(data)
    gear = gear_ids(read(os.path.join(data, "items", "items.xml")))
    prices, unsellable = price_tables(prices_text)
    rows = []
    for name, level, exp, health, spawns, min_l, max_l in pool_entries(pool_text):
        hl, scaled = hunt_level(level, exp, health, min_l, max_l)
        if not (in_band(hl) or name in EXTRA):
            continue
        path = files.get(name.lower())
        if not path:
            continue
        _, _, loot = R.parse_monster(path, names)
        entries = []
        for iid, cmax, chance in loot:
            if chance <= 0:
                continue
            cls, price = classify(iid, cmax, prices, unsellable, gear)
            entries.append((iid, min(chance, 100000), max(1, cmax), cls, price))
        rows.append((name, hl, scaled, spawns, sorted(entries)))
    rows.sort(key=lambda r: (r[1], r[0]))
    return rows


def render(rows):
    out = ["-- Loot of the hunting bands: the input of tools/loot_model.lua (server/README.md \"Loot by monster level\").",
           "-- GENERATED by server/tools/loot_bands.py from an installed base server's data; do not edit by hand.",
           "-- {name, level on the hunting scale, level-scaled, pool spawns, loot = {{id, chance per 100000, max count,",
           "-- class (coin / gear / junk / other), NPC price}}}",
           "return {"]
    for name, hl, scaled, spawns, entries in rows:
        loot = ", ".join("{%d, %d, %d, \"%s\", %d}" % e for e in entries)
        out.append("\t{name = \"%s\", level = %d, scaled = %s, spawns = %d, loot = {%s}}," % (
            name, hl, "true" if scaled else "false", spawns, loot))
    out.append("}")
    return "\n".join(out) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("data")
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args(argv)
    text = render(build(args.data, read(os.path.join(SERVER, "data", "scripts", "chaos", "bounty_pool.lua")),
                        read(os.path.join(SERVER, "data", "lib", "chaos_item_prices_data.lua"))))
    if args.check:
        same = os.path.exists(args.out) and read(args.out) == text
        print("loot bands: " + ("up to date" if same else "OUT OF DATE (rerun without --check)"))
        return 0 if same else 1
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("wrote %s (%d monsters)" % (args.out, text.count("{name =")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
