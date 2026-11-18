#!/usr/bin/env python3
"""Test of gen_malgrath_boss.py (O637): python3 -I client/tools/sprites/gen_malgrath_boss_test.py

The committed table, sums and ids file against the rules (ids, geometry, timing, a failing case for every rule), the geometry on
numbers (the odd square canvas, the window of an effect, the send offset), and `discover` / `load_anim` / `plan` / `build` / `live`
on a synthetic pack drawn here (sheets of frames side by side, a figure that bobs, a ground shadow at alpha 110, an effect part that
widens the box) and a small synthetic input pair: the shadow dropped by the cut, any other alpha level refused, no pixel lost in the
outfit or in the effect windows, the foot on the last row, the middle on the middle column, the same frames in the four directions,
the join (the body of an effect frame is the body of the outfit frame it replaces, pixel for pixel), the outfit and the effects
appended after the input's, every slot reading back as drawn, wrong input pairs and an existing output folder refused, a second build
giving the same bytes, `live` holding the pair to every number. No pack files and no real pair needed. Needs numpy and Pillow (the fx
venv of CI). Nothing drawn here is art of any pack."""
import copy
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
import gen_malgrath_boss as M  # noqa: E402
import gen_creature_outfits as G  # noqa: E402
import gen_wst_outfits as W  # noqa: E402
import check_pair_test as T  # noqa: E402
from datspr import Dat, Spr  # noqa: E402

# a small animation set: name, frames, ms, ox, oy; the figure stands at the same canvas pixels in every sheet, as in the pack
FX, FY, FW_, FH_ = 170, 133, 60, 88
TA = (('Idle', 4, 110, 165, 130), ('Move', 3, 105, 164, 131), ('Slam', 5, 90, 120, 100), ('Roar', 4, 85, 100, 90))
TE = (('mg_slam', 'Slam'), ('mg_roar', 'Roar'))
TV = (2, 3)


