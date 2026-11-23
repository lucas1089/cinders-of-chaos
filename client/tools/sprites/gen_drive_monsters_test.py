#!/usr/bin/env python3
"""Test of gen_drive_monsters.py (O726): python3 -I client/tools/sprites/gen_drive_monsters_test.py

The committed table, sums, redraw pictures and monster map against the rules (every rule with a failing case), and `discover` / `load` /
`resize` / `resample` / `measure` / `redraw_import` / `build` / `live` on synthetic 8-direction packs drawn here (Animations/Idle|Walk|
Running/<8 directions>/frame_NNN.png of random blocks with legs: a big walker on a 160 px canvas (scaled down to a 3x3 outfit), a floater
with idle only, a small one drawn near game size whose walk has no west and whose frames have canvases of three sizes, the big walker
shipped twice), on a synthetic redraw drop (four standing pictures; then idle and walk frames dropped later, picked up by a second import)
and a small synthetic input pair: the hard alpha and the palette of the block filter at whole and broken scales, every outfit 3x3, the
frame counts, the still redraw (1 phase, no animator, let through the motion rules only), the mirrored west walk, the canvas, the outfit
shape, wrong pictures, input pairs and an existing output folder refused, `live` holding the pair to the sums. No pack file and no real
pair needed. Needs numpy and Pillow (the fx venv of CI). Nothing drawn here is art of anyone."""
import csv
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
import gen_drive_monsters as D  # noqa: E402
import gen_wst_outfits_test as WT  # noqa: E402
from datspr import Dat  # noqa: E402
from import_outfits import parse_body  # noqa: E402

EIGHT = ('south', 'south-east', 'east', 'north-east', 'north', 'north-west', 'west', 'south-west')
failed = 0


def check(cond, what):
    global failed
    if not cond:
        failed += 1
        print('FAIL', what)


