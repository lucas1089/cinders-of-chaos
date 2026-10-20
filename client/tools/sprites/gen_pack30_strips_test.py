#!/usr/bin/env python3
"""Tests of gen_pack30_strips.py on synthetic strips only (no pack file is read).

    /tmp/fxenv/bin/python -I gen_pack30_strips_test.py
"""
import os
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_pack30_strips as G  # noqa: E402
import pack30lib as P  # noqa: E402

OK = []


def check(cond, what):
    if not cond:
        print('FAIL', what)
        sys.exit(1)
    OK.append(what)


def raises(fn, what):
    try:
        fn()
    except P.PackError:
        OK.append(what)
        return
    print('FAIL', what, '(no PackError)')
    sys.exit(1)


def frame(cell, x0, y0, x1, y1, val):
    """a frame with a filled box; the colour encodes `val` so frames can be told apart"""
    a = np.zeros((cell, cell, 4), np.uint8)
    a[y0:y1, x0:x1] = (val, 50, 200, 255)
    a[y0, x0] = (val, 1, 1, 255)          # a marker pixel at the box's top-left corner (shows mirroring)
    return a


def strip(frames):
    return np.concatenate(frames, axis=1)


def row(slug, path, w, h):
    return P.FileRow(slug, path, 1, 'x' * 32, w, h)


def packs(*slugs, fit='high'):
    return [P.Pack(s, 'set30 mutter', 'v1', 'ready', 'strips', '', 'x', fit, '', 'x', 1, 1, '') for s in slugs]


# ------------------------------------------------------------------------------------------------ names
def test_names():
    check(G.parse_name('Goblin_Shaman_idle_strip9.png') == ('goblin_shaman', 'idle', 9), 'plain name')
    check(G.parse_name('spr_rat_king_walk_strip13.png') == ('rat_king', 'walk', 13), 'spr_ prefix dropped')
    check(G.parse_name('spr_Basic_Skeleton_Idle_strip9.png') == ('basic_skeleton', 'idle', 9), 'case ignored')
    check(G.parse_name('dr_zombie_walk_death_strip9.png') == ('dr_zombie', 'walk_death', 9), 'walk_death is its own anim')
    check(G.parse_name('survivor_old_man_take_dmg_strip9.png') == ('survivor_old_man', 'take_dmg', 9), 'take_dmg')
    check(G.parse_name('Pumpkin_Headed_attack_strip9.png') == ('pumpkin_headed_monster', 'attack', 9), 'alias merges spellings')
    check(G.parse_name('readme.json') is None and G.parse_name('Foo_strip9.png') is None, 'not a strip name')
    raises(lambda: G.strip_cell(row('a', 'X_idle_strip9.png', 500, 64)), 'width must be N square frames')
    check(G.strip_cell(row('a', 'X_idle_strip9.png', 576, 64)) == 64, 'cell = strip height')


