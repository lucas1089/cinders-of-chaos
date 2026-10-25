#!/usr/bin/env python3
"""Pair 41: the missiles of the purchased projectile pack redrawn from its native 32 px renders, and three of its
unused variants appended as new missiles (owner allowed new pairs without asking).

    python3 -I gen_pack41_missiles.py build --src DIR [--src DIR ...]   # cut the strips, write the spec and tables
    python3 -I gen_pack41_missiles.py build --src DIR ... --check       # rebuild in memory, compare with the repo and the disk
    python3 -I gen_pack41_missiles.py build --check                     # CI, no pack: the committed tables agree
    python3 -I gen_pack41_missiles.py measure --src DIR [--src DIR ...] # how far each variant's art reaches (no writes)

Why: pair 36 took the 64 px renders of the projectile pack and halved them (gen_pack36_fx.halve: a 2 x 2 mean, then
a dithered alpha). The pack also ships hand-tuned renders made at 32 px (sheets/32px, frames of 64 x 64 = 2 x 2 tiles,
pivot = the frame centre, 8 frames at 12 fps, rows E SE S SW W NW N NE). This redraws, in place, every missile id
pair 36 built from a halved 64 px variant, from the native 32 px frames of the same variant. Nothing is halved.

What it keeps from pair 36 (the same ids, so every script, monster and engine send shows the new art):
  * the 3 x 3 direction patterns: gen_pack27_fx.MISSILE_DIR maps the sheet rows (E SE S SW W NW N NE) onto the
    client's pattern cells (x west / centre / east, y north / centre / south); the centre cell repeats the south row;
  * the point: the pivot (frame pixel 32, 32) lands on (13, 13) of the tile, as in every pack import;
  * the cut: layers merged, frames trimmed, alpha 0 / 255 with the 4x4 Bayer dither of gen_pack27_fx.clean_alpha (the
    convention pairs 27 and 29 used on the same native renders);
  * ids 4..125: gen_pack36_fx.replaced_missile's rule (at most 2 x 2 tiles, send offset 0, 0);
  * ids 189..250 (the appended ones): the send offset (dx, dy) of art_import/pack36_missiles.csv, so the dx / dy of
    server/data/lib/chaos_pack36_fx_ids.lua stay right (at most 3 x 3 tiles). Art that reaches past the bottom-right
    tile is moved up and left as a whole, as replaced_missile does (the build prints every move).
The art does not sit in the centre 32 px of its 64 px frame: `measure` prints the share outside it per variant. The
frame is kept whole (the pivot-locked placement above), so nothing is cut at the centre.

Appended (NEW below): ids 251 and on, named in server/data/lib/chaos_pack41_fx_ids.lua. Ids 254 (the server's
CONST_ANI_WEAPONTYPE, "use the weapon's missile" in a combat's distance effect) and 255 (check_pair.py warns above 254)
stay free. No spell sends them yet.

Licence (docs/CREDITS.md "Projectiles"): use in games, modified or not, no attribution; no resale, redistribution or
sharing of the assets, even modified; never machine-learning training data. So nothing cut here is committed:
art_import/pack41_fx/ is ignored by git; committed are this script, the spec (names, sizes, offsets, frame counts),
pack41_fx.sums (sha256 of each strip's decoded pixels) and pack41_fx_sources.csv (name, pack, source variant). The
script reads the frames, alpha boxes and metadata only to place them; it never samples a palette or a style.
Deterministic: no randomness; Pillow 12.3.0 and numpy 2.5.3 (the CI pins).
"""
import argparse
import csv
import glob
import io
import json
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_pack27_fx as G  # noqa: E402
import gen_pack36_fx as P  # noqa: E402

ART = os.path.join(HERE, 'art_import')
OUT = os.path.join(ART, 'pack41_fx')
SPEC = os.path.join(ART, 'pack41_missiles.csv')
SOURCES = os.path.join(ART, 'pack41_fx_sources.csv')
SUMS = os.path.join(ART, 'pack41_fx.sums')
GITIGNORE_TEXT = ('# strips cut from the purchased projectile pack: not to be redistributed, never committed '
                  '(gen_pack41_missiles.py)\n*\n!.gitignore\n')
PACK = 'projectiles'
PACK_NAME = 'Projectiles'
FIRST_NEW = 251              # pair 36 ends at 250
LAST_NEW = 253               # 254 is the server's CONST_ANI_WEAPONTYPE, 255 is above check_pair's limit
LICENCE = P.LICENCE
CENTRE = (16, 16, 48, 48)    # the centre 32 px of a 64 px frame

