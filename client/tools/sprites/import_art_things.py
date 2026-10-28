#!/usr/bin/env python3
"""Append the prepared art of art_import/ (items and creature outfits) to COPIES of our 10.98 Tibia.dat / Tibia.spr.

python3 -I import_art_things.py --ours-dat Tibia.dat --ours-spr Tibia.spr --out-dir OUT \
        [--first-item 33000] [--first-outfit 2000] [--expect-items N] [--server-offset 3000] \
        [--manifest-out ../../../server/data/items/art_items.csv] [--outfits-out ../../../server/data/items/art_outfits.csv] \
        [--sheets DIR]

Input: art_import/things.csv (one row per thing, in id order) and the PNG atlases next to it (art_import/*.png,
art_import/creatures/<key>.png). The art is ours to ship: converted once from the source sheets (32 px grid, 16 px icons
upscaled 2x with Scale2x, creatures cropped to the tiles they use and anchored bottom-right as the dat draws).

Items (cat=item): appended after the last item of the input. --first-item pads the item list with blank entries so the
first new item gets that id whatever was appended before (stable ids; must be above the last existing item). One item
per row: size w x h tiles, patterns (px x py from the row's extra, else 1), phases (synchronised animation, ms from the
row's extra or 140). --expect-items N stops the run unless the input has exactly N items (for a things file appended
to an earlier output, e.g. art_import/pouches.csv: --first-item 33651 --expect-items 33650). Flags from the row: dat flag names of the 10.98 table (ground:speed, light:level:colour,
minimap:colour, the rest without data) or copy:<client id> (the flags of an existing item, market data dropped: used for
the new looks of existing server items, so stackable / multi-use / light stay as they were).
Outfits (cat=outfit): appended after the last outfit, --first-outfit pads with blank outfits the same way. Two frame
groups (idle: 2 phases, walking: 4 phases; per-phase ms from the row), 4 directions (patterns=8: 8, the diagonals
north-east, south-east, south-west, north-west after them; client base patch 0160), 2 layers (base + colour mask:
yellow head, red body, green legs, blue feet, the client's template layer), size w x h tiles.
Other outfit layouts (compose_outfit.py writes them; every key is optional and the defaults are the layout above):
the phases column lists the phases per frame group ("2+4", "1+8", or "8" for one group); extra keys gtypes=0+1
(group types), layers=1|2, addons=N (pattern y), mounts=N (pattern z), exact=46+46 (exact size per group), durs<g>=
min:max/min:max/... (per-phase ms of group g), anim<g>=async:loop:start; the flags column takes 10.98 flag names as
for items (displacement:x:y may be negative) and bones:nx:ny:sx:sy:ex:ey:wx:wy (byte 39, the rider seat). The sheet has
one row per group and phase (group 0's phases first) and one column per ((z * addons + y) * layers + layer) * patterns +
direction, each cell w x h tiles; the row's x / y are the sheet's top-left corner.
Atlas names are paths without .png relative to the directory of the --things file.
An outfit row with mode=replace and extra look=ID rewrites the existing outfit ID in place instead of appending one
(new art for a look the server already uses: its sprites are appended, the old entry's bytes are replaced, the outfit
count stays); the append-only guard then allows exactly those outfits to change.

Outputs: OUT/Tibia.dat, OUT/Tibia.spr; --manifest-out: the items.otb / items.xml manifest for
server/tools/install_pack_items.py (client id, server id = client id + --server-offset, or the existing server id for
rows with mode=replace); --outfits-out: lookType and palette colours per creature (server monster XML).
Identical sprites are stored once; sprites already in the input spr are reused. Inputs are never modified.
Deterministic: the same inputs give byte-identical outputs.

Verification (always): the output dat re-parses (same variant); every slot of every new item and outfit (each pattern,
phase, direction, layer) decodes pixel-identical to the art; blank padding entries are blank; every old dat entry is
byte-identical; 3000 sampled old sprites (plus the first and last) are unchanged; then check_pair.py's append-only
guard: every old thing and sprite record byte-identical, the new things and sprites valid for the client.
"""
import argparse, csv, hashlib, os, random, struct, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
from datspr import Dat, Spr, TABLE_NEW, _DATA, sprite_index
from set_multiuse import flag_spans

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')
NEW_BYTE = {name: b for b, name in TABLE_NEW.items()}
BLANK_ITEM = b'\xff' + bytes([1, 1, 1, 1, 1, 1, 1]) + struct.pack('<I', 0)
BLANK_OUTFIT = b'\xff' + bytes([1, 0, 1, 1, 1, 1, 1, 1, 1]) + struct.pack('<I', 0)
OUTFIT_POSES = (2, 4)   # idle phases, walking phases (rows of the creature sheet)

