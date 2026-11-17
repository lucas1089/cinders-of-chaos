#!/usr/bin/env python3
"""Spell effects and a projectile of a purchased effect pack at game size (O596, trimmed by O600; joins client pair 73).

    python3 -I gen_spell_vfx.py build DAT SPR OUT_DIR --src DIR   # DIR: the downloaded 128 px sheets (any layout, found by
                                                                 # digest); OUT_DIR gets Tibia.dat, Tibia.spr and strips/
    python3 -I gen_spell_vfx.py build DAT SPR OUT_DIR --src DIR --write   # also writes art_import/spell_vfx.csv and .sums
    python3 -I gen_spell_vfx.py check                             # CI, no art, no pair: table, sums, ids file, tags agree
    python3 -I gen_spell_vfx.py ids [--check]                     # server/data/lib/chaos_spell_vfx_ids.lua, the tags of
                                                                 # spell_fx_elements.csv
    python3 -I gen_spell_vfx.py live DAT SPR                      # the pair holds every piece at its id, pixel for pixel

The art is purchased (docs/CREDITS.md "Spell effect packs (O596)"): use and change are allowed, the picture files may not
be passed on. So no picture is in the repository. Committed are this script, the table art_import/spell_vfx.csv (one row
per piece: a neutral name, the pack key, src = the first 12 hex of the sha256 of the sheet file, the grid, the result) and
art_import/spell_vfx.sums (the digest of every built strip). The sheets are read by this local script only: they are
never sent to a web or AI service. `build` needs them; `check` and `live` work from the table and the pair alone.

O600 (owner, after the previews: "use only the ones that were really bad"): of the 46 pieces of O596 three are left,
for the three spells whose effect of today does not read at game size (server/data/lib/chaos_spell_vfx.lua).

Input pair: exactly 4,742 effects and 253 missiles (pair 72, or pair 72 plus the other steps of pair 73, which add no
effect and no missile). Any other pair is refused. The 2 effects are appended at the fixed ids 4743..4744 (the block
4743..5142 is this step's; the next step starts at 5143 and pads the gap). Missile ids are one byte on the wire, so no
missile can be appended past 253: the projectile fills the blank stock id 46 (never drawn before, no script sends
it). No missile is rebuilt in place any more (the tool still can: a MISSILES row with an empty `new`).

Game size, not HD (owner: "do the recommended"): a 128 px cell is put with its anchor on the middle of a canvas, turned
for a projectile's direction, and scaled with a Lanczos filter on premultiplied colour: projectiles and small hits to a
64 px footprint, areas, auras and big hits to 96 px. Then the lift (at that size the packs lose their glow on grass and
stone): alpha through 1 - (1 - a)^LIFT, colour a step more saturated and deeper in the glow, and the cut of
docs/SPRITE_STYLE.md: alpha 255 from CUT up, one glow level GLOW from HALO up, nothing below, 16 colours a piece.
At most 12 phases an effect, spread over the frames that still show something; a projectile is 8 phases of 50 ms on
3 x 3 tiles with its head on the middle, sent at offset (1, 1) (base patch 0194 animates it).

Needs numpy and Pillow (the fx venv of CI). Deterministic: the same sheets give the same strips.
"""
import argparse
import csv
import hashlib
import io
import math
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
ART = os.path.join(HERE, 'art_import')
SPEC = os.path.join(ART, 'spell_vfx.csv')
SUMS = os.path.join(ART, 'spell_vfx.sums')
LUA = os.path.join(ROOT, 'server', 'data', 'lib', 'chaos_spell_vfx_ids.lua')
TAGS = os.path.join(ROOT, 'server', 'data', 'spells', 'spell_fx_elements.csv')

NEED_EFFECTS, NEED_MISSILES = 4742, 253     # the input pair (pair 72)
FIRST, LAST = 4743, 5142                    # this step's effect ids
MISSILE_MAX = 253                           # one byte on the wire, 254 and 255 are the engine's
PAIR = 73
CELL = 128
CUT, HALO, GLOW = 0.5, 0.2, 144
LIFT = 1.8
COLOURS = 16
MAX_PHASES = 12
FPS = 24
MISSILE_PHASES, MISSILE_MS, MISSILE_PX = 8, 50, 96
# where the anchor of a cell lands, px from the top left of the target tile
AT = {'body': (16, 12), 'tile': (16, 16), 'ground': (16, 22), 'feet': (16, 26), 'head': (16, 0)}
PATTERN = {(1, 0): (2, 1), (-1, 0): (0, 1), (0, -1): (1, 0), (0, 1): (1, 2),
           (1, -1): (2, 0), (1, 1): (2, 2), (-1, 1): (0, 2), (-1, -1): (0, 0)}
