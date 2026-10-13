"""Build the 32x32 item dataset for the CNN critic and generator (writes one .npz outside git).

Sources, all read-only:
    --pair DIR       the live pair (Tibia.dat + Tibia.spr, e.g. things_custom23)
    --library DIR    a donor library folder (Tibia.dat, Tibia.spr, catalogue.csv), repeatable
    --icons DIR      the library item icon folder (catalogue.csv + <set>_32.png atlases), optional
Refused: paths naming the spell effect pack or the owner's reference sheets (see EXCLUDED_PARTS; more
local folder names, comma separated, in the environment variable CHAOS_CNN_EXCLUDE).

Rows kept: 1x1 carried things (not ground, border, wall or fixed), first sprite, 12+ opaque pixels.
Rows dropped: catalogue rows tagged "named character" or "branded", pair items that share a sprite with an effect.
Kind: dat market category, else cloth slot, else "unknown" (kept as a real-art positive for the critic).
Dedupe: exact RGBA (transparent pixels zeroed), then a coarse key (mask + 3-bit colour) for near copies.

    python3 -I build_dataset.py --pair P --library L/donorB ... --icons L/item_icons --out OUT.npz
"""
import argparse
import csv
import hashlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import numpy as np
from PIL import Image

from datspr import Dat, Spr

KINDS = ('sword', 'axe', 'club', 'rod', 'distance', 'ammo', 'shield', 'helmet', 'armor', 'legs', 'boots',
         'ring', 'amulet', 'misc')
MARKET = {20: 'sword', 17: 'axe', 18: 'club', 21: 'rod', 19: 'distance', 16: 'ammo', 13: 'shield', 7: 'helmet',
          1: 'armor', 8: 'legs', 3: 'boots', 11: 'ring', 2: 'amulet'}
CLOTH = {1: 'helmet', 2: 'amulet', 4: 'armor', 7: 'legs', 8: 'boots', 9: 'ring', 10: 'ammo'}
SKIP_TAGS = ('named character', 'branded')
# the spell effect pack is PNG strips with no Tibia.dat / Tibia.spr, so it cannot be read here at all; the names below
# are a second guard, plus any local folder names in CHAOS_CNN_EXCLUDE
EXCLUDED_PARTS = ('purchased_weto', 'oblique', 'effect_pack') + tuple(
    x.strip().lower() for x in os.environ.get('CHAOS_CNN_EXCLUDE', '').split(',') if x.strip())
FIXED = ('ground', 'clip', 'bottom', 'top', 'fullground', 'notmoveable')


def refuse(path):
    p = path.lower()
    for x in EXCLUDED_PARTS:
        if x in p:
            sys.exit(f'{path}: excluded source ({x})')


def clean(img):
    img = img.copy()
    img[img[..., 3] == 0] = 0
    return img


def kind_of(t):
    m = t.flags.get('market')
    if m and m[0]:
        return MARKET.get(m[0], 'misc'), 'market'
    c = t.flags.get('cloth')
    if c in CLOTH:
        return CLOTH[c], 'cloth'
    if c in (3, 5, 6):
        return 'unknown', 'cloth-hand'
    return 'unknown', 'none'


def from_pair_or_lib(path, name, live):
    refuse(path)
    dat = Dat(os.path.join(path, 'Tibia.dat'))
    spr = Spr(os.path.join(path, 'Tibia.spr'))
    rows = {}
    cat = os.path.join(path, 'catalogue.csv')
    if os.path.exists(cat):
        for r in csv.DictReader(open(cat, newline='', encoding='utf-8', errors='replace')):
            if r['category'] == 'item':
                rows[int(r['lib_id'])] = r['description'].lower()
    fx_sprites = set()
    if live:
        for e in dat.effects:
            fx_sprites.update(e.sprites)
        fx_sprites.discard(0)
    out, skipped = [], {'tagged': 0, 'fx_shared': 0, 'size': 0, 'empty': 0}
    flagless = not any(t.flags for t in dat.items[:2000])
    for t in dat.items:
        if t.w != 1 or t.h != 1:
            continue
        f = t.flags
        if any(k in f for k in FIXED):
            continue
        d = rows.get(t.id, '')
        if not (f.get('pickupable') or (flagless and not f)):
            continue
        if any(k in d for k in SKIP_TAGS):
            skipped['tagged'] += 1
            continue
        if live and fx_sprites.intersection(t.sprites):
            skipped['fx_shared'] += 1
            continue
        if not t.sprites or not t.sprites[0]:
            continue
        a = spr.sprite(t.sprites[0])
        if a is None:
            skipped['empty'] += 1
            continue
        op = (a[..., 3] > 0)
        if op.sum() < 12 or op.mean() > 0.85:
            skipped['size'] += 1
            continue
        k, how = kind_of(t)
        out.append((clean(a), k, how, name, t.id, 'library only' in d))
    spr._cache.clear()
    print(f'{name}: {len(out)} rows, skipped {skipped}', file=sys.stderr)
    return out


