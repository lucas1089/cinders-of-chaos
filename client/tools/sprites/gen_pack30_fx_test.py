#!/usr/bin/env python3
"""python3 -I client/tools/sprites/gen_pack30_fx_test.py : gen_pack30_fx.py on synthetic generated images only (no pack
image is read), an import with import_fx_art.py (--lua-out, --catalog-out) into a tiny synthetic pair, plus the committed
tables (spec, sources, sums, flask table) against the pick list. Needs numpy and Pillow (fx venv)."""
import csv
import json
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import check_pair_test as CT  # noqa: E402
import gen_pack30_fx as G  # noqa: E402
import pack30lib as P  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def raises(fn, what, text=None):
    try:
        fn()
    except P.PackError as e:
        check(text is None or text in str(e), '%s (message %r)' % (what, str(e)))
        return
    check(False, what + ' (no error)')


def box(cell, x0, y0, x1, y1, rgb):
    a = np.zeros((cell, cell, 4), np.uint8)
    a[y0:y1, x0:x1] = rgb + (255,)
    return a


def strip_of(frames):
    return np.concatenate(frames, axis=1)


# ------------------------------------------------------------------------------------------------ the pick list
def test_picks():
    pk = G.picks()
    ids = G.ids_of(pk)
    eff = [p for p in pk if G.kind_of(p) == 'effect']
    mis = [p for p in pk if G.kind_of(p) == 'missile']
    check(len(eff) == 25 and len(mis) == 3, 'twenty-five effects, three missiles: %d %d' % (len(eff), len(mis)))
    check([ids[p.name] for p in eff] == list(range(830, 855)), 'effect ids 830..854 in pick order')
    check([ids[p.name] for p in mis] == [186, 187, 188], 'missile ids 186..188')
    check(len({p.name for p in pk}) == 28, 'names are unique')
    check([p.kind for p in eff] == ['burst'] * 12 + ['circle'] * 9 + ['splash'] * 4, 'effect kinds in plan order')
    G.check_blocks(pk)
    # no name is used by another catalogue
    cats = os.path.normpath(os.path.join(HERE, '..', '..', '..', 'server', 'data', 'spells'))
    mine = {p.name for p in pk}
    for fn in sorted(os.listdir(cats)):
        if fn.endswith('_catalog.csv') and fn != 'pack30_fx_catalog.csv':
            with open(os.path.join(cats, fn), newline='', encoding='utf-8') as f:
                for r in csv.DictReader(f):
                    check(r.get('name') not in mine, '%s: name %s already used' % (fn, r.get('name')))


def test_overflow():
    pk = G.picks()
    extra = G.Pick('burst', 'mfx_extra', 'magic_fx', 'X_strip17.png', 60, 'x')
    raises(lambda: G.check_blocks(pk + [extra]), 'a 26th effect stops', '26 effects')
    raises(lambda: G.check_blocks(pk + [G.Pick('flask', 'f4', 'potions', 'p/tira.png', 0, 'x')]),
           'a 4th missile stops', '4 missiles')
    try:
        G.check_blocks(pk + [extra])
    except P.PackError as e:
        check('overflow' in str(e) and '830' in str(e) and '854' in str(e), 'the message names the block and the overflow')


