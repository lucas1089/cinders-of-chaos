#!/usr/bin/env python3
"""Pair 27 trial: a catacomb boss look and catacomb decoration from the owner's licensed monster and tile kit.

    python3 -I gen_assets_art.py build --src DIR          # DIR holds the sources under the names of SOURCES
                                                         #   -> art_import/assets_art/<key>.png (ignored by git)
                                                         #   + art_import/assets_art.csv, assets_art.sums,
                                                         #     assets_art_sources.csv, monster_looks/assets_art_picks.csv
    python3 -I gen_assets_art.py build --src DIR --check  # rebuild in memory, compare everything
    python3 -I gen_assets_art.py build --check            # CI, without the sources: spec, sources and picks match the
                                                         #   tables; sheets on disk (if any) match the sums
    python3 -I gen_assets_art.py preview --out DIR --dat P/Tibia.dat --spr P/Tibia.spr

Source and licence: the owner's Google Drive folder "ots/assets" (kit added 2026-10-15; the pack credited
in docs/CREDITS.md, same drop and licence file). Licence: use in unlimited commercial
projects (games included), modified or not, no attribution needed; no reselling, redistributing, sublicensing or
sharing of the assets themselves; no machine-learning training. Shipping converted frames inside the game client is
use in a game. So neither the sources nor the cut sheets are committed: art_import/assets_art/ is ignored by git and
art_import/assets_art.sums holds the sha256 of every sheet's decoded RGBA pixels. SOURCES names each file by a neutral
name, its Drive file id and md5.

Only files the Drive connector saves to disk could be taken (about 38 KB and up; smaller files come back inline and
are not transcribed). That leaves one monster (the headless rider, idle in four directions, walk north and west) and
four animated mechanics strips. The rest of the kit is listed in client/MANIFEST.md as pending.

Conversion: alpha under 12 cleared, nothing else changes the pixels.
  * hollow_rider (outfit 2234, 5x5 = 160 px cells, layers 1): idle group 4 phases (idle strips), walk group 4 phases
    (walk strips north and west; east and south take the idle strips, the kit has no walk strip we could fetch);
  * items (from 33986): cells cut from the strips, animated rows with all frames, static rows one frame;
    portal_open is a 160 px cell whose art fits a 96 px square at (64, 62): cut to 3x3.
Not in any published pair. Trial: appended to pair 27 (effects 674-758, missiles 154-160) with import_art_things.py;
server side behind ChaosAssetsArt.PAIR27 (off).
Deterministic: numpy and Pillow only.
"""
import argparse
import csv
import hashlib
import io
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
ART = os.path.join(HERE, 'art_import')
OUT_DIR = os.path.join(ART, 'assets_art')
THINGS = os.path.join(ART, 'assets_art.csv')
SUMS = os.path.join(ART, 'assets_art.sums')
SOURCES_CSV = os.path.join(ART, 'assets_art_sources.csv')
PICKS = os.path.join(HERE, 'monster_looks', 'assets_art_picks.csv')

FIRST_OUTFIT = 2234         # after pair 27's 2233 outfits
FIRST_ITEM = 33986          # after pair 27's 33985 items
SERVER_OFFSET = 3000
ALPHA_MIN = 12
PACK = 'Meadow Monsters Vol. 1'
LICENCE = ('purchased; commercial use in games, credit not required; no resale or redistribution of the files; '
           'no machine-learning use; author: docs/CREDITS.md')
DIRS = ('n', 'e', 's', 'w')
FIELDS = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode', 'server_id',
          'extra']
PICK_FIELDS = ['key', 'look', 'lib', 'lib_id', 'recolour', 'family', 'rank', 'monsters', 'description', 'edit']

