#!/usr/bin/env python3
"""Pair 37: the owner's novelty and moon outfits, read from object-builder exports (.obd) into importer sheets.

    python3 -I gen_pack37_looks.py build --src SRC            # sheets -> art_import/pack37_looks/ (ignored by git),
                                                              #   pack37_looks.csv, .sums, pack37_looks_sources.csv,
                                                              #   pack37_moon_fix.csv (the moon looks in place)
    python3 -I gen_pack37_looks.py build --src SRC --check    # rebuild in memory, compare every committed file
    python3 -I gen_pack37_looks.py build --check              # CI, no sources: tables agree with LOOKS and the server
    python3 -I gen_pack37_looks.py preview --src SRC --out P  # owner review sheet (PNG, scratchpad only)

Source (internal label `set37 outfits`, docs/CREDITS.md): .obd files the owner put on Drive (folders "random" and
"obd+"), downloaded 2026-10-22. Supplied by the owner, source pack unnamed. The files are untrusted data: each is
md5-checked against LOOKS before it is decoded, decoded by `read_obd` below (pure parsing, LZMA with an output cap),
never executed or opened with another tool. Import-only like the purchased packs: the sheets are never committed and
`style_check.py` is not run on them.

.obd layout (object builder, versions 200 and 300; LZMA "alone" stream): u16 version, u16 client (1098), u8 category
(2 = outfit), u32 offset of the texture block, the 10.98 flags up to 0xFF, then the frame groups. Version 300: u8 group
count, per group a u8 type; version 200: one group, no type byte. Per group: u8 width, u8 height, u8 exact size when
either is over 1, u8 layers, pattern x, y, z, u8 frames; with frames > 1 u8 animation mode, i32 loop count, i8 start
frame and frames x (u32 min, u32 max) ms. Then every sprite in dat order: u32 id, (300: u32 length,) ARGB pixels.

Ids (pair 36: 38,640 items, 2,667 outfits): outfits from FIRST_OUTFIT in LOOKS order, no items. Server use:
server/data/lib/chaos_pack37_looks.lua (the store, outfits.xml through server/tools/install_outfits.py); `build --check`
compares its look ids and names with LOOKS.

Picked (owner 2026-10-22: "uns outfits bem diferente ... tipo de pizza"): the four moon outfits (male and female,
colourable, two addons, mounted frames), two plush bears and three crawling hands (one look, walk frames) and the fry
box costume (one idle frame per direction: it slides when walking). The moon set's standing frames are moved down to
stock ground (STAND_SHIFT, client/MANIFEST.md "Moon outfits on the ground"); pack37_moon_fix.csv rewrites them in a pair
that already has them. No pizza outfit was on the Drive. FRY_BOX: the
fast-food mark on the box front is painted over (`delogo`: small enclosed yellow marks become the box red).
"""
import argparse, csv, hashlib, io, lzma, os, struct, sys
from collections import Counter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
SLUG = 'pack37_looks'
SERVER_LIB = os.path.join(ROOT, 'server', 'data', 'lib', 'chaos_pack37_looks.lua')
FIRST_OUTFIT = 2668
PACK = 'set37 outfits'
LICENCE = 'supplied by the owner, source pack unnamed; ships only inside the compiled game'
MAX_OBD = 64 << 20   # decoded size cap

