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

Pair 42 (second set, the same tool): the 21 remaining swaps the owner approved, from unused variants of the same pack: six
in-use stock ids (1 spear, 22 sniper arrow, 34 flaming arrow, 35 shiver arrow, 7 burst arrow, 6 poison arrow; same
rules as above: send offset 0, 0, at most 2 x 2 tiles, nothing cut) and fifteen named ones (SWAPS below; each registered in
server/data/lib/chaos_pack41_fx_ids.lua, no spell wired; send offset from the art, at most 3 x 3 tiles, nothing moved).
art_import/pack42_missiles.csv, pack42_fx_sources.csv and pack42_fx.sums; the strips go to the same ignored folder.
Which ids are free is the owner's check of the base server and of the repo: see the SWAPS comment and client/MANIFEST.md.

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
SPEC42 = os.path.join(ART, 'pack42_missiles.csv')
SOURCES42 = os.path.join(ART, 'pack42_fx_sources.csv')
SUMS42 = os.path.join(ART, 'pack42_fx.sums')
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

# SWAPS (pair 42): (missile id, pack effect id, variant, Lua name or None), in the owner's order. A None name redraws a
# stock id that is in use (the engine and the base data send it): offset 0, 0, at most 2 x 2 tiles, as pair 41. A name
# registers the missile in chaos_pack41_fx_ids.lua: its own send offset, at most 3 x 3 tiles.
# The owner asked for ids 62-76 (in this order: ball_lightning/thunder, blood_spike/necrotic, boulder/magma,
# flame_lance/spirit, poison_dart/necrotic, razor_leaf/sakura, shadow_bolt/blood, soul_skull/spirit, spirit_arrow/blood,
# spirit_arrow/gold, spirit_wisp/arcane, venom_glob/necrotic, void_orb/abyss, water_bolt/abyss, wind_blade/storm), "skip
# an id in use and take the next unused one". Checked on the base server (monster files send 62-74 and 76 by number, 75
# is free; the engine names none of them) and on the repo: 75 is free; the next unused ids above 76 are 100, 108, 111, 115
# and 137 up (116-136 and 153 up are named in our Lua tables; 77-114 minus those are sent by number in the base data).
SWAPS = [
    (1, 'proj_spear', 'steel', None),
    (22, 'proj_piercing_arrow', 'steel', None),
    (34, 'proj_arrow', 'fire', None),
    (35, 'proj_arrow', 'frost', None),
    (7, 'proj_split_arrow', 'fire', None),
    (6, 'proj_split_arrow', 'poison', None),
    (100, 'proj_ball_lightning', 'thunder', 'proj_ball_lightning_thunder'),   # wanted 62
    (108, 'proj_blood_spike', 'necrotic', 'proj_blood_spike_necrotic'),        # wanted 63
    (111, 'proj_boulder', 'magma', 'proj_boulder_magma'),                      # wanted 64
    (115, 'proj_flame_lance', 'spirit', 'proj_flame_lance_spirit'),            # wanted 65
    (137, 'proj_poison_dart', 'necrotic', 'proj_poison_dart_necrotic'),        # wanted 66
    (138, 'proj_razor_leaf', 'sakura', 'proj_razor_leaf_sakura'),              # wanted 67
    (139, 'proj_shadow_bolt', 'blood', 'proj_shadow_bolt_blood'),              # wanted 68
    (140, 'proj_soul_skull', 'spirit', 'proj_soul_skull_spirit'),              # wanted 69
    (141, 'proj_spirit_arrow', 'blood', 'proj_spirit_arrow_blood'),            # wanted 70
    (142, 'proj_spirit_arrow', 'gold', 'proj_spirit_arrow_gold'),              # wanted 71
    (143, 'proj_spirit_wisp', 'arcane', 'proj_spirit_wisp_arcane'),            # wanted 72
    (144, 'proj_venom_glob', 'necrotic', 'proj_venom_glob_necrotic'),          # wanted 73
    (145, 'proj_void_orb', 'abyss', 'proj_void_orb_abyss'),                    # wanted 74
    (75, 'proj_water_bolt', 'abyss', 'proj_water_bolt_abyss'),                 # wanted 75, free
    (146, 'proj_wind_blade', 'storm', 'proj_wind_blade_storm'),                # wanted 76
]
FIELDS42 = ['replace'] + G.FIELDS + ['lua']


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


