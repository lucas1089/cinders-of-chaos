"""Item forge: 32x32 equipment icons from a parts library, learned material ramps and per-set composition rules.

Data (committed, written by item_forge_learn.py from the sprite libraries; the forge reads no library):
    item_forge_data/style.json   material ramps (3 families each), outline ink, light direction, cell fill per kind,
                                 element glow ramps (colour statistics of the spell effect set, no pixels)
    item_forge_data/parts.json   parts cut from allowed library items (item_forge_data/parts.csv names the source of
                                 every part): slot letter + level per pixel, recoloured here with new ramps
Hand-drawn ornaments (gems, sun emblems, studs, fuller inlays) are text grids in this file.

Roles of a part pixel: M main metal, S second metal or blade, T trim, F field (enamel, cloth panel), C cloth,
L wood or leather, G gem. A set theme gives each role a ramp ('gold:2' = family 2 of the learned gold, 'el:fire' =
the fire glow; family 0 = median ramp, 1 deep, 2 middle, 3 pale; 'mix:a+b@0.3' = a blended 30 % toward b). A recipe per kind places parts, ornaments and relights.

    python3 -I item_forge.py build [--theme sunsworn] --out DIR     # the set's icons (+ 1x/4x sheets)
    python3 -I item_forge.py build --check                          # rebuild in memory, compare with sums (CI)
    python3 -I item_forge.py variant IN.png [IN2.png ...] --out DIR # common/rare/epic + fire/ice/poison/void
Deterministic: no randomness; the same data gives byte-identical pixels.
"""
import argparse
import hashlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image, ImageDraw

from item_forge_learn import components, hsv, lum, material_of

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, 'item_forge_data')
SUMS = os.path.join(DATA, 'sums.txt')
STYLE = json.load(open(os.path.join(DATA, 'style.json')))
PARTS = json.load(open(os.path.join(DATA, 'parts.json')))['parts']
N = 32
LV = 6


# ------------------------------------------------------------------------------------------------ ramps
def hex2rgb(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], np.float64)


def _fix(r):
    """six distinct steps, dark to light (a glow table may repeat a colour)"""
    r = [np.asarray(c, np.float64) for c in r]
    for i in range(1, len(r)):
        if np.abs(r[i] - r[i - 1]).sum() < 6:
            j = min(i + 1, len(r) - 1)
            r[i] = (r[i - 1] + r[j]) / 2 if j != i else r[i - 1] * 0.8 + 255 * 0.2
    return np.array(r)


def ramp(spec):
    if spec.startswith('mix:'):
        a, rest = spec[4:].split('+')
        b, t = rest.split('@')
        return ramp(a) * (1 - float(t)) + ramp(b) * float(t)
    if spec.startswith('el:'):
        return _fix([hex2rgb(h) for h in STYLE['elements'][spec[3:]]])
    if spec.startswith('#'):
        return _fix([hex2rgb(h) for h in spec.split(',')])
    mat, _, fam = spec.partition(':')
    m = STYLE['materials'][mat]
    fams = [m['ramp']] + m['variants']             # 0 = median ramp, 1 deep, 2 middle, 3 pale family
    hs = fams[int(fam or 0)]
    return _fix([hex2rgb(h) for h in hs])


INK = hex2rgb(STYLE['outline']['ink'])
ang = np.radians(STYLE['light']['angle_deg'])
LIGHT = np.array([-np.cos(ang), -np.sin(ang)])   # screen direction towards the light (x right, y down)