# key, name (server), source file, md5, size, Drive folder, sex (male / female / both)
LOOKS = [
    ('starweaver_m', 'Starweaver', 'outfit_2718_1098-v3.obd', 'd81a05330c991aaaba2994aebddf93e0', 'random', 'male'),
    ('starweaver_f', 'Starweaver', 'outfit_2719_1098-v3.obd', '35b2d1cc6e380fd5bdc5a4c25d65d698', 'random', 'female'),
    ('crescent_oracle_m', 'Crescent Oracle', 'outfit_2720_1098-v3.obd', 'bf28e80081d6a355a41482166e8dd843', 'random', 'male'),
    ('crescent_oracle_f', 'Crescent Oracle', 'outfit_2721_1098-v3.obd', '8ed728219c77e5cde9b4888e30195a7e', 'random', 'female'),
    ('moonblade_mystic_m', 'Moonblade Mystic', 'outfit_2722_1098-v3.obd', '58c4cb1092ed1b23f3768f5bb37cc8d9', 'random', 'male'),
    ('moonblade_mystic_f', 'Moonblade Mystic', 'outfit_2723_1098-v3.obd', '1273c2f906c2054bb2a9d6875cea0c35', 'random', 'female'),
    ('moonflame_mystic_m', 'Moonflame Mystic', 'outfit_2724_1098-v3.obd', '660f9e83b107ef0e52433c7aa650adb9', 'random', 'male'),
    ('moonflame_mystic_f', 'Moonflame Mystic', 'outfit_2725_1098-v3.obd', 'd90696b61a0198ba52bdec5b55a87915', 'random', 'female'),
    ('plush_bear', 'Plush Bear', 'outfit_839_1098-v3.obd', 'b3aec526c62d6452afce22343802c560', 'random', 'both'),
    ('snow_plush_bear', 'Snow Plush Bear', 'outfit_840_1098-v3.obd', '7dc7c05507d9907278cfab22465287e3', 'random', 'both'),
    ('frost_crawling_hand', 'Frost Crawling Hand', 'outfit_841_1098-v3.obd', 'd88b884c11afe43ae932a1d822153985', 'random', 'both'),
    ('grave_crawling_hand', 'Grave Crawling Hand', 'outfit_842_1098-v3.obd', 'a466c9569bd9a5b42dc4b7a2eb9c450f', 'random', 'both'),
    ('rose_crawling_hand', 'Rose Crawling Hand', 'outfit_843_1098-v3.obd', 'b00d55f528d600d1f6d6a5a779c4bd80', 'random', 'both'),
    ('fry_box', 'Fry Box Costume', 'outfit_5113-1098-v2.obd', '49db68a0385e11a956163488e5741f8e', 'obd+', 'both'),
]
FRY_BOX = 'fry_box'
MOON = ('starweaver_m', 'starweaver_f', 'crescent_oracle_m', 'crescent_oracle_f', 'moonblade_mystic_m',
        'moonblade_mystic_f', 'moonflame_mystic_m', 'moonflame_mystic_f')
# Placement of the moon set. The files say displacement 8, 8, and with it the set stands 9 px left of and 10 px above
# stock look 128 (feet x 47.5 / bottom row 53 against 56.5 / 63, south idle, body only): it floats. Mounted it sits
# right: on a mount the client draws the rider by the mount's displacement, not the outfit's (outfit.cpp: the outfit
# displacement is added back before the rider is drawn), so the outfit displacement only places the standing look.
# Pair 37 moved x alone (0, 8), believing one displacement served both states, and the set floated about 10 px.
# Now displacement 0, 0 (it cannot go below 0 without the client's negative-offset drawing paths), which moves the
# standing look 8 px right and 8 px down, and STAND_SHIFT moves the standing cells (pattern z 0, every frame of
# both groups, every addon and layer) down by whole pixels per direction until the body's lowest idle row lands on
# STOCK_FEET, as far as the 64 px cell allows (no pixel is pushed out). Mounted cells (z 1) are untouched.
DISPLACEMENT = {k: (0, 0) for k in MOON}
STAND_SHIFT = set(MOON)
STOCK_FEET = 23   # screen row (from the tile top) of the lowest idle pixel of look 128, every direction (pair 37)
FIX_SLUG = 'pack37_moon_fix'   # the moon rows as in-place replacements (mode=replace, look=ID) for a pair after 37
THINGS_HEADER = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode',
                 'server_id', 'extra']
SOURCES_HEADER = ['name', 'kind', 'pack', 'source', 'licence']
FLAG_ARGS = {0x08: '<H', 0x09: '<H', 0x16: '<HH', 0x19: '<hh', 0x1A: '<H', 0x1D: '<H', 0x1E: '<H', 0x23: '<H'}


# ------------------------------------------------------------------------------------------------ .obd reader
class ObdError(ValueError):
    pass


class _R:
    def __init__(self, b):
        self.b, self.p = b, 0

    def u(self, fmt):
        n = struct.calcsize(fmt)
        if self.p + n > len(self.b):
            raise ObdError('truncated')
        v = struct.unpack_from(fmt, self.b, self.p)
        self.p += n
        return v if len(v) > 1 else v[0]

    def raw(self, n):
        if self.p + n > len(self.b):
            raise ObdError('truncated')
        v = self.b[self.p:self.p + n]
        self.p += n
        return v


def decompress(data):
    d = lzma.LZMADecompressor(format=lzma.FORMAT_ALONE)
    out = d.decompress(data, max_length=MAX_OBD)
    if not d.eof:
        raise ObdError('LZMA stream too large or truncated')
    return out


