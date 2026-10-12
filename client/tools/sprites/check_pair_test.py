#!/usr/bin/env python3
"""Tests of check_pair.py on small synthetic pairs (no real pair needed, no numpy / Pillow).

python3 -I client/tools/sprites/check_pair_test.py
"""
import os
import struct
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_pair as cp  # noqa: E402

SIG_DAT, SIG_SPR = 0x42A3, 0x57BBD603
RED, YELLOW = (255, 0, 0, 255), (255, 255, 0, 255)


def record(pixels):
    """our spr record: colour key, u16 size, runs of (u16 transparent, u16 coloured, RGBA pixels).
    pixels: {index 0..1023: (r, g, b, a)}"""
    body = bytearray()
    i = 0
    idx = sorted(pixels)
    while idx:
        start = idx[0]
        run = [start]
        while len(run) < len(idx) and idx[len(run)] == start + len(run):
            run.append(idx[len(run)])
        body += struct.pack('<HH', start - i, len(run))
        for k in run:
            body += bytes(pixels[k])
        i = start + len(run)
        idx = idx[len(run):]
    return b'\xff\x00\xff' + struct.pack('<H', len(body)) + bytes(body)


def spr_bytes(records, count=None):
    """records: list of bytes or None (empty slot), ids 1..n"""
    n = len(records) if count is None else count
    head = 8 + 4 * n
    offs, blob, pos = [], bytearray(), head
    for r in records:
        if r is None:
            offs.append(0)
        else:
            offs.append(pos); blob += r; pos += len(r)
    offs += [0] * (n - len(records))
    return struct.pack('<II', SIG_SPR, n) + struct.pack(f'<{n}I', *offs) + bytes(blob)


def group(sprites, w=1, h=1, layers=1, px=1, py=1, pz=1, phases=1, gtype=None, anim=None):
    e = bytearray()
    if gtype is not None:
        e.append(gtype)
    e += bytes([w, h])
    if w > 1 or h > 1:
        e.append(32 * max(w, h))
    e += bytes([layers, px, py, pz, phases])
    if phases > 1:
        asyn, loop, start, durs = anim or (1, 0, 0, [100] * (2 * phases))
        e += struct.pack('<Bib', asyn, loop, start) + struct.pack(f'<{2 * phases}I', *durs)
    assert len(sprites) == w * h * layers * px * py * pz * phases, (len(sprites), w, h, layers, px, py, pz, phases)
    return bytes(e) + struct.pack(f'<{len(sprites)}I', *sprites)


def entry(flags=b'', groups=(), outfit=False):
    e = bytes(flags) + b'\xff'
    if outfit:
        e += bytes([len(groups)])
    return e + b''.join(groups)


def dat_bytes(items, outfits, effects, missiles, counts=None):
    c = counts or (99 + len(items), len(outfits), len(effects), len(missiles))
    return struct.pack('<IHHHH', SIG_DAT, *c) + b''.join(items + outfits + effects + missiles)


def good_parts():
    """a small valid pair: 2 items, 2 outfits (one with a colour mask), 1 effect, 1 missile, 8 sprites."""
    recs = [record({0: RED, 1: RED, 40: (10, 20, 30, 255)}),        # 1 art
            record({5: (200, 100, 50, 128)}),                         # 2 art
            record({0: YELLOW, 1: RED}),                              # 3 mask (template colours)
            record({100 + k: (10 * k, 2, 3, 255) for k in range(20)}), # 4 art (20 shades)
            None,                                                     # 5 empty slot (unused)
            record({200: (9, 9, 9, 255)}),                            # 6 art
            record({300: (7, 7, 7, 255)}),                            # 7 art
            record({7 + k: (90, 4 * k, 70, 255) for k in range(20)})]  # 8 art: an aura's front layer
    items = [entry(bytes([17]), [group([1])]),                                         # 100 pickupable
             entry(bytes([22]) + struct.pack('<HH', 3, 200), [group([2, 4], phases=2)])]  # 101 light, animated
    outfits = [entry(bytes([25]) + struct.pack('<hh', 8, 8),                           # 1: 2 layers, idle + walk
                     [group([1, 3] * 4, layers=2, px=4, gtype=0),
                      group([1, 3] * 8, layers=2, px=4, phases=2, gtype=1)], outfit=True),
               entry(bytes([28]), [group([6, 8] * 4, layers=2, px=4, gtype=1)], outfit=True)]  # 2: aura (front layer)
    effects = [entry(b'', [group([7, 6, 4], phases=3)])]
    missiles = [entry(b'', [group([4] * 9, px=3, py=3)])]
    return recs, items, outfits, effects, missiles


