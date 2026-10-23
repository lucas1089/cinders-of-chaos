#!/usr/bin/env python3
"""Draws the live spectator snapshot with the client's sprites (server/README.md "Live spectator", docs/ADMIN_APP.md).

The engine (data/scripts/chaos/spectate.lua) writes remote.spectate in the server folder once a second while the admin
app watches a player: the tiles around the player on its floor (client ids bottom to top), the creatures on them and the
player's stats. chaos-ctl.sh spectate NAME runs this tool on that file and prints its answer to the app.

    python3 -I server/tools/spectate_render.py render --dat P/Tibia.dat --spr P/Tibia.spr --snapshot SERVER/remote.spectate \
        --watch NAME [--max-age 5] [--cache-dir DIR]
        one JSON line: {"ok": true, "name", "level", "voc", "hp", "maxhp", "mp", "maxmp", "cap", "soul", "pos": [x, y, z],
        "age", "w", "h", "png": base64 of a 480 x 352 PNG (the client's 15 x 11 tiles, 32 px each)}
        or {"ok": false, "error": "offline" | "stale" | "bad-snapshot" | "no-pair", "message"}; exit 0 for offline,
        1 for the others
    python3 -I server/tools/spectate_render.py index --dat P/Tibia.dat --cache-dir DIR
        builds the sprite index of the dat now (else the first render does it)
    python3 -I server/tools/spectate_render.py unpack-pair --sums SHA256SUMS.parts --out DIR PART...
        the pair archive of the windows-assets branch (things/things-1098.tar.xz.part*): every part checked against the
        sums file, then only Tibia.dat and Tibia.spr are taken out of the tar (by their base name, regular files only)
    python3 -I server/tools/spectate_render.py info --dat P/Tibia.dat --spr P/Tibia.spr [--cache-dir DIR]
        key=value lines: dat, spr, dat_md5, dat_bytes, spr_bytes, index

Drawing, as the client does for one floor: tiles row by row; per tile the ground, borders, bottom items (walls), the
other items oldest first, the creatures, then the top items (arches); elevation lifts what stands on it; positional
patterns by the world position, stack patterns by count, fluid colours by kind. Creatures: idle frame 0 in their
direction, addons, the four outfit colours (the website's maths, website/tools/gen_sprite_images.py), a mount with its
rider seat; then a health bar and the name over each, coloured by health as the client does. Not drawn: other floors,
light, animations, effects, missiles, walking offsets, text and the client's own interface.

The dat is parsed once (client/tools/sprites/datspr.py) into a small index of the first animation frame of every item
and look, kept as JSON in --cache-dir and rebuilt when the dat changes (size, time, inode). The spr is read in place.
Needs python3-numpy and python3-pil. Tests: spectate_render_test.py (a synthetic pair, no real pair needed).
"""
import argparse
import base64
import hashlib
import io
import json
import lzma
import os
import re
import sys
import tarfile
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, os.path.join(REPO, 'client', 'tools', 'sprites'))
sys.path.insert(0, os.path.join(REPO, 'website', 'tools'))
import numpy as np  # noqa: E402
from PIL import Image, ImageDraw, ImageFont  # noqa: E402
import datspr  # noqa: E402
import gen_sprite_images as gsi  # noqa: E402

VIEW_W, VIEW_H = 15, 11       # the client's view in tiles; the player stands at (7, 5) of it
TILE = 32
INDEX_VERSION = 1
SNAPSHOT_VERSION = 1
MAX_SNAPSHOT_BYTES = 2_000_000
KEEP_FLAGS = ('ground', 'clip', 'bottom', 'top', 'stackable', 'fluid', 'splash')
PAIR_FILES = ('Tibia.dat', 'Tibia.spr')
NAME_RE = re.compile(r"^[A-Za-z][A-Za-z '-]{2,28}$")
# drawing order on a tile: ground, borders, bottom items, common items, creatures, top items
P_GROUND, P_CLIP, P_BOTTOM, P_COMMON, P_TOP = 0, 1, 2, 3, 5