def pick_rows42():
    """-> pair 42's picks in spec order: ('replace', id, name, effect, variant, (2, 2, 0, 0)) for an unnamed swap,
    ('named', id, name, effect, variant, Lua name) for a registered one; the stock rule's geometry is (w, h, dx, dy)"""
    out = []
    for oid, e, v, lua in SWAPS:
        name = f'rep42_m{oid}'
        out.append(('replace', oid, name, e, v, (2, 2, 0, 0)) if lua is None else ('named', oid, name, e, v, lua))
    return out


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
    """-> (spec row, strip, source, notes). Kinds: replace (an id redrawn in place, send offset fixed), new (appended),
    named (pair 42: a free id redrawn and given a Lua name, send offset from the art)"""
    kind, oid, name, eid, var, geo = pick
    rows, ms = load(srcs, eid, var)
    pats, n = patterns(rows)
    src = f'{eid}/{var}'
    notes = []
    lua = ''
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
        if kind == 'named':
            lua = geo
            note = f'{eid} ({var}) native 32 px, id {oid}'
        else:
            note = dict((nm, t) for _, _, nm, t in NEW).get(name, name)
    row = dict(replace=oid if kind in ('replace', 'named') else '', kind='missile', name=name,
               file=f'pack41_fx/{name}.png', w=w, h=h, phases=n, ms=ms, dx=dx, dy=dy, note=f'{note} (from {src})')
    if kind == 'named':
        row['lua'] = lua
    return row, strip, src, notes


# ------------------------------------------------------------------------------------------------ output tables
FIELDS = ['replace'] + G.FIELDS


def spec_text(rows, fields=None):
    buf = io.StringIO()
    wr = csv.DictWriter(buf, fieldnames=fields or FIELDS, lineterminator='\n')
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


def read_sums(path=SUMS):
    if not os.path.exists(path):
        return {}
    return {l.split('  ', 1)[1].strip(): l.split('  ', 1)[0] for l in open(path) if l.strip()}


def sets():
    """the two spec sets of this tool: pair 41 (the first build) and pair 42 (the swaps on top of pair 41)"""
    return [dict(label='pack41', picks=pick_rows, spec=SPEC, sources=SOURCES, sums=SUMS, fields=FIELDS),
            dict(label='pack42', picks=pick_rows42, spec=SPEC42, sources=SOURCES42, sums=SUMS42, fields=FIELDS42)]


def build_set(S, srcs, check):
    picks = S['picks']()
    rows, entries, sums, notes = [], [], {}, {}
    old = read_sums(S['sums']) if check else {}
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
    texts = {S['spec']: spec_text(rows, S['fields']), S['sources']: sources_text(entries),
             S['sums']: ''.join(f'{sums[r["file"]]}  {r["file"]}\n' for r in rows)}
    if check:
        bad = [p for p, t in texts.items() if not os.path.exists(p) or open(p, newline='').read() != t]
        for p in bad:
            print('differs:', os.path.relpath(p, HERE))
        for f in bad_art:
            print('strip differs:', f)
        print(f'{S["label"]}: {len(rows)} strips rebuilt, {"OK" if not (bad or bad_art) else "DIFFERS"}')
        return 1 if bad or bad_art else 0
    for p, t in texts.items():
        open(p, 'w', newline='').write(t)
    for n, t in sorted(notes.items()):
        print(f'{n}: {"; ".join(t)}')
    nrep = sum(1 for r in rows if r['replace'])
    print(f'{S["label"]}: {len(rows)} strips: {nrep} redrawn in place, {len(rows) - nrep} appended '
          f'(ids {FIRST_NEW}..{FIRST_NEW + len(rows) - nrep - 1})' if len(rows) > nrep else
          f'{S["label"]}: {len(rows)} strips: {nrep} redrawn in place')
    return 0


def build(srcs, check):
    return max(build_set(S, srcs, check) for S in sets())


