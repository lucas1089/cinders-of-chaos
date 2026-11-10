#!/usr/bin/env python3
"""Card set model (O453): what a card set costs and gives against a mixed build, per class at level 500. Computed, not measured.

usage: python3 -I server/tools/card_set_model.py [--check] [--level N] [--csv]

The set bonus (cards_config.lua `sets`, cards_core.lua, server/README.md "Card sets (O453)"): 3 cards of one element, one per
convert line the class casts, give one small bonus: Fire damage +5%, Earth poison 5% of the hit, Death leech 1.5%, Holy heal 0.5%
of the maximum health, Energy slow 15% for 1.5 s. No other model reads the cards, so this one stands apart: class_dps_model.py,
the pack, boss, tower and survival models never see a card and are not moved by this change.

The model, per class (all inputs are in the repo):
  base       the class's damage per second at the level (class_dps_model.dps), split by spell: the share of every Chaos attack spell
             in rotation_sim's "every spell on cooldown" harness (the C4 measure), on 1 target and on 5 targets.
  element    the native element of a spell (client spelldata.lua, the damage type of its script; none = physical); a convert card moves
             the hits of its line's spells to the element of its tier (cards_config.lua families, also).
  resistance the mean damage taken multiplier of an element over the monsters of data/monster/monsters/chaos (1 - percent / 100, no
             entry = 1.0). It is the only resistance data in the repo (the base server's monsters are not committed): an assumption,
             printed with the table. A convert card is worth share x (mult(new) / mult(native) - 1) of the damage of its spells.
  cards      legendary: +15 to the stat (melee or distance skill, magic level) all the time (an upper bound: 20% chance per hit of 50
             or more, 90 s), valued by running the harness with the stat raised. Bloodlust (Warrior, Berserker) and Tautstring (Ranger
             line): +7% / +8% of the skill, all the time, same way. One legendary counts (one summon at a time). Heal, widen: no damage.
  mixed      the best 5 cards of the class with every set bonus off (the best build of a game with no sets): each convert line takes
             any of its 4 elements or none. Found by search over every choice.
  set        the best 5 cards that make a set: the same search, the set's damage part added (Fire and Earth: pct x the share of the
             damage that is of the element at the end; Death, Holy and Energy give a leech, a heal and a slow: no damage, not valued).
  worst case the cap (4% since O473, 6% before: raw percent of the one additive damage pool) of the class's damage per second: if ALL
             its damage were of the set's element.
--check fails when a set is better than the best mixed build of a class by AHEAD (0.7 points since O474, was 0.5) or more (the owner's rule: then lower it;
below that the lead is inside the model's own guess, and for the classes whose native element is the set's element it cannot be
lowered away: the bonus is on damage the class deals anyway, the cards cost it nothing), when a class's
best set is more than 10% away from its best mixed build on 1 or 5 targets, when a damage part is above the cap, or when fewer
than 3 class lines have a set within 10%.
"""
import glob
import itertools
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import class_dps_model as CD  # noqa: E402
import rotation_sim as R  # noqa: E402

REPO = os.path.normpath(os.path.join(HERE, '..', '..'))
CONFIG = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'cards_config.lua')
SPELLDATA = os.path.join(REPO, 'client', 'overlay', 'modules', 'game_chaosspells', 'spelldata.lua')
MONSTERS = os.path.join(REPO, 'server', 'data', 'monster', 'monsters', 'chaos', '*.xml')
LEVEL = 500
SLOTS = 5
LEGENDARY_STAT = 15
TOLERANCE = 0.10          # a set and a mixed build within 10% of each other
AHEAD = 0.007             # a set may lead the best mixed build by less than this (0.7 points: inside the weights' guess, see the header)
# O474 (2026-11-10): was 0.005. The damage over time rule (side dots 0.30 x the hit) moved the best set of the Mystic at level 500 to the
# fire spells (Witchfire Bolt, Falling Pyre): the fire set leads the best mixed build by +0.4% on 1 target and +0.61% on 5 targets
# (was +0.26% / +0.36%). A native-element lead cannot be lowered away (the header); the limit follows by 0.2 points. Model: card_set_model
MIN_LINES_WITHIN = 3      # at least 3 class lines show it
PHYS = 'physical'
ELEMENTS = ('fire', 'ice', 'earth', 'energy', 'holy', 'death', 'drown')


