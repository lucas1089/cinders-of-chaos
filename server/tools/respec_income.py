#!/usr/bin/env python3
"""Gold income per hour of hunting at a few levels, the basis of the respec prices (respec_core.lua, README "Respec").

    python3 -I server/tools/respec_income.py <server>/data [--sell-prices PATH]

This is the unpaced model. Pack combat keeps its gold per hour (README "Pack combat (pace)"); the corpse rule by monster
level is checked against the pace rule of 2026-10-20 band by band by tools/loot_model.lua (its input written by
tools/loot_bands.py, which reuses the parsers below).

For each level the hunt is a set of monsters that are spawned in the loaded map (counted in <mapName>-spawn.xml) and
that the leveling model of the README ("The leveling model and the hours") puts there; level 1000 is the tier 3 set of
tools/late_game_spawns.csv (Nightglass Core). Per monster, from its loot table (XML or Lua monster file):
  coins      expected gold, crystal / platinum / gold coins, count x the stock level count multiplier
  items      expected NPC sell value of the other drops (data/scripts/chaos/sell_prices.lua, what the Auto Seller pays)
  chaos      the Chaos loot layer's extra rolls (loot_config.lua extraRolls x the tier spawn chances of monster_tiers.lua)
Kills per hour = 3600 x efficiency x area DPS / effective health (the engine's level health bonus included). The area DPS
is the average 5-target rotation DPS of data/spells/README.md (level 300 and 1000, linear in between and below) and the
efficiency the leveling model's 0.47; the late-game monsters are pulled 3 at a time (x0.75 of the 5-target DPS).
"""
import argparse
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_SERVER = os.path.dirname(HERE)

EFFICIENCY = 0.47
DPS_POINTS = [(300, 1804.0), (1000, 4337.0)]  # average "Total 5 targets" of the five vocations, data/spells/README.md
HEALTH_BONUS = 0.0074  # config.lua monsterBonusHealth
LEVEL_COUNT_MULT = [(5, 50, 1.15), (51, 100, 1.35), (101, 200, 1.65), (201, 300, 1.95), (301, 500, 2.25), (501, 10000, 2.70)]
# Chaos loot layer: P(tier) x extra rolls x count mult (monster_tiers.lua spawnChance, loot_config.lua)
CHAOS_EXTRA = 0.06 * 1 * 1.0 + 0.015 * 2 * 1.25 + 0.0025 * 3 * 1.5
COINS = {2148: 1, 2152: 100, 2160: 10000}

LEVELS = [100, 300, 500, 600, 1000]
# (name, from level, share of the 5-target DPS, monsters)
HUNTS = [
    ("Dragons", 100, 1.0, ["Dragon", "Dragon Lord", "Wyrm", "Hydra"]),
    ("Demons", 250, 1.0, ["Demon", "Hellspawn", "Behemoth", "Dark Torturer", "Juggernaut"]),
    ("Soul War", 500, 1.0, ["Infernal Demon", "Cleftfiend", "Rotten Golem", "Branchy Crawler", "Mould Phantom", "Infernal Phantom",
                "Druid's Apparition", "Knight's Apparition"]),
    ("Nightglass Core (late game tier 3)", 800, 0.75, ["Azure Dragon", "Golden Lord", "Lacewing Moth", "Jungle Beasts", "Lady bug", "Grindmaw the Mauler"]),
]


def dps_at(level):
    (l1, d1), (l2, d2) = DPS_POINTS
    return d1 + (d2 - d1) * (level - l1) / (l2 - l1)


def level_mult(level):
    for lo, hi, m in LEVEL_COUNT_MULT:
        if lo <= level <= hi:
            return m
    return 1.0


