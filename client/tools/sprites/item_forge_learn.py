"""Learn the item style tables and cut the parts library for item_forge.py from the sprite libraries we hold.

The forge never reads a library at run time. This script reads them once and writes two data files that are committed:
    item_forge_data/style.json   material ramps, outline and light rules, cell fill per kind, element glow ramps
    item_forge_data/parts.json   part grids cut from allowed library items (item_forge_data/parts.csv says which)

Sources (all read-only, none of them in git):
    --pair DIR       the live pair (stock and Chaos items; things_custom23)
    --library DIR    a donor library folder (Tibia.dat, Tibia.spr, catalogue.csv), repeatable
    --vfx DIR        the spell effect set: ONLY colour statistics are read from it (its licence forbids shipping its
                     pixels in a generator or training a model on it). A few ramp colours per element are stored, no
                     frame, cut or pixel pattern.
Never read: the owner's reference sheets (scratchpad/purchased_weto/) and the oblique pack-effect cuts.

Labels: the market category of the dat (armour 1, boots 3, helmet 7, legs 8, shield 13, axe 17, club 18, sword 20,
wand/rod 21), else the cloth slot, else a nearest-neighbour vote on the 16x16 silhouette against the labelled items
(7 neighbours, 6 must agree). Rows tagged "named character" or "branded" in a catalogue are skipped. Rows tagged
"library only" (retail-style, commercial server art) count for statistics but never give parts.

    python3 -I item_forge_learn.py style --pair P --library L1 --library L2 ... --vfx V   # write style.json
    python3 -I item_forge_learn.py parts --pair P --library L1 ...                         # write parts.json
    python3 -I item_forge_learn.py style ... --check / parts ... --check    # rebuild in memory, compare
    python3 -I item_forge_learn.py check        # without the libraries (CI): both files parse, digests match
    python3 -I item_forge_learn.py sheet --pair P --library L ... --out DIR   # contact sheets per kind (for picking)
"""
import argparse
import colorsys
import csv
import hashlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, 'item_forge_data')
STYLE = os.path.join(DATA, 'style.json')
PARTS_CSV = os.path.join(DATA, 'parts.csv')
PARTS = os.path.join(DATA, 'parts.json')

KINDS = ('sword', 'axe', 'club', 'rod', 'shield', 'helmet', 'armor', 'legs', 'boots')
MARKET = {20: 'sword', 17: 'axe', 18: 'club', 21: 'rod', 13: 'shield', 7: 'helmet', 1: 'armor', 8: 'legs', 3: 'boots'}
CLOTH = {1: 'helmet', 4: 'armor', 7: 'legs', 8: 'feet'}
SKIP_TAGS = ('named character', 'branded')
LIB_ONLY_TAGS = ('library only',)
EXCLUDED_DIRS = ('purchased_weto',)
LEVELS = 6
WEAPONS = ('sword', 'axe', 'club', 'rod')

# element -> effect ids of the spell effect set whose colours describe it (colour statistics only)
VFX_ELEMENTS = {
    'fire': ('ember_crown', 'fire_explosion', 'fireball', 'fireball_hit', 'burning', 'infernal_seal', 'meteor_strike'),
    'ice': ('frost_bastion', 'frost_glyph', 'frost_nova', 'ice_lance', 'ice_shatter', 'frozen'),
    'lightning': ('storm_mantle', 'storm_ring', 'lightning_strike', 'lightning_orb', 'lightning_hit'),
    'poison': ('plague_mist', 'toxic_burst', 'venom_glob', 'venom_splash', 'poisoned'),
    'holy': ('dawn_aegis', 'holy_seal', 'holy_smite', 'holy_spear', 'holy_hit'),
    'void': ('void_rift', 'void_maw', 'shadow_shroud', 'shadow_eruption', 'shadow_orb', 'shadow_hit'),
    'blood': ('blood_pact', 'bleeding'),
}


# ------------------------------------------------------------------------------------------------ colour helpers
def lum(rgb):
    rgb = np.asarray(rgb, np.float64)
    return rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114


def hsv(rgb):
    r, g, b = (float(c) / 255.0 for c in rgb[:3])
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    return h * 360.0, s, v


