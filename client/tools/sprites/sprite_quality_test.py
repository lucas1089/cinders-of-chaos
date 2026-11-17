#!/usr/bin/env python3
"""python3 -I client/tools/sprites/sprite_quality_test.py : sprite_quality.py on synthetic art (O625).

A flat blob fails the bar; a shaded, outlined, animated blob passes; each metric moves the right way when its cause is
added or removed (outline, hue shift, colours, noise, banding, pillow shading, light direction, motion, popping, duplicate
frames, mirrored directions, soft alpha); the sheet, strip, pair and npz readers give the same frames; the CLI exit codes;
the committed bar file is well formed and holds its reference. Needs numpy and Pillow (CI: /tmp/fxenv)."""
import contextlib
import io
import json
import math
import os
import shutil
import struct
import sys
import tempfile

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_pair_test as T  # noqa: E402
import sprite_quality as Q  # noqa: E402

failed = 0


def ok(cond, what):
    global failed
    if not cond:
        failed += 1
        print('FAIL:', what)


# ---------------------------------------------------------------------------------------------------------------- synthetic art
def smooth_noise(n, scale, seed):
    rng = np.random.RandomState(seed)
    g = rng.rand(n // scale + 2, n // scale + 2)
    img = Image.fromarray((g * 255).astype(np.uint8)).resize((n + 2 * scale, n + 2 * scale), Image.BILINEAR)
    return np.asarray(img, np.float64)[:n, :n] / 255.0


RAMP = [(0.0, (30, 14, 70)), (0.35, (120, 20, 70)), (0.65, (200, 45, 40)), (1.0, (255, 215, 110))]


def ramp(t):
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,))
    for (t0, c0), (t1, c1) in zip(RAMP[:-1], RAMP[1:]):
        m = (t >= t0) & (t <= t1)
        f = ((t - t0) / (t1 - t0))[..., None]
        out = np.where(m[..., None], np.array(c0) * (1 - f) + np.array(c1) * f, out)
    return out


