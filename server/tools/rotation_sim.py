#!/usr/bin/env python3
"""Attack rotations of at most 5 spells: a deterministic rotation simulator, the best set per class and level, the
helper's auto rotation data (owner, 2026-10-14: "Faça todas as classes terem até 5 magias na rotação e nunca ficarem
2s sem uma").

usage: python3 -I server/tools/rotation_sim.py [--report] [--write | --check] [--class NAME] [--level N]
       python3 -I server/tools/rotation_sim.py --export-stock SERVER_DIR

Data (everything in the repo, so CI runs it without the base tree):
  server/data/spells/chaos/spells_chaos.xml   the Chaos spells: group, cooldowns, level, mana, vocations; the cast
                                              time from the spell script (ChaosCasting.spell ms = ...)
  server/data/spells/stock_spells.csv         the stock attack and healing spells as the installed spells.xml has
                                              them (after rename_spells.py, add_vocations.py, patch_spell_ids.py and
                                              patch_spell_timings.py); written by --export-stock from an installed
                                              server
  server/data/spells/rotation_model.csv       the average damage of one cast on the main target (an expression of
                                              the class's stats at the level), the targets of the 5-dummy pack it
                                              hits, and the rotation flags (keep: a debuff kept up; chi: a Monk
                                              finisher; skip: no direct damage or a condition the dummies never meet;
                                              utility: a spell players cast by hand that no preset and no set of 5
                                              takes, the snares Snare Trap and Seeker Mine)

The model (computed, not measured): a priority rotation, cast the first ready spell of the list whenever the attack
group allows it. A cast starts the spell's cooldown, its group cooldown (the cast spell's groupcooldown on every group
it is in, the attack group included) and its secondary group cooldown; a cast-time spell holds the next cast until it
fires. The Monk line's chi: +1 per auto-attack hit (one per 2 s at most, the auto attack never faster than
minPlayerAttackInterval), +2 Ashen Fist, +1 Pressure Points, max 5; a finisher waits for 4 chi (the measured harness).
The gap is the longest time between two casts over HORIZON seconds from a fresh start; 2.0 s means a cast on every
attack group cooldown. The damage is relative (no passive tree, no class factor, no auto attack, no minions); the
change of a class's spell damage bounds the change of its total.

--report prints, per class and level band (15 / 30 / 60 / 100 / 300 / 600 / 1000), the best set of at most 5 with
its gap and damage against the measured kit (the C4 harness: every Chaos attack spell of the class on cooldown);
--class / --level also list the class's spells with their numbers.
--mana [--check] [--class NAME]: the mana runway (owner, 2026-10-17: "Magias com custo de mana muito alto, difíceis de
manter"): per class and checked level, how long the best set runs from a full pool with the vocation's own regeneration
(mana_runway); a row under MANA_RUNWAY (15 s) is SHORT, and --check exits 1 on any.
--heal: Shadow Mend (the Thief line's self heal) at level 300 and 1000 against the measured self heal per second of the Ranger
line and the Illusionist (server/data/spells/README.md "Healing"): the formula of chaos_constants.lua, the cooldown and manapercent
of spells_chaos.xml, the base health and the mana pool of the data.
--ladder [--check]: the cooldown ladder per class (owner, 2026-10-20: the attack spells at 2, 4, 6 s ... from the
first to the strongest; ladder() below, server/data/spells/README.md "Cooldown ladder"); --check exits 1 when a spell's
cooldown or group cooldown is off it.
--write / --check: client/overlay/modules/game_helperrotation/autorotation_data.lua (the helper's "Auto rotation"
button: the best set for every level where the class gets a new attack spell, and its heals).
"""
import csv, functools, itertools, math, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..'))
SPELLS = os.path.join(REPO, 'server', 'data', 'spells')
CHAOS_XML = os.path.join(SPELLS, 'chaos', 'spells_chaos.xml')
STOCK_CSV = os.path.join(SPELLS, 'stock_spells.csv')
MODEL_CSV = os.path.join(SPELLS, 'rotation_model.csv')
TEMPLAR_CORE = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'templar_aura_core.lua')
TOSS_SCRIPT = os.path.join(SPELLS, 'chaos', 'thief', 'shuriken_toss.lua')
BLADES = os.path.join(SPELLS, 'chaos', '_blades.lua')
PACKTOOLS = os.path.join(SPELLS, 'chaos', '_packtools.lua')
CLIENT_DATA = os.path.join(REPO, 'client', 'overlay', 'modules', 'game_helperrotation', 'autorotation_data.lua')
VOCATION_XMLS = os.path.join(REPO, 'server', 'data', 'XML')      # chaos_vocations*.xml: mana gain and regeneration
START_STATS = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'start_stats.lua')  # level 1 mana per class

GCD = 2.0                     # the attack group cooldown of nearly every attack spell
HORIZON = 120.0               # seconds simulated from a fresh start
MAX_SPELLS = 5
BANDS = (15, 30, 60, 100, 300, 600, 1000)
MANA_RUNWAY = 15.0                # a class's best set must run this many seconds on a full mana pool (see mana_runway)
MANA_MAX_LEVEL = 300              # checked at the bands and preset levels up to here (the owner's review: 8 to 100; 200 and 300 too)
NO_PRESET = ('skip', 'utility')  # flags that keep a spell out of every rotation the simulator builds
MIN_PLAYER_ATTACK_INTERVAL = 1.0  # config.lua minPlayerAttackInterval (src-patch 0011), seconds
CHI_HIT_INTERVAL = 2.0            # one chi per melee hit, at most one per 2 s (ChaosMonk.cfg.chi)
KEEP_SHARE = 0.95                 # a best set keeps 95% of the measured kit's damage when it can
PACK_WEIGHT = 0.25                # score = 1 target + 0.25 x the 5-target total
CANDIDATES = 10                   # the strongest spells per second a class's best set is searched among (+ below)

