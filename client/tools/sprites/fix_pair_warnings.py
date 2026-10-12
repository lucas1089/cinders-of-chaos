#!/usr/bin/env python3
"""Fix the check_pair.py warnings of our 10.98 pair that show in game, in COPIES of the pair.

python3 -I fix_pair_warnings.py --ours-dat P/Tibia.dat --ours-spr P/Tibia.spr --out-dir OUT \
        [--spec pair_fixes/fixes.csv] [--changes-out pair_fixes/things_custom18_changes.csv] \
        [--expect-dat-md5 MD5[,MD5...]] [--link-spr]

python3 -I fix_pair_warnings.py --ours-dat P/Tibia.dat --ours-spr P/Tibia.spr --scan-displacement [--looks IDS]
        (writes nothing) lists the outfits of IDS (comma list of ids and ranges; default all) that are 2x2 or larger,
        have no displacement and pass the `displacement` premise, with their feet line: per direction the lowest row
        with 3 or more art pixels, as the client draws it (row 0 = the top of the creature's tile), the median of the
        four, and its offset from the median of the IDS looks that have displacement 8,8. A candidate list for review
        by eye: trailing capes or chains lower the feet line, so a premise pass alone is no proof.

The spec CSV (kind, cat, id, group, arg, reason) lists every fix; nothing else in the pair changes. Kinds:
  durations          arg "P:MS" or "P-Q:MS": phases P..Q of the group's animator get min = max = MS. A phase must
                     be 0 ms (or MS already). Async, loop count and start phase stay as they are.
  zero_empty         arg "SID,SID,...": every slot of the thing pointing at one of these sprite ids becomes 0.
                     Each id must be an empty spr slot (the client draws nothing there either).
  clear_addon_masks  arg "Y-Z": in addon patterns Y..Z, a second-layer (colour mask) sprite that is pixel-identical
                     to the layer-0 sprite of its slot (art copied into the mask) becomes 0. A sprite of template
                     colours only (a real mask) is kept; anything else stops the run. Base pattern masks are kept.
  drop_addon_rows    arg "N": the group keeps its first N addon rows (pattern y). The result must have the other
                     group's layers and patterns (the client indexes every group with the last one's).
  displacement       arg "X,Y" (the stock player place is 8,8), group "*": the outfit gets displacement X, Y (dat byte
                     25, inserted in flag order; the sprites and frame groups are untouched). Premise: the outfit has no
                     displacement (or 0, 0), every frame group is 2x2 or larger, and its art sits where the art of a
                     stock 8,8 player outfit sits: the art of the idle group (phase 0, addon 0, mount 0, layer 0, all
                     directions) reaches within EDGE_GAP px of the frame's bottom and right edges, and drawn with no
                     displacement its feet line (see --scan-displacement) is FEET_LOW px or more below the stock one
                     (row FEET_STOCK of the tile), so X, Y = 8, 8 brings it closer. Art drawn for no displacement keeps
                     about 8 px clear of the edges. With the fault the client draws the look 8 px low and right of its
                     tile, and its name, health bar and target square sit 8 px off too.
group is a frame-group index or "*" (all groups). Outfits only for the last three kinds.

Idempotent: a fix that is already applied changes nothing, so a run on its own output gives the same files.
Outputs in --out-dir: Tibia.dat, Tibia.spr (a byte copy, or a hard link with --link-spr). --changes-out writes one CSV
row per changed field (cat, id, group, field, where, old, new, reason). Inputs are never modified. Deterministic.
Verification (always run): every changed entry re-serialises to its exact old bytes before the edit; the output
re-parses with the same counts; every thing not in the spec is byte-identical; each spec thing differs only in the
fields its fix names (flags byte-identical, except the displacement a `displacement` fix sets); the spr is byte-identical (md5). Then check_pair.py's append-only check
with --allow-changed = exactly the changed things must pass.
"""
import argparse
import csv
import hashlib
import os
import shutil
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import check_pair as cp  # noqa: E402