# ------------------------------------------------------------------------------------------------ pixels
def test_effect_strip():
    # 64 px frames, art 20 x 20 at the frame centre, last two frames empty
    fr = [box(64, 22, 22, 42, 42, (10 * i + 10, 20, 30)) for i in range(5)] + [np.zeros((64, 64, 4), np.uint8)] * 2
    strip, w, h, n, dx, dy = G.effect_strip('t', fr, (10, 8))
    check(n == 6, 'trailing empty frames dropped, one empty frame appended: %d' % n)
    # the frame centre (32, 32) goes to (10, 8) of the target tile: the art (22..42) spans x 0..20, y -2..18, so one
    # tile wide and two high with the target tile at the bottom
    check((w, h, dx, dy) == (1, 2, 0, 0), 'size: %s' % ((w, h, dx, dy),))
    W = w * 32
    ys, xs = np.nonzero(strip[:, :W, 3])
    left, top = w - 1 - dx, h - 1 - dy
    off_x, off_y = left * 32 + 10 - 32, top * 32 + 8 - 32
    check(xs.min() == 22 + off_x and ys.min() == 22 + off_y, 'art placed with the frame centre on the point')
    check(not strip[:, (n - 1) * W:, 3].any() and all(strip[:, i * W:(i + 1) * W, 3].any() for i in range(n - 1)),
          'the last frame is empty, the others are not')
    # a big art needs 3x3: 62 px box around the centre at the tile centre
    big = [box(64, 1, 1, 63, 63, (9, 9, 9))] * 3
    strip, w, h, n, dx, dy = G.effect_strip('b', big, (16, 16))
    check((w, h, dx, dy, n) == (3, 3, 1, 1, 4), 'a 64 px burst on the tile centre is 3x3 with offset 1,1: %s' % ((w, h, dx, dy, n),))
    check(strip.shape == (96, 96 * 4, 4) and (strip[:, :96, 3] > 0).sum() == 62 * 62, 'no pixel lost')
    # leading empty frames are dropped too
    strip, w, h, n, dx, dy = G.effect_strip('l', [np.zeros((64, 64, 4), np.uint8)] + big, (16, 16))
    check(n == 4, 'leading empty frame dropped')
    raises(lambda: G.effect_strip('e', [fr[0], np.zeros((64, 64, 4), np.uint8), fr[1]], (10, 8)), 'empty frame inside', 'inside')
    raises(lambda: G.effect_strip('z', [np.zeros((64, 64, 4), np.uint8)] * 2, (10, 8)), 'no visible frame', 'no visible')
    raises(lambda: G.effect_strip('x', [box(128, 0, 0, 128, 128, (1, 2, 3))], (16, 16)), 'more than 3x3 stops', 'limit')


def test_hard_alpha():
    a = np.zeros((2, 2, 4), np.uint8)
    a[0, 0] = (5, 6, 7, 127)
    a[0, 1] = (5, 6, 7, 128)
    a[1, 0] = (5, 6, 7, 255)
    h = G.hard_alpha(a)
    check(h[0, 0].tolist() == [0, 0, 0, 0] and h[0, 1].tolist() == [5, 6, 7, 255] and h[1, 0, 3] == 255, 'alpha cut at 128')
    raises(lambda: G.frames_of(np.zeros((64, 1000, 4), np.uint8), 'f'), 'a strip of whole frames', 'whole frames')
    raises(lambda: G.frames_of(np.zeros((64, 640, 4), np.uint8), 'f', 9), 'frame count', '10 frames, expected 9')


def sheet_fixture(cell=64):
    """a 3x3 sheet: each non-centre cell a different coloured box; the centre empty; and the eight single files"""
    cells, singles = {}, {}
    for (x, y), d in G.MISSILE_DIR.items():
        if (x, y) == (1, 1):
            cells[(x, y)] = np.zeros((cell, cell, 4), np.uint8)
            continue
        c = box(cell, 8 + 3 * x, 10 + 2 * y, 40 + 3 * x, 30 + 4 * y, (40 + 20 * x, 60 + 30 * y, 90 + 10 * (x + y)))
        cells[(x, y)] = c
        singles[d] = c
    sheet = np.zeros((3 * cell, 3 * cell, 4), np.uint8)
    for (x, y), c in cells.items():
        sheet[y * cell:(y + 1) * cell, x * cell:(x + 1) * cell] = c
    return sheet, singles


