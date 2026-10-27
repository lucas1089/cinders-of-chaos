#!/usr/bin/env python3
"""Pair 51 missiles: refill the 62 blank missile ids of pair 51 (prune_pair.py of pair 50) with the best of the 169 missiles
of the two purchased sprite sources (source G and source F) that pair 50 had to skip (no free id).

python3 -I import_pair51_missiles.py --dat pair51/Tibia.dat --spr pair51/Tibia.spr --out-dir pair51b \
    --src-g-dat G.dat --src-g-spr G.spr --src-f-dat F.dat --src-f-spr F.spr [--dry-run]

Input: pair51_missiles.csv (missile_id, source, src_id, name, element, size, phases) and the `missile` rows of
pair51_removed.csv. Every missile_id must be one of those rows and still blank in the input dat (one 1x1 frame, sprite 0).
Each blank entry is replaced entirely: flags reduced to light and displacement (the missile rule of import_pair50.py),
the source's frame group (3x3 direction patterns, phases and animator) with sprite ids mapped into the spr. Sprites
identical to a record of the input are reused, the others are appended; the offset table grows by 4 bytes per new sprite
(the input spr is streamed in 16 MB chunks, never loaded). No id moves, no other entry changes.

Verification (always): the output dat re-parses and every entry but the 62 is byte-identical; every new entry has the
expected flags, groups, sizes, patterns, phases and animator; every sprite slot decodes pixel-identical to its source slot;
composed frames of all new missiles are compared; 3000 sampled old sprites are unchanged.
Deterministic: the same inputs give byte-identical outputs.
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
import numpy as np  # noqa: E402,F401
import import_donor_things as idt  # noqa: E402
import import_pair50 as ip  # noqa: E402
from datspr import Dat, Spr, TABLE_NEW  # noqa: E402

SEL = os.path.join(HERE, 'pair51_missiles.csv')
REMOVED = os.path.join(HERE, 'pair51_removed.csv')
COLS = ['missile_id', 'source', 'src_id', 'name', 'element', 'size', 'phases']
MAX_MISSILE = 253        # the protocol sends one byte, 254 is CONST_ANI_WEAPONTYPE, 255 is not used


def read_selection(path=SEL):
    with open(path, newline='', encoding='utf-8') as fh:
        rd = csv.DictReader(fh)
        assert rd.fieldnames == COLS, rd.fieldnames
        rows = [{'id': int(r['missile_id']), 'tag': r['source'], 'src_id': int(r['src_id']), 'name': r['name'],
                 'element': r['element']} for r in rd]
    return rows


def removed_missiles(path=REMOVED):
    with open(path, newline='', encoding='utf-8') as fh:
        return sorted(int(r['id']) for r in csv.DictReader(fh) if r['kind'] == 'missile')


def check_selection(rows, free):
    ids = [r['id'] for r in rows]
    if sorted(ids) != sorted(free):
        raise SystemExit('selection ids are not the freed missile ids of pair51_removed.csv')
    if len(set(ids)) != len(ids) or max(ids) > MAX_MISSILE:
        raise SystemExit('duplicate selection id, or an id above %d' % MAX_MISSILE)
    if len({r['name'] for r in rows}) != len(rows):
        raise SystemExit('missile names are not unique')
    if len({(r['tag'], r['src_id']) for r in rows}) != len(rows):
        raise SystemExit('a source missile is selected twice')


def is_blank(d, t):
    """the blank entry prune_pair.py leaves: one 1x1 frame, one phase, sprite 0 (flag bytes may stay)"""
    return t.raw[1] - 11 >= t.raw[0] and bytes(d[t.raw[1] - 11:t.raw[1]]) == ip_blank_tail()


def ip_blank_tail():
    return bytes([1, 1, 1, 1, 1, 1, 1]) + struct.pack('<I', 0)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--dat', required=True); ap.add_argument('--spr', required=True); ap.add_argument('--out-dir', required=True)
    ap.add_argument('--src-g-dat', required=True); ap.add_argument('--src-g-spr', required=True)
    ap.add_argument('--src-f-dat', required=True); ap.add_argument('--src-f-spr', required=True)
    ap.add_argument('--selection', default=SEL); ap.add_argument('--removed', default=REMOVED)
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args(argv)
    t0 = time.time()
    log = lambda s: print(s, flush=True)  # noqa: E731
    assert os.path.abspath(os.path.dirname(a.dat)) != os.path.abspath(a.out_dir), 'out-dir must differ from the input dir'

    rows = read_selection(a.selection)
    check_selection(rows, removed_missiles(a.removed))
    od = Dat(a.dat); ospr = Spr(a.spr)
    assert od.variant[0] == 'new' and all(od.variant[1:]) and ospr.u32count and ospr.alpha
    d = od.data
    ours = idt.parse_dat(d, idt.OUR_KINDS)
    for r in rows:
        t = ours['missile'][r['id'] - 1]
        assert t.id == r['id'], (t.id, r['id'])
        if not is_blank(d, t):
            raise SystemExit('missile %d is not blank in the input dat' % r['id'])
    log('input: %d missiles, spr %d sprites; %d blank slots to fill' % (len(ours['missile']), ospr.count, len(rows)))

    sources = {}
    for tag, dp, sp in (('G', a.src_g_dat, a.src_g_spr), ('F', a.src_f_dat, a.src_f_spr)):
        data, things, spr, profile = idt.open_source(dp, sp, 'library')
        spr._cache = type('NoCache', (dict,), {'get': lambda s, k, dflt=None: None, '__setitem__': lambda s, k, v: None})()
        sources[tag] = ({t.id: t for t in things['missile']}, spr)
        del data, things
    chosen = []
    for r in rows:
        tmap, sspr = sources[r['tag']]
        t = tmap.get(r['src_id'])
        if t is None:
            raise SystemExit('source %s has no missile %d' % (r['tag'], r['src_id']))
        idt.drop_empty_groups(t)
        g = t.groups[0]
        if len(t.groups) != 1 or (g['px'], g['py'], g['pz'], g['layers']) != (3, 3, 1, 1):
            raise SystemExit('missile %s%d is not a 3x3 direction missile' % (r['tag'], r['src_id']))
        if not any(idt.record(sspr, s) is not None for s in set(g['sprites']) if s):
            raise SystemExit('missile %s%d has no visible pixel' % (r['tag'], r['src_id']))
        if (g['w'] > 1 or g['h'] > 1) and g['exact'] < 32:
            g['exact'] = 32
        chosen.append((r, t, ip.our_flags(t, 'missile')))

    # sprites: reuse identical records of the input, append the rest once
    m = ospr.m
    ours_rec = {}
    for sid in range(ospr.count, 0, -1):
        o = int(ospr.offs[sid - 1])
        if o:
            ours_rec[hashlib.md5(m[o:o + 5 + struct.unpack_from('<H', m, o + 3)[0]]).digest()] = sid
    smaps = {'G': {0: 0}, 'F': {0: 0}}
    newrecs, newidx, reused = [], {}, 0
    for r, t, flags in chosen:
        smap, sspr = smaps[r['tag']], sources[r['tag']][1]
        for s in t.groups[0]['sprites']:
            if s in smap:
                continue
            rec = idt.record(sspr, s)
            if rec is None:
                smap[s] = 0
                continue
            h = hashlib.md5(rec).digest()
            if h in ours_rec:
                smap[s] = ours_rec[h]; reused += 1
            else:
                if h not in newidx:
                    newrecs.append(rec); newidx[h] = ospr.count + len(newrecs)
                smap[s] = newidx[h]
    nbytes = sum(len(x) for x in newrecs)
    out_size = len(m) + 4 * len(newrecs) + nbytes
    log('sprites: %d new records (%s bytes), %d slots reuse records of the input; output spr %s bytes'
        % (len(newrecs), f'{nbytes:,}', reused, f'{out_size:,}'))
    if a.dry_run:
        log('dry run: nothing written')
        return 0
    st = os.statvfs(os.path.dirname(os.path.abspath(a.out_dir)) or '.')
    if st.f_bavail * st.f_frsize < out_size + (64 << 20):
        raise SystemExit('not enough disk space for the output spr (%s bytes)' % f'{out_size:,}')

    # dat: replace the entries
    byid = {r['id']: (r, t, flags) for r, t, flags in chosen}
    out = bytearray(d[:ours['missile'][0].raw[0]])
    for t in ours['missile']:
        if t.id in byid:
            r, st_, flags = byid[t.id]
            out += idt.entry_bytes('missile', flags, st_.groups, smaps[r['tag']])
        else:
            out += d[t.raw[0]:t.raw[1]]
    assert ours['missile'][-1].raw[1] == len(d)
    os.makedirs(a.out_dir, exist_ok=True)
    dat_path = os.path.join(a.out_dir, 'Tibia.dat'); spr_path = os.path.join(a.out_dir, 'Tibia.spr')
    open(dat_path, 'wb').write(out)
    idt.write_spr(spr_path, ospr.signature, m, ospr.count, newrecs)
    log('wrote %s (%s bytes), %s' % (dat_path, f'{len(out):,}', spr_path))

    # verification
    md = Dat(dat_path); ms = Spr(spr_path)
    assert md.variant == od.variant and md.counts == od.counts
    assert ms.count == ospr.count + len(newrecs) and ms.signature == ospr.signature and md.max_sprite <= ms.count
    nt = idt.parse_dat(bytes(out), idt.OUR_KINDS)
    for cat in idt.CATS:
        assert len(nt[cat]) == len(ours[cat])
        for to, tn in zip(ours[cat], nt[cat]):
            if cat == 'missile' and to.id in byid:
                continue
            assert out[tn.raw[0]:tn.raw[1]] == d[to.raw[0]:to.raw[1]], (cat, to.id, 'old entry changed')
    for tag in ('G', 'F'):
        pairs = [(t, nt['missile'][r['id'] - 1], flags) for r, t, flags in chosen if r['tag'] == tag]
        ns, nf = idt.verify_things(pairs, sources[tag][1], ms, log, sample_every=1)
        log('source %s: %d missiles, %d sprite slots pixel-identical, %d composed frames identical' % (tag, len(pairs), ns, nf))
    random.seed(1)
    for sid in random.sample(range(1, ospr.count + 1), min(3000, ospr.count)) + [1, ospr.count]:
        x, y = ospr.sprite(sid), ms.sprite(sid)
        assert (x is None) == (y is None) and (x is None or (x == y).all()), sid
    log('verified: output parses, all other entries byte-identical, 3000 sampled old sprites unchanged (%.0fs)' % (time.time() - t0))
    return 0


if __name__ == '__main__':
    sys.exit(main())
