#!/usr/bin/env python3
"""Class DPS balance (O430): every class within +-25% of the level median on 1 target and on 5 targets (+-30% at level 100).

usage: python3 -I server/tools/class_dps_model.py [--check] [--before | --round-before | --steps | --spread] [--csv]

Owner, 2026-11-06: "balance the classes that are far from the median DPS". The anchor is a measured DPS test of all 21 classes at
levels 100, 500 and 1000 (server/data/spells/class_dps_measured.csv: one character per class and level, the same gear rule, the
passive tree build of the class, the helper's Auto setup rotation, 60 s on training dummies, 1 target and 5 targets; the
"every spell" column is the same rotation with every rule cast on one target, which is what the helper does since O430).
The test ran BEFORE O429 (faster auto attacks) and before the numbers of this change.

The model (computed, not measured): the table's numbers moved by the changes made since the test:
  1 target   = every-spell 1 target x (1 - f1 + f1 x r) x m
  5 targets  = helper 5 targets      x (1 - f5 + f5 x r) x m x (1 + w5 x (x - 1))
  r  the auto attack gain of O429, old base attack interval / new (chaos_vocations*.xml; attack_rate_config.lua trainOld)
  f1, f5  the auto attack's share of the measured damage (rotation_sim.py spell damage of the cast rotation next to
          weapon_sim.py's auto attack of the class's weapon kind, snapshot in the csv; 1 target and 5 targets)
  m  the class damage factor now / then (class_tree.lua classDamage, the csv holds "then")
  w5 the share of the measured 5 target damage that is a spell hit on a target other than the first of its cast (snapshot
     in the csv), x the extra target factor (spell_factor_config.lua `extra`, rotation_sim.py extra_factor)
No other changes are modelled (a retuned gear set, a tree change); the weights are the model's guess and the measurement spread
was +-5% to +-15%, so the check keeps a class inside the band, not on a number.
--check   exit 1 when a class is outside its band at one of the levels or the table has a hole
--before  print the measured table before the change (helper mode, the state the owner saw)
--round-before  print the model before the balance round of O470 to O474 (the measured table moved by O429 and the class factors,
          which is what this file computed until O475)
--steps   print the factor of each step of the round per class at the levels of ROUND_LEVELS, then the medians
--spread  print the fresh / typical / invested damage of the median class (O475, rough: the pool, the gear and the critical hit)

O444 (2026-11-09): this file is the ONE source of class damage for the balance models. boss_model.py, pack_model.py and
tower_model.py read `dps(class, level)` and `median_dps(level)` below, not a table of their own (they carried the C4
measurement of 2026-10-11, which is older than O430 and put the Sentinel at 1.80 of the Deadeye on a boss while this model
has it at -14% of the median on 1 target). `dps` is the model at the three measured levels and, between and outside them,
a straight line in the logarithm of level and damage (below 100 and between the anchors), then 0.093% a level above 1000
(the old rule: 2.41 a level over the C4 median 2598 at level 1000; the 500 to 1000 slope of this table is 0.096%). Computed,
not measured, as everything here.
"""
import csv
import math
import os
import re
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
import rotation_sim as R  # noqa: E402

CSV = os.path.join(REPO, 'server', 'data', 'spells', 'class_dps_measured.csv')
CLASS_TREE = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'class_tree.lua')
ATTACK_RATE = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'attack_rate_config.lua')
VOCATION_XMLS = [os.path.join(REPO, 'server', 'data', 'XML', n) for n in
                 ('chaos_vocations.xml', 'chaos_vocations_monk.xml', 'chaos_vocations_necro.xml', 'chaos_vocations_templar.xml')]
