"""Shared helpers for the CNN sprite tools: data, negatives, material codes, models, pixel-art cleanup, previews.

Needs numpy, Pillow and PyTorch (CPU build is enough). No weights or data live in git.
"""
import colorsys
import math
import os

import numpy as np
from PIL import Image, ImageDraw

import torch
import torch.nn as nn
import torch.nn.functional as F

KINDS = ('sword', 'axe', 'club', 'rod', 'distance', 'ammo', 'shield', 'helmet', 'armor', 'legs', 'boots',
         'ring', 'amulet', 'misc')
NK = len(KINDS)
UNKNOWN = NK                       # index of "unknown" in the dataset y
MATERIALS = ('gold', 'steel', 'darkiron', 'bone', 'brown', 'red', 'blue', 'green', 'purple', 'cyan')
NM = len(MATERIALS)
NEG_TYPES = ('random_palette', 'blur', 'noise', 'pixel_jitter', 'blocky', 'tile_shuffle', 'flat', 'blob')


# ------------------------------------------------------------------------------------------------ io
def load_png(path):
    a = np.asarray(Image.open(path).convert('RGBA')).copy()
    if a.shape[:2] != (32, 32):
        im = Image.fromarray(a)
        im.thumbnail((32, 32), Image.NEAREST)
        c = Image.new('RGBA', (32, 32))
        c.paste(im, ((32 - im.width) // 2, (32 - im.height) // 2))
        a = np.asarray(c).copy()
    return binarize(a)


def binarize(a):
    a = a.copy()
    op = a[..., 3] >= 128
    a[..., 3] = np.where(op, 255, 0)
    a[~op] = 0
    return a


def to_tensor(X):
    """uint8 N,32,32,4 -> float N,4,32,32: premultiplied RGB in [0,1] and alpha"""
    t = torch.from_numpy(np.ascontiguousarray(X)).float().div_(255.0).permute(0, 3, 1, 2)
    t[:, :3] *= t[:, 3:4]
    return t


def to_diff(X):
    """uint8 -> [-1,1] RGBA for the generator (transparent rgb = 0)"""
    t = torch.from_numpy(np.ascontiguousarray(X)).float().div_(127.5).sub_(1.0).permute(0, 3, 1, 2)
    m = (t[:, 3:4] > 0).float()
    t[:, :3] = t[:, :3] * m
    return t


def from_diff(t):
    a = t.clamp(-1, 1).add(1).mul(127.5).permute(0, 2, 3, 1).round().byte().numpy()
    return a


# ------------------------------------------------------------------------------------------------ material code
def material_of(rgb):
    r, g, b = (float(c) / 255.0 for c in rgb[:3])
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    h *= 360.0
    if v < 0.12:
        return None
    if s < 0.18 or (s < 0.26 and v < 0.30):
        if 25 <= h <= 65 and s >= 0.10 and v >= 0.55:
            return 'bone'
        return 'steel' if v >= 0.42 else 'darkiron'
    if 25 <= h <= 65 and s < 0.38 and v >= 0.55:
        return 'bone'
    if 36 <= h < 66:
        return 'gold' if v >= 0.40 else 'brown'
    if 14 <= h < 36:
        return 'gold' if (s >= 0.55 and v >= 0.62) else 'brown'
    if h < 14 or h >= 335:
        return 'red'
    if 66 <= h < 165:
        return 'green'
    if 165 <= h < 200:
        return 'cyan'
    if 200 <= h < 260:
        return 'blue'
    return 'purple'


def material_code(img):
    """dominant material of the opaque pixels (by count, ink excluded) -> index into MATERIALS"""
    op = img[..., 3] > 0
    px = img[op][:, :3]
    if len(px) == 0:
        return 1
    q = (px >> 3).astype(np.int32)
    keys, inv, cnt = np.unique(q[:, 0] * 1024 + q[:, 1] * 32 + q[:, 2], return_inverse=True, return_counts=True)
    votes = np.zeros(NM)
    for k, c in zip(keys, cnt):
        rgb = ((k // 1024) * 8 + 4, ((k // 32) % 32) * 8 + 4, (k % 32) * 8 + 4)
        m = material_of(rgb)
        if m:
            votes[MATERIALS.index(m)] += c
    return int(votes.argmax()) if votes.sum() else 2


# ------------------------------------------------------------------------------------------------ negatives
def _blob_mask(rng):
    n = rng.normal(size=(8, 8))
    m = np.asarray(Image.fromarray(((n - n.min()) / (np.ptp(n) + 1e-6) * 255).astype(np.uint8)).resize(
        (32, 32), Image.BICUBIC)).astype(np.float32) / 255.0
    yy, xx = np.mgrid[0:32, 0:32]
    r = np.hypot(yy - 15.5 + rng.uniform(-4, 4), xx - 15.5 + rng.uniform(-4, 4)) / rng.uniform(9, 15)
    return (m - r * 0.6) > rng.uniform(-0.2, 0.2)


def make_negative(img, rng, other=None, kind=None):
    """one degraded / fake version of a real item (uint8 32x32x4, binary alpha). Returns (img, type index)."""
    t = rng.integers(len(NEG_TYPES)) if kind is None else kind
    a = img.astype(np.float32)
    op = img[..., 3] > 0
    if op.sum() < 4:
        t = NEG_TYPES.index('blob')
    out = a.copy()
    name = NEG_TYPES[t]
    if name == 'random_palette':
        px = img[op][:, :3]
        cols, inv = np.unique(px, axis=0, return_inverse=True)
        newc = rng.integers(0, 256, size=cols.shape)
        if rng.random() < 0.5:   # keep luminance order but random hues: harder negative
            l = cols @ np.array([0.299, 0.587, 0.114])
            base = rng.integers(0, 256, size=3).astype(np.float32)
            newc = np.clip(base[None] * (l[:, None] / 255.0) * rng.uniform(0.6, 1.6, size=cols.shape), 0, 255)
            newc = newc[:, rng.permutation(3)]
        out[op, :3] = newc[inv.ravel()]
    elif name == 'blur':
        im = Image.fromarray(img).filter(__import__('PIL.ImageFilter', fromlist=['x']).GaussianBlur(
            rng.uniform(0.7, 1.4)))
        out = np.asarray(im).astype(np.float32)
    elif name == 'noise':
        out[..., :3] += rng.normal(0, rng.uniform(18, 50), size=(32, 32, 3)) * op[..., None]
    elif name == 'pixel_jitter':
        ys, xs = np.nonzero(op)
        r = rng.integers(1, 3)
        dy = np.clip(ys + rng.integers(-r, r + 1, len(ys)), 0, 31)
        dx = np.clip(xs + rng.integers(-r, r + 1, len(xs)), 0, 31)
        out[ys, xs] = a[dy, dx]
    elif name == 'blocky':
        s = int(rng.choice([8, 11, 16]))
        im = Image.fromarray(img).resize((s, s), Image.BOX).resize((32, 32), Image.NEAREST)
        out = np.asarray(im).astype(np.float32)
    elif name == 'tile_shuffle':
        ts = int(rng.choice([4, 8]))
        n = 32 // ts
        tiles = a.reshape(n, ts, n, ts, 4).transpose(0, 2, 1, 3, 4).reshape(n * n, ts, ts, 4)
        idx = np.arange(n * n)
        sel = idx[tiles[:, :, :, 3].sum(axis=(1, 2)) > 0]
        if len(sel) > 1:
            k = rng.permutation(sel)
            tiles[sel] = tiles[k]
        out = tiles.reshape(n, n, ts, ts, 4).transpose(0, 2, 1, 3, 4).reshape(32, 32, 4)
    elif name == 'flat':
        px = img[op][:, :3].astype(np.float32)
        k = int(rng.integers(1, 3))
        cen = px[rng.integers(0, len(px), k)]
        d = ((px[:, None] - cen[None]) ** 2).sum(-1)
        out[op, :3] = cen[d.argmin(1)]
    elif name == 'blob':
        m = _blob_mask(rng)
        if other is not None and rng.random() < 0.5:   # real colours on a fake shape
            px = other[other[..., 3] > 0][:, :3]
            cols = px[rng.integers(0, len(px), size=(32, 32))].astype(np.float32)
        else:
            c0 = rng.integers(0, 256, 3).astype(np.float32)
            g = np.linspace(rng.uniform(0.3, 1.0), rng.uniform(0.3, 1.2), 32)[:, None, None]
            cols = np.clip(c0[None, None] * g + rng.normal(0, 20, (32, 32, 3)), 0, 255)
        out = np.zeros((32, 32, 4), np.float32)
        out[..., :3] = cols
        out[..., 3] = m * 255
    out = np.clip(out, 0, 255).astype(np.uint8)
    return binarize(out), t


def shift(img, rng, r=2):
    dy, dx = rng.integers(-r, r + 1, 2)
    return np.roll(np.roll(img, dy, 0), dx, 1)


# ------------------------------------------------------------------------------------------------ critic
def _blk(i, o):
    return nn.Sequential(nn.Conv2d(i, o, 3, padding=1, bias=False), nn.BatchNorm2d(o), nn.LeakyReLU(0.1, True))


class Critic(nn.Module):
    """small CNN, two heads: item kind (NK classes) and real-vs-fake (one logit)"""

    def __init__(self, w=32):
        super().__init__()
        self.f = nn.Sequential(_blk(4, w), _blk(w, w), nn.MaxPool2d(2),
                               _blk(w, 2 * w), _blk(2 * w, 2 * w), nn.MaxPool2d(2),
                               _blk(2 * w, 4 * w), _blk(4 * w, 4 * w), nn.MaxPool2d(2),
                               _blk(4 * w, 4 * w))
        self.drop = nn.Dropout(0.3)
        self.kind = nn.Linear(4 * w, NK)
        self.real = nn.Linear(4 * w, 1)

    def forward(self, x):
        h = self.f(x)
        h = torch.cat([h.mean((2, 3))], 1)
        h = self.drop(h)
        return self.kind(h), self.real(h).squeeze(1)


def load_critic(path):
    m = Critic()
    m.load_state_dict(torch.load(path, map_location='cpu'))
    m.eval()
    return m


@torch.no_grad()
def critic_scores(model, X):
    """uint8 N,32,32,4 -> (P(kind) N x NK, P(real) N)"""
    ks, rs = [], []
    for i in range(0, len(X), 512):
        k, r = model(to_tensor(X[i:i + 512]))
        ks.append(F.softmax(k, 1))
        rs.append(torch.sigmoid(r))
    return torch.cat(ks).numpy(), torch.cat(rs).numpy()


# ------------------------------------------------------------------------------------------------ generator: small DDPM U-Net
class TimeEmb(nn.Module):
    def __init__(self, d):
        super().__init__()
        self.d = d
        self.mlp = nn.Sequential(nn.Linear(d, 4 * d), nn.SiLU(), nn.Linear(4 * d, 4 * d))

    def forward(self, t):
        half = self.d // 2
        f = torch.exp(-math.log(10000) * torch.arange(half, dtype=torch.float32) / half)
        a = t.float()[:, None] * f[None]
        return self.mlp(torch.cat([a.sin(), a.cos()], 1))


class Res(nn.Module):
    def __init__(self, i, o, e):
        super().__init__()
        self.n1 = nn.GroupNorm(8, i)
        self.c1 = nn.Conv2d(i, o, 3, padding=1)
        self.e = nn.Linear(e, o)
        self.n2 = nn.GroupNorm(8, o)
        self.c2 = nn.Conv2d(o, o, 3, padding=1)
        self.skip = nn.Conv2d(i, o, 1) if i != o else nn.Identity()

    def forward(self, x, emb):
        h = self.c1(F.silu(self.n1(x)))
        h = h + self.e(emb)[:, :, None, None]
        h = self.c2(F.silu(self.n2(h)))
        return h + self.skip(x)


class Attn(nn.Module):
    def __init__(self, c):
        super().__init__()
        self.n = nn.GroupNorm(8, c)
        self.qkv = nn.Conv2d(c, 3 * c, 1)
        self.o = nn.Conv2d(c, c, 1)

    def forward(self, x):
        b, c, h, w = x.shape
        q, k, v = self.qkv(self.n(x)).reshape(b, 3, c, h * w).unbind(1)
        a = F.scaled_dot_product_attention(q.transpose(1, 2), k.transpose(1, 2), v.transpose(1, 2))
        return x + self.o(a.transpose(1, 2).reshape(b, c, h, w))


class UNet(nn.Module):
    """32x32 RGBA, conditioned on time, item kind (NK + 1 null) and material (NM + 1 null)"""

    def __init__(self, ch=64, mult=(1, 2, 2)):
        super().__init__()
        e = 4 * ch
        self.temb = TimeEmb(ch)
        self.kemb = nn.Embedding(NK + 1, e)
        self.memb = nn.Embedding(NM + 1, e)
        self.inp = nn.Conv2d(4, ch, 3, padding=1)
        chs = [ch * m for m in mult]
        self.down = nn.ModuleList()
        c = ch
        skips = [c]
        for li, co in enumerate(chs):
            self.down.append(nn.ModuleList([Res(c, co, e), Res(co, co, e)]))
            c = co
            skips += [c, c]
            if li < len(chs) - 1:
                self.down.append(nn.Conv2d(c, c, 3, stride=2, padding=1))
                skips.append(c)
        self.mid1, self.mida, self.mid2 = Res(c, c, e), Attn(c), Res(c, c, e)
        self.up = nn.ModuleList()
        for li, co in reversed(list(enumerate(chs))):
            blocks = nn.ModuleList()
            for _ in range(3):
                blocks.append(Res(c + skips.pop(), co, e))
                c = co
            self.up.append(blocks)
            if li > 0:
                self.up.append(nn.Upsample(scale_factor=2, mode='nearest'))
        self.attn16 = Attn(chs[-1])
        self.out = nn.Sequential(nn.GroupNorm(8, c), nn.SiLU(), nn.Conv2d(c, 4, 3, padding=1))

    def forward(self, x, t, k, m):
        emb = self.temb(t) + self.kemb(k) + self.memb(m)
        h = self.inp(x)
        hs = [h]
        for mod in self.down:
            if isinstance(mod, nn.ModuleList):
                for r in mod:
                    h = r(h, emb)
                    hs.append(h)
            else:
                h = mod(h)
                hs.append(h)
        h = self.mid2(self.mida(self.mid1(h, emb)), emb)
        h = self.attn16(h)
        for mod in self.up:
            if isinstance(mod, nn.ModuleList):
                for r in mod:
                    h = r(torch.cat([h, hs.pop()], 1), emb)
            else:
                h = mod(h)
        return self.out(h)


class Diffusion:
    def __init__(self, T=1000):
        self.T = T
        s = 0.008
        x = torch.linspace(0, T, T + 1)
        ac = torch.cos(((x / T) + s) / (1 + s) * math.pi * 0.5) ** 2
        ac = ac / ac[0]
        self.ab = ac[1:].clamp(1e-5, 0.9999)   # alpha-bar per step

    def noise(self, x0, t, eps):
        a = self.ab[t][:, None, None, None]
        return a.sqrt() * x0 + (1 - a).sqrt() * eps

    @torch.no_grad()
    def sample(self, model, k, m, steps=50, guide=2.0, x=None, start=1.0, gen=None):
        """DDIM (eta 0) with classifier-free guidance. x/start: img2img (SDEdit) from an image at noise level start."""
        n = len(k)
        ts = torch.linspace(int((self.T - 1) * start), 0, steps).long()
        if x is None:
            x = torch.randn(n, 4, 32, 32, generator=gen)
        else:
            x = self.noise(x, torch.full((n,), int(ts[0])), torch.randn(x.shape, generator=gen))
        kn = torch.full_like(k, NK)
        mn = torch.full_like(m, NM)
        for i, t in enumerate(ts):
            tt = torch.full((n,), int(t))
            e = model(torch.cat([x, x]), torch.cat([tt, tt]), torch.cat([k, kn]), torch.cat([m, mn]))
            ec, eu = e.chunk(2)
            eps = eu + guide * (ec - eu)
            a = self.ab[t]
            x0 = ((x - (1 - a).sqrt() * eps) / a.sqrt()).clamp(-1, 1)
            # re-derive eps from the clamped x0, else clamping leaves the noise estimate inconsistent (speckle)
            eps = (x - a.sqrt() * x0) / (1 - a).sqrt()
            if i + 1 < len(ts):
                an = self.ab[ts[i + 1]]
                x = an.sqrt() * x0 + (1 - an).sqrt() * eps
            else:
                x = x0
        return x


# ------------------------------------------------------------------------------------------------ pixel-art cleanup
def clean_pixel_art(img, colours=14, outline=True, min_blob=3):
    """alpha to 0/255, drop specks, palette-quantise the opaque pixels, selective dark outline on the silhouette"""
    a = img.copy()
    op = a[..., 3] >= 128
    # drop small connected bits
    lab = np.zeros((32, 32), np.int32)
    n = 0
    for y in range(32):
        for x in range(32):
            if op[y, x] and not lab[y, x]:
                n += 1
                st = [(y, x)]
                lab[y, x] = n
                while st:
                    cy, cx = st.pop()
                    for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                        if 0 <= ny < 32 and 0 <= nx < 32 and op[ny, nx] and not lab[ny, nx]:
                            lab[ny, nx] = n
                            st.append((ny, nx))
    if n:
        sizes = np.bincount(lab.ravel())
        sizes[0] = 0
        keep = sizes >= min_blob
        keep[sizes.argmax()] = True
        op = keep[lab] & op
    out = np.zeros_like(a)
    if op.sum() == 0:
        return out
    px = a[op][:, :3]
    pim = Image.fromarray(px.reshape(1, -1, 3).astype(np.uint8))
    q = pim.quantize(colors=min(colours, len(np.unique(px, axis=0))), method=Image.Quantize.MEDIANCUT)
    px = np.asarray(q.convert('RGB')).reshape(-1, 3)
    out[op, :3] = px
    out[op, 3] = 255
    if outline:
        p = np.pad(op, 1)
        edge = op & ~(p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:])
        rgb = out[..., :3].astype(np.float32)
        lumv = rgb @ np.array([0.299, 0.587, 0.114])
        dark = edge & (lumv > 40)
        out[dark, :3] = (rgb[dark] * 0.35 + np.array([8, 6, 10]) * 0.65).astype(np.uint8)
    return out


# ------------------------------------------------------------------------------------------------ previews
def slot():
    s = Image.new('RGBA', (36, 36), (20, 18, 18, 255))
    d = ImageDraw.Draw(s)
    d.line([(0, 0), (35, 0)], fill=(10, 9, 9))
    d.line([(0, 0), (0, 35)], fill=(10, 9, 9))
    d.line([(0, 35), (35, 35)], fill=(70, 62, 54))
    d.line([(35, 0), (35, 35)], fill=(70, 62, 54))
    d.rectangle([1, 1, 34, 34], fill=(44, 40, 38))
    return s


def slot_rows(rows, zoom=1, label_w=120, cap=None):
    """rows: list of (label, [uint8 32x32x4 or None], [optional per-cell caption]) -> PIL image, slots at zoom"""
    cw = 38
    ncol = max(len(r[1]) for r in rows)
    W, H = 6 + ncol * cw, 6 + len(rows) * cw
    pan = Image.new('RGBA', (W, H), (36, 32, 30, 255))
    for j, r in enumerate(rows):
        for i, it in enumerate(r[1]):
            x, y = 3 + i * cw, 3 + j * cw
            pan.alpha_composite(slot(), (x, y))
            if it is not None:
                pan.alpha_composite(Image.fromarray(it), (x + 2, y + 2))
    pan = pan.resize((W * zoom, H * zoom), Image.NEAREST)
    capH = 11 if any(len(r) > 2 for r in rows) else 0
    rowH = cw * zoom + capH
    out = Image.new('RGBA', (label_w + pan.width, 16 + len(rows) * rowH + 3 * zoom), (14, 12, 12, 255))
    d = ImageDraw.Draw(out)
    if cap:
        d.text((4, 2), cap, fill=(230, 220, 200))
    for j, r in enumerate(rows):
        y0 = 16 + j * rowH
        out.alpha_composite(pan.crop((0, j * cw * zoom, pan.width, (j + 1) * cw * zoom + 3 * zoom)), (label_w, y0))
        d.text((4, y0 + cw * zoom // 2 - 6), r[0], fill=(220, 210, 190))
        if len(r) > 2:
            for i, c in enumerate(r[2]):
                d.text((label_w + (3 + i * cw) * zoom, y0 + cw * zoom + 1), str(c), fill=(170, 160, 140))
    return out


def ensure(path):
    os.makedirs(path, exist_ok=True)
    return path
