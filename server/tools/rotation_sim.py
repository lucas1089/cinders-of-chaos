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
change of a class's spell damage bounds the change of its total. Every spell's damage is x the class spell factor
of server/data/scripts/chaos/spell_factor_config.lua (owner, 2026-10-20), the table the server applies to spell hits.

--report prints, per class and level band (15 / 30 / 60 / 100 / 300 / 600 / 1000), the best set of at most 5 with
its gap and damage against the measured kit (the C4 harness: every Chaos attack spell of the class on cooldown);
--class / --level also list the class's spells with their numbers.
--mana [--check] [--class NAME]: the mana runway (owner, 2026-10-17: "Magias com custo de mana muito alto, difíceis de
manter"): per class and checked level, how long the best set runs from a full pool with the vocation's own regeneration
(mana_runway); a row under MANA_RUNWAY (15 s) is SHORT, and --check exits 1 on any. Checked up to MANA_MAX_LEVEL (1000):
every spell costs one fixed number at every level (owner 2026-10-21, server/README.md "Fixed spell costs"), so the
high bands are checked too; each row also shows the runway with the level regeneration of mana_flow_config.lua on top
(not part of the check). --check also fails when a spell's fixed cost is above a class's whole pool at the spell's
level (cost_fits).
--heal: Shadow Mend (the Thief line's self heal) at level 300 and 1000 against the measured self heal per second of the Ranger
line and the Illusionist (server/data/spells/README.md "Healing"): the formula of chaos_constants.lua, the cooldown and the
fixed mana cost of spells_chaos.xml, the base health of the data.
--ladder [--check]: the cooldown ladder per class (owner, 2026-10-20: the attack spells at 2, 4, 6 s ... from the
first to the strongest; O176, 2026-10-24: 2, 4, 6, 7 ... 13 s, LADDER_COOLDOWNS; ladder() below, server/data/spells/README.md "Cooldown ladder"); --check exits 1 when a spell's
cooldown or group cooldown is off it.
--quest: per class the gain of the level 500 attack (Q1) and of the level 1200 ultimate (Q3) over a character without the line spell
quests; --check also fails when Q1 adds less than 3% or more than 6% (mean of levels 500-800), less than 1.5% or more than 9% at any of
500, 600, 800, 1000 and 1200, Q3 less than 6% or more than 12% (level 1200), or both together less than 12% or more than 15% at 1200.
Every other number of this tool (best sets, reports, mana) is that character without quests; the helper data holds the presets of a
character with all of them.
--write / --check: client/overlay/modules/game_helperrotation/autorotation_data.lua (the helper's "Auto rotation"
button: the best set for every level where the class gets a new attack spell, and its heals). The file also holds the rotation
variants (O446: single, pack, mines; section "variants" below), written after the default block. --check also holds the
variants to their rules and the default block to rotation_default_digest.txt.
--variants [--class NAME] [--check]: per class at levels 100 / 500 / 1000 each variant against the default on 1 and 5 targets
(computed, not measured) and the findings; --check prints the rule problems and exits 1 on any. --variants --table prints the
markdown tables of server/data/spells/README.md "Rotation variants (O446)".
--write-digest: rotation_default_digest.txt, the sha256 of the default block (run it only when the default rows are meant to move).
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
# the class factor on spell damage the server applies (passivetree_effects.lua, spell_factor_core.lua)
SPELL_FACTOR = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'spell_factor_config.lua')

QUEST_SCALE = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'quest_spell_scale_config.lua')
GCD = 2.0                     # the attack group cooldown of nearly every attack spell
HORIZON = 120.0               # seconds simulated from a fresh start
MAX_SPELLS = 5
BANDS = (15, 30, 60, 100, 300, 600, 1000)
MANA_RUNWAY = 15.0                # a class's best set must run this many seconds on a full mana pool (see mana_runway)
MANA_MAX_LEVEL = 1000             # checked at the bands and preset levels up to here (fixed costs, 2026-10-21: up to 1000)
NO_PRESET = ('skip', 'utility')  # flags that keep a spell out of every rotation the simulator builds
# `ultimate` (line spell quests, level 1200): a spell that is not one of the 5 of a set. The helper casts it when it is ready, on
# top of the 5 (owner 2026-10-28: exempt from the rotation cap). It has no ladder rung and a fixed cooldown of ULT_COOLDOWN ms.
ULTIMATE = 'ultimate'
ULT_COOLDOWN = (35000, 50000)
ULT_LEVEL = 1200
MIN_PLAYER_ATTACK_INTERVAL = 0.333  # config.lua minPlayerAttackInterval (src-patches 0011, 0088: 3 per second, O426), seconds
CHI_HIT_INTERVAL = 2.0            # one chi per melee hit, at most one per 2 s (ChaosMonk.cfg.chi)
KEEP_SHARE = 0.95                 # a best set keeps 95% of the measured kit's damage when it can
GAP_FREE = 0.90                   # a set with no gap over 2 s wins when it has 90% of the best set's score (O136)
FILL_KEEP = 0.97                  # a free slot takes a spell when the set keeps 97% of its score (fill_slots, O157)
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


# the Beastmaster's wolves (O332): BITE is the bite of a wolf spell's maul, ChaosClasses.biteValues (biteLevel x level + biteSkill x
# distance skill of Chaos.classes.companion); WOLF is the owner's wolf factor (Pack Alpha and the Trials' minion damage,
# ChaosClasses.wolfFactor): 1 here, so presets, the ladder and the C4 comparison are those of a character with neither.
# companion_model.py sets it to look at an invested one (and clears the analyse cache, set_wolf below).
WOLF = 1.0
WOLF_LEVEL = 400  # the level of the second companion (Chaos.classes.companion.caps); PETS below
COMPANION_CONSTANTS = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'chaos_constants.lua')


@functools.lru_cache(maxsize=None)
def wolf_bite():
    """(biteLevel, biteSkill) of Chaos.classes.companion, a wolf spell's bite"""
    text = open(COMPANION_CONSTANTS, encoding='utf-8').read()
    return (float(re.search(r'biteLevel = ([0-9.]+)', text).group(1)), float(re.search(r'biteSkill = ([0-9.]+)', text).group(1)))


def set_wolf(factor):
    """look at a Beastmaster with this wolf factor (the sets found so far are forgotten)"""
    global WOLF
    WOLF = float(factor)
    _ANALYSED.clear()


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
    bite = wolf_bite()
    return {'L': float(level), 'l': level / 5.0, 'ML': ml, 'SK': sk, 'ATK': atk, 'P': p, 'FIST': fist,
            'BITE': bite[0] * level + bite[1] * sk, 'PETS': 2 if level >= WOLF_LEVEL else 1, 'WOLF': WOLF, 'cls': cls,
            'SMITE': smite_for(cls, level), 'TOSS': toss_for(cls, level), 'FLURRY': flurry_for(cls, level),
            'SWEEP': sweep_scale(), 'OFFHAND': OFFHAND.get(cls, 1.0), 'FAN': pack_scale('fan'),
            'SANCT': pack_scale('sanctified'), 'WAVE': pack_scale('shieldWave')}


@functools.lru_cache(maxsize=None)
def spell_factors():
    """{vocation id: factor} of ChaosSpellFactorConfig.byVocation (spell_factor_config.lua): the factor from the last
    point of the class's byLevel curve up, and the whole factor of a class without a curve"""
    text = open(SPELL_FACTOR, encoding='utf-8').read()
    block = re.search(r'byVocation\s*=\s*\{(.*?)\n\t\}', text, re.S).group(1)
    return {int(v): float(f) for v, f in re.findall(r'\[(\d+)\]\s*=\s*([0-9.]+)', block)}


@functools.lru_cache(maxsize=None)
def spell_curves():
    """{vocation id: [(level, factor), ...]} of ChaosSpellFactorConfig.byLevel: flat below the first point, linear
    between points (the rule of spell_factor_core.lua)"""
    text = open(SPELL_FACTOR, encoding='utf-8').read()
    m = re.search(r'byLevel\s*=\s*\{(.*?)\n\t\}', text, re.S)
    out = {}
    for v, pts in re.findall(r'\[(\d+)\]\s*=\s*\{((?:\s*\{\d+,\s*[0-9.]+\},?)+)\s*\}', m.group(1) if m else ''):
        out[int(v)] = [(int(a), float(b)) for a, b in re.findall(r'\{(\d+),\s*([0-9.]+)\}', pts)]
    return out


