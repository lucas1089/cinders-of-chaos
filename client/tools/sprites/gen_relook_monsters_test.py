#!/usr/bin/env python3
"""Test of gen_relook_monsters.py (O768): python3 -I client/tools/sprites/gen_relook_monsters_test.py

The committed table, sums, words, pictures, monsters and map against the rules (each rule with a failing case); the committed pictures
build as the table and the sums say (every frame rule, the O728 lean); `drop_import` of a synthetic upright PixelLab v3 drop (rotations,
a walk of 8 plus the standing frame_000, an idle of 4, drawn here upright): the pictures come out sheared to the game's angle, the idle is
the drop's own, a drop without an idle in every direction gets the script breath; `build` / `live` on a small synthetic input pair (first
id 3): the new outfits 3x3, idle 4 of 300 ms and walk 8 of 100 ms, the same bytes twice, an input pair of another outfit count or another
dat md5 and an existing output folder refused, `live` against other sums. Needs numpy and Pillow (the fx venv of CI). Nothing drawn here is
art of anyone."""
import csv
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
import gen_relook_monsters as A  # noqa: E402
import gen_wst_outfits_test as WT  # noqa: E402
from datspr import Dat  # noqa: E402
from import_outfits import parse_body  # noqa: E402

failed = 0


def check(cond, what):
    global failed
    if not cond:
        failed += 1
        print('FAIL', what)


def upright(seed, di, i):
    """an 80 x 80 upright figure of our own (a block body on two legs, hard alpha): the v3 view, not at the game's angle"""
    rng = np.random.default_rng(seed * 100 + di * 10 + i)
    a = np.zeros((80, 80, 4), np.uint8)
    x = 22 + 2 * di
    a[8:56, x:x + 28, :3] = rng.integers(30, 220, (48, 28, 3))
    a[8:56, x:x + 28, 3] = 255
    for lx in (x + 3 + (i % 2), x + 19 - (i % 2)):
        a[56:76, lx:lx + 6, :3] = 60
        a[56:76, lx:lx + 6, 3] = 255
    return a


def drop(root, name, seed, idle=True):
    """root/name/: an unzipped PixelLab v3 download (STATE/rotations, STATE/animations/walk/DIR/frame_000..008, idle/DIR/frame_000..003)"""
    st = os.path.join(root, name, 'Idle')
    os.makedirs(os.path.join(st, 'rotations'))
    for di, d in enumerate(A.D.DIRS):
        Image.fromarray(upright(seed, di, 0), 'RGBA').save(os.path.join(st, 'rotations', d + '.png'))
        for anim, n in (('walk', 9), ('idle', 4)):
            if anim == 'idle' and not (idle or d == 'south'):
                continue
            os.makedirs(os.path.join(st, 'animations', anim, d))
            for i in range(n):
                Image.fromarray(upright(seed + (1 if anim == 'walk' else 2), di, i), 'RGBA').save(
                    os.path.join(st, 'animations', anim, d, 'frame_%03d.png' % i))


def write_csv(path, rows_):
    with open(path, 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, list(rows_[0]), lineterminator='\n')
        w.writeheader()
        w.writerows(rows_)


