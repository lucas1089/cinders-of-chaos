#!/usr/bin/env python3
"""The Bayer dissolve tail of the pack effects cut, in one step (ROADMAP O766, pair 85).

python3 -I fix_dissolve_tail.py scan DAT SPR [--write]
python3 -I fix_dissolve_tail.py build DAT SPR OUT_DIR [--dry-run] [--write-sums]
python3 -I fix_dissolve_tail.py check DAT SPR

Why. The pack imports (gen_pack27_fx.dissolve, used by gen_pack29_fx, gen_pack36_fx, gen_area_fx) cut a looping effect to a
one-shot whose last three phases dissolve by a 4x4 Bayer order: 3/4, 2/4 and 1/4 of the art kept. The mesh rules of pair 66
(O523) and O733 (clean_pack_dither.py) take only the lone dots of a checker or lattice: the first stage stays whole, a grid of
holes over the art, and the others leave dotted rests. Seen in the client on pair 84 (2026-11-25): effect 3036
mega_gravity_press ends in a checker grid and two frames of dots. The fix cuts the three tail phases with their time; the blank
end phase stays, so the effect still ends empty. Nothing is drawn, no pixel or colour changes, no sprite record is added.

  scan   the dissolve tail rule (anim_fixes.dissolve_tail: the signature on the last three phases with art) on every effect
         of the pair; --write writes pair_fixes/dissolve_tail.csv (anim_fixes rows, op undissolve).
  build  applies the table on a copy of the pair (anim_fixes.apply_rows), verifies it and writes OUT_DIR/Tibia.dat and a copy
         of the spr. pair_fixes/dissolve_tail.sums holds the digest (fix_pack_fx.digest) of every listed thing before (pair
         84) and after; a build whose digests differ from it stops (--write-sums writes it instead).
  check  every listed thing is in its `after` form, or in its `before` form while client_pair.PAIR_ASSETS is older than PAIR
         ("pending").
fix_pack_fx.forms and fixed_ids take a thing in its cut form as fixed, so the live checks of the import tools pass on pair 85.
Deterministic: the same pair and table give the same bytes.
"""
import argparse
import csv
import hashlib
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import anim_fixes as AF  # noqa: E402
import import_donor_things as idt  # noqa: E402

PAIR = 85
TABLE = os.path.join(HERE, 'pair_fixes', 'dissolve_tail.csv')
SUMS = os.path.join(HERE, 'pair_fixes', 'dissolve_tail.sums')


def fpf():
    import fix_pack_fx
    return fix_pack_fx


# ------------------------------------------------------------------------------------------------ scan
def scan(dat_path, spr_path, log=print):
    """[row] of every effect the tail rule finds"""
    _d, spr, things = fpf().load(dat_path, spr_path)
    store = AF.Store(spr)
    rows = []
    for t in things['effect']:
        g = t.groups[0]
        if len(t.groups) != 1 or g['phases'] < 6:
            continue
        m = AF.phase_metrics(store, g)
        tail = AF.dissolve_tail(m)
        if tail is None:
            continue
        keep = list(range(tail[0])) + list(range(tail[1], g['phases']))
        rows.append({'kind': 'effect', 'id': t.id, 'op': 'undissolve',
                     'args': 'of=%d;keep=%s' % (g['phases'], AF.keep_text(keep)),
                     'reason': 'O766: Bayer dissolve tail, phases %d-%d of %d (art %d, %d, %d)' % (
                         tail[0], tail[1] - 1, g['phases'], m[tail[0]][0], m[tail[0] + 1][0], m[tail[0] + 2][0]),
                     'review': ''})
    log('dissolve tail scan: %d effects of %d' % (len(rows), len(things['effect'])))
    return rows


def write_table(rows, path=TABLE):
    with open(path, 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=AF.SPEC_COLS, lineterminator='\n')
        w.writeheader()
        for r in rows:
            w.writerow(r)