# ------------------------------------------------------------------------------------------------ plan
def test_plan():
    rows = [row('p', 'Imp_idle_strip9.png', 576, 64), row('p', 'Imp_walk_strip9.png', 576, 64),
            row('p', 'Imp_death_strip9.png', 576, 64), row('p', 'Imp_attack_strip9.png', 576, 64),
            row('p', 'Imp_hit_strip9.png', 576, 64),
            row('p', 'Monk_idle_strip9.png', 576, 64), row('p', 'Monk_pray_strip9.png', 576, 64),
            row('p', 'Squid_idle_strip17.png', 2176, 128), row('p', 'Squid_death_strip17.png', 2176, 128),
            row('p', 'Ghoul_walk_strip9.png', 576, 64),
            row('p', 'Lonely_death_strip9.png', 576, 64), row('p', 'notes.png', 10, 10),
            row('other', 'Zed_idle_strip9.png', 576, 64)]
    looks, unused, unmatched = G.plan(rows, packs('p'))
    keys = [lk.key for lk in looks]
    check(keys == ['p__ghoul', 'p__imp', 'p__monk', 'p__monk_pray', 'p__squid'], 'looks sorted, pray right after: %s' % keys)
    ghoul = looks[0]
    check(ghoul.idle is ghoul.walk, 'missing idle reuses walk')
    squid = looks[4]
    check(squid.idle is squid.walk, 'missing walk reuses idle (squid)')
    monk = looks[2]
    check(monk.walk is monk.idle is not None and not monk.pray, 'no walk strip: idle in both groups')
    pray = looks[3]
    check(pray.pray and pray.idle is pray.walk and pray.idle.path == 'Monk_pray_strip9.png', 'pray outfit uses the pray strip')
    check(sorted(unused) == ['p/Imp_attack_strip9.png', 'p/Imp_hit_strip9.png'], 'attack and hit are unused')
    check(any('notes.png' in u for u in unmatched) and any('lonely' in u for u in unmatched),
          'unmatched files and creatures without a body reported: %s' % unmatched)
    out, corpses = G.apply_overrides(looks, {})
    check([c.key for c in corpses] == ['p__imp', 'p__squid'], 'corpses only for creatures with a death strip')
    raises(lambda: G.plan(rows + [row('p', 'imp_idle_strip9.png', 576, 64)], packs('p')), 'two idle strips of one creature stop')
    raises(lambda: G.plan([row('p', 'A_idle_strip9.png', 576, 64), row('p', 'A_walk_strip9.png', 288, 32)], packs('p')),
           'idle and walk of different cells stop')
    # fit order: low packs last
    rows2 = [row('lowp', 'A_idle_strip9.png', 576, 64), row('hip', 'B_idle_strip9.png', 576, 64)]
    pk = packs('hip') + packs('lowp', fit='low')
    check([lk.key for lk in G.plan(rows2, pk)[0]] == ['hip__b', 'lowp__a'], 'low-fit packs get the last ids')
    # overrides
    ov = {'p__imp': {'skip': 1}, 'p__monk': {'rename': 'Cult Elder'}}
    out, corpses = G.apply_overrides(G.plan(rows, packs('p'))[0], ov)
    check([lk.key for lk in out] == ['p__ghoul', 'p__monk', 'p__monk_pray', 'p__squid'], 'skip drops the outfit')
    check(out[1].name == 'Cult Elder' and [c.key for c in corpses] == ['p__squid'], 'rename; skip drops the corpse too')
    many = [row('p', 'C%d_idle_strip9.png' % i, 576, 64) for i in range(121)]
    raises(lambda: G.apply_overrides(G.plan(many, packs('p'))[0], {}), 'more than 120 outfits stop')
    many = [row('p', 'C%d_idle_strip9.png' % i, 576, 64) for i in range(26)] + \
           [row('p', 'C%d_death_strip9.png' % i, 576, 64) for i in range(26)]
    raises(lambda: G.apply_overrides(G.plan(many, packs('p'))[0], {}), 'more than 25 corpses stop')


# ------------------------------------------------------------------------------------------------ sheets
def cells(sheet, tw, th, nrows):
    """{(row, dir): cell} of an outfit sheet; dir 0 n, 1 e, 2 s, 3 w"""
    W, H = tw * 32, th * 32
    return {(r, d): sheet[r * H:(r + 1) * H, d * W:(d + 1) * W] for r in range(nrows) for d in range(4)}