def test_sheet():
    sheet, singles = sheet_fixture()
    cells = G.sheet_cells(sheet, 64)
    check(np.array_equal(cells[(1, 1)], cells[(1, 2)]) and cells[(1, 1)][..., 3].any(), 'the empty centre repeats the south cell')
    check(np.array_equal(cells[(0, 0)], sheet[:64, :64]), 'cells keep their pixels')
    check(G.check_sheet_layout(sheet, 64, singles) == [], 'layout equals the single files')
    bad = dict(singles)
    bad['ne'] = singles['nw']
    check(len(G.check_sheet_layout(sheet, 64, bad)) == 1 and 'ne' in G.check_sheet_layout(sheet, 64, bad)[0], 'a swapped file is found')
    check(any('no single' in b for b in G.check_sheet_layout(sheet, 64, {'n': singles['n']})), 'a missing single file is found')
    raises(lambda: G.sheet_cells(sheet[:, :190], 64), 'not 3x3 cells', 'not 3x3')
    s2 = sheet.copy()
    s2[64:128, 64:128] = box(64, 20, 20, 30, 30, (1, 1, 1))
    raises(lambda: G.sheet_cells(s2, 64), 'centre cell with art', 'centre cell holds art')
    s3 = sheet.copy()
    s3[:64, :64] = 0
    raises(lambda: G.sheet_cells(s3, 64), 'an empty direction cell', 'is empty')
    # patterns of the sheet: one phase; pattern (x, y) holds the cell (x, y)
    pats = {k: [v] for k, v in cells.items()}
    strip, w, h, n, dx, dy = G.missile_strip('m', pats, (32, 32))
    check((n, w, h, dx, dy) == (1, 2, 2, 0, 0), 'sheet size and offset: %s' % ((n, w, h, dx, dy),))
    W, H = w * 32, h * 32
    check(strip.shape == (3 * H, 3 * W, 4), 'missile strip shape %s' % (strip.shape,))
    for (x, y), v in pats.items():
        got = (strip[y * H:(y + 1) * H, x * W:(x + 1) * W, 3] > 0).sum()
        check(got == (v[0][..., 3] > 0).sum(), 'pattern %s keeps every pixel' % ((x, y),))
    # the art centre (32, 32) is on tile point (13, 13): the pattern (0, 0) box 8..40 x 10..34 shifts by (13 - 32) + (w-1-dx... )
    sx, sy = (w - 1 - dx) * 32 + 13 - 32, (h - 1 - dy) * 32 + 13 - 32
    ys, xs = np.nonzero(strip[:H, :W, 3])
    check(xs.min() == 8 + sx and ys.min() == 10 + sy, 'the cell centre is put on the missile point (13, 13)')


def test_flask():
    frames = [box(32, 5, 7, 28, 27, (30 + i, 40, 50)) for i in range(8)]
    pats = G.flask_patterns(frames)
    check(len(pats) == 9 and all(len(v) == 8 for v in pats.values()), 'nine cells of eight frames')
    check(all(np.array_equal(pats[(0, 0)][i], pats[(2, 2)][i]) for i in range(8)), 'the same strip in every direction')
    strip, w, h, n, dx, dy = G.missile_strip('f', pats, (16, 16))
    check((w, h, dx, dy, n) == (1, 1, 0, 0, 8), 'a 23 x 20 flask is 1x1 with 8 phases: %s' % ((w, h, dx, dy, n),))
    check(strip.shape == (96, 3 * 32 * 8, 4), 'strip shape')
    raises(lambda: G.missile_strip('f', {(0, 0): frames}, (16, 16)), 'patterns must be 3x3', '3 x 3')
    pats[(1, 1)] = frames[:4]
    raises(lambda: G.missile_strip('f', pats, (16, 16)), 'equal frame counts', '3 x 3')


def test_timing():
    meta = {'ms': [60] * 14, 'repete': [0, 13], 'quadro': [64, 64]}
    check(G.timing_of(meta, 't', 14, 64) == 60, 'one value')
    raises(lambda: G.timing_of({'ms': [60, 50]}, 't', 2, 64), 'mixed timing', 'not one value')
    raises(lambda: G.timing_of(meta, 't', 12, 64), 'frame count', '14 frames')
    raises(lambda: G.timing_of(meta, 't', 14, 32), 'cell size', 'frames of')
    raises(lambda: G.timing_of({}, 't', 14, 64), 'no timing', 'not one value')


# ------------------------------------------------------------------------------------------------ flask table
def montagem():
    plus = [[0, 1, 0], [1, 3, 1], [0, 1, 0]]
    disc = [[0, 1, 1, 1, 0], [1, 1, 1, 1, 1], [1, 1, 3, 1, 1], [1, 1, 1, 1, 1], [0, 1, 1, 1, 0]]
    out = {}
    for el, proj, ex in (('lava', SHEET_DIR, 'efeitos/fogo_esparramado_v'), ('veneno', 'the flask itself', 'efeitos/bomba_veneno_v')):
        out[el + '_health'] = dict(projetil=proj, explosao=ex + '1', area=[[3]])
        out[el + '_strong'] = dict(projetil=proj, explosao=ex + '1', area=plus)
        out[el + '_great'] = dict(projetil=proj, explosao=ex + '4', area=disc)
    return out


SHEET_DIR = G.SHEET_DIR


