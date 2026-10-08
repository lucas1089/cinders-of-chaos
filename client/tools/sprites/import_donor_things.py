#!/usr/bin/env python3
"""Donor things -> our 10.98 format: build a library pair from a donor, or append chosen things to a live pair.

Sources (--source, default by the dat signature): donor-b (donor B, the 64px donor, own flag table, see below),
donor-c (a 10.98 extended dat whose items carry extra flag bytes without payload, which are stripped, and repeated
flags, of which the last is kept as the client does; frame groups without sprites are dropped; --extra-items
reads its extended-items file, items numbered after the dat's last item) and library (a pair this tool wrote).

Two commands:

  library  python3 -I import_donor_things.py library --src-dat DONOR.dat --src-spr DONOR.spr --ours-spr OUR.spr \
                  --out-dir LIB [--sheets DIR] [--source donor-c] [--extra-items F] [--named 'outfit:4080-4159']
           Converts every meaningful donor thing (outfits, items, effects, missiles) into a separate 10.98 pair with fresh
           numbering (items 100.., outfits / effects / missiles 1..), in donor order.  Skipped: entries without a single
           visible pixel, things whose every visible sprite already exists (pixel identical) in OUR.spr, exact
           duplicates of a thing kept earlier (same sizes, flags and sprite pixels), the donor's editor marker tiles
           (donor flag 9), and things our parser cannot read (wider or taller than 16 tiles, more than 8 layers).
           Identical sprites are stored once.  Writes LIB/Tibia.dat, LIB/Tibia.spr, LIB/catalogue.csv (one row per
           library thing; --named rows are tagged "named character") and LIB/skipped.csv; --sheets draws contact
           sheets with the library ids printed.

  import   python3 -I import_donor_things.py import --src-dat LIB/Tibia.dat --src-spr LIB/Tibia.spr \
                  --ours-dat Tibia.dat --ours-spr Tibia.spr --select SELECTION.csv --out-dir OUT \
                  [--first-item 28000] [--server-id-offset 12000] [--expect outfit=1511,effect=429,missile=126]
           Appends the selected things (rows category,src_id[,name,purpose] of SELECTION.csv; the source is the library
           or the raw donor pair, detected by the dat signature) to COPIES of our pair: new ids follow the last existing
           id of each category, in selection order.  --first-item pads the item list with blank entries so the first new
           item gets that id (keeps item ids stable when other tools append items before this one; must be above the
           last existing item).  Sprite records already present in our spr (same record bytes) are reused, the others
           are appended once.  Writes OUT/Tibia.dat, OUT/Tibia.spr, OUT/donor_import.csv (category, source id -> new id,
           server id for items) and OUT/donor_items.csv (the items.otb / items.xml manifest that
           server/tools/install_donor_items.py installs; server id = client id + --server-id-offset).
           Missile ids must stay <= 254 (the 10.98 protocol sends them as one byte): a selection above that stops.

Donor B dat layout (signature 0x542535F9): the 10.98 layout (u32 header counts after the signature, flags then 0xFF,
frame groups for outfits only, width, height, exact size when >1x1, layers, patterns x/y/z, phases, animator when
phases > 1, u32 sprite ids).  Its flag bytes are the 10.98 table with a reduced set: 0 ground (u16 speed), 1 clip,
2 bottom, 3 top, 4 container, 5 stackable, 13 notmoveable, 14 blockmissile (items), 15 blockpath, 16 not walkable (always
together with 15; written as our notwalkable), 17 pickupable, 22 light (u16 x2), 25 displacement (SIGNED i16 x2: big
creatures are centred with negative offsets), 26 elevation, 29 minimap, 31 fullground; stripped: 9 (u16, editor marker
tiles), 23, 24, 35 (u16), negative elevations, and on outfits / effects / missiles every flag but light and
displacement.  The spr is our record layout (alpha, colour key, u16 size, runs of u16 transparent / u16 coloured pixels,
32x32), so records are copied byte for byte.
Negative displacements need the client feature GameNegativeOffset (enabled for 1098 in base-patches/0006-features.patch);
our own things only use 0..32, which read the same signed or unsigned.

Verification (always): the output dat is re-parsed by datspr (same variant as ours) and by this tool's parser to the
last byte; every converted thing has the expected flag bytes and the source's groups, sizes, patterns, phases and
animator; every sprite slot decodes pixel-identical to the source slot (all groups, phases, directions, addons, layers);
composed frames are compared for all frames of every 25th thing and the first frame of all others; for import, every
old dat entry is byte-identical and 3000 sampled old sprites are unchanged.  Deterministic: same inputs, same bytes.
"""
import argparse
import csv
import hashlib
import os
import random
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402
from datspr import Dat, Spr, TABLE_NEW, _DATA, DEFAULT_EXTRA  # noqa: E402

DONOR_SIG = 0x542535F9
CATS = ('item', 'outfit', 'effect', 'missile')
FIRST = {'item': 100, 'outfit': 1, 'effect': 1, 'missile': 1}
NEW_BYTE = {name: b for b, name in TABLE_NEW.items()}

# payload length per flag byte; 'm' market, 'c' count + 16 bytes per entry
_KLEN = {None: 0, 'u16': 2, 'u16x2': 4, 'market': 'm'}
OUR_KINDS = {b: _KLEN[_DATA.get(n)] for b, n in TABLE_NEW.items()}
for _b, _k in DEFAULT_EXTRA.items():
    OUR_KINDS[_b] = {None: 0, 'u16x2': 4, 'c16': 'c'}.get(_k, int(_k[1:]) if _k and _k[0] == 'b' else 0)
DONOR_KINDS = {0: 2, 9: 2, 22: 4, 25: 4, 26: 2, 29: 2, 35: 2,
               1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 13: 0, 14: 0, 15: 0, 16: 0, 17: 0, 23: 0, 24: 0, 31: 0}
