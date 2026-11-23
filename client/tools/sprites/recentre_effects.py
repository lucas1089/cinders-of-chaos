#!/usr/bin/env python3
"""Move the art of an effect inside its canvas by whole pixels, on a pair (ROADMAP O725b, pair 80).

python3 -I recentre_effects.py build DAT SPR OUT_DIR [--spec pair_fixes/effect_centre.csv]
python3 -I recentre_effects.py check DAT SPR [--spec ...]

Why. A status effect sits on a creature, so its alpha centre (every frame, weighted by alpha) must stand on the middle of the
canvas, which gen_area_fx.py sends onto the target tile (O725: effect 3036 `mega_gravity_press` stands 6.3 px down and right).
No send offset moves art by less than a tile, so the art itself moves. Nothing is drawn: the pixels are the pair's own.

The table (pair_fixes/effect_centre.csv): kind (effect), id, `shift` (dx,dy in px, whole numbers), `of` (the centre in px from the
canvas middle the row expects before), `to` (the centre it expects after), reason. For each row, every phase, pattern and layer of
the first frame group is composed into one canvas of w*32 x h*32, moved by the shift, and cut back into 32 px sprites. Rules:
  premise   the measured centre must be `of` or `to` (0.05 px): `of` is moved, `to` means the row is done and is skipped, so a
            second run changes nothing (an empty plan writes no files); any other centre stops the run (a table of another pair).
  edges     a pixel moved out of the canvas stops the run: nothing is cut off.
  append    every new picture is a new sprite record after the pair's last id (the same pixels share one record); no record of the
            pair is rewritten, and the dat only changes the sprite ids of the rows' effects (flags, sizes, animators stay).
Verification (always): the dat of every thing outside the table is byte-identical, the new entries parse with the table's ids, the
spr keeps every old record byte for byte and every new sprite decodes to the pixels asked for, the new centre is `to`.
Deterministic: the same pair and table give the same bytes.
"""
import argparse
import csv
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
import anim_fixes as AF  # noqa: E402
import import_donor_things as idt  # noqa: E402
from datspr import Spr  # noqa: E402

SPEC = os.path.join(HERE, 'pair_fixes', 'effect_centre.csv')
TOL = 0.05


def pair_of(text):
    a, b = text.split(',')
    return float(a), float(b)


def read_spec(path):
    rows = []
    with open(path, newline='', encoding='utf-8') as f:
        for r in csv.DictReader(f):
            if r['kind'] != 'effect':
                raise SystemExit('%s: kind %r is not effect' % (path, r['kind']))
            r['id'] = int(r['id'])
            dx, dy = (int(v) for v in r['shift'].split(','))
            r['dx'], r['dy'] = dx, dy
            r['of'], r['to'] = pair_of(r['of']), pair_of(r['to'])
            if max(abs(r['of'][0] + dx - r['to'][0]), abs(r['of'][1] + dy - r['to'][1])) > TOL * 2:
                raise SystemExit('effect %d: of + shift is not to' % r['id'])
            rows.append(r)
    return rows


def canvases(store, g):
    """[(frame key, canvas)] of a frame group: every phase, pattern and layer"""
    return [(k, AF.frame(store, g, *k)) for k in AF.frames_of(g)]


def centre(cvs, w, h):
    """alpha centre of the canvases (px, from the middle of the w x h tile canvas), None when blank"""
    sx = sy = tot = 0.0
    for _k, f in cvs:
        a = f[..., 3].astype(float)
        ys, xs = np.nonzero(a)
        if not len(xs):
            continue
        wt = a[ys, xs]
        sx += float((xs + 0.5) @ wt)
        sy += float((ys + 0.5) @ wt)
        tot += float(wt.sum())
    if not tot:
        return None
    return sx / tot - w * 16, sy / tot - h * 16


