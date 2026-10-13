"""Elemental recolour variants of monster looks we already ship (gen_theme_art.py recolour). Reads the outfits from
our own pair (the live things), recolours the base layer (the colour mask layer, when there is one, is kept as it is)
and writes them in the import_art_things.py outfit layout, so they append as new looks.

The recolour keeps every pixel's value and position: saturated pixels (the glow, flames, eyes) take the variant's
hue (their spread of hues halved round it), the rest gets a light tint of it. No reference art is involved.
"""
import numpy as np

from datspr import sprite_index
from import_outfits import parse_body

# variant: target hue (degrees), saturation factor, value lift, tint of the unsaturated pixels
VARIANTS = {
    'frost': (200.0, 1.0, 0.06, 0.10),
    'venom': (100.0, 1.05, 0.0, 0.10),
    'void': (275.0, 1.0, 0.0, 0.12),
}
SOURCES = [   # (source look, key, name, variants) : looks of client/tools/sprites/monster_looks/picks.csv
    (2108, 'crypt_minion', 'skeleton', ('frost', 'venom', 'void')),
    (2104, 'obsidian_minion', 'hound', ('frost', 'venom', 'void')),
]
ADJ = {'frost': 'frost-bound', 'venom': 'venom-soaked', 'void': 'void-touched'}


def rgb_to_hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = rgb.max(-1); mn = rgb.min(-1)
    d = mx - mn
    h = np.zeros_like(mx)
    m = d > 1e-6
    rc = np.where(m, (mx - r) / np.where(m, d, 1), 0)
    gc = np.where(m, (mx - g) / np.where(m, d, 1), 0)
    bc = np.where(m, (mx - b) / np.where(m, d, 1), 0)
    h = np.where(r == mx, bc - gc, np.where(g == mx, 2.0 + rc - bc, 4.0 + gc - rc))
    h = np.where(m, (h / 6.0) % 1.0, 0)
    s = np.where(mx > 1e-6, d / np.where(mx > 1e-6, mx, 1), 0)
    return h, s, mx


def hsv_to_rgb(h, s, v):
    i = np.floor(h * 6).astype(int) % 6
    f = h * 6 - np.floor(h * 6)
    p = v * (1 - s); q = v * (1 - s * f); t = v * (1 - s * (1 - f))
    sel = [i == k for k in range(6)]
    r = np.select(sel, [v, q, p, p, t, v])
    g = np.select(sel, [t, v, v, q, p, p])
    b = np.select(sel, [p, p, t, v, v, q])
    return np.stack([r, g, b], -1)


def source_hue(frames):
    """the mean hue (circular) of the saturated pixels of an outfit's base layer"""
    xs, ys = 0.0, 0.0
    for img in frames:
        a = img[..., 3] > 0
        h, s, v = rgb_to_hsv(img[..., :3].astype(np.float32) / 255)
        w = (s > 0.35) & (v > 0.25) & a
        xs += np.cos(h[w] * 2 * np.pi).sum(); ys += np.sin(h[w] * 2 * np.pi).sum()
    return (np.arctan2(ys, xs) / (2 * np.pi)) % 1.0


def recolour(img, src_h, variant):
    th, sk, lift, tint = VARIANTS[variant]
    th /= 360.0
    out = img.copy()
    a = img[..., 3] > 0
    rgb = img[..., :3].astype(np.float32) / 255
    h, s, v = rgb_to_hsv(rgb)
    dh = ((h - src_h + 0.5) % 1.0) - 0.5
    sat = (s > 0.28) & (v > 0.12)
    nh = np.where(sat, (th + dh * 0.5) % 1.0, h)
    ns = np.where(sat, np.clip(s * sk, 0, 1), s)
    nv = np.where(sat, np.clip(v + lift * v, 0, 1), v)
    new = hsv_to_rgb(nh, ns, nv)
    tcol = hsv_to_rgb(np.full_like(h, th), np.full_like(h, 0.6), v)
    new = np.where(sat[..., None], new, new * (1 - tint) + tcol * tint)
    out[..., :3] = np.where(a[..., None], np.round(np.clip(new, 0, 1) * 255), img[..., :3]).astype(np.uint8)
    return out


def frame(spr, g, d, y, z, layer, ph):
    W, H = g.w * 32, g.h * 32
    img = np.zeros((H, W, 4), np.uint8)
    for hh in range(g.h):
        for ww in range(g.w):
            t = spr.sprite(g.sprites[sprite_index(g, d, y, z, layer, ph, ww, hh)])
            if t is not None:
                y0, x0 = (g.h - 1 - hh) * 32, (g.w - 1 - ww) * 32
                img[y0:y0 + 32, x0:x0 + 32] = t
    return img


def variant_sheets(dat, spr):
    """-> [(key, name, sheet RGBA, spec row dict)]"""
    out = []
    for look, key, noun, variants in SOURCES:
        t = dat.outfit(look)
        assert not t.flags, (look, 'source look with flags: carry them over first', t.flags)
        gs = parse_body(dat, t)
        g0 = gs[0]
        assert all((g.w, g.h, g.layers, g.px, g.py, g.pz) == (g0.w, g0.h, g0.layers, 4, g0.py, g0.pz) for g in gs), look
        base = [frame(spr, g, d, 0, 0, 0, ph) for g in gs for ph in range(g.phases) for d in range(4)]
        src_h = source_hue(base)
        for var in variants:
            nrows = sum(g.phases for g in gs)
            ncols = g0.pz * g0.py * g0.layers * 4
            W, H = g0.w * 32, g0.h * 32
            sheet = np.zeros((nrows * H, ncols * W, 4), np.uint8)
            row = 0
            for g in gs:
                for ph in range(g.phases):
                    for z in range(g.pz):
                        for y in range(g.py):
                            for layer in range(g.layers):
                                for d in range(4):
                                    img = frame(spr, g, d, y, z, layer, ph)
                                    if layer == 0:
                                        img = recolour(img, src_h, var)
                                    c = ((z * g.py + y) * g.layers + layer) * 4 + d
                                    sheet[row * H:(row + 1) * H, c * W:(c + 1) * W] = img
                    row += 1
            ex = ['gtypes=%s' % '+'.join(str(g.gtype) for g in gs), 'layers=%d' % g0.layers, 'addons=%d' % g0.py,
                  'mounts=%d' % g0.pz, 'exact=%s' % '+'.join(str(g.exact) for g in gs)]
            for k, g in enumerate(gs):
                if g.anim:
                    asyn, loop, start, durs = g.anim
                    ex.append('durs%d=%s' % (k, '/'.join('%d:%d' % (durs[2 * i], durs[2 * i + 1])
                                                           for i in range(g.phases))))
                    ex.append('anim%d=%d:%d:%d' % (k, asyn, loop, start))
            vkey = '%s_%s' % (key, var)
            name = '%s %s' % (ADJ[var], noun)
            spec = dict(key=vkey, cat='outfit', kind='creature', name=name, atlas='theme_recolour/%s' % vkey, x=0, y=0,
                        w=g0.w, h=g0.h, patterns=4, phases='+'.join(str(g.phases) for g in gs), flags='', mode='new',
                        server_id='', extra='|'.join(ex) + '|source=%d' % look)
            out.append((vkey, name, sheet, spec))
    return out