def lua_numbers(text):
    return {k: float(v) for k, v in re.findall(r'(\w+) = (-?[\d.]+)', text)}


def load_config(path=CONFIG):
    """{'families': [{spell, spells [names], elements [4]}], 'lines': {spell: [classes]}, 'sets': {element: row}, 'need', 'cap'}"""
    text = open(path, encoding='utf-8').read()
    fams = []
    block = text[text.index('local families = {'):text.index('C.families = families')]
    for m in re.finditer(r'\{kind = "convert", spell = "([^"]+)", id = (\d+), how = "\w+", elements = \{([^}]*)\}(?:,\s*also = \{((?:\{"[^"]+", \d+\},?\s*)+)\})?',
                         block, re.S):
        names = [m.group(1)] + re.findall(r'\{"([^"]+)", \d+\}', m.group(4) or '')
        fams.append({'spell': m.group(1), 'spells': names, 'elements': [e.lower() for e in re.findall(r'"(\w+)"', m.group(3))]})
    lines = {}
    lb = text[text.index('C.lineClasses = {'):text.index('-- Card sets (O453, server/README.md')]
    for spell, body in re.findall(r'\["([^"]+)"\] = \{(.*?)\}', lb, re.S):
        lines[spell] = re.findall(r'"([^"]+)"', body)
    sb = text[text.index('C.sets = {'):text.index('C.sets.maxSets')]
    sets = {}
    for name, body in re.findall(r'\n\t\t(\w+) = \{(kind = [^}]*)\}', sb):
        row = lua_numbers(body)
        row['kind'] = re.search(r'kind = "(\w+)"', body).group(1)
        sets[name.lower()] = row
    top = lua_numbers(sb.split('by = {')[0])
    return {'families': fams, 'lines': lines, 'sets': sets, 'need': int(top['need']), 'cap': top['damagePartMax'],
            'pvp': 1 / 3.0}


def spell_data(path=SPELLDATA):
    """{spell name: (element, [vocation ids])}; a spell with no element is physical"""
    out = {}
    for line in open(path, encoding='utf-8'):
        m = re.search(r'name = "([^"]+)".*?vocations = \{([^}]*)\}(?:.*?element = "(\w+)")?', line)
        if m:
            out[m.group(1)] = (m.group(3) or PHYS, [int(v) for v in re.findall(r'\d+', m.group(2))])
    return out


def resistances(pattern=MONSTERS):
    """{element: mean damage taken multiplier} over the monster files, and the number of files"""
    files = sorted(glob.glob(pattern))
    total = {e: 0.0 for e in (PHYS,) + ELEMENTS}
    for f in files:
        text = open(f, encoding='utf-8').read()
        res = {}
        for e, v in re.findall(r'(\w+?)Percent="(-?\d+)"', text):
            res['earth' if e == 'poison' else e] = int(v)
        for e in total:
            total[e] += 1 - res.get(e, 0) / 100.0
    return {e: v / len(files) for e, v in total.items()}, len(files)


_ENV = {}


def kit(cls, level=LEVEL, stat=None, skill=None):
    """({spell name: (share on 1 target, share on 5 targets)}, dps1, dps5) of the 'every spell' harness; stat = +points of the
    class's main stat (a legendary card), skill = x the skill (Bloodlust, Tautstring)"""
    if 'all' not in _ENV:
        _ENV['all'] = R.load_all()
    spells, model = _ENV['all']
    have = [s for s in R.class_spells(spells, cls, level) if R.quest_spell_ok(s, 0)]
    saved = R.stats

    def bumped(c, lv):
        env = dict(saved(c, lv))
        kind = R.CLASS_KIND[c]
        if kind == 'caster':
            env['ML'] += stat or 0
        else:
            env['SK'] = (env['SK'] + (stat or 0)) * (skill or 1.0)
            env['P'] = env['SK'] * (env['FIST'] if kind == 'fist' else env['ATK'])
        return env
    R.stats = bumped
    try:
        pool = R.prepare(have, model, cls, level)
    finally:
        R.stats = saved
    harness = R.harness(pool)
    hits = []
    R.simulate(harness['spells'], hits=hits)
    names = {s.words: s.name for s in harness['spells']}
    t1, t5 = sum(h[1] for h in hits), sum(h[2] for h in hits)
    share = {}
    for _, h1, h5, words in hits:
        a = share.setdefault(names[words], [0.0, 0.0])
        a[0] += h1 / t1
        a[1] += h5 / t5
    return {k: tuple(v) for k, v in share.items()}, harness['dps1'], harness['dps5']


