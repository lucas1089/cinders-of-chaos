#!/usr/bin/env python3
"""Tests of gen_awakened_fx.py (O711, prototype): the table rules, the drawing held to its bar (the same bytes twice, frame
counts, alpha 0 / one glow level / 255, canvas bounds, the start and the fade close, no equal neighbour frames), distinct
pictures per element and per shape, the committed sums; the pair step on a synthetic pair of 5,353 effects and 253 missiles
(build, live, a changed pixel, refusals), the turned missile patterns, the ids file and the tags (stale cases). No real pair:
python3 -I client/tools/sprites/gen_awakened_fx_test.py (numpy, Pillow)."""
import io
import os
import shutil
import sys
import tempfile
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_awakened_fx as G  # noqa: E402
import check_pair_test as T  # noqa: E402
from datspr import Dat  # noqa: E402

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


def quiet(fn, *a):
    buf = io.StringIO()
    with redirect_stdout(buf):
        try:
            rc = fn(*a)
        except SystemExit as e:
            rc = e.code if isinstance(e.code, int) else 1
            buf.write(str(e.code))
    return rc, buf.getvalue()


def synthetic_pair(effects=5353, missiles=253, blank=G.BLANK_IDS):
    import numpy as np
    import import_art_things as iat
    recs = [iat.encode_sprite(np.full((32, 32, 4), 200, np.uint8)), iat.encode_sprite(np.full((32, 32, 4), 90, np.uint8))]
    items = [T.entry(bytes([17]), [T.group([1])])]
    effs = [T.entry(b'', [T.group([2])]) for _ in range(effects)]
    miss = [T.entry(b'', [T.group([0 if i + 1 in blank else 1] * 9, px=3, py=3)]) for i in range(missiles)]
    outfits = [T.entry(b'', [T.group([1] * 4, px=4, gtype=0)], outfit=True)]
    return T.Case().pair(recs, items, outfits, effs, miss)


def test_missile_strip():
    import numpy as np
    east = np.zeros((32, 32 * 2, 4), np.uint8)
    east[16, 23] = (200, 100, 50, 255)
    east[10, 20] = (10, 20, 30, 144)
    east[16, 32 + 24] = (7, 8, 9, 255)
    out = G.missile_strip(east)
    ok(out.shape == (96, 96 * 2, 4), 'a missile strip is 3 x 3 patterns of 2 frames')

    def cell(d, f):
        px, py = G.PATTERN[d]
        return out[py * 32:(py + 1) * 32, (px * 2 + f) * 32:(px * 2 + f + 1) * 32]

    ok((cell('east', 0) == east[:, :32]).all() and (cell('east', 1) == east[:, 32:]).all(), 'the east pattern is the strip')
    ok(tuple(cell('north', 0)[8, 16]) == (200, 100, 50, 255), 'north: the head turned up')
    ok(tuple(cell('west', 0)[15, 8]) == (200, 100, 50, 255), 'west: the head turned back')
    ok(tuple(cell('south', 0)[23, 15]) == (200, 100, 50, 255), 'south: the head turned down')
    mid = out[32:64, 2 * 32:3 * 32]
    ok((mid == cell('south', 0)).all(), 'the middle cell repeats south')
    cols = {tuple(c) for c in out[out[..., 3] > 0].tolist()}
    ok(cols <= {(200, 100, 50, 255), (10, 20, 30, 144), (7, 8, 9, 255)}, 'turning makes no colour and no alpha level')
    ok(not out[out[..., 3] == 0].any(), 'a transparent pixel carries no colour')
    for d in G.DIRS:
        n = int((cell(d, 0)[..., 3] > 0).sum())
        ok(n == 2 if 0 in G.DIRS[d] else 1 <= n <= 4, '%s: the turn keeps the picture (%d pixels)' % (d, n))
    ok(G.missile_strip(east).tobytes() == out.tobytes(), 'the same bytes twice')


