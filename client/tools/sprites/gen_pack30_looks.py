#!/usr/bin/env python3
"""Pair 30, task T1: the 75 four-direction sheet creatures of the three monster packs (internal label `set30 monsters`)
as outfits 2237..2311 plus one corpse item each, client ids 34759..34833 (server id = client id + 3000).

    python3 -I gen_pack30_looks.py build --src DRIVEPACKS          # cut the sheets -> art_import/pack30_looks/<key>.png
                                                                   #   and <key>_corpse.png (ignored by git) + pack30_looks.csv,
                                                                   #   .sums, pack30_looks_sources.csv, pack30_tints.csv,
                                                                   #   monster_looks/pack30_picks.csv
    python3 -I gen_pack30_looks.py build --src DRIVEPACKS --check  # rebuild in memory, compare every committed file
    python3 -I gen_pack30_looks.py build --check                   # CI, no sources: the committed tables agree with each
                                                                   #   other and with pack30_looks.files; sheets on disk (if
                                                                   #   any) match the sums

Python: numpy and Pillow (CI uses the fx venv). Run with -I.

Import-only (PLAN_PAIR30 section 0). The packs ban machine-learning use and sharing: nothing here looks at, measures for
style, samples a palette from or previews a pack image. The script reads, per creature, `<folder>/sheets/*_sheet.png`
and `<folder>/animations.json` (geometry facts only: cell size, direction order, pose list, fps and the tint RGB values;
no description text is copied). Every file is addressed as pack slug + relative path and its md5 is checked against
art_import/pack30_looks.files before it is decoded. Neither the sources nor the cut sheets are committed.

Sort order (task S2 relies on it): creatures are sorted by pack slug, then by creature folder slug (plain string order,
so mon_a < mon_b < mon_c; the folder slug is the look key). Creature i (0 based) gets outfit 2237 + i and corpse item
34759 + i. The 75 look keys in that order are therefore fixed by pack30_looks.files; adding a pack or a creature moves
every later id and is refused (COUNT).

Format per creature (the sheet is exactly the dat outfit model): poses are rows (idle1, idle2, walk1-4, attack1-2,
death1-3), 8 columns of `cell` px: the left four are the base (up, right, down, left = dat directions n, e, s, w),
the right four the colour mask (head yellow, body red, legs green, feet blue). Used: idle1-2 (group 0, 2 phases) and
walk1-4 (group 1, 4 phases), 4 directions, 2 layers (layer 0 base, layer 1 mask in column 4 + direction); output
sheet = 6 rows x 8 columns of S x S tiles, which is what import_art_things.py reads for `2+4` with layers=2.
Not used: attack and death poses (a 10.98 outfit has only idle and walking), `*_shadow.png` (a flat ground shadow),
`*_glow.png` (an additive layer, 4 creatures have one; left out and noted in the sources CSV). Death3 facing down is
the corpse item.

Size rule (no viewing, no pack anchor): per creature the union alpha bounding box (alpha >= 1 after clearing alpha < 12)
over the 6 used poses and the 4 directions of the BASE layer. S = the smallest of 1, 2, 3, 4 tiles that holds the box
plus 1 px; 1..3, and 4 where a box of 96..125 px needs it (10 of the large creatures); more than 4 stops the build.
The box is cut out of every frame and placed with its right edge 1 px from the frame's right edge and its bottom edge 1 px from the bottom, the same shift in every frame and direction (no jitter, no
mirroring: east and west are drawn as the pack has them). Mask: alpha >= 128 becomes 255 and the pixel snaps to the
one marker colour within 40 per channel, every other mask pixel is cleared, so the mask holds at most four colours;
the mask is cut with the same box. Base: alpha < 12 cleared, nothing else touches the pixels.
Corpse: the death3 frame facing down (base layer), its own alpha box (S = 1..4 tiles), the same bottom-right
placement, one phase; item kind corpse, race=blood (the owner changes it per look with the monster file).

Overrides (art_import/pack30_overrides.csv, key = the look key): `rename` (our name), `dx`, `dy` (px shift of the box),
`tiles` (N or WxH, up to 4). `skip` is refused here (it would move every later id).

Tint presets: `tints` of animations.json give head/body/legs/feet RGB per scheme; pack30lib.rgb_to_outfit_index maps
each to the nearest of the 133 outfit colours -> art_import/pack30_tints.csv (key, scheme, head, body, legs, feet;
the first scheme of the pack is the default and also sits in the outfit row's extra head=|body=|legs=|feet=).
Timing: idle and walk ms from the pack's fps (3 -> 333 ms, 8 -> 125 ms).

Verification (client/MANIFEST.md "Pair 30 build"): import_art_things.py --things art_import/pack30_looks.csv
--first-outfit 2237 --first-item 34759 --expect-items 34758 (after the items-A..D blocks, or on the pair 29 base with
--first-item 34759 and the blank padding) checks every slot pixel-identical and runs check_pair.
"""
import argparse
import csv
import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pack30lib as L

