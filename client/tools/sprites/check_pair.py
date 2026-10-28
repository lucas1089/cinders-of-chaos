#!/usr/bin/env python3
"""Check a 10.98 Tibia.dat / Tibia.spr pair the way our client reads it, and guard imports (append-only mode).

python3 -I check_pair.py DAT SPR [--rgb] [--aura-looks 2136,2137] [--examples 5] [--verbose]
python3 -I check_pair.py NEW.dat NEW.spr --old OLD.dat OLD.spr [--new-only] [--allow-changed 'outfit:1561,2132-2135']

Pure Python (no numpy, no Pillow), so it runs with -I anywhere. Inputs are only read (the spr is mapped, not copied).
The dat is parsed with the client's own rules for 10.98 (file byte 16 = no-move-animation, 17.. shifted by one, frame
groups for outfits, animator data when an entry has more than one phase, u32 sprite ids), not with datspr.py, so a
flag byte our tools and the client read differently shows up as an error.

Errors (exit 1):
  dat     header counts the client cannot load (65535), a truncated entry, a flag list without its end byte within
          255 attributes, a flag byte that is not a 10.98 byte and not one of ours (CUSTOM_FLAGS: 39 = the rider seat
          of base patch 0034), a size, layer, pattern or phase count of 0, more than 65535 sprites in one thing (the
          client refuses it), frame groups of one outfit with different layers or patterns (the client keeps the last
          group's), an animator start phase outside -1..phases-1 (the client's VALIDATE), a sprite id above the spr
          count, bytes after the last missile.
  spr     a header or offset table that does not fit, an offset into the table or past the end, a record whose pixel
          runs do not decode to at most 32x32 pixels with exactly the record's bytes (truncated or overlong sprite).
  append  (--old) a dat or spr signature that changed, a category or the sprite count that shrank, an old thing whose
          entry bytes changed (unless listed in --allow-changed), an old sprite record whose bytes changed.
Warnings (odd but valid): duplicate or unordered flags, item flags on an outfit, effect or missile (also the usual
sign of a sprite count that does not match an entry's dims, which shifts the next entry), flags our things do not use on that category (rider seat on a
non-outfit, a seat without the negative displacement patch 0034 needs, out-of-range seat values), displacement outside
-128..128, elevation above 64, light colour above 215, async bytes other than 0 / 1, loop counts below -1, phase
durations of 0 ms, with min > max or above 10 s, outfit patterns that are not 4 directions / up to 3 addons / up to 2
mount patterns, missiles that are not 3x3 patterns or above id 254 (the protocol sends one byte), duplicate frame group
types, a non-blank thing with no sprite at all, sprite ids that point at an empty spr slot, outfits with 2 layers whose
second layer is empty or holds art instead of a colour mask (more than 16 shaded colours besides the four template
colours: yellow head, red body, green legs, blue feet; fewer are stray pixels, info); auras use their second layer as the front layer and are left out: --aura-looks, default the client ids of
server/data/XML/chaos_auras*.csv).
Info: blank padding entries (our importers' 1x1 no-sprite entries), slots with sprite 0 (the client draws nothing
there; allowed everywhere), sprites no thing uses, records shared by several sprite ids.

Append-only (--old OLD.dat OLD.spr): the guard every import runs. Every old item, outfit, effect and missile is byte
identical, every old sprite record is byte identical, only new ids were appended. --new-only limits the full checks of
the new pair to the new things and sprites (the old ones were just shown to be unchanged), which keeps it fast on the
live pair. Importers call check_append_only() at the end of a run (import_art_things.py, import_outfits.py,
import_donor_things.py import).
"""
import argparse
import csv
import mmap
import os
import struct
import sys

CATS = ('item', 'outfit', 'effect', 'missile')
FIRST = {'item': 100, 'outfit': 1, 'effect': 1, 'missile': 1}
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..', '..'))

