"""Tibia .dat / .spr parser + outfit renderer (OTClient-style, several flag-table variants).

Usage:  from datspr import Dat, Spr, render_outfit
Variants are auto-detected by trial parse (a variant is accepted only when it consumes the file exactly).
"""
import struct, mmap, itertools
import numpy as np
from PIL import Image

# --- flag tables: file byte -> (name, data-kind)
# data kinds: None, 'u16', 'u16x2', 'market'
def _tab(names):
    return {i: n for i, n in enumerate(names) if n}

_DATA = {'ground': 'u16', 'writable': 'u16', 'writableonce': 'u16', 'light': 'u16x2',
         'displacement': 'u16x2', 'elevation': 'u16', 'minimap': 'u16', 'lenshelp': 'u16',
         'cloth': 'u16', 'market': 'market', 'defaultaction': 'u16'}

_COMMON = ['ground', 'clip', 'bottom', 'top', 'container', 'stackable', 'forceuse', 'multiuse',
           'writable', 'writableonce', 'fluid', 'splash', 'notwalkable', 'notmoveable',
           'blockmissile', 'blockpath']
_AFTER = ['pickupable', 'hangable', 'hookS', 'hookE', 'rotateable', 'light', 'donthide',
          'translucent', 'displacement', 'elevation', 'lying', 'animateAlways', 'minimap',
          'lenshelp', 'fullground', 'look', 'cloth', 'market']
# "old"  (<=10.0x): 16 pickupable ... 33 market ; 34 usable(no data) ; 0xFF end
TABLE_OLD = _tab(_COMMON + _AFTER + ['usable'])
# "new" (>=10.10, includes 10.98): 16 nomoveanim, 17.. shifted +1, 35 defaultaction(u16), 36.. no data
TABLE_NEW = _tab(_COMMON + ['nomoveanim'] + _AFTER + ['defaultaction', 'wrappable', 'unwrappable', 'topeffect'])
TABLE_NEW[254] = 'usable'
TABLE_OLD[254] = 'usable'
TABLES = {'old': TABLE_OLD, 'new': TABLE_NEW}


# extra (custom) flag bytes found in donor-style dats: byte -> data kind
DEFAULT_EXTRA = {39: 'b16', 41: None, 42: 'c16', 43: None, 46: 'u16x2', 62: 'b16'}


class ParseError(Exception):
    pass


class Thing:
    __slots__ = ('id', 'flags', 'w', 'h', 'exact', 'layers', 'px', 'py', 'pz', 'phases',
                 'anim', 'sprites', 'raw', 'cat', 'extras', 'spr_pos', 'u32', 'attr_end', 'groups')

    def __repr__(self):
        return f'<Thing {self.cat}{self.id} {self.w}x{self.h} L{self.layers} P{self.px}{self.py}{self.pz} F{self.phases}>'


