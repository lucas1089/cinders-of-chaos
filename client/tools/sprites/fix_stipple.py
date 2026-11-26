#!/usr/bin/env python3
"""The stipple of the purchased pack effects redrawn as solid pixel art (ROADMAP O769, pair 88).

python3 -I fix_stipple.py scan DAT SPR [--write] [--out stats.csv]
python3 -I fix_stipple.py build DAT SPR OUT_DIR [--dry-run] [--write-sums]
python3 -I fix_stipple.py check DAT SPR

Why. Owner 2026-11-26 ("3 redesenha"): the dotted rests and the Bayer or checker fill inside the body of the pack effects go;
solid fills with hard alpha, the house rules of O733. The pack imports up to pair 65 cut the soft glow of a pack frame to 0 / 255
with a 4x4 Bayer threshold (gen_pack27_fx.clean_alpha before O523). Pair 66 (clean_pack_dither.py) took the lone dots of a glow
under alpha 0.5 away; a glow above 0.5 kept its art with holes on the Bayer grid (one in four or one in two pixels clear): a
stipple inside the body. O766 cut the dissolve tail only. This tool fills those holes and takes the dim lattice dots of the faint
fringe, from the pair alone: no pack art is read from outside, viewed or sent anywhere.

The rule, per frame canvas (every pattern, layer and phase of group 0; alpha > 0 is art):
  fill   a clear pixel whose four sides are art (a hole) and that has another hole on the dither grid of it: a diagonal
         neighbour (a checker) or a pixel two away along an axis or a diagonal (the 3/4 Bayer stage). A lone hole of drawn art
         (an eye, the centre of a ring) has no such partner and stays. The hole takes the colour that most of its four sides
         share (ties: the one nearest their mean), so only colours the effect already has are used, alpha 255.
  drop   a lone art pixel (no art among its 8 neighbours) with at least LATTICE_MIN lone art pixels at distance two (the lattice of
         a faint fringe, one dot per 2x2 or 4x4 cell) and darker than DROP_LUMA of the frame's art median luma: the dotted rests.
         A brighter lone pixel is a spark and stays; one pixel lines (they have a neighbour) stay.
A thing is listed when its fill pixels over all frames reach MIN_FILL and MIN_SHARE of its art (a few coincidences in drawn art
change nothing). Things with soft alpha (any 0 < alpha < 255) are never touched: the rule is for hard alpha art. Things another
tool's live check holds by its own table (OWNED) are left out. Frame counts, timing, sizes, ids and flags never change; a changed
tile becomes a new sprite record after the pair's last (Store.add), old records stay byte for byte.

  scan   the rule on every live effect and missile; --write writes pair_fixes/stipple.csv (anim_fixes rows, op unstipple,
         args fill=N;drop=M: the counts the op must find again).
  build  applies the table on a copy of the pair, verifies it and writes OUT_DIR/Tibia.dat and Tibia.spr; pair_fixes/stipple.sums
         holds the digest (fix_pack_fx.digest) of every listed thing before (pair 87) and after; a build that differs stops.
  check  every listed thing is in its `after` form, or in its `before` form while client_pair.PAIR_ASSETS is older than PAIR.
fix_pack_fx.forms and fixed_ids take a thing in its redrawn form as fixed (it was in their fixed form in pair 87); the live
checks of gen_area_fx.py, gen_gap_fx.py, gen_wst_more_fx.py and recentre_effects.py read fixed_ids, so the O735 effects 5442+ are
in scope too.
Deterministic: the same pair and table give the same bytes.
"""
import argparse
import csv
import hashlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
import anim_fixes as AF  # noqa: E402
import import_donor_things as idt  # noqa: E402

PAIR = 88
TABLE = os.path.join(HERE, 'pair_fixes', 'stipple.csv')
SUMS = os.path.join(HERE, 'pair_fixes', 'stipple.sums')
STATS_COLS = ['kind', 'id', 'art', 'fill', 'drop', 'holes_left', 'lone_left']

MIN_FILL = 24           # fill pixels over all frames of a thing, at least
MIN_SHARE = 0.004       # and this share of its art
LATTICE_MIN = 2         # lone art pixels at distance two of a dropped dot
DROP_LUMA = 0.75        # a dropped dot is darker than this share of the frame's median art luma

