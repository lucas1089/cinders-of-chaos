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

Weights are the pool's spawn counts.

O751: `--late` needs no base server. Every pool monster above the base pool (hunting level 658 and up, the level-scaled
monsters of the planned and late hunts) is one of our own monster files (data/monster/**), so the loot of the late bands
is read from the repository: the monster files, the item prices and the gear ids of chaos_item_prices_data.lua (an entry
given by name instead of id is left out and counted). Output tools/loot_bands_late_data.lua, the late bands of
tools/loot_model.lua (800 to 2500).

    python3 -I server/tools/loot_bands.py --late [--check] The output (default server/tools/loot_bands_data.lua) is sorted and has no date,
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
OUT_LATE = os.path.join(HERE, "loot_bands_late_data.lua")
LATE_FROM = 658  # the first hunting level above the base pool (O285: the base pool ends at 657)


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


def gear_table(text):
    """ids of the `gear = {` block of chaos_item_prices_data.lua (equipment: rarity and item level price it)"""
    block = text.partition("gear = {")[2].partition("}")[0]
    return set(int(a) for a in re.findall(r"\[(\d+)\]\s*=", block))


def repo_monster_files(data):
    """lower name -> path of every monster file of the repository (XML <monster name=...> or Lua createMonsterType)"""
    files = {}
    for root, dirs, fs in os.walk(os.path.join(data, "monster")):
        dirs.sort()
        for f in sorted(fs):
            if not (f.endswith(".xml") or f.endswith(".lua")):
                continue
            p = os.path.join(root, f)
            t = read(p)
            m = re.search(r'<monster\s+name="([^"]+)"', t) or re.search(r'createMonsterType\("([^"]+)"\)', t)
            if m:
                files.setdefault(m.group(1).lower(), p)
    return files


def build_late(data, pool_text, prices_text):
    """(rows, missing monsters, entries by name left out): the pool monsters of hunting level LATE_FROM and up"""
    files = repo_monster_files(data)
    gear = gear_table(prices_text)
    prices, unsellable = price_tables(prices_text)
    rows, missing, by_name = [], [], 0
    for name, level, exp, health, spawns, min_l, max_l in pool_entries(pool_text):
        hl, _scaled = hunt_level(level, exp, health, min_l, max_l)
        if hl < LATE_FROM:
            continue
        path = files.get(name.lower())
        if not path:
            missing.append(name)
            continue
        if path.endswith(".xml"):
            block = re.search(r"<loot>(.*?)</loot>", read(path), re.S)
            tags = re.findall(r"<item\s[^>]*>", block.group(1) if block else "")
            by_name += sum(1 for t in tags if not re.search(r'\bid="\d+"', t))
        _, _, loot = R.parse_monster(path, {})
        entries = []
        for iid, cmax, chance in loot:
            if chance <= 0:
                continue
            cls, price = classify(iid, cmax, prices, unsellable, gear)
            entries.append((iid, min(chance, 100000), max(1, cmax), cls, price))
        rows.append((name, hl, True, spawns, sorted(entries)))
    rows.sort(key=lambda r: (r[1], r[0]))
    return rows, missing, by_name


def render(rows, late=False):
    out = ["-- Loot of the hunting bands: the input of tools/loot_model.lua (server/README.md \"Loot by monster level\").",
           ("-- GENERATED by server/tools/loot_bands.py --late from the repository's own monster files (O751: the late\n"
            "-- bands, hunting level %d and up, every monster level-scaled); do not edit by hand." % LATE_FROM) if late else
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
    ap.add_argument("data", nargs="?")
    ap.add_argument("--out")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--late", action="store_true")
    args = ap.parse_args(argv)
    if args.late:
        args.out = args.out or OUT_LATE
        rows, missing, by_name = build_late(os.path.join(SERVER, "data"),
                                            read(os.path.join(SERVER, "data", "scripts", "chaos", "bounty_pool.lua")),
                                            read(os.path.join(SERVER, "data", "lib", "chaos_item_prices_data.lua")))
        for name in missing:
            print("no monster file in the repository, left out: %s" % name, file=sys.stderr)
        if by_name:
            print("%d loot entries given by name, left out" % by_name, file=sys.stderr)
        text = render(rows, late=True)
    elif not args.data:
        ap.error("BASE_DATA is needed (or --late)")
        return 2
    else:
        args.out = args.out or OUT
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
