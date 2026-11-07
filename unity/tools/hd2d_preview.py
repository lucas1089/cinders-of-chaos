#!/usr/bin/env python3
"""HD-2D preview (O432): the offline picture the owner sees before the Unity scene exists.

    python3 -I unity/tools/hd2d_preview.py DAT SPR OUT_DIR [--scale N]

Draws one hand-made temple room (15 x 11 tiles of the temple tileset, client ids 44511-44549, a few outfits) from the
real sprite pair twice and writes classic.png, hd2d.png and side_by_side.png:
- classic: flat, 32 px tiles, a 64 px thing drawn up and left of its tile, as the classic client does.
- hd2d: the same sprites as flat floor quads and upright billboards in a 3D scene seen by a tilted perspective camera,
  with real point lights (torches), soft drop shadows, bloom, distance fog and a vertical depth-of-field blur.
  Sprites are sampled nearest-neighbour per output pixel, so the pixels stay crisp.

The scene rules below are the contract with the Unity core (C#). Keep both in step:

  classify(thing)      'floor' or 'upright'                (see classify)
  light_of(thing)      (radius in tiles, linear rgb) or None   (dat light attribute, colour_from_index)
  colour_from_index(i) r = i // 36, g = (i // 6) % 6, b = i % 6, each * 51   (8-bit 6x6x6 cube)
  billboard_rect(...)  an upright thing of w x h tiles stands with its bottom-right cell on its tile: it spans
                       x in [tx + 1 - w, tx + 1], y in [0, h] (tiles up) on the plane z = ty + BASE_Z
  floor quads          a thing of w x h tiles covers tiles [tx + 1 - w, tx] x [ty + 1 - h, ty] on y = 0
  world axes           x east, y up, z south; one tile is 1 unit on x and z, a sprite pixel is 1/32 unit
  draw order           floors: dat order (ground, borders, bottom, rest), then uprights far to near (z, then x)

Needs numpy and Pillow. The sprite readers are client/tools/sprites/datspr.py, loaded only for the real pair.
"""
import argparse
import math
import os
import sys
from dataclasses import dataclass, field

import numpy as np
from PIL import Image, ImageDraw

TILE = 32            # sprite pixels per tile
BASE_Z = 0.8         # an upright thing stands this far into its tile (0 north edge, 1 south edge)
PITCH_DEG = 40.0     # camera pitch down
FOV_DEG = 26.0       # vertical field of view, narrow
LIGHT_HEIGHT = 1.5   # torch light height above the floor in tiles
LIGHT_GAIN = 1.45     # linear light strength of a torch at its centre
AMBIENT = (0.045, 0.06, 0.12)   # dim cool ambient, linear
FOG_COLOUR = (0.035, 0.045, 0.085)
FOG_START = 1.0      # tiles of distance before the fog begins, relative to the camera-to-room-centre distance
SHADOW_RES = 24      # shadow map pixels per tile
ALPHA_CUT = 128      # a sprite pixel is drawn when its alpha is at least this


# --- the rules the Unity core repeats -------------------------------------------------------------------------------

@dataclass
class ThingInfo:
    """What the renderer needs of a dat entry. flags uses the names of datspr.py (ground, clip, bottom, ...)."""
    w: int
    h: int
    flags: dict = field(default_factory=dict)
    category: str = 'item'            # 'item' or 'outfit'


# attributes that make an item more than flat paint: it blocks, it can be carried, or it hangs on a wall
_NOT_FLAT = ('notwalkable', 'blockmissile', 'blockpath', 'pickupable', 'container', 'stackable', 'hangable',
             'rotateable', 'top', 'light', 'elevation', 'forceuse', 'usable', 'multiuse', 'writable')


def classify(info):
    """'floor' for what lies flat on the ground, 'upright' for what stands (walls, objects, creatures).

    floor: an outfit never. An item with the dat ground flag, or the ground border flag (clip), or the on-bottom flag
    without a blocking attribute, or an item with none of the attributes of _NOT_FLAT (carpets, mosaics, stains).
    A wall has the on-bottom flag too, but it blocks (notwalkable), so it stands.
    """
    if info.category != 'item':
        return 'upright'
    f = info.flags
    if f.get('ground') is not None and f.get('ground') is not False:
        return 'floor'
    if f.get('clip'):
        return 'floor'
    blocked = any(f.get(k) for k in _NOT_FLAT)
    if blocked:
        return 'upright'
    return 'floor'


