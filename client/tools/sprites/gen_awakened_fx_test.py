#!/usr/bin/env python3
"""Tests of gen_awakened_fx.py (O711, prototype): the table rules, the drawing held to its bar (the same bytes twice, frame
counts, alpha 0 / one glow level / 255, canvas bounds, the start and the fade close, no equal neighbour frames), distinct
pictures per element and per shape, the committed sums. No pair:
python3 -I client/tools/sprites/gen_awakened_fx_test.py (numpy, Pillow)."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_awakened_fx as G  # noqa: E402

N = [0]


def ok(cond, msg):
    N[0] += 1
    if not cond:
        raise SystemExit('FAIL: ' + msg)


def test_table():
    rows = G.pieces()
    ok(G.table_errors(rows) == [], 'the table holds its rules: %s' % G.table_errors(rows))
    eff = [r for r in rows if r['kind'] == 'effect']
    mis = [r for r in rows if r['kind'] == 'missile']
    ok(len(G.ELEMENTS) == 8 and len(G.SHAPES) == 5, '8 elements and 5 shapes')
    ok(len(eff) == 40 and len(mis) == 8, '40 effects and 8 missiles')
    ok(all(10 <= int(r['frames']) <= 12 for r in eff), 'effects of 10 to 12 frames')
    ok({r['element'] for r in eff} == set(G.ELEMENTS) and {r['shape'] for r in eff} == set(G.SHAPES), 'every element and shape')
    bad = [dict(r) for r in rows]
    bad[1]['slot'] = 9
    ok(G.table_errors(bad), 'a hole in the slots is found')
    bad = [dict(r) for r in rows]
    bad[0]['name'] = 'fire'
    ok(G.table_errors(bad), 'a name is af_*')
    bad = [dict(r) for r in rows]
    bad[1]['seed'] = bad[0]['seed']
    ok(G.table_errors(bad), 'a shared seed is found')
    bad = [dict(r) for r in rows]
    bad[0]['frames'] = 6
    ok(G.table_errors(bad), 'a short effect is found')
    spec = G.read_spec()
    ok([[str(r[k]) for k in G.FIELDS] for r in rows] == [[r[k] for k in G.FIELDS] for r in spec], 'awakened_fx.csv is the table')
    ok(G.read_total() == [len(rows)], 'the total row records the count')
    ok(list(G.read_sums()) == [r['name'] for r in rows], 'one sum per row, in order')


def test_ramps():
    seen = set()
    for el in G.ELEMENTS:
        r = G.ramp(el)
        ok(len(r) == G.N + len(G.EXTRA.get(el, ())) and len(set(r)) == len(r), '%s: a ramp of %d different colours' % (el, len(r)))
        ok(sum(r[0]) < sum(r[G.N - 1]), '%s: dark to light' % el)
        ok(r[0] != (0, 0, 0), '%s: the rim is a dark shade, not black' % el)
        ok(tuple(r) not in seen, '%s: its own ramp' % el)
        seen.add(tuple(r))
    mids = [G.ramp(e)[12] for e in G.ELEMENTS]
    for i in range(len(mids)):
        for j in range(i + 1, len(mids)):
            d = sum(abs(a - b) for a, b in zip(mids[i], mids[j]))
            ok(d >= 40, 'the mid colours of %s and %s differ' % (G.ELEMENTS[i], G.ELEMENTS[j]))


def test_drawing():
    import numpy as np
    pairs = G.build_rows()
    again = G.build_rows()
    sums = G.read_sums()
    digests = {}
    for (r, s), (_r2, s2) in zip(pairs, again):
        ok(s.tobytes() == s2.tobytes(), '%s: the same bytes twice' % r['name'])
        ok(G.digest(s) == sums[r['name']], '%s: the committed sum' % r['name'])
        ok(G.art_errors(s, r) == [], '%s holds the bar: %s' % (r['name'], G.art_errors(s, r)))
        n = int(r['frames'])
        ok(s.shape == (int(r['h']) * 32, int(r['w']) * 32 * n, 4) and s.dtype == np.uint8,
           '%s: %d frames of the canvas' % (r['name'], n))
        ok(set(np.unique(s[..., 3]).tolist()) <= {0, G.GLOW, 255}, '%s: alpha 0, %d or 255' % (r['name'], G.GLOW))
        ok((s[..., 3] == 255).any() and (s[..., 3] == G.GLOW).any(), '%s: solid pixels and a glow' % r['name'])
        digests[r['name']] = G.digest(s)
    ok(len(set(digests.values())) == len(digests), 'no two strips are the same picture')
    means = {}
    for r, s in pairs:
        if r['kind'] == 'effect':
            a = s[..., 3] == 255
            means.setdefault(r['element'], []).append(s[a][:, :3].mean(axis=0))
    em = {e: np.mean(v, axis=0) for e, v in means.items()}
    for i, a in enumerate(G.ELEMENTS):
        for b in G.ELEMENTS[i + 1:]:
            ok(float(np.abs(em[a] - em[b]).sum()) > 30, '%s and %s are different in colour' % (a, b))
    canv = {(int(r['w']), int(r['h'])) for r, _ in pairs if r['kind'] == 'effect'}
    ok(len(canv) == 4, 'the shapes have four different canvases (single and around share one)')
    by = {r['name']: (r, s) for r, s in pairs}
    for el in G.ELEMENTS:
        cs = []
        for sh in ('single', 'around'):
            r, s = by['af_%s_%s' % (el, sh)]
            W = int(r['w']) * 32
            k = max(range(int(r['frames'])), key=lambda i: int((s[:, i * W:(i + 1) * W, 3] > 0).sum()))
            f = s[:, k * W:(k + 1) * W, 3] > 0
            cs.append(int(f[36:60, 40:56].sum()))
        ok(cs[0] > 0 and cs[0] != cs[1], '%s: around is not single (%s)' % (el, cs))


def test_missiles():
    for r, s in G.build_rows():
        if r['kind'] != 'missile':
            continue
        ok(s.shape == (32, 32 * G.MISSILE_FRAMES, 4), '%s: 4 phases of 32 x 32' % r['name'])
        fr = [s[:, i * 32:(i + 1) * 32].tobytes() for i in range(G.MISSILE_FRAMES)]
        ok(len(set(fr)) == G.MISSILE_FRAMES, '%s: four different phases' % r['name'])


def test_check():
    ok(G.check(quiet=True) == 0, 'check passes on the repository')


if __name__ == '__main__':
    test_table()
    test_ramps()
    test_drawing()
    test_missiles()
    test_check()
    print('gen_awakened_fx tests: %d checks OK' % N[0])