HERE = os.path.dirname(os.path.abspath(__file__))
ART = L.ART
PICKS_DIR = os.path.join(HERE, 'monster_looks')

FIRST_OUTFIT = 2237
FIRST_ITEM = 34759
SERVER_OFFSET = 3000
COUNT = 75                       # outfits 2237..2311, corpses 34759..34833 (blocks looks and corpses-1)
LABEL = 'set30 monsters'
CAT = 'looks'
LICENCE = ('purchased; use in games incl. commercial, modified or recoloured; no attribution needed; no resale or '
           'sharing of the raw files; never AI training data or a style reference; studio: docs/CREDITS.md')
USED = ('idle1', 'idle2', 'walk1', 'walk2', 'walk3', 'walk4')
NDIR = 4
DIRECTIONS = ['up', 'right', 'down', 'left']
CORPSE_FLAGS = 'container forceuse notmoveable usable'
MAX_LOOK_TILES = L.MAX_TILES     # 4: ten of the 27 large creatures have a box of 96..125 px (3x3 holds 95); the limit of the plan is 4x4
THINGS_FIELDS = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode',
                 'server_id', 'extra']
TINT_FIELDS = ['key', 'scheme', 'head', 'body', 'legs', 'feet']
SOURCES_FIELDS = ['name', 'kind', 'pack', 'source', 'licence']
PICK_FIELDS = ['key', 'look', 'lib', 'lib_id', 'recolour', 'family', 'rank', 'monsters', 'description', 'edit']
PART = ('head', 'body', 'legs', 'feet')


class Paths:
    """Output locations (tests give a temporary art dir)."""

    def __init__(self, art=ART, picks_dir=PICKS_DIR):
        self.art = art
        self.out = os.path.join(art, 'pack30_looks')
        self.things = os.path.join(art, 'pack30_looks.csv')
        self.sums = os.path.join(art, 'pack30_looks.sums')
        self.sources = os.path.join(art, 'pack30_looks_sources.csv')
        self.tints = os.path.join(art, 'pack30_tints.csv')
        self.files = os.path.join(art, 'pack30_looks.files')
        self.overrides = os.path.join(art, 'pack30_overrides.csv')
        self.picks = os.path.join(picks_dir, 'pack30_picks.csv')


class Creature:
    def __init__(self, pack, folder, sheet, jpath, glow):
        self.pack, self.folder, self.sheet, self.json, self.glow = pack, folder, sheet, jpath, glow
        self.key = L.slugify(folder)


class Info:
    """what the tables need from one creature (from pixels in a build, from the committed CSVs in a check)."""

    def __init__(self, key, tw, th, ctw, cth, idle_ms, walk_ms, schemes):
        self.key, self.tw, self.th, self.ctw, self.cth = key, tw, th, ctw, cth
        self.idle_ms, self.walk_ms, self.schemes = idle_ms, walk_ms, schemes   # schemes: [(name, (h, b, l, f))]


