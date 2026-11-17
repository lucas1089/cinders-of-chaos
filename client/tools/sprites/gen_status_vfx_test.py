#!/usr/bin/env python3
"""Tests of gen_status_vfx.py on sheets and a small pair the test draws itself (no pack art, no real pair; numpy, Pillow).

python3 -I client/tools/sprites/gen_status_vfx_test.py

Covers: the committed table and sums (check), the alpha levels (solid, one glow level, nothing below `lo`: a faint body
shadow goes), the scale and anchor of a status canvas, every `step`th frame, the kill rules (the plain body goes, a band
above the feet, blank frames before N, the feet on the canvas point), the source found by digest whatever its name,
the pair step (blank effects up to the reserved id, fixed ids after it, older things byte-identical, refusals for a
pair that is too small or too big, the same bytes twice), `live` on the built pair and after a changed pixel, the
generated Lua and tag text.
"""
import hashlib
import io
import os
import shutil
import sys
import tempfile
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
import check_pair_test as t  # noqa: E402
import gen_status_vfx as G  # noqa: E402
import import_art_things as iat  # noqa: E402
from datspr import Dat, Spr  # noqa: E402

fails = 0
checks = 0


def check(cond, what):
    global fails, checks
    checks += 1
    if not cond:
        fails += 1
        print('FAIL', what)


def quiet(fn, *a):
    buf = io.StringIO()
    with redirect_stdout(buf):
        try:
            rc = fn(*a)
        except SystemExit as e:
            rc = e.code if isinstance(e.code, int) else 1
            buf.write(str(e.code))
    return rc, buf.getvalue()


def status_sheet(cols=3, rows=2):
    """cells of 96 x 128: a solid red block at the feet, a half-alpha ring, a faint body shadow; the block moves a pixel a frame"""
    a = np.zeros((rows * 128, cols * 96, 4), np.uint8)
    for f in range(cols * rows):
        cy, cx = divmod(f, cols)
        c = a[cy * 128:(cy + 1) * 128, cx * 96:(cx + 1) * 96]
        c[40:112, 36:60] = (40, 40, 200, 36)            # the faint body shadow: must go
        c[20:40, 30:66] = (250, 240, 80, 110)           # a soft halo: the glow level
        c[96:112, 40 + f:56 + f] = (220, 30, 20, 255)   # solid, at the feet
    return Image.fromarray(a)


def kill_strip(n=4):
    a = np.zeros((64, n * 64, 4), np.uint8)
    for f in range(n):
        c = a[:, f * 64:(f + 1) * 64]
        c[44:47, 20 - f:44 + f] = (150, 90, 40, 255)    # ground art that widens
        if f < 2:
            c[20:47, 26:38] = G.BODY[0] + (255,)        # the plain body over it, feet at row 46
            c[20:47, 26] = G.BODY[2] + (255,)
        c[10 + f, 32] = (240, 240, 255, 255)            # a spark above
    return Image.fromarray(a)


def row(i, name, kind, **kw):
    r = dict(id=i, name=name, kind=kind, key=kw.pop('key'), part=kw.pop('part'), w=2, h=2, phases=3, ms=66, dx=0, dy=0,
             src='', cols=3, rows=2, frames=6, step=2, scale=0.5, sx=48, sy=112, ax=32, ay=56, gain=1.0, lo=0.3, tint='',
             rule='', element='any', note='test')
    r.update(kw)
    return r


def synthetic_pair(case, effects=2):
    recs = [iat.encode_sprite(np.full((32, 32, 4), 200, np.uint8)), iat.encode_sprite(np.full((32, 32, 4), 90, np.uint8))]
    items = [t.entry(bytes([17]), [t.group([1])])]
    effs = [t.entry(b'', [t.group([2])]) for _ in range(effects)]
    miss = [t.entry(b'', [t.group([1] * 9, px=3, py=3)])]
    return case.pair(recs, items, [], effs, miss)