# ------------------------------------------------------------------------------------------------ ornaments
# two characters per pixel: '..' empty, 'o.' ink, role letter + level
ORN = {
    'gem3': ['o.o.o.o.o.',
             'o.G5G4G2o.',
             'o.G4G3G1o.',
             'o.G2G1G0o.',
             'o.o.o.o.o.'],
    'gem2': ['o.o.o.o.',
             'o.G5G3o.',
             'o.G2G0o.',
             'o.o.o.o.'],
    'gemdot': ['G5G3',
               'G2G0'],
    'sun9': ['........T5........',
             '..T5....T4....T3..',
             '....T4o.o.o.T3....',
             '....o.M5M4M3o.....',
             'T5T4o.M4G4M2o.T2T1',
             '....o.M3M2M1o.....',
             '....T3o.o.o.T1....',
             '..T3....T2....T1..',
             '........T1........'],
    'sun7': ['......T5......',
             '..T4o.o.o.T3..',
             '..o.M5M4M3o...',
             'T5o.M4G4M2o.T1',
             '..o.M3M2M1o...',
             '..T3o.o.o.T1..',
             '......T1......'],
    'rays11': ['..........T5..........',
               '..T5................T3',
               '....T4............T3..',
               '......................',
               '......................',
               'T5T4................T2',
               '......................',
               '......................',
               '....T3............T1..',
               '..T3................T1',
               '..........T1..........'],
    'sun13': ['............T4............',
              '..T4........T4........T2..',
              '....T3......T3......T2....',
              '........o.o.o.o.o.........',
              '......o.M5M5M4M4M3o.......',
              '......o.M5G5G4G3M2o.......',
              'T4T4T3o.M4G4G3G1M2o.T2T1T1',
              '......o.M4G2G1G0M1o.......',
              '......o.M3M2M2M1M1o.......',
              '........o.o.o.o.o.........',
              '....T2......T2......T1....',
              '..T2........T1........T1..',
              '............T1............'],
    'stud': ['T5T3',
             'T3T1'],
}


def sun_head(r_disc=2.6, r_ray=5.2):
    """a sun disc with eight rays that touch it (one outline around both), drawn by rule"""
    n = int(2 * r_ray) + 1
    c = n // 2
    rows = []
    for y in range(n):
        row = ''
        for x in range(n):
            dx, dy = x - c, y - c
            d = (dx * dx + dy * dy) ** 0.5
            lit = -(dx * LIGHT[0] + dy * LIGHT[1]) < 0      # towards the light
            if d <= r_disc - 1.0:
                row += 'G' + str(4 if lit else 1) if d > 0.5 else 'G5'
            elif d <= r_disc:
                row += 'M' + str(5 if lit else 2)
            elif d <= r_ray and (dx == 0 or dy == 0 or abs(dx) == abs(dy)) and d > r_disc:
                k = 4 if lit else 2
                row += 'T' + str(k if d < r_ray - 1 else k - 1)
            else:
                row += '..'
        rows.append(row)
    return rows


def orn_grid(name):
    if name == 'sunhead':
        return sun_head()
    return ORN[name]


# ------------------------------------------------------------------------------------------------ canvas
class Canvas:
    def __init__(self):
        self.role = np.full((N, N), '', dtype='<U1')
        self.lev = np.zeros((N, N), np.int16)
        self.ink = np.zeros((N, N), bool)

    def paint(self, grid, dx, dy, remap=None, under=False, ink=True):
        remap = remap or {}
        for y, row in enumerate(grid):
            for x in range(0, len(row), 2):
                c = row[x:x + 2]
                X, Y = x // 2 + dx, y + dy
                if c == '..' or not (0 <= X < N and 0 <= Y < N):
                    continue
                filled = bool(self.role[Y, X]) or self.ink[Y, X]
                if c[0] == 'o':
                    if not ink:
                        continue
                    if not under:
                        self.ink[Y, X] = True
                        self.role[Y, X] = ''
                    elif not filled:
                        self.ink[Y, X] = True
                    continue
                if under and filled:
                    continue
                r = remap.get(c[0], c[0])
                self.role[Y, X] = r
                self.lev[Y, X] = int(c[1])
                self.ink[Y, X] = False

    def body(self):
        return self.role != ''


def place(cv, part, dx=0, dy=0, remap=None, under=False, flip=False):
    p = PARTS[part]
    ox, oy = (int(v) for v in p['anchor'].split())
    g = p['grid']
    if flip:
        g = [''.join(r[i:i + 2] for i in range(len(r) - 2, -1, -2)) for r in g]
    cv.paint(g, ox + dx, oy + dy, remap, under)