@functools.lru_cache(maxsize=None)
def extra_curves():
    """{vocation id: [(level, factor), ...]} of ChaosSpellFactorConfig.extra (O430): the extra target factor, the factor on a
    spell's hits on every target of a cast but the first (spell_factor_core.lua F.extraFor)"""
    text = open(SPELL_FACTOR, encoding='utf-8').read()
    m = re.search(r'\n\textra\s*=\s*\{(.*?)\n\t\}', text, re.S)
    out = {}
    for v, pts in re.findall(r'\[(\d+)\]\s*=\s*\{((?:\s*\{\d+,\s*[0-9.]+\},?)+)\s*\}', m.group(1) if m else ''):
        out[int(v)] = [(int(a), float(b)) for a, b in re.findall(r'\{(\d+),\s*([0-9.]+)\}', pts)]
    return out


def extra_factor(cls, level):
    """the extra target factor of class `cls` at `level` (1 when not listed). Only tools/class_dps_model.py uses it: the best
    sets, the pack and boss models and the quest bounds of this tool are the class baseline without it"""
    pts = extra_curves().get(VOC[cls])
    return interp(pts, level) if pts else 1.0


def spell_factor(cls, level=None):
    """the class spell factor of class `cls` at `level` (1 when not listed): every spell's damage of the model is x this"""
    v = VOC[cls]
    pts = spell_curves().get(v)
    if pts and level is not None:
        return interp(pts, level)
    return spell_factors().get(v, 1.0)


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
        # a line spell quest spell (needlearn="1": only its quest teaches it; server/README.md "Line spell quests")
        'quest': chaos and a.get('needlearn') == '1',
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
    for s in spells:
        s['ultimate'] = s['group'] == 'attack' and ULTIMATE in model[s['words']]['flags']
    return spells, model


def class_spells(spells, cls, level, group='attack'):
    return [s for s in spells if s['group'] == group and cls in s['vocations'] and s['level'] <= level]


# ---------------------------------------------------------------------------------------------------------- sim
class Spell(object):
    __slots__ = ('chaos', 'words', 'name', 'id', 'cd', 'gcd', 'sec', 'seccd', 'cast', 'dmg', 'dmg5', 'chi', 'gain', 'keep', 'area')


@functools.lru_cache(maxsize=None)
def quest_scales():
    """{spell name: {class name: factor}} of quest_spell_scale_config.lua: the class factor of a line spell quest spell (the spell
    is shared by three classes whose best sets differ; the factors put the gain of each class in bounds). A factor is a number or
    a curve [(level, factor), ...] (flat below the first point, linear between points, the last point's value above it), for a
    class whose best set drifts away from the spell with the level (the Necromancer line, the Beastmaster)"""
    text = open(QUEST_SCALE, encoding='utf-8').read() if os.path.isfile(QUEST_SCALE) else ''
    out = {}
    for name, body in re.findall(r'(?m)^\t\["([^"]+)"\]\s*=\s*\{(.*)\},?\s*$', text):
        row = {}
        for c, v in re.findall(r'\["([^"]+)"\]\s*=\s*(\{\{[^=]*?\}\}|[0-9.]+)', body):
            row[c] = [(float(a), float(b)) for a, b in re.findall(r'\{([0-9.]+),\s*([0-9.]+)\}', v)] if v.startswith('{') else float(v)
        out[name] = row
    return out


def quest_factor(name, cls, level):
    """the class factor of a quest spell at a level (quest_scales: a number, or a curve)"""
    f = quest_scales().get(name, {}).get(cls, 1.0)
    return interp(f, level) if isinstance(f, list) else f


def prepare(spells, model, cls, level, ultimates=False, allow=()):
    """the simulator's spells of a class at a level; the ultimates (flag `ultimate`) only with ultimates=True and then only
    them: they are no part of a set of 5. `allow`: words of NO_PRESET spells that join the pool anyway (the mines variant of
    the helper's rotation variants, O446: Seeker Mine); no caller but variant_pool passes it"""
    env = stats(cls, level)
    out = []
    for s in spells:
        m = model[s['words']]
        if (m['flags'] & set(NO_PRESET) and s['words'] not in allow) or (ULTIMATE in m['flags']) != ultimates:
            continue
        p = Spell()
        p.words, p.name, p.id, p.chaos = s['words'], s['name'], s['id'], s['chaos']
        p.cd = s['cooldown'] / 1000.0
        p.gcd = s['groupcooldown'] / 1000.0
        p.sec = s['secondarygroup']
        p.seccd = s['secondarygroupcooldown'] / 1000.0
        p.cast = s['cast'] / 1000.0
        p.dmg = evaluate(m['dmg'], env) * spell_factor(cls, level)  # the class spell factor (spell_factor_config.lua)
        if s.get('quest'):
            p.dmg *= quest_factor(s['name'], cls, level)  # quest_spell_scale_config.lua
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


def simulate(rotation, horizon=HORIZON, hits=None):
    """cast times of a priority rotation; returns (casts, gap, dmg1 per second, dmg5 per second). `hits`, a list, collects
    (landing time, hit on 1 target, hit on 5 targets, words) of every cast that lands inside the horizon (weakness_model.py)"""
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
            if hits is not None:
                hits.append((t + s.cast, hit, hit * (s.dmg5 / s.dmg if s.dmg else 0), s.words))
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
    rot, gap, d1, d5 = fill_slots(pool, rot, gap, d1, d5, limit)
    return {'spells': rot, 'gap': gap, 'dps1': d1, 'dps5': d5}


def fill_slots(pool, rot, gap, d1, d5, limit):
    """free slots (O157, owner 2026-10-24: the Thief's Gutting Slash, Razor Rain, Venom Spiral, Crescent Cut and Last
    Breath were missing from Auto setup): while the set has fewer than `limit` spells, the spell of the pool that keeps
    the gap and FILL_KEEP of the score joins it (the one with the best score first). A class always uses its five slots
    when a spell fits; a slot is left empty only when every spell left would cost more than FILL_LOSS of the damage."""
    base = score(d1, d5)
    while len(rot) < limit:
        pick = None
        for s in pool:
            if s in rot or s.keep:
                continue
            alt = order(rot + [s])
            _, g, a1, a5 = simulate(alt)
            if g > max(gap, GCD) + 1e-9 or score(a1, a5) < FILL_KEEP * base:
                continue
            if pick is None or score(a1, a5) > score(pick[2], pick[3]):
                pick = (alt, g, a1, a5)
        if pick is None:
            break
        rot, gap, d1, d5 = pick
        base = score(d1, d5)
    return rot, gap, d1, d5


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
    best_free = None  # the best set without a dead gap (GAP_FREE below)
    for k in range(max(1, len(keep)), min(limit, len(cands) + len(keep)) + 1):
        for combo in itertools.combinations(cands, k - len(keep)):
            rot = order(keep + list(combo))
            _, gap, d1, d5 = simulate(rot)
            share = min(d1 / ref['dps1'], d5 / ref['dps5']) if ref and ref['dps1'] and ref['dps5'] else 1.0
            short = share < KEEP_SHARE
            key = (short, -round(share, 3) if short else 0, -score(d1, d5), k)
            if best is None or key < best[0]:
                best = (key, rot, gap, d1, d5)
            if gap <= GCD + 1e-9 and (best_free is None or key < best_free[0]):
                best_free = (key, rot, gap, d1, d5)
    # no dead gap (O136, owner 2026-10-22: no long gaps in a rotation): a set that casts on every attack group cooldown
    # wins when it keeps GAP_FREE of the best set's score
    if best_free is not None and best_free is not best and \
            score(best_free[3], best_free[4]) >= GAP_FREE * score(best[3], best[4]):
        best = best_free
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


def quest_spell_ok(s, quest):
    """is the spell part of a character with `quest` quests done: 0 none (the baseline every balance model measures), 1 the
    level 500 attack, 3 the level 500 attack and the level 1200 ultimate"""
    if not s.get('quest'):
        return True
    return quest >= (3 if s.get('ultimate') else 1)


