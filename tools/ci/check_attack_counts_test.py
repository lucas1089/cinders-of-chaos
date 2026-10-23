#!/usr/bin/env python3
"""python3 -I tools/ci/check_attack_counts_test.py: check_attack_counts.py on synthetic spell lists (a class short of
spells, a line out of step, a duplicate, an unknown vocation, healing not counted) and on the repository (passes)."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import check_attack_counts as C  # noqa: E402

fails = 0


def ok(cond, what):
    global fails
    if not cond:
        print('FAIL', what)
        fails += 1


CLASSES = [c for c, _, _ in C.R.CLASSES]


def full(n=2):
    """n attack spells per class, each spell listed for one class only"""
    return [{'name': '%s %d' % (c, i), 'group': 'attack', 'vocations': [c]} for c in CLASSES for i in range(n)]


ok(C.problems(full(2), 2) == [], 'an even list passes')
ok(len(CLASSES) == 21, 'twenty-one classes')

short = full(2)[:-1]
bad = C.problems(short, 2)
ok(len(bad) >= 2 and any('Sentinel has 1' in b for b in bad), 'a class one spell short is named: %s' % bad)
ok(any('templar line' in b.lower() for b in bad), 'and its line is named as out of step: %s' % bad)

extra = full(2) + [{'name': 'Extra', 'group': 'attack', 'vocations': ['Monk']}]
bad = C.problems(extra, 2)
ok(any('Monk has 3' in b for b in bad), 'a class with one spell too many fails')

heal = full(2) + [{'name': 'Mend', 'group': 'healing', 'vocations': CLASSES}]
ok(C.problems(heal, 2) == [], 'healing spells are not counted')

support = full(2) + [{'name': 'Haste', 'group': 'support', 'vocations': CLASSES}]
ok(C.problems(support, 2) == [], 'supports are not counted')

dup = full(2) + [{'name': 'Warrior 0', 'group': 'attack', 'vocations': ['Warrior']}]
ok(any('twice' in b for b in C.problems(dup, 2)), 'a spell listed twice for a class fails')

shared = [{'name': 'S%d' % i, 'group': 'attack', 'vocations': list(CLASSES)} for i in range(3)]
ok(C.problems(shared, 3) == [], 'a spell shared by every class counts once for each')

unknown = full(2) + [{'name': 'Odd', 'group': 'attack', 'vocations': ['Bard']}]
ok(any('unknown vocation Bard' in b for b in C.problems(unknown, 2)), 'an unknown vocation fails')

none = full(2) + [{'name': 'Orphan', 'group': 'attack', 'vocations': []}]
ok(any('no vocation' in b for b in C.problems(none, 2)), 'an attack spell with no class fails')

ok(C.main([]) == 0, 'the repository passes')

if fails:
    sys.exit(1)
print('check_attack_counts_test: ok')