def ornament(cv, name, cx, cy, remap=None):
    g = orn_grid(name)
    h, w = len(g), len(g[0]) // 2
    cv.paint(g, cx - w // 2, cy - h // 2, remap)


def relight(cv, role, base, spread, bevel=True, keep=0.5):
    """re-shade one role from the learned light direction (brightest towards the light), blended with the part's
    own shading (keep = weight of the source levels), an inset bevel where the role meets another role, and a 2x2
    ordered dither only on the exact middle of a step"""
    m = cv.role == role
    if not m.any():
        return
    ys, xs = np.nonzero(m)
    px = (xs - xs.mean()) / max(1.0, xs.max() - xs.min())
    py = (ys - ys.mean()) / max(1.0, ys.max() - ys.min())
    t = px * LIGHT[0] + py * LIGHT[1]
    v = (1 - keep) * (base + spread * 2 * t) + keep * cv.lev[ys, xs]
    bayer = np.array([[0.25, 0.75], [1.0, 0.5]])
    new = []
    for (y, x), val in zip(zip(ys, xs), v):
        f = val - np.floor(val)
        lv = int(np.floor(val)) + (1 if f >= 0.56 or (f > 0.44 and bayer[y % 2, x % 2] > 0.5) else 0)
        if bevel:
            up = y > 0 and cv.role[y - 1, x] != role
            left = x > 0 and cv.role[y, x - 1] != role
            down = y < N - 1 and cv.role[y + 1, x] != role
            right = x < N - 1 and cv.role[y, x + 1] != role
            if up or left:
                lv += 1
            if down or right:
                lv -= 1
        new.append(max(0, min(LV - 1, lv)))
    cv.lev[ys, xs] = new


def absorb(cv, small, into, maxpx=20):
    """islands of one role (4-connected, at most maxpx pixels) become another role: drops a source emblem's
    specks from a field that is about to be relit"""
    seen = np.zeros((N, N), bool)
    for y, x in zip(*np.nonzero(cv.role == small)):
        if seen[y, x]:
            continue
        st, mem = [(y, x)], []
        seen[y, x] = True
        while st:
            cy, cx = st.pop()
            mem.append((cy, cx))
            for yy, xx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                if 0 <= yy < N and 0 <= xx < N and not seen[yy, xx] and cv.role[yy, xx] == small:
                    seen[yy, xx] = True
                    st.append((yy, xx))
        if len(mem) <= maxpx:
            for p in mem:
                cv.role[p] = into


def soles(cv, role, lev, rows=1):
    """the lowest body pixels of every column become a trim band (boot soles, greave hems)"""
    for x in range(N):
        ys = np.nonzero(cv.role[:, x] != '')[0]
        for y in ys[::-1][:rows]:
            cv.role[y, x] = role
            cv.lev[y, x] = lev


def line(cv, role, pts, lev):
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        n = max(abs(x1 - x0), abs(y1 - y0))
        for i in range(n + 1):
            x = round(x0 + (x1 - x0) * i / max(1, n)); y = round(y0 + (y1 - y0) * i / max(1, n))
            if cv.role[y, x]:
                cv.role[y, x] = role
                cv.lev[y, x] = lev


def render(cv, roles, rim=True):
    """outline pass + colour. Outer outline: near-black ink (learned) on the 4-neighbour ring. Inner ink pixels
    survive only as lines between body pixels and take the darkest shade of their neighbours' ramp, darkened."""
    body = cv.body()
    ink = cv.ink & ~body
    p = np.pad(body, 1)
    nb = p[:-2, 1:-1].astype(int) + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]
    inner = ink & (nb >= 2)
    solid = body | inner
    q = np.pad(solid, 1)
    ring = ~solid & (q[:-2, 1:-1] | q[2:, 1:-1] | q[1:-1, :-2] | q[1:-1, 2:])
    lev = cv.lev.copy()
    if rim:
        open_up = ~np.pad(solid, 1)[:-2, 1:-1]
        open_left = ~np.pad(solid, 1)[1:-1, :-2]
        open_down = ~np.pad(solid, 1)[2:, 1:-1]
        open_right = ~np.pad(solid, 1)[1:-1, 2:]
        lit = body & (open_up | open_left) & ~(open_down | open_right)
        shade = body & (open_down | open_right) & ~(open_up | open_left)
        lev = np.where(lit, np.minimum(lev + 1, LV - 1), lev)
        lev = np.where(shade, np.maximum(lev - 1, 0), lev)
    out = np.zeros((N, N, 4), np.uint8)
    R = {k: ramp(v) for k, v in roles.items()}
    for y, x in zip(*np.nonzero(body)):
        out[y, x, :3] = np.clip(R[cv.role[y, x]][lev[y, x]], 0, 255).round()
        out[y, x, 3] = 255
    for y, x in zip(*np.nonzero(inner)):
        rs = [cv.role[yy, xx] for yy, xx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1))
              if 0 <= yy < N and 0 <= xx < N and cv.role[yy, xx]]
        r = max(sorted(set(rs)), key=rs.count)
        out[y, x, :3] = (R[r][0] * 0.55).round()
        out[y, x, 3] = 255
    for y, x in zip(*np.nonzero(ring)):
        out[y, x, :3] = INK
        out[y, x, 3] = 255
    return out