def main():
    # ---- the committed table
    rc, out = quiet(G.check)
    check(rc == 0, 'the committed table, sums and generated files agree: ' + out[-300:])
    rows = G.read_table()
    check(len(rows) == 3 * len(G.STATUSES) + len(G.KILLS), 'three rows a status and one a kill overlay')
    check(rows[0]['id'] == 5143 and rows[-1]['id'] == 5143 + len(rows) - 1, 'ids from 5143 in table order')
    check(G.table_text(rows) == open(G.TABLE, encoding='utf-8', newline='').read(), 'the table is in the tool\'s format')
    text = open(G.TABLE, encoding='utf-8').read() + open(G.SUMS, encoding='utf-8').read()
    check(all(len(r['src']) == 12 for r in rows), 'src is 12 hex')
    check('/' not in text and '.png' not in text, 'no file name or path in the table and the sums')
    bad = [dict(r) for r in rows]
    bad[3]['id'] = 9
    check(any('expected' in e for e in G.table_errors(bad)), 'a moved id is an error')
    bad = [dict(r) for r in rows if r['name'] != 'st_stun_loop']
    check(any('stun has no loop' in e for e in G.table_errors(bad)), 'a missing part is an error')
    lua = G.lua_text(rows)
    check('M.PAIR = 73' in lua and 'burn = {start = 5143, loop = 5144, stop = 5145' in lua, 'the Lua names the ids')
    check(lua.count('start = ') == len(G.STATUSES) and 'melt = {id = ' in lua, 'every status and kill overlay in the Lua')
    tags = G.tags_text(rows)
    check(tags.count('\n5143,st_burn_start,fire\n') == 1 and tags.count(',st_') == len(rows), 'one tag row an effect')
    check(G.tags_text(rows) == open(G.TAGS, encoding='utf-8', newline='').read(), 'the tag file is current')

    # ---- levels
    pm = np.zeros((1, 4, 4), np.float32)
    pm[0, 0] = (0.8, 0.1, 0.1, 1.0)                    # solid
    pm[0, 1] = (0.4 * 0.4, 0.4 * 0.4, 0.1 * 0.4, 0.4)  # glow
    pm[0, 2] = (0.1 * 0.1, 0.1 * 0.1, 0.1 * 0.1, 0.1)  # below lo
    lv = G.levels(pm, 1.0, 0.3, (1.0, 1.0, 1.0))
    check(lv[0, 0, 3] == 255 and lv[0, 1, 3] == G.GLOW and lv[0, 2, 3] == 0 and lv[0, 3, 3] == 0, 'alpha 255, the glow level, nothing')
    check(tuple(lv[0, 2]) == (0, 0, 0, 0), 'a dropped pixel is 0, 0, 0, 0')
    check(int(lv[0, 1, 0]) > int(0.4 * 255), 'the glow colour is lifted')
    lv2 = G.levels(pm, 3.0, 0.3, (1.0, 1.0, 1.0))
    check(lv2[0, 1, 3] == 255 and lv2[0, 2, 3] == G.GLOW, 'gain moves pixels up a level')
    lv3 = G.levels(pm, 1.0, 0.3, (0.5, 1.0, 1.0))
    check(lv3[0, 0, 0] < lv[0, 0, 0], 'tint multiplies the colour')

    # ---- a status sheet
    r = row(6, 'st_burn_loop', 'status', key='burn', part='loop')
    fr = G.status_frames(status_sheet(), r)
    check(len(fr) == 3 and fr[0].shape == (64, 64, 4), 'frames 0, 2, 4 on a 64 x 64 canvas')
    alphas = set(np.unique(np.concatenate(fr)[..., 3]).tolist())
    check(alphas <= {0, G.GLOW, 255} and G.GLOW in alphas and 255 in alphas, 'only the three alpha levels: %s' % sorted(alphas))
    solid = np.nonzero(fr[0][..., 3] == 255)
    check(solid[0].max() == 55, 'the feet of the sheet (row 111) land just above canvas row 56: %d' % solid[0].max())
    check(abs((solid[1].min() + solid[1].max()) / 2.0 - 31.5) <= 1.0, 'centred on canvas x 32')
    body = fr[0][20:44, 26:30]
    check(not body[..., 3].any(), 'the faint body shadow is gone')
    x0 = np.nonzero(fr[0][..., 3] == 255)[1].min()
    x1 = np.nonzero(fr[1][..., 3] == 255)[1].min()
    check(x1 == x0 + 1, 'frame 2 of the sheet is the second frame (the block moved 2 px, 1 px at half scale)')
    r2 = dict(r, scale=1.0, sx=48, sy=104, ax=32, ay=16)
    fr2 = G.status_frames(status_sheet(), r2)
    s2 = np.nonzero(fr2[0][..., 3] == 255)
    check(s2[0].min() == 8 and s2[0].max() == 23, 'another anchor and scale: the block around canvas row 16')

    # ---- a kill strip
    k = row(7, 'st_kill_sink', 'kill', key='sink', part='over', w=3, h=2, dx=1, phases=4, cols=4, rows=1, frames=4, step=1,
            scale=1, sx=0, sy=0, ax=48, ay=56, lo=0.5, rule='nobody')
    kf = G.kill_frames(kill_strip(), k)
    check(len(kf) == 4 and kf[0].shape == (64, 96, 4), 'four frames on a 96 x 64 canvas')
    check(not G.is_body(kf[0])[kf[0][..., 3] > 0].any(), 'nobody: no body pixel left')
    ground = np.nonzero((kf[0][..., :3] == (150, 90, 40)).all(axis=2))
    check(ground[0].max() == 56, 'the pack\'s feet row sits on canvas row 56')
    check(abs((ground[1].min() + ground[1].max()) / 2.0 - 47.5) <= 1.0, 'and on canvas x 48')
    check((kf[0][..., :3] == (240, 240, 255)).all(axis=2).any(), 'the spark above stays')
    kb = G.kill_frames(kill_strip(), dict(k, rule='band:3;from:1'))
    check(not kb[0][..., 3].any(), 'from:1 blanks frame 0')
    check(kb[1][..., 3].any() and not (kb[1][..., :3] == (240, 240, 255)).all(axis=2).any(), 'band: only the rows at the feet')
    check(np.nonzero(kb[1][..., 3])[0].min() == 54, 'band:3 keeps three rows')

    # ---- the pair step on a synthetic pair
    tmp = tempfile.mkdtemp(prefix='statusvfx')
    keep = (G.BASE_EFFECTS, G.RESERVED_LAST, G.FIRST, G.TABLE, G.SUMS)
    try:
        src = os.path.join(tmp, 'any', 'deep')
        os.makedirs(src)
        status_sheet().save(os.path.join(src, 'whatever_name.png'))
        kill_strip().save(os.path.join(src, 'x.png'))
        open(os.path.join(src, 'notes.txt'), 'w').write('not a picture')

        def h12(p):
            return hashlib.sha256(open(p, 'rb').read()).hexdigest()[:12]
        sources = G.find_sources(tmp)
        check(set(sources) == {h12(os.path.join(src, 'whatever_name.png')), h12(os.path.join(src, 'x.png'))}, 'sources by digest')
        r['src'] = h12(os.path.join(src, 'whatever_name.png'))
        k['src'] = h12(os.path.join(src, 'x.png'))
        G.BASE_EFFECTS, G.RESERVED_LAST, G.FIRST = 2, 5, 6
        trows = [r, k]
        frames = [G.frames_of(x, sources) for x in trows]
        rc, out = quiet(G.frames_of, dict(r, src='0' * 12), sources)
        check(rc == 1 and 'no sheet' in out, 'a sheet that is not there is named')
        case = t.Case()
        dat, spr = synthetic_pair(case, effects=2)
        out1 = os.path.join(tmp, 'o1')
        rc, out = quiet(G.apply, dat, spr, out1, trows, frames)
        check(rc == 0 and '3 blank up to 5' in out, 'applied: ' + out[-200:])
        od, nd = Dat(dat), Dat(os.path.join(out1, 'Tibia.dat'))
        ns = Spr(os.path.join(out1, 'Tibia.spr'))
        check(len(nd.effects) == 7 and len(nd.missiles) == 1, '2 old + 3 blank + 2 new effects, the missile stays')
        check(all(nd.data[a.raw[0]:a.raw[1]] == od.data[b.raw[0]:b.raw[1]] for a, b in zip(nd.effects[:2], od.effects)),
              'the old effects are byte-identical')
        check(all((e.w, e.h, e.phases) == (1, 1, 1) and not any(e.sprites) for e in nd.effects[2:5]), 'the gap is blank effects')
        e6, e7 = nd.effects[5], nd.effects[6]
        check((e6.w, e6.h, e6.phases) == (2, 2, 3) and (e7.w, e7.h, e7.phases) == (3, 2, 4), 'the new effects at ids 6 and 7')
        check(ns.count > Spr(spr).count, 'sprites appended')
        out2 = os.path.join(tmp, 'o2')
        quiet(G.apply, dat, spr, out2, trows, frames)
        check(open(os.path.join(out1, 'Tibia.spr'), 'rb').read() == open(os.path.join(out2, 'Tibia.spr'), 'rb').read()
              and open(os.path.join(out1, 'Tibia.dat'), 'rb').read() == open(os.path.join(out2, 'Tibia.dat'), 'rb').read(),
              'the same bytes twice')
        # a pair that already has the sibling's effects up to the reserved id: no padding
        dat5, spr5 = synthetic_pair(t.Case(), effects=5)
        rc, out = quiet(G.apply, dat5, spr5, os.path.join(tmp, 'o5'), trows, frames)
        check(rc == 0 and '0 blank' in out, 'a full reserved block: nothing padded')
        check(len(Dat(os.path.join(tmp, 'o5', 'Tibia.dat')).effects) == 7, 'the same ids')
        # refusals
        rc, out = quiet(G.apply, os.path.join(out1, 'Tibia.dat'), os.path.join(out1, 'Tibia.spr'), os.path.join(tmp, 'o3'), trows, frames)
        check(rc == 1 and 'refused' in out, 'a pair that has the effects already is refused')
        dat1, spr1 = synthetic_pair(t.Case(), effects=1)
        rc, out = quiet(G.apply, dat1, spr1, os.path.join(tmp, 'o4'), trows, frames)
        check(rc == 1 and 'refused' in out, 'a pair older than the base is refused')
        check(not os.path.exists(os.path.join(tmp, 'o3')) and not os.path.exists(os.path.join(tmp, 'o4')), 'a refusal writes nothing')

        # ---- live on the built pair, from the table and the sums alone
        G.TABLE, G.SUMS = os.path.join(tmp, 't.csv'), os.path.join(tmp, 't.sums')
        open(G.TABLE, 'w', newline='\n').write(G.table_text(trows))
        open(G.SUMS, 'w').write(''.join('%s  %s\n' % (G.digest(G.strip_of(f)), x['name']) for x, f in zip(trows, frames)))
        rc, out = quiet(G.live, os.path.join(out1, 'Tibia.dat'), os.path.join(out1, 'Tibia.spr'))
        check(rc == 0, 'live: the pair holds the table: ' + out[-200:])
        rc, out = quiet(G.live, dat5, spr5)
        check(rc == 1 and 'the table ends at' in out, 'live: a pair without the effects fails')
        frames_b = [[f.copy() for f in fs] for fs in frames]
        frames_b[0][1][55, 30] = (1, 2, 3, 255)
        quiet(G.apply, dat, spr, os.path.join(tmp, 'o6'), trows, frames_b)
        rc, out = quiet(G.live, os.path.join(tmp, 'o6', 'Tibia.dat'), os.path.join(tmp, 'o6', 'Tibia.spr'))
        check(rc == 1 and 'pixels differ' in out, 'live: one changed pixel is found')
        # build: the strip must be the one of the sums
        rc, out = quiet(G.build, dat, spr, os.path.join(tmp, 'o7'), tmp)
        check(rc == 1 and 'has no' in out, 'build: an incomplete table is refused')
    finally:
        G.BASE_EFFECTS, G.RESERVED_LAST, G.FIRST, G.TABLE, G.SUMS = keep
        shutil.rmtree(tmp, ignore_errors=True)

    print('gen_status_vfx_test: %d checks, %d failed' % (checks, fails))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