def test_pair_step():
    tmp = tempfile.mkdtemp(prefix='awakened_test_')
    sums = G.SUMS
    try:
        dat, spr = synthetic_pair()
        o1 = os.path.join(tmp, 'o1')
        rc, out = quiet(G.build, dat, spr, o1)
        ok(rc == 0 and 'live: 40 effects at 5354..5393, 8 missiles, OK' in out, 'build and live: ' + out[-300:])
        od, nd = Dat(dat), Dat(os.path.join(o1, 'Tibia.dat'))
        ok(len(nd.effects) == 5393 and len(nd.missiles) == 253, '40 effects appended, no missile appended')
        ok(all(nd.data[a.raw[0]:a.raw[1]] == od.data[b.raw[0]:b.raw[1]] for a, b in zip(nd.effects[:5353], od.effects)),
           'the old effects are byte-identical')
        mine = set(G.MISSILE_IDS)
        same = [nd.data[a.raw[0]:a.raw[1]] == od.data[b.raw[0]:b.raw[1]] for i, (a, b) in enumerate(zip(nd.missiles, od.missiles))
                if i + 1 not in mine]
        ok(all(same) and len(same) == 245, 'the other 245 missiles are byte-identical')
        for mid in G.MISSILE_IDS:
            m = nd.missiles[mid - 1]
            ok((m.w, m.h, m.phases) == (1, 1, G.MISSILE_FRAMES) and any(m.sprites), 'missile %d holds a 1 x 1, 4 phase missile' % mid)
        o2 = os.path.join(tmp, 'o2')
        quiet(G.build, dat, spr, o2)
        ok(open(os.path.join(o1, 'Tibia.dat'), 'rb').read() == open(os.path.join(o2, 'Tibia.dat'), 'rb').read()
           and open(os.path.join(o1, 'Tibia.spr'), 'rb').read() == open(os.path.join(o2, 'Tibia.spr'), 'rb').read(),
           'the same bytes twice')
        rc, out = quiet(G.live, dat, spr)
        ok(rc == 1 and 'the pair has 5353 effects' in out, 'live: the input pair fails')
        lines = open(sums).read().splitlines()
        bad = os.path.join(tmp, 'bad.sums')
        open(bad, 'w').write('\n'.join(['0' * 64 + lines[0][64:]] + lines[1:]) + '\n')
        G.SUMS = bad
        rc, out = quiet(G.live, os.path.join(o1, 'Tibia.dat'), os.path.join(o1, 'Tibia.spr'))
        ok(rc == 1 and 'pixels differ from the sum' in out, 'live: a changed pixel is found')
        G.SUMS = sums
        cases = [(5352, 253, G.BLANK_IDS), (5354, 253, G.BLANK_IDS), (5353, 252, G.BLANK_IDS), (5353, 253, (47, 52))]
        for k, (e, m, blank) in enumerate(cases):
            d2, s2 = synthetic_pair(e, m, blank)
            o = os.path.join(tmp, 'r%d' % k)
            rc, out = quiet(G.build, d2, s2, o)
            ok(rc == 1 and 'refused' in out and not os.path.exists(o), 'refused: %d effects, %d missiles, blank %s' % (e, m, blank))
        ok(not G.pair_ok(5393, 253) and G.pair_ok(5353, 253), 'only pair 75 is the input')
    finally:
        G.SUMS = sums
        shutil.rmtree(tmp, ignore_errors=True)


def test_ids_and_tags():
    rows = G.read_spec()
    ok(G.ids(True, quiet=True) == 0, 'the ids file and the tags are current')
    lua = G.lua_text(rows)
    ok(lua == open(G.LUA, encoding='utf-8', newline='').read(), 'the ids file is the text of the script')
    ok(lua.count('af_') == 48 and 'id = 5354,' in lua and 'id = 5393,' in lua, '40 effects and 8 missiles in the ids file')
    for r in rows:
        if r['kind'] == 'missile':
            ok('%s = {id = %d,' % (r['name'], G.MISSILE_IDS[int(r['slot']) - 1]) in lua, '%s at its id' % r['name'])
    ok(len(set(G.MISSILE_IDS)) == 8 and all(1 <= i <= 253 for i in G.MISSILE_IDS), 'eight different missile ids inside the pair')
    tags = G.tags_text(rows)
    ok(tags.count(',af_') == 40, 'one tag per effect')
    for r in rows:
        if r['kind'] == 'effect':
            ok('\n%d,%s,%s\n' % (G.FIRST + int(r['slot']) - 1, r['name'], r['element']) in tags,
               '%s tagged %s' % (r['name'], r['element']))
    tmp = tempfile.mkdtemp(prefix='awakened_ids_')
    keep = (G.LUA, G.TAGS)
    try:
        G.LUA = os.path.join(tmp, 'ids.lua')
        G.TAGS = os.path.join(tmp, 'tags.csv')
        shutil.copy(keep[0], G.LUA)
        shutil.copy(keep[1], G.TAGS)
        ok(quiet(G.ids, True)[0] == 0, 'copies are current')
        open(G.LUA, 'a').write('-- stale\n')
        rc, out = quiet(G.ids, True)
        ok(rc == 1 and 'OUT OF DATE' in out, 'a stale ids file is found')
        ok(quiet(G.check, True)[0] == 1, 'check fails on a stale ids file')
        quiet(G.ids, False)
        ok(quiet(G.ids, True)[0] == 0, 'ids rewrites it')
        text = open(G.TAGS).read().replace(',af_fire_single,fire', ',af_fire_single,ice')
        open(G.TAGS, 'w').write(text)
        ok(quiet(G.ids, True)[0] == 1, 'a wrong tag is found')
        text = open(G.TAGS).read().splitlines()
        open(G.TAGS, 'w').write('\n'.join(l for l in text if ',af_ice_' not in l) + '\n')
        ok(quiet(G.ids, True)[0] == 1, 'a missing tag is found')
    finally:
        G.LUA, G.TAGS = keep
        shutil.rmtree(tmp, ignore_errors=True)


def test_check():
    ok(G.check(quiet=True) == 0, 'check passes on the repository')


if __name__ == '__main__':
    test_table()
    test_ramps()
    test_drawing()
    test_missiles()
    test_missile_strip()
    test_pair_step()
    test_ids_and_tags()
    test_check()
    print('gen_awakened_fx tests: %d checks OK' % N[0])