# server vocation ids (docs/CLASSES.md; client/tools/gen_spell_data.py VOC)
VOC = {'Mystic': 1, 'Ranger': 3, 'Warrior': 4, 'Elementalist': 5, 'Deadeye': 7, 'Juggernaut': 8, 'Illusionist': 10,
       'Thief': 11, 'Ninja': 12, 'Samurai': 13, 'Berserker': 14, 'Beastmaster': 15, 'Monk': 17, 'Shadowfist': 18,
       'Iron Sage': 19, 'Necromancer': 20, 'Lich': 21, 'Bone Lord': 22, 'Templar': 23, 'Inquisitor': 24,
       'Sentinel': 25}
# class -> (line, kind of stats)
CLASSES = [
    ('Warrior', 'Warrior', 'melee'), ('Juggernaut', 'Warrior', 'melee'), ('Berserker', 'Warrior', 'melee'),
    ('Ranger', 'Ranger', 'distance'), ('Deadeye', 'Ranger', 'distance'), ('Beastmaster', 'Ranger', 'distance'),
    ('Mystic', 'Mystic', 'caster'), ('Elementalist', 'Mystic', 'caster'), ('Illusionist', 'Mystic', 'caster'),
    ('Thief', 'Thief', 'melee'), ('Ninja', 'Thief', 'melee'), ('Samurai', 'Thief', 'melee'),
    ('Necromancer', 'Necromancer', 'caster'), ('Lich', 'Necromancer', 'caster'), ('Bone Lord', 'Necromancer', 'caster'),
    ('Monk', 'Monk', 'fist'), ('Shadowfist', 'Monk', 'fist'), ('Iron Sage', 'Monk', 'fist'),
    ('Templar', 'Templar', 'melee'), ('Inquisitor', 'Templar', 'melee'), ('Sentinel', 'Templar', 'melee'),
]
CLASS_KIND = {c: k for c, _, k in CLASSES}

# the stats of the C4 measurement (server/data/spells/README.md "Classes with the passive trees": level 300 / 1000;
# 100 and 600 in between), linear between the anchors
ANCHORS = {
    'ml_caster': [(1, 0), (100, 60), (300, 100), (600, 120), (1000, 140)],
    'ml_other': [(1, 0), (100, 10), (300, 25), (600, 32), (1000, 40)],
    'skill': [(1, 10), (100, 80), (300, 110), (600, 125), (1000, 140)],
    'atk_melee': [(1, 10), (100, 45), (300, 55), (600, 60), (1000, 65)],
    'atk_distance': [(1, 10), (100, 45), (300, 60), (600, 70), (1000, 77)],
}


def interp(points, x):
    if x <= points[0][0]:
        return float(points[0][1])
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        if x <= x1:
            return y0 + (y1 - y0) * (x - x0) / float(x1 - x0)
    return float(points[-1][1])


def stats(cls, level):
    kind = CLASS_KIND[cls]
    ml = interp(ANCHORS['ml_caster' if kind == 'caster' else 'ml_other'], level)
    sk = interp(ANCHORS['skill'], level)
    atk = interp(ANCHORS['atk_distance' if kind == 'distance' else 'atk_melee'], level)
    fist = min(60.0, 40 + 0.025 * level)
    p = sk * (fist if kind == 'fist' else atk)
    return {'L': float(level), 'l': level / 5.0, 'ML': ml, 'SK': sk, 'ATK': atk, 'P': p, 'FIST': fist,
            'BITE': 0.12 * level + 0.6 * sk, 'PETS': 2 if level >= 400 else 1, 'cls': cls,
            'SMITE': smite_for(cls, level), 'TOSS': toss_for(cls, level), 'FLURRY': flurry_for(cls, level),
            'SWEEP': sweep_scale(), 'OFFHAND': OFFHAND.get(cls, 1.0), 'FAN': pack_scale('fan'),
            'SANCT': pack_scale('sanctified'), 'WAVE': pack_scale('shieldWave')}


def smite_for(cls, level):
    early = smite_early().get(VOC[cls])
    if early and level < early[0]:
        return early[1]
    return smite_scale().get(VOC[cls], 1.0)


def early_scales(text):
    """{vocation: (below level, scale)} of a table of `[voc] = {below = N, scale = X}` entries"""
    return {int(v): (int(b), float(k)) for v, b, k in re.findall(
        r'\[(\d+)\]\s*=\s*\{below\s*=\s*(\d+),\s*scale\s*=\s*([0-9.]+)\}', text)}


def smite_early():
    """{vocation: (below level, scale)} of ChaosTemplar.cfg.radiantSmite.early"""
    return early_scales(open(TEMPLAR_CORE, encoding='utf-8').read())


@functools.lru_cache(maxsize=None)
def toss_scales():
    """Shuriken Toss's class scale (chaos/thief/shuriken_toss.lua): ({voc: scale}, {voc: (below, scale)}, default)"""
    text = open(TOSS_SCRIPT, encoding='utf-8').read()
    m = re.search(r'local SCALE\s*=\s*\{([^}]*)\}', text)
    e = re.search(r'local EARLY\s*=\s*(\{.*?\}\s*\})\s*\n', text)
    d = re.search(r'local DEFAULT_SCALE\s*=\s*([0-9.]+)', text)
    scale = {int(k): float(v) for k, v in re.findall(r'\[(\d+)\]\s*=\s*([0-9.]+)', m.group(1))} if m else {}
    return scale, early_scales(e.group(1)) if e else {}, float(d.group(1)) if d else 1.0