# ------------------------------------------------------------------------------------------------ build
def build(dat_path, spr_path, out_dir=None, dry_run=False, write=False, table=TABLE, sums_path=SUMS, log=print):
    """-> {(kind, id): (before, after)}"""
    F = fpf()
    if out_dir and os.path.abspath(os.path.dirname(dat_path)) == os.path.abspath(out_dir):
        raise SystemExit('out-dir must differ from the input dir')
    rows = AF.read_spec(table)
    if any(r['op'] != 'undissolve' for r in rows):
        raise SystemExit('%s: only undissolve rows' % table)
    d, spr, things = F.load(dat_path, spr_path)
    store = AF.Store(spr)
    keys = sorted({(r['kind'], r['id']) for r in rows})
    before = {}
    for kind, i in keys:
        t = F.thing_of(things, kind, i)
        if t is None:
            raise SystemExit('%s %d is not in the pair' % (kind, i))
        before[(kind, i)] = F.digest(store, AF.TS(t).groups)
    sums = F.read_sums(sums_path)
    if sums and not write and all(sums.get(k, (None, None))[1] == v for k, v in before.items()):
        log('every thing of the table is cut already: nothing to do')
        return {k: sums[k] for k in keys}
    edited = AF.apply_rows(rows, things, store, log)
    for (kind, i), ts in edited.items():
        t = ts.orig
        if idt.entry_bytes(t.cat, t.flags, t.groups) != d[t.raw[0]:t.raw[1]]:
            raise SystemExit('%s %d: its entry does not round-trip; refusing' % (kind, i))
    if store.recs:
        raise SystemExit('the cut added %d sprite records' % len(store.recs))
    got = {k: (before[k], F.digest(store, edited[k].groups)) for k in keys}
    cut = sum(int(AF.args_of(r['args'])['of']) - edited[(r['kind'], r['id'])].groups[0]['phases'] for r in rows)
    log('dissolve tail: %d things cut, %d phases removed, no sprite record added' % (len(edited), cut))
    if write:
        F.write_sums(got, sums_path)
        with open(sums_path, encoding='utf-8') as f:
            body = f.read().split('\n', 1)[1]
        with open(sums_path, 'w', encoding='utf-8', newline='\n') as f:
            f.write('# kind id before after: sha256 (first 24 hex) of the thing in pair 84 and after fix_dissolve_tail.py build (O766)\n')
            f.write(body)
        log('wrote %s (%d things)' % (sums_path, len(got)))
    elif got != {k: sums.get(k) for k in keys}:
        bad = [k for k in keys if sums.get(k) != got[k]]
        raise SystemExit('%d things differ from %s (first %s): run with --write-sums after a review' % (
            len(bad), os.path.basename(sums_path), bad[:3]))
    if dry_run or not out_dir:
        log('dry run: nothing written')
        return got
    os.makedirs(out_dir, exist_ok=True)
    st = os.statvfs(out_dir)
    if st.f_bavail * st.f_frsize < os.path.getsize(spr_path) + len(d) + (64 << 20):
        raise SystemExit('not enough disk space for the output pair')
    out = bytearray(d[:things['item'][0].raw[0]])
    for cat in AF.CATS:
        for t in things[cat]:
            ts = edited.get((cat, t.id))
            out += ts.entry() if ts else d[t.raw[0]:t.raw[1]]
    nd, ns = os.path.join(out_dir, 'Tibia.dat'), os.path.join(out_dir, 'Tibia.spr')
    with open(nd, 'wb') as f:
        f.write(out)
    shutil.copyfile(spr_path, ns)
    log('wrote %s (%s bytes, md5 %s), %s (a copy of the input spr)' % (nd, f'{len(out):,}', hashlib.md5(out).hexdigest(), ns))
    verify(d, bytes(out), things, edited, store, ns, got, log)
    return got


