#!/usr/bin/env python3
"""Fix the check_pair.py warnings of our 10.98 pair that show in game, in COPIES of the pair.

python3 -I fix_pair_warnings.py --ours-dat P/Tibia.dat --ours-spr P/Tibia.spr --out-dir OUT \
        [--spec pair_fixes/fixes.csv] [--changes-out pair_fixes/things_custom18_changes.csv] \
        [--expect-dat-md5 MD5[,MD5...]] [--link-spr]

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
group is a frame-group index or "*" (all groups). Outfits only for the last two kinds.

Idempotent: a fix that is already applied changes nothing, so a run on its own output gives the same files.
Outputs in --out-dir: Tibia.dat, Tibia.spr (a byte copy, or a hard link with --link-spr). --changes-out writes one CSV
row per changed field (cat, id, group, field, where, old, new, reason). Inputs are never modified. Deterministic.
Verification (always run): every changed entry re-serialises to its exact old bytes before the edit; the output
re-parses with the same counts; every thing not in the spec is byte-identical; each spec thing differs only in the
fields its fix names (flags byte-identical); the spr is byte-identical (md5). Then check_pair.py's append-only check
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


def semantic_ok(row, ot, nt):
    """the new thing differs from the old one only in what its fix may change."""
    if ot.flags != nt.flags or len(ot.groups) != len(nt.groups):
        return False
    kind = row['kind']
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


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--ours-dat', required=True)
    ap.add_argument('--ours-spr', required=True)
    ap.add_argument('--out-dir', required=True)
    ap.add_argument('--spec', default=os.path.join(HERE, 'pair_fixes', 'fixes.csv'))
    ap.add_argument('--changes-out', default=None, help='CSV of every changed field')
    ap.add_argument('--expect-dat-md5', default=None, help='fail unless the input dat has one of these md5s (comma list)')
    ap.add_argument('--link-spr', action='store_true', help='hard-link the spr instead of copying it (saves disk)')
    a = ap.parse_args(argv)

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
        old_things[(cat, tid)] = (t, [copy_group(g) for g in t.groups])
        t.groups = [copy_group(g) for g in t.groups]
        for row in rows:
            log = []
            apply_fix(row, t, spr, log)
            for gi, field, where, old, new in log:
                changes.append((cat, tid, gi, field, where, old, new, row['reason']))
        nb = groups_bytes(t)
        if nb != gb:
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
                    if not semantic_ok(row, ot0, nt):
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
