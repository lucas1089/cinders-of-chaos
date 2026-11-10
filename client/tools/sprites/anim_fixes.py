#!/usr/bin/env python3
"""Animation fixes done by rule on the art we already have (pair 61, ROADMAP O458): a table of exact, repeatable
operations on the dat fields and on existing pixels of a 10.98 pair. Nothing is drawn, nothing is fetched.

python3 -I anim_fixes.py --ours-dat P/Tibia.dat --ours-spr P/Tibia.spr --out-dir OUT [--spec pair_fixes/anim_fixes.csv]
        [--changes-out pair_fixes/pair61_changes.csv] [--expect-dat-md5 MD5] [--dry-run]
python3 -I anim_fixes.py scan-trim --ours-dat D --ours-spr S --ids 1,3,415 [--share 0.05] [--floor 4]
        (writes nothing) prints the table rows the trim rule gives for these effects

The table (kind, id, op, args, reason, review) lists every fix; nothing else in the pair changes. kind is the category
(outfit, effect, missile, item), id the thing id, args `key=value;key=value`. The ops, in the order they are applied
per row (rows of one thing are applied in table order, each on the result of the one before):
  trim        effects and looks with phases. Cut the leading and trailing phases that hold under `share` of the
              thing's peak opaque pixels, leaving at least `floor` phases. The rule runs on the thing and must give
              exactly `keep=A-B` (phases A..B-1 stay) out of `of=N` phases, or the run stops: a table for another
              pair cannot be applied by mistake. The kept phases keep their own durations, so the visible part keeps
              its speed. A frame with no pixels at all counts as under the share.
  dedupe      drop phases that differ from the last kept phase by under `share` of the pixels (union of opaque pixels,
              colour step over 16 or alpha step over 32 counts as different). The first and the last phase always
              stay. Must give `keep=i,j,...` out of `of=N` and a total time inside `band=MIN-MAX` ms.
  lift        lighten the darkest shades toward the thing's own mid tone, keeping its hue: layer 0 of every sprite
              of the thing, pixels darker than the mid tone are blended toward it with weight
              `k * (1 - V / Vmid)`; `vmid_min` raises a mid tone that is itself dark (its hue kept).
  clear_px    remove the isolated opaque pixels (no opaque 8-neighbour) of one `frame=N` (and `dir=D` for looks);
              must remove exactly `expect=n` pixels.
  clear_color remove the pixels of exactly one colour `rgb=R,G,B` in `frame=N` (optional `group=G`, `dir=D`);
              must remove `expect=n` pixels.
  pulse       a one-frame look gets an idle of `n` phases (`ms` each): a slow brightness pulse, never darker than the
              still (factor 1 + amp * (1 - cos) / 2); the animateAlways attribute is set.
  displacement  `x,y` sets dat attribute 25 (the sprites and groups are untouched).
Every op checks its premise first (trim and dedupe check `of=N`, so a row cannot apply twice). Deterministic: the same pair and table give the same bytes. Verification (always): every entry
re-serialises to its exact old bytes before the edit; every thing not in the table is byte-identical (the count is
printed); the output re-parses with the same counts; the new sprites decode to the pixels asked for; 4,000 old
sprites are unchanged. check_pair.py --old with --allow-changed = exactly the changed things must pass afterwards.
"""
import argparse
import csv
import hashlib
import os
import random
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
import import_art_things as iat  # noqa: E402
import import_donor_things as idt  # noqa: E402
from datspr import Spr  # noqa: E402

FIRST = idt.FIRST
CATS = idt.CATS
DISPLACEMENT_BYTE = 25
ANIMATE_ALWAYS_BYTE = 28
SPEC = os.path.join(HERE, 'pair_fixes', 'anim_fixes.csv')
SPEC_COLS = ['kind', 'id', 'op', 'args', 'reason', 'review']
MID_PCT = (40, 60)