DONOR_MAP = {0: 'ground', 1: 'clip', 2: 'bottom', 3: 'top', 4: 'container', 5: 'stackable', 13: 'notmoveable',
             14: 'blockmissile', 15: 'blockpath', 16: 'notwalkable', 17: 'pickupable', 22: 'light', 25: 'displacement',
             26: 'elevation', 29: 'minimap', 31: 'fullground'}
NON_ITEM_KEEP = {'light', 'displacement'}
# donor C (a 10.98 dat whose items also carry flag bytes outside the table, without payload): 10.98 payload lengths
DONORC_KINDS = {0: 2, 8: 2, 9: 2, 22: 4, 25: 4, 26: 2, 29: 2, 30: 2, 33: 2, 34: 'm', 35: 2}
MAX_WH, MAX_LAYERS = 16, 8                      # datspr's bounds (our other tools must still read the pair)


class ParseError(Exception):
    pass


# ============================================================================================== dat reading / writing
class Thing:
    __slots__ = ('cat', 'id', 'flags', 'groups', 'raw')


def parse_thing(data, pos, cat, tid, kinds, default=None):
    """one entry at pos -> (Thing, end).  A flag byte missing from kinds raises, or carries `default` payload bytes."""
    t = Thing(); t.cat = cat; t.id = tid; t.flags = []; start = pos
    while True:
        b = data[pos]; pos += 1
        if b == 0xFF:
            break
        k = kinds.get(b, default)
        if k is None:
            raise ParseError(f'unknown flag {b} at {pos - 1} ({cat} {tid})')
        if k == 'm':
            k = 8 + struct.unpack_from('<H', data, pos + 6)[0] + 4
        elif k == 'c':
            k = 1 + 16 * data[pos]
        t.flags.append((b, bytes(data[pos:pos + k]))); pos += k
    ng = 1
    if cat == 'outfit':
        ng = data[pos]; pos += 1
    t.groups = []
    for _ in range(ng):
        g = {'gtype': 0}
        if cat == 'outfit':
            g['gtype'] = data[pos]; pos += 1
        g['w'], g['h'] = data[pos], data[pos + 1]; pos += 2
        g['exact'] = 32
        if g['w'] > 1 or g['h'] > 1:
            g['exact'] = data[pos]; pos += 1
        g['layers'], g['px'], g['py'], g['pz'], g['phases'] = data[pos:pos + 5]; pos += 5
        g['anim'] = None
        if g['phases'] > 1:
            head = struct.unpack_from('<Bib', data, pos); pos += 6
            durs = struct.unpack_from('<%dI' % (2 * g['phases']), data, pos); pos += 8 * g['phases']
            g['anim'] = (head, durs)
        ns = g['w'] * g['h'] * g['layers'] * g['px'] * g['py'] * g['pz'] * g['phases']
        g['sprites'] = struct.unpack_from('<%dI' % ns, data, pos); pos += 4 * ns
        t.groups.append(g)
    t.raw = (start, pos)
    return t, pos


def parse_dat(data, kinds, default=None):
    """things of a 10.98-layout dat (outfits with frame groups, u32 sprites, animator); must end exactly at EOF.
    flags: [(byte, payload bytes)]; groups: [dict]; raw: (start, end)."""
    sig, ni, no, ne, nm = struct.unpack_from('<IHHHH', data, 0)
    pos, out = 12, {c: [] for c in CATS}
    for cat, n in zip(CATS, (ni - 99, no, ne, nm)):
        for i in range(n):
            t, pos = parse_thing(data, pos, cat, FIRST[cat] + i, kinds, default)
            out[cat].append(t)
    if pos != len(data):
        raise ParseError(f'parse ended at {pos}, file has {len(data)} bytes')
    return out


def parse_extra_items(path, first_id, kinds, default):
    """an extended-items file (magic TEXI, u32 version, u32 count, then u32 length + item entry per item); the items
    are numbered from first_id."""
    data = open(path, 'rb').read()
    magic, _ver, n = struct.unpack_from('<4sII', data, 0)
    if magic != b'TEXI':
        raise ParseError('not an extended-items file')
    pos, out = 12, []
    for i in range(n):
        ln = struct.unpack_from('<I', data, pos)[0]; pos += 4
        t, end = parse_thing(data, pos, 'item', first_id + i, kinds, default)
        if end != pos + ln:
            raise ParseError(f'extended item {i}: entry length {ln}, parsed {end - pos}')
        pos = end
        out.append(t)
    if pos != len(data):
        raise ParseError('extended-items file: trailing bytes')
    return out


def flag_bytes(flags):
    return b''.join(bytes([b]) + v for b, v in flags)


def entry_bytes(cat, flags, groups, smap=None):
    """our 10.98 entry: flags, 0xFF, [group count], per group: [type], w, h, [exact], layers, px, py, pz, phases,
    [animator], u32 sprite ids (mapped through smap when given)."""
    e = bytearray(flag_bytes(flags)) + b'\xff'
    if cat == 'outfit':
        e.append(len(groups))
    for g in groups:
        if cat == 'outfit':
            e.append(g['gtype'])
        e += bytes([g['w'], g['h']])
        if g['w'] > 1 or g['h'] > 1:
            e.append(g['exact'])
        e += bytes([g['layers'], g['px'], g['py'], g['pz'], g['phases']])
        if g['phases'] > 1:
            head, durs = g['anim']
            e += struct.pack('<Bib', *head) + struct.pack('<%dI' % len(durs), *durs)
        sp = g['sprites'] if smap is None else [smap[s] for s in g['sprites']]
        e += struct.pack('<%dI' % len(sp), *sp)
    return bytes(e)