# 10.98 flag table as the client reads it: file byte -> (name, payload kind). Kinds: None (no payload), 'u16',
# 'u16x2', 'disp' (two signed 16-bit values with GameNegativeOffset), 'market', 'bones' (four x, y pairs of i16).
FLAGS_1098 = {
    0: ('ground', 'u16'), 1: ('clip', None), 2: ('bottom', None), 3: ('top', None), 4: ('container', None),
    5: ('stackable', None), 6: ('forceuse', None), 7: ('multiuse', None), 8: ('writable', 'u16'),
    9: ('writableonce', 'u16'), 10: ('fluid', None), 11: ('splash', None), 12: ('notwalkable', None),
    13: ('notmoveable', None), 14: ('blockmissile', None), 15: ('blockpath', None), 16: ('nomoveanim', None),
    17: ('pickupable', None), 18: ('hangable', None), 19: ('hookS', None), 20: ('hookE', None),
    21: ('rotateable', None), 22: ('light', 'u16x2'), 23: ('donthide', None), 24: ('translucent', None),
    25: ('displacement', 'disp'), 26: ('elevation', 'u16'), 27: ('lying', None), 28: ('animateAlways', None),
    29: ('minimap', 'u16'), 30: ('lenshelp', 'u16'), 31: ('fullground', None), 32: ('look', None),
    33: ('cloth', 'u16'), 34: ('market', 'market'), 35: ('defaultaction', 'u16'), 36: ('wrappable', None),
    37: ('unwrappable', None), 38: ('topeffect', None), 254: ('usable', None),
}
# our own bytes on top of 10.98 (client/MANIFEST.md "Rider seat on donor mounts"): 39 = Bones, the rider seat that base
# patch 0034 reads on mounts with a negative displacement.
CUSTOM_FLAGS = {39: ('bones', 'bones')}
PAYLOAD = {None: 0, 'u16': 2, 'u16x2': 4, 'disp': 4, 'bones': 16}
MASK_COLOURS = {0xFFFF00, 0xFF0000, 0x00FF00, 0x0000FF}   # RGB of the template layer: head, body, legs, feet
MAX_STRAY = 16       # a mask with more shaded colours than this holds art (stock masks have a few stray pixels)
NAME_BYTE = {v[0]: b for b, v in FLAGS_1098.items()}
# flags that only mean something on items (map things); on an outfit, effect or missile they hint at a misparse
ITEM_ONLY = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 17, 18, 19, 20, 21, 26, 27, 29, 31, 33, 34, 35, 36, 37}


class Report:
    def __init__(self, examples=5):
        self.items = {'error': {}, 'warning': {}, 'info': {}}
        self.examples = examples
        self.notes = []

    def add(self, level, code, ref, msg=''):
        e = self.items[level].setdefault(code, [0, []])
        e[0] += 1
        e[1].append(f'{ref}{": " + msg if msg else ""}')

    def error(self, code, ref, msg=''):
        self.add('error', code, ref, msg)

    def warn(self, code, ref, msg=''):
        self.add('warning', code, ref, msg)

    def info(self, code, ref, msg=''):
        self.add('info', code, ref, msg)

    def count(self, level):
        return sum(n for n, _ in self.items[level].values())

    @property
    def ok(self):
        return not self.items['error']

    def codes(self, level):
        return set(self.items[level])

    def text(self, verbose=False):
        out = list(self.notes)
        for level in ('error', 'warning', 'info'):
            for code in sorted(self.items[level]):
                n, ex = self.items[level][code]
                shown = ex if verbose else ex[:self.examples]
                more = '' if len(shown) == len(ex) else f' (+{len(ex) - len(shown)} more)'
                out.append(f'{level.upper():7} {code}: {n}')
                for s in shown:
                    out.append(f'        {s}')
                if more:
                    out.append(f'        ...{more}')
        out.append(f'result: {self.count("error")} errors, {self.count("warning")} warnings')
        return '\n'.join(out)


class Group:
    __slots__ = ('gtype', 'w', 'h', 'exact', 'layers', 'px', 'py', 'pz', 'phases', 'anim', 'sprites')


class Thing:
    __slots__ = ('cat', 'id', 'start', 'end', 'flags', 'groups')

    @property
    def ref(self):
        return f'{self.cat} {self.id}'

    def flag(self, name):
        for b, name_, val in self.flags:
            if name_ == name:
                return val
        return None


class DatError(Exception):
    pass


def i16(v):
    return v - 65536 if v >= 32768 else v