# ------------------------------------------------------------------------------------------------ sprites
class Store:
    """reads sprites of the input pair, collects the records of new sprites (ids after the input's last)"""

    def __init__(self, spr):
        self.spr = spr
        self.recs = []          # new records, id = spr.count + 1 + index
        self.by_rec = {}        # md5 of a record -> id
        self.pix = {}           # new id -> decoded tile (what the spr must give back)

    def tile(self, sid):
        """the tile of a sprite id as a writable (32, 32, 4) array, transparent for 0"""
        if sid == 0:
            return np.zeros((32, 32, 4), np.uint8)
        if sid > self.spr.count:
            return self.pix[sid].copy()
        a = self.spr.sprite(sid)
        return np.zeros((32, 32, 4), np.uint8) if a is None else a.copy()

    def add(self, tile, old=None):
        """id for a tile: the old id when the pixels are the same, 0 when empty, else a new or reused record"""
        t = iat.decoded(np.ascontiguousarray(tile))
        if old is not None and (t == iat.decoded(self.tile(old))).all():
            return old
        rec = iat.encode_sprite(t)
        if rec is None:
            return 0
        k = hashlib.md5(rec).digest()
        sid = self.by_rec.get(k)
        if sid is None:
            self.recs.append(rec)
            sid = self.spr.count + len(self.recs)
            self.by_rec[k] = sid
            self.pix[sid] = t
        return sid


class TS:
    """a thing being edited: flags and frame groups (dicts with a list of sprite ids)"""

    def __init__(self, t):
        self.cat, self.id, self.orig = t.cat, t.id, t
        self.flags = list(t.flags)
        self.groups = []
        for g in t.groups:
            n = dict(g)
            n['sprites'] = list(g['sprites'])
            self.groups.append(n)
        self.log = []   # (group, field, old, new)
        self.rows = []

    def entry(self):
        return idt.entry_bytes(self.cat, self.flags, self.groups)


def sidx(g, x=0, y=0, z=0, layer=0, phase=0, ww=0, hh=0):
    return ((((((phase * g['pz'] + z) * g['py'] + y) * g['px'] + x) * g['layers'] + layer) * g['h'] + hh) * g['w'] + ww)


def frame(store, g, x=0, y=0, z=0, layer=0, phase=0):
    """the composite (h*32, w*32, 4) of one frame"""
    w, h = g['w'], g['h']
    cv = np.zeros((h * 32, w * 32, 4), np.uint8)
    for hh in range(h):
        for ww in range(w):
            sid = g['sprites'][sidx(g, x, y, z, layer, phase, ww, hh)]
            if sid:
                cv[(h - 1 - hh) * 32:(h - hh) * 32, (w - 1 - ww) * 32:(w - ww) * 32] = store.tile(sid)
    return cv


def put_frame(store, g, img, x=0, y=0, z=0, layer=0, phase=0):
    """cut a composite back into the frame's tiles; unchanged tiles keep their ids. Returns the tiles changed."""
    w, h = g['w'], g['h']
    n = 0
    for hh in range(h):
        for ww in range(w):
            i = sidx(g, x, y, z, layer, phase, ww, hh)
            tile = img[(h - 1 - hh) * 32:(h - hh) * 32, (w - 1 - ww) * 32:(w - ww) * 32]
            sid = store.add(tile, old=g['sprites'][i])
            if sid != g['sprites'][i]:
                n += 1
            g['sprites'][i] = sid
    return n


def frames_of(g):
    """[(x, y, z, layer, phase)] of every frame of a group"""
    return [(x, y, z, l, p) for p in range(g['phases']) for z in range(g['pz']) for y in range(g['py'])
            for x in range(g['px']) for l in range(g['layers'])]


def block(g):
    return len(g['sprites']) // g['phases']


def durations(g):
    """[(min, max)] per phase, 0 ms when the group has no animator"""
    if not g['anim']:
        return [(0, 0)] * g['phases']
    d = g['anim'][1]
    return [(d[2 * i], d[2 * i + 1]) for i in range(g['phases'])]


