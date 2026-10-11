#!/usr/bin/env python3
"""Small icons of the depot window (client module game_depottabs).

Run: python3 -I client/tools/gen_depot_art.py [OUTDIR]
     default OUTDIR: client/overlay/data/images/game/depot  ->  lock.png (10x12, a locked tab), edit.png (12x12, the
     rename / colour button), store.png (12x12, the store button: a coin with a plus)

Drawn from pixel masks in the house palette (ember gold, iron, near-black outline; client_chaos_theme styles.otui).
Our own art; deterministic. Needs Pillow."""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
DEFAULT_OUT = os.path.join(ROOT, 'client', 'overlay', 'data', 'images', 'game', 'depot')

PALETTE = {
    '.': None,
    'k': (13, 11, 14, 255),      # outline (bg / near-black)
    'g': (232, 184, 74, 255),    # ember gold
    'h': (246, 207, 114, 255),   # bright gold (light from the top left)
    'd': (150, 108, 40, 255),    # dark gold
    'i': (125, 113, 118, 255),   # iron light
    'n': (58, 51, 57, 255),      # iron
    'p': (214, 201, 174, 255),   # parchment
    'r': (184, 22, 15, 255),     # blood
}

LOCK = [
    '...kkkk...',
    '..kiiiik..',
    '.kik..kik.',
    '.ki....ik.',
    '.kn....nk.',
    'kkkkkkkkkk',
    'khhggggggk',
    'khgggkgggk',
    'kggggkgggk',
    'kgggggggdk',
    'kddddddddk',
    'kkkkkkkkkk',
]

EDIT = [
    '........kk..',
    '.......krrk.',
    '......kprrk.',
    '.....khpkk..',
    '....khgk....',
    '...khgk.....',
    '..khgk......',
    '.khgdk......',
    '.kpdk.......',
    'kppk........',
    'kkk.........',
    '............',
]

STORE = [
    '...kkkkkk...',
    '..khhhgggk..',
    '.khhgggggdk.',
    'khggggkgggdk',
    'khggggkgggdk',
    'khggkkkkkgdk',
    'kgggggkgggdk',
    'kgggggkgggdk',
    '.kgggggggdk.',
    '..kddddddk..',
    '...kkkkkk...',
    '............',
]

ICONS = {'lock': LOCK, 'edit': EDIT, 'store': STORE}


def draw(mask):
    h, w = len(mask), len(mask[0])
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    for y, row in enumerate(mask):
        if len(row) != w:
            raise SystemExit('ragged mask row %d' % y)
        for x, ch in enumerate(row):
            c = PALETTE[ch]
            if c:
                img.putpixel((x, y), c)
    return img


def main(argv):
    out = argv[1] if len(argv) > 1 else DEFAULT_OUT
    os.makedirs(out, exist_ok=True)
    for name, mask in sorted(ICONS.items()):
        path = os.path.join(out, name + '.png')
        draw(mask).save(path, optimize=True)
        print('wrote', os.path.relpath(path, ROOT))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