FIRST = cp.FIRST
EDGE_GAP = 3        # displacement premise: art within this many px of the frame's bottom and right edges
FEET_STOCK = 24     # feet line of the stock player looks (displacement 8,8): row 24 of the tile (things_custom20 median)
FEET_LOW = 5        # displacement premise: feet line at least this far below FEET_STOCK with no displacement
TEMPLATE = {bytes(c) for c in ((255, 255, 0), (255, 0, 0), (0, 255, 0), (0, 0, 255))}   # mask colours (RGB)


def md5(path):
    h = hashlib.md5()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def groups_bytes(t):
    """the frame-group part of an entry, as the client reads it (everything after the flags' 0xFF)."""
    out = bytearray()
    if t.cat == 'outfit':
        out.append(len(t.groups))
    for g in t.groups:
        if t.cat == 'outfit':
            out.append(g.gtype)
        out += bytes([g.w, g.h])
        if g.w > 1 or g.h > 1:
            out.append(g.exact)
        out += bytes([g.layers, g.px, g.py, g.pz, g.phases])
        if g.phases > 1:
            asyn, loop, start, durs = g.anim
            out += struct.pack('<Bib', asyn, loop, start)
            out += struct.pack('<' + 'I' * len(durs), *durs)
        ns = g.w * g.h * g.layers * g.px * g.py * g.pz * g.phases
        if len(g.sprites) != ns:
            raise SystemExit(f'{t.ref}: {len(g.sprites)} sprite ids for {ns} slots')
        out += struct.pack(f'<{ns}I', *g.sprites)
    return bytes(out)


def flag_chunks(d, t, flags_end):
    """[(byte, raw bytes)] of the entry's flags, split as the client reads them; their join is d[t.start:flags_end - 1]."""
    table = dict(cp.FLAGS_1098)
    table.update(cp.CUSTOM_FLAGS)
    out, pos = [], t.start
    for b, name, val in t.flags:
        if d[pos] != b:
            raise SystemExit(f'{t.ref}: flag bytes do not match the parse')
        kind = table.get(b, (None, None))[1]
        if kind == 'market':
            ln = struct.unpack_from('<H', d, pos + 7)[0]
            k = 8 + ln + 4
        else:
            k = cp.PAYLOAD[kind] if b in table else 0
        out.append((b, bytes(d[pos:pos + 1 + k])))
        pos += 1 + k
    if pos != flags_end - 1:
        raise SystemExit(f'{t.ref}: flags do not re-serialise to their own bytes')
    return out


def art_gaps(t, spr):
    """(px between the art and the frame's right edge, px to its bottom edge): idle group, phase 0, addon 0, mount 0,
    layer 0, all directions; None when that art is empty."""
    g = t.groups[0]
    right = bottom = None
    for x in range(g.px):
        for hh in range(g.h):
            for ww in range(g.w):
                for i, v in decode(spr, g.sprites[cp.sprite_index(g, x=x, ww=ww, hh=hh)]).items():
                    if v[3]:
                        X, Y = (g.w - 1 - ww) * 32 + i % 32 + 1, (g.h - 1 - hh) * 32 + i // 32 + 1
                        right = X if right is None else max(right, X)
                        bottom = Y if bottom is None else max(bottom, Y)
    if right is None:
        return None
    return g.w * 32 - right, g.h * 32 - bottom


