#!/usr/bin/env python3
"""Creature palette and despeckle pass (pair 40): one shared palette per look, lone pixels cleaned, in place.

    python3 -I gen_creature_palette.py build --dat P/Tibia.dat --spr P/Tibia.spr --out-dir NEW [--sheets DIR]
        # pair P -> pair NEW with the target looks rewritten in place; writes monster_looks/creature_palette.csv
    python3 -I gen_creature_palette.py build --dat P/Tibia.dat --spr P/Tibia.spr --check
        # the pass again in memory (no pair written): the committed report must match, frame hashes included
    python3 -I gen_creature_palette.py build --check
        # CI, no pair: the committed report lists exactly the TARGETS, with their status

The owner approved the pass (variant A of the style study of 2026-10-22) on our donor creature looks and the looks made
from them. Per look:
  1. one palette for the whole look (every frame group, phase, direction, addon, mount and art layer), K_SMALL or
     K_BIG colours (by the look's size), chosen by k-means in CIE Lab with a fixed seed. Every palette colour is a real
     colour of the look: each cluster takes its weighted medoid (the real colour nearest to all its pixels). Three groups get their own entries, so the pass
     cannot move a pixel from one to another: near-black (luma < DARK, the outline and the deepest shadows), accents
     (small vivid or bright hue families: glowing eyes, runes, gems; up to ACCENT_MAX entries), neutral greys
     (Lab chroma under NEUTRAL_C, so a grey never drifts into a hue) and the rest. Every
     colour of a group moves to the nearest palette colour of that group.
  2. despeckle: a body pixel (not on the rim, not an accent) whose colour none of its four neighbours shares takes the
     most common neighbour colour (two or more of them), when the two are within SPECK_LUMA in luma and on the same
     side of the near-black line (dark inner lines neither grow nor shrink). Two passes.
  Alpha is never changed (soft glow pixels keep their alpha); transparent pixels stay transparent. The outline is not
  touched: rim pixels are not despeckled, and a near-black colour only maps to a near-black one. A colour mask layer
  (template: only pure colours) is never quantised, and the base pixels under it stay exactly as they were.
A look whose accents suffer is reported and left as it was (status `kept`): more than ACCENT_FAR of its vivid pixels
or SPOT_LOST of its spot pixels (vivid pixels in small spots) move more than SPOT_DE in Lab, or the vivid pixels move
more than ACCENT_DE on average.

The recolour looks of gen_theme_art.py recolour (theme_recolour.py) are remade from their passed source, so
`gen_theme_art.py recolour` on the new pair gives the looks the pair holds. The build checks first that the recolour
of the old source is exactly the old recolour look.

The pair is written like import_art_things.py does: the dat keeps its size (only the sprite ids of the target looks
change), the spr gets the new sprites appended (identical records stored once, records already in the spr reused).
Verification: the new dat re-parses; every slot of every target look decodes to the passed frame; every other thing
is byte-identical; old sprite records are unchanged (sampled); check_pair.py's append-only guard with the changed
looks allowed. Deterministic: the same pair gives byte-identical outputs.

No other art is read: the palettes come from each look's own pixels.
"""
import argparse, csv, hashlib, io, os, random, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPORT = os.path.join(HERE, 'monster_looks', 'creature_palette.csv')

SEED = 4040            # k-means++ seed (fixed: same look, same palette)
ITERS = 40             # k-means iterations (it stops earlier when the labels settle)
K_SMALL = 32           # palette size of a look up to 3 x 3 tiles
K_BIG = 32             # palette size of a larger look
DARK = 24.0            # luma under this: near-black (outline colours, docs/SPRITE_STYLE.md)
VIVID_C = 45.0         # Lab chroma of a vivid colour ...
VIVID_L = 40.0         # ... at this lightness or more
BRIGHT_L = 85.0        # or any colour this light
NEUTRAL_C = 10.0       # Lab chroma under this: a neutral grey (its own palette entries)
ACCENT_SHARE = 0.06    # a vivid hue family under this share of the look's pixels is an accent
ACCENT_MAX = 10        # palette entries for accents at most
SPOT_WIN = 5           # a vivid pixel with at most SPOT_MAX vivid pixels in its SPOT_WIN x SPOT_WIN window ...
SPOT_MAX = 8           # ... is part of a small spot (an eye, a spark, a rune dot)
SPOT_SHARE = 0.25      # a vivid colour with this share of its pixels in spots is an accent
SPOT_LOST = 0.10       # at most this share of the spot pixels may move more than SPOT_DE
SPOT_DE = 20.0
SOLID = 128            # the accent measures read pixels of this alpha or more (fainter glow is hardly seen)
ACCENT_FAR = 0.10      # at most this share of the vivid pixels may move more than SPOT_DE
ACCENT_DE = 10.0       # mean CIE76 move of the accent pixels at most
SPECK_LUMA = 40.0      # despeckle only between colours this close in luma
SPECK_PASSES = 2
TEMPLATE = {(255, 255, 0), (255, 0, 0), (0, 255, 0), (0, 0, 255)}