class Dat:
    CATS = ('item', 'outfit', 'effect', 'missile')

    def __init__(self, path_or_bytes, variant=None, extra=None):
        self.extra = dict(DEFAULT_EXTRA if extra is None else extra)
        d = open(path_or_bytes, 'rb').read() if isinstance(path_or_bytes, str) else bytes(path_or_bytes)
        self.data = d
        self.signature, ni, no, ne, nm = struct.unpack_from('<IHHHH', d, 0)
        self.counts = (ni, no, ne, nm)
        self.variant = None
        opts = [variant] if variant else [
            (t, a, u, True, fg) for t in ('new', 'old') for a in (True, False) for u in (True, False) for fg in (True, False)]
        err = None
        for v in opts:
            try:
                self._parse(*v)
                self.variant = v
                break
            except (ParseError, struct.error, IndexError) as e:
                err = e
        if self.variant is None:
            raise ParseError(f'no variant parsed this dat (sig {self.signature:#x}): {err}')

    # variant = (table, animator, u32sprites, patternZ, outfit_frame_groups)
    def _parse(self, table, animator, u32, pz_present, fg=False):
        d = self.data
        tab = TABLES[table]
        kinds = dict(_DATA)
        tab = dict(tab)
        for b, k in self.extra.items():
            tab[b] = f'x{b}'; kinds[f'x{b}'] = k
        pos = 12
        ni, no, ne, nm = self.counts
        cats = []
        first = {'item': 100, 'outfit': 1, 'effect': 1, 'missile': 1}
        maxspr = 0
        for cat, n in zip(self.CATS, (ni - 99, no, ne, nm)):   # items counted from 100: header count = max id
            lst = []
            for i in range(n):
                t = Thing()
                t.cat = cat[0]
                t.id = first[cat] + i
                start = pos
                flags = {}
                extras = []
                spr_pos = []
                while True:
                    b0 = pos
                    b = d[pos]; pos += 1
                    if b == 0xFF:
                        t.attr_end = b0   # offset of the 0xFF that ends the flag list
                        break
                    nm_ = tab.get(b)
                    if b in self.extra:
                        extras_pending = b0
                    else:
                        extras_pending = None
                    if nm_ is None:
                        raise ParseError(f'unknown flag {b} at {pos-1} ({cat}{t.id})')
                    kind = kinds.get(nm_)
                    if kind is None:
                        flags[nm_] = True
                    elif kind == 'u16':
                        flags[nm_] = struct.unpack_from('<H', d, pos)[0]; pos += 2
                    elif kind == 'u16x2':
                        flags[nm_] = struct.unpack_from('<HH', d, pos); pos += 4
                    elif isinstance(kind, str) and kind[0] == 'b':
                        n_ = int(kind[1:]); flags[nm_] = d[pos:pos + n_]; pos += n_
                    elif kind == 'c16':
                        n_ = d[pos]; pos += 1; flags[nm_] = d[pos:pos + 16 * n_]; pos += 16 * n_
                    elif kind == 'market':
                        cat_, trade, show, ln = struct.unpack_from('<HHHH', d, pos); pos += 8
                        if ln > 200:
                            raise ParseError('market name len')
                        pos += ln
                        pos += 4
                        flags[nm_] = (cat_, trade, show)
                    if extras_pending is not None:
                        extras.append((b0, pos))
                t.flags = flags
                t.extras = extras
                t.spr_pos = spr_pos
                t.u32 = u32
                ngroups = 1
                groups = []
                if fg and cat == 'outfit':
                    ngroups = d[pos]; pos += 1
                    if not 1 <= ngroups <= 2:
                        raise ParseError('bad group count')
                for gi in range(ngroups):
                    if fg and cat == 'outfit':
                        pos += 1   # group type
                    w, h = d[pos], d[pos + 1]; pos += 2
                    if w == 0 or h == 0 or w > 16 or h > 16:
                        raise ParseError(f'bad size {w}x{h} ({cat}{t.id})')
                    exact = 32
                    if w > 1 or h > 1:
                        exact = d[pos]; pos += 1
                    layers, px, py = d[pos], d[pos + 1], d[pos + 2]; pos += 3
                    pz = 1
                    if pz_present:
                        pz = d[pos]; pos += 1
                    ph = d[pos]; pos += 1
                    if not (1 <= layers <= 8 and 1 <= px <= 32 and 1 <= py <= 32 and 1 <= pz <= 16 and 1 <= ph <= 255):
                        raise ParseError(f'bad dims ({cat}{t.id}) L{layers} {px}{py}{pz} F{ph}')
                    t.anim = None
                    if animator and ph > 1:
                        asyn = d[pos]; loop = struct.unpack_from('<i', d, pos + 1)[0]; sp = struct.unpack_from('<b', d, pos + 5)[0]
                        pos += 6
                        durs = struct.unpack_from('<' + 'II' * ph, d, pos); pos += 8 * ph
                        t.anim = (asyn, loop, sp, durs)
                    ns = w * h * layers * px * py * pz * ph
                    if ns > 100000:
                        raise ParseError('too many sprites')
                    spr_pos.append((pos, ns))
                    if u32:
                        sp_ = struct.unpack_from(f'<{ns}I', d, pos); pos += 4 * ns
                    else:
                        sp_ = struct.unpack_from(f'<{ns}H', d, pos); pos += 2 * ns
                    if gi == 0:
                        g0 = (w, h, exact, layers, px, py, pz, ph, sp_)
                    groups.append((w, h, exact, layers, px, py, pz, ph, sp_, t.anim))
                w, h, exact, layers, px, py, pz, ph, sp_ = g0
                # every frame group (outfits of a dat with idle / moving groups have two): (w, h, exact, layers, px,
                # py, pz, phases, sprites, anim); the attributes above are group 0's, t.anim the last group's
                t.groups = groups
                t.w, t.h, t.exact, t.layers, t.px, t.py, t.pz, t.phases = w, h, exact, layers, px, py, pz, ph
                t.sprites = sp_
                t.raw = (start, pos)
                if sp_:
                    maxspr = max(maxspr, max(sp_))
                lst.append(t)
                self._dbg = (cat, t, pos)
            cats.append(lst)
        if pos != len(d):
            raise ParseError(f'trailing bytes: parsed {pos} of {len(d)}')
        self.items, self.outfits, self.effects, self.missiles = cats
        self.max_sprite = maxspr

    def outfit(self, lookType):
        if 1 <= lookType <= len(self.outfits):
            return self.outfits[lookType - 1]
        return None