# ------------------------------------------------------------------------------------------------ the creature list
def creatures_from_files(rows):
    """Creatures of a pack30_looks.files list, sorted by (pack slug, folder slug)."""
    by_path = {(r.slug, r.path): r for r in rows}
    out = []
    for r in rows:
        parts = r.path.split('/')
        if len(parts) == 3 and parts[1] == 'sheets' and parts[2].lower().endswith('_sheet.png'):
            folder = parts[0]
            jpath = folder + '/animations.json'
            if (r.slug, jpath) not in by_path:
                raise L.PackError('%s/%s: no animations.json beside the sheet' % (r.slug, folder))
            glow = [p for (s, p) in by_path if s == r.slug and p.startswith(folder + '/sheets/')
                    and p.lower().endswith('_glow.png')]
            out.append(Creature(r.slug, folder, r.path, jpath, bool(glow)))
    out.sort(key=lambda c: (c.pack, c.folder))
    keys = [c.key for c in out]
    if len(set(keys)) != len(keys):
        raise L.PackError('two creatures share a look key: %s' % sorted(k for k in keys if keys.count(k) > 1))
    return out


def check_count(creatures, count=COUNT):
    if len(creatures) != count:
        raise L.PackError('%d creatures, the id blocks hold exactly %d (outfits %d.., corpses %d..): a change here '
                          'moves every later id, ask the integrator' % (len(creatures), count, FIRST_OUTFIT, FIRST_ITEM))


# ------------------------------------------------------------------------------------------------ pixels
def load_geometry(path, md5):
    """animations.json after the md5 check: only the geometry facts (cell, directions, poses, fps, tints)."""
    import hashlib
    data = open(path, 'rb').read()
    if hashlib.md5(data).hexdigest() != md5:
        raise L.PackError('%s: md5 differs from the list' % path)
    d = json.loads(data.decode('utf-8'))
    cell = int(d['cell'])
    poses = list(d['poses'])
    if list(d['directions']) != DIRECTIONS:
        raise L.PackError('%s: directions %s, expected %s' % (path, d['directions'], DIRECTIONS))
    for p in USED + ('death3',):
        if p not in poses:
            raise L.PackError('%s: pose %s missing' % (path, p))
    schemes = list(d['schemes'])
    if not schemes or sorted(schemes) != sorted(d['tints']):
        raise L.PackError('%s: schemes and tints disagree' % path)
    tints = []
    for s in schemes:
        t = d['tints'][s]
        tints.append((L.slugify(s), tuple(L.rgb_to_outfit_index(tuple(int(v) for v in t[p])) for p in PART)))
    return {'cell': cell, 'poses': poses, 'idle_ms': L.fps_to_ms(d['fps']['idle']),
            'walk_ms': L.fps_to_ms(d['fps']['walk']), 'schemes': tints}


def split_sheet(sheet, geo, where):
    """-> (base, mask): dicts pose -> [4 cell arrays]; base alpha-cleaned, mask snapped to the four markers."""
    cell, poses = geo['cell'], geo['poses']
    if sheet.shape[:2] != (len(poses) * cell, 2 * NDIR * cell):
        raise L.PackError('%s: sheet %dx%d, expected %dx%d for %d poses of %d px' % (
            where, sheet.shape[1], sheet.shape[0], 2 * NDIR * cell, len(poses) * cell, len(poses), cell))
    base, mask = {}, {}
    for name in USED + ('death3',):
        r = poses.index(name)
        row = sheet[r * cell:(r + 1) * cell]
        base[name] = [L.clean_alpha(row[:, d * cell:(d + 1) * cell]) for d in range(NDIR)]
        mask[name] = [L.snap_mask(row[:, (NDIR + d) * cell:(NDIR + d + 1) * cell]) for d in range(NDIR)]
    return base, mask