def read_obd(data):
    """Parse one outfit .obd (bytes of the file). Returns {version, flags, groups: [{w, h, exact, layers, px, py, pz,
    frames, anim, durs, tiles: [RGBA 32x32 uint8] in dat order}]}."""
    r = _R(decompress(data))
    ver, client, cat = r.u('<H'), r.u('<H'), r.u('<B')
    if ver not in (200, 300) or cat != 2:
        raise ObdError('not an outfit export (version %d, category %d)' % (ver, cat))
    tex = r.u('<I')
    flags = {}
    while True:
        f = r.u('<B')
        if f == 0xFF:
            break
        if f == 0x22:
            raise ObdError('market data on an outfit')
        flags[f] = r.u(FLAG_ARGS[f]) if f in FLAG_ARGS else True
        if r.p > tex:
            raise ObdError('flags run past the texture block')
    if r.p != tex:
        raise ObdError('flags end at %d, texture block at %d' % (r.p, tex))
    v2 = ver == 200
    groups = []
    for _ in range(1 if v2 else r.u('<B')):
        g = {'type': 0 if v2 else r.u('<B')}
        g['w'], g['h'] = r.u('<BB')
        g['exact'] = r.u('<B') if (g['w'] > 1 or g['h'] > 1) else 32
        g['layers'], g['px'], g['py'], g['pz'], g['frames'] = r.u('<BBBBB')
        if not (1 <= g['w'] <= 8 and 1 <= g['h'] <= 8 and g['layers'] in (1, 2) and g['px'] == 4 and
                1 <= g['py'] <= 4 and 1 <= g['pz'] <= 2 and 1 <= g['frames'] <= 64):
            raise ObdError('unsupported group shape %r' % g)
        g['anim'], g['durs'] = None, None
        if g['frames'] > 1:
            g['anim'] = (r.u('<B'), r.u('<i'), r.u('<b'))
            g['durs'] = [r.u('<II') for _ in range(g['frames'])]
        n = g['w'] * g['h'] * g['layers'] * g['px'] * g['py'] * g['pz'] * g['frames']
        tiles = []
        for _ in range(n):
            r.u('<I')
            ln = 4096 if v2 else r.u('<I')
            if ln != 4096:
                raise ObdError('sprite of %d bytes' % ln)
            a = np.frombuffer(r.raw(4096), np.uint8).reshape(1024, 4)
            t = np.stack([a[:, 1], a[:, 2], a[:, 3], a[:, 0]], 1)
            t[t[:, 3] == 0] = 0
            tiles.append(t.reshape(32, 32, 4))
        g['tiles'] = tiles
        groups.append(g)
    if r.p != len(r.b):
        raise ObdError('%d trailing bytes' % (len(r.b) - r.p))
    if not 1 <= len(groups) <= 2:
        raise ObdError('%d frame groups' % len(groups))
    return {'version': ver, 'client': client, 'flags': flags, 'groups': groups}


def tile_index(g, fr, z, y, x, layer, tx, ty):
    return ((((((fr * g['pz'] + z) * g['py'] + y) * g['px'] + x) * g['layers'] + layer) * g['h'] + ty) * g['w'] + tx)


def cell(g, fr, z, y, d, layer):
    """the w x h tile canvas of one sprite slot, tiles anchored bottom-right as the dat draws them"""
    w, h = g['w'], g['h']
    c = np.zeros((h * 32, w * 32, 4), np.uint8)
    for ty in range(h):
        for tx in range(w):
            y0, x0 = (h - 1 - ty) * 32, (w - 1 - tx) * 32
            c[y0:y0 + 32, x0:x0 + 32] = g['tiles'][tile_index(g, fr, z, y, d, layer, tx, ty)]
    return c


def _rows(c):
    return np.nonzero(c[:, :, 3].any(1))[0]


def shift_rows(c, s):
    """the cell moved down by s pixel rows (up when negative); refuses to push an opaque pixel out of the cell"""
    if s == 0:
        return c
    lost = c[c.shape[0] - s:] if s > 0 else c[:-s]
    if lost[:, :, 3].any():
        raise ObdError('a shift of %d rows would cut the art' % s)
    out = np.zeros_like(c)
    if s > 0:
        out[s:] = c[:c.shape[0] - s]
    else:
        out[:s] = c[-s:]
    return out


