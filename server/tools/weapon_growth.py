#!/usr/bin/env python3
"""The weapon growth of O472 (owner 2026-11-10: "You can do everything"; the damage design, section B5): the weapon values grow with
the level. One table, one rule, shared by the install tools and the models.

W(level) is the factor on the weapon term of a hit: 1.00 up to level 100, 1.14 at 200, 1.26 at 300, 1.42 at 500, 1.55 at 700, 1.85 at
850, 2.20 at 1000, 2.35 at 1500, 2.60 at 2000, straight in the logarithm of the level between the rows (so W is smooth and rises by
at most 1.082 over 50 levels), flat above 2000. Skill x attack is about 85% of a weapon hit, so the attack of a weapon grows by
a = 1 + (W - 1) / 0.85.

The same table is in server/data/scripts/chaos/spell_scaling_config.lua `weaponGrowth` (the Lua side: the caster factor); tests/
weapon_growth_test.lua and tools/weapon_growth_test.py hold the two equal. Plain Python, no state.
"""
import math

WEAPON_GROWTH = ((100, 1.00), (200, 1.14), (300, 1.26), (500, 1.42), (700, 1.55), (850, 1.85), (1000, 2.20), (1500, 2.35),
                 (2000, 2.60))
WEAPON_SKILL_SHARE = 0.85   # skill x attack is about this share of a weapon hit

# the attack of the uniques of data/items/chaos_items.xml before O472, keyed by the stock base id the unique is made from (only the ones
# the growth changed): the `old` of chaos_weapon_growth.lua's uniques, so an owned unique can follow (ChaosCrafting.growWeapon).
# 7408 is the Misericorde of the Pale Vow, on 27193 until O505: an old copy turns into 7408 first (chaos_jewelry.lua uniqueMoves)
OLD_UNIQUE_ATTACK = {
    2404: 56, 2408: 78, 2411: 64, 7384: 50, 7402: 56, 7404: 42, 7408: 68, 7418: 44, 7422: 54, 8209: 52, 8925: 58, 8931: 72,
    14334: 76, 22417: 88, 25418: 62, 25880: 73, 25881: 74, 25882: 77, 25884: 78, 25885: 91, 25886: 92, 26765: 83,
    27230: 75, 27474: 78, 27646: 73, 27658: 58, 36659: 64, 40011: 68, 40012: 70
}


def weapon_w(level):
    """W(level): 1.00 up to level 100, straight in the logarithm of the level between the rows, flat above 2000"""
    pts = WEAPON_GROWTH
    if level <= pts[0][0]:
        return pts[0][1]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        if level <= x1:
            return y0 + (y1 - y0) * math.log(level / float(x0)) / math.log(x1 / float(x0))
    return pts[-1][1]


def weapon_a(level):
    """the growth of a weapon's attack: a = 1 + (W - 1) / 0.85"""
    return 1 + (weapon_w(level) - 1) / WEAPON_SKILL_SHARE


def grown(attack, level):
    """a whole attack value of the level times a (round half up)"""
    return int(attack * weapon_a(level) + 0.5)


# ------------------------------------------------------------------------------------------------ the stock weapons' marker comments
# tools/patch_stock_weapon_growth.py keeps the numbers of the stock weapons before the growth in one comment at the end of items.xml
# (id, attack, element damage) and one at the end of weapons.xml (id, min, max); the step and tools/survey_base_weapons.py read them back
ITEMS_BEGIN = '\t<!-- Chaos weapon growth O472 (server/tools/patch_stock_weapon_growth.py, do not edit by hand): the attack and element damage before it. id attack key=value ...\n'
WANDS_BEGIN = '\t<!-- Chaos weapon growth O472 (server/tools/patch_stock_weapon_growth.py, do not edit by hand): the wand damage before it. id min max\n'
END = '\t-->\n'


def block_span(text, begin):
    """(start, end) of a marker comment in an XML text, None without one"""
    s = text.find(begin)
    if s < 0:
        return None
    e = text.find(END, s)
    if e < 0:
        raise SystemExit('growth block without its end')
    return s, e + len(END)


def read_items_block(text):
    """{id: (attack, {element key: value})} of the marker comment of items.xml (empty without one)"""
    span = block_span(text, ITEMS_BEGIN)
    out = {}
    if not span:
        return out
    for line in text[span[0] + len(ITEMS_BEGIN):span[1] - len(END)].splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0].isdigit():
            out[int(parts[0])] = (int(parts[1]), {k: int(v) for k, v in (p.split('=') for p in parts[2:])})
    return out


def read_wands_block(text):
    """{id: (min, max)} of the marker comment of weapons.xml"""
    span = block_span(text, WANDS_BEGIN)
    out = {}
    if not span:
        return out
    for line in text[span[0] + len(WANDS_BEGIN):span[1] - len(END)].splitlines():
        parts = line.split()
        if len(parts) == 3 and all(p.isdigit() for p in parts):
            out[int(parts[0])] = (int(parts[1]), int(parts[2]))
    return out