LEVELS = (100, 500, 1000)
BAND = {100: 0.30, 500: 0.25, 1000: 0.25}
# the class key of class_tree.lua classDamage
KEY = {'Warrior': 'warrior', 'Juggernaut': 'juggernaut', 'Berserker': 'berserker', 'Ranger': 'ranger', 'Deadeye': 'deadeye',
       'Beastmaster': 'beastmaster', 'Mystic': 'mystic', 'Elementalist': 'elementalist', 'Illusionist': 'illusionist',
       'Thief': 'thief', 'Ninja': 'ninja', 'Samurai': 'samurai', 'Necromancer': 'necromancer', 'Lich': 'lich',
       'Bone Lord': 'bonelord', 'Monk': 'monk', 'Shadowfist': 'shadowfist', 'Iron Sage': 'ironsage', 'Templar': 'templar',
       'Inquisitor': 'inquisitor', 'Sentinel': 'sentinel'}


def load_rows(path=CSV):
    out = {}
    with open(path, encoding='utf-8') as f:
        for r in csv.DictReader(f):
            out[(r['class'], int(r['level']))] = {k: float(v) for k, v in r.items() if k not in ('class', 'level')}
    return out


def class_damage(path=CLASS_TREE):
    """{class key: [(level, factor), ...]} of class_tree.lua classDamage"""
    text = open(path, encoding='utf-8').read()
    block = text.split('M.classDamage = {', 1)[1].split('\n}', 1)[0]
    out = {}
    for m in re.finditer(r'^\t(\w+) = (\{\{[^\n]*\}\}),', block, re.M):
        out[m.group(1)] = [(int(a), float(b)) for a, b in re.findall(r'\{(\d+),\s*([0-9.]+)\}', m.group(2))]
    return out


def intervals():
    """({vocation id: base attack interval ms now}, {vocation id: ms before O429}) from the vocation XMLs and attack_rate_config.lua"""
    now = {}
    for p in VOCATION_XMLS:
        for m in re.finditer(r'<vocation id="(\d+)"[^>]*?attackspeed="(\d+)"', open(p, encoding='utf-8').read()):
            now[int(m.group(1))] = int(m.group(2))
    text = open(ATTACK_RATE, encoding='utf-8').read()
    default = int(re.search(r'trainDefault = (\d+)', text).group(1))
    old = {int(a): int(b) for a, b in re.findall(r'\[(\d+)\] = (\d+)', re.search(r'trainOld = \{([^}]*)\}', text).group(1))}
    return now, {v: old.get(v, default) for v in now}


def model(rows=None, damage=None, interval=None, extra=None, rnd=True):
    """{(class, level): {'1t': dps, '5t': dps, ...}} and {level: (median 1t, median 5t)}. rnd (O475): the numbers after the balance round
    (round_factor() at the measured level; 'pre1' and 'pre5' keep the model before it); rnd=False is the model before the round"""
    rows = rows or load_rows()
    damage = damage or class_damage()
    now, old = interval or intervals()
    extra = extra or R.extra_factor
    out, med = {}, {}
    for lv in LEVELS:
        for cls in KEY:
            r = rows[(cls, lv)]
            voc = R.VOC[cls]
            gain = old[voc] / float(now[voc])
            m = R.interp(damage[KEY[cls]], lv) / r['class_damage_before']
            x = extra(cls, lv)
            one = r['every_spell_1t'] * (1 - r['auto_share_1t'] + r['auto_share_1t'] * gain) * m
            five = r['helper_5t'] * (1 - r['auto_share_5t'] + r['auto_share_5t'] * gain) * m * (1 + r['extra_share_5t'] * (x - 1))
            out[(cls, lv)] = {'1t': one, '5t': five, 'm': m, 'x': x, 'gain': gain, 'pre1': one, 'pre5': five, 'r1': 1.0, 'r5': 1.0}
            if rnd:
                r1, r5 = round_factor(cls, lv)
                out[(cls, lv)].update({'1t': one * r1, '5t': five * r5, 'r1': r1, 'r5': r5})
        med[lv] = (statistics.median(out[(c, lv)]['1t'] for c in KEY), statistics.median(out[(c, lv)]['5t'] for c in KEY))
    return out, med


def problems(out=None, med=None):
    if out is None:
        out, med = model()
    bad = []
    for lv in LEVELS:
        for cls in KEY:
            for i, name in ((0, '1t'), (1, '5t')):
                d = out[(cls, lv)][name] / med[lv][i] - 1
                if abs(d) > BAND[lv]:
                    bad.append('%s level %d, %s: %+.0f%% of the median (band +-%.0f%%)' % (cls, lv, name, d * 100, BAND[lv] * 100))
    return bad