# items.otb for each kind: (group, flags, top order); flag bits of the base server's itemloader
SOLID, MISSILE, PATH, USEABLE, PICKUP, MOVE, STACK = 1, 2, 4, 16, 32, 64, 128
ONTOP, HANG, ANIM, FORCEUSE = 1 << 13, 1 << 16, 1 << 24, 1 << 26
OTB = {'product': (0, PICKUP | MOVE | STACK, 0), 'food': (0, PICKUP | MOVE | STACK, 0), 'corpse': (2, FORCEUSE, 0),
       'tree': (0, SOLID | ONTOP, 2), 'stump': (0, SOLID | ONTOP, 2), 'ground': (1, 0, 0), 'water': (1, 0, 0),
       'border': (0, ONTOP, 1), 'shore': (0, ONTOP, 1), 'lake': (0, 0, 0), 'dock': (0, 0, 0),
       'weapon': (0, PICKUP | MOVE, 0),   # weapon: hand items (the Monk's fist weapons, art_import/fist_weapons.csv)
       'decor': (0, 0, 0)}   # decor: fixed decoration (art_import/owner_art.csv: small plants, the waypoint seal)
# the pair 30 pack art (pack30lib.py): wall = hangs on a wall, flask = stackable pickup like a potion, prop = fixed object
OTB.update({'wall': (0, HANG, 0), 'flask': (0, PICKUP | MOVE | STACK, 0), 'prop': (0, 0, 0)})
# the themed set pieces (art_import/theme_things.csv, gen_theme_art.py): the group and flags of the stock item of
# each kind (melee weapons useable, arrows and bolts stackable, the backpack a container)
OTB.update({k: (0, USEABLE | PICKUP | MOVE, 0) for k in ('sword', 'axe', 'club')})
OTB.update({k: (0, PICKUP | MOVE, 0) for k in ('bow', 'crossbow', 'wand', 'rod', 'shield', 'spellbook', 'helmet', 'armor',
                                               'legs', 'boots', 'amulet', 'ring')})
OTB.update({'backpack': (2, PICKUP | MOVE, 0), 'arrow': (0, PICKUP | MOVE | STACK, 0), 'bolt': (0, PICKUP | MOVE | STACK, 0)})


def extra_of(r):
    out = {}
    for part in (r['extra'] or '').split('|'):
        if '=' in part:
            k, v = part.split('=', 1)
            out[k] = v
    return out


def read_things(path):
    rows = list(csv.DictReader(open(path, newline='')))
    for r in rows:
        for k in ('x', 'y', 'w', 'h'):
            r[k] = int(r[k])
        r['ex'] = extra_of(r)
    return rows


_atlas = {}
ATLAS_DIR = [ART]   # directory of the --things file (main sets it)


def atlas(name):
    path = os.path.normpath(os.path.join(ATLAS_DIR[0], name + '.png'))
    if path not in _atlas:
        _atlas[path] = np.asarray(Image.open(path).convert('RGBA'))
    return _atlas[path]


class Shape:
    """enough attributes for datspr.sprite_index"""
    def __init__(self, w, h, layers, px, py, phases):
        self.w, self.h, self.layers, self.px, self.py, self.pz, self.phases = w, h, layers, px, py, 1, phases


def tiles_of(img, w, h):
    out = {}
    for hh in range(h):
        for ww in range(w):
            y0 = (h - 1 - hh) * 32; x0 = (w - 1 - ww) * 32
            out[(ww, hh)] = np.ascontiguousarray(img[y0:y0 + 32, x0:x0 + 32])
    return out