def moved(cv, dx, dy):
    """cv moved by (dx, dy) px; None when a pixel with alpha would leave the canvas"""
    h, w = cv.shape[:2]
    out = np.zeros_like(cv)
    ys, xs = np.nonzero(cv[..., 3])
    if len(xs) and (xs.min() + dx < 0 or xs.max() + dx >= w or ys.min() + dy < 0 or ys.max() + dy >= h):
        return None
    out[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)] = cv[max(-dy, 0):h + min(-dy, 0), max(-dx, 0):w + min(-dx, 0)]
    return out


def near(a, b):
    return a is not None and max(abs(a[0] - b[0]), abs(a[1] - b[1])) <= TOL


def plan(things, store, rows):
    """-> ({id: TS} of the effects to change, [log lines]); stops on a premise that fails"""
    edited, log = {}, []
    for r in rows:
        lst = things['effect']
        i = r['id'] - 1
        if not 0 <= i < len(lst) or lst[i].id != r['id']:
            raise SystemExit('effect %d is not in the pair' % r['id'])
        ts = AF.TS(lst[i])
        g = ts.groups[0]
        cur = centre(canvases(store, g), g['w'], g['h'])
        if near(cur, r['to']):
            log.append('effect %d: centre %.1f, %.1f is the table\'s `to`: done already, skipped' % (r['id'], cur[0], cur[1]))
            continue
        if not near(cur, r['of']):
            raise SystemExit('effect %d: centre %s is neither of %s nor to %s: not this pair' % (r['id'], cur, r['of'], r['to']))
        n = 0
        for k in AF.frames_of(g):
            cv = moved(AF.frame(store, g, *k), r['dx'], r['dy'])
            if cv is None:
                raise SystemExit('effect %d: the shift %d,%d cuts art off at an edge (frame %s); refusing' % (r['id'], r['dx'], r['dy'], k))
            n += AF.put_frame(store, g, cv, *k)
        after = centre(canvases(store, g), g['w'], g['h'])
        if not near(after, r['to']):
            raise SystemExit('effect %d: the centre after is %s, the table says %s' % (r['id'], after, r['to']))
        edited[r['id']] = ts
        log.append('effect %d: %d phases, shift %d,%d, centre %.1f, %.1f -> %.1f, %.1f, %d tiles re-pointed' % (
            r['id'], g['phases'], r['dx'], r['dy'], cur[0], cur[1], after[0], after[1], n))
    return edited, log


def load(dat_path, spr_path):
    d = open(dat_path, 'rb').read()
    spr = Spr(spr_path)
    if not (spr.u32count and spr.alpha):
        raise SystemExit('not an alpha u32 spr')
    return d, spr, idt.parse_dat(d, idt.OUR_KINDS)


def build(dat_path, spr_path, out_dir, spec=SPEC, log=print):
    if os.path.abspath(os.path.dirname(dat_path)) == os.path.abspath(out_dir):
        raise SystemExit('out-dir must differ from the input dir')
    d, spr, things = load(dat_path, spr_path)
    store = AF.Store(spr)
    rows = read_spec(spec)
    edited, lines = plan(things, store, rows)
    for ln in lines:
        log(ln)
    if not edited:
        log('nothing to do: the pair is as the table wants it, nothing written')
        return None
    for tid, ts in edited.items():
        t = ts.orig
        if idt.entry_bytes(t.cat, t.flags, t.groups) != d[t.raw[0]:t.raw[1]]:
            raise SystemExit('effect %d: its entry does not round-trip; refusing' % tid)
    out_size = len(spr.m) + 4 * len(store.recs) + sum(len(r) for r in store.recs)
    os.makedirs(out_dir, exist_ok=True)
    st = os.statvfs(out_dir)
    if st.f_bavail * st.f_frsize < out_size + (64 << 20):
        raise SystemExit('not enough disk space for the output spr (%s bytes)' % f'{out_size:,}')
    out = bytearray(d[:things['item'][0].raw[0]])
    for cat in AF.CATS:
        for t in things[cat]:
            ts = edited.get(t.id) if cat == 'effect' else None
            out += ts.entry() if ts else d[t.raw[0]:t.raw[1]]
    nd, ns = os.path.join(out_dir, 'Tibia.dat'), os.path.join(out_dir, 'Tibia.spr')
    open(nd, 'wb').write(out)
    idt.write_spr(ns, spr.signature, spr.m, spr.count, store.recs)
    log('wrote %s (%s bytes), %s (%s bytes); %d sprite records appended (%d to %d)' % (
        nd, f'{len(out):,}', ns, f'{os.path.getsize(ns):,}', len(store.recs), spr.count, spr.count + len(store.recs)))
    verify(d, bytes(out), things, edited, store, spr, ns, rows, log)
    return store