def set_phases(ts, g, order, durs=None, label=''):
    """the group plays the phases `order` (indexes of its current phases), durations of the phase each came from
    unless `durs` is given"""
    old = durations(g)
    blk = block(g)
    sp = []
    for p in order:
        sp += g['sprites'][p * blk:(p + 1) * blk]
    nd = [old[p] for p in order] if durs is None else durs
    n0 = g['phases']
    g['sprites'] = sp
    g['phases'] = len(order)
    if g['phases'] > 1:
        head = g['anim'][0] if g['anim'] else (1, 0, 0)
        g['anim'] = (head, tuple(v for d in nd for v in d))
    else:
        g['anim'] = None
    ts.log.append(('0', 'phases', str(n0), str(len(order))))
    ts.log.append(('0', 'total_ms', str(sum(d[1] for d in old)), str(sum(d[1] for d in nd))))


def opaque(img):
    return int((img[..., 3] > 0).sum())


def args_of(s):
    out = {}
    for part in s.split(';'):
        part = part.strip()
        if part:
            k, _, v = part.partition('=')
            out[k.strip()] = v.strip()
    return out


def need(a, *keys):
    for k in keys:
        if k not in a:
            raise SystemExit('missing argument %s' % k)


# ------------------------------------------------------------------------------------------------ frame rules
def trim_range(cnt, share, floor):
    """[A, B) kept: leading and trailing counts under share * peak are cut, at least `floor` phases stay"""
    thr = share * max(cnt)
    a, b = 0, len(cnt)
    while b - a > floor and cnt[a] < thr:
        a += 1
    while b - a > floor and cnt[b - 1] < thr:
        b -= 1
    return a, b


def frame_diff(a, b):
    """share of the union of opaque pixels where two frames differ (colour step over 16, alpha step over 32)"""
    oa, ob = a[..., 3] > 0, b[..., 3] > 0
    un = oa | ob
    n = int(un.sum())
    if n == 0:
        return 0.0
    d = (np.abs(a[..., :3].astype(np.int16) - b[..., :3]).max(axis=2) > 16) | (oa != ob) \
        | (np.abs(a[..., 3].astype(np.int16) - b[..., 3]) > 32)
    return float((d & un).sum()) / n


def dedupe_keep(frames, share):
    keep = [0]
    for i in range(1, len(frames) - 1):
        if frame_diff(frames[i], frames[keep[-1]]) >= share:
            keep.append(i)
    if len(frames) > 1:
        keep.append(len(frames) - 1)
    return keep


def phase_frames(store, g):
    return [frame(store, g, phase=p) for p in range(g['phases'])]


# ------------------------------------------------------------------------------------------------ colour rules
def thing_pixels(store, ts, layer0_only=True):
    """(N, 3) colours of the opaque pixels of every distinct sprite of layer 0 of the thing"""
    seen, out = set(), []
    for g in ts.groups:
        for (x, y, z, l, p) in frames_of(g):
            if layer0_only and l:
                continue
            for hh in range(g['h']):
                for ww in range(g['w']):
                    sid = g['sprites'][sidx(g, x, y, z, l, p, ww, hh)]
                    if sid and sid not in seen:
                        seen.add(sid)
                        t = store.tile(sid)
                        out.append(t[t[..., 3] > 0][:, :3])
    return np.concatenate(out) if out else np.zeros((0, 3), np.uint8)


def mid_tone(px, vmid_min=0):
    """(colour float[3], V of it): the mean of the pixels between the 40th and 60th percentile of V, its hue kept
    when raised to vmid_min"""
    v = px.max(axis=1).astype(np.float64)
    lo, hi = np.percentile(v, MID_PCT)
    sel = px[(v >= lo) & (v <= hi)].astype(np.float64)
    mid = sel.mean(axis=0) if len(sel) else px.astype(np.float64).mean(axis=0)
    vm = float(mid.max())
    if vm < vmid_min:
        mid = mid * (vmid_min / vm) if vm > 0 else np.full(3, float(vmid_min))
        vm = float(mid.max())
    return mid, vm


def lift_tile(t, mid, vmid, k):
    """the lift on one (…, 4) tile"""
    o = t[..., 3] > 0
    c = t[..., :3].astype(np.float64)
    v = c.max(axis=-1)
    w = np.where(o & (v < vmid), k * (1.0 - v / vmid), 0.0)[..., None]
    n = c + w * (mid - c)
    out = t.copy()
    out[..., :3] = np.clip(np.floor(n + 0.5), 0, 255).astype(np.uint8)
    return out