def analyse(spells, model, cls, level, quest=0):
    """the best set of a class at a level. `quest` 0 (default) is a character without the line spell quests: every balance model
    (pack_model, minion_model, boss_model, weapon_sim, tower_model) measures that baseline. quest 1 adds the level 500 attack,
    quest 3 the level 500 attack and the ultimate on top of the 5 (quest_report below prints the gains)."""
    key = (id(spells), id(model), cls, level, quest)  # the callers pass the same loaded lists: the search runs once per class and level
    if key not in _ANALYSED:
        if quest:
            base = analyse(spells, model, cls, level, 0)
            have = [s for s in class_spells(spells, cls, level) if s.get('quest') and quest_spell_ok(s, quest)]
            best = with_quest_attack(base['best'], prepare(have, model, cls, level))
            best = with_ultimates(best, prepare(have, model, cls, level, True))
            _ANALYSED[key] = {'pool': base['pool'], 'best': best, 'all': base['all']}
        else:
            have = [s for s in class_spells(spells, cls, level) if quest_spell_ok(s, 0)]
            pool = prepare(have, model, cls, level)
            best = best_set(pool)
            best = with_ultimates(mana_fit(best, pool, spells, cls, level), [])
            _ANALYSED[key] = {'pool': pool, 'best': best, 'all': harness(pool)}
    return _ANALYSED[key]


def with_quest_attack(best, quest_spells):
    """The best set of a character with the level 500 attack: the baseline set, or the baseline set with one of its spells swapped
    for the attack when that scores more (a fixed swap, not a new search: the set search keeps a gap and a share of the measured
    kit, so a new search jumps between sets and the gain of the attack would be noise). The set stays at most 5 spells."""
    if not best or not quest_spells:
        return best
    top = (score(best['dps1'], best['dps5']), None)
    for q in quest_spells:
        for drop in best['spells']:
            rot = order([s for s in best['spells'] if s is not drop] + [q])
            _, gap, d1, d5 = simulate(rot)
            if score(d1, d5) > top[0]:
                top = (score(d1, d5), {'spells': rot, 'gap': gap, 'dps1': d1, 'dps5': d5})
        if len(best['spells']) < MAX_SPELLS:  # a free slot: the attack joins the set
            rot = order(best['spells'] + [q])
            _, gap, d1, d5 = simulate(rot)
            if score(d1, d5) > top[0]:
                top = (score(d1, d5), {'spells': rot, 'gap': gap, 'dps1': d1, 'dps5': d5})
    return top[1] or best


def with_ultimates(best, ults):
    """The class's ultimates on top of its best set of 5 (owner 2026-10-28: they take no preset slot). An ultimate casts once
    per cooldown and the cast takes one attack group cooldown (GCD) away from the set, whose rotation casts on every group
    cooldown, so it adds (its hit - GCD x the set's damage per second) / cooldown, no more. best['dps1'] and ['dps5'] include
    it; best['base1'], ['base5'] are the set alone and best['ult1'], ['ult5'] what the ultimate adds, best['ultimates'] the
    spells. A chi finisher counts at 4 chi (the least it waits for)."""
    if not best:
        return best
    best = dict(best, base1=best['dps1'], base5=best['dps5'], ult1=0.0, ult5=0.0, ultimates=list(ults))
    if not ults:
        return best
    for u in ults:
        k = (0.30 + 0.14 * 4) if u.chi else 1.0
        best['ult1'] += max(0.0, u.dmg * k - GCD * best['base1']) / u.cd
        best['ult5'] += max(0.0, u.dmg5 * k - GCD * best['base5']) / u.cd
    best['dps1'] += best['ult1']
    best['dps5'] += best['ult5']
    return best


# ---------------------------------------------------------------------------------------------------------- client
def breakpoints(spells, model, cls):
    """the levels where the class gets a new attack spell the rotation can use, and the level bands (the stats grow)"""
    lv = {s['level'] for s in spells if s['group'] == 'attack' and cls in s['vocations'] and
          not model[s['words']]['flags'] & set(NO_PRESET + (ULTIMATE,))}
    steps = {b for b in BANDS if b >= min(lv)} if lv else set()
    if cls == 'Beastmaster' and lv:
        steps.add(WOLF_LEVEL)  # the second companion (O332): the wolf spells deal twice as much, so the best set changes
    return sorted(lv | steps)


def creatures(rotation, model):
    """the helper's monster count per spell: always 1 (O430, owner 2026-11-06). Until then an area spell (3+ of the pack) waited
    for 2 monsters when the rotation had a single-target spell to cast on a lone target, so the classes built on area spells
    (Sentinel, Inquisitor, Templar, Mystic) cast one or two spells on a boss and fell back to the auto attack (the measured DPS
    of 2026-11-06: -50 to -77% of the median on one target). An area spell hits a lone target too, so it casts there as well;
    on a pack the area spells still go first (autorotation.lua areaFirst), the same order as before."""
    return [1 for _ in rotation]


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
    """the whole autorotation_data.lua: the default block (client_data_default, byte for byte what it was before the variants,
    held by rotation_default_digest.txt) and the variants block (O446) after it"""
    return client_data_default(spells, model) + variants_text(spells, model)


def client_data_default(spells, model):
    out = ['-- GENERATED by server/tools/rotation_sim.py --write from the server spell data and',
           '-- server/data/spells/rotation_model.csv. Do not edit.',
           '-- ChaosAutoRotationData.classes[serverVocationId] = { name, presets = { { level, gap, spells = { id, ... },',
           '--   creatures = { n, ... } } },',
           '--   extras = { id, ... } (the attack spells no preset holds, newest first; the helper tops up with them last),',
           '--   ultimate = id (the class line\'s level 1200 ultimate: not one of the 5, the helper casts it when ready),',
           '--   heals = { { id, level }, ... } }; a preset is the best rotation of at most 5 attack spells from its level on',
           '-- (the first spell first), gap = its longest time between two casts in seconds. spells[id] = the spell numbers of every attack spell.',
           'ChaosAutoRotationData = {', '  gcd = %.1f,' % GCD, '  classes = {']
    used = {}
    for cls, _, _ in CLASSES:
        out.append('    [%d] = { name = %s, presets = {' % (VOC[cls], lua_str(cls)))
        last, held = None, set()
        for lv in breakpoints(spells, model, cls):
            r = best_set(prepare(class_spells(spells, cls, lv), model, cls, lv))
            if not r:
                continue
            ids = [s.id for s in r['spells']]
            if ids == last:
                continue
            last = ids
            held.update(ids)
            for s in r['spells']:
                used[s.id] = s
            crowd = creatures(r['spells'], model)
            out.append('      { level = %d, gap = %.2f, spells = { %s }, creatures = { %s } },' % (
                lv, r['gap'], ', '.join(map(str, ids)), ', '.join(map(str, crowd))))
        # attack spells of the class no preset holds (a weaker single hit, a chi builder): the helper's top-up takes them
        # last, newest first, so every attack spell can be in Auto setup's rotation (O157)
        extra = sorted((x for x in spells if x['group'] == 'attack' and cls in x['vocations'] and x['id'] not in held and
                        not model[x['words']]['flags'] & set(NO_PRESET + (ULTIMATE,))), key=lambda x: (-x['level'], x['id']))
        # the class's ultimate (one per class line; not one of the 5 of a preset, cast by the helper when it is ready)
        ult = [x for x in spells if x['group'] == 'attack' and cls in x['vocations'] and
               ULTIMATE in model[x['words']]['flags']]
        out.append('    }, %s%sheals = {' % ('extras = { %s }, ' % ', '.join(str(x['id']) for x in extra) if extra else '',
                                             'ultimate = %d, ' % ult[0]['id'] if ult else ''))
        for h in heals(spells, cls)[:3]:
            out.append('      { id = %d, level = %d },' % (h['id'], h['level']))
        out.append('    } },')
    out.append('  },')
    out.append('  spells = {')
    # every attack spell the rotation can take is in the table, used by a preset or not (O157): the helper's top-up and
    # Auto setup look a spell up here, and a kit spell that is in no preset (Tidal Palm, Rampart Quake) was unknown
    byid = {}
    for s in spells:
        if s['group'] == 'attack' and not model[s['words']]['flags'] & set(NO_PRESET):
            byid[s['id']] = s
    for sid in sorted(byid):
        s = byid[sid]
        p = used.get(sid)
        chi = p.chi if p else 'chi' in model[s['words']]['flags']
        out.append('    [%d] = { name = %s, words = %s, cooldown = %d, groupCooldown = %d, secondaryGroup = %s, '
                   'secondaryCooldown = %d, cast = %d, area = %s, chi = %s },' % (
                       sid, lua_str(s['name']), lua_str(s['words']), s['cooldown'], s['groupcooldown'],
                       lua_str(s['secondarygroup']), s['secondarygroupcooldown'], s['cast'],
                       'true' if model[s['words']]['t5'] >= 3 else 'false', 'true' if chi else 'false'))
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


