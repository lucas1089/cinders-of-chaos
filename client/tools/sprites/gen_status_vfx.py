#!/usr/bin/env python3
"""Status layer and kill overlay effects from two purchased packs (O597): a step of pair 73.

    python3 -I gen_status_vfx.py build DAT SPR OUT_DIR --src DIR   # the pair with the effects; DIR holds the downloaded
                                                                   # sheets (any names, any depth: found by digest)
    python3 -I gen_status_vfx.py table --src DIR                   # rewrite art_import/status_vfx.csv (src, frames) and
                                                                   # status_vfx.sums from the sheets
    python3 -I gen_status_vfx.py check                             # CI, no art: the table, the sums, the generated files
    python3 -I gen_status_vfx.py ids [--check]                     # server/data/lib/chaos_status_vfx_ids.lua, the tags of
                                                                   # server/data/spells/spell_fx_elements.csv
    python3 -I gen_status_vfx.py live DAT SPR                      # the pair holds every effect of the table at its id
    python3 -I gen_status_vfx.py strips OUT_DIR --src DIR          # the strips as PNG (previews only, never committed)

No art in the repository (the O540 pattern): the packs' licence forbids passing on the image files, so only the table
art_import/status_vfx.csv (how each sheet is cut: grid, frames, scale, anchor, levels; `src` = the first 12 hex of the
sha256 of the sheet file, no pack name) and the digests status_vfx.sums of the strips that go into the pair are committed.
The sheets are read by this local script only: never sent to a web or AI service. The packs: docs/CREDITS.md.

The pair step: on top of pair 72 or of any later pair that still has at most 5,142 effects. The sibling step (O596, the
spell packs) owns effects 4743..5142; this step's ids are fixed, 5143 onwards in table order. A pair with fewer than
5,142 effects is padded with blank effects (1 tile, no sprite) up to 5142 first; a pair with fewer than 4,742 or more
than 5,142 effects is refused. Missiles are not touched. Inputs are never modified; deterministic.

Status rows (kind `status`, 14 statuses x start / loop / stop): a sheet of 96 x 128 cells (feet at 48, 112) at 30 frames
a second. Every `step`th frame is taken, scaled by `scale` with a premultiplied Lanczos filter and placed on a 64 x 64
canvas (2 x 2 tiles) so that the sheet point (sx, sy) lands on the canvas point (ax, ay); the feet of the creature are
the canvas point (32, 56) (game_statusfx puts the canvas there). Alpha times `gain`, then the style's levels
(docs/SPRITE_STYLE.md): 0.5 and more is solid, `lo` .. 0.5 is the one glow level (alpha 144) with its colour lifted,
below `lo` nothing (this also drops the faint body shadow some sheets carry). `tint` multiplies the colour.
Kill rows (kind `kill`): a strip of 64 x 64 cells, native pixel art of a plain dark body dying. The body is not ours
to draw (the dying monster's own sprite dissolves by a shader, client/tools/gen_kill_dissolve.py); the row's `rule`
keeps what is left: `nobody` drops the body colours, `band:N` keeps only the N rows above the feet line (a puddle,
rubble), `from:N` blanks the frames before N. Placed on a 96 x 64 canvas (3 x 2 tiles, sent at the tile + (1, 0)) with
the pack's feet on the canvas point (48, 56).

Needs numpy and Pillow (the fx venv of CI) for build / table / live / strips; `check` and `ids` are stdlib only.
"""
import argparse
import csv
import hashlib
import io
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
ART = os.path.join(HERE, 'art_import')
TABLE = os.path.join(ART, 'status_vfx.csv')
SUMS = os.path.join(ART, 'status_vfx.sums')
LUA = os.path.join(ROOT, 'server', 'data', 'lib', 'chaos_status_vfx_ids.lua')
TAGS = os.path.join(ROOT, 'server', 'data', 'spells', 'spell_fx_elements.csv')

