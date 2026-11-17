#!/usr/bin/env python3
"""Fifteen wings of a sprite pair of the owner's pick as new wings outfits (O627; client/MANIFEST.md "Source wings (O627)").

    python3 -I gen_source_wings.py check                       # the table, the sums keys, the server lib, the anchors file (no pair, no source)
    python3 -I gen_source_wings.py ids --src DIR               # measures of the ROWS outfits of the source pair under DIR (author's aid)
    python3 -I gen_source_wings.py table --src DIR [--write]   # measure the source, print (or write) the table and the sums
    python3 -I gen_source_wings.py sums --src DIR --check      # the source pair gives the committed table and sums
    python3 -I gen_source_wings.py build DAT SPR OUT_DIR --src DIR
                                                               # a pair with 3,529 outfits in, 15 more out (OUT_DIR must not exist)
    python3 -I gen_source_wings.py live DAT SPR                # the pair holds every wing at its id, as the sums and the table say
    python3 -I gen_source_wings.py anchors [--check]           # client_chaos_wingfit/source_wing_anchors.lua from the table
    python3 -I gen_source_wings.py preview OUT.mp4 --src DIR [--dat D --spr S --body LOOK]
                                                               # the 15 on a stand-in body (or a look of a pair), standing and walking

Owner 2026-11-17 (translated): fifteen wings of the source pair, the O626 ranking picks 906, 903, 940, 912, 902, 943, 908, 942, 913,
941, 904, 1240, 915, 1221, 1220. The source pair has no licence of its own and its sprites go only into our private sprite pair,
as pair 50 took from the same source (client/MANIFEST.md "Pair 50"; docs/CREDITS.md, wing source). So no picture is committed
(the O540 way): committed are this tool, the table art_import/source_wings.csv (one row a wing: the source outfit id, the first 12 hex
of the digest of its sprites, our new outfit id, the name, the size, the frames, the milliseconds, the anchor, the shift, the numbers
of the shape test) and art_import/source_wings.sums (a digest of every built outfit, to hold a built pair to). The source files are
read by this local script only: never sent to a web or AI service, never shown to one.

Source. `--src DIR` holds the source pair (Tibia.dat and Tibia.spr, in DIR or one folder down). A wing is the outfit of the id of
`src`: one layer, no addons, one frame group of 4 to 8 phases, four directions of one y pattern. `srchash` is the first 12 hex digits
of the sha256 of its shape, its durations and every sprite slot, so a pair that holds another picture under that id is found.

Fit to our wing rules (base patches 0203 and 0204, client/MANIFEST.md "Code-drawn wings for the existing looks (O583)"). The engine puts
the wings' anchor, one point of the picture, on the torso of the body it draws, measured from the body's own alpha. So the picture is
placed for one anchor and nothing else is needed on any body, mount or look of the game.
  Frames. Every phase of the source, pixel for pixel, no sampling, no colour change, no palette reduction (O625 rule 1); the
  durations of the source, every phase as long as the source says. The only picture change: stray specks (an 11 x 11 px box that
  holds 4 opaque-or-glow pixels or fewer, none of them at alpha 192 or above) are dropped; the table counts them (`strays`). The source
  has one: 4 glow pixels 36 px from the wing in one frame of the west view of five wings.
  Canvas. The smallest of 3x3, 4x4, 5x5 tiles that holds the placed art (a 2x2 source goes on 3x3: the anchor needs room on both sides).
  Nothing is cut or sampled; a wing that does not fit 5x5 stops the build.
  Place. The art keeps its y, no vertical shift ever: the anchor row is the torso row of the stock look 128 of our pair (the art of the
  source was fitted to a body of its own engine, its wings drawn at the creature's place and the body 6 px up and left, client/MANIFEST.md "Wings
  centred on the body"; torso of 128 by the 0204 rule y 8, less the 6 px lift: `ANCHOR_Y` = +2 from the creature's place, canvas y 66 of
  3x3). x, by the O495 rule for every wing in the game: in each direction the wing's centre goes on the anchor column, the middle of the
  canvas, by one whole pixel shift of that direction (the same for every phase; `shift` is north:east:south:west). So on any body the wing
  pair stands on the torso column facing every way. The source's own side views are the face-on views turned over (the transpose of the
  south and north art, measured: `dirs`), and in two 4x4 wings the face-on and side art sit on different columns; centring each view keeps
  every one on the body.
  The wing centre of a direction is the O495 one (gen_wing_centres.py): the alpha weighted mean over all phases, or when the union of
  the phases has a gap of 2 empty columns or more with 25% of the art on each side, the midpoint of the two masses' means.
  The anchor is the point (x, y) from the creature's place, sprite px: x = 32 - 16 * N, y = 2 for an NxN canvas (-16, 2 on 3x3);
  client_chaos_wingfit/source_wing_anchors.lua hands one row a look to the engine (setOutfitWingsAnchor).
  Layers. Our two y patterns (base patch 0203): y 0 is the whole wing, y 1 the part in front of the body. The source draws as the stock
  wings of our client do (one y pattern: south and east before the body, north and west after it), so: south and east y 0 = the
  whole picture, y 1 = empty; north and west y 1 = the whole picture, y 0 = its opaque pixels only (a client without the patch draws
  y 0 only: no glow there; the patched one draws the opaque pixels twice, the same colour, and the glow once, in front).
  Flags. animateAlways only (as every animated wings look). The source `light` flag (radius 10, five of the wings) and the `displacement` are
  not carried: a light of ten tiles on every wearer is not meant (owner decision, README); `src_light` in the table names it.

Shape test (heuristic, numbers only; the owner picked from a ranking of the same kind). `dirs` = how many of the four directions are
different pictures (frame 0); `solid` = pixels / convex hull of the south view, `dip` = column density in the middle third over the outer
thirds (a wing pair with a gap for the body has a dip), `aspect` = box width / height, `floor` = pixels from the anchor to the nearest
art pixel. Kinds: `aura` when only 2 directions differ (a ring that turns nothing), or the south view is a filled oval (solid 0.85+, dip 0.9+),
or nothing touches the body (floor 16+: a halo over the head); `borderline` when it is one blob (solid 0.7+, dip 0.85+); else `wings`.

Ids. The wings go after the 3,529 outfits of pair 73 (the three boss outfits 3527-3529 of O608 are its last). They join pair 74, which also
takes the decor flames (O623) as items: no other step of pair 74 adds an outfit, so the row at line n (0-based) is outfit 3530 + n and
wings.xml id 122 + n (README "Source wings (O627)"). The append and its checks are gen_wst_outfits.build (old things byte identical, every
slot read back). After the build: `gen_wing_centres.py` makes client_chaos_wingfit/wing_centres.lua again (the table of a client without
base patch 0204 and of the previews) and gen_outfit_anchors.py client_chaos_charselect/outfit_anchors.lua; neither is part of this tool.
Needs numpy and Pillow (the fx venv of CI) for everything but `check`.
"""
import csv
import hashlib
import os
import re
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_wst_outfits as W  # noqa: E402