def toss_for(cls, level):
    scale, early, default = toss_scales()
    e = early.get(VOC[cls])
    if e and level < e[0]:
        return e[1]
    return scale.get(VOC[cls], default)


# the Ninja's off-hand strike after each melee weapon strike: 50% of it (two blades of the same attack), README "Thief line"
OFFHAND = {'Ninja': 1.5}


@functools.lru_cache(maxsize=None)
def blades_cfg(key, path=None):
    """a block of ChaosBlades.cfg (chaos/_blades.lua) or ChaosPackTools.cfg (chaos/_packtools.lua, path=PACKTOOLS):
    ({voc: scale}, {voc: (below, scale)}, default or the scale)"""
    text = open(path or BLADES, encoding='utf-8').read()
    block = re.search(r'\b' + key + r'\s*=\s*\{(.*?)\n\t\},', text, re.S).group(1)
    m = re.search(r'\bscale\s*=\s*\{([^}]*)\}', block)
    e = re.search(r'\bearly\s*=\s*(\{.*?\}\s*\})', block, re.S)
    d = re.search(r'\bdefaultScale\s*=\s*([0-9.]+)', block) or re.search(r'^\s*scale\s*=\s*([0-9.]+)', block, re.M)
    scale = {int(k): float(v) for k, v in re.findall(r'\[(\d+)\]\s*=\s*([0-9.]+)', m.group(1))} if m else {}
    return scale, early_scales(e.group(1)) if e else {}, float(d.group(1)) if d else 1.0


def flurry_for(cls, level):
    """Blade Flurry's class scale (ChaosBlades.cfg.flurry)"""
    scale, early, default = blades_cfg('flurry')
    e = early.get(VOC[cls])
    if e and level < e[0]:
        return e[1]
    return scale.get(VOC[cls], default)


def pack_scale(key, cls=None):
    """the scale of a pack tool (ChaosPackTools.cfg.<key>): the class's when the block has a table"""
    scale, _, default = blades_cfg(key, PACKTOOLS)
    return scale.get(VOC[cls], default) if cls else default


def sweep_scale():
    """Iaido Sweep's scale (ChaosBlades.cfg.sweep)"""
    return blades_cfg('sweep')[2]


def smite_scale():
    """Radiant Smite's damage scale per Templar class (ChaosTemplar.cfg.radiantSmite.scale, templar_aura_core.lua)"""
    text = open(TEMPLAR_CORE, encoding='utf-8').read()
    m = re.search(r'radiantSmite\s*=\s*\{[^{}]*scale\s*=\s*\{([^}]*)\}', text)
    if not m:
        return {}
    return {int(k): float(v) for k, v in re.findall(r'\[(\d+)\]\s*=\s*([0-9.]+)', m.group(1))}


def avg(a, b):
    return (a + b) / 2.0


def evaluate(expr, env):
    return float(eval(expr, {'__builtins__': {}}, dict(env, avg=avg, min=min, max=max)))


# ---------------------------------------------------------------------------------------------------------- data
def attrs(text):
    return dict(re.findall(r'(\w+)="([^"]*)"', text))


def cast_ms(script):
    path = os.path.join(SPELLS, script)
    if not os.path.isfile(path):
        return 0
    m = re.search(r'ChaosCasting\.spell\(\{[^}]*?\bms\s*=\s*(\d+)', open(path, encoding='utf-8').read(), re.S)
    return int(m.group(1)) if m else 0


def spell_row(a, vocs, chaos):
    return {
        'id': int(a.get('spellid') or 0), 'name': a.get('name', ''), 'words': a.get('words', ''),
        'group': a.get('group', ''), 'level': int(a.get('level') or a.get('lvl') or 0),
        'mana': int(a.get('mana') or 0), 'cooldown': int(a.get('cooldown') or a.get('exhaustion') or 0),
        'groupcooldown': int(a.get('groupcooldown') or 0), 'secondarygroup': a.get('secondarygroup', ''),
        'secondarygroupcooldown': int(a.get('secondarygroupcooldown') or 0),
        'params': a.get('params') == '1', 'vocations': vocs, 'chaos': chaos,
        'cast': cast_ms(a.get('script', '')) if chaos else 0,
    }


def instants(xml_text):
    xml_text = re.sub(r'<!--.*?-->', '', xml_text, flags=re.S)
    for m in re.finditer(r'<instant\b([^>]*?)(/>|>(.*?)</instant>)', xml_text, flags=re.S):
        yield attrs(m.group(1)), re.findall(r'<vocation name="([^"]+)"', m.group(3) or '')


def load_chaos():
    out = []
    for a, vocs in instants(open(CHAOS_XML, encoding='utf-8').read()):
        if a.get('group') in ('attack', 'healing'):
            out.append(spell_row(a, vocs, True))
    return out


STOCK_FIELDS = ['id', 'name', 'words', 'group', 'level', 'mana', 'cooldown', 'groupcooldown', 'secondarygroup',
                'secondarygroupcooldown', 'params', 'vocations']