BLANK_ITEM = entry_bytes('item', [], [{'gtype': 0, 'w': 1, 'h': 1, 'exact': 32, 'layers': 1, 'px': 1, 'py': 1, 'pz': 1,
                                       'phases': 1, 'anim': None, 'sprites': (0,)}])


def convert_flags(t, profile):
    """(our flag list, stripped names).  Library things are already in our table and pass unchanged."""
    if profile == 'library':
        return list(t.flags), []
    out, stripped = [], []
    if profile == 'donor-c':
        last = {}
        for b, v in t.flags:                          # a repeated flag: the client keeps the last value read
            if b not in TABLE_NEW:
                stripped.append(f'd{b}')
            else:
                if b in last:
                    stripped.append(f'dup{b}')
                last[b] = v
        return sorted(last.items()), stripped
    for b, v in t.flags:
        name = DONOR_MAP.get(b)
        if name is None:
            stripped.append(f'd{b}'); continue
        if t.cat != 'item' and name not in NON_ITEM_KEEP:
            stripped.append(name); continue
        if name == 'elevation' and struct.unpack('<h', v)[0] < 0:
            stripped.append('elevation<0'); continue
        out.append((NEW_BYTE[name], v))
    return sorted(out), stripped


def drop_empty_groups(t):
    """remove frame groups with a zero dimension (no sprites; the client draws nothing for them, our parser refuses
    them); returns the number removed.  An outfit keeps at least one group."""
    keep = [g for g in t.groups if g['w'] * g['h'] * g['layers'] * g['px'] * g['py'] * g['pz'] * g['phases']]
    n = len(t.groups) - len(keep)
    if n and keep:
        t.groups = keep
        return n
    return 0


def flag_names(flags):
    return [TABLE_NEW.get(b, f'x{b}') for b, _ in flags]


# ============================================================================================== sprites
def record(spr, sid):
    """raw record bytes of a sprite (None when the slot is empty or has no visible pixel)."""
    if sid == 0 or sid > spr.count or not spr.offs[sid - 1]:
        return None
    a = spr.sprite(sid)
    if a is None or not a[:, :, 3].any():
        return None
    if spr._record_ok(sid, spr.alpha):
        o = int(spr.offs[sid - 1]); ln = struct.unpack_from('<H', spr.m, o + 3)[0]
        return bytes(spr.m[o:o + 5 + ln])
    from gen_effects import encode_sprite
    return encode_sprite(a)


def pixel_key(a):
    """exact pixel identity of a decoded sprite (colour of fully transparent pixels ignored)."""
    a = a.copy(); a[a[:, :, 3] == 0] = 0
    return hashlib.md5(a.tobytes()).digest()


def spr_pixel_keys(spr, log=None):
    keys = set()
    for sid in range(1, spr.count + 1):
        if spr.offs[sid - 1]:
            a = spr.sprite(sid)
            if a is not None and a[:, :, 3].any():
                keys.add(pixel_key(a))
        if len(spr._cache) > 20000:
            spr._cache.clear()
        if sid % 100000 == 0:
            if log:
                log(f'  pixel keys: {sid}/{spr.count}')
    spr._cache.clear()
    return keys


def write_spr(path, signature, base_m, base_count, newrecs):
    """our spr layout: u32 signature, u32 count, u32 offsets, records.  With a base spr the old table grows by the new
    entries, old records are copied (shifted by 4 * new count) and the new records appended."""
    nn = len(newrecs)
    if base_m is not None:
        offs = np.frombuffer(base_m, dtype='<u4', count=base_count, offset=8).astype('<u8')
        offs[offs > 0] += 4 * nn
        cur = len(base_m) + 4 * nn
    else:
        offs = np.zeros(0, '<u8'); cur = 8 + 4 * nn
    new_offs = []
    for rec in newrecs:
        new_offs.append(cur); cur += len(rec)
    if cur >= 1 << 32:
        raise SystemExit('spr would exceed 4 GB')
    table = np.concatenate([offs, np.array(new_offs, dtype='<u8')]).astype('<u4')
    with open(path, 'wb') as f:
        f.write(struct.pack('<II', signature, base_count + nn)); f.write(table.tobytes())
        if base_m is not None:
            pos = 8 + 4 * base_count
            while pos < len(base_m):
                f.write(base_m[pos:pos + (1 << 24)]); pos += 1 << 24
        for rec in newrecs:
            f.write(rec)


# ============================================================================================== render / describe
def sprite_index(g, x=0, y=0, z=0, layer=0, phase=0, ww=0, hh=0):
    return ((((((phase * g['pz'] + z) * g['py'] + y) * g['px'] + x) * g['layers'] + layer) * g['h'] + hh) * g['w'] + ww)


def compose(g, spr, x=0, y=0, z=0, phase=0, layer=0):
    cv = Image.new('RGBA', (g['w'] * 32, g['h'] * 32), (0, 0, 0, 0))
    for hh in range(g['h']):
        for ww in range(g['w']):
            a = spr.sprite(g['sprites'][sprite_index(g, x, y, z, layer, phase, ww, hh)])
            if a is not None:
                cv.alpha_composite(Image.fromarray(a, 'RGBA'), ((g['w'] - 1 - ww) * 32, (g['h'] - 1 - hh) * 32))
    return cv


def frames_of(g):
    return [(x, y, z, ph, l) for ph in range(g['phases']) for z in range(g['pz']) for y in range(g['py'])
            for x in range(g['px']) for l in range(g['layers'])]


def thumb(t, spr):
    """south-facing first frame of the first group (all layers composited for items / effects, layer 0 for outfits)."""
    g = t.groups[0]
    x = 2 if t.cat == 'outfit' and g['px'] >= 4 else 0
    im = compose(g, spr, x)
    if t.cat != 'outfit':
        for l in range(1, g['layers']):
            im.alpha_composite(compose(g, spr, x, layer=l))
    return im