# --------------------------------------------------------------------------------------------------------- targets
# (first look, last look, set, why)
TARGETS = [
    (2100, 2125, 'donor', 'rift families, omen guardians and world monsters (things_custom11)'),
    (2126, 2126, 'donor', 'the Cinderheart (things_custom13)'),
    (2127, 2131, 'donor', 'raid bosses (things_custom14)'),
    (2132, 2135, 'donor', 'faction mounts (things_custom14)'),
    (2136, 2139, 'donor', 'faction auras (things_custom14)'),
    (2188, 2193, 'recolour', 'theme recolours of 2108 and 2104 (gen_theme_art.py recolour, things_custom24)'),
    (2200, 2207, 'rift', 'rift rank variants (rift_variants.py, things_custom24)'),
]
# looks left as they are by rule, with the reason (judge() adds the looks whose accents suffer)
AURA = ('aura: a soft glow effect (most pixels semi-transparent), not creature pixel art; the pass is for creatures '
        '(docs/SPRITE_STYLE.md: soft alpha is for effects and glows)')
SKIP = {2136: AURA, 2137: AURA, 2138: AURA, 2139: AURA}
RECOLOUR_FIRST = 2188  # theme_recolour.SOURCES x variants, in that order, from this look (chaos_theme_art.lua)


def target_looks():
    out = []
    for a, b, kind, _why in TARGETS:
        out += [(i, kind) for i in range(a, b + 1)]
    return out


def recolour_map():
    """recolour look -> (source look, variant)"""
    import theme_recolour as TR
    out, i = {}, RECOLOUR_FIRST
    for look, _key, _noun, variants in TR.SOURCES:
        for v in variants:
            out[i] = (look, v); i += 1
    return out


# ------------------------------------------------------------------------------------------------------ colour maths
def luma(rgb):
    rgb = np.asarray(rgb, np.float64)
    return 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]


def lab(rgb):
    c = np.asarray(rgb, np.float64) / 255.0
    c = np.where(c > 0.04045, ((c + 0.055) / 1.055) ** 2.4, c / 12.92)
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = c @ m.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


def vivid(lb):
    """vivid or bright colours (Lab rows)"""
    ch = np.hypot(lb[..., 1], lb[..., 2])
    return ((ch >= VIVID_C) & (lb[..., 0] >= VIVID_L)) | (lb[..., 0] >= BRIGHT_L)