# ids another tool's live check holds by its own table or strips (not by fix_pack_fx.fixed_ids): left as they are
OWNED = {
    'effect': [(4090, 4101, 'loot beams O522, soft alpha'), (4743, 4744, 'gen_spell_vfx.py'), (5143, 5189, 'gen_status_vfx.py'),
               (5321, 5325, 'gen_lightning_fx.py'), (5326, 5333, 'gen_malgrath_boss.py'), (5334, 5353, 'gen_footprint_fx.py'),
               (5354, 5441, 'gen_awakened_fx.py')],
    'missile': [(43, 43, 'gen_awakened_fx.py'), (46, 46, 'gen_spell_vfx.py'), (47, 47, 'gen_awakened_fx.py'),
                (52, 52, 'gen_awakened_fx.py'), (147, 151, 'gen_awakened_fx.py')],
}


def owned(kind, i):
    return any(a <= i <= b for a, b, _r in OWNED.get(kind, ()))


def owned_extra():
    """{(kind, id)} of the donor effects (gen_donor_fx.py live) and the redrawn missiles (gen_missile_fx.py)"""
    out = set()
    for p, col in ((os.path.join(HERE, '..', '..', '..', 'server', 'data', 'spells', 'donor_fx_catalog.csv'), 'id'),
                   (os.path.join(HERE, 'art_import', 'missile_fx_p67.csv'), 'replace')):
        with open(p, newline='', encoding='utf-8') as f:
            for r in csv.DictReader(f):
                out.add((r['kind'], int(r[col])))
    return out


# ------------------------------------------------------------------------------------------------ the rule
def shift(a, dy, dx):
    """a moved by (dy, dx) on its first two axes, zeros come in"""
    h, w = a.shape[:2]
    o = np.zeros_like(a)
    o[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)] = a[max(-dy, 0):h + min(-dy, 0), max(-dx, 0):w + min(-dx, 0)]
    return o


SIDES = ((1, 0), (-1, 0), (0, 1), (0, -1))
DIAG = ((1, 1), (1, -1), (-1, 1), (-1, -1))
TWO = ((2, 0), (-2, 0), (0, 2), (0, -2), (2, 2), (2, -2), (-2, 2), (-2, -2))
RING = tuple((dy, dx) for dy in (-1, 0, 1) for dx in (-1, 0, 1) if (dy, dx) != (0, 0))


def luma(rgb):
    rgb = rgb.astype(np.float64)
    return 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]


def masks(img):
    """RGBA canvas -> (fill mask, drop mask)"""
    a = (img[..., 3] > 0).astype(np.int16)
    k4 = sum(shift(a, dy, dx) for dy, dx in SIDES)
    hole = (a == 0) & (k4 == 4)
    h16 = hole.astype(np.int16)
    partner = sum(shift(h16, dy, dx) for dy, dx in DIAG + TWO)
    fill = hole & (partner >= 1)
    k8 = k4 + sum(shift(a, dy, dx) for dy, dx in DIAG)
    lone = (a == 1) & (k8 == 0)
    drop = np.zeros(a.shape, bool)
    if lone.any():
        l16 = lone.astype(np.int16)
        near = sum(shift(l16, dy, dx) for dy, dx in TWO)
        lu = luma(img[..., :3])
        med = float(np.median(lu[a == 1]))
        drop = lone & (near >= LATTICE_MIN) & (lu < DROP_LUMA * med)
    return fill, drop


def fill_colours(img, fill):
    """[N, 3] colours for the fill pixels: the colour most of the four sides share, ties to the one nearest their mean"""
    ys, xs = np.nonzero(fill)
    h, w = fill.shape
    n = np.stack([img[np.clip(ys + dy, 0, h - 1), np.clip(xs + dx, 0, w - 1), :3].astype(np.int32) for dy, dx in SIDES], 1)
    eq = (n[:, :, None, :] == n[:, None, :, :]).all(3).sum(2)            # [N, 4] how many sides share each side's colour
    mean = n.mean(1, keepdims=True)
    dist = np.abs(n - mean).sum(2)                                      # [N, 4]
    score = eq * 100000 - dist
    pick = score.argmax(1)
    return n[np.arange(len(ys)), pick].astype(np.uint8)


def redraw(img):
    """RGBA canvas -> (redrawn canvas, fill count, drop count)"""
    fill, drop = masks(img)
    out = img.copy()
    if fill.any():
        out[..., :3][fill] = fill_colours(img, fill)
        out[..., 3][fill] = 255
    out[drop] = 0
    return out, int(fill.sum()), int(drop.sum())


def soft_alpha(store, g):
    return any(((f[..., 3] > 0) & (f[..., 3] < 255)).any() for f in (AF.frame(store, g, *k) for k in AF.frames_of(g)))