def set_displacement(row, t, chunks, spr, log):
    """the `displacement` fix: edit chunks (flag list) in place."""
    if t.cat != 'outfit':
        raise SystemExit(f'{t.ref}: displacement is for outfits')
    if row['group'] != '*':
        raise SystemExit(f'{t.ref}: displacement is a thing attribute, group must be "*"')
    try:
        x, y = (int(v) for v in row['arg'].split(','))
    except ValueError:
        raise SystemExit(f'{t.ref}: displacement arg {row["arg"]!r} is not "X,Y"')
    if not (0 <= x <= 32 and 0 <= y <= 32) or (x, y) == (0, 0):
        raise SystemExit(f'{t.ref}: displacement {x},{y} out of range (1..32)')
    new = (25, b'\x19' + struct.pack('<hh', x, y))
    old = [c for c in chunks if c[0] == 25]
    if old and old[0][1] == new[1]:
        return                                      # already applied
    if old and old[0][1] != b'\x19' + struct.pack('<hh', 0, 0):
        cur = struct.unpack_from('<hh', old[0][1], 1)
        raise SystemExit(f'{t.ref}: already has displacement {cur[0]},{cur[1]}, not none or 0,0')
    for gi, g in enumerate(t.groups):
        if g.w < 2 or g.h < 2:
            raise SystemExit(f'{t.ref} group {gi}: {g.w}x{g.h}, not 2x2 or larger')
    gaps = art_gaps(t, spr)
    if gaps is None or max(gaps) > EDGE_GAP:
        raise SystemExit(f'{t.ref}: art keeps {gaps} px (right, bottom) clear of the frame edges, more than {EDGE_GAP}: '
                         'it is drawn for no displacement, not like a stock 8,8 look')
    feet = feet_line(t, spr, (0, 0))
    if feet < FEET_STOCK + FEET_LOW:
        raise SystemExit(f'{t.ref}: feet line {feet} with no displacement, less than {FEET_LOW} px below the stock '
                         f'{FEET_STOCK}: it does not stand low')
    if old:
        chunks[chunks.index(old[0])] = new
        log.append(('*', 'displacement', 'flag 25', '0,0', f'{x},{y}'))
    else:
        k = next((i for i, c in enumerate(chunks) if c[0] > 25 and c[0] != 254), len(chunks))
        chunks.insert(k, new)
        log.append(('*', 'displacement', 'flag 25', 'none', f'{x},{y}'))


def copy_group(g):
    n = cp.Group()
    for k in cp.Group.__slots__:
        setattr(n, k, getattr(g, k))
    n.sprites = list(g.sprites)
    if g.anim:
        n.anim = (g.anim[0], g.anim[1], g.anim[2], list(g.anim[3]))
    return n


def decode(spr, sid):
    """{pixel index: rgba bytes} of a record (alpha records), {} for sprite 0 or an empty slot."""
    if not sid:
        return {}
    rec = spr.record(sid)
    if rec is None:
        return {}
    out = {}
    p, px, end = 5, 0, len(rec)
    while p + 4 <= end:
        skip, cnt = struct.unpack_from('<HH', rec, p)
        p += 4
        px += skip
        for k in range(cnt):
            out[px + k] = bytes(rec[p + 4 * k:p + 4 * k + 4])
        p += 4 * cnt
        px += cnt
    return out


def read_spec(path):
    rows = []
    with open(path, newline='', encoding='utf-8') as f:
        for row in csv.DictReader(f):
            if row['cat'] not in cp.CATS:
                raise SystemExit(f'{path}: unknown category {row["cat"]!r}')
            row['id'] = int(row['id'])
            rows.append(row)
    if not rows:
        raise SystemExit(f'{path}: no rows')
    keys = [(r['kind'], r['cat'], r['id'], r['group'], r['arg']) for r in rows]
    if len(set(keys)) != len(keys):
        raise SystemExit(f'{path}: a fix is listed twice')
    return rows


def span(s):
    a, _, b = s.partition('-')
    return range(int(a), int(b or a) + 1)


def groups_of(t, gspec):
    if gspec == '*':
        return list(range(len(t.groups)))
    gi = int(gspec)
    if not 0 <= gi < len(t.groups):
        raise SystemExit(f'{t.ref}: no frame group {gi}')
    return [gi]


def slot(g, idx):
    """sprite slot index -> (ww, hh, layer, x, y, z, phase)"""
    r = idx
    ww = r % g.w; r //= g.w
    hh = r % g.h; r //= g.h
    layer = r % g.layers; r //= g.layers
    x = r % g.px; r //= g.px
    y = r % g.py; r //= g.py
    z = r % g.pz; r //= g.pz
    return ww, hh, layer, x, y, z, r