# ---- O475: the balance round (O470 to O474) as named steps ----------------------------------------------------------------
# The measured table and the factors above are the typical character BEFORE the round. The round changed the damage of a player in
# four ways that the table cannot see; each is a step below, a factor on the class damage computed from the real files of the
# repo (never a number copied from the design), 1 target and 5 targets, at any level (a straight line in log level and log factor
# between ROUND_LEVELS, flat outside). round_factor() multiplies them. `dps()` and `median_dps()` apply it, so every balance model
# that reads them sees the typical damage after the round; `model(rnd=False)`, `shipped_before()` and `dps(..., rnd=False)` are
# the numbers before (--round-before).
#   weapon  O472: W(level) (weapon_growth.py) through the weapon attack (weapon classes and hybrids: the attack and the fist times
#           a(level), the wolf bite times W) and through the caster factor (the six caster classes: every Chaos spell times W; a
#           stock spell of the base scripts does not take it; Necromancer minions take it too and are part of the class number),
#           and the auto attack (the attack of the weapon, the power factors of weapon_power_config.lua). Healing: never. Computed
#           with rotation_sim.grown_stats() on the harness of the measured table (every Chaos attack spell of the class on cooldown)
#           and the auto attack of the class's weapon kind, as the weighted sum: (spells + auto) after / (spells + auto) before.
#   dots    O474: the six spells whose damage over time rose (rotation_sim.LADDER_HOLD holds their damage of before) and the
#           ailments of gear are not modelled beyond the rows: the same harness with the rows of before against the rows now. The
#           model counts a dot in full, so it is the model's number; what lands on one hunt monster moved more (README "Damage over
#           time (O474)"). The kit's other dots keep their totals.
#   gear    O471: the item level curve, the tier tilt: the mean Weapon Damage (weapon classes and hybrids, on the weapon term at
#           WEAPON_SKILL_SHARE) or Spell Damage (casters, in the pool: through the soft cap) of a Rare drop of the level, now against
#           before (the curve and equal weights of before O471 are BEFORE_O471 below). The critical caps (45 chance, 150 extra) and the
#           rune ceiling (level 4) do not touch the typical character: it holds one critical slot and runes below level 4 (CRIT_STEP).
#   pool    O473: the one additive pool against the old product of sources, for the typical profile of tools/damage_pool_table.lua
#           (server/data/spells/pool_typical.csv, written by `luajit tools/damage_pool_table.lua --csv`): a tree supply of 25 raw at 100
#           to 170 at 2000, one unique power of 30%, a 12% gem, charms 3%, Paragon at half. The profile is assumed, not measured, and the
#           same for every class: what the pool does to a class with a rich or a poor tree (the design's Mystic +24%, Berserker +5%)
#           is not modelled. This is the largest step and the least certain one.
# Not modelled: the pvp scale (pvp_model.py applies it), skill growth above level 1000 (O475 does not do it, owner's optional item),
# the unique passives' prices and the cards, which the typical profile has no part of.
ROUND_LEVELS = (100, 200, 300, 500, 700, 850, 1000, 1500, 2000)
ITEM_MODS = os.path.join(REPO, 'server', 'data', 'lib', 'chaos_item_mods.lua')
POOL_CONFIG = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'damage_pool_config.lua')
POOL_CSV = os.path.join(REPO, 'server', 'data', 'spells', 'pool_typical.csv')
POWER_CONFIG = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'weapon_power_config.lua')
# the item level curve and tier weights before O471 (chaos_item_mods.lua, git history: the commit "O471: item level curve, tier tilt")
BEFORE_O471 = {
    'curve': [(1, 1), (10, 5), (25, 12), (50, 22), (100, 36), (200, 54), (350, 74), (500, 90), (700, 106), (900, 118), (1100, 128),
              (1500, 136), (3000, 142), (6000, 145)],
    'weights': [100] * 8,
}
CRIT_STEP = 1.0     # the typical character is nowhere near a cap of 45 / 150: see the header
RARE_DROP = 'rare'  # the typical character wears Rare drops of its level (Rare +4 on the item level)
_ROUND = {}