def family(lb):
    """hue family of Lab rows: 0..11 by 30 degrees of Lab hue, 12 for bright colours of low chroma"""
    ch = np.hypot(lb[..., 1], lb[..., 2])
    hue = (np.degrees(np.arctan2(lb[..., 2], lb[..., 1])) + 360.0) % 360.0
    return np.where(ch < VIVID_C, 12, (hue // 30).astype(np.int64))


def pack(rgb):
    rgb = np.asarray(rgb, np.int64)
    return (rgb[..., 0] << 16) | (rgb[..., 1] << 8) | rgb[..., 2]


def unpack(code):
    code = np.asarray(code, np.int64)
    return np.stack([(code >> 16) & 255, (code >> 8) & 255, code & 255], -1)


def vivid_px(img):
    """vivid, not near-black, solid (alpha SOLID or more) pixels of an RGBA frame"""
    return (img[..., 3] >= SOLID) & vivid(lab(img[..., :3])) & (luma(img[..., :3]) >= DARK)


def spots(viv):
    """vivid pixels in small spots: few vivid pixels in the window round them"""
    r = SPOT_WIN // 2
    c = np.pad(viv.astype(np.int64), r).cumsum(0).cumsum(1)
    c = np.pad(c, ((1, 0), (1, 0)))
    h, w = viv.shape
    n = c[SPOT_WIN:SPOT_WIN + h, SPOT_WIN:SPOT_WIN + w] - c[:h, SPOT_WIN:SPOT_WIN + w] \
        - c[SPOT_WIN:SPOT_WIN + h, :w] + c[:h, :w]
    return viv & (n <= SPOT_MAX)


# ------------------------------------------------------------------------------------------------------------ palette
def kmeans(x, w, k, seed=SEED):
    """weighted k-means of rows x (weights w): -> labels. k-means++ start from a fixed seed; deterministic."""
    n = len(x)
    if n <= k:
        return np.arange(n)
    rng = np.random.default_rng(seed)
    p = w / w.sum()
    cent = [x[int(rng.choice(n, p=p))]]
    d = ((x - cent[0]) ** 2).sum(1)
    for _ in range(1, k):
        q = w * d
        if q.sum() <= 0:
            break
        cent.append(x[int(rng.choice(n, p=q / q.sum()))])
        d = np.minimum(d, ((x - cent[-1]) ** 2).sum(1))
    c = np.array(cent)
    lbl = None
    for _ in range(ITERS):
        new = ((x[:, None, :] - c[None]) ** 2).sum(2).argmin(1)
        if lbl is not None and (new == lbl).all():
            break
        lbl = new
        for j in range(len(c)):
            m = lbl == j
            if m.any():
                c[j] = (x[m] * w[m, None]).sum(0) / w[m].sum()
    return lbl


def medoid(x, w):
    """index of the row of x with the least weighted squared distance to all rows (first of a tie)"""
    best, bi = None, 0
    for a in range(0, len(x), 512):
        d = (((x[a:a + 512, None, :] - x[None]) ** 2).sum(2) * w[None]).sum(1)
        i = int(np.argmin(d))
        if best is None or d[i] < best:
            best, bi = float(d[i]), a + i
    return bi


def group_palette(codes, counts, k, seed=SEED):
    """k real colours for one group (codes sorted, counts): -> {code: palette code}"""
    if len(codes) <= k:
        return {int(c): int(c) for c in codes}
    lb = lab(unpack(codes))
    lbl = kmeans(lb, counts.astype(np.float64), k, seed)
    reps = []
    for j in np.unique(lbl):
        m = lbl == j
        reps.append(int(codes[m][medoid(lb[m], counts[m].astype(np.float64))]))
    reps = np.array(sorted(set(reps)), np.int64)
    rl = lab(unpack(reps))
    near = ((lb[:, None, :] - rl[None]) ** 2).sum(2).argmin(1)
    return {int(c): int(reps[i]) for c, i in zip(codes, near)}


def split_budget(weights, sizes, k):
    """k palette entries over groups by pixel count: each group at least 1, none more than its colours"""
    n = len(weights)
    if not n:
        return []
    ks = [1] * n
    left = k - n
    tot = float(sum(weights))
    while left > 0:
        room = [i for i in range(n) if ks[i] < sizes[i]]
        if not room:
            break
        i = max(room, key=lambda j: (weights[j] / tot - ks[j] / float(k), -j))
        ks[i] += 1; left -= 1
    return ks


def accent_families(codes, counts, spot_codes=()):
    """[(family, bool mask over codes)] of the accent colours: vivid hue families under ACCENT_SHARE of the pixels,
    and in bigger families the colours used mostly in small spots; the most vivid families first"""
    rgb = unpack(codes); lb = lab(rgb)
    viv = vivid(lb) & ~(luma(rgb) < DARK)
    fam = family(lb)
    total = max(int(counts.sum()), 1)
    spot = viv & np.isin(codes, np.array(sorted(spot_codes), np.int64))
    out = []
    for f in sorted(set(fam[viv].tolist())):
        m = viv & (fam == f)
        if counts[m].sum() / total >= ACCENT_SHARE:
            m = spot & (fam == f)
            if not m.any():
                continue
        score = float(np.hypot(lb[m, 1], lb[m, 2]).mean() + lb[m, 0].mean())
        out.append((-score, f, m))
    out.sort(key=lambda t: (t[0], t[1]))
    return [(f, m) for _s, f, m in out]


def make_palette(codes, counts, k_total, spot_codes=()):
    """the look's palette: -> ({code: palette code}, info). codes / counts: every visible colour of the look;
    info['accents']: the palette colours the pass protects (despeckle leaves them alone)."""
    codes = np.asarray(codes, np.int64); counts = np.asarray(counts, np.int64)
    order = np.argsort(codes); codes, counts = codes[order], counts[order]
    fams = accent_families(codes, counts, spot_codes)
    info = {'k': k_total, 'accent_entries': 0}
    if len(codes) <= max(k_total, K_BIG):   # a look of 32 colours or fewer keeps its palette (despeckle only)
        info['identity'] = True
        info['accents'] = {int(c) for _f, m in fams for c in codes[m]}
        info['accent_entries'] = len(info['accents'])
        return {int(c): int(c) for c in codes}, info
    rgb = unpack(codes); lb = lab(rgb)
    dark = luma(rgb) < DARK
    acc = np.zeros(len(codes), bool)
    out = {}
    left = ACCENT_MAX
    for f, m in fams:
        if left <= 0:
            break
        kf = min(2 if m.sum() > 2 else 1, int(m.sum()), left)
        out.update(group_palette(codes[m], counts[m], kf, SEED + 1 + f))
        left -= kf
        acc |= m
    rest = k_total - (ACCENT_MAX - left)
    chroma = np.hypot(lb[:, 1], lb[:, 2])
    free = ~acc
    parts = [m for m in (dark & free, ~dark & free & (chroma < NEUTRAL_C), ~dark & free & (chroma >= NEUTRAL_C))
             if m.any()]
    ks = split_budget([int(counts[m].sum()) for m in parts], [int(m.sum()) for m in parts], rest)
    for m, kk in zip(parts, ks):
        out.update(group_palette(codes[m], counts[m], kk, SEED))
    info['accents'] = {out[int(c)] for c in codes[acc]}
    info['accent_entries'] = len(info['accents'])
    return out, info


# ---------------------------------------------------------------------------------------------------------- despeckle
def rim_of(vis):
    p = np.pad(vis, 1)
    return vis & ~(p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:])


def despeckle(img, frozen=None, keep_codes=(), passes=SPECK_PASSES):
    """img RGBA (H, W, 4) uint8 -> a copy with lone body pixels cleaned (alpha unchanged)."""
    a = img.copy()
    vis = a[..., 3] > 0
    ok = vis & ~rim_of(vis)
    if frozen is not None:
        ok &= ~frozen
    keep = np.array(sorted(keep_codes), np.int64)
    for _ in range(passes):
        code = np.where(vis, pack(a[..., :3]), -1)
        cand = ok & ~np.isin(code, keep)
        p = np.pad(code, 1, constant_values=-1)
        nb = np.stack([p[:-2, 1:-1], p[2:, 1:-1], p[1:-1, :-2], p[1:-1, 2:]], -1)
        lone = cand & ~(nb == code[..., None]).any(-1)
        if not lone.any():
            break
        ys, xs = np.nonzero(lone)
        n = nb[ys, xs]                                            # (m, 4)
        cnt = (n[:, :, None] == n[:, None, :]).sum(2)             # how often each neighbour colour occurs
        best = cnt.argmax(1)                                      # first of the most common
        val = n[np.arange(len(n)), best]
        good = (cnt[np.arange(len(n)), best] >= 2) & (val >= 0)
        new = unpack(val)
        l0, l1 = luma(a[ys, xs, :3]), luma(new)
        good &= (np.abs(l1 - l0) < SPECK_LUMA) & ((l1 < DARK) == (l0 < DARK))   # never across the near-black line
        a[ys[good], xs[good], :3] = new[good].astype(np.uint8)
    return a


# ------------------------------------------------------------------------------------------------------------ metrics
def frame_stats(img, frozen=None):
    """(body pixels, lone body pixels, vivid pixels) of one frame"""
    vis = img[..., 3] > 0
    body = vis & ~rim_of(vis)
    if frozen is not None:
        body &= ~frozen
    code = np.where(vis, pack(img[..., :3]), -1)
    p = np.pad(code, 1, constant_values=-2)
    same = (p[:-2, 1:-1] == code) | (p[2:, 1:-1] == code) | (p[1:-1, :-2] == code) | (p[1:-1, 2:] == code)
    return int(body.sum()), int((body & ~same).sum())


def max_cell_colours(img):
    h, w = img.shape[:2]
    best = 0
    for y in range(0, h, 32):
        for x in range(0, w, 32):
            c = img[y:y + 32, x:x + 32]
            v = c[..., 3] > 0
            if v.any():
                best = max(best, len(np.unique(pack(c[v][:, :3]))))
    return best


# --------------------------------------------------------------------------------------------------------- the pass
def is_mask_layer(frames):
    """frames of one layer: True when every visible pixel is a pure colour (each channel 0 or 255)"""
    any_px = False
    for f in frames:
        v = f[..., 3] > 0
        if v.any():
            any_px = True
            px = f[v][:, :3]
            if not np.isin(px, (0, 255)).all():
                return False
    return any_px


def pass_look(frames, layers_of, k_total):
    """frames: {key: RGBA}, layers_of: {key: (layer index, mask key or None)}. The keys of mask layers are kept;
    -> (new frames, stats dict)."""
    mask_keys = {k for k, (_l, m) in layers_of.items() if m == 'mask'}
    frozen = {}
    for k, (layer, m) in layers_of.items():
        if m not in (None, 'mask'):
            mk = m
            fm = frames[mk]
            frozen[k] = fm[..., 3] > 0
    codes, spot_codes = [], []
    for k, f in frames.items():
        if k in mask_keys:
            continue
        v = f[..., 3] > 0
        if k in frozen:
            v &= ~frozen[k]
        codes.append(pack(f[v][:, :3]))
        spot_codes.append(pack(f[spots(vivid_px(f)) & v][:, :3]))
    allc = np.concatenate(codes) if codes else np.zeros(0, np.int64)
    uc, cn = np.unique(allc, return_counts=True)
    sc, sn = np.unique(np.concatenate(spot_codes) if spot_codes else np.zeros(0, np.int64), return_counts=True)
    tot = dict(zip(uc.tolist(), cn.tolist()))
    spot_set = {int(c) for c, n in zip(sc, sn) if n >= SPOT_SHARE * tot[int(c)]}
    pal, info = make_palette(uc, cn, k_total, spot_set)
    keep = info['accents']
    lut_from = np.array(sorted(pal), np.int64)
    lut_to = np.array([pal[int(c)] for c in lut_from], np.int64)
    out = {}
    st = {'body0': 0, 'lone0': 0, 'body1': 0, 'lone1': 0, 'cell0': 0, 'cell1': 0}
    for k, f in frames.items():
        if k in mask_keys:
            out[k] = f
            continue
        g = f.copy()
        v = g[..., 3] > 0
        fz = frozen.get(k)
        q = v & ~fz if fz is not None else v
        if q.any():
            idx = np.searchsorted(lut_from, pack(g[q][:, :3]))
            g[q, :3] = unpack(lut_to[idx]).astype(np.uint8)
        g = despeckle(g, fz, keep)
        g[g[..., 3] == 0] = 0
        out[k] = g
        b0, l0 = frame_stats(f, fz); b1, l1 = frame_stats(g, fz)
        st['body0'] += b0; st['lone0'] += l0; st['body1'] += b1; st['lone1'] += l1
        st['cell0'] = max(st['cell0'], max_cell_colours(f)); st['cell1'] = max(st['cell1'], max_cell_colours(g))
    st.update(look_compare(frames, out, mask_keys, frozen))
    st['info'] = info
    return out, st


def look_compare(before, after, mask_keys=(), frozen=None):
    """colours before / after, vivid pixels before / after, mean Lab move of the vivid pixels"""
    frozen = frozen or {}
    c0, c1 = set(), set()
    v0 = v1 = s0 = s1 = vf = 0
    de_sum, de_n = 0.0, 0
    for k, f in before.items():
        if k in mask_keys:
            continue
        g = after[k]
        v = f[..., 3] > 0
        if k in frozen:
            v &= ~frozen[k]
        if not v.any():
            continue
        p0 = f[v][:, :3]; p1 = g[v][:, :3]
        c0 |= set(np.unique(pack(p0)).tolist()); c1 |= set(np.unique(pack(p1)).tolist())
        l0 = lab(p0); l1 = lab(p1)
        d0 = luma(p0) < DARK; d1 = luma(p1) < DARK
        so = f[v][:, 3] >= SOLID
        a0 = vivid(l0) & ~d0 & so; a1 = vivid(l1) & ~d1 & so
        v0 += int(a0.sum()); v1 += int(a1.sum())
        if a0.any():
            dv = np.sqrt(((l0[a0] - l1[a0]) ** 2).sum(1))
            de_sum += float(dv.sum()); de_n += int(a0.sum()); vf += int((dv > SPOT_DE).sum())
        sp = spots(vivid_px(f))
        if k in frozen:
            sp &= ~frozen[k]
        if sp.any():
            de = np.sqrt(((lab(f[sp][:, :3]) - lab(g[sp][:, :3])) ** 2).sum(1))
            s0 += int(sp.sum()); s1 += int((de > SPOT_DE).sum())
    return {'colours0': len(c0), 'colours1': len(c1), 'vivid0': v0, 'vivid1': v1,
            'vivid_de': de_sum / de_n if de_n else 0.0, 'vivid_far': vf, 'spots0': s0, 'spots_moved': s1}


def judge(st):
    """'' when the look may change, else the reason it is kept"""
    if st['vivid0'] >= 20:
        if st['vivid_far'] > ACCENT_FAR * st['vivid0']:
            return 'accents lost: %d of %d vivid pixels moved' % (st['vivid_far'], st['vivid0'])
        if st['vivid_de'] > ACCENT_DE:
            return 'accents moved: mean %.1f Lab' % st['vivid_de']
    if st['spots0'] >= 20 and st['spots_moved'] > SPOT_LOST * st['spots0']:
        return 'small accents lost: %d of %d spot pixels moved' % (st['spots_moved'], st['spots0'])
    if st['lone1'] * st['body0'] > st['lone0'] * st['body1']:
        return 'speckle not lower'
    return ''


# ---------------------------------------------------------------------------------------------------- pair access
def look_frames(dat, spr, t):
    """{(g, ph, z, y, d, layer): RGBA canvas} of every frame of outfit t, and its groups (import_outfits.parse_body)"""
    from import_outfits import parse_body
    from datspr import sprite_index
    gs = parse_body(dat, t)
    out = {}
    for gi, g in enumerate(gs):
        W, H = g.w * 32, g.h * 32
        for ph in range(g.phases):
            for z in range(g.pz):
                for y in range(g.py):
                    for d in range(g.px):
                        for layer in range(g.layers):
                            img = np.zeros((H, W, 4), np.uint8)
                            for hh in range(g.h):
                                for ww in range(g.w):
                                    s = spr.sprite(g.sprites[sprite_index(g, d, y, z, layer, ph, ww, hh)])
                                    if s is not None:
                                        y0, x0 = (g.h - 1 - hh) * 32, (g.w - 1 - ww) * 32
                                        img[y0:y0 + 32, x0:x0 + 32] = s
                            out[(gi, ph, z, y, d, layer)] = img
    return out, gs


def layer_roles(frames, gs, aura):
    """{key: (layer, None | 'mask' | mask key)}: a template layer of a look with 2 layers (not an aura) is a mask"""
    roles = {k: (k[5], None) for k in frames}
    if aura or max(g.layers for g in gs) < 2:
        return roles
    for li in range(1, max(g.layers for g in gs)):
        ks = [k for k in frames if k[5] == li]
        if is_mask_layer([frames[k] for k in ks]):
            for k in ks:
                roles[k] = (li, 'mask')
                base = k[:5] + (0,)
                roles[base] = (0, k)
    return roles


def frames_hash(frames):
    h = hashlib.sha256()
    for k in sorted(frames):
        h.update(repr(k).encode()); h.update(np.ascontiguousarray(frames[k]).tobytes())
    return h.hexdigest()[:16]


def k_for(gs):
    return K_BIG if max(g.w * g.h for g in gs) > 9 else K_SMALL


CANDIDATES = {}   # look -> the frames the pass made (also for kept looks: previews)


def run_pass(dat, spr, log=print):
    """-> (rows, {look: new frames}, {look: old frames}, {look: groups})"""
    import theme_recolour as TR
    rmap = recolour_map()
    auras = set(range(2136, 2140))
    rows, new, old, groups = [], {}, {}, {}
    for look, kind in target_looks():
        t = dat.outfit(look)
        fr, gs = look_frames(dat, spr, t)
        old[look], groups[look] = fr, gs
        if look in rmap:
            src, var = rmap[look]
            sfr = old[src]
            sg = groups[src]
            base_keys = [(gi, ph, 0, 0, d, 0) for gi, g in enumerate(sg) for ph in range(g.phases) for d in range(4)]
            h0 = TR.source_hue([sfr[k] for k in base_keys])
            for k, f in fr.items():
                exp = TR.recolour(sfr[k], h0, var) if k[5] == 0 else sfr[k]
                exp = exp.copy(); exp[exp[..., 3] == 0] = 0
                if not np.array_equal(exp, f):
                    raise SystemExit('recolour look %d is not the recolour of %d (%s) at %s' % (look, src, var, k))
            if src in new:
                nsrc = new[src]
                h1 = TR.source_hue([nsrc[k] for k in base_keys])
                nf = {}
                for k in fr:
                    g_ = TR.recolour(nsrc[k], h1, var) if k[5] == 0 else nsrc[k]
                    g_ = g_.copy(); g_[g_[..., 3] == 0] = 0
                    nf[k] = g_
                st = {'body0': 0, 'lone0': 0, 'body1': 0, 'lone1': 0, 'cell0': 0, 'cell1': 0}
                for k in fr:
                    b0, l0 = frame_stats(fr[k]); b1, l1 = frame_stats(nf[k])
                    st['body0'] += b0; st['lone0'] += l0; st['body1'] += b1; st['lone1'] += l1
                    st['cell0'] = max(st['cell0'], max_cell_colours(fr[k]))
                    st['cell1'] = max(st['cell1'], max_cell_colours(nf[k]))
                st.update(look_compare(fr, nf))
                st['info'] = {'k': 'from %d' % src}
                why = SKIP.get(look, '')
            else:
                nf, st, why = fr, None, 'source %d kept' % src
        else:
            roles = layer_roles(fr, gs, look in auras)
            nf, st = pass_look(fr, roles, k_for(gs))
            why = SKIP.get(look) or judge(st)
        if st is None:
            st = {'body0': 0, 'lone0': 0, 'body1': 0, 'lone1': 0, 'cell0': 0, 'cell1': 0, 'colours0': 0,
                  'colours1': 0, 'vivid0': 0, 'vivid1': 0, 'vivid_de': 0.0, 'vivid_far': 0, 'spots0': 0, 'spots_moved': 0,
                  'info': {'k': '-'}}
        CANDIDATES[look] = nf
        changed = not why and any(not np.array_equal(nf[k], fr[k]) for k in fr)
        if changed:
            new[look] = nf
        status = 'changed' if changed else ('kept' if why else 'same')
        row = {
            'look': look, 'set': kind, 'status': status, 'reason': why,
            'k': st['info'].get('k', ''), 'colours_before': st['colours0'], 'colours_after': st['colours1'],
            'speckle_before': '%.3f' % (st['lone0'] / max(st['body0'], 1)),
            'speckle_after': '%.3f' % (st['lone1'] / max(st['body1'], 1)),
            'cell_colours_before': st['cell0'], 'cell_colours_after': st['cell1'],
            'vivid_before': st['vivid0'], 'vivid_moved': st['vivid_far'], 'vivid_move': '%.1f' % st['vivid_de'],
            'spots_before': st['spots0'], 'spots_moved': st['spots_moved'],
            'accent_entries': st['info'].get('accent_entries', ''),
            'frames': len(fr), 'sha256': frames_hash(nf) if changed else '',
        }
        rows.append(row)
        log('%(look)d %(set)s %(status)s colours %(colours_before)s -> %(colours_after)s speckle %(speckle_before)s -> '
            '%(speckle_after)s cell %(cell_colours_before)s -> %(cell_colours_after)s vivid %(vivid_moved)s/'
            '%(vivid_before)s (move %(vivid_move)s) spots %(spots_moved)s/%(spots_before)s %(reason)s' % row)
    return rows, new, old, groups


FIELDS = ['look', 'set', 'status', 'reason', 'k', 'colours_before', 'colours_after', 'speckle_before', 'speckle_after',
          'cell_colours_before', 'cell_colours_after', 'vivid_before', 'vivid_moved', 'vivid_move', 'spots_before', 'spots_moved', 'accent_entries',
          'frames', 'sha256']


def report_text(rows):
    buf = io.StringIO()
    w = csv.DictWriter(buf, FIELDS, lineterminator='\n')
    w.writeheader()
    for r in rows:
        w.writerow(r)
    return buf.getvalue()


def read_report():
    with open(REPORT, newline='') as f:
        return list(csv.DictReader(f))


def check_report_rows(rows):
    """CI (no pair): the committed report covers exactly the TARGETS, in order, with sane statuses"""
    errs = []
    want = target_looks()
    got = [(int(r['look']), r['set']) for r in rows]
    if got != want:
        errs.append('report looks / sets differ from TARGETS')
    rmap = recolour_map()
    status = {int(r['look']): r for r in rows}
    for r in rows:
        lk = int(r['look'])
        if r['status'] not in ('changed', 'kept', 'same'):
            errs.append('%d: status %r' % (lk, r['status']))
        if lk in SKIP and (r['status'] != 'kept' or r['reason'] != SKIP[lk]):
            errs.append('%d: listed in SKIP but not kept with its reason' % lk)
        if (r['status'] == 'changed') != bool(r['sha256']):
            errs.append('%d: a changed look needs its frame hash, only it' % lk)
        if r['status'] == 'kept' and not r['reason']:
            errs.append('%d: kept without a reason' % lk)
        if lk in rmap and status.get(rmap[lk][0], {}).get('status') != 'changed' and r['status'] == 'changed':
            errs.append('%d: changed although its source %d is not' % (lk, rmap[lk][0]))
    return errs


# ------------------------------------------------------------------------------------------------------ pair writer
def encode_sprite(tile):
    """the spr record of a 32 x 32 RGBA tile (import_art_things.encode_sprite), None when empty"""
    from import_art_things import encode_sprite as enc
    return enc(tile)


def write_pair(dat, spr, new, groups, out_dir, log=print):
    """the input pair with the sprite ids of the looks of `new` replaced; -> (sprites appended, slots rewritten)"""
    from datspr import sprite_index
    assert dat.variant[2], 'u32 sprite ids expected (10.98)'
    d = bytearray(dat.data)
    recs, plan = {}, []          # record -> None (in order), [(dat offset, record or old id)]
    slots = 0
    for look in sorted(new):
        t = dat.outfit(look)
        gs = groups[look]
        assert len(t.spr_pos) == len(gs), look
        for gi, (g, (pos, ns)) in enumerate(zip(gs, t.spr_pos)):
            assert ns == len(g.sprites)
            for ph in range(g.phases):
                for z in range(g.pz):
                    for y in range(g.py):
                        for x in range(g.px):
                            for layer in range(g.layers):
                                img = new[look][(gi, ph, z, y, x, layer)]
                                for hh in range(g.h):
                                    for ww in range(g.w):
                                        i = sprite_index(g, x, y, z, layer, ph, ww, hh)
                                        y0, x0 = (g.h - 1 - hh) * 32, (g.w - 1 - ww) * 32
                                        tile = np.ascontiguousarray(img[y0:y0 + 32, x0:x0 + 32])
                                        sid = g.sprites[i]
                                        oldt = spr.sprite(sid)
                                        oldt = np.zeros((32, 32, 4), np.uint8) if oldt is None else oldt
                                        if np.array_equal(oldt, tile):
                                            continue
                                        rec = encode_sprite(tile)
                                        slots += 1
                                        if rec is None:
                                            plan.append((pos + 4 * i, 0))
                                        else:
                                            recs.setdefault(rec, None)
                                            plan.append((pos + 4 * i, rec))
    # records already in the spr (import_art_things.py does the same)
    mb = np.frombuffer(spr.m, dtype=np.uint8)
    offs = spr.offs.astype(np.int64)
    nzi = np.nonzero(offs)[0]
    lens = 5 + mb[offs[nzi] + 3].astype(np.int64) + (mb[offs[nzi] + 4].astype(np.int64) << 8)
    want = {}
    for rec in recs:
        want.setdefault(len(rec), {})[hashlib.md5(rec).digest()] = rec
    existing = {}
    if want:
        for i in np.nonzero(np.isin(lens, np.array(sorted(want), np.int64)))[0]:
            o = int(offs[nzi[i]]); ln = int(lens[i])
            rec = bytes(spr.m[o:o + ln])
            hit = want[ln].get(hashlib.md5(rec).digest())
            if hit is not None and hit == rec and rec not in existing:
                existing[rec] = int(nzi[i]) + 1
    cnt = spr.count
    newrecs, rec_id = [], {}
    for rec in recs:
        if rec in existing:
            rec_id[rec] = existing[rec]
        else:
            newrecs.append(rec); rec_id[rec] = cnt + len(newrecs)
    for off, v in plan:
        struct.pack_into('<I', d, off, v if isinstance(v, int) else rec_id[v])
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, 'Tibia.dat'), 'wb') as f:
        f.write(bytes(d))
    m = spr.m; nn = len(newrecs)
    toffs = spr.offs.astype('<u8').copy(); toffs[toffs > 0] += 4 * nn
    cur = len(m) + 4 * nn
    new_offs = []
    for rec in newrecs:
        new_offs.append(cur); cur += len(rec)
    assert cur < 1 << 32, 'spr would exceed 4 GB'
    table = np.concatenate([toffs, np.array(new_offs, dtype='<u8')]).astype('<u4')
    with open(os.path.join(out_dir, 'Tibia.spr'), 'wb') as f:
        f.write(struct.pack('<II', spr.signature, cnt + nn)); f.write(table.tobytes())
        p = 8 + 4 * cnt
        while p < len(m):
            f.write(m[p:p + (1 << 24)]); p += 1 << 24
        for rec in newrecs:
            f.write(rec)
    log('pair: %d looks, %d sprite slots rewritten, %d distinct new sprites (%d appended, %d reused), spr %d -> %d'
        % (len(new), slots, len(recs), nn, len(recs) - nn, cnt, cnt + nn))
    return nn, slots


