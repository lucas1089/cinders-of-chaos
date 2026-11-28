#!/usr/bin/env python3
"""python3 -I client/tools/sprites/gen_idle_loops_test.py : gen_idle_loops.py (O787, pair 92) on a synthetic pair: a recipe
from an idle_loop.py json, a pickupable item never padded, the loops of every pattern, the table and sums, `build` (items
animated in place: flags kept, a padded still on its own tile, patterns, durations, the append-only guard, same bytes
twice, a wrong pair refused) and `live` (the loop form, the still form pending or not); then the committed recipes,
table, sums and wire rows. Synthetic pictures only (CI uses the fx venv)."""
import io
import json
import os
import shutil
import struct
import sys
import tempfile
from contextlib import redirect_stdout

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_idle_loops as G  # noqa: E402
import idle_loop as IL  # noqa: E402
import check_pair as cp  # noqa: E402
import check_pair_test as t  # noqa: E402

FAILS = []


def ok(cond, msg):
    if not cond:
        FAILS.append(msg)
        print('FAIL:', msg)


def quiet(fn, *a, **kw):
    with redirect_stdout(io.StringIO()):
        return fn(*a, **kw)


def blob(cx, cy, r, base, accent):
    """a round body of radius r at (cx, cy) of a 32 px tile, a bright accent in the middle"""
    px = {}
    for y in range(32):
        for x in range(32):
            d = (x - cx) ** 2 + (y - cy) ** 2
            if d <= r * r:
                shade = max(0, 60 - 6 * int(d ** 0.5))
                px[y * 32 + x] = accent if d <= 2 else (min(255, base[0] + shade), base[1], base[2], 255)
    return px


NOTMOVE = bytes([13])          # 10.98: notmoveable
PICKUP = bytes([17])           # pickupable


def synthetic():
    recs = [t.record(blob(16, 20, 8, (90, 40, 30), (255, 220, 120, 255))),     # 1
            t.record(blob(14, 18, 7, (40, 60, 120), (200, 240, 255, 255))),    # 2
            t.record(blob(18, 20, 7, (40, 90, 60), (220, 255, 200, 255))),     # 3
            t.record(blob(15, 22, 6, (100, 40, 100), (255, 200, 255, 255))),   # 4
            t.record(blob(17, 19, 8, (80, 80, 40), (255, 255, 160, 255))),     # 5
            t.record(blob(24, 24, 12, (70, 50, 50), (255, 180, 120, 255))),    # 6 2x2: bottom right
            t.record(blob(8, 24, 12, (70, 50, 50), (255, 180, 120, 255))),     # 7 2x2: bottom left
            t.record(blob(24, 31, 6, (70, 50, 50), (255, 180, 120, 255))),     # 8 2x2: top right
            t.record(blob(16, 20, 8, (40, 80, 100), (180, 255, 255, 255)))]    # 9 pickupable gem
    items = [t.entry(NOTMOVE, [t.group([1])]),                                   # 100 a brazier: padded
             t.entry(NOTMOVE, [t.group([2, 3, 4, 5], px=2, py=2)]),              # 101 four position patterns
             t.entry(NOTMOVE + bytes([22]) + struct.pack('<HH', 4, 181), [t.group([6, 7, 8, 0], w=2, h=2)]),   # 102 2x2, light
             t.entry(PICKUP, [t.group([9])])]                                    # 103 pickupable
    base = t.good_parts()
    return recs, items, base[2], base[3], base[4]


def src_json(path, cid, layers, pad=False, frames=12, ms=100):
    meta = {'tool': 'idle_loop.py', 'frames': frames, 'ms': ms, 'seed': 0, 'soft': False, 'theme': None, 'element': None,
            'layers': layers, 'clamp': 56, 'pad': pad, 'pair': {'item': cid, 'dat_md5': 'f' * 32}}
    with open(path, 'w') as f:
        json.dump(meta, f)