def apply_fix(row, t, spr, log):
    """edit t.groups in place; append (group, field, where, old, new) to log."""
    kind, arg = row['kind'], row['arg']
    if kind == 'durations':
        phases, _, ms = arg.partition(':')
        ms = int(ms)
        if not 1 <= ms <= 10000:
            raise SystemExit(f'{t.ref}: duration {ms} ms out of range')
        for gi in groups_of(t, row['group']):
            g = t.groups[gi]
            if not g.anim:
                raise SystemExit(f'{t.ref} group {gi}: no animator')
            durs = g.anim[3]
            for p in span(phases):
                if not 0 <= p < g.phases:
                    raise SystemExit(f'{t.ref} group {gi}: no phase {p}')
                old = (durs[2 * p], durs[2 * p + 1])
                if old == (ms, ms):
                    continue
                if old != (0, 0):
                    raise SystemExit(f'{t.ref} group {gi} phase {p}: {old[0]}-{old[1]} ms, not 0 ms')
                durs[2 * p] = durs[2 * p + 1] = ms
                log.append((gi, 'duration', f'phase {p}', '0 ms', f'{ms} ms'))
    elif kind == 'zero_empty':
        sids = {int(s) for s in arg.split(',') if s.strip()}
        for s in sids:
            if not 0 < s <= spr.count or spr.offs[s - 1]:
                raise SystemExit(f'{t.ref}: sprite {s} is not an empty spr slot')
        for gi in groups_of(t, row['group']):
            g = t.groups[gi]
            for idx, s in enumerate(g.sprites):
                if s in sids:
                    ww, hh, layer, x, y, z, ph = slot(g, idx)
                    g.sprites[idx] = 0
                    log.append((gi, 'sprite', f'layer {layer} tile {ww},{hh} dir {x} addon {y} z {z} phase {ph}',
                                str(s), '0'))
    elif kind == 'clear_addon_masks':
        if t.cat != 'outfit':
            raise SystemExit(f'{t.ref}: clear_addon_masks is for outfits')
        rows_ = span(arg)
        for gi in groups_of(t, row['group']):
            g = t.groups[gi]
            if g.layers != 2:
                raise SystemExit(f'{t.ref} group {gi}: {g.layers} layers, not 2')
            for idx, s in enumerate(g.sprites):
                ww, hh, layer, x, y, z, ph = slot(g, idx)
                if layer != 1 or y not in rows_ or not s:
                    continue
                art = decode(spr, g.sprites[idx - g.w * g.h])
                mask = decode(spr, s)
                if mask != art:
                    if all(v[:3] in TEMPLATE for v in mask.values()):
                        continue            # a real colour mask: kept
                    raise SystemExit(f'{t.ref} group {gi} slot {idx}: sprite {s} is neither a copy of the art nor a '
                                     'colour mask')
                g.sprites[idx] = 0
                log.append((gi, 'sprite', f'layer 1 tile {ww},{hh} dir {x} addon {y} z {z} phase {ph}', str(s), '0'))
    elif kind == 'drop_addon_rows':
        if t.cat != 'outfit':
            raise SystemExit(f'{t.ref}: drop_addon_rows is for outfits')
        keep = int(arg)
        for gi in groups_of(t, row['group']):
            g = t.groups[gi]
            if g.py == keep:
                continue
            if not 1 <= keep < g.py:
                raise SystemExit(f'{t.ref} group {gi}: cannot keep {keep} of {g.py} addon rows')
            new = []
            for idx, s in enumerate(g.sprites):
                if slot(g, idx)[4] < keep:
                    new.append(s)
            dropped = len(g.sprites) - len(new)
            log.append((gi, 'pattern y', 'addon rows', str(g.py), str(keep)))
            log.append((gi, 'sprites', f'addon rows {keep}..{g.py - 1} dropped', str(len(g.sprites)),
                        f'{len(new)} (-{dropped})'))
            g.py = keep
            g.sprites = new
        first = t.groups[0]
        for g in t.groups[1:]:
            if (g.layers, g.px, g.py, g.pz) != (first.layers, first.px, first.py, first.pz):
                raise SystemExit(f'{t.ref}: frame groups still differ in layers or patterns')
    else:
        raise SystemExit(f'unknown fix kind {kind!r}')