def load_stock():
    out = []
    for r in csv.DictReader(open(STOCK_CSV, encoding='utf-8')):
        row = {k: r[k] for k in STOCK_FIELDS}
        for k in ('id', 'level', 'mana', 'cooldown', 'groupcooldown', 'secondarygroupcooldown'):
            row[k] = int(row[k] or 0)
        row['params'] = row['params'] == '1'
        row['vocations'] = [v for v in row['vocations'].split(';') if v]
        row['chaos'] = False
        row['cast'] = 0
        out.append(row)
    return out


def export_stock(server_dir):
    """the stock attack and healing instants of an installed server's spells.xml (outside the Chaos block)"""
    path = os.path.join(server_dir, 'data', 'spells', 'spells.xml')
    text = open(path, encoding='utf-8', errors='surrogateescape').read()
    head, _, rest = text.partition('<!-- BEGIN chaos spells')
    _, _, tail = rest.partition('<!-- END chaos spells -->')
    rows = []
    for a, vocs in instants(head + tail):
        if a.get('group') not in ('attack', 'healing') or not vocs:
            continue
        r = spell_row(a, vocs, False)
        r['params'] = '1' if r['params'] else ''
        r['vocations'] = ';'.join(v for v in vocs if v in VOC)
        if r['vocations']:
            rows.append(r)
    rows.sort(key=lambda r: (r['group'], r['level'], r['words']))
    with open(STOCK_CSV, 'w', encoding='utf-8', newline='') as f:
        w = csv.DictWriter(f, fieldnames=STOCK_FIELDS, extrasaction='ignore', lineterminator='\n')
        w.writeheader()
        w.writerows(rows)
    print('wrote %s (%d spells)' % (os.path.relpath(STOCK_CSV, REPO), len(rows)))


def load_model():
    model = {}
    for r in csv.DictReader(open(MODEL_CSV, encoding='utf-8')):
        model[r['words']] = {'dmg': r['dmg'], 't5': float(r['t5'] or 1), 'flags': set(r['flags'].split(';')) - {''}}
    return model


def load_all():
    spells = load_chaos() + load_stock()
    model = load_model()
    attack = [s for s in spells if s['group'] == 'attack']
    missing = [s['words'] for s in attack if s['words'] not in model]
    if missing:
        raise SystemExit('rotation_model.csv has no row for: %s' % ', '.join(sorted(set(missing))))
    return spells, model


def class_spells(spells, cls, level, group='attack'):
    return [s for s in spells if s['group'] == group and cls in s['vocations'] and s['level'] <= level]


# ---------------------------------------------------------------------------------------------------------- sim
class Spell(object):
    __slots__ = ('chaos', 'words', 'name', 'id', 'cd', 'gcd', 'sec', 'seccd', 'cast', 'dmg', 'dmg5', 'chi', 'gain', 'keep', 'area')


def prepare(spells, model, cls, level):
    env = stats(cls, level)
    out = []
    for s in spells:
        m = model[s['words']]
        if m['flags'] & set(NO_PRESET):
            continue
        p = Spell()
        p.words, p.name, p.id, p.chaos = s['words'], s['name'], s['id'], s['chaos']
        p.cd = s['cooldown'] / 1000.0
        p.gcd = s['groupcooldown'] / 1000.0
        p.sec = s['secondarygroup']
        p.seccd = s['secondarygroupcooldown'] / 1000.0
        p.cast = s['cast'] / 1000.0
        p.dmg = evaluate(m['dmg'], env)
        p.dmg5 = p.dmg * m['t5']
        p.chi = 'chi' in m['flags']
        p.gain = 2 if 'chi2' in m['flags'] else (1 if 'chi1' in m['flags'] else 0)
        p.keep = 'keep' in m['flags']
        p.area = m['t5'] >= 3  # the same rule as creatures(): an area spell hits 3+ of a pack
        out.append(p)
    return out


def score(one, five):
    """what a rotation is chosen by: one target plus a quarter of the 5-target total (a hunt is both)"""
    return one + PACK_WEIGHT * five


def order(spells):
    """priority: the debuffs kept up first, then the area spells (3+ targets of the pack), then the single-target spells;
    inside each group the longest cooldown first, then the most damage per cast (the harness: the strongest ready spell)"""
    return sorted(spells, key=lambda s: (not s.keep, not s.area, -s.cd, -score(s.dmg, s.dmg5), s.words))