def read(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def item_names(data):
    names = {}
    for m in re.finditer(r'<item\s+id="(\d+)"[^>]*?name="([^"]*)"', read(os.path.join(data, "items", "items.xml"))):
        names.setdefault(m.group(2).lower(), int(m.group(1)))
    return names


def sell_prices(path):
    return {int(k): int(v) for k, v in re.findall(r"\[(\d+)\]\s*=\s*(\d+)", read(path))}


def monster_files(data):
    """lower name -> path, XML (monsters.xml) and Lua (monster.name / Game.createMonsterType)"""
    files = {}
    mdir = os.path.join(data, "monster")
    for name, f in re.findall(r'<monster\s+name="([^"]+)"\s+file="([^"]+)"', read(os.path.join(mdir, "monsters.xml"))):
        p = os.path.join(mdir, f)
        if not os.path.exists(p):
            continue  # the engine does not load it either (a file name in another case): not in the game
        files.setdefault(name.lower(), p)
    for root, _, fs in os.walk(os.path.join(mdir, "lua")):
        for f in fs:
            if f.endswith(".lua"):
                p = os.path.join(root, f)
                m = re.search(r'createMonsterType\("([^"]+)"\)', read(p))
                if m:
                    files.setdefault(m.group(1).lower(), p)
    return files


def parse_monster(path, names):
    text = read(path)
    loot = []
    if path.endswith(".xml"):
        health = int(re.search(r'<health\s+now="(\d+)"', text).group(1))
        lv = re.search(r'<level\s+min="(\d+)"\s+max="(\d+)"', text)
        level = (int(lv.group(1)) + int(lv.group(2))) / 2 if lv else 0
        block = re.search(r"<loot>(.*?)</loot>", text, re.S)
        for tag in re.findall(r"<item\s[^>]*>", block.group(1) if block else ""):
            iid = re.search(r'\bid="(\d+)"', tag)
            if iid:
                iid = int(iid.group(1))
            else:
                n = re.search(r'\bname="([^"]+)"', tag)
                iid = n and names.get(n.group(1).lower())
            if not iid:
                continue
            cmax = re.search(r'countmax="(\d+)"', tag)
            chance = re.search(r'chance="(\d+)"', tag)
            loot.append((iid, int(cmax.group(1)) if cmax else 1, int(chance.group(1)) if chance else 0))
    else:
        health = int(re.search(r"monster\.health\s*=\s*(\d+)", text).group(1))
        level = 0
        block = re.search(r"monster\.loot\s*=\s*\{(.*?)\n\}", text, re.S)
        for entry in re.findall(r"\{([^{}]*)\}", block.group(1) if block else ""):
            iid = re.search(r'id\s*=\s*(\d+)', entry)
            if iid:
                iid = int(iid.group(1))
            else:
                n = re.search(r'id\s*=\s*"([^"]+)"', entry) or re.search(r'name\s*=\s*"([^"]+)"', entry)
                iid = n and names.get(n.group(1).lower())
            if not iid:
                continue
            cmax = re.search(r"maxCount\s*=\s*(\d+)", entry)
            chance = re.search(r"chance\s*=\s*(\d+)", entry)
            loot.append((iid, int(cmax.group(1)) if cmax else 1, int(chance.group(1)) if chance else 0))
    return health, level, loot


def per_kill(loot, level, prices):
    mult = level_mult(level)
    coins = items = 0.0
    for iid, cmax, chance in loot:
        p = min(chance, 100000) / 100000.0
        count = max(1.0, math.floor((1 + cmax) / 2.0 * mult)) if cmax > 1 else 1.0
        if iid in COINS:
            coins += p * count * COINS[iid]
        else:
            items += p * count * prices.get(iid, 0)
    return coins, items


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("data")
    ap.add_argument("--sell-prices", default=os.path.join(REPO_SERVER, "data", "scripts", "chaos", "sell_prices.lua"))
    args = ap.parse_args()
    names = item_names(args.data)
    prices = sell_prices(args.sell_prices)
    files = monster_files(args.data)
    cfg = read(os.path.join(os.path.dirname(args.data), "config.lua"))
    mapname = re.search(r'mapName\s*=\s*"([^"]+)"', cfg).group(1)
    spawn = read(os.path.join(args.data, "world", mapname + "-spawn.xml"))
    hunts = []
    for hname, minlevel, aoe, monsters in HUNTS:
        rows = []
        for name in monsters:
            path = files.get(name.lower())
            if not path:
                print("not loaded by the server, left out:", name, file=sys.stderr)
                continue
            spawned = len(re.findall(r'name="%s"' % re.escape(name), spawn, re.I))
            health, mlevel, loot = parse_monster(path, names)
            coins, items = per_kill(loot, mlevel, prices)
            rows.append((name, spawned, health * (1 + HEALTH_BONUS * mlevel), coins, items))
        hunts.append((hname, minlevel, aoe, rows))
        print("%s (from level %d)" % (hname, minlevel))
        for name, spawned, h, c, i in rows:
            print("  %-22s spawned %4d  health %7.0f  coins/kill %7.0f  items/kill %7.0f" % (name, spawned, h, c, i))
    out = []
    for level in LEVELS:
        best = None
        print("level %d (area DPS %.0f):" % (level, dps_at(level) * EFFICIENCY))
        for hname, minlevel, aoe, rows in hunts:
            if minlevel > level:
                continue
            dps = dps_at(level) * aoe * EFFICIENCY
            # an even mix of the hunt's monsters: kills/h of the mix, gold per kill averaged over the mix
            seconds = sum(r[2] / dps for r in rows) / len(rows)
            kills = 3600 / seconds
            coins = kills * sum(r[3] for r in rows) / len(rows) * (1 + CHAOS_EXTRA)
            items = kills * sum(r[4] for r in rows) / len(rows) * (1 + CHAOS_EXTRA)
            print("  %-36s %5.0f kills/h  coins %10s  items %10s  total %10s" % (
                hname, kills, f"{coins:,.0f}", f"{items:,.0f}", f"{coins + items:,.0f}"))
            if not best or coins + items > best[1] + best[2]:
                best = (hname, coins, items, kills)
        out.append((level, best))
    print("\n| Level | Best hunt | Kills / h | Coins / h | Item sale value / h | Total / h | 30-45 min | 1-2 min |")
    print("|---|---|---|---|---|---|---|---|")
    for level, (hname, c, i, k) in out:
        t = c + i
        print("| %d | %s | %.0f | %s | %s | %s | %s-%s | %s-%s |" % (level, hname, k, f"{c:,.0f}", f"{i:,.0f}", f"{t:,.0f}",
            f"{t / 2:,.0f}", f"{t * 0.75:,.0f}", f"{t / 60:,.0f}", f"{t / 30:,.0f}"))

if __name__ == "__main__":
    main()