# NEW: variants of the pack no pair used, appended in this order: (effect id, variant, Lua name, note)
NEW = [
    ('proj_arrow', 'fire', 'proj_arrow_fire', 'fire arrow'),
    ('proj_arrow', 'frost', 'proj_arrow_frost', 'frost arrow'),
    ('proj_piercing_arrow', 'holy', 'proj_piercing_arrow_holy', 'holy piercing arrow'),
]


# ------------------------------------------------------------------------------------------------ the targets
def read_csv(path):
    with open(path, newline='') as fh:
        return list(csv.DictReader(fh))


def targets():
    """-> [(id, name, effect id, variant, pair 36 (w, h, dx, dy))] of every missile pair 36 built from a variant of
    the projectile pack (halved from the 64 px render), in id order; read from the committed pair 36 tables"""
    src = {r['name']: r['source'] for r in read_csv(os.path.join(ART, 'pack36_fx_sources.csv'))
           if r['kind'] == 'missile' and r['pack'] == PACK_NAME}
    out = []
    for r in read_csv(os.path.join(ART, 'pack36_replace.csv')):
        if r['kind'] == 'missile' and r['name'] in src:
            e, _, v = src[r['name']].partition('/')
            out.append((int(r['replace']), e, v, (int(r['w']), int(r['h']), int(r['dx']), int(r['dy']))))
    n = 188
    for r in read_csv(os.path.join(ART, 'pack36_missiles.csv')):
        n += 1
        if r['name'] in src:
            e, _, v = src[r['name']].partition('/')
            out.append((n, e, v, (int(r['w']), int(r['h']), int(r['dx']), int(r['dy']))))
    out.sort()
    return [(i, f'rep41_m{i}', e, v, geo) for i, e, v, geo in out]


def pick_rows():
    """-> the picks in spec order: ('replace' | 'new', id or None, name, effect, variant, pair 36 geometry or None)"""
    rows = [('replace', i, name, e, v, geo) for i, name, e, v, geo in targets()]
    rows += [('new', None, name, e, v, None) for e, v, name, _ in NEW]
    return rows


# ------------------------------------------------------------------------------------------------ the art
def load(srcs, eid, var):
    """-> ({row: [64 x 64 RGBA frame]} in the sheet's order E SE S SW W NW N NE, ms per frame); alpha 0 / 255"""
    d, rows = G.load(srcs, eid, var)
    assert d['category'] == 'projectiles' and d['tile_size'] == 32, (eid, var)
    assert (d['frame_width'], d['frame_height']) == (64, 64) and list(d['pivot']) == [32, 32], (eid, var, 'frame')
    assert [x.lower() for x in d['directions']] == G.DIRS8, (eid, var, d['directions'])
    assert len(rows) == 8 and all(len(f) == 8 for f in rows.values()), (eid, var)
    return {r: [G.clean_alpha(f) for f in fr] for r, fr in rows.items()}, int(round(1000 / d['fps']))


def patterns(rows):
    """the 3 x 3 pattern cells -> trimmed frames (the cell's direction row, gen_pack27_fx.MISSILE_DIR)"""
    pats = {pat: P.trim(rows[G.DIRS8.index(d)]) for pat, d in G.MISSILE_DIR.items()}
    n = min(len(v) for v in pats.values())
    return {k: v[:n] for k, v in pats.items()}, n


def fixed_missile(name, pats, n, dx, dy, max_tiles):
    """the patterns for an id whose send offset (dx, dy) is fixed: like gen_pack36_fx.replaced_missile, the whole art
    is shifted up / left (as one, all patterns together) when it reaches past the bottom-right tile, and cut only past
    max_tiles. -> (strip, w, h, share of art pixels cut, (sx, sy) the shift in pixels)"""
    allf = [f for pat in G.MISSILE_DIR for f in pats[pat]]
    placed, w, h, cut = P.anchored(allf, (32, 32), G.MISSILE_CENTRE, dx, dy, max_tiles, name)
    assert len(placed) == len(allf), (name, 'a missile frame cut away')
    shift = P.pull(allf, (32, 32), G.MISSILE_CENTRE, dx, dy)
    W, H = w * 32, h * 32
    strip = np.zeros((3 * H, 3 * W * n, 4), np.uint8)
    for k, pat in enumerate(G.MISSILE_DIR):
        for f in range(n):
            x, y = pat
            x0 = (x * n + f) * W
            strip[y * H:(y + 1) * H, x0:x0 + W] = placed[k * n + f]
    return strip, w, h, cut, shift


