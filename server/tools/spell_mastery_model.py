#!/usr/bin/env python3
"""Spell modifier masteries (O451): what each choice gives, computed, not measured.

usage: python3 -I server/tools/spell_mastery_model.py [--check] [--table] [--detail CHOICE_ID]

A choice (server/data/lib/chaos_spell_masteries_config.lua) gives ONE spell a free support effect: the effect of a Common
support rune, reduced to `strength` percent where the rune has numbers to reduce (no support has a price). No tool measures
supports: rotation_sim.py models rotations and class_dps_model.py class damage, neither reads a rune. So the gain is computed
from the support's own numbers (data/lib/chaos_supports_config.lua, the rules of supports.lua) on the rotation simulator:

  spell     the change of one cast of the spell on 1 target and on the 5 dummy pack of rotation_model.csv (t5 targets hit)
  rotation  every legal set of at most 5 spells of the class's pool (rotation_sim.variant_level: gap <= 2 s, mana runway) that
            holds the spell, simulated with and without the effect; the largest change of the damage per second of a set that
            holds the spell, on 1 target and on 5 targets: what the effect adds in that set, as a share of the damage of the
            class's DEFAULT set (the helper's). This is the best case of the choice on its own: a player who builds the set
            round the spell. A set that does not hold the spell gains nothing.
  class     the rotation change x (1 - the auto attack's share of the class damage) of class_dps_measured.csv, at that level
            (the auto attack is no spell; its share is the table's own). Hex raises every hit on the hexed monsters, spells and
            auto attack alike, so its class gain is the hex share of the damage (uptime x targets hexed)

What each effect does to a spell hit (the same rules as scripts/chaos/supports.lua, no resistances, no crit, no kill):
  brand       the spell's damage +value%
  echo        the spell's hits strike again for value2% with a chance of value% per cast: +value x value2 / 100 of the spell
  quickening  cooldown -value% (never below 1 s); the rotation casts on the 2 s attack group, so a few percent rarely
              moves a cast to an earlier group tick: the model shows it
  fork        the hit also hits `count` more enemies for value2% of it; on the pack the neighbours that exist (5 - targets hit)
  shatter     the enemies next to the target take value% of the hit (at most 4); on the pack 5 - targets hit
  breadth     the enemies of the pack the area spell missed (5 - targets hit) take value2% of the average hit (at most 6)
  hex         +value% damage from everyone for 4 s on the monsters the spell hit; uptime = 4 s / the seconds between two casts
Levels 100, 500 and 1000 (class_dps_measured.csv); a spell the class does not have at the level is skipped.

O473 (2026-11-10): a choice whose support is a brand (config `damage`) is not a free support: while its spell is cast it adds
`each` (3) raw percent to the additive damage pool (damage_pool_config.lua sources.masteries, at most 12 for masteries). The model
counts it as the brand did, the spell's damage +3% (the largest it can be: the pool's soft cap only lowers it). CAP below counts raw
pool percent for those rows.
Owner rule (2026-11-10): no build above +40% over its class default in its specialty. The limit of this model is stricter, so
that a choice fits under the cap next to keystones: every choice at most +15% of the class damage on its own (CAP).
--check exits 1 on a problem (a gain over CAP, a choice whose spell no class of the line can cast, a hole).
--table prints the markdown table of docs/BUILDS.md "Spell modifier masteries (O451)".
--detail ID prints the numbers of one choice per class and level.
"""
import copy
import csv
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
import rotation_sim as R  # noqa: E402