def figure(a, ox, oy, i):
    """the figure (same colours in every sheet) in frame a of a sheet whose canvas offset is (ox, oy); it bobs two pixels every second frame"""
    rng = np.random.default_rng(5)
    col = np.repeat(np.repeat(rng.integers(1, 256, (FH_ // 2, FW_ // 2, 3)).astype(np.uint8), 2, 0), 2, 1)
    x, y = FX - ox, FY - oy + 2 * (i % 2)
    a[y:y + FH_, x:x + FW_, :3] = col
    a[y:y + FH_, x:x + FW_, 3] = 255
    a[y + FH_:y + FH_ + 4, x:x + FW_, :3] = 5
    a[y + FH_:y + FH_ + 4, x:x + FW_, 3] = M.SHADOW                    # the baked ground shadow
    return a


def part(a, rect, i, ox, oy):
    """an effect part (a block that moves with the frame number) at canvas rect (x, y, w, h)"""
    x, y, w, h = rect
    a[y - oy + i:y - oy + i + h, x - ox:x - ox + w, :3] = (200, 30 + 20 * i, 90)
    a[y - oy + i:y - oy + i + h, x - ox:x - ox + w, 3] = 255


def sheet(root, variant, name, frames, fw, fh, ox, oy, rect=None, soft=False, tint=0):
    p = os.path.join(root, 'Color (%d)' % variant, 'Sheets')
    os.makedirs(p, exist_ok=True)
    fr = []
    for i in range(frames):
        a = np.zeros((fh, fw, 4), np.uint8)
        figure(a, ox, oy, i)
        if rect:
            part(a, rect, i, ox, oy)
        if soft:
            a[3, 3] = (9, 9, 9, 77)
        a[..., 1] = (a[..., 1].astype(np.int32) + 30 * tint) % 256     # a palette variant: other colours
        fr.append(a)
    Image.fromarray(np.concatenate(fr, axis=1), 'RGBA').save(os.path.join(p, name + '.png'))


def pack(root, soft_in=None):
    sheet(root, 1, 'Idle', 4, 70, 100, 165, 130, soft=soft_in == 'Idle')
    sheet(root, 1, 'Move', 3, 72, 100, 164, 131)
    sheet(root, 1, 'Slam', 5, 160, 140, 120, 100, rect=(235, 160, 30, 70), soft=soft_in == 'Slam')     # right of the figure and lower than it
    sheet(root, 1, 'Roar', 4, 130, 150, 100, 90, rect=(120, 100, 40, 30))                              # up and to the left
    for v in TV:
        sheet(root, v, 'Idle', 4, 70, 100, 165, 130, tint=v)
    return root


def check(cond, what):
    if not cond:
        raise AssertionError(what)


def main():
    # ---- the committed table, sums and ids file
    t = M.rows()
    check(M.problems() == [], M.problems())
    check(len(t) == 14 and [r['kind'] for r in t] == ['idle', 'walk'] + ['effect'] * 8 + ['variant'] * 4, 'the rows')
    check(M.PAIR == 74 and M.FIRST_OUTFIT == 3530 and M.FIRST_EFFECT == 5326, 'the ids come after pair 73 (3,529 outfits, 5,325 effects)')
    check([r['id'] for r in t[:2]] == ['3530', '3530'] and [int(r['id']) for r in t[2:10]] == list(range(5326, 5334)), 'ids')
    check([r['name'] for r in t[2:10]] == [n for n, _s in M.EFFECTS], 'effect names in order')
    check([r['tiles'] for r in t[:2]] == ['7x7', '7x7'], 'the outfit is 7x7: the 188 x 199 px figure, smallest odd square')
    check([(r['frames'], r['ms']) for r in t[:2]] == [('16', '110'), ('12', '105')], 'idle 16 frames of 110 ms, walk 12 of 105 ms')
    check([(r['sheet'], r['frames'], r['ms']) for r in t[2:10]] == [(s, str(M.anim_of(s)[1]), str(M.anim_of(s)[2])) for _n, s in M.EFFECTS], 'timing')
    check(M.outfit_geometry(M.union([M.box_of(t[0]), M.box_of(t[1])])) == (7, (-88, -74)), 'the shift of the pack: the foot on row 223')
    check([r['tiles'] for r in t[2:10]] == ['11x9', '13x10', '7x9', '9x9', '9x9', '7x9', '9x9', '9x8'], 'effect sizes')
    check([r['send'] for r in t[2:10]] == ['5:2', '6:2', '3:2', '4:2', '4:2', '3:2', '4:1', '4:1'], 'send offsets')
    check([r['name'] for r in t[10:]] == ['color_2', 'color_3', 'color_4', 'color_5'], 'the variants are noted, not imported')
    sums = M.read_sums()
    check(set(sums) == {'3530'} | {n for n, _s in M.EFFECTS} and all(len(v) == 64 for v in sums.values()) and len(set(sums.values())) == 9, 'sums')
    check(M.ids(True, quiet=True) == 0, 'the ids file is current')
    check(M.main(['check']) == 0, 'check')
    # no pack name in the tool, the table, the sums or the ids file (docs/CREDITS.md names it)
    words = ('abyssal', 'lich', 'giant boss', 'pack 7', 'top-down')
    for path in (M.TABLE, M.SUMS, M.LUA, os.path.join(HERE, 'gen_malgrath_boss.py'), os.path.abspath(__file__)):
        low = open(path, encoding='utf-8').read().lower()
        if path == os.path.abspath(__file__):
            low = ''.join(l for l in low.splitlines(True) if 'words' not in l)
        check(not [w for w in words if w in low], (path, [w for w in words if w in low]))

    # ---- every rule has a failing case
    def with_(i, **kw):
        out = copy.deepcopy(t)
        out[i].update(kw)
        return out

    def bad(table, text, sums_=None):
        p = M.problems(table, sums if sums_ is None else sums_)
        check(any(text in x for x in p), (text, p))

    bad(with_(0, id='3531'), 'it must be 3530')
    bad(with_(3, id='5400'), 'must be 5327')
    bad(with_(1, src=t[0]['src']), 'on two rows')
    bad(with_(0, src='xyz'), 'not 12 hex')
    bad(with_(2, frames='21'), 'not those of ANIMS')
    bad(with_(0, ms='83'), 'not those of ANIMS')
    bad(with_(4, ox='9'), 'not those of ANIMS')
    bad(with_(0, sheet='Nope'), 'not an animation')
    bad(with_(0, pixels='0'), 'pixels 0')
    bad(with_(0, pics='17'), 'pictures')
    bad(with_(0, tiles='5x5'), 'boxes give')
    bad(with_(1, win='1:0:0:0'), 'no window')
    bad(with_(2, tiles='10x9'), 'the box gives')
    bad(with_(3, win='0:0:0:0'), 'the box gives')
    bad(with_(4, send='0:0'), 'the box gives')
    bad(with_(10, frames='3'), 'variant row')
    bad(with_(10, sheet='Move'), 'variant row')
    bad(t[:5] + t[6:], 'not idle, walk')
    bad(t[::-1], 'not idle, walk')
    bad(t, 'name other things', {k: v for k, v in sums.items() if k != 'mg_death'})
    bad(t, 'not 64 hex', {**sums, '3530': 'x'})
    check(M.problems(t, sums, expect_tiles=5) and any('pack gives 5x5' in x for x in M.problems(t, sums, expect_tiles=5)), 'expect tiles')

    # ---- the geometry on numbers
    check(M.outfit_geometry((106, 99, 293, 297)) == (7, (-88, -74)), 'the pack figure: 188 x 199')
    n, (sx, sy) = M.outfit_geometry((170, 133, 229, 222))
    check((n, sx, sy) == (3, -152, 95 - 222), 'a 90 px figure: 3x3, foot on the last row, middle on the middle column')
    check(M.outfit_geometry((0, 0, 127, 127))[0] == 5, 'a 128 px figure is 4 tiles: an even count goes up to the odd 5')
    check(M.outfit_geometry((0, 0, 128, 10))[0] == 5, '129 px: 5 tiles')
    check(M.outfit_geometry((0, 0, 40, 40))[0] == 3, 'at least 3x3')
    try:
        M.outfit_geometry((0, 0, 299, 100))
    except ValueError as e:
        check('nothing is sampled down' in str(e), str(e))
    else:
        raise AssertionError('a 300 px figure fits no 9x9')
    check(M.outfit_geometry((10, 0, 20, 30))[0] == 3, 'small')
    check(M.window((106, 99, 293, 297), 7, (-88, -74)) == (0, 0, 0, 0), 'the figure itself needs no window')
    check(M.window((8, 66, 388, 359), 7, (-88, -74)) == (3, 3, 1, 2), 'lightning rain: 3 tiles left and right, 1 above, 2 below')
    check(M.window((105, 97, 295, 359), 7, (-88, -74)) == (0, 0, 0, 2), 'a beam to the bottom of the canvas')
    check(M.window((120, 99, 120, 99), 7, (-88, -74)) == (0, 0, 0, 0), 'inside')
    check(M.window((0, 0, 0, 0), 7, (-88, -74)) == (3, 0, 3, 0) and M.window((0, 0, 0, 0), 7, (-100, -64)) == (4, 0, 2, 0), 'exact tile edges')
    check(M.effect_geometry((8, 66, 388, 359), 7, (-88, -74)) == (13, 10, '3:3:1:2', (6, 2)), 'the send offset: 3 + right, bottom')
    check(M.boss_tile_col(7) == 3 and M.boss_tile_col(3) == 1 and G.disp_of(7) == (-96, 0), 'the boss tile is canvas column 3, 96 px = 3 tiles')
    for k in (3, 5, 7, 9):       # the displacement is a whole number of tiles for an odd canvas
        check(G.disp_of(k)[0] % 32 == 0, k)
    sx, sy = -88, -74
    # the figure's bottom-left tile of the outfit canvas reads (col, row) of the boss's tile: col 3, row 6 for 7x7
    check((32 * 7 - 1) / 2.0 - G.disp_of(7)[0] == 32 * 7 - 16.5 - 96 + 96 and G.tile_box(7) == (96, 192, 127, 223), 'tile box')
    check(M.flags_of({'tiles': '7x7'}) == (bytes([25, 0xA0, 0xFF, 0, 0]), {'displacement': (65440, 0)}), 'flags of 7x7: -96, 0')
    check(M.flags_of({'tiles': '3x3'})[1] == {'displacement': (65504, 0)}, 'flags of 3x3: -32')
    check(M.pair_ok(3529, 5325, 253) and not M.pair_ok(3530, 5325, 253) and not M.pair_ok(3529, 5333, 253) and not M.pair_ok(3529, 5325, 254), 'pair_ok')
    check(M.pair_ok(2, 1, 1, 3, 2, 1) and not M.pair_ok(2, 2, 1, 3, 2, 1), 'pair_ok with other ids')

    # ---- the pack files
    with tempfile.TemporaryDirectory() as tmp:
        deep = os.path.join(tmp, 'pack', 'deep')
        src = pack(deep)
        files = M.discover(os.path.join(tmp, 'pack'))
        check(sorted(files) == [1, 2, 3] and sorted(files[1]) == ['Idle', 'Move', 'Roar', 'Slam'] and sorted(files[2]) == ['Idle'], 'discover')
        os.makedirs(os.path.join(tmp, 'pack', 'x', 'Color (9)', 'Sheets No Effects'))
        check(sorted(M.discover(os.path.join(tmp, 'pack'))) == [1, 2, 3], 'only a Color (N) folder with a Sheets folder counts')
        src = os.path.join(tmp, 'pack')
        kw = dict(first_outfit=3, first_effect=2, anims=TA, effects=TE, variants=TV)
        p = M.plan(src, **kw)
        check(p['n'] == 3 and p['shift'] == (-152, -127), (p['n'], p['shift']))
        r = p['rows']
        check([x['kind'] for x in r] == ['idle', 'walk', 'effect', 'effect', 'variant', 'variant'], 'rows')
        check([x['id'] for x in r[:4]] == ['3', '3', '2', '3'], 'ids from the first new outfit and effect')
        check(M.problems(r, p['sums'], 3, 2, TA, TE, TV, expect_tiles=3) == [], M.problems(r, p['sums'], 3, 2, TA, TE, TV, expect_tiles=3))
        # the shadow (alpha 110) is dropped by the cut, nothing else: every placed pixel is 0 or 255
        check(p['loaded']['Idle']['dropped'] == 4 * 4 * FW_ and p['loaded']['Idle']['pixels'] == 4 * FW_ * FH_, (p['loaded']['Idle']['dropped'], p['loaded']['Idle']['pixels']))
        m = p['m']
        check(set(np.unique(np.concatenate([f[..., 3].ravel() for v in m['placed'].values() for f in v]))) <= {0, 255}, 'alpha 0 / 255 only')
        check((m['idle'], m['walk'], m['idle_ms'], m['walk_ms'], m['scale']) == (4, 3, 110, 105, '96/96'), 'outfit numbers')
        # no pixel lost, the foot on the boss's tile, the same frames in the four directions
        check(G.pixel_problems(m) == [] and G.foot_problems(m) == [], (G.pixel_problems(m), G.foot_problems(m)))
        for g in ('idle', 'walk'):
            for d in range(1, 4):
                check(all(np.array_equal(a, b) for a, b in zip(m['placed'][(g, 0)], m['placed'][(g, d)])), 'one picture facing every way')
        low = max(int(np.nonzero(f[..., 3])[0].max()) for v in m['placed'].values() for f in v)
        left = min(int(np.nonzero(f[..., 3])[1].min()) for v in m['placed'].values() for f in v)
        right = max(int(np.nonzero(f[..., 3])[1].max()) for v in m['placed'].values() for f in v)
        check(low == 95 and abs((left + right) / 2.0 - 47.5) <= 0.5, (low, left, right))
        # the effects: the window holds every pixel, and the body of an effect frame is the body of the outfit frame (the join)
        for (row, strip) in p['strips']:
            w, h = (int(v) for v in row['tiles'].split('x'))
            wa, wb, wc, wd = (int(v) for v in row['win'].split(':'))
            check(strip.shape == (32 * h, 32 * w * int(row['frames']), 4) and w == 3 + wa + wb and h == 3 + wc + wd, (row['name'], strip.shape))
            check(G.opaque(strip) == int(row['pixels']), 'pixels')
            for f in range(int(row['frames'])):
                fr = strip[:, f * 32 * w:(f + 1) * 32 * w]
                body = fr[32 * wc:32 * wc + 96, 32 * wa:32 * wa + 96]
                want = m['placed'][('idle', 0)][f % 2]                # the bob of frame f: the figure is the one of Idle frame f % 2
                mask = want[..., 3] > 0
                check(mask.any() and np.array_equal(body[mask], want[mask]), (row['name'], f, 'the body joins the outfit'))
        slam = p['strips'][0][0]
        check((slam['tiles'], slam['win'], slam['send']) == ('4x4', '0:1:0:1', '2:1'), (slam['tiles'], slam['win'], slam['send']))
        roar = p['strips'][1][0]
        check(roar['win'] == '1:0:1:0' and roar['tiles'] == '4x4' and roar['send'] == '1:0', (roar['tiles'], roar['win'], roar['send']))
        # a second plan gives the same table and sums
        p2 = M.plan(src, **kw)
        check(M.table_text(p2['rows']) == M.table_text(r) and p2['sums'] == p['sums'], 'deterministic')
        # another alpha level is refused
        soft = pack(os.path.join(tmp, 'soft'), soft_in='Slam')
        try:
            M.plan(soft, **kw)
        except SystemExit as e:
            check('alpha' in str(e), str(e))
        else:
            raise AssertionError('a sheet with alpha 77 was taken')
        # a missing sheet, a missing Color (1)
        os.remove(os.path.join(deep, 'Color (1)', 'Sheets', 'Roar.png'))
        try:
            M.plan(src, **kw)
        except SystemExit as e:
            check('no sheet Roar' in str(e), str(e))
        else:
            raise AssertionError('a pack without a sheet was taken')
        sheet(deep, 1, 'Roar', 4, 130, 150, 100, 90, rect=(120, 100, 40, 30))
        try:
            M.plan(os.path.join(tmp, 'empty'), **kw)
        except SystemExit as e:
            check('Color (1)' in str(e), str(e))
        else:
            raise AssertionError('an empty folder was taken')
        # a sheet that is no whole number of frames, a frame that leaves the canvas
        try:
            M.read_frames(os.path.join(deep, 'Color (1)', 'Sheets', 'Idle.png'), 3)
        except ValueError as e:
            check('whole frames' in str(e), str(e))
        else:
            raise AssertionError('280 px in 3 frames')
        try:
            M.to_canvas(np.zeros((40, 40, 4), np.uint8), 390, 0)
        except ValueError as e:
            check('leaves' in str(e), str(e))
        else:
            raise AssertionError('a frame past the canvas')
        # a figure too tall for 9x9 tiles is refused, nothing sampled
        try:
            M.outfit_geometry((0, 0, 100, 299))
        except ValueError:
            pass
        else:
            raise AssertionError('299 px tall')

        # ---- the pair: build, read back, live
        recs, items, outfits, effects, missiles = T.good_parts()
        odat = os.path.join(tmp, 'in.dat')
        ospr = os.path.join(tmp, 'in.spr')
        open(odat, 'wb').write(T.dat_bytes(items, outfits, effects, missiles))
        open(ospr, 'wb').write(T.spr_bytes(recs))
        out = os.path.join(tmp, 'out')
        lines = []
        table, sums_ = M.build(odat, ospr, out, src, need_missiles=1, log=lines.append, **kw)
        check(any('append-only guard passed' in x for x in lines) and any('outfit 3 and 2 effects 2..3 appended' in x for x in lines), lines)
        check(table == r and sums_ == p['sums'], 'build returns the plan')
        paths = (os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr'))
        check(sorted(os.listdir(tmp)) == sorted(['pack', 'soft', 'in.dat', 'in.spr', 'out']), 'no strip or work folder stays: ' + str(os.listdir(tmp)))
        d, sp = Dat(paths[0]), Spr(paths[1])
        check((len(d.outfits), len(d.effects), len(d.missiles)) == (3, 3, 1), (len(d.outfits), len(d.effects)))
        check(dict(d.outfit(3).flags) == {'displacement': (65504, 0)} and (d.effects[1].w, d.effects[1].h, d.effects[1].phases) == (4, 4, 5), 'dat')
        quiet = dict(log=lambda *_: None, first_outfit=3, first_effect=2)
        check(M.live(*paths, table=table, sums=sums_, **quiet) == [], M.live(*paths, table=table, sums=sums_, **quiet))
        check(M.live(odat, ospr, table=table, sums=sums_, **quiet), 'a pair without the boss')
        check(M.live(*paths, table=table, sums={**sums_, '3': '0' * 64}, **quiet), 'another outfit digest')
        check(M.live(*paths, table=table, sums={**sums_, 'mg_slam': '0' * 64}, **quiet), 'another effect digest')
        for badt, text in ((with_t(table, 0, ms='111'), 'do not last 111 ms'), (with_t(table, 0, pixels=str(int(table[0]['pixels']) + 1)), 'opaque pixels'),
                           (with_t(table, 1, pics='1'), 'different pictures'), (with_t(table, 0, frames='5'), 'phases'),
                           (with_t(table, 2, tiles='6x6'), 'size or phases'), (with_t(table, 2, ms='91'), 'do not last 91 ms'),
                           (with_t(table, 3, pixels='1'), 'opaque pixels')):
            pr = M.live(*paths, table=badt, sums=sums_, **quiet)
            check(any(text in x for x in pr), (text, pr))
        # the boss faces the front: another picture in one direction is found
        frames, gs = M.outfit_frames(d, sp, 3, 3)
        check(len(frames) == 8 and all(np.array_equal(frames[('idle', 0)][i], frames[('idle', 3)][i]) for i in range(4)), 'four directions, one picture')
        # refusals
        for args, kw2, text in (((odat, ospr, out, src), {}, 'exists'),
                                ((odat, ospr, os.path.join(tmp, 'o2'), src), dict(first_outfit=9), 'refused: the input pair has'),
                                ((odat, ospr, os.path.join(tmp, 'o3'), src), dict(first_effect=9), 'refused: the input pair has'),
                                ((odat, ospr, os.path.join(tmp, 'o4'), src), dict(need_missiles=7), 'refused: the input pair has')):
            k = dict(kw, need_missiles=1)
            k.update(kw2)
            try:
                M.build(*args, log=lambda *_: None, **k)
            except SystemExit as e:
                check(text in str(e), (text, str(e)))
            else:
                raise AssertionError('build did not refuse: ' + text)
        check(not os.path.exists(os.path.join(tmp, 'o2')) and not os.path.exists(os.path.join(tmp, 'o2.work')), 'a refusal leaves nothing')
        # a second build of the same pack gives the same bytes
        out2 = os.path.join(tmp, 'again')
        M.build(odat, ospr, out2, src, need_missiles=1, log=lambda *_: None, **kw)
        check(open(paths[0], 'rb').read() == open(os.path.join(out2, 'Tibia.dat'), 'rb').read(), 'same dat')
        check(open(paths[1], 'rb').read() == open(os.path.join(out2, 'Tibia.spr'), 'rb').read(), 'same spr')
        # the preview reads a pair: not run here (ffmpeg), but the ids file text is from the table
    text = M.lua_text(t)
    check(text.count('\n\t\tmg_') == 8 and 'mg_lightning_rain = {id = 5327, dx = 6, dy = 2, w = 13, h = 10, ms = 2210}' in text and 'pair = 74, outfit = 3530' in text, 'lua text')
    check(M.main(['build', 'a', 'b', 'c']) == 1 and M.main([]) == 1, 'the command line needs --src and a command')
    print('gen_malgrath_boss_test: ok')


def with_t(table, i, **kw):
    out = copy.deepcopy(table)
    out[i].update(kw)
    return out


if __name__ == '__main__':
    main()