def convert(srcs, pick):
    """-> (spec row, strip, notes)"""
    kind, oid, name, eid, var, geo = pick
    rows, ms = load(srcs, eid, var)
    pats, n = patterns(rows)
    src = f'{eid}/{var}'
    notes = []
    if kind == 'replace':
        dx, dy = geo[2:]
        tiles = P.REPLACE_MAX_MISSILE_TILES if oid <= 188 else P.MAX_MISSILE_TILES
        strip, w, h, cut, shift = fixed_missile(name, pats, n, dx, dy, tiles)
        if cut > 0:
            notes.append(f'{cut:.1%} of the art cut')
        if shift != (0, 0):
            notes.append(f'art moved {shift[0]},{shift[1]} px (past the bottom-right tile)')
        if (w, h) != geo[:2]:
            notes.append(f'canvas {w}x{h}, pair 36 {geo[0]}x{geo[1]}')
        note = f'{eid} ({var}) native 32 px, id {oid}'
    else:
        got = P.missile_strip(name, rows, (32, 32), G.MISSILE_CENTRE)
        if got is None:
            raise SystemExit(f'{name}: larger than {P.MAX_MISSILE_TILES} tiles')
        strip, w, h, n, dx, dy = got
        note = dict((nm, t) for _, _, nm, t in NEW).get(name, name)
    row = dict(replace=oid if kind == 'replace' else '', kind='missile', name=name, file=f'pack41_fx/{name}.png',
               w=w, h=h, phases=n, ms=ms, dx=dx, dy=dy, note=f'{note} (from {src})')
    return row, strip, src, notes


# ------------------------------------------------------------------------------------------------ output tables
FIELDS = ['replace'] + G.FIELDS


def spec_text(rows):
    buf = io.StringIO()
    wr = csv.DictWriter(buf, fieldnames=FIELDS, lineterminator='\n')
    wr.writeheader()
    wr.writerows(rows)
    return buf.getvalue()


def sources_text(entries):
    buf = io.StringIO()
    wr = csv.writer(buf, lineterminator='\n')
    wr.writerow(['name', 'kind', 'pack', 'source', 'licence'])
    for row, src in entries:
        wr.writerow([row['name'], 'missile', PACK_NAME, src, LICENCE])
    return buf.getvalue()


def existing_names():
    """every ChaosVfxMissile name of the committed Lua tables (a new name must not shadow one)"""
    names = set()
    lib = os.path.join(HERE, '..', '..', '..', 'server', 'data', 'lib')
    for p in sorted(glob.glob(os.path.join(lib, 'chaos_*.lua'))):
        if os.path.basename(p) == 'chaos_pack41_fx_ids.lua':
            continue
        for line in open(p, encoding='utf-8', errors='replace'):
            if line.startswith('ChaosVfxMissile.'):
                names.add(line[len('ChaosVfxMissile.'):].split(' ')[0])
    return names


def read_sums():
    if not os.path.exists(SUMS):
        return {}
    return {l.split('  ', 1)[1].strip(): l.split('  ', 1)[0] for l in open(SUMS) if l.strip()}


def build(srcs, check):
    picks = pick_rows()
    rows, entries, sums, notes = [], [], {}, {}
    old = read_sums() if check else {}
    bad_art = []
    if not check:
        os.makedirs(OUT, exist_ok=True)
        open(os.path.join(OUT, '.gitignore'), 'w').write(GITIGNORE_TEXT)
    for p in picks:
        row, strip, src, nt = convert(srcs, p)
        if not check:
            Image.fromarray(strip).save(os.path.join(ART, row['file']), optimize=False)
        sums[row['file']] = G.digest(strip)
        rows.append(row)
        entries.append((row, src))
        if nt:
            notes[row['name']] = nt
        if check and old.get(row['file']) != sums[row['file']]:
            bad_art.append(row['file'])
    texts = {SPEC: spec_text(rows), SOURCES: sources_text(entries),
             SUMS: ''.join(f'{sums[r["file"]]}  {r["file"]}\n' for r in rows)}
    if check:
        bad = [p for p, t in texts.items() if not os.path.exists(p) or open(p, newline='').read() != t]
        for p in bad:
            print('differs:', os.path.relpath(p, HERE))
        for f in bad_art:
            print('strip differs:', f)
        print(f'pack41: {len(rows)} strips rebuilt, {"OK" if not (bad or bad_art) else "DIFFERS"}')
        return 1 if bad or bad_art else 0
    for p, t in texts.items():
        open(p, 'w', newline='').write(t)
    for n, t in sorted(notes.items()):
        print(f'{n}: {"; ".join(t)}')
    nrep = sum(1 for r in rows if r['replace'])
    print(f'{len(rows)} strips: {nrep} redrawn in place, {len(rows) - nrep} appended '
          f'(ids {FIRST_NEW}..{FIRST_NEW + len(rows) - nrep - 1})')
    return 0