def groups_sig(g):
    anim = g.anim and (g.anim[0], g.anim[1], g.anim[2], tuple(g.anim[3]))
    return tuple(tuple(g.sprites) if k == 'sprites' else anim if k == 'anim' else getattr(g, k) for k in cp.Group.__slots__)


def semantic_ok(row, ot, nt, kinds=()):
    """the new thing differs from the old one only in what its fix may change (kinds: every fix kind of the thing)."""
    kind = row['kind']
    strip = lambda fl: [f for f in fl if f[0] != 25]
    if kind == 'displacement':
        x, y = (int(v) for v in row['arg'].split(','))
        if strip(ot.flags) != strip(nt.flags) or nt.flag('displacement') != (x, y):
            return False
        if ot.flag('displacement') not in (None, (0, 0), (x, y)):
            return False
        if set(kinds) - {'displacement'}:
            return True                     # the other fixes of the thing check its frame groups
        return [groups_sig(g) for g in ot.groups] == [groups_sig(g) for g in nt.groups]
    oflags, nflags = (strip(ot.flags), strip(nt.flags)) if 'displacement' in kinds else (ot.flags, nt.flags)
    if oflags != nflags or len(ot.groups) != len(nt.groups):
        return False
    for go, gn in zip(ot.groups, nt.groups):
        same = ['gtype', 'w', 'h', 'exact', 'layers', 'px', 'pz', 'phases']
        if kind != 'drop_addon_rows':
            same.append('py')
        if any(getattr(go, k) != getattr(gn, k) for k in same):
            return False
        if kind == 'durations':
            if list(go.sprites) != list(gn.sprites) or go.anim[:3] != gn.anim[:3]:
                return False
            if any(a != b and a != 0 for a, b in zip(go.anim[3], gn.anim[3])):
                return False
        else:
            if (go.anim is None) != (gn.anim is None) or (go.anim and (go.anim[:3] != gn.anim[:3]
                                                                      or list(go.anim[3]) != list(gn.anim[3]))):
                return False
            if kind in ('zero_empty', 'clear_addon_masks'):
                if len(go.sprites) != len(gn.sprites):
                    return False
                if any(a != b and b != 0 for a, b in zip(go.sprites, gn.sprites)):
                    return False
            elif kind == 'drop_addon_rows':
                kept = [s for i, s in enumerate(go.sprites) if slot(go, i)[4] < gn.py]
                if list(gn.sprites) != kept:
                    return False
    return True