PAIR = 73
BASE_EFFECTS = 4742          # pair 72
RESERVED_LAST = 5142         # the sibling step's last id
FIRST = RESERVED_LAST + 1    # our first id
PREFIX = 'st_'               # every name of this table starts with it (the tag rows are found by it)
FEET = (32, 56)              # canvas point of the creature's feet on a status canvas
STATUSES = ['burn', 'freeze', 'shock', 'poison', 'curse', 'root', 'soak', 'stun', 'confuse', 'haste', 'bless', 'regen',
            'shield', 'rage']
PARTS = ['start', 'loop', 'stop']
KILLS = ['melt', 'sink', 'bones', 'vapour', 'stone']
ELEMENT = dict(burn='fire', freeze='ice', shock='energy', poison='earth', curse='death', root='earth', soak='ice',
               stun='any', confuse='any', haste='any', bless='holy', regen='holy', shield='arcane', rage='physical')
FIELDS = ['id', 'name', 'kind', 'key', 'part', 'w', 'h', 'phases', 'ms', 'dx', 'dy', 'src', 'cols', 'rows', 'frames',
          'step', 'scale', 'sx', 'sy', 'ax', 'ay', 'gain', 'lo', 'tint', 'rule', 'element', 'note']
INTS = ['id', 'w', 'h', 'phases', 'ms', 'dx', 'dy', 'cols', 'rows', 'frames', 'step', 'sx', 'sy', 'ax', 'ay']
FLOATS = ['scale', 'gain', 'lo']
CELL = (96, 128)             # status sheet cell
KCELL = 64                   # kill strip cell
GLOW = 144                   # the one glow level


# ---------------------------------------------------------------------------------------------------- the table
def read_table(path=None):
    with open(path or TABLE, newline='', encoding='utf-8') as fh:
        rows = list(csv.DictReader(fh))
    for r in rows:
        for k in INTS:
            r[k] = int(r[k])
        for k in FLOATS:
            r[k] = float(r[k])
    return rows


def table_text(rows):
    buf = io.StringIO()
    w = csv.DictWriter(buf, FIELDS, lineterminator='\n')
    w.writeheader()
    for r in rows:
        o = dict(r)
        for k in FLOATS:
            o[k] = ('%.3f' % o[k]).rstrip('0').rstrip('.')
        w.writerow({k: o[k] for k in FIELDS})
    return buf.getvalue()


def table_errors(rows):
    errs = []
    names = [r['name'] for r in rows]
    if len(set(names)) != len(names):
        errs.append('duplicate name')
    for i, r in enumerate(rows):
        if r['id'] != FIRST + i:
            errs.append('%s: id %d, expected %d (fixed ids from %d in table order)' % (r['name'], r['id'], FIRST + i, FIRST))
        if not r['name'].startswith(PREFIX):
            errs.append('%s: name without the %s prefix' % (r['name'], PREFIX))
        if len(r['src']) != 12 or any(c not in '0123456789abcdef' for c in r['src']):
            errs.append('%s: src is not 12 hex' % r['name'])
        if r['kind'] == 'status':
            if r['key'] not in STATUSES or r['part'] not in PARTS:
                errs.append('%s: unknown status or part' % r['name'])
            if (r['w'], r['h'], r['dx'], r['dy']) != (2, 2, 0, 0):
                errs.append('%s: a status canvas is 2 x 2 tiles' % r['name'])
            if r['element'] != ELEMENT.get(r['key']):
                errs.append('%s: element' % r['name'])
        elif r['kind'] == 'kill':
            if r['key'] not in KILLS or r['part'] != 'over':
                errs.append('%s: unknown kill overlay' % r['name'])
            if (r['w'], r['h'], r['dx'], r['dy']) != (3, 2, 1, 0):
                errs.append('%s: a kill canvas is 3 x 2 tiles sent at +1, 0' % r['name'])
            if r['element'] != 'any':
                errs.append('%s: element' % r['name'])
        else:
            errs.append('%s: kind' % r['name'])
        if not 1 <= r['phases'] <= 32 or not 30 <= r['ms'] <= 200:
            errs.append('%s: phases or ms out of range' % r['name'])
        if r['kind'] == 'status' and r['phases'] != len(range(0, r['frames'], r['step'])):
            errs.append('%s: phases is not frames / step' % r['name'])
    have = {(r['key'], r['part']) for r in rows if r['kind'] == 'status'}
    for s in STATUSES:
        for p in PARTS:
            if (s, p) not in have:
                errs.append('status %s has no %s row' % (s, p))
    for k in KILLS:
        if not any(r['kind'] == 'kill' and r['key'] == k for r in rows):
            errs.append('kill overlay %s has no row' % k)
    return errs


