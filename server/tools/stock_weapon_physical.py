#!/usr/bin/env python3
"""The physical attack of the stock melee weapons (O673, owner decision 2026-11-19: the Juggernaut's weapons go up to level 2500 like
the other classes'; server/README.md "Physical attack of the melee weapons (O673)").

usage: python3 -I server/tools/stock_weapon_physical.py [--table | --check]

A weapon spell of a melee class reads skill x max(20, physical attack) (data/spells/chaos/_common.lua meleeAttack): the element damage
of a weapon is not in it. The equipment sets give 35% of their attack as an element (install_gear_sets.py ELEMENT_SHARE), so a spell
reads 65% of the tier from a set weapon. The stock weapons of the levels 180 to 600 (soul and sanguine families) are mostly element:
attack 8 to 16 plus an element of 44 to 79 after the growth, a physical share of 15%. The stock pool of the Gambler for the levels 600
to 999 holds only those, so a Juggernaut of level 817 without a set weapon cast with an attack of 20 (0.29 of the median class, README
"The rest of the closed audit (O589)" step 24).

The rule, applied by patch_stock_weapon_growth.py after the growth and held equal in tools/weapon_coverage.lua stockWeapons: a sword,
axe or club that grows (a level above 100, no charges) keeps its total (attack + element damage, after the growth), and its element
damage is at most ELEMENT_SHARE of it, rounded half up; the rest is physical attack. A weapon with a smaller element share is left as it
is. With several element keys the cap is shared by their size. Plain Python, no state.
"""
import csv
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import weapon_growth as WG  # noqa: E402

ELEMENT_SHARE = 0.35        # the same as install_gear_sets.py ELEMENT_SHARE (the sets), held by the test
KINDS = ('sword', 'axe', 'club')
STOCK_CSV = os.path.join(HERE, '..', 'data', 'items', 'base_weapons.csv')


def applies(kind, level, charges):
    """a stock weapon this rule reads: a melee kind of a level that grows"""
    return kind in KINDS and charges == 0 and level > 100


def split(attack, elems):
    """(attack, {key: value}) after the rule: `elems` = {element key: damage}, in any order. The total is kept, the element sum is
    capped at ELEMENT_SHARE of it"""
    total = attack + sum(elems.values())
    cap = int(total * ELEMENT_SHARE + 0.5)
    have = sum(elems.values())
    if have <= cap:
        return attack, dict(elems)
    out = {k: int(v * cap / float(have) + 0.5) for k, v in elems.items()}
    drift = cap - sum(out.values())
    if drift and out:
        big = max(sorted(out), key=lambda k: out[k])     # the rounding falls on the largest key (the first by name on a tie)
        out[big] += drift
    return total - sum(out.values()), out


def rows():
    """the stock melee rows of data/items/base_weapons.csv: dicts id, kind, hands, level, charges and the pairs (attack, element)
    before (the snapshot), grown (after the growth) and after (after growth and rule)"""
    out = []
    with open(STOCK_CSV, newline='', encoding='utf-8') as f:
        for r in csv.DictReader(f):
            level = int(r['level'])
            if r['kind'] not in KINDS:
                continue
            attack, element = int(r['attack']), int(r['element'])
            row = {'id': int(r['id']), 'kind': r['kind'], 'hands': int(r['hands']), 'level': level, 'before': (attack, element),
                   'charges': int(r['charges'])}
            if applies(r['kind'], level, row['charges']):
                a = WG.weapon_a(level)
                g = (int(attack * a + 0.5) if attack > 0 else attack, int(element * a + 0.5) if element > 0 else element)
                new_a, new_e = split(g[0], {'e': g[1]})
                row['grown'], row['after'] = g, (new_a, new_e['e'])
            else:
                row['grown'] = row['after'] = (attack, element)
            out.append(row)
    return out


def table():
    """text: per level band of the stock melee weapons that grow, the count, the weapons whose physical attack is under 60% of their
    total and the best physical attack, before and after the rule"""
    bands = ((100, 300), (300, 600), (600, 1000), (1000, 100000))
    lines = ['band        weapons  element-heavy before  best physical before  element-heavy after  best physical after']
    for lo, hi in bands:
        sel = [r for r in rows() if applies(r['kind'], r['level'], r['charges']) and lo < r['level'] <= hi]
        if not sel:
            continue

        def heavy(key):
            return sum(1 for r in sel if r[key][1] > 0 and r[key][0] < 0.6 * sum(r[key]))
        lines.append('%-11s %7d  %20d  %20d  %19d  %19d' % ('%d-%d' % (lo + 1, hi if hi < 100000 else 2500), len(sel), heavy('grown'),
                     max(r['grown'][0] for r in sel), heavy('after'), max(r['after'][0] for r in sel)))
    return '\n'.join(lines)


def check():
    bad = []
    for r in rows():
        ga, ge = r['grown']
        aa, ae = r['after']
        if ga + ge != aa + ae:
            bad.append('%d: the total moved' % r['id'])
        if applies(r['kind'], r['level'], r['charges']) and ae > int((aa + ae) * ELEMENT_SHARE + 0.5):
            bad.append('%d: element %d of %d' % (r['id'], ae, aa + ae))
    return bad


def main(argv):
    if '--check' in argv:
        bad = check()
        for b in bad:
            print(b)
        print('stock weapon physical: ' + ('%d problem(s)' % len(bad) if bad else 'ok'))
        return 1 if bad else 0
    print(table())
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