def verify(dat, spr, new, out_dir, log=print):
    """the written pair: re-parses, the changed looks decode to the passed frames, everything else is unchanged"""
    from datspr import Dat, Spr
    md = Dat(os.path.join(out_dir, 'Tibia.dat')); ms = Spr(os.path.join(out_dir, 'Tibia.spr'))
    assert md.variant == dat.variant and md.counts == dat.counts and len(md.data) == len(dat.data)
    assert ms.signature == spr.signature and ms.alpha and md.max_sprite <= ms.count
    for lst0, lst1 in ((dat.items, md.items), (dat.outfits, md.outfits), (dat.effects, md.effects),
                       (dat.missiles, md.missiles)):
        for t0, t1 in zip(lst0, lst1):
            assert t0.raw == t1.raw, (t0, 'moved')
            b0, b1 = dat.data[t0.raw[0]:t0.raw[1]], md.data[t1.raw[0]:t1.raw[1]]
            if t0.cat == 'o' and t0.id in new:
                continue
            assert b0 == b1, (t0, 'changed')
    n = 0
    for look, frames in new.items():
        fr, _gs = look_frames(md, ms, md.outfit(look))
        assert set(fr) == set(frames), look
        for k in fr:
            assert np.array_equal(fr[k], frames[k]), (look, k)
            n += 1
    rnd = random.Random(40)
    sample = sorted({1, spr.count} | {rnd.randint(1, spr.count) for _ in range(3000)})
    for sid in sample:
        a, b = spr.sprite(sid), ms.sprite(sid)
        assert (a is None and b is None) or np.array_equal(a, b), ('old sprite changed', sid)
    log('verified: %d frames of %d looks decode to the pass, every other thing byte-identical, %d sampled old sprites '
        'unchanged' % (n, len(new), len(sample)))