def build_creature(src, c, rows_by_path, ov, private=None):
    """-> (Info, sheet array, corpse array) of one creature, or raises PackError."""
    where = '%s/%s' % (c.pack, c.folder)
    jr, sr = rows_by_path[(c.pack, c.json)], rows_by_path[(c.pack, c.sheet)]
    geo = load_geometry(L.source_path(src, c.pack, c.json, private), jr.md5)
    sheet = L.load_verified(L.source_path(src, c.pack, c.sheet, private), sr.md5)
    base, mask = split_sheet(sheet, geo, where)
    cell = geo['cell']
    frames = [base[p][d] for p in USED for d in range(NDIR)]
    box = L.union_bbox(frames)
    if box is None:
        raise L.PackError('%s: the six used poses are empty' % where)
    bw, bh = box[2] - box[0], box[3] - box[1]
    til = L.ov_get(ov, c.key, 'tiles')
    try:
        if til:
            tw, th = til
            if max(tw, th) > MAX_LOOK_TILES:
                raise L.PackError('%s: tiles override %dx%d above %d' % (c.key, tw, th, MAX_LOOK_TILES))
        else:
            tw = th = L.fit_tiles(bw, bh, margin=1, lo=1, hi=MAX_LOOK_TILES)
        dx, dy = L.ov_get(ov, c.key, 'dx', 0), L.ov_get(ov, c.key, 'dy', 0)
        S = L.TILE
        out = np.zeros((len(USED) * th * S, 2 * NDIR * tw * S, 4), np.uint8)
        for ri, p in enumerate(USED):
            for d in range(NDIR):
                for layer, src_cells in ((0, base), (1, mask)):
                    cellimg = L.place_bottom_right(src_cells[p][d], box, tw, th, 1, dx, dy)
                    x0 = (layer * NDIR + d) * tw * S
                    out[ri * th * S:(ri + 1) * th * S, x0:x0 + tw * S] = cellimg
        corpse_frame = base['death3'][2]
        cbox = L.alpha_bbox(corpse_frame)
        if cbox is None:
            raise L.PackError('%s: death3 facing down is empty' % where)
        ctw = cth = L.fit_tiles(cbox[2] - cbox[0], cbox[3] - cbox[1], margin=1, lo=1, hi=MAX_LOOK_TILES)
        corpse = L.place_bottom_right(corpse_frame, cbox, ctw, cth, 1)
    except L.PackError as e:
        raise L.PackError('%s (%s): %s' % (c.key, where, e))
    info = Info(c.key, tw, th, ctw, cth, geo['idle_ms'], geo['walk_ms'], geo['schemes'])
    return info, out, corpse


# ------------------------------------------------------------------------------------------------ tables
def name_of(key, ov):
    return L.ov_get(ov, key, 'rename') or L.humanize(key)


def things_rows(infos, ov):
    rows = []
    for i in infos:
        e = 'idle_ms=%d|walk_ms=%d|%s' % (i.idle_ms, i.walk_ms, '|'.join(
            '%s=%d' % (p, v) for p, v in zip(PART, i.schemes[0][1])))
        rows.append([i.key, 'outfit', 'creature', name_of(i.key, ov), 'pack30_looks/' + i.key, 0, 0, i.tw, i.th, 4,
                     '2+4', '', 'new', '', e])
    for i in infos:
        rows.append(['corpse_' + i.key, 'item', 'corpse', 'dead ' + name_of(i.key, ov).lower(),
                     'pack30_looks/%s_corpse' % i.key, 0, 0, i.ctw, i.cth, 1, 1, CORPSE_FLAGS, 'new', '', 'race=blood'])
    return rows


def tint_rows(infos):
    return [[i.key, name] + list(idx) for i in infos for name, idx in i.schemes]


def sources_rows(creatures):
    rows = []
    for c in creatures:
        note = ' (glow layer not used)' if c.glow else ''
        rows.append([c.key, 'outfit', LABEL, '%s/%s%s' % (c.pack, c.sheet, note), LICENCE])
    for c in creatures:
        rows.append(['corpse_' + c.key, 'item', LABEL, '%s/%s (death3 facing down)' % (c.pack, c.sheet), LICENCE])
    return rows


def picks_rows(infos, ov):
    rows = []
    for n, i in enumerate(infos):
        nm = name_of(i.key, ov)
        rows.append([i.key, FIRST_OUTFIT + n, 'pack30', '', '', 'gallery', 'gallery', '',
                     '%s: sheet look, %dx%d, %d tint schemes' % (nm, i.tw, i.th, len(i.schemes)),
                     'sheet look with colour mask'])
    return rows


def sums_lines(items):
    return L.sums_text(items)


