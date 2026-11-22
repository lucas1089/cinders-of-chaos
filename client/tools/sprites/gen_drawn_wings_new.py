#!/usr/bin/env python3
"""The six code-drawn wings of O581 as NEW wings looks of pair 78 (O581 phase 2; client/MANIFEST.md "Code-drawn wings as cosmetics (O581 phase 2)").

usage: python3 -I client/tools/sprites/gen_drawn_wings_new.py new-table [--check]
       python3 -I client/tools/sprites/gen_drawn_wings_new.py build-new DAT SPR OUT_DIR
       python3 -I client/tools/sprites/gen_drawn_wings_new.py live-new DAT SPR
(gen_drawn_wings.py hands the same three commands over.)

The designs are those of gen_drawn_wings.py (Ember Pinions, Ossuary Wings, Void Orbit, Bladefan, Rimeshard, Grave Lanterns). Here they get
what a wing cosmetic needs: a client look id, a wings.xml id and a row in the table drawn_wings/new_looks.csv.

  key, name        the design key and name of gen_drawn_wings.py DESIGNS
  theme, element   a word for the look, and the element the store text names (the server reads the element)
  wings            the wings.xml id (the 121 old wings are 1-121; these are 122-127)
  look             the client look id: appended after the last outfit of pair 77 (3554), so 3555-3560

`new-table` writes (or with --check compares) the table rules, drawn_wings/new_looks.sums (one sha256 a look over its 128 pictures, the
same digest as designs.sums), client_chaos_wingfit/wing_anchors.lua (the six looks join the 121 of designs.csv) and the server's
data/lib/chaos_drawn_wings_ids.lua (ids, names, elements; data/lib/chaos_drawn_wings.lua adds the price and the gate).

`build-new DAT SPR OUT_DIR` takes pair 77 and no other (dat md5 80cdf40aa03fc6097752f2d0822ffae7, 3,554 outfits) and writes pair 78 in OUT_DIR
(not there yet): six new outfits 3555-3560, the same shape as the O583 wings (3 x 3 tiles, one layer, 4 directions, 2 y patterns: 0 the whole
wing, 1 the part in front of the body; 16 phases of 83 ms, no displacement, animateAlways), sprites appended only, every old outfit, item,
effect and missile byte for byte. Verified before the rename (the append-only guard of check_pair.py too). The table of the pair
(wing_centres.lua, its dat md5) is not touched here: the md5s of the live pair change only when pair 78 goes to windows-assets.

`live-new DAT SPR` holds a built pair to the table: the six looks exist, are wings looks of that shape and hold the pictures of new_looks.sums.
"""
import csv
import hashlib
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import gen_drawn_wings as k  # noqa: E402
import gen_drawn_wings_families as fm  # noqa: E402

CSV = os.path.join(HERE, 'drawn_wings', 'new_looks.csv')
SUMS = os.path.join(HERE, 'drawn_wings', 'new_looks.sums')
REPO = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
IDS_LUA = os.path.join(REPO, 'server', 'data', 'lib', 'chaos_drawn_wings_ids.lua')

PAIR_IN = 77
PAIR_OUT = 78
INPUT_DAT_MD5 = '80cdf40aa03fc6097752f2d0822ffae7'     # pair 77 (server/tools/client_pair.py PAIR_ASSETS_DAT_MD5)
INPUT_OUTFITS = 3554                                    # pair 77 ends at the last PixelLab monster (pairs 75-77 added effects and missiles only)
FIRST_NEW = INPUT_OUTFITS + 1                           # 3555
FIRST_WINGS = 122                                       # wings.xml ids: 1-121 are the old wings
ELEMENTS = ('fire', 'water', 'wind', 'earth', 'energy', 'light', 'dark', 'neutral')
HEADER = ['key', 'name', 'theme', 'element', 'wings', 'look']
# (theme, element) of the six designs, in gen_drawn_wings.DESIGNS order
THEMES = {'ember_pinions': ('ember', 'fire'), 'ossuary_wings': ('bone', 'dark'), 'void_orbit': ('void', 'dark'),
          'bladefan': ('steel', 'neutral'), 'rimeshard': ('frost', 'water'), 'grave_lanterns': ('grave', 'earth')}


def table_rows():
    """the rows the table must hold, from DESIGNS and the constants above"""
    out = []
    for i, (key, name, _o, _f, _p) in enumerate(k.DESIGNS):
        theme, element = THEMES[key]
        out.append({'key': key, 'name': name, 'theme': theme, 'element': element,
                    'wings': str(FIRST_WINGS + i), 'look': str(FIRST_NEW + i)})
    return out


def table_text(rows=None):
    rows = table_rows() if rows is None else rows
    return ','.join(HEADER) + '\n' + ''.join(','.join(r[c] for c in HEADER) + '\n' for r in rows)


