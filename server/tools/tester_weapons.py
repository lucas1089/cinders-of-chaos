#!/usr/bin/env python3
"""The weapon a class hits with (O665; server/README.md "The rest of the closed audit (O589)" step 24). Pure functions, no engine, no database.

The pick of the weapon (tester_checks.py weapon_pick) went by item level. A weapon SPELL reads the physical attack of the weapon in the hand and
nothing else (data/spells/chaos/_common.lua meleeAttack / distanceAttack: skill x attack, never under 20), a caster's spell reads the wand's mean
damage (spell_scaling_config.lua: the growth factor x min(1.2, wand / the level's mean wand)). The melee equipment sets from level 600 to 999 carry most
of their attack as an ELEMENT (sanguine blade: attack 13, fire 73; soulcutter: attack 10, death 64): the auto attack counts it, a spell does not, so a
bot of level 800 that wears one casts with skill x 20 where a weapon of the level has skill x 112 (install_gear_sets.py WEAPON_CURVES). The bot reads
the numbers from the server's own files, as it reads the equip rules.

Run the tests: python3 -I server/tools/testers_test.py"""
import os
import re

WEAPON_KIND = {'Warrior': 'melee', 'Juggernaut': 'melee', 'Berserker': 'melee', 'Thief': 'melee', 'Ninja': 'melee', 'Samurai': 'melee',
               'Templar': 'melee', 'Inquisitor': 'melee', 'Sentinel': 'melee', 'Ranger': 'distance', 'Deadeye': 'distance', 'Beastmaster': 'distance',
               'Mystic': 'wand', 'Elementalist': 'wand', 'Illusionist': 'wand', 'Necromancer': 'wand', 'Lich': 'wand', 'Bone Lord': 'wand'}
WEAPON_TYPES = {'sword': 'melee', 'axe': 'melee', 'club': 'melee', 'distance': 'distance', 'wand': 'wand'}   # items.xml weaponType -> the kind it serves
WEAPON_MARGIN = 1.10      # a weapon is better when its power is 10 % over the worn one's (a tie keeps the weapon in the hand)
WEAPON_FLOOR = 20         # a spell never reads an attack under 20 (an empty hand)


def load_weapon_stats(server_dir):
    """{item id: {'type': items.xml weaponType, 'attack': items.xml attack, 'wand': mean of the wand's min and max (weapons.xml)}} of the installed
    server, {} when items.xml cannot be read"""
    out = {}
    try:
        with open(os.path.join(server_dir, 'data', 'items', 'items.xml'), encoding='latin-1') as f:
            text = f.read()
    except OSError:
        return out
    for m in re.finditer(r'<item\s+id="(\d+)"[^>]*?>(.*?)</item>', text, re.S):
        attrs = {k.lower(): v for k, v in re.findall(r'<attribute\s+key="(\w+)"\s+value="([^"]*)"', m.group(2))}
        wt = attrs.get('weapontype')
        if wt in WEAPON_TYPES:
            try:
                attack = int(attrs.get('attack') or 0)
            except ValueError:
                attack = 0
            out[int(m.group(1))] = {'type': wt, 'attack': attack, 'wand': 0.0}
    try:
        with open(os.path.join(server_dir, 'data', 'weapons', 'weapons.xml'), encoding='latin-1') as f:
            wtext = f.read()
    except OSError:
        return out
    for m in re.finditer(r'<wand\s+id="(\d+)"[^>]*?\bmin="(\d+)"[^>]*?\bmax="(\d+)"', wtext):
        row = out.get(int(m.group(1)))
        if row is not None:
            row['wand'] = (int(m.group(2)) + int(m.group(3))) / 2.0
    return out


def weapon_power(stats, item_id, cls):
    """what the weapon is worth to the class's spells: the physical attack for a melee class (a sword, axe or club), the bow's attack for a distance
    class, the wand's mean damage for a caster; 0 for a weapon of another kind (a bow in the hand of a Warrior); None when the class has no rule
    (the fist classes) or the weapon is not in `stats`: the bot then goes by item level as before"""
    kind = WEAPON_KIND.get(cls)
    row = (stats or {}).get(item_id) if item_id is not None else None
    if kind is None or row is None:
        return None
    if WEAPON_TYPES.get(row.get('type')) != kind:
        return 0.0
    if kind == 'wand':
        return float(row.get('wand') or 0.0)
    return float(max(WEAPON_FLOOR, row.get('attack') or 0))


def weapon_beats(power, worn_power):
    """True when a weapon of `power` is worth wearing instead of one of `worn_power` (WEAPON_MARGIN over it); None when either is unknown (go by item
    level)"""
    if power is None or worn_power is None:
        return None
    return power > worn_power * WEAPON_MARGIN


# The plan of the gear sets (install_gear_sets.py WEAPON_CURVES, anchors 8 .. 2000): the attack of a one-handed melee weapon, a launcher, the mean damage of
# a wand. The melee sets give 35 % of that attack as an element (ELEMENT_SHARE), so the physical part a spell reads is 65 % of it.
PLAN_ANCHORS = (8, 50, 100, 200, 300, 400, 500, 700, 850, 1000, 1500, 2000)
PLAN_CURVES = {'melee': (16, 40, 46, 57, 67, 75, 81, 94, 118, 147, 168, 199), 'distance': (31, 38, 68, 83, 94, 103, 111, 125, 155, 191, 212, 245),
               'wand': (16, 40, 62, 99, 119, 138, 151, 178, 226, 285, 331, 398)}
PLAN_PHYSICAL = {'melee': 0.65, 'distance': 1.0, 'wand': 1.0}
PLAN_SHARE = 0.5          # a weapon under half of what a set weapon of the level gives is worth fresh crates of the Gambler


def plan_power(level, cls):
    """what a weapon of the level's plan is worth to the class's spells (the physical part), None for a class with no rule"""
    kind = WEAPON_KIND.get(cls)
    if kind is None:
        return None
    level = max(PLAN_ANCHORS[0], min(PLAN_ANCHORS[-1], float(level or 0)))
    pts = list(zip(PLAN_ANCHORS, PLAN_CURVES[kind]))
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        if level <= x1:
            return (y0 + (y1 - y0) * (level - x0) / float(x1 - x0)) * PLAN_PHYSICAL[kind]
    return pts[-1][1] * PLAN_PHYSICAL[kind]


def power_short(power, level, cls):
    """True when the weapon in the hand is under PLAN_SHARE of the plan of the level (False when it is not, or the power or the class is not known)"""
    plan = plan_power(level, cls)
    return power is not None and plan is not None and power < PLAN_SHARE * plan