def measure(store, g):
    """(art, fill, drop, holes left, lone left) over every frame of a group"""
    art = nf = nd = hl = ll = 0
    for k in AF.frames_of(g):
        img = AF.frame(store, g, *k)
        if not img[..., 3].any():
            continue
        new, f, d = redraw(img)
        art += int((img[..., 3] > 0).sum())
        nf += f
        nd += d
        f2, d2 = masks(new)
        hl += int(f2.sum())
        ll += int(d2.sum())
    return art, nf, nd, hl, ll


def listed(art, fill):
    return fill >= MIN_FILL and fill >= MIN_SHARE * art


# ------------------------------------------------------------------------------------------------ the op (anim_fixes)
def op_unstipple(store, ts, a):
    AF.need(a, 'fill', 'drop')
    g = ts.groups[0]
    got = [0, 0]
    for k in AF.frames_of(g):
        f, d = masks(AF.frame(store, g, *k))
        got[0] += int(f.sum())
        got[1] += int(d.sum())
    if got != [int(a['fill']), int(a['drop'])]:
        raise SystemExit('%s%d: fill %d drop %d, the row says %s %s' % (ts.cat, ts.id, got[0], got[1], a['fill'], a['drop']))

    def fn(img):
        new, f, d = redraw(img)
        return new, f + d
    n = AF.map_frames(store, ts, fn)
    ts.log.append(('0', 'unstipple', 'stipple of fix_stipple.py', '%d filled, %d dots removed' % (got[0], got[1])))
    return n


# ------------------------------------------------------------------------------------------------ scan
def fpf():
    import fix_pack_fx
    return fix_pack_fx


def scan(dat_path, spr_path, log=print, stats=None):
    """[row] of every thing the rule lists"""
    _d, spr, things = fpf().load(dat_path, spr_path)
    store = AF.Store(spr)
    extra = owned_extra()
    rows, out = [], []
    skipped = {'soft': 0, 'owned': 0}
    for kind in ('effect', 'missile'):
        for t in things[kind]:
            g = t.groups[0]
            if len(t.groups) != 1 or not any(g['sprites']):
                continue
            if owned(kind, t.id) or (kind, t.id) in extra:
                skipped['owned'] += 1
                continue
            if soft_alpha(store, g):
                skipped['soft'] += 1
                continue
            art, f, d, hl, ll = measure(store, g)
            out.append({'kind': kind, 'id': t.id, 'art': art, 'fill': f, 'drop': d, 'holes_left': hl, 'lone_left': ll})
            if listed(art, f):
                rows.append({'kind': kind, 'id': t.id, 'op': 'unstipple', 'args': 'fill=%d;drop=%d' % (f, d),
                             'reason': 'O769: stipple redrawn solid (art %d, %.1f%% filled)' % (art, 100.0 * f / art),
                             'review': ''})
    if stats:
        with open(stats, 'w', newline='', encoding='utf-8') as fh:
            w = csv.DictWriter(fh, fieldnames=STATS_COLS, lineterminator='\n')
            w.writeheader()
            w.writerows(out)
    log('stipple scan: %d things listed of %d measured (%d owned by another tool, %d soft alpha)' % (
        len(rows), len(out), skipped['owned'], skipped['soft']))
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
    if any(r['op'] != 'unstipple' for r in rows):
        raise SystemExit('%s: only unstipple rows' % table)
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
        log('every thing of the table is redrawn already: nothing to do')
        return {k: sums[k] for k in keys}
    edited = AF.apply_rows(rows, things, store, log)
    nf = sum(int(AF.args_of(r['args'])['fill']) for r in rows)
    nd = sum(int(AF.args_of(r['args'])['drop']) for r in rows)
    log('stipple: %d things redrawn, %d pixels filled, %d dots removed, %d sprite records appended' % (
        len(rows), nf, nd, len(store.recs)))
    for (kind, i), ts in edited.items():
        t = ts.orig
        if idt.entry_bytes(t.cat, t.flags, t.groups) != d[t.raw[0]:t.raw[1]]:
            raise SystemExit('%s %d: its entry does not round-trip; refusing' % (kind, i))
    got = {k: (before[k], F.digest(store, edited[k].groups)) for k in keys}
    same = [k for k, (b, a) in got.items() if b == a]
    if same:
        raise SystemExit('%d things of the table do not change: %s' % (len(same), same[:5]))
    if write:
        with open(sums_path, 'w', encoding='utf-8', newline='\n') as f:
            f.write('# kind id before after: sha256 (first 24 hex) of the thing in pair 87 and after fix_stipple.py build (O769)\n')
            for (kind, i), (b, a) in sorted(got.items()):
                f.write('%s %d %s %s\n' % (kind, i, b, a))
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
    extra = 4 * len(store.recs) + sum(len(r) for r in store.recs)
    if st.f_bavail * st.f_frsize < os.path.getsize(spr_path) + extra + len(d) + (64 << 20):
        raise SystemExit('not enough disk space for the output pair')
    out = bytearray(d[:things['item'][0].raw[0]])
    for cat in AF.CATS:
        for t in things[cat]:
            ts = edited.get((cat, t.id))
            out += ts.entry() if ts else d[t.raw[0]:t.raw[1]]
    nd_path, ns = os.path.join(out_dir, 'Tibia.dat'), os.path.join(out_dir, 'Tibia.spr')
    with open(nd_path, 'wb') as f:
        f.write(out)
    idt.write_spr(ns, spr.signature, spr.m, spr.count, store.recs)
    log('wrote %s (%s bytes, md5 %s), %s (%s bytes; %d sprite records appended, %d to %d)' % (
        nd_path, f'{len(out):,}', hashlib.md5(out).hexdigest(), ns, f'{os.path.getsize(ns):,}', len(store.recs),
        spr.count + 1, spr.count + len(store.recs)))
    verify(d, bytes(out), things, edited, store, ns, got, log, spr=spr)
    return got