def colour_from_index(idx):
    """8-bit colour of the dat light attribute: a 6x6x6 cube, each step 51. Returns (r, g, b) in 0..255."""
    idx = int(idx) % 216
    return ((idx // 36) * 51, ((idx // 6) % 6) * 51, (idx % 6) * 51)


def light_of(info):
    """(radius in tiles, linear rgb 0..1) when the dat has the light attribute, else None."""
    lt = info.flags.get('light')
    if not lt:
        return None
    level, idx = int(lt[0]), int(lt[1])
    if level <= 0:
        return None
    rgb = tuple((c / 255.0) ** 2.2 for c in colour_from_index(idx))
    return float(level), rgb


def floor_rect(info, tx, ty):
    """(x0, z0, x1, z1) of the tiles a floor thing covers."""
    return (tx + 1 - info.w, ty + 1 - info.h, tx + 1, ty + 1)


def billboard_rect(info, tx, ty):
    """(x0, x1, height, z) of an upright thing: bottom-right cell on its tile, feet on the floor."""
    return (tx + 1 - info.w, tx + 1, float(info.h), ty + BASE_Z)


def draw_order_key(placement_kind, info, tx, ty):
    """Sort key of an upright thing: far (small z) first, then west to east, so a nearer one hides a farther one."""
    return (ty + BASE_Z, tx)


@dataclass
class Placement:
    kind: str            # 'item' or 'outfit'
    id: int
    tx: int
    ty: int


class Assets:
    """Interface of sprite access. Real: PairAssets. Tests: a synthetic one."""

    def info(self, kind, cid):
        raise NotImplementedError

    def image(self, kind, cid):
        """RGBA uint8 array (h * 32, w * 32, 4), the first frame, facing south."""
        raise NotImplementedError


class PairAssets(Assets):
    def __init__(self, dat_path, spr_path):
        here = os.path.dirname(os.path.abspath(__file__))
        sys.path.insert(0, os.path.join(here, '..', '..', 'client', 'tools', 'sprites'))
        import datspr
        self._ds = datspr
        self.dat = datspr.Dat(dat_path)
        self.spr = datspr.Spr(spr_path)

    def _thing(self, kind, cid):
        if kind == 'outfit':
            return self.dat.outfits[cid - 1]
        return self.dat.items[cid - 100]

    def info(self, kind, cid):
        t = self._thing(kind, cid)
        return ThingInfo(t.w, t.h, dict(t.flags), 'outfit' if kind == 'outfit' else 'item')

    def image(self, kind, cid):
        t = self._thing(kind, cid)
        return np.asarray(self._ds.render_thing(t, self.spr, direction='south'))


# --- the scene ------------------------------------------------------------------------------------------------------

ROOM_W, ROOM_H = 15, 11
WALL_TOP = 2.0       # height of the back wall in tiles, for the camera framing

# client ids of the temple tileset (server/data/items/temple_art.csv)
MARBLE, CHECKER, RUNE = 44511, 44512, 44513
BORDER_N, BORDER_E, BORDER_S, BORDER_W = 44514, 44515, 44516, 44517
CORNER_NW, CORNER_NE, CORNER_SW, CORNER_SE = 44518, 44519, 44520, 44521
MOSAIC, CARPET = 44522, 44523
BLOOD_1, BLOOD_3 = 44524, 44526
WALL_A, WALL_B, WALL_C = 44528, 44529, 44530
WALL_NS_A, WALL_NS_B, WALL_NS_C = 44532, 44533, 44534
WALL_CORNER = 44536
PILLAR_A, PILLAR_B = 44540, 44541
TORCH = 44544
PEDESTAL_A, PEDESTAL_B, PEDESTAL_C, PEDESTAL_D = 44545, 44546, 44547, 44548
GARGOYLE = 44549


def temple_scene(outfits=(57, 9, 33)):
    """The hand-made room: tiles 0..14 x 0..10 of floor, walls on row -1 and columns -1 and 15, a carpet down the
    middle, mosaics, pillars with torches, statue pedestals, a rune pad, and the outfits on the carpet."""
    P = []

    def put(cid, tx, ty, kind='item'):
        P.append(Placement(kind, cid, tx, ty))

    W, H = ROOM_W, ROOM_H
    for ty in range(H):
        for tx in range(W):
            ex, ey = tx in (0, W - 1), ty in (0, H - 1)
            if ex and ey:
                put({(0, 0): CORNER_NW, (1, 0): CORNER_NE, (0, 1): CORNER_SW, (1, 1): CORNER_SE}[(tx > 0, ty > 0)], tx, ty)
            elif ey:
                put(BORDER_N if ty == 0 else BORDER_S, tx, ty)
            elif ex:
                put(BORDER_W if tx == 0 else BORDER_E, tx, ty)
            else:
                put(MARBLE, tx, ty)
    for tx, ty in ((6, 2), (8, 2)):
        put(CHECKER, tx, ty)
    put(RUNE, 7, 2)
    put(CARPET, 8, 10)                       # 3 x 4: columns 6..8, rows 7..10 ...
    put(CARPET, 8, 6)                        # ... and rows 3..6, one long carpet to the rune pad
    for tx, ty in ((4, 4), (12, 4), (4, 9), (12, 9)):
        put(MOSAIC, tx, ty)
    put(BLOOD_1, 11, 7)
    put(BLOOD_3, 3, 7)
    # back wall, side walls and corners
    back = (WALL_A, WALL_B, WALL_A, WALL_C)
    for tx in range(0, W):
        put(back[tx % 4], tx, -1)
    # The side walls (WALL_NS_*) are oblique slabs: drawn as camera-facing cards they float, so the side stays open.
    # pillars with a torch on the floor beside each, pedestals and gargoyles
    for tx, ty in ((3, 2), (11, 2), (3, 6), (11, 6), (3, 10), (11, 10)):
        put(PILLAR_A if (tx + ty) % 2 else PILLAR_B, tx, ty)
        put(TORCH, tx + 1, ty)
    for tx, ty, cid in ((2, 3, PEDESTAL_A), (13, 3, PEDESTAL_B), (2, 8, PEDESTAL_C), (13, 8, PEDESTAL_D)):
        put(cid, tx, ty)
    put(GARGOYLE, 7, 1)
    # creatures on the carpet
    spots = ((6, 8), (9, 5), (7, 3))
    for oid, (tx, ty) in zip(outfits, spots):
        put(oid, tx, ty, 'outfit')
    return P


# --- classic render -------------------------------------------------------------------------------------------------

def _floor_sort(info):
    f = info.flags
    if f.get('ground') is not None and f.get('ground') is not False:
        return 0
    if f.get('clip'):
        return 1
    return 2


def split_scene(placements, assets):
    """(floors, uprights): floors in dat order (ground, border, rest, stable), uprights far to near."""
    floors, ups = [], []
    for i, p in enumerate(placements):
        info = assets.info(p.kind, p.id)
        (floors if classify(info) == 'floor' else ups).append((p, info, i))
    floors.sort(key=lambda e: (_floor_sort(e[1]), e[2]))
    ups.sort(key=lambda e: draw_order_key(e[0].kind, e[1], e[0].tx, e[0].ty) + (e[2],))
    return floors, ups


def render_classic(placements, assets, bounds=None, pad=1):
    """Flat picture, 32 px per tile, RGBA uint8. bounds (tx0, ty0, tx1, ty1) inclusive tiles, default: the room."""
    if bounds is None:
        bounds = (-1, -1, ROOM_W, ROOM_H - 1)
    tx0, ty0, tx1, ty1 = bounds
    tx0 -= pad; ty0 -= pad; tx1 += pad; ty1 += pad
    W, H = (tx1 - tx0 + 1) * TILE, (ty1 - ty0 + 1) * TILE
    canvas = Image.new('RGBA', (W, H), (0, 0, 0, 255))
    floors, ups = split_scene(placements, assets)
    # classic draw order: every ground first, then by tile row, west to east, a tile's things in stack order
    seq = [e for e in floors] + ups
    rest = [e for e in seq if _floor_sort(e[1]) != 0 or classify(e[1]) != 'floor']
    grounds = [e for e in seq if classify(e[1]) == 'floor' and _floor_sort(e[1]) == 0]
    rest.sort(key=lambda e: (e[0].ty, e[0].tx, 0 if classify(e[1]) == 'floor' else 1, e[2]))
    for p, info, _ in grounds + rest:
        img = Image.fromarray(np.ascontiguousarray(assets.image(p.kind, p.id)), 'RGBA')
        # bottom-right cell on the tile: 64 px things are drawn 32 px up and left
        x = (p.tx - tx0 + 1) * TILE - img.width
        y = (p.ty - ty0 + 1) * TILE - img.height
        canvas.alpha_composite(img, (x, y)) if x >= 0 and y >= 0 else _paste_clipped(canvas, img, x, y)
    return np.asarray(canvas)


def _paste_clipped(canvas, img, x, y):
    layer = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    layer.paste(img, (x, y))
    canvas.alpha_composite(layer)


# --- camera ---------------------------------------------------------------------------------------------------------

class Camera:
    """Perspective camera looking at a point of the floor from the south, pitched down. World: x east, y up, z south."""

    def __init__(self, target, distance, width, height, pitch_deg=PITCH_DEG, fov_deg=FOV_DEG, shift=(0.0, 0.0)):
        self.w, self.h = width, height
        p = math.radians(pitch_deg)
        self.target = np.array(target, np.float64)
        self.pos = self.target + distance * np.array([0.0, math.sin(p), math.cos(p)])
        f = self.target - self.pos
        self.f = f / np.linalg.norm(f)
        self.r = np.array([1.0, 0.0, 0.0])
        self.u = np.cross(self.r, self.f)
        self.focal = (height / 2.0) / math.tan(math.radians(fov_deg) / 2.0)
        self.cx = width / 2.0 + shift[0]
        self.cy = height / 2.0 + shift[1]

    def project(self, pts):
        """(n, 3) world points -> (n, 3): pixel x, pixel y (down), view depth."""
        d = np.asarray(pts, np.float64) - self.pos
        depth = d @ self.f
        x = self.cx + (d @ self.r) / depth * self.focal
        y = self.cy - (d @ self.u) / depth * self.focal
        return np.stack([x, y, depth], axis=1)

    def rays(self, xs, ys):
        """Unit-depth ray directions (view depth 1) for pixel centres: (..., 3)."""
        a = ((xs + 0.5) - self.cx) / self.focal
        b = ((ys + 0.5) - self.cy) / self.focal
        return self.f + a[..., None] * self.r - b[..., None] * self.u


def room_points(wall_top=WALL_TOP):
    """The corners that must stay in frame: the floor and the top of the back wall."""
    x0, x1 = 0.0, float(ROOM_W)
    z0, z1 = -1.0 + BASE_Z, float(ROOM_H)
    return np.array([[x0, 0, z0], [x1, 0, z0], [x0, 0, z1], [x1, 0, z1], [x0, wall_top, z0], [x1, wall_top, z0]], np.float64)


def fit_camera(width, height, margin=0.02, points=None, pitch_deg=PITCH_DEG, fov_deg=FOV_DEG):
    """Camera that frames the room: the nearest distance at which the points fit inside the margin, then shifted so the
    projected box is centred (a lens shift, the view direction stays the room centre)."""
    pts = room_points() if points is None else np.asarray(points, np.float64)
    c = pts.mean(axis=0)
    c[1] = 0.0
    lo, hi = 2.0, 400.0
    for _ in range(60):
        mid = (lo + hi) / 2
        cam = Camera(c, mid, width, height, pitch_deg, fov_deg)
        q = cam.project(pts)
        bw = q[:, 0].max() - q[:, 0].min()
        bh = q[:, 1].max() - q[:, 1].min()
        if bw <= width * (1 - 2 * margin) and bh <= height * (1 - 2 * margin):
            hi = mid
        else:
            lo = mid
    cam = Camera(c, hi, width, height, pitch_deg, fov_deg)
    q = cam.project(pts)
    sx = width / 2 - (q[:, 0].max() + q[:, 0].min()) / 2
    sy = height / 2 - (q[:, 1].max() + q[:, 1].min()) / 2
    cam = Camera(c, hi, width, height, pitch_deg, fov_deg, shift=(sx, sy))
    cam.distance = hi
    return cam


# --- light ----------------------------------------------------------------------------------------------------------

@dataclass
class Light:
    pos: tuple           # x, y, z in tiles
    radius: float        # tiles
    rgb: tuple           # linear
    owner: int = -1      # index into the uprights that carries it (casts no shadow for this light)


def falloff(dist, radius):
    """Warm smooth falloff: 1 at the light, 0 at 0.85 * radius, (1 - (d / (0.85 r))^2)^2."""
    t = np.clip(1.0 - (np.asarray(dist, np.float64) / (radius * 0.85)) ** 2, 0.0, 1.0)
    return t * t


def collect_lights(ups, assets):
    lights = []
    for k, (p, info, _) in enumerate(ups):
        lo = light_of(info)
        if lo is None:
            continue
        radius, rgb = lo
        x0, x1, h, z = billboard_rect(info, p.tx, p.ty)
        # the flame is in the right cell of the sprite, about 1.1 tiles up; the light stands a little in front of it
        lights.append(Light(((x0 + x1) / 2 + (x1 - x0) / 4, LIGHT_HEIGHT, z + 0.45), radius, rgb, k))
    return lights


def box_blur(a, r, axis):
    """Box blur along an axis with edge clamping (cumulative sum). r in pixels, int."""
    r = int(r)
    if r <= 0:
        return a
    a = np.moveaxis(a, axis, 0)
    n = a.shape[0]
    pad = np.concatenate([np.repeat(a[:1], r + 1, 0), a, np.repeat(a[-1:], r, 0)], 0)
    cs = np.cumsum(pad, axis=0, dtype=np.float64)
    out = (cs[2 * r + 1:2 * r + 1 + n] - cs[:n]) / (2 * r + 1)
    return np.moveaxis(out.astype(np.float32), 0, axis)


def blur(a, r, passes=3):
    """Gaussian-like blur: box blur passes on both axes. a: (h, w) or (h, w, c)."""
    a = a.astype(np.float32)
    for _ in range(passes):
        a = box_blur(box_blur(a, r, 0), r, 1)
    return a


# --- HD-2D render ---------------------------------------------------------------------------------------------------

def floor_texture(floors, assets, origin, size_tiles):
    """All floor things painted flat in one world-space texture, TILE px per tile. origin: (x, z) of its top-left."""
    ox, oz = origin
    wt, ht = size_tiles
    tex = Image.new('RGBA', (wt * TILE, ht * TILE), (0, 0, 0, 0))
    for p, info, _ in floors:
        img = Image.fromarray(np.ascontiguousarray(assets.image(p.kind, p.id)), 'RGBA')
        x0, z0, _, _ = floor_rect(info, p.tx, p.ty)
        layer = Image.new('RGBA', tex.size, (0, 0, 0, 0))
        layer.paste(img, (int(round((x0 - ox) * TILE)), int(round((z0 - oz) * TILE))))
        tex.alpha_composite(layer)
    return np.asarray(tex)


def shadow_maps(ups, imgs, lights, origin, size_tiles):
    """One soft shadow map per light on the floor (0 lit .. 1 shadowed), SHADOW_RES px per tile.
    Every opaque sprite pixel of every upright thing is projected from the light through its world point onto y = 0."""
    ox, oz = origin
    wt, ht = size_tiles
    SW, SH = int(wt * SHADOW_RES), int(ht * SHADOW_RES)
    pts = []
    for k, ((p, info, _), img) in enumerate(zip(ups, imgs)):
        rows, cols = np.nonzero(img[:, :, 3] >= ALPHA_CUT)
        if rows.size == 0:
            continue
        x0, x1, h, z = billboard_rect(info, p.tx, p.ty)
        X = x0 + (cols + 0.5) / TILE
        Y = h - (rows + 0.5) / TILE
        pts.append(np.stack([X, Y, np.full(X.shape, z), np.full(X.shape, k)], axis=1))
    maps = []
    allp = np.concatenate(pts, 0) if pts else np.zeros((0, 4))
    for L in lights:
        lx, ly, lz = L.pos
        m = allp[(allp[:, 3] != L.owner) & (allp[:, 1] < ly * 0.85)]
        m = m[((m[:, 0] - lx) ** 2 + (m[:, 2] - lz) ** 2) < (L.radius * 1.6) ** 2]
        t = ly / (ly - m[:, 1])
        sx = lx + (m[:, 0] - lx) * t
        sz = lz + (m[:, 2] - lz) * t
        ix = ((sx - ox) * SHADOW_RES).astype(int)
        iz = ((sz - oz) * SHADOW_RES).astype(int)
        ok = (ix >= 1) & (ix < SW - 1) & (iz >= 1) & (iz < SH - 1)
        mp = np.zeros((SH, SW), np.float32)
        for dz in (0, 1):
            for dx in (0, 1):
                mp[iz[ok] + dz, ix[ok] + dx] = 1.0
        mp = blur(mp, max(1, SHADOW_RES // 8), 3)      # soft edge, about 0.12 tile
        maps.append(np.clip(mp * 1.8, 0.0, 1.0))
    return maps


def hd2d_render(placements, assets, width=1440, height=900, return_parts=False):
    """The HD-2D picture as RGB uint8 (height, width, 3)."""
    floors, ups = split_scene(placements, assets)
    cam = fit_camera(width, height)
    ox, oz, wt, ht = -4.0, -4.0, ROOM_W + 8, ROOM_H + 8
    tex = floor_texture(floors, assets, (ox, oz), (wt, ht))
    imgs = [assets.image(p.kind, p.id) for p, _, _ in ups]
    lights = collect_lights(ups, assets)

    ys, xs = np.mgrid[0:height, 0:width]
    ray = cam.rays(xs.astype(np.float64), ys.astype(np.float64)).astype(np.float32)   # (h, w, 3), view depth 1
    cp = cam.pos.astype(np.float32)

    albedo = np.zeros((height, width, 3), np.float32)
    pos = np.zeros((height, width, 3), np.float32)
    upright = np.zeros((height, width), bool)
    emissive = np.zeros((height, width), np.float32)

    # floor: ray against y = 0
    hit = ray[..., 1] < -1e-6
    t = np.where(hit, -cp[1] / np.where(hit, ray[..., 1], -1.0), 0.0)
    fx = cp[0] + t * ray[..., 0]
    fz = cp[2] + t * ray[..., 2]
    tu = np.floor((fx - ox) * TILE).astype(int)
    tv = np.floor((fz - oz) * TILE).astype(int)
    inside = hit & (tu >= 0) & (tu < tex.shape[1]) & (tv >= 0) & (tv < tex.shape[0])
    samp = tex[np.clip(tv, 0, tex.shape[0] - 1), np.clip(tu, 0, tex.shape[1] - 1)]
    solid = inside & (samp[..., 3] >= ALPHA_CUT)
    albedo[solid] = samp[solid][:, :3] / 255.0
    pos[..., 0], pos[..., 1], pos[..., 2] = fx, 0.0, fz
    floor_mask = solid.copy()
    depth = np.where(hit, t, 1e4).astype(np.float32)

    # uprights, far to near: ray against the plane z = zb, nearest-neighbour texel
    glow_of = {L.owner: L for L in lights}
    for k, ((p, info, _), img) in enumerate(zip(ups, imgs)):
        x0, x1, h, z = billboard_rect(info, p.tx, p.ty)
        corners = np.array([[x0, 0, z], [x1, 0, z], [x0, h, z], [x1, h, z]])
        q = cam.project(corners)
        bx0, bx1 = max(int(math.floor(q[:, 0].min())), 0), min(int(math.ceil(q[:, 0].max())) + 1, width)
        by0, by1 = max(int(math.floor(q[:, 1].min())), 0), min(int(math.ceil(q[:, 1].max())) + 1, height)
        if bx1 <= bx0 or by1 <= by0:
            continue
        r = ray[by0:by1, bx0:bx1]
        tt = (z - cp[2]) / r[..., 2]
        X = cp[0] + tt * r[..., 0]
        Y = cp[1] + tt * r[..., 1]
        u = np.floor((X - x0) * TILE).astype(int)
        v = np.floor((h - Y) * TILE).astype(int)
        ok = (u >= 0) & (u < img.shape[1]) & (v >= 0) & (v < img.shape[0])
        s = img[np.clip(v, 0, img.shape[0] - 1), np.clip(u, 0, img.shape[1] - 1)]
        ok &= s[..., 3] >= ALPHA_CUT
        sl = (slice(by0, by1), slice(bx0, bx1))
        col = s[..., :3].astype(np.float32) / 255.0
        albedo[sl][ok] = col[ok]
        pos[sl][ok] = np.stack([X, Y, np.full(X.shape, z, np.float32)], -1)[ok]
        upright[sl][ok] = True
        floor_mask[sl][ok] = False
        depth[sl][ok] = tt[ok]
        em = np.zeros(ok.shape, np.float32)
        if k in glow_of:   # the flame: the bright pixels of a light source glow by themselves
            lum = col @ np.array([0.3, 0.59, 0.11], np.float32)
            em = np.clip((lum - 0.45) * 3.0, 0.0, 1.0)
        emissive[sl][ok] = em[ok]
    covered = floor_mask | upright

    # lighting, linear
    lin = albedo ** 2.2
    N = np.where(upright[..., None], np.array([0.0, 0.35, 0.94], np.float32), np.array([0.0, 1.0, 0.0], np.float32))
    smaps = shadow_maps(ups, imgs, lights, (ox, oz), (wt, ht))
    light = np.zeros_like(lin)
    light += np.array(AMBIENT, np.float32)
    ao = np.where(upright, 0.7 + 0.3 * np.clip(pos[..., 1] / 0.9, 0, 1), 1.0).astype(np.float32)
    sx_ = np.clip(((pos[..., 0] - ox) * SHADOW_RES).astype(int), 0, int(wt * SHADOW_RES) - 1)
    sz_ = np.clip(((pos[..., 2] - oz) * SHADOW_RES).astype(int), 0, int(ht * SHADOW_RES) - 1)
    for L, sm in zip(lights, smaps):
        d = np.stack([L.pos[0] - pos[..., 0], L.pos[1] - pos[..., 1], L.pos[2] - pos[..., 2]], -1)
        dist = np.linalg.norm(d, axis=-1)
        dirn = d / np.maximum(dist, 1e-4)[..., None]
        ndl = np.clip((np.sum(N * dirn, -1) + 0.25) / 1.25, 0.0, 1.0)
        a = falloff(dist, L.radius) * ndl * LIGHT_GAIN
        sh = 1.0 - 0.88 * sm[sz_, sx_] * (~upright)
        light += (a * sh * ao)[..., None] * np.array(L.rgb, np.float32)
    hdr = lin * (light * 1.0)
    hdr += (emissive[..., None] * np.array([2.2, 1.5, 0.7], np.float32)) * (lin > 0)
    hdr += lin * 0.0

    # fog by distance from the camera, then the void behind the room
    dist_cam = depth * np.linalg.norm(ray, axis=-1)
    d0 = cam.distance
    fog = 1.0 - np.exp(-np.clip(dist_cam - d0 * 0.8, 0, None) * (1.0 / (d0 * 0.9)))
    hdr = hdr * (1 - fog[..., None]) + np.array(FOG_COLOUR, np.float32) * fog[..., None]
    hdr[~covered] = np.array(FOG_COLOUR, np.float32) * 0.6

    # bloom: the bright part of the picture, blurred at three widths, added back
    scale = width / 480.0
    bright = np.clip(hdr - 0.85, 0.0, None)
    bloom = blur(bright, max(2, int(2.2 * scale)), 2) * 0.9 + blur(bright, max(3, int(6 * scale)), 2) * 0.9 \
        + blur(bright, max(6, int(14 * scale)), 2) * 0.8
    hdr = hdr + bloom * np.array([1.0, 0.9, 0.75], np.float32)

    # tone map, gamma
    exposure = 1.0
    x = hdr * exposure
    ldr = (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14)       # ACES fit
    ldr = np.clip(ldr, 0, 1) ** (1 / 2.2)

    # vertical depth of field: sharp middle band, growing blur to the top and bottom edges
    ldr = depth_of_field(ldr, focus=0.52, band=0.27, max_radius=2.4 * scale)

    # vignette
    yy = (np.arange(height) / (height - 1) * 2 - 1)[:, None]
    xx = (np.arange(width) / (width - 1) * 2 - 1)[None, :]
    vig = 1.0 - 0.28 * np.clip(xx ** 2 * 0.6 + yy ** 2 * 0.5, 0, 1.2)
    ldr = ldr * vig[..., None]
    out = (np.clip(ldr, 0, 1) * 255 + 0.5).astype(np.uint8)
    if return_parts:
        return out, dict(camera=cam, lights=lights, covered=covered)
    return out


def dof_weights(height, focus, band, levels):
    """(height, levels) weights: row y blends two neighbouring blur levels by its distance from the focus row.
    focus: focus row as a fraction of the height; band: half height of the fully sharp band as a fraction of the
    height; the blur radius reaches the last level at the picture edge furthest from the focus."""
    y = (np.arange(height) + 0.5) / height
    d = np.abs(y - focus)
    far = max(focus, 1 - focus) - band
    s = np.clip((d - band) / max(far, 1e-6), 0.0, 1.0)
    s = s * s * (3 - 2 * s)                                 # smooth
    f = s * (levels - 1)
    lo = np.floor(f).astype(int)
    hi = np.minimum(lo + 1, levels - 1)
    w = np.zeros((height, levels), np.float32)
    w[np.arange(height), lo] += (1 - (f - lo)).astype(np.float32)
    w[np.arange(height), hi] += (f - lo).astype(np.float32)
    return w


def depth_of_field(img, focus=0.5, band=0.2, max_radius=8.0, levels=5):
    """Blur that grows with the distance of a row from the focus row; rows inside the band stay sharp."""
    h = img.shape[0]
    w = dof_weights(h, focus, band, levels)
    out = np.zeros_like(img, np.float32)
    for i in range(levels):
        r = int(round(max_radius * i / (levels - 1)))
        lvl = img if r == 0 else blur(img, r, 2)
        out += lvl * w[:, i][:, None, None]
    return out


# --- output ---------------------------------------------------------------------------------------------------------

def side_by_side(classic, hd, scale_classic=None, gap=16):
    """Both pictures on one canvas, the classic one enlarged by whole numbers (nearest) to about the HD height."""
    ch = classic.shape[0]
    n = scale_classic or max(1, int(round(hd.shape[0] * 0.8 / ch)))
    c = Image.fromarray(classic[:, :, :3]).resize((classic.shape[1] * n, ch * n), Image.NEAREST)
    h = Image.fromarray(hd)
    H = max(c.height, h.height) + 36
    canvas = Image.new('RGB', (c.width + h.width + gap * 3, H), (18, 16, 20))
    canvas.paste(c, (gap, 36 + (H - 36 - c.height) // 2))
    canvas.paste(h, (c.width + gap * 2, 36 + (H - 36 - h.height) // 2))
    d = ImageDraw.Draw(canvas)
    d.text((gap, 12), 'Classic (flat, 32 px tiles)', fill=(230, 220, 200))
    d.text((c.width + gap * 2, 12), 'HD-2D (billboards, torch lights, shadows, bloom, fog, depth of field)', fill=(230, 220, 200))
    return np.asarray(canvas)


def main(argv=None):
    ap = argparse.ArgumentParser(description='HD-2D preview of the temple room from the real sprite pair (O432).')
    ap.add_argument('dat')
    ap.add_argument('spr')
    ap.add_argument('out_dir')
    ap.add_argument('--scale', type=int, default=3, help='output size: the HD picture is 480 x 300 times this (default 3)')
    a = ap.parse_args(argv)
    if a.scale < 1:
        ap.error('--scale must be at least 1')
    assets = PairAssets(a.dat, a.spr)
    scene = temple_scene()
    os.makedirs(a.out_dir, exist_ok=True)
    classic = render_classic(scene, assets)
    hd = hd2d_render(scene, assets, 480 * a.scale, 300 * a.scale)
    n = max(1, int(round(300 * a.scale * 0.8 / classic.shape[0])))
    Image.fromarray(classic[:, :, :3]).resize((classic.shape[1] * n, classic.shape[0] * n), Image.NEAREST).save(
        os.path.join(a.out_dir, 'classic.png'))
    Image.fromarray(hd).save(os.path.join(a.out_dir, 'hd2d.png'))
    Image.fromarray(side_by_side(classic, hd)).save(os.path.join(a.out_dir, 'side_by_side.png'))
    print('wrote classic.png, hd2d.png, side_by_side.png to', a.out_dir)
    return 0


if __name__ == '__main__':
    sys.exit(main())