# ------------------------------------------------------------------------------------------------ themes, recipes
THEMES = {
    'sunsworn': {
        'name': 'Sunsworn',
        'roles': {'M': 'gold:3', 'T': 'gold:2', 'S': 'steel:2', 'F': 'mix:bone:3+steel:3@0.35', 'C': 'red:1',
                  'L': 'red:0', 'G': 'ruby:3'},
        'gem': 'gem3',
        'emblem': 'sun',
    },
    'gravebound': {
        'name': 'Gravebound (second theme, same recipes)',
        'roles': {'M': 'darkiron:2', 'T': 'bone:2', 'S': 'darkiron:2', 'F': 'bone:1', 'C': 'green:0',
                  'L': 'leather:1', 'G': 'el:poison'},
        'gem': 'gem3',
        'emblem': 'sun',
    },
}
PIECES = ('sword', 'axe', 'shield', 'helmet', 'armor', 'legs', 'boots', 'rod')


def forge(theme, kind):
    th = THEMES[theme]
    roles = dict(th['roles'])
    cv = Canvas()
    if kind == 'sword':
        place(cv, 'sword_blade_broad')
        line(cv, 'T', [(5, 5), (17, 17)], 2)                       # gilded fuller, a 2 px stair
        line(cv, 'T', [(6, 5), (18, 17)], 3)
        place(cv, 'sword_hilt_winged')
        ornament(cv, 'gem3', 20, 21)
    elif kind == 'axe':
        place(cv, 'axe_head_bearded', remap={'S': 'M'})
        place(cv, 'axe_haft')
        relight(cv, 'M', 3.0, 1.4, bevel=True)
        ornament(cv, 'gem3', 14, 14)
    elif kind == 'shield':
        place(cv, 'shield_heater')
        absorb(cv, 'T', 'F', 30)
        relight(cv, 'F', 3.4, 1.0, keep=0.0)
        ornament(cv, 'sun13', 16, 15)
    elif kind == 'helmet':
        place(cv, 'helm_shell_great', dy=2, remap={'S': 'M', 'T': 'F'})
        place(cv, 'helm_crest_plume', dy=-1, under=True)
        relight(cv, 'M', 3.0, 1.2, bevel=False, keep=0.6)
        ornament(cv, 'gem3', 16, 9)
    elif kind == 'armor':
        place(cv, 'armor_cuirass_plate')
        place(cv, 'armor_skirt_cloth', under=True)
        relight(cv, 'F', 3.2, 1.2, keep=0.4)
        ornament(cv, 'sun7', 16, 21, remap={'M': 'F'})
    elif kind == 'legs':
        place(cv, 'legs_plate_greaves', remap={'S': 'F'})
        place(cv, 'legs_belt')
        relight(cv, 'F', 3.0, 1.2, bevel=False)
        ornament(cv, 'gemdot', 16, 2)
    elif kind == 'boots':
        place(cv, 'boots_plate', remap={'S': 'F'})
        relight(cv, 'F', 3.0, 1.2, bevel=False)
        soles(cv, 'T', 2, rows=2)
        line(cv, 'T', [(4, 18), (15, 18)], 3)
        line(cv, 'T', [(19, 18), (29, 18)], 3)
        place(cv, 'boots_cuff', dx=0, dy=-3)
        place(cv, 'boots_cuff', dx=-16, dy=-3)
        ornament(cv, 'gemdot', 10, 6)
        ornament(cv, 'gemdot', 25, 6)
    elif kind == 'rod':
        place(cv, 'rod_sceptre_ring', remap={'L': 'F'})
        relight(cv, 'F', 3.0, 1.0, bevel=False)
        ornament(cv, 'sunhead', 16, 6)
    else:
        raise KeyError(kind)
    return render(cv, roles)