def blob(n=128, phase=0, nph=8, shade=True, outline='hue', texture=0.34, bands=False, soft=False, pillow=False,
         light=(-0.8, -0.7, 0.35), speck=0, shift=(0, 0), glow=0.12, rx=46, ry=42, flat_colour=None, seed=3, sway=2.0):
    yy, xx = np.mgrid[:n, :n].astype(np.float64)
    ph = 2 * math.pi * phase / nph
    cx, cy = n / 2 + shift[0] + sway * math.sin(ph), n / 2 + 4 + shift[1]
    sy = ry * (1 + 0.02 * math.sin(ph))
    u, v = (xx - cx) / rx, (yy - cy) / sy
    r2 = u * u + v * v
    inside = r2 <= 1.0
    z = np.sqrt(np.clip(1 - r2, 0, 1))
    l = np.array(light, float)
    l /= np.linalg.norm(l)
    lam = np.clip(u * l[0] + v * l[1] + z * l[2], 0, 1)
    if pillow:
        lam = z                                          # luma follows the distance from the rim: a dome lit from the viewer
    t = 0.28 + 0.62 * lam if shade else np.full(lam.shape, 0.55)
    t = t + texture * (np.roll(smooth_noise(n, 2, seed), int(round(cx - n / 2)), axis=1) - 0.5) * 2
    t = t + glow * np.sin(ph + 0.16 * xx + 0.1 * yy) * (1 if shade else 0)
    if bands:
        t = np.floor(t * 4) / 4.0 + 0.1
    rgb = ramp(t)
    if flat_colour is not None:
        rgb = np.zeros((n, n, 3)) + np.array(flat_colour, float)
    rgba = np.zeros((n, n, 4), np.uint8)
    alpha = np.where(inside, 255, 0).astype(np.uint8)
    if soft:
        ring = (~inside) & (r2 <= 1.0 + 0.03)
        alpha = np.where(ring, 90, alpha).astype(np.uint8)
    rgba[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    rgba[..., 3] = alpha
    rgba[alpha == 0, :3] = 0
    if outline:
        solid = alpha >= 128
        er = solid.copy()
        for _ in range(2):
            nb = Q.nb4(er)
            er = er & nb[0] & nb[1] & nb[2] & nb[3]
        rim = solid & ~er
        if outline == 'black':
            rgba[rim, :3] = (6, 6, 8)
        else:
            rgba[rim, :3] = np.clip(rgb[rim] * 0.22, 0, 255).astype(np.uint8)
    if speck:
        rng = np.random.RandomState(seed + 9)
        ys, xs = np.nonzero((alpha >= 128) & (r2 < 0.7))
        for i in rng.choice(len(ys), speck, replace=False):
            rgba[ys[i], xs[i], :3] = (255, 255, 255) if speck < 100 else (rng.randint(256), rng.randint(256), rng.randint(256))
    return rgba


def seq(n=8, **kw):
    return [blob(phase=i, nph=n, **kw) for i in range(n)]


def art_of(frames, kind='boss', dirs=('north', 'east', 'south', 'west'), ms=None):
    a = Q.Art('synthetic', kind)
    for d in dirs:
        a.add('anim', d, frames, [100] * len(frames))
    return a


def run(frames, kind='boss', thr=Q.SOLID):
    return Q.analyse(art_of(frames, kind), thr)['summary']


def run2(**kw):
    return run(seq(2, **kw))


def spots(frames):
    """the good boss with eight small bright specks added to every frame."""
    out = []
    for f in frames:
        f = f.copy()
        for k in range(24):
            y, x = 38 + (k // 6) * 9, 38 + (k % 6) * 10
            f[y, x, :3] = (255, 240, 200)
        out.append(f)
    return out


GOOD = spots(seq(8))
BAR = Q.load_bar()


def rows_of(frames, kind='boss'):
    res = Q.analyse(art_of(frames, kind), BAR['kinds'][kind].get('solid', Q.SOLID))
    return Q.check(res, kind, BAR)


def failing(rows):
    return {r['metric'] for r in rows if not r['ok'] and r['level'] == 'fail'}


# ---------------------------------------------------------------------------------------------------------------- tests
def test_good_and_flat():
    rows = rows_of(GOOD)
    ok(Q.passed(rows), 'the shaded, outlined, animated blob passes as a boss: failing %s' % sorted(failing(rows)))
    flat = [blob(shade=False, outline=None, texture=0, glow=0, flat_colour=(160, 40, 40))]
    fr = rows_of(flat)
    bad = failing(fr)
    ok(not Q.passed(fr), 'a flat one-colour blob fails')
    ok({'colours', 'ramp_steps', 'contrast', 'detail_p10', 'outline_coverage'} <= bad, 'a flat blob fails for its own reasons: %s' % sorted(bad))
    still = failing(rows_of([blob(shade=False, outline=None, texture=0, glow=0, flat_colour=(160, 40, 40))] * 8))
    ok({'changed_share', 'dup_frames'} <= still, 'eight equal frames fail the animation rows: %s' % sorted(still))


def test_metrics_move():
    g = run(spots(seq(2)))
    # outline
    flatb = dict(shade=False, texture=0, glow=0, flat_colour=(200, 120, 60))
    no = run2(outline=None, **flatb)
    hu = run2(outline='hue', **flatb)
    bl = run2(outline='black', **flatb)
    g_cov, g_hue, g_sel = hu['outline_coverage'], hu['outline_hue_share'], hu['outline_selout_share']

    ok(g_cov > no['outline_coverage'] + 0.4, 'outline coverage rises with an outline: %.2f -> %.2f' % (no['outline_coverage'], g_cov))
    ok(g_hue > bl['outline_hue_share'] + 0.3, 'a dark-hue outline reads as hue, a black one as black: %.2f vs %.2f' % (g_hue, bl['outline_hue_share']))
    ok(bl['outline_black_share'] > 0.9, 'black outline: black share %.2f' % bl['outline_black_share'])
    ok(g_sel > bl['outline_selout_share'] + 0.2, 'a hue outline follows the interior: %.2f vs %.2f' % (g_sel, bl['outline_selout_share']))
    # shading, colours, ramps
    fl = run2(shade=False, texture=0, glow=0)
    ok(g['colours'] > 10 * max(1, fl['colours']) and g['ramp_steps'] > fl['ramp_steps'] + 5, 'shading adds colours and ramp steps: %.0f / %.1f vs %.0f / %.1f' % (g['colours'], g['ramp_steps'], fl['colours'], fl['ramp_steps']))
    ok(g['contrast'] > fl['contrast'] + 40, 'shading adds contrast')
    ok(g['ramp_hue_shift'] > 8, 'the ramp turns hue from shadow to light: %.1f' % g['ramp_hue_shift'])
    gray = []
    for f in seq(2):
        h = f.copy()
        l = Q.luma(h[..., :3]).astype(np.uint8)
        h[..., 0] = h[..., 1] = h[..., 2] = l
        gray.append(h)
    gm = run(gray)
    ok(gm['ramp_steps_max'] == 0 and gm['grey_share'] > 0.99, 'a grey sprite has no hue family: grey share %.2f' % gm['grey_share'])
    # light direction
    ok(g['light_name'] in ('top-left', 'top', 'left'), 'light from the top left is read as %s' % g['light_name'])
    rl = run2(light=(0.8, 0.7, 0.35))
    ok(rl['light_name'] in ('bottom-right', 'bottom', 'right'), 'light from the bottom right is read as %s' % rl['light_name'])
    ok(g['light_x'] * rl['light_x'] < 0 and g['light_y'] * rl['light_y'] < 0, 'the light vector turns with the light')
    ok(g['light_frames_agree'] > 0.9, 'one light over the loop: %.2f' % g['light_frames_agree'])
    # pillow
    pl = run2(pillow=True, texture=0.02, glow=0)
    ok(pl['pillow'] == 1 and abs(pl['pillow_r']) > 0.45, 'a dome lit from the viewer is pillow shaded: r %.2f' % pl['pillow_r'])
    ok(g['pillow'] == 0, 'the side-lit blob is not pillow shaded: r %.2f' % g['pillow_r'])
    # noise and smoothness
    nz = run2(speck=600)
    ok(nz['local_std'] > g['local_std'] + 5, 'pixel noise raises the local deviation: %.1f -> %.1f' % (g['local_std'], nz['local_std']))
    ok(run2(texture=0.5)['local_std'] > g['local_std'], 'heavy texture raises the local deviation')
    ok(run2(texture=0.0, glow=0)['detail_mean'] < g['detail_mean'], 'no texture, less detail')
    # banding
    bn = run2(bands=True, texture=0.0, glow=0)
    sm = run2(texture=0.0, glow=0)
    ok(bn['flat_run_share'] > sm['flat_run_share'] + 0.2, 'posterised art has long single-colour runs: %.2f vs %.2f' % (bn['flat_run_share'], sm['flat_run_share']))
    ok(bn['colours'] < sm['colours'], 'posterising lowers the colour count')
    # highlights
    ok(g['spec_clusters'] >= 4, 'the specks are counted as highlights: %.1f' % g['spec_clusters'])
    ok(run2()['spec_clusters'] < g['spec_clusters'], 'no specks, fewer highlights')
    # alpha
    sf = run2(soft=True)
    ok(sf['semi_share'] > g['semi_share'] + 0.01 and sf['alpha_levels'] > g['alpha_levels'], 'soft edge pixels show as semi alpha: %.3f' % sf['semi_share'])
    ok(sf['semi_edge_share'] > 0.8, 'semi alpha at the edge, not inside: %.2f' % sf['semi_edge_share'])
    ok(g['alpha_255_share'] == 1.0 and g['holes'] == 0, 'a clean blob is all 255 alpha, no holes')
    # canvas
    ok(0.7 < g['fill_share'] < 0.85 and 4.0 < g['complexity'] < 5.0, 'an ellipse fills pi/4 of its box and has a round rim: %.2f / %.2f' % (g['fill_share'], g['complexity']))
    holey = []
    for f in seq(2):
        f = f.copy()
        f[60:62, 60:62, 3] = 0
        f[80, 70, 3] = 0
        holey.append(f)
    hs = run(holey)
    ok(hs['holes'] == 2 and hs['hole_px'] == 5, 'holes are counted: %s %s' % (hs['holes'], hs['hole_px']))
    # checker dither
    chk = []
    for f in seq(2):
        f = f.copy()
        yy, xx = np.mgrid[:128, :128]
        m = (((yy + xx) % 2) == 0) & (yy > 50) & (yy < 90) & (xx > 50) & (xx < 90)
        f[m, :3] = (200, 60, 50)
        f[(~m) & (yy > 50) & (yy < 90) & (xx > 50) & (xx < 90), :3] = (120, 30, 40)
        chk.append(f)
    ok(run(chk)['checker_share'] > g['checker_share'] + 0.02, 'a checkerboard patch is seen as dither: %.3f' % run(chk)['checker_share'])


def test_animation():
    g = run(GOOD)
    ok(g['frames_max'] == 8 and g['dup_frames'] == 0 and g['loop_exact'] == 0, 'eight different frames, loop seam not held')
    ok(0.4 <= g['changed_share'] <= 0.95, 'the glow band changes much of the body: %.2f' % g['changed_share'])
    ok(g['shade_only_share'] > 0.8 and g['silhouette_change_share'] < 0.12, 'shading moves, silhouette stays: %.2f / %.3f' % (g['shade_only_share'], g['silhouette_change_share']))
    ok(g['area_range'] < 0.08, 'breathing keeps the volume: %.3f' % g['area_range'])
    ok(0.4 <= g['loop_ratio'] <= 2.0, 'the loop closes like any step: %.2f' % g['loop_ratio'])
    still = run([GOOD[0]] * 8)
    ok(still['changed_share'] == 0 and still['dup_frames'] == 7 and still['loop_exact'] == 1, 'a still loop: no change, 7 duplicates, seam held')
    held = run(GOOD + [GOOD[0]])
    ok(held['loop_exact'] == 1 and held['loop_ratio'] == 0, 'a last frame equal to the first is caught as a held seam')
    # a pop at the seam: the last frame far from the first
    pop = [blob(phase=i, nph=16) for i in range(8)]     # half a cycle: the seam jumps back
    ok(run(pop)['loop_ratio'] > g['loop_ratio'] + 0.5, 'a jump at the seam raises the loop ratio: %.2f' % run(pop)['loop_ratio'])
    # popping silhouette: every frame at another place
    jit = run([blob(phase=i, shift=((i * 5) % 11 - 5, (i * 7) % 9 - 4)) for i in range(8)])
    ok(jit['silhouette_change_share'] > 0.12 and jit['motion_px'] > 3, 'a jittering silhouette: %.2f, motion %.1f px' % (jit['silhouette_change_share'], jit['motion_px']))
    # a walk of one pixel a frame
    mv = run([blob(phase=0, glow=0, shift=(i, 0), seed=3) for i in range(8)])
    ok(0.8 <= mv['motion_px'] <= 1.6, 'a body that moves 1 px a frame measures about 1 px: %.2f' % mv['motion_px'])
    ok(mv['centroid_x_range'] > 6, 'the centroid travels: %.1f' % mv['centroid_x_range'])
    # squash and stretch
    sq = run([blob(phase=i, glow=0, ry=42 + 3 * math.sin(i)) for i in range(8)])
    ok(sq['bbox_h_range'] >= 4 and sq['ratio_range'] > g['ratio_range'], 'a stretched body shows in the box ratio: %.3f' % sq['ratio_range'])
    # durations
    ok(g['ms_mean'] == 100 and g['loop_ms'] == 800, 'durations carried: %s %s' % (g['ms_mean'], g['loop_ms']))
    # directions: copies, shifted copies, mirrors, drawn
    a = Q.Art('d', 'boss')
    a.add('anim', 'east', GOOD)
    a.add('anim', 'west', [f[:, ::-1] for f in GOOD])
    a.add('anim', 'north', [Q.shift(f, 2, 3) for f in GOOD])
    a.add('anim', 'south', GOOD)
    r = Q.analyse(a)['summary']
    ok(r['ew_mirror_share'] > 0.99, 'west drawn as the east mirror: %.2f' % r['ew_mirror_share'])
    ok(0 < r['dirs_identical_share'] < 0.5, 'some direction pairs identical, some not: %.2f' % r['dirs_identical_share'])
    ok(Q.same_share(GOOD[0], Q.shift(GOOD[0], 2, 3), True) > 0.95 and Q.same_share(GOOD[0], Q.shift(GOOD[0], 2, 3), False) < 0.6,
       'a copy a few px off counts as the same only when shifts are allowed')
    d4 = Q.Art('d', 'boss')
    for i, dn in enumerate(Q.DIR_NAMES):
        d4.add('anim', dn, [blob(phase=k, texture=0.1 + 0.05 * i, seed=20 + i) for k in range(4)])
    r4 = Q.analyse(d4)['summary']
    ok(r4['dirs_identical_share'] == 0 and r4['dirs_same_shifted'] < 0.7 and r4['ew_mirror_share'] < 0.7, 'four drawn directions: not identical (%.2f), not shifted copies (%.2f), no mirror (%.2f)' % (r4['dirs_identical_share'], r4['dirs_same_shifted'], r4['ew_mirror_share']))


def test_kinds_and_bar():
    ok(set(BAR['kinds']) == {'boss', 'creature', 'outfit', 'item', 'effect'}, 'the bar has the five kinds')
    for k, spec in BAR['kinds'].items():
        for name, e in spec['metrics'].items():
            ok(e.get('why') and ('min' in e or 'max' in e), '%s %s has a threshold and a why' % (k, name))
            ok(e.get('level', 'fail') in ('fail', 'warn'), '%s %s level' % (k, name))
            if 'scale' in e:
                ok(e['scale'] in ('sqrt', 'linear') and e['ref_px'] > 0, '%s %s scale' % (k, name))
    ref = {}
    for name, e in BAR['kinds']['boss']['metrics'].items():
        if 'ref' in e:
            ref[name] = e['ref']
            if 'min' in e:
                ok(e['min'] <= e['ref'] * 1.001 or name in ('detail_p10',), 'boss %s: min %s does not exceed the reference %s' % (name, e['min'], e['ref']))
            if 'max' in e and name not in ('hole_px', 'holes', 'loop_exact', 'dup_frames', 'pillow', 'flat_run_share', 'flat_tile_share'):
                ok(e['max'] >= e['ref'] * 0.999, 'boss %s: max %s is not below the reference %s' % (name, e['max'], e['ref']))
    # effective(): scaling and floors
    e = {'min': 600, 'scale': 'linear', 'ref_px': 8000, 'floor': 40, 'scale_cap': 1.0}
    ok(Q.effective(e, {'solid_px': 800})[0] == 60.0, 'a tenth of the size asks a tenth of the colours')
    ok(Q.effective(e, {'solid_px': 100})[0] == 40, 'the floor holds')
    ok(Q.effective(e, {'solid_px': 80000})[0] == 600, 'a bigger sprite is not asked for more')
    # kinds: item and effect on a small strip
    small = []
    for i in range(6):
        f = blob(n=32, phase=i, nph=6, rx=12, ry=11, texture=0.1, glow=0.25)
        small.append(f)
    strip = np.concatenate(small, 1)
    rows = Q.check(Q.analyse(Q.load_image(_png(strip), 'item'), 128), 'item', BAR)
    ok(Q.passed(rows), 'a small shaded animated item passes: %s' % sorted(failing(rows)))
    bad = Q.check(Q.analyse(Q.load_image(_png(np.concatenate([small[0]] * 6, 1)), 'item'), 128), 'item', BAR)
    ok('dup_frames' in failing(bad) and 'changed_share' in failing(bad), 'a still strip fails the animation rows')
    glow = []
    for i in range(6):
        f = blob(n=32, phase=i, nph=6, rx=12, ry=11, soft=True, outline=None, texture=0.05, glow=0.3)
        glow.append(f)
    rows = Q.check(Q.analyse(Q.load_image(_png(np.concatenate(glow, 1)), 'effect'), 40), 'effect', BAR)
    ok(Q.passed(rows), 'a soft animated effect passes: %s' % sorted(failing(rows)))
    # warn level only fails with --strict
    rows = rows_of(GOOD)
    ok(any(r['level'] == 'warn' and not r['ok'] for r in rows) and Q.passed(rows) and not Q.passed(rows, True), 'warn rows fail only in strict mode')


_tmp = []


def _png(arr):
    d = tempfile.mkdtemp(prefix='sprite_quality_test_')
    _tmp.append(d)
    p = os.path.join(d, 'x.png')
    Image.fromarray(arr).save(p)
    return p


def test_readers():
    # outfit sheet: 4 direction columns, 4 idle rows + 8 walk rows of 128 px cells
    idle = [blob(phase=i, nph=4) for i in range(4)]
    walk = [blob(phase=i, nph=8, texture=0.2) for i in range(8)]
    rows = [np.concatenate([f] * 4, 1) for f in idle + walk]
    sheet = np.concatenate(rows, 0)
    a = Q.load_image(_png(sheet), 'boss')
    ok(list(a.frames) == ['idle', 'walk'] and len(a.frames['idle']['east']) == 4 and len(a.frames['walk']['west']) == 8, 'the sheet is cut into idle 4 and walk 8')
    ok((a.frames['walk']['north'][3] == walk[3]).all(), 'cells hold the right frames')
    a1 = Q.load_image(_png(np.concatenate([np.concatenate([f] * 8, 1) for f in walk], 0)), 'outfit', cell=128)
    ok(len(a1.frames['walk']['south']) == 8, 'more template columns are ignored, four directions are read')
    try:
        Q.load_image(_png(np.zeros((100, 100, 4), np.uint8)), 'boss')
        ok(False, 'a picture that is no sheet is refused')
    except ValueError:
        pass
    st = Q.load_image(_png(np.concatenate(walk[:5], 1)), 'effect')
    ok(len(st.frames['strip']['-']) == 5, 'a strip of square frames')
    # a pair: a 2x2 outfit of 4 directions and 2 phases made of tile records
    c = T.Case()
    try:
        fr = [[blob(n=64, phase=p, nph=2, rx=22, ry=20, texture=0.1 + 0.03 * d, seed=5 + d) for p in range(2)] for d in range(4)]
        recs, sprites = [], []
        for p in range(2):
            for d in range(4):
                for hh in range(2):
                    for ww in range(2):
                        y0, x0 = (1 - hh) * 32, (1 - ww) * 32
                        tile = fr[d][p][y0:y0 + 32, x0:x0 + 32]
                        pix = {i: tuple(int(v) for v in tile[i // 32, i % 32]) for i in range(1024) if tile[i // 32, i % 32, 3]}
                        recs.append(T.record(pix))
                        sprites.append(len(recs))
        outfits = [T.entry(b'', [T.group(sprites, w=2, h=2, px=4, phases=2, gtype=0)], outfit=True)]
        dat, spr = c.pair(recs, [], outfits, [], [])
        a = Q.load_pair(dat, spr, 1)
        got = a.frames['anim']
        same = all((got[Q.DIR_NAMES[d]][p] == fr[d][p]).all() for d in range(4) for p in range(2))
        ok(same, 'the pair reader composes the tiles into the drawn frames, per direction and phase')
        ok(a.ms['anim'] == [100, 100], 'the dat durations are read: %s' % a.ms)
        r = Q.analyse(a)
        ok(r['summary']['frames_max'] == 2 and r['summary']['ms_mean'] == 100, 'analyse reads the pair art')
        # CLI on the pair, and an npz of the same
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = Q.main(['measure', '--kind', 'outfit', '--dat', dat, '--spr', spr, '--outfit', '1'])
        ok(rc == 0 and 'canvas' in out.getvalue() and 'outfit1' in out.getvalue(), 'measure --dat --spr --outfit prints the metrics')
        np.savez_compressed(os.path.join(c.dir, 'r.npz'), g0_sprites=np.array([np.zeros((32, 32, 4), np.uint8)] * 32),
                            meta=np.array(json.dumps({'groups': [{'w': 2, 'h': 2, 'layers': 1, 'px': 4, 'py': 1, 'pz': 1, 'phases': 2,
                                                                  'anim': {'durations': [[100, 100], [100, 100]]}}]})))
        z = Q.load_npz(os.path.join(c.dir, 'r.npz'))
        ok(len(z.frames['anim']) == 4 and z.ms['anim'] == [100, 100], 'the npz reader gives groups, directions, durations')
    finally:
        shutil.rmtree(c.dir, ignore_errors=True)


def cli(*argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            rc = Q.main(list(argv))
        except SystemExit as e:
            rc = e.code if isinstance(e.code, int) else 2
    return rc, out.getvalue()


def test_cli():
    good = _png(np.concatenate([np.concatenate([f] * 4, 1) for f in GOOD], 0))
    flat = _png(np.concatenate([np.concatenate([blob(shade=False, outline=None, texture=0, glow=0, flat_colour=(160, 40, 40))] * 4, 1)] * 8, 0))
    rc, out = cli('check', '--kind', 'boss', good)
    ok(rc == 0 and out.startswith('PASS'), 'check passes the good sheet: rc %s: %s' % (rc, out[:300]))
    rc, out = cli('check', '--kind', 'boss', flat)
    ok(rc == 1 and out.startswith('FAIL') and 'colours' in out, 'check fails the flat sheet with the metric named: rc %s' % rc)
    rc, out = cli('check', '--kind', 'boss', '--strict', good)
    ok(rc == 1, 'check --strict fails on a warning')
    rc, out = cli('measure', '--kind', 'boss', good)
    ok(rc == 0 and 'colours' in out and 'outline_coverage' in out and 'changed_share' in out, 'measure prints every group of numbers')
    rc, out = cli('measure', '--json', '--kind', 'boss', good, flat)
    data = json.loads(out)
    ok(len(data) == 2 and data[0]['summary']['colours'] > data[1]['summary']['colours'], 'measure --json gives one record per file')
    rc, out = cli('check', '--json', '--kind', 'boss', good)
    ok(json.loads(out)[0]['ok'] is True, 'check --json')
    rc, out = cli('measure', '--frames', '--kind', 'boss', good)
    ok('frame idle' in out or 'frame walk' in out, 'measure --frames lists frames')
    rc, out = cli('check', good)
    ok(rc == 2, 'check without --kind is a usage error')
    rc, out = cli('measure')
    ok(rc != 0, 'nothing to read is an error')


def test_files_are_ours():
    # the committed art measures and checks without error on the files this tool is documented for
    here = os.path.dirname(os.path.abspath(__file__))
    p = os.path.join(here, 'art_import', 'decor_flames', 'candle.png')
    if os.path.exists(p):
        rc, out = cli('check', '--kind', 'item', p)
        ok(rc in (0, 1) and ('PASS' in out or 'FAIL' in out), 'check runs on a committed strip')


def main():
    for t in (test_good_and_flat, test_metrics_move, test_animation, test_kinds_and_bar, test_readers, test_cli, test_files_are_ours):
        t()
    for d in _tmp:
        shutil.rmtree(d, ignore_errors=True)
    print('sprite_quality_test:', 'FAILED %d' % failed if failed else 'ok')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
