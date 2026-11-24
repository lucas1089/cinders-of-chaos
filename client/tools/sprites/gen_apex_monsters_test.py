#!/usr/bin/env python3
"""Test of gen_apex_monsters.py (O763): python3 -I client/tools/sprites/gen_apex_monsters_test.py

The committed table, sums, words, pictures and monster files against the rules (each rule with a failing case); the committed pictures
build as the table and the sums say (every frame rule, the O728 lean); `drop_import` of a synthetic PixelLab drop (rotations, a walk of
8 plus the standing frame_000, drawn here at the game's angle), `build` / `live` on a small synthetic input pair (first id 3): the new
outfits 3x3, idle 4 of 300 ms and walk 8 of 100 ms, the same bytes twice, an input pair of another outfit count or another dat md5 and an
existing output folder refused, `live` against other sums. Needs numpy and Pillow (the fx venv of CI). Nothing drawn here is art of anyone."""
import csv
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from PIL import Image  # noqa: E402
import gen_apex_monsters as A  # noqa: E402
import gen_drive_monsters_test as DT  # noqa: E402
import gen_wst_outfits_test as WT  # noqa: E402
from datspr import Dat  # noqa: E402
from import_outfits import parse_body  # noqa: E402

failed = 0


def check(cond, what):
    global failed
    if not cond:
        failed += 1
        print('FAIL', what)


def drop(root, name, seed):
    """root/name/: an unzipped PixelLab download of a synthetic figure (STATE/rotations, STATE/animations/walkv3/DIR/frame_000..008)"""
    st = os.path.join(root, name, 'Idle')
    for di, d in enumerate(A.D.DIRS):
        os.makedirs(os.path.join(st, 'rotations'), exist_ok=True)
        os.makedirs(os.path.join(st, 'animations', 'walkv3', d))
        Image.fromarray(DT.figure(seed, di, 0)[8:88, 8:88], 'RGBA').save(os.path.join(st, 'rotations', d + '.png'))
        for i in range(9):
            Image.fromarray(DT.figure(seed + 1, di, i)[8:88, 8:88], 'RGBA').save(
                os.path.join(st, 'animations', 'walkv3', d, 'frame_%03d.png' % i))


def write_csv(path, rows_):
    with open(path, 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, list(rows_[0]))
        w.writeheader()
        w.writerows(rows_)