def test_sheet():
    # a box x 10..30, y 8..40 in 64 px frames: 20 x 32 wide, 2x2 tiles, box right 1 px from the right edge
    idle = [frame(64, 10, 8, 30, 40, 10), frame(64, 12, 8, 30, 40, 11)]
    walk = [frame(64, 10, 10, 30, 42, 20), frame(64, 8, 8, 32, 40, 21), frame(64, 10, 8, 30, 40, 22)]
    sheet, tw, th, margin = G.sheet_of(idle, walk)
    check((tw, th, margin) == (2, 2, 1) and sheet.shape == (5 * 64, 4 * 64, 4), 'size and sheet shape: %s' % (sheet.shape,))
    c = cells(sheet, tw, th, 5)
    alle = np.concatenate([c[(r, 1)][:, :, 3][None] for r in range(5)], 0).any(0)
    ys, xs = np.nonzero(alle)
    ub = P.union_bbox(idle + walk)
    bw, bh = ub[2] - ub[0], ub[3] - ub[1]
    check(xs.max() == 62 and ys.max() == 62, 'east: the union box ends 1 px from the right and bottom edge')
    # every frame and direction uses the same box position (no jitter): the union box corner is the same in all
    check(all(c[(r, d)][:, :, 3].any() for r in range(5) for d in range(4)), 'every cell drawn')
    # east = as drawn
    x0 = 64 - 1 - bw
    y0 = 64 - 1 - bh
    src = idle[0][ub[1]:ub[3], ub[0]:ub[2]]
    check(np.array_equal(c[(0, 1)][y0:y0 + bh, x0:x0 + bw], src), 'east is the strip as drawn (face r)')
    # west = mirror
    mir = P.mirror(idle[0])
    mb = P.union_bbox([P.mirror(f) for f in idle + walk])
    check(np.array_equal(c[(0, 3)][y0:y0 + bh, x0:x0 + bw], mir[mb[1]:mb[3], mb[0]:mb[2]]), 'west is the mirror')
    check(not np.array_equal(c[(0, 1)], c[(0, 3)]), 'east and west differ')
    # north reuses east, south reuses west
    check(np.array_equal(c[(2, 0)], c[(2, 1)]) and np.array_equal(c[(2, 2)], c[(2, 3)]), 'north = east, south = west')
    # frames differ over phases (walk rows follow idle rows)
    check(not np.array_equal(c[(0, 1)], c[(1, 1)]) and not np.array_equal(c[(2, 1)], c[(3, 1)]), 'phases differ')
    # flip: the strip faces left, so east is the mirror
    s2, *_ = G.sheet_of(idle, walk, flip=1)
    c2 = cells(s2, 2, 2, 5)
    check(np.array_equal(c2[(0, 1)], c[(0, 3)]) and np.array_equal(c2[(0, 3)], c[(0, 1)]), 'flip swaps east and west')
    check(np.array_equal(c2[(0, 0)], c2[(0, 1)]), 'flip: north follows the new east')
    # face=l is the same as flip
    s3, *_ = G.sheet_of(idle, walk, face='l')
    check(np.array_equal(s3, s2), 'face l = flip')
    s3b, *_ = G.sheet_of(idle, walk, face='l', flip=1)
    check(np.array_equal(s3b, sheet), 'face l and flip cancel')
    # ns=w: north takes the west picture, south the east one
    s4, *_ = G.sheet_of(idle, walk, ns='w')
    c4 = cells(s4, 2, 2, 5)
    check(np.array_equal(c4[(0, 0)], c[(0, 3)]) and np.array_equal(c4[(0, 2)], c[(0, 1)])
          and np.array_equal(c4[(0, 1)], c[(0, 1)]), 'ns=w swaps north and south')
    # dx dy shift the whole box
    s5, *_ = G.sheet_of(idle, walk, dx=-3, dy=-2)
    c5 = cells(s5, 2, 2, 5)
    ys5, xs5 = np.nonzero(np.concatenate([c5[(r, 1)][:, :, 3][None] for r in range(5)], 0).any(0))
    check(xs5.max() == 59 and ys5.max() == 60, 'dx, dy move the box')
    raises(lambda: G.sheet_of(idle, walk, dx=40), 'a shift out of the canvas stops')
    # a creature identical in both groups (idle reused for walk) has the same rows
    s6, *_ = G.sheet_of(idle, idle)
    check(s6.shape == (4 * 64, 4 * 64, 4) and np.array_equal(s6[:2 * 64], s6[2 * 64:]), 'idle reused for walk')
    # tiles override
    s7, tw7, th7, _ = G.sheet_of(idle, walk, tiles=(3, 3))
    check((tw7, th7) == (3, 3) and s7.shape == (5 * 96, 4 * 96, 4), 'tiles override')
    # a tiny creature in a 64 px frame is still 1x1 (box 10 x 12 + margin)
    small = [frame(64, 20, 20, 30, 32, 5)]
    check(G.sheet_of(small, small)[1:3] == (1, 1), 'small box: 1x1')
    # a box filling the cell keeps the source size with no margin
    full = [frame(64, 0, 0, 64, 64, 9)]
    sf, twf, thf, mf = G.sheet_of(full, full)
    check((twf, thf, mf) == (2, 2, 0) and sf.shape == (2 * 64, 4 * 64, 4), 'full cell: source size, margin 0')
    # 32 px cells -> 1x1; 128 px cell -> 4x4
    sk = [frame(32, 4, 4, 20, 31, 5)]
    check(G.sheet_of(sk, sk)[1:3] == (1, 1), '32 px cell: 1x1')
    big = [frame(128, 5, 5, 120, 126, 5)]
    check(G.sheet_of(big, big)[1:3] == (4, 4), '128 px cell: 4x4')
    raises(lambda: G.sheet_of([np.zeros((64, 64, 4), np.uint8)], [np.zeros((64, 64, 4), np.uint8)]), 'empty strip stops')
    # soft alpha under 12 is cleared before the box is taken
    a = frame(64, 20, 20, 30, 32, 5)
    a[0, 0] = (1, 1, 1, 5)
    fr = G.cut_frames(strip([a]), row('p', 'A_idle_strip1.png', 64, 64))
    check(P.alpha_bbox(fr[0]) == (20, 20, 30, 32), 'faint pixels do not widen the box')
    raises(lambda: G.cut_frames(strip([a, a]), row('p', 'A_idle_strip9.png', 128, 64)), 'frame count must match the name')


