#!/usr/bin/env python3
"""Redraw existing items of a 10.98 Tibia.dat / Tibia.spr pair IN PLACE with new one-tile art (pair 53: the reward chest
38758 and the cursed chest 38642; pair 63: the 35 animated socket gems).

python3 -I redraw_items.py --dat IN.dat --spr IN.spr --out-dir OUT --item 38758=ATLAS.png --item 38642=ATLAS.png [--dry-run]
python3 -I redraw_items.py --dat IN.dat --spr IN.spr --out-dir OUT --strip 33905=gems.png@0 --strip 33906=gems.png@1 ...

Each --item is `client id=32 x 32 RGBA PNG` (alpha 0 / 255). The item keeps its id and its flag bytes (so the server's
items.otb row, light, elevation, container and the rest stay as they were); its frame group is replaced by one 1 x 1 frame,
one layer, one phase, no animation: the entry loses the 2 x 2 exact-size byte and the duration table of an animated look.
The new sprite is appended to the spr (the offset table grows by 4 bytes per new sprite; the old sprites of the item stay
in the file, unused). No id moves and no other entry changes. A sprite identical to a record of the input is reused.

Verification (always): the output dat re-parses, every entry but the redrawn ones is byte-identical, every redrawn entry
has the expected flags and group, every new sprite decodes pixel-identical to its PNG, 3,000 sampled old sprites are
unchanged. Deterministic: the same inputs give byte-identical outputs. The output spr is written in one pass (head, grown
offset table, old records, new records): about the size of the input in free disk space.
check_pair.py --old IN.dat IN.spr --allow-changed item:38758,38642 is the append-only guard of the result.

--strip ID=PNG@ROW redraws an ANIMATED item and keeps its frame group: PNG is an atlas of 32 px cells, ROW (default 0) is
the row, the phases run left to right. The item's group must be one 1 x 1 group of one layer and one pattern whose phase
count equals the cells of the row; the group is kept as it is (type, size, layers, patterns, phases, the animator head and
the duration table, the flag bytes) and only its sprite ids change: one id per phase, identical cells share one sprite, a
sprite identical to a record of the input is reused, the rest is appended in item order. Verification adds: every phase
decodes pixel-identical to its atlas cell, identical cells share an id, the group differs from the old one in its sprite
ids only. An item is either --item or --strip, not both.
"""
import argparse
import hashlib
import os
import random
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
import import_art_things as iat  # noqa: E402
import import_donor_things as idt  # noqa: E402
from datspr import Dat, Spr  # noqa: E402

STILL = {'gtype': 0, 'w': 1, 'h': 1, 'exact': 32, 'layers': 1, 'px': 1, 'py': 1, 'pz': 1, 'phases': 1, 'anim': None}


def check_cell(a, label):
    """one 32 x 32 RGBA cell: opaque or clear pixels only, not empty; colour of clear pixels zeroed"""
    if ((a[..., 3] != 0) & (a[..., 3] != 255)).any():
        raise SystemExit('%s: semi-transparent pixels' % label)
    if not (a[..., 3] == 255).any():
        raise SystemExit('%s: empty' % label)
    a = a.copy()
    a[a[..., 3] == 0] = 0
    return a


def read_art(path):
    """the 32 x 32 RGBA picture of one item; refuses anything else"""
    a = np.array(Image.open(path).convert('RGBA'))
    if a.shape != (32, 32, 4):
        raise SystemExit('%s: %d x %d, not 32 x 32' % (path, a.shape[1], a.shape[0]))
    return check_cell(a, path)