def main():
    # ---- the committed files
    check(A.problems() == [], 'committed table: %s' % A.problems())
    check(A.words_problems() == [], 'words: %s' % A.words_problems())
    check(A.monster_problems() == [], 'monsters: %s' % A.monster_problems())
    check(A.write_map(check=True) == [], 'monster_apex_looks.csv is current')
    check([r[2] for r in A.map_rows()] == list(range(3734, 3744)) and all(r[1] <= 3733 for r in A.map_rows()),
          'the map: a stand-in look of pair 83, the new look of pair 84')
    t = A.rows()
    check([int(r['new']) for r in t] == list(range(3734, 3744)), 'outfits 3734..3743 after the 3,733 of pair 83')
    check(A.FIRST_NEW == 3734 and A.PAIR == 84, 'pair 84 from outfit 3734')
    check(all(r['tiles'] == '3x3' and r['lean'] == '0.00' and r['scale'] == '1.00' and (r['idle'], r['walk']) == ('4', '8') for r in t),
          'every look 3x3, drawn at the angle, idle 4 and walk 8')
    check(len({m for _k, m, _l, _f in A.MONSTERS}) == 10 and sorted(lv for _k, _m, lv, _f in A.MONSTERS) ==
          [2100, 2100, 2200, 2200, 2300, 2300, 2400, 2400, 2500, 2500], 'ten monsters, two a band of 2100-2500')
    check(A.built_problems() == [], 'the committed pictures build as the table: %s' % A.built_problems())
    sys.path.insert(0, os.path.join(A.REPO, 'server', 'tools'))
    import client_pair
    check(client_pair.PAIR_APEX_MONSTERS == A.PAIR, 'client_pair.PAIR_APEX_MONSTERS is the pair of the outfits')

    tmp = tempfile.mkdtemp(prefix='o763test')
    try:
        # ---- failing cases of the rules
        bad_t = [dict(t[0], new='3800')] + t[1:]
        check(any('new id' in x for x in A.problems(bad_t)), 'a wrong id')
        check(any('sums' in x for x in A.problems(t, {k: v for k, v in list(A.read_sums().items())[1:]})), 'sums naming other outfits')
        check(any('rows' in x for x in A.problems(t[::-1])), 'rows out of order')
        ws = list(csv.DictReader(open(A.WORDS, newline='', encoding='utf-8')))
        pw = os.path.join(tmp, 'w.csv')
        for bad_w, text in ((dict(ws[0], monster='Nobody'), 'gives'), (dict(ws[0], pixellab_id='x'), 'pixellab_id'),
                            (dict(ws[0], description='a knight'), 'dark fantasy')):
            write_csv(pw, [bad_w] + ws[1:])
            check(any(text in x for x in A.words_problems(pw)), 'words rule %s' % text)
        write_csv(pw, ws[::-1])
        check(any('MONSTERS' in x for x in A.words_problems(pw)), 'words out of order')
        mdir = os.path.join(tmp, 'mon')
        shutil.copytree(A.MONSTER_DIR, mdir, ignore=lambda d, fs: [f for f in fs if f.endswith('.xml') and f not in
                                                                   {x for _k, _m, _l, x in A.MONSTERS}])
        check(A.monster_problems(folder=mdir) == [], 'the copied files pass')
        p = os.path.join(mdir, 'umbral_devourer.xml')
        orig = open(p, encoding='utf-8').read()
        for change, to, text in (('type="1532"', 'type="3743"', 'stand-in'), ('min="2480"', 'min="2400"', '<level>')):
            open(p, 'w', encoding='utf-8').write(orig.replace(change, to))
            check(any(text in x for x in A.monster_problems(folder=mdir)), 'monster rule %s' % text)
        open(p, 'w', encoding='utf-8').write(orig.replace('<flag summonable="0"/>', '<flag boss="1"/>'))
        check(any('no boss' in x for x in A.monster_problems(folder=mdir)), 'monster rule boss')
        os.remove(p)
        check(any('no monster file' in x for x in A.monster_problems(folder=mdir)), 'a missing file')
        sw = os.path.join(tmp, 'sw.csv')
        rows_sw = list(csv.DictReader(open(A.SWAPS, newline='', encoding='utf-8')))
        write_csv(sw, [r for r in rows_sw if r['new'] != 'Soot Hangman'])
        check(any('Soot Hangman spawns in no hunt' in x for x in A.monster_problems(swaps=sw)), 'a monster that spawns nowhere')

        # ---- a synthetic PixelLab drop -> the pictures of two keys
        dr = os.path.join(tmp, 'drop')
        drop(dr, 'alpha', 4)
        drop(dr, 'beta', 6)
        root = os.path.join(tmp, 'root')
        check(A.drop_import(dr, ('alpha', 'beta'), root, log=lambda *_: None) == ['alpha', 'beta'], 'drop-import both keys')
        got = sorted(os.listdir(os.path.join(root, 'alpha')))
        check(got == sorted(A.D.STANDING + ('idle', 'walk')), 'standing pictures, idle and walk: %s' % got)
        want = ((None, 'alpha', 'redraw'), (None, 'beta', 'redraw'))
        ms = A.measured(root, want, first=3)
        tbl = [r for r, _p in ms]
        sums = A.D.pack_sums(ms)
        check([(r['new'], r['tiles'], r['idle'], r['idle_ms'], r['walk'], r['walk_ms']) for r in tbl] ==
              [('3', '3x3', '4', '300', '8', '100'), ('4', '3x3', '4', '300', '8', '100')], 'the rows: %s' % tbl)

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
        for args, kw, text in (((odat, ospr, out, root, want), dict(first=3, dat_md5=None), 'exists'),
                               ((odat, ospr, os.path.join(tmp, 'o2'), root, want), dict(first=5, dat_md5=None), 'pair 83'),
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
    print('gen_apex_monsters_test: %s' % ('ok' if not failed else '%d failed' % failed))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