FIELDS = ['kind', 'id', 'name', 'pack', 'src', 'cols', 'rows', 'frames', 'ax', 'ay', 'size', 'at', 'element', 'role',
          'w', 'h', 'phases', 'ms', 'dx', 'dy', 'note']

# (name, pack key, src, cols, rows, frames, anchor x, anchor y, footprint px, at, element, role, note)
EFFECTS = [
    ('sv_death_bone_shatter', 'death_a', '78632c328005', 6, 4, 22, 0.5, 0.5, 96, 'body', 'death', 'hit', 'bone splinters'),
    ('sv_death_lifesteal', 'death_a', 'fac42de15d61', 8, 4, 32, 0.5, 0.52, 96, 'body', 'death', 'aura', 'life drawn out in red threads'),
]
# (name, pack key, src, cols, rows, frames, anchor x, anchor y, missile id, new name or '' for a rebuild in place, element, note)
MISSILES = [
    ('sv_death_skull', 'death_a', '06e85ef15cc6', 8, 3, 24, 0.66, 0.5, 46, 'new', 'death', 'a wailing skull (blank stock id 46)'),
]


def pieces():
    """the table rows that need no art: effects at FIRST.., then the missiles"""
    out = []
    for i, (name, pack, src, cols, rows, frames, ax, ay, size, at, element, role, note) in enumerate(EFFECTS):
        out.append(dict(kind='effect', id=FIRST + i, name=name, pack=pack, src=src, cols=cols, rows=rows, frames=frames,
                        ax=ax, ay=ay, size=size, at=at, element=element, role=role, note=note))
    for name, pack, src, cols, rows, frames, ax, ay, mid, new, element, note in MISSILES:
        out.append(dict(kind='missile', id=mid, name=name, pack=pack, src=src, cols=cols, rows=rows, frames=frames,
                        ax=ax, ay=ay, size=64, at='new' if new else 'replace', element=element, role='missile', note=note))
    return out


def table_errors(rows):
    """rules of the table that hold without art"""
    errs = []
    eff = [r for r in rows if r['kind'] == 'effect']
    mis = [r for r in rows if r['kind'] == 'missile']
    ids = [int(r['id']) for r in eff]
    if ids != list(range(FIRST, FIRST + len(ids))):
        errs.append('effect ids are not %d.. in order' % FIRST)
    if ids and ids[-1] > LAST:
        errs.append('effect ids past %d' % LAST)
    names = [r['name'] for r in rows]
    if len(set(names)) != len(names) or any(not n.startswith('sv_') for n in names):
        errs.append('names: not unique or not sv_*')
    mids = [int(r['id']) for r in mis]
    if len(set(mids)) != len(mids) or any(not 1 <= m <= MISSILE_MAX for m in mids):
        errs.append('missile ids: not unique or not 1..%d (one byte on the wire)' % MISSILE_MAX)
    for r in rows:
        if len(r['src']) != 12 or any(c not in '0123456789abcdef' for c in r['src']):
            errs.append('%s: src is not 12 hex' % r['name'])
        if int(r['cols']) * int(r['rows']) < int(r['frames']):
            errs.append('%s: more frames than cells' % r['name'])
        if r['kind'] == 'effect' and (int(r['size']) not in (64, 96) or r['at'] not in AT):
            errs.append('%s: size or at' % r['name'])
        if r['pack'] not in ('fire_a', 'death_a', 'death_b', 'holy_a', 'storm_a'):
            errs.append('%s: pack key' % r['name'])
    srcs = [r['src'] for r in rows]
    if len(set(srcs)) != len(srcs):
        errs.append('a sheet is used twice')
    return errs


def pair_ok(effects, missiles):
    return effects == NEED_EFFECTS and missiles == NEED_MISSILES


# ------------------------------------------------------------------------------------------------- the art
def digest(strip):
    import numpy as np
    return hashlib.sha256(np.ascontiguousarray(strip).tobytes() + repr(strip.shape).encode()).hexdigest()