MANA_FLOW = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'mana_flow_config.lua')


@functools.lru_cache(maxsize=None)
def flow_curve():
    """(fromLevel, [(level, mana a second)]) of mana_flow_config.lua: the regeneration every class gets by level"""
    text = open(MANA_FLOW, encoding='utf-8').read()
    start = int(re.search(r'fromLevel = (\d+)', text).group(1))
    curve = re.search(r'curve = \{(.*?)\}\s*\n', text, re.S).group(1)
    return start, [(int(l), float(v)) for l, v in re.findall(r'\{(\d+), ([\d.]+)\}', curve)]


def flow_regen(level):
    """mana a second of the mana flow at a level (mana_flow_core.lua regenPerSecond)"""
    start, curve = flow_curve()
    return 0.0 if level < start else interp(curve, level)


def all_spells():
    """every Chaos instant (attack, healing, support) and the stock attack and healing spells, with their fixed costs"""
    return [spell_row(a, vocs, True) for a, vocs in instants(open(CHAOS_XML, encoding='utf-8').read())] + load_stock()


def cost_fits(spells=None):
    """[(spell, class, level, cost, pool)] of every spell whose fixed cost is above a class's whole pool at the spell's
    own level (no class could ever cast it there); empty when every cost fits"""
    bad = []
    for s in (all_spells() if spells is None else spells):
        for cls in s['vocations']:
            if cls not in VOC:
                continue
            lv = max(s['level'], 8)
            pool = mana_pool(cls, lv)
            if s['mana'] > pool:
                bad.append((s['name'], cls, lv, s['mana'], pool))
    return bad


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
            net = r[3] - r[2] - flow_regen(lv)
            flow = '%7.1f s' % (r[1] / net) if net > 0 else '    inf  '
            print('%-12s %4d  pool %6d  regen %5.2f/s  spent %7.2f/s  runway %7.1f s%s  with level regen %s  %s' % (
                cls, lv, r[1], r[2], r[3], r[0], '  SHORT' if flag else '', flow,
                ' > '.join('%s %d' % c for c in r[4])))
    return short


# ---------------------------------------------------------------------------------------------------------- healing
CONSTANTS = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'chaos_constants.lua')
HEAL_INT = 1.2                    # intelligence 20: the engine adds 20% to every non-physical value (the harness)
HEAL_ML = {300: 30, 1000: 40}     # the harness's magic level of the Thief line (server/data/spells/README.md "Healing")
HEAL_REF = {300: {'Ranger line': 798, 'Illusionist': 1538}, 1000: {'Ranger line': 1180, 'Illusionist': 2317}}  # measured self heal /s


def shadow_mend_cfg():
    """{perLevel, perMagicLevel, maxHealthShare, spread} of Chaos.classes.shadowMend, and the spell's cooldown (ms) and
    fixed mana cost from spells_chaos.xml"""
    text = open(CONSTANTS, encoding='utf-8').read()
    m = re.search(r'shadowMend = \{([^}]*)\}', text)
    cfg = {k: float(v) for k, v in re.findall(r'(\w+) = ([\d.]+)', m.group(1))}
    xml = open(CHAOS_XML, encoding='utf-8').read()
    a = attrs(re.search(r'<instant\b[^>]*name="Shadow Mend"[^>]*>', xml).group(0))
    cfg['cooldown'] = int(a['cooldown'])
    cfg['mana'] = float(a['mana'])
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
    cost = c['mana']
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


# ----------------------------------------------------------------------------------------------------- quest gain
QUEST1_LEVELS = (500, 600, 800, 1000)   # the levels the level 500 attack's gain is printed at
QUEST1_CHECK = (500, 600, 800)          # and checked at: the mean of these is in Q1_GAIN and none is outside Q1_EDGE
Q1_GAIN = (0.03, 0.06)                  # the level 500 attack adds this much of the baseline best-set score (--check)
Q1_EDGE = (0.015, 0.09)                 # no single level of QUEST1_EDGE_LEVELS is further out than this (class identity pass 2026-10-28: 1000
                                        # and 1200 count too; a class whose best set drifts away from the spell has a factor curve, see
                                        # quest_spell_scale_config.lua)
QUEST1_EDGE_LEVELS = (500, 600, 800, 1000, 1200)
Q_BOTH = (0.12, 0.15)                   # both quests together at level 1200 add this much (a full quester; --check)
Q3_GAIN = (0.06, 0.12)                  # the level 1200 ultimate adds this much on top (--check)


def quest_gain(spells, model, cls, level):
    """(gain of the level 500 attack, gain of the ultimate on top of it) as a share of the baseline best-set score (1 target +
    0.25 x pack) of a character without quests: (S1 - S0) / S0 and (S3 - S1) / S0. The ultimate counts from level 1200 only."""
    s = []
    for q in (0, 1, 3):
        b = analyse(spells, model, cls, level, q)['best']
        s.append(score(b['dps1'], b['dps5']) if b else 0.0)
    if not s[0]:
        return 0.0, 0.0
    return (s[1] - s[0]) / s[0], (s[2] - s[1]) / s[0]


def quest_bad(spells, model):
    """the classes whose quest gain is out of bounds (quest_report without the printing)"""
    import io, contextlib
    with contextlib.redirect_stdout(io.StringIO()):
        return quest_report(spells, model)


def quest_report(spells, model, only_cls=None, check=False):
    """prints per class the gain of Q1 (levels 500-1000) and of Q3 (level 1200, on top of Q1) over the baseline best set; with
    check=True returns the classes out of Q1_GAIN / Q3_GAIN"""
    bad = []
    for cls, _, _ in CLASSES:
        if only_cls and cls != only_cls:
            continue
        row = []
        for lv in QUEST1_LEVELS:
            q1, _ = quest_gain(spells, model, cls, lv)
            row.append(q1)
            if lv in QUEST1_EDGE_LEVELS and not Q1_EDGE[0] <= q1 <= Q1_EDGE[1]:
                bad.append('%s level %d: the level 500 attack adds %.1f%%, not %.1f-%.1f%%' % (
                    cls, lv, 100 * q1, 100 * Q1_EDGE[0], 100 * Q1_EDGE[1]))
        mean = sum(g for g, lv in zip(row, QUEST1_LEVELS) if lv in QUEST1_CHECK) / len(QUEST1_CHECK)
        if not Q1_GAIN[0] <= mean <= Q1_GAIN[1]:
            bad.append('%s: the level 500 attack adds %.1f%% on average (levels %s), not %d-%d%%' % (
                cls, 100 * mean, ', '.join(map(str, QUEST1_CHECK)), 100 * Q1_GAIN[0], 100 * Q1_GAIN[1]))
        q1, q3 = quest_gain(spells, model, cls, ULT_LEVEL)
        if not Q1_EDGE[0] <= q1 <= Q1_EDGE[1]:
            bad.append('%s level %d: the level 500 attack adds %.1f%%, not %.1f-%.1f%%' % (
                cls, ULT_LEVEL, 100 * q1, 100 * Q1_EDGE[0], 100 * Q1_EDGE[1]))
        if not Q_BOTH[0] <= q1 + q3 <= Q_BOTH[1]:
            bad.append('%s level %d: both quests add %.1f%%, not %d-%d%%' % (
                cls, ULT_LEVEL, 100 * (q1 + q3), 100 * Q_BOTH[0], 100 * Q_BOTH[1]))
        if not Q3_GAIN[0] <= q3 <= Q3_GAIN[1]:
            bad.append('%s level %d: the ultimate adds %.1f%%, not %d-%d%%' % (cls, ULT_LEVEL, 100 * q3, 100 * Q3_GAIN[0], 100 * Q3_GAIN[1]))
        print('%-12s Q1 %s   level %d: Q1 %+5.1f%%  Q3 %+5.1f%%  both %+5.1f%%' % (
            cls, ' '.join('%5.1f%%' % (100 * g) for g in row), ULT_LEVEL, 100 * q1, 100 * q3, 100 * (q1 + q3)))
    return bad