class Case:
    def __init__(self):
        self.dir = tempfile.mkdtemp(prefix='check_pair_test_')
        self.n = 0

    def write(self, dat, spr):
        self.n += 1
        d = os.path.join(self.dir, f'p{self.n}')
        os.makedirs(d)
        open(os.path.join(d, 'Tibia.dat'), 'wb').write(dat)
        open(os.path.join(d, 'Tibia.spr'), 'wb').write(spr)
        return os.path.join(d, 'Tibia.dat'), os.path.join(d, 'Tibia.spr')

    def pair(self, recs, items, outfits, effects, missiles, counts=None, spr=None):
        return self.write(dat_bytes(items, outfits, effects, missiles, counts), spr or spr_bytes(recs))


def run(c, *paths, **kw):
    kw.setdefault('auras', {2})
    return cp.check(*paths, **kw)


FAILS = []


def expect(cond, what):
    if not cond:
        FAILS.append(what)
        print('FAIL', what)


def test_good(c):
    p = c.pair(*good_parts())
    r = run(c, *p)
    expect(r.ok, f'good pair has no errors: {r.text()}')
    expect(not r.count('warning'), f'good pair has no warnings: {r.text()}')
    expect('spr-unused' not in r.codes('info'), 'every record of the good pair is used')
    expect('spr-empty-slots' in r.codes('info'), 'the empty slot 5 is reported as info')
    r = run(c, *p, auras=set())
    expect('mask-not-mask' in r.codes('warning'), 'an aura not listed as aura: its front layer is not a mask')
    expect(cp.main([*p, '--aura-looks', '2']) == 0, 'CLI exit 0 on a good pair')


def test_counts(c):
    recs, items, outfits, effects, missiles = good_parts()
    # header says one more item than written: everything after shifts, the parse runs off the end
    p = c.pair(recs, items, outfits, effects, missiles, counts=(102, 2, 1, 1))
    r = run(c, *p)
    expect('dat-structure' in r.codes('error'), f'header count too high: {r.text()}')
    expect(cp.main(list(p)) == 1, 'CLI exit 1 on errors')
    # header says one missile less: bytes left over
    p = c.pair(recs, items, outfits, effects, missiles, counts=(101, 2, 1, 0))
    expect('dat-trailing' in run(c, *p).codes('error'), 'header count too low: trailing bytes')
    p = c.pair(recs, items, outfits, effects, missiles, counts=(101, 0xFFFF, 1, 1))
    expect('dat-structure' in run(c, *p).codes('error'), 'count 65535 is refused')
    # wrong sprite count in one entry: one sprite id more than the dims say. The client reads the extra id as the next
    # entry's flags; here it reads as clip + ground on an outfit, which the item-only flag check reports.
    bad = list(items)
    bad[1] = bad[1] + struct.pack('<I', 1)
    p = c.pair(recs, bad, outfits, effects, missiles)
    r = run(c, *p)
    expect('flag-category' in r.codes('warning'), f'an extra sprite id shows as item flags on an outfit: {r.text()}')
    # the last entry one sprite id short: truncated
    p = c.write(dat_bytes(items, outfits, effects, missiles)[:-4], spr_bytes(recs))
    expect('dat-structure' in run(c, *p).codes('error'), 'truncated dat')
    # sprite id above the spr count
    bad = [items[0], entry(b'', [group([99])])]
    p = c.pair(recs, bad, outfits, effects, missiles)
    expect('sprite-range' in run(c, *p).codes('error'), 'sprite id above the spr count')
    # a 0 in the dims
    bad = [items[0], entry(b'', [bytes([1, 1, 1, 1, 1, 1, 0])])]
    p = c.pair(recs, bad, outfits, effects, missiles)
    expect('dat-structure' in run(c, *p).codes('error'), 'phase count 0 is refused')


