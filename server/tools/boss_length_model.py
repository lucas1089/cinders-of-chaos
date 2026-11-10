#!/usr/bin/env python3
"""The boss lengths of the balance round (O475, owner 2026-11-10: "You can do everything"; computed, not measured).

usage: python3 -I server/tools/boss_length_model.py [--derive] [--check]

After the round (O470 to O474) the typical character deals more than the numbers the boss models were set with (the C4 median:
913 at level 300, 2,600 at 1000). This tool derives, from class_dps_model.py (the one source of class damage, after the round), the
numbers that give the bosses their planned length again, and --check holds the committed configs to them:

  dungeon bosses   150 s for the typical character of the level (the five generated dungeons): D.dps of dungeons_difficulty.lua is the
                   table below, healthMult of each boss is 150 s x D.dps(level + 25) / (file health x (1 + 0.0074 x boss level))
  rift guardian    55 s: rift_config.lua density.model dps1 / dps5 and their exponents, fitted to the same damage over the tiers'
                   minimum levels (the guardian's health follows: guardianSeconds x dps1 x guardianUptime; the packs keep their 225 s:
                   packSeconds, the same model on dps5)
  Omen guardian    5:18 solo at level 1000 (318 s with 380 healed a second at 75% uptime): the XML health of the three Omen guardians;
                   the Ascended Omens and the Cinderheart (XML health) and the models that fight them (uber_config.lua and
                   raid_config.lua refDps) and the five raid bosses (XML health) move by the same factor, so their documented times hold

The typical damage on one target is the median class at the level (class_dps_model.median_dps, 1 target) x the share a boss lets
through (BOSS_KEPT: the boss armour takes armourTarget.boss percent of the physical half, the resistance BOSS_RES of the elemental
half); on a pack it is the 5 target median x NORMAL_KEPT (armourTarget.normal, NORMAL_RES). BOSS_RES and NORMAL_RES are assumptions
(mean resistance of the monsters; the design's 30 and 15). Not in it: boss mechanics and the uptime, which the configs hold.

--derive   print the numbers (the table of D.dps, the five healthMult, the rift model, the Omen factor)
--check    exit 1 when a committed number is more than 1.5% (the Omen XML 0.5%) off its derivation
"""
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import class_dps_model as CD  # noqa: E402

SERVER = os.path.normpath(os.path.join(HERE, '..'))
CHAOS = os.path.join(SERVER, 'data', 'scripts', 'chaos')
DUNGEONS = os.path.join(CHAOS, 'dungeons_difficulty.lua')
AREAGEN = os.path.join(CHAOS, 'areagen_config.lua')
RIFT = os.path.join(CHAOS, 'rift_config.lua')
UBER = os.path.join(CHAOS, 'uber_config.lua')
RAID = os.path.join(CHAOS, 'raid_config.lua')
DEFENCE = os.path.join(CHAOS, 'monster_defence_config.lua')
PVP = os.path.join(CHAOS, 'pvp_balance_config.lua')
OMENS = os.path.join(SERVER, 'data', 'monster', 'monsters', 'chaos', 'omens')
ASCENDED = os.path.join(SERVER, 'data', 'monster', 'monsters', 'chaos', 'ascended')
RAIDS = os.path.join(SERVER, 'data', 'monster', 'monsters', 'chaos', 'raid')
RAID_OLD = {'gravewarden_ulthar.xml': 4000000, 'morwen_the_ash_sister.xml': 4400000, 'the_marrow_colossus.xml': 4800000,
            'vhoss_the_hexmaw.xml': 5000000, 'varkhul_the_ashen_sovereign.xml': 7200000}   # the XML health before O475

BOSS_RES, NORMAL_RES = 0.30, 0.15
DPS_LEVELS = (100, 200, 300, 500, 700, 850, 1000, 1500, 2000)
BOSS_SECONDS = 150          # a dungeon boss, solo, the typical character
GUARDIAN_SECONDS = 55       # a rift guardian (rift_config.lua density.model guardianSeconds)
OMEN_SECONDS = 318          # the Omen guardian solo at level 1000
OMEN_UPTIME, OMEN_HEAL = 0.75, 380   # uptime of the model and the guardian's heal a second (README "Solo kill times": 330-380)
OMEN_OLD = 500000           # the XML health before O475
ASCENDED_OLD, CINDER_OLD = 1200000, 1650000
REFDPS_OLD = 3000           # uber_config.lua / raid_config.lua model.refDps before O475
GEAR = 1.15                 # rift_config.lua density.model gear
# the five generated dungeons: id, player level (dungeon level + 25), boss level, file health (the monster file's, README "Solo kill times")
DUNGEON_BOSSES = (('vault', 825, 900, 14800), ('marrow', 1025, 1100, 15000), ('crucible', 1325, 1400, 15500),
                  ('sanctum', 1625, 1700, 16000), ('throne', 2025, 2100, 16000))