def read_strip(path, row, cache=None):
    """the cells of row ROW of an atlas of 32 px cells, left to right, each checked: [32 x 32 x 4]"""
    key = os.path.abspath(path)
    if cache is not None and key in cache:
        a = cache[key]
    else:
        a = np.array(Image.open(path).convert('RGBA'))
        if cache is not None:
            cache[key] = a
    if a.shape[0] % 32 or a.shape[1] % 32:
        raise SystemExit('%s: %d x %d, not a multiple of 32' % (path, a.shape[1], a.shape[0]))
    if not 0 <= row < a.shape[0] // 32:
        raise SystemExit('%s: row %d is not in the atlas (%d rows)' % (path, row, a.shape[0] // 32))
    return [check_cell(a[row * 32:row * 32 + 32, c * 32:c * 32 + 32], '%s row %d cell %d' % (path, row, c))
            for c in range(a.shape[1] // 32)]


def redrawn_entry(t, sid):
    """the new dat entry of item t (a parsed Thing): its flags, then one 1 x 1 still drawing sprite sid"""
    g = dict(STILL, sprites=(sid,))
    return idt.entry_bytes('item', t.flags, [g])


def parse_items(specs):
    out = {}
    for s in specs:
        k, _, v = s.partition('=')
        if not k.isdigit() or not v:
            raise SystemExit('--item wants ID=FILE.png, got %r' % s)
        if int(k) in out:
            raise SystemExit('item %s given twice' % k)
        out[int(k)] = v
    return out


def parse_strips(specs):
    """--strip ID=FILE.png[@ROW] -> {id: (file, row)}"""
    out = {}
    for s in specs:
        k, _, v = s.partition('=')
        f, _, r = v.partition('@')
        if not k.isdigit() or not f or (r and not r.isdigit()):
            raise SystemExit('--strip wants ID=FILE.png[@ROW], got %r' % s)
        if int(k) in out:
            raise SystemExit('item %s given twice' % k)
        out[int(k)] = (f, int(r) if r else 0)
    return out


def strip_entry(t, sids):
    """the new dat entry of animated item t (a parsed Thing): its flags and its one group as it is, with sprite ids sids"""
    return idt.entry_bytes('item', t.flags, [dict(t.groups[0], sprites=tuple(sids))])


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--dat', required=True)
    ap.add_argument('--spr', required=True)
    ap.add_argument('--out-dir', required=True)
    ap.add_argument('--item', action='append', default=[], metavar='ID=PNG')
    ap.add_argument('--strip', action='append', default=[], metavar='ID=PNG@ROW')
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args(argv)
    t0 = time.time()
    log = lambda s: print(s, flush=True)  # noqa: E731
    if not a.item and not a.strip:
        sys.exit('give at least one --item or --strip')
    if os.path.abspath(os.path.dirname(a.dat)) == os.path.abspath(a.out_dir):
        sys.exit('out-dir must differ from the input dir')
    want = parse_items(a.item)
    strips = parse_strips(a.strip)
    both = sorted(set(want) & set(strips))
    if both:
        sys.exit('item %d is both --item and --strip' % both[0])
    cache = {}
    # frames[cid] = the cells the item shows: one for a still, one per phase for a strip
    frames = {cid: [read_art(p)] for cid, p in want.items()}
    for cid, (p, row) in strips.items():
        frames[cid] = read_strip(p, row, cache)
    changed = sorted(frames)

    od, ospr = Dat(a.dat), Spr(a.spr)
    assert od.variant[0] == 'new' and all(od.variant[1:]) and ospr.u32count and ospr.alpha
    d = od.data
    ours = idt.parse_dat(d, idt.OUR_KINDS)
    items = {t.id: t for t in ours['item']}
    for cid in changed:
        t = items.get(cid)
        if t is None:
            sys.exit('item %d is not in the input dat' % cid)
        if idt.entry_bytes('item', t.flags, t.groups) != d[t.raw[0]:t.raw[1]]:
            sys.exit('item %d: its entry does not round-trip; refusing' % cid)
        g = t.groups[0]
        if cid in want:
            log('item %d: %dx%d, %d phase(s), %d sprite ids now -> 1x1 still' % (cid, g['w'], g['h'], g['phases'], len(g['sprites'])))
            continue
        if (len(t.groups) != 1 or (g['w'], g['h'], g['layers'], g['px'], g['py'], g['pz']) != (1,) * 6
                or len(g['sprites']) != g['phases']):
            sys.exit('item %d: --strip wants one 1x1 group of one layer and one pattern' % cid)
        if len(frames[cid]) != g['phases']:
            sys.exit('item %d: the atlas row has %d cells, the item %d phases' % (cid, len(frames[cid]), g['phases']))
        log('item %d: %d phases kept (animator and durations as they are), %d distinct cells' % (
            cid, g['phases'], len({f.tobytes() for f in frames[cid]})))

    # sprites: reuse an identical record of the input, else append (one per distinct cell, in item and phase order)
    m = ospr.m
    have = {}
    for sid in range(ospr.count, 0, -1):
        o = int(ospr.offs[sid - 1])
        if o:
            have[hashlib.md5(m[o:o + 5 + struct.unpack_from('<H', m, o + 3)[0]]).digest()] = sid
    newrecs, sids_of = [], {}
    for cid in changed:
        sids = []
        for f in frames[cid]:
            rec = iat.encode_sprite(f)
            h = hashlib.md5(rec).digest()
            if h not in have:
                newrecs.append(rec)
                have[h] = ospr.count + len(newrecs)
            sids.append(have[h])
        sids_of[cid] = tuple(sids)
    nbytes = sum(len(x) for x in newrecs)
    out_size = len(m) + 4 * len(newrecs) + nbytes
    log('sprites: %d new record(s) (%s bytes), output spr %s bytes' % (len(newrecs), f'{nbytes:,}', f'{out_size:,}'))
    if len(changed) <= 8:
        log('sprite ids: ' + ', '.join('%d -> %s' % (c, ' '.join(map(str, sids_of[c]))) for c in changed))
    if a.dry_run:
        log('dry run: nothing written')
        return 0
    st = os.statvfs(os.path.dirname(os.path.abspath(a.out_dir)) or '.')
    if st.f_bavail * st.f_frsize < out_size + (64 << 20):
        sys.exit('not enough disk space for the output spr (%s bytes)' % f'{out_size:,}')

    out = bytearray(d[:ours['item'][0].raw[0]])
    for t in ours['item']:
        if t.id in want:
            out += redrawn_entry(t, sids_of[t.id][0])
        elif t.id in strips:
            out += strip_entry(t, sids_of[t.id])
        else:
            out += d[t.raw[0]:t.raw[1]]
    rest = ours['item'][-1].raw[1]
    out += d[rest:]
    os.makedirs(a.out_dir, exist_ok=True)
    dat_path, spr_path = os.path.join(a.out_dir, 'Tibia.dat'), os.path.join(a.out_dir, 'Tibia.spr')
    open(dat_path, 'wb').write(out)
    idt.write_spr(spr_path, ospr.signature, m, ospr.count, newrecs)
    log('wrote %s (%s bytes), %s' % (dat_path, f'{len(out):,}', spr_path))

    # verification
    md, ms = Dat(dat_path), Spr(spr_path)
    assert md.variant == od.variant and md.counts == od.counts
    assert ms.count == ospr.count + len(newrecs) and ms.signature == ospr.signature and md.max_sprite <= ms.count
    nt = idt.parse_dat(bytes(out), idt.OUR_KINDS)
    for cat in idt.CATS:
        assert len(nt[cat]) == len(ours[cat])
        for to, tn in zip(ours[cat], nt[cat]):
            if cat == 'item' and to.id in want:
                assert tn.flags == to.flags, ('flags changed', to.id)
                g = tn.groups[0]
                assert len(tn.groups) == 1 and (g['w'], g['h'], g['layers'], g['px'], g['py'], g['pz'], g['phases']) == (1,) * 7
                assert g['sprites'] == sids_of[to.id], (to.id, g['sprites'])
                px = ms.sprite(sids_of[to.id][0])
                assert px is not None and (px == iat.decoded(frames[to.id][0])).all(), ('sprite differs from the art', to.id)
                continue
            if cat == 'item' and to.id in strips:
                assert tn.flags == to.flags, ('flags changed', to.id)
                og, g = to.groups[0], tn.groups[0]
                assert len(tn.groups) == 1 and {k: v for k, v in g.items() if k != 'sprites'} == \
                    {k: v for k, v in og.items() if k != 'sprites'}, ('group changed beyond its sprite ids', to.id)
                assert g['sprites'] == sids_of[to.id] and len(g['sprites']) == og['phases'], (to.id, g['sprites'])
                for ph, cell in enumerate(frames[to.id]):
                    px = ms.sprite(g['sprites'][ph])
                    assert px is not None and (px == iat.decoded(cell)).all(), ('phase differs from the atlas cell', to.id, ph)
                    for ph2 in range(ph):
                        assert (g['sprites'][ph2] == g['sprites'][ph]) == (frames[to.id][ph2].tobytes() == cell.tobytes()), \
                            ('identical cells must share a sprite, distinct ones must not', to.id, ph2, ph)
                continue
            assert out[tn.raw[0]:tn.raw[1]] == d[to.raw[0]:to.raw[1]], (cat, to.id, 'old entry changed')
    random.seed(1)
    for sid in random.sample(range(1, ospr.count + 1), min(3000, ospr.count)) + [1, ospr.count]:
        x, y = ospr.sprite(sid), ms.sprite(sid)
        assert (x is None) == (y is None) and (x is None or (x == y).all()), sid
    log('verified: output parses, every other entry byte-identical, flags kept, new sprites pixel-identical%s, 3000 old sprites unchanged (%.0fs)'
        % (' (strips: every phase equals its atlas cell, group kept but for sprite ids)' if strips else '', time.time() - t0))
    return 0


if __name__ == '__main__':
    sys.exit(main())