def test_flags(c):
    recs, items, outfits, effects, missiles = good_parts()
    p = c.pair(recs, [entry(bytes([50]), [group([1])]), items[1]], outfits, effects, missiles)
    expect('flag-unknown' in run(c, *p).codes('error'), 'unknown flag byte')
    p = c.pair(recs, [entry(bytes([41]), [group([1])]), items[1]], outfits, effects, missiles)
    expect('flag-not-1098' in run(c, *p).codes('error'), 'byte 41 is not a 10.98 flag')
    p = c.pair(recs, [entry(bytes([254, 17]), [group([1])]), items[1]], outfits, effects, missiles)
    r = run(c, *p)
    expect(r.ok and 'flag-order' in r.codes('warning'), f'254 is valid, out of order is a warning: {r.text()}')
    p = c.pair(recs, [entry(bytes([17, 17]), [group([1])]), items[1]], outfits, effects, missiles)
    expect('flag-duplicate' in run(c, *p).codes('warning'), 'duplicate flag')
    p = c.pair(recs, [entry(bytes([17] * 300), [group([1])]), items[1]], outfits, effects, missiles)
    expect('dat-structure' in run(c, *p).codes('error'), 'no end byte within 255 flags')
    seat = bytes([39]) + struct.pack('<8h', 20, -8, 14, -8, 25, -20, 12, -18)
    neg = bytes([25]) + struct.pack('<hh', -32, -32)
    o_seated = entry(neg + seat, [group([1, 3] * 4, layers=2, px=4, gtype=0)], outfit=True)
    p = c.pair(recs, items, [o_seated, outfits[1]], effects, missiles)
    r = run(c, *p)
    expect(r.ok and not r.count('warning'), f'a seat on a negative-displacement mount is fine: {r.text()}')
    o_pos = entry(bytes([25]) + struct.pack('<hh', 8, 8) + seat, [group([1, 3] * 4, layers=2, px=4, gtype=0)], outfit=True)
    p = c.pair(recs, items, [o_pos, outfits[1]], effects, missiles)
    expect('seat-unused' in run(c, *p).codes('warning'), 'seat without negative displacement')
    p = c.pair(recs, [entry(seat, [group([1])]), items[1]], outfits, effects, missiles)
    expect('seat-not-outfit' in run(c, *p).codes('warning'), 'seat on an item')
    p = c.pair(recs, [entry(bytes([25]) + struct.pack('<hh', 300, 0), [group([1])]), items[1]], outfits, effects, missiles)
    expect('displacement-range' in run(c, *p).codes('warning'), 'odd displacement')
    p = c.pair(recs, [entry(bytes([26]) + struct.pack('<H', 200), [group([1])]), items[1]], outfits, effects, missiles)
    expect('elevation-high' in run(c, *p).codes('warning'), 'odd elevation')
    market = bytes([34]) + struct.pack('<HHHH', 1, 100, 100, 4) + b'Orb!' + struct.pack('<HH', 0, 0)
    p = c.pair(recs, [entry(market + bytes([35]) + struct.pack('<H', 1), [group([1])]), items[1]], outfits, effects, missiles)
    r = run(c, *p)
    expect(r.ok and not r.count('warning'), f'market and default action payloads parse: {r.text()}')


def test_animation(c):
    recs, items, outfits, effects, missiles = good_parts()
    p = c.pair(recs, [items[0], entry(b'', [group([2, 4], phases=2, anim=(1, 0, 2, [100] * 4))])], outfits, effects, missiles)
    expect('anim-start' in run(c, *p).codes('error'), 'start phase out of range')
    p = c.pair(recs, [items[0], entry(b'', [group([2, 4], phases=2, anim=(1, 0, -1, [0, 0, 200, 100]))])],
               outfits, effects, missiles)
    r = run(c, *p)
    expect(r.ok and {'anim-zero', 'anim-min-max'} <= r.codes('warning'), f'zero and min > max durations: {r.text()}')
    p = c.pair(recs, [items[0], entry(b'', [group([2, 4], phases=2, anim=(5, -3, 0, [100] * 4))])], outfits, effects, missiles)
    expect({'anim-async', 'anim-loop'} <= run(c, *p).codes('warning'), 'odd async byte and loop count')
    mixed = entry(b'', [group([1, 3] * 4, layers=2, px=4, gtype=0), group([1] * 4, px=4, gtype=1)], outfit=True)
    p = c.pair(recs, items, [mixed, outfits[1]], effects, missiles)
    expect('group-mismatch' in run(c, *p).codes('warning'), 'groups with different layers')
    p = c.pair(recs, items, outfits, effects, [entry(b'', [group([4])])])
    expect('missile-patterns' in run(c, *p).codes('warning'), 'missile without 3x3 patterns')


