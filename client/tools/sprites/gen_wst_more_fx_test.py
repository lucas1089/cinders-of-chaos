#!/usr/bin/env python3
"""Tests of gen_wst_more_fx.py (O735): the committed table, sums, ids file, tags and catalog; the element by name and hue;
the cut (empty frames, equal frames merged with their time, a loop cut to close or left out, the one-shot blank end); the
house rules (mesh, stray pixels, art cut by the pack frame, no art); the placement (a heading never moved, an off-centre
effect moved onto the tile); discover on synthetic metadata and catalog sets (a set unknown by its digest is not read, a
variant pair 36 took is not taken again); the pair step on a synthetic pair of 5,441 effects and 253 missiles (append at
5442.., live, a changed pixel, the same bytes twice, refusals). No purchased art and no real pair:
python3 -I client/tools/sprites/gen_wst_more_fx_test.py (numpy, Pillow)."""
import hashlib
import io
import json
import os
import shutil
import sys
import tempfile
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_wst_more_fx as G  # noqa: E402

N = [0]


def ok(cond, msg):
    N[0] += 1
    if not cond:
        raise SystemExit('FAIL: ' + msg)


def quiet(fn, *a):
    buf = io.StringIO()
    with redirect_stdout(buf):
        try:
            rc = fn(*a)
        except SystemExit as e:
            rc = e.code if isinstance(e.code, int) else 1
            buf.write(str(e.code))
    return rc, buf.getvalue()


def test_committed():
    rows = G.read_spec()
    ok(rows and G.table_errors(rows) == [], 'the committed table holds its rules: %s' % G.table_errors(rows)[:3])
    ok(int(rows[0]['id']) == 5442 == G.FIRST, 'the first new effect is 5442, after effect 5441 of pair 81')
    ok(G.read_total() == [len(rows)], 'the total row records the count')
    ok(list(G.read_sums()) == [r['name'] for r in rows], 'one sum per effect, in order')
    ok(quiet(G.check)[0] == 0, 'check passes on the repository')
    heads = {}
    for r in rows:
        if r['dir']:
            heads.setdefault(r['name'][:-len(r['dir']) - 1], []).append(r['dir'])
    ok(all(v == G.OUR_DIRS for v in heads.values()), 'every heading set has its 8 headings in order')
    ok(all(r['tag'] in ('any', r['element']) for r in rows), 'a tag is the element of the name or any')
    for p in (G.SPEC, G.SUMS, G.LUA, G.CATALOG, os.path.join(HERE, 'gen_wst_more_fx.py')):
        text = open(p).read().lower()
        ok(not G.names_pack(text), 'no pack name in ' + os.path.basename(p))
    for p in (G.SPEC, G.SUMS, G.LUA, G.CATALOG):
        ok('.png' not in open(p).read().lower(), 'no picture file name in ' + os.path.basename(p))
    bad = [dict(r) for r in rows[:3]]
    bad[1]['id'] = '9'
    ok(G.table_errors(bad), 'a hole in the ids is found')
    bad = [dict(r) for r in rows[:3]]
    bad[0]['src'] = 'sheet.png'
    ok(G.table_errors(bad), 'src must be 12 hex')
    bad = [dict(r) for r in rows[:3]]
    bad[0]['eid'] = 'uib_your_turn'
    ok(G.table_errors(bad), 'a picture of words is refused')
    hd = [r for r in rows if r['dir']][:8]
    if hd:
        ok(G.table_errors([dict(r, id=str(G.FIRST + i)) for i, r in enumerate(hd[:7])]), 'a heading set short of one heading')