CONFIG = os.path.join(REPO, 'server', 'data', 'lib', 'chaos_spell_masteries_config.lua')
POOL = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'damage_pool_config.lua')
SUPPORTS = os.path.join(REPO, 'server', 'data', 'lib', 'chaos_supports_config.lua')
MEASURED = os.path.join(REPO, 'server', 'data', 'spells', 'class_dps_measured.csv')
LEVELS = (100, 500, 1000)
CAP = 0.15            # a choice on its own: at most this share of the class damage (owner cap +40% in a specialty, with room for keystones)
HEX_SECONDS = 4.0     # chaos_supports_config.lua effect.hexDuration
COOLDOWN_FLOOR = 1.0  # effect.cooldownMinMs
FORK_RANGE_PACK = 4   # the neighbours of a target in the pack of 5
SHATTER_MAX = 4       # effect.shatterMax
BREADTH_MAX = 6       # effect.breadthMax


# ---------------------------------------------------------------------------------------------------------- the data
def _numbers(text):
    return [int(x) for x in re.findall(r'-?\d+', text)]


def load_config(path=CONFIG):
    """{'tier', 'strength', 'reduce': {key: [fields]}, 'choices': [{id, line, node, effect, name, spell, support}]}"""
    text = open(path, encoding='utf-8').read()
    cfg = {'tier': int(re.search(r'\n\ttier = (\d+)', text).group(1)),
           'strength': int(re.search(r'\n\tstrength = (\d+)', text).group(1))}
    block = re.search(r'\n\treduce = \{(.*?)\n\t\}', text, re.S).group(1)
    cfg['reduce'] = {k: re.findall(r'"(\w+)"', v) for k, v in re.findall(r'(\w+) = \{([^}]*)\}', block)}
    # O473 (2026-11-10): the damage choices (the brands) are entries of the additive damage pool: +each raw, no free support
    dmg = re.search(r'\n\tdamage = \{([^}]*)\}', text)
    cfg['damage'] = set(re.findall(r'(\w+) = true', dmg.group(1))) if dmg else set()
    pool = open(POOL, encoding='utf-8').read()
    cfg['pool_each'] = int(re.search(r'masteries = \{[^}]*each = (\d+)', pool).group(1))
    cfg['pool_cap'] = int(re.search(r'masteries = \{[^}]*cap = (\d+)', pool).group(1))
    rows = []
    for m in re.finditer(r'\{id = (\d+), line = "(\w+)", node = (\d+), effect = (\d+), name = "([^"]+)", spell = (\d+), '
                         r'support = "(\w+)"\}', text):
        rows.append({'id': int(m.group(1)), 'line': m.group(2), 'node': int(m.group(3)), 'effect': int(m.group(4)),
                     'name': m.group(5), 'spell': int(m.group(6)), 'support': m.group(7)})
    cfg['choices'] = rows
    return cfg


def load_supports(path=SUPPORTS):
    """{key: {'values': [...], 'values2': [...] or None, 'group': str or None, 'element': str or None}} of the support runes"""
    text = open(path, encoding='utf-8').read()
    out = {}
    for m in re.finditer(r'\{key = "(\w+)",(.*?)\n\t\t\ttext = ', text, re.S):
        body = m.group(2)
        v = re.search(r'\bvalues = \{([^}]*)\}', body)
        v2 = re.search(r'\bvalues2 = \{([^}]*)\}', body)
        g = re.search(r'group = "(\w+)"', body)
        e = re.search(r'element = "(\w+)"', body)
        out[m.group(1)] = {'values': _numbers(v.group(1)), 'values2': _numbers(v2.group(1)) if v2 else None,
                           'group': g.group(1) if g else None, 'element': e.group(1) if e else None}
    return out


def free_effect(cfg, supports, key):
    """{'value', 'value2'} of the free support: the rune's numbers at the config tier, the fields of `reduce` cut to the strength
    (rounded down, at least 1): the same rule as ChaosSupports.freeEffect in data/lib/chaos_supports.lua"""
    if key in cfg.get('damage', ()):
        # a pool entry: +each raw percent on the hits of the spell. Counted as the brand's "the spell's damage +value%": the most it can
        # add (the soft cap of the pool only makes it smaller)
        return {'value': cfg['pool_each'], 'value2': None}
    s = supports[key]
    e = {'value': s['values'][cfg['tier'] - 1], 'value2': s['values2'][cfg['tier'] - 1] if s['values2'] else None}
    for f in cfg['reduce'][key]:
        e[f] = max(1, int(math.floor(e[f] * cfg['strength'] / 100.0 + 1e-6)))
    return e