def simulate(rotation, horizon=HORIZON):
    """cast times of a priority rotation; returns (casts, gap, dmg1 per second, dmg5 per second)"""
    ready = [0.0] * len(rotation)
    group = {}
    t = 0.0
    chi, chi_t = 0, 0.0
    casts = []
    swing = max(CHI_HIT_INTERVAL, MIN_PLAYER_ATTACK_INTERVAL)
    d1 = d5 = 0.0
    while t < horizon:
        if chi_t + swing <= t:  # auto-attack chi since the last update
            n = int((t - chi_t) // swing)
            chi, chi_t = min(5, chi + n), chi_t + n * swing
        pick = None
        soonest = None
        for i, s in enumerate(rotation):
            at = max(ready[i], group.get('attack', 0.0), group.get(s.sec, 0.0) if s.sec else 0.0)
            if s.chi and chi < 4:
                at = max(at, chi_t + swing * (4 - chi))
            if at <= t + 1e-9:
                pick = i
                break
            soonest = at if soonest is None else min(soonest, at)
        if pick is None:
            t = soonest if soonest is not None else horizon
            continue
        s = rotation[pick]
        casts.append((round(t, 3), s.words))
        ready[pick] = t + s.cd
        group['attack'] = t + max(s.gcd, s.cast)
        if s.sec:
            group[s.sec] = t + s.seccd
        hit = s.dmg
        if s.chi:
            scale = 0.30 + 0.14 * chi
            hit = s.dmg * ((2 + chi) / 7.0 if 'Flurry' in s.name else scale)
            chi = 0
        elif s.gain:
            chi = min(5, chi + s.gain)
        if t + s.cast <= horizon:
            d1 += hit
            d5 += hit * (s.dmg5 / s.dmg if s.dmg else 0)
        t = t + max(s.gcd, s.cast, 1e-3)
    times = [c[0] for c in casts]
    gaps = [b - a for a, b in zip(times, times[1:])]
    if times:
        gaps.append(horizon - times[-1] if horizon - times[-1] > GCD else 0.0)
    gap = max(gaps) if gaps else horizon
    return casts, round(gap, 3), d1 / horizon, d5 / horizon


def best_set(pool, limit=MAX_SPELLS):
    """the best rotation of at most `limit` spells: gap <= 2.0 s first, then one that keeps 95% of the measured kit's
    damage on one target and on five (harness() below) when one does (else the one closest to it), then the best score.
    The search runs over the class's strongest spells; when no set keeps 95% it runs again over more of them."""
    if not pool:
        return None
    ref = harness(pool)
    best = search(pool, ref, limit, CANDIDATES, 3)
    if best[0][2]:
        wider = search(pool, ref, limit, CANDIDATES + 2, 6)
        if wider[0] < best[0]:
            best = wider
    _, rot, gap, d1, d5 = best
    return {'spells': rot, 'gap': gap, 'dps1': d1, 'dps5': d5}


def search(pool, ref, limit, by_rate, by_cast):
    # the strongest per second on their own cooldown, the hardest single casts (long cooldowns) and the best fillers
    ranked = sorted(pool, key=lambda s: -score(s.dmg, s.dmg5) * min(1.0, GCD / max(s.cd, GCD)))
    cands = ranked[:by_rate]
    for s in sorted(pool, key=lambda s: -score(s.dmg, s.dmg5))[:by_cast]:
        if s not in cands:
            cands.append(s)
    for s in [s for s in ranked if max(s.cd, s.gcd) <= GCD][:2]:
        if s not in cands:
            cands.append(s)
    # a debuff kept up (Withering Curse, Judgement, Pressure Points) is in every set: its worth is the damage it adds
    # to the rest, which the per-cast numbers leave out (the harness kept them up too)
    keep = [s for s in pool if s.keep]
    cands = [s for s in cands if not s.keep]
    best = None
    for k in range(max(1, len(keep)), min(limit, len(cands) + len(keep)) + 1):
        for combo in itertools.combinations(cands, k - len(keep)):
            rot = order(keep + list(combo))
            _, gap, d1, d5 = simulate(rot)
            share = min(d1 / ref['dps1'], d5 / ref['dps5']) if ref and ref['dps1'] and ref['dps5'] else 1.0
            short = share < KEEP_SHARE
            key = (short, -round(share, 3) if short else 0, -score(d1, d5), k)
            if best is None or key < best[0]:
                best = (key, rot, gap, d1, d5)
    return best


def harness(pool):
    """the measured rotation (C4, 2026-10-11): every attack spell of the class's Chaos kit on cooldown, the strongest
    ready first (the stock spells and the snares, added 2026-10-12, were not in it; the pool has no utility spell)"""
    kit = [s for s in pool if s.chaos]
    if not kit:
        return None
    rot = order(kit)
    _, gap, d1, d5 = simulate(rot)
    return {'spells': rot, 'gap': gap, 'dps1': d1, 'dps5': d5}


_ANALYSED = {}


def analyse(spells, model, cls, level):
    key = (id(spells), id(model), cls, level)  # the callers pass the same loaded lists: the search runs once per class and level
    if key not in _ANALYSED:
        pool = prepare(class_spells(spells, cls, level), model, cls, level)
        best = best_set(pool)
        _ANALYSED[key] = {'pool': pool, 'best': mana_fit(best, pool, spells, cls, level), 'all': harness(pool)}
    return _ANALYSED[key]


# ---------------------------------------------------------------------------------------------------------- client
def breakpoints(spells, model, cls):
    """the levels where the class gets a new attack spell the rotation can use, and the level bands (the stats grow)"""
    lv = {s['level'] for s in spells if s['group'] == 'attack' and cls in s['vocations'] and
          not model[s['words']]['flags'] & set(NO_PRESET)}
    return sorted(lv | ({b for b in BANDS if b >= min(lv)} if lv else set()))


def creatures(rotation, model):
    """the helper's monster count per spell: an area spell (3+ of the pack) waits for 2 monsters when the rotation has a
    single-target spell to cast on a lone target; otherwise 1, so a lone target never leaves the helper idle"""
    area = [model[s.words]['t5'] >= 3 for s in rotation]
    ok = any(not a for a in area)
    return [2 if a and ok else 1 for a in area]


def heals(spells, cls):
    """the class's own healing spells for the helper's healing tab: no named target, no cure (the "puir" spells), no
    long emergency cooldown (over 10 s), the higher level first"""
    out = [s for s in spells if s['group'] == 'healing' and cls in s['vocations'] and not s['params'] and
           not s['words'].startswith('puir') and s['cooldown'] <= 10000]
    out.sort(key=lambda s: (-s['level'], s['words']))
    return out


def lua_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def client_data(spells, model):
    out = ['-- GENERATED by server/tools/rotation_sim.py --write from the server spell data and',
           '-- server/data/spells/rotation_model.csv. Do not edit.',
           '-- ChaosAutoRotationData.classes[serverVocationId] = { name, presets = { { level, gap, spells = { id, ... },',
           '--   creatures = { n, ... } } },',
           '--   heals = { { id, level }, ... } }; a preset is the best rotation of at most 5 attack spells from its level on',
           '-- (the first spell first), gap = its longest time between two casts in seconds. spells[id] = the spell numbers.',
           'ChaosAutoRotationData = {', '  gcd = %.1f,' % GCD, '  classes = {']
    used = {}
    for cls, _, _ in CLASSES:
        out.append('    [%d] = { name = %s, presets = {' % (VOC[cls], lua_str(cls)))
        last = None
        for lv in breakpoints(spells, model, cls):
            r = best_set(prepare(class_spells(spells, cls, lv), model, cls, lv))
            if not r:
                continue
            ids = [s.id for s in r['spells']]
            if ids == last:
                continue
            last = ids
            for s in r['spells']:
                used[s.id] = s
            crowd = creatures(r['spells'], model)
            out.append('      { level = %d, gap = %.2f, spells = { %s }, creatures = { %s } },' % (
                lv, r['gap'], ', '.join(map(str, ids)), ', '.join(map(str, crowd))))
        out.append('    }, heals = {')
        for h in heals(spells, cls)[:3]:
            out.append('      { id = %d, level = %d },' % (h['id'], h['level']))
        out.append('    } },')
    out.append('  },')
    out.append('  spells = {')
    byid = {}
    for s in spells:
        if s['id'] in used:
            byid[s['id']] = s
    for sid in sorted(byid):
        s = byid[sid]
        p = used[sid]
        out.append('    [%d] = { name = %s, words = %s, cooldown = %d, groupCooldown = %d, secondaryGroup = %s, '
                   'secondaryCooldown = %d, cast = %d, area = %s, chi = %s },' % (
                       sid, lua_str(s['name']), lua_str(s['words']), s['cooldown'], s['groupcooldown'],
                       lua_str(s['secondarygroup']), s['secondarygroupcooldown'], s['cast'],
                       'true' if model[s['words']]['t5'] >= 3 else 'false', 'true' if p.chi else 'false'))
    out.append('  },')
    out.append('}')
    return '\n'.join(out) + '\n'


# ---------------------------------------------------------------------------------------------------------- mana
@functools.lru_cache(maxsize=None)
def mana_stats():
    """{class: (level 1 mana, mana per level, regeneration per second)} from start_stats.lua and chaos_vocations*.xml.
    The regeneration is the vocation's own (gainmanaamount per gainmanaticks seconds): no gear, passive tree or potion"""
    start = {int(v): int(m) for v, m in re.findall(r'\[(\d+)\] = \{health = \d+, mana = (\d+)',
                                                    open(START_STATS, encoding='utf-8').read())}
    out = {}
    for fn in sorted(os.listdir(VOCATION_XMLS)):
        if not (fn.startswith('chaos_vocations') and fn.endswith('.xml')):
            continue
        text = re.sub(r'<!--.*?-->', '', open(os.path.join(VOCATION_XMLS, fn), encoding='utf-8').read(), flags=re.S)
        for m in re.finditer(r'<vocation\b([^>]*)>', text):
            a = attrs(m.group(1))
            if a.get('name') in VOC:
                out[a['name']] = (start[int(a['id'])], int(a['gainmana']),
                                  int(a['gainmanaamount']) / float(a['gainmanaticks']))
    return out


def mana_pool(cls, level):
    first, gain, _ = mana_stats()[cls]
    return first + (level - 1) * gain


def set_runway(rot, spells, cls, level):
    """seconds a rotation runs from a full mana pool with the vocation's own regeneration (inf when the regeneration pays
    for it); mana_runway() below is this for the class's best set"""
    cost = {s['words']: s['mana'] for s in spells if cls in s['vocations'] and s['group'] == 'attack'}
    casts, _, _, _ = simulate(rot)
    spent = sum(cost[w] for _, w in casts) / HORIZON
    net = spent - mana_stats()[cls][2]
    return mana_pool(cls, level) / net if net > 0 else float('inf')


def mana_fit(best, pool, spells, cls, level):
    """the best set, unless it runs under MANA_RUNWAY seconds on a full pool (2026-10-20: a stronger area spell, Skewering
    Line, joined the Ranger line's set at level 60 and its 150 mana put the set at 14.8 s): then the best set without
    one of its spells that keeps the gap and the runway, by the same damage score. The mana costs stay as they are."""
    if not best or set_runway(best['spells'], spells, cls, level) >= MANA_RUNWAY:
        return best
    fits = []
    for drop in best['spells']:
        alt = best_set([s for s in pool if s is not drop])
        if alt and alt['gap'] <= GCD and set_runway(alt['spells'], spells, cls, level) >= MANA_RUNWAY:
            fits.append(alt)
    if not fits:
        return best
    return max(fits, key=lambda a: score(a['dps1'], a['dps5']))


def mana_runway(spells, model, cls, level):
    """how long the class's best set (at most 5 spells, the helper's auto rotation) can be cast without a pause from a
    full mana pool, with the vocation's own regeneration only: pool / (mana spent per second - regeneration), in seconds
    (None when the regeneration pays for it, or the class has no attack spell yet). The set is the one the damage score
    picks; mana is not part of the choice. Returns (runway, pool, regeneration/s, spent/s, the set with its costs)"""
    best = analyse(spells, model, cls, level)['best']
    if not best:
        return None
    cost = {s['words']: s['mana'] for s in spells if cls in s['vocations'] and s['group'] == 'attack'}
    casts, _, _, _ = simulate(best['spells'])
    spent = sum(cost[w] for _, w in casts) / HORIZON
    pool, regen = mana_pool(cls, level), mana_stats()[cls][2]
    net = spent - regen
    return (pool / net if net > 0 else float('inf'), pool, regen, spent, [(s.name, cost[s.words]) for s in best['spells']])


def mana_levels(spells, model, cls):
    """the levels a class is checked at: the bands and the preset levels from 8 (the start level) to MANA_MAX_LEVEL"""
    return sorted(l for l in set(BANDS) | set(breakpoints(spells, model, cls)) | {8} if l <= MANA_MAX_LEVEL)


def mana_report(spells, model, only_cls=None):
    """prints the runway of every class at every checked level; returns the rows under MANA_RUNWAY"""
    short = []
    for cls, _, _ in CLASSES:
        if only_cls and cls != only_cls:
            continue
        for lv in mana_levels(spells, model, cls):
            r = mana_runway(spells, model, cls, lv)
            if not r:
                continue
            flag = r[0] < MANA_RUNWAY
            if flag:
                short.append((cls, lv, r))
            print('%-12s %4d  pool %6d  regen %5.2f/s  spent %7.2f/s  runway %7.1f s%s  %s' % (
                cls, lv, r[1], r[2], r[3], r[0], '  SHORT' if flag else '',
                ' > '.join('%s %d' % c for c in r[4])))
    return short


# ---------------------------------------------------------------------------------------------------------- healing
CONSTANTS = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'chaos_constants.lua')
HEAL_INT = 1.2                    # intelligence 20: the engine adds 20% to every non-physical value (the harness)
HEAL_ML = {300: 30, 1000: 40}     # the harness's magic level of the Thief line (server/data/spells/README.md "Healing")
HEAL_REF = {300: {'Ranger line': 798, 'Illusionist': 1538}, 1000: {'Ranger line': 1180, 'Illusionist': 2317}}  # measured self heal /s