# ------------------------------------------------------------------------------------------------------ contact sheets
def contact_sheet(before, after, title_b, title_a, zoom=2):
    """before (left) and after (right): rows = directions, columns = frames (both groups, up to 8), 2x"""
    from PIL import Image, ImageDraw
    bg = (70, 66, 74, 255); gap = 6
    keys = sorted(before)
    cols = sorted({(k[0], k[1]) for k in keys})
    if len(cols) > 8:
        cols = [cols[i] for i in sorted(set(np.linspace(0, len(cols) - 1, 8).round().astype(int).tolist()))]
    dirs = sorted({k[4] for k in keys})
    H = max(before[k].shape[0] for k in keys); W = max(before[k].shape[1] for k in keys)

    def block(fr):
        im = Image.new('RGBA', (len(cols) * (W + gap), len(dirs) * (H + gap)), bg)
        for ci, (g, ph) in enumerate(cols):
            for di, d in enumerate(dirs):
                c = Image.new('RGBA', (W, H), (0, 0, 0, 0))
                for k in keys:
                    if k[:5] == (g, ph, 0, 0, d):
                        a = fr[k]
                        c.alpha_composite(Image.fromarray(a, 'RGBA'), (W - a.shape[1], H - a.shape[0]))
                im.alpha_composite(c, (ci * (W + gap), di * (H + gap)))
        return im
    b, a = block(before), block(after)
    sh = Image.new('RGBA', (b.width * 2 + 24, b.height + 18), bg)
    sh.alpha_composite(b, (0, 18)); sh.alpha_composite(a, (b.width + 24, 18))
    dr = ImageDraw.Draw(sh)
    dr.text((2, 3), title_b, fill=(235, 235, 235, 255)); dr.text((b.width + 26, 3), title_a, fill=(235, 235, 235, 255))
    return sh.resize((sh.width * zoom, sh.height * zoom), Image.NEAREST).convert('RGB')