def verify(d, out, things, edited, store, spr_path, got, log):
    F = fpf()
    nt = idt.parse_dat(out, idt.OUR_KINDS)
    same = 0
    for cat in AF.CATS:
        assert len(nt[cat]) == len(things[cat]), cat
        for to, tn in zip(things[cat], nt[cat]):
            ts = edited.get((cat, to.id))
            if ts is None:
                assert out[tn.raw[0]:tn.raw[1]] == d[to.raw[0]:to.raw[1]], (cat, to.id, 'old entry changed')
                same += 1
                continue
            assert tn.flags == ts.flags and len(tn.groups) == 1, (cat, to.id)
            gn, go = tn.groups[0], to.groups[0]
            assert list(gn['sprites']) == ts.groups[0]['sprites'] and gn['anim'] == ts.groups[0]['anim'], (cat, to.id)
            assert all(gn[k] == go[k] for k in ('w', 'h', 'layers', 'px', 'py', 'pz')), (cat, to.id)
            assert gn['phases'] == go['phases'] - 3, (cat, to.id, 'three phases cut')
            assert set(gn['sprites']) <= set(go['sprites']), (cat, to.id, 'a sprite that was not in the thing')
    nstore = AF.Store(F.Spr(spr_path))
    for (kind, i), (_b, a) in got.items():
        assert F.digest(nstore, AF.TS(F.thing_of(nt, kind, i)).groups) == a, ('digest after', kind, i)
    log('verified: %d entries byte-identical, %d cut by three phases, their sprites a subset of their own, every thing at its '
        '`after` digest' % (same, len(edited)))


# ------------------------------------------------------------------------------------------------ check
def assets_pair():
    import recentre_effects
    return recentre_effects.pair_assets()


def forms(dat_path, spr_path, sums_path=SUMS):
    """{(kind, id): 'after' | 'before' | None} of the things of the sums in this pair"""
    F = fpf()
    sums = F.read_sums(sums_path)
    if not sums:
        return {}
    return F.forms(dat_path, spr_path, sums, raw=True)


def check(dat_path, spr_path, assets=None, sums_path=SUMS, log=print):
    """0 when every listed thing is cut (or, before pair PAIR is on windows-assets, still whole)"""
    assets = assets_pair() if assets is None else assets
    f = forms(dat_path, spr_path, sums_path)
    if not f:
        log('%s is missing or empty' % sums_path)
        return 1
    n = {'after': 0, 'before': 0, None: 0}
    bad = []
    for k, v in sorted(f.items()):
        n[v] += 1
        if v is None or (v == 'before' and assets >= PAIR):
            bad.append('%s %d: %s' % (k[0], k[1], 'neither form' if v is None else 'the tail is there: the cut is due since pair %d' % PAIR))
    for b in bad:
        log(b)
    state = 'cut' if n['after'] == len(f) else 'pending (pair %d, windows-assets has pair %d)' % (PAIR, assets) if not bad else 'NOT OK'
    log('dissolve tail: %d things, %d cut, %d whole, %d neither: %s' % (len(f), n['after'], n['before'], n[None], state))
    return 1 if bad else 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    s = sub.add_parser('scan')
    s.add_argument('dat')
    s.add_argument('spr')
    s.add_argument('--write', action='store_true')
    b = sub.add_parser('build')
    b.add_argument('dat')
    b.add_argument('spr')
    b.add_argument('out_dir', nargs='?')
    b.add_argument('--dry-run', action='store_true')
    b.add_argument('--write-sums', action='store_true')
    c = sub.add_parser('check')
    c.add_argument('dat')
    c.add_argument('spr')
    a = ap.parse_args(argv)
    if a.cmd == 'scan':
        rows = scan(a.dat, a.spr)
        for r in rows:
            print('%s,%d,%s,%s' % (r['kind'], r['id'], r['op'], r['args']))
        if a.write:
            write_table(rows)
            print('wrote %s (%d rows)' % (TABLE, len(rows)))
        return 0
    if a.cmd == 'build':
        if not a.out_dir and not a.dry_run:
            ap.error('build needs OUT_DIR or --dry-run')
        build(a.dat, a.spr, a.out_dir, a.dry_run, a.write_sums)
        return 0
    return check(a.dat, a.spr)


if __name__ == '__main__':
    sys.exit(main())