def test_pair():
    c = t.Case()
    try:
        recs, items, outfits, effects, missiles = synthetic()
        dat, spr = c.pair(recs, items, outfits, effects, missiles)
        md5 = G.file_md5(dat)
        rdir = os.path.join(c.dir, 'recipes')
        os.makedirs(rdir)
        motes = [IL.layer('motes', (240, 110, 20), amount=3), IL.layer('pulse', (240, 110, 20))]
        shine = [IL.layer('shine', (255, 215, 110)), IL.layer('pulse', (255, 215, 110))]
        pulse = [IL.layer('pulse', (110, 200, 255))]
        plan = [(1, 100, motes, True, False), (2, 101, pulse, False, False), (3, 102, shine, False, False),
                (4, 103, motes, True, True)]
        for n, cid, layers, pad, keep in plan:
            src = os.path.join(c.dir, 'src_%d.json' % cid)
            src_json(src, cid, layers, pad)
            argv = ['recipe', src, os.path.join(rdir, '%02d_%d.json' % (n, cid)), '--pair', dat, spr, '--n', str(n),
                    '--name', 'thing %d' % cid] + (['--keep-1x1'] if keep else [])
            ok(quiet(G.main, argv) == 0, 'recipe %d passes on the synthetic pair' % cid)
        # a pickupable item is never padded
        src = os.path.join(c.dir, 'src_103.json')
        try:
            quiet(G.main, ['recipe', src, os.path.join(c.dir, 'x.json'), '--pair', dat, spr, '--n', '9'])
            ok(False, 'a padded pickupable item is refused')
        except SystemExit as e:
            ok('pickupable' in str(e), 'a padded pickupable item is refused: %s' % e)
        r103 = json.load(open(os.path.join(rdir, '04_103.json')))
        ok(r103['pad'] is False and r103['kept_1x1'] is True and r103['size'] == [32, 32], 'kept 1x1: no pad, 32 x 32')
        r101 = json.load(open(os.path.join(rdir, '02_101.json')))
        ok(r101['patterns'] == [2, 2] and r101['pair']['dat_md5'] == md5, 'the recipe names the patterns and this pair')

        rows, lines, drawn, bad = G.make(dat, spr, rdir, md5, log=lambda *_a: None)
        ok(bad == [], 'make: every loop passes: %s' % bad)
        ok([(ln[0], ln[1], ln[2]) for ln in lines] == [(100, 0, 0), (101, 0, 0), (101, 1, 0), (101, 0, 1), (101, 1, 1),
                                                        (102, 0, 0), (103, 0, 0)], 'one loop per pattern')
        ok(len({ln[4] for ln in lines if ln[0] == 101}) == 4, 'each pattern has its own loop')
        ok([(r['tiles'], r['exact']) for r in rows] == [('2x2', 64), ('1x1', 32), ('2x2', 64), ('1x1', 32)],
           'tiles and exact size: padded 2x2 of 64, 1x1, a 2x2 keeps its exact size')
        try:
            G.make(dat, spr, rdir, 'e' * 32, log=lambda *_a: None)
            ok(False, 'another pair is refused')
        except SystemExit:
            ok(True, 'another pair is refused')

        table, sums, wire = (os.path.join(c.dir, n) for n in ('t.csv', 's.sums', 'w.csv'))
        open(table, 'w').write(G.table_text(rows))
        open(sums, 'w').write(G.sums_text(lines))
        open(wire, 'w').write('server,client,animation,group\n4100,100,1,\n4101,101,1,\n4102,102,1,\n4103,103,1,\n')
        ok(G.check(rdir, table, sums, wire, expect=4, source_md5=md5) == [], 'check: recipes, table, sums and wire agree: %s'
           % G.check(rdir, table, sums, wire, expect=4, source_md5=md5))
        open(wire, 'w').write('server,client,animation,group\n4100,100,1,\n4101,101,0,\n')
        bad = G.check(rdir, table, sums, wire, expect=4, source_md5=md5)
        ok(any('animation 0' in b for b in bad) and any('item 102' in b for b in bad), 'check: a wire row off, a node missing')
        open(table, 'w').write(G.table_text(rows).replace(',12,100,', ',12,120,', 1))
        ok(any('ms' in b for b in G.check(rdir, table, sums, wire, expect=4, source_md5=md5)), 'check: a stale table row')

        out = os.path.join(c.dir, 'out')
        quiet(G.build, dat, spr, out, rdir, sums, md5)
        od, os_ = os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr')
        ok(G.live(od, os_, rdir, sums, pending_ok=False) == ([], []), 'live: the built pair holds every loop')
        ok(G.live(dat, spr, rdir, sums, pending_ok=True) == ([], [100, 101, 102, 103]), 'live: the still pair is pending')
        bad, _p = G.live(dat, spr, rdir, sums, pending_ok=False)
        ok(len(bad) == 4 and all('one phase' in b for b in bad), 'live: the still pair once due: %s' % bad)

        old = {x.id: x for x in cp.parse_dat(open(dat, 'rb').read())[2]['item']}
        new = {x.id: x for x in cp.parse_dat(open(od, 'rb').read())[2]['item']}
        for cid in (100, 101, 102, 103):
            ok(new[cid].flags == old[cid].flags, 'item %d keeps its flag bytes' % cid)
        g = {cid: new[cid].groups[0] for cid in new}
        ok((g[100].w, g[100].h, g[100].phases) == (2, 2, 12), 'the padded item is 2x2 of 12 phases')
        ok((g[101].w, g[101].px, g[101].py, g[101].phases, len(g[101].sprites)) == (1, 2, 2, 12, 48), 'patterns kept')
        ok((g[102].w, g[102].phases) == (2, 12) and (g[103].w, g[103].phases) == (1, 12), '2x2 and 1x1 animated')
        import datspr
        nd, ns = datspr.Dat(od), datspr.Spr(os_)
        ok(all(nd.items[i - 100].anim[:3] == G.ANIM_HEAD and set(nd.items[i - 100].anim[3]) == {100}
               for i in (100, 101, 102, 103)), 'animator async, forever, from phase 0; 100 ms a phase')
        ok(nd.items[102 - 100].exact == 64 and nd.items[100 - 100].exact == 64, 'exact sizes')
        # the padded still stands on its own tile: its pixels in the bottom right tile of every frame
        sd, ss = datspr.Dat(dat), datspr.Spr(spr)
        still = G.thing_canvas(sd.items[0], ss)
        body = still[..., 3] > 0
        for ph in range(12):
            f = G.thing_canvas(nd.items[0], ns, phase=ph)
            ok((f[32:, 32:, 3][body] == 255).all(), 'phase %d: the body stays on its own tile' % ph)
        ok(not np.array_equal(G.thing_canvas(nd.items[0], ns, phase=0), G.thing_canvas(nd.items[0], ns, phase=6)),
           'the brazier moves')
        r = cp.check(od, os_, auras={2}, monsters={}, old=(dat, spr), allow_changed=cp.parse_allow('item:100-103'))
        ok(r.ok, 'the append-only guard passes with the four items allowed to change: ' + r.text())
        ok(not cp.check(od, os_, auras={2}, monsters={}, old=(dat, spr)).ok, 'without the allowance the guard sees them')
        out2 = os.path.join(c.dir, 'out2')
        quiet(G.build, dat, spr, out2, rdir, sums, md5)
        ok(open(os.path.join(out2, 'Tibia.spr'), 'rb').read() == open(os_, 'rb').read() and
           open(os.path.join(out2, 'Tibia.dat'), 'rb').read() == open(od, 'rb').read(), 'same inputs, same pair')
        try:
            quiet(G.build, od, os_, os.path.join(c.dir, 'out3'), rdir, sums, md5)
            ok(False, 'the built pair is not a source')
        except SystemExit:
            ok(True, 'the built pair is not a source')
        bad_sums = os.path.join(c.dir, 'bad.sums')
        open(bad_sums, 'w').write(open(sums).read().replace(' after ', ' after 0', 1))
        try:
            quiet(G.build, dat, spr, os.path.join(c.dir, 'out4'), rdir, bad_sums, md5)
            ok(False, 'loops that differ from the sums are refused')
        except SystemExit:
            ok(True, 'loops that differ from the sums are refused')
    finally:
        shutil.rmtree(c.dir, ignore_errors=True)


def test_committed():
    bad = G.check()
    ok(bad == [], 'the committed recipes, table, sums and wire rows agree: %s' % bad[:5])
    rs = G.recipes()
    ok(all(r['option'] == 'A' for r in rs), 'option A for all (owner 2026-11-28 "Todos a")')
    ok(sum(1 for r in rs if r['pad']) == 6 and sum(1 for r in rs if r['kept_1x1']) == 7, '6 padded, 7 kept 1x1')
    import client_pair
    ok(client_pair.PAIR_IDLE_LOOPS == G.PAIR == 92, 'client_pair.PAIR_IDLE_LOOPS is the pair of the loops')


def main():
    test_pair()
    test_committed()
    print('gen_idle_loops_test: %s' % ('OK' if not FAILS else '%d FAILED' % len(FAILS)))
    return 1 if FAILS else 0


if __name__ == '__main__':
    sys.exit(main())