def stand_shifts(gs, dy):
    """rows per direction (north, east, south, west) that the standing cells (pattern z 0) move down: the body's
    lowest idle row (group 0, addon 0, layer 0, every frame) lands on STOCK_FEET of the screen with displacement dy,
    clamped to the free room of every standing cell of the direction (both groups, every addon and layer)"""
    g0 = gs[0]
    H = g0['h'] * 32
    out = []
    for d in range(4):
        feet = [r.max() for fr in range(g0['frames']) for r in [_rows(cell(g0, fr, 0, 0, d, 0))] if len(r)]
        used = [r for g in gs for fr in range(g['frames']) for y in range(g['py']) for L in range(g['layers'])
                for r in [_rows(cell(g, fr, 0, y, d, L))] if len(r)]
        if not feet:
            raise ObdError('direction %d: no body pixel standing' % d)
        want = STOCK_FEET + H - 32 + dy - int(max(feet))
        lo, hi = -int(min(r.min() for r in used)), H - 1 - int(max(r.max() for r in used))
        out.append(max(lo, min(want, hi)))
    return out


# ------------------------------------------------------------------------------------------------ fry box mark
def _red(p):
    r, g, b, a = (int(x) for x in p)
    return a > 0 and r >= 60 and g * 2 < r and b * 2 < r


def _mark(p):
    r, g, b, a = (int(x) for x in p)
    return a > 0 and r >= 60 and g * 10 >= r * 6 and b * 2 < g


def delogo(img, max_size=60):
    """Paint over the printed mark of the box: 4-connected yellow components of at most max_size pixels whose outside
    neighbours are at least two thirds box red (the rest its dark outline) take the most common red around them.
    Returns (image, painted pixels). The fries themselves are larger and bordered by their outline: untouched."""
    a = img.copy()
    H, W = a.shape[:2]
    seen = np.zeros((H, W), bool)
    painted = 0
    for y in range(H):
        for x in range(W):
            if seen[y, x] or not _mark(a[y, x]):
                continue
            comp, stack, border, other, inside = [], [(y, x)], Counter(), 0, True
            seen[y, x] = True
            while stack:
                cy, cx = stack.pop()
                comp.append((cy, cx))
                for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                    if not (0 <= ny < H and 0 <= nx < W):
                        inside = False
                        continue
                    p = a[ny, nx]
                    if _mark(p):
                        if not seen[ny, nx]:
                            seen[ny, nx] = True
                            stack.append((ny, nx))
                    elif _red(p):
                        border[tuple(int(v) for v in p)] += 1
                    else:
                        other += 1
            if inside and len(comp) <= max_size and border and sum(border.values()) >= 2 * other:
                col = border.most_common(1)[0][0]
                for cy, cx in comp:
                    a[cy, cx] = col
                painted += len(comp)
    return a, painted


# ------------------------------------------------------------------------------------------------ sheets and tables
def sheet_of(obd, key):
    """importer sheet (import_art_things.py OutfitLayout): one row per group and frame, one column per
    ((z * addons + y) * layers + layer) * 4 + direction. Returns (sheet, things row fields)."""
    gs = obd['groups']
    g0 = gs[0]
    shape = ('w', 'h', 'layers', 'px', 'py', 'pz')
    if any(tuple(g[k] for k in shape) != tuple(g0[k] for k in shape) for g in gs):
        raise ObdError('%s: frame groups differ in shape' % key)
    w, h, L, py, pz = g0['w'], g0['h'], g0['layers'], g0['py'], g0['pz']
    dx, dy = DISPLACEMENT.get(key, obd['flags'].get(0x19, (0, 0)))
    shifts = stand_shifts(gs, dy) if key in STAND_SHIFT else [0, 0, 0, 0]
    rows = sum(g['frames'] for g in gs)
    cols = pz * py * L * 4
    sheet = np.zeros((rows * h * 32, cols * w * 32, 4), np.uint8)
    painted = 0
    row = 0
    for g in gs:
        for fr in range(g['frames']):
            for z in range(pz):
                for y in range(py):
                    for layer in range(L):
                        for d in range(4):
                            c = cell(g, fr, z, y, d, layer)
                            if z == 0:
                                c = shift_rows(c, shifts[d])
                            if key == FRY_BOX and layer == 0 and y == 0:
                                c, n = delogo(c)
                                painted += n
                            col = ((z * py + y) * L + layer) * 4 + d
                            sheet[row * h * 32:(row + 1) * h * 32, col * w * 32:(col + 1) * w * 32] = c
            row += 1
    if key == FRY_BOX and not painted:
        raise ObdError('fry box: no mark painted over (the art changed?)')
    extra = ['gtypes=' + '+'.join(str(g['type'] if len(gs) > 1 else 0) for g in gs), 'layers=%d' % L]
    if py > 1:
        extra.append('addons=%d' % py)
    if pz > 1:
        extra.append('mounts=%d' % pz)
    for i, g in enumerate(gs):
        if g['frames'] > 1:
            extra.append('durs%d=%s' % (i, '/'.join('%d:%d' % d for d in g['durs'])))
            extra.append('anim%d=%d:%d:%d' % ((i,) + tuple(g['anim'])))
    flags = 'displacement:%d:%d' % (dx, dy)
    fields = {'w': w, 'h': h, 'phases': '+'.join(str(g['frames']) for g in gs), 'flags': flags,
              'extra': '|'.join(extra), 'painted': painted, 'shifts': shifts}
    return sheet, fields