class BadSnapshot(Exception):
    pass


class Look:
    """the first animation frame of a dat thing, enough for datspr.sprite_index and gen_sprite_images.draw_thing"""
    __slots__ = ('w', 'h', 'layers', 'px', 'py', 'pz', 'phases', 'sprites', 'flags')

    def __init__(self, w, h, layers, px, py, pz, flags, sprites):
        self.w, self.h, self.layers, self.px, self.py, self.pz = w, h, layers, px, py, pz
        self.phases = 1
        self.flags = flags
        self.sprites = sprites


# ------------------------------------------------------------------------------------------------ the index
def _record(t):
    n = t.w * t.h * t.layers * t.px * t.py * t.pz          # phase 0 only
    flags = {}
    for k in KEEP_FLAGS:
        if k in t.flags:
            flags[k] = 1
    if 'elevation' in t.flags:
        flags['elevation'] = int(t.flags['elevation'])
    if 'displacement' in t.flags:
        flags['displacement'] = [int(v) for v in t.flags['displacement']]
    if 'x39' in t.flags:
        flags['x39'] = bytes(t.flags['x39']).hex()
    return [t.w, t.h, t.layers, t.px, t.py, t.pz, flags, [int(s) for s in t.sprites[:n]]]


def build_index(dat_path):
    dat = datspr.Dat(dat_path)
    return {'v': INDEX_VERSION, 'items': [_record(t) for t in dat.items],
            'outfits': [_record(t) for t in dat.outfits]}


def _look(rec):
    w, h, layers, px, py, pz, flags, sprites = rec
    flags = dict(flags)
    if 'displacement' in flags:
        flags['displacement'] = tuple(flags['displacement'])
    if 'x39' in flags:
        flags['x39'] = bytes.fromhex(flags['x39'])
    return Look(w, h, layers, px, py, pz, flags, sprites)


def dat_key(dat_path):
    st = os.stat(dat_path)
    return f'{st.st_size}:{st.st_mtime_ns}:{st.st_ino}:{INDEX_VERSION}'


def load_index(dat_path, cache_dir=None):
    """(items by client id, looks by look type): from the cache when it matches the dat, else parsed (and cached)."""
    key = dat_key(dat_path)
    path = os.path.join(cache_dir, 'dat-index.json') if cache_dir else None
    data = None
    if path and os.path.isfile(path):
        try:
            with open(path, encoding='utf-8') as f:
                data = json.load(f)
            if not isinstance(data, dict) or data.get('key') != key or data.get('v') != INDEX_VERSION:
                data = None
        except (OSError, ValueError):
            data = None
    if data is None:
        data = build_index(dat_path)
        data['key'] = key
        if path:
            os.makedirs(cache_dir, mode=0o700, exist_ok=True)
            fd, tmp = tempfile.mkstemp(prefix='.dat-index.', dir=cache_dir)
            with os.fdopen(fd, 'w', encoding='utf-8') as f:
                json.dump(data, f, separators=(',', ':'))
            os.replace(tmp, path)
    items = {100 + i: _look(r) for i, r in enumerate(data['items'])}
    outfits = {1 + i: _look(r) for i, r in enumerate(data['outfits'])}
    return items, outfits


# ------------------------------------------------------------------------------------------------ the snapshot
def _int(v, lo, hi, what):
    if isinstance(v, bool) or not isinstance(v, int) or not lo <= v <= hi:
        raise BadSnapshot(f'{what}: {v!r}')
    return v