def write_sheets(rows, new, old, out):
    os.makedirs(out, exist_ok=True)
    n = 0
    for r in rows:
        lk = r['look']
        if lk not in new:
            continue
        im = contact_sheet(old[lk], new[lk], 'look %d before: %s colours, speckle %s' % (lk, r['colours_before'],
                                                                                          r['speckle_before']),
                           'after: %s colours, speckle %s' % (r['colours_after'], r['speckle_after']))
        im.save(os.path.join(out, 'look_%d.png' % lk), optimize=True)
        n += 1
    md = ['| look | set | status | colours | speckle | max colours / 32 px cell | vivid pixels moved | spot pixels '
          'moved | note |', '|---|---|---|---|---|---|---|---|---|']
    for r in rows:
        md.append('| %(look)s | %(set)s | %(status)s | %(colours_before)s -> %(colours_after)s | %(speckle_before)s -> '
                  '%(speckle_after)s | %(cell_colours_before)s -> %(cell_colours_after)s | %(vivid_moved)s / '
                  '%(vivid_before)s | %(spots_moved)s / %(spots_before)s | %(reason)s |' % r)
    open(os.path.join(out, 'summary.md'), 'w').write('\n'.join(md) + '\n')
    open(os.path.join(out, 'summary.csv'), 'w').write(report_text(rows))
    print('wrote %d contact sheets and summary.md to %s' % (n, out))