def verify(d, out, things, edited, store, spr_path, got, log, spr=None):
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
            assert tn.flags == ts.flags == list(to.flags) and len(tn.groups) == 1, (cat, to.id)
            gn, go = tn.groups[0], to.groups[0]
            assert gn['anim'] == go['anim'], (cat, to.id, 'timing changed')
            assert all(gn[k] == go[k] for k in ('w', 'h', 'layers', 'px', 'py', 'pz', 'phases')), (cat, to.id)
    ms = F.Spr(spr_path)
    assert ms.count == spr.count + len(store.recs) and ms.signature == spr.signature
    for sid, pix in store.pix.items():
        g2 = ms.sprite(sid)
        assert g2 is not None and (g2 == pix).all(), ('new sprite differs', sid)
    import random
    random.seed(1)
    for sid in random.sample(range(1, spr.count + 1), min(20000, spr.count)) + [1, spr.count]:
        x, y = int(spr.offs[sid - 1]), int(ms.offs[sid - 1])
        assert (x == 0) == (y == 0), ('slot emptiness changed', sid)
        if x:
            n = 5 + int.from_bytes(spr.m[x + 3:x + 5], 'little')
            assert spr.m[x:x + n] == ms.m[y:y + n], ('old record changed', sid)
    nstore = AF.Store(ms)
    for (kind, i), (_b, a) in got.items():
        assert F.digest(nstore, AF.TS(F.thing_of(nt, kind, i)).groups) == a, ('digest after', kind, i)
    log('verified: %d entries byte-identical, %d changed (same sizes, phases and timing; new sprites decode as built, old '
        'records unchanged), every thing at its `after` digest' % (same, len(edited)))


# ------------------------------------------------------------------------------------------------ check
def read_sums(path=SUMS):
    return fpf().read_sums(path)


def forms(dat_path, spr_path, sums_path=SUMS):
    """{(kind, id): 'after' | 'before' | None} of the things of the sums in this pair"""
    sums = read_sums(sums_path)
    if not sums:
        return {}
    return fpf().forms(dat_path, spr_path, sums, raw=True, stipple=False)


def check(dat_path, spr_path, assets=None, sums_path=SUMS, log=print):
    """0 when every listed thing is redrawn (or, before pair PAIR is on windows-assets, still in its pair 87 form)"""
    if assets is None:
        import recentre_effects
        assets = recentre_effects.pair_assets()
    f = forms(dat_path, spr_path, sums_path)
    if not f:
        log('%s is missing or empty' % sums_path)
        return 1
    n = {'after': 0, 'before': 0, None: 0}
    bad = []
    for k, v in sorted(f.items()):
        n[v] += 1
        if v is None or (v == 'before' and assets >= PAIR):
            bad.append('%s %d: %s' % (k[0], k[1], 'neither form' if v is None else 'the stipple is there: due since pair %d' % PAIR))
    for b in bad:
        log(b)
    state = 'redrawn' if n['after'] == len(f) else 'pending (pair %d, windows-assets has pair %d)' % (PAIR, assets) if not bad else 'NOT OK'
    log('stipple: %d things, %d redrawn, %d as before, %d neither: %s' % (len(f), n['after'], n['before'], n[None], state))
    return 1 if bad else 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    s = sub.add_parser('scan')
    s.add_argument('dat')
    s.add_argument('spr')
    s.add_argument('--write', action='store_true')
    s.add_argument('--out')
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
        rows = scan(a.dat, a.spr, stats=a.out)
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