def read_snapshot(path, watch, max_age, now=None):
    """the snapshot as a dict, checked; raises BadSnapshot (or returns it with online False)."""
    try:
        with open(path, 'rb') as f:
            raw = f.read(MAX_SNAPSHOT_BYTES + 1)
    except OSError as e:
        raise BadSnapshot(f'cannot read the snapshot: {e.strerror}') from None
    if len(raw) > MAX_SNAPSHOT_BYTES:
        raise BadSnapshot('snapshot too big')
    try:
        s = json.loads(raw.decode('utf-8'))
    except (UnicodeDecodeError, ValueError):
        raise BadSnapshot('not JSON') from None
    if not isinstance(s, dict) or s.get('v') != SNAPSHOT_VERSION:
        raise BadSnapshot('not a snapshot of this version')
    if s.get('watch') != watch:
        raise BadSnapshot('stale: the snapshot is of another watch')
    t = _int(s.get('t'), 0, 2 ** 40, 't')
    now = time.time() if now is None else now
    if now - t > max_age:
        raise BadSnapshot(f'stale: {int(now - t)} s old')
    if s.get('online') is not True:
        s['online'] = False
        return s
    w = _int(s.get('w'), 1, 40, 'w')
    h = _int(s.get('h'), 1, 40, 'h')
    _int(s.get('x0'), -100, 70000, 'x0')
    _int(s.get('y0'), -100, 70000, 'y0')
    pos = s.get('pos')
    if not isinstance(pos, dict):
        raise BadSnapshot('pos')
    for k in ('x', 'y', 'z'):
        _int(pos.get(k), -100, 70000, 'pos.' + k)
    tiles = s.get('tiles')
    if not isinstance(tiles, list) or len(tiles) != w * h:
        raise BadSnapshot('tiles')
    for tl in tiles:
        if not isinstance(tl, (list, dict)) or len(tl) > 32:
            raise BadSnapshot('tile')
        for e in (tl if isinstance(tl, list) else []):
            if isinstance(e, list):
                if len(e) != 2:
                    raise BadSnapshot('item')
                _int(e[0], 0, 0xFFFFFF, 'item')
                _int(e[1], 0, 0xFFFF, 'count')
            else:
                _int(e, 0, 0xFFFFFF, 'item')
    cres = s.get('creatures')
    if isinstance(cres, dict) and not cres:
        cres = s['creatures'] = []     # an empty table may come as {}
    if not isinstance(cres, list) or len(cres) > 200:
        raise BadSnapshot('creatures')
    for c in cres:
        if not isinstance(c, dict) or not isinstance(c.get('o'), dict):
            raise BadSnapshot('creature')
        _int(c.get('x'), -100, 70000, 'creature x')
        _int(c.get('y'), -100, 70000, 'creature y')
        _int(c.get('d', 2), 0, 3, 'direction')
        _int(c.get('hp', 0), 0, 100, 'health')
        for k in ('t', 'h', 'b', 'l', 'f', 'a', 'm', 'x'):
            _int(c['o'].get(k, 0), 0, 0xFFFFFF, 'look ' + k)
        if not isinstance(c.get('name', ''), str) or len(c.get('name', '')) > 40:
            raise BadSnapshot('creature name')
    for k in ('level', 'hp', 'maxhp', 'mp', 'maxmp', 'cap', 'soul'):
        if k in s:
            _int(s[k], -2 ** 31, 2 ** 40, k)
    return s


# ------------------------------------------------------------------------------------------------ drawing
def blit(canvas, img, x, y):
    """alpha-composite img (h x w x 4) onto canvas at (x, y), clipped to the canvas."""
    H, W = canvas.shape[:2]
    h, w = img.shape[:2]
    x0, y0 = max(0, x), max(0, y)
    x1, y1 = min(W, x + w), min(H, y + h)
    if x0 >= x1 or y0 >= y1:
        return
    sub = img[y0 - y:y1 - y, x0 - x:x1 - x]
    if not sub[..., 3].any():
        return
    gsi.over(canvas, np.ascontiguousarray(sub), (x0, y0))