# ------------------------------------------------------------------------------------------------ ops
def map_tiles(store, ts, fn, layers=(0,)):
    """apply fn(tile) -> tile to every sprite of the given layers of the thing; one new id per distinct old id"""
    cache, n = {}, 0
    for g in ts.groups:
        for (x, y, z, l, p) in frames_of(g):
            if l not in layers:
                continue
            for hh in range(g['h']):
                for ww in range(g['w']):
                    i = sidx(g, x, y, z, l, p, ww, hh)
                    old = g['sprites'][i]
                    if not old:
                        continue
                    if old not in cache:
                        cache[old] = store.add(fn(store.tile(old)), old=old)
                    if cache[old] != old:
                        g['sprites'][i] = cache[old]
                        n += 1
    return n


def op_trim(store, ts, a):
    need(a, 'share', 'floor', 'of', 'keep')
    g = ts.groups[0]
    if g['phases'] != int(a['of']):
        raise SystemExit('%s%d: %d phases, the row wants %s' % (ts.cat, ts.id, g['phases'], a['of']))
    cnt = [opaque(f) for f in phase_frames(store, g)]
    lo, hi = trim_range(cnt, float(a['share']), int(a['floor']))
    if '%d-%d' % (lo, hi) != a['keep']:
        raise SystemExit('%s%d: the trim rule keeps %d-%d, the row says %s' % (ts.cat, ts.id, lo, hi, a['keep']))
    set_phases(ts, g, list(range(lo, hi)))


def op_dedupe(store, ts, a):
    need(a, 'share', 'of', 'keep', 'band')
    g = ts.groups[0]
    if g['phases'] != int(a['of']):
        raise SystemExit('%s%d: %d phases, the row wants %s' % (ts.cat, ts.id, g['phases'], a['of']))
    keep = dedupe_keep(phase_frames(store, g), float(a['share']))
    if ','.join(map(str, keep)) != a['keep']:
        raise SystemExit('%s%d: the dedupe rule keeps %s, the row says %s' % (ts.cat, ts.id, keep, a['keep']))
    set_phases(ts, g, keep)
    total = sum(d[1] for d in durations(g))
    lo, hi = (int(v) for v in a['band'].split('-'))
    if not lo <= total <= hi:
        raise SystemExit('%s%d: total %d ms outside the band %s' % (ts.cat, ts.id, total, a['band']))


def op_lift(store, ts, a):
    need(a, 'k', 'vmid_min')
    px = thing_pixels(store, ts)
    if not len(px):
        raise SystemExit('%s%d: no pixels' % (ts.cat, ts.id))
    mid, vm = mid_tone(px, float(a['vmid_min']))
    k = float(a['k'])
    n = map_tiles(store, ts, lambda t: lift_tile(t, mid, vm, k))
    ts.log.append(('*', 'lift', 'mid %s V %.0f' % (tuple(int(round(c)) for c in mid), vm), '%d slots re-pointed' % n))


def isolated_px(img):
    a = img[..., 3] > 0
    p = np.pad(a, 1, constant_values=False)
    nb = np.zeros(a.shape, np.int16)
    for dy in (0, 1, 2):
        for dx in (0, 1, 2):
            if (dy, dx) != (1, 1):
                nb += p[dy:dy + a.shape[0], dx:dx + a.shape[1]]
    return a & (nb == 0)


def op_clear_px(store, ts, a):
    need(a, 'frame', 'expect')
    g = ts.groups[0]
    ph = int(a['frame'])
    d = int(a.get('dir', 0))
    img = frame(store, g, x=d, phase=ph)
    m = isolated_px(img)
    if int(m.sum()) != int(a['expect']):
        raise SystemExit('%s%d: %d isolated pixels in frame %d, the row says %s' % (ts.cat, ts.id, int(m.sum()), ph, a['expect']))
    img[m] = 0
    put_frame(store, g, img, x=d, phase=ph)
    ts.log.append(('0', 'clear_px', 'frame %d' % ph, '%d pixels removed' % int(m.sum())))