def read_sums():
    out = {}
    if os.path.exists(SUMS):
        for line in open(SUMS, encoding='utf-8'):
            d, n = line.strip().split('  ', 1)
            out[n] = d
    return out


# ---------------------------------------------------------------------------------------------------- the art
def digest(strip):
    import numpy as np
    return hashlib.sha256(np.ascontiguousarray(strip).tobytes() + repr(strip.shape).encode()).hexdigest()


def find_sources(src):
    """{12 hex: path} of every PNG under src"""
    out = {}
    for base, _, files in os.walk(src):
        for f in sorted(files):
            if f.lower().endswith('.png'):
                p = os.path.join(base, f)
                with open(p, 'rb') as fh:
                    out[hashlib.sha256(fh.read()).hexdigest()[:12]] = p
    return out


def parse_tint(t):
    return tuple(float(v) for v in t.split(':')) if t else (1.0, 1.0, 1.0)


def levels(pm, gain, lo, tint):
    """premultiplied float RGBA (0..1) -> uint8 RGBA with alpha 0 / GLOW / 255 and the glow colour lifted"""
    import numpy as np
    a = np.clip(pm[..., 3] * gain, 0.0, 1.0)
    rgb = pm[..., :3] / np.maximum(pm[..., 3:4], 1e-4)
    rgb = np.clip(rgb * np.array(tint, np.float32), 0.0, 1.0)
    solid = a >= 0.5
    glow = (a >= lo) & ~solid
    out = np.zeros(pm.shape[:2] + (4,), np.uint8)
    # contrast: solid pixels keep their colour a little deeper, the glow level is lifted toward its brightest channel
    s = np.clip((rgb - 0.5) * 1.15 + 0.5, 0.0, 1.0)
    mx = np.maximum(rgb.max(axis=2, keepdims=True), 1e-4)
    g = np.clip(rgb / mx * np.clip(mx * 1.35 + 0.15, 0.0, 1.0), 0.0, 1.0)
    out[..., :3][solid] = np.round(s[solid] * 255.0)
    out[..., 3][solid] = 255
    out[..., :3][glow] = np.round(g[glow] * 255.0)
    out[..., 3][glow] = GLOW
    return out


def status_frames(sheet, r):
    """the frames of a status row: a list of (64, 64, 4) uint8"""
    import numpy as np
    from PIL import Image
    a = np.asarray(sheet.convert('RGBA')).astype(np.float32) / 255.0
    cw, ch = CELL
    assert a.shape[1] == r['cols'] * cw and a.shape[0] == r['rows'] * ch, (r['name'], a.shape)
    pm = a.copy()
    pm[..., :3] *= pm[..., 3:4]
    tw, th = int(round(cw * r['scale'])), int(round(ch * r['scale']))
    x0 = int(round(r['ax'] - r['sx'] * r['scale']))
    y0 = int(round(r['ay'] - r['sy'] * r['scale']))
    W, H = r['w'] * 32, r['h'] * 32
    tint = parse_tint(r['tint'])
    out = []
    for f in range(0, r['frames'], r['step']):
        cy, cx = divmod(f, r['cols'])
        cell = pm[cy * ch:(cy + 1) * ch, cx * cw:(cx + 1) * cw]
        small = np.stack([np.asarray(Image.fromarray(np.ascontiguousarray(cell[..., c]), 'F').resize((tw, th), Image.LANCZOS))
                          for c in range(4)], axis=2)
        small = np.clip(small, 0.0, 1.0)
        canvas = np.zeros((H, W, 4), np.float32)
        sx0, sy0 = max(0, -x0), max(0, -y0)
        dx0, dy0 = max(0, x0), max(0, y0)
        w = min(tw - sx0, W - dx0)
        h = min(th - sy0, H - dy0)
        if w > 0 and h > 0:
            canvas[dy0:dy0 + h, dx0:dx0 + w] = small[sy0:sy0 + h, sx0:sx0 + w]
        out.append(levels(canvas, r['gain'], r['lo'], tint))
    return out