def shadow_mend_cfg():
    """{perLevel, perMagicLevel, maxHealthShare, spread} of Chaos.classes.shadowMend, and the spell's cooldown (ms) and
    manapercent from spells_chaos.xml"""
    text = open(CONSTANTS, encoding='utf-8').read()
    m = re.search(r'shadowMend = \{([^}]*)\}', text)
    cfg = {k: float(v) for k, v in re.findall(r'(\w+) = ([\d.]+)', m.group(1))}
    xml = open(CHAOS_XML, encoding='utf-8').read()
    a = attrs(re.search(r'<instant\b[^>]*name="Shadow Mend"[^>]*>', xml).group(0))
    cfg['cooldown'] = int(a['cooldown'])
    cfg['manapercent'] = float(a['manapercent'])
    return cfg


def heal_health(cls, level):
    """base maximum health of a class at a level: start_stats.lua plus the vocation's gain per level (no gear, no tree)"""
    start = {int(v): int(h) for v, h in re.findall(r'\[(\d+)\] = \{health = (\d+)', open(START_STATS, encoding='utf-8').read())}
    ids = {'Thief': 11}
    gain = {'Thief': 12}
    return start[ids[cls]] + (level - 1) * gain[cls]


def shadow_mend_rate(level, ml, health=None):
    """Shadow Mend on the Thief: (average heal of a cast, heal per second at the cooldown, mana per cast, heal per mana,
    mana per minute); the same formula as ChaosClasses.shadowMendRange x the intelligence bonus"""
    c = shadow_mend_cfg()
    health = heal_health('Thief', level) if health is None else health
    avg = (level * c['perLevel'] + ml * c['perMagicLevel'] + health * c['maxHealthShare']) * HEAL_INT
    cost = mana_pool('Thief', level) * c['manapercent'] / 100.0
    per_s = avg / (c['cooldown'] / 1000.0)
    return avg, per_s, cost, avg / cost, cost * 60000.0 / c['cooldown']