def encode_sprite(tile):
    a = np.ascontiguousarray(tile).reshape(1024, 4)
    on = a[:, 3] > 0
    if not on.any():
        return None
    body = bytearray()
    i = 0
    last = int(np.nonzero(on)[0][-1]) + 1
    while i < last:
        j = i
        while j < last and not on[j]:
            j += 1
        k = j
        while k < last and on[k]:
            k += 1
        body += struct.pack('<HH', j - i, k - j) + a[j:k].tobytes()
        i = k
    return b'\xff\x00\xff' + struct.pack('<H', len(body)) + bytes(body)


def decoded(tile):
    """what the spr gives back for a tile (fully transparent pixels read as 0,0,0,0)."""
    t = tile.copy()
    t[t[:, :, 3] == 0] = 0
    return t


# ------------------------------------------------------------------------------------------------ frames from the art
def item_frames(r):
    """{(pattern x, pattern y, phase): RGBA canvas}"""
    px, py = int(r['ex'].get('px', 1)), int(r['ex'].get('py', 1))
    W, H = r['w'] * 32, r['h'] * 32
    a = atlas(r['atlas'])
    out = {}
    nph = int(r['phases'])
    assert int(r['patterns']) == px * py, (r['key'], r['patterns'], px, py)
    for p in range(px * py):
        for f in range(nph):
            y0, x0 = r['y'] + p * H, r['x'] + f * W
            out[(p % px, p // px, f)] = a[y0:y0 + H, x0:x0 + W]
    return out, px, py, nph


class OutfitLayout:
    """frame groups, layers and patterns of an outfit row (defaults: the creature layout of things.csv)."""

    def __init__(self, r):
        e = r['ex']
        ph = str(r['phases'] or '+'.join(map(str, OUTFIT_POSES)))
        self.phases = tuple(int(x) for x in ph.split('+'))
        n = len(self.phases)
        assert 1 <= n <= 2 and all(1 <= p <= 255 for p in self.phases), (r['key'], ph)
        self.gtypes = tuple(int(x) for x in e['gtypes'].split('+')) if 'gtypes' in e else tuple(range(n))
        self.layers = int(e.get('layers', 2))
        self.py = int(e.get('addons', 1))
        self.pz = int(e.get('mounts', 1))
        # 4 directions, or 8 (then north-east, south-east, south-west, north-west: client base patch 0160)
        self.px = int(r['patterns'] or 4)
        assert self.px in (4, 8), (r['key'], 'outfits have 4 or 8 directions')
        assert len(self.gtypes) == n and self.layers in (1, 2) and 1 <= self.py <= 4 and 1 <= self.pz <= 2, r['key']
        big = r['w'] > 1 or r['h'] > 1
        self.exact = (tuple(int(x) for x in e['exact'].split('+')) if 'exact' in e
                      else (32 * max(r['w'], r['h']),) * n)
        assert len(self.exact) == n and all(0 < x < 256 for x in self.exact) or not big, (r['key'], 'exact')
        legacy = (int(e['idle_ms']), int(e['walk_ms'])) if 'idle_ms' in e and 'walk_ms' in e else None
        self.anim = []
        for g, nph in enumerate(self.phases):
            if nph == 1:
                self.anim.append(None)
                continue
            if f'durs{g}' in e:
                durs = []
                for part in e[f'durs{g}'].split('/'):
                    lo, _, hi = part.partition(':')
                    durs += [int(lo), int(hi or lo)]
                assert len(durs) == 2 * nph, (r['key'], f'durs{g} needs {nph} phases')
            else:
                ms = legacy[g] if legacy and g < 2 else int(e.get('idle_ms' if g == 0 else 'walk_ms', 140))
                durs = [ms] * (2 * nph)
            asyn, loop, start = (int(x) for x in e.get(f'anim{g}', '0:0:0').split(':'))
            self.anim.append((asyn, loop, start, tuple(durs)))

    def column(self, z, y, layer, d):
        return ((z * self.py + y) * self.layers + layer) * self.px + d


def outfit_frames(r, lay=None):
    """{(group, phase, direction, layer, y, z) -> canvas}"""
    lay = lay or OutfitLayout(r)
    W, H = r['w'] * 32, r['h'] * 32
    a = atlas(r['atlas'])
    out = {}
    row = 0
    for g, n in enumerate(lay.phases):
        for ph in range(n):
            y0 = r['y'] + row * H
            for z in range(lay.pz):
                for y in range(lay.py):
                    for d in range(lay.px):
                        for layer in range(lay.layers):
                            x0 = r['x'] + lay.column(z, y, layer, d) * W
                            cell = a[y0:y0 + H, x0:x0 + W]
                            assert cell.shape[:2] == (H, W), (r['key'], 'sheet too small', g, ph, z, y, layer, d)
                            out[(g, ph, d, layer, y, z)] = cell
            row += 1
    return out


# ------------------------------------------------------------------------------------------------ dat entries
def item_flags(r, od):
    toks = r['flags'].split()
    if len(toks) == 1 and toks[0].startswith('copy:'):
        cid = int(toks[0][5:])
        t = od.items[cid - 100]
        spans, end = flag_spans(od, t.raw[0])
        out = bytearray()
        for i, (b, pos) in enumerate(spans):
            nxt = spans[i + 1][1] if i + 1 < len(spans) else end
            if TABLE_NEW.get(b) in (None, 'market') or b in od.extra:
                continue
            out += od.data[pos:nxt]
        return bytes(out)
    parts = []
    for tok in toks:
        name, *vals = tok.split(':')
        b = NEW_BYTE[name]
        kind = _DATA.get(name)
        data = bytes([b])
        if kind == 'u16':
            data += struct.pack('<H', int(vals[0]))
        elif kind == 'u16x2':
            data += struct.pack('<HH', int(vals[0]), int(vals[1]))
        else:
            assert not vals and kind is None, tok
        parts.append((b, data))
    return b''.join(d for _, d in sorted(parts))


def outfit_flags(r):
    """flag bytes of an outfit row: 10.98 names (displacement may be negative) and bones (byte 39, the rider seat)."""
    parts = []
    for tok in (r['flags'] or '').split():
        name, *vals = tok.split(':')
        if name == 'bones':
            assert len(vals) == 8, (r['key'], tok)
            parts.append((39, bytes([39]) + struct.pack('<8h', *(int(v) for v in vals))))
            continue
        b = NEW_BYTE[name]
        kind = _DATA.get(name)
        data = bytes([b])
        if kind == 'u16':
            data += struct.pack('<H', int(vals[0]) & 0xFFFF)
        elif kind == 'u16x2':
            data += struct.pack('<HH', int(vals[0]) & 0xFFFF, int(vals[1]) & 0xFFFF)
        else:
            assert not vals and kind is None, (r['key'], tok)
        parts.append((b, data))
    assert len({b for b, _ in parts}) == len(parts), (r['key'], 'flag twice')
    return b''.join(d for _, d in sorted(parts))


def item_entry(flags, w, h, px, py, nph, ms, sids):
    e = bytearray(flags) + b'\xff' + bytes([w, h])
    if w > 1 or h > 1:
        e += bytes([32 * max(w, h)])
    e += bytes([1, px, py, 1, nph])
    if nph > 1:
        e += struct.pack('<Bib', 1, 0, 0) + struct.pack('<' + 'II' * nph, *([ms] * (2 * nph)))
    return bytes(e + struct.pack(f'<{len(sids)}I', *sids))


def outfit_entry(w, h, lay, sids_by_group, flags=b''):
    e = bytearray(flags) + b'\xff' + bytes([len(lay.phases)])
    for g, n in enumerate(lay.phases):
        e += bytes([lay.gtypes[g], w, h])
        if w > 1 or h > 1:
            e += bytes([lay.exact[g]])
        e += bytes([lay.layers, lay.px, lay.py, lay.pz, n])
        if n > 1:
            asyn, loop, start, durs = lay.anim[g]
            e += struct.pack('<Bib', asyn, loop, start) + struct.pack('<' + 'II' * n, *durs)
        e += struct.pack(f'<{len(sids_by_group[g])}I', *sids_by_group[g])
    return bytes(e)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--ours-dat', required=True); ap.add_argument('--ours-spr', required=True)
    ap.add_argument('--out-dir', required=True)
    ap.add_argument('--things', default=os.path.join(ART, 'things.csv'))
    ap.add_argument('--first-item', type=int, default=None); ap.add_argument('--first-outfit', type=int, default=None)
    ap.add_argument('--expect-items', type=int, default=None, help='the input must have exactly this many items')
    ap.add_argument('--server-offset', type=int, default=3000)
    ap.add_argument('--manifest-out', default=None); ap.add_argument('--outfits-out', default=None)
    ap.add_argument('--sheets', default=None, help='directory for preview sheets of the new things')
    a = ap.parse_args()
    t0 = time.time()
    os.makedirs(a.out_dir, exist_ok=True)
    for p in (a.ours_dat, a.ours_spr):
        assert os.path.abspath(os.path.dirname(p)) != os.path.abspath(a.out_dir), 'out-dir must differ from the input dir'
    ATLAS_DIR[0] = os.path.dirname(os.path.abspath(a.things))
    rows = read_things(a.things)
    items = [r for r in rows if r['cat'] == 'item']
    outfits = [r for r in rows if r['cat'] == 'outfit']
    for r in outfits:
        if r['mode'] == 'replace':
            if 'look' not in r['ex']:
                sys.exit(f'{r["key"]}: an outfit with mode=replace needs look=ID in extra')
            r['look'] = int(r['ex']['look'])
    replaced = sorted(r['look'] for r in outfits if r['mode'] == 'replace')
    if len(set(replaced)) != len(replaced):
        sys.exit('an outfit is replaced twice')
    appended = [r for r in outfits if r['mode'] != 'replace']

    od = Dat(a.ours_dat); ospr = Spr(a.ours_spr)
    assert od.variant[0] == 'new' and all(od.variant[1:]), f'expected our 10.98 dat (animator, u32, frame groups): {od.variant}'
    assert ospr.u32count and ospr.alpha, 'expected an alpha spr with u32 count'
    ni, no = od.counts[0], od.counts[1]
    if a.expect_items is not None and ni != a.expect_items:
        sys.exit(f'--expect-items {a.expect_items}: the input has {ni} items (wrong pair, or already imported)')
    first_item = a.first_item or ni + 1
    first_outfit = a.first_outfit or no + 1
    if first_item <= ni:
        sys.exit(f'--first-item {first_item} is not above the last item {ni} of the input (wrong pair, or already imported)')
    if first_outfit <= no:
        sys.exit(f'--first-outfit {first_outfit} is not above the last outfit {no} of the input (wrong pair, or already imported)')
    pad_i, pad_o = first_item - ni - 1, (first_outfit - no - 1) if appended else 0
    for look in replaced:
        if not 1 <= look <= no:
            sys.exit(f'look={look}: not an outfit of the input')
    last_item = first_item + len(items) - 1
    assert last_item <= 0xFFFF and last_item + a.server_offset <= 0xFFFF, 'ids above 65535'
    print(f'ours: dat {od.signature:#x} items {ni}, outfits {no}; spr {ospr.count} sprites')

    # --- sprites
    recs, per_item, per_outfit = {}, [], []
    for r in items:
        frames, px, py, nph = item_frames(r)
        shp = Shape(r['w'], r['h'], 1, px, py, nph)
        ids = [None] * (r['w'] * r['h'] * px * py * nph)
        for (x, y, ph), img in frames.items():
            for (ww, hh), tile in tiles_of(img, r['w'], r['h']).items():
                rec = encode_sprite(tile)
                ids[sprite_index(shp, x, y, 0, 0, ph, ww, hh)] = rec
                if rec is not None:
                    recs.setdefault(rec, None)
        per_item.append((r, frames, shp, ids))
    for r in outfits:
        lay = OutfitLayout(r)
        frames = outfit_frames(r, lay)
        groups = []
        for g, n in enumerate(lay.phases):
            shp = Shape(r['w'], r['h'], lay.layers, lay.px, lay.py, n)
            shp.pz = lay.pz
            ids = [None] * (r['w'] * r['h'] * lay.layers * lay.px * lay.py * lay.pz * n)
            for (g_, ph, d, layer, y, z), img in frames.items():
                if g_ != g:
                    continue
                for (ww, hh), tile in tiles_of(img, r['w'], r['h']).items():
                    rec = encode_sprite(tile)
                    ids[sprite_index(shp, d, y, z, layer, ph, ww, hh)] = rec
                    if rec is not None:
                        recs.setdefault(rec, None)
            groups.append((shp, ids))
        per_outfit.append((r, frames, groups, lay))
    # reuse records already in the input spr
    mb = np.frombuffer(ospr.m, dtype=np.uint8)
    offs = ospr.offs.astype(np.int64)
    nzi = np.nonzero(offs)[0]
    lens = 5 + mb[offs[nzi] + 3].astype(np.int64) + (mb[offs[nzi] + 4].astype(np.int64) << 8)
    want = {}
    for rec in recs:
        want.setdefault(len(rec), {})[hashlib.md5(rec).digest()] = rec
    existing = {}
    for i in np.nonzero(np.isin(lens, np.array(list(want), np.int64)))[0]:
        o = int(offs[nzi[i]]); ln = int(lens[i])
        rec = bytes(ospr.m[o:o + ln])
        hit = want[ln].get(hashlib.md5(rec).digest())
        if hit is not None and hit == rec and rec not in existing:
            existing[rec] = int(nzi[i]) + 1
    cnt = ospr.count
    newrecs, rec_id = [], {None: 0}
    for rec in recs:
        if rec in existing:
            rec_id[rec] = existing[rec]
        else:
            newrecs.append(rec); rec_id[rec] = cnt + len(newrecs)

    # --- dat
    d = od.data
    items_end = od.items[-1].raw[1]
    outfits_end = od.outfits[-1].raw[1]
    item_blob = bytearray(BLANK_ITEM * pad_i)
    for r, frames, shp, ids in per_item:
        item_blob += item_entry(item_flags(r, od), r['w'], r['h'], shp.px, shp.py, shp.phases, int(r['ex'].get('ms', 140)),
                                [rec_id[x] for x in ids])
    outfit_blob = bytearray(BLANK_OUTFIT * pad_o)
    swaps = []          # (start, end, bytes) of the replaced outfits in the input dat
    for r, frames, groups, lay in per_outfit:
        e = outfit_entry(r['w'], r['h'], lay, [[rec_id[x] for x in ids] for shp, ids in groups], outfit_flags(r))
        if r['mode'] == 'replace':
            s0, e0 = od.outfit(r['look']).raw
            swaps.append((s0, e0, e))
        else:
            outfit_blob += e
    mid = bytearray(d[items_end:outfits_end])
    for s0, e0, e in sorted(swaps, reverse=True):
        mid[s0 - items_end:e0 - items_end] = e
    out = bytearray(d[:items_end]) + item_blob + mid + outfit_blob + d[outfits_end:]
    struct.pack_into('<HH', out, 4, last_item if items else ni, first_outfit + len(appended) - 1 if appended else no)
    open(os.path.join(a.out_dir, 'Tibia.dat'), 'wb').write(out)

    # --- spr (streamed: bigger table, old records shifted by 4*n, new records appended)
    m = ospr.m; nn = len(newrecs)
    toffs = ospr.offs.astype('<u8').copy(); toffs[toffs > 0] += 4 * nn
    cur = len(m) + 4 * nn
    new_offs = []
    for rec in newrecs:
        new_offs.append(cur); cur += len(rec)
    assert cur < 1 << 32, 'spr would exceed 4 GB'
    table = np.concatenate([toffs, np.array(new_offs, dtype='<u8')]).astype('<u4')
    with open(os.path.join(a.out_dir, 'Tibia.spr'), 'wb') as f:
        f.write(struct.pack('<II', ospr.signature, cnt + nn)); f.write(table.tobytes())
        pos = 8 + 4 * cnt
        while pos < len(m):
            f.write(m[pos:pos + (1 << 24)]); pos += 1 << 24
        for rec in newrecs:
            f.write(rec)
    print(f'dat: items {ni} -> {last_item} ({pad_i} blank, new client ids {first_item}..{last_item}); outfits {no} -> '
          f'{first_outfit + len(appended) - 1 if appended else no} ({pad_o} blank, new '
          f'{first_outfit}..{first_outfit + len(appended) - 1}; replaced {",".join(map(str, replaced)) or "none"}); '
          f'spr: {len(recs)} distinct sprites, {nn} appended, {len(recs) - nn} reused ({cnt} -> {cnt + nn})')

    # --- verification
    md = Dat(os.path.join(a.out_dir, 'Tibia.dat')); ms_ = Spr(os.path.join(a.out_dir, 'Tibia.spr'))
    assert md.variant == od.variant, md.variant
    assert md.counts[2:] == od.counts[2:], md.counts
    assert ms_.count == cnt + nn and md.max_sprite <= ms_.count and ms_.alpha and ms_.signature == ospr.signature
    for t in od.items:
        mt = md.items[t.id - 100]
        assert md.data[mt.raw[0]:mt.raw[1]] == d[t.raw[0]:t.raw[1]], ('item changed', t.id)
    for t in od.outfits + od.effects + od.missiles:
        if t.cat == 'o' and t.id in replaced:
            continue
        lst = {'o': md.outfits, 'e': md.effects, 'm': md.missiles}[t.cat]
        mt = lst[t.id - 1]
        assert md.data[mt.raw[0]:mt.raw[1]] == d[t.raw[0]:t.raw[1]], ('thing changed', t.cat, t.id)
    for i in range(pad_i):
        mt = md.items[ni + 1 + i - 100]
        assert md.data[mt.raw[0]:mt.raw[1]] == BLANK_ITEM
    for i in range(pad_o):
        mt = md.outfits[no + i]
        assert md.data[mt.raw[0]:mt.raw[1]] == BLANK_OUTFIT
    nslot = 0
    for k, (r, frames, shp, ids) in enumerate(per_item):
        mt = md.items[first_item + k - 100]
        assert (mt.w, mt.h, mt.px, mt.py, mt.phases) == (r['w'], r['h'], shp.px, shp.py, shp.phases), r['key']
        assert md.data[mt.raw[0]:mt.raw[0] + len(item_flags(r, od))] == item_flags(r, od), r['key']
        for (x, y, ph), img in frames.items():
            for (ww, hh), tile in tiles_of(img, r['w'], r['h']).items():
                got = ms_.sprite(mt.sprites[sprite_index(mt, x, y, 0, 0, ph, ww, hh)])
                if got is None:
                    assert not tile[:, :, 3].any(), (r['key'], x, y, ph)
                else:
                    assert np.array_equal(got, decoded(tile)), (r['key'], x, y, ph, ww, hh)
                nslot += 1
    from import_outfits import parse_body
    k_new = 0
    for r, frames, groups, lay in per_outfit:
        if r['mode'] == 'replace':
            mt = md.outfit(r['look'])
        else:
            mt = md.outfit(first_outfit + k_new)
            k_new += 1
        mg = parse_body(md, mt)
        assert len(mg) == len(lay.phases), r['key']
        fl = outfit_flags(r)
        assert md.data[mt.raw[0]:mt.raw[0] + len(fl)] == fl and md.data[mt.raw[0] + len(fl)] == 0xFF, (r['key'], 'flags')
        for g, (shp, ids) in enumerate(groups):
            h = mg[g]
            assert (h.gtype, h.w, h.h, h.layers, h.px, h.py, h.pz, h.phases, h.anim) == \
                   (lay.gtypes[g], r['w'], r['h'], lay.layers, lay.px, lay.py, lay.pz, lay.phases[g], lay.anim[g]), r['key']
            for (g_, ph, dd, layer, y, z), img in frames.items():
                if g_ != g:
                    continue
                for (ww, hh), tile in tiles_of(img, r['w'], r['h']).items():
                    got = ms_.sprite(h.sprites[sprite_index(h, dd, y, z, layer, ph, ww, hh)])
                    if got is None:
                        assert not tile[:, :, 3].any(), r['key']
                    else:
                        assert np.array_equal(got, decoded(tile)), (r['key'], g, ph, dd, layer, y, z)
                    nslot += 1
    random.seed(1)
    for sid in random.sample(range(1, cnt + 1), min(3000, cnt)) + [1, cnt]:
        x, y = ospr.sprite(sid), ms_.sprite(sid)
        assert (x is None) == (y is None) and (x is None or (x == y).all()), sid
    print(f'verified: output dat parses ({md.variant}); {len(items)} items and {len(outfits)} outfits '
          f'({len(replaced)} replaced in place), {nslot} sprite slots '
          f'pixel-identical to the art; {pad_i} + {pad_o} blank padding entries; every other old item, outfit, effect and '
          f'missile byte-identical; 3000 sampled old sprites unchanged')

    # --- manifests
    if a.manifest_out:
        with open(a.manifest_out, 'w', newline='') as fh:
            w = csv.writer(fh, lineterminator='\n')
            w.writerow(['client_id', 'server_id', 'key', 'kind', 'mode', 'name', 'size', 'otb_group', 'otb_flags', 'top_order',
                        'speed', 'light_level', 'light_color', 'extra'])
            for k, (r, frames, shp, ids) in enumerate(per_item):
                cid = first_item + k
                toks = {t.split(':')[0]: t.split(':')[1:] for t in r['flags'].split()}
                if r['mode'] == 'replace':
                    sid, g, fl, top = int(r['server_id']), '', '', ''
                    speed, light = 0, (0, 0)
                else:
                    sid = cid + a.server_offset
                    g, fl, top = OTB[r['kind']]
                    if 'notwalkable' in toks:
                        fl |= SOLID
                    if shp.phases > 1:
                        fl |= ANIM
                    speed = int(toks['ground'][0]) if 'ground' in toks else 0
                    light = tuple(int(v) for v in toks['light']) if 'light' in toks else (0, 0)
                w.writerow([cid, sid, r['key'], r['kind'], r['mode'], r['name'], '%dx%d' % (r['w'], r['h']), g, fl, top,
                            speed, light[0], light[1], r['extra']])
        print('manifest', a.manifest_out)
    if a.outfits_out:
        with open(a.outfits_out, 'w', newline='') as fh:
            w = csv.writer(fh, lineterminator='\n')
            w.writerow(['look_type', 'key', 'name', 'size', 'head', 'body', 'legs', 'feet'])
            k_new = 0
            for r, frames, groups, lay in per_outfit:
                e = r['ex']
                if r['mode'] == 'replace':
                    look = r['look']
                else:
                    look = first_outfit + k_new
                    k_new += 1
                w.writerow([look, r['key'], r['name'], '%dx%d' % (r['w'], r['h']), e.get('head', ''),
                            e.get('body', ''), e.get('legs', ''), e.get('feet', '')])
        print('outfits', a.outfits_out)
    from check_pair import check_append_only
    check_append_only(a.ours_dat, a.ours_spr, os.path.join(a.out_dir, 'Tibia.dat'), os.path.join(a.out_dir, 'Tibia.spr'),
                      allow_changed={('outfit', look) for look in replaced})
    if a.sheets:
        os.makedirs(a.sheets, exist_ok=True)
        from datspr import render_thing
        cols, cw = 16, 100
        new = [md.items[first_item + k - 100] for k in range(len(items))]
        sh = Image.new('RGBA', (cols * cw, ((len(new) + cols - 1) // cols) * cw), (60, 60, 60, 255))
        for k, t in enumerate(new):
            im = render_thing(t, ms_)
            im.thumbnail((cw - 4, cw - 4))
            sh.alpha_composite(im, ((k % cols) * cw + 2, (k // cols) * cw + 2))
        sh.convert('RGB').save(os.path.join(a.sheets, 'art_items.png'))
        print('sheet', os.path.join(a.sheets, 'art_items.png'))
    print(f'done in {time.time() - t0:.1f}s')


if __name__ == '__main__':
    main()