def parse_dat(data, rep=None, custom=CUSTOM_FLAGS):
    """-> (signature, counts, {cat: [Thing]}, end offset). Structural errors raise DatError (the client stops loading
    there too); flag-level findings go to rep."""
    n = len(data)
    if n < 12:
        raise DatError(f'dat header truncated ({n} bytes)')
    sig, ni, no, ne, nm = struct.unpack_from('<IHHHH', data, 0)
    counts = (ni, no, ne, nm)
    pos = 12
    things = {}
    table = dict(FLAGS_1098)
    table.update(custom)

    def need(k, what):
        if pos + k > n:
            raise DatError(f'{what}: entry truncated at offset {pos} (needs {k} bytes, file has {n})')

    for cat, cnt in zip(CATS, counts):
        if cnt == 0xFFFF:
            raise DatError(f'{cat} count 65535: the client loads count + 1 entries with a 16-bit id and never stops')
        lst = []
        first = FIRST[cat]
        for tid in range(first, cnt + 1):
            t = Thing()
            t.cat, t.id, t.start = cat, tid, pos
            ref = t.ref
            flags = []
            done = False
            for _ in range(255):
                need(1, ref)
                b = data[pos]; pos += 1
                if b == 0xFF:
                    done = True
                    break
                name, kind = table.get(b, (None, None))
                if name is None:
                    if rep is not None:
                        if 40 <= b <= 43:
                            rep.error('flag-not-1098', ref, f'byte {b} (no payload in the client, not a 10.98 flag)')
                        else:
                            rep.error('flag-unknown', ref, f'byte {b} at offset {pos - 1}')
                    flags.append((b, f'byte{b}', True))
                    continue
                if kind == 'market':
                    need(8, ref)
                    cat_, trade, show, ln = struct.unpack_from('<HHHH', data, pos); pos += 8
                    need(ln + 4, ref)
                    mname = bytes(data[pos:pos + ln]); pos += ln
                    restrict, level = struct.unpack_from('<HH', data, pos); pos += 4
                    val = (cat_, trade, show, mname, restrict, level)
                else:
                    k = PAYLOAD[kind]
                    need(k, ref)
                    if kind is None:
                        val = True
                    elif kind == 'u16':
                        val = struct.unpack_from('<H', data, pos)[0]
                    elif kind == 'u16x2':
                        val = struct.unpack_from('<HH', data, pos)
                    elif kind == 'disp':
                        val = tuple(i16(v) for v in struct.unpack_from('<HH', data, pos))
                    else:
                        val = struct.unpack_from('<8h', data, pos)
                    pos += k
                flags.append((b, name, val))
            if not done:
                raise DatError(f'{ref}: no end byte within 255 flags (the client throws "corrupt data")')
            t.flags = flags
            ngroups = 1
            if cat == 'outfit':
                need(1, ref)
                ngroups = data[pos]; pos += 1
                if ngroups == 0:
                    raise DatError(f'{ref}: 0 frame groups')
            groups = []
            total = 0
            for _ in range(ngroups):
                g = Group()
                g.gtype = 0
                if cat == 'outfit':
                    need(1, ref)
                    g.gtype = data[pos]; pos += 1
                need(2, ref)
                g.w, g.h = data[pos], data[pos + 1]; pos += 2
                g.exact = 32
                if g.w > 1 or g.h > 1:
                    need(1, ref)
                    g.exact = data[pos]; pos += 1
                need(5, ref)
                g.layers, g.px, g.py, g.pz, g.phases = data[pos:pos + 5]; pos += 5
                if 0 in (g.w, g.h, g.layers, g.px, g.py, g.pz, g.phases):
                    raise DatError(f'{ref}: a size, layer, pattern or phase count is 0 '
                                   f'({g.w}x{g.h} L{g.layers} P{g.px}{g.py}{g.pz} F{g.phases}) at offset {pos - 5}')
                g.anim = None
                if g.phases > 1:
                    need(6 + 8 * g.phases, ref)
                    asyn, loop, start = struct.unpack_from('<Bib', data, pos); pos += 6
                    durs = struct.unpack_from('<' + 'II' * g.phases, data, pos); pos += 8 * g.phases
                    g.anim = (asyn, loop, start, durs)
                ns = g.w * g.h * g.layers * g.px * g.py * g.pz * g.phases
                total += ns
                if total > 65535:
                    raise DatError(f'{ref}: more than 65535 sprites (the client throws)')
                need(4 * ns, ref)
                g.sprites = struct.unpack_from(f'<{ns}I', data, pos); pos += 4 * ns
                groups.append(g)
            t.groups = groups
            t.end = pos
            lst.append(t)
        things[cat] = lst
    return sig, counts, things, pos