# ------------------------------------------------------------------------------------------------------------- main
def md5(path):
    h = hashlib.md5()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(1 << 24), b''):
            h.update(b)
    return h.hexdigest()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('--dat'); b.add_argument('--spr'); b.add_argument('--out-dir')
    b.add_argument('--check', action='store_true')
    b.add_argument('--sheets', help='before / after contact sheets (PNG) and summary.md into this folder')
    b.add_argument('--expect-dat-md5', help='stop unless the input dat has this md5')
    a = ap.parse_args(argv)
    if not a.dat:
        if not a.check:
            ap.error('build needs --dat and --spr (only build --check runs without the pair)')
        errs = check_report_rows(read_report())
        if errs:
            print('\n'.join(errs))
            sys.exit('gen_creature_palette.py build --check: %d problems' % len(errs))
        rows = read_report()
        print('check: %s lists the %d target looks (%d changed, %d kept)' % (
            os.path.relpath(REPORT, HERE), len(rows), sum(r['status'] == 'changed' for r in rows),
            sum(r['status'] == 'kept' for r in rows)))
        return
    from datspr import Dat, Spr
    if a.expect_dat_md5 and md5(a.dat) != a.expect_dat_md5:
        sys.exit('input dat md5 %s, expected %s' % (md5(a.dat), a.expect_dat_md5))
    dat, spr = Dat(a.dat), Spr(a.spr)
    rows, new, old, groups = run_pass(dat, spr)
    text = report_text(rows)
    if a.sheets:
        write_sheets(rows, new, old, a.sheets)
    if a.check:
        cur = open(REPORT, newline='').read() if os.path.isfile(REPORT) else ''
        if cur != text:
            sys.exit('gen_creature_palette.py build --check: %s differs from the pass' % os.path.relpath(REPORT, HERE))
        print('check: the pass gives the committed %s (%d looks changed)' % (os.path.relpath(REPORT, HERE), len(new)))
        return
    if not a.out_dir:
        ap.error('build needs --out-dir (or --check)')
    write_pair(dat, spr, new, groups, a.out_dir)
    verify(dat, spr, new, a.out_dir)
    open(REPORT, 'w', newline='').write(text)
    print('wrote %s; changed looks: %s' % (os.path.relpath(REPORT, HERE), ','.join(str(k) for k in sorted(new))))
    print('dat %s  spr %s' % (md5(os.path.join(a.out_dir, 'Tibia.dat')), md5(os.path.join(a.out_dir, 'Tibia.spr'))))


if __name__ == '__main__':
    main()
