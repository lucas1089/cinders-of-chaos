#!/usr/bin/env python3
"""Cut a small 10.98 dat out of a donor dat whose items carry flags datspr.py cannot read, keeping only the given
outfits, so import_outfits.py can read it.

usage: python3 -I donor_subset.py DONOR.dat OUT.dat 4212,4220,3482

The donor must be a 10.98 extended dat (u32 sprite ids, outfit frame groups, frame durations when animated). Its
entries are walked with the 10.98 payload lengths (a flag byte outside the 10.98 table is taken as carrying no
payload); the walk must end exactly at the end of the file. The output keeps the donor's outfit numbering: the wanted
outfits are copied byte for byte (their flag bytes must all be in the 10.98 table), every other outfit becomes an empty
1x1 entry, there is one dummy item and no effects or missiles. Use it with the donor's .spr unchanged.
"""
import struct
import sys

LEN = {0: 2, 8: 2, 9: 2, 22: 4, 25: 4, 26: 2, 29: 2, 30: 2, 33: 2, 35: 2}  # payload bytes per flag (34 = market)
KNOWN = set(range(0, 39)) | {254}
EMPTY_GROUP = bytes([1, 1, 1, 1, 1, 1, 1]) + b'\0\0\0\0'  # 1x1, 1 layer, 1x1x1 patterns, 1 phase, sprite 0


def main(argv):
    if len(argv) != 3:
        print(__doc__)
        return 2
    d = open(argv[0], 'rb').read()
    want = {int(x) for x in argv[2].split(',')}
    sig, ni, no, ne, nm = struct.unpack_from('<IHHHH', d, 0)
    pos = 12

    def flags():
        nonlocal pos
        s, seen = pos, []
        while True:
            b = d[pos]
            pos += 1
            if b == 0xFF:
                return d[s:pos], seen
            seen.append(b)
            if b == 34:
                n = struct.unpack_from('<H', d, pos + 6)[0]
                pos += 8 + n + 4
            else:
                pos += LEN.get(b, 0)

    def group():
        nonlocal pos
        s = pos
        w, h = d[pos], d[pos + 1]
        pos += 2
        if w > 1 or h > 1:
            pos += 1
        l, px, py, pz, ph = d[pos:pos + 5]
        pos += 5
        if ph > 1:
            pos += 6 + 8 * ph
        pos += 4 * w * h * l * px * py * pz * ph
        return d[s:pos]

    for _ in range(ni - 99):
        flags()
        group()
    out = bytearray(struct.pack('<IHHHH', sig, 100, no, 0, 0))
    out += b'\xff' + EMPTY_GROUP  # item 100
    for i in range(1, no + 1):
        raw, seen = flags()
        gs = d[pos]
        pos += 1
        body = bytearray([gs])
        for _ in range(gs):
            body.append(d[pos])
            pos += 1
            body += group()
        if i in want:
            bad = [b for b in seen if b not in KNOWN]
            if bad:
                sys.exit('outfit %d has flag(s) %s outside the 10.98 table' % (i, bad))
            out += raw + body
            print('outfit %d: flags %s, %d bytes' % (i, seen, len(raw) + len(body)))
        else:
            out += b'\xff' + bytes([1, 0]) + EMPTY_GROUP
    for _ in range(ne + nm):
        flags()
        group()
    if pos != len(d):
        sys.exit('walk ended at %d, file has %d bytes: not a 10.98 extended dat this tool understands' % (pos, len(d)))
    missing = sorted(want - set(range(1, no + 1)))
    if missing:
        sys.exit('donor has no outfit(s) %s' % missing)
    open(argv[1], 'wb').write(out)
    print('%s: %d outfits kept, %d bytes' % (argv[1], len(want), len(out)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