def is_blank(t):
    return (not t.flags and len(t.groups) == 1 and t.groups[0].w == 1 and t.groups[0].h == 1
            and len(t.groups[0].sprites) == 1 and t.groups[0].sprites[0] == 0)


def sprite_index(g, x=0, y=0, z=0, layer=0, phase=0, ww=0, hh=0):
    return ((((((phase * g.pz + z) * g.py + y) * g.px + x) * g.layers + layer) * g.h + hh) * g.w + ww)


def check_thing(t, rep, spr_count, empty_slots, auras):
    ref = t.ref
    seen = {}
    last = -1
    for b, name, val in t.flags:
        if b in seen:
            rep.warn('flag-duplicate', ref, f'{name} twice (the client keeps the last)')
        seen[b] = val
        if b < last:
            rep.warn('flag-order', ref, f'byte {b} after {last}')
        last = max(last, b)
        if t.cat != 'item' and b in ITEM_ONLY:
            rep.warn('flag-category', ref, f'{name} (an item flag) on a {t.cat}')
        if name == 'displacement':
            if not all(-128 <= v <= 128 for v in val):
                rep.warn('displacement-range', ref, f'{val}')
        elif name == 'elevation' and val > 64:
            rep.warn('elevation-high', ref, f'{val}')
        elif name == 'light':
            if val[1] > 215:
                rep.warn('light-colour', ref, f'colour {val[1]} (8-bit palette is 0..215)')
            if val[0] > 255:
                rep.warn('light-level', ref, f'intensity {val[0]}')
        elif name == 'bones':
            if t.cat != 'outfit':
                rep.warn('seat-not-outfit', ref, 'rider seat (byte 39) on a non-outfit')
            disp = t.flag('displacement')
            if not disp or not (disp[0] < 0 or disp[1] < 0):
                rep.warn('seat-unused', ref, 'rider seat without a negative displacement (base patch 0034 ignores it)')
            if not all(-128 <= v <= 128 for v in val):
                rep.warn('seat-range', ref, f'{val}')
        elif name == 'market':
            if len(val[3]) > 255:
                rep.warn('market-name', ref, f'name of {len(val[3])} bytes')
    gs = t.groups
    if t.cat == 'outfit':
        types = [g.gtype for g in gs]
        if len(set(types)) != len(types) or any(x > 1 for x in types):
            rep.warn('group-types', ref, f'frame group types {types}')
        if len(gs) > 2:
            rep.warn('group-count', ref, f'{len(gs)} frame groups')
        first = gs[0]
        for g in gs[1:]:
            if (g.layers, g.px, g.py, g.pz) != (first.layers, first.px, first.py, first.pz):
                rep.warn('group-mismatch', ref, 'frame groups differ in layers or patterns; the client indexes every '
                         f'group with the last one\'s (L{first.layers} P{first.px}{first.py}{first.pz} vs '
                         f'L{g.layers} P{g.px}{g.py}{g.pz}), so some frames draw the wrong sprites')
            elif (g.w, g.h) != (first.w, first.h):
                rep.info('group-sizes', ref, f'{first.w}x{first.h} and {g.w}x{g.h} (the client pads the smaller)')
    blank = is_blank(t)
    if blank:
        rep.info('blank-entry', ref)
    nonzero = 0
    for gi, g in enumerate(gs):
        gref = ref if len(gs) == 1 else f'{ref} group {gi}'
        if g.w > 8 or g.h > 8:
            rep.warn('size-large', gref, f'{g.w}x{g.h}')
        if (g.w > 1 or g.h > 1) and not (32 <= g.exact <= 32 * max(g.w, g.h)) and g.exact != 255:
            rep.warn('exact-size', gref, f'exact size {g.exact} for {g.w}x{g.h}')
        if t.cat == 'outfit':
            if g.px not in (1, 4, 8):
                # 8: the diagonals after the four directions (client base patch 0160)
                rep.warn('outfit-directions', gref, f'{g.px} x patterns (4 or 8 directions expected)')
            if g.py > 3:
                rep.warn('outfit-addons', gref, f'{g.py} addon patterns')
            if g.pz > 2:
                rep.warn('outfit-mount-patterns', gref, f'{g.pz} z patterns')
            if g.layers > 2:
                rep.warn('outfit-layers', gref, f'{g.layers} layers (the client uses 1 or 2)')
        elif t.cat == 'missile' and (g.px, g.py) != (3, 3):
            rep.warn('missile-patterns', gref, f'{g.px}x{g.py} patterns (3x3 directions expected)')
        if g.anim:
            asyn, loop, start, durs = g.anim
            if asyn not in (0, 1):
                rep.warn('anim-async', gref, f'async byte {asyn}')
            if loop < -1:
                rep.warn('anim-loop', gref, f'loop count {loop}')
            if not -1 <= start < g.phases:
                rep.error('anim-start', gref, f'start phase {start} of {g.phases} (the client refuses it)')
            for p in range(g.phases):
                lo, hi = durs[2 * p], durs[2 * p + 1]
                if hi < lo:
                    rep.warn('anim-min-max', gref, f'phase {p}: min {lo} > max {hi} ms')
                if hi == 0:
                    rep.warn('anim-zero', gref, f'phase {p}: 0 ms')
                if hi > 10000:
                    rep.warn('anim-long', gref, f'phase {p}: {hi} ms')
        for s in g.sprites:
            if s:
                nonzero += 1
                if s > spr_count:
                    rep.error('sprite-range', gref, f'sprite id {s} > spr count {spr_count}')
                elif s in empty_slots:
                    rep.warn('sprite-empty-slot', gref, f'sprite id {s} has no record (draws nothing)')
    zero = sum(len(g.sprites) for g in gs) - nonzero
    if zero and not blank:
        rep.info('sprite-zero-slots', ref, f'{zero} slots with sprite 0')
    if not nonzero and not blank:
        rep.warn('thing-empty', ref, 'no sprite at all')
    if t.cat == 'missile' and t.id > 254:
        rep.warn('missile-id', ref, 'above 254: the 10.98 protocol sends missile ids as one byte')