def synthetic_rows():
    rows = []
    for p in G.picks():
        k = dict(kind=G.kind_of(p), name=p.name, file='%s/%s.png' % (G.ATLAS_DIR, p.name), w=3, h=3, phases=5, ms=60,
                 dx=1, dy=1, note='x')
        if p.name in ('potion_flask_lava', 'potion_flask_poison'):
            k.update(w=1, h=1, dx=0, dy=0, phases=8, ms=125)
        rows.append(k)
    return rows


def test_potions():
    rows = synthetic_rows()
    d = G.potions_data(rows, montagem())
    check([f['key'] for f in d['flasks']] == ['lava_small', 'lava_medium', 'lava_large', 'venom_small', 'venom_medium', 'venom_large'],
          'six flasks in element and size order: %s' % [f['key'] for f in d['flasks']])
    f = {x['key']: x for x in d['flasks']}
    check(f['lava_large']['burst'] == 'fire_splash_b' and f['lava_small']['burst'] == 'fire_splash_a', 'lava bursts')
    check(f['venom_small']['burst'] == 'poison_burst_a' and f['venom_large']['burst'] == 'poison_burst_b', 'venom bursts')
    check(f['lava_medium']['missile'] == 'potion_lava' and f['venom_medium']['missile'] == 'potion_flask_poison', 'projectiles')
    check(f['lava_small']['flask_missile'] == 'potion_flask_lava', 'own flask missile')
    check(f['lava_small']['area'] == [[3]] and len(f['venom_large']['area']) == 5, 'area patterns kept')
    check(d['bursts']['fire_splash_a']['id'] == 851 and d['missiles']['potion_flask_poison']['id'] == 188, 'ids from the spec order')
    check(d['bursts']['fire_splash_a']['total_ms'] == 5 * 60, 'total ms')
    text = G.potions_text(d)
    check(json.loads(text) == d and text.endswith('}\n') and text.isascii(), 'canonical ascii json')
    bad = montagem()
    bad['lava_health']['area'] = [[1]]
    raises(lambda: G.potions_data(rows, bad), 'area without a centre', 'area pattern')
    bad = montagem()
    bad['lava_health']['area'] = [[0, 3], [1, 1]]
    raises(lambda: G.potions_data(rows, bad), 'even area', 'area pattern')
    bad = montagem()
    bad['lava_health']['explosao'] = 'efeitos/unknown'
    raises(lambda: G.potions_data(rows, bad), 'unknown burst', 'not one of')
    bad = montagem()
    bad['fire_health'] = bad.pop('lava_health')
    raises(lambda: G.potions_data(rows, bad), 'unknown flask key', 'unknown flask key')
    check(G.area_ok([[3]]) and not G.area_ok([]) and not G.area_ok([[3, 3, 3]]) and not G.area_ok([[0, 1, 0], [1, 3], [0, 1, 0]]),
          'area_ok')


# ------------------------------------------------------------------------------------------------ whole pipeline
class Fixture:
    """a temp drivepacks folder with a synthetic file for every pick, and the matching FileRow list"""

    def __init__(self):
        self.dir = tempfile.mkdtemp(prefix='g30fx_')
        self.rows = []

    def put(self, slug, path, data, w='', h=''):
        full = os.path.join(self.dir, slug, *path.split('/'))
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, 'wb') as f:
            f.write(data)
        self.rows.append(P.FileRow(slug, path, str(len(data)), P.file_md5(full), str(w), str(h)))
        return full

    def png(self, slug, path, arr):
        full = self.put(slug, path, b'')
        self.rows.pop()
        Image.fromarray(arr, 'RGBA').save(full)
        self.rows.append(P.FileRow(slug, path, str(os.path.getsize(full)), P.file_md5(full), str(arr.shape[1]), str(arr.shape[0])))
        return full


