#!/usr/bin/env python3
"""python3 -I client/tools/sprites/gen_pack30_looks_test.py : gen_pack30_looks.py on SYNTHETIC packs only (generated
rectangles in a temporary folder; no pack image is read or shown), plus the committed looks tables against each other.
Needs numpy and Pillow (the fx venv)."""
import atexit
import json
import os
import shutil
import sys
import tempfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pack30lib as L  # noqa: E402
import gen_pack30_looks as G  # noqa: E402
import import_art_things as IAT  # noqa: E402

failed = 0
POSES = ['idle1', 'idle2', 'walk1', 'walk2', 'walk3', 'walk4', 'attack1', 'attack2', 'death1', 'death2', 'death3']
MK = L.MASK_MARKERS


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def raises(fn, what):
    try:
        fn()
    except L.PackError:
        return
    check(False, what)


def make_sheet(cell, box_w, box_h, seed):
    """a synthetic sheet: every (pose, dir) base cell holds an asymmetric block, the mask the four markers."""
    a = np.zeros((len(POSES) * cell, 8 * cell, 4), np.uint8)
    rng = np.random.RandomState(seed)
    for r in range(len(POSES)):
        for d in range(4):
            x0 = 3 + d * 2 + (r % 3)               # moves with direction and pose, so the union is larger than one box
            y0 = 5 + r % 2
            ox, oy = d * cell, r * cell
            blk = np.zeros((box_h, box_w, 4), np.uint8)
            blk[...] = (90 + d * 20, 100 + r * 5, 110, 255)
            blk[0, :, :] = (250, 250, 250, 255)     # a top line, so a mirror would be visible
            blk[:, 0, :] = (10, 200, 10, 255)       # a left column
            blk[1, 1] = (7, 7, 7, 5)                # alpha under 12: cleared
            a[oy + y0:oy + y0 + box_h, ox + x0:ox + x0 + box_w] = blk
            m = np.zeros((box_h, box_w, 4), np.uint8)
            q = box_h // 4
            for k, mk in enumerate(MK):
                m[k * q:(k + 1) * q, :] = (mk[0], mk[1], mk[2], 255)
            m[0, 0] = (120, 120, 120, 255)           # not a marker: cleared
            m[0, 1] = (255, 255, 0, 100)             # marker with alpha < 128: cleared
            m[1, 0] = (250, 10, 10, 220)             # near the red marker: snaps
            a[oy + y0:oy + y0 + box_h, (4 + d) * cell + x0:(4 + d) * cell + x0 + box_w] = m
    return a


def write_creature(root, pack, folder, cell, bw, bh, seed, glow=False, tints=None):
    d = os.path.join(root, pack, folder)
    os.makedirs(os.path.join(d, 'sheets'))
    sheet = make_sheet(cell, bw, bh, seed)
    name = folder.capitalize() + '_sheet.png'
    Image.fromarray(sheet, 'RGBA').save(os.path.join(d, 'sheets', name))
    Image.fromarray(np.zeros((len(POSES) * cell, 4 * cell, 4), np.uint8), 'RGBA').save(
        os.path.join(d, 'sheets', folder.capitalize() + '_shadow.png'))
    if glow:
        Image.fromarray(np.zeros((len(POSES) * cell, 4 * cell, 4), np.uint8), 'RGBA').save(
            os.path.join(d, 'sheets', folder.capitalize() + '_glow.png'))
    tints = tints or {'ash': {'head': [255, 255, 255], 'body': [0, 0, 0], 'legs': [200, 40, 40], 'feet': [10, 10, 250]},
                      'moss': {'head': [90, 160, 80], 'body': [60, 100, 60], 'legs': [30, 50, 30], 'feet': [120, 90, 40]}}
    js = {'name': folder, 'cell': cell, 'directions': ['up', 'right', 'down', 'left'], 'poses': POSES,
          'fps': {'idle': 3, 'walk': 8, 'attack': 10, 'death': 7}, 'schemes': list(tints), 'tints': tints,
          'description': 'text that must never be copied'}
    json.dump(js, open(os.path.join(d, 'animations.json'), 'w'))
    return sheet


def setup(creatures, overrides=None):
    """creatures: [(pack, folder, cell, bw, bh, glow)] -> (tmp root, src dir, Paths, sheets by key)"""
    root = tempfile.mkdtemp()
    atexit.register(shutil.rmtree, root, True)
    src = os.path.join(root, 'src')
    art = os.path.join(root, 'art')
    pk = os.path.join(root, 'picks')
    os.makedirs(art)
    os.makedirs(pk)
    sheets = {}
    rows = []
    for n, (pack, folder, cell, bw, bh, glow) in enumerate(creatures):
        sheets[folder] = write_creature(src, pack, folder, cell, bw, bh, n, glow)
    for pack in sorted({c[0] for c in creatures}):
        rows += L.scan_pack(pack, os.path.join(src, pack), looks=True)
    p = G.Paths(art, pk)
    open(p.files, 'w', newline='').write(L.files_text(rows))
    open(p.overrides, 'w', newline='').write(L.csv_text(L.OVERRIDE_FIELDS, overrides or []))
    return root, src, p, sheets