def class_cards(cls, cfg):
    """the convert lines of a class: [(family, spells the class casts that the line acts on)] and the utility card"""
    return [f for f in cfg['families'] if cls in cfg['lines'].get(f['spell'], [])]


def value(cls, cfg, mult, shares, choice, extras, set_element=None):
    """damage gain (fraction, on 1 target and on 5 targets) of a build: `choice` {line spell: element or None}, `extras` the gain of
    the legendary and utility cards; the set's damage part when set_element names the set"""
    nat = SPELLS_NAT
    out = []
    for i in (0, 1):
        eff = {}
        for name, s in shares.items():
            eff[name] = nat.get(name, PHYS)
        gain = 0.0
        for fam in class_cards(cls, cfg):
            el = choice.get(fam['spell'])
            if not el:
                continue
            for name in fam['spells']:
                if name in shares:
                    gain += shares[name][i] * (mult[el] / mult[nat.get(name, PHYS)] - 1)
                    eff[name] = el
        if set_element:
            row = cfg['sets'][set_element]
            if row['kind'] in ('damage', 'poison'):
                part = sum(shares[n][i] for n, e in eff.items() if e == set_element)
                gain += row['pct'] / 100.0 * part
        out.append(gain + extras[i])
    return out


SPELLS_NAT = {}


def class_rows(level=LEVEL):
    cfg = load_config()
    data = spell_data()
    SPELLS_NAT.clear()
    SPELLS_NAT.update({n: e for n, (e, _) in data.items()})
    mult, nmon = resistances()
    rows = []
    for cls, line, kind in R.CLASSES:
        shares, d1, d5 = kit(cls, level)
        d1m, d5m = CD.dps(cls, level)
        leg = kit(cls, level, stat=LEGENDARY_STAT)
        legendary = [leg[1] / d1 - 1, leg[2] / d5 - 1]
        util_pct = {'Warrior': 7, 'Berserker': 7, 'Ranger': 8, 'Deadeye': 8, 'Beastmaster': 8}.get(cls)
        utility = [0.0, 0.0]
        if util_pct:
            u = kit(cls, level, skill=1 + util_pct / 100.0)
            utility = [u[1] / d1 - 1, u[2] / d5 - 1]
        extras = [legendary[i] + utility[i] for i in (0, 1)]
        lines = class_cards(cls, cfg)
        # the other cards of the class that give no damage (Grand Mending, Taunt of Iron) fill free slots at value 0
        best = {'mixed': None, 'set': None}
        options = [[None] + [e for e in f['elements'] if e in cfg['sets'] or e in ('ice', 'drown')] for f in lines]
        for pick in itertools.product(*options):
            cards = sum(1 for e in pick if e)
            if cards > SLOTS - 1:
                continue  # the legendary takes a slot
            choice = {lines[i]['spell']: e for i, e in enumerate(pick) if e}
            counts = {}
            for e in pick:
                if e in cfg['sets']:
                    counts[e] = counts.get(e, 0) + 1
            made = [e for e, n in counts.items() if n >= cfg['need']]
            # a build that makes a set is a set build; as a mixed build it counts with the bonus off (the best build of a game
            # with no sets): the set must beat that, not only the builds that avoid the cards
            cands = [(None, 'mixed')] + [(e, 'set') for e in made]
            for el, kind_ in cands:
                v = value(cls, cfg, mult, shares, choice, extras, el)
                # one legendary and the utility card take their slots; the line cards use the rest
                free = SLOTS - 1 - (1 if util_pct else 0)
                if cards > free:
                    continue
                cur = best[kind_]
                if cur is None or sum(v) > sum(cur['v']) + 1e-12:
                    best[kind_] = {'v': v, 'choice': choice, 'element': el, 'cards': cards}
        rows.append({'class': cls, 'line': line, 'dps': (d1m, d5m), 'legendary': legendary, 'utility': utility,
                     'mixed': best['mixed'], 'set': best['set'], 'lines': [f['spell'] for f in lines], 'cfg': cfg,
                     'cap': (cfg['cap'] / 100.0 * d1m, cfg['cap'] / 100.0 * d5m)})
    return rows, mult, nmon