# ------------------------------------------------------------------------------------------------ variants
TIERS = {
    'common': {'M': 'gold:1', 'S': 'steel:1', 'C': 'leather:1', 'L': 'wood:1', 'G': None, 'add_gem': None,
               'glint': 0},
    'rare': {'M': 'gold:2', 'S': 'steel:2', 'C': 'blue:2', 'L': 'leather:2', 'G': 'sapphire:3', 'add_gem': 'sapphire:3',
             'glint': 0},
    'epic': {'M': 'gold:3', 'S': 'mix:steel:3+purple:3@0.18', 'C': 'purple:2', 'L': 'leather:2', 'G': 'amethyst:3',
             'add_gem': 'amethyst:3', 'glint': 2},
}
ELEMENTS = {
    'fire': {'M': 'mix:gold:1+el:fire@0.25', 'S': 'mix:steel:1+el:fire@0.22', 'C': 'el:fire', 'L': 'leather:1',
             'G': 'el:fire', 'vein': 'el:fire', 'add_gem': 'el:fire'},
    'ice': {'M': 'mix:steel:3+el:ice@0.35', 'S': 'mix:steel:3+el:ice@0.25', 'C': 'el:ice', 'L': 'mix:steel:1+el:ice@0.3',
            'G': 'el:ice', 'vein': 'el:ice', 'add_gem': 'el:ice'},
    'poison': {'M': 'mix:gold:1+el:poison@0.3', 'S': 'mix:steel:1+el:poison@0.2', 'C': 'el:poison',
               'L': 'leather:1', 'G': 'el:poison', 'vein': 'el:poison', 'add_gem': 'el:poison'},
    'void': {'M': 'mix:darkiron:2+el:void@0.35', 'S': 'mix:darkiron:2+el:void@0.25', 'C': 'el:void',
             'L': 'darkiron:1', 'G': 'el:void', 'vein': 'el:void', 'add_gem': 'el:void'},
}
ROLE_OF = {'gold': 'M', 'steel': 'S', 'darkiron': 'S', 'bone': 'S', 'wood': 'L', 'leather': 'L', 'red': 'C',
           'blue': 'C', 'green': 'C', 'purple': 'C', 'crystal': 'C', 'ruby': 'G', 'sapphire': 'G', 'emerald': 'G',
           'amethyst': 'G'}


def analyse(img):
    """per pixel: role, level (nearest step of the learned ramp of its material), ink and inner-line flags"""
    a = img[..., 3] > 0
    rgb = img[..., :3].astype(np.float64)
    L = lum(rgb)
    role = np.full((N, N), '', dtype='<U1')
    lev = np.zeros((N, N), np.int16)
    mats = {}
    for mem in components(img):
        cs = np.array([rgb[p] for p in mem])
        o = np.argsort(lum(cs), kind='stable')
        top = cs[o[int(len(o) * 0.8)]]
        mat = material_of(tuple(top), None, len(mem))
        if mat == 'ink':
            continue
        r = ROLE_OF.get(mat, 'S')
        if r == 'C' and mat == 'crystal' and len(mem) <= 14:
            r = 'G'
        ref = [float(lum(hex2rgb(h))) for h in STYLE['materials'].get(mat, STYLE['materials']['steel'])['ramp']]
        for y, x in mem:
            role[y, x] = r
            lev[y, x] = int(np.argmin([abs(L[y, x] - v) for v in ref]))
        mats[mat] = mats.get(mat, 0) + len(mem)
    ink = a & (role == '')
    return role, lev, ink, mats