LADDER_LEVEL = 300   # the damage per cast the cooldown ladder ranks by (the C4 measurement level)
LADDER_STEP = 2000   # ms between two rungs of the first LADDER_FLAT rungs
# the cooldown of rung 1, 2, 3 ... 10 (ms). O176 (owner 2026-10-24: "diminua o cooldown das magias mais fortes, para aumentar
# a DPS de todas as classes"): 2, 4, 6 s as before (O94), then one second a rung instead of two: 7, 8 ... 13 s. The strongest
# rungs lose 25 to 35% (was 12, 14, 16, 18, 20 s: 9, 10, 11, 12, 13 s); a rung stays above the one below it.
LADDER_COOLDOWNS = (2000, 4000, 6000, 7000, 8000, 9000, 10000, 11000, 12000, 13000)
# O474 (2026-11-10): the damage over time rule (side dots 0.30 x the hit, Soul Rot x1.5, Blightbrand x1.25, Martyr's Pyre x1.1) raised the
# damage per cast of six spells and would have moved seven cooldowns by the ladder (Witchfire Bolt 7 -> 9 s, Falling Pyre 10 -> 11, Soul Rot
# 11 -> 13, Blightbrand 12 -> 13, Briar Prison 8 -> 7, Tempest Fan 9 -> 8, Crypt Collapse 13 -> 12). A longer wait would take back the gain the
# change is for, and a dot lands in full only on a target that lives (server/README.md "Damage over time (O474)"). So the ladder ranks these
# six spells by their `dmg` of before (words -> expression); every cooldown stays. Owner's call in the final re-fit: remove an entry to let
# the ladder move that spell.
LADDER_HOLD = {
    'kah pyr vesh': 'avg(l+ML*3+15,l+ML*5+30)*1.2+4*(ML*0.15+3)',                  # Witchfire Bolt
    'drai gal vas infr': 'avg(l+ML*6.6+145,l+ML*10.8+265)*1.2+4*(ML*0.2+5)',        # Falling Pyre
    'kah mynd frak': 'avg(l+ML*5.7+55,l+ML*9.7+100)*1.4+5*(ML*0.3+4)',              # Shattered Psyche
    'kah nyx putr': '6*avg(l+ML*1.2+20,l+ML*1.6+40)*1.15',                           # Soul Rot
    'kah putr brak': '6*avg(l+ML*1.949+8,l+ML*3.118+16)',                            # Blightbrand
    'kah sol pyr': '5*avg(l+P*0.0258+ML*0.5+8,l+P*0.0413+ML*0.8+16)',                # Martyr's Pyre
}


QUEST_COOLDOWN = 13000   # a line spell quest attack (level 500) is not ranked: it sits above the ladder at the last rung's 13 s


def rung_cooldown(rung):
    """the cooldown (ms) of rung `rung` (1 = the first spell); a class has at most 10 attack spells (O133)"""
    return LADDER_COOLDOWNS[min(rung, len(LADDER_COOLDOWNS)) - 1]


def ladder(spells, model, level=LADDER_LEVEL):
    """The cooldown ladder (owner 2026-10-20: "faça todas as magias de ataque terem 2s de diferença, começando pela
    primeira delas. assim elas ficam com 2s, 4s, 6s de cooldown, da mais fraca pra mais forte"). Per class: the first
    attack spell (the lowest level, the class's level 8 spell) is rung 1, the others follow from the weakest to the
    strongest by the damage of one cast on one target at `level` (rotation_model.csv with the class's stats; an area
    spell by its main-target hit). A spell several classes share has one cooldown: the rung most of them give it (a tie:
    the lower). The cooldown of a rung is LADDER_COOLDOWNS (O176). The line spell quest attacks (needlearn="1") are not ranked: they are the last rung of their classes at QUEST_COOLDOWN. Returns ({name: cooldown ms}, {class: [(name, rung, damage)]}, [(name, {class: rung}, rung)])."""
    attack = [s for s in spells if s['group'] == 'attack' and not s.get('quest')]
    quest = [s for s in spells if s['group'] == 'attack' and s.get('quest') and not s.get('ultimate')]
    rungs, per_class = {}, {}
    for cls, _, _ in CLASSES:
        env = stats(cls, level)
        rows = [(evaluate(LADDER_HOLD.get(s['words'], model[s['words']]['dmg']), env), s['level'], s['name'])
                for s in attack if cls in s['vocations']]
        if not rows:
            continue
        first = min(rows, key=lambda r: (r[1], r[0]))
        rows = [first] + sorted(r for r in rows if r is not first)
        per_class[cls] = [(n, i + 1, d) for i, (d, _, n) in enumerate(rows)]
        # the quest spells (level 500) come last whatever they deal: the line's reward is above its whole ladder
        for s in quest:
            if cls in s['vocations']:
                per_class[cls].append((s['name'], len(per_class[cls]) + 1, evaluate(model[s['words']]['dmg'], env)))
        for n, rung, _ in per_class[cls]:
            rungs.setdefault(n, {})[cls] = rung
    final, conflicts = {}, []
    for n, by in rungs.items():
        counts = {}
        for r in by.values():
            counts[r] = counts.get(r, 0) + 1
        rung = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))[0][0]
        final[n] = QUEST_COOLDOWN if n in {s['name'] for s in quest} else rung_cooldown(rung)
        if len(counts) > 1:
            conflicts.append((n, by, rung))
    return final, per_class, sorted(conflicts)