def test_main():
    # input order is deliberately not the sorted order
    crs = [('t_b', 'zed_wolf', 64, 30, 24, False), ('t_a', 'moss_imp', 128, 70, 60, True), ('t_a', 'ash_rat', 64, 20, 20, False)]
    root, src, p, sheets = setup(crs)
    creatures, infos, out, ov = G.build_all(src, p, 3, private={})
    keys = [i.key for i in infos]
    check(keys == ['ash_rat', 'moss_imp', 'zed_wolf'], 'sorted by pack, then slug: %s' % keys)
    check([c.glow for c in creatures] == [False, True, False], 'glow detected, not used')

    # size rule: union box of the base over 6 poses x 4 directions, smallest of 1..4 tiles holding box + 1 px
    by = {i.key: i for i in infos}
    check((by['ash_rat'].tw, by['ash_rat'].th) == (1, 1), 'ash_rat 1x1: %s' % ((by['ash_rat'].tw, by['ash_rat'].th),))
    check(by['zed_wolf'].tw == 2 and by['zed_wolf'].th == 2, 'zed_wolf union box > 31 px needs 2x2')
    check(by['moss_imp'].tw == 3, 'moss_imp 3x3')

    # right and bottom edge 1 px from the frame edge, the same shift for every frame and direction, no mirror
    for key, cell, bw, bh in (('zed_wolf', 64, 30, 24), ('moss_imp', 128, 70, 60), ('ash_rat', 64, 20, 20)):
        info, (sheet, corpse) = by[key], out[key]
        S = info.tw * 32
        check(sheet.shape == (6 * S, 8 * S, 4), '%s sheet shape %s' % (key, sheet.shape))
        src_sheet = L.clean_alpha(sheets[key])
        frames = [src_sheet[r * cell:(r + 1) * cell, d * cell:(d + 1) * cell] for r in range(6) for d in range(4)]
        box = L.union_bbox(frames)
        w, h = box[2] - box[0], box[3] - box[1]
        for r in range(6):
            for d in range(4):
                got = sheet[r * S:(r + 1) * S, d * S:(d + 1) * S]
                want = np.zeros((S, S, 4), np.uint8)
                want[S - 1 - h:S - 1, S - 1 - w:S - 1] = frames[r * 4 + d][box[1]:box[3], box[0]:box[2]]
                check(np.array_equal(got, want), '%s r%d d%d placed bottom-right with the union box' % (key, r, d))
        un = L.union_bbox([sheet[r * S:(r + 1) * S, d * S:(d + 1) * S] for r in range(6) for d in range(4)])
        check(un[2] == S - 1 and un[3] == S - 1, '%s union reaches 1 px from right and bottom: %s' % (key, un))
        # no mirroring anywhere: east is not the flipped west
        e, w = sheet[0:S, 1 * S:2 * S], sheet[0:S, 3 * S:4 * S]
        check(not np.array_equal(e, L.mirror(w)), '%s east is not a mirror of west' % key)
        # mask layer: only the four markers, alpha 255, off-marker and weak pixels cleared, near-marker snapped
        mask = sheet[:, 4 * S:]
        on = mask[..., 3] > 0
        cols = {tuple(c) for c in mask[on][:, :3].tolist()}
        check(cols <= set(MK), '%s mask colours %s' % (key, cols))
        check(set(mask[on][:, 3].tolist()) == {255}, '%s mask alpha 255' % key)
        check(len(cols) == 4, '%s all four markers present' % key)
        # same shift for the mask as the base (the first mask pixel of the first frame lines up with its base block)
        mfr = mask[0:S, 0:S]
        mbox = L.alpha_bbox(mfr)
        bbox0 = L.alpha_bbox(sheet[0:S, 0:S])
        check(mbox[2] <= bbox0[2] and mbox[3] <= bbox0[3], '%s mask inside the base box' % key)
        # alpha under 12 is gone from the base
        base = sheet[:, :4 * S]
        check(not ((base[..., 3] > 0) & (base[..., 3] < 12)).any(), '%s base alpha < 12 cleared' % key)

    # the glow and shadow files are not used: nothing of them is read (the sheet is the only image)
    # corpse: death3 facing down (column 2), own alpha box, bottom-right
    info, (sheet, corpse) = by['ash_rat'], out['ash_rat']
    fr = L.clean_alpha(sheets['ash_rat'][10 * 64:11 * 64, 2 * 64:3 * 64])
    cb = L.alpha_bbox(fr)
    cw, ch = cb[2] - cb[0], cb[3] - cb[1]
    S = info.ctw * 32
    check(corpse.shape == (S, S, 4) and info.ctw == info.cth == 1, 'corpse 1x1')
    want = np.zeros((S, S, 4), np.uint8)
    want[S - 1 - ch:S - 1, S - 1 - cw:S - 1] = fr[cb[1]:cb[3], cb[0]:cb[2]]
    check(np.array_equal(corpse, want), 'corpse is death3 facing down, bottom-right')

    # tables
    t = G.all_tables(creatures, infos, ov, p, out)
    rows = list(__import__('csv').DictReader(open_text(t[p.things])))
    outfits = [r for r in rows if r['cat'] == 'outfit']
    items = [r for r in rows if r['cat'] == 'item']
    check([r['key'] for r in outfits] == keys and [r['key'] for r in items] == ['corpse_' + k for k in keys], 'rows in sorted order')
    check(outfits[0]['phases'] == '2+4' and outfits[0]['patterns'] == '4' and outfits[0]['atlas'] == 'pack30_looks/ash_rat', 'outfit row')
    check(outfits[0]['name'] == 'Ash Rat' and items[0]['name'] == 'dead ash rat', 'names from the slug')
    check(items[0]['kind'] == 'corpse' and items[0]['flags'] == 'container forceuse notmoveable usable' and
          items[0]['extra'] == 'race=blood', 'corpse row')
    check('idle_ms=333|walk_ms=125|' in outfits[0]['extra'], 'ms from fps: %s' % outfits[0]['extra'])
    tint = [r for r in __import__('csv').DictReader(open_text(t[p.tints]))]
    check([(r['key'], r['scheme']) for r in tint][:2] == [('ash_rat', 'ash'), ('ash_rat', 'moss')], 'tint rows, scheme order kept')
    want_idx = [L.rgb_to_outfit_index(v) for v in ((255, 255, 255), (0, 0, 0), (200, 40, 40), (10, 10, 250))]
    check([int(tint[0][c]) for c in G.PART] == want_idx, 'tint indices are the nearest outfit colours')
    check(outfits[0]['extra'].endswith('head=%d|body=%d|legs=%d|feet=%d' % tuple(want_idx)), 'default look colours = first scheme')
    pk = list(__import__('csv').DictReader(open_text(t[p.picks])))
    check([int(r['look']) for r in pk] == [2237, 2238, 2239] and pk[0]['family'] == 'gallery', 'picks: ids 2237.. in order')
    check('text that must never be copied' not in ''.join(t.values()), 'description text is never copied')
    check(all(('t_a' in r[3] or 't_b' in r[3]) for r in G.sources_rows(creatures)), 'sources hold pack slug/path')
    check(any('glow layer not used' in r[3] for r in G.sources_rows(creatures)), 'glow noted in the sources')
    check(set(r[2] for r in G.sources_rows(creatures)) == {'set30 monsters'}, 'label')

    # deterministic: a second build gives the same tables and sheets
    c2, i2, o2, ov2 = G.build_all(src, p, 3, private={})
    t2 = G.all_tables(c2, i2, ov2, p, o2)
    check(t == t2, 'two builds give identical tables')

    # the rows load in the real importer and the frames are the sheet cells
    G.write_all(p, t, infos, out)
    IAT.ATLAS_DIR[0] = p.art
    IAT._atlas.clear()
    trows = IAT.read_things(p.things)
    for r in trows:
        if r['cat'] == 'outfit':
            fr = IAT.outfit_frames(r)
            S = r['w'] * 32
            sheet = out[r['key']][0]
            check(len(fr) == 6 * 4 * 2, '%s frames %d' % (r['key'], len(fr)))
            check(np.array_equal(fr[(1, 3, 2, 1, 0, 0)], sheet[5 * S:6 * S, 6 * S:7 * S]), '%s walk4 south mask cell' % r['key'])
            check(np.array_equal(fr[(0, 1, 1, 0, 0, 0)], sheet[1 * S:2 * S, 1 * S:2 * S]), '%s idle2 east base cell' % r['key'])
        else:
            check(r['mode'] == 'new' and int(r['patterns']) == 1, 'corpse item row')
    check(os.path.isfile(os.path.join(p.out, '.gitignore')), 'sheet folder has its .gitignore')

    # build --check without sources, then with
    check(G.check_tables(p, None, 3) == [], 'no-source check passes: %s' % G.check_tables(p, None, 3))
    check(G.check_tables(p, src, 3, {}) == [], 'source check passes')
    # a hand edit is found
    txt = open(p.things).read().replace('Ash Rat', 'Ash Rodent')
    open(p.things, 'w', newline='').write(txt)
    check(G.check_tables(p, None, 3) != [], 'edited csv is found')
    open(p.things, 'w', newline='').write(txt.replace('Ash Rodent', 'Ash Rat'))
    # a changed sheet is found by the sums
    sp = os.path.join(p.out, 'ash_rat.png')
    a = np.asarray(Image.open(sp).convert('RGBA')).copy()
    a[0, 0] = (1, 2, 3, 255)
    Image.fromarray(a, 'RGBA').save(sp)
    check(any('ash_rat.png' in b for b in G.check_tables(p, None, 3)), 'changed sheet differs from the sums')
    # count guard
    raises(lambda: G.check_count(creatures, 4), 'creature count other than the block is refused')
    # a source file that differs from the list is refused (md5)
    f = os.path.join(src, 't_a', 'ash_rat', 'sheets', 'Ash_rat_sheet.png')
    a = np.asarray(Image.open(f).convert('RGBA')).copy()
    a[0, 0] = (9, 9, 9, 255)
    Image.fromarray(a, 'RGBA').save(f)
    raises(lambda: G.build_all(src, p, 3, private={}), 'md5 mismatch stops the build')


