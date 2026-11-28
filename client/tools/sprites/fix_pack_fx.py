#!/usr/bin/env python3
"""The rule-based fixes of the purchased-pack effects found by the O733 audit, in one step (ROADMAP O734, pair 82).

python3 -I fix_pack_fx.py build DAT SPR OUT_DIR [--dry-run] [--write-sums]
python3 -I fix_pack_fx.py check DAT SPR

Why. The O733 audit (numbers only) found 203 used effect ids of the purchased effect packs that break a house rule. The fixes
that need no pack file are done here, from the pair alone: nothing is drawn, no pixel is invented, colours never change. Three
committed tables, applied in this fixed order on one copy of the pair:
  1. dissolve   pair_fixes/dissolve_mesh.csv (O733): clean_pack_dither.py --only, the Bayer dissolve of the pair 73 imports
                (its plan is made on the input pair; the cleaned tiles become new sprite records of the listed things).
  2. centre     the rows of pair_fixes/effect_centre.csv with pair == PAIR: recentre_effects.py, the art moved by whole pixels
                inside its canvas (nothing cut off; `of` is the centre after step 1).
  3. frames     pair_fixes/pack_fx_fixes.csv: anim_fixes.py rows, ops merge (identical phases become one, the total time
                stays), clear_strays (dim isolated dots), drop_faint (pixels under alpha 40), demesh (the pair 66 mesh
                rule of clean_pack_dither.py on one thing).
Every row checks its premise, so a table of another pair stops the run. The ids, flags, sizes, patterns and layers of every
thing stay; only `merge` changes a phase count (the total time stays). Every new picture is a new sprite record after the
pair's last id; no record of the pair is rewritten, and a thing outside the tables is byte-identical.

pair_fixes/pack_fx_fixed.sums: per thing of the tables, the digest of its form in the input pair (`before`, pair 81) and after
the build (`after`). `build` refuses an output whose digests differ from it (`--write-sums` writes it instead); `check`: every
thing is in its `after` form, or in its `before` form while client_pair.PAIR_ASSETS is older than PAIR ("pending").
fixed_ids(DAT, SPR) gives the things in their `after` form: the live checks of the import tools (gen_area_fx.py, gen_gap_fx.py,
recentre_effects.py, clean_pack_dither.py) take that form as theirs.
Deterministic: the same pair and tables give the same bytes.
"""
import argparse
import hashlib
import os
import random
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import anim_fixes as AF  # noqa: E402
import clean_pack_dither as cpd  # noqa: E402
import import_donor_things as idt  # noqa: E402
import recentre_effects as RC  # noqa: E402
from datspr import Dat, Spr  # noqa: E402

PAIR = 82
FIXES = os.path.join(HERE, 'pair_fixes', 'pack_fx_fixes.csv')
SUMS = os.path.join(HERE, 'pair_fixes', 'pack_fx_fixed.sums')
CAT = {'e': 'effect', 'm': 'missile'}


# ------------------------------------------------------------------------------------------------ tables
def tables(fixes=FIXES, dissolve=cpd.ONLY, centre=RC.SPEC):
    """-> (dissolve {(t.cat, id): mesh}, centre rows of PAIR, frame rows)"""
    only = cpd.read_only(dissolve)
    crow = [r for r in RC.read_spec(centre) if r['pair'] == PAIR]
    frows = AF.read_spec(fixes)
    return only, crow, frows


def touched(only, crow, frows):
    """sorted [(kind, id)] of every thing a table names"""
    s = {(CAT[c], i) for c, i in only} | {('effect', r['id']) for r in crow} | {(r['kind'], r['id']) for r in frows}
    return sorted(s)


def read_sums(path=SUMS):
    out = {}
    if not os.path.exists(path):
        return out
    with open(path, encoding='utf-8') as f:
        for ln in f:
            ln = ln.strip()
            if ln and not ln.startswith('#'):
                kind, i, before, after = ln.split()
                out[(kind, int(i))] = (before, after)
    return out


def write_sums(rows, path=SUMS):
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write('# kind id before after: sha256 (first 24 hex) of the thing in the input pair and after fix_pack_fx.py build (O734)\n')
        for (kind, i), (b, a) in sorted(rows.items()):
            f.write('%s %d %s %s\n' % (kind, i, b, a))