def op_clear_color(store, ts, a):
    need(a, 'frame', 'rgb', 'expect')
    g = ts.groups[int(a.get('group', 0))]
    ph = int(a['frame'])
    d = int(a.get('dir', 0))
    rgb = [int(v) for v in a['rgb'].split(',')]
    img = frame(store, g, x=d, phase=ph)
    m = (img[..., 3] > 0) & (img[..., 0] == rgb[0]) & (img[..., 1] == rgb[1]) & (img[..., 2] == rgb[2])
    if int(m.sum()) != int(a['expect']):
        raise SystemExit('%s%d: %d pixels of %s in frame %d, the row says %s' % (ts.cat, ts.id, int(m.sum()), a['rgb'], ph, a['expect']))
    img[m] = 0
    put_frame(store, g, img, x=d, phase=ph)
    ts.log.append((a.get('group', '0'), 'clear_color', 'frame %d dir %d rgb %s' % (ph, d, a['rgb']), '%d pixels removed' % int(m.sum())))


def op_pulse(store, ts, a):
    """a one-phase look gets `n` phases of a slow brightness pulse (factor 1 + amp * (1 - cos) / 2) and animateAlways"""
    need(a, 'n', 'amp', 'ms')
    g = ts.groups[0]
    if g['phases'] != 1 or len(ts.groups) != 1:
        raise SystemExit('%s%d: pulse wants one group of one phase' % (ts.cat, ts.id))
    n, amp, ms = int(a['n']), float(a['amp']), int(a['ms'])
    base = list(g['sprites'])
    sp = []
    for i in range(n):
        f = 1.0 + amp * (1.0 - np.cos(2 * np.pi * i / n)) / 2.0   # never darker than the still
        for sid in base:
            if not sid:
                sp.append(0)
                continue
            t = store.tile(sid)
            t[..., :3] = np.clip(np.floor(t[..., :3].astype(np.float64) * f + 0.5), 0, 255).astype(np.uint8)
            sp.append(store.add(t, old=sid))
    g['sprites'] = sp
    g['phases'] = n
    g['anim'] = ((0, 0, 0), tuple([ms, ms] * n))
    if not any(f[0] == ANIMATE_ALWAYS_BYTE for f in ts.flags):
        k = next((i for i, f in enumerate(ts.flags) if f[0] > ANIMATE_ALWAYS_BYTE and f[0] != 254), len(ts.flags))
        ts.flags.insert(k, (ANIMATE_ALWAYS_BYTE, b''))
    ts.log.append(('0', 'phases', '1', str(n)))
    ts.log.append(('0', 'pulse', 'static', 'brightness 1 +- %.2f over %d ms, animateAlways' % (amp, n * ms)))


def set_displacement(ts, xy):
    x, y = (int(v) for v in xy.split(','))
    new = (DISPLACEMENT_BYTE, struct.pack('<hh', x, y))
    old = [f for f in ts.flags if f[0] == DISPLACEMENT_BYTE]
    if old:
        ts.log.append(('*', 'displacement', '%d,%d' % struct.unpack('<hh', old[0][1]), '%d,%d' % (x, y)))
        ts.flags[ts.flags.index(old[0])] = new
    else:
        k = next((i for i, f in enumerate(ts.flags) if f[0] > DISPLACEMENT_BYTE and f[0] != 254), len(ts.flags))
        ts.flags.insert(k, new)
        ts.log.append(('*', 'displacement', 'none', '%d,%d' % (x, y)))


OPS = {'trim': op_trim, 'dedupe': op_dedupe, 'lift': op_lift,
       'clear_px': op_clear_px, 'clear_color': op_clear_color}
EXTRA_OPS = {'pulse': op_pulse}


# ------------------------------------------------------------------------------------------------ run
def read_spec(path):
    rows = []
    with open(path, newline='', encoding='utf-8') as f:
        for r in csv.DictReader(f):
            if r['kind'] not in CATS:
                raise SystemExit('%s: kind %r is not a category' % (path, r['kind']))
            if r['op'] not in OPS and r['op'] not in EXTRA_OPS and r['op'] != 'displacement':
                raise SystemExit('%s: unknown op %r' % (path, r['op']))
            r['id'] = int(r['id'])
            rows.append(r)
    return rows


