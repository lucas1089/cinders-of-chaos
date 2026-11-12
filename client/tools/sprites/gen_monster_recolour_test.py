#!/usr/bin/env python3
"""Test of gen_monster_recolour.py (O529): python3 -I client/tools/sprites/gen_monster_recolour_test.py"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
import gen_monster_recolour as G  # noqa: E402


def px(r, g, b, a=255):
    return np.array([[[r, g, b, a]]], dtype=np.uint8)


def row(m, sh=10, look='1', mode='hue', hue='0'):
    return {'look': look, 'hue_shift': str(sh), 'monster': m, 'mode': mode, 'theme': 'x', 'source_hue': hue, 'source_sat': '1'}


def main():
    # red +120 = green, +240 = blue; alpha stays; a grey pixel has no hue and stays in mode hue
    assert tuple(G.recolour(px(255, 0, 0), 120)[0, 0]) == (0, 255, 0, 255)
    assert tuple(G.recolour(px(255, 0, 0), 240)[0, 0]) == (0, 0, 255, 255)
    assert tuple(G.recolour(px(120, 120, 120, 200), 90)[0, 0]) == (120, 120, 120, 200)
    o = G.recolour(px(200, 100, 0), 180)[0, 0]   # value and saturation stay
    assert max(o[:3]) == 200 and min(o[:3]) == 0, o
    t = G.recolour(px(100, 100, 100), 120, 'tint')[0, 0]   # grey takes the target hue at the tint saturation, value kept
    assert t[1] == 100 and t[0] == t[2] and abs(int(t[0]) - round(100 * (1 - G.TINT_SAT))) <= 1, t
    # the committed table
    assert G.problems() == [], G.problems()
    assert G.problems([row('A', 400)])
    assert any('less than' in p for p in G.problems([row('A', 10), row('B', 20)]))
    assert G.problems([row('A', 100), row('B', 200)]) == []
    assert any('two rows' in p for p in G.problems([row('A', 100), row('A', 200)]))
    assert G.main(['build']) == 2
    print('gen_monster_recolour_test: OK')


if __name__ == '__main__':
    main()