def check_without_art():
    """CI: spec, sources and sums name the same things; the targets are exactly pair 36's projectile missiles; new ids
    and names free; geometry of the appended ones equals pair 36's; then pair 42's set"""
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
    errs += tables_agree(SPEC, SOURCES, SUMS, rows)
    errs += check_pair42(ids)
    for e in errs:
        print(e)
    have = sum(1 for p in (SPEC, SPEC42) for r in read_csv(p) if os.path.exists(os.path.join(ART, r['file'])))
    print(f'pack41 + pack42: {len(rows)} + {len(SWAPS)} missiles, {have} strips on disk checked, '
          f"{'OK' if not errs else f'{len(errs)} problem(s)'}")
    return 1 if errs else 0


def tables_agree(spec, sources, sums_path, rows):
    """sources and sums list the spec names / files in order; strips on disk equal their sums"""
    errs = []
    src = read_csv(sources)
    if [s['name'] for s in src] != [r['name'] for r in rows]:
        errs.append(f'{os.path.basename(sources)} does not list the spec names')
    sums = [l.split('  ', 1)[1].strip() for l in open(sums_path) if l.strip()]
    if sums != [r['file'] for r in rows]:
        errs.append(f'{os.path.basename(sums_path)} does not list the spec files in order')
    want_sums = read_sums(sums_path)
    for r in rows:
        f = r['file']
        if os.path.exists(os.path.join(ART, f)):
            a = np.asarray(Image.open(os.path.join(ART, f)).convert('RGBA'))
            if G.digest(a) != want_sums.get(f):
                errs.append(f'{f}: differs from its sum')
    return errs


def check_pair42(ids41):
    """pair 42's set: the spec lists SWAPS in order, every id is a stock or pair 36 / 41 missile (1..250) not redrawn by
    pair 41, a named swap has a free Lua name and a send offset inside its canvas (pair 41's 251-253 are untouched)"""
    errs = []
    if not all(os.path.exists(p) for p in (SPEC42, SOURCES42, SUMS42)):
        return ['pack42: missing spec, sources or sums']
    rows = read_csv(SPEC42)
    want = pick_rows42()
    if [r['name'] for r in rows] != [p[2] for p in want]:
        errs.append('pack42_missiles.csv does not list SWAPS in order')
    ids = [int(r['replace']) for r in rows]
    if len(set(ids)) != len(ids):
        errs.append('pack42: a missile id is redrawn twice')
    if set(ids) & set(ids41):
        errs.append(f'pack42: ids redrawn by pair 41 as well: {sorted(set(ids) & set(ids41))}')
    taken = existing_names()
    lua = [r['lua'] for r in rows if r['lua']]
    if len(set(lua)) != len(lua):
        errs.append('pack42: a Lua name twice')
    for r in rows:
        oid = int(r['replace'])
        w, h, dx, dy = int(r['w']), int(r['h']), int(r['dx']), int(r['dy'])
        if not 1 <= oid <= 250 or oid >= FIRST_NEW:
            errs.append(f"{r['name']}: id {oid} outside 1..250 (251-253 are pair 41's, 254 and 255 stay free)")
        if not (0 <= dx < w and 0 <= dy < h) or w > 3 or h > 3:
            errs.append(f"{r['name']}: size or offset outside")
        if not r['lua'] and (dx, dy) != (0, 0):
            errs.append(f"{r['name']}: an unnamed stock swap has send offset 0, 0")
        if not r['lua'] and (w > 2 or h > 2):
            errs.append(f"{r['name']}: an unnamed stock swap is at most 2 x 2 tiles")
        if r['lua'] and r['lua'] in taken:
            errs.append(f"{r['lua']}: name already used in another Lua table")
    errs += tables_agree(SPEC42, SOURCES42, SUMS42, rows)
    return errs


def measure(srcs):
    """per variant the pack holds: the union box of its art in the 64 x 64 frame and the share of opaque pixels
    outside the centre 32 x 32; the targets and NEW picks marked"""
    used = {(p[3], p[4]): p[0] for p in pick_rows() + pick_rows42()}
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