def _lin_log(points, x):
    """a straight line in log(x) and log(y) between points [(x, y), ...]; flat outside"""
    if x <= points[0][0]:
        return points[0][1]
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        if x <= x1:
            return y0 * (y1 / y0) ** (math.log(x / float(x0)) / math.log(x1 / float(x0)))
    return points[-1][1]


def item_mods_config(path=ITEM_MODS):
    """{'curve', 'tier_levels', 'weights', 'rare', 'weapon_damage', 'spell_damage'} read from chaos_item_mods.lua"""
    text = open(path, encoding='utf-8').read()

    def pairs(body):
        return [(int(a), int(b)) for a, b in re.findall(r'\{(\d+),\s*(\d+)\}', body)]
    curve = re.search(r'itemLevel = \{.*?curve = \{(.*?)\},\s*\n\s*tierBonus', text, re.S).group(1)
    levels = re.search(r'tierLevels = \{([^}]*)\}', text).group(1)
    weights = re.search(r'tierWeights = \{([^}]*)\}', text).group(1)
    bonus = re.search(r'tierBonus = \{[^}]*rare = (\d+)', text).group(1)

    def tiers(key):
        m = re.search(r'key = "%s".*?tiers = \{(.*?)\}\}' % key, text, re.S)
        return pairs(m.group(1) + '}')
    return {'curve': pairs(curve), 'tier_levels': [int(v) for v in levels.split(',')], 'weights': [int(v) for v in weights.split(',')],
            'rare': int(bonus), 'weapon_damage': tiers('weapondamage'), 'spell_damage': tiers('spelldamage')}


def mean_modifier(level, tiers, cfg=None, before=False):
    """the mean value of a weapon modifier on a Rare drop of a hunting level: the item level is the curve at the level + the Rare
    addition, the tiers it allows weigh in with tierWeights, each at the middle of its range"""
    cfg = cfg or item_mods_config()
    curve = BEFORE_O471['curve'] if before else cfg['curve']
    weights = BEFORE_O471['weights'] if before else cfg['weights']
    il = int(R.interp(curve, level) + 0.5) + cfg['rare']
    top = max(1, sum(1 for g in cfg['tier_levels'] if il >= g))
    w = weights[:top]
    return sum(wi * (lo + hi) / 2.0 for wi, (lo, hi) in zip(w, tiers[:top])) / float(sum(w))


def pool_soft():
    text = open(POOL_CONFIG, encoding='utf-8').read()
    m = re.search(r'softCap = \{cap = (\d+), H = (\d+)\}', text)
    return float(m.group(1)), float(m.group(2))


def soft(raw):
    cap, h = pool_soft()
    return raw if raw <= cap else cap + h * math.log(1 + (raw - cap) / h)


def pool_rows(path=POOL_CSV):
    """[(level, tree raw, factor of the old product, factor of the one pool)] of the typical profile"""
    with open(path, encoding='utf-8') as f:
        return [(int(r['level']), float(r['tree_raw']), float(r['before']), float(r['after'])) for r in csv.DictReader(f)]


def step_pool(level):
    """the pool of O473 against the old product for the typical profile: after / before the damage factor"""
    return _lin_log([(lv, a / b) for lv, _, b, a in pool_rows()], level)


def step_gear(cls, level):
    """O471: the mean Weapon Damage (weapon classes, hybrids) or Spell Damage (casters) of a Rare drop of the level, after against
    before. Weapon Damage is local to the weapon: it moves the weapon term, WEAPON_SKILL_SHARE of a hit. Spell Damage is a raw
    entry of the pool: it moves the pool through the soft cap, from the typical tree supply of the profile"""
    cfg = item_mods_config()
    if R.CLASS_KIND[cls] == 'caster':
        d = mean_modifier(level, cfg['spell_damage'], cfg) - mean_modifier(level, cfg['spell_damage'], cfg, True)
        raw = _lin_log([(lv, max(r, 1e-6)) for lv, r, _, _ in pool_rows()], level)
        return (1 + soft(raw + d) / 100.0) / (1 + soft(raw) / 100.0)
    import weapon_growth as WG
    k = WG.WEAPON_SKILL_SHARE / 100.0
    return (1 + mean_modifier(level, cfg['weapon_damage'], cfg) * k) / (1 + mean_modifier(level, cfg['weapon_damage'], cfg, True) * k)