def sheet_items(infos, sheets):
    """[(path, array)] in id order: the 75 sheets, then the 75 corpses."""
    out = [('pack30_looks/%s.png' % i.key, sheets[i.key][0]) for i in infos]
    out += [('pack30_looks/%s_corpse.png' % i.key, sheets[i.key][1]) for i in infos]
    return out


def all_tables(creatures, infos, ov, p, sheets=None):
    t = {p.things: L.csv_text(THINGS_FIELDS, things_rows(infos, ov)),
         p.tints: L.csv_text(TINT_FIELDS, tint_rows(infos)),
         p.sources: L.csv_text(SOURCES_FIELDS, sources_rows(creatures)),
         p.picks: L.csv_text(PICK_FIELDS, picks_rows(infos, ov))}
    if sheets is not None:
        t[p.sums] = sums_lines(sheet_items(infos, sheets))
    return t


# ------------------------------------------------------------------------------------------------ build and check
def read_files_list(p):
    rows = L.read_files(p.files)
    return rows, {(r.slug, r.path): r for r in rows}


def load_overrides(p):
    ov = L.load_overrides(p.overrides)
    for k, d in ov.items():
        if 'skip' in d:
            raise L.PackError('%s: skip would move every later id (pair 30 looks have fixed ids)' % k)
    return ov


def build_all(src, p, count=COUNT, private=None):
    rows, by_path = read_files_list(p)
    creatures = creatures_from_files(rows)
    check_count(creatures, count)
    ov = load_overrides(p)
    infos, sheets, errors = [], {}, []
    for c in creatures:
        try:
            info, sheet, corpse = build_creature(src, c, by_path, ov, private)
        except L.PackError as e:
            errors.append(str(e))     # report every creature that does not fit, not only the first
            continue
        infos.append(info)
        sheets[c.key] = (sheet, corpse)
    if errors:
        raise L.PackError('%d creature(s) stop the build:\n  %s' % (len(errors), '\n  '.join(errors)))
    return creatures, infos, sheets, ov


def write_png(path, a):
    Image.fromarray(a, 'RGBA').save(path, optimize=False, compress_level=9)


def write_all(p, tables, infos, sheets):
    os.makedirs(p.out, exist_ok=True)
    gi = os.path.join(p.out, '.gitignore')
    if not os.path.isfile(gi):
        with open(gi, 'w', newline='') as f:
            f.write('# cut from the purchased packs: not to be redistributed, never committed (gen_pack30_looks.py)\n*\n!.gitignore\n')
    for i in infos:
        write_png(os.path.join(p.out, i.key + '.png'), sheets[i.key][0])
        write_png(os.path.join(p.out, i.key + '_corpse.png'), sheets[i.key][1])
    for path, text in tables.items():
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w', newline='', encoding='utf-8') as f:
            f.write(text)


def read_text(path):
    return open(path, newline='', encoding='utf-8').read() if os.path.isfile(path) else None


def disk_digest(path):
    return L.digest(np.asarray(Image.open(path).convert('RGBA')))


def infos_from_tables(p):
    """The committed CSVs back into Info (the no-source check)."""
    with open(p.things, newline='', encoding='utf-8') as f:
        rows = list(csv.DictReader(f))
    outs = [r for r in rows if r['cat'] == 'outfit']
    itms = [r for r in rows if r['cat'] == 'item']
    with open(p.tints, newline='', encoding='utf-8') as f:
        tints = list(csv.DictReader(f))
    infos = []
    for o, it in zip(outs, itms):
        ex = dict(kv.split('=', 1) for kv in o['extra'].split('|') if '=' in kv)
        sch = [(t['scheme'], tuple(int(t[x]) for x in PART)) for t in tints if t['key'] == o['key']]
        infos.append(Info(o['key'], int(o['w']), int(o['h']), int(it['w']), int(it['h']),
                          int(ex['idle_ms']), int(ex['walk_ms']), sch))
    return infos, len(outs), len(itms)