def test_element():
    ok(G.name_element('', 'blood', 'impact_physical_strike') == 'death', 'the variant before the effect id')
    ok(G.name_element('fire', '', 'frost_cone') == 'fire', 'the pack element field first')
    ok(G.name_element('', '', 'ethereal_breath') == 'arcane', 'a word of the id')
    ok(G.name_element('', '', 'big_round_thing') == '', 'no element word')
    ok(G.tag_of('fire', (20, 0.8, 150)) == 'fire', 'an orange fire is fire')
    ok(G.tag_of('fire', (210, 0.8, 150)) == 'any', 'a blue "fire" is any')
    ok(G.tag_of('ice', (200, 0.6, 180)) == 'ice' and G.tag_of('ice', (0, 0.05, 220)) == 'ice', 'blue or white ice')
    ok(G.tag_of('', (20, 0.8, 150)) == 'any', 'no name element: any, never a guess from the hue alone')


def blob(fw, fh, cx, cy, r, rgb=(255, 128, 0)):
    import numpy as np
    ys, xs = np.indices((fh, fw))
    d = np.sqrt((xs + 0.5 - cx) ** 2 + (ys + 0.5 - cy) ** 2)
    a = np.zeros((fh, fw, 4), np.uint8)
    a[..., 0], a[..., 1], a[..., 2] = rgb
    a[..., 3] = (np.clip(1.25 - d / r, 0, 1) * 255).astype(np.uint8) if r > 0 else 0
    a[a[..., 3] == 0] = 0
    return a


def test_cut_and_rules():
    import numpy as np
    import gen_pack27_fx as P
    f = [P.clean_alpha(blob(64, 64, 32, 32, r)) for r in (0, 10, 10, 14, 0, 18, 0)]
    fr, durs, why = G.cut(f, 83, False)
    ok(not why and len(fr) == 3 and durs == [166, 83, 83], 'empty frames dropped, an equal frame merged: %s' % durs)
    loop = [P.clean_alpha(blob(64, 64, 32, 32, r)) for r in (8, 11, 14, 17, 20, 23, 26, 29)]
    fr, durs, why = G.cut(loop, 83, True)
    ok(not why and len(fr) < 8 and G.loop_ratio(fr) <= G.LOOP_RATIO, 'a growing loop is cut to a range that closes (%d)' % len(fr))
    cyc = [P.clean_alpha(blob(64, 64, 32, 32, r)) for r in (10, 14, 18, 14)]
    fr, _d, why = G.cut(cyc, 83, True)
    ok(not why and len(fr) == 4, 'a loop that closes is kept whole')
    jump = [P.clean_alpha(blob(64, 64, 32, 32, 10 + i)) for i in range(11)]
    ok(G.cut(jump, 83, True)[2] == 'loop_jump', 'a loop that jumps back is out')
    ok(G.cut([P.clean_alpha(blob(64, 64, 32, 32, 10 + i % 20)) for i in range(60)], 83, False)[2] == 'too_long', 'too many phases')
    ok(G.cut([np.zeros((32, 32, 4), np.uint8)] * 3, 83, False)[2] == 'no_art', 'no art')
    good = [P.clean_alpha(blob(64, 64, 32, 32, r)) for r in (10, 14)]
    ok(G.quality(good, 0) == '', 'a solid blob passes')
    ok(G.quality(good, 12) == 'clipped', 'art cut by the pack frame is out')
    mesh = np.zeros((64, 64, 4), np.uint8)
    mesh[::2, ::2] = (200, 50, 50, 255)
    mesh[1::2, 1::2] = (200, 50, 50, 255)
    ok(G.quality([mesh, mesh], 0) == 'mesh', 'a checker mesh is out')
    stray = np.zeros((64, 64, 4), np.uint8)
    stray[::4, ::4] = (90, 200, 90, 255)
    ok(G.quality([stray, stray], 0) == 'stray', 'scattered single pixels are out')
    ok(G.quality([P.clean_alpha(blob(64, 64, 32, 32, 2))], 0) == 'no_art', 'almost nothing left after the cut')
    ok(set(np.unique(good[0][..., 3]).tolist()) <= {0, 255}, 'the cut is hard: alpha 0 / 255')
    bar = np.zeros((32, 32, 4), np.uint8)
    bar[10:22, 0:32] = (200, 200, 50, 255)                      # art from the left border to the right border of its tile
    strip, w, h, dx, dy = G.strip_of([bar, bar], (0, 0), (0, 0), False, 'bar')
    ok((w, h, dx, dy) == (3, 1, 1, 0), 'art along the canvas border gets a tile more on that side: %s' % ((w, h, dx, dy),))
    ok(max(max(G.border_runs(strip[:, i * 96:(i + 1) * 96, 3])) for i in range(2)) < G.EDGE_RUN, 'no art run on the border')
    ok(G.strip_of([np.concatenate([bar] * G.MAX_TILES, 1)], (0, 0), (0, 0), False, 'wide') is None,
       'more than MAX_TILES after the border tile: out')