def md5(path):
    h = hashlib.md5()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def apply_rows(rows, things, store, log=print):
    """apply the table to the parsed things; returns {(cat, id): TS}"""
    edited = {}
    for r in rows:
        key = (r['kind'], r['id'])
        if key not in edited:
            lst = things[r['kind']]
            i = r['id'] - FIRST[r['kind']]
            if not 0 <= i < len(lst) or lst[i].id != r['id']:
                raise SystemExit('%s %d is not in the pair' % key)
            edited[key] = TS(lst[i])
        ts = edited[key]
        ts.rows.append(r)
        if r['op'] == 'displacement':
            set_displacement(ts, r['args'])
        elif r['op'] in OPS:
            OPS[r['op']](store, ts, args_of(r['args']))
        else:
            EXTRA_OPS[r['op']](store, ts, args_of(r['args']))
    return edited


def build(a, log=print):
    ours_dat, ours_spr = a.ours_dat, a.ours_spr
    d = open(ours_dat, 'rb').read()
    spr = Spr(ours_spr)
    if not (spr.u32count and spr.alpha):
        raise SystemExit('not an alpha u32 spr')
    if a.expect_dat_md5 and hashlib.md5(d).hexdigest() not in a.expect_dat_md5.split(','):
        raise SystemExit('input dat md5 %s is not one of %s' % (hashlib.md5(d).hexdigest(), a.expect_dat_md5))
    things = idt.parse_dat(d, idt.OUR_KINDS)
    rows = read_spec(a.spec)
    store = Store(spr)
    edited = apply_rows(rows, things, store, log)
    # every entry must round-trip before the edit
    for (cat, tid), ts in edited.items():
        t = ts.orig
        if idt.entry_bytes(t.cat, t.flags, t.groups) != d[t.raw[0]:t.raw[1]]:
            raise SystemExit('%s%d: its entry does not round-trip; refusing' % (cat, tid))
    log('rows: %d, things changed: %d, new sprites: %d (%s bytes)'
        % (len(rows), len(edited), len(store.recs), f'{sum(len(r) for r in store.recs):,}'))
    cut = []
    for (cat, tid), ts in sorted(edited.items()):
        ph = [e for e in ts.log if e[1] == 'phases']
        ms = [e for e in ts.log if e[1] == 'total_ms']
        if ph and ms:
            cut.append('%s %d: %s -> %s phases, %s -> %s ms' % (cat, tid, ph[0][2], ph[-1][3], ms[0][2], ms[-1][3]))
    log('phases cut (%d things):\n  %s' % (len(cut), '\n  '.join(cut)))
    total = sum(len(v) for v in things.values())
    log('things not in the table, byte-identical: %d of %d' % (total - len(edited), total))
    if a.changes_out:
        write_changes(a.changes_out, edited)
    if a.dry_run:
        log('dry run: nothing written')
        return edited, store, things
    out_size = len(spr.m) + 4 * len(store.recs) + sum(len(r) for r in store.recs)
    st = os.statvfs(os.path.dirname(os.path.abspath(a.out_dir)) or '.')
    if st.f_bavail * st.f_frsize < out_size + (64 << 20):
        raise SystemExit('not enough disk space for the output spr (%s bytes)' % f'{out_size:,}')
    out = bytearray(d[:things['item'][0].raw[0]])
    for cat in CATS:
        for t in things[cat]:
            ts = edited.get((cat, t.id))
            out += ts.entry() if ts else d[t.raw[0]:t.raw[1]]
    assert [things[c] for c in CATS if things[c]][-1][-1].raw[1] == len(d)
    os.makedirs(a.out_dir, exist_ok=True)
    dat_path, spr_path = os.path.join(a.out_dir, 'Tibia.dat'), os.path.join(a.out_dir, 'Tibia.spr')
    open(dat_path, 'wb').write(out)
    idt.write_spr(spr_path, spr.signature, spr.m, spr.count, store.recs)
    log('wrote %s (%s bytes), %s (%s bytes)' % (dat_path, f'{len(out):,}', spr_path, f'{os.path.getsize(spr_path):,}'))
    verify(d, bytes(out), things, edited, store, spr, spr_path, log)
    return edited, store, things