# neutral source name -> (Drive file id, md5 of the file as downloaded)
SOURCES = {
    'rider_idle_n.png': ('1arVDov1zgemURCNFHtN1m1zYVm1TFXJS', '0d52cc2e6893b49fc02444fe4b1cd5a9'),
    'rider_idle_e.png': ('1e4cF5dhgfNOuB2HhiES_kn1onsDYO_3v', '919e7a8d677af30f829adbff6f058942'),
    'rider_idle_s.png': ('1DijlD8v9czjBiC6GqDZF8rl_gRvLIUKE', '25bfaac1950f430f3579601894020669'),
    'rider_idle_w.png': ('1BdrWA1IkuaKMbaqH-OLlcprPLPU00z_y', '585b462dda3ade97a4648a89df697872'),
    'rider_walk_n.png': ('1oTZX1SduoooWKLQoT96sflx-fCB9vRmu', '0af97a7a76bb1664b7cd20ab3d41e9a3'),
    'rider_walk_w.png': ('1y30XQ--9Xh0eypMFFl91fBZb7HRS677y', 'e1ed7f9b476d62d4ee7e9c5fba54b65e'),
    'portal_open.png': ('1zBB8xCL-XuqOYRQmZOSn1ZiqvrDhy5vJ', '9d5aea53e8833a93b4bc013404b35417'),
    'portal_closing.png': ('1yqQjBn3yrvgdDN_qhjKkCsq5DQqU8cSf', 'fb915d2963a3fbde786860615acf52b2'),
    'seal_breaking.png': ('1UwBEpKh3sBUDnafUFZ3mlaRj8nZfVXF2', '60101c72a01e52629df338c30e9b9011'),
    'sarcophagus_lid.png': ('18qibqe0XQTejVdGdpGOuIWCzxla64n0_', 'a26d2b2ced7a6d14f423f28d0cc64f34'),
}

# the monster look: key, name, cell px, frames per strip, idle sources, walk sources (n, e, s, w), ms, family,
# rank, monster, description
RIDER_MS = 140
LOOK = ('hollow_rider', 'Hollow Rider', 160, 4,
        ('rider_idle_n.png', 'rider_idle_e.png', 'rider_idle_s.png', 'rider_idle_w.png'),
        ('rider_walk_n.png', 'rider_idle_e.png', 'rider_idle_s.png', 'rider_walk_w.png'),
        'catacombs', 'boss', 'Hollow Rider',
        'headless rider with a pumpkin lantern head on a skeletal horse, 5x5')

# items: key, source, cell w, cell h (px), crop (x0, y0) inside the cell, size in tiles, frames ('all' or index),
# ms, name, kind, flags, family
ITEMS = [
    ('crypt_portal', 'portal_open.png', 160, 160, (64, 62), 3, 'all', 120, 'crypt portal', 'decor',
     'notmoveable light:3:204', 'catacomb'),
    ('crypt_portal_collapse', 'portal_closing.png', 128, 128, (0, 0), 4, 'all', 140, 'collapsing crypt portal',
     'decor', 'notmoveable light:2:204', 'catacomb'),
    ('crypt_portal_husk', 'portal_closing.png', 128, 128, (0, 0), 4, 7, 0, 'burnt-out portal ring', 'decor',
     'notmoveable', 'catacomb'),
    ('crypt_seal', 'seal_breaking.png', 96, 96, (0, 0), 3, 0, 0, 'sealed crypt hatch', 'stump',
     'bottom notwalkable notmoveable light:2:30', 'catacomb'),
    ('crypt_seal_breaking', 'seal_breaking.png', 96, 96, (0, 0), 3, 'all', 140, 'breaking crypt seal', 'stump',
     'bottom notwalkable notmoveable light:3:30', 'catacomb'),
    ('crypt_seal_open', 'seal_breaking.png', 96, 96, (0, 0), 3, 7, 0, 'open crypt hatch', 'decor',
     'notmoveable light:2:30', 'catacomb'),
    ('sarcophagus', 'sarcophagus_lid.png', 64, 96, (0, 0), (2, 3), 0, 0, 'sealed sarcophagus', 'stump',
     'bottom notwalkable notmoveable', 'catacomb'),
    ('sarcophagus_opening', 'sarcophagus_lid.png', 64, 96, (0, 0), (2, 3), 'all', 140, 'sarcophagus lid grinding open',
     'stump', 'bottom notwalkable notmoveable', 'catacomb'),
    ('sarcophagus_open', 'sarcophagus_lid.png', 64, 96, (0, 0), (2, 3), 7, 0, 'open sarcophagus', 'stump',
     'bottom notwalkable notmoveable', 'catacomb'),
]
FRAMES = 8          # every mechanics strip has 8 frames