def item_priority(t):
    f = t.flags
    if 'ground' in f:
        return P_GROUND
    if 'clip' in f:
        return P_CLIP
    if 'bottom' in f:
        return P_BOTTOM
    if 'top' in f:
        return P_TOP
    return P_COMMON


def item_patterns(t, wx, wy, wz, sub):
    if 'stackable' in t.flags:
        x, y = gsi.stack_pattern(1 if sub is None else sub, t.px, t.py)
        return x, y, 0
    if 'fluid' in t.flags or 'splash' in t.flags:
        x, y = gsi.fluid_pattern((sub or 0) & 7, t.px, t.py)
        return x, y, 0
    return wx % t.px, wy % t.py, wz % t.pz


def _disp(t):
    d = t.flags.get('displacement') or (0, 0)
    return gsi.s16(d[0]), gsi.s16(d[1])


_THINGS = {}


def thing_img(t, spr, x, y, z, layers=None):
    """gen_sprite_images.draw_thing, kept for the rest of this run (a view repeats the same grounds and walls)"""
    k = (id(t), x, y, z, layers)
    img = _THINGS.get(k)
    if img is None:
        if len(_THINGS) > 4000:
            _THINGS.clear()
        img = gsi.draw_thing(t, spr, x, y, z, None if layers is None else list(layers))
        _THINGS[k] = img
    return img


def draw_item(canvas, t, spr, left, top, wx, wy, wz, sub=None):
    """the item with its bottom-right cell on the tile whose top-left is (left, top)"""
    x, y, z = item_patterns(t, wx, wy, wz, sub)
    img = thing_img(t, spr, x, y, z)
    dx, dy = _disp(t)
    blit(canvas, img, left - (t.w - 1) * TILE - dx, top - (t.h - 1) * TILE - dy)


def creature_image(c, outfits, spr):
    """(image, (x, y) of its top-left relative to the tile's top-left) of an outfit creature, or None"""
    o = c['o']
    t = outfits.get(o.get('t', 0))
    if t is None:
        return None
    m = outfits.get(o.get('m', 0)) if o.get('m', 0) else None
    meta = gsi.outfit_meta(t)
    mmeta = gsi.outfit_meta(m) if m is not None else None
    rxy, mxy, z = gsi.place(meta, mmeta)
    z = min(z, t.pz - 1)
    rects = [(rxy[0], rxy[1], t.w * TILE, t.h * TILE)]
    if mxy is not None:
        rects.append((mxy[0], mxy[1], m.w * TILE, m.h * TILE))
    left = min(r[0] for r in rects)
    top = min(r[1] for r in rects)
    right = max(r[0] + r[2] for r in rects)
    bottom = max(r[1] + r[3] for r in rects)
    img = np.zeros((bottom - top, right - left, 4), np.uint8)
    d = c.get('d', 2)
    if mxy is not None:
        mart = thing_img(m, spr, d if m.px >= 4 else 0, 0, 0, (0,))
        gsi.over(img, mart, (mxy[0] - left, mxy[1] - top))
    colours = (o.get('h', 0), o.get('b', 0), o.get('l', 0), o.get('f', 0))
    addons = o.get('a', 0)
    dx = d if t.px >= 4 else 0
    at = (rxy[0] - left, rxy[1] - top)
    for y in range(t.py):
        if y > 0 and not addons & (1 << (y - 1)):
            continue
        gsi.over(img, thing_img(t, spr, dx, y, z, (0,)), at)
        if t.layers > 1:
            gsi.tint(img, thing_img(t, spr, dx, y, z, (1,)), colours, at)
    return img, (left, top)


def health_colour(pct):
    """the client's colour of a creature's name and health bar"""
    if pct > 92:
        return (0x00, 0xBC, 0x00)
    if pct > 60:
        return (0x50, 0xA1, 0x50)
    if pct > 30:
        return (0xA1, 0xA1, 0x00)
    if pct > 8:
        return (0xBF, 0x0A, 0x0A)
    if pct > 3:
        return (0x91, 0x0F, 0x0F)
    return (0x85, 0x0C, 0x0C)


