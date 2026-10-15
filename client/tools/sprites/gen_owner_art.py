#!/usr/bin/env python3
"""Owner art of 2026-10-15: monster looks, wings and decoration from the owner's sheets, ready for import_art_things.py.

Source and licence: the owner's Google Drive folder "ots" (files added 2026-10-15; the owner confirmed the art is their
own or commissioned and free to use for monsters and variants, outfits and wings as cosmetics, decoration and map
items). The Drive titles are not copied here; SOURCES names each file by a neutral name, its Drive file id and md5.

    python3 -I gen_owner_art.py build --src DIR        # DIR holds the sources under the names of SOURCES
    python3 -I gen_owner_art.py build --check          # CI: the committed sheets, things file and picks match the spec
    python3 -I gen_owner_art.py build --src DIR --check   # rebuild from the sources, compare pixel for pixel
    python3 -I gen_owner_art.py preview --out DIR --dat P/Tibia.dat --spr P/Tibia.spr [--before-dat D --before-spr S]

The sources (all RGBA PNG):
  monster sheets, 64 px cells (2x2): 8 x 5 cells; rows 0-3 the walk of north, east, south, west (8 phases), row 4 the
      idle frame of each direction (columns 0-3);
  monster grids (drakes 64 px, lions 128 px = 4x4): one column per direction (north, east, south, west), one row per
      walk phase (3); the idle frame is walk phase 0;
  wings grids, 96 px cells (3x3): one column per direction, one row per phase (9, 8 or 5), animated always. The six
      feather wings drew the east column again as the west one (the wings point the same way), so their west column
      is the east one mirrored about the wearer's axis (the mean art centre of north and south), moved back inside the
      cell if a tip would leave it (`west_from_east`);
  cacti: 45 plants on a 640 x 320 sheet, not on a cell grid: cut as blobs (8-connected after a 2 px grouping), each on
      a 2x2 canvas, its foot (the lowest rows' mean x) on the item's own tile (x 48) and its lowest row on y 61;
  waypoint: a 96 x 5760 strip, 60 frames of a 3x3 floor seal (stone ring, cyan rune light), animated.
Alpha under 12 is cleared (soft edges of the lions and the wings' glow stay); nothing else changes the pixels.

Outputs (committed):
  art_import/owner_art/<key>.png   one sheet per look in import_art_things.py's outfit layout (layers=1: one row per
                                   frame group and phase, idle first; one column per direction)
  art_import/owner_art/cacti.png   the 45 plants side by side, 64 px each (items)
  art_import/owner_art/waypoint.png  the 60 frames side by side (one item, 60 phases)
  art_import/owner_art.csv         the things file: outfits 2213-2233 (after pair 25's 2212), items 33940-33985
                                   (after pair 25's 33939), server id = client id + 3000
  monster_looks/owner_art_picks.csv  picks.csv rows of the 21 looks (families hunt, dungeonboss, storewings, exclusive);
                                   appended to picks.csv when pair 26 is published (client/MANIFEST.md "Owner art")
Append to a pair (pair 25 = things_custom25):
    python3 -I import_art_things.py --ours-dat P/Tibia.dat --ours-spr P/Tibia.spr --out-dir NEW \
        --things art_import/owner_art.csv --first-item 33940 --first-outfit 2213 --expect-items 33939 \
        --manifest-out ../../../server/data/items/owner_decor.csv
Deterministic: numpy and Pillow only (CI pins Pillow 12.3.0 / numpy 2.5.3).
"""
import argparse
import csv
import hashlib
import io
import os
import sys
from collections import deque

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
ART = os.path.join(HERE, 'art_import')
OUT_DIR = os.path.join(ART, 'owner_art')
THINGS = os.path.join(ART, 'owner_art.csv')
PICKS = os.path.join(HERE, 'monster_looks', 'owner_art_picks.csv')

FIRST_OUTFIT = 2213         # after things_custom25's 2212 outfits
FIRST_ITEM = 33940          # after things_custom25's 33939 items
SERVER_OFFSET = 3000
ALPHA_MIN = 12
DIRS = ('north', 'east', 'south', 'west')
FIELDS = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode', 'server_id',
          'extra']
PICK_FIELDS = ['key', 'look', 'lib', 'lib_id', 'recolour', 'family', 'rank', 'monsters', 'description', 'edit']