# ------------------------------------------------------------------------------------------------ digests
def digest(store, groups):
    """sha256 (24 hex) of a thing's frame groups: sizes, patterns, phases, durations and every frame's pixels"""
    h = hashlib.sha256()
    for g in groups:
        h.update(struct.pack('<8I', g['w'], g['h'], g['layers'], g['px'], g['py'], g['pz'], g['phases'], len(groups)))
        h.update(repr(AF.durations(g)).encode())
        for k in AF.frames_of(g):
            cv = AF.frame(store, g, *k)
            cv[cv[..., 3] == 0] = 0
            h.update(cv.tobytes())
    return h.hexdigest()[:24]


def thing_of(things, kind, i):
    lst = things[kind]
    j = i - AF.FIRST[kind]
    if not 0 <= j < len(lst) or lst[j].id != i:
        return None
    return lst[j]


def load(dat_path, spr_path):
    d = open(dat_path, 'rb').read()
    spr = Spr(spr_path)
    if not (spr.u32count and spr.alpha):
        raise SystemExit('not an alpha u32 spr')
    return d, spr, idt.parse_dat(d, idt.OUR_KINDS)


_FORMS = {}


def tail_sums():
    """fix_dissolve_tail.py's sums (O766): {(kind, id): (before, after)}, the tail cut after this tool's fixes"""
    import fix_dissolve_tail
    return read_sums(fix_dissolve_tail.SUMS)


def stipple_sums():
    """fix_stipple.py's sums (O769): {(kind, id): (before, after)}, the stipple redrawn after this tool's fixes and the tail cut"""
    import fix_stipple
    return read_sums(fix_stipple.SUMS)


def stipple2_sums():
    """fix_stipple.py's stage 2 sums (O777): the 1/16 stage and the glow lattice redrawn on pair 89"""
    import fix_stipple
    return read_sums(fix_stipple.SUMS2)


def forms(dat_path, spr_path, sums=None, raw=False, stipple=True):
    """{(kind, id): 'after' | 'before' | None} of every thing of the sums file in this pair (cached per path and size). A thing
    whose fixed form later lost its dissolve tail (fix_dissolve_tail.py, O766) counts as 'after' unless `raw`; a thing whose
    form of this table (or its tail cut form) later had its stipple redrawn (fix_stipple.py: O769, then the stage 2 of O777
    on that form or on its own) counts as 'after'. `stipple` False chains neither redraw, 'late' only the stage 2 (the
    forms of the O769 sums themselves)."""
    sums = read_sums() if sums is None else sums
    tails = {} if raw else tail_sums()
    chain = [] if not stipple else [stipple2_sums()] if stipple == 'late' else [stipple_sums(), stipple2_sums()]
    key = (os.path.abspath(dat_path), os.path.getsize(dat_path), os.path.abspath(spr_path), os.path.getsize(spr_path),
           tuple(sorted(sums.items())), tuple(sorted(tails.items())), tuple(tuple(sorted(c.items())) for c in chain))
    if key in _FORMS:
        return _FORMS[key]
    d, spr, things = load(dat_path, spr_path)
    store = AF.Store(spr)
    out = {}
    for (kind, i), (b, a) in sums.items():
        t = thing_of(things, kind, i)
        got = digest(store, AF.TS(t).groups) if t is not None else None
        tb, ta = tails.get((kind, i), (None, None))
        mine = {a} | ({ta} if tb == a else set())
        for c in chain:
            sb, sa = c.get((kind, i), (None, None))
            if sb in mine:
                mine.add(sa)
        out[(kind, i)] = ('after' if got in mine else 'before' if got == b else None)
    _FORMS[key] = out
    return out


def fixed_ids(dat_path, spr_path):
    """{(kind, id)} of the things this pair holds in their fixed (`after`) form, with the things whose dissolve tail
    fix_dissolve_tail.py cut (O766) and the things whose stipple fix_stipple.py redrew (O769, stage 2 of O777): the live
    checks of the import tools take that form as theirs"""
    import fix_dissolve_tail
    out = {k for k, v in forms(dat_path, spr_path).items() if v == 'after'}
    import fix_stipple
    out |= {k for k, v in fix_dissolve_tail.forms(dat_path, spr_path).items() if v == 'after'}
    for st in sorted(fix_stipple.STAGES):
        out |= {k for k, v in fix_stipple.forms(dat_path, spr_path, stage=st).items() if v == 'after'}
    return out