def open_text(s):
    import io
    return io.StringIO(s)


def test_limits_and_overrides():
    # a union box of ~120 px is 4x4; one above 127 px needs 5 tiles and stops
    root, src, p, sheets = setup([('t_a', 'big_one', 128, 108, 100, False)])
    _, infos, out, _ = G.build_all(src, p, 1, private={})
    check((infos[0].tw, infos[0].th) == (4, 4), 'a union box of 120 px is 4x4')
    root, src, p, sheets = setup([('t_a', 'huge_one', 160, 140, 140, False)])
    raises(lambda: G.build_all(src, p, 1, private={}), 'a box above 4 tiles stops the build')
    # overrides: tiles, dx, dy, rename; skip is refused
    root, src, p, sheets = setup([('t_a', 'ash_rat', 64, 20, 20, False)],
                                 [['ash_rat', 'tiles', '2'], ['ash_rat', 'dx', '-2'], ['ash_rat', 'dy', '-3'],
                                  ['ash_rat', 'rename', 'Dust Rat']])
    c, infos, out, ov = G.build_all(src, p, 1, private={})
    check((infos[0].tw, infos[0].th) == (2, 2), 'tiles override')
    sheet = out['ash_rat'][0]
    un = L.union_bbox([sheet[r * 64:(r + 1) * 64, d * 64:(d + 1) * 64] for r in range(6) for d in range(4)])
    check(un[2] == 64 - 1 - 2 and un[3] == 64 - 1 - 3, 'dx, dy shift the box: %s' % (un,))
    check(G.things_rows(infos, ov)[0][3] == 'Dust Rat', 'rename')
    root, src, p, sheets = setup([('t_a', 'ash_rat', 64, 20, 20, False)], [['ash_rat', 'skip', '1']])
    raises(lambda: G.build_all(src, p, 1, private={}), 'skip is refused')
    # an empty sheet and a wrong sheet size stop the build
    root, src, p, sheets = setup([('t_a', 'ash_rat', 64, 20, 20, False)])
    try:
        G.split_sheet(np.zeros((10, 10, 4), np.uint8), {'cell': 64, 'poses': POSES}, 'x')
        check(False, 'wrong sheet size')
    except L.PackError:
        pass