def material_of(rgb, kind=None, cluster_px=99):
    """The material class of one colour (rules on hue, saturation, value). kind and cluster size split
    wood/leather and gems from cloth."""
    h, s, v = hsv(rgb)
    if v < 0.10:
        return 'ink'
    if s < 0.16 or (s < 0.24 and v < 0.30) or (185 <= h <= 260 and s < 0.34):   # blue-grey steel too
        if 25 <= h <= 65 and s >= 0.09 and v >= 0.55:
            return 'bone'
        return 'steel' if v >= 0.42 else 'darkiron'
    if 25 <= h <= 65 and s < 0.38 and v >= 0.55:
        return 'bone'
    gem = cluster_px <= 14 and s >= 0.5 and v >= 0.45
    if 36 <= h < 66:
        return 'gold' if v >= 0.35 else ('wood' if kind in WEAPONS else 'leather')
    if 14 <= h < 36:
        if s >= 0.55 and v >= 0.62:
            return 'gold'
        return 'wood' if kind in WEAPONS else 'leather'
    if h < 14 or h >= 335:
        return 'ruby' if gem else 'red'
    if 66 <= h < 165:
        return 'emerald' if gem else 'green'
    if 165 <= h < 200:
        return 'crystal'
    if 200 <= h < 255:
        return 'sapphire' if gem else 'blue'
    return 'amethyst' if gem else 'purple'


MATERIALS = ('gold', 'steel', 'darkiron', 'bone', 'wood', 'leather', 'red', 'blue', 'green', 'purple', 'crystal',
             'ruby', 'sapphire', 'emerald', 'amethyst')


def hexc(rgb):
    return '#%02x%02x%02x' % tuple(int(round(c)) for c in rgb[:3])


# ------------------------------------------------------------------------------------------------ sources
class Source:
    def __init__(self, name, path, live):
        from datspr import Dat, Spr
        self.name, self.path, self.live = name, path, live
        self.dat = Dat(os.path.join(path, 'Tibia.dat'))
        self.spr = Spr(os.path.join(path, 'Tibia.spr'))
        self.rows = {}
        cat = os.path.join(path, 'catalogue.csv')
        if os.path.exists(cat):
            for r in csv.DictReader(open(cat, newline='')):
                if r['category'] == 'item':
                    self.rows[int(r['lib_id'])] = r
        self.md5 = md5_file(os.path.join(path, 'Tibia.dat'))

    def item(self, iid):
        t = self.dat.items[iid - 100]
        return t

    def image(self, iid):
        """first frame, layer 0, pattern 0 of a 1x1 item as uint8 HxWx4, or None"""
        t = self.item(iid)
        if t.w != 1 or t.h != 1:
            return None
        a = self.spr.sprite(t.sprites[0])
        return None if a is None else a.copy()

    def tags(self, iid):
        r = self.rows.get(iid)
        return r['description'] if r else ''

    def usable(self, iid):
        d = self.tags(iid)
        return not any(k in d for k in SKIP_TAGS)

    def parts_ok(self, iid):
        d = self.tags(iid)
        return self.usable(iid) and not any(k in d for k in LIB_ONLY_TAGS)


def md5_file(p):
    h = hashlib.md5()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def open_sources(args):
    out = []
    for p in args.pair or []:
        out.append(Source('live', p, True))
    for p in args.library or []:
        if any(x in p for x in EXCLUDED_DIRS):
            sys.exit(f'{p}: excluded source (owner reference sheets)')
        out.append(Source(os.path.basename(os.path.normpath(p)), p, False))
    return out


def label_of(src, t):
    m = t.flags.get('market')
    if m and m[0] in MARKET:
        return MARKET[m[0]], 'market'
    if m and m[0]:
        return 'other', 'market'
    c = t.flags.get('cloth')
    if c in (1, 4, 7, 8):
        return {1: 'helmet', 4: 'armor', 7: 'legs', 8: 'boots'}[c], 'cloth'
    if c in (2, 3, 9, 10):
        return 'other', 'cloth'
    return None, None


