#!/usr/bin/env python3
"""Art of the Dungeons window cards (client game_dungeons, O555): the nine-slice frames of a dungeon card and the
dark fade over the bottom of a picture.

usage: python3 -I client/tools/gen_dungeon_card_art.py [OUTDIR]
       python3 -I client/tools/gen_dungeon_card_art.py --check    (draws in memory, fails when a shipped file differs)
       default OUTDIR: client/overlay/data/images/dungeons

Files (names used by game_dungeons/dungeons.otui):
  card_frame.png        16x16 nine-slice (image-border 4): the card at rest. A black outline, a one pixel iron rim lit from
                        the top left, a dark inset line, a face that darkens downwards. The four corner pixels are cut.
  card_frame_hover.png  the same with a warm ember rim (the mouse is over the card)
  card_frame_sel.png    the same with a gold rim and a faint ember glow inside the rim (the card of the chosen dungeon)
  scrim.png             4x64: near black, fully clear at the top and 92% opaque at the bottom (an ease curve); the
                        client stretches it over the lower part of a dungeon picture so a name stays readable on any art

The palette is the theme's (client_chaos_theme/styles.otui: iron, ember gold, blood). No picture is copied from anywhere:
every pixel is computed here. Every alpha edge is hard (no blur) so the frames stay crisp at 1x. Deterministic; needs Pillow
only (CI runs it in the fx venv with the other art checks).
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..'))
OUT = os.path.join(REPO, 'client', 'overlay', 'data', 'images', 'dungeons')

BLACK = (13, 11, 14)
IRON_LIT, IRON_DARK = (87, 77, 82), (58, 51, 57)
EMBER_LIT, EMBER_DARK = (184, 116, 47), (110, 60, 24)
GOLD_LIT, GOLD_DARK, GOLD_INSET = (246, 207, 114), (168, 116, 32), (107, 74, 20)
FACE_TOP, FACE_BOTTOM = (42, 35, 41), (17, 14, 19)
FACE_HOVER_TOP, FACE_HOVER_BOTTOM = (58, 40, 32), (22, 14, 14)
FACE_SEL_TOP, FACE_SEL_BOTTOM = (54, 40, 26), (20, 14, 11)
GLOW = (224, 84, 30)

N = 16          # the nine-slice image is N x N, its border B
B = 4


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def frame(rim_lit, rim_dark, inset, face_top, face_bottom, glow=None):
    """One frame: black outline, rim (lit top left, dark bottom right), inset line, face gradient."""
    im = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    px = im.load()
    for y in range(N):
        t = y / (N - 1)
        face = lerp(face_top, face_bottom, t)
        for x in range(N):
            ring = min(x, y, N - 1 - x, N - 1 - y)
            if ring == 0:
                col = BLACK
            elif ring == 1:
                col = rim_lit if (x == 1 or y == 1) else rim_dark     # lit on the top and left edge
            elif ring == 2:
                col = inset
            elif ring == 3 and glow is not None:
                col = lerp(face, glow, 0.38)
            else:
                col = face
            px[x, y] = col + (255,)
    for x, y in ((0, 0), (N - 1, 0), (0, N - 1), (N - 1, N - 1)):   # the four corner pixels are cut
        px[x, y] = (0, 0, 0, 0)
    return im


def scrim():
    w, h = 4, 64
    im = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    px = im.load()
    for y in range(h):
        t = y / (h - 1)
        a = int(round(235 * (t * t * (3 - 2 * t))))     # smoothstep: clear on top, dense at the bottom
        for x in range(w):
            px[x, y] = BLACK + (a,)
    return im


def build():
    return {
        'card_frame.png': frame(IRON_LIT, IRON_DARK, (10, 8, 11), FACE_TOP, FACE_BOTTOM),
        'card_frame_hover.png': frame(EMBER_LIT, EMBER_DARK, (24, 12, 8), FACE_HOVER_TOP, FACE_HOVER_BOTTOM),
        'card_frame_sel.png': frame(GOLD_LIT, GOLD_DARK, GOLD_INSET, FACE_SEL_TOP, FACE_SEL_BOTTOM, glow=GLOW),
        'scrim.png': scrim(),
    }


def same(a, b):
    return a.size == b.size and a.mode == b.mode and a.tobytes() == b.tobytes()


def main(argv):
    check = '--check' in argv
    args = [a for a in argv if not a.startswith('--')]
    files = build()
    if check:
        bad = []
        for name, im in files.items():
            path = os.path.join(OUT, name)
            if not os.path.isfile(path):
                bad.append('%s: missing' % name)
                continue
            with Image.open(path) as got:
                if not same(got.convert('RGBA'), im):
                    bad.append('%s: differs from the generator' % name)
        if bad:
            print('gen_dungeon_card_art --check FAILED:\n  ' + '\n  '.join(bad))
            print('  run: python3 -I client/tools/gen_dungeon_card_art.py')
            return 1
        print('gen_dungeon_card_art --check ok (%d files)' % len(files))
        return 0
    out = args[0] if args else OUT
    os.makedirs(out, exist_ok=True)
    for name, im in files.items():
        im.save(os.path.join(out, name), optimize=True)
    print('wrote %d files to %s' % (len(files), out))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