def fixture():
    fx = Fixture()
    for i, p in enumerate(G.picks()):
        if p.kind in ('burst', 'circle'):
            n = int(p.path.rsplit('strip', 1)[1].split('.')[0])
            # frames grow; a burst has two empty frames at the end
            fr = [box(64, 8, 8, 20 + 2 * j, 20 + 2 * j, (20 + i, 40 + j, 60)) if j < n - 2 or p.kind == 'circle'
                  else np.zeros((64, 64, 4), np.uint8) for j in range(n)]
            fx.png(p.slug, p.path, strip_of(fr))
        elif p.kind == 'splash':
            cell = 32 if p.name == 'poison_burst_a' else 64
            n = 12 if cell == 32 else 14
            fx.png(p.slug, p.path, strip_of([box(cell, 2, 2, 4 + j, 4 + j, (50, 60 + j, 70)) for j in range(n)]))
            d = p.path.rsplit('/', 1)[0]
            fx.put(p.slug, d + '/animacao.json', json.dumps({'ms': [60] * n, 'repete': [0, n - 1], 'quadro': [cell, cell]}).encode())
        elif p.kind == 'flask':
            fx.png(p.slug, p.path, strip_of([box(32, 5, 7, 28, 27, (30 + j, 40, 50)) for j in range(8)]))
            d = p.path.rsplit('/', 1)[0]
            fx.put(p.slug, d + '/animacao.json', json.dumps({'ms': [125] * 8, 'repete': [0, 7], 'quadro': [32, 32]}).encode())
    sheet, singles = sheet_fixture()
    fx.png('potions', G.SHEET_FILE, sheet)
    for fn, d in G.SHEET_DIRS.items():
        fx.png('potions', '%s/%s.png' % (G.SHEET_DIR, fn), singles[d])
    fx.put('potions', G.MONTAGEM, json.dumps(montagem()).encode())
    return fx


def test_render_and_import():
    fx = fixture()
    pk = G.picks()
    src = G.Source(fx.dir, {}, fx.rows)
    rows, strips = G.render(pk, src)
    check(len(rows) == 28 and [r['name'] for r in rows] == [p.name for p in pk], 'one row per pick, in order')
    r0, r12 = rows[0], rows[12]
    check(r0['phases'] == 16 and r0['ms'] == 60 and r12['phases'] == 10 and r12['ms'] == 110,
          'burst: 15 visible frames + 1 empty; circle: 9 + 1 (%d, %d)' % (r0['phases'], r12['phases']))
    check([rows[i]['phases'] for i in (21, 23, 24)] == [15, 13, 15] and rows[23]['ms'] == 60,
          'splash phases from the strip, ms from its timing file')
    check(rows[25]['kind'] == 'missile' and rows[25]['phases'] == 1 and rows[26]['phases'] == 8 and rows[26]['ms'] == 125,
          'missiles')
    for r, s in zip(rows, strips):
        check(G.G.check_strip(r, s) == [], '%s: strip passes the shape check' % r['name'])
    # the texts are deterministic
    rows2, strips2 = G.render(pk, src)
    check(G.spec_text(rows) == G.spec_text(rows2) and G.sums_text(rows, strips) == G.sums_text(rows2, strips2),
          'a second render gives the same tables')
    check(G.spec_text(rows).splitlines()[0] == 'kind,name,file,w,h,phases,ms,dx,dy,note', 'spec header is the importer format')
    # a changed file is refused by its md5
    p0 = os.path.join(fx.dir, 'magic_fx', pk[0].path)
    with open(p0, 'ab') as f:
        f.write(b'x')
    raises(lambda: G.render(pk[:1], src), 'md5 mismatch', 'md5')
    # a file missing from the list
    raises(lambda: G.Source(fx.dir, {}, []).load('magic_fx', pk[1].path), 'unlisted file', 'not in pack30_fx.files')
    # the sheet checked against singles: a wrong single file stops the render
    fx2 = fixture()
    sp = os.path.join(fx2.dir, 'potions', G.SHEET_DIR, 'ne.png')
    Image.fromarray(box(64, 0, 0, 5, 5, (9, 9, 9)), 'RGBA').save(sp)
    fx2.rows = [r if (r.slug, r.path) != ('potions', G.SHEET_DIR + '/ne.png')
                else P.FileRow(r.slug, r.path, str(os.path.getsize(sp)), P.file_md5(sp), '64', '64') for r in fx2.rows]
    raises(lambda: G.render(pk, G.Source(fx2.dir, {}, fx2.rows)), 'sheet not laid out as the client reads it', 'not laid out')
    # import into a tiny synthetic pair
    rows3 = [dict(r) for r in rows]
    tmp = tempfile.mkdtemp(prefix='g30fx_imp_')
    for r, s in zip(rows3, strips):
        full = os.path.join(tmp, 'art', r['name'] + '.png')
        os.makedirs(os.path.dirname(full), exist_ok=True)
        Image.fromarray(s, 'RGBA').save(full)
        r['file'] = os.path.relpath(full, G.ART)
    spec = os.path.join(tmp, 'spec.csv')
    with open(spec, 'w', encoding='utf-8', newline='') as f:
        f.write(G.spec_text(rows3))
    c = CT.Case()
    recs, items, outfits, effects, missiles = CT.good_parts()
    dat, spr = c.pair(recs, items, outfits, effects, missiles)
    out, lua, cat = os.path.join(tmp, 'out'), os.path.join(tmp, 'ids.lua'), os.path.join(tmp, 'cat.csv')
    res = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'import_fx_art.py'), '--ours-dat', dat, '--ours-spr', spr,
                          '--out-dir', out, '--spec', spec, '--expect-first-effect', '2', '--expect-first-missile', '2',
                          '--lua-out', lua, '--catalog-out', cat], capture_output=True, text=True)
    check(res.returncode == 0, 'import_fx_art accepts the spec: %s' % (res.stdout[-300:] + res.stderr[-600:]))
    if res.returncode == 0:
        text = open(lua, encoding='utf-8').read()
        check('ChaosVfx.mfx_arcane = {id = 2, dx = %d, dy = %d, ms = %d}' % (rows[0]['dx'], rows[0]['dy'], rows[0]['ms'] * rows[0]['phases']) in text,
              'Lua line of the first effect')
        check('ChaosVfx.poison_burst_b = {id = 26,' in text and 'ChaosVfxMissile.potion_lava = {id = 2,' in text
              and 'ChaosVfxMissile.potion_flask_poison = {id = 4,' in text, 'Lua lines of the last effect and the missiles')
        cr = list(csv.DictReader(open(cat, encoding='utf-8')))
        check(len(cr) == 28 and cr[0]['name'] == 'mfx_arcane' and cr[-1]['id'] == '4', 'catalogue rows')
        check('verified' in res.stdout and '28 new things' in res.stdout, 'importer verified the 28 things')
    wrong = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'import_fx_art.py'), '--ours-dat', dat, '--ours-spr', spr,
                            '--out-dir', out + '2', '--spec', spec, '--expect-first-effect', '830'], capture_output=True, text=True)
    check(wrong.returncode != 0, 'a wrong input pair is refused by --expect-first-effect')
    shutil.rmtree(tmp)
    shutil.rmtree(fx.dir)
    shutil.rmtree(fx2.dir)
    shutil.rmtree(c.dir)


