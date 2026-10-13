"""Themed equipment icons for gen_theme_art.py: the base pieces are PixelLab paintings (Create image Pro, style A:
classic 32x32 icons, near-black 1 px outline, light from the top-left), picked per piece and cleaned by item_post.py.
Only text prompts, the set's own palette (the ramps below) and a stock item of our pair as style reference went in;
no reference sheet of the owner was sent or read.

Committed:
    art_import/theme_items/<set>.png     one 32x32 cell per piece in theme_sets.pieces() order (the cleaned picks)
    art_import/theme_items_picks.csv     which candidate of which PixelLab job became each piece (provenance)
    art_import/theme_items_prompts.csv   the job of every piece: endpoint, size, prompt, style reference, seed
The raw PixelLab results are not in git (like the rift variants): `import_picks` turns them into the strips once.

Arrows and bolts are one painted piece each; their 8 stack patterns of the client (1, 2, 3, 4, 5, 10, 25, 50 pieces)
are made here: 1-5 copies of the piece side by side across its own axis (10, 25, 50 show 4, 5, 5 copies tied with a
leather band; a piece too long for the bundle is drawn smaller there). Deterministic.
"""
import csv
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ITEMS_DIR = os.path.join(HERE, 'art_import', 'theme_items')
PICKS = os.path.join(HERE, 'art_import', 'theme_items_picks.csv')
PROMPTS = os.path.join(HERE, 'art_import', 'theme_items_prompts.csv')
N = 32

# ------------------------------------------------------------------------------------------------ material ramps
# dark -> light, hue-shifted; each set's prompt palette is its materials' ramps (7 steps each) plus a near-black ink
M = {
    'bone': ['#2a2116', '#5e5038', '#9c8a64', '#cfc29a', '#f4ecd2'],
    'grave': ['#0e100e', '#22261f', '#3a4033', '#56604a', '#7c8868'],
    'necro': ['#06301a', '#0f6a34', '#22b25a', '#6cf29a', '#d8ffe4'],
    'ironblk': ['#0c0c10', '#1e1f26', '#363844', '#565a68', '#8a8e9c'],
    'voidsteel': ['#05060e', '#10152c', '#23305c', '#4a62a4', '#9cb8f0'],
    'voidcloth': ['#06040c', '#140e24', '#261c40', '#3e2f62', '#5e4c8a'],
    'voidglow': ['#0a1e5a', '#1e52c8', '#4a9cff', '#a6dcff', '#f0fbff'],
    'wood': ['#241306', '#4e2c10', '#7c4c22', '#a8743c', '#d4a468'],
    'leaf': ['#0c2410', '#1c4a1a', '#3a7a2a', '#6aae3e', '#b6dc72'],
    'bronze': ['#2a1806', '#6a4214', '#a26e26', '#d6a44a', '#f8dc96'],
    'amber': ['#3a1a02', '#8a4a06', '#d48812', '#ffc23e', '#fff0b0'],
    'leather': ['#1e1008', '#40220e', '#683a1a', '#91592c', '#bb8048'],
    'silver': ['#161c2c', '#3c465e', '#6e7c98', '#b0bcd2', '#f2f6ff'],
    'moonblue': ['#080e2a', '#142656', '#25428a', '#4a70c4', '#8eb2f0'],
    'moonglow': ['#1a3a7a', '#3c78d0', '#7cb8ff', '#c8e6ff', '#ffffff'],
    'gold': ['#3a2204', '#8a5c0c', '#cc961c', '#f4cc52', '#fff4be'],
    'crimson': ['#300406', '#6e0c12', '#aa1c22', '#e04838', '#ff9a7c'],
    'ivory': ['#3a3428', '#7a705c', '#bcb298', '#e8e0c8', '#ffffff'],
    'ruby': ['#3a0208', '#860a1a', '#d01c30', '#ff5a5a', '#ffd2c8'],
    'steel': ['#14181e', '#363e4a', '#626c7c', '#9ea8b6', '#e8eef4'],
    'red': ['#2a0404', '#640a0a', '#a01414', '#d63428', '#ff7a5c'],
    'white': ['#3c3a38', '#7c7872', '#b8b4aa', '#e2ded2', '#fffef8'],
    'ice': ['#06203e', '#10508c', '#2a8ad0', '#7ccaf6', '#e8fbff'],
    'icedeep': ['#040e22', '#0a2652', '#164890', '#2e76c8', '#66aee8'],
    'emerald': ['#02261a', '#05603a', '#0ea25c', '#4ce08e', '#c8ffe0'],
    'teal': ['#022a2c', '#06626a', '#10a2a6', '#4ee0d8', '#d4fff8'],
    'ivorygold': ['#4a3410', '#9a7426', '#d8b452', '#f6e2a0', '#fffcec'],
    'green': ['#0a2a08', '#18561a', '#2e8c2a', '#5ec244', '#b4f07c'],
    'orangewood': ['#2e1004', '#6a2a08', '#a84e14', '#de7c2a', '#ffb468'],
    'lime': ['#123a06', '#2a7a0c', '#52c41a', '#a6ff4a', '#f0ffd0'],
}
INK = '#0c0a0a'


def ramp7(name):
    """a 5-stop ramp with the midpoints added: 9 colours"""
    r = M[name]
    out = []
    for i in range(4):
        a = [int(r[i][j:j + 2], 16) for j in (1, 3, 5)]
        b = [int(r[i + 1][j:j + 2], 16) for j in (1, 3, 5)]
        out += [r[i], '#%02x%02x%02x' % tuple(round(x + (y - x) * 0.5) for x, y in zip(a, b))]
    return out + [r[4]]


def palette(materials):
    """the prompt palette of a set: ink + the ramps of its materials"""
    pal = [INK]
    for m in materials:
        pal += ramp7(m)
    return pal