PACK_TEXT = 'synthetic set'


def write_meta(root):
    """a metadata set: one non-directional effect off the tile centre, one 8 heading cone, one with words"""
    from PIL import Image
    import numpy as np
    os.makedirs(os.path.join(root, 'fontes', 'cones'))
    os.makedirs(os.path.join(root, 'art', 'oblique', '32px', 'spells'))
    effects = []

    def sheet(eid, rows, loop, frames=6, directional=False):
        img = np.concatenate([np.concatenate(fr, 1) for fr in rows], 0)
        rel = 'oblique/32px/spells/%s.png' % eid
        Image.fromarray(img).save(os.path.join(root, 'art', rel))
        effects.append(dict(id=eid, category='spells', loop=loop, fps=12, frames=frames,
                            directions=['E', 'SE', 'S', 'SW', 'W', 'NW', 'N', 'NE'] if directional else None,
                            element='fire' if 'fire' in eid else None,
                            variants={'oblique/32': dict(frame_w=96, frame_h=96, anchor_tile=[1, 1], rows=len(rows),
                                                         files={'all': rel})}))
    sheet('fire_ring', [[blob(96, 96, 74, 48, r) for r in (0, 8, 12, 16, 12, 0)]], False)
    heads = []
    for k in range(8):
        dx, dy = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)][k]
        heads.append([blob(96, 96, 48 + 14 * dx, 48 + 14 * dy, r, (90, 160, 255)) for r in (6, 9, 12, 9, 6, 0)])
    sheet('frost_cone', heads, False, directional=True)
    sheet('uib_your_turn', [[blob(96, 96, 48, 48, 10)] * 6], False)
    json.dump(dict(pack=PACK_TEXT, family='cones', tile=32, effects=effects),
              open(os.path.join(root, 'fontes', 'cones', 'metadata.json'), 'w'))


def write_catalog(root, taken_var):
    """a 64 px catalog set: an impact in two colours (one of them pair 36's), a text piece"""
    from PIL import Image
    import numpy as np
    cat = [dict(id='impact_test', category='impacts', variants=['steel', taken_var]),
           dict(id='text_test', category='text', variants=['gold'])]
    os.makedirs(os.path.join(root, 'fontes'))
    json.dump(cat, open(os.path.join(root, 'fontes', 'catalog.json'), 'w'))
    for v in ('steel', taken_var):
        d = os.path.join(root, 'fontes', 'sheets', '64px', 'impacts', 'impact_test', v)
        os.makedirs(d)
        fr = [blob(192, 192, 112, 112, r, (200, 200, 210)) for r in (0, 20, 30, 40, 30)]
        Image.fromarray(np.concatenate(fr, 1)).save(os.path.join(root, 'sheet_%s_full.png' % v))
        json.dump(dict(id='impact_test', variant=v, loop=False, fps=16, tile_size=64, frame_width=192, frame_height=192,
                       pivot=[112, 112], anchor_tile=[1, 1], layers=['main'], directions=[],
                       sheets={'full': 'sheet_%s_full.png' % v}), open(os.path.join(d, 'impact_test_%s.json' % v), 'w'))