def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def kept(kind):
    """the share of a typical hit that gets through: armour on the physical half, resistance on the elemental half"""
    armour = int(re.search(r'armourTarget = \{[^}]*\b%s = (\d+)' % kind, read(DEFENCE)).group(1)) / 100.0
    share = float(re.search(r'physicalShare = ([0-9.]+)', read(PVP)).group(1))
    res = BOSS_RES if kind == 'boss' else NORMAL_RES
    return share * (1 - armour) + (1 - share) * (1 - res)


def one_target(level):
    """damage per second of the typical character on one boss"""
    return CD.median_dps(level)[0] * kept('boss')


def area(level):
    """damage per second of the typical character on 5 targets (a pack)"""
    return CD.median_dps(level)[1] * kept('normal')


def dps_table():
    return [(lv, one_target(lv)) for lv in DPS_LEVELS]


def table_dps(rows, level):
    """the log-linear rule of D.dps: straight in log level and log damage between rows, flat above the last, scaled by the level below the first"""
    if level <= rows[0][0]:
        return rows[0][1] * max(level, 1) / float(rows[0][0])
    for (x0, y0), (x1, y1) in zip(rows, rows[1:]):
        if level <= x1:
            return y0 * (y1 / y0) ** (math.log(level / float(x0)) / math.log(x1 / float(x0)))
    return rows[-1][1]


def health_mult(rows, level, boss_level, file_health, seconds=BOSS_SECONDS):
    return seconds * table_dps(rows, level) / (file_health * (1 + 0.0074 * boss_level))


def fit(values, levels, gear=GEAR):
    """value at level 1000 and the exponent of a power law v = a x (L / 1000) ^ e x gear through the points (least squares in the logs)"""
    xs = [math.log(l / 1000.0) for l in levels]
    ys = [math.log(v / gear) for v in values]
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    e = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sum((x - mx) ** 2 for x in xs)
    return math.exp(my - e * mx), e


def rift_levels():
    return [int(v) for v in re.findall(r'\{minLevel = (\d+), pick', read(RIFT))]


def rift_fit():
    lv = rift_levels()
    return fit([one_target(l) for l in lv], lv), fit([area(l) for l in lv], lv)


def omen_factor():
    health = (one_target(1000) * OMEN_UPTIME - OMEN_HEAL) * OMEN_SECONDS
    return health, health / OMEN_OLD


# ------------------------------------------------------------------------------------------------ committed numbers
def committed_dps():
    text = read(DUNGEONS)
    m = re.search(r'\n\tdps = (\{\{[^\n]*\}\})\}', text)
    return [(int(a), float(b)) for a, b in re.findall(r'\{(\d+),\s*([0-9.]+)\}', m.group(1))]


def committed_mults():
    text = read(AREAGEN)
    out = {}
    for m in re.finditer(r'id = "(\w+)", name = "[^"]*", kind = "dungeon".*?healthMult = ([0-9.]+)', text, re.S):
        out[m.group(1)] = float(m.group(2))
    return out


def committed_rift():
    text = read(RIFT)
    g = lambda k: float(re.search(r'\b%s = ([0-9.]+)' % k, text).group(1))
    return (g('dps1'), g('dps1Exp')), (g('dps5'), g('dps5Exp'))


def committed_health(folder):
    out = {}
    for f in sorted(os.listdir(folder)):
        if f.endswith('.xml'):
            m = re.search(r'<health now="(\d+)"', read(os.path.join(folder, f)))
            if m:
                out[f] = int(m.group(1))
    return out


def committed_refdps():
    return float(re.search(r'refDps = (\d+)', read(UBER)).group(1)), float(re.search(r'refDps = (\d+)', read(RAID)).group(1))