_HUES = ['red', 'orange', 'yellow', 'green', 'green', 'cyan', 'blue', 'blue', 'purple', 'pink', 'red']


def tone(im):
    a = np.asarray(im).astype(np.float32)
    m = a[:, :, 3] > 0
    if not m.any():
        return 'blank'
    rgb = a[:, :, :3][m] / 255.0
    v = rgb.max(1); s = np.where(v > 0, (v - rgb.min(1)) / np.maximum(v, 1e-6), 0)
    lum = float(v.mean())
    if float(s.mean()) < 0.18:
        hue = 'grey'
    else:
        hsv = np.asarray(Image.fromarray(a[:, :, :3].astype(np.uint8)).convert('HSV')).reshape(-1, 3)[m.reshape(-1)]
        sel = hsv[:, 1] > 60
        h = np.bincount((hsv[sel, 0].astype(int) * 10 // 256), minlength=10).argmax() if sel.any() else 0
        hue = _HUES[h]
    return ('dark ' if lum < 0.35 else 'bright ' if lum > 0.75 else '') + hue


def describe(t, flags, im):
    g = t.groups[0]
    names = set(flag_names(flags))
    if t.cat == 'outfit':
        kind = 'creature' if g['px'] >= 4 else 'static figure'
        kind += ' walk' if any(gr['phases'] > 1 for gr in t.groups) else ''
    elif t.cat == 'item':
        if 'ground' in names:
            kind = 'ground'
        elif 'clip' in names:
            kind = 'border'
        elif 'container' in names:
            kind = 'container'
        elif 'stackable' in names:
            kind = 'stackable'
        elif 'pickupable' in names:
            kind = 'pickup'
        elif 'notwalkable' in names or 'blockpath' in names:
            kind = 'wall/blocking' if 'top' in names or g['h'] >= 2 or g['w'] >= 2 else 'blocking object'
        elif 'top' in names:
            kind = 'top decoration'
        elif 'bottom' in names:
            kind = 'bottom decoration'
        else:
            kind = 'decoration'
        if 'light' in names:
            kind += ' light'
        if g['phases'] > 1:
            kind += ' animated'
    else:
        kind = t.cat + (' animated' if g['phases'] > 1 else '')
    return f'{kind}, {tone(im)}'


def size_of(t):
    g = t.groups[0]
    return f"{g['w']}x{g['h']}"


def frames_text(t):
    return ' '.join(f"L{g['layers']}P{g['px']}{g['py']}{g['pz']}F{g['phases']}" for g in t.groups)


def sheet(entries, spr, path, cell, cols, title=''):
    """entries: [(label, thing)]"""
    lh = 10
    rows = (len(entries) + cols - 1) // cols
    top = 14 if title else 0
    im = Image.new('RGB', (cols * cell, top + max(1, rows) * (cell + lh)), (44, 44, 48))
    dr = ImageDraw.Draw(im)
    if title:
        dr.text((3, 2), title, fill=(255, 140, 120))
    for i, (label, t) in enumerate(entries):
        th = thumb(t, spr)
        bb = th.getchannel('A').getbbox()
        if bb:
            th = th.crop(bb)
        if th.width > cell or th.height > cell - 2:
            f = min(cell / th.width, (cell - 2) / th.height)
            th = th.resize((max(1, int(th.width * f)), max(1, int(th.height * f))), Image.LANCZOS)
        cx = (i % cols) * cell; cy = top + (i // cols) * (cell + lh)
        tile = Image.new('RGBA', (cell, cell), (44, 44, 48, 255))
        tile.alpha_composite(th, ((cell - th.width) // 2, cell - th.height))
        im.paste(tile.convert('RGB'), (cx, cy))
        dr.text((cx + 1, cy + cell), str(label), fill=(235, 225, 120))
    im.save(path)


# ============================================================================================== verification
def verify_things(pairs, src_spr, out_spr, log, sample_every=25):
    """pairs: [(source thing, output thing, expected flags)]: flags, groups and every sprite slot; composed frames for
    all frames of every `sample_every`-th thing and the first frame of the others."""
    nslots = nframes = 0
    checked = {}
    for i, (s, o, fl) in enumerate(pairs):
        assert o.flags == fl, (o.cat, o.id, 'flags')
        assert len(s.groups) == len(o.groups), (o.cat, o.id)
        for gs, go in zip(s.groups, o.groups):
            for k in ('gtype', 'w', 'h', 'exact', 'layers', 'px', 'py', 'pz', 'phases', 'anim'):
                assert gs[k] == go[k], (o.cat, o.id, k)
            for a, b in zip(gs['sprites'], go['sprites']):
                key = (a, b)
                if key not in checked:
                    x, y = src_spr.sprite(a) if a else None, out_spr.sprite(b) if b else None
                    if x is not None and not x[:, :, 3].any():
                        x = None
                    ok = (x is None) == (y is None) and (x is None or np.array_equal(x, y))
                    if not ok:
                        raise SystemExit(f'MISMATCH {o.cat} {o.id}: source sprite {a} vs output sprite {b}')
                    checked[key] = True
                nslots += 1
            frs = frames_of(gs) if i % sample_every == 0 else frames_of(gs)[:1]
            for (x, y, z, ph, l) in frs:
                if not np.array_equal(np.asarray(compose(gs, src_spr, x, y, z, ph, l)),
                                      np.asarray(compose(go, out_spr, x, y, z, ph, l))):
                    raise SystemExit(f'MISMATCH {o.cat} {o.id} frame x{x} y{y} z{z} phase {ph} layer {l}')
                nframes += 1
        if len(checked) > 400000:
            checked.clear()
        if len(src_spr._cache) + len(out_spr._cache) > 40000:
            src_spr._cache.clear(); out_spr._cache.clear()
        if i % 2000 == 0:
            if i:
                log(f'  verified {i}/{len(pairs)} things')
    return nslots, nframes


def open_source(dat_path, spr_path, profile=None, extra_items=None):
    """profile: 'donor-b' (flag table of donor B, signed displacements), 'donor-c' (10.98 table plus flag bytes without
    payload, stripped) or 'library' (our table); default: donor-b for donor B's dat signature, else library."""
    data = open(dat_path, 'rb').read()
    sig = struct.unpack_from('<I', data, 0)[0]
    if profile is None:
        profile = 'donor-b' if sig == DONOR_SIG else 'library'
    kinds, default = {'donor-b': (DONOR_KINDS, None), 'donor-c': (DONORC_KINDS, 0), 'library': (OUR_KINDS, None)}[profile]
    things = parse_dat(data, kinds, default)
    if extra_items:
        ni = struct.unpack_from('<H', data, 4)[0]
        things['item'] += parse_extra_items(extra_items, ni + 1, kinds, default)
    spr = Spr(spr_path)
    if not spr.alpha or not spr.u32count:
        raise SystemExit('source spr: expected alpha sprites with a u32 count')
    return data, things, spr, profile


def parse_ranges(spec):
    """'outfit:4080-4159,4200;item:100' -> {(cat, id)}"""
    out = set()
    for part in (spec or '').split(';'):
        if not part.strip():
            continue
        cat, ids = part.split(':')
        for r in ids.split(','):
            lo, _, hi = r.partition('-')
            out.update((cat.strip(), i) for i in range(int(lo), int(hi or lo) + 1))
    return out


# ============================================================================================== library
def cmd_library(a, log):
    data, things, sspr, profile = open_source(a.src_dat, a.src_spr, a.source, a.extra_items)
    named = parse_ranges(a.named)
    log(f'{profile}: dat {struct.unpack_from("<I", data, 0)[0]:#x} ' + ', '.join(f'{len(things[c])} {c}s' for c in CATS)
        + f'; spr {sspr.signature:#x} {sspr.count} sprites')
    ospr = Spr(a.ours_spr)
    log('hashing our sprites (pixel keys)...')
    ours = spr_pixel_keys(ospr, log)
    log(f'  {len(ours)} distinct visible sprites in ours')

    dkey = {}                                         # donor sprite id -> pixel key (None = empty)

    def key_of(sid):
        if sid not in dkey:
            a = sspr.sprite(sid) if sid and sid <= sspr.count and sspr.offs[sid - 1] else None
            dkey[sid] = pixel_key(a) if a is not None and a[:, :, 3].any() else None
        return dkey[sid]

    kept, skipped = {c: [] for c in CATS}, []
    seen = {}
    for cat in CATS:
        for t in things[cat]:
            if len(sspr._cache) > 20000:
                sspr._cache.clear()
            reason = None
            dropped = drop_empty_groups(t)
            if any(g['w'] > MAX_WH or g['h'] > MAX_WH or g['layers'] > MAX_LAYERS or g['px'] > 32 or g['py'] > 32
                   or g['pz'] > 16 for g in t.groups):
                reason = 'oversize'
            elif profile == 'donor-b' and cat == 'item' and any(b == 9 for b, _ in t.flags):
                reason = 'editor marker'
            else:
                keys = [key_of(s) for g in t.groups for s in g['sprites']]
                vis = [k for k in keys if k is not None]
                if not vis:
                    reason = 'empty'
                elif all(k in ours for k in vis):
                    reason = 'already in ours'
                else:
                    flags, stripped = convert_flags(t, profile)
                    if dropped:
                        stripped.append(f'{dropped} empty group(s)')
                    sig = (cat, flag_bytes(flags), tuple((g['gtype'], g['w'], g['h'], g['exact'], g['layers'], g['px'],
                                                          g['py'], g['pz'], g['phases'], g['anim']) for g in t.groups),
                           hashlib.md5(b''.join(k or b'-' for k in keys)).digest())
                    if sig in seen:
                        reason = f'duplicate of {cat} {seen[sig]}'
                    else:
                        seen[sig] = t.id
                        kept[cat].append((t, flags, stripped, sig[3].hex()[:12]))
            if reason:
                skipped.append((cat, t.id, reason))
        log(f'{cat}s: {len(kept[cat])} kept of {len(things[cat])}')
    sspr._cache.clear()

    # sprites: unique by pixel key, records copied
    os.makedirs(a.out_dir, exist_ok=True)
    smap, bykey, recs = {0: 0}, {}, []
    for cat in CATS:
        for t, flags, stripped, h in kept[cat]:
            for g in t.groups:
                for s in g['sprites']:
                    if s in smap:
                        continue
                    k = key_of(s)
                    if k is None:
                        smap[s] = 0; continue
                    if k not in bykey:
                        recs.append(record(sspr, s)); bykey[k] = len(recs)
                    smap[s] = bykey[k]
            if len(sspr._cache) > 20000:
                sspr._cache.clear()
    log(f'sprites: {len(recs)} distinct records')

    if len(kept['item']) + 99 > 0xFFFF:
        raise SystemExit(f"{len(kept['item'])} items do not fit a dat (65435 at most)")
    parts = []
    counts = []
    for cat in CATS:
        parts.append(b''.join(entry_bytes(cat, flags, t.groups, smap) for t, flags, stripped, h in kept[cat]))
        counts.append(len(kept[cat]))
    out_dat = struct.pack('<IHHHH', 0x42A3, counts[0] + 99, counts[1], counts[2], counts[3]) + b''.join(parts)
    dat_path = os.path.join(a.out_dir, 'Tibia.dat'); spr_path = os.path.join(a.out_dir, 'Tibia.spr')
    open(dat_path, 'wb').write(out_dat)
    write_spr(spr_path, ospr.signature, None, 0, recs)
    log(f'wrote {dat_path} ({len(out_dat)} bytes), {spr_path} ({os.path.getsize(spr_path)} bytes)')

    # verification
    lt = parse_dat(out_dat, OUR_KINDS)
    md = Dat(dat_path)
    od = Dat(a.ours_dat) if a.ours_dat else None
    if od is not None:
        assert md.variant == od.variant, (md.variant, od.variant)
    lspr = Spr(spr_path)
    assert lspr.count == len(recs) and lspr.alpha and lspr.u32count
    pairs = []
    for cat in CATS:
        assert len(lt[cat]) == len(kept[cat])
        for (t, flags, stripped, h), o in zip(kept[cat], lt[cat]):
            pairs.append((t, o, flags))
    nslots, nframes = verify_things(pairs, sspr, lspr, log)
    log(f'verified: library dat parses to EOF (datspr variant {md.variant}), {len(pairs)} things; {nslots} sprite slots '
        f'pixel-identical to the donor, {nframes} composed frames identical; flags as converted')

    # catalogue
    cat_path = os.path.join(a.out_dir, 'catalogue.csv')
    with open(cat_path, 'w', newline='') as fh:
        w = csv.writer(fh)
        w.writerow(['category', 'lib_id', 'source_id', 'size', 'frames', 'flags', 'stripped', 'description', 'hash'])
        for cat in CATS:
            for (t, flags, stripped, h), o in zip(kept[cat], lt[cat]):
                im = thumb(o, lspr)
                if len(lspr._cache) > 20000:
                    lspr._cache.clear()
                desc = describe(o, flags, im)
                if (cat, t.id) in named:
                    desc = 'named character (do not use live), ' + desc
                w.writerow([cat, o.id, t.id, size_of(o), frames_text(o), ' '.join(flag_names(flags)), ' '.join(stripped),
                            desc, h])
            lspr._cache.clear()
    with open(os.path.join(a.out_dir, 'skipped.csv'), 'w', newline='') as fh:
        w = csv.writer(fh); w.writerow(['category', 'source_id', 'reason'])
        w.writerows(skipped)
    log(f'catalogue {cat_path}')
    if a.sheets:
        draw_sheets(lt, lspr, a.sheets, log)


def draw_sheets(lt, spr, out, log, per=None):
    os.makedirs(out, exist_ok=True)
    spec = {'outfit': (72, 20, 400), 'item': (40, 30, 900), 'effect': (64, 20, 400), 'missile': (48, 20, 400)}
    n = 0
    for cat in CATS:
        cell, cols, per_sheet = spec[cat]
        L = lt[cat]
        for k in range(0, len(L), per_sheet):
            chunk = L[k:k + per_sheet]
            p = os.path.join(out, f'{cat}s_{chunk[0].id:05d}-{chunk[-1].id:05d}.png')
            sheet([(t.id, t) for t in chunk], spr, p, cell, cols, f'library {cat}s {chunk[0].id}-{chunk[-1].id}')
            spr._cache.clear(); n += 1
    log(f'{n} sheets in {out}')


# ============================================================================================== import
OTB_SOLID, OTB_MISSILE, OTB_PATH, OTB_PICKUP, OTB_MOVE, OTB_STACK = 1, 2, 4, 32, 64, 128
OTB_TOP, OTB_ANIM = 1 << 13, 1 << 24


def otb_row(new_id, sid_off, name, t, flags):
    names = dict((TABLE_NEW.get(b), v) for b, v in flags)
    g = t.groups[0]
    group = 1 if 'ground' in names else 2 if 'container' in names else 0
    fl = 0
    if 'notwalkable' in names or 'blockpath' in names:
        fl |= OTB_SOLID | OTB_PATH
    if 'blockmissile' in names:
        fl |= OTB_MISSILE
    if 'pickupable' in names:
        fl |= OTB_PICKUP
    if 'notmoveable' not in names and 'ground' not in names and 'pickupable' in names:
        fl |= OTB_MOVE
    if 'stackable' in names:
        fl |= OTB_STACK
    top = 1 if 'clip' in names else 2 if 'bottom' in names else 3 if 'top' in names else 0
    if top:
        fl |= OTB_TOP
    if g['phases'] > 1:
        fl |= OTB_ANIM
    speed = struct.unpack('<H', names['ground'])[0] if 'ground' in names else 0
    ll, lc = struct.unpack('<HH', names['light']) if 'light' in names else (0, 0)
    mm = struct.unpack('<H', names['minimap'])[0] if 'minimap' in names else ''
    return {'client_id': new_id, 'server_id': new_id + sid_off, 'key': f'donor_b_{new_id}', 'name': name,
            'kind': 'ground' if group == 1 else 'object', 'piece': '', 'size': size_of(t),
            'patterns': f"{g['px']}x{g['py']}", 'phases': g['phases'], 'frame_ms': g['anim'][1][0] if g['anim'] else 0,
            'speed': speed, 'otb_group': group, 'otb_flags': fl, 'top_order': top, 'light_level': ll, 'light_color': lc,
            'minimap': mm, 'dat_flags': ' '.join(flag_names(flags))}


MANIFEST_COLS = ['client_id', 'server_id', 'key', 'name', 'kind', 'piece', 'size', 'patterns', 'phases', 'frame_ms', 'speed',
                 'otb_group', 'otb_flags', 'top_order', 'light_level', 'light_color', 'minimap', 'dat_flags']


def read_selection(path):
    rows = []
    with open(path, newline='') as fh:
        for r in csv.DictReader(fh):
            if not r.get('category') or r['category'].startswith('#'):
                continue
            cat = r['category'].strip()
            if cat not in CATS:
                raise SystemExit(f'selection: unknown category {cat!r}')
            rows.append((cat, int(r['src_id']), (r.get('name') or '').strip(), (r.get('purpose') or '').strip()))
    keys = [(c, i) for c, i, _, _ in rows]
    if len(set(keys)) != len(keys):
        raise SystemExit('selection: duplicate rows')
    return rows


def cmd_import(a, log):
    sdata, things, sspr, profile = open_source(a.src_dat, a.src_spr, a.source, a.extra_items)
    log(f'source ({profile}): ' + ', '.join(f'{len(things[c])} {c}s' for c in CATS))
    for p in (a.ours_dat, a.ours_spr):
        assert os.path.abspath(os.path.dirname(p)) != os.path.abspath(a.out_dir), 'out-dir must differ from the input dir'
    od = Dat(a.ours_dat); ospr = Spr(a.ours_spr)
    assert od.variant[0] == 'new' and all(od.variant[1:]), f'expected our 10.98 dat: {od.variant}'
    assert ospr.u32count and ospr.alpha
    d = od.data
    ours = parse_dat(d, OUR_KINDS)
    n_old = {c: len(ours[c]) for c in CATS}
    log(f'ours: dat {od.signature:#x} last ids: ' + ', '.join(f'{c} {n_old[c] + FIRST[c] - 1}' for c in CATS) + f'; spr {ospr.count} sprites')
    sel = read_selection(a.select)
    by = {c: {t.id: t for t in things[c]} for c in CATS}

    first_item = n_old['item'] + 100
    pad = 0
    if a.first_item:
        if a.first_item < first_item:
            raise SystemExit(f'--first-item {a.first_item} is not above the last item {first_item - 1}')
        pad = a.first_item - first_item; first_item = a.first_item
    nxt = {'item': first_item, 'outfit': n_old['outfit'] + 1, 'effect': n_old['effect'] + 1, 'missile': n_old['missile'] + 1}
    for spec in (a.expect or '').split(','):
        if spec:
            c, v = spec.split('=')
            if nxt[c] != int(v):
                raise SystemExit(f'first new {c} would be {nxt[c]}, expected {v}: wrong input pair (or already imported)')

    chosen = {c: [] for c in CATS}
    for cat, sid, name, purpose in sel:
        t = by[cat].get(sid)
        if t is None:
            raise SystemExit(f'source has no {cat} {sid}')
        dropped = drop_empty_groups(t)
        if any(g['w'] > MAX_WH or g['h'] > MAX_WH or g['layers'] > MAX_LAYERS for g in t.groups):
            raise SystemExit(f'{cat} {sid}: too big for our tools')
        if cat == 'item' and profile == 'donor-b' and any(b == 9 for b, _ in t.flags):
            raise SystemExit(f'item {sid}: donor editor marker tile')
        flags, stripped = convert_flags(t, profile)
        if dropped:
            stripped.append(f'{dropped} empty group(s)')
        chosen[cat].append((t, flags, stripped, nxt[cat], name, purpose))
        nxt[cat] += 1
    if chosen['missile'] and chosen['missile'][-1][3] > 254:
        raise SystemExit(f'missile ids would reach {chosen["missile"][-1][3]}; the 10.98 protocol allows 254')
    if nxt['item'] - 1 > 0xFFFF or (chosen['item'] and chosen['item'][-1][3] + a.server_id_offset > 0xFFFF):
        raise SystemExit('item or server ids would exceed 65535')

    # sprites: reuse identical records of ours, append the rest once
    log('indexing our sprite records...')
    m = ospr.m
    ours_rec = {}
    for sid in range(ospr.count, 0, -1):               # lowest id wins
        o = int(ospr.offs[sid - 1])
        if o:
            ln = struct.unpack_from('<H', m, o + 3)[0]
            ours_rec[hashlib.md5(m[o:o + 5 + ln]).digest()] = sid
    smap, newrecs, newidx = {0: 0}, [], {}
    reused = 0
    for cat in CATS:
        for t, *_ in chosen[cat]:
            for g in t.groups:
                for s in g['sprites']:
                    if s in smap:
                        continue
                    rec = record(sspr, s)
                    if rec is None:
                        smap[s] = 0; continue
                    h = hashlib.md5(rec).digest()
                    if h in ours_rec:
                        smap[s] = ours_rec[h]; reused += 1
                    else:
                        if h not in newidx:
                            newrecs.append(rec); newidx[h] = ospr.count + len(newrecs)
                        smap[s] = newidx[h]
        sspr._cache.clear()

    # dat: each category's new entries go right after its last old entry
    ends = {'item': ours['outfit'][0].raw[0] if ours['outfit'] else len(d),
            'outfit': ours['effect'][0].raw[0], 'effect': ours['missile'][0].raw[0], 'missile': len(d)}
    starts = {'item': 12, 'outfit': ends['item'], 'effect': ends['outfit'], 'missile': ends['effect']}
    out = bytearray(d[:12])
    new_blobs = {}
    for cat in CATS:
        blob = (BLANK_ITEM * pad if cat == 'item' else b'') + b''.join(
            entry_bytes(cat, flags, t.groups, smap) for t, flags, *_ in chosen[cat])
        new_blobs[cat] = blob
        out += d[starts[cat]:ends[cat]] + blob
    cnt = (nxt['item'] - 1, nxt['outfit'] - 1, nxt['effect'] - 1, nxt['missile'] - 1)
    struct.pack_into('<HHHH', out, 4, *cnt)
    os.makedirs(a.out_dir, exist_ok=True)
    dat_path = os.path.join(a.out_dir, 'Tibia.dat'); spr_path = os.path.join(a.out_dir, 'Tibia.spr')
    open(dat_path, 'wb').write(out)
    write_spr(spr_path, ospr.signature, m, ospr.count, newrecs)
    log(f'dat: ' + ', '.join(f'{c}s {n_old[c]} -> {len(chosen[c])} new' for c in CATS)
        + (f' (+{pad} blank items before the first new item)' if pad else '')
        + f'; spr: {reused} records reused from ours, {len(newrecs)} appended ({ospr.count} -> {ospr.count + len(newrecs)})')

    # verification
    md = Dat(dat_path); ms = Spr(spr_path)
    assert md.variant == od.variant, md.variant
    assert md.counts == cnt, md.counts
    assert ms.count == ospr.count + len(newrecs) and ms.signature == ospr.signature and md.max_sprite <= ms.count
    nt = parse_dat(bytes(out), OUR_KINDS)
    for cat in CATS:
        for to in ours[cat]:
            tn = nt[cat][to.id - FIRST[cat]]
            assert out[tn.raw[0]:tn.raw[1]] == d[to.raw[0]:to.raw[1]], (cat, to.id, 'old entry changed')
        for i in range(pad if cat == 'item' else 0):
            tn = nt[cat][n_old[cat] + i]
            assert out[tn.raw[0]:tn.raw[1]] == BLANK_ITEM
    pairs = []
    for cat in CATS:
        for t, flags, stripped, nid, name, purpose in chosen[cat]:
            pairs.append((t, nt[cat][nid - FIRST[cat]], flags))
    nslots, nframes = verify_things(pairs, sspr, ms, log, sample_every=1 if len(pairs) < 400 else 10)
    random.seed(1)
    for sid in random.sample(range(1, ospr.count + 1), min(3000, ospr.count)) + [1, ospr.count]:
        x, y = ospr.sprite(sid), ms.sprite(sid)
        assert (x is None) == (y is None) and (x is None or (x == y).all()), sid
    log(f'verified: output parses (datspr {md.variant}) to EOF; {len(pairs)} new things: {nslots} sprite slots '
        f'pixel-identical to the source, {nframes} composed frames identical, flags as converted; every old item, '
        f'outfit, effect and missile byte-identical; 3000 sampled old sprites unchanged')

    with open(os.path.join(a.out_dir, 'donor_import.csv'), 'w', newline='') as fh:
        w = csv.writer(fh)
        w.writerow(['category', 'src_id', 'new_id', 'server_id', 'name', 'purpose', 'size', 'frames', 'flags', 'stripped'])
        for cat in CATS:
            for t, flags, stripped, nid, name, purpose in chosen[cat]:
                w.writerow([cat, t.id, nid, nid + a.server_id_offset if cat == 'item' else '', name, purpose, size_of(t),
                            frames_text(t), ' '.join(flag_names(flags)), ' '.join(stripped)])
    with open(os.path.join(a.out_dir, 'donor_items.csv'), 'w', newline='') as fh:
        w = csv.DictWriter(fh, MANIFEST_COLS); w.writeheader()
        for t, flags, stripped, nid, name, purpose in chosen['item']:
            w.writerow(otb_row(nid, a.server_id_offset, name or f'donor item {t.id}', t, flags))
    if a.preview:
        draw_preview(chosen, nt, ms, a.preview)
        log(f'preview sheets in {a.preview}')


def draw_preview(chosen, nt, spr, out):
    os.makedirs(out, exist_ok=True)
    for cat in CATS:
        L = [(nid, nt[cat][nid - FIRST[cat]]) for t, flags, stripped, nid, name, purpose in chosen[cat]]
        if L:
            cell = 72 if cat == 'outfit' else 48
            sheet(L, spr, os.path.join(out, f'{cat}s.png'), cell, 16, f'new {cat}s (our ids)')


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    lb = sub.add_parser('library')
    lb.add_argument('--src-dat', required=True); lb.add_argument('--src-spr', required=True)
    lb.add_argument('--source', choices=('donor-b', 'donor-c'), default=None, help='default: by the dat signature')
    lb.add_argument('--extra-items', default=None, help='extended-items file of the source (items after 65535)')
    lb.add_argument('--named', default=None, help="'outfit:4080-4159;item:..': tagged 'named character' in the catalogue")
    lb.add_argument('--ours-spr', required=True, help='our spr: things whose sprites are all in it are skipped')
    lb.add_argument('--ours-dat', default=None, help='optional: check the library parses as the same variant as ours')
    lb.add_argument('--out-dir', required=True); lb.add_argument('--sheets', default=None)
    im = sub.add_parser('import')
    im.add_argument('--src-dat', required=True); im.add_argument('--src-spr', required=True)
    im.add_argument('--source', choices=('donor-b', 'donor-c', 'library'), default=None,
                    help='default: donor-b for its dat signature, else library')
    im.add_argument('--extra-items', default=None)
    im.add_argument('--ours-dat', required=True); im.add_argument('--ours-spr', required=True)
    im.add_argument('--select', required=True, help='CSV: category,src_id[,name,purpose]')
    im.add_argument('--out-dir', required=True)
    im.add_argument('--first-item', type=int, default=None)
    im.add_argument('--server-id-offset', type=int, default=12000)
    im.add_argument('--expect', default=None, help='e.g. outfit=1511,item=28000: stop unless the first new ids match')
    im.add_argument('--preview', default=None)
    a = ap.parse_args()
    t0 = time.time()

    def log(s):
        print(s, flush=True)
    (cmd_library if a.cmd == 'library' else cmd_import)(a, log)
    log(f'done in {time.time() - t0:.0f}s')


if __name__ == '__main__':
    main()