class SprFile:
    """the spr mapped read-only; offsets read lazily."""

    def __init__(self, path):
        self.path = path
        self.f = open(path, 'rb')
        self.size = os.fstat(self.f.fileno()).st_size
        self.m = mmap.mmap(self.f.fileno(), 0, access=mmap.ACCESS_READ) if self.size else b''
        if self.size < 8:
            raise DatError(f'spr header truncated ({self.size} bytes)')
        self.signature, self.count = struct.unpack_from('<II', self.m, 0)
        if 8 + 4 * self.count > self.size:
            raise DatError(f'spr offset table of {self.count} entries does not fit in {self.size} bytes')
        self.offs = struct.unpack_from(f'<{self.count}I', self.m, 8)

    def record(self, sid):
        """record bytes (header + pixel data) or None for an empty slot; no checks."""
        o = self.offs[sid - 1]
        if not o:
            return None
        ln = self.m[o + 3] | (self.m[o + 4] << 8)
        return self.m[o:o + 5 + ln]

    def close(self):
        if self.size:
            self.m.close()
        self.f.close()


def decode_ok(m, start, end, bpp):
    """True when the pixel runs in m[start:end] decode exactly (client rules) to at most 1024 pixels."""
    p, px = start, 0
    while p < end:
        if end - p < 4:
            return False
        t, c = struct.unpack_from('<HH', m, p)
        p += 4
        px += t
        if px > 1024:
            return False
        px += c
        if px > 1024 or c * bpp > end - p:
            return False
        p += c * bpp
    return True


def detect_alpha(spr, sample=300):
    votes = {3: 0, 4: 0}
    n = 0
    for sid in range(1, spr.count + 1):
        o = spr.offs[sid - 1]
        if not o or o + 5 > spr.size:
            continue
        ln = spr.m[o + 3] | (spr.m[o + 4] << 8)
        if o + 5 + ln > spr.size:
            continue
        for bpp in (3, 4):
            if decode_ok(spr.m, o + 5, o + 5 + ln, bpp):
                votes[bpp] += 1
        n += 1
        if n >= sample:
            break
    return votes[4] >= votes[3]