def main():
    # ---- the committed files
    check(A.problems() == [], 'committed table: %s' % A.problems())
    check(A.words_problems() == [], 'words: %s' % A.words_problems())
    check(A.monster_problems() == [], 'monsters: %s' % A.monster_problems())
    check(A.write_map(check=True) == [], 'monster_relook_looks.csv is current')
    check([r[2] for r in A.map_rows()] == [3744, 3745, 3746, 1041, 3280], 'the map: outfits 3744-3746, then the stock looks')
    check([r[1] for r in A.map_rows()] == [2687, 1049, 567, 1041, 3183], 'the old looks are the committed pool looks')
    t = A.rows()
    check([int(r['new']) for r in t] == [3744, 3745, 3746], 'outfits 3744..3746 after the 3,743 of pair 85')
    check(A.FIRST_NEW == 3744 and A.PAIR == 86, 'pair 86 from outfit 3744')
    check(all(r['tiles'] == '3x3' and r['lean'] == '0.00' and r['scale'] == '1.00' and (r['idle'], r['walk']) == ('4', '8') for r in t),
          'every look 3x3, committed at the angle, idle 4 and walk 8')
    check(A.built_problems() == [], 'the committed pictures build as the table: %s' % A.built_problems())
    sys.path.insert(0, os.path.join(A.REPO, 'server', 'tools'))
    import client_pair
    check(client_pair.PAIR_RELOOK_MONSTERS == A.PAIR, 'client_pair.PAIR_RELOOK_MONSTERS is the pair of the outfits')
    check(client_pair.PAIR_RELOOK_BODY == A.PAIR_BODY == 89, 'client_pair.PAIR_RELOOK_BODY is the pair of the body alignment (O770)')
    check(sorted(A.read_sums(A.OLD_SUMS)) == ['3744', '3745', '3746'] and not set(A.read_sums(A.OLD_SUMS).values()) & set(A.read_sums().values()),
          'the pair 86 form of the three outfits is kept for relook and differs from the new one')

    tmp = tempfile.mkdtemp(prefix='o768test')
    try:
        # ---- failing cases of the rules
        check(any('new id' in x for x in A.problems([dict(t[0], new='3800')] + t[1:])), 'a wrong id')
        check(any('sums' in x for x in A.problems(t, {k: v for k, v in list(A.read_sums().items())[1:]})), 'sums naming other outfits')
        check(any('rows' in x for x in A.problems(t[::-1])), 'rows out of order')
        check(any('redraw is never sheared' in x for x in A.problems([dict(t[0], lean='0.25')] + t[1:])), 'a sheared redraw row')
        ws = list(csv.DictReader(open(A.WORDS, newline='', encoding='utf-8')))
        pw = os.path.join(tmp, 'w.csv')
        for bad_w, text in ((dict(ws[0], monster='Nobody'), 'gives'), (dict(ws[0], pixellab_id='x'), 'pixellab_id'),
                            (dict(ws[0], description='a knight'), 'dark fantasy')):
            write_csv(pw, [bad_w] + ws[1:])
            check(any(text in x for x in A.words_problems(pw)), 'words rule %s' % text)
        write_csv(pw, ws[::-1])
        check(any('MONSTERS' in x for x in A.words_problems(pw)), 'words out of order')
        old = A.D.G.old_looks()
        lv = A.D.P.pool_levels()
        check(any('no row of the bounty pool' in x for x in A.monster_problems({k: v for k, v in old.items() if k != 'Banshee'}, lv)),
              'a monster the pool does not know')
        check(any('not a hunt monster' in x for x in A.monster_problems(old, {k: v for k, v in lv.items() if k != 'Hellhound'})),
              'a monster off the hunt list')
        check(any('a look of pair 85' in x for x in A.monster_problems(dict(old, Werelion=3800), lv)), 'a committed look above pair 85')

        # ---- strays: an island of 3 px or fewer goes, the body stays
        pic = upright(1, 2, 0)
        pic[2, 2] = (200, 200, 200, 255)
        pic[2:4, 70] = (200, 200, 200, 255)
        cleaned, gone = A.drop_strays(pic)
        check(gone == 3 and not cleaned[2, 2, 3] and not cleaned[2, 70, 3] and np.array_equal(cleaned, upright(1, 2, 0)),
              'drop_strays takes the two islands, nothing of the body')

        # ---- a synthetic upright PixelLab drop -> pictures at the game's angle
        dr = os.path.join(tmp, 'drop')
        drop(dr, 'alpha', 4)
        drop(dr, 'beta', 6, idle=False)
        root = os.path.join(tmp, 'root')
        logs = []
        check(A.drop_import(dr, {'alpha': 'alpha', 'beta': 'beta'}, root, log=logs.append) == ['alpha', 'beta'], 'drop-import both keys')
        check('idle pixellab' in logs[0] and 'idle breath' in logs[1], 'the drop idle when every direction has one, else the breath: %s' % logs)
        got = sorted(os.listdir(os.path.join(root, 'alpha')))
        check(got == sorted(A.D.STANDING + ('idle', 'walk')), 'standing pictures, idle and walk: %s' % got)
        south = np.array(Image.open(os.path.join(root, 'alpha', 'south.png')))
        ln = A.L.lean(south)
        check(ln is not None and A.L.LEAN[0] <= ln <= A.L.LEAN[1], 'the south picture leans %s px: at the angle' % ln)
        check(A.L.lean(upright(4, 2, 0)) < A.L.LEAN[0], 'the drop itself is upright')
        check(all(A.drop_strays(np.array(Image.open(os.path.join(dp, f))))[1] == 0 for dp, _d, fs in os.walk(os.path.join(root, 'alpha'))
                  for f in fs), 'no stray in the imported pictures')
        check(len(os.listdir(os.path.join(root, 'alpha', 'idle', 'south'))) == 4 and
              len(os.listdir(os.path.join(root, 'alpha', 'walk', 'west'))) == 8, 'idle 4 and walk 8 frames')
        check(A.body_problems(root, ('alpha', 'beta')) == [], 'drop-import puts every idle and walk on the standing picture by the body: %s'
              % A.body_problems(root, ('alpha', 'beta')))

        # ---- O770: idle and walk on the standing picture by the body (the Banshee's idle stood 8 px off its walk facing north)
        pd = A.read_pictures('alpha', root)
        check(abs(A.body_x(pd['stand']['south']) - A.body_x(pd['idle']['south'][0])) <= A.BODY_TOL, 'body_x of the idle is the standing one')
        legs = np.zeros((80, 80, 4), np.uint8)
        legs[10:40, 30:40] = (90, 90, 90, 255)                # the body
        legs[40:70, 20:24] = (60, 60, 60, 255)                # a leg far out: the feet column moves, the body column does not
        legs[40:70, 44:48] = (60, 60, 60, 255)
        check(abs(A.body_x(legs) - 34.5) < 1e-9, 'body_x reads the upper half only (%.1f)' % A.body_x(legs))
        for dn in A.L.DROP_DIRS:
            pd['walk'][dn] = [A.L.moved(a, -6, 0) for a in pd['walk'][dn]]
            pd['idle'][dn] = [A.L.moved(a, 3, 0) for a in pd['idle'][dn]]
        A.write_pictures('alpha', pd, root)
        bad = A.body_problems(root, ('alpha',))
        check(len(bad) == 8 and any('walk north body stands -6.0 px' in x for x in bad) and any('idle south body stands +3.0 px' in x for x in bad),
              'body_problems names a walk 6 px left and an idle 3 px right: %s' % bad)
        moves = A.realign(('alpha',), root, log=lambda *_: None)['alpha']
        check(moves[('walk', 'north')] == 6 and moves[('idle', 'east')] == -3, 'realign moves them back: %s' % moves)
        check(A.body_problems(root, ('alpha',)) == [] and not any(A.realign(('alpha',), root, log=lambda *_: None)['alpha'].values()),
              'after realign the bodies stand on the standing picture, a second run moves nothing')
        check(A.body_problems() == [], 'the committed pictures stand on their standing pictures: %s' % A.body_problems())

        want = ((None, 'alpha', 'redraw'), (None, 'beta', 'redraw'))
        ms = A.measured(root, want, first=3)
        tbl = [r for r, _p in ms]
        sums = A.D.pack_sums(ms)
        check([(r['new'], r['tiles'], r['lean'], r['idle'], r['idle_ms'], r['walk'], r['walk_ms']) for r in tbl] ==
              [('3', '3x3', '0.00', '4', '300', '8', '100'), ('4', '3x3', '0.00', '4', '300', '8', '100')], 'the rows: %s' % tbl)

        # ---- the pair
        odat, ospr = WT.input_pair(tmp)
        out = os.path.join(tmp, 'out')
        new = A.build(odat, ospr, out, root, want, first=3, dat_md5=None, log=lambda *_: None)
        check(new == [3, 4], 'new ids %s' % new)
        paths = (os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr'))
        d = Dat(paths[0])
        check(len(d.outfits) == 4, 'two old outfits and two new')
        g0, g1 = parse_body(d, d.outfit(3))
        check((g0.phases, g1.phases, (g0.w, g0.h)) == (4, 8, (3, 3)), 'idle 4, walk 8, 3x3')
        check(g0.anim == (0, 0, 0, (300, 300) * 4) and g1.anim == (0, 0, 0, (100, 100) * 8), 'durations')
        quiet = dict(log=lambda *_: None)
        check(A.live(*paths, table=tbl, sums=sums, first=3, **quiet) == [], 'live passes')
        check(A.live(*paths, table=tbl, sums={**sums, '4': '0' * 64}, first=3, **quiet) != [], 'live: other sums')
        check(A.live(odat, ospr, table=tbl, sums=sums, first=3, **quiet) != [], 'live: a pair without the outfits')
        out2 = os.path.join(tmp, 'again')
        A.build(odat, ospr, out2, root, want, first=3, dat_md5=None, log=lambda *_: None)
        check(open(paths[0], 'rb').read() == open(os.path.join(out2, 'Tibia.dat'), 'rb').read() and
              open(paths[1], 'rb').read() == open(os.path.join(out2, 'Tibia.spr'), 'rb').read(), 'same pair twice')
        # ---- O770 relook: a pair built from pictures off by the body is rewritten in place as the realigned pictures build
        root2 = os.path.join(tmp, 'root2')
        shutil.copytree(root, root2)
        for key in ('alpha', 'beta'):
            pd2 = A.read_pictures(key, root2)
            pd2['walk']['north'] = [A.L.moved(a, -5, 0) for a in pd2['walk']['north']]
            A.write_pictures(key, pd2, root2)
        ms_old = A.measured(root2, want, first=3)
        old_out = os.path.join(tmp, 'old')
        A.build(odat, ospr, old_out, root2, want, first=3, dat_md5=None, log=lambda *_: None)
        old_sums = A.D.pack_sums(ms_old)
        A.realign(('alpha', 'beta'), root2, log=lambda *_: None)
        ms_new = A.measured(root2, want, first=3)
        t_new, s_new = [r for r, _p in ms_new], A.D.pack_sums(ms_new)
        check(old_sums != s_new, 'the shifted walk builds other outfits')
        rel = os.path.join(tmp, 'rel')
        p_old = (os.path.join(old_out, 'Tibia.dat'), os.path.join(old_out, 'Tibia.spr'))
        got = A.relook(*p_old, rel, table=t_new, sums=s_new, old=old_sums, root=root2, log=lambda *_: None)
        p_rel = (os.path.join(rel, 'Tibia.dat'), os.path.join(rel, 'Tibia.spr'))
        check(got == [3, 4] and A.live(*p_rel, table=t_new, sums=s_new, first=3, **quiet) == [], 'relook rewrites both outfits, live passes')
        check(A.relook(*p_rel, os.path.join(tmp, 'rel2'), table=t_new, sums=s_new, old=old_sums, root=root2, log=lambda *_: None) == []
              and not os.path.exists(os.path.join(tmp, 'rel2')), 'relook of a pair already in the new form writes nothing')
        try:
            A.relook(*p_old, os.path.join(tmp, 'rel3'), table=t_new, sums=s_new, old={}, root=root2, log=lambda *_: None)
        except SystemExit as e:
            check('neither' in str(e), 'relook refuses a pair in neither form: %s' % e)
        else:
            check(False, 'relook did not refuse a pair in neither form')

        for args, kw, text in (((odat, ospr, out, root, want), dict(first=3, dat_md5=None), 'exists'),
                               ((odat, ospr, os.path.join(tmp, 'o2'), root, want), dict(first=5, dat_md5=None), 'pair 85'),
                               ((odat, ospr, os.path.join(tmp, 'o3'), root, want), dict(first=3), 'md5'),
                               ((odat, ospr, os.path.join(tmp, 'o4'), root, ((None, 'ghost', 'redraw'),)), dict(first=3, dat_md5=None),
                                'no redraw character')):
            try:
                A.build(*args, log=lambda *_: None, **kw)
            except SystemExit as e:
                check(text in str(e), 'refusal %s: %s' % (text, e))
            else:
                check(False, 'build did not refuse: ' + text)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    check(A.main(['build', 'a', 'b']) == 2 and A.main(['nothing']) == 2, 'usage')
    print('gen_relook_monsters_test: %s' % ('ok' if not failed else '%d failed' % failed))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