def ladder_report(spells, model, check=False):
    final, per_class, conflicts = ladder(spells, model)
    cd = {s['name']: s['cooldown'] for s in spells if s['group'] == 'attack'}
    gcd = {s['name']: s['groupcooldown'] for s in spells if s['group'] == 'attack'}
    for cls, rows in per_class.items():
        print('%-12s %s' % (cls, ' < '.join('%s %d s%s' % (n, final[n] // 1000, '' if final[n] == rung_cooldown(rung)
                                                          else ' (rung %d)' % rung) for n, rung, _ in rows)))
    for n, by, rung in conflicts:
        print('shared: %s %s -> rung %d (%d s)' % (n, ', '.join('%s %d' % kv for kv in sorted(by.items())), rung,
                                                    rung_cooldown(rung) // 1000))
    wrong = ['%s: cooldown %d, the ladder %d' % (n, cd[n], c) for n, c in sorted(final.items()) if cd[n] != c]
    # an ultimate (line spell quest 3) has no rung: its cooldown is one fixed number between ULT_COOLDOWN
    for s in spells:
        if s.get('ultimate'):
            print('ultimate %s %d s, level %d' % (s['name'], s['cooldown'] // 1000, s['level']))
            if not ULT_COOLDOWN[0] <= s['cooldown'] <= ULT_COOLDOWN[1]:
                wrong.append('%s: ultimate cooldown %d, not %d to %d' % (s['name'], s['cooldown'], *ULT_COOLDOWN))
            if s['level'] != ULT_LEVEL:
                wrong.append('%s: ultimate level %d, not %d' % (s['name'], s['level'], ULT_LEVEL))
    wrong += ['%s: group cooldown %d, not %d' % (n, g, int(GCD * 1000)) for n, g in sorted(gcd.items())
              if g != int(GCD * 1000)]
    for w in wrong:
        print('OFF THE LADDER ' + w)
    return 1 if wrong and check else 0


# ----------------------------------------------------------------------------------------------- variants (O446)
# Owner decision 2026-11-09: the Auto rotation gets variants, so that a build can be played with low attention and not only
# with the default set. A variant is another list of at most 5 spells from the same pool, found by the same simulator, kept
# next to the default (never in its place): the default rows of autorotation_data.lua are byte for byte what they were and
# rotation_default_digest.txt holds their sha256 (--check fails when they move). Computed, not measured.
#   single  the best set on 1 target (a boss)
#   pack    the best set on 5 targets
#   mines   only for the classes that hold Seeker Mine: the best set with Seeker Mine in it (see mine_rhythm)
# Rules (owner 2026-11-10): a variant is at most +VAR_MAX_GAIN over the default in its specialty (never above: the best set
# under the cap is the variant), and a single or pack variant pays a visible price on the other count (VAR_MIN_PRICE); a variant
# that is the default at a level is not listed there. It keeps the default's rules: spells the class holds at the level, the 2 s
# gap (a few defaults hold a longer one), the mana runway. The mines variant has no gain and no price filter: it is the best
# set with the mine in it, its price is the late burst and the moving pack (mine_rhythm), outside the standing dummies; where it
# beats the default on both counts that is a finding.
SNARES = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'snares_config.lua')
DEFAULT_DIGEST = os.path.join(SPELLS, 'rotation_default_digest.txt')
VARIANTS = ('single', 'pack', 'mines')
VAR_MAX_GAIN = 0.40               # owner rule: no variant above +40% over the default in its specialty
VAR_FLAG_GAIN = 0.25              # owner rule: flag any above +25%
VAR_MIN_GAIN = 0.05               # a variant that gains less than this in its specialty is not offered
VAR_MIN_PRICE = 0.03              # a specialist pays at least this on the other target count
MINE_WORDS = 'kah snar'           # Seeker Mine: the spell of the mines variant
MINE_MOVING_LOSS = 0.33           # measured in game (README "Snares, vigils and Hollow Vessel measured in game"): a moving pack costs the snares a third


@functools.lru_cache(maxsize=None)
def mine_cfg():
    """the numbers of the mines from snares_config.lua: arm, fuse, burst targets, stagger (ms), damage factor, the cap"""
    text = open(SNARES, encoding='utf-8').read()
    block = re.search(r'\n\tmine = \{(.*?)\}', text, re.S).group(1)
    cfg = {k: float(v) for k, v in re.findall(r'(\w+) = ([0-9.]+)', block)}
    cfg['cap'] = int(re.search(r'caps = \{[^}]*\bmine = (\d+)', text).group(1))
    return cfg


def mine_rhythm(cooldown):
    """The mine as a rhythm of place, wait, detonate, from snares_config.lua. A mine is thrown (one cast, `cooldown` s, the
    attack group), armed armMs later, and goes off when Detonate Mines is cast (cooldown 1 s, no group: it never takes an attack
    slot) or, with nobody casting it, at the end of its fuse, fuseMs after it is armed: arm + fuse after the throw at the latest.
    At the throw rate of the cooldown a mine lives that long, so `live` mines are out at once and the cap must hold them; the
    burst takes at most maxTargets enemies and a pack of 5 fits. The hit is the trap hit x damageFactor (rotation_model.csv row).
    The damage per second does not depend on when a mine goes off, only on how often it is thrown, so the simulator counts a
    mine like any spell of that cooldown and the helper needs no Detonate Mines rule: the fuse is the rhythm. What the model
    cannot see is the pack that walks off before the burst: MINE_MOVING_LOSS (measured) stands for it. Returns (live, life s)."""
    c = mine_cfg()
    life = (c['armMs'] + c['fuseMs']) / 1000.0
    return int(math.ceil(life / cooldown)), life


def mine_classes(spells):
    """the classes that hold Seeker Mine, from the spell data"""
    return [cls for cls, _, _ in CLASSES if any(s['words'] == MINE_WORDS and cls in s['vocations'] for s in spells)]


def variant_pool(spells, model, cls, level, mines=False):
    """the pool of the default set (the helper data's: quest attacks included) and, with mines, Seeker Mine in it"""
    return prepare(class_spells(spells, cls, level), model, cls, level, allow=(MINE_WORDS,) if mines else ())


def all_sets(pool, limit=MAX_SPELLS):
    """every rotation of at most `limit` spells of the pool, a debuff kept up (flag keep) always in it, in priority order"""
    keep = [s for s in pool if s.keep]
    rest = [s for s in pool if not s.keep]
    for k in range(max(1, len(keep)), min(limit, len(rest) + len(keep)) + 1):
        for combo in itertools.combinations(rest, k - len(keep)):
            yield order(keep + list(combo))


def set_stats(rot, cost, cls, level):
    """(gap, 1 target per second, 5 targets per second, mana runway in s, the mine's part of the 5 targets per second)"""
    hits = []
    casts, gap, d1, d5 = simulate(rot, hits=hits)
    spent = sum(cost[w] for _, w in casts) / HORIZON
    net = spent - mana_stats()[cls][2]
    run = mana_pool(cls, level) / net if net > 0 else float('inf')
    mine5 = sum(h[2] for h in hits if h[3] == MINE_WORDS) / HORIZON
    return gap, d1, d5, run, mine5


def choose_variants(sets, a1, a5, mines):
    """({variant: set or None}, a set better than the default on both counts or None) from the legal sets of a level and the default's
    damage per second on 1 target (a1) and on 5 targets (a5). The rules of the section header: single and pack are the best set for
    their count between VAR_MIN_GAIN and VAR_MAX_GAIN over the default with a price of VAR_MIN_PRICE on the other count; mines is the
    best score with the mine, under the cap on both counts."""
    found = {}
    pick = lambda ok, key: min((s for s in sets if ok(s)), key=key, default=None)
    ids = lambda s: tuple(x.id for x in s['rot'])
    tie = lambda s: (-len(s['rot']), ids(s))
    up1, up5 = (1 + VAR_MAX_GAIN) * a1, (1 + VAR_MAX_GAIN) * a5      # the cap
    gain1, gain5 = (1 + VAR_MIN_GAIN) * a1, (1 + VAR_MIN_GAIN) * a5
    low1, low5 = (1 - VAR_MIN_PRICE) * a1, (1 - VAR_MIN_PRICE) * a5  # the price
    plain = lambda s: not s['mine']
    found['single'] = pick(lambda s: plain(s) and gain1 <= s['d1'] <= up1 and s['d5'] <= low5,
                           lambda s: (-round(s['d1'] / a1, 3), -round(s['d5'] / a5, 3)) + tie(s))
    found['pack'] = pick(lambda s: plain(s) and gain5 <= s['d5'] <= up5 and s['d1'] <= low1,
                         lambda s: (-round(s['d5'] / a5, 3), -round(s['d1'] / a1, 3)) + tie(s))
    if mines:
        # the mines: the best score with Seeker Mine in the set, under the cap on both counts. No gain and no price filter: the
        # list differs from the default by the mine itself, it is for the builds that lay mines (Snarewright's Creed, Fusewright's
        # Charm: their bonuses are not in these numbers), and its price is the late burst and the pack that walks off (mine_rhythm,
        # MINE_MOVING_LOSS), which the standing dummies do not show. A set better on both counts is a finding (variants_report),
        # the default is not changed.
        found['mines'] = pick(lambda s: s['mine'] and s['d1'] <= up1 and s['d5'] <= up5,
                              lambda s: (-round(score(s['d1'], s['d5']), 3),) + tie(s))
    # a set better than the default on both counts (a finding, not a variant: the default is wrong there; owner 2026-11-10)
    both = [s for s in sets if s['d1'] >= (1 + VAR_MIN_PRICE) * a1 and s['d5'] >= (1 + VAR_MIN_PRICE) * a5]
    return found, min(both, key=lambda s: (-round(min(s['d1'] / a1, s['d5'] / a5), 3),) + tie(s), default=None)


_VARIANT_CACHE = {}


def variant_level(spells, model, cls, level):
    """The variants of a class at a level: {'default': {...}, 'sets': [every legal set with its numbers], and one entry per
    variant that exists here}. A set is legal when it casts at least every 2 s (the owner's rule: never 2 s without a spell; a
    few defaults hold a longer gap, a variant never does) and keeps the mana runway (MANA_RUNWAY, or the default's own when it
    is shorter)."""
    key = (id(spells), id(model), cls, level)
    if key in _VARIANT_CACHE:
        return _VARIANT_CACHE[key]
    mines = cls in mine_classes(spells) and any(s['words'] == MINE_WORDS and s['level'] <= level and cls in s['vocations']
                                                for s in spells)
    pool = variant_pool(spells, model, cls, level, mines)
    base = best_set([s for s in pool if s.words != MINE_WORDS])
    out = {'default': None, 'sets': [], 'found': {}, 'both': None}
    if not base:
        _VARIANT_CACHE[key] = out
        return out
    cost = {s['words']: s['mana'] for s in spells if cls in s['vocations'] and s['group'] == 'attack'}
    g0, a1, a5, r0, _ = set_stats(base['spells'], cost, cls, level)
    out['default'] = {'rot': base['spells'], 'gap': g0, 'd1': a1, 'd5': a5, 'run': r0}
    gap_ok, run_ok = GCD + 1e-9, min(MANA_RUNWAY, r0)  # a few defaults hold a longer gap (README O446); a variant never does
    for rot in all_sets(pool):
        gap, d1, d5, run, mine5 = set_stats(rot, cost, cls, level)
        if gap > gap_ok or run < run_ok or not d1:
            continue
        out['sets'].append({'rot': rot, 'gap': gap, 'd1': d1, 'd5': d5, 'run': run, 'mine5': mine5,
                            'mine': any(s.words == MINE_WORDS for s in rot)})
    out['found'], out['both'] = choose_variants(out['sets'], a1, a5, mines)
    _VARIANT_CACHE[key] = out
    return out


def pct(x, base):
    return 100.0 * (x / base - 1.0) if base else 0.0


def variant_entries(spells, model, cls):
    """{variant: [entry]} of a class: one entry per level breakpoint where the variant exists and is not the default. An entry
    holds level, upTo (the next breakpoint, None for the last), the set (ids), its gap, the change against the default there in
    percent (one: 1 target, five: 5 targets, moving: 5 targets when a moving pack costs the mines MINE_MOVING_LOSS of their
    damage; the mines variant only)."""
    lvs = breakpoints(spells, model, cls)
    out = {}
    for i, lv in enumerate(lvs):
        v = variant_level(spells, model, cls, lv)
        d = v['default']
        if not d:
            continue
        for name in VARIANTS:
            s = v['found'].get(name)
            if not s or [x.id for x in s['rot']] == [x.id for x in d['rot']]:
                continue
            e = {'level': lv, 'upTo': lvs[i + 1] if i + 1 < len(lvs) else None, 'gap': s['gap'],
                 'ids': [x.id for x in s['rot']], 'one': pct(s['d1'], d['d1']), 'five': pct(s['d5'], d['d5'])}
            if name == 'mines':
                e['moving'] = pct(s['d5'] - MINE_MOVING_LOSS * s['mine5'], d['d5'])
            out.setdefault(name, []).append(e)
    return out


def variants_text(spells, model):
    """the variants block of autorotation_data.lua: ChaosAutoRotationData.variants = { names, classes, spells (the ones the main
    table lacks) }. Additive: a client that ignores it behaves as before."""
    out = ['', '-- ChaosAutoRotationData.variants (O446, owner 2026-11-09): the Auto rotation variants, written next to the default set',
           '-- and never in its place. classes[serverVocationId][name] = { { level, upTo, gap, spells = { id, ... }, creatures = { n, ... },',
           '--   one, five [, moving] }, ... }: the set from `level` up to (not including) `upTo` (nil: no end), its change against the',
           '-- default set in percent at that level on 1 target (one) and on 5 targets (five), computed by rotation_sim.py, not measured;',
           '-- moving: the mines variant on a pack that keeps moving (the measured loss of the mines). A level with no entry has no',
           '-- variant: the default set. spells = the attack spells of a variant that the main spells table lacks (Seeker Mine).',
           'ChaosAutoRotationData.variants = {', '  names = { %s },' % ', '.join(lua_str(n) for n in VARIANTS), '  classes = {']
    used = set()
    for cls, _, _ in CLASSES:
        ent = variant_entries(spells, model, cls)
        if not ent:
            continue
        out.append('    [%d] = {' % VOC[cls])
        for name in VARIANTS:
            if name not in ent:
                continue
            out.append('      %s = {' % name)
            for e in ent[name]:
                out.append('        { level = %d, upTo = %s, gap = %.2f, spells = { %s }, creatures = { %s }, one = %d, five = %d%s },' % (
                    e['level'], 'nil' if e['upTo'] is None else e['upTo'], e['gap'], ', '.join(map(str, e['ids'])),
                    ', '.join('1' for _ in e['ids']), round(e['one']), round(e['five']),
                    ', moving = %d' % round(e['moving']) if 'moving' in e else ''))
                used.update(e['ids'])
            out.append('      },')
        out.append('    },')
    out.append('  },')
    main_ids = {s['id'] for s in spells if s['group'] == 'attack' and not model[s['words']]['flags'] & set(NO_PRESET)}
    out.append('  spells = {')
    for s in sorted((s for s in spells if s['group'] == 'attack' and s['id'] in used and s['id'] not in main_ids),
                    key=lambda s: s['id']):
        out.append('    [%d] = { name = %s, words = %s, cooldown = %d, groupCooldown = %d, secondaryGroup = %s, '
                   'secondaryCooldown = %d, cast = %d, area = %s, chi = false },' % (
                       s['id'], lua_str(s['name']), lua_str(s['words']), s['cooldown'], s['groupcooldown'],
                       lua_str(s['secondarygroup']), s['secondarygroupcooldown'], s['cast'],
                       'true' if model[s['words']]['t5'] >= 3 else 'false'))
    out.append('  },')
    out.append('}')
    return '\n'.join(out) + '\n'


def default_digest(spells, model):
    """sha256 of the default block of autorotation_data.lua: what rotation_default_digest.txt holds"""
    import hashlib
    return hashlib.sha256(client_data_default(spells, model).encode('utf-8')).hexdigest()


def read_digest():
    return open(DEFAULT_DIGEST, encoding='utf-8').read().split()[0] if os.path.isfile(DEFAULT_DIGEST) else ''


def write_digest(spells, model):
    open(DEFAULT_DIGEST, 'w', encoding='utf-8').write(
        '%s  default block of client/overlay/modules/game_helperrotation/autorotation_data.lua (rotation_sim.py --write-digest)\n' %
        default_digest(spells, model))


VARIANT_REPORT_LEVELS = (100, 500, 1000)


def variant_rows(spells, model, levels=VARIANT_REPORT_LEVELS, only_cls=None):
    """[(class, level, default, {variant: set or None}, both)] for the report and the docs"""
    rows = []
    for cls, _, _ in CLASSES:
        if only_cls and cls != only_cls:
            continue
        for lv in levels:
            v = variant_level(spells, model, cls, lv)
            if v['default']:
                rows.append((cls, lv, v['default'], v['found'], v['both']))
    return rows


def variants_report(spells, model, only_cls=None):
    """prints, per class at levels 100 / 500 / 1000, each variant against the default on 1 and 5 targets (computed, not
    measured), the sets, and the findings: a set better than the default on both counts, a gain over VAR_FLAG_GAIN, a default
    with a gap over 2 s"""
    names = lambda rot: ' > '.join(s.name for s in rot)
    for cls, lv, d, found, both in variant_rows(spells, model, only_cls=only_cls):
        print('%-12s %4d  default 1t %7.1f  5t %8.1f  gap %.2f  runway %6.1f s  %s' % (
            cls, lv, d['d1'], d['d5'], d['gap'], d['run'], names(d['rot'])))
        for name in VARIANTS:
            if name == 'mines' and cls not in mine_classes(spells):
                continue
            s = found.get(name)
            if not s:
                print('               %-6s none (the default at this level)' % name)
                continue
            one, five = pct(s['d1'], d['d1']), pct(s['d5'], d['d5'])
            mv = ('  moving pack 5t %+5.1f%%' % pct(s['d5'] - MINE_MOVING_LOSS * s['mine5'], d['d5'])) if name == 'mines' else ''
            flag = '  FLAG over %d%%' % round(100 * VAR_FLAG_GAIN) if max(one, five) > 100 * VAR_FLAG_GAIN else ''
            print('               %-6s 1t %+6.1f%%  5t %+6.1f%%  gap %.2f  runway %6.1f s%s%s  %s' % (
                name, one, five, s['gap'], s['run'], mv, flag, names(s['rot'])))
        if both:
            print('               FINDING better on both counts: 1t %+.1f%%  5t %+.1f%%  %s' % (
                pct(both['d1'], d['d1']), pct(both['d5'], d['d5']), names(both['rot'])))
    for cls, _, _ in CLASSES:
        if only_cls and cls != only_cls:
            continue
        for lv in breakpoints(spells, model, cls):
            d = variant_level(spells, model, cls, lv)['default']
            if d and d['gap'] > GCD + 1e-9:
                print('FINDING default gap %.2f s: %s %d  %s' % (d['gap'], cls, lv, names(d['rot'])))


def variants_table(spells, model):
    """the two markdown tables of server/data/spells/README.md "Rotation variants (O446)": the variants against the default per
    class at levels 100 / 500 / 1000, and where each class has them (computed, not measured)"""
    out = ['| Class | Level | Default, 1 target / 5 targets | One target | Groups | Mines (moving pack, 5 targets) |',
           '|---|---:|---:|---:|---:|---:|']
    mine_cls = mine_classes(spells)
    for cls, lv, d, found, both in variant_rows(spells, model):
        cells = []
        for name in VARIANTS:
            s = found.get(name)
            if name == 'mines' and cls not in mine_cls:
                cells.append('-')
            elif not s:
                cells.append('none')
            else:
                one, five = pct(s['d1'], d['d1']), pct(s['d5'], d['d5'])
                cell = '%+.0f%% / %+.0f%%' % (one, five)
                if name == 'mines':
                    cell += ' (%+.0f%%)' % pct(s['d5'] - MINE_MOVING_LOSS * s['mine5'], d['d5'])
                cells.append(cell + (' flag' if max(one, five) > 100 * VAR_FLAG_GAIN else ''))
        out.append('| %s | %d | %.0f / %.0f | %s |' % (cls, lv, d['d1'], d['d5'], ' | '.join(cells)))
    out += ['', '| Class | One target | Groups | Mines |', '|---|---|---|---|']
    for cls, _, _ in CLASSES:
        lvs = breakpoints(spells, model, cls)
        ent = variant_entries(spells, model, cls)
        cells = []
        for name in VARIANTS:
            if name == 'mines' and cls not in mine_cls:
                cells.append('-')
                continue
            have = [e['level'] for e in ent.get(name, [])]
            cells.append('%d of %d levels, from %d' % (len(have), len(lvs), have[0]) if have else 'none')
        out.append('| %s | %s |' % (cls, ' | '.join(cells)))
    return out


def variants_check(spells, model):
    """the rules of the variants (O446) against the data: only spells the class holds at the level, at most 5, no duplicate, the
    mine only in the mines variant and only for the classes that hold it, a gap of at most 2 s, the mana runway of the default's
    rule, the cooldowns of the ladder, a gain between VAR_MIN_GAIN and VAR_MAX_GAIN in the specialty and a price on the other
    count, never the default's own set, the mine's rhythm inside the cap, the default block as the digest says. Returns the
    problems"""
    bad = []
    final, _, _ = ladder(spells, model)
    byid = {s['id']: s for s in spells if s['group'] == 'attack'}
    mine_cls = mine_classes(spells)
    live, life = mine_rhythm(byid[next(i for i, s in byid.items() if s['words'] == MINE_WORDS)]['cooldown'] / 1000.0)
    cfg = mine_cfg()
    if live > cfg['cap']:
        bad.append('the mine rhythm needs %d mines out at once (a mine lives %.1f s), the cap is %d' % (live, life, cfg['cap']))
    if model[MINE_WORDS]['t5'] > cfg['maxTargets']:
        bad.append('a mine burst takes at most %d targets, the pack model hits %d' % (cfg['maxTargets'], model[MINE_WORDS]['t5']))
    if default_digest(spells, model) != read_digest():
        bad.append('the default rows of autorotation_data.lua moved (digest %s, now %s): the variants never change them; if the '
                   'change is meant run python3 -I server/tools/rotation_sim.py --write-digest' % (read_digest()[:12], default_digest(spells, model)[:12]))
    for cls, _, _ in CLASSES:
        ent = variant_entries(spells, model, cls)
        if 'mines' in ent and cls not in mine_cls:
            bad.append('%s has a mines variant and no Seeker Mine' % cls)
        for name, rows in ent.items():
            for e in rows:
                tag = '%s %s level %d' % (cls, name, e['level'])
                ids = e['ids']
                if len(ids) > MAX_SPELLS or len(set(ids)) != len(ids):
                    bad.append('%s: %s is not 1 to %d different spells' % (tag, ids, MAX_SPELLS))
                for i in ids:
                    s = byid.get(i)
                    if not s or cls not in s['vocations'] or s['level'] > e['level']:
                        bad.append('%s: spell %d is not one the class holds at that level' % (tag, i))
                        continue
                    if s['words'] == MINE_WORDS and name != 'mines':
                        bad.append('%s: Seeker Mine outside the mines variant' % tag)
                    if name == 'mines' and MINE_WORDS not in {byid[j]['words'] for j in ids if j in byid}:
                        bad.append('%s: the mines variant holds no Seeker Mine' % tag)
                    if s['groupcooldown'] != int(GCD * 1000) or (s['name'] in final and s['cooldown'] != final[s['name']]):
                        bad.append('%s: %s is off the cooldown ladder' % (tag, s['name']))
                v = variant_level(spells, model, cls, e['level'])
                d = v['default']
                pool = {p.id: p for p in variant_pool(spells, model, cls, e['level'], name == 'mines')}
                if not all(i in pool for i in ids):
                    bad.append('%s: a spell of the set is not in the simulator pool' % tag)
                    continue
                cost = {s['words']: s['mana'] for s in spells if cls in s['vocations'] and s['group'] == 'attack'}
                gap, d1, d5, run, _ = set_stats(order([pool[i] for i in ids]), cost, cls, e['level'])
                if gap > GCD + 1e-9 or abs(gap - e['gap']) > 0.006:
                    bad.append('%s: gap %.2f s (the data says %.2f), the rule is at most 2 s' % (tag, gap, e['gap']))
                if run < min(MANA_RUNWAY, d['run']) - 1e-9:
                    bad.append('%s: the set runs %.1f s on a full mana pool, under %.0f s' % (tag, run, MANA_RUNWAY))
                one, five = d1 / d['d1'] - 1, d5 / d['d5'] - 1
                if ids == [x.id for x in d['rot']]:
                    bad.append('%s: the set is the default set' % tag)
                if max(one, five) > VAR_MAX_GAIN + 1e-9:
                    bad.append('%s: +%.1f%% over the default, the cap is +%d%%' % (tag, 100 * max(one, five), round(100 * VAR_MAX_GAIN)))
                if name == 'single' and not (one >= VAR_MIN_GAIN and five <= -VAR_MIN_PRICE):
                    bad.append('%s: 1t %+.1f%% 5t %+.1f%%: no gain or no price' % (tag, 100 * one, 100 * five))
                if name == 'pack' and not (five >= VAR_MIN_GAIN and one <= -VAR_MIN_PRICE):
                    bad.append('%s: 1t %+.1f%% 5t %+.1f%%: no gain or no price' % (tag, 100 * one, 100 * five))
                if abs(100 * one - e['one']) > 0.01 or abs(100 * five - e['five']) > 0.01:
                    bad.append('%s: the numbers of the data are not the set\'s' % tag)
    return bad


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
        over = cost_fits()
        for name, c, lv, cost, pool in over:
            print('COST ABOVE THE POOL %s (%s, level %d): %d mana, pool %d' % (name, c, lv, cost, pool))
        print('%d spell costs above a class pool at the spell\'s level' % len(over))
        return 1 if (short or over) and '--check' in argv else 0
    if '--heal' in argv:
        heal_report()
        return 0
    if '--write-digest' in argv:
        write_digest(spells, model)
        print('wrote %s' % os.path.relpath(DEFAULT_DIGEST, REPO))
        return 0
    if '--variants' in argv and '--table' in argv:
        print('\n'.join(variants_table(spells, model)))
        return 0
    if '--variants' in argv:
        variants_report(spells, model, cls)
        bad = variants_check(spells, model) if '--check' in argv else []
        for b in bad:
            print('VARIANT RULE ' + b)
        print('%d variant rule problems' % len(bad) if '--check' in argv else 'variants: computed, not measured')
        return 1 if bad else 0
    if '--report' in argv or cls or lv:
        report(spells, model, cls, lv)
    if '--quest' in argv or '--check' in argv:
        print('gain of the line spell quests over a character without them (best-set score, levels %s, ultimate at %d):' %
              (', '.join(map(str, QUEST1_LEVELS)), ULT_LEVEL))
        bad = quest_report(spells, model, cls)
        for b in bad:
            print('OUT OF BOUNDS ' + b)
        if bad and '--check' in argv:
            return 1
    if '--write' in argv or '--check' in argv:
        text = client_data(spells, model)
        old = open(CLIENT_DATA, encoding='utf-8').read() if os.path.isfile(CLIENT_DATA) else ''
        if '--check' in argv:
            if old != text:
                print('%s is out of date: run python3 -I server/tools/rotation_sim.py --write' %
                      os.path.relpath(CLIENT_DATA, REPO))
                return 1
            print('%s is up to date' % os.path.relpath(CLIENT_DATA, REPO))
            bad = variants_check(spells, model)
            for b in bad:
                print('VARIANT RULE ' + b)
            if bad:
                return 1
            print('the rotation variants keep their rules (%s)' % ', '.join(VARIANTS))
        elif old != text:
            open(CLIENT_DATA, 'w', encoding='utf-8').write(text)
            print('wrote %s' % os.path.relpath(CLIENT_DATA, REPO))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