class Spr:
    def __init__(self, path, alpha=None, u32count=None):
        self.f = open(path, 'rb')
        self.m = mmap.mmap(self.f.fileno(), 0, access=mmap.ACCESS_READ)
        m = self.m
        self.signature = struct.unpack_from('<I', m, 0)[0]
        size = len(m)
        # count is u32 for >= 9.6 sprites, u16 before; detect by checking that the table fits and offsets are sane
        cands = [u32count] if u32count is not None else [True, False]
        self.count = None
        for u in cands:
            if u:
                cnt = struct.unpack_from('<I', m, 4)[0]; base = 8
            else:
                cnt = struct.unpack_from('<H', m, 4)[0]; base = 6
            if base + 4 * cnt > size or cnt == 0:
                continue
            offs = np.frombuffer(m, dtype='<u4', count=cnt, offset=base)
            nz = offs[offs > 0]
            if len(nz) and nz.max() < size and nz.min() >= base + 4 * cnt - 8:
                # sanity: first nonzero offset should point to a plausible record
                o = int(nz[0]); sz = struct.unpack_from('<H', m, o + 3)[0]
                if o + 5 + sz <= size:
                    self.count, self.offs, self.u32count = cnt, offs, u
                    break
        if self.count is None:
            raise ParseError('cannot parse spr header')
        self.alpha = alpha if alpha is not None else self._detect_alpha()
        self._cache = {}

    def _detect_alpha(self):
        # try decode first 50 nonempty sprites with 3 and 4 byte pixels; the right one consumes the record exactly
        ok = {False: 0, True: 0}
        n = 0
        for sid in range(1, self.count + 1):
            if not self.offs[sid - 1]:
                continue
            for a in (False, True):
                if self._record_ok(sid, a):
                    ok[a] += 1
            n += 1
            if n >= 60:
                break
        return ok[True] > ok[False]

    def _record_ok(self, sid, a):
        m = self.m; o = int(self.offs[sid - 1]); sz = struct.unpack_from('<H', m, o + 3)[0]
        p = o + 5; end = p + sz; bpp = 4 if a else 3; px = 0
        while p < end:
            if p + 4 > end:
                return False
            t, c = struct.unpack_from('<HH', m, p); p += 4
            px += t + c
            p += c * bpp
            if px > 1024:
                return False
        return p == end

    def sprite(self, sid):
        """returns uint8 array 32x32x4 (RGBA) ; None if empty"""
        if sid == 0 or sid > self.count:
            return None
        o = int(self.offs[sid - 1])
        if not o:
            return None
        c = self._cache.get(sid)
        if c is not None:
            return c
        m = self.m
        sz = struct.unpack_from('<H', m, o + 3)[0]
        p = o + 5; end = p + sz; bpp = 4 if self.alpha else 3
        img = np.zeros((1024, 4), np.uint8)
        px = 0
        while p < end:
            t, cnt = struct.unpack_from('<HH', m, p); p += 4
            px += t
            if cnt:
                raw = np.frombuffer(m, dtype=np.uint8, count=cnt * bpp, offset=p).reshape(cnt, bpp)
                img[px:px + cnt, :3] = raw[:, :3]
                img[px:px + cnt, 3] = raw[:, 3] if self.alpha else 255
                p += cnt * bpp; px += cnt
        a = img.reshape(32, 32, 4)
        if len(self._cache) < 200000:
            self._cache[sid] = a
        return a

    def raw_record(self, sid):
        """(rgba array or None)"""
        return self.sprite(sid)