def test_committed():
    """the committed tables, when present, agree with each other and with pack30_looks.files (no sources needed)."""
    p = G.Paths()
    if not os.path.isfile(p.things):
        print('note: no committed pack30_looks.csv yet, skipped')
        return
    bad = G.check_tables(p, None)
    check(not bad, 'committed looks tables: %s' % bad[:3])
    rows = list(__import__('csv').DictReader(open(p.things, newline='')))
    outs = [r for r in rows if r['cat'] == 'outfit']
    itms = [r for r in rows if r['cat'] == 'item']
    check(len(outs) == len(itms) == G.COUNT, 'counts')
    check(G.FIRST_OUTFIT + G.COUNT - 1 == 2311 and G.FIRST_ITEM + G.COUNT - 1 == 34833, 'id blocks')
    names = [r['name'] for r in outs]
    check(len(set(names)) == len(names), 'names are unique')
    import re
    text = ' '.join(open(f, encoding='utf-8').read() for f in (p.things, p.tints, p.sources, p.picks))
    check(not re.search(r'w' + 'st|mon_', text.replace('mon_a/', '').replace('mon_b/', '').replace('mon_c/', ''), re.I), 'no vendor tokens')


if __name__ == '__main__':
    test_main()
    test_limits_and_overrides()
    test_committed()
    print('gen_pack30_looks_test:', 'OK' if not failed else '%d failure(s)' % failed)
    sys.exit(1 if failed else 0)