SKULL_COLOURS = {1: (255, 220, 0), 2: (0, 200, 0), 3: (235, 235, 235), 4: (210, 0, 0), 5: (20, 20, 20),
                 6: (255, 140, 0)}


def render(snap, items, outfits, spr):
    """the client's 15 x 11 view of the snapshot as an RGB PIL image (480 x 352)"""
    w, h, x0, y0 = snap['w'], snap['h'], snap['x0'], snap['y0']
    z = snap['pos']['z']
    canvas = np.zeros((h * TILE, w * TILE, 4), np.uint8)
    canvas[..., 3] = 255
    by_tile = {}
    for c in snap['creatures']:
        by_tile.setdefault((c['x'] - x0, c['y'] - y0), []).append(c)
    infos = []
    for ty in range(h):
        for tx in range(w):
            stack = snap['tiles'][ty * w + tx]
            if isinstance(stack, dict):
                stack = []
            things = []
            for k, e in enumerate(stack):
                cid, sub = (e[0], e[1]) if isinstance(e, list) else (e, None)
                t = items.get(cid)
                if t is not None:
                    things.append((item_priority(t), k, t, sub))
            things.sort(key=lambda v: (v[0], v[1]))
            left, top = tx * TILE, ty * TILE
            wx, wy = x0 + tx, y0 + ty
            elev = 0
            cres = by_tile.get((tx, ty), [])
            drawn = False
            for pr, _k, t, sub in things:
                if pr == P_TOP and not drawn:
                    elev = draw_creatures(canvas, cres, outfits, items, spr, left, top, elev, infos, wx, wy, z)
                    drawn = True
                draw_item(canvas, t, spr, left - elev, top - elev, wx, wy, z, sub)
                if 'elevation' in t.flags:
                    elev = min(24, elev + t.flags['elevation'])
            if not drawn:
                draw_creatures(canvas, cres, outfits, items, spr, left, top, elev, infos, wx, wy, z)
    img = Image.fromarray(canvas, 'RGBA').convert('RGB')
    draw_infos(img, infos)
    vx = snap['pos']['x'] - (VIEW_W // 2) - x0
    vy = snap['pos']['y'] - (VIEW_H // 2) - y0
    vx = max(0, min(w - VIEW_W, vx)) if w >= VIEW_W else 0
    vy = max(0, min(h - VIEW_H, vy)) if h >= VIEW_H else 0
    view = Image.new('RGB', (VIEW_W * TILE, VIEW_H * TILE), (0, 0, 0))
    view.paste(img.crop((vx * TILE, vy * TILE, (vx + VIEW_W) * TILE, (vy + VIEW_H) * TILE)), (0, 0))
    return view


def draw_creatures(canvas, cres, outfits, items, spr, left, top, elev, infos, wx, wy, z):
    for c in cres:
        o = c['o']
        dxy = (8, 8)
        if o.get('t', 0) == 0:
            t = items.get(o.get('x', 0))
            if t is not None:
                draw_item(canvas, t, spr, left - elev, top - elev, wx, wy, z)
        else:
            got = creature_image(c, outfits, spr)
            if got is not None:
                img, (ox, oy) = got
                blit(canvas, img, left - elev + ox, top - elev + oy)
                dxy = _disp(outfits[o['t']])
        infos.append((left - elev - dxy[0] + 16, top - elev - dxy[1], c))
    return elev


def draw_infos(img, infos):
    """health bars and names over the creatures, as the client draws them over everything"""
    d = ImageDraw.Draw(img)
    font = ImageFont.load_default()
    for cx, ty, c in infos:
        col = health_colour(c.get('hp', 0))
        bx, by = cx - 14, ty - 6
        d.rectangle((bx, by, bx + 27, by + 3), fill=(0, 0, 0))
        fill = int(round(26 * c.get('hp', 0) / 100))
        if fill > 0:
            d.rectangle((bx + 1, by + 1, bx + fill, by + 2), fill=col)
        name = c.get('name', '')
        if name:
            tw = d.textlength(name, font=font)
            nx, ny = cx - tw / 2, by - 12
            for ox, oy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                d.text((nx + ox, ny + oy), name, font=font, fill=(0, 0, 0))
            d.text((nx, ny), name, font=font, fill=col)
        skull = c.get('skull', 0)
        if skull in SKULL_COLOURS:
            d.ellipse((bx + 29, by - 2, bx + 35, by + 4), fill=SKULL_COLOURS[skull], outline=(0, 0, 0))


def png_bytes(img):
    """a small PNG: the view in 256 colours (the art has few; names and bars stay sharp)"""
    q = img.quantize(256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    buf = io.BytesIO()
    q.save(buf, 'PNG', compress_level=6)
    return buf.getvalue()


def answer(snap, img, now=None):
    now = time.time() if now is None else now
    out = {'ok': True, 'name': snap.get('name', ''), 'level': snap.get('level', 0), 'voc': snap.get('voc', ''),
           'hp': snap.get('hp', 0), 'maxhp': snap.get('maxhp', 0), 'mp': snap.get('mp', 0),
           'maxmp': snap.get('maxmp', 0), 'cap': snap.get('cap', 0), 'soul': snap.get('soul', 0),
           'pos': [snap['pos']['x'], snap['pos']['y'], snap['pos']['z']], 'age': max(0, int(now - snap['t'])),
           'w': img.width, 'h': img.height, 'png': base64.b64encode(png_bytes(img)).decode('ascii')}
    for k in ('name', 'voc'):
        out[k] = str(out[k])[:40]
    return out


# ------------------------------------------------------------------------------------------------ the pair archive
def read_sums(path):
    """{base name: sha256} of a sha256sum file ("HEX  path" or "HEX *path")"""
    sums = {}
    with open(path, encoding='utf-8') as f:
        for line in f:
            m = re.match(r'^([0-9a-fA-F]{64}) [ *](\S+)\s*$', line)
            if m:
                sums[os.path.basename(m.group(2))] = m.group(1).lower()
    return sums


class _Chain(io.RawIOBase):
    """the parts read as one file"""

    def __init__(self, paths):
        self.paths = list(paths)
        self.f = None

    def readable(self):
        return True

    def readinto(self, b):
        while True:
            if self.f is None:
                if not self.paths:
                    return 0
                self.f = open(self.paths.pop(0), 'rb')
            n = self.f.readinto(b)
            if n:
                return n
            self.f.close()
            self.f = None

    def close(self):
        if self.f:
            self.f.close()
        super().close()


def unpack_pair(parts, sums_path, out_dir):
    """checks every part against the sums, then writes Tibia.dat and Tibia.spr of the archive into out_dir (new)."""
    if not parts:
        raise SystemExit('no parts')
    sums = read_sums(sums_path)
    for p in parts:
        want = sums.get(os.path.basename(p))
        if not want:
            raise SystemExit(f'{os.path.basename(p)} is not in {os.path.basename(sums_path)}')
        h = hashlib.sha256()
        with open(p, 'rb') as f:
            for chunk in iter(lambda: f.read(1 << 20), b''):
                h.update(chunk)
        if h.hexdigest() != want:
            raise SystemExit(f'{os.path.basename(p)}: sha256 does not match')
    os.makedirs(out_dir, mode=0o755)
    got = set()
    chain = _Chain(sorted(parts, key=os.path.basename))
    with lzma.open(io.BufferedReader(chain)) as xz, tarfile.open(fileobj=xz, mode='r|') as tar:
        for m in tar:
            base = os.path.basename(m.name)
            if base not in PAIR_FILES or not m.isreg() or base in got:
                continue
            src = tar.extractfile(m)
            fd = os.open(os.path.join(out_dir, base), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
            with os.fdopen(fd, 'wb') as dst:
                for chunk in iter(lambda: src.read(1 << 20), b''):
                    dst.write(chunk)
            got.add(base)
    missing = [n for n in PAIR_FILES if n not in got]
    if missing:
        raise SystemExit('the archive has no ' + ', '.join(missing))
    return [os.path.join(out_dir, n) for n in PAIR_FILES]


# ------------------------------------------------------------------------------------------------ main
def fail(error, message, code=1):
    print(json.dumps({'ok': False, 'error': error, 'message': message}))
    return code


def cmd_render(a):
    if not NAME_RE.match(a.watch or ''):
        return fail('bad-name', 'not a character name')
    if not (os.path.isfile(a.dat) and os.path.isfile(a.spr)):
        return fail('no-pair', 'no Tibia.dat / Tibia.spr: run chaos-ctl.sh spectate-pair fetch (docs/ADMIN_APP.md)')
    try:
        snap = read_snapshot(a.snapshot, a.watch, a.max_age)
    except BadSnapshot as e:
        msg = str(e)
        return fail('stale' if msg.startswith('stale') else 'bad-snapshot', msg)
    if not snap['online']:
        return fail('offline', f'{a.watch} is not online', 0)
    items, outfits = load_index(a.dat, a.cache_dir)
    spr = datspr.Spr(a.spr)
    img = render(snap, items, outfits, spr)
    print(json.dumps(answer(snap, img), separators=(',', ':')))
    return 0


def cmd_info(a):
    print(f'dat={a.dat}')
    print(f'spr={a.spr}')
    ok = os.path.isfile(a.dat) and os.path.isfile(a.spr)
    print('pair=' + ('yes' if ok else 'no'))
    if os.path.isfile(a.dat):
        h = hashlib.md5()
        with open(a.dat, 'rb') as f:
            for chunk in iter(lambda: f.read(1 << 20), b''):
                h.update(chunk)
        print(f'dat_md5={h.hexdigest()}')
        print(f'dat_bytes={os.path.getsize(a.dat)}')
    if os.path.isfile(a.spr):
        print(f'spr_bytes={os.path.getsize(a.spr)}')
    idx = 'no'
    if a.cache_dir and os.path.isfile(a.dat):
        try:
            with open(os.path.join(a.cache_dir, 'dat-index.json'), encoding='utf-8') as f:
                idx = 'yes' if json.load(f).get('key') == dat_key(a.dat) else 'old'
        except (OSError, ValueError):
            idx = 'no'
    print(f'index={idx}')
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    r = sub.add_parser('render')
    r.add_argument('--dat', required=True)
    r.add_argument('--spr', required=True)
    r.add_argument('--snapshot', required=True)
    r.add_argument('--watch', required=True)
    r.add_argument('--max-age', type=int, default=5)
    r.add_argument('--cache-dir')
    i = sub.add_parser('index')
    i.add_argument('--dat', required=True)
    i.add_argument('--cache-dir', required=True)
    u = sub.add_parser('unpack-pair')
    u.add_argument('--sums', required=True)
    u.add_argument('--out', required=True)
    u.add_argument('parts', nargs='+')
    n = sub.add_parser('info')
    n.add_argument('--dat', required=True)
    n.add_argument('--spr', required=True)
    n.add_argument('--cache-dir')
    a = ap.parse_args(argv)
    if a.cmd == 'render':
        return cmd_render(a)
    if a.cmd == 'index':
        items, outfits = load_index(a.dat, a.cache_dir)
        print(f'index: {len(items)} items, {len(outfits)} looks')
        return 0
    if a.cmd == 'unpack-pair':
        for p in unpack_pair(a.parts, a.sums, a.out):
            print(p)
        return 0
    return cmd_info(a)


if __name__ == '__main__':
    sys.exit(main())