def sprite_index(t, x=0, y=0, z=0, layer=0, phase=0, ww=0, hh=0):
    return ((((((phase * t.pz + z) * t.py + y) * t.px + x) * t.layers + layer) * t.h + hh) * t.w + ww)


def render_thing(t, spr, direction='south', layers='base', phase=0, z=0):
    """Render first frame; direction 'south' => patternX=2 if px>=4 else 0. layers 'base' (layer 0) or 'all'."""
    x = {'north': 0, 'east': 1, 'south': 2, 'west': 3}[direction] if t.px >= 4 else 0
    W, H = t.w * 32, t.h * 32
    canvas = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    lrange = range(t.layers) if layers == 'all' else range(1)
    for l in lrange:
        for hh in range(t.h):
            for ww in range(t.w):
                sid = t.sprites[sprite_index(t, x, 0, z, l, phase, ww, hh)]
                a = spr.sprite(sid)
                if a is None:
                    continue
                im = Image.fromarray(a, 'RGBA')
                canvas.alpha_composite(im, ((t.w - 1 - ww) * 32, (t.h - 1 - hh) * 32))
    return canvas


def render_outfit(dat, spr, lookType, **kw):
    t = dat.outfit(lookType)
    if t is None:
        return None
    return render_thing(t, spr, **kw)


def phash(img, size=16):
    """perceptual hash of an RGBA PIL image: alpha-composite on grey, crop to bbox, resize, dhash+mean bits"""
    a = np.asarray(img)
    if a.shape[2] == 4:
        al = a[:, :, 3] > 0
    else:
        al = np.ones(a.shape[:2], bool)
    if not al.any():
        return 0
    ys, xs = np.where(al)
    crop = img.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    bg = Image.new('RGBA', crop.size, (128, 128, 128, 255)); bg.alpha_composite(crop)
    g = np.asarray(bg.convert('L').resize((size + 1, size), Image.LANCZOS), dtype=np.float32)
    bits = (g[:, 1:] > g[:, :-1]).flatten()
    m = g[:, :size] > g[:, :size].mean()
    bits = np.concatenate([bits, m.flatten()])
    return int(''.join('1' if b else '0' for b in bits), 2)


def hamming(a, b):
    return bin(a ^ b).count('1')


def _crop(im):
    bb = im.getchannel('A').getbbox()
    return im.crop(bb) if bb else im


def pixdiff(a, b):
    """mean abs RGB diff in [0,1] over the union of opaque pixels of the two images, each cropped to its
    opaque bounding box (translation invariant; different bbox sizes simply mismatch at the edges)."""
    a, b = _crop(a), _crop(b)
    W = max(a.width, b.width); H = max(a.height, b.height)
    ca = Image.new('RGBA', (W, H)); ca.paste(a, (0, 0))
    cb = Image.new('RGBA', (W, H)); cb.paste(b, (0, 0))
    x = np.asarray(ca).astype(np.int16); y = np.asarray(cb).astype(np.int16)
    ma = x[:, :, 3] > 0; mb = y[:, :, 3] > 0
    un = ma | mb
    if not un.any():
        return 0.0
    d = np.abs(x[:, :, :3] - y[:, :, :3]).mean(axis=2)
    d[ma != mb] = 255
    return float(d[un].mean() / 255)


if __name__ == '__main__':
    import sys
    dat = Dat(sys.argv[1])
    print('variant', dat.variant, 'counts', dat.counts, 'parsed outfits', len(dat.outfits), 'max sprite id', dat.max_sprite)
    if len(sys.argv) > 2:
        s = Spr(sys.argv[2])
        print('spr sig %#x count %d u32count %s alpha %s' % (s.signature, s.count, s.u32count, s.alpha))