def load(path=CSV):
    with open(path, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


# ------------------------------------------------------------------------------------------------ the pictures
def patterns(key):
    """{(y, direction index, frame): RGBA 96 x 96} of a design, the shape fm.patterns gives a row of the old table"""
    out = {}
    for x, d in enumerate(k.DIRS):
        for f in range(k.FRAMES):
            back, front = k.render_frame(key, d, f)
            out[(0, x, f)] = fm.whole(back, front)
            out[(1, x, f)] = front
    return out


def digests(rows=None):
    """{look: sha256 of the 128 pictures}"""
    rows = load() if rows is None else rows
    return {int(r['look']): fm.digest(patterns(r['key'])) for r in rows}


def sums_text(sums):
    return ''.join('%d %s\n' % (look, sums[look]) for look in sorted(sums))


def read_sums(path=SUMS):
    out = {}
    with open(path, encoding='utf-8') as f:
        for line in f:
            look, h = line.split()
            out[int(look)] = h
    return out


def anchor_looks(path=CSV):
    """the looks of this table, for wing_anchors.lua (gen_drawn_wings_families.anchors_text joins them to the 121 of designs.csv)"""
    return sorted(int(r['look']) for r in load(path)) if os.path.isfile(path) else []


# ------------------------------------------------------------------------------------------------ the rules
def problems(rows=None, old=None):
    """the rules of the table that need no drawing: the rows are the designs in order, the ids are the next free ones, no name or id of
    an old wing is taken"""
    rows = load() if rows is None else rows
    old = fm.load() if old is None else old
    bad = []
    want = table_rows()
    if [r['key'] for r in rows] != list(k.KEYS):
        bad.append('the rows must be the six designs of gen_drawn_wings.py in order: %s' % [r['key'] for r in rows])
    if rows != want:
        bad.append('new_looks.csv is not what the designs and the ids rule give: run new-table')
    looks = [int(r['look']) for r in rows]
    wings = [int(r['wings']) for r in rows]
    if looks != list(range(FIRST_NEW, FIRST_NEW + len(rows))):
        bad.append('looks must be %d..%d in order: %s' % (FIRST_NEW, FIRST_NEW + len(rows) - 1, looks))
    if wings != list(range(FIRST_WINGS, FIRST_WINGS + len(rows))):
        bad.append('wings ids must be %d..%d in order: %s' % (FIRST_WINGS, FIRST_WINGS + len(rows) - 1, wings))
    if set(looks) & {sp.look for sp in old} or set(wings) & {sp.wings for sp in old}:
        bad.append('a look or wings id of designs.csv is taken')
    old_names = {sp.name.lower() for sp in old}
    for r in rows:
        if r['name'].lower() in old_names:
            bad.append('%s: the name is one of the old wings' % r['name'])
        if r['element'] not in ELEMENTS:
            bad.append('%s: element %s' % (r['name'], r['element']))
        if not r['theme'].isalpha():
            bad.append('%s: theme' % r['key'])
    if len({r['name'] for r in rows}) != len(rows):
        bad.append('a name twice')
    return bad


# ------------------------------------------------------------------------------------------------ the server's ids file
def ids_text(rows=None):
    rows = load() if rows is None else rows
    lines = ['-- Generated by client/tools/sprites/gen_drawn_wings_new.py new-table from client/tools/sprites/drawn_wings/new_looks.csv. Do not edit.',
             '-- The six code-drawn wings of O581 as wings of client pair %d: the wings.xml id (the 121 old wings are 1-121), the client look' % PAIR_OUT,
             '-- (appended after the last outfit of pair %d, %d), the name and the element of the store text. Read by data/lib/chaos_drawn_wings.lua' % (PAIR_IN, INPUT_OUTFITS),
             '-- (the gate, the price, the store offers) and server/tools/install_outfits.py (the wings.xml lines).',
             'local M = {}', '', 'M.wings = {']
    lines.append(',\n'.join('\t{key = "wings_%s", id = %s, look = %s, name = "%s", element = "%s"}'
                            % (r['key'], r['wings'], r['look'], r['name'], r['element']) for r in rows))
    lines += ['}', '', 'return M', '']
    return '\n'.join(lines)


# ------------------------------------------------------------------------------------------------ the pair
def group_of(pats):
    """(Group, tiles in sprite order) of the one frame group of a wings look; shape as fm.new_group makes it"""
    from import_outfits import Group
    from datspr import sprite_index
    g = Group()
    g.gtype = 0
    g.w = g.h = fm.TILES
    g.exact = k.SIZE
    g.layers, g.px, g.py, g.pz, g.phases = 1, 4, fm.PATTERN_Y, 1, k.FRAMES
    g.anim = (0, 0, 0, (fm.FRAME_MS, fm.FRAME_MS) * k.FRAMES)
    n = g.w * g.h * g.px * g.py * g.pz * g.phases
    g.sprites = tuple(range(n))
    tiles = [np.zeros((32, 32, 4), np.uint8) for _ in range(n)]
    for (y, x, f), img in pats.items():
        for hh in range(g.h):
            for ww in range(g.w):
                tiles[sprite_index(g, x, y, 0, 0, f, ww, hh)] = np.ascontiguousarray(
                    img[(g.h - 1 - hh) * 32:(g.h - hh) * 32, (g.w - 1 - ww) * 32:(g.w - ww) * 32])
    return g, tiles


def flags_of(row):
    """(the flag bytes of the entry, the flags as the dat reader gives them): animateAlways only, no displacement"""
    from import_outfits import NEW_BYTE
    return bytes([NEW_BYTE['animateAlways']]), {'animateAlways': True}


def pair_ok(dat_path, n_outfits, expect_md5=INPUT_DAT_MD5, first=FIRST_NEW):
    """None when the pair is pair 77 as it is, else the reason it is refused"""
    with open(dat_path, 'rb') as f:
        got = hashlib.md5(f.read()).hexdigest()
    if got != expect_md5:
        return 'input dat md5 %s, expected %s (pair %d): this step takes pair %d only' % (got, expect_md5, PAIR_IN, PAIR_IN)
    if n_outfits != first - 1:
        return 'the input has %d outfits, pair %d has %d (already built?)' % (n_outfits, PAIR_IN, first - 1)
    return None


def build_new(dat, spr, out_dir, rows=None, first=FIRST_NEW, expect_md5=INPUT_DAT_MD5, log=print):
    """pair 77 -> pair 78 in OUT_DIR; returns the new look ids. `first` and `expect_md5` are the test's: a synthetic pair"""
    from datspr import Dat
    import gen_wst_outfits as W
    rows = load() if rows is None else rows
    if os.path.exists(out_dir):
        raise SystemExit('%s exists: remove it or name another folder' % out_dir)
    why = pair_ok(dat, len(Dat(dat).outfits), expect_md5, first)
    if why:
        raise SystemExit('refused: ' + why)
    if [int(r['look']) for r in rows] != list(range(first, first + len(rows))):
        raise SystemExit('refused: the table looks are not the next free outfit ids from %d' % first)
    cache = {}

    def specs_of(r):
        if r['key'] not in cache:
            cache[r['key']] = [group_of(patterns(r['key']))]
        return cache[r['key']]
    done = W.build(dat, spr, out_dir, None, table=rows, first=first, expect_md5=None, log=log, specs_of=specs_of, flags_of=flags_of)
    log('wings looks %s appended after outfit %d of pair %d; dat md5 of pair %d: run md5sum on %s' % (
        ', '.join(map(str, done)), first - 1, PAIR_IN, PAIR_OUT, os.path.join(out_dir, 'Tibia.dat')))
    return done


def live(dat_path, spr_path, rows=None, sums=None, log=print):
    """a pair holds the six wings looks: they exist, have the shape of a drawn wing and the pictures of new_looks.sums. Returns the problem lines"""
    from datspr import Dat, Spr
    rows = load() if rows is None else rows
    sums = read_sums() if sums is None else sums
    dat, spr = Dat(dat_path), Spr(spr_path)
    bad = []
    for r in rows:
        look = int(r['look'])
        got = fm.pair_patterns(dat, spr, look)
        if isinstance(got, str):
            bad.append(got)
        elif fm.digest(got) != sums.get(look):
            bad.append('look %d (%s): pictures are not those of new_looks.sums' % (look, r['key']))
        elif {name for name in dat.outfit(look).flags} != {'animateAlways'}:
            bad.append('look %d (%s): flags %s, animateAlways only' % (look, r['key'], sorted(dat.outfit(look).flags)))
    for line in bad:
        log(line)
    log('%d of %d new wings looks hold the drawn pictures' % (len(rows) - len(bad), len(rows)))
    return bad


# ------------------------------------------------------------------------------------------------ commands
def write_or_check(path, text, check):
    old = open(path, encoding='utf-8').read() if os.path.isfile(path) else None
    if old == text:
        return []
    if check:
        return ['%s is stale: run gen_drawn_wings_new.py new-table' % os.path.relpath(path, REPO)]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    print('wrote ' + os.path.relpath(path, REPO))
    return []


def main(argv):
    cmd, args = argv[0], argv[1:]
    check = '--check' in args
    args = [a for a in args if a != '--check']
    if cmd == 'new-table':
        bad = write_or_check(CSV, table_text(), check)
        bad += problems()
        if not bad:
            sums = digests()
            if len(set(sums.values())) != len(sums):
                bad.append('two looks draw the same pictures')
            old = fm.read_sums()
            if set(sums.values()) & set(old.values()):
                bad.append('a new look draws the same pictures as an old wing')
            bad += write_or_check(SUMS, sums_text(sums), check)
            bad += write_or_check(fm.ANCHORS, fm.anchors_text(), check)
            bad += write_or_check(IDS_LUA, ids_text(), check)
        for line in bad:
            print(line)
        print('%d new wings looks%s' % (len(load()) if os.path.isfile(CSV) else 0, '' if bad else ': ok'))
        return 1 if bad else 0
    if cmd == 'build-new':
        if len(args) != 3:
            print(__doc__)
            return 2
        build_new(args[0], args[1], args[2])
        return 0
    if cmd == 'live-new':
        if len(args) != 2:
            print(__doc__)
            return 2
        return 1 if live(args[0], args[1]) else 0
    raise SystemExit('unknown command %s' % cmd)


COMMANDS = ('new-table', 'build-new', 'live-new')

if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
