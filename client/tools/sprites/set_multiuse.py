#!/usr/bin/env python3
"""Give items the multi-use ("use with") flag in a 10.98 Tibia.dat.

usage: python3 -I set_multiuse.py DAT [CLIENT_ID ...] [--out OUT] [--check]

With no ids it sets the flag on the crafting orbs that lack it: the Orb of Transmutation (server 29851, client 27195)
and the Exalted Orb (server 29855, client 27199). With the flag the client starts "use with" (the crosshair) when the
orb is used, and sends the target item to the server (data/scripts/chaos/crafting.lua). The server side is the
items.otb "useable" flag of the same items: server/tools/install_crafting.py.

The flag byte (7, the same in every 10.x dat) is inserted into the item's flag list in ascending order; nothing else
moves (the dat has no offsets). Writes DAT in place (a copy is kept as DAT.bak the first time) unless --out is given.
--check only reports. Idempotent: an item that has the flag already is left alone. Run it after gen_effects.py, which
writes a new Tibia.dat.
"""
import os, shutil, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from datspr import Dat, TABLES, _DATA  # noqa: E402

ORBS = {27195: 'Orb of Transmutation', 27199: 'Exalted Orb'}
MULTIUSE = 7
END = 0xFF


def flag_spans(dat, start):
    """[(byte, offset)] of the flags of the thing whose flag list starts at `start`, and the offset of the end byte."""
    table, _animator, _u32, _pz, _fg = dat.variant
    tab, kinds = dict(TABLES[table]), dict(_DATA)
    for b, k in dat.extra.items():
        tab[b] = 'x%d' % b
        kinds['x%d' % b] = k
    d, pos, out = dat.data, start, []
    while True:
        b = d[pos]
        if b == END:
            return out, pos
        out.append((b, pos))
        pos += 1
        kind = kinds.get(tab.get(b))
        if kind == 'u16':
            pos += 2
        elif kind == 'u16x2':
            pos += 4
        elif isinstance(kind, str) and kind[0] == 'b':
            pos += int(kind[1:])
        elif kind == 'c16':
            pos += 1 + 16 * d[pos]
        elif kind == 'market':
            ln = int.from_bytes(d[pos + 6:pos + 8], 'little')
            pos += 8 + ln + 4


def set_multiuse(data, ids):
    """Returns (new bytes, notes)."""
    dat = Dat(data)
    notes, inserts = [], []
    for cid in ids:
        if not 100 <= cid < 100 + len(dat.items):
            notes.append('%d: no such item' % cid)
            continue
        t = dat.items[cid - 100]
        if t.flags.get('multiuse'):
            notes.append('%d: multi-use already' % cid)
            continue
        spans, end = flag_spans(dat, t.raw[0])
        at = next((off for b, off in spans if b > MULTIUSE), end)
        inserts.append(at)
        notes.append('%d: multi-use flag set%s' % (cid, ' (%s)' % ORBS[cid] if cid in ORBS else ''))
    out = bytearray(dat.data)
    for at in sorted(inserts, reverse=True):
        out[at:at] = bytes([MULTIUSE])
    if inserts:
        check = Dat(bytes(out))  # must still parse exactly, with the flag on
        for cid in ids:
            if 100 <= cid < 100 + len(check.items):
                assert check.items[cid - 100].flags.get('multiuse'), cid
    return bytes(out), notes


def main():
    args = sys.argv[1:]
    out_path = None
    if '--out' in args:
        i = args.index('--out')
        out_path = args[i + 1]
        del args[i:i + 2]
    check = '--check' in args
    args = [a for a in args if a != '--check']
    if not args:
        print(__doc__)
        return 1
    path = args[0]
    ids = [int(a) for a in args[1:]] or sorted(ORBS)
    data = open(path, 'rb').read()
    new, notes = set_multiuse(data, ids)
    for n in notes:
        print(n)
    if check or new == data:
        return 0
    target = out_path or path
    if target == path and not os.path.exists(path + '.bak'):
        shutil.copyfile(path, path + '.bak')
    open(target, 'wb').write(new)
    print('written:', target)
    return 0


if __name__ == '__main__':
    sys.exit(main())