def _read_power(path=POWER_CONFIG):
    """{'levels', 'distance', 'wand', ...} of weapon_power_config.lua"""
    text = open(path, encoding='utf-8').read()
    out = {}
    for key in ('levels', 'melee', 'distance', 'wand', 'fist'):
        out[key] = [float(v) for v in re.search(r'\b%s = \{([^}]*)\}' % key, text).group(1).split(',')]
    return out


def _power(table, kind, level):
    return R.interp(list(zip(table['levels'], table[kind])), level) if kind in table else 1.0


def power_before():
    """weapon_power_config.lua as it was before O472: the power factors computed on the weapon curves of before, with no W on the
    reference rotation (weapon_sim.before_growth)"""
    if 'power_before' not in _ROUND:
        import weapon_sim as WS
        with WS.before_growth():
            f = WS.power_factors()
        _ROUND['power_before'] = dict(f, levels=[float(v) for v in WS.POWER_LEVELS])
    return _ROUND['power_before']


def auto_dps(cls, level, grown):
    """damage per second of the auto attack on one target, the formula of weapon_sim.py (max hit of the engine, the style factors
    and the class factors left out) x the power factor of weapon_power_config.lua (grown) or of before O472, x the vocation's
    attack interval; a caster's auto attack is its wand: the mean wand curve x the power factor"""
    import install_gear_sets as G
    import weapon_growth as WG
    st = R.stats(cls, level)
    kind = R.CLASS_KIND[cls]
    iv = intervals()[0][R.VOC[cls]] / 1000.0
    table = _read_power() if grown else power_before()
    if kind == 'caster':
        mean = G.curve('wand', level) if grown else G.old_weapon_curve('wand', level)
        return mean * _power(table, 'wand', level) / iv
    atk = st['FIST'] if kind == 'fist' else st['ATK']
    if grown:
        atk *= WG.weapon_a(level)
    top = level // 5 + ((st['SK'] / 4.0 + 1) * (atk / 3.0) * 1.03)
    if kind == 'distance':
        return ((level / 5.0 + top) / 2.0) * 0.96 * _power(table, 'distance', level) / iv
    return top / 2.0 / iv


_KIT = {}


def _loaded():
    if 'loaded' not in _KIT:
        spells, model_ = R.load_all()
        held = dict(model_)
        for words, expr in R.LADDER_HOLD.items():
            held[words] = dict(model_[words], dmg=expr)
        _KIT['loaded'] = (spells, model_, held)
    return _KIT['loaded']


def _kit(cls, level, rows):
    """(1 target, 5 targets) damage per second of every Chaos attack spell of the class on cooldown (the harness of the measured
    table), with the rows `rows` of rotation_model.csv, under the stats rotation_sim has now (grown_stats() or not)"""
    spells = _loaded()[0]
    have = [s for s in R.class_spells(spells, cls, level) if R.quest_spell_ok(s, 0)]
    h = R.harness(R.prepare(have, rows, cls, level))
    return (h['dps1'], h['dps5']) if h else (0.0, 0.0)


def steps(cls, level):
    """{'dots': (f1, f5), 'weapon': (f1, f5), 'gear': f, 'pool': f, 'crit': f} at one level, from the real files"""
    spells, now_rows, old_rows = _loaded()
    with_old = {}
    R._ANALYSED.clear()
    s_old = _kit(cls, level, old_rows)
    s_new = _kit(cls, level, now_rows)
    a_old = auto_dps(cls, level, False)
    a_new = auto_dps(cls, level, True)
    with R.grown_stats():
        s_grown = _kit(cls, level, now_rows)
    out = {}
    out['dots'] = tuple((s_new[i] + a_old) / (s_old[i] + a_old) if s_old[i] + a_old else 1.0 for i in (0, 1))
    out['weapon'] = tuple((s_grown[i] + a_new) / (s_new[i] + a_old) if s_new[i] + a_old else 1.0 for i in (0, 1))
    out['gear'] = step_gear(cls, level)
    out['pool'] = step_pool(level)
    out['crit'] = CRIT_STEP
    return out