def heal_report():
    """prints Shadow Mend against the measured self heals of the Ranger line and the Illusionist (README "Healing")"""
    for lv, ml in sorted(HEAL_ML.items()):
        avg, per_s, cost, per_mana, per_min = shadow_mend_rate(lv, ml)
        ref = HEAL_REF[lv]
        print('Thief %4d  ml %2d  cast %6.0f  %6.0f/s  cost %5.0f  %5.1f heal/mana  %6.0f mana/min  Ranger line %4d  Illusionist %4d' % (
            lv, ml, avg, per_s, cost, per_mana, per_min, ref['Ranger line'], ref['Illusionist']))


# ---------------------------------------------------------------------------------------------------------- report
def fmt_set(r):
    return ' > '.join(s.name for s in r['spells'])


def report(spells, model, only_cls=None, only_level=None):
    rows = []
    for cls, _, _ in CLASSES:
        if only_cls and cls != only_cls:
            continue
        for lv in ([only_level] if only_level else BANDS):
            a = analyse(spells, model, cls, lv)
            b, h = a['best'], a['all']
            if not b:
                print('%-12s %4d  no attack spell' % (cls, lv))
                continue
            line = '%-12s %4d  best %d: gap %.2f s  1t %7.1f  5t %8.1f' % (
                cls, lv, len(b['spells']), b['gap'], b['dps1'], b['dps5'])
            if h and h['dps1'] and h['dps5']:
                line += ' | C4 kit (%d): gap %.2f s  1t %7.1f  5t %8.1f  ->  1t %+.1f%%  5t %+.1f%%' % (
                    len(h['spells']), h['gap'], h['dps1'], h['dps5'], 100 * (b['dps1'] / h['dps1'] - 1),
                    100 * (b['dps5'] / h['dps5'] - 1))
            else:
                line += ' | C4 kit: no Chaos attack spell yet'
            print(line)
            print('                  %s' % fmt_set(b))
            if only_cls:
                for s in sorted(a['pool'], key=lambda s: -s.dmg):
                    print('                    %-26s cd %5.1f gcd %3.1f %s cast %.1f dmg %7.1f x%.1f' % (
                        s.name, s.cd, s.gcd, ('%s %.0f' % (s.sec, s.seccd)) if s.sec else '', s.cast, s.dmg,
                        s.dmg5 / s.dmg if s.dmg else 0))
            rows.append((cls, lv, b, h))
    return rows


