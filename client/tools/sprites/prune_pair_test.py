#!/usr/bin/env python3
"""Tests of prune_pair.py on a small synthetic pair (no real pair needed).

python3 -I client/tools/sprites/prune_pair_test.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_pair as cp  # noqa: E402
import check_pair_test as t  # noqa: E402
import prune_pair as pp  # noqa: E402

LOG = []


def quiet(msg):
    LOG.append(msg)


def removed_csv(c, rows):
    c.n += 1
    path = os.path.join(c.dir, f'removed{c.n}.csv')
    with open(path, 'w', encoding='utf-8') as f:
        f.write('kind,id,reason\n')
        for k, i in rows:
            f.write(f'{k},{i},test\n')
    return path


def parsed(path):
    return cp.parse_dat(open(path, 'rb').read())


def sprite_ids(things):
    out = set()
    for lst in things.values():
        for th in lst:
            for g in th.groups:
                out.update(g.sprites)
    out.discard(0)
    return out


def test_prune(c):
    dat, spr = c.pair(*t.good_parts())
    csv_ = removed_csv(c, [('item', 101), ('effect', 1)])
    out = os.path.join(c.dir, 'out')
    arch = os.path.join(c.dir, 'arch')
    pp.prune(dat, spr, csv_, out, arch, log=quiet)
    od, os_ = os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr')
    t.expect(os.path.getsize(os_) < os.path.getsize(spr), 'the pruned spr is smaller')
    sig, counts, things, end = parsed(od)
    osig, ocounts, othings, _ = parsed(dat)
    t.expect(counts == ocounts and sig == osig, 'header unchanged')
    it = things['item'][1]
    t.expect(it.id == 101 and it.groups[0].sprites == (0,), 'removed item 101 is blank, id kept')
    t.expect(it.flag('light') is not None or any(f[0] == 22 for f in it.flags), 'removed item keeps its flags')
    t.expect(things['effect'][0].groups[0].sprites == (0,), 'removed effect is blank')
    # sprites 2 and 7 were only used by removed things (2 by item 101, 7 by the effect); 4 is shared with kept things
    spr_o = pp.Spr(os_)
    t.expect(spr_o.count == 5, f'5 sprites stay (got {spr_o.count})')
    t.expect(sprite_ids(things) == set(range(1, 6)), 'new ids are 1..5 without holes')
    r = cp.check(od, os_, auras={2})
    t.expect(r.ok, f'pruned pair has no errors: {r.text()}')
    spr_o.close()
    # the archive holds the removed things under their original ids and ids of the original spr
    ad, asp = os.path.join(arch, 'Tibia.dat'), os.path.join(arch, 'Tibia.spr')
    _, _, athings, _ = parsed(ad)
    t.expect(athings['item'][1].groups[0].sprites == (2, 4), 'archive item 101 keeps its original sprite ids')
    t.expect(athings['item'][0].groups[0].sprites == (0,), 'archive: a kept item is a blank entry')
    t.expect(sprite_ids(athings) == {2, 4, 7, 6}, f'archive sprites {sorted(sprite_ids(athings))}')
    r = cp.check(ad, asp)
    t.expect(r.ok, f'archive pair has no errors: {r.text()}')


def test_idempotent(c):
    dat, spr = c.pair(*t.good_parts())
    csv_ = removed_csv(c, [('missile', 1)])
    o1, o2 = os.path.join(c.dir, 'i1'), os.path.join(c.dir, 'i2')
    pp.prune(dat, spr, csv_, o1, log=quiet)
    pp.prune(dat, spr, csv_, o2, log=quiet)
    same = all(open(os.path.join(o1, n), 'rb').read() == open(os.path.join(o2, n), 'rb').read()
               for n in ('Tibia.dat', 'Tibia.spr'))
    t.expect(same, 'two runs give the same bytes')


def test_shared_records(c):
    recs, items, outfits, effects, missiles = t.good_parts()
    dat = t.dat_bytes(items, outfits, effects, missiles)
    spr = t.spr_bytes(recs)
    # sprite 9 and 10 share one record (one offset)
    import struct
    n = 10
    base = t.spr_bytes(recs + [t.record({1: t.RED}), None], count=n)
    off = struct.unpack_from('<I', base, 8 + 4 * 8)[0]
    b = bytearray(base)
    struct.pack_into('<I', b, 8 + 4 * 9, off)
    items2 = items + [t.entry(bytes([17]), [t.group([9])]), t.entry(bytes([17]), [t.group([10])])]
    dat = t.dat_bytes(items2, outfits, effects, missiles)
    d, s = c.write(dat, bytes(b))
    out = os.path.join(c.dir, 'sh')
    pp.prune(d, s, removed_csv(c, []), out, log=quiet)
    _, _, th, _ = parsed(os.path.join(out, 'Tibia.dat'))
    o = pp.Spr(os.path.join(out, 'Tibia.spr'))
    a, bb = th['item'][2].groups[0].sprites[0], th['item'][3].groups[0].sprites[0]
    t.expect(a != bb and o.offs[a - 1] == o.offs[bb - 1], 'shared records stay shared')
    o.close()


def test_outfit(c):
    dat, spr = c.pair(*t.good_parts())
    out = os.path.join(c.dir, 'of')
    pp.prune(dat, spr, removed_csv(c, [('outfit', 1)]), out, log=quiet)
    _, _, th, _ = parsed(os.path.join(out, 'Tibia.dat'))
    o = th['outfit'][0]
    t.expect(len(o.groups) == 1 and o.groups[0].sprites == (0,), 'removed outfit has one blank group')
    t.expect(th['outfit'][1].groups[0].sprites != (0,) * 8, 'the kept outfit still draws')


def test_strip_flags(c):
    dat, spr = c.pair(*t.good_parts())
    out = os.path.join(c.dir, 'sf')
    pp.prune(dat, spr, removed_csv(c, [('item', 100)]), out, strip_flags=True, log=quiet)
    _, _, th, _ = parsed(os.path.join(out, 'Tibia.dat'))
    t.expect(th['item'][0].flags == [], '--strip-flags drops the flags')


def test_restore(c):
    dat, spr = c.pair(*t.good_parts())
    csv_ = removed_csv(c, [('item', 101), ('effect', 1)])
    out, arch, back = (os.path.join(c.dir, n) for n in ('r_out', 'r_arch', 'r_back'))
    pp.prune(dat, spr, csv_, out, arch, log=quiet)
    pp.restore(os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr'),
               os.path.join(arch, 'Tibia.dat'), os.path.join(arch, 'Tibia.spr'),
               pp.parse_ids('item:101'), back, log=quiet)
    bd, bs = os.path.join(back, 'Tibia.dat'), os.path.join(back, 'Tibia.spr')
    r = cp.check(bd, bs, auras={2})
    t.expect(r.ok, f'restored pair has no errors: {r.text()}')
    _, _, th, _ = parsed(bd)
    s = pp.Spr(bs)
    ids = th['item'][1].groups[0].sprites
    ref = pp.Spr(spr)
    t.expect(all(ref.record(old) == s.record(new) for old, new in zip((2, 4), ids)),
             'restored item draws the original records')
    t.expect(th['effect'][0].groups[0].sprites == (0,), 'the effect stays removed')
    s.close(); ref.close()


def test_errors(c):
    dat, spr = c.pair(*t.good_parts())
    bad = removed_csv(c, [('item', 5000)])
    try:
        pp.prune(dat, spr, bad, os.path.join(c.dir, 'e1'), log=quiet)
        t.expect(False, 'an id outside the dat is refused')
    except pp.PruneError:
        pass
    c.n += 1
    p = os.path.join(c.dir, f'k{c.n}.csv')
    open(p, 'w').write('kind,id,reason\nmonster,1,x\n')
    try:
        pp.read_removed(p)
        t.expect(False, 'an unknown kind is refused')
    except pp.PruneError:
        pass


def test_names(c):
    root = os.path.join(c.dir, 'repo')
    lib = os.path.join(root, 'server', 'data', 'lib')
    sc = os.path.join(root, 'server', 'data', 'scripts', 'chaos')
    os.makedirs(lib)
    os.makedirs(sc)
    os.makedirs(os.path.join(root, 'server', 'tests'))
    open(os.path.join(lib, 'chaos_x_fx_ids.lua'), 'w').write(
        'ChaosVfx.spark_n = {id = 1, dx = 0, dy = 0, ms = 1}\n'
        'ChaosVfx.ring_a = {id = 2, dx = 0, dy = 0, ms = 1}\n'
        'ChaosVfx.word_stunned = {id = 3, dx = 0, dy = 0, ms = 1}\n'
        'ChaosVfx.idle = {id = 4, dx = 0, dy = 0, ms = 1}\n'
        'ChaosVfx.cond_poison = {id = 5, dx = 0, dy = 0, ms = 1}\n'
        'ChaosVfxMissile.fan_knife = {id = 6}\n'
        'ChaosVfxMissile.bolt_fire = {id = 7}\n'
        'ChaosVfxMissile.lonely = {id = 8}\n')
    open(os.path.join(sc, 'swap.lua'), 'w').write(
        'C.spells = {[136] = {missile = {razor_disc = "fan_knife"}}}\n'      # a swap table value
        'local t = {[CONST_ANI_FIRE] = "bolt_fire"}\n'                       # a keyed value
        'local n = "word_" .. state\n'                                        # a concatenated prefix
        'local b = "spark"\n')                                               # the base of spark_n
    open(os.path.join(root, 'server', 'tests', 'x_test.lua'), 'w').write('local a = "idle", "lonely", "cond_poison"\n')
    used = pp.used_by_name(root)
    t.expect(used.get(('missile', 6)) == 'fan_knife', 'a swap table value is a reference')
    t.expect(used.get(('missile', 7)) == 'bolt_fire', 'a CONST_ANI_ keyed value is a reference')
    t.expect(('effect', 3) in used, 'a concatenated prefix word_ keeps word_stunned')
    t.expect(('effect', 1) in used, 'the base without a direction suffix keeps spark_n')
    t.expect(all(k not in used for k in (('effect', 2), ('effect', 4), ('effect', 5), ('missile', 8))),
             'unused names (also those only in a test) stay removable')
    kl = pp.keep_list()
    t.expect(kl and all(k[0] in pp.CATS for k in kl) and all(r for r in kl.values()), 'the keep file has a reason per row')
    t.expect(all(k in pp.used_by_name(root) for k in kl), 'every keep row counts as used')
    dat, spr = c.pair(*t.good_parts())
    csv_ = removed_csv(c, [('effect', 1), ('effect', 3), ('effect', 4)])
    try:
        pp.prune(dat, spr, csv_, os.path.join(c.dir, 'n1'), log=quiet, repo=root)
        t.expect(False, 'prune refuses a list that names an effect used by name')
    except pp.PruneError:
        pass
    out = os.path.join(c.dir, 'n.csv')
    dropped = pp.keep_names(csv_, root, out, log=quiet)
    t.expect(sorted(int(r['id']) for r in dropped) == [1, 3], 'keep-names drops the used effects')
    t.expect([r['id'] for r in pp.csv.DictReader(open(out))] == ['4'], 'keep-names leaves the unused one')


def main():
    c = t.Case()
    for name, fn in sorted(globals().items()):
        if name.startswith('test_') and callable(fn):
            fn(c)
    if t.FAILS:
        print(f'{len(t.FAILS)} failed')
        return 1
    print('prune_pair_test: ok')
    return 0


if __name__ == '__main__':
    sys.exit(main())