def test_masks(c):
    recs, items, outfits, effects, missiles = good_parts()
    nomask = entry(b'', [group([1, 0] * 4, layers=2, px=4, gtype=0)], outfit=True)
    p = c.pair(recs, items, [nomask, outfits[1]], effects, missiles)
    expect('mask-empty' in run(c, *p).codes('warning'), 'empty mask layer')
    art = entry(b'', [group([1, 4] * 4, layers=2, px=4, gtype=0)], outfit=True)
    p = c.pair(recs, items, [art, outfits[1]], effects, missiles)
    expect('mask-not-mask' in run(c, *p).codes('warning'), 'shaded art in the mask layer')
    recs2 = recs + [record({0: (0, 255, 255, 255), 1: YELLOW}), record({0: (7, 7, 7, 255), 1: RED})]
    stray = entry(b'', [group([1, 10] * 4, layers=2, px=4, gtype=0)], outfit=True)
    p = c.pair(recs2, items, [stray, outfits[1]], effects, missiles)
    r = run(c, *p)
    expect('mask-stray-colours' in r.codes('info') and not r.count('warning'), f'a few stray mask pixels: info {r.text()}')
    cyan = entry(b'', [group([1, 9] * 4, layers=2, px=4, gtype=0)], outfit=True)
    p = c.pair(recs2, items, [cyan, outfits[1]], effects, missiles)
    r = run(c, *p)
    expect(r.ok and 'mask-odd-colours' in r.codes('info') and not r.count('warning'), f'pure odd colours: info {r.text()}')
    p = c.pair(recs, items, [outfits[0], outfits[1], entry(b'', [bytes([0]) + group([0])], outfit=True)], effects, missiles)
    r = run(c, *p)
    expect('blank-entry' in r.codes('info') and r.ok, 'blank padding entry is info')
    p = c.pair(recs, [items[0], entry(bytes([17]), [group([0, 0], phases=2)])], outfits, effects, missiles)
    expect('thing-empty' in run(c, *p).codes('warning'), 'a non-blank thing with no sprite')
    p = c.pair(recs, [items[0], entry(b'', [group([5])])], outfits, effects, missiles)
    expect('sprite-empty-slot' in run(c, *p).codes('warning'), 'sprite id with no record')


def test_spr(c):
    recs, items, outfits, effects, missiles = good_parts()
    good = spr_bytes(recs)
    # truncated file: the last record is cut
    p = c.pair(recs, items, outfits, effects, missiles, spr=good[:-3])
    expect('spr-truncated' in run(c, *p).codes('error'), 'truncated last sprite')
    # a record whose runs need more bytes than its size says
    bad = list(recs)
    r1 = bytearray(recs[0]); struct.pack_into('<H', r1, 3, len(recs[0]) - 5 - 2); bad[0] = bytes(r1)
    p = c.pair(bad, items, outfits, effects, missiles)
    expect('spr-bad-runs' in run(c, *p).codes('error'), 'record shorter than its runs')
    # runs that paint more than 1024 pixels
    over = b'\xff\x00\xff' + struct.pack('<H', 8) + struct.pack('<HH', 1024, 1) + bytes((1, 2, 3, 255))
    p = c.pair([over] + recs[1:], items, outfits, effects, missiles)
    expect('spr-bad-runs' in run(c, *p).codes('error'), 'pixel runs past 32x32')
    # offset into the table
    t = bytearray(good); struct.pack_into('<I', t, 8, 10)
    p = c.pair(recs, items, outfits, effects, missiles, spr=bytes(t))
    expect('spr-offset-table' in run(c, *p).codes('error'), 'offset into the table')
    # count larger than the table
    t = bytearray(good); struct.pack_into('<I', t, 4, 10 ** 6)
    p = c.pair(recs, items, outfits, effects, missiles, spr=bytes(t))
    expect('spr-header' in run(c, *p).codes('error'), 'table does not fit')
    # an unused record
    p = c.pair(recs + [record({1: RED})], items, outfits, effects, missiles)
    r = run(c, *p)
    expect(r.ok and 'spr-unused' in r.codes('info'), 'unused record is info')
    # RGB records are detected
    rgb = [b'\xff\x00\xff' + struct.pack('<H', 7) + struct.pack('<HH', 3, 1) + bytes((1, 2, 3))] * 8
    p = c.pair(rgb, items, outfits, effects, missiles)
    r = run(c, *p)
    expect('RGB records' in r.text() and 'spr-bad-runs' not in r.codes('error'), f'RGB spr detected: {r.text()}')