def variant(img, spec, base_roles=None):
    """recolour one item by roles; adds a gem where the tier or element asks for one and the item has none, glints
    for epic, glowing veins on inner lines for elements. Alpha (the silhouette) never changes."""
    role, lev, ink, mats = analyse(img)
    rgb = img[..., :3].astype(np.float64).copy()
    out = img.copy()
    roles = dict(spec)
    G = roles.get('G')
    body = role != ''
    if G is None:                                   # common: gems become plain metal
        mr = 'S' if (role == 'S').sum() >= (role == 'M').sum() else 'M'
        role = np.where(role == 'G', mr, role)
    add = roles.get('add_gem')
    if add and not (role == 'G').any():
        # deepest 3x3 spot of the biggest metal role, away from the outline
        mr = 'M' if (role == 'M').sum() >= (role == 'S').sum() else 'S'
        m = role == mr
        best = None
        ys, xs = np.nonzero(m)
        cy, cx = ys.mean(), xs.mean()
        for y in range(2, N - 2):
            for x in range(2, N - 2):
                if m[y - 2:y + 3, x - 2:x + 3].all():
                    d = (y - cy) ** 2 + (x - cx) ** 2
                    if best is None or d < best[0]:
                        best = (d, y, x)
        if best:
            _, y, x = best
            gem = orn_grid('gem3')
            for j, row in enumerate(gem):
                for i in range(0, len(row), 2):
                    c = row[i:i + 2]
                    Y, X = y - 2 + j, x - 2 + i // 2
                    if c[0] == 'o':
                        role[Y, X] = 'K'
                    else:
                        role[Y, X] = 'G'
                        lev[Y, X] = int(c[1])
            G = add
    R = {k: ramp(v) for k, v in roles.items() if k in 'MSCLG' and v}
    if 'G' not in R and G:
        R['G'] = ramp(G)
    for y, x in zip(*np.nonzero(body | (role == 'K'))):
        r = role[y, x]
        if r == 'K':
            out[y, x, :3] = (R[mr][0] * 0.45).round()
            continue
        out[y, x, :3] = np.clip(R[r][lev[y, x]], 0, 255).round()
    vein = roles.get('vein')
    if vein:            # enchanted creases: inner ink lines and the deepest metal shade inside the body glow
        V = ramp(vein)
        p = np.pad(body | ink, 1)
        nb = p[:-2, 1:-1].astype(int) + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]
        q = np.pad(body, 1)
        nbb = q[:-2, 1:-1].astype(int) + q[2:, 1:-1] + q[1:-1, :-2] + q[1:-1, 2:]
        crease = (ink & (nb == 4) & (nbb >= 2)) | (np.isin(role, ['M', 'S']) & (lev == 0) & (nb == 4))
        for i, (y, x) in enumerate(zip(*np.nonzero(crease))):
            out[y, x, :3] = V[3 if (y + x) % 3 else 4].round()
    for _ in range(roles.get('glint', 0)):
        metal = np.isin(role, ['M', 'S']) & (lev >= 4)
        ys, xs = np.nonzero(metal)
        if not len(ys):
            break
        score = -(xs * LIGHT[0] + ys * LIGHT[1]) * -1
        order = np.lexsort((xs, ys, -score))
        for i in order:
            y, x = ys[i], xs[i]
            if (out[max(0, y - 2):y + 3, max(0, x - 2):x + 3, 0] == 255).all() is False or True:
                if (out[y, x, :3] == 255).all():
                    continue
                out[y, x, :3] = 255
                for yy, xx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                    if 0 <= yy < N and 0 <= xx < N and body[yy, xx]:
                        out[yy, xx, :3] = np.minimum(255, out[yy, xx, :3].astype(int) + 70)
                lev[max(0, y - 3):y + 4, max(0, x - 3):x + 4] = 0
                break
    assert ((out[..., 3] > 0) == (img[..., 3] > 0)).all()
    return out


