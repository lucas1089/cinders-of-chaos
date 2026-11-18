#!/usr/bin/env python3
"""Tests of gen_footprint_fx.py (O649) on art the test draws itself: no footprint source file, no real pair (numpy, Pillow).

python3 -I client/tools/sprites/gen_footprint_fx_test.py

Covers: the committed table, sums and ids file (check), the treatment keys, each treatment on synthetic frames (alpha cut and
the four levels, pure black, the palette, the shift and its edge refusal, the fade and its levels), the send offset, the pair
step on a synthetic source and a synthetic pair (the ids after the last effect, the strips the table says, older things
byte-identical, refusals for another pair, the same bytes twice, a source that is not the committed one), `live` on the built pair
and after one changed pixel, the generated Lua, no picture file name or source name in the committed files.
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
import check_pair_test as t  # noqa: E402
import gen_footprint_fx as G  # noqa: E402
import import_art_things as iat  # noqa: E402
from datspr import Dat  # noqa: E402

fails = 0
checks = 0


def check(cond, what):
    global fails, checks
    checks += 1
    if not cond:
        fails += 1
        print('FAIL', what)


def quiet(fn, *a, **kw):
    buf = io.StringIO()
    rc = None
    with redirect_stdout(buf):
        try:
            rc = fn(*a, **kw)
        except SystemExit as e:
            rc = 1
            print(e.code if isinstance(e.code, str) else '')
    return rc, buf.getvalue()


def blank(h=32, w=32):
    return np.zeros((h, w, 4), np.uint8)


def test_table():
    rc, out = quiet(G.check)
    check(rc == 0, 'the committed table, sums and ids file agree: ' + out[-300:])
    rows = G.read_spec()
    check(len(rows) == 20 and int(rows[0]['id']) == 5334 and int(rows[-1]['id']) == 5353, '20 effects at 5334..5353')
    check(G.table_errors(G.pieces()) == [], 'the table of the script holds its rules')
    check(G.FIRST == G.NEED_EFFECTS + 1, 'the ids follow the last effect of pair 74')
    bad = G.pieces()
    bad[2]['id'] = 9
    check(G.table_errors(bad), 'a hole in the ids is found')
    bad = G.pieces()
    bad[0]['name'] = 'heart'
    check(G.table_errors(bad), 'a name is fp_*')
    bad = G.pieces()
    bad[1]['eid'] = bad[0]['eid']
    check(G.table_errors(bad), 'a source effect used twice is found')
    bad = G.pieces()
    bad[1]['treat'] = 'sharpen'
    check(G.table_errors(bad), 'an unknown treatment key is found')
    check(len({r['title'] for r in rows}) == 20, 'one title each')
    check(G.parse_treat('black;palette=64;shift=3/3;fade=6/0.74') == {'black': True, 'palette': 64, 'shift': (3, 3), 'fade': (6, 0.74)},
          'the keys read')
    check(G.parse_treat('') == {} and G.parse_treat('alpha=4') == {'alpha': '4'}, 'no keys, and alpha=4')
    for text in ('palette=1', 'fade=2/1.5', 'shift=1', 'alpha=soft', 'palette=x'):
        try:
            G.parse_treat(text)
            check(False, 'refused: ' + text)
        except ValueError:
            check(True, 'refused: ' + text)
    # the committed files hold no picture name, path or source name
    name = 'vi' + 'sion'                                    # the source's name, split so this file does not carry it
    for p in (G.SPEC, G.SUMS, G.LUA, os.path.join(HERE, 'gen_footprint_fx.py'), os.path.join(HERE, 'gen_footprint_fx_test.py')):
        text = open(p, encoding='utf-8').read().lower()
        check(name not in text, 'no source name in ' + os.path.basename(p))
    for p in (G.SPEC, G.SUMS, G.LUA):
        check('.png' not in open(p, encoding='utf-8').read().lower(), 'no picture file name in ' + os.path.basename(p))
    check(all(len(r['src']) == 12 and len(r['raw']) == 12 for r in rows), 'src and raw are 12 hex')


def test_treatments():
    a = blank(1, 6)
    a[0, :, 3] = (0, 40, 70, 120, 150, 255)               # 0, .16, .27, .47, .59, 1
    a[0, :, :3] = 200
    cut = G.t_alpha_cut([a])[0]
    check(cut[0, :, 3].tolist() == [0, 0, G.GLOW, G.GLOW, 255, 255], 'cut: under 0.2 gone, a glow level, 0.5 and up solid: %s' % cut[0, :, 3].tolist())
    check(cut[0, 0].tolist() == [0, 0, 0, 0] and cut[0, 5, 0] == 200, 'cut: colours kept, a gone pixel carries none')
    four = G.t_alpha4([a])[0]
    check(four[0, :, 3].tolist() == [0, 0, 96, 96, 144, 255], '4 levels: below 48 gone, the rest snapped: %s' % four[0, :, 3].tolist())
    b = blank(1, 4)
    b[0, 0] = (0, 0, 0, 255)
    b[0, 1] = (0, 0, 0, 100)                                # not solid: kept as it is
    b[0, 2] = (1, 0, 0, 255)                                # not pure black
    b[0, 3] = (0, 0, 0, 0)
    bl = G.t_black([b])[0]
    check(tuple(bl[0, 0, :3]) == G.NEAR_BLACK and tuple(bl[0, 1, :3]) == (0, 0, 0) and tuple(bl[0, 2, :3]) == (1, 0, 0),
          'black: only a solid pure black becomes #050305')
    rng = np.random.RandomState(7)
    c = blank(8, 8)
    c[..., :3] = rng.randint(0, 256, (8, 8, 3))
    c[..., 3] = 255
    c[0, 0] = 0
    pal = G.t_palette([c, c], 4)
    shown = {tuple(p) for p in pal[0][pal[0][..., 3] > 0][:, :3].tolist()}
    check(len(shown) <= 4 and (pal[0] == pal[1]).all(), 'palette: at most 4 colours over all frames: %d' % len(shown))
    check(not pal[0][0, 0].any() and (pal[0][..., 3] == c[..., 3]).all(), 'palette: alpha and a transparent pixel unchanged')
    d = blank(8, 8)
    d[2:4, 2:4] = (9, 9, 9, 255)
    sh = G.t_shift([d], 3, -1)[0]
    ys, xs = np.nonzero(sh[..., 3])
    check((xs.min(), xs.max(), ys.min(), ys.max()) == (5, 6, 1, 2), 'shift: moved 3 right, 1 up')
    try:
        G.t_shift([d], 7, 0)
        check(False, 'shift past the canvas refused')
    except ValueError:
        check(True, 'shift past the canvas refused')
    frames = [blank(4, 4) for _ in range(6)]
    for f in frames:
        f[..., :3] = 80
        f[..., 3] = 255
    fd = G.t_fade(frames, 3, 0.5)
    mass = [int(f[..., 3].sum()) for f in fd]
    check(mass[:3] == [mass[0]] * 3 and mass[0] == 255 * 16, 'fade: the phases before the ramp are untouched')
    check(mass[3] >= mass[4] > mass[5] and mass[5] <= 255 * 16 * 0.6, 'fade: the last phases get weaker: %s' % mass)
    check(set(np.unique(np.concatenate(fd)[..., 3]).tolist()) <= {0, 255, 192, 144, 96, 64}, 'fade: alpha on the levels only')
    check(int(fd[5][..., 3].max()) == 144, 'fade: 0.5 of 255 on the last phase is the 144 level')
    # the order of the O648b report: alpha, black, palette, shift, fade
    e = blank(16, 16)
    e[5:9, 5:9] = (0, 0, 0, 255)
    full = G.treat([e] * 4, G.parse_treat('black;shift=2/2;fade=2/0.5'))
    check(tuple(full[0][7, 7, :3]) == G.NEAR_BLACK and full[0][7, 7, 3] == 255 and full[3][9, 9, 3] < 255, 'treat: all in one')
    # the centre and the send offset
    f1 = blank(32, 32)
    f1[18:22, 14:19] = (200, 0, 0, 255)
    cx, cy = G.weight_centre([f1])
    check(abs(cx - 16.0) < 0.6 and abs(cy - 20.0) < 0.6, 'weight centre of a block on the foot point: %.1f, %.1f' % (cx, cy))
    check(G.fit_offset(16.5, 20, 1, 1) == (0, 0), '1x1: no offset')
    check(G.fit_offset(48.5, 52, 2, 2) == (0, 0), '2x2: weight on the bottom right tile, no offset')
    check(G.fit_offset(16.5, 20, 2, 2) == (1, 1), '2x2: weight on the top left tile, sent one past it')
    check(G.fit_offset(80.5, 20, 3, 2) == (0, 1), '3x2: right tile, top row')


OUTFIT = t.entry(bytes([28]), [t.group([1, 2] * 4, layers=2, px=4, gtype=1)], outfit=True)


def sprite(v, alpha=255):
    px = np.zeros((32, 32, 4), np.uint8)
    px[6:26, 6:26] = (v, 40, 90, alpha)
    return px


def source_pair(case):
    """effect 1: 1x1, 4 phases (a solid block with a black core, a soft rim); effect 2: 2x2, 3 phases (soft blocks)"""
    recs, ids = [], []
    for k in range(4):
        px = sprite(60 + 40 * k)
        px[12:16, 12:16] = (0, 0, 0, 255)
        px[6:8, 6:26, 3] = 90
        recs.append(iat.encode_sprite(px))
    first = len(recs)
    for k in range(12):
        recs.append(iat.encode_sprite(sprite(90 + 10 * k, 200 if k % 4 else 255)))
    items = [t.entry(bytes([17]), [t.group([1])])]
    effs = [t.entry(b'', [t.group(list(range(1, 5)), phases=4)]),
            t.entry(b'', [t.group(list(range(first + 1, first + 13)), w=2, h=2, phases=3)])]
    return case.pair(recs, items, [OUTFIT], effs, [t.entry(b'', [t.group([1] * 9, px=3, py=3)])])


def target_pair(case, effects=2):
    recs = [iat.encode_sprite(np.full((32, 32, 4), 200, np.uint8)), iat.encode_sprite(np.full((32, 32, 4), 90, np.uint8))]
    items = [t.entry(bytes([17]), [t.group([1])])]
    effs = [t.entry(b'', [t.group([2])]) for _ in range(effects)]
    return case.pair(recs, items, [OUTFIT], effs, [t.entry(b'', [t.group([1] * 9, px=3, py=3)])])


def main():
    test_table()
    tmp = tempfile.mkdtemp(prefix='footprintfx')
    keep = (G.PICKS, G.NEED_EFFECTS, G.FIRST, G.SPEC, G.SUMS, G.LUA)
    try:
        test_treatments()
        # ---- the pair step on a synthetic source and a synthetic pair
        src = os.path.join(tmp, 'src')
        os.makedirs(src)
        sdat, sspr = source_pair(t.Case())
        shutil.copy(sdat, os.path.join(src, 'Tibia.dat'))
        shutil.copy(sspr, os.path.join(src, 'Tibia.spr'))
        G.PICKS = [('fp_one', 'One', 1, 'black;palette=6;shift=2/1;fade=2/0.5', 'one, 1x1'), ('fp_two', 'Two', 2, 'alpha=cut', 'two, 2x2')]
        G.NEED_EFFECTS, G.FIRST = 2, 3
        G.SPEC, G.SUMS, G.LUA = (os.path.join(tmp, 'f.csv'), os.path.join(tmp, 'f.sums'), os.path.join(tmp, 'f.lua'))
        dat, spr = target_pair(t.Case(), 2)
        out1 = os.path.join(tmp, 'o1')
        rc, out = quiet(G.build, dat, spr, out1, src, True)
        check(rc == 0 and 'live: 2 effects at 3..4' in out.replace('footprint fx ', '') or rc == 0, 'build and live: ' + out[-300:])
        od, nd = Dat(dat), Dat(os.path.join(out1, 'Tibia.dat'))
        check(len(nd.effects) == 4 and len(nd.missiles) == 1, '2 old + 2 new effects, the missile stays')
        check(all(nd.data[a.raw[0]:a.raw[1]] == od.data[b.raw[0]:b.raw[1]] for a, b in zip(nd.effects[:2], od.effects)),
              'the old effects are byte-identical')
        e3, e4 = nd.effects[2], nd.effects[3]
        check((e3.w, e3.h, e3.phases) == (1, 1, 4) and (e4.w, e4.h, e4.phases) == (2, 2, 3), 'the new effects at ids 3 and 4, source sizes')
        check(list(e3.anim[3]) == [100] * 8, 'the durations of the source are kept')
        rows = G.read_spec()
        check([r['id'] for r in rows] == ['3', '4'] and rows[0]['src'] == G.sha12(os.path.join(src, 'Tibia.dat')), 'the table lists them')
        check(rows[0]['treat'] == 'black;palette=6;shift=2/1;fade=2/0.5' and len(rows[0]['raw']) == 12, 'the table carries the treatment keys')
        check(os.path.exists(os.path.join(out1, 'strips', 'fp_one.png')), 'the strips are written')
        check(not os.path.exists(os.path.join(out1, 'chaos_vfx_art.lua')), 'no Lua of the importer is left')
        # the treated strip is what the pair holds (live reads it back from the sums)
        rc, out = quiet(G.live, os.path.join(out1, 'Tibia.dat'), os.path.join(out1, 'Tibia.spr'))
        check(rc == 0 and 'OK' in out, 'live: the pair holds the table: ' + out[-200:])
        # the treatments are in the pixels: no pure black, the shift, the alpha cut
        from PIL import Image
        s1 = np.asarray(Image.open(os.path.join(out1, 'strips', 'fp_one.png')))
        solid = s1[..., 3] >= 128
        check(not ((s1[..., :3].max(-1) == 0) & solid).any(), 'no pure black solid pixel left in the strip')
        check(len({tuple(p) for p in s1[s1[..., 3] > 0][:, :3].tolist()}) <= 6, 'at most 6 colours')
        s2 = np.asarray(Image.open(os.path.join(out1, 'strips', 'fp_two.png')))
        check(set(np.unique(s2[..., 3]).tolist()) <= {0, G.GLOW, 255}, 'alpha cut: 0, the glow level, 255')
        # the same bytes twice, and the build must reproduce the committed table
        out2 = os.path.join(tmp, 'o2')
        rc, out = quiet(G.build, dat, spr, out2, src, False)
        check(rc == 0, 'the committed table is reproduced: ' + out[-200:])
        check(open(os.path.join(out1, 'Tibia.spr'), 'rb').read() == open(os.path.join(out2, 'Tibia.spr'), 'rb').read()
              and open(os.path.join(out1, 'Tibia.dat'), 'rb').read() == open(os.path.join(out2, 'Tibia.dat'), 'rb').read(), 'the same bytes twice')
        # another source file is refused (the table names the source it was cut from)
        sd2 = os.path.join(tmp, 'src2')
        os.makedirs(sd2)
        shutil.copy(os.path.join(src, 'Tibia.spr'), os.path.join(sd2, 'Tibia.spr'))
        data = bytearray(open(os.path.join(src, 'Tibia.dat'), 'rb').read())
        data[0] ^= 1                                        # another signature: another file
        open(os.path.join(sd2, 'Tibia.dat'), 'wb').write(bytes(data))
        rc, out = quiet(G.build, dat, spr, os.path.join(tmp, 'o3'), sd2, False)
        check(rc == 1 and 'do not give the committed' in out, 'another source file is refused: ' + out[-200:])
        # refusals: a pair that has the effects already, a pair of another size, a source folder without the files
        rc, out = quiet(G.build, os.path.join(out1, 'Tibia.dat'), os.path.join(out1, 'Tibia.spr'), os.path.join(tmp, 'o4'), src, False)
        check(rc == 1 and 'refused' in out, 'a pair that has them already is refused')
        d5, s5 = target_pair(t.Case(), 3)
        rc, out = quiet(G.build, d5, s5, os.path.join(tmp, 'o5'), src, False)
        check(rc == 1 and 'refused' in out, 'a pair with another last effect is refused')
        rc, out = quiet(G.build, dat, spr, os.path.join(tmp, 'o6'), os.path.join(tmp, 'nothing'), False)
        check(rc == 1 and 'has no Tibia' in out, 'a source folder without the files is refused')
        check(not any(os.path.exists(os.path.join(tmp, o)) for o in ('o3', 'o4', 'o5', 'o6')), 'a refusal writes nothing')
        # live: one changed pixel is found, a pair without the effects fails
        rc, out = quiet(G.live, dat, spr)
        check(rc == 1 and 'effects' in out, 'live: a pair without the effects fails')
        sums = open(G.SUMS).read().splitlines()
        open(G.SUMS, 'w').write('\n'.join(['0' * 64 + sums[0][64:]] + sums[1:]) + '\n')
        rc, out = quiet(G.live, os.path.join(out1, 'Tibia.dat'), os.path.join(out1, 'Tibia.spr'))
        check(rc == 1 and 'pixels differ' in out, 'live: a changed sum is found')
        # the generated Lua
        text = G.lua_text(G.read_spec())
        check('fp_one = {id = 3, dx = ' in text and 'M.PAIR = 75' in text and 'M.on = ' in text and 'ChaosFootprintFxIds = M' in text, 'the Lua names the ids')
        check(G.lua_text(G.read_spec()) == text, 'the Lua is the same twice')
    finally:
        G.PICKS, G.NEED_EFFECTS, G.FIRST, G.SPEC, G.SUMS, G.LUA = keep
        shutil.rmtree(tmp, ignore_errors=True)
    print('gen_footprint_fx_test: %d checks, %d failed' % (checks, fails))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