LADDER_LEVEL = 300   # the damage per cast the cooldown ladder ranks by (the C4 measurement level)
LADDER_STEP = 2000   # ms between two rungs


def ladder(spells, model, level=LADDER_LEVEL):
    """The cooldown ladder (owner 2026-10-20: "faça todas as magias de ataque terem 2s de diferença, começando pela
    primeira delas. assim elas ficam com 2s, 4s, 6s de cooldown, da mais fraca pra mais forte"). Per class: the first
    attack spell (the lowest level, the class's level 8 spell) is rung 1, the others follow from the weakest to the
    strongest by the damage of one cast on one target at `level` (rotation_model.csv with the class's stats; an area
    spell by its main-target hit). A spell several classes share has one cooldown: the rung most of them give it (a tie:
    the lower). Returns ({name: cooldown ms}, {class: [(name, rung, damage)]}, [(name, {class: rung}, rung)])."""
    attack = [s for s in spells if s['group'] == 'attack']
    rungs, per_class = {}, {}
    for cls, _, _ in CLASSES:
        env = stats(cls, level)
        rows = [(evaluate(model[s['words']]['dmg'], env), s['level'], s['name']) for s in attack if cls in s['vocations']]
        if not rows:
            continue
        first = min(rows, key=lambda r: (r[1], r[0]))
        rows = [first] + sorted(r for r in rows if r is not first)
        per_class[cls] = [(n, i + 1, d) for i, (d, _, n) in enumerate(rows)]
        for n, rung, _ in per_class[cls]:
            rungs.setdefault(n, {})[cls] = rung
    final, conflicts = {}, []
    for n, by in rungs.items():
        counts = {}
        for r in by.values():
            counts[r] = counts.get(r, 0) + 1
        rung = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))[0][0]
        final[n] = rung * LADDER_STEP
        if len(counts) > 1:
            conflicts.append((n, by, rung))
    return final, per_class, sorted(conflicts)


def ladder_report(spells, model, check=False):
    final, per_class, conflicts = ladder(spells, model)
    cd = {s['name']: s['cooldown'] for s in spells if s['group'] == 'attack'}
    gcd = {s['name']: s['groupcooldown'] for s in spells if s['group'] == 'attack'}
    for cls, rows in per_class.items():
        print('%-12s %s' % (cls, ' < '.join('%s %d s%s' % (n, final[n] // 1000, '' if final[n] == rung * LADDER_STEP
                                                          else ' (rung %d)' % rung) for n, rung, _ in rows)))
    for n, by, rung in conflicts:
        print('shared: %s %s -> rung %d (%d s)' % (n, ', '.join('%s %d' % kv for kv in sorted(by.items())), rung,
                                                    rung * LADDER_STEP // 1000))
    wrong = ['%s: cooldown %d, the ladder %d' % (n, cd[n], c) for n, c in sorted(final.items()) if cd[n] != c]
    wrong += ['%s: group cooldown %d, not %d' % (n, g, int(GCD * 1000)) for n, g in sorted(gcd.items())
              if g != int(GCD * 1000)]
    for w in wrong:
        print('OFF THE LADDER ' + w)
    return 1 if wrong and check else 0


def main(argv):
    if '--ladder' in argv:
        spells, model = load_all()
        return ladder_report(spells, model, '--check' in argv)
    if '--export-stock' in argv:
        export_stock(argv[argv.index('--export-stock') + 1])
        return 0
    spells, model = load_all()
    cls = argv[argv.index('--class') + 1] if '--class' in argv else None
    lv = int(argv[argv.index('--level') + 1]) if '--level' in argv else None
    if '--mana' in argv:
        short = mana_report(spells, model, cls)
        print('%d class/level rows under %.0f s of mana' % (len(short), MANA_RUNWAY))
        return 1 if short and '--check' in argv else 0
    if '--heal' in argv:
        heal_report()
        return 0
    if '--report' in argv or cls or lv:
        report(spells, model, cls, lv)
    if '--write' in argv or '--check' in argv:
        text = client_data(spells, model)
        old = open(CLIENT_DATA, encoding='utf-8').read() if os.path.isfile(CLIENT_DATA) else ''
        if '--check' in argv:
            if old != text:
                print('%s is out of date: run python3 -I server/tools/rotation_sim.py --write' %
                      os.path.relpath(CLIENT_DATA, REPO))
                return 1
            print('%s is up to date' % os.path.relpath(CLIENT_DATA, REPO))
        elif old != text:
            open(CLIENT_DATA, 'w', encoding='utf-8').write(text)
            print('wrote %s' % os.path.relpath(CLIENT_DATA, REPO))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