def find_sheets(src):
    """{12 hex: path} of the PNG files under src"""
    out = {}
    for base, _dirs, files in os.walk(src):
        for f in sorted(files):
            if f.lower().endswith('.png'):
                p = os.path.join(base, f)
                with open(p, 'rb') as fh:
                    out.setdefault(hashlib.sha256(fh.read()).hexdigest()[:12], p)
    return out


def cells_of(sheet, cols, rows, frames):
    """the frames of a sheet as float premultiplied RGBA arrays (CELL x CELL)"""
    import numpy as np
    a = np.asarray(sheet.convert('RGBA')).astype(np.float32) / 255.0
    assert a.shape[0] == rows * CELL and a.shape[1] == cols * CELL, ('sheet size', a.shape, cols, rows)
    out = []
    for i in range(frames):
        c, r = i % cols, i // cols
        cell = a[r * CELL:(r + 1) * CELL, c * CELL:(c + 1) * CELL].copy()
        cell[..., :3] *= cell[..., 3:4]
        out.append(cell)
    return out


def place(cell, ax, ay, scale, angle=0.0):
    """the cell with its anchor on the middle of a square canvas, turned by angle (degrees, counter clockwise) and scaled:
    float straight RGBA, side 2 * CELL * scale"""
    import numpy as np
    from PIL import Image
    side = 2 * CELL
    pad = np.zeros((side, side, 4), np.float32)
    x0, y0 = int(round(CELL - ax * CELL)), int(round(CELL - ay * CELL))
    pad[y0:y0 + CELL, x0:x0 + CELL] = cell
    n = int(round(side * scale))
    chans = []
    for i in range(4):
        im = Image.fromarray(pad[..., i], 'F')
        if angle:
            im = im.rotate(angle, resample=Image.BICUBIC)
        chans.append(np.asarray(im.resize((n, n), Image.LANCZOS)))
    o = np.clip(np.stack(chans, -1), 0, 1)
    al = o[..., 3:4]
    rgb = np.where(al > 1e-4, o[..., :3] / np.maximum(al, 1e-4), 0)
    return np.clip(np.concatenate([rgb, al], -1), 0, 1)


def lift(f):
    """the glow and contrast lift on a float straight RGBA frame"""
    import numpy as np
    a = 1.0 - (1.0 - f[..., 3]) ** LIFT
    rgb = f[..., :3]
    grey = rgb.mean(-1, keepdims=True)
    rgb = np.clip(grey + (rgb - grey) * 1.25, 0, 1)                     # a step more saturated
    halo = (a < CUT)[..., None]
    rgb = np.where(halo, np.clip(rgb * 0.92, 0, 1), rgb)                # the glow a step deeper, so it reads on light ground
    return np.concatenate([rgb, a[..., None]], -1)


def palette_of(frames):
    """COLOURS colours of the kept pixels of every frame (median cut)"""
    import numpy as np
    from PIL import Image
    px = np.concatenate([f[f[..., 3] >= HALO][:, :3] for f in frames])
    if len(px) == 0:
        return np.zeros((1, 3), np.float32)
    if len(px) > 40000:
        px = px[np.linspace(0, len(px) - 1, 40000).astype(int)]
    im = Image.fromarray((px * 255 + 0.5).astype(np.uint8).reshape(-1, 1, 3), 'RGB')
    q = im.quantize(colors=COLOURS, method=Image.Quantize.MEDIANCUT)
    used = sorted(set(np.asarray(q).ravel().tolist()))
    pal = np.array(q.getpalette()[:3 * 256], np.float32).reshape(-1, 3) / 255.0
    return pal[used]


def cut(f, pal):
    """float RGBA -> uint8 RGBA: alpha 0, GLOW or 255, the colours of pal; a transparent pixel carries no colour"""
    import numpy as np
    a = f[..., 3]
    d = ((f[..., None, :3] - pal[None, None, :, :]) ** 2).sum(-1)
    rgb = pal[d.argmin(-1)]
    al = np.where(a >= CUT, 255, np.where(a >= HALO, GLOW, 0)).astype(np.uint8)
    out = np.concatenate([(rgb * 255 + 0.5).astype(np.uint8), al[..., None]], -1)
    out[al == 0] = 0
    return out