REPO = W.REPO
ART = os.path.join(HERE, 'art_import')
TABLE = os.path.join(ART, 'source_wings.csv')
SUMS = os.path.join(ART, 'source_wings.sums')
HEADER = ['src', 'srchash', 'new', 'key', 'name', 'kind', 'size', 'frames', 'ms', 'anchor', 'shift', 'centres', 'strays', 'pixels',
          'dirs', 'solid', 'dip', 'aspect', 'floor', 'src_light', 'note']
SERVER_LIB = os.path.join(REPO, 'server', 'data', 'lib', 'chaos_source_wings.lua')
ANCHORS = os.path.join(REPO, 'client', 'overlay', 'modules', 'client_chaos_wingfit', 'source_wing_anchors.lua')
OTMOD = os.path.join(REPO, 'client', 'overlay', 'modules', 'client_chaos_wingfit', 'client_chaos_wingfit.otmod')
CLIENT_PAIR = os.path.join(REPO, 'server', 'tools', 'client_pair.py')
PAIR = 74
OUTFITS_73 = 3529
FIRST_NEW = OUTFITS_73 + 1
FIRST_WINGS_ID = 122          # wings.xml: the 121 wings of the pair 33 build end at 121
ANCHOR_Y = 2                  # from the creature's place: the torso row of the stock look 128 in the wings' frame (canvas y 66 of 3x3)
TILE_SIZES = (3, 4, 5)
MAX_PHASES = 32
STRAY_BOX = 5                 # an 11 x 11 box round a pixel
STRAY_MAX = 4                 # pixels the box may hold
STRAY_ALPHA = 192             # a stray has none at this alpha or above
GAP_COLS = 2                  # O495: the widest gap of this many empty columns splits the two masses
MASS_SHARE = 0.25             # and each mass holds this share of the art
CENTRE_TOL = 0.6              # px: the centre of every view from the anchor column, after the whole pixel shift of its direction
DIRS = ('north', 'east', 'south', 'west')   # engine order
NORTH, EAST, SOUTH, WEST = range(4)
KINDS = ('wings', 'borderline', 'aura')
PRICE_SMALL, PRICE_LARGE = 250, 300           # the store prices of the pair 33 wings by the drawn size (3x3 / larger)

# the wings in id order: (source outfit id, key, name, element). The element is the store text's ("Fire wings, animated."); the colours
# are the source's own (measured: the mean colour of the opaque pixels), the names ours, dark fantasy, English like every wings name.
ROWS = (
    (906, 'voidbloom', 'Voidbloom Wings', 'dark'),
    (903, 'bloodmoon', 'Bloodmoon Wings', 'dark'),
    (940, 'rustfang', 'Rustfang Wings', 'fire'),
    (912, 'nightglass', 'Nightglass Wings', 'dark'),
    (902, 'cinderveil', 'Cinderveil Wings', 'fire'),
    (943, 'ashenrelic', 'Ashen Relic Wings', 'neutral'),
    (908, 'gildenmourn', 'Gildenmourn Wings', 'light'),
    (942, 'sootweave', 'Sootweave Wings', 'neutral'),
    (913, 'mirewood', 'Mirewood Wings', 'earth'),
    (941, 'gravemist', 'Gravemist Wings', 'dark'),
    (904, 'drownlight', 'Drownlight Wings', 'water'),
    (1240, 'redthorn', 'Redthorn Wings', 'dark'),
    (915, 'wraithspan', 'Wraithspan Wings', 'water'),
    (1221, 'hollowhalo', 'Hollow Halo Wings', 'dark'),
    (1220, 'bloodring', 'Bloodring Wings', 'dark'),
)
ELEMENTS = ('dark', 'earth', 'fire', 'light', 'neutral', 'water', 'wind', 'energy')