# ------------------------------------------------------------------------------------------------ build
def dissolve_step(dat_path, spr, things, store, only, edited, log):
    """clean_pack_dither --only on the input pair; the cleaned tiles re-pointed in the listed things"""
    changed, stats, left = cpd.plan(Dat(dat_path), spr, only)
    if left:
        raise SystemExit('dissolve: %d listed things are left whole (%s): not this pair' % (len(left), sorted(left)[:3]))
    repoint = {}
    n = 0
    for (c, i) in sorted(only):
        kind = CAT[c]
        key = (kind, i)
        if key not in stats:
            continue                                  # done already (fewer than MIN_REMOVED mesh pixels)
        if key not in edited:
            edited[key] = AF.TS(thing_of(things, kind, i))
        for g in edited[key].groups:
            for j, sid in enumerate(g['sprites']):
                if sid in changed:
                    if sid not in repoint:
                        repoint[sid] = store.add(changed[sid])
                    g['sprites'][j] = repoint[sid]
                    n += 1
        edited[key].log.append(('*', 'dissolve', '%d mesh pixels' % stats[key][0], 'cleaned'))
    log('1 dissolve: %d things cleaned, %d mesh pixels removed, %d sprites, %d slots re-pointed' % (
        len(stats), sum(v[0] for v in stats.values()), len(changed), n))


def centre_step(things, store, crow, edited, log):
    eff = {i: ts for (k, i), ts in edited.items() if k == 'effect'}
    eff, lines = RC.plan(things, store, crow, eff)
    for i, ts in eff.items():
        edited[('effect', i)] = ts
    for ln in lines:
        log('  ' + ln)
    log('2 centre: %d rows' % len(crow))


def frames_step(things, store, frows, edited, log):
    AF.apply_rows(frows, things, store, log, edited)
    ops = {}
    for r in frows:
        ops[r['op']] = ops.get(r['op'], 0) + 1
    log('3 frames: %d rows (%s)' % (len(frows), ', '.join('%s %d' % kv for kv in sorted(ops.items()))))


def build(dat_path, spr_path, out_dir=None, dry_run=False, write=False, fixes=FIXES, dissolve=cpd.ONLY, centre=RC.SPEC,
          sums_path=SUMS, log=print):
    """-> {(kind, id): (before, after)}"""
    if out_dir and os.path.abspath(os.path.dirname(dat_path)) == os.path.abspath(out_dir):
        raise SystemExit('out-dir must differ from the input dir')
    only, crow, frows = tables(fixes, dissolve, centre)
    keys = touched(only, crow, frows)
    d, spr, things = load(dat_path, spr_path)
    store = AF.Store(spr)
    before = {}
    for kind, i in keys:
        t = thing_of(things, kind, i)
        if t is None:
            raise SystemExit('%s %d is not in the pair' % (kind, i))
        before[(kind, i)] = digest(store, AF.TS(t).groups)
    sums = read_sums(sums_path)
    if sums and not write and all(sums.get(k, (None, None))[1] == v for k, v in before.items()):
        log('every thing of the tables is in its fixed form already: nothing to do')
        return {k: sums[k] for k in keys}
    edited = {}
    dissolve_step(dat_path, spr, things, store, only, edited, log)
    centre_step(things, store, crow, edited, log)
    frames_step(things, store, frows, edited, log)
    for (kind, i), ts in edited.items():
        t = ts.orig
        if idt.entry_bytes(t.cat, t.flags, t.groups) != d[t.raw[0]:t.raw[1]]:
            raise SystemExit('%s %d: its entry does not round-trip; refusing' % (kind, i))
    got = {k: (before[k], digest(store, edited[k].groups) if k in edited else before[k]) for k in keys}
    same = [k for k, (b, a) in got.items() if b == a]
    if same:
        raise SystemExit('%d things of the tables do not change: %s' % (len(same), same[:5]))
    log('things changed: %d, new sprites: %d (%s bytes)' % (len(edited), len(store.recs), f'{sum(len(r) for r in store.recs):,}'))
    if write:
        write_sums(got, sums_path)
        log('wrote %s (%d things)' % (sums_path, len(got)))
    elif got != {k: sums.get(k) for k in keys}:
        bad = [k for k in keys if sums.get(k) != got[k]]
        raise SystemExit('%d things differ from %s (first %s): run with --write-sums after a review' % (
            len(bad), os.path.basename(sums_path), bad[:3]))
    if dry_run or not out_dir:
        log('dry run: nothing written')
        return got
    out_size = len(spr.m) + 4 * len(store.recs) + sum(len(r) for r in store.recs)
    os.makedirs(out_dir, exist_ok=True)
    st = os.statvfs(out_dir)
    if st.f_bavail * st.f_frsize < out_size + len(d) + (64 << 20):
        raise SystemExit('not enough disk space for the output pair (%s bytes)' % f'{out_size:,}')
    out = bytearray(d[:things['item'][0].raw[0]])
    for cat in AF.CATS:
        for t in things[cat]:
            ts = edited.get((cat, t.id))
            out += ts.entry() if ts else d[t.raw[0]:t.raw[1]]
    nd, ns = os.path.join(out_dir, 'Tibia.dat'), os.path.join(out_dir, 'Tibia.spr')
    open(nd, 'wb').write(out)
    idt.write_spr(ns, spr.signature, spr.m, spr.count, store.recs)
    log('wrote %s (%s bytes, md5 %s), %s (%s bytes); %d sprite records appended (%d to %d)' % (
        nd, f'{len(out):,}', hashlib.md5(out).hexdigest(), ns, f'{os.path.getsize(ns):,}', len(store.recs), spr.count + 1,
        spr.count + len(store.recs)))
    verify(d, bytes(out), things, edited, store, spr, ns, got, log)
    return got