def test_corpse():
    death = [frame(64, 10, 30, 40, 50, 1), frame(64, 6, 36, 50, 56, 2)]
    c, s = G.corpse_of(death[-1])
    check(s == 2 and c.shape == (64, 64, 4), 'corpse canvas')
    ys, xs = np.nonzero(c[:, :, 3])
    check(xs.max() == 62 and ys.max() == 62 and (xs.max() - xs.min() + 1, ys.max() - ys.min() + 1) == (44, 20),
          'corpse: last frame, box 1 px inside bottom right')
    check(G.corpse_of(frame(32, 2, 10, 20, 24, 3))[1] == 1, '32 px death frame: 1x1')


# ------------------------------------------------------------------------------------------------ tables and import layout
def build_fixture():
    files = {}
    rows = []

    def add(slug, path, frames):
        a = strip(frames)
        files[(slug, path)] = a
        rows.append(P.FileRow(slug, path, 1, 'x' * 32, a.shape[1], a.shape[0]))

    add('p', 'Imp_idle_strip2.png', [frame(64, 10, 8, 30, 40, 10), frame(64, 12, 8, 30, 40, 11)])
    add('p', 'Imp_walk_strip3.png', [frame(64, 10, 10, 30, 42, 20), frame(64, 8, 8, 32, 40, 21), frame(64, 10, 8, 30, 40, 22)])
    add('p', 'Imp_death_strip2.png', [frame(64, 10, 30, 40, 50, 1), frame(64, 6, 36, 50, 56, 2)])
    add('p', 'Imp_attack_strip2.png', [frame(64, 0, 0, 5, 5, 1)] * 2)
    add('p', 'Monk_idle_strip2.png', [frame(64, 14, 6, 30, 44, 30), frame(64, 14, 7, 30, 44, 31)])
    add('p', 'Monk_pray_strip2.png', [frame(64, 14, 10, 30, 44, 40), frame(64, 14, 12, 30, 44, 41)])
    add('p', 'Rat_idle_strip2.png', [frame(32, 4, 8, 24, 30, 50), frame(32, 4, 9, 24, 30, 51)])
    add('p', 'Rat_death_strip2.png', [frame(32, 4, 14, 26, 30, 60), frame(32, 3, 20, 28, 31, 61)])
    return rows, files


