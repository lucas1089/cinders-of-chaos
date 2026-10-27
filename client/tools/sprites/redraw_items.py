#!/usr/bin/env python3
"""Redraw existing items of a 10.98 Tibia.dat / Tibia.spr pair IN PLACE with new one-tile art (pair 53: the reward chest
38758 and the cursed chest 38642).

python3 -I redraw_items.py --dat IN.dat --spr IN.spr --out-dir OUT --item 38758=ATLAS.png --item 38642=ATLAS.png [--dry-run]

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


def read_art(path):
    """the 32 x 32 RGBA picture of one item; refuses anything else"""
    a = np.array(Image.open(path).convert('RGBA'))
    if a.shape != (32, 32, 4):
        raise SystemExit('%s: %d x %d, not 32 x 32' % (path, a.shape[1], a.shape[0]))
    if ((a[..., 3] != 0) & (a[..., 3] != 255)).any():
        raise SystemExit('%s: semi-transparent pixels' % path)
    if not (a[..., 3] == 255).any():
        raise SystemExit('%s: empty' % path)
    a[a[..., 3] == 0] = 0
    return a


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


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--dat', required=True)
    ap.add_argument('--spr', required=True)
    ap.add_argument('--out-dir', required=True)
    ap.add_argument('--item', action='append', required=True, metavar='ID=PNG')
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args(argv)
    t0 = time.time()
    log = lambda s: print(s, flush=True)  # noqa: E731
    if os.path.abspath(os.path.dirname(a.dat)) == os.path.abspath(a.out_dir):
        sys.exit('out-dir must differ from the input dir')
    want = parse_items(a.item)
    art = {cid: read_art(p) for cid, p in want.items()}

    od, ospr = Dat(a.dat), Spr(a.spr)
    assert od.variant[0] == 'new' and all(od.variant[1:]) and ospr.u32count and ospr.alpha
    d = od.data
    ours = idt.parse_dat(d, idt.OUR_KINDS)
    items = {t.id: t for t in ours['item']}
    for cid in want:
        t = items.get(cid)
        if t is None:
            sys.exit('item %d is not in the input dat' % cid)
        if idt.entry_bytes('item', t.flags, t.groups) != d[t.raw[0]:t.raw[1]]:
            sys.exit('item %d: its entry does not round-trip; refusing' % cid)
        g = t.groups[0]
        log('item %d: %dx%d, %d phase(s), %d sprite ids now -> 1x1 still' % (cid, g['w'], g['h'], g['phases'], len(g['sprites'])))

    # sprites: reuse an identical record of the input, else append
    m = ospr.m
    recs = {cid: iat.encode_sprite(art[cid]) for cid in want}
    have = {}
    for sid in range(ospr.count, 0, -1):
        o = int(ospr.offs[sid - 1])
        if o:
            have[hashlib.md5(m[o:o + 5 + struct.unpack_from('<H', m, o + 3)[0]]).digest()] = sid
    newrecs, sid_of = [], {}
    for cid in sorted(want):
        h = hashlib.md5(recs[cid]).digest()
        if h in have:
            sid_of[cid] = have[h]
        else:
            newrecs.append(recs[cid])
            have[h] = sid_of[cid] = ospr.count + len(newrecs)
    nbytes = sum(len(x) for x in newrecs)
    out_size = len(m) + 4 * len(newrecs) + nbytes
    log('sprites: %d new record(s) (%s bytes), sprite ids %s; output spr %s bytes'
        % (len(newrecs), f'{nbytes:,}', ', '.join('%d -> %d' % kv for kv in sorted(sid_of.items())), f'{out_size:,}'))
    if a.dry_run:
        log('dry run: nothing written')
        return 0
    st = os.statvfs(os.path.dirname(os.path.abspath(a.out_dir)) or '.')
    if st.f_bavail * st.f_frsize < out_size + (64 << 20):
        sys.exit('not enough disk space for the output spr (%s bytes)' % f'{out_size:,}')

    out = bytearray(d[:ours['item'][0].raw[0]])
    for t in ours['item']:
        out += redrawn_entry(t, sid_of[t.id]) if t.id in want else d[t.raw[0]:t.raw[1]]
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
                assert g['sprites'] == (sid_of[to.id],), (to.id, g['sprites'])
                px = ms.sprite(sid_of[to.id])
                assert px is not None and (px == iat.decoded(art[to.id])).all(), ('sprite differs from the art', to.id)
                continue
            assert out[tn.raw[0]:tn.raw[1]] == d[to.raw[0]:to.raw[1]], (cat, to.id, 'old entry changed')
    random.seed(1)
    for sid in random.sample(range(1, ospr.count + 1), min(3000, ospr.count)) + [1, ospr.count]:
        x, y = ospr.sprite(sid), ms.sprite(sid)
        assert (x is None) == (y is None) and (x is None or (x == y).all()), sid
    log('verified: output parses, every other entry byte-identical, flags kept, new sprites pixel-identical, 3000 old sprites unchanged (%.0fs)'
        % (time.time() - t0))
    return 0


if __name__ == '__main__':
    sys.exit(main())