# neutral source name -> (Drive file id, md5 of the file as downloaded)
SOURCES = {
    'lion_holy.png': ('1-HtjiBooNgAuy894uX4xRLjGeWUGIsWL', '3976802a833a638391e6cd4889adfaed'),
    'lion_spectral.png': ('16r3CdnhzkixURGtwV9EqyxdDrmr52j-m', 'fdc4a32f4ba04423305d1a1cf02aa35f'),
    'lion_fire.png': ('1YEkgl-Rr6jsfvJBK4uUxuJaIPRhb_uVf', '6ca16cb19980842bd608246db6e09616'),
    'lion_emerald.png': ('19uJ2ceWbmbb-Fh_Yl09iCPexiZxlO9x0', '9d5a8eb2cc044412ef7d6d44132e3152'),
    'drake_pyre.png': ('1qZcMNdnyo8T_HvXrxRvIVwca8UTgX-Qu', 'ccec39f7c0d8e79c203d3235954944b3'),
    'drake_gold.png': ('1X-hZ59d0km5kG-O58Nrcbo1LS6m2SGdL', '3ee7847ed6c16eeebf61aa3d79db0406'),
    'golem_magma.png': ('1SzPpRo8650ysMNcDBsk1x0mjRm_6YPlG', 'cc7fb6a3bbee3ddcf5c1e158156658e6'),
    'golem_ice.png': ('1gYV8DE15cqrcTbkOaR8JxrX6ve4OWOSi', '462684b40f83df704e00432474aa6385'),
    'brute_fire.png': ('1M7-1ahkBtBTZf1xjH-qrtd_RBDbUwBQ3', '010b3378f5a0c607c702251f3a2a870a'),
    'dragon_ice.png': ('1ebH5KdJz4fSmfVVAuMvaAlliULmHQPmx', 'f4e03acc3ffaaa0e33e558a9e8a1df54'),
    'yeti_gold.png': ('10MrWbHh417Oks_OKvbOcNX-4iYssBr_B', 'e91324ffe0f41239979213802018c504'),
    'behemoth_gold.png': ('19eLhA9pBHXyc8E5YO697W67MlVuYd2b8', '0f6760f5aa6251d33649d6efed375f25'),
    'wings_feather_lime.png': ('16z5DsMgvLAu_2Yg8gyJIfx_a8zWad86s', 'edbf2a5a690597298fca42bdd5b7d7fe'),
    'wings_feather_teal.png': ('1krAfVoNdPrYVoxkuMvTxoiwVJKqqx1a7', '98f43cc4d66cd6e2375f1240e1fdeb11'),
    'wings_feather_violet.png': ('1JN3LrljYlRn90yh8B_FCK7Ou8pS4oPuC', 'df5c04592958b42c55b34de936db5b08'),
    'wings_feather_ember.png': ('1EETQR1CFFaeyKdsRqdBxFxLfT92Mnejd', '4730198e4a7c17b3d7a3dc2de9d4e416'),
    'wings_feather_verdant.png': ('1_CkGtqt41SgP0pBPbvDsAV0HN6zxZDhJ', '7ff9b9934788e5e7c7a31fe61fdb998c'),
    'wings_feather_crimson.png': ('1yzFxrCrb1YToXbE6Nx5-L_mU6CDWdmmh', '8ae78b1a1c2c475ab2fca6bd1c7aeb4e'),
    'wings_ornate_violet.png': ('1kRRVHUCdzoziMCefZNw49ydfXuDfivCd', '3d005feaf807d568bbd4b9dfb6eb5908'),
    'wings_ornate_ember.png': ('1xOEGBqdF8HHYNXcuh2fYMzsB_M82K3_Z', '9e34c8a49b4d628d30ca9f7d3c49f578'),
    'wings_moth_violet.png': ('1JP8_25agsCUfhs1Nd6d8A-861tanGTWD', '84ac5236f96dd042d075fcb6acc28e3d'),
    'cacti.png': ('1AwnPdmEHruGXWlo6VGX6yosk093NlNc0', '29fced508b3c7c58421b82d004cb3f1e'),
    'waypoint.png': ('1KalOCrV64b1nbLotYyYhuMYXbH6X3kwH', '2c6b778ba3026913c7633faa2a36ca17'),
}