def verify(d, out, things, edited, store, spr, spr_path, got, log):
    ms = Spr(spr_path)
    assert ms.count == spr.count + len(store.recs) and ms.signature == spr.signature
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
            assert tn.flags == ts.flags and len(tn.groups) == len(ts.groups), (cat, to.id)
            for gn, ge, go in zip(tn.groups, ts.groups, to.groups):
                assert list(gn['sprites']) == ge['sprites'] and gn['anim'] == ge['anim'], (cat, to.id)
                assert all(gn[k] == go[k] for k in ('w', 'h', 'layers', 'px', 'py', 'pz')), (cat, to.id)
                if gn['phases'] != go['phases']:      # only `merge` changes a phase count, and the total time stays
                    assert sum(x[1] for x in AF.durations(gn)) == sum(x[1] for x in AF.durations(go)), (cat, to.id)
    for sid, pix in store.pix.items():
        g2 = ms.sprite(sid)
        assert g2 is not None and (g2 == pix).all(), ('new sprite differs', sid)
    random.seed(1)
    for sid in random.sample(range(1, spr.count + 1), min(20000, spr.count)) + [1, spr.count]:
        x, y = int(spr.offs[sid - 1]), int(ms.offs[sid - 1])
        assert (x == 0) == (y == 0), ('slot emptiness changed', sid)
        if x:
            n = 5 + int.from_bytes(spr.m[x + 3:x + 5], 'little')
            assert spr.m[x:x + n] == ms.m[y:y + n], ('old record changed', sid)
    nstore = AF.Store(ms)
    for (kind, i), (_b, a) in got.items():
        assert digest(nstore, AF.TS(thing_of(nt, kind, i)).groups) == a, ('digest after', kind, i)
    log('verified: %d entries byte-identical, %d changed, %d new sprites decode to the pixels, 20,000 old records identical, '
        'every thing of the tables at its `after` digest' % (same, len(edited), len(store.pix)))


# ------------------------------------------------------------------------------------------------ check
def check(dat_path, spr_path, assets=None, sums_path=SUMS, log=print):
    """0 when every thing of the sums is in its fixed form (or, before pair PAIR is on windows-assets, its input form)"""
    assets = RC.pair_assets() if assets is None else assets
    sums = read_sums(sums_path)
    if not sums:
        log('%s is missing or empty' % sums_path)
        return 1
    f = forms(dat_path, spr_path, sums)
    n = {'after': 0, 'before': 0, None: 0}
    bad = []
    for k, v in sorted(f.items()):
        n[v] += 1
        if v is None or (v == 'before' and assets >= PAIR):
            bad.append('%s %d: %s' % (k[0], k[1], 'neither form' if v is None else 'the input form: the fix is due since pair %d' % PAIR))
    for b in bad:
        log(b)
    state = 'fixed' if n['after'] == len(f) else 'pending (pair %d, windows-assets has pair %d)' % (PAIR, assets) if not bad else 'NOT OK'
    log('pack fx fixes: %d things, %d fixed, %d in the input form, %d neither: %s' % (len(f), n['after'], n['before'], n[None], state))
    return 1 if bad else 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
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
    if a.cmd == 'build':
        if not a.out_dir and not a.dry_run:
            ap.error('build needs OUT_DIR or --dry-run')
        build(a.dat, a.spr, a.out_dir, a.dry_run, a.write_sums)
        return 0
    return check(a.dat, a.spr)


if __name__ == '__main__':
    sys.exit(main())