BODY = ((44, 40, 53), (132, 124, 153), (18, 17, 23))     # the three colours of the kill strips' plain body


def is_body(px):
    """the pixels of the strips' plain body (its fill, its light edge, its outline)"""
    import numpy as np
    m = np.zeros(px.shape[:2], bool)
    for c in BODY:
        m |= (px[..., 0] == c[0]) & (px[..., 1] == c[1]) & (px[..., 2] == c[2])
    return m


def kill_frames(strip, r):
    """the frames of a kill row: a list of (64, 96, 4) uint8"""
    import numpy as np
    a = np.asarray(strip.convert('RGBA')).copy()
    n = a.shape[1] // KCELL
    assert a.shape[0] == KCELL and a.shape[1] == n * KCELL and n == r['frames'], (r['name'], a.shape)
    a[a[..., 3] < 128] = 0
    a[..., 3] = np.where(a[..., 3] > 0, 255, 0)
    rules = dict(x.split(':') if ':' in x else (x, '') for x in r['rule'].split(';') if x)
    first = a[:, :KCELL]
    ys = np.nonzero(first[..., 3].any(axis=1))[0]
    body0 = is_body(first) & (first[..., 3] > 0)
    feet_y = int(np.nonzero(body0.any(axis=1))[0].max()) if body0.any() else int(ys.max())
    xs = np.nonzero(body0.any(axis=0))[0]
    feet_x = int(round((xs.min() + xs.max()) / 2.0)) if len(xs) else KCELL // 2
    W, H = r['w'] * 32, r['h'] * 32
    x0, y0 = r['ax'] - feet_x, r['ay'] - feet_y
    out = []
    for f in range(0, r['frames'], r['step']):
        cell = a[:, f * KCELL:(f + 1) * KCELL].copy()
        if 'from' in rules and f < int(rules['from']):
            cell[:] = 0
        if 'nobody' in rules:
            cell[is_body(cell)] = 0
        if 'band' in rules:
            cell[:max(0, feet_y - int(rules['band']) + 1)] = 0
        canvas = np.zeros((H, W, 4), np.uint8)
        sx0, sy0 = max(0, -x0), max(0, -y0)
        dx0, dy0 = max(0, x0), max(0, y0)
        w = min(KCELL - sx0, W - dx0)
        h = min(KCELL - sy0, H - dy0)
        canvas[dy0:dy0 + h, dx0:dx0 + w] = cell[sy0:sy0 + h, sx0:sx0 + w]
        canvas[canvas[..., 3] == 0] = 0
        out.append(canvas)
    return out


def frames_of(r, sources):
    from PIL import Image
    p = sources.get(r['src'])
    if not p:
        raise SystemExit('%s: no sheet with digest %s under --src' % (r['name'], r['src']))
    img = Image.open(p)
    fr = status_frames(img, r) if r['kind'] == 'status' else kill_frames(img, r)
    assert len(fr) == r['phases'], (r['name'], len(fr), r['phases'])
    assert any(f[..., 3].any() for f in fr), (r['name'], 'no art')
    return fr