# the 21 looks in look-id order (FIRST_OUTFIT + index):
# key, source, layout ('sheet8' | 'grid'), cell px, walk phases, name, family, monster (exact <monster name>) or use,
# description; wings: key, source, 'wings', 96, phases, name, family, use, description, ms, west_from_east
MONSTER_MS = 100            # walk phase time (the client steps the walk by distance; this is the idle animator's)
LOOKS = [
    ('lion_holy', 'lion_holy.png', 'grid', 128, 3, 'Gilded Lionlord', 'dungeonboss', 'Vaelith the Fallen Seraph',
     'white-maned lion lord in gold plate and a red cape, 4x4'),
    ('lion_spectral', 'lion_spectral.png', 'grid', 128, 3, 'Gravemane Spectre', 'dungeonboss', 'Ossivane the Gravecage',
     'blue spectral lion beast with glowing grave sigils, 4x4'),
    ('lion_furnace', 'lion_fire.png', 'grid', 128, 3, 'Furnace-heart Lion', 'dungeonboss', 'Forgewarden Kharzun',
     'lion beast of cracked basalt with molten veins, 4x4'),
    ('drake_pyre', 'drake_pyre.png', 'grid', 64, 3, 'Pyre Drake', 'dungeonboss', 'Azhkarrath the Chained Wyrm',
     'black-red wyrm with a burning mane'),
    ('lion_emerald', 'lion_emerald.png', 'grid', 128, 3, 'Emerald Ravager', 'hunt', 'Gloamfang Ravager',
     'green-maned lion beast studded with emerald crystals, 4x4'),
    ('golem_magma', 'golem_magma.png', 'sheet8', 64, 8, 'Magma Juggernaut', 'hunt', 'Cinderhorn Juggernaut',
     'magma stone golem with glowing seams'),
    ('brute_fire', 'brute_fire.png', 'sheet8', 64, 8, 'Cinder Brute', 'hunt', 'Cinderskull Reaver',
     'one-eyed brute of black-red rock, flames on its head'),
    ('golem_ice', 'golem_ice.png', 'sheet8', 64, 8, 'Rime Colossus', 'hunt', 'Silicron',
     'ice stone golem with frost spikes'),
    ('dragon_ice', 'dragon_ice.png', 'sheet8', 64, 8, 'Frostwing Vyrm', 'hunt', 'Vyrm',
     'pale blue ice dragon with long wings'),
    ('yeti_gold', 'yeti_gold.png', 'sheet8', 64, 8, 'Gilded Yeti', 'hunt', 'Winterstride',
     'golden-furred yeti'),
    ('behemoth_gold', 'behemoth_gold.png', 'sheet8', 64, 8, 'Gilded Behemoth', 'hunt', 'Bloodantler Fiend',
     'horned brute of golden hide'),
    ('drake_gold', 'drake_gold.png', 'grid', 64, 3, 'Gilded Drake', 'hunt', 'Mirecoil Wyrm',
     'golden wyrm with a feathered mane'),
]
WINGS = [
    ('wings_jadeleaf', 'wings_feather_lime.png', 9, 'Jadeleaf Pinions', 'storewings', 'store (Wings)',
     'lime feathered wings', 110, True),
    ('wings_tidewing', 'wings_feather_teal.png', 9, 'Tidewing Plumes', 'storewings', 'store (Wings)',
     'teal feathered wings with a soft glow', 110, True),
    ('wings_duskfeather', 'wings_feather_violet.png', 9, 'Duskfeather Wings', 'storewings', 'store (Wings)',
     'violet feathered wings with a soft glow', 110, True),
    ('wings_emberplume', 'wings_feather_ember.png', 9, 'Emberplume Wings', 'storewings', 'store (Wings)',
     'orange feathered wings with a soft glow', 110, True),
    ('wings_wildgrove', 'wings_feather_verdant.png', 9, 'Wildgrove Wings', 'storewings', 'store (Wings)',
     'green feathered wings with a soft glow', 110, True),
    ('wings_bloodfeather', 'wings_feather_crimson.png', 9, 'Bloodfeather Wings', 'storewings', 'store (Wings)',
     'crimson feathered wings with a soft glow', 110, True),
    ('wings_gloomgild', 'wings_ornate_violet.png', 8, 'Gloomgild Wings', 'exclusive', 'boss drop (Nyxareth)',
     'violet scaled wings on gilded bone roots with a violet gem', 120, False),
    ('wings_sunforged', 'wings_ornate_ember.png', 8, 'Sunforged Wings', 'exclusive', 'boss drop (the Cinderheart)',
     'ember scaled wings on gilded bone roots with a violet gem', 120, False),
    ('wings_starmoth', 'wings_moth_violet.png', 5, 'Starmoth Wings', 'exclusive', 'boss drop (the Ascended Omens)',
     'violet moth wings dusted with starlight', 140, False),
]
# the ornate wings stand 6 px left and 12 px higher than the stock and our other wings (fix_pair_warnings.py
# --scan-aura-displacement: art centre -25.6,-33.3 px against -17.8..-20.8,-17.8..-22.5); a shift of the art would cut
# their tips at the cell edge, so the dat moves them (displacement may be negative: drawn right and down)
WING_DISPLACEMENT = {'wings_gloomgild': (-6, -12), 'wings_sunforged': (-6, -12)}
WAYPOINT = ('waypoint_seal', 'waypoint.png', 60, 'waypoint seal', 100, 'notmoveable light:3:35')
# the 45 plants in sheet order (rows of the source, left to right): name; blocking = more than BLOCK_PX art pixels
CACTI = ['leaning cactus', 'leaning cactus', 'tall cactus', 'tall cactus', 'tall cactus', 'budding tall cactus',
         'round-topped cactus', 'flowering round-topped cactus', 'columnar cactus', 'flowering columnar cactus',
         'pale columnar cactus', 'flowering spiny cactus', 'barrel cactus', 'flowering cactus', 'blooming cactus',
         'spiny cactus', 'small columnar cactus', 'flowering spiny cactus', 'small columnar cactus',
         'flowering dark cactus', 'potted flower', 'dark agave', 'desert shrub', 'potted agave', 'dry shrub',
         'succulent', 'thorny shrub', 'potted aloe', 'withered cactus', 'succulent', 'potted grass',
         'flowering cactus', 'potted succulent', 'flowering succulent', 'barrel cactus', 'flowering barrel cactus',
         'flowering prickly cactus', 'prickly pear', 'round cactus', 'round cactus', 'thorn sprout', 'desert grass',
         'flowering cactus', 'flowering shrub', 'blue agave']