def feet_line(t, spr, disp):
    """median over the directions of the lowest screen row (from the tile's top) with >= 3 art pixels, drawn with
    displacement disp; None when the idle art is empty."""
    g = t.groups[0]
    rows = []
    for x in range(min(g.px, 4)):
        count = {}
        for hh in range(g.h):
            for ww in range(g.w):
                for i, v in decode(spr, g.sprites[cp.sprite_index(g, x=x, ww=ww, hh=hh)]).items():
                    if v[3]:
                        Y = (g.h - 1 - hh) * 32 + i // 32 - disp[1] - (g.h - 1) * 32
                        count[Y] = count.get(Y, 0) + 1
        full = [y for y, n in count.items() if n >= 3]
        if full:
            rows.append(max(full) + 1)
    if not rows:
        return None
    rows.sort()
    k = len(rows)
    return rows[k // 2] if k % 2 else (rows[k // 2 - 1] + rows[k // 2]) / 2


def parse_ids(spec):
    out = set()
    for part in spec.split(','):
        if part.strip():
            out.update(span(part.strip()))
    return out


def scan_displacement(things, spr, ids):
    outs = things['outfit']
    ids = sorted(ids) if ids else [t.id for t in outs]
    ref, cand = [], []
    for o in ids:
        if not 1 <= o <= len(outs):
            raise SystemExit(f'outfit {o} is not in the pair')
        t = outs[o - 1]
        if cp.is_blank(t):
            continue
        disp = t.flag('displacement') or (0, 0)
        if disp == (8, 8):
            f = feet_line(t, spr, disp)
            if f is not None:
                ref.append(f)
        elif disp == (0, 0) and all(g.w > 1 and g.h > 1 for g in t.groups):
            gaps = art_gaps(t, spr)
            if gaps is not None and max(gaps) <= EDGE_GAP:
                cand.append((t, gaps))
    if not ref:
        raise SystemExit('no look with displacement 8,8 among the ids')
    ref.sort()
    med = ref[len(ref) // 2]
    print(f'{len(ref)} looks with displacement 8,8: feet line median {med} (row from the tile top)')
    print(f'{len(cand)} looks 2x2 or larger with no displacement whose art reaches the frame edges like theirs:')
    for t, gaps in cand:
        f = feet_line(t, spr, (0, 0))
        ok = 'premise ok' if f >= FEET_STOCK + FEET_LOW else 'stands right (premise fails)'
        print(f'  outfit {t.id}: edge gap right {gaps[0]} bottom {gaps[1]}; feet {f} ({f - med:+} px), '
              f'with 8,8 {f - 8} ({f - 8 - med:+} px); {ok}')
    return [t.id for t, _ in cand]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--ours-dat', required=True)
    ap.add_argument('--ours-spr', required=True)
    ap.add_argument('--out-dir')
    ap.add_argument('--spec', default=os.path.join(HERE, 'pair_fixes', 'fixes.csv'))
    ap.add_argument('--changes-out', default=None, help='CSV of every changed field')
    ap.add_argument('--expect-dat-md5', default=None, help='fail unless the input dat has one of these md5s (comma list)')
    ap.add_argument('--link-spr', action='store_true', help='hard-link the spr instead of copying it (saves disk)')
    ap.add_argument('--scan-displacement', action='store_true', help='list displacement candidates, write nothing')
    ap.add_argument('--looks', default='', help='with --scan-displacement: outfit ids to scan (e.g. 128-160,2051)')
    a = ap.parse_args(argv)
    if a.scan_displacement:
        with open(a.ours_dat, 'rb') as f:
            _, _, things, _ = cp.parse_dat(f.read(), None)
        spr = cp.SprFile(a.ours_spr)
        scan_displacement(things, spr, parse_ids(a.looks))
        spr.close()
        return 0
    if not a.out_dir:
        raise SystemExit('--out-dir is required')

    if a.expect_dat_md5 and md5(a.ours_dat) not in a.expect_dat_md5.split(','):
        raise SystemExit(f'{a.ours_dat}: md5 is not {a.expect_dat_md5}')
    spec = read_spec(a.spec)
    with open(a.ours_dat, 'rb') as f:
        d = f.read()
    sig, counts, things, end = cp.parse_dat(d, None)
    if end != len(d):
        raise SystemExit('input dat has trailing bytes')
    spr = cp.SprFile(a.ours_spr)

    by_thing = {}
    for row in spec:
        by_thing.setdefault((row['cat'], row['id']), []).append(row)
    edits = []          # (start, end, new bytes)
    changes = []        # csv rows
    old_things = {}
    for (cat, tid), rows in sorted(by_thing.items(), key=lambda kv: (cp.CATS.index(kv[0][0]), kv[0][1])):
        k = tid - FIRST[cat]
        if not 0 <= k < len(things[cat]):
            raise SystemExit(f'{cat} {tid} is not in the pair')
        t = things[cat][k]
        gb = groups_bytes(t)
        flags_end = t.end - len(gb)
        if d[flags_end:t.end] != gb or d[flags_end - 1] != 0xFF:
            raise SystemExit(f'{t.ref}: entry does not re-serialise to its own bytes')
        chunks = flag_chunks(d, t, flags_end)
        fb = b''.join(c[1] for c in chunks)
        old_things[(cat, tid)] = (t, [copy_group(g) for g in t.groups])
        t.groups = [copy_group(g) for g in t.groups]
        for row in rows:
            log = []
            if row['kind'] == 'displacement':
                set_displacement(row, t, chunks, spr, log)
            else:
                apply_fix(row, t, spr, log)
            for gi, field, where, old, new in log:
                changes.append((cat, tid, gi, field, where, old, new, row['reason']))
        nb = groups_bytes(t)
        nfb = b''.join(c[1] for c in chunks)
        if nfb != fb:
            edits.append((t.start, t.end, nfb + b'\xff' + nb))
        elif nb != gb:
            edits.append((flags_end, t.end, nb))

    out = bytearray()
    pos = 0
    for s, e, blob in sorted(edits):
        out += d[pos:s] + blob
        pos = e
    out += d[pos:]

    os.makedirs(a.out_dir, exist_ok=True)
    od, osp = os.path.join(a.out_dir, 'Tibia.dat'), os.path.join(a.out_dir, 'Tibia.spr')
    with open(od, 'wb') as f:
        f.write(out)
    if os.path.abspath(a.ours_spr) != os.path.abspath(osp):
        if os.path.exists(osp):
            os.remove(osp)
        if a.link_spr:
            os.link(a.ours_spr, osp)
        else:
            shutil.copyfile(a.ours_spr, osp)
    spr.close()

    # verification
    nsig, ncounts, nthings, nend = cp.parse_dat(bytes(out), None)
    if (nsig, ncounts) != (sig, counts) or nend != len(out):
        raise SystemExit('verify: signature, counts or length changed')
    changed = set()
    for cat in cp.CATS:
        for ot, nt in zip(things[cat], nthings[cat]):
            key = (cat, ot.id)
            ob, nb = d[ot.start:ot.end], out[nt.start:nt.end]
            if key in old_things:
                ot0 = old_things[key][0]
                ot0.groups = old_things[key][1]
                for row in by_thing[key]:
                    if not semantic_ok(row, ot0, nt, [r['kind'] for r in by_thing[key]]):
                        raise SystemExit(f'verify: {ot.ref} changed beyond its fix ({row["kind"]})')
                if ob != nb:
                    changed.add(key)
            elif ob != nb:
                raise SystemExit(f'verify: {ot.ref} is not byte-identical')
    if md5(osp) != md5(a.ours_spr):
        raise SystemExit('verify: spr differs')
    allow = set(changed)
    rep = cp.check(od, osp, old=(a.ours_dat, a.ours_spr), new_only=True, allow_changed=allow)
    if not rep.ok:
        print(rep.text())
        raise SystemExit('verify: check_pair append-only check with --allow-changed failed')

    if a.changes_out:
        with open(a.changes_out, 'w', newline='', encoding='utf-8') as f:
            w = csv.writer(f, lineterminator='\n')
            w.writerow(['cat', 'id', 'group', 'field', 'where', 'old', 'new', 'reason'])
            w.writerows(changes)
    per = {}
    for cat, tid in sorted(changed, key=lambda k: (cp.CATS.index(k[0]), k[1])):
        per.setdefault(cat, []).append(tid)
    print(f'{len(changes)} field changes in {len(changed)} things; '
          f'{sum(len(v) for v in things.values()) - len(changed)} other things byte-identical; spr byte-identical')
    if changed:
        print('--allow-changed ' + "'" + ';'.join(f'{c}:' + ','.join(map(str, v)) for c, v in per.items()) + "'")
    print(f'dat {md5(od)}  spr {md5(osp)}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