def measured(path=MEASURED):
    out = {}
    with open(path, encoding='utf-8') as f:
        for r in csv.DictReader(f):
            out[(r['class'], int(r['level']))] = (float(r['auto_share_1t']), float(r['auto_share_5t']))
    return out


# ------------------------------------------------------------------------------------------------ the effects on a spell
def hit_targets(s):
    """targets of the 5 dummy pack a cast of the spell hits (rotation_model.csv t5, 1 to 5; the simulator's dmg5 / dmg)"""
    return max(1.0, min(5.0, s.dmg5 / s.dmg)) if s.dmg else 1.0


def spell_change(support, e, s):
    """(1 target, 5 targets) change of the damage of one cast of spell s (a rotation_sim.Spell) with the effect e (a fraction)"""
    t = hit_targets(s)
    if support in ('dawnbrand', 'gravebrand', 'emberbrand', 'rimebrand', 'stormbrand'):
        return e['value'] / 100.0, e['value'] / 100.0
    if support == 'echo':
        return e['value'] * e['value2'] / 10000.0, e['value'] * e['value2'] / 10000.0
    if support == 'fork':
        more = min(e['value'], 5 - t)
        return 0.0, more * e['value2'] / 100.0 / t
    if support == 'shatter':
        more = min(SHATTER_MAX, 5 - t)
        return 0.0, more * e['value'] / 100.0 / t
    if support == 'breadth':
        more = min(BREADTH_MAX, max(0.0, 5 - t))
        return 0.0, more * e['value2'] / 100.0 / t
    return 0.0, 0.0  # quickening (a cooldown) and hex (every hit) are not a change of one cast


def modified(support, e, s):
    """a copy of the simulator's spell with the effect applied (damage and cooldown); hex is applied by hex_gain"""
    m = copy.copy(s)
    d1, d5 = spell_change(support, e, s)
    m.dmg = s.dmg * (1 + d1)
    m.dmg5 = s.dmg5 * (1 + d5)
    if support == 'quickening':
        m.cd = max(COOLDOWN_FLOOR, s.cd * (1 - e['value'] / 100.0))
    return m


def spell_rate_change(support, e, s):
    """(1 target, 5 targets) change of the damage per second of the spell cast on its cooldown (quickening counts here)"""
    d1, d5 = spell_change(support, e, s)
    rate = 1.0
    if support == 'quickening':
        gap = max(s.cd, s.gcd, s.cast, 1e-3)
        new = max(max(COOLDOWN_FLOOR, s.cd * (1 - e['value'] / 100.0)), s.gcd, s.cast, 1e-3)
        rate = gap / new
    return (1 + d1) * rate - 1, (1 + d5) * rate - 1


def hex_gain(rot, spell_id, e, casts):
    """(1 target, 5 targets) class damage change of Hex on a spell of the rotation: +value% on the monsters the spell hit for 4 s,
    for every hit (spells and auto attack). `casts` = casts of the rotation over the horizon (rotation_sim.simulate)"""
    s = next(x for x in rot if x.id == spell_id)
    n = sum(1 for _, w in casts if w == s.words)
    if not n:
        return 0.0, 0.0
    uptime = min(1.0, HEX_SECONDS / (R.HORIZON / n))
    t = hit_targets(s)
    return e['value'] / 100.0 * uptime, e['value'] / 100.0 * uptime * t / 5.0


# ------------------------------------------------------------------------------------------------------- the rotation
_DATA = {}


