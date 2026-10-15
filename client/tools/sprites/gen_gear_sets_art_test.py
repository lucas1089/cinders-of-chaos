#!/usr/bin/env python3
"""python3 -I client/tools/sprites/gen_gear_sets_art_test.py : the pure parts of gen_gear_sets_art.py (the layout of
every sheet, the one- / two-handed split by size, the exact palette PNG, the rules, the names and the things table of
the committed atlases). No sources needed."""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_gear_sets_art as G  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


# the layout: 64 cells a set, known kinds, armour fits, every kind every set needs
for key, *_r in G.SETS:
    cells = G.cells_of(key)
    kinds = {k for _r, _c, k, _f in cells}
    check(len(cells) == 64, key + ': 64 cells')
    need = {'helmet', 'armor', 'shield', 'spellbook', 'sword', 'axe', 'club', 'bow', 'crossbow', 'amulet', 'ring', 'wand',
            'rod'}
    check(need <= kinds, key + ': every kind of the sheets')
    fits = {(k, f) for _r, _c, k, f in cells if k in ('helmet', 'armor')}
    check(all((k, f) in fits for k in ('helmet', 'armor') for f in 'HMC'), key + ': heavy, medium and cloth head and body')
    check(all(f == '' for _r, _c, k, f in cells if k not in ('helmet', 'armor', 'legs')), key + ': fits only on armour')
check(len(G.SETS) == 7 and len(set(G.SOURCES)) == 7, 'seven sets from seven sheets')

# one- / two-handed: the larger half by art pixels
sheet = np.zeros((256, 256, 4), np.uint8)
key = 'cinderwrought'
swords = [(r, c) for r, c, k, _f in G.cells_of(key) if k == 'sword']
for i, (r, c) in enumerate(swords):
    sheet[r * 32:r * 32 + 4 + 4 * i, c * 32:c * 32 + 10, 3] = 255
h = G.hands_of(key, sheet)
check([h[rc] for rc in swords] == [1, 1, 2, 2], 'hands: the two larger swords are two-handed')
clubs = [(r, c) for r, c, k, _f in G.cells_of(key) if k == 'club']
check(sorted(h[rc] for rc in clubs) == [1, 2], 'hands: of two equal clubs the later one is two-handed')

# the exact palette PNG keeps every pixel
rng = np.random.RandomState(7)
pal = rng.randint(0, 256, (40, 4)).astype(np.uint8)
pal[0] = 0
img = pal[rng.randint(0, 40, (256, 256))]
img[img[..., 3] == 0] = 0
check(np.array_equal(G.decode(G.png_bytes(img)), img), 'png_bytes: lossless')

# rules: an empty cell and colour under alpha 0 are reported
bad = img.copy()
bad[:32, :32] = 0
check(any('empty cell (0, 0)' in b for b in G.check_rules('t', bad)), 'rules: empty cell')
bad[0, 0] = (5, 0, 0, 0)
check(any('colour under alpha 0' in b for b in G.check_rules('t', bad)), 'rules: colour under alpha 0')

# the committed atlases: names unique per set, the things table in id order
atlases = G.read_atlases()
check(len(atlases) == 7, 'seven committed atlases')
if len(atlases) == 7:
    rows = G.things_rows(atlases)
    check(len(rows) == 448 and len({r[0] for r in rows}) == 448, 'things: 448 rows, unique keys')
    check(len({r[3] for r in rows}) == 448, 'things: unique names')
    check(rows[0][0] == 'cinderwrought_helmet_1' and rows[-1][4] == 'gear_sets/blightfang', 'things: sheet order')
    check(all(r[11] == 'copy:%d' % G.COPY[r[2]] for r in rows), 'things: dat flags of a stock item of the kind')
    for key, *_r in G.SETS:
        for p in G.piece_rows(key, atlases[key]):
            if p['kind'] in G.MELEE:
                check(p['fit'] in ('1', '2'), p['key'] + ': hands')

print('gen_gear_sets_art_test:', 'OK' if not failed else '%d failure(s)' % failed)
sys.exit(1 if failed else 0)