def round_anchors(cls):
    """{level: steps} of a class at ROUND_LEVELS, computed once"""
    if cls not in _ROUND:
        _ROUND[cls] = {lv: steps(cls, lv) for lv in ROUND_LEVELS}
    return _ROUND[cls]


def round_factor(cls, level, name=None):
    """(1 target, 5 targets) factor of the round on the class damage at any level: the product of the steps (or one step), a
    straight line in log level and log factor between ROUND_LEVELS, flat below 100 and above 2000"""
    a = round_anchors(cls)

    def one(st, i):
        f = 1.0
        for k, v in st.items():
            if name and k != name:
                continue
            f *= v[i] if isinstance(v, tuple) else v
        return f
    return tuple(_lin_log([(lv, one(a[lv], i)) for lv in ROUND_LEVELS], max(level, 1)) for i in (0, 1))


# ---- O444: the class damage every balance model reads --------------------------------------------------------------------
GROWTH_ABOVE_1000 = 0.00093   # damage growth per level above 1000, a share of the level 1000 damage (all classes the same)
_CACHE = {}


def shipped():
    """(model, medians) of the committed state after the round (O475), computed once"""
    if 'model' not in _CACHE:
        _CACHE['model'] = model()
    return _CACHE['model']


def shipped_before():
    """(model, medians) of the committed class factors BEFORE the balance round (what shipped() was until O475), computed once"""
    if 'before' not in _CACHE:
        _CACHE['before'] = model(rnd=False)
    return _CACHE['before']


def _anchor_value(points, level):
    """points = [(anchor level, damage), ...] ascending: a straight line in log(level), log(damage) between two anchors, the
    slope of the first two below the first anchor, the growth above 1000 a straight line (GROWTH_ABOVE_1000 a level)"""
    if level <= 0:
        return 0.0
    if level >= points[-1][0]:
        return points[-1][1] * (1 + GROWTH_ABOVE_1000 * (level - points[-1][0]))
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        if level <= x1:
            e = (math.log(y1) - math.log(y0)) / (math.log(x1) - math.log(x0))
            return y0 * (level / float(x0)) ** e
    raise AssertionError('level above the last anchor is handled first')


def dps(cls, level, out=None, rnd=True):
    """(1 target, 5 targets) damage per second of a class at any level: the model's numbers before the round at 100, 500 and 1000,
    in between and outside as described in the header, times the round's factor of the level (O475, round_factor(); rnd=False
    leaves it out). At 100, 500 and 1000 it is the number of shipped(). No pack cleave and no boss uptime: those are the models' own"""
    if out is None:
        out = shipped_before()[0]
    base = tuple(_anchor_value([(lv, out[(cls, lv)][k]) for lv in LEVELS], level) for k in ('pre1', 'pre5')) if 'pre1' in out[(cls, LEVELS[0])] else \
        tuple(_anchor_value([(lv, out[(cls, lv)][k]) for lv in LEVELS], level) for k in ('1t', '5t'))
    if not rnd or level <= 0:
        return base
    r = round_factor(cls, level)
    return (base[0] * r[0], base[1] * r[1])


def median_dps(level, out=None, rnd=True):
    """(median 1 target, median 5 targets) of the 21 classes at any level (the median of dps(), so the same line the
    classes follow; at 100, 500 and 1000 it is the table's median)"""
    return tuple(statistics.median(dps(c, level, out, rnd)[i] for c in KEY) for i in (0, 1))