def lua_rows(rows):
    return '{' + ', '.join('{%d, %d}' % (lv, round(v)) for lv, v in rows) + '}'


def derive():
    rows = dps_table()
    print('D.dps rows (typical damage on one boss; median class x %.3f):' % kept('boss'))
    print('  ' + lua_rows(rows))
    print('\nhealthMult for %d s:' % BOSS_SECONDS)
    for name, lv, bl, hp in DUNGEON_BOSSES:
        print('  %-9s level %d: %.2f (health %.0f)' % (name, lv, health_mult([(l, round(v)) for l, v in rows], lv, bl, hp),
                                                      BOSS_SECONDS * table_dps(rows, lv)))
    (d1, e1), (d5, e5) = rift_fit()
    print('\nrift model: dps1 = %.0f, dps1Exp = %.2f, dps5 = %.0f, dps5Exp = %.2f (gear %.2f, tier levels %s)' % (
        d1, e1, d5, e5, GEAR, rift_levels()))
    h, f = omen_factor()
    print('\nOmen guardian health %.0f (x%.3f of %d): Ascended %.0f, Cinderheart %.0f, refDps %.0f' % (
        h, f, OMEN_OLD, ASCENDED_OLD * f, CINDER_OLD * f, REFDPS_OLD * f))
    return 0


def problems():
    bad = []
    rows = dps_table()
    have = committed_dps()
    if [lv for lv, _ in have] != list(DPS_LEVELS):
        bad.append('D.dps levels are %s, not %s' % ([lv for lv, _ in have], list(DPS_LEVELS)))
    else:
        for (lv, v), (_, c) in zip(rows, have):
            if abs(c / v - 1) > 0.015:
                bad.append('D.dps at %d is %.0f, the derivation %.0f' % (lv, c, v))
    mults = committed_mults()
    for name, lv, bl, hp in DUNGEON_BOSSES:
        want = health_mult(have, lv, bl, hp)
        if name not in mults or abs(mults[name] / want - 1) > 0.015:
            bad.append('%s healthMult is %s, 150 s on the committed D.dps is %.2f' % (name, mults.get(name), want))
    (c1, ce1), (c5, ce5) = committed_rift()
    (d1, e1), (d5, e5) = rift_fit()
    for name, have_v, want_v in (('dps1', c1, d1), ('dps5', c5, d5)):
        if abs(have_v / want_v - 1) > 0.015:
            bad.append('rift %s is %.0f, the derivation %.0f' % (name, have_v, want_v))
    for name, have_v, want_v in (('dps1Exp', ce1, e1), ('dps5Exp', ce5, e5)):
        if abs(have_v - want_v) > 0.015:
            bad.append('rift %s is %.2f, the derivation %.2f' % (name, have_v, want_v))
    health, factor = omen_factor()
    for f, v in committed_health(OMENS).items():
        if abs(v / health - 1) > 0.005:
            bad.append('Omen %s health %d, the derivation %.0f' % (f, v, health))
    for f, v in committed_health(ASCENDED).items():
        old = {'ysgrath_the_cinderheart.xml': CINDER_OLD}.get(f, ASCENDED_OLD if f.startswith('ascended_') else None)
        if old and abs(v / (old * factor) - 1) > 0.005:
            bad.append('%s health %d, the derivation %.0f' % (f, v, old * factor))
    for f, v in committed_health(RAIDS).items():
        if f in RAID_OLD and abs(v / (RAID_OLD[f] * factor) - 1) > 0.005:
            bad.append('raid boss %s health %d, the derivation %.0f' % (f, v, RAID_OLD[f] * factor))
    for name, v in zip(('uber', 'raid'), committed_refdps()):
        if abs(v / (REFDPS_OLD * factor) - 1) > 0.015:
            bad.append('%s refDps is %.0f, the derivation %.0f' % (name, v, REFDPS_OLD * factor))
    return bad


def main(argv):
    if '--derive' in argv:
        return derive()
    bad = problems()
    if '--check' in argv:
        for b in bad:
            print('FAIL ' + b)
        if not bad:
            print('boss length check: ok (dungeon bosses %d s, rift guardian %d s, Omen guardian %d s, from the typical damage after the round)' % (
                BOSS_SECONDS, GUARDIAN_SECONDS, OMEN_SECONDS))
        return 1 if bad else 0
    return derive()


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