def digest(a):
    return hashlib.sha256(np.ascontiguousarray(a).tobytes() + repr(a.shape).encode()).hexdigest()


def csv_text(header, rows):
    s = io.StringIO()
    w = csv.writer(s, lineterminator='\n')
    w.writerow(header)
    w.writerows(rows)
    return s.getvalue()


def read_source(src, fname, md5):
    path = os.path.join(src, fname)
    data = open(path, 'rb').read()
    if hashlib.md5(data).hexdigest() != md5:
        raise SystemExit('%s: md5 differs from LOOKS (not the file the owner supplied)' % path)
    return data


def fix_row(row):
    """a pack37_looks.csv row as an in-place replacement of its look (import_art_things.py mode=replace)"""
    out = list(row)
    out[12] = 'replace'
    out[14] = row[14] + '|look=' + dict(p.split('=', 1) for p in row[14].split('|'))['id']
    return out


def build(src):
    """(committed texts, {atlas path: sheet})"""
    things, fix, sources, sums, sheets = [], [], [], [], {}
    for i, (key, name, fname, md5, folder, sex) in enumerate(LOOKS):
        obd = read_obd(read_source(src, fname, md5))
        sheet, f = sheet_of(obd, key)
        atlas = '%s/%s' % (SLUG, key)
        sheets[atlas] = sheet
        sums.append('%s  %s.png\n' % (digest(sheet), atlas))
        things.append([key, 'outfit', 'look', name, atlas, 0, 0, f['w'], f['h'], 4, f['phases'], f['flags'], 'new',
                       '', 'id=%d|sex=%s|' % (FIRST_OUTFIT + i, sex) + f['extra']])
        if key in STAND_SHIFT:
            fix.append(fix_row(things[-1]))
        sources.append([key, 'outfit', PACK, '%s/%s md5 %s' % (folder, fname, md5), LICENCE])
    texts = {SLUG + '.csv': csv_text(THINGS_HEADER, things), FIX_SLUG + '.csv': csv_text(THINGS_HEADER, fix),
             SLUG + '.sums': ''.join(sums),
             SLUG + '_sources.csv': csv_text(SOURCES_HEADER, sources)}
    return texts, sheets


def server_looks():
    """(id, key, name) of every look in server/data/lib/chaos_pack37_looks.lua's M.looks"""
    import re
    text = open(SERVER_LIB, encoding='utf-8').read()
    return [(int(m.group(2)), m.group(1), m.group(3)) for m in
            re.finditer(r'\{key = "([a-z_]+)", look = (\d+), name = "([^"]+)"', text)]