def data():
    if 'spells' not in _DATA:
        _DATA['spells'], _DATA['model'] = R.load_all()
        _DATA['cfg'] = load_config()
        _DATA['supports'] = load_supports()
        _DATA['auto'] = measured()
    return _DATA


def line_classes(line):
    names = {'warrior': 'Warrior', 'ranger': 'Ranger', 'mystic': 'Mystic', 'thief': 'Thief', 'necromancer': 'Necromancer',
             'monk': 'Monk', 'templar': 'Templar'}
    return [c for c, l, _ in R.CLASSES if l == names[line]]


def rotation_gain(cls, level, choice):
    """None when the class cannot use the spell at the level, else {'one', 'five', 'in_default'}: the largest change of the damage per
    second of a legal set that holds the spell (spell part, a fraction), and whether the default set holds it"""
    d = data()
    v = R.variant_level(d['spells'], d['model'], cls, level)
    base = v['default']
    if not base:
        return None
    pool = R.variant_pool(d['spells'], d['model'], cls, level)
    spell = next((s for s in pool if s.id == choice['spell']), None)
    if spell is None:
        return None
    e = free_effect(d['cfg'], d['supports'], choice['support'])
    in_default = any(s.id == spell.id for s in base['rot'])
    best1 = best5 = 0.0
    hexed = (0.0, 0.0)
    entries = [{'rot': base['rot'], 'd1': base['d1'], 'd5': base['d5']}] + v['sets']
    for entry in entries:
        rot = entry['rot']
        if not any(s.id == spell.id for s in rot):
            continue
        if choice['support'] == 'hex':
            casts = R.simulate(rot)[0]
            h = hex_gain(rot, spell.id, e, casts)
            hexed = (max(hexed[0], h[0]), max(hexed[1], h[1]))
            continue
        mod = R.order([modified(choice['support'], e, s) if s.id == spell.id else s for s in rot])
        _, gap, m1, m5 = R.simulate(mod)
        if gap > R.GCD + 1e-9 and entry is not entries[0]:
            continue  # a variant is a legal set: it never goes 2 s without a cast
        # what the effect adds in this set, as a share of the DEFAULT set's damage (a weak set that holds the spell would show
        # a big share of its own small damage: that is no gain over the class default)
        best1 = max(best1, (m1 - entry['d1']) / base['d1'] if base['d1'] else 0.0)
        best5 = max(best5, (m5 - entry['d5']) / base['d5'] if base['d5'] else 0.0)
    return {'one': best1, 'five': best5, 'hex': hexed, 'in_default': in_default, 'spell': spell, 'effect': e}


def choice_numbers(choice):
    """{(class, level): {'one', 'five' (the class damage change, fractions), 'rotation_one', 'rotation_five', 'in_default'}} and the
    spell's own change {'one', 'five'} per cast and the same per second of cooldown"""
    d = data()
    out = {}
    own = None
    for cls in line_classes(choice['line']):
        for lv in LEVELS:
            g = rotation_gain(cls, lv, choice)
            if g is None:
                continue
            a1, a5 = d['auto'][(cls, lv)]
            if choice['support'] == 'hex':
                one, five = g['hex']
                r1, r5 = 0.0, 0.0
            else:
                r1, r5 = g['one'], g['five']
                one, five = r1 * (1 - a1), r5 * (1 - a5)
            out[(cls, lv)] = {'one': one, 'five': five, 'rotation_one': r1, 'rotation_five': r5, 'in_default': g['in_default']}
            if own is None:
                own = spell_rate_change(choice['support'], g['effect'], g['spell'])
    return out, own


def summary(choice, nums=None, own=None):
    """the worst case over the three classes and the levels: class damage change on 1 and 5 targets, the spell's own change, the
    number of class x level cells counted and the cells whose default set holds the spell"""
    if nums is None:
        nums, own = choice_numbers(choice)
    cells = list(nums.values())
    return {'class_one': max((c['one'] for c in cells), default=0.0), 'class_five': max((c['five'] for c in cells), default=0.0),
            'spell_one': own[0] if own else 0.0, 'spell_five': own[1] if own else 0.0, 'cells': len(cells),
            'in_default': sum(1 for c in cells if c['in_default'])}


