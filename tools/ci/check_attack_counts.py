#!/usr/bin/env python3
"""Every class has the same number of attack spells (owner 2026-10-23: "devem ter a mesma quantidade").

Rule of the count: an attack spell is an <instant group="attack"> of server/data/spells/chaos/spells_chaos.xml or a row
of server/data/spells/stock_spells.csv with group attack, once for every vocation that lists it. It is the group the
cooldown ladder, the rotation model, the helper and the spellbook already use, so it counts the snares, Feral
Command, Corpse Explosion and the strikes that carry a debuff. Minions, supports and healing are not counted.

Checks:
 - every one of the 21 vocations has exactly ATTACK_SPELLS (12) attack spells;
 - the three classes of a line (a base class and its two ascensions) have the same count, and every line the same as
   the others (this follows from the first check but names the line that is off);
 - every attack spell has a vocation list and no vocation outside the 21.
usage: python3 -I tools/ci/check_attack_counts.py [--table]      (--table prints the count of every class)
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(REPO, 'server', 'tools'))
import rotation_sim as R  # noqa: E402

ATTACK_SPELLS = 12


def counts(spells):
    """{class: [names of its attack spells]} for the 21 classes of rotation_sim.CLASSES"""
    out = {cls: [] for cls, _, _ in R.CLASSES}
    for s in spells:
        if s['group'] != 'attack':
            continue
        for v in s['vocations']:
            if v in out:
                out[v].append(s['name'])
    return out


def problems(spells, want=ATTACK_SPELLS):
    """the failures of a list of spell rows (rotation_sim.load_chaos() + load_stock()), as strings"""
    bad = []
    known = {cls for cls, _, _ in R.CLASSES}
    for s in spells:
        if s['group'] != 'attack':
            continue
        if not s['vocations']:
            bad.append('%s: an attack spell with no vocation' % s['name'])
        for v in s['vocations']:
            if v not in known:
                bad.append('%s: unknown vocation %s' % (s['name'], v))
    have = counts(spells)
    for cls, names in have.items():
        dup = sorted({n for n in names if names.count(n) > 1})
        if dup:
            bad.append('%s lists %s twice' % (cls, ', '.join(dup)))
        if len(names) != want:
            bad.append('%s has %d attack spells, every class needs %d' % (cls, len(names), want))
    lines = {}
    for cls, line, _ in R.CLASSES:
        lines.setdefault(line, []).append(len(have[cls]))
    for line, ns in lines.items():
        if len(set(ns)) != 1:
            bad.append('the %s line differs between its base class and its ascensions: %s' % (line, ns))
    return bad


def main(argv):
    spells = R.load_chaos() + R.load_stock()
    if '--table' in argv:
        have = counts(spells)
        for cls, line, _ in R.CLASSES:
            print('%-13s %-12s %2d' % (cls, line, len(have[cls])))
    bad = problems(spells)
    for b in bad:
        print('FAIL', b)
    if bad:
        return 1
    print('check_attack_counts: all %d classes have %d attack spells' % (len(R.CLASSES), ATTACK_SPELLS))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