def strip_of(frames):
    import numpy as np
    s = np.concatenate(frames, axis=1)
    s[s[..., 3] == 0] = 0
    return s


# ---------------------------------------------------------------------------------------------------- the pair
def apply(dat_path, spr_path, out_dir, rows, frames):
    """write OUT_DIR/Tibia.dat and Tibia.spr: the input pair, blank effects up to RESERVED_LAST, then the rows"""
    import random
    import numpy as np
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr, sprite_index
    from gen_effects import encode_sprite
    from import_vfx import entry_bytes, render_back, tiles_of, T_
    assert os.path.abspath(os.path.dirname(dat_path)) != os.path.abspath(out_dir), 'OUT_DIR must differ from the input folder'
    od, ospr = Dat(dat_path), Spr(spr_path)
    assert od.variant[0] == 'new' and all(od.variant[1:]), 'expected our 10.98 dat: %r' % (od.variant,)
    assert ospr.u32count and ospr.alpha, 'expected an alpha spr with u32 count'
    ne0, nm0 = len(od.effects), len(od.missiles)
    if ne0 < BASE_EFFECTS or ne0 > RESERVED_LAST:
        raise SystemExit('refused: the pair has %d effects; this step goes on pair 72 (%d effects) or on a pair with at most '
                         '%d (ids %d.. are this table\'s)' % (ne0, BASE_EFFECTS, RESERVED_LAST, FIRST))
    pad = RESERVED_LAST - ne0
    gens = []
    for r, fr in zip(rows, frames):
        gens.append(dict(kind='effect', w=r['w'], h=r['h'], layers=1, px=1, py=1, phases=r['phases'], ms=r['ms'],
                         frames={(i, 0, 0, 0): f for i, f in enumerate(fr)}, dx=r['dx'], dy=r['dy'], disp=None,
                         durs=[(r['ms'], r['ms'])] * r['phases']))
    blank = entry_bytes(dict(kind='effect', w=1, h=1, layers=1, px=1, py=1, phases=1, ms=100, disp=None, durs=None), [0])
    recs, lists = {}, []
    for g in gens:
        T = T_(g)
        lst = [0] * (g['w'] * g['h'] * g['phases'])
        for (ph, x, y, l), img in g['frames'].items():
            for (ww, hh), tile in tiles_of(img, g['w'], g['h']).items():
                rec = encode_sprite(np.ascontiguousarray(tile))
                if rec is not None:
                    recs.setdefault(rec, len(recs) + 1)
                    lst[sprite_index(T, x, y, 0, l, ph, ww, hh)] = rec
        lists.append(lst)
    base = ospr.count
    newrecs = list(recs)
    rid = {rec: base + i + 1 for i, rec in enumerate(newrecs)}
    entries = [entry_bytes(g, [rid[x] if x else 0 for x in lst]) for g, lst in zip(gens, lists)]
    d = od.data
    e_end = od.effects[-1].raw[1]
    assert od.missiles[0].raw[0] == e_end and od.missiles[-1].raw[1] == len(d)
    out = bytearray(d[:e_end]) + blank * pad + b''.join(entries) + d[e_end:]
    total = RESERVED_LAST + len(rows)
    struct.pack_into('<HH', out, 8, total, nm0)
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, 'Tibia.dat'), 'wb') as fh:
        fh.write(out)
    m, oc, nn = ospr.m, ospr.count, len(newrecs)
    toffs = ospr.offs.astype('<u8').copy()
    toffs[toffs > 0] += 4 * nn
    cur = len(m) + 4 * nn
    new_offs = []
    for rec in newrecs:
        new_offs.append(cur)
        cur += len(rec)
    assert cur < 1 << 32, 'spr would exceed 4 GB'
    table = np.concatenate([toffs, np.array(new_offs, dtype='<u8')]).astype('<u4')
    with open(os.path.join(out_dir, 'Tibia.spr'), 'wb') as fh:
        fh.write(struct.pack('<II', ospr.signature, oc + nn))
        fh.write(table.tobytes())
        pos = 8 + 4 * oc
        while pos < len(m):
            fh.write(m[pos:pos + (1 << 24)])
            pos += 1 << 24
        for rec in newrecs:
            fh.write(rec)
    # verification
    md, ms = Dat(os.path.join(out_dir, 'Tibia.dat')), Spr(os.path.join(out_dir, 'Tibia.spr'))
    assert md.variant == od.variant
    assert md.counts == (od.counts[0], od.counts[1], total, nm0), md.counts
    assert ms.count == oc + nn and md.max_sprite <= ms.count and ms.alpha and ms.signature == ospr.signature
    assert md.data[:8] == d[:8] and md.data[12:e_end] == d[12:e_end], 'items, outfits or old effects changed'
    for to, tm in zip(od.missiles, md.missiles):
        assert md.data[tm.raw[0]:tm.raw[1]] == d[to.raw[0]:to.raw[1]], ('missile', to.id)
    for i in range(ne0, RESERVED_LAST):
        t = md.effects[i]
        assert (t.w, t.h, t.phases) == (1, 1, 1) and not any(t.sprites), ('pad', i + 1)
    for r, g in zip(rows, gens):
        t = md.effects[r['id'] - 1]
        assert (t.w, t.h, t.layers, t.px, t.py, t.pz, t.phases) == (g['w'], g['h'], 1, 1, 1, 1, g['phases']), r['name']
        back = render_back(t, ms, 1)
        for k, img in g['frames'].items():
            assert np.array_equal(back[k], img), ('MISMATCH', r['name'], k)
    random.seed(1)
    for sid in random.sample(range(1, oc + 1), min(3000, oc)) + [1, oc]:
        x, y = ospr.sprite(sid), ms.sprite(sid)
        assert (x is None) == (y is None) and (x is None or (x == y).all()), sid
    print('pair: effects %d -> %d (%d blank up to %d, %d of this table at %d..%d), missiles %d, sprites %d -> %d; every '
          'older thing byte-identical, every new frame pixel-identical to the art' % (
              ne0, total, pad, RESERVED_LAST, len(rows), FIRST, total, nm0, oc, oc + nn))
    return 0