def check_spr(spr, rep, bpp, sids=None):
    """record checks for sids (default all). Returns the set of empty slots among them."""
    table_end = 8 + 4 * spr.count
    m, size = spr.m, spr.size
    empty = set()
    starts = {}
    rng = range(1, spr.count + 1) if sids is None else sids
    for sid in rng:
        o = spr.offs[sid - 1]
        if not o:
            empty.add(sid)
            continue
        if o < table_end:
            rep.error('spr-offset-table', f'sprite {sid}', f'offset {o} inside the offset table (ends {table_end})')
            continue
        if o + 5 > size:
            rep.error('spr-offset-end', f'sprite {sid}', f'offset {o} past the end ({size})')
            continue
        ln = m[o + 3] | (m[o + 4] << 8)
        if o + 5 + ln > size:
            rep.error('spr-truncated', f'sprite {sid}', f'record of {ln} bytes at {o} runs past the end ({size})')
            continue
        if not decode_ok(m, o + 5, o + 5 + ln, bpp):
            rep.error('spr-bad-runs', f'sprite {sid}', f'pixel runs do not decode to 32x32 within {ln} bytes')
            continue
        if o in starts:
            rep.info('spr-shared-record', f'sprite {sid}', f'same record as sprite {starts[o]}')
        else:
            starts[o] = sid
    return empty


def mask_pixels(spr, sid, bpp):
    """set of RGB ints of the visible pixels of a record."""
    rec = spr.record(sid)
    out = set()
    if rec is None:
        return out
    m = memoryview(rec)
    p, end = 5, len(rec)
    while p + 4 <= end:
        t, c = struct.unpack_from('<HH', m, p)
        p += 4
        chunk = bytes(m[p:p + c * bpp])
        p += c * bpp
        if bpp == 4:
            for v in memoryview(chunk).cast('I'):
                if v >> 24:
                    out.add(((v & 0xFF) << 16) | (v & 0xFF00) | ((v >> 16) & 0xFF))
        else:
            for i in range(0, len(chunk), 3):
                out.add((chunk[i] << 16) | (chunk[i + 1] << 8) | chunk[i + 2])
    return out


def _pure(v):
    return all(((v >> k) & 0xFF) in (0, 0xFF) for k in (0, 8, 16))


def check_masks(outfits, spr, rep, bpp, auras):
    cache = {}
    for t in outfits:
        if t.id in auras:
            continue
        g0 = t.groups[0]
        if g0.layers != 2:
            continue
        colours = set()
        for g in t.groups:
            if g.layers < 2:
                continue
            for ph in range(g.phases):
                for z in range(g.pz):
                    for y in range(g.py):
                        for x in range(g.px):
                            for hh in range(g.h):
                                for ww in range(g.w):
                                    s = g.sprites[sprite_index(g, x, y, z, 1, ph, ww, hh)]
                                    if not s or s > spr.count:
                                        continue
                                    if s not in cache:
                                        cache[s] = mask_pixels(spr, s, bpp)
                                    colours |= cache[s]
        odd = colours - MASK_COLOURS
        if not colours:
            rep.warn('mask-empty', t.ref, '2 layers but the second (colour mask) is empty')
        elif sum(1 for v in odd if not _pure(v)) > MAX_STRAY:
            n = sum(1 for v in odd if not _pure(v))
            rep.warn('mask-not-mask', t.ref, f'second layer holds art ({n} shaded colours), not a colour mask: an '
                     'aura or wings look missing from --aura-looks, or a broken mask')
        elif any(not _pure(v) for v in odd):
            n = sum(1 for v in odd if not _pure(v))
            rep.info('mask-stray-colours', t.ref, f'{n} shaded colour(s) in the colour mask (stray pixels, untinted)')
        elif odd:
            rep.info('mask-odd-colours', t.ref, 'pure colours besides the four template colours: '
                     + ' '.join(f'{v:06x}' for v in sorted(odd)))


def default_auras():
    out = set()
    d = os.path.join(REPO, 'server', 'data', 'XML')
    if os.path.isdir(d):
        for fn in sorted(os.listdir(d)):
            if fn.startswith('chaos_auras') and fn.endswith('.csv'):
                with open(os.path.join(d, fn), newline='', encoding='utf-8') as f:
                    for row in csv.DictReader(f):
                        try:
                            out.add(int(row['client_id']))
                        except (KeyError, ValueError, TypeError):
                            pass
    return out