def table(out, med):
    lines = ['| Level | Class | 1 target | vs median | 5 targets | vs median | m | extra |', '|---|---|---:|---:|---:|---:|---:|---:|']
    for lv in LEVELS:
        for cls in KEY:
            o = out[(cls, lv)]
            lines.append('| %d | %s | %.0f | %+.0f%% | %.0f | %+.0f%% | %.2f | %.2f |' % (
                lv, cls, o['1t'], (o['1t'] / med[lv][0] - 1) * 100, o['5t'], (o['5t'] / med[lv][1] - 1) * 100, o['m'], o['x']))
        lines.append('| %d | median | %.0f | | %.0f | | | |' % (lv, med[lv][0], med[lv][1]))
    return '\n'.join(lines)


def before_table(rows=None):
    rows = rows or load_rows()
    lines = ['| Level | Class | 1 target (helper) | vs median | 5 targets | vs median |', '|---|---|---:|---:|---:|---:|']
    for lv in LEVELS:
        m1 = statistics.median(rows[(c, lv)]['helper_1t'] for c in KEY)
        m5 = statistics.median(rows[(c, lv)]['helper_5t'] for c in KEY)
        for cls in KEY:
            r = rows[(cls, lv)]
            lines.append('| %d | %s | %.0f | %+.0f%% | %.0f | %+.0f%% |' % (
                lv, cls, r['helper_1t'], (r['helper_1t'] / m1 - 1) * 100, r['helper_5t'], (r['helper_5t'] / m5 - 1) * 100))
    return '\n'.join(lines)


def spread_rows(levels=ROUND_LEVELS):
    """[(level, fresh / typical, invested / typical before, after)]: the damage pool of the three profiles of tools/damage_pool_table.lua
    (assumed profiles, the pool part of the spread only: no critical hit, no runes, no tier of gear), the old product against the one pool"""
    with open(POOL_CSV, encoding='utf-8') as f:
        rows = {int(r['level']): r for r in csv.DictReader(f)}
    out = []
    for lv in levels:
        r = rows[lv]
        out.append((lv, float(r['fresh_before']) / float(r['before']), float(r['fresh_after']) / float(r['after']),
                    float(r['invested_before']) / float(r['before']), float(r['invested_after']) / float(r['after'])))
    return out


def steps_table():
    lines = ['| Class | Level | dots | weapon | gear | pool | all (1 target) | all (5 targets) |', '|---|---:|---:|---:|---:|---:|---:|---:|']
    for cls in KEY:
        for lv in ROUND_LEVELS:
            st = round_anchors(cls)[lv]
            r1, r5 = round_factor(cls, lv)
            lines.append('| %s | %d | %.2f / %.2f | %.2f / %.2f | %.3f | %.3f | %.2f | %.2f |' % (
                cls, lv, st['dots'][0], st['dots'][1], st['weapon'][0], st['weapon'][1], st['gear'], st['pool'], r1, r5))
    lines.append('')
    lines.append('| Level | median 1 target before | after | median 5 targets before | after |')
    lines.append('|---:|---:|---:|---:|---:|')
    for lv in ROUND_LEVELS:
        b, a = median_dps(lv, rnd=False), median_dps(lv)
        lines.append('| %d | %.0f | %.0f | %.0f | %.0f |' % (lv, b[0], a[0], b[1], a[1]))
    return '\n'.join(lines)


def main(argv):
    if '--steps' in argv:
        print(steps_table())
        return 0
    if '--spread' in argv:
        print('level  fresh / typical before  after   invested / typical before  after   (damage pool only, assumed profiles)')
        for lv, fb, fa, ib, ia in spread_rows():
            print('%5d  %22.2f %6.2f   %25.2f %6.2f' % (lv, fb, fa, ib, ia))
        return 0
    if '--round-before' in argv:
        o, m = shipped_before()
        print(table(o, m))
        return 0
    if '--before' in argv:
        print(before_table())
        return 0
    out, med = model()
    bad = problems(out, med)
    if '--check' in argv:
        for b in bad:
            print('FAIL ' + b)
        if not bad:
            print('class dps check: ok (21 classes, levels %s, within +-25%% of the median on 1 and 5 targets, +-30%% at 100)' %
                  ','.join(map(str, LEVELS)))
        return 1 if bad else 0
    print(table(out, med))
    if bad:
        print('\nOutside the band: ' + '; '.join(bad))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