def pick_phases(shown, cap=MAX_PHASES):
    """the frame indexes kept: at most cap, spread from the first to the last frame that shows something"""
    idx = [i for i, s in enumerate(shown) if s]
    assert idx, 'no frame shows anything'
    lo, hi = idx[0], idx[-1]
    n = min(cap, hi - lo + 1)
    if n == 1:
        return [lo]
    out = sorted(set(int(round(lo + k * (hi - lo) / (n - 1))) for k in range(n)))
    return [i for i in out if shown[i]] or [lo]


def fit_axis(lo, hi, p):
    """tiles before and after the target tile for content [lo, hi) px around a point p px into the tile (at most 2)"""
    before = min(2, max(0, int(math.ceil((-(p + lo)) / 32.0))))
    after = min(2, max(0, int(math.ceil((p + hi - 32) / 32.0))))
    return before, after


def build_effect(r, sheet):
    """-> (strip uint8, the computed fields)"""
    import numpy as np
    scale = int(r['size']) / float(CELL)
    cells = cells_of(sheet, int(r['cols']), int(r['rows']), int(r['frames']))
    fl = [lift(place(c, float(r['ax']), float(r['ay']), scale)) for c in cells]
    pal = palette_of(fl)
    done = [cut(f, pal) for f in fl]
    keep = pick_phases([int((d[..., 3] > 0).sum()) >= 6 for d in done])
    done = [done[i] for i in keep]
    mid = done[0].shape[0] // 2                                         # the anchor
    ys, xs = np.where(np.max([d[..., 3] for d in done], 0) > 0)
    px, py = AT[r['at']]
    left, right = fit_axis(int(xs.min()) - mid, int(xs.max()) + 1 - mid, px)
    up, down = fit_axis(int(ys.min()) - mid, int(ys.max()) + 1 - mid, py)
    w, h = left + 1 + right, up + 1 + down
    x0, y0 = mid - (left * 32 + px), mid - (up * 32 + py)               # the canvas corner inside the padded frame
    frames = []
    for d in done:
        c = np.zeros((h * 32, w * 32, 4), np.uint8)
        sx0, sy0 = max(0, x0), max(0, y0)
        sx1, sy1 = min(d.shape[1], x0 + w * 32), min(d.shape[0], y0 + h * 32)
        c[sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0] = d[sy0:sy1, sx0:sx1]
        frames.append(c)
    span = keep[-1] - keep[0] + 1
    ms = int(min(120, max(60, round(span * 1000.0 / FPS / len(keep)))))
    return np.concatenate(frames, axis=1), dict(w=w, h=h, phases=len(keep), ms=ms, dx=right, dy=down)


def build_missile(r, sheet):
    import numpy as np
    cells = cells_of(sheet, int(r['cols']), int(r['rows']), int(r['frames']))
    step = max(1, len(cells) // MISSILE_PHASES)
    cells = [cells[(i * step) % len(cells)] for i in range(MISSILE_PHASES)]
    by = {}
    for (dx, dy), pat in PATTERN.items():
        ang = math.degrees(math.atan2(-dy, dx))
        by[pat] = [lift(place(c, float(r['ax']), float(r['ay']), 0.5, ang)) for c in cells]
    by[(1, 1)] = by[(1, 2)]                                             # the centre pattern repeats south
    pal = palette_of([f for fs in by.values() for f in fs])
    P = MISSILE_PX
    strip = np.zeros((3 * P, 3 * P * MISSILE_PHASES, 4), np.uint8)
    for (x, y), fs in by.items():
        for f, fr in enumerate(fs):
            d = cut(fr, pal)
            o = (d.shape[0] - P) // 2
            strip[y * P:(y + 1) * P, (x * MISSILE_PHASES + f) * P:(x * MISSILE_PHASES + f + 1) * P] = d[o:o + P, o:o + P]
    return strip, dict(w=3, h=3, phases=MISSILE_PHASES, ms=MISSILE_MS, dx=1, dy=1)


def build_rows(src):
    """[(row with the computed fields, strip)] from the sheets under src"""
    from PIL import Image
    sheets = find_sheets(src)
    out = []
    for r in pieces():
        if r['src'] not in sheets:
            sys.exit('%s: no sheet with digest %s under %s' % (r['name'], r['src'], src))
        sheet = Image.open(sheets[r['src']])
        strip, more = (build_effect if r['kind'] == 'effect' else build_missile)(r, sheet)
        r.update(more)
        out.append((r, strip))
    return out


def spec_text(rows):
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=FIELDS, lineterminator='\n')
    w.writeheader()
    w.writerows(rows)
    n = sum(1 for r in rows if r['kind'] == 'effect')
    w.writerow(dict(kind='total', id=n, name='effects_%d_%d' % (FIRST, FIRST + n - 1),
                    note='this step appends exactly %d effects and no missile; the next step starts at %d' % (n, LAST + 1)))
    return buf.getvalue()