def test_discover_and_convert():
    tmp = tempfile.mkdtemp(prefix='wstmore_test_')
    meta = dict(G.META_SETS)
    try:
        write_meta(os.path.join(tmp, 'm'))
        _d, sources = G.taken()
        taken_var = next(s.split('/')[1] for s in sorted(sources) if s.count('/') == 1)
        write_catalog(os.path.join(tmp, 'c'), taken_var)
        found = G.discover([os.path.join(tmp, 'm'), os.path.join(tmp, 'c')])
        ok(not [s for s in found if s.set != 'mv'], 'an unknown set (by the digest of its name) is not read')
        G.META_SETS[hashlib.sha256(PACK_TEXT.encode()).hexdigest()[:12]] = 'm3'
        found = G.discover([os.path.join(tmp, 'm'), os.path.join(tmp, 'c')])
        names = sorted((s.set, s.eid, s.var) for s in found)
        ok(('m3', 'fire_ring', '') in names and ('m3', 'frost_cone', '') in names, 'the metadata set is found: %s' % names)
        ok(not [s for s in found if s.eid == 'text_test'], 'text pictures are not candidates')
        ok(G.worded('uib_your_turn') and not G.worded('fire_ring'), 'a piece of words is known by its name')
        ring = next(s for s in found if s.eid == 'fire_ring')
        got, why = G.convert(ring)
        ok(not why and len(got) == 1, 'the ring converts: %s' % why)
        r, strip = got[0]
        ok((r['mx'], r['my']) == (-26, 0), 'an effect 26 px right of the tile middle is moved onto it: %s' % ((r['mx'], r['my']),))
        ok(r['tag'] == 'fire' and r['element'] == 'fire', 'an orange fire ring is fire')
        ok(not strip[:, -int(r['w']) * 32:, 3].any() and int(r['phases']) == 5, 'a one-shot ends with a blank phase')
        cone = next(s for s in found if s.eid == 'frost_cone')
        got, why = G.convert(cone)
        ok(not why and [x['dir'] for x, _ in got] == G.OUR_DIRS, 'a cone is 8 effects n..nw')
        ok(all((x['mx'], x['my']) == (0, 0) for x, _ in got), 'a heading is never moved')
        ok(all(x['tag'] == 'ice' for x, _ in got), 'a blue frost cone is ice')
        imp = [s for s in found if s.eid == 'impact_test']
        ok(len(imp) == 2, 'both colours are candidates before the pair 36 filter')
        got, why = G.convert(next(s for s in imp if s.var == 'steel'))
        ok(not why and got[0][0]['element'] == 'physical' and got[0][0]['tag'] == 'physical', 'grey steel is physical')
        ok(int(got[0][0]['ms']) == 62, 'the 64 px set plays 16 a second')
        again, _ = G.convert(ring)
        ok(G.digest(again[0][1]) == G.digest(G.convert(ring)[0][0][1]), 'the same sheet gives the same strip')
    finally:
        G.META_SETS.clear()
        G.META_SETS.update(meta)
        shutil.rmtree(tmp, ignore_errors=True)


def synthetic_pair(effects=5441, missiles=253, blank=()):
    import numpy as np
    import import_art_things as iat
    import check_pair_test as T
    recs = [iat.encode_sprite(np.full((32, 32, 4), 200, np.uint8)), iat.encode_sprite(np.full((32, 32, 4), 90, np.uint8))]
    items = [T.entry(bytes([17]), [T.group([1])])]
    effs = [T.entry(b'', [T.group([0 if i + 1 in blank else 2])]) for i in range(effects)]
    miss = [T.entry(b'', [T.group([1] * 9, px=3, py=3)]) for _ in range(missiles)]
    outfits = [T.entry(b'', [T.group([1] * 4, px=4, gtype=0)], outfit=True)]
    return T.Case().pair(recs, items, outfits, effs, miss)