def draw(root, anim, counts, canvas, body, k=2, seed=1, dirs=EIGHT, canvases=None):
    """root/Animations/anim/<dir>/frame_NNN.png: a block body of k x k random colour cells (w, h in px) with two legs, standing on the
    bottom of the canvas less 8 px, moving a cell from frame to frame and different in each direction"""
    rng = np.random.default_rng(seed + sum(map(ord, anim)))
    w, h = body
    for di, d in enumerate(dirs):
        p = os.path.join(root, 'Animations', anim, d)
        os.makedirs(p)
        n = counts if isinstance(counts, int) else counts[di % len(counts)]
        for i in range(n):
            cv = canvas if canvases is None else canvases[(di + i) % len(canvases)]
            a = np.zeros((cv, cv, 4), np.uint8)
            cells = rng.integers(40, 250, ((h + k - 1) // k, (w + k - 1) // k, 3)).astype(np.uint8)
            col = np.repeat(np.repeat(cells, k, 0), k, 1)[:h, :w]
            legs = 4 * k
            x = (cv - w) // 2 + k * (di % 3) - k
            x -= x % k
            y = cv - 8 - h - legs - k * (i % 2)
            y -= y % k
            a[y:y + h, x:x + w, :3] = col
            a[y:y + h, x:x + w, 3] = 255
            for lx in (x + k, x + w - 3 * k):
                a[y + h:y + h + legs, lx:lx + 2 * k, :3] = 70
                a[y + h:y + h + legs, lx:lx + 2 * k, 3] = 255
            Image.fromarray(a, 'RGBA').save(os.path.join(p, 'frame_%03d.png' % i))


def figure(seed, di, i, soft=False):
    """a 96 x 96 standing figure of our own: a block body with two legs, hard alpha (or soft, to be refused)"""
    rng = np.random.default_rng(seed * 100 + di * 10 + i)
    a = np.zeros((96, 96, 4), np.uint8)
    x = 30 + 2 * di
    a[10:70, x:x + 30, :3] = rng.integers(30, 220, (60, 30, 3))
    a[10:70, x:x + 30, 3] = 255
    for lx in (x + 3 + (i % 2), x + 20 - (i % 2)):
        a[70:92, lx:lx + 6, :3] = 60
        a[70:92, lx:lx + 6, 3] = 255
    if soft:
        a[10, x, 3] = 128
    return D.L.shear(a, 0.3, 91)        # drawn at the game's angle (O728)


def stand(folder, soft=False):
    os.makedirs(folder)
    for di, name in enumerate(D.STANDING):
        Image.fromarray(figure(1, di, 0, soft), 'RGBA').save(os.path.join(folder, name))


def frames(folder):
    """idle (6 a direction) and walk (8) frames dropped beside the standing pictures"""
    for anim, n, dirs in (('idle', 6, D.DIRS), ('walk', 8, D.DIRS)):
        for di, d in enumerate(dirs):
            p = os.path.join(folder, anim, d)
            os.makedirs(p)
            for i in range(n):
                Image.fromarray(figure(2 if anim == 'idle' else 3, di, i), 'RGBA').save(os.path.join(p, 'frame_%03d.png' % i))


def main():
    # ---- the committed files
    check(D.problems() == [], 'committed table: %s' % D.problems())
    check(D.map_problems() == [], 'committed map: %s' % D.map_problems())
    check(D.write_map(check=True) == [], 'monster_drive_looks.csv is current')
    t = D.rows()
    check([int(r['new']) for r in t] == list(range(3561, 3589)), 'outfits 3561..3588 (O726 3561..3571, O729 3572..3588)')
    # O729: the words of the redraws of the upright third-party looks
    check(D.words_problems() == [], 'drive_redraw_words.csv: %s' % D.words_problems())
    check(len(D.O729_KEYS) == 17 and all(D.DROP_NAMES[k] == k for k in D.O729_KEYS), 'O729: 17 keys, the drop folder is the key')
    tmpw = tempfile.mkdtemp(prefix='o729words')
    rows_w = list(csv.DictReader(open(D.WORDS, newline='', encoding='utf-8')))
    for bad_w, text in ((dict(rows_w[0], monster='Nobody'), 'PICKS gives'), (dict(rows_w[0], pixellab_id='x'), 'pixellab_id'),
                        (dict(rows_w[0], description='a knight'), 'dark fantasy')):
        pw = os.path.join(tmpw, 'w.csv')
        with open(pw, 'w', newline='', encoding='utf-8') as f:
            w = csv.DictWriter(f, list(rows_w[0]))
            w.writeheader()
            w.writerows([bad_w] + rows_w[1:])
        check(any(text in x for x in D.words_problems(pw)), 'words rule %s' % text)
    check(any('O729_KEYS' in x for x in D.words_problems(D.WORDS, keys=D.O729_KEYS[::-1])), 'words out of order')
    check(D.words_problems(os.path.join(tmpw, 'none.csv')) == ['art_import/drive_redraw_words.csv is missing'], 'words missing')
    shutil.rmtree(tmpw, ignore_errors=True)
    check(D.FIRST_NEW == 3561 and D.PAIR == 81, 'after the 3,560 outfits of pair 80, pair 81')
    check(len({m for _k, m in D.PICKS}) == len(t), 'one monster a look')
    for r in t:
        check(D.P.tiles_of_text(r['tiles']) == 3, '%s: 3x3' % r['key'])
        check(0.2 <= float(r['scale']) <= 1.0, '%s: scale %s' % (r['key'], r['scale']))
    check({r['key'] for r in t if r['art'] == 'pack'} == {'wolf', 'crab'}, 'the wolf and the crab keep the pack art, the rest are redraws')
    check(all(r['scale'] == '1.00' for r in t if r['art'] == 'redraw'), 'redraws at game size')
    check(D.redraw_problems(t) == [], 'the redraw pictures: %s' % D.redraw_problems(t))
    check(any('has no' in x for x in D.redraw_problems(t, root=os.path.join(HERE, 'no-such-folder'))), 'a redraw without its pictures')
    check(any('south.png gives' in x for x in D.redraw_problems([dict(r, src='0' * 12) if r['art'] == 'redraw' else r for r in t])),
          'a redraw src that is not its south.png')
    # every rule fails on a bad row
    for bad, text in ((dict(t[0], new='9'), 'new id'), (dict(t[0], tiles='2x2'), 'size'), (dict(t[0], disp='8:0'), 'displacement'),
                      (dict(t[0], scale='1/2'), 'scale'), (dict(t[0], scale='1.20'), 'scale'),
                      (dict(t[0], art='x'), 'art'), (dict(t[0], float='1'), 'float'), (dict(t[0], idle='12'), 'idle'),
                      (dict(t[3], idle='1', idle_ms='0'), 'idle phases'), (dict(t[3], walk='1', walk_ms='0', walk_src='still'), 'walk is'),
                      (dict(t[0], scale='0.80'), 'game size'),
                      (dict(t[0], east='mirror'), 'east'), (dict(t[6], east='own'), 'east'),
                      (dict(t[0], walk='6'), 'walk is'), (dict(t[0], west='left'), 'walk_src'), (dict(t[0], src='xyz'), 'src'),
                      (dict(t[0], pixels='0'), 'pixels'), (dict(t[0], key='Seraph'), 'lower-case')):
        p = D.problems([bad] + t[1:])
        check(any(text in x for x in p), 'rule %s: %s' % (text, p))
    check(any('other outfits' in x for x in D.problems(t, {**D.read_sums(), '9999': 'x'})), 'sums name other outfits')
    check(any('not ROWS' in x for x in D.problems(t[::-1], D.read_sums())), 'rows out of order')
    old = {m: 1 for _k, m in D.PICKS}
    lv = {m: 10 for _k, m in D.PICKS}
    check(D.map_problems(t, old=old, levels=lv) == [], 'map on fakes')
    check(any('picked twice' in x for x in D.map_problems(t, D.PICKS + (('seraph', D.PICKS[0][1]),), old, lv)), 'a monster twice')
    check(any('worn by no monster' in x for x in D.map_problems(t, D.PICKS[1:], old, lv)), 'an outfit worn by none')
    check(any('not a hunt monster' in x for x in D.map_problems(t, D.PICKS, old, {})), 'a monster outside the hunt list')
    check(any('no monster file' in x for x in D.map_problems(t, D.PICKS, {}, lv)), 'an unknown monster')
    check(any('no row' in x for x in D.map_problems(t, D.PICKS + (('nokey', 'Rat'),), {**old, 'Rat': 21}, {**lv, 'Rat': 1})), 'a key with no row')

    # ---- the block filter: hard alpha, the block rule, no new colour
    a = np.zeros((4, 4, 4), np.uint8)
    a[0, 0] = (10, 20, 30, 255)
    a[0, 1] = (50, 60, 70, 255)
    a[1, 0] = (50, 60, 70, 255)                 # block (0, 0): 3 opaque, two of one colour
    a[2, 2] = (1, 2, 3, 255)                    # block (1, 1): one pixel of four: clear
    a[0, 2] = a[0, 3] = (9, 9, 9, 255)
    a[1, 2] = (8, 8, 8, 255)
    a[1, 3] = (8, 8, 8, 255)                    # block (0, 1): a tie, the first in the block wins
    s = D.shrink(a, 2)
    check(s.shape == (2, 2, 4), 'shape of a / 2')
    check(tuple(s[0, 0]) == (50, 60, 70, 255), 'the colour most opaque pixels have: %s' % (s[0, 0],))
    check(tuple(s[0, 1]) == (9, 9, 9, 255), 'a tie takes the first in the block: %s' % (s[0, 1],))
    check(s[1, 1, 3] == 0 and not s[1, 1].any(), 'one pixel of four is clear, no colour under it')
    rng = np.random.default_rng(5)
    big = np.zeros((61, 47, 4), np.uint8)
    big[..., :3] = rng.integers(0, 6, (61, 47, 3)) * 40
    big[..., 3] = (rng.random((61, 47)) > 0.4) * 255
    for k in (1, 2, 3):
        s = D.shrink(big, k)
        check(s.shape[:2] == (-(-61 // k), -(-47 // k)), 'padded shape at 1/%d' % k)
        check(set(np.unique(s[..., 3]).tolist()) <= {0, 255}, 'hard alpha at 1/%d' % k)
        src_c = set(map(tuple, big[big[..., 3] > 0][:, :3].tolist()))
        check(set(map(tuple, s[s[..., 3] > 0][:, :3].tolist())) <= src_c, 'no new colour at 1/%d' % k)
        check(not s[s[..., 3] == 0].any(), 'no colour under a clear pixel at 1/%d' % k)
        check(np.array_equal(D.shrink(big, k)[-1], s[-1]), 'the bottom row stays the bottom row')
    for sc in (0.73, 0.58, 0.5, 0.91):
        idx = D.resize_idx(61, sc)
        check(idx[-1][1] == 61 and all(a[1] == b[0] for a, b in zip(idx, idx[1:])) and all(b > a for a, b in idx),
              'source runs follow each other to the bottom at %.2f' % sc)
        s = D.resize(big, sc)
        check(s.shape[:2] == (len(idx), len(D.resize_idx(47, sc))), 'shape at %.2f' % sc)
        check(set(np.unique(s[..., 3]).tolist()) <= {0, 255}, 'hard alpha at %.2f' % sc)
        src_c = set(map(tuple, big[big[..., 3] > 0][:, :3].tolist()))
        check(set(map(tuple, s[s[..., 3] > 0][:, :3].tolist())) <= src_c, 'no new colour at %.2f' % sc)
        check(not s[s[..., 3] == 0].any(), 'no colour under a clear pixel at %.2f' % sc)
    check(np.array_equal(D.resize(big, 0.5), D.shrink(big, 2)), 'resize 0.5 is the 2 x 2 block filter')
    check(D.G.pick(20, 8) == [0, 2, 5, 7, 10, 12, 15, 17] and D.G.pick(5, 8) == [0, 0, 1, 1, 2, 3, 3, 4], 'evenly spaced frames')

    tmp = tempfile.mkdtemp(prefix='o726test')
    try:
        src, src2 = os.path.join(tmp, 'src'), os.path.join(tmp, 'src2')
        big_root = os.path.join(src, 'pack_big', 'x')
        draw(big_root, 'Idle', (11, 12, 17, 9), 160, (56, 104), k=2, seed=1)
        draw(big_root, 'Walk', (9, 11, 10, 9), 160, (56, 104), k=2, seed=2)
        draw(big_root, 'Flying_Idle', 6, 160, (90, 60), k=2, seed=3)        # not read: only "idle"
        fl_root = os.path.join(src, 'pack_float', 'x')
        draw(fl_root, 'Idle', 20, 160, (60, 100), k=2, seed=4)
        sm_root = os.path.join(src, 'pack_small', 'x')
        draw(sm_root, 'idle', 5, 84, (40, 46), k=1, seed=5, canvases=(84, 88))
        draw(sm_root, 'walk', (10, 12, 9), 92, (40, 46), k=1, seed=6, dirs=('south', 'south-east', 'east', 'north-east', 'north'),
             canvases=(88, 92))
        draw(sm_root, 'death', 4, 84, (40, 46), k=1, seed=7)
        shutil.copytree(os.path.join(src, 'pack_big'), os.path.join(src2, 'again'))     # one pack shipped twice
        chars = D.discover([src, src2])
        check(len(chars) == 3, 'three characters, the copy read once: %d' % len(chars))
        by = {}
        for c in chars:
            by[('big' if 'pack_big' in c.files[('idle', 0)][0] else 'float' if 'pack_float' in c.files[('idle', 0)][0] else 'small')] = c
        check(by['big'].walk_src == 'walk' and by['big'].west == 'own', 'the big one walks on its walk')
        check(by['float'].walk_src == 'idle', 'the floater walks on its idle')
        check(by['small'].west == 'mirror' and by['small'].files[('walk', 3)] == by['small'].files[('walk', 1)], 'no west walk: east mirrored')
        check(all('Flying' not in f for fs in by['big'].files.values() for f in fs), 'flying frames not read')
        check(len(by['big'].id) == 12 and int(by['big'].id, 16) >= 0, 'src id: 12 hex digits')
        fs = D.load(by['small'])
        check(len({a.shape for lst in fs.values() for a in lst}) == 1 and fs[('idle', 0)][0].shape[0] == 92, 'one canvas, the largest')
        check(all(np.array_equal(w, e[:, ::-1]) for w, e in zip(fs[('walk', 3)], fs[('walk', 1)])), 'the west walk is the east one mirrored')
        check(D.scale_start(D.load(by['big'])) < 1 and D.scale_start(fs) == 1, 'a big figure starts below 1, one near game size at 1')
        # a redraw drop: four standing pictures under any name
        drop, rroot = os.path.join(tmp, 'drop'), os.path.join(tmp, 'redraw')
        stand(os.path.join(drop, 'Any Name'))
        rid = D.W._sha12(os.path.join(drop, 'Any Name', 'south.png'))
        want = ((by['big'].id, 'seraph', 'pack'), (by['float'].id, 'aberration', 'pack'), (by['small'].id, 'seacaptain', 'pack'),
                (rid, 'ghost', 'redraw'))
        check(D.redraw_import(drop, rroot, want, log=lambda *_: None) == ['ghost'], 'the drop is matched by its south.png')
        check(sorted(os.listdir(os.path.join(rroot, 'ghost'))) == sorted(D.STANDING), 'the four standing pictures copied')
        check(D.redraw_problems([{'key': 'ghost', 'src': rid, 'art': 'redraw'}], root=rroot) == [], 'the import passes its rule')
        bad_drop = os.path.join(tmp, 'baddrop')
        stand(os.path.join(bad_drop, 'x'), soft=True)
        try:
            D.redraw_import(bad_drop, rroot, ((D.W._sha12(os.path.join(bad_drop, 'x', 'south.png')), 'ghost', 'redraw'),), log=lambda *_: None)
        except SystemExit as e:
            check('hard alpha' in str(e), 'soft alpha refused: %s' % e)
        else:
            check(False, 'a soft alpha redraw was imported')
        check(D.redraw_import(bad_drop, rroot, want, log=lambda *_: None) == [], 'an unknown south.png is skipped')
        ms = D.measured([src, src2], want, first=3, redraw=rroot)
        r0, r1, r2, r3 = (r for r, _p in ms)
        check((r3['art'], r3['idle'], r3['idle_ms'], r3['walk'], r3['walk_ms'], r3['walk_src'], r3['scale'], r3['tiles']) ==
              ('redraw', '1', '0', '1', '0', 'still', '1.00', '3x3'), 'a redraw with no frames stands still: %s' % r3)
        check(D.problems([dict(r, new=str(3561 + i)) for i, (r, _p) in enumerate(ms)], {str(3561 + i): 'x' for i in range(4)}, want=None) == [],
              'the rows pass the table rules: %s' % D.problems([dict(r, new=str(3561 + i)) for i, (r, _p) in enumerate(ms)],
                                                               {str(3561 + i): 'x' for i in range(4)}, want=None))
        check(0.5 < float(r0['scale']) < 1 and 0.5 < float(r1['scale']) < 1 and r2['scale'] == '1.00',
              'scales %s' % [r0['scale'], r1['scale'], r2['scale']])
        check(all(r['tiles'] == '3x3' for r in (r0, r1, r2)), 'every outfit 3x3, the small one too')
        check((r0['idle'], r1['idle'], r2['idle']) == ('8', '8', '5') and r2['idle_ms'] == '200', 'idle phases: at most 8, the pack count below')
        check(all(r['walk'] == '8' and r['walk_ms'] == '100' for r in (r0, r1, r2)), 'walk 8 x 100 ms')
        check(r0['idle_frames'] == '12/17/11/11' or r0['idle_frames'].count('/') == 3, 'frame counts north / east / south / west')
        check(r1['float'] == '1' and r0['float'] == '0', 'the floater floats')
        check(r2['west'] == 'mirror' and r2['walk_frames'].split('/')[3] == r2['walk_frames'].split('/')[1], 'west counts as east')
        for r, placed in ms:
            check(D.frame_problems(r, placed) == [], '%s: %s' % (r['key'], D.frame_problems(r, placed)))
            check(all(set(np.unique(a[..., 3]).tolist()) <= {0, 255} for lst in placed.values() for a in lst), 'hard alpha placed')
        sums = D.pack_sums(ms)
        check(D.pack_sums(D.measured([src], want, first=3, redraw=rroot)) == sums, 'the same packs give the same sums')
        # O728: the packs (upright blocks) are sheared, the redraw (drawn leaning) is not; every look leans in the band
        check(all(D.L.K_MIN <= float(r['lean']) <= D.L.K for r in (r0, r1, r2)) and r3['lean'] == '0.00',
              'lean column %s' % [r['lean'] for r, _p in ms])
        for r, placed in ms:
            check(D.L.lean_ok(placed), '%s leans %s' % (r['key'], D.L.lean_text(placed)))
        sh_pixels = {r['key']: int(r['pixels']) for r, _p in ms}
        check(all(v > 0 for v in sh_pixels.values()), 'pixels counted')
        r_up, p_up = ms[3]
        flat = {k: [np.ascontiguousarray(D.L.shear(a, -0.3)) for a in v] for k, v in p_up.items()}
        check(any('game\'s angle' in x for x in D.frame_problems(dict(r_up, key='ghost'), flat)), 'an upright redraw fails the lean rule')
        keep = D.UPRIGHT_PENDING
        D.UPRIGHT_PENDING = ('seraph',)
        check(not any('game\'s angle' in x for x in D.frame_problems(dict(r_up, key='seraph'), flat)), 'a pending key waits')
        check(any('UPRIGHT_PENDING' in x for x in D.frame_problems(dict(r_up, key='seraph'), p_up)), 'a pending key that leans is named')
        D.UPRIGHT_PENDING = keep
        check(D.UPRIGHT_PENDING == (), 'every oblique redraw is in (O728)')
        for bad, text in ((dict(r3, lean='0.25'), 'never sheared'), (dict(r0, lean='0.30'), 'lean 0.30'), (dict(r0, lean='x'), 'lean x')):
            p = D.problems([dict(bad, new='3561')], {'3561': 'x'}, want=None)
            check(any(text in x for x in p), 'lean rule %s: %s' % (text, p))
        # O728: an oblique PixelLab download imported as a redraw (rotations, a v3 walk of 9 with the standing frame_000)
        pl_drop = os.path.join(tmp, 'pldrop', 'plague', 'Idle')
        for di, d in enumerate(D.DIRS):
            os.makedirs(os.path.join(pl_drop, 'rotations'), exist_ok=True)
            os.makedirs(os.path.join(pl_drop, 'animations', 'walkv3-%d' % di, d))
            Image.fromarray(figure(4, di, 0)[8:88, 8:88], 'RGBA').save(os.path.join(pl_drop, 'rotations', d + '.png'))
            for i in range(9):
                Image.fromarray(figure(5, di, i)[8:88, 8:88], 'RGBA').save(
                    os.path.join(pl_drop, 'animations', 'walkv3-%d' % di, d, 'frame_%03d.png' % i))
        droot = os.path.join(tmp, 'droproot')
        check(D.drop_import(os.path.join(tmp, 'pldrop'), root=droot, log=lambda *_: None) == ['plaguemedic'], 'the drop name maps to its key')
        got = sorted(os.listdir(os.path.join(droot, 'plaguemedic')))
        check(got == sorted(D.STANDING + ('idle', 'walk')), 'standing pictures, idle and walk written: %s' % got)
        check([len(os.listdir(os.path.join(droot, 'plaguemedic', g, 'south'))) for g in ('idle', 'walk')] == [4, 8],
              'a breath of 4, a walk of 8 (frame_000 is the standing reference)')
        rp, pp = D.measure(D.redraw_character(os.path.join(droot, 'plaguemedic')), 'plaguemedic', 9, 'redraw')
        check((rp['idle'], rp['idle_ms'], rp['walk'], rp['lean'], rp['tiles']) == ('4', '300', '8', '0.00', '3x3'), 'the drop row: %s' % rp)
        check(D.frame_problems(rp, pp) == [], 'the drop passes every rule: %s' % D.frame_problems(rp, pp))
        check(D.redraw_built_problems() == [], 'the committed redraws build as the table: %s' % D.redraw_built_problems())

        # ---- the pair
        odat, ospr = WT.input_pair(tmp)
        out = os.path.join(tmp, 'out')
        lines = []
        new = D.build(odat, ospr, out, [src, src2], want=want, first=3, log=lines.append, redraw=rroot)
        check(new == [3, 4, 5, 6], 'new ids %s' % new)
        tbl = [r for r, _p in ms]
        paths = (os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr'))
        d = Dat(paths[0])
        check(len(d.outfits) == 6, 'two old outfits and four new')
        s0, s1 = parse_body(d, d.outfit(6))
        check((s0.phases, s1.phases, s0.anim, s1.anim) == (1, 1, None, None), 'the still redraw: one phase a group, no animator')
        g0, g1 = parse_body(d, d.outfit(3))
        check((g0.gtype, g0.phases, g1.gtype, g1.phases, g0.layers) == (0, 8, 1, 8, 1), 'idle 8 and walk 8, one layer')
        check(g0.anim == (0, 0, 0, (200, 200) * 8) and g1.anim == (0, 0, 0, (100, 100) * 8), 'durations')
        for r in tbl:
            check(dict(d.outfit(int(r['new'])).flags) == D.P.flags_of(r)[1], 'the displacement is the only flag')
        quiet = dict(log=lambda *_: None)
        check(D.live(*paths, table=tbl, sums=sums, first=3, **quiet) == [], 'live passes')
        check(D.live(*paths, table=tbl, sums={**sums, '4': '0' * 64}, first=3, **quiet) != [], 'live: other sums')
        check(D.live(odat, ospr, table=tbl, sums=sums, first=3, **quiet) != [], 'live: a pair without the outfits')
        check(D.live(*paths, table=[dict(tbl[0], idle_ms='300')] + tbl[1:], sums=sums, first=3, **quiet) != [], 'live: other durations')
        check(D.live(*paths, table=tbl[:3] + [dict(tbl[3], pixels='1')], sums=sums, first=3, **quiet) != [], 'live: a still look checked too')
        for args, kw, text in (((odat, ospr, out, [src]), dict(want=want, first=3), 'exists'),
                               ((odat, ospr, os.path.join(tmp, 'o2'), [src]), dict(want=want, first=5), 'needs 4'),
                               ((odat, ospr, os.path.join(tmp, 'o3'), [src]), dict(want=(('0' * 12, 'seraph', 'pack'),), first=3), 'no pack character'),
                               ((odat, ospr, os.path.join(tmp, 'o4'), [src]), dict(want=(('0' * 12, 'ghost', 'redraw'),), first=3, redraw=rroot),
                                'no redraw character')):
            try:
                D.build(*args, log=lambda *_: None, **kw)
            except SystemExit as e:
                check(text in str(e), 'refusal %s: %s' % (text, e))
            else:
                check(False, 'build did not refuse: ' + text)
        out2 = os.path.join(tmp, 'again')
        D.build(odat, ospr, out2, [src], want=want, first=3, log=lambda *_: None, redraw=rroot)
        check(open(paths[0], 'rb').read() == open(os.path.join(out2, 'Tibia.dat'), 'rb').read(), 'same dat twice')
        check(open(paths[1], 'rb').read() == open(os.path.join(out2, 'Tibia.spr'), 'rb').read(), 'same spr twice')

        # frames dropped later: the next import picks them up, the redraw moves
        frames(os.path.join(drop, 'Any Name'))
        check(D.redraw_import(drop, rroot, want, log=lambda *_: None) == ['ghost'], 'the second drop')
        check(sorted(os.listdir(os.path.join(rroot, 'ghost'))) == sorted(D.STANDING + ('idle', 'walk')), 'idle and walk copied')
        ms2 = D.measured([src], want, first=3, redraw=rroot)
        r3b, p3b = ms2[3]
        check((r3b['idle'], r3b['walk'], r3b['walk_src'], r3b['idle_ms'], r3b['walk_ms']) == ('6', '8', 'walk', '200', '100'),
              'the redraw moves now: %s' % r3b)
        check(D.frame_problems(r3b, p3b) == [], 'its frames pass every rule: %s' % D.frame_problems(r3b, p3b))
        fc = D.facing(os.path.join(rroot, 'ghost'), os.path.join(rroot, 'ghost'))
        check(sorted(fc) == sorted((g, d) for g in ('idle', 'walk') for d in D.DIRS),
              'facing measures every frame folder: %s' % sorted(fc))
        check(all(len(v) == (6 if g == 'idle' else 8) and set(v) <= set(D.DIRS) for (g, _d), v in fc.items()), 'one nearest view a frame')
        r3m, p3m = D.measure(D.redraw_character(os.path.join(rroot, 'ghost')), 'seacaptain', 9, 'redraw')
        r3o, p3o = D.measure(D.redraw_character(os.path.join(rroot, 'ghost')), 'ghost', 9, 'redraw')
        check(r3m['east'] == 'mirror' and r3o['east'] == 'own' and r3m['disp'] == r3o['disp'], 'EAST_FROM_WEST sets the east column')
        check(any(not np.array_equal(a, b) for a, b in zip(p3m[('walk', 1)], p3o[('walk', 1)])) and
              all(np.array_equal(a, b) for a, b in zip(p3m[('walk', 3)], p3o[('walk', 3)])), 'only the walk east changes')
        out3 = os.path.join(tmp, 'moving')
        D.build(odat, ospr, out3, [src], want=want, first=3, log=lambda *_: None, redraw=rroot)
        check(D.live(os.path.join(out3, 'Tibia.dat'), os.path.join(out3, 'Tibia.spr'), table=[r for r, _p in ms2], sums=D.pack_sums(ms2),
                     first=3, **quiet) == [], 'live passes on the moving redraw')
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    check(D.main(['build', 'a', 'b']) == 2 and D.main(['nothing']) == 2, 'usage')
    print('gen_drive_monsters_test: %s' % ('ok' if not failed else '%d failed' % failed))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