def verify(d, out, things, edited, store, spr, spr_path, rows, log):
    ms = Spr(spr_path)
    assert ms.count == spr.count + len(store.recs) and ms.signature == spr.signature
    nt = idt.parse_dat(out, idt.OUR_KINDS)
    same = 0
    for cat in AF.CATS:
        assert len(nt[cat]) == len(things[cat]), cat
        for to, tn in zip(things[cat], nt[cat]):
            ts = edited.get(to.id) if cat == 'effect' else None
            if ts is None:
                assert out[tn.raw[0]:tn.raw[1]] == d[to.raw[0]:to.raw[1]], (cat, to.id, 'old entry changed')
                same += 1
                continue
            assert tn.flags == ts.flags and len(tn.groups) == len(ts.groups), to.id
            for gn, ge, go in zip(tn.groups, ts.groups, to.groups):
                assert list(gn['sprites']) == ge['sprites'] and gn['anim'] == go['anim'], to.id
                assert all(gn[k] == go[k] for k in ('w', 'h', 'phases', 'layers', 'px', 'py', 'pz')), to.id
    for sid, pix in store.pix.items():
        got = ms.sprite(sid)
        assert got is not None and (got == pix).all(), ('new sprite differs', sid)
    for sid in range(1, spr.count + 1):          # every old record is the same bytes
        x, y = int(spr.offs[sid - 1]), int(ms.offs[sid - 1])
        assert (x == 0) == (y == 0), ('slot emptiness changed', sid)
        if x:
            n = 5 + int.from_bytes(spr.m[x + 3:x + 5], 'little')
            assert spr.m[x:x + n] == ms.m[y:y + n], ('old record changed', sid)
    nstore = AF.Store(ms)
    for r in rows:
        if r['id'] not in edited:
            continue
        g = nt['effect'][r['id'] - 1].groups[0]
        c = centre(canvases(nstore, g), g['w'], g['h'])
        assert near(c, r['to']), ('centre after', r['id'], c)
    log('verified: %d entries byte-identical, %d changed, %d new sprites decode to the pixels, %d old records identical, '
        'centres at the table\'s `to`' % (same, len(edited), len(store.pix), spr.count))


def check(dat_path, spr_path, spec=SPEC, log=print):
    """0 when every row of the table stands at its `to`"""
    d, spr, things = load(dat_path, spr_path)
    store = AF.Store(spr)
    bad = 0
    for r in read_spec(spec):
        g = AF.TS(things['effect'][r['id'] - 1]).groups[0]
        c = centre(canvases(store, g), g['w'], g['h'])
        ok = near(c, r['to'])
        bad += not ok
        log('effect %d: centre %s from the canvas middle, table says %.1f, %.1f: %s' % (
            r['id'], 'blank' if c is None else '%.1f, %.1f' % c, r['to'][0], r['to'][1], 'OK' if ok else 'NOT DONE'))
    return 1 if bad else 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('dat')
    b.add_argument('spr')
    b.add_argument('out_dir')
    b.add_argument('--spec', default=SPEC)
    c = sub.add_parser('check')
    c.add_argument('dat')
    c.add_argument('spr')
    c.add_argument('--spec', default=SPEC)
    a = ap.parse_args(argv)
    if a.cmd == 'build':
        build(a.dat, a.spr, a.out_dir, a.spec)
        return 0
    return check(a.dat, a.spr, a.spec)


if __name__ == '__main__':
    sys.exit(main())