BLOCK_PX = 1200
CACTUS_FOOT_X, CACTUS_FOOT_Y = 48, 61


# ------------------------------------------------------------------------------------------------ sources
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


def cells(a, c):
    """[row][col] -> c x c cell"""
    h, w = a.shape[:2]
    assert h % c == 0 and w % c == 0, (a.shape, c)
    return [[a[r * c:(r + 1) * c, k * c:(k + 1) * c] for k in range(w // c)] for r in range(h // c)]


def monster_frames(a, layout, c, walk):
    """-> (idle [dir], walk [phase][dir])"""
    g = cells(a, c)
    if layout == 'sheet8':
        assert len(g) == 5 and len(g[0]) == 8 and walk == 8, a.shape
        return [g[4][d] for d in range(4)], [[g[d][p] for d in range(4)] for p in range(8)]
    assert len(g[0]) == 4 and len(g) == walk, (a.shape, c, walk)
    return [g[0][d] for d in range(4)], [[g[p][d] for d in range(4)] for p in range(walk)]


def centre_x(cell):
    xs = np.nonzero(cell[..., 3] > 0)[1]
    return float(xs.mean()) if len(xs) else None


def mirror_about(cell, axis):
    """the cell mirrored about x = axis (whole pixels: x -> round(2 * axis) - x), moved back inside if needed"""
    w = cell.shape[1]
    xs = np.nonzero(cell[..., 3].any(axis=0))[0]
    s = int(round(2 * axis))
    lo, hi = s - xs.max(), s - xs.min()
    shift = -max(0, hi - (w - 1)) + max(0, -lo)
    out = np.zeros_like(cell)
    for x in xs:
        out[:, s - x + shift] = cell[:, x]
    return out


def wings_frames(a, phases, west_from_east):
    g = cells(a, 96)
    assert len(g) == phases and len(g[0]) == 4, (a.shape, phases)
    frames = [[g[p][d].copy() for d in range(4)] for p in range(phases)]
    if west_from_east:
        cs = [centre_x(frames[p][d]) for p in range(phases) for d in (0, 2)]
        axis = sum(cs) / len(cs)
        for p in range(phases):
            frames[p][3] = mirror_about(frames[p][1], axis)
    return frames


def blobs(a, group=2):
    """the art's blobs: [(y0, x0, y1, x1)] (inclusive), 8-connected after growing the art by `group` px; in sheet
    order: by the 64 px band of the lowest row, then left to right"""
    on = a[..., 3] > 0
    h, w = on.shape
    grown = on.copy()
    for dy in range(-group, group + 1):
        for dx in range(-group, group + 1):
            sh = np.zeros_like(on)
            sh[max(0, dy):h + min(0, dy), max(0, dx):w + min(0, dx)] = on[max(0, -dy):h - max(0, dy),
                                                                         max(0, -dx):w - max(0, dx)]
            grown |= sh
    lab = np.zeros((h, w), np.int32)
    out = []
    n = 0
    for y in range(h):
        for x in range(w):
            if grown[y, x] and not lab[y, x]:
                n += 1
                lab[y, x] = n
                q = deque([(y, x)])
                while q:
                    cy, cx = q.popleft()
                    for ny in (cy - 1, cy, cy + 1):
                        for nx in (cx - 1, cx, cx + 1):
                            if 0 <= ny < h and 0 <= nx < w and grown[ny, nx] and not lab[ny, nx]:
                                lab[ny, nx] = n
                                q.append((ny, nx))
    for i in range(1, n + 1):
        m = (lab == i) & on
        if m.any():
            ys, xs = np.nonzero(m)
            out.append((int(ys.min()), int(xs.min()), int(ys.max()), int(xs.max()), m))
    out.sort(key=lambda b: (b[2] // 64, b[1]))
    return out


def plant_canvas(a, b):
    """one blob on a 64 x 64 canvas: its foot (mean x of its lowest 4 rows) at CACTUS_FOOT_X, lowest row at
    CACTUS_FOOT_Y, kept inside"""
    y0, x0, y1, x1, m = b
    bw, bh = x1 - x0 + 1, y1 - y0 + 1
    assert bw <= 64 and bh <= 63, ('plant too large for 2x2', bw, bh)
    ys, xs = np.nonzero(m[y1 - 3:y1 + 1, :])
    foot = int(round(xs.mean()))
    left = min(max(0, CACTUS_FOOT_X - (foot - x0)), 64 - bw)
    top = CACTUS_FOOT_Y - bh + 1
    cv = np.zeros((64, 64, 4), np.uint8)
    part = a[y0:y1 + 1, x0:x1 + 1].copy()
    part[~m[y0:y1 + 1, x0:x1 + 1]] = 0
    cv[top:top + bh, left:left + bw] = part
    return cv


# ------------------------------------------------------------------------------------------------ outputs
def look_sheet(idle, walk):
    """rows: idle (one phase) then the walk phases; columns: north, east, south, west"""
    rows = [idle] + walk
    return np.concatenate([np.concatenate(r, axis=1) for r in rows], axis=0)


def wings_sheet(frames):
    return np.concatenate([np.concatenate(r, axis=1) for r in frames], axis=0)


def build_sheets(src):
    out = {}
    for key, name, layout, c, walk, *_ in LOOKS:
        idle, wk = monster_frames(load(src, name), layout, c, walk)
        out[key] = look_sheet(idle, wk)
    for key, name, phases, _n, _f, _u, _d, _ms, west in WINGS:
        out[key] = wings_sheet(wings_frames(load(src, name), phases, west))
    cac = load(src, 'cacti.png')
    bl = blobs(cac)
    assert len(bl) == len(CACTI), ('plants', len(bl), len(CACTI))
    out['cacti'] = np.concatenate([plant_canvas(cac, b) for b in bl], axis=1)
    wp = load(src, WAYPOINT[1])
    assert wp.shape == (96 * WAYPOINT[2], 96, 4), wp.shape
    out['waypoint'] = np.concatenate([wp[i * 96:(i + 1) * 96] for i in range(WAYPOINT[2])], axis=1)
    return out


def expected_shapes():
    s = {}
    for key, _n, _l, c, walk, *_ in LOOKS:
        s[key] = (c * (1 + walk), c * 4)
    for key, _n, phases, *_ in WINGS:
        s[key] = (96 * phases, 96 * 4)
    s['cacti'] = (64, 64 * len(CACTI))
    s['waypoint'] = (96, 96 * WAYPOINT[2])
    return s


def plant_blocks(cacti, i):
    return int((cacti[:, i * 64:(i + 1) * 64, 3] > 0).sum()) > BLOCK_PX


def things_rows(sheets):
    rows = []
    for key, _src, _l, c, walk, name, *_ in LOOKS:
        t = c // 32
        durs = '/'.join(['%d' % MONSTER_MS] * walk)
        rows.append([key, 'outfit', 'creature', name, 'owner_art/' + key, 0, 0, t, t, 4, '1+%d' % walk, '', 'new', '',
                     'layers=1|gtypes=0+1|exact=%d+%d|durs1=%s|anim1=0:0:0' % (c, c, durs)])
    for key, _src, phases, name, _f, _u, _d, ms, _w in WINGS:
        durs = '/'.join(['%d' % ms] * phases)
        disp = WING_DISPLACEMENT.get(key)
        flags = 'animateAlways' + (' displacement:%d:%d' % disp if disp else '')
        rows.append([key, 'outfit', 'wings', name, 'owner_art/' + key, 0, 0, 3, 3, 4, str(phases), flags, 'new',
                     '', 'gtypes=1|layers=1|exact=96|durs0=%s|anim0=0:0:0' % durs])
    cac = sheets['cacti']
    seen = {}
    for i, name in enumerate(CACTI):
        seen[name] = seen.get(name, 0) + 1
        block = plant_blocks(cac, i)
        rows.append(['cactus_%02d' % (i + 1), 'item', 'stump' if block else 'decor', name, 'owner_art/cacti', i * 64, 0,
                     2, 2, 1, 1, 'bottom notwalkable notmoveable' if block else 'notmoveable', 'new', '',
                     'family=cacti|block=%d' % block])
    key, _src, ph, name, ms, flags = WAYPOINT
    rows.append([key, 'item', 'decor', name, 'owner_art/waypoint', 0, 0, 3, 3, 1, ph, flags, 'new', '',
                 'ms=%d|family=waypoint|block=0' % ms])
    return rows


def picks_rows():
    out = []
    for i, (key, src, _l, c, _w, name, family, monster, desc) in enumerate(LOOKS):
        out.append([key, FIRST_OUTFIT + i, 'owner', SOURCES[src][0], '', family, 'boss' if family == 'dungeonboss'
                    else 'hunt', monster, '%s: %s' % (name, desc), 'owner-sheet'])
    for j, (key, src, _p, name, family, use, desc, _ms, west) in enumerate(WINGS):
        out.append([key, FIRST_OUTFIT + len(LOOKS) + j, 'owner', SOURCES[src][0], '', family, 'wings', use,
                    '%s: %s' % (name, desc), 'owner-sheet; west mirrored from east' if west else 'owner-sheet'])
    return out


def csv_bytes(header, rows):
    s = io.StringIO()
    w = csv.writer(s, lineterminator='\n')
    w.writerow(header)
    w.writerows(rows)
    return s.getvalue().encode()


def png_bytes(a):
    b = io.BytesIO()
    Image.fromarray(a, 'RGBA').save(b, format='PNG', optimize=False, compress_level=9)
    return b.getvalue()


def check_rules(sheets):
    bad = []
    for key, shape in expected_shapes().items():
        a = sheets.get(key)
        if a is None:
            bad.append(key + ' missing')
            continue
        if a.shape[:2] != shape:
            bad.append('%s: %s, the spec gives %s' % (key, a.shape[:2], shape))
            continue
        al = a[..., 3]
        if ((al > 0) & (al < ALPHA_MIN)).any():
            bad.append(key + ': alpha under %d left' % ALPHA_MIN)
        if (a[al == 0][:, :3] != 0).any():
            bad.append(key + ': colour under alpha 0')
    if not bad:
        for key, _n, _l, c, walk, *_ in LOOKS:
            a = sheets[key]
            for r in range(1 + walk):
                for d in range(4):
                    if not a[r * c:(r + 1) * c, d * c:(d + 1) * c, 3].any():
                        bad.append('%s: empty frame (row %d, %s)' % (key, r, DIRS[d]))
        for key, _n, phases, *_ in WINGS:
            a = sheets[key]
            for r in range(phases):
                for d in range(4):
                    if not a[r * 96:(r + 1) * 96, d * 96:(d + 1) * 96, 3].any():
                        bad.append('%s: empty frame (phase %d, %s)' % (key, r, DIRS[d]))
    return bad


def outputs(sheets):
    out = {os.path.join(OUT_DIR, k + '.png'): png_bytes(v) for k, v in sheets.items()}
    out[THINGS] = csv_bytes(FIELDS, things_rows(sheets))
    out[PICKS] = csv_bytes(PICK_FIELDS, picks_rows())
    return out


def read_sheets():
    out = {}
    for key in expected_shapes():
        p = os.path.join(OUT_DIR, key + '.png')
        if os.path.exists(p):
            out[key] = np.asarray(Image.open(p).convert('RGBA'))
    return out


def cmd_build(a):
    if a.src:
        sheets = build_sheets(a.src)
    elif a.check:
        sheets = read_sheets()
    else:
        sys.exit('build needs --src (the owner sheets); without it only --check runs')
    bad = check_rules(sheets)
    if bad:
        sys.exit('\n'.join(bad))
    for path, data in sorted(outputs(sheets).items()):
        rel = os.path.relpath(path, REPO)
        if a.check:
            if not os.path.exists(path):
                bad.append(rel + ' missing')
            elif path.endswith('.png'):
                have = np.asarray(Image.open(path).convert('RGBA'))
                want = np.asarray(Image.open(io.BytesIO(data)).convert('RGBA'))
                if have.shape != want.shape or not (have == want).all():
                    bad.append(rel + ' differs')
            elif open(path, 'rb').read() != data:
                bad.append(rel + ' differs')
        else:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, 'wb').write(data)
            print('wrote', rel)
    if bad:
        sys.exit('\n'.join(bad) + '\nrun gen_owner_art.py build --src DIR')
    if a.check:
        print('owner art: %d sheets, %d looks, %d items match the spec' % (
            len(sheets), len(LOOKS) + len(WINGS), len(CACTI) + 1))


# ------------------------------------------------------------------------------------------------ previews
def checker_ground(w, h, tile=32):
    """a dark stone floor of 32 px tiles with faint joints, so the tile grid shows"""
    g = np.zeros((h, w, 4), np.uint8)
    g[..., 3] = 255
    yy, xx = np.mgrid[0:h, 0:w]
    base = 44 + ((xx // tile + yy // tile) % 2) * 6
    g[..., 0] = base
    g[..., 1] = base - 4
    g[..., 2] = base - 8
    joint = (xx % tile == 0) | (yy % tile == 0)
    g[joint, :3] = 30
    return Image.fromarray(g, 'RGBA')


def draw_thing(canvas, t, spr, tile_xy, direction=2, phase=0, layer=0, group=None, dx=0, dy=0):
    """the client's rule: the w x h frame's bottom-right tile on the thing's tile (plus an offset)"""
    from datspr import sprite_index
    g = group or t
    W, H = g.w * 32, g.h * 32
    tx, ty = tile_xy
    x0, y0 = tx * 32 + 32 - W + dx, ty * 32 + 32 - H + dy
    px = direction if g.px >= 4 else 0
    for hh in range(g.h):
        for ww in range(g.w):
            sid = g.sprites[sprite_index(g, px, 0, 0, layer, phase, ww, hh)]
            a = spr.sprite(sid)
            if a is None:
                continue
            canvas.alpha_composite(Image.fromarray(a, 'RGBA'), (x0 + (g.w - 1 - ww) * 32, y0 + (g.h - 1 - hh) * 32))


def groups_of(dat, t):
    from import_outfits import parse_body
    return parse_body(dat, t)


def cmd_preview(a):
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    dat, spr = Dat(a.dat), Spr(a.spr)
    before = (Dat(a.before_dat), Spr(a.before_spr)) if a.before_dat else None
    os.makedirs(a.out, exist_ok=True)
    sc = 2
    looks = {k: FIRST_OUTFIT + i for i, (k, *_r) in enumerate(LOOKS)}
    # monsters: each look in the four directions on a tile floor (idle), its walk phases facing south, and the
    # current look of the monster (before pair) beside it
    for i, (key, _s, _l, c, walk, name, family, monster, _d) in enumerate(LOOKS):
        t = dat.outfit(FIRST_OUTFIT + i)
        gs = groups_of(dat, t)
        tiles_w = 4 * (c // 32 + 1) + walk * (c // 32 + 1) + 6
        th = c // 32 + 2
        cv = checker_ground(tiles_w * 32, th * 32)
        x = c // 32
        for d in range(4):
            draw_thing(cv, t, spr, (x, th - 2), d, 0, group=gs[0])
            x += c // 32 + 1
        for p in range(walk):
            draw_thing(cv, t, spr, (x, th - 2), 2, p, group=gs[1])
            x += c // 32 + 1
        if before:
            bd, bs = before
            import re
            xml = os.path.join(REPO, 'server', 'data', 'monster', 'monsters', 'chaos',
                               monster.lower().replace(' ', '_') + '.xml')
            m = re.search(r'<look type="(\d+)"', open(xml, encoding='utf-8').read()) if os.path.exists(xml) else None
            if m:
                bt = bd.outfit(int(m.group(1)))
                bg = groups_of(bd, bt)
                draw_thing(cv, bt, bs, (tiles_w - 1, th - 2), 2, 0, group=bg[0])
        cv.resize((cv.width * sc, cv.height * sc), Image.NEAREST).save(os.path.join(a.out, 'look_%d_%s.png' % (
            FIRST_OUTFIT + i, key)))
    # wings on a stock player look (128, the citizen), every direction, phase 0 and a GIF of the beat facing south
    player = dat.outfit(128)
    pg = groups_of(dat, player)[0]
    for j, (key, _s, phases, name, *_r) in enumerate(WINGS):
        look = FIRST_OUTFIT + len(LOOKS) + j
        t = dat.outfit(look)
        g = groups_of(dat, t)[0]
        ddx, ddy = WING_DISPLACEMENT.get(key, (0, 0))
        frames = []
        for p in range(phases):
            cv = checker_ground(4 * 4 * 32, 4 * 32)
            for d in range(4):
                tile = (d * 4 + 2, 2)
                # wings rule: frame px (x - 64 + 6, y - 64 + 6) from the tile top left (bottom-right anchor + GameWingOffset);
                # behind the body unless facing north
                if d != 0:
                    draw_thing(cv, t, spr, tile, d, p, group=g, dx=6 - ddx, dy=6 - ddy)
                draw_thing(cv, player, spr, tile, d, 0, group=pg)
                if d == 0:
                    draw_thing(cv, t, spr, tile, d, p, group=g, dx=6 - ddx, dy=6 - ddy)
            frames.append(cv.resize((cv.width * sc, cv.height * sc), Image.NEAREST))
        frames[0].save(os.path.join(a.out, 'wings_%d_%s.png' % (look, key)))
        frames[0].convert('RGB').save(os.path.join(a.out, 'wings_%d_%s.gif' % (look, key)), save_all=True,
                                      append_images=[f.convert('RGB') for f in frames[1:]], duration=120, loop=0)
    # decoration: every new item on a floor, client ids written under
    items = list(range(FIRST_ITEM, FIRST_ITEM + len(CACTI) + 1))
    cols = 12
    rows_n = (len(items) + cols - 1) // cols
    cv = checker_ground(cols * 3 * 32, rows_n * 3 * 32)
    for k, cid in enumerate(items):
        t = dat.items[cid - 100]
        draw_thing(cv, t, spr, ((k % cols) * 3 + 2, (k // cols) * 3 + 2), 0, 0)
    cv.resize((cv.width * sc, cv.height * sc), Image.NEAREST).save(os.path.join(a.out, 'decoration.png'))
    # a small desert scene: cacti round the waypoint seal
    scene = checker_ground(14 * 32, 10 * 32)
    wp = dat.items[FIRST_ITEM + len(CACTI) - 100]
    draw_thing(scene, wp, spr, (8, 6), 0, 0)
    spots = [(2, 2), (4, 1), (11, 2), (12, 4), (2, 6), (3, 8), (11, 8), (13, 7), (6, 3), (9, 9)]
    for k, (x, y) in enumerate(spots):
        draw_thing(scene, dat.items[FIRST_ITEM + (k * 4) % len(CACTI) - 100], spr, (x, y), 0, 0)
    scene.resize((scene.width * sc, scene.height * sc), Image.NEAREST).save(os.path.join(a.out, 'decoration_scene.png'))
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
    p.add_argument('--before-dat')
    p.add_argument('--before-spr')
    a = ap.parse_args()
    if a.cmd == 'preview':
        sys.path.insert(0, HERE)
    (cmd_build if a.cmd == 'build' else cmd_preview)(a)


if __name__ == '__main__':
    main()