def test_pair_step():
    from datspr import Dat
    tmp = tempfile.mkdtemp(prefix='wstmore_pair_')
    keep = (G.SPEC, G.SUMS, dict(G.META_SETS))
    try:
        write_meta(os.path.join(tmp, 'm'))
        G.META_SETS[hashlib.sha256(PACK_TEXT.encode()).hexdigest()[:12]] = 'm3'
        G.SPEC, G.SUMS = os.path.join(tmp, 't.csv'), os.path.join(tmp, 't.sums')
        dat, spr = synthetic_pair()
        o1 = os.path.join(tmp, 'o1')
        rc, out = quiet(G.build, dat, spr, o1, [os.path.join(tmp, 'm')], True, 1)
        ok(rc == 0 and 'live: 9 effects at 5442..5450, OK' in out, 'build and live: ' + out[-400:])
        ok('out words' in out, 'the piece of words is reported out')
        od, nd = Dat(dat), Dat(os.path.join(o1, 'Tibia.dat'))
        ok(len(nd.effects) == 5450 and len(nd.missiles) == 253, '9 effects appended, no missile')
        ok(all(nd.data[a.raw[0]:a.raw[1]] == od.data[b.raw[0]:b.raw[1]] for a, b in zip(nd.effects[:5441], od.effects)),
           'the old effects are byte-identical')
        rows = G.read_spec()
        ok([r['name'] for r in rows][:1] == ['m3_fire_ring'] and len(rows) == 9, 'table order: %s' % [r['name'] for r in rows])
        o2 = os.path.join(tmp, 'o2')
        rc, out = quiet(G.build, dat, spr, o2, [os.path.join(tmp, 'm')], False, 1)
        ok(rc == 0, 'the committed table matches a second build: ' + out[-300:])
        ok(open(os.path.join(o1, 'Tibia.spr'), 'rb').read() == open(os.path.join(o2, 'Tibia.spr'), 'rb').read(), 'the same bytes twice')
        lines = open(G.SUMS).read().splitlines()
        open(G.SUMS, 'w').write('\n'.join(['0' * 64 + lines[0][64:]] + lines[1:]) + '\n')
        rc, out = quiet(G.live, os.path.join(o1, 'Tibia.dat'), os.path.join(o1, 'Tibia.spr'))
        ok(rc == 1 and 'pixels differ from the sum' in out, 'live: a changed pixel is found')
        for k, (e, m, blank) in enumerate([(5440, 253, ()), (5442, 253, ()), (5441, 252, ()), (5441, 253, (5400,))]):
            d2, s2 = synthetic_pair(e, m, blank)
            rc, out = quiet(G.build, d2, s2, os.path.join(tmp, 'r%d' % k), [os.path.join(tmp, 'm')], False, 1)
            ok(rc == 1 and 'refused' in out, 'refused: %d effects, %d missiles, blank %s' % (e, m, blank))
        rc, out = quiet(G.live, dat, spr)
        ok(rc == 1 and 'the pair has 5441 effects' in out, 'live: the input pair fails')
    finally:
        G.SPEC, G.SUMS = keep[0], keep[1]
        G.META_SETS.clear()
        G.META_SETS.update(keep[2])
        shutil.rmtree(tmp, ignore_errors=True)


def test_server_files():
    rows = G.read_spec()
    ok(open(G.LUA).read() == G.lua_text(rows), 'chaos_wst_more_fx_ids.lua is up to date')
    ok('pair = 82, first = 5442, count = %d' % len(rows) in G.lua_text(rows), 'pair, first and count in the ids file')
    tags = G.tags_text(rows)
    ok(open(G.TAGS, newline='').read() == tags, 'the tags are up to date')
    ok('372,fire_nova,fire\n' in tags, 'the other tag rows stay')
    ok(open(G.CATALOG).read() == G.catalog_text(rows), 'the catalog is up to date')
    head = open(G.CATALOG).readline().strip()
    ok(head == 'id,name,family,element,shape,size,frames,play', 'catalog columns: ' + head)


def main():
    test_element()
    test_committed()
    test_server_files()
    try:
        import numpy  # noqa: F401
        from PIL import Image  # noqa: F401
    except ImportError:
        print('gen_wst_more_fx_test: numpy / Pillow missing, the art tests are skipped')
        print('gen_wst_more_fx_test: %d checks OK' % N[0])
        return 0
    test_cut_and_rules()
    test_discover_and_convert()
    test_pair_step()
    print('gen_wst_more_fx_test: %d checks OK' % N[0])
    return 0


if __name__ == '__main__':
    sys.exit(main())
