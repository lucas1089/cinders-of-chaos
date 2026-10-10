#!/usr/bin/env python3
# Percent armour (engine patch 0016, server/README.md "Percent armour"): damage a player takes from typical monsters with
# the stock armour formula and with the percent formula, by a Monte Carlo of the real engine rules.
#
#   python3 -I server/tools/armor_sim.py <server>/data [--k 250] [--cap 80] [--seconds 20000] [--seed 1]
#
# What it models, as the engine does it (src/creature.cpp Creature::blockHit, src/game.cpp combatChangeHealth,
# src/monsters.cpp, src/player.cpp Player::getDefense):
#   * the monster's attacks from its XML: melee (min / max, or skill / attack: max = ceil(skill x attack x 0.05 +
#     attack x 0.5)), every `interval` ms, the spells with their `chance`; a value is min + (max - min) x clamp(N(0.5,
#     0.25), 0, 1) (the engine's normal_random); melee is blocked by defence and armour, a "physical" spell by armour only,
#     elemental attacks by neither (item absorbs are left out: the same in both formulas)
#   * defence (unchanged): at most one block per second (blockCount), damage - uniform(def / 2, def), with def = (shielding
#     / 4 + 2.23) x shield defence x 0.15 (fight mode balanced, factor 1.0 here)
#   * stock armour: armour > 3: damage - uniform(armour / 2, armour - (armour % 2 + 1)), at least 0
#   * percent armour: damage x (1 - min(cap, armour / (armour + K))), physical only, rounded like the engine
#   * the monster level bonus (config monsterBonusDamage = 0.0015 per level) multiplies the blocked hit
# Monsters: the bounty pool (data/scripts/chaos/bounty_pool.lua: hunting level and spawn count) of the repo, the 12
# monsters with the most spawns in each band; the late game band is the 17 level-scaled monsters of late_game_spawns.csv.
# Players: armour totals from the base items (tools note in the README) plus the rarity armour bonus, see PROFILES.
import argparse
import math
import os
import random
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_SERVER = os.path.dirname(HERE)

BANDS = [
    # name, player level, hunting level range of the monsters
    ("level 100", 100, (80, 130)),
    ("level 300", 300, (250, 360)),
    ("level 1000", 1000, None),  # the late-game monsters
]

# armour = the typical item armour of the level's gear (median of the five best per slot, tools: armorgear in the README)
# + the rarity bonus of the engine (item.cpp: +2..+7 per item at Rare..Mythic, +8..+19 at the top rarities);
# shield: its defence and the shielding skill (None = no shield)
PROFILES = {
    100: [("caster", 72, None), ("tank", 93, (37, 80))],
    300: [("caster", 96, None), ("tank", 118, (39, 100))],
    1000: [("caster", 140, None), ("tank", 200, (53, 130))],
}

BONUS_PER_LEVEL = 0.0015