def candidate(src, t):
    """1x1, not ground, not a border, something one could carry"""
    if t.w != 1 or t.h != 1:
        return False
    f = t.flags
    if any(k in f for k in ('ground', 'clip', 'bottom', 'top', 'fullground', 'notmoveable', 'container')):
        return False
    d = src.tags(t.id)
    if f.get('pickupable') or 'pickup' in d:
        return True
    return not f and 'pickup' not in d and src.name in ('donorE', 'donorM')


def feat(img):
    a = (img[..., 3] > 0).astype(np.float32)
    small = a.reshape(16, 2, 16, 2).mean(axis=(1, 3)).ravel()
    n = np.linalg.norm(small)
    return small / n if n else small


def collect(sources):
    """(source, id, image, kind, how, parts_ok) for every usable carried 1x1 item with art"""
    lab, unl = [], []
    for src in sources:
        for t in src.dat.items:
            if not candidate(src, t) or not src.usable(t.id):
                continue
            img = src.image(t.id)
            if img is None:
                continue
            a = img[..., 3] > 0
            if a.sum() < 12 or a.mean() > 0.78:
                continue
            k, how = label_of(src, t)
            rec = [src, t.id, img, k, how, src.parts_ok(t.id)]
            (lab if k else unl).append(rec)
    if lab and unl:
        X = np.stack([feat(r[2]) for r in lab])
        y = np.array([r[3] for r in lab])
        for i0 in range(0, len(unl), 2000):
            chunk = unl[i0:i0 + 2000]
            Q = np.stack([feat(r[2]) for r in chunk])
            sim = Q @ X.T
            idx = np.argsort(-sim, axis=1, kind='stable')[:, :7]
            for r, row in zip(chunk, idx):
                ks, cnt = np.unique(y[row], return_counts=True)
                j = int(np.argmax(cnt))
                if cnt[j] >= 6 and ks[j] in KINDS:
                    r[3], r[4] = str(ks[j]), 'knn'
    return [r for r in lab + unl if r[3] in KINDS]


# ------------------------------------------------------------------------------------------------ measurements
def boundary(a):
    p = np.pad(a, 1)
    n4 = [p[:-2, 1:-1], p[2:, 1:-1], p[1:-1, :-2], p[1:-1, 2:]]
    edge = a & ~(n4[0] & n4[1] & n4[2] & n4[3])
    lit = a & (~n4[0] | ~n4[2])        # open towards up or left
    shade = a & (~n4[1] | ~n4[3])      # open towards down or right
    return edge, lit & ~shade, shade & ~lit