# ------------------------------------------------------------------------------------------------ strips
def strip_path(set_key):
    return os.path.join(ITEMS_DIR, set_key + '.png')


def load_strip(set_key, n):
    """the set's cleaned pieces: a list of n 32x32 RGBA uint8 arrays"""
    a = np.asarray(Image.open(strip_path(set_key)).convert('RGBA'))
    if a.shape != (N, n * N, 4):
        raise SystemExit('%s: %s, expected %dx%d' % (strip_path(set_key), a.shape[:2], N, n * N))
    return [a[:, i * N:(i + 1) * N].copy() for i in range(n)]


# ------------------------------------------------------------------------------------------------ ammunition
STACK = (1, 2, 3, 4, 5, 10, 25, 50)          # the client's stack patterns (count -> pattern 0..7)
SHOWN = {1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 10: 4, 25: 5, 50: 5}     # copies drawn; a band from 10 up
BAND = ('#2c180a', '#5a3418', '#86532a')      # leather band of the bundles (dark, mid, light)


def _axis(on):
    ys, xs = np.nonzero(on)
    c = np.array([xs.mean(), ys.mean()])
    cov = np.cov(np.stack([xs - c[0], ys - c[1]]))
    w, v = np.linalg.eigh(cov)
    d = v[:, int(np.argmax(w))]
    n = np.array([-d[1], d[0]])
    if n[0] + n[1] < -1e-6 or (abs(n[0] + n[1]) <= 1e-6 and n[1] < 0):
        n = -n                                  # copies step towards the lower right (or down), behind the first
    return c, d, n


def _bundle(tile, m, step, band):
    on = tile[..., 3] > 0
    c, d, n = _axis(on)
    offs = [(int(round(k * step * n[0])), int(round(k * step * n[1]))) for k in range(m)]
    offs = [(ox - offs[-1][0] // 2, oy - offs[-1][1] // 2) for ox, oy in offs]
    C = 64
    cv = np.zeros((C, C, 4), np.uint8)
    for ox, oy in reversed(offs):               # the farthest copy first, the first copy on top
        ys, xs = np.nonzero(on)
        cv[ys + oy + 16, xs + ox + 16] = tile[ys, xs]
    if band:
        con = cv[..., 3] > 0
        ys, xs = np.nonzero(con)
        cc = np.array([xs.mean(), ys.mean()])
        u = (xs - cc[0]) * d[0] + (ys - cc[1]) * d[1]
        v = (xs - cc[0]) * n[0] + (ys - cc[1]) * n[1]
        sel = np.abs(u + 1.0) <= 1.0
        vmin, vmax = v[sel].min(), v[sel].max()
        for y, x, uu, vv in zip(ys[sel], xs[sel], u[sel], v[sel]):
            edge = vv <= vmin + 0.5 or vv >= vmax - 0.5
            col = BAND[0] if edge else BAND[2] if uu < -1.0 else BAND[1]
            cv[y, x, :3] = [int(col[i:i + 2], 16) for i in (1, 3, 5)]
    ys, xs = np.nonzero(cv[..., 3])
    return cv[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def ammo_stack(tile, margin=1):
    """the 8 stack patterns of one arrow or bolt tile; each centred in 32x32 inside the margin"""
    out = []
    lim = N - 2 * margin
    for count in STACK:
        m = SHOWN[count]
        t, shrink = tile, 0
        while True:
            step = 3.5
            while True:
                b = _bundle(t, m, step, count >= 10)
                if max(b.shape[:2]) <= lim or step <= 1.5:
                    break
                step -= 0.25
            if max(b.shape[:2]) <= lim:
                break
            shrink += 1                     # a long piece: the copies are drawn smaller (item_post.fit, 1 px a turn)
            if shrink > 10:
                raise SystemExit('ammo bundle of %d does not fit in %d px' % (count, lim))
            import item_post as IP
            t = IP.centre(IP.fit(IP.crop(tile), 1 + shrink))
        h, w = b.shape[:2]
        t = np.zeros((N, N, 4), np.uint8)
        y0, x0 = (N - h + 1) // 2, (N - w + 1) // 2
        t[y0:y0 + h, x0:x0 + w] = b
        out.append(t)
    return out


def render(tile, kind):
    """the patterns of one piece: 8 for arrows and bolts, else the tile itself"""
    if kind in ('arrow', 'bolt'):
        return ammo_stack(tile)
    return [tile]


# ------------------------------------------------------------------------------------------------ import
PICK_FIELDS = ['key', 'tag', 'cand', 'slot', 'roll', 'box', 'by']


def import_picks(raw_dir, sets, pieces_of, log=print):
    """the strips from the raw PixelLab candidates (RAW_DIR/<tag>/cand_NN.png) and the picks CSV"""
    import item_post as IP
    picks = {r['key']: r for r in csv.DictReader(open(PICKS, newline=''))}
    os.makedirs(ITEMS_DIR, exist_ok=True)
    for s in sets:
        ps = pieces_of(s)
        tiles = []
        for key, kind, style, name, kit in ps:
            r = picks.get(key)
            if r is None:
                raise SystemExit('no pick for ' + key)
            src = os.path.join(raw_dir, r['tag'], 'cand_%02d.png' % int(r['cand']))
            roll = [int(v) for v in (r.get('roll') or '').split()] or None
            box = [int(v) for v in (r.get('box') or '').split()] or None
            tiles.append(IP.process(np.asarray(Image.open(src).convert('RGBA')), r['slot'] or 'full', roll=roll, box=box))
        Image.fromarray(np.concatenate(tiles, axis=1), 'RGBA').save(strip_path(s['key']), optimize=False)
        log('%s: %d pieces' % (s['key'], len(tiles)))