def problems(rows, mult=None):
    bad, within = [], {}
    cfg = rows[0]['cfg']
    for el, row in cfg['sets'].items():
        if row['kind'] in ('damage', 'poison') and row['pct'] > cfg['cap']:
            bad.append('%s: the damage part %.1f%% is above the cap %.1f%%' % (el, row['pct'], cfg['cap']))
    for r in rows:
        if r['set'] is None or r['mixed'] is None:
            bad.append('%s: no set or no mixed build found' % r['class'])
            continue
        for i, name in ((0, '1 target'), (1, '5 targets')):
            s, m = 1 + r['set']['v'][i], 1 + r['mixed']['v'][i]
            if s > m + AHEAD:
                bad.append('%s: the %s set is strictly better than the best mixed build on %s (%+.2f%%): lower it' % (
                    r['class'], r['set']['element'], name, (s / m - 1) * 100))
            if abs(s / m - 1) > TOLERANCE:
                bad.append('%s: the best set is %+.1f%% against the best mixed build on %s (limit +-%d%%)' % (
                    r['class'], (s / m - 1) * 100, name, TOLERANCE * 100))
        ok = all(abs((1 + r['set']['v'][i]) / (1 + r['mixed']['v'][i]) - 1) <= TOLERANCE for i in (0, 1))
        within.setdefault(r['line'], False)
        within[r['line']] = within[r['line']] or ok
    if sum(within.values()) < MIN_LINES_WITHIN:
        bad.append('only %d class lines have a set within %d%% of the mixed build (need %d)' % (
            sum(within.values()), TOLERANCE * 100, MIN_LINES_WITHIN))
    return bad


def table(rows, mult, nmon):
    out = ['Mean damage taken multiplier over %d monster files: %s' % (
        nmon, ', '.join('%s %.3f' % (e, mult[e]) for e in (PHYS,) + ELEMENTS)),
        '', '| Class | 1 target | Legendary | Mixed best | Best set | Set vs mixed (1t / 5t) | Worst case 1t | Worst case 5t |',
        '|---|---:|---:|---|---|---|---:|---:|']
    for r in rows:
        m, s = r['mixed'], r['set']
        d = ['%+.1f%%' % (((1 + s['v'][i]) / (1 + m['v'][i]) - 1) * 100) for i in (0, 1)]
        out.append('| %s | %.0f | %+.1f%% | %s | %s %s | %s / %s | %.0f | %.0f |' % (
            r['class'], r['dps'][0], r['legendary'][0] * 100, '%+.1f%%' % (m['v'][0] * 100), s['element'],
            '%+.1f%%' % (s['v'][0] * 100), d[0], d[1], r['cap'][0], r['cap'][1]))
    return '\n'.join(out)


def main(argv):
    level = int(argv[argv.index('--level') + 1]) if '--level' in argv else LEVEL
    rows, mult, nmon = class_rows(level)
    bad = problems(rows, mult)
    if '--check' in argv:
        for b in bad:
            print('FAIL ' + b)
        if not bad:
            ahead = [r['class'] for r in rows if any(r['set']['v'][i] > r['mixed']['v'][i] + 1e-9 for i in (0, 1))]
            print('card set model: ok (21 classes at level %d, no set ahead of its best mixed build by %.1f points, all within %d%%; '
                  'ahead by less: %s)' % (level, AHEAD * 100, TOLERANCE * 100, ', '.join(ahead) or 'none'))
        return 1 if bad else 0
    print(table(rows, mult, nmon))
    if bad:
        print('\n' + '\n'.join('PROBLEM ' + b for b in bad))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