def verify(d, out, things, edited, store, spr, spr_path, log):
    ms = Spr(spr_path)
    assert ms.count == spr.count + len(store.recs) and ms.signature == spr.signature
    nt = idt.parse_dat(out, idt.OUR_KINDS)
    same = 0
    for cat in CATS:
        assert len(nt[cat]) == len(things[cat]), cat
        for to, tn in zip(things[cat], nt[cat]):
            ts = edited.get((cat, to.id))
            if ts is None:
                assert out[tn.raw[0]:tn.raw[1]] == d[to.raw[0]:to.raw[1]], (cat, to.id, 'old entry changed')
                same += 1
                continue
            assert tn.flags == ts.flags and len(tn.groups) == len(ts.groups), (cat, to.id)
            for gn, ge in zip(tn.groups, ts.groups):
                assert list(gn['sprites']) == ge['sprites'] and gn['phases'] == ge['phases'], (cat, to.id)
                assert gn['anim'] == ge['anim'], (cat, to.id, 'animator')
    for sid, pix in store.pix.items():
        got = ms.sprite(sid)
        assert got is not None and (got == pix).all(), ('new sprite differs', sid)
    random.seed(1)
    for sid in random.sample(range(1, spr.count + 1), min(4000, spr.count)) + [1, spr.count]:
        x, y = spr.sprite(sid), ms.sprite(sid)
        assert (x is None) == (y is None) and (x is None or (x == y).all()), sid
    log('verified: output parses, %d entries byte-identical, %d changed entries match the table, %d new sprites '
        'pixel-identical, 4000 old sprites unchanged' % (same, len(edited), len(store.pix)))


def write_changes(path, edited):
    with open(path, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(['cat', 'id', 'group', 'field', 'old', 'new', 'reason'])
        for (cat, tid), ts in sorted(edited.items()):
            why = '; '.join(sorted({r['reason'] for r in ts.rows}))
            for g, field, old, new in ts.log:
                w.writerow([cat, tid, g, field, old, new, why])


def scan_trim(a):
    d = open(a.ours_dat, 'rb').read()
    things = idt.parse_dat(d, idt.OUR_KINDS)
    store = Store(Spr(a.ours_spr))
    w = csv.writer(sys.stdout)
    for cid in (int(v) for v in a.ids.split(',')):
        ts = TS(things['effect'][cid - 1])
        g = ts.groups[0]
        cnt = [opaque(f) for f in phase_frames(store, g)]
        lo, hi = trim_range(cnt, a.share, a.floor)
        if (lo, hi) != (0, len(cnt)):
            w.writerow(['effect', cid, 'trim', 'share=%s;floor=%d;of=%d;keep=%d-%d' % (a.share, a.floor, len(cnt), lo, hi), '', ''])


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv and argv[0] == 'scan-trim':
        ap = argparse.ArgumentParser(prog='anim_fixes.py scan-trim')
        ap.add_argument('--ours-dat', required=True)
        ap.add_argument('--ours-spr', required=True)
        ap.add_argument('--ids', required=True)
        ap.add_argument('--share', type=float, default=0.05)
        ap.add_argument('--floor', type=int, default=4)
        scan_trim(ap.parse_args(argv[1:]))
        return 0
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--ours-dat', required=True)
    ap.add_argument('--ours-spr', required=True)
    ap.add_argument('--out-dir', required=True)
    ap.add_argument('--spec', default=SPEC)
    ap.add_argument('--changes-out')
    ap.add_argument('--expect-dat-md5')
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args(argv)
    if os.path.abspath(os.path.dirname(a.ours_dat)) == os.path.abspath(a.out_dir):
        raise SystemExit('out-dir must differ from the input dir')
    build(a)
    return 0


if __name__ == '__main__':
    sys.exit(main())