def check_tables(p, src=None, count=COUNT, private=None):
    """-> [problem]. With src: full rebuild in memory and byte comparison; without: consistency of the committed files."""
    bad = []
    rows, by_path = read_files_list(p)
    creatures = creatures_from_files(rows)
    try:
        check_count(creatures, count)
    except L.PackError as e:
        bad.append(str(e))
    ov = load_overrides(p)
    if src:
        creatures, infos, sheets, ov = build_all(src, p, count, private)
        want = all_tables(creatures, infos, ov, p, sheets)
    else:
        if not os.path.isfile(p.things) or not os.path.isfile(p.tints):
            return bad + ['%s or %s missing (run build --src)' % (p.things, p.tints)]
        infos, no, ni = infos_from_tables(p)
        if no != ni or no != len(creatures) or [i.key for i in infos] != [c.key for c in creatures]:
            bad.append('%s: outfits/items do not match the creature list of %s' % (p.things, p.files))
            return bad
        sums = read_text(p.sums)
        want = all_tables(creatures, infos, ov, p)
        if sums is None:
            bad.append('%s missing' % p.sums)
        else:
            lines = [ln.split('  ', 1) for ln in sums.splitlines()]
            paths = [x[1] for x in lines]
            exp = ['pack30_looks/%s.png' % i.key for i in infos] + ['pack30_looks/%s_corpse.png' % i.key for i in infos]
            if paths != exp:
                bad.append('%s: paths are not the %d sheets then %d corpses in id order' % (p.sums, len(infos), len(infos)))
            else:
                found = 0
                for h, rel in lines:
                    f = os.path.join(p.art, rel)
                    if os.path.isfile(f):
                        found += 1
                        if disk_digest(f) != h:
                            bad.append('%s differs from %s' % (rel, os.path.basename(p.sums)))
                print('looks check: %d of %d sheets on disk checked against the sums' % (found, len(lines)))
        for k in range(len(infos)):
            i = infos[k]
            if not (1 <= i.tw <= MAX_LOOK_TILES and 1 <= i.th <= MAX_LOOK_TILES and
                    1 <= i.ctw <= MAX_LOOK_TILES and 1 <= i.cth <= MAX_LOOK_TILES):
                bad.append('%s: size out of 1..%d tiles' % (i.key, MAX_LOOK_TILES))
            if not i.schemes or any(not 0 <= v <= 132 for _, idx in i.schemes for v in idx):
                bad.append('%s: tint schemes' % i.key)
    for path, text in want.items():
        got = read_text(path)
        if got is None:
            bad.append('%s missing' % path)
        elif got != text:
            bad.append('%s differs from the generated text (run build)' % path)
    return bad


def run_build(src, p, check, count=COUNT, private=None):
    if check:
        bad = check_tables(p, src, count, private)
        for b in bad:
            print(b)
        print('pack30 looks check:', 'OK' if not bad else '%d problem(s)' % len(bad))
        return not bad
    if not src:
        raise L.PackError('build needs --src DRIVEPACKS (or --check)')
    creatures, infos, sheets, ov = build_all(src, p, count, private)
    tables = all_tables(creatures, infos, ov, p, sheets)
    write_all(p, tables, infos, sheets)
    sizes = {}
    for i in infos:
        sizes[(i.tw, i.th)] = sizes.get((i.tw, i.th), 0) + 1
    cs = {}
    for i in infos:
        cs[(i.ctw, i.cth)] = cs.get((i.ctw, i.cth), 0) + 1
    print('wrote %d sheets, %d corpses, %s' % (len(infos), len(infos), ', '.join(os.path.basename(x) for x in tables)))
    print('outfit sizes (tiles): %s; corpse sizes: %s; outfits %d..%d, corpses %d..%d' % (
        sorted(sizes.items()), sorted(cs.items()), FIRST_OUTFIT, FIRST_OUTFIT + len(infos) - 1, FIRST_ITEM,
        FIRST_ITEM + len(infos) - 1))
    return True


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('--src', help='the drivepacks folder')
    b.add_argument('--check', action='store_true')
    a = ap.parse_args(argv)
    try:
        ok = run_build(a.src, Paths(), a.check)
    except L.PackError as e:
        print('STOP:', e)
        return 1
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