def parse_allow(spec):
    """'outfit:1561,2132-2135;item:100' -> {(cat, id)}"""
    out = set()
    for part in (spec or '').split(';'):
        part = part.strip()
        if not part:
            continue
        cat, ids = part.split(':', 1)
        if cat not in CATS:
            raise SystemExit(f'--allow-changed: unknown category {cat!r}')
        for r in ids.split(','):
            r = r.strip()
            if '-' in r:
                a, b = r.split('-')
                out.update((cat, i) for i in range(int(a), int(b) + 1))
            elif r:
                out.add((cat, int(r)))
    return out


def check(dat_path, spr_path, old=None, new_only=False, allow_changed=(), auras=None, rgb=None, examples=5):
    """Full check of a pair (optionally append-only against old=(dat, spr)). Returns a Report."""
    rep = Report(examples)
    auras = default_auras() if auras is None else set(auras)
    with open(dat_path, 'rb') as f:
        data = f.read()
    try:
        spr = SprFile(spr_path)
    except DatError as e:
        rep.error('spr-header', spr_path, str(e))
        return rep
    try:
        sig, counts, things, end = parse_dat(data, rep)
    except DatError as e:
        rep.error('dat-structure', dat_path, str(e))
        spr.close()
        return rep
    if end != len(data):
        rep.error('dat-trailing', dat_path, f'{len(data) - end} bytes after the last missile')
    bpp = (3 if rgb else 4) if rgb is not None else (4 if detect_alpha(spr) else 3)
    rep.notes.append(f'dat {os.path.basename(dat_path)}: signature {sig:#x}, items {counts[0]}, outfits {counts[1]}, '
                     f'effects {counts[2]}, missiles {counts[3]}, {len(data)} bytes')
    rep.notes.append(f'spr {os.path.basename(spr_path)}: signature {spr.signature:#x}, {spr.count} sprites, '
                     f'{"alpha" if bpp == 4 else "RGB"} records, {spr.size} bytes')

    old_counts, old_spr_count, old_ids = None, 0, None
    if old:
        old_counts, old_spr_count, old_ids = append_only(old, data, sig, counts, things, spr, rep, allow_changed)
    new_sids = None
    if new_only and old_counts is not None:
        new_sids = range(old_spr_count + 1, spr.count + 1)
    empty = check_spr(spr, rep, bpp, new_sids)
    if new_sids is not None:
        empty |= {sid for sid in range(1, old_spr_count + 1) if not spr.offs[sid - 1]}
    used = set()
    for cat in CATS:
        for t in things[cat]:
            if new_only and old_ids is not None and (cat, t.id) in old_ids:
                continue
            check_thing(t, rep, spr.count, empty, auras)
            for g in t.groups:
                used.update(g.sprites)
    outs = [t for t in things['outfit'] if not (new_only and old_ids is not None and ('outfit', t.id) in old_ids)]
    check_masks(outs, spr, rep, bpp, auras)
    if not new_only:
        used_records = {s for s in used if 0 < s <= spr.count} - empty
        unused = spr.count - len(empty) - len(used_records)
        if unused > 0:
            rep.info('spr-unused', spr_path, f'{unused} sprite records no thing uses')
        if empty:
            rep.info('spr-empty-slots', spr_path, f'{len(empty)} sprite ids without a record')
    spr.close()
    return rep