def variant_set(img):
    res = {}
    for t, spec in TIERS.items():
        res[t] = variant(img, spec)
    for e, spec in ELEMENTS.items():
        res[e] = variant(img, spec)
    return res


# ------------------------------------------------------------------------------------------------ sheets, check
def slot_tile():
    s = Image.new('RGBA', (36, 36), (20, 18, 18, 255)); d = ImageDraw.Draw(s)
    d.line([(0, 0), (35, 0)], fill=(10, 9, 9)); d.line([(0, 0), (0, 35)], fill=(10, 9, 9))
    d.line([(0, 35), (35, 35)], fill=(70, 62, 54)); d.line([(35, 0), (35, 35)], fill=(70, 62, 54))
    d.rectangle([1, 1, 34, 34], fill=(44, 40, 38))
    return s


def strip(imgs, z=1):
    W = 3 + 38 * len(imgs)
    pan = Image.new('RGBA', (W, 42), (36, 32, 30, 255))
    for i, a in enumerate(imgs):
        pan.alpha_composite(slot_tile(), (3 + i * 38, 3))
        pan.alpha_composite(Image.fromarray(a, 'RGBA'), (5 + i * 38, 5))
    return pan.resize((pan.width * z, pan.height * z), Image.NEAREST)


def build_all():
    out = {}
    for th in THEMES:
        for k in PIECES:
            out[f'{th}_{k}'] = forge(th, k)
    return out


def sums_of(items):
    return {k: hashlib.sha256(v.tobytes()).hexdigest()[:16] for k, v in sorted(items.items())}


def margin_report(items):
    rep = []
    for k, a in sorted(items.items()):
        ys, xs = np.nonzero(a[..., 3])
        rep.append(f'{k}: bbox {xs.min()}..{xs.max()} x {ys.min()}..{ys.max()}, cover {a[..., 3].astype(bool).mean():.2f}')
    return rep


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=('build', 'variant'))
    ap.add_argument('inputs', nargs='*')
    ap.add_argument('--theme')
    ap.add_argument('--out')
    ap.add_argument('--check', action='store_true')
    a = ap.parse_args()
    if a.cmd == 'build':
        items = build_all()
        sums = sums_of(items)
        text = ''.join(f'{k} {v}\n' for k, v in sums.items())
        if a.check:
            if not os.path.exists(SUMS) or open(SUMS).read() != text:
                sys.exit('item_forge: output differs from item_forge_data/sums.txt')
            print(f'item_forge: {len(items)} icons match sums.txt')
            return
        open(SUMS, 'w').write(text)
        if a.out:
            os.makedirs(a.out, exist_ok=True)
            for k, v in items.items():
                if a.theme and not k.startswith(a.theme):
                    continue
                Image.fromarray(v, 'RGBA').save(os.path.join(a.out, k + '.png'))
            for th in THEMES:
                if a.theme and th != a.theme:
                    continue
                ims = [items[f'{th}_{k}'] for k in PIECES]
                strip(ims, 1).save(os.path.join(a.out, f'{th}_1x.png'))
                strip(ims, 4).save(os.path.join(a.out, f'{th}_4x.png'))
        print('\n'.join(margin_report(items)))
    else:
        os.makedirs(a.out, exist_ok=True)
        for p in a.inputs:
            img = np.asarray(Image.open(p).convert('RGBA')).copy()
            img[img[..., 3] < 128] = 0
            img[..., 3] = np.where(img[..., 3] > 0, 255, 0)
            vs = variant_set(img)
            base = os.path.splitext(os.path.basename(p))[0]
            for k, v in vs.items():
                Image.fromarray(v, 'RGBA').save(os.path.join(a.out, f'{base}_{k}.png'))
            strip([img] + list(vs.values()), 4).save(os.path.join(a.out, f'{base}_variants_4x.png'))


if __name__ == '__main__':
    main()
