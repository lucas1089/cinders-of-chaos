#!/usr/bin/env python3
"""Name plate frames of game_nameplate (drawn behind player names by base patch 0022 as a 9-slice, border 6):
  plate_<id>.png  16x15: 6 px end caps (rim corners and a small ornament), a 4 px middle that is stretched under the name.
  ids: default (blackened iron, ember accent), gold (staff), crimson (siege champions), violet, frost, ember, verdant
  and bone (store frames), ashen, sapphire, rose, jade, copper, obsidian, amber and storm (the second store set),
  laurel, sepulchre and infernal (never sold: exclusives_config.lua; a crowned ornament), cinderwrought (the season
  pass premium track, crowned too). preview_nameplates.png (not shipped) shows them at 4x.
python3 -I client/tools/gen_nameplate_art.py   (writes into client/overlay/modules/game_nameplate/images/)"""
import os
import sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'overlay', 'modules', 'game_nameplate', 'images')
W, H, B = 16, 15, 6

# id: (rim, rim highlight, fill top, fill bottom, ornament, ornament core)
FRAMES = {
    'default': ((112, 98, 90), (168, 150, 136), (40, 30, 27), (14, 10, 10), (150, 58, 34), (240, 128, 60)),
    'gold':    ((196, 146, 52), (255, 226, 140), (52, 36, 14), (18, 12, 6), (210, 156, 50), (255, 236, 160)),
    'crimson': ((176, 34, 30), (240, 104, 84), (54, 14, 14), (18, 5, 5), (190, 36, 28), (255, 140, 100)),
    'violet':  ((128, 74, 178), (196, 156, 240), (36, 20, 48), (12, 6, 16), (140, 80, 196), (226, 190, 255)),
    'frost':   ((80, 140, 180), (176, 222, 248), (18, 32, 44), (6, 10, 15), (90, 150, 200), (206, 242, 255)),
    # store frames of the cosmetics update (server shop.lua FRAMES)
    'ember':   ((200, 96, 32), (255, 180, 110), (50, 22, 10), (16, 7, 4), (224, 110, 36), (255, 214, 140)),
    'verdant': ((70, 150, 70), (170, 230, 150), (18, 40, 20), (6, 14, 7), (84, 170, 80), (210, 255, 190)),
    'bone':    ((186, 176, 150), (240, 232, 210), (44, 40, 34), (14, 13, 11), (204, 194, 168), (255, 250, 236)),
    # the second set of store frames (server shop_core.lua FRAMES 6-13)
    'ashen':    ((132, 126, 120), (196, 190, 182), (34, 32, 30), (12, 11, 10), (150, 142, 132), (226, 218, 206)),
    'sapphire': ((40, 76, 176), (130, 170, 250), (12, 20, 52), (4, 7, 18), (52, 96, 210), (176, 206, 255)),
    'rose':     ((196, 92, 132), (250, 176, 206), (48, 18, 30), (16, 6, 10), (220, 108, 150), (255, 210, 228)),
    'jade':     ((40, 150, 130), (140, 230, 206), (10, 40, 36), (4, 14, 12), (52, 176, 150), (190, 255, 236)),
    'copper':   ((176, 102, 56), (236, 170, 120), (44, 24, 14), (15, 8, 5), (196, 116, 62), (255, 200, 150)),
    'obsidian': ((54, 44, 66), (130, 104, 160), (14, 11, 18), (5, 4, 7), (110, 70, 160), (200, 160, 255)),
    'amber':    ((210, 140, 30), (255, 210, 120), (52, 32, 8), (18, 11, 3), (230, 156, 36), (255, 230, 150)),
    'storm':    ((90, 150, 200), (220, 240, 255), (16, 26, 40), (5, 8, 14), (120, 190, 240), (255, 255, 255)),
    # never sold (exclusives_config.lua): drawn with a crowned ornament
    'laurel':    ((88, 150, 60), (226, 210, 120), (24, 38, 14), (8, 13, 5), (200, 176, 70), (255, 240, 160)),
    'sepulchre': ((96, 84, 96), (180, 164, 180), (24, 20, 26), (8, 7, 9), (150, 90, 200), (220, 180, 255)),
    'infernal':  ((150, 40, 16), (255, 150, 60), (40, 10, 4), (14, 3, 1), (255, 96, 24), (255, 220, 120)),
    # the season pass premium track (server seasonpass_config.lua, Ashen Pass tier 40): ash-grey iron, a cinder core
    'cinderwrought': ((92, 84, 80), (214, 160, 110), (30, 24, 22), (10, 8, 7), (230, 110, 40), (255, 214, 150)),
}
CROWNED = {'laurel', 'sepulchre', 'infernal', 'cinderwrought'}
FILL_ALPHA = 225


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def inside(x, y):
    """rounded rectangle with 2 px corner cut"""
    cut = {0: 2, 1: 1, H - 1: 2, H - 2: 1}.get(y, 0)
    return cut <= x <= W - 1 - cut


def plate(spec, crowned=False):
    rim, hi, top, bottom, orn, core = spec
    im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    px = im.load()
    for y in range(H):
        for x in range(W):
            if not inside(x, y):
                continue
            edge = not (inside(x - 1, y) and inside(x + 1, y) and inside(x, y - 1) and inside(x, y + 1))
            if edge:
                px[x, y] = rim + (255,)
            elif y == 1:
                px[x, y] = hi + (225,)  # bevel light along the top
            elif y == H - 2:
                px[x, y] = lerp(rim, (0, 0, 0), 0.4) + (240,)
            else:
                px[x, y] = lerp(top, bottom, (y - 2) / float(H - 5)) + (FILL_ALPHA,)
    # ornaments in the end caps: a small spiked diamond on the middle row, mirrored
    mid = H // 2
    for cx in (2, W - 3):
        for (dx, dy, c) in ((0, 0, core), (-1, 0, orn), (1, 0, orn), (0, -1, orn), (0, 1, orn),
                            (0, -2, rim), (0, 2, rim)):
            px[cx + dx, mid + dy] = c + (255,)
        if crowned:
            # two more points above and below the diamond: a small crown on the end cap
            for (dx, dy) in ((-1, -2), (1, -2), (-1, 2), (1, 2)):
                px[cx + dx, mid + dy] = core + (255,)
    # thin rule from each ornament toward the name (kept inside the cap, the stretched middle stays plain)
    for x in (4, 5):
        px[x, mid] = lerp(orn, bottom, 0.45) + (220,)
        px[W - 1 - x, mid] = lerp(orn, bottom, 0.45) + (220,)
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    images = {}
    for key, spec in FRAMES.items():
        images[key] = plate(spec, key in CROWNED)
        images[key].save(os.path.join(OUT, 'plate_%s.png' % key))
    if '--preview' in sys.argv:
        # the plates stretched to a name width, at 4x, for a look before a client build
        prev = Image.new('RGBA', (90 * 4, (H + 4) * len(images) * 4), (60, 54, 48, 255))
        for i, im in enumerate(images.values()):
            w = 90
            row = Image.new('RGBA', (w, H), (0, 0, 0, 0))
            row.paste(im.crop((0, 0, B, H)), (0, 0))
            row.paste(im.crop((B, 0, W - B, H)).resize((w - 2 * B, H), Image.NEAREST), (B, 0))
            row.paste(im.crop((W - B, 0, W, H)), (w - B, 0))
            prev.alpha_composite(row.resize((w * 4, H * 4), Image.NEAREST), (0, (i * (H + 4) + 2) * 4))
        prev.save(sys.argv[sys.argv.index('--preview') + 1])
    print('wrote', OUT)


if __name__ == '__main__':
    main()