def build(dat, spr, out_dir, src):
    rows = read_table()
    errs = table_errors(rows)
    sources = find_sources(src)
    sums = read_sums()
    frames = []
    for r in rows:
        fr = frames_of(r, sources)
        if digest(strip_of(fr)) != sums.get(r['name']):
            errs.append('%s: the strip differs from status_vfx.sums (another sheet, or run `table --src`)' % r['name'])
        frames.append(fr)
    if errs:
        print('\n'.join(errs))
        return 1
    return apply(dat, spr, out_dir, rows, frames)


def table(src):
    """refresh src-independent numbers and the sums from the sheets (the rows' cut numbers stay as written)"""
    rows = read_table()
    sources = find_sources(src)
    lines = []
    for r in rows:
        lines.append('%s  %s\n' % (digest(strip_of(frames_of(r, sources))), r['name']))
    with open(SUMS, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(''.join(lines))
    with open(TABLE, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(table_text(rows))
    print('wrote %s and %s (%d rows)' % (os.path.relpath(TABLE, ROOT), os.path.relpath(SUMS, ROOT), len(rows)))
    return 0


def strips(out_dir, src):
    from PIL import Image
    rows = read_table()
    sources = find_sources(src)
    os.makedirs(out_dir, exist_ok=True)
    for r in rows:
        Image.fromarray(strip_of(frames_of(r, sources))).save(os.path.join(out_dir, r['name'] + '.png'))
    print('wrote %d strips to %s (never commit them)' % (len(rows), out_dir))
    return 0


def live(dat_path, spr_path):
    import numpy as np
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    from import_vfx import render_back
    dat, spr = Dat(dat_path), Spr(spr_path)
    rows = read_table()
    sums = read_sums()
    errs = []
    if len(dat.effects) < FIRST + len(rows) - 1:
        errs.append('the pair has %d effects, the table ends at %d' % (len(dat.effects), FIRST + len(rows) - 1))
    else:
        for r in rows:
            t = dat.effects[r['id'] - 1]
            if (t.w, t.h, t.phases) != (r['w'], r['h'], r['phases']):
                errs.append('%s: size or phases differ at %d' % (r['name'], r['id']))
                continue
            d = list(t.anim[3]) if t.anim else []
            if r['phases'] > 1 and d != [r['ms']] * (2 * r['phases']):
                errs.append('%s: durations differ' % r['name'])
            back = render_back(t, spr, 1)
            strip = strip_of([back[(p, 0, 0, 0)] for p in range(t.phases)])
            if digest(strip) != sums.get(r['name']):
                errs.append('%s: pixels differ from the sum' % r['name'])
            lv = set(np.unique(strip[..., 3]).tolist())
            if not lv <= {0, GLOW, 255}:
                errs.append('%s: alpha levels %s' % (r['name'], sorted(lv)))
    for e in errs:
        print(e)
    print('status vfx live: %d effects at ids %d..%d, %s' % (len(rows), FIRST, FIRST + len(rows) - 1,
                                                           'OK' if not errs else '%d problem(s)' % len(errs)))
    return 1 if errs else 0


# ---------------------------------------------------------------------------------------------------- generated files
def lua_text(rows):
    by = {(r['kind'], r['key'], r['part']): r for r in rows}
    L = ['-- GENERATED by client/tools/sprites/gen_status_vfx.py from art_import/status_vfx.csv (O597): the effect ids of the',
         '-- status layer and of the kill overlays, effects %d..%d of client pair %d. Do not edit by hand.' % (
             rows[0]['id'], rows[-1]['id'], PAIR),
         '-- Gate: config.lua `chaosClientPair` >= %d, read from the file at load (M.on); a client on an older pair has no such' % PAIR,
         '-- effect, so below it the server sends none of these ids (lib/chaos_status_vfx.lua, cosmetics).',
         'local M = {}',
         '',
         'M.PAIR = %d' % PAIR,
         'M.FIRST = %d' % rows[0]['id'],
         'M.LAST = %d' % rows[-1]['id'],
         '',
         '-- the statuses in bit order (bit i - 1 of a mask is M.order[i]): {start, loop, stop} effect ids and their length in ms',
         'M.order = {%s}' % ', '.join('"%s"' % s for s in STATUSES),
         'M.status = {']
    for s in STATUSES:
        a, b, c = (by[('status', s, p)] for p in PARTS)
        L.append('\t%s = {start = %d, loop = %d, stop = %d, startMs = %d, loopMs = %d, stopMs = %d},' % (
            s, a['id'], b['id'], c['id'], a['phases'] * a['ms'], b['phases'] * b['ms'], c['phases'] * c['ms']))
    L += ['}',
          '',
          '-- the overlay a kill dissolve mode plays on the tile of the kill: effect id, tile shift, length in ms',
          'M.kill = {']
    for k in KILLS:
        r = by[('kill', k, 'over')]
        L.append('\t%s = {id = %d, dx = %d, dy = %d, ms = %d},' % (k, r['id'], r['dx'], r['dy'], r['phases'] * r['ms']))
    L += ['}',
          '',
          '-- the pair recorded in a config.lua text, or nil (the same reading as server/tools/client_pair.py parse)',
          'function M.parsePair(text)',
          '\tif type(text) ~= "string" then',
          '\t\treturn nil',
          '\tend',
          '\tlocal v = text:match("^%s*chaosClientPair%s*=%s*(%d+)%s*%-?%-?[^\\n]*$") or text:match("\\n%s*chaosClientPair%s*=%s*(%d+)%s*%-?%-?[^\\n]*")',
          '\treturn v and tonumber(v) or nil',
          'end',
          '',
          'function M.recordedPair(path)',
          '\tlocal f = io.open(path or "config.lua", "r")',
          '\tif not f then',
          '\t\treturn nil',
          '\tend',
          '\tlocal text = f:read("*a")',
          '\tf:close()',
          '\treturn M.parsePair(text)',
          'end',
          '',
          '-- the gate, read once at load; tests set it by hand',
          'M.on = (M.recordedPair() or 0) >= M.PAIR',
          '',
          'ChaosStatusVfxIds = M',
          'return M']
    return '\n'.join(L) + '\n'


def tags_text(rows):
    with open(TAGS, encoding='utf-8', newline='') as fh:
        keep = [l for l in fh.read().splitlines() if not l.split(',')[1:2] or not l.split(',')[1].startswith(PREFIX)]
    mine = ['%d,%s,%s' % (r['id'], r['name'], r['element']) for r in rows]
    # id order, like the other pair 73 steps (gen_gap_fx.py, gen_area_fx.py): every step agrees on one file
    return '\n'.join(keep[:1] + sorted(keep[1:] + mine, key=lambda l: int(l.split(',')[0]))) + '\n'


def generated(rows):
    return {LUA: lua_text(rows), TAGS: tags_text(rows)}


def ids(check):
    rows = read_table()
    errs = table_errors(rows)
    if errs:
        print('\n'.join(errs))
        return 1
    bad = 0
    for p, text in generated(rows).items():
        if check:
            have = open(p, encoding='utf-8', newline='').read() if os.path.exists(p) else None
            print(os.path.relpath(p, ROOT) + (': up to date' if have == text else ': OUT OF DATE (run gen_status_vfx.py ids)'))
            bad += have != text
        else:
            with open(p, 'w', encoding='utf-8', newline='\n') as fh:
                fh.write(text)
            print('wrote', os.path.relpath(p, ROOT))
    return 1 if bad else 0


def check():
    rows = read_table()
    errs = table_errors(rows)
    sums = read_sums()
    if list(sums) != [r['name'] for r in rows]:
        errs.append('status_vfx.sums does not list the table rows in order')
    for n, d in sums.items():
        if len(d) != 64:
            errs.append('%s: bad digest' % n)
    raw = open(TABLE, encoding='utf-8', newline='').read()
    if raw != table_text(rows):
        errs.append('status_vfx.csv is not in the tool\'s format (run `table --src DIR`)')
    for p in sorted(os.listdir(ART)):
        if p.startswith('status_vfx') and p not in ('status_vfx.csv', 'status_vfx.sums'):
            errs.append('art_import/%s: only the table and the sums may be committed' % p)
    for e in errs:
        print(e)
    bad = ids(True)
    print('status vfx: %d rows (%d statuses x 3, %d kill overlays), ids %d..%d, %s' % (
        len(rows), len(STATUSES), len(KILLS), FIRST, FIRST + len(rows) - 1, 'OK' if not errs and not bad else 'FAILED'))
    return 1 if errs or bad else 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build'); b.add_argument('dat'); b.add_argument('spr'); b.add_argument('out'); b.add_argument('--src', required=True)
    t = sub.add_parser('table'); t.add_argument('--src', required=True)
    sub.add_parser('check')
    i = sub.add_parser('ids'); i.add_argument('--check', action='store_true')
    l = sub.add_parser('live'); l.add_argument('dat'); l.add_argument('spr')
    s = sub.add_parser('strips'); s.add_argument('out'); s.add_argument('--src', required=True)
    a = ap.parse_args(argv)
    if a.cmd == 'build':
        return build(a.dat, a.spr, a.out, a.src)
    if a.cmd == 'table':
        return table(a.src)
    if a.cmd == 'check':
        return check()
    if a.cmd == 'ids':
        return ids(a.check)
    if a.cmd == 'live':
        return live(a.dat, a.spr)
    return strips(a.out, a.src)


if __name__ == '__main__':
    sys.exit(main())