# ------------------------------------------------------------------------------------------------ conversion
def load(src, name):
    path = os.path.join(src, name)
    data = open(path, 'rb').read()
    want = SOURCES[name][1]
    if hashlib.md5(data).hexdigest() != want:
        sys.exit('%s: md5 %s, the spec has %s (another file?)' % (path, hashlib.md5(data).hexdigest(), want))
    return clean(np.asarray(Image.open(io.BytesIO(data)).convert('RGBA')))


def clean(a):
    a = a.copy()
    a[a[..., 3] < ALPHA_MIN] = 0
    return a


def strip_frames(a, cw, ch):
    """a horizontal strip -> [frame] of cw x ch"""
    assert a.shape[0] == ch and a.shape[1] % cw == 0, (a.shape, cw, ch)
    return [a[:, i * cw:(i + 1) * cw] for i in range(a.shape[1] // cw)]


def tiles_of(size):
    return (size, size) if isinstance(size, int) else size


def item_frames(strip, row):
    key, _src, cw, ch, (x0, y0), size, frames, *_ = row
    tw, th = tiles_of(size)
    fr = strip_frames(strip, cw, ch)
    assert len(fr) == FRAMES, (key, len(fr))
    cut = [f[y0:y0 + th * 32, x0:x0 + tw * 32] for f in fr]
    for f in fr:     # nothing may be lost by the crop
        mask = np.zeros(f.shape[:2], bool)
        mask[y0:y0 + th * 32, x0:x0 + tw * 32] = True
        assert not f[~mask, 3].any(), (key, 'art outside the crop')
    return cut if frames == 'all' else [cut[frames]]


def look_sheet(idle, walk):
    """rows: the idle phases then the walk phases; columns: n, e, s, w"""
    rows = [[idle[d][p] for d in range(4)] for p in range(len(idle[0]))]
    rows += [[walk[d][p] for d in range(4)] for p in range(len(walk[0]))]
    return np.concatenate([np.concatenate(r, axis=1) for r in rows], axis=0)


def build_sheets(src):
    out = {}
    key, _n, c, nf, idle_src, walk_src, *_ = LOOK
    idle = [strip_frames(load(src, s), c, c) for s in idle_src]
    walk = [strip_frames(load(src, s), c, c) for s in walk_src]
    assert all(len(x) == nf for x in idle + walk)
    out[key] = look_sheet(idle, walk)
    cache = {}
    for row in ITEMS:
        if row[1] not in cache:
            cache[row[1]] = load(src, row[1])
        out[row[0]] = np.concatenate(item_frames(cache[row[1]], row), axis=1)
    return out


def expected_shapes():
    key, _n, c, nf, *_ = LOOK
    s = {key: (c * 2 * nf, c * 4)}
    for key, _s, _cw, _ch, _o, size, frames, *_ in ITEMS:
        tw, th = tiles_of(size)
        s[key] = (th * 32, tw * 32 * (FRAMES if frames == 'all' else 1))
    return s


def digest(a):
    return hashlib.sha256(np.ascontiguousarray(a).tobytes() + repr(a.shape).encode()).hexdigest()


# ------------------------------------------------------------------------------------------------ outputs
def things_rows():
    rows = []
    key, name, c, nf, *_ = LOOK
    t = c // 32
    durs = '/'.join(['%d' % RIDER_MS] * nf)
    rows.append([key, 'outfit', 'creature', name, 'assets_art/' + key, 0, 0, t, t, 4, '%d+%d' % (nf, nf), '', 'new',
                 '', 'layers=1|gtypes=0+1|exact=%d+%d|durs0=%s|durs1=%s|anim0=0:0:0|anim1=0:0:0' % (c, c, durs, durs)])
    for key, _s, _cw, _ch, _o, size, frames, ms, name, kind, flags, family in ITEMS:
        tw, th = tiles_of(size)
        ph = FRAMES if frames == 'all' else 1
        if ph > 1:
            flags += ' animateAlways'
        extra = 'family=%s|block=%d' % (family, int('notwalkable' in flags))
        if ph > 1:
            extra = 'ms=%d|' % ms + extra
        rows.append([key, 'item', kind, name, 'assets_art/' + key, 0, 0, tw, th, 1, ph, flags, 'new', '', extra])
    return rows


def picks_rows():
    key, name, _c, _nf, _i, _w, family, rank, monster, desc = LOOK
    return [[key, FIRST_OUTFIT, 'assets', SOURCES[LOOK[4][0]][0], '', family, rank, monster,
             '%s: %s' % (name, desc), 'kit strips; walk east and south from the idle strips']]


def sources_rows():
    out = [[LOOK[0], 'outfit', PACK, ' '.join(sorted(set(LOOK[4] + LOOK[5]))), LICENCE]]
    for key, src, *_ in ITEMS:
        out.append([key, 'item', PACK, src, LICENCE])
    return out


def csv_text(header, rows):
    s = io.StringIO()
    w = csv.writer(s, lineterminator='\n')
    w.writerow(header)
    w.writerows(rows)
    return s.getvalue()


def sums_text(sheets):
    return ''.join('%s  assets_art/%s.png\n' % (digest(sheets[k]), k) for k in expected_shapes())


def tables():
    return {THINGS: csv_text(FIELDS, things_rows()), PICKS: csv_text(PICK_FIELDS, picks_rows()),
            SOURCES_CSV: csv_text(['name', 'kind', 'pack', 'source', 'licence'], sources_rows())}


def check_rules(sheets):
    bad = []
    for key, shape in expected_shapes().items():
        a = sheets.get(key)
        if a is None:
            bad.append(key + ' missing')
        elif a.shape[:2] != shape:
            bad.append('%s: %s, the spec gives %s' % (key, a.shape[:2], shape))
        else:
            al = a[..., 3]
            if ((al > 0) & (al < ALPHA_MIN)).any():
                bad.append(key + ': alpha under %d left' % ALPHA_MIN)
            if (a[al == 0][:, :3] != 0).any():
                bad.append(key + ': colour under alpha 0')
            if not al.any():
                bad.append(key + ': empty')
    return bad


def read(path):
    return open(path, newline='').read() if os.path.exists(path) else None


def check_without_art():
    ok = True
    for path, text in tables().items():
        if read(path) != text:
            print(os.path.relpath(path, REPO), 'differs from the tables (run build --src)')
            ok = False
    sums = read(SUMS)
    if sums is None:
        print('missing', SUMS)
        return False
    sum_of = dict(reversed(line.split('  ', 1)) for line in sums.splitlines())
    want = ['assets_art/%s.png' % k for k in expected_shapes()]
    if sorted(sum_of) != sorted(want):
        print('sums do not list exactly the spec sheets')
        ok = False
    found = 0
    for f in want:
        p = os.path.join(ART, f)
        if os.path.exists(p):
            found += 1
            a = np.asarray(Image.open(p).convert('RGBA'))
            if digest(a) != sum_of.get(f):
                print(f, 'differs from assets_art.sums')
                ok = False
    print('assets art check (no sources): %d things, %d sheets on disk checked:' % (len(want), found),
          'OK' if ok else 'FAILED')
    return ok


def build(src, check):
    if not src:
        if not check:
            sys.exit('build needs --src (the kit files); without it only --check runs')
        return check_without_art()
    sheets = build_sheets(src)
    bad = check_rules(sheets)
    if bad:
        print('\n'.join(bad))
        return False
    files = dict(tables())
    files[SUMS] = sums_text(sheets)
    if check:
        ok = all(read(p) == t for p, t in files.items())
        for k, a in sheets.items():
            p = os.path.join(OUT_DIR, k + '.png')
            if os.path.exists(p) and not np.array_equal(np.asarray(Image.open(p).convert('RGBA')), a):
                print(k, 'sheet differs from a rebuild')
                ok = False
        print('assets art check:', 'OK' if ok else 'FAILED')
        return ok
    os.makedirs(OUT_DIR, exist_ok=True)
    for k, a in sheets.items():
        Image.fromarray(a, 'RGBA').save(os.path.join(OUT_DIR, k + '.png'), optimize=True)
    for p, t in files.items():
        open(p, 'w', newline='').write(t)
        print('wrote', os.path.relpath(p, REPO))
    return True


# ------------------------------------------------------------------------------------------------ previews
def cmd_preview(a):
    """the look in four directions (idle) and its walk facing north and west, a GIF of the walk; the items on a floor;
    a small crypt scene"""
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    from gen_owner_art import checker_ground, draw_thing, groups_of
    dat, spr = Dat(a.dat), Spr(a.spr)
    os.makedirs(a.out, exist_ok=True)
    sc = 2
    t = dat.outfit(FIRST_OUTFIT)
    gs = groups_of(dat, t)
    c = LOOK[2] // 32
    cv = checker_ground(4 * (c + 1) * 32, (c + 2) * 32)
    for d in range(4):
        draw_thing(cv, t, spr, (d * (c + 1) + c, c), d, 0, group=gs[0])
    cv.resize((cv.width * sc, cv.height * sc), Image.NEAREST).save(os.path.join(a.out, 'look_%d_%s_dirs.png' % (
        FIRST_OUTFIT, LOOK[0])))
    for d, dn in ((0, 'n'), (1, 'e'), (2, 's'), (3, 'w')):
        frames = []
        for p in range(LOOK[3]):
            f = checker_ground((c + 2) * 32, (c + 2) * 32)
            draw_thing(f, t, spr, (c, c), d, p, group=gs[1])
            frames.append(f.resize((f.width * sc, f.height * sc), Image.NEAREST).convert('RGB'))
        frames[0].save(os.path.join(a.out, 'look_%d_%s_walk_%s.gif' % (FIRST_OUTFIT, LOOK[0], dn)), save_all=True,
                       append_images=frames[1:], duration=RIDER_MS, loop=0)
    n = len(ITEMS)
    cv = checker_ground(n * 5 * 32, 6 * 32)
    for k in range(n):
        it = dat.items[FIRST_ITEM + k - 100]
        draw_thing(cv, it, spr, (k * 5 + 4, 4), 0, 0)
    cv.resize((cv.width * sc, cv.height * sc), Image.NEAREST).save(os.path.join(a.out, 'items.png'))
    scene = checker_ground(16 * 32, 12 * 32)
    place = [(0, (5, 5)), (6, (9, 4)), (8, (12, 4)), (3, (4, 10)), (5, (8, 10)), (2, (14, 10))]
    for k, xy in place:
        draw_thing(scene, dat.items[FIRST_ITEM + k - 100], spr, xy, 0, 0)
    draw_thing(scene, t, spr, (12, 9), 3, 0, group=gs[0])
    scene.resize((scene.width * sc, scene.height * sc), Image.NEAREST).save(os.path.join(a.out, 'crypt_scene.png'))
    print('previews in', a.out)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('--src')
    b.add_argument('--check', action='store_true')
    p = sub.add_parser('preview')
    p.add_argument('--out', required=True)
    p.add_argument('--dat', required=True)
    p.add_argument('--spr', required=True)
    a = ap.parse_args()
    if a.cmd == 'preview':
        cmd_preview(a)
    elif not build(a.src, a.check):
        sys.exit(1)


if __name__ == '__main__':
    main()