def measure(img, kind):
    a = img[..., 3] > 0
    rgb = img[..., :3].astype(np.float64)
    L = lum(rgb)
    ys, xs = np.nonzero(a)
    edge, lit, shade = boundary(a)
    inner = a & ~edge
    m = {}
    m['w'] = int(xs.max() - xs.min() + 1)
    m['h'] = int(ys.max() - ys.min() + 1)
    m['cover'] = float(a.mean())
    m['margin'] = int(min(xs.min(), ys.min(), 31 - xs.max(), 31 - ys.max()))
    d = xs - ys
    m['diag'] = float((d.max() - d.min()) / np.sqrt(2))
    m['edge_l'] = float(np.median(L[edge]))
    m['edge_dark'] = float((L[edge] < 64).mean())
    m['lit_l'] = float(L[lit].mean()) if lit.any() else m['edge_l']
    m['shade_l'] = float(L[shade].mean()) if shade.any() else m['edge_l']
    ring = a & ~edge
    _, lit2, shade2 = boundary(ring)
    m['rim_lit'] = float(L[lit2].mean()) if lit2.any() else 0.0
    m['rim_shade'] = float(L[shade2].mean()) if shade2.any() else 0.0
    dark = edge & (L < 64)
    m['ink'] = rgb[dark].mean(axis=0).tolist() if dark.any() else None
    if inner.sum() >= 8:
        p = np.pad(L, 1, mode='edge')
        nb = np.stack([p[1 + dy:33 + dy, 1 + dx:33 + dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx])
        m['inner_line'] = float((L[inner] < 0.55 * np.median(nb, axis=0)[inner]).mean())
        iy, ix = np.nonzero(inner)
        A = np.stack([ix - ix.mean(), iy - iy.mean(), np.ones_like(ix, dtype=np.float64)], 1)
        g, *_ = np.linalg.lstsq(A, L[inner], rcond=None)
        m['grad'] = [float(g[0]), float(g[1])]
    return m


def components(img):
    """4-connected runs of compatible colours inside the outline: both grey, or both coloured with close hue.
    Returns a list of pixel lists (y, x)."""
    a = img[..., 3] > 0
    edge, _, _ = boundary(a)
    rgb = img[..., :3]
    H = np.zeros((32, 32)); Sa = np.zeros((32, 32)); V = np.zeros((32, 32))
    for y, x in zip(*np.nonzero(a)):
        H[y, x], Sa[y, x], V[y, x] = hsv(rgb[y, x])
    L = lum(rgb.astype(np.float64))
    body = a & ~(edge & (L < 34)) & (L >= 22)
    grey = (Sa < 0.16) | ((Sa < 0.24) & (V < 0.30))
    seen = np.zeros((32, 32), bool)
    out = []
    for y, x in zip(*np.nonzero(body)):
        if seen[y, x]:
            continue
        seen[y, x] = True
        st, mem = [(y, x)], []
        while st:
            cy, cx = st.pop()
            mem.append((cy, cx))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                yy, xx = cy + dy, cx + dx
                if 0 <= yy < 32 and 0 <= xx < 32 and body[yy, xx] and not seen[yy, xx]:
                    if grey[cy, cx] != grey[yy, xx]:
                        continue
                    if not grey[yy, xx]:
                        dh = abs(H[cy, cx] - H[yy, xx])
                        if min(dh, 360 - dh) > 14:
                            continue
                    seen[yy, xx] = True
                    st.append((yy, xx))
        out.append(mem)
    return out


def ramps_of(img, kind):
    """material -> list of 6-colour ramps (dark to light) found on one item"""
    rgb = img[..., :3].astype(np.float64)
    out = {}
    for mem in components(img):
        if len(mem) < 3:
            continue
        cs = np.array([rgb[p] for p in mem])
        L = lum(cs)
        o = np.argsort(L, kind='stable')
        cs, L = cs[o], L[o]
        if L[-1] - L[0] < 25:
            continue
        top = cs[int(len(cs) * 0.8)]
        mat = material_of(tuple(top), kind, len(mem))
        if mat == 'ink':
            continue
        if len(mem) < 8 and mat not in ('ruby', 'sapphire', 'emerald', 'amethyst', 'crystal'):
            continue
        q = np.quantile(L, [0.03, 0.2, 0.4, 0.6, 0.8, 0.97])
        ramp = []
        for qq in q:
            near = np.abs(L - qq) <= max(4.0, 0.06 * (L[-1] - L[0] + 1))
            ramp.append(np.median(cs[near], axis=0) if near.any() else cs[np.argmin(np.abs(L - qq))])
        out.setdefault(mat, []).append((np.array(ramp), len(mem)))
    return out


# ------------------------------------------------------------------------------------------------ style
def build_style(sources, vfx):
    items = collect(sources)
    per_kind = {k: [] for k in KINDS}
    ramps = {m: [] for m in MATERIALS}
    counts = {}
    seen_ramps = set()
    for src, iid, img, kind, how, pok in items:
        per_kind[kind].append(measure(img, kind))
        counts.setdefault(src.name, {}).setdefault(kind, 0)
        counts[src.name][kind] += 1
        counts.setdefault('_how', {}).setdefault(how, 0)
        counts['_how'][how] += 1
        for mat, lst in ramps_of(img, kind).items():
            for r, n in lst:
                key = (mat, tuple((r // 8).astype(int).ravel()))
                if mat in ramps and key not in seen_ramps:      # recoloured copies count once
                    seen_ramps.add(key)
                    ramps[mat].append((r, n))
    style = {'about': 'learned by item_forge_learn.py from the sprite libraries; do not edit by hand',
             'sources': [{'name': s.name, 'dat_md5': s.md5} for s in sources],
             'counts': counts, 'kinds': {}, 'materials': {}, 'outline': {}, 'light': {}}
    allm = []
    for k, ms in per_kind.items():
        if not ms:
            continue
        allm += ms
        f = lambda key, q: round(float(np.quantile([m[key] for m in ms], q)), 2)
        style['kinds'][k] = {
            'n': len(ms),
            'w': [f('w', .1), f('w', .5), f('w', .9)], 'h': [f('h', .1), f('h', .5), f('h', .9)],
            'cover': [f('cover', .1), f('cover', .5), f('cover', .9)],
            'diag': [f('diag', .1), f('diag', .5), f('diag', .9)],
            'margin': [f('margin', .1), f('margin', .5), f('margin', .9)],
            'edge_dark': f('edge_dark', .5), 'edge_l': f('edge_l', .5),
            'lit_l': f('lit_l', .5), 'shade_l': f('shade_l', .5),
            'rim_lit': f('rim_lit', .5), 'rim_shade': f('rim_shade', .5),
        }
    inks = np.array([m['ink'] for m in allm if m.get('ink')])
    il = [m['inner_line'] for m in allm if 'inner_line' in m]
    gr = np.array([m['grad'] for m in allm if 'grad' in m])
    style['outline'] = {
        'ink': hexc(np.median(inks, axis=0)), 'ink_p25': hexc(np.quantile(inks, 0.25, axis=0)),
        'ink_p75': hexc(np.quantile(inks, 0.75, axis=0)),
        'edge_dark': round(float(np.median([m['edge_dark'] for m in allm])), 3),
        'lit_minus_shade': round(float(np.median([m['lit_l'] - m['shade_l'] for m in allm])), 2),
        'rim_lit_minus_shade': round(float(np.median([m['rim_lit'] - m['rim_shade'] for m in allm])), 2),
        'inner_line': round(float(np.median(il)), 3),
    }
    ang = np.degrees(np.arctan2(-gr[:, 1], -gr[:, 0]))
    style['light'] = {
        'from_left': round(float((gr[:, 0] < 0).mean()), 3), 'from_top': round(float((gr[:, 1] < 0).mean()), 3),
        'angle_deg': round(float(np.median(ang)), 1),
        'about': 'angle of the brightening direction, 0 = from the right, 90 = from above, 135 = from the upper left'}
    for mat, rs in ramps.items():
        if len(rs) < 5:
            continue
        R = np.stack([r for r, n in rs])
        W = np.array([n for r, n in rs], np.float64)
        med = []
        for i in range(LEVELS):
            med.append([weighted_median(R[:, i, c], W) for c in range(3)])
        med = np.array(med)
        # keep the ramp ordered dark -> light
        med = med[np.argsort(lum(med), kind='stable')]
        style['materials'][mat] = {'n_items': len(rs), 'ramp': [hexc(c) for c in med],
                                   'variants': [[hexc(c) for c in v] for v in ramp_variants(R, W)]}
    if vfx:
        style['elements'] = vfx_ramps(vfx)
    style['digest'] = digest(style)
    return style


def ramp_variants(R, W, k=3, iters=12):
    """k ramp families of one material (deep, middle, pale), k-means on the ramps, seeded by mean luminance"""
    X = R.reshape(len(R), -1)
    ml = lum(R).mean(axis=1)
    o = np.argsort(ml, kind='stable')
    C = np.stack([X[o[int((i + 0.5) * len(o) / k)]] for i in range(k)])
    for _ in range(iters):
        d = ((X[:, None, :] - C[None]) ** 2).sum(-1)
        lab = d.argmin(1)
        for i in range(k):
            if (lab == i).any():
                C[i] = (X[lab == i] * W[lab == i, None]).sum(0) / W[lab == i].sum()
    C = C.reshape(k, LEVELS, 3)
    C = C[np.argsort(lum(C).mean(axis=1), kind='stable')]
    return [c[np.argsort(lum(c), kind='stable')] for c in C]


def weighted_median(v, w):
    o = np.argsort(v, kind='stable')
    c = np.cumsum(w[o])
    return float(v[o][np.searchsorted(c, c[-1] / 2.0)])


def vfx_ramps(root):
    """per element: 6 glow colours (dark to light) = luminance-binned medians of the opaque pixels of its effects.
    Only these numbers are kept."""
    meta = json.load(open(os.path.join(root, 'metadata.json')))
    files = {}
    for e in meta['effects']:
        v = e['variants'].get('oblique/32')
        if v:
            files[e['id']] = os.path.join(root, v['files']['all'])
    out = {'about': 'colour statistics of the spell effect set (its licence allows use in our game, not shipping its '
                    'pixels in a generator or training on it): six luminance-binned median colours per element; no '
                    'frame, cut or pattern of the set is stored'}
    for el, ids in VFX_ELEMENTS.items():
        px = []
        for i in ids:
            if i in files:
                a = np.asarray(Image.open(files[i]).convert('RGBA'))
                m = a[..., 3] >= 200
                px.append(a[m][:, :3])
        if not px:
            continue
        P = np.concatenate(px).astype(np.float64)[::7]
        P = P[lum(P) >= 30]                       # glow, not the dark smoke and shadow under it
        h = np.array([hsv(c)[1] for c in P])
        P = P[h > 0.25] if (h > 0.25).sum() > 200 else P
        L = lum(P)
        q = np.quantile(L, np.linspace(0.04, 0.985, LEVELS))
        ramp = []
        for qq in q:
            near = np.abs(L - qq) <= 6
            ramp.append(np.median(P[near], axis=0) if near.any() else P[np.argmin(np.abs(L - qq))])
        out[el] = [hexc(c) for c in ramp]
    return out


def digest(d):
    body = {k: v for k, v in d.items() if k != 'digest'}
    return hashlib.sha256(json.dumps(body, sort_keys=True, separators=(',', ':')).encode()).hexdigest()[:16]


def dump(d):
    return json.dumps(d, indent=1, sort_keys=True) + '\n'


# ------------------------------------------------------------------------------------------------ parts
# A part is cut from an allowed item: rectangle, optional pixel keep rule, a mirror for symmetric halves. Each pixel
# becomes slot+level: slot = the material role in the source (mapped through the CSV's slot map), level = nearest
# step (0..5) of the learned ramp of the source material, 'o' = outline. The forge recolours slots with new ramps.
def material_map(img, kind):
    """material per pixel, decided per colour component (its upper colours), so a blue-grey blade stays steel
    and the dark steps of gold stay gold"""
    mm = np.full((32, 32), 'ink', dtype='<U8')
    rgb = img[..., :3].astype(np.float64)
    for mem in components(img):
        cs = np.array([rgb[p] for p in mem])
        o = np.argsort(lum(cs), kind='stable')
        mat = material_of(tuple(cs[o[int(len(o) * 0.8)]]), kind, len(mem))
        for p in mem:
            mm[p] = mat
    return mm


def cut_part(img, row, style, kind):
    x0, y0, x1, y1 = (int(v) for v in row['rect'].split())
    sub = img[y0:y1 + 1, x0:x1 + 1].copy()
    mm = material_map(img, kind)[y0:y1 + 1, x0:x1 + 1]
    keep = row.get('keep', '').strip()
    a = sub[..., 3] > 0
    if keep.startswith('mats:'):
        allow = set(keep[5:].split('+'))
        for y, x in zip(*np.nonzero(a)):
            if mm[y, x] not in allow and lum(sub[y, x, :3]) >= 34:
                a[y, x] = False
    if keep:
        L0 = lum(sub[..., :3].astype(np.float64))
        body = a & (L0 >= 34)
        p = np.pad(body, 1)
        touch = p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
        a &= body | touch
    for tok in row.get('erase', '').split():
        ex, ey = (int(v) for v in tok.split(','))
        if y0 <= ey <= y1 and x0 <= ex <= x1:
            a[ey - y0, ex - x0] = False
    slots = {}
    for tok in row['slots'].split():
        k, v = tok.split('=')
        slots[k] = v
    mats = style['materials']
    rows = []
    for y in range(sub.shape[0]):
        line = ''
        for x in range(sub.shape[1]):
            if not a[y, x]:
                line += '..'
                continue
            c = tuple(int(v) for v in sub[y, x, :3])
            L = float(lum(c))
            mat = mm[y, x]
            if L < 34 or mat == 'ink':
                line += 'o.'
                continue
            slot = slots.get(mat, slots.get('*', 'A'))
            ref = mats.get(mat) or mats['steel']
            rl = [float(lum(hex2rgb(h))) for h in ref['ramp']]
            lev = int(np.argmin([abs(L - v) for v in rl]))
            line += slot + str(lev)
        rows.append(line)
    if row.get('mirror') in ('x', 'x1'):    # left half given: x mirrors all columns, x1 shares the last one
        skip = 2 if row['mirror'] == 'x1' else 0
        rows = [r + ''.join(r[i:i + 2] for i in range(len(r) - 2 - skip, -1, -2)) for r in rows]
    return rows


def hex2rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def build_parts(sources, style):
    by = {s.name: s for s in sources}
    out = {'about': 'cut by item_forge_learn.py from item_forge_data/parts.csv; slot letter + level 0..5, o = outline',
           'parts': {}}
    for row in csv.DictReader(open(PARTS_CSV, newline='')):
        if row['part'].startswith('#'):
            continue
        src = by.get(row['source'])
        if src is None:
            sys.exit(f"part {row['part']}: source {row['source']} not given")
        iid = int(row['id'])
        if not src.parts_ok(iid):
            sys.exit(f"part {row['part']}: {row['source']} {iid} is library only or excluded")
        img = src.image(iid)
        if img is None:
            sys.exit(f"part {row['part']}: {row['source']} {iid} has no 1x1 art")
        t = src.item(iid)
        kind, _ = label_of(src, t)
        grid = cut_part(img, row, style, kind or row['kind'])
        out['parts'][row['part']] = {'kind': row['kind'], 'source': row['source'], 'id': iid,
                                     'anchor': row['anchor'], 'grid': grid}
    out['digest'] = digest(out)
    return out


# ------------------------------------------------------------------------------------------------ sheets
def sheets(sources, out_dir, per=120):
    os.makedirs(out_dir, exist_ok=True)
    items = collect(sources)
    for kind in KINDS:
        sel = [r for r in items if r[3] == kind and r[5]][:per * 4]
        for page in range(0, len(sel), per):
            chunk = sel[page:page + per]
            cols = 12
            z = 3
            im = Image.new('RGBA', (cols * 34 * z, ((len(chunk) + cols - 1) // cols) * 40 * z), (40, 38, 36, 255))
            dr = ImageDraw.Draw(im)
            for i, (src, iid, img, _, how, _) in enumerate(chunk):
                x, y = (i % cols) * 34 * z, (i // cols) * 40 * z
                im.alpha_composite(Image.fromarray(img, 'RGBA').resize((32 * z, 32 * z), Image.NEAREST), (x, y + 6 * z))
                dr.text((x + 2, y + 2), f'{src.name} {iid}', fill=(220, 220, 120))
            im.save(os.path.join(out_dir, f'{kind}_{page // per}.png'))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=('style', 'parts', 'check', 'sheet'))
    ap.add_argument('--pair', action='append')
    ap.add_argument('--library', action='append')
    ap.add_argument('--vfx')
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--out')
    a = ap.parse_args()
    if a.cmd == 'check':
        for p in (STYLE, PARTS):
            d = json.load(open(p))
            if d.get('digest') != digest(d):
                sys.exit(f'{p}: digest mismatch (edited by hand or stale)')
        st = json.load(open(STYLE))
        for m in ('gold', 'steel', 'darkiron', 'wood', 'leather'):
            if m not in st['materials']:
                sys.exit(f'style.json: material {m} missing')
        print('style.json and parts.json ok')
        return
    srcs = open_sources(a)
    if not srcs:
        sys.exit('give --pair and/or --library')
    if a.cmd == 'sheet':
        sheets(srcs, a.out)
        return
    if a.cmd == 'style':
        d = build_style(srcs, a.vfx)
        path = STYLE
    else:
        d = build_parts(srcs, json.load(open(STYLE)))
        path = PARTS
    text = dump(d)
    if a.check:
        if not os.path.exists(path) or open(path).read() != text:
            sys.exit(f'{path} differs from a rebuild')
        print(f'{path} ok')
        return
    os.makedirs(DATA, exist_ok=True)
    open(path, 'w').write(text)
    print(f'wrote {path}')


if __name__ == '__main__':
    main()