def read(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def bounty_pool(server_dir):
    text = read(os.path.join(server_dir, "data/scripts/chaos/bounty_pool.lua"))
    hunt = text.split("bosses =")[0]
    out = []
    for m in re.finditer(r'\{name = "([^"]+)", level = (\d+), exp = (\d+), health = (\d+), spawns = (\d+)', hunt):
        out.append({"name": m.group(1), "level": int(m.group(2)), "spawns": int(m.group(5))})
    return out


def late_game(server_dir):
    names = []
    for line in read(os.path.join(server_dir, "tools/late_game_spawns.csv")).splitlines()[1:]:
        parts = line.split(",")
        if len(parts) >= 9 and parts[8] not in names:
            names.append(parts[8])
    return names


def monster_files(data_dir):
    reg = read(os.path.join(data_dir, "monster/monsters.xml"))
    files = {}
    for m in re.finditer(r'<monster\s+name="([^"]+)"\s+file="([^"]+)"', reg):
        files[m.group(1).lower()] = os.path.join(data_dir, "monster", m.group(2))
    # monsters written in Lua (data/monster/lua/**): Game.createMonsterType("Name")
    for root, _, names in os.walk(os.path.join(data_dir, "monster", "lua")):
        for fn in sorted(names):
            if fn.endswith(".lua"):
                path = os.path.join(root, fn)
                m = re.search(r'createMonsterType\(\s*"([^"]+)"', read(path))
                if m and m.group(1).lower() not in files:
                    files[m.group(1).lower()] = path
    return files


def parse_lua_monster(path):
    x = read(path)
    block = re.search(r"monster\.attacks\s*=\s*\{(.*?)\n\}", x, re.S)
    attacks = []
    for entry in re.findall(r"\{([^{}]*)\}", block.group(1) if block else ""):
        def field(key, default=None):
            m = re.search(r"\b" + key + r'\s*=\s*"?([A-Za-z_0-9.\- ]+?)"?\s*(,|$)', entry)
            return m.group(1).strip() if m else default
        name = (field("name") or "").lower()
        interval = int(float(field("interval", "2000")))
        chance = int(float(field("chance", "100")))
        if field("minDamage") is not None or field("maxDamage") is not None:
            lo, hi = abs(int(float(field("minDamage", "0")))), abs(int(float(field("maxDamage", "0"))))
        elif name == "melee" and field("skill") and field("attack"):
            skill, atk = int(float(field("skill"))), int(float(field("attack")))
            lo, hi = 0, math.ceil(skill * atk * 0.05 + atk * 0.5)
        else:
            continue
        if hi <= 0 and lo <= 0:
            continue
        ctype = field("type") or ""
        if name == "melee":
            kind, chance = "melee", 100
        elif name == "combat" and ctype == "COMBAT_PHYSICALDAMAGE":
            kind = "physical"
        elif name == "combat":
            kind = "element"
        else:
            continue
        attacks.append({"kind": kind, "lo": min(lo, hi), "hi": max(lo, hi), "interval": interval, "chance": chance})
    return 0, attacks


def attr(tag, key, default=None):
    m = re.search(r'\b' + key + r'="([^"]*)"', tag)
    return m.group(1) if m else default


def parse_monster(path):
    if path.endswith(".lua"):
        return parse_lua_monster(path)
    x = read(path)
    lvl = re.search(r'<level\s+min="(\d+)"\s+max="(\d+)"', x)
    level = (int(lvl.group(1)) + int(lvl.group(2))) / 2 if lvl else 0
    attacks = []
    block = re.search(r"<attacks>(.*?)</attacks>", x, re.S)
    for tag in re.findall(r"<attack\s[^>]*>", block.group(1) if block else ""):
        name = (attr(tag, "name") or "").lower()
        interval = int(attr(tag, "interval", "2000"))
        chance = int(attr(tag, "chance", "100"))
        if attr(tag, "min") is not None or attr(tag, "max") is not None:
            lo, hi = abs(int(attr(tag, "min", "0"))), abs(int(attr(tag, "max", "0")))
        elif name == "melee" and attr(tag, "skill") and attr(tag, "attack"):
            skill, atk = int(attr(tag, "skill")), int(attr(tag, "attack"))
            lo, hi = 0, math.ceil(skill * atk * 0.05 + atk * 0.5)
        else:
            continue
        if hi <= 0:
            continue
        if name == "melee":
            kind = "melee"
            chance = 100
        elif name in ("physical", "bleed"):
            kind = "physical"
        else:
            kind = "element"
        attacks.append({"kind": kind, "lo": min(lo, hi), "hi": max(lo, hi), "interval": interval, "chance": chance})
    return level, attacks


def normal_value(rng, lo, hi):
    v = min(1.0, max(0.0, rng.gauss(0.5, 0.25)))
    return int(round(lo + (hi - lo) * v))


def stock_armor(rng, damage, armor):
    if armor > 3:
        damage -= rng.randint(armor // 2, armor - (armor % 2 + 1))
    elif armor > 0:
        damage -= 1
    return max(0, damage)


def percent_armor(damage, armor, k, cap):
    if armor <= 0:
        return damage
    r = min(cap / 100.0, armor / float(armor + k))
    return max(0, damage - int(round(damage * r)))


def defend(rng, damage, shield, state):
    if not shield or state["blocks"] <= 0:
        return damage
    state["blocks"] -= 1
    sdef, skill = shield
    d = int((skill / 4.0 + 2.23) * sdef * 0.15)
    return max(0, damage - rng.randint(d // 2, d))


def simulate(rng, attacks, level, armor, shield, mode, k, cap, seconds):
    """damage per second taken from one monster (always in range, every attack fires)"""
    bonus = BONUS_PER_LEVEL * level
    total = phys = 0
    state = {"blocks": 2}
    for t_ms in range(0, seconds * 1000, 1000):
        state["blocks"] = min(2, state["blocks"] + 1)
        for a in attacks:
            if t_ms % a["interval"] != 0 or rng.randint(1, 100) > a["chance"]:
                continue
            dmg = normal_value(rng, a["lo"], a["hi"])
            if a["kind"] != "element":
                if a["kind"] == "melee":
                    dmg = defend(rng, dmg, shield, state)
                if dmg > 0:
                    dmg = stock_armor(rng, dmg, armor) if mode == "stock" else percent_armor(dmg, armor, k, cap)
            dmg += int(round(dmg * bonus))
            total += dmg
            if a["kind"] != "element":
                phys += dmg
    return total / seconds, phys / seconds


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("data", help="a server's data folder (monsters.xml and the monster files)")
    ap.add_argument("--k", type=float, default=250)
    ap.add_argument("--cap", type=float, default=80)
    ap.add_argument("--seconds", type=int, default=20000)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("-v", action="store_true", help="one line per monster")
    args = ap.parse_args()

    files = monster_files(args.data)
    pool = bounty_pool(REPO_SERVER)
    print("K = %g, cap = %g%%; reduction armour / (armour + K) at 50 / 100 / 150 / 200 armour: %s" % (
        args.k, args.cap, " / ".join("%.1f%%" % (100 * min(args.cap / 100, a / (a + args.k))) for a in (50, 100, 150, 200))))
    for band, plevel, rng_levels in BANDS:
        if rng_levels:
            cands = [m for m in pool if rng_levels[0] <= m["level"] <= rng_levels[1]]
            cands.sort(key=lambda m: -m["spawns"])
            names = [m["name"] for m in cands]
        else:
            names = late_game(REPO_SERVER)
        chosen = []
        for n in names:
            path = files.get(n.lower())
            if not path or not os.path.exists(path):
                continue
            level, attacks = parse_monster(path)
            if attacks:
                chosen.append((n, level, attacks))
            if rng_levels and len(chosen) >= 12:
                break
        print("\n== %s: %d monsters: %s" % (band, len(chosen), ", ".join(c[0] for c in chosen)))
        for prof, armor, shield in PROFILES[plevel]:
            sums = {"stock": [0, 0], "percent": [0, 0]}
            rows = []
            for n, level, attacks in chosen:
                r = {}
                for mode in ("stock", "percent"):
                    rng = random.Random(args.seed)
                    tot, phys = simulate(rng, attacks, level, armor, shield, mode, args.k, args.cap, args.seconds)
                    r[mode] = (tot, phys)
                    sums[mode][0] += tot
                    sums[mode][1] += phys
                rows.append((n, r))
            s, p = sums["stock"], sums["percent"]
            print("  %-6s armour %3d%s: damage/s per monster, average over the set: stock %.0f (physical %.0f), "
                  "percent %.0f (physical %.0f): total %+.1f%%, physical %+.1f%%" % (
                      prof, armor, (", shield %d / shielding %d" % shield) if shield else "",
                      s[0] / len(chosen), s[1] / len(chosen), p[0] / len(chosen), p[1] / len(chosen),
                      100.0 * (p[0] - s[0]) / max(1, s[0]), 100.0 * (p[1] - s[1]) / max(1, s[1])))
            if args.v:
                for n, r in rows:
                    print("      %-24s stock %6.0f  percent %6.0f" % (n, r["stock"][0], r["percent"][0]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