def test_append(c):
    recs, items, outfits, effects, missiles = good_parts()
    old = c.pair(recs, items, outfits, effects, missiles)
    # good: one item, one outfit and two sprites appended
    recs2 = recs + [record({9: RED}), record({10: RED})]
    items2 = items + [entry(bytes([17]), [group([9])])]
    outfits2 = outfits + [entry(b'', [group([10] * 4, px=4, gtype=0)], outfit=True)]
    new = c.pair(recs2, items2, outfits2, effects, missiles)
    r = run(c, *new, old=old)
    expect(r.ok, f'pure append passes: {r.text()}')
    r = run(c, *new, old=old, new_only=True)
    expect(r.ok and 'append-only: 6 old things and 8 old sprites compared' in r.text(), f'new-only mode: {r.text()}')
    rep = cp.check_append_only(*old, *new, log=lambda s: None)
    expect(rep.ok, 'importer hook passes on a pure append')
    # an old item changed
    items3 = [entry(bytes([17, 18]), [group([1])])] + items2[1:]
    new = c.pair(recs2, items3, outfits2, effects, missiles)
    expect('append-thing-changed' in run(c, *new, old=old).codes('error'), 'changed old item')
    r = run(c, *new, old=old, allow_changed={('item', 100)})
    expect(r.ok and 'append-allowed-change' in r.codes('info'), f'--allow-changed lets it pass: {r.text()}')
    try:
        cp.check_append_only(*old, *new, log=lambda s: None)
        expect(False, 'importer hook must exit on a changed old thing')
    except SystemExit:
        pass
    # an old sprite changed (same size, other colour)
    recs3 = list(recs2); recs3[0] = record({0: YELLOW, 1: RED, 40: (10, 20, 30, 255)})
    new = c.pair(recs3, items2, outfits2, effects, missiles)
    expect('append-sprite-changed' in run(c, *new, old=old).codes('error'), 'changed old sprite')
    # an old empty slot filled
    recs4 = list(recs2); recs4[4] = record({3: RED})
    new = c.pair(recs4, items2, outfits2, effects, missiles)
    expect('append-sprite-changed' in run(c, *new, old=old).codes('error'), 'old empty sprite slot filled')
    # a thing removed (fewer missiles) and sprites removed
    new = c.pair(recs[:6], items2, outfits2, effects, [])
    r = run(c, *new, old=old)
    expect({'append-count', 'append-spr-count'} <= r.codes('error'), f'removed things and sprites: {r.text()}')
    # inserted in the middle: every later outfit moves
    outfits5 = [outfits2[2]] + outfits
    new = c.pair(recs2, items2, outfits5, effects, missiles)
    expect('append-thing-changed' in run(c, *new, old=old).codes('error'), 'insert instead of append')
    # other signature
    d = bytearray(dat_bytes(items2, outfits2, effects, missiles)); struct.pack_into('<I', d, 0, 0x1234)
    new = c.write(bytes(d), spr_bytes(recs2))
    expect('append-dat-signature' in run(c, *new, old=old).codes('error'), 'dat signature changed')
    expect(cp.parse_allow('outfit:1561,2132-2134;item:100') ==
           {('outfit', 1561), ('outfit', 2132), ('outfit', 2133), ('outfit', 2134), ('item', 100)}, 'parse_allow')


def main():
    c = Case()
    for f in (test_good, test_counts, test_flags, test_animation, test_masks, test_spr, test_append):
        f(c)
    import shutil
    shutil.rmtree(c.dir, ignore_errors=True)
    if FAILS:
        print(f'{len(FAILS)} failures')
        return 1
    print('check_pair_test: all passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