def sums_text(pairs):
    return ''.join('%s  %s\n' % (digest(s), r['name']) for r, s in pairs)


def read_spec():
    with open(SPEC, newline='') as fh:
        return [r for r in csv.DictReader(fh) if r['kind'] != 'total']


def read_total():
    with open(SPEC, newline='') as fh:
        return [int(r['id']) for r in csv.DictReader(fh) if r['kind'] == 'total']


def read_sums():
    return dict(l.strip().split('  ', 1)[::-1] for l in open(SUMS))


def build(dat, spr, out, src, write):
    import numpy as np
    from PIL import Image
    sys.path.insert(0, HERE)
    from datspr import Dat
    d = Dat(dat)
    if not pair_ok(len(d.effects), len(d.missiles)):
        sys.exit('refused: the input pair has %d effects and %d missiles, this step needs exactly %d and %d (pair 72)' % (
            len(d.effects), len(d.missiles), NEED_EFFECTS, NEED_MISSILES))
    errs = table_errors(pieces())
    if errs:
        sys.exit('\n'.join(errs))
    for r in pieces():
        if r['kind'] == 'missile' and r['at'] == 'new' and any(d.missiles[int(r['id']) - 1].sprites):
            sys.exit('refused: missile %s is not blank in the input pair' % r['id'])
    pairs = build_rows(src)
    rows = [r for r, _ in pairs]
    texts = {SPEC: spec_text(rows), SUMS: sums_text(pairs)}
    if write:
        for p, t in texts.items():
            open(p, 'w', newline='').write(t)
            print('wrote', os.path.relpath(p, ROOT))
    else:
        bad = [p for p, t in texts.items() if not os.path.exists(p) or open(p, newline='').read() != t]
        if bad:
            sys.exit('the sheets do not give the committed %s (run with --write after a wanted change)' % ', '.join(
                os.path.relpath(p, ROOT) for p in bad))
    strips = os.path.join(os.path.abspath(out), 'strips')
    os.makedirs(strips, exist_ok=True)
    spec = os.path.join(strips, 'import.csv')
    with open(spec, 'w', newline='') as fh:
        w = csv.writer(fh, lineterminator='\n')
        w.writerow(['replace', 'kind', 'name', 'file', 'w', 'h', 'phases', 'ms', 'dx', 'dy', 'note', 'alpha', 'durs', 'lua'])
        for r, s in pairs:
            f = os.path.join(strips, r['name'] + '.png')
            Image.fromarray(np.ascontiguousarray(s)).save(f, optimize=False)
            w.writerow([r['id'] if r['kind'] == 'missile' else '', r['kind'], r['name'], f, r['w'], r['h'], r['phases'], r['ms'],
                        r['dx'], r['dy'], r['note'], 'soft', '', r['name'] if r['at'] == 'new' else ''])
    cmd = [sys.executable, '-I', os.path.join(HERE, 'import_fx_art.py'), '--ours-dat', dat, '--ours-spr', spr, '--out-dir', out,
           '--spec', spec, '--expect-first-effect', str(FIRST), '--keep-donor-names']
    if subprocess.run(cmd).returncode:
        sys.exit('import_fx_art.py failed')
    for f in ('chaos_vfx_art.lua', 'vfx_art_catalog.csv'):                # this step's ids come from the table
        p = os.path.join(out, f)
        if os.path.exists(p):
            os.remove(p)
    return live(os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr'))


# ------------------------------------------------------------------------------------------------- server files
def lua_text(rows):
    eff = [r for r in rows if r['kind'] == 'effect']
    L = ['-- GENERATED by client/tools/sprites/gen_spell_vfx.py from art_import/spell_vfx.csv (O596). Do not edit by hand.',
         '-- The spell effects and projectiles of the purchased effect pack (docs/CREDITS.md; O600 kept three pieces), drawn by client pair %d:' % PAIR,
         '-- %d effects at the ids %d..%d, appended after the effects of pair 72, projectiles: %d. A projectile id is one' % (
             len(eff), FIRST, FIRST + len(eff) - 1, len(rows) - len(eff)),
         '-- byte on the wire, so none is appended: `new` fills a blank stock id, the others rebuild a pack projectile in place',
         '-- at its own size and send offset (they keep their old names and are listed for the record only).',
         '-- A plain table: data/lib/chaos_spell_vfx.lua merges it into ChaosVfx / ChaosVfxMissile when config.lua',
         '-- chaosClientPair is %d or more, so a server on an older pair never sends one of these ids.' % PAIR,
         'ChaosSpellVfxIds = {',
         '\tpair = %d, first = %d, count = %d,' % (PAIR, FIRST, len(eff)),
         '\teffects = {']
    for r in eff:
        L.append('\t\t%s = {id = %s, dx = %s, dy = %s, ms = %d, element = "%s"},  -- %s' % (
            r['name'], r['id'], r['dx'], r['dy'], int(r['ms']) * int(r['phases']), r['element'], r['note']))
    L += ['\t},', '\tmissiles = {']
    for r in rows:
        if r['kind'] == 'missile' and r['at'] == 'new':
            L.append('\t\t%s = {id = %s, dx = %s, dy = %s, element = "%s"},  -- %s' % (
                r['name'], r['id'], r['dx'], r['dy'], r['element'], r['note']))
    L += ['\t},', '\trebuilt = {']
    for r in rows:
        if r['kind'] == 'missile' and r['at'] != 'new':
            L.append('\t\t[%s] = "%s",  -- %s' % (r['id'], r['name'], r['note']))
    L += ['\t},', '}']
    return '\n'.join(L) + '\n'


def tags_text(rows):
    """spell_fx_elements.csv with this step's effect rows (id, name, element) in id order, the other rows as they are"""
    with open(TAGS, encoding='utf-8', newline='') as fh:
        keep = [l for l in fh.read().splitlines() if not l.split(',')[1:2] or not l.split(',')[1].startswith('sv_')]
    mine = ['%s,%s,%s' % (r['id'], r['name'], r['element']) for r in rows if r['kind'] == 'effect']
    # data rows sorted by id: the donor (4703-4742) and spell vfx (4743-) steps both write this file, neither owns its end
    return '\n'.join(keep[:1] + sorted(keep[1:] + mine, key=lambda l: int(l.split(',')[0]))) + '\n'


def ids(check):
    rows = read_spec()
    want = {LUA: lua_text(rows), TAGS: tags_text(rows)}
    if check:
        bad = 0
        for p, text in want.items():
            have = open(p, encoding='utf-8', newline='').read() if os.path.exists(p) else None
            print(os.path.relpath(p, ROOT) + (': up to date' if have == text else ': OUT OF DATE (run gen_spell_vfx.py ids)'))
            bad += have != text
        return 1 if bad else 0
    for p, text in want.items():
        open(p, 'w', encoding='utf-8', newline='\n').write(text)
        print('wrote', os.path.relpath(p, ROOT))
    return 0


def check():
    errs = table_errors(pieces())
    rows = read_spec() if os.path.exists(SPEC) else []
    static = [k for k in FIELDS if k not in ('w', 'h', 'phases', 'ms', 'dx', 'dy')]
    if [[str(r[k]) for k in static] for r in pieces()] != [[r[k] for k in static] for r in rows]:
        errs.append('art_import/spell_vfx.csv does not list the pieces of the script in order')
    n = sum(1 for r in rows if r['kind'] == 'effect')
    if read_total() != [n] if rows else True:
        errs.append('spell_vfx.csv: the total row does not record the %d effects' % n)
    for r in rows:
        w, h, dx, dy, ph, ms = (int(r[k]) for k in ('w', 'h', 'dx', 'dy', 'phases', 'ms'))
        if not (0 <= dx < w and 0 <= dy < h and 1 <= w <= 5 and 1 <= h <= 5):
            errs.append('%s: size or offset' % r['name'])
        if r['kind'] == 'effect' and not (1 <= ph <= MAX_PHASES and 60 <= ms <= 120):
            errs.append('%s: phases or ms' % r['name'])
        if r['kind'] == 'missile' and (w, h, dx, dy, ph, ms) != (3, 3, 1, 1, MISSILE_PHASES, MISSILE_MS):
            errs.append('%s: a projectile is 3 x 3 at (1, 1), %d phases of %d ms' % (r['name'], MISSILE_PHASES, MISSILE_MS))
    sums = [l.split('  ', 1)[1].strip() for l in open(SUMS)] if os.path.exists(SUMS) else []
    if sums != [r['name'] for r in rows]:
        errs.append('spell_vfx.sums does not list the table names in order')
    for p in (SPEC, SUMS, LUA):                                       # no pack name outside docs/CREDITS.md
        text = open(p, encoding='utf-8').read().lower() if os.path.exists(p) else ''
        for word in PACK_WORDS:
            if word in text:
                errs.append('%s names a pack' % os.path.relpath(p, ROOT))
    for e in errs:
        print(e)
    bad = ids(True) if rows else 1
    print('spell vfx: %d effects %d..%d, %d projectiles, %s' % (n, FIRST, FIRST + n - 1, len(rows) - n,
                                                             'OK' if not errs and not bad else 'PROBLEMS'))
    return 1 if errs or bad else 0


# the pack names, split so this file does not name them either (docs/CREDITS.md does)
PACK_WORDS = ['ig' + 'nis', 'um' + 'bra', 'mor' + 'tis', 'hal' + 'low v', 'arc' + 'light']


def live(dat_path, spr_path):
    """the pair holds each piece at its id: size, phases, durations and the pixels of the sums"""
    import numpy as np
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    from import_vfx import render_back
    dat, spr = Dat(dat_path), Spr(spr_path)
    rows = read_spec()
    sums = read_sums()
    errs = []
    n = sum(1 for r in rows if r['kind'] == 'effect')
    if len(dat.effects) < FIRST + n - 1 or len(dat.missiles) != NEED_MISSILES:
        errs.append('the pair has %d effects and %d missiles' % (len(dat.effects), len(dat.missiles)))
    for r in rows if not errs else []:
        t = (dat.effects if r['kind'] == 'effect' else dat.missiles)[int(r['id']) - 1]
        ph, w, h = int(r['phases']), int(r['w']), int(r['h'])
        if (t.w, t.h, t.phases) != (w, h, ph):
            errs.append('%s: size or phases differ at %s' % (r['name'], r['id']))
            continue
        if t.anim and set(t.anim[3]) != {int(r['ms'])}:
            errs.append('%s: durations differ' % r['name'])
        back = render_back(t, spr, 1)
        if r['kind'] == 'effect':
            strip = np.concatenate([back[(f, 0, 0, 0)] for f in range(ph)], axis=1)
        else:
            strip = np.zeros((3 * h * 32, 3 * w * 32 * ph, 4), np.uint8)
            for (f, x, y, _l), img in back.items():
                strip[y * h * 32:(y + 1) * h * 32, (x * ph + f) * w * 32:(x * ph + f + 1) * w * 32] = img
        strip = strip.copy()
        strip[strip[..., 3] == 0] = 0
        if digest(strip) != sums.get(r['name']):
            errs.append('%s: pixels differ from the sum' % r['name'])
    for e in errs:
        print(e)
    print('spell vfx live: %d effects at %d..%d, %d projectiles, %s' % (n, FIRST, FIRST + n - 1, len(rows) - n,
                                                                      'OK' if not errs else '%d problem(s)' % len(errs)))
    return 1 if errs else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=['build', 'check', 'ids', 'live'])
    ap.add_argument('rest', nargs='*')
    ap.add_argument('--src')
    ap.add_argument('--write', action='store_true')
    ap.add_argument('--check', action='store_true')
    a = ap.parse_args()
    if a.cmd == 'build':
        if not a.src or len(a.rest) != 3:
            sys.exit('build DAT SPR OUT_DIR --src DIR')
        return build(a.rest[0], a.rest[1], a.rest[2], a.src, a.write)
    if a.cmd == 'ids':
        return ids(a.check)
    if a.cmd == 'live':
        if len(a.rest) != 2:
            sys.exit('live DAT SPR')
        return live(*a.rest)
    return check()


if __name__ == '__main__':
    sys.exit(main())