def test_tables():
    rows, files = build_fixture()
    pk = packs('p')
    looks, _u, _m = G.plan(rows, pk)
    looks, corpses = G.apply_overrides(looks, {})
    load = lambda r: files[(r.slug, r.path)]  # noqa: E731
    sheets, sizes = G.render(looks, corpses, load, {})
    check(sorted(sheets) == ['p__imp', 'p__imp_corpse', 'p__monk', 'p__monk_pray', 'p__rat', 'p__rat_corpse'],
          'sheet names: %s' % sorted(sheets))
    check(sizes['p__rat'] == (1, 1) and sizes['p__imp'] == (2, 2) and sizes['p__rat_corpse'] == (1, 1), 'sizes')
    text = G.things_text(G.things_rows(looks, corpses, sizes))
    check(text == G.things_text(G.things_rows(looks, corpses, sizes)), 'things text deterministic')
    lines = text.splitlines()
    check(lines[0] == ','.join(G.FIELDS), 'things header')
    check(lines[1].startswith('p__imp,outfit,creature,Imp,pack30_strips/p__imp,0,0,2,2,4,2+3,,new,,layers=1|gtypes=0+1|'
                              'exact=64+64|durs0=110:110/110:110|durs1=110:110/110:110/110:110|anim0=0:0:0|anim1=0:0:0|'
                              'family=p'), 'outfit row: %s' % lines[1])
    check(any(ln.startswith('p__imp_corpse,item,corpse,dead imp,pack30_strips/p__imp_corpse,0,0,2,2,1,1,'
                            'container forceuse notmoveable,new') for ln in lines), 'corpse row')
    check([ln.split(',')[10] for ln in lines[1:4]] == ['2+3', '2+2', '2+2'], 'phases: walk reused from idle')
    check(sums_ok(sheets), 'sums text sorted and one line per sheet')
    src = G.sources_text(looks, corpses, pk)
    check(src.splitlines()[0] == 'name,kind,pack,source,licence' and 'set30 mutter,p/Imp_idle_strip2.png' in src
          and 'p__imp_corpse,corpse,set30 mutter,p/Imp_death_strip2.png' in src, 'sources csv')
    check(src.count('p__monk,outfit') == 1 and 'Monk_pray' in src, 'a reused strip is listed once')
    # the importer reads the table and the sheet layout
    import import_art_things as I
    with tempfile.TemporaryDirectory() as td:
        G.write_sheets(sheets, os.path.join(td, 'pack30_strips'))
        open(os.path.join(td, 'things.csv'), 'w', newline='').write(text)
        check(open(os.path.join(td, 'pack30_strips', '.gitignore')).read() == G.GITIGNORE_TEXT, 'sheet folder ignores itself')
        I.ATLAS_DIR[0] = td
        I._atlas.clear()
        its = I.read_things(os.path.join(td, 'things.csv'))
        outs = [r for r in its if r['cat'] == 'outfit']
        check(len(outs) == 4 and len(its) == 6, 'importer parses the rows')
        for r in outs:
            lay = I.OutfitLayout(r)
            fr = I.outfit_frames(r, lay)
            check(lay.layers == 1 and lay.gtypes == (0, 1) and len(fr) == sum(lay.phases) * 4, 'layout %s' % r['key'])
            check(len(lay.anim) == 2 and all(an is None or len(an[3]) == 2 * n for an, n in zip(lay.anim, lay.phases)),
                  'durations %s' % r['key'])
        imp = outs[0]
        fr = I.outfit_frames(imp)
        check(np.array_equal(fr[(0, 0, 1, 0, 0, 0)], sheets['p__imp'][0:64, 64:128]), 'importer cell = east of phase 0')
        check(np.array_equal(fr[(1, 2, 3, 0, 0, 0)], sheets['p__imp'][(2 + 2) * 64:(2 + 3) * 64, 192:256]),
              'importer cell = west of the last walk phase')
        item = I.item_frames(its[-1])
        check(len(item[0]) == 1, 'corpse item has one frame')


def sums_ok(sheets):
    t = G.sums_of(sheets)
    lines = t.splitlines()
    return len(lines) == len(sheets) and [ln.split('  ')[1] for ln in lines] == \
        ['pack30_strips/%s.png' % k for k in sorted(sheets)] and t == G.sums_of(dict(reversed(list(sheets.items()))))


def main():
    for t in (test_names, test_plan, test_sheet, test_corpse, test_tables):
        t()
    print('gen_pack30_strips_test: %d checks passed' % len(OK))


if __name__ == '__main__':
    main()