def check_without_art():
    """CI: spec, sources and sums name the same things; the targets are exactly pair 36's projectile missiles; new ids
    and names free; geometry of the appended ones equals pair 36's"""
    errs = []
    if not all(os.path.exists(p) for p in (SPEC, SOURCES, SUMS)):
        print('pack41: missing spec, sources or sums')
        return 1
    rows = read_csv(SPEC)
    want = pick_rows()
    if [r['name'] for r in rows] != [p[2] for p in want]:
        errs.append('pack41_missiles.csv does not list the pair 36 projectile missiles and the NEW picks in order')
    ids = [int(r['replace']) for r in rows if r['replace']]
    if len(set(ids)) != len(ids):
        errs.append('a missile id is redrawn twice')
    new = [r for r in rows if not r['replace']]
    if len(new) != len(NEW) or FIRST_NEW + len(new) - 1 > LAST_NEW:
        errs.append(f'new missiles must be ids {FIRST_NEW}..{LAST_NEW} at most')
    taken = existing_names()
    for r in new:
        if r['name'] in taken:
            errs.append(f"{r['name']}: name already used in another Lua table")
    for r, p in zip(rows, want):
        w, h, dx, dy = int(r['w']), int(r['h']), int(r['dx']), int(r['dy'])
        if not (0 <= dx < w and 0 <= dy < h) or w > 3 or h > 3:
            errs.append(f"{r['name']}: size or offset outside")
        if r['replace'] and int(r['replace']) <= 188 and (dx, dy) != (0, 0):
            errs.append(f"{r['name']}: an in-place stock missile has send offset 0, 0")
        if r['replace'] and int(r['replace']) > 188 and p[5] and (dx, dy) != p[5][2:]:
            errs.append(f"{r['name']}: send offset differs from pair 36 (the Lua offsets would be wrong)")
    src = read_csv(SOURCES)
    if [s['name'] for s in src] != [r['name'] for r in rows]:
        errs.append('pack41_fx_sources.csv does not list the spec names')
    sums = [l.split('  ', 1)[1].strip() for l in open(SUMS) if l.strip()]
    if sums != [r['file'] for r in rows]:
        errs.append('pack41_fx.sums does not list the spec files in order')
    have = [r['file'] for r in rows if os.path.exists(os.path.join(ART, r['file']))]
    if have:
        want_sums = read_sums()
        for f in have:
            a = np.asarray(Image.open(os.path.join(ART, f)).convert('RGBA'))
            if G.digest(a) != want_sums.get(f):
                errs.append(f'{f}: differs from its sum')
    for e in errs:
        print(e)
    print(f'pack41: {len(rows)} missiles, {len(have)} strips on disk checked, '
          f"{'OK' if not errs else f'{len(errs)} problem(s)'}")
    return 1 if errs else 0


def measure(srcs):
    """per variant the pack holds: the union box of its art in the 64 x 64 frame and the share of opaque pixels
    outside the centre 32 x 32; the targets and NEW picks marked"""
    used = {(p[3], p[4]): p[0] for p in pick_rows()}
    paths = []
    for s in srcs:
        paths += glob.glob(os.path.join(s, '**', 'sheets', '32px', 'projectiles', '*', '*', '*.json'), recursive=True)
    keys = sorted({(json.load(open(p))['id'], json.load(open(p))['variant']) for p in paths})
    for eid, var in keys:
        rows, _ = load(srcs, eid, var)
        a = np.stack([f[:, :, 3] > 0 for fr in rows.values() for f in fr])
        ys, xs = np.nonzero(a.any(0))
        x0, y0, x1, y1 = CENTRE
        inside = int(a[:, y0:y1, x0:x1].sum())
        tot = int(a.sum())
        print(f'{eid}/{var}: box {xs.min()},{ys.min()}..{xs.max() + 1},{ys.max() + 1}  outside the centre 32 px '
              f'{1 - inside / tot:.0%}  {used.get((eid, var), "unused")}')
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=['build', 'measure'])
    ap.add_argument('--src', action='append', default=[])
    ap.add_argument('--check', action='store_true')
    a = ap.parse_args()
    if a.cmd == 'measure':
        return measure(a.src)
    if not a.src:
        if not a.check:
            sys.exit('build needs --src (or --check alone)')
        return check_without_art()
    return build(a.src, a.check)


if __name__ == '__main__':
    sys.exit(main())