def append_only(old, data, sig, counts, things, spr, rep, allow_changed):
    odat_path, ospr_path = old
    with open(odat_path, 'rb') as f:
        od = f.read()
    try:
        osig, ocounts, othings, _ = parse_dat(od, None)
    except DatError as e:
        rep.error('append-old-dat', odat_path, str(e))
        return None, 0, None
    rep.notes.append(f'append-only against {odat_path} ({ocounts[0]} items, {ocounts[1]} outfits, '
                     f'{ocounts[2]} effects, {ocounts[3]} missiles)')
    if osig != sig:
        rep.error('append-dat-signature', 'dat', f'{osig:#x} -> {sig:#x}')
    ids = set()
    for cat, oc, nc in zip(CATS, ocounts, counts):
        if nc < oc:
            rep.error('append-count', cat, f'{oc} -> {nc}: things were removed')
        new_list = things[cat]
        for ot in othings[cat]:
            ids.add((cat, ot.id))
            k = ot.id - FIRST[cat]
            if k >= len(new_list):
                continue
            nt = new_list[k]
            if od[ot.start:ot.end] != data[nt.start:nt.end]:
                if (cat, ot.id) in allow_changed:
                    rep.info('append-allowed-change', ot.ref)
                else:
                    rep.error('append-thing-changed', ot.ref, 'entry bytes differ from the old pair')
    try:
        ospr = SprFile(ospr_path)
    except DatError as e:
        rep.error('append-old-spr', ospr_path, str(e))
        return ocounts, 0, ids
    if ospr.signature != spr.signature:
        rep.error('append-spr-signature', 'spr', f'{ospr.signature:#x} -> {spr.signature:#x}')
    if spr.count < ospr.count:
        rep.error('append-spr-count', 'spr', f'{ospr.count} -> {spr.count}: sprites were removed')
    changed = 0
    for sid in range(1, min(ospr.count, spr.count) + 1):
        a, b = ospr.offs[sid - 1], spr.offs[sid - 1]
        if (not a) != (not b):
            ok = False
        elif not a:
            ok = True
        else:
            if a + 5 > ospr.size or b + 5 > spr.size:
                ok = False
            else:
                la = ospr.m[a + 3] | (ospr.m[a + 4] << 8)
                lb = spr.m[b + 3] | (spr.m[b + 4] << 8)
                ok = la == lb and ospr.m[a:a + 5 + la] == spr.m[b:b + 5 + lb]
        if not ok:
            changed += 1
            rep.error('append-sprite-changed', f'sprite {sid}', 'record differs from the old pair')
    n_old = ospr.count
    ospr.close()
    rep.notes.append(f'append-only: {sum(len(v) for v in othings.values())} old things and {n_old} old sprites compared; '
                     f'new: ' + ', '.join(f'{c - o} {cat}s' for cat, o, c in zip(CATS, ocounts, counts))
                     + f', {spr.count - n_old} sprites')
    return ocounts, n_old, ids


def check_append_only(old_dat, old_spr, new_dat, new_spr, allow_changed=(), log=print):
    """Importer hook: append-only guard plus the checks of the new things and sprites. Exits on errors."""
    rep = check(new_dat, new_spr, old=(old_dat, old_spr), new_only=True, allow_changed=set(allow_changed))
    if not rep.ok:
        log(rep.text())
        raise SystemExit(f'check_pair: {new_dat} / {new_spr} is not an append-only, valid extension of the input pair')
    log(f'check_pair: append-only guard passed ({rep.count("warning")} warnings in the new things'
        + (f': {", ".join(sorted(rep.codes("warning")))}' if rep.count('warning') else '') + ')')
    return rep


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('dat'); ap.add_argument('spr')
    ap.add_argument('--old', nargs=2, metavar=('OLD_DAT', 'OLD_SPR'), help='append-only check against this pair')
    ap.add_argument('--new-only', action='store_true', help='with --old: check only the new things and sprites')
    ap.add_argument('--allow-changed', default='', help="with --old: old things that may change, e.g. 'outfit:1561,2132-2135'")
    ap.add_argument('--aura-looks', default=None, help='outfit ids whose second layer is a front layer (default: '
                    'client ids of server/data/XML/chaos_auras*.csv)')
    ap.add_argument('--rgb', action='store_true', default=None, help='3-byte pixels (default: detected)')
    ap.add_argument('--examples', type=int, default=5, help='examples shown per finding')
    ap.add_argument('--verbose', action='store_true', help='show every finding')
    a = ap.parse_args(argv)
    auras = None if a.aura_looks is None else {int(x) for x in a.aura_looks.split(',') if x.strip()}
    rep = check(a.dat, a.spr, old=a.old, new_only=a.new_only, allow_changed=parse_allow(a.allow_changed),
                auras=auras, rgb=a.rgb, examples=a.examples)
    print(rep.text(a.verbose))
    return 0 if rep.ok else 1


if __name__ == '__main__':
    sys.exit(main())