def from_icons(path):
    refuse(path)
    out = []
    atlases = {}
    for r in csv.DictReader(open(os.path.join(path, 'catalogue.csv'), newline='')):
        s = r['set']
        if s not in atlases:
            atlases[s] = np.asarray(Image.open(os.path.join(path, s + '_32.png')).convert('RGBA'))
        x, y = int(r['x']), int(r['y'])
        a = atlases[s][y:y + 32, x:x + 32]
        if a.shape[:2] != (32, 32):
            continue
        op = a[..., 3] > 0
        if op.sum() < 12 or op.mean() > 0.85:
            continue
        a = a.copy()
        a[..., 3] = np.where(a[..., 3] >= 128, 255, 0)
        out.append((clean(a), 'unknown', 'icon', 'icons:' + s, int(r['index']), False))
    print(f'icons: {len(out)} rows', file=sys.stderr)
    return out


def coarse_key(img):
    q = (img[..., :3] >> 5).astype(np.uint8)
    q[img[..., 3] == 0] = 0
    return hashlib.md5(q.tobytes() + (img[..., 3] > 0).tobytes()).digest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--pair', action='append', default=[])
    ap.add_argument('--library', action='append', default=[])
    ap.add_argument('--icons')
    ap.add_argument('--out', required=True)
    a = ap.parse_args()
    rows = []
    for p in a.pair:
        rows += from_pair_or_lib(p, 'pair', True)
    for p in a.library:
        rows += from_pair_or_lib(p, os.path.basename(os.path.normpath(p)), False)
    if a.icons:
        rows += from_icons(a.icons)
    n0 = len(rows)
    seen, seen2, keep = set(), set(), []
    nx = nc = 0
    # labelled rows first so a duplicate keeps its label
    order = sorted(range(len(rows)), key=lambda i: (rows[i][1] == 'unknown', rows[i][3] != 'pair'))
    for i in order:
        img = rows[i][0]
        h = hashlib.md5(img.tobytes()).digest()
        if h in seen:
            nx += 1
            continue
        seen.add(h)
        c = coarse_key(img)
        if c in seen2:
            nc += 1
            continue
        seen2.add(c)
        keep.append(rows[i])
    print(f'total {n0}, exact dupes {nx}, near dupes {nc}, kept {len(keep)}', file=sys.stderr)
    kinds = KINDS + ('unknown',)
    X = np.stack([r[0] for r in keep]).astype(np.uint8)
    y = np.array([kinds.index(r[1]) for r in keep], np.int16)
    np.savez_compressed(a.out, X=X, y=y, kinds=np.array(kinds),
                        how=np.array([r[2] for r in keep]), src=np.array([r[3] for r in keep]),
                        ids=np.array([r[4] for r in keep], np.int32), libonly=np.array([r[5] for r in keep]))
    # count table
    srcs = sorted(set(r[3].split(':')[0] for r in keep))
    print('kind'.ljust(10) + ''.join(s[:7].rjust(8) for s in srcs) + 'total'.rjust(8))
    for k in kinds:
        cnt = [sum(1 for r in keep if r[1] == k and r[3].split(':')[0] == s) for s in srcs]
        print(k.ljust(10) + ''.join(str(c).rjust(8) for c in cnt) + str(sum(cnt)).rjust(8))
    print('total'.ljust(10) + ''.join(str(sum(1 for r in keep if r[3].split(':')[0] == s)).rjust(8) for s in srcs)
          + str(len(keep)).rjust(8))


if __name__ == '__main__':
    main()