# ------------------------------------------------------------------------------------------------ committed tables
def test_committed():
    check(G.cmd_build(None, True) == 0, 'build --check (no sources) passes on the committed tables')
    pk = G.picks()
    packs = P.load_packs()
    rd = list(csv.DictReader(open(G.SPEC, newline='', encoding='utf-8')))
    check([r['name'] for r in rd] == [p.name for p in pk], 'spec names = pick list')
    check(sum(r['kind'] == 'effect' for r in rd) == 25 and sum(r['kind'] == 'missile' for r in rd) == 3, 'spec counts')
    src = list(csv.DictReader(open(G.SOURCES, newline='', encoding='utf-8')))
    labels = {r['pack'] for r in src}
    check(labels == {'set30 mutter', 'set30 potions'}, 'labels used: %s' % labels)
    check(all(not r['source'].startswith('/') for r in src), 'sources are folder/file')
    # no vendor, pack or game name in the tables (tools/ci/check_names.py is the CI gate; a coarse local check)
    blob = ''.join(open(p, encoding='utf-8').read() for p in (G.SPEC, G.SOURCES, G.POTIONS))
    check(('w' + 'st') not in blob.lower() and 'tibia' not in blob.lower(), 'no vendor or game words in the tables')
    check(G.sources_text(pk, packs) == open(G.SOURCES, encoding='utf-8', newline='').read(), 'sources text is the rebuild')
    # block sizes against the plan
    check(G.FIRST_EFFECT == 830 and G.MAX_EFFECTS == 25 and G.FIRST_MISSILE == 186 and G.MAX_MISSILES == 3, 'blocks')


def main():
    test_picks()
    test_overflow()
    test_effect_strip()
    test_hard_alpha()
    test_sheet()
    test_flask()
    test_timing()
    test_potions()
    test_render_and_import()
    test_committed()
    print('gen_pack30_fx_test:', 'ok' if not failed else '%d failed' % failed)
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