def problems(rows=None):
    d = data()
    bad = []
    cfg = d['cfg']
    for c in cfg['choices']:
        if c['support'] not in d['supports'] or (c['support'] not in cfg['reduce'] and c['support'] not in cfg['damage']):
            bad.append('%s: support %s is unknown or not reduced' % (c['name'], c['support']))
            continue
        nums, own = choice_numbers(c)
        if not nums:
            bad.append('%s: no class of the %s line can cast spell %d at 100, 500 or 1000' % (c['name'], c['line'], c['spell']))
            continue
        s = summary(c, nums, own)
        if s['class_one'] > CAP or s['class_five'] > CAP:
            bad.append('%s: +%.1f%% / +%.1f%% of the class damage (1 / 5 targets), over %d%%' % (
                c['name'], s['class_one'] * 100, s['class_five'] * 100, CAP * 100))
    return bad


def table():
    d = data()
    cfg = d['cfg']
    lines = ['| Class line | Choice | Spell | Support | Tier | Price | Spell gain 1T / 5T | Class gain 1T / 5T |',
             '|---|---|---|---|---|---|---|---|']
    by_id = {s['id']: s['name'] for s in d['spells'] if s['chaos'] or s['id']}
    for c in cfg['choices']:
        s = summary(c)
        e = free_effect(cfg, d['supports'], c['support'])
        rune = d['supports'][c['support']]
        parts = []
        if c['support'] in cfg['damage']:
            parts.append('no free rune: +%d increased damage in the pool (O473)' % cfg['pool_each'])
        for f in cfg['reduce'].get(c['support'], []):
            full = rune['values'][cfg['tier'] - 1] if f == 'value' else rune['values2'][cfg['tier'] - 1]
            parts.append('%d instead of %d' % (e[f], full))
        lines.append('| %s | %s | %s | %s | Common | none, reduced: %s | %+.0f%% / %+.0f%% | %+.1f%% / %+.1f%% |' % (
            c['line'].capitalize(), c['name'], by_id.get(c['spell'], str(c['spell'])), c['support'].capitalize(), '; '.join(parts),
            s['spell_one'] * 100, s['spell_five'] * 100, s['class_one'] * 100, s['class_five'] * 100))
    return '\n'.join(lines)


def detail(cid):
    d = data()
    c = next(x for x in d['cfg']['choices'] if x['id'] == cid)
    nums, own = choice_numbers(c)
    out = ['%s (%s on spell %d): spell %+.1f%% / %+.1f%% per second' % (c['name'], c['support'], c['spell'], own[0] * 100,
                                                                         own[1] * 100)]
    for (cls, lv), n in sorted(nums.items()):
        out.append('  %-12s %4d  rotation %+5.1f%% / %+5.1f%%  class %+5.1f%% / %+5.1f%%  %s' % (
            cls, lv, n['rotation_one'] * 100, n['rotation_five'] * 100, n['one'] * 100, n['five'] * 100,
            'in the default set' if n['in_default'] else 'a set built round it'))
    return '\n'.join(out)


def main(argv):
    if '--detail' in argv:
        print(detail(int(argv[argv.index('--detail') + 1])))
        return 0
    if '--table' in argv:
        print(table())
        return 0
    bad = problems()
    if '--check' in argv:
        for b in bad:
            print('FAIL ' + b)
        if not bad:
            n = len(data()['cfg']['choices'])
            print('spell mastery check: ok (%d choices, each at most +%d%% of the class damage on 1 and 5 targets)' % (n, CAP * 100))
        return 1 if bad else 0
    print(table())
    for b in bad:
        print('FAIL ' + b)
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