def check_tables():
    bad = []
    rows = list(csv.DictReader(open(os.path.join(ART, SLUG + '.csv'), newline='')))
    src = list(csv.DictReader(open(os.path.join(ART, SLUG + '_sources.csv'), newline='')))
    sums = [ln.split('  ', 1)[1] for ln in open(os.path.join(ART, SLUG + '.sums')).read().split('\n') if ln]
    want = [(k, n, FIRST_OUTFIT + i) for i, (k, n, *_r) in enumerate(LOOKS)]
    got = [(r['key'], r['name'], int(dict(p.split('=', 1) for p in r['extra'].split('|'))['id'])) for r in rows]
    if got != want:
        bad.append('things file and LOOKS differ')
    if [r['name'] for r in src] != [k for k, *_r in LOOKS]:
        bad.append('sources and LOOKS differ')
    if any(r['pack'] != PACK or r['licence'] != LICENCE for r in src):
        bad.append('sources rows need pack %r and the licence text' % PACK)
    if sorted(r['atlas'] + '.png' for r in rows) != sorted(sums):
        bad.append('things and sums differ')
    fix_path = os.path.join(ART, FIX_SLUG + '.csv')
    fix = list(csv.reader(open(fix_path, newline=''))) if os.path.exists(fix_path) else []
    want_fix = [fix_row([r[k] for k in THINGS_HEADER]) for r in rows if r['key'] in STAND_SHIFT]
    if fix[:1] != [THINGS_HEADER] or fix[1:] != want_fix:
        bad.append('%s.csv and the moon rows of %s.csv differ (rows mode=replace, look=id)' % (FIX_SLUG, SLUG))
    if any(r['flags'] != 'displacement:%d:%d' % DISPLACEMENT[r['key']] for r in rows if r['key'] in DISPLACEMENT):
        bad.append('a displacement of %s.csv differs from DISPLACEMENT' % SLUG)
    lua = sorted(server_looks())
    if lua != sorted((FIRST_OUTFIT + i, k, n) for i, (k, n, *_r) in enumerate(LOOKS)):
        bad.append('server/data/lib/chaos_pack37_looks.lua M.looks and LOOKS differ: %r' % lua)
    return bad


def cmd_build(a):
    bad = check_tables() if a.check and os.path.exists(os.path.join(ART, SLUG + '.csv')) else []
    if a.src:
        texts, sheets = build(a.src)
        for name, text in texts.items():
            path = os.path.join(ART, name)
            if a.check:
                if not os.path.exists(path) or open(path, newline='').read() != text:
                    bad.append(name + ' is not up to date')
            else:
                open(path, 'w', newline='').write(text)
        if not a.check:
            os.makedirs(os.path.join(ART, SLUG), exist_ok=True)
            for atlas, sheet in sheets.items():
                Image.fromarray(sheet).save(os.path.join(ART, atlas + '.png'))
            print('wrote %d sheets, %s' % (len(sheets), ', '.join(texts)))
    elif not a.check:
        raise SystemExit('build needs --src (or --check)')
    if a.check:
        if bad:
            print('\n'.join(bad))
            return 1
        print('pack37 looks: tables agree' + (' with the sources' if a.src else ''))
    return 0


def cmd_preview(a):
    """south idle frame: bare and with both addons; west on a mount when it has mounted frames"""
    from PIL import ImageDraw
    cells = []
    for i, (key, name, fname, md5, *_r) in enumerate(LOOKS):
        obd = read_obd(read_source(a.src, fname, md5))
        sheet, f = sheet_of(obd, key)
        g = obd['groups'][0]
        W, H = g['w'] * 32, g['h'] * 32
        L, py = g['layers'], g['py']
        ims = []
        for y in sorted({0, py - 1}):
            c = Image.fromarray(np.ascontiguousarray(sheet[0:H, (y * L * 4 + 2) * W:(y * L * 4 + 3) * W]))
            if y:
                c = Image.alpha_composite(Image.fromarray(np.ascontiguousarray(sheet[0:H, 2 * W:3 * W])), c)
            ims.append(c)
        cells.append(('%d %s' % (FIRST_OUTFIT + i, name), ims))
    cw, ch = 300, 170
    out = Image.new('RGBA', (4 * cw, ((len(cells) + 3) // 4) * ch), (60, 60, 60, 255))
    dr = ImageDraw.Draw(out)
    for n, (label, ims) in enumerate(cells):
        x0, y0 = (n % 4) * cw, (n // 4) * ch
        dr.text((x0 + 4, y0 + 2), label, fill=(255, 255, 0))
        x = x0 + 6
        for im in ims:
            s = 2 if im.width <= 64 else 1
            im = im.resize((im.width * s, im.height * s), Image.NEAREST)
            out.alpha_composite(im, (x, y0 + 16))
            x += im.width + 8
    out.save(a.out)
    print(a.out)
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('build'); p.add_argument('--src'); p.add_argument('--check', action='store_true')
    p = sub.add_parser('preview'); p.add_argument('--src', required=True); p.add_argument('--out', required=True)
    a = ap.parse_args(argv)
    return {'build': cmd_build, 'preview': cmd_preview}[a.cmd](a)


if __name__ == '__main__':
    sys.exit(main())