def rows(path=TABLE):
    with open(path, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def read_sums(path=SUMS):
    return W.read_sums(path)


def anchor_of(tiles):
    """(x, y) of the anchor of an NxN canvas, from the creature's place in sprite px"""
    return 32 - 16 * tiles, ANCHOR_Y


def anchor_text(tiles):
    return '%d:%d' % anchor_of(tiles)


def tiles_of_size(text):
    m = re.fullmatch(r'(\d)x(\d)', text)
    return int(m.group(1)) if m and m.group(1) == m.group(2) and int(m.group(1)) in TILE_SIZES else None


def ints_of(text, n):
    m = re.fullmatch(r':'.join([r'(-?\d+)'] * n), text or '')
    return [int(v) for v in m.groups()] if m else None


def price_of(tiles):
    return PRICE_SMALL if tiles <= 3 else PRICE_LARGE


def row_text_of(r):
    return ','.join(r[k] for k in HEADER) + '\n'


def table_text(rs):
    return ','.join(HEADER) + '\n' + ''.join(row_text_of(r) for r in rs)


def sums_text(sums):
    return ('# sha256 of each outfit (shapes, animator, every sprite slot) by outfit id, written by gen_source_wings.py table --write (O627)\n'
            + ''.join('%s %s\n' % (k, sums[k]) for k in sorted(sums)))


def problems(table=None, sums=None, first=FIRST_NEW, want=ROWS):
    """What is wrong with the table: the rows are ROWS in order, ids in a row from the first new outfit, a src once, a name once, the kind,
    the size, the anchor of the size, the shift and centres, the counts, and the sums name the same outfits."""
    t = rows() if table is None else table
    s = read_sums() if sums is None else sums
    out, seen, names, keys = [], set(), set(), set()
    if want is not None and [(int(r['src']), r['key'], r['name']) for r in t] != [(a, b, c) for a, b, c, _ in want]:
        out.append('the rows are not ROWS of gen_source_wings.py, in its order')
    for i, r in enumerate(t):
        d, n = r['src'], int(r['new'])
        if not d.isdigit() or int(d) < 1:
            out.append('row %d: src %s is not an outfit id' % (i, d))
        if not re.fullmatch(r'[0-9a-f]{12}', r['srchash']):
            out.append('src %s: srchash %s is not 12 hex digits' % (d, r['srchash']))
        if n != first + i:
            out.append('src %s: new id %d, the row at line %d must be %d' % (d, n, i, first + i))
        if d in seen:
            out.append('src %s is on two rows' % d)
        seen.add(d)
        if r['name'] in names or r['key'] in keys:
            out.append('src %s: the name or the key is used twice' % d)
        names.add(r['name'])
        keys.add(r['key'])
        if not re.fullmatch(r'[a-z]{4,16}', r['key']):
            out.append('src %s: key %s is not 4 to 16 lower case letters' % (d, r['key']))
        if not re.fullmatch(r"[A-Z][A-Za-z' ]{3,30} Wings", r['name']):
            out.append('src %s: name %s is not a name ending in Wings' % (d, r['name']))
        if r['kind'] not in KINDS:
            out.append('src %s: kind %s is not one of %s' % (d, r['kind'], ', '.join(KINDS)))
        n_t = tiles_of_size(r['size'])
        if n_t is None:
            out.append('src %s: size %s is not 3x3, 4x4 or 5x5' % (d, r['size']))
            continue
        if r['anchor'] != anchor_text(n_t):
            out.append('src %s: anchor %s, an %s canvas has %s' % (d, r['anchor'], r['size'], anchor_text(n_t)))
        if not 1 <= int(r['frames']) <= MAX_PHASES:
            out.append('src %s: %s frames, 1 to %d' % (d, r['frames'], MAX_PHASES))
        if int(r['ms']) < 20:
            out.append('src %s: a phase lasts %s ms' % (d, r['ms']))
        sh = ints_of(r['shift'], 4)
        if sh is None or max(abs(v) for v in sh) > 160:
            out.append('src %s: shift %s is not four whole numbers of px north:east:south:west' % (d, r['shift']))
        cs = ints_of(r['centres'], 4)
        if cs is None:
            out.append('src %s: centres %s are not four whole numbers (tenths of a px) north:east:south:west' % (d, r['centres']))
        elif max(abs(v) for v in cs) > 10 * CENTRE_TOL:
            out.append('src %s: a view stands %s tenths of a px off the anchor column, at most %d' % (d, r['centres'], 10 * CENTRE_TOL))
        for k in ('strays', 'pixels', 'dirs', 'solid', 'dip', 'aspect', 'floor'):
            if not re.fullmatch(r'\d+', r[k]):
                out.append('src %s: %s %s is not a whole number' % (d, k, r[k]))
        if r['dirs'].isdigit() and not 1 <= int(r['dirs']) <= 4:
            out.append('src %s: dirs %s, 1 to 4' % (d, r['dirs']))
        if r['pixels'].isdigit() and int(r['pixels']) < 1:
            out.append('src %s: no pixels' % d)
        if r['kind'] in KINDS and r['solid'].isdigit() and r['dip'].isdigit() and r['floor'].isdigit() and r['dirs'].isdigit():
            if kind_of(int(r['dirs']), int(r['solid']), int(r['dip']), int(r['floor'])) != r['kind']:
                out.append('src %s: kind %s is not what the shape numbers say' % (d, r['kind']))
        if not re.fullmatch(r'(\d+:\d+|none)', r['src_light']):
            out.append('src %s: src_light %s is not N:colour or none' % (d, r['src_light']))
    if set(s) != {r['new'] for r in t}:
        out.append('source_wings.sums and the table name other outfits (%s)' % ', '.join(sorted(set(s) ^ {r['new'] for r in t})))
    return out


def kind_of(dirs, solid, dip, floor):
    """wings, borderline or aura from the shape numbers (solid and dip in hundredths, floor in px)"""
    if dirs <= 2 or (solid >= 85 and dip >= 90) or floor >= 16:
        return 'aura'
    if solid >= 70 and dip >= 85:
        return 'borderline'
    return 'wings'


def lib_rows(path=SERVER_LIB):
    """[(key, id, look, name, element, cost)] of the M.wings lines of the server lib, in file order"""
    if not os.path.exists(path):
        return []
    text = open(path, encoding='utf-8').read()
    return [(k, int(i), int(lk), n, e, int(c)) for k, i, lk, n, e, c in re.findall(
        r'\{key = "wings_(\w+)", id = (\d+), look = (\d+), name = "([^"]+)", element = "(\w+)", cost = (\d+)\}', text)]


def lib_problems(table=None, lib=None, path=SERVER_LIB):
    """the server lib names the table's wings: id, look, name, element, price by the drawn size, the pair of the gate"""
    t = rows() if table is None else table
    got = lib_rows(path) if lib is None else lib
    out = []
    want = [(r['key'], FIRST_WINGS_ID + i, int(r['new']), r['name'], e, price_of(tiles_of_size(r['size']) or 3))
            for i, (r, (_a, _b, _c, e)) in enumerate(zip(t, ROWS))]
    if got != want:
        out.append('server/data/lib/chaos_source_wings.lua M.wings is not the table: %s' % (
            [(a, b) for a, b in zip(got, want) if a != b][:2] or '%d rows, the table has %d' % (len(got), len(want))))
    if os.path.exists(path):
        text = open(path, encoding='utf-8').read()
        m = re.search(r'^M\.PAIR = (\d+)', text, re.M)
        cp = open(CLIENT_PAIR, encoding='utf-8').read()
        n = re.search(r'^PAIR_SOURCE_WINGS = (\d+)', cp, re.M)
        if not m or int(m.group(1)) != PAIR or not n or int(n.group(1)) != PAIR:
            out.append('the gate is not pair %d in the server lib and in client_pair.py PAIR_SOURCE_WINGS' % PAIR)
    return out


def anchors_text(table=None):
    t = rows() if table is None else table
    lines = ['\t\t{%d, %d, %d},\n' % ((int(r['new']),) + tuple(anchor_of(tiles_of_size(r['size'])))) for r in t]
    return ('-- Generated by client/tools/sprites/gen_source_wings.py anchors from art_import/source_wings.csv. Do not edit.\n'
            '-- Source wings (O627): the point of every source wings look that sits on the body torso, one row {look, x, y}, sprite px\n'
            '-- from the creature\'s place (base patch 0204 measures the body and puts this point on its torso). The same shape as\n'
            '-- wing_anchors.lua, but one anchor a look: the canvas of a wing is 3x3, 4x4 or 5x5 tiles.\n'
            'ChaosSourceWingAnchors = {\n'
            '\twings = {\n' + ''.join(lines) + '\t},\n}\nreturn ChaosSourceWingAnchors\n')


def anchors_problems(table=None, path=ANCHORS):
    out = []
    if not os.path.exists(path) or open(path, encoding='utf-8', newline='').read() != anchors_text(table):
        out.append('source_wing_anchors.lua is not what the table gives (run gen_source_wings.py anchors)')
    scripts = re.search(r'scripts:\s*\[([^\]]*)\]', open(OTMOD, encoding='utf-8').read())
    if not scripts or 'source_wing_anchors' not in [s.strip() for s in scripts.group(1).split(',')]:
        out.append('client_chaos_wingfit.otmod does not load source_wing_anchors')
    return out


# ---------------------------------------------------------------- the source pair

class Wing:
    """one source outfit: frames[d][p] RGBA (H, W, 4) with no colour under a transparent pixel, the durations, the dat displacement"""
    pass


def find_pair(src):
    for root, _dirs, files in os.walk(src):
        if 'Tibia.dat' in files and 'Tibia.spr' in files:
            return os.path.join(root, 'Tibia.dat'), os.path.join(root, 'Tibia.spr')
    raise SystemExit('no Tibia.dat and Tibia.spr under %s' % src)


def clean(a):
    import numpy as np
    return np.where(a[..., 3:4] > 0, a, 0).astype(np.uint8)


def src_hash(w):
    h = hashlib.sha256()
    h.update(repr((w.w, w.h, w.layers, w.px, w.py, w.pz, w.phases, w.durs, w.disp)).encode())
    for d in range(4):
        for p in range(w.phases):
            h.update(w.frames[d][p].tobytes())
    return h.hexdigest()[:12]


def load_source(src, ids=None):
    """{id: Wing} of the outfits `ids` (default: the ROWS) of the source pair under `src`"""
    import numpy as np
    from datspr import Dat, Spr, sprite_index
    dat_path, spr_path = find_pair(src)
    dat, spr = Dat(dat_path), Spr(spr_path)
    out = {}
    for i in (ids if ids is not None else [r[0] for r in ROWS]):
        t = dat.outfit(i)
        if t is None:
            raise SystemExit('the source pair has no outfit %d' % i)
        if len(t.groups) != 1:
            raise SystemExit('outfit %d: %d frame groups, a wing has one' % (i, len(t.groups)))
        gw, gh, _exact, layers, px, py, pz, ph, sp, anim = t.groups[0]
        if (layers, px, py, pz) != (1, 4, 1, 1) or not 1 <= ph <= MAX_PHASES:
            raise SystemExit('outfit %d: %d layers, patterns %d %d %d, %d phases: not a one layer wing of four directions' % (
                i, layers, px, py, pz, ph))
        w = Wing()
        w.id, w.w, w.h, w.layers, w.px, w.py, w.pz, w.phases = i, gw, gh, layers, px, py, pz, ph
        w.durs = tuple(anim[3]) if anim else (100, 100)
        d = t.flags.get('displacement')
        w.disp = tuple(v - 65536 if v >= 32768 else v for v in d) if isinstance(d, tuple) else (0, 0)
        w.light = tuple(t.flags['light']) if 'light' in t.flags else None
        w.frames = {}
        g = type('G', (), dict(w=gw, h=gh, layers=layers, px=px, py=py, pz=pz))
        for x in range(4):
            lst = []
            for p in range(ph):
                img = np.zeros((gh * 32, gw * 32, 4), np.uint8)
                for hh in range(gh):
                    for ww in range(gw):
                        a = spr.sprite(sp[sprite_index(g, x, 0, 0, 0, p, ww, hh)])
                        if a is not None:
                            img[(gh - 1 - hh) * 32:(gh - hh) * 32, (gw - 1 - ww) * 32:(gw - ww) * 32] = a
                lst.append(clean(img))
            w.frames[x] = lst
        out[i] = w
    return out


# ---------------------------------------------------------------- measuring

def box_sum(m, r):
    """for every pixel the count of set pixels of the (2r+1) x (2r+1) box round it"""
    import numpy as np
    h, w = m.shape
    p = np.pad(m.astype(np.int64), r)
    c = np.zeros((p.shape[0] + 1, p.shape[1] + 1), np.int64)
    c[1:, 1:] = p.cumsum(0).cumsum(1)
    n = 2 * r + 1
    return c[n:n + h, n:n + w] - c[:h, n:n + w] - c[n:n + h, :w] + c[:h, :w]


def strays_of(a):
    """boolean mask of the stray specks of a frame: pixels whose box holds STRAY_MAX or fewer pixels, none of them solid enough"""
    import numpy as np
    m = a[..., 3] > 0
    if not m.any():
        return m
    few = box_sum(m, STRAY_BOX) <= STRAY_MAX
    solid = box_sum(a[..., 3] >= STRAY_ALPHA, STRAY_BOX) > 0
    return m & few & ~solid


def centre_x(frames):
    """(centre column, method) of a direction by the O495 rule: the alpha weighted mean over all phases, or the midpoint of the two
    masses' means when the union has a gap of GAP_COLS empty columns or more with MASS_SHARE of the art on each side"""
    import numpy as np
    wt = sum(f[..., 3].astype(np.float64).sum(0) for f in frames)
    cols = np.nonzero(wt)[0]
    xs = np.arange(len(wt), dtype=np.float64)
    lo, hi = cols[0], cols[-1]
    best, at = 0, None
    run = 0
    for c in range(lo, hi + 1):
        if wt[c] == 0:
            run += 1
            if run > best:
                best, at = run, c - run + 1
        else:
            run = 0
    if best >= GAP_COLS:
        left, right = slice(lo, at), slice(at + best, hi + 1)
        tot = wt.sum()
        if wt[left].sum() >= MASS_SHARE * tot and wt[right].sum() >= MASS_SHARE * tot:
            ml = (wt[left] * xs[left]).sum() / wt[left].sum()
            mr = (wt[right] * xs[right]).sum() / wt[right].sum()
            return (ml + mr) / 2.0, 'two'
    return float((wt * xs).sum() / wt.sum()), 'mean'


def hull_area(pts):
    pts = sorted(set(map(tuple, pts)))
    if len(pts) < 3:
        return float(len(pts))

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo = []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    up = []
    for p in reversed(pts):
        while len(up) >= 2 and cross(up[-2], up[-1], p) <= 0:
            up.pop()
        up.append(p)
    h = lo[:-1] + up[:-1]
    a = 0
    for i in range(len(h)):
        x1, y1 = h[i]
        x2, y2 = h[(i + 1) % len(h)]
        a += x1 * y2 - x2 * y1
    return abs(a) / 2.0 + len(h) / 2.0 + 1


def shape_numbers(f, anchor_xy):
    """the numbers of the shape test from a south frame (RGBA of the placed canvas) and the anchor's canvas point:
    solid and dip in hundredths, aspect in hundredths, floor in px"""
    import numpy as np
    a = f[..., 3] > 0
    ys, xs = np.nonzero(a)
    solid = a.sum() / hull_area(np.stack([xs, ys], 1))
    cols = a.sum(0)[xs.min():xs.max() + 1].astype(np.float64)
    n = len(cols)
    third, sides = cols[n // 3:2 * n // 3], np.concatenate([cols[:n // 3], cols[2 * n // 3:]])
    dip = third.mean() / max(sides.mean(), 1e-9)
    aspect = (xs.max() - xs.min() + 1) / float(ys.max() - ys.min() + 1)
    near = float(np.hypot(xs - anchor_xy[0], ys - anchor_xy[1]).min())
    return int(round(100 * solid)), int(round(100 * dip)), int(round(100 * aspect)), int(near)


def fit(w):
    """the placed wing: {'tiles', 'shift', 'strays', 'placed': {d: [RGBA canvas per phase]}, 'centres': [4 floats from the anchor column],
    'methods'} from a source Wing; raises ValueError when no canvas up to 5x5 holds it"""
    import numpy as np
    src = {d: [f.copy() for f in w.frames[d]] for d in range(4)}
    nstrays = 0
    for d in range(4):
        for f in src[d]:
            s = strays_of(f)
            if s.any():
                nstrays += int(s.sum())
                f[s] = 0
    # the art in px from the creature's place (the source canvas bottom right on the tile, the dat displacement out)
    ox, oy = w.w * 32 - 32 + w.disp[0], w.h * 32 - 32 + w.disp[1]
    cen = {}
    for d in range(4):
        if not any(f[..., 3].any() for f in src[d]):
            raise ValueError('outfit %d: the %s view is empty' % (w.id, DIRS[d]))
        cen[d] = centre_x(src[d])
    for n in TILE_SIZES:
        ax, _ay = anchor_of(n)
        size = 32 * n
        shifts = [int(round(ax - (cen[d][0] - ox))) for d in range(4)]
        placed, ok = {}, True
        for d in range(4):
            lst = []
            for f in src[d]:
                img = np.zeros((size, size, 4), np.uint8)
                ys, xs = np.nonzero(f[..., 3])
                if len(ys):
                    nx = xs - ox + (size - 32) + shifts[d]
                    ny = ys - oy + (size - 32)
                    if nx.min() < 0 or nx.max() >= size or ny.min() < 0 or ny.max() >= size:
                        ok = False
                        break
                    img[ny, nx] = f[ys, xs]
                lst.append(img)
            if not ok:
                break
            placed[d] = lst
        if ok:
            anchor_col = size - 32 + ax
            return {'tiles': n, 'shifts': shifts, 'strays': nstrays, 'placed': placed,
                    'centres': [cen[d][0] - ox + shifts[d] + (size - 32) - anchor_col for d in range(4)],
                    'methods': [cen[d][1] for d in range(4)]}
    raise ValueError('outfit %d does not fit a canvas of %dx%d tiles with its anchor' % (w.id, TILE_SIZES[-1], TILE_SIZES[-1]))


def layers_of(d, img):
    """(y 0, y 1) of one frame of direction d: south and east before the body, north and west after it (the stock rule of the client)"""
    import numpy as np
    if d in (SOUTH, EAST):
        return img, np.zeros_like(img)
    solid = img[..., 3] == 255
    y0 = np.zeros_like(img)
    y0[solid] = img[solid]
    return y0, img


def count_pixels(placed):
    return int(sum((f[..., 3] > 0).sum() for d in range(4) for f in placed[d]))


def measure(w):
    """a table row (dict) of a source Wing, with the placed art"""
    import numpy as np
    f = fit(w)
    n = f['tiles']
    ax, ay = anchor_of(n)
    acx, acy = 32 * n - 32 + ax, 32 * n - 32 + ay
    south = f['placed'][SOUTH][0]
    solid, dip, aspect, near = shape_numbers(south, (acx, acy))
    distinct = {f['placed'][d][0].tobytes() for d in range(4)}
    ms = set(w.durs)
    if len(ms) != 1:
        raise ValueError('outfit %d: the phases do not all last the same time (%s)' % (w.id, sorted(ms)))
    r = {'src': str(w.id), 'srchash': src_hash(w), 'size': '%dx%d' % (n, n), 'frames': str(w.phases), 'ms': str(w.durs[0]),
         'anchor': anchor_text(n), 'shift': ':'.join(str(v) for v in f['shifts']),
         'centres': ':'.join(str(int(round(10 * c))) for c in f['centres']),
         'strays': str(f['strays']), 'pixels': str(count_pixels(f['placed'])), 'dirs': str(len(distinct)), 'solid': str(solid),
         'dip': str(dip), 'aspect': str(aspect), 'floor': str(near),
         'src_light': '%d:%d' % w.light if w.light else 'none', 'kind': kind_of(len(distinct), solid, dip, near)}
    return r, f


def groups_of(f, w_ms, phases):
    """[(Group, [tile arrays in slot order])] of a fitted wing: one group of type 1, NxN, one layer, 4 directions, 2 y patterns"""
    from import_outfits import Group
    from gen_effects import tiles_of
    n = f['tiles']
    g = Group()
    g.gtype, g.w, g.h, g.exact, g.layers, g.px, g.py, g.pz, g.phases = 1, n, n, 32 * n, 1, 4, 2, 1, phases
    g.anim = (0, 0, 0, tuple([w_ms, w_ms] * phases)) if phases > 1 else None
    pic = {}
    for ph in range(phases):
        for d in range(4):
            y0, y1 = layers_of(d, f['placed'][d][ph])
            pic[(ph, 0, d)] = tiles_of(y0, n, n)
            pic[(ph, 1, d)] = tiles_of(y1, n, n)
    tiles = []
    for ph in range(phases):          # the slot order of datspr.sprite_index: phase, z, y, x, layer, hh, ww
        for y in range(2):
            for d in range(4):
                t = pic[(ph, y, d)]
                for hh in range(n):
                    for ww in range(n):
                        tiles.append(t[(ww, hh)])
    g.sprites = tuple(range(len(tiles)))
    return [(g, tiles)]


def flags_of(_row=None):
    """(the flag bytes of an outfit entry, the flags as the dat reader gives them): animateAlways only"""
    from import_outfits import NEW_BYTE
    return bytes([NEW_BYTE['animateAlways']]), {'animateAlways': True}


def measured(src, want=ROWS, first=FIRST_NEW):
    """[(row dict, fit)] of the wings of `want`, ids from `first`"""
    ws = load_source(src, [r[0] for r in want])
    out = []
    for i, (sid, key, name, _el) in enumerate(want):
        try:
            r, f = measure(ws[sid])
        except ValueError as e:
            raise SystemExit(str(e))
        r.update({'new': str(first + i), 'key': key, 'name': name, 'note': NOTES.get(sid, '')})
        out.append((r, f, ws[sid]))
    return out


# the notes of the table (facts the owner reads: no source name, only our own ids)
NOTES = {1240: 'dup of look 1186 (Strength Wings) before O583 redrew it'}


def pack_sums(ms):
    return {r['new']: W.spec_digest(groups_of(f, int(r['ms']), int(r['frames']))) for r, f, _w in ms}


def build(dat, spr, out_dir, src, want=ROWS, first=FIRST_NEW, log=print):
    """pair in (its outfits end at first - 1) -> pair out in OUT_DIR: one new outfit per row. Returns the new ids."""
    ms = measured(src, want, first)
    by = {r['new']: (f, int(r['ms']), int(r['frames'])) for r, f, _w in ms}
    ids = W.build(dat, spr, out_dir, None, table=[r for r, _f, _w in ms], first=first, log=log,
                  specs_of=lambda r: groups_of(by[r['new']][0], by[r['new']][1], by[r['new']][2]), flags_of=flags_of)
    for r, f, _w in ms:
        log('%d %-10s src %-4s %s canvas, shifts %s, %d strays' % (int(r['new']), r['key'], r['src'], r['size'], r['shift'], int(r['strays'])))
    return ids


def pair_views(dat, spr, look):
    """({d: [(y0, y1) RGBA canvas per phase]}, the group) of a wings look of a pair"""
    import numpy as np
    from import_outfits import parse_body
    t = dat.outfit(look)
    gs = parse_body(dat, t)
    g = gs[0]
    n = g.w
    out = {}
    for d in range(4):
        lst = []
        for ph in range(g.phases):
            pair = []
            for y in range(2):
                img = np.zeros((32 * n, 32 * n, 4), np.uint8)
                for hh in range(n):
                    for ww in range(n):
                        sid = g.sprites[((((ph * g.pz) * g.py + y) * g.px + d) * g.layers * n + hh) * n + ww]
                        a = spr.sprite(sid) if sid else None
                        if a is not None:
                            img[(n - 1 - hh) * 32:(n - hh) * 32, (n - 1 - ww) * 32:(n - ww) * 32] = a
                pair.append(img)
            lst.append(tuple(pair))
        out[d] = lst
    return out, g


def live(dat, spr, table=None, sums=None, log=print):
    """the pair holds every wing at its id: the digest of the sums file, the shape the table says (NxN, one layer, 4 x 2 patterns, the
    frames and milliseconds, animateAlways only), the layers by the rule, the face-on views on the anchor column, the pixel count"""
    import numpy as np
    from datspr import Dat, Spr
    from import_outfits import parse_body
    t = rows() if table is None else table
    s = read_sums() if sums is None else sums
    d, sp = Dat(dat), Spr(spr)
    last = int(t[-1]['new'])
    if len(d.outfits) < last:
        return ['the pair has %d outfits, the source wings end at %d' % (len(d.outfits), last)]
    out = []
    for r in t:
        nid = int(r['new'])
        who = 'outfit %d (src %s)' % (nid, r['src'])
        if W.digest(d, sp, nid) != s.get(r['new']):
            out.append('%s: the pictures are not the ones of source_wings.sums' % who)
        th = d.outfit(nid)
        gs = parse_body(d, th)
        n = tiles_of_size(r['size'])
        ph, ms = int(r['frames']), int(r['ms'])
        if dict(th.flags) != {'animateAlways': True}:
            out.append('%s: flags %s, animateAlways only' % (who, dict(th.flags)))
        elif len(gs) != 1 or (gs[0].gtype, gs[0].w, gs[0].h, gs[0].layers, gs[0].px, gs[0].py, gs[0].pz) != (1, n, n, 1, 4, 2, 1):
            out.append('%s: not one group of %s, one layer, 4 directions, 2 y patterns' % (who, r['size']))
        elif gs[0].phases != ph or (ph > 1 and (not gs[0].anim or tuple(gs[0].anim[3]) != (ms, ms) * ph)):
            out.append('%s: not %d phases of %d ms' % (who, ph, ms))
        else:
            views, g = pair_views(d, sp, nid)
            total = 0
            ax, _ay = anchor_of(n)
            col = 32 * n - 32 + ax
            for dd in range(4):
                for p in range(ph):
                    y0, y1 = views[dd][p]
                    want0, want1 = layers_of(dd, y1 if dd in (NORTH, WEST) else y0)
                    if not (np.array_equal(clean(y0), want0) and np.array_equal(clean(y1), want1)):
                        out.append('%s: the layers of the %s view, phase %d, are not the rule' % (who, DIRS[dd], p))
                        break
                    total += int((y1 if dd in (NORTH, WEST) else y0)[..., 3].astype(bool).sum())
            for dd in range(4):
                whole = [(y1 if dd in (NORTH, WEST) else y0) for y0, y1 in views[dd]]
                c, _m = centre_x(whole)
                if abs(c - col) > CENTRE_TOL:
                    out.append('%s: the %s view is centred %.1f px from the anchor column %d, at most %d' % (who, DIRS[dd], c - col, col, CENTRE_TOL))
            if total != int(r['pixels']):
                out.append('%s: %d pixels in its sprites, the table counts %s' % (who, total, r['pixels']))
    log('live: %d wings %d to %d checked, %d problems' % (len(t), int(t[0]['new']), last, len(out)))
    return out


# ---------------------------------------------------------------- the preview

BG = (56, 60, 68)
CELL = 192          # px at 1x of one view: the torso is at TORSO
TORSO = (96, 130)
SCALE = 2


def figure(d):
    """a plain dark grey 1x1 stand-in body, RGBA 96 x 96 with its torso at (48, 64): a head, a torso of 20 rows and two legs"""
    import numpy as np
    img = np.zeros((96, 96, 4), np.uint8)
    body = np.array([70, 72, 80, 255], np.uint8)
    light = np.array([104, 106, 116, 255], np.uint8)
    dark = np.array([30, 30, 36, 255], np.uint8)
    img[54:74, 42:54] = body                  # torso, rows 54 to 73: its middle is the anchor row 64
    img[74:84, 43:46] = body                  # legs
    img[74:84, 50:53] = body
    img[43:53, 41:51] = light                 # head
    for box in ((54, 74, 42, 54), (74, 84, 43, 46), (74, 84, 50, 53), (43, 53, 41, 51)):
        y0, y1, x0, x1 = box
        img[y0:y1, x0] = dark
        img[y0:y1, x1 - 1] = dark
        img[y0, x0:x1] = dark
        img[y1 - 1, x0:x1] = dark
    if d != NORTH:
        ex = {SOUTH: 0, EAST: 3, WEST: -3}[d]
        img[47, 43 + ex] = dark
        img[47, 48 + ex] = dark
    return img


def over(dst, src, x, y):
    """alpha blend RGBA src on RGB float dst at (x, y), clipped"""
    import numpy as np
    h, w = src.shape[:2]
    x0, y0, x1, y1 = max(0, x), max(0, y), min(dst.shape[1], x + w), min(dst.shape[0], y + h)
    if x1 <= x0 or y1 <= y0:
        return
    s = src[y0 - y:y1 - y, x0 - x:x1 - x].astype(np.float64)
    a = s[..., 3:4] / 255.0
    dst[y0:y1, x0:x1] = dst[y0:y1, x0:x1] * (1 - a) + s[..., :3] * a


BOB = (0, -1, -2, -1)


def view_cell(f, d, walking, step):
    """RGB float CELL x CELL of direction d: the wings' y 0 behind the body, the body, y 1 in front, the anchor on the torso. Walking: the
    body drifts along its facing and bobs; the wings follow it (the engine puts the anchor on the torso as drawn)"""
    import numpy as np
    cell = np.empty((CELL, CELL, 3), np.float64)
    cell[:] = BG
    n = f['tiles']
    ax, ay = anchor_of(n)
    size = 32 * n
    y0, y1 = layers_of(d, f['placed'][d][f['phase'](step)])
    drift = ((step % 24) - 12) if walking else 0
    dx = {NORTH: 0, SOUTH: 0, EAST: drift, WEST: -drift}[d]
    dy = {NORTH: -drift, SOUTH: drift, EAST: 0, WEST: 0}[d]
    tx = TORSO[0] + dx
    ty = TORSO[1] + dy + (BOB[(step // 3) % 4] if walking else 0)
    wx, wy = tx - (size - 32 + ax), ty - (size - 32 + ay)
    over(cell, y0, int(wx), int(wy))
    over(cell, figure(d), int(tx - 48), int(ty - 64))
    over(cell, y1, int(wx), int(wy))
    return cell


def write_mp4(path, frames_iter, w, h, fps):
    import numpy as np
    cmd = ['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', '%dx%d' % (w, h), '-framerate', str(fps),
           '-i', '-', '-pix_fmt', 'yuv420p', '-c:v', 'libx264', '-crf', '18', '-movflags', '+faststart', path]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for img in frames_iter:
        proc.stdin.write(np.ascontiguousarray(img).tobytes())
    proc.stdin.close()
    if proc.wait() != 0:
        raise SystemExit('ffmpeg failed for ' + path)


def label_image(width, text):
    import numpy as np
    from PIL import Image, ImageDraw
    im = Image.new('RGB', (width // SCALE, 20), (30, 32, 38))
    ImageDraw.Draw(im).text((4, 4), text, fill=(236, 236, 236))
    return np.asarray(im.resize((width, 40), Image.NEAREST))


def preview(path, src, seconds=6, fps=20, want=ROWS, log=print):
    """one MP4: each wing for `seconds`, a row of the four directions standing and a row walking, at game scale 2x, a label with the
    source id, our outfit id and the name; on a plain grey stand-in body (no pair 73 needed)"""
    import numpy as np
    ms = measured(src, want)
    cw = CELL * SCALE
    width, height = 4 * cw, 2 * cw + 40
    labels = {}

    def frames():
        for r, f, w in ms:
            f['phase'] = (lambda step, ph=int(r['frames']), t=int(r['ms']): int(step * 1000.0 / fps / t) % ph)
            lab = label_image(width, '%s   src %s   outfit %s   %s   %s canvas   %s' % (r['name'], r['src'], r['new'], r['kind'], r['size'],
                                                                                  'dup of 1186' if r['note'] else ''))
            for step in range(int(seconds * fps)):
                top = [view_cell(f, d, False, step) for d in (NORTH, EAST, SOUTH, WEST)]
                bot = [view_cell(f, d, True, step) for d in (NORTH, EAST, SOUTH, WEST)]
                grid = np.concatenate([np.concatenate(top, axis=1), np.concatenate(bot, axis=1)], axis=0)
                grid = np.repeat(np.repeat(grid, SCALE, axis=0), SCALE, axis=1).astype(np.uint8)
                yield np.concatenate([lab, grid], axis=0)
    write_mp4(path, frames(), width, height, fps)
    log('wrote %s: %d wings, %dx%d, %d s each' % (path, len(ms), width, height, seconds))


# ---------------------------------------------------------------- the command line

def opt(args, key):
    return W.opt(args, key)


def main(argv):
    args = list(argv)
    if args[:1] == ['check']:
        p = problems() + lib_problems() + anchors_problems()
        for line in p:
            print('PROBLEM', line)
        print('source_wings: %d rows, %d problems' % (len(rows()), len(p)))
        return 1 if p else 0
    cmd = args.pop(0) if args else ''
    src = opt(args, '--src')
    if cmd == 'anchors':
        text = anchors_text()
        if '--check' in args:
            ok = os.path.exists(ANCHORS) and open(ANCHORS, encoding='utf-8', newline='').read() == text
            print('source_wing_anchors.lua: %s' % ('up to date' if ok else 'PROBLEM not what the table gives'))
            return 0 if ok else 1
        with open(ANCHORS, 'w', encoding='utf-8', newline='') as f:
            f.write(text)
        return 0
    if cmd == 'ids' and src:
        for sid, key, name, _el in ROWS:
            try:
                r, f, w = measured(src, [(sid, key, name, _el)], FIRST_NEW)[0]
                print('%s %-12s %s canvas %s frames x %s ms, shifts %s, centres %s, strays %s, dirs %s, solid %s dip %s aspect %s floor %s -> %s, light %s' % (
                    r['src'], key, r['size'], r['frames'], r['ms'], r['shift'], r['centres'], r['strays'], r['dirs'], r['solid'], r['dip'], r['aspect'],
                    r['floor'], r['kind'], r['src_light']))
            except SystemExit as e:
                print('%s cannot be a wing: %s' % (sid, e))
        return 0
    if cmd in ('table', 'sums') and src:
        ms = measured(src)
        ttext, stext = table_text([r for r, _f, _w in ms]), sums_text(pack_sums(ms))
        if cmd == 'sums' or '--check' in args:
            old = open(SUMS, encoding='utf-8').read() if os.path.exists(SUMS) else None
            oldt = open(TABLE, encoding='utf-8', newline='').read() if os.path.exists(TABLE) else None
            if old != stext or oldt != ttext:
                print('PROBLEM source_wings.csv / .sums are not what the source pair gives')
                return 1
            print('source_wings.csv and .sums: up to date')
            return 0
        sys.stdout.write(ttext)
        if '--write' in args:
            with open(TABLE, 'w', encoding='utf-8', newline='') as f:
                f.write(ttext)
            with open(SUMS, 'w', encoding='utf-8', newline='') as f:
                f.write(stext)
        return 0
    if cmd == 'build' and src and len(args) == 3:
        p = problems()
        if p:
            print('\n'.join(p))
            return 1
        ids = build(args[0], args[1], args[2], src)
        p = live(os.path.join(args[2], 'Tibia.dat'), os.path.join(args[2], 'Tibia.spr'))
        for line in p:
            print('PROBLEM', line)
        print('built %d wings %d to %d' % (len(ids), ids[0], ids[-1]))
        return 1 if p else 0
    if cmd == 'live' and len(args) == 2:
        p = live(args[0], args[1])
        for line in p:
            print('PROBLEM', line)
        return 1 if p else 0
    if cmd == 'preview' and src and len(args) == 1:
        preview(args[0], src)
        return 0
    print(__doc__)
    return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
