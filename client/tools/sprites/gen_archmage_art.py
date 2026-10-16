#!/usr/bin/env python3
"""Pair 29: the Archmage, the Mystic line's class outfit (outfits 2235 male / 2236 female), our own rig art.

    python3 -I gen_archmage_art.py build [--procs 4]   # render with class_art.py (about 20 minutes) ->
                                                        #   art_import/archmage/archmage_<sex>.png, art_import/archmage.csv,
                                                        #   art_import/archmage.sums
    python3 -I gen_archmage_art.py build --check       # CI: the things file matches class_art.py's row, the sheets on
                                                        #   disk match the sums (no render)

The design is `archmage` in client/tools/outfit_art/class_art_line.py (owner-approved 2026-10-16, it replaces the donor
look 1559): a long tinted robe, a white beard (his) or long white hair (hers), an ember orb on a wooden staff; addon 1
a pointed hat with a gold band; addon 2 a dark mantle, gold hem trim and a floating ember sigil. class_art.py renders it
in the stock player layout (`--layout 1+8`: idle 1, walking 8 phases), 2x2 tiles, displacement 8,8, 2 layers (art +
colour template), 3 addon patterns, 2 mount patterns. No donor, stock, pack or AI pixels: the sheets are committed
(art_import/archmage/). Deterministic: the same code gives the same sheets.

Import (client/MANIFEST.md "Archmage (pair 29)"):
    python3 -I import_art_things.py --ours-dat P/Tibia.dat --ours-spr P/Tibia.spr --out-dir NEW \\
        --things art_import/archmage.csv --first-outfit 2235 --expect-items 34442
"""
import argparse
import csv
import hashlib
import io
import os
import shutil
import sys
import tempfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')
OUT = os.path.join(ART, 'archmage')
THINGS = os.path.join(ART, 'archmage.csv')
SUMS = os.path.join(ART, 'archmage.sums')
CLASS_ART = os.path.join(HERE, '..', 'outfit_art')
LAYOUT = '1+8'
SEXES = ('male', 'female')


def _ca():
    sys.path.insert(0, CLASS_ART)
    import class_art
    return class_art


def rows():
    CA = _ca()
    out = []
    for sex in SEXES:
        r = dict(CA.things_row('archmage', sex, LAYOUT))
        r['atlas'] = 'archmage/' + r['atlas']
        out.append(r)
    return out, CA.FIELDS


def things_text():
    rs, fields = rows()
    buf = io.StringIO()
    w = csv.DictWriter(buf, fields, lineterminator='\n')
    w.writeheader()
    w.writerows(rs)
    return buf.getvalue()


def digest(path):
    a = np.ascontiguousarray(np.asarray(Image.open(path).convert('RGBA')))
    return hashlib.sha256(a.tobytes() + repr(a.shape).encode()).hexdigest()


def sums_text():
    return ''.join(f'{digest(os.path.join(OUT, f"archmage_{s}.png"))}  archmage/archmage_{s}.png\n' for s in SEXES)


def check():
    ok = True
    if not os.path.exists(THINGS) or open(THINGS, newline='').read() != things_text():
        print(THINGS, 'differs from class_art.py things_row (run build)')
        ok = False
    want = {}
    for line in (open(SUMS).read().splitlines() if os.path.exists(SUMS) else []):
        h, f = line.split('  ', 1)
        want[f] = h
    for s in SEXES:
        f = f'archmage/archmage_{s}.png'
        p = os.path.join(ART, f)
        if not os.path.exists(p) or digest(p) != want.get(f):
            print(f, 'missing or differs from archmage.sums')
            ok = False
    print('archmage art check:', 'OK' if ok else 'FAILED')
    return ok


def build(procs):
    CA = _ca()
    tmp = tempfile.mkdtemp()
    try:
        CA.cmd_build([('archmage', s) for s in SEXES], tmp, procs, LAYOUT)
        os.makedirs(OUT, exist_ok=True)
        for s in SEXES:
            shutil.copyfile(os.path.join(tmp, f'archmage_{s}.png'), os.path.join(OUT, f'archmage_{s}.png'))
    finally:
        shutil.rmtree(tmp)
    open(THINGS, 'w', newline='').write(things_text())
    open(SUMS, 'w').write(sums_text())
    print('wrote', THINGS, SUMS)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('--check', action='store_true')
    b.add_argument('--procs', type=int, default=4)
    a = ap.parse_args()
    if a.check:
        sys.exit(0 if check() else 1)
    build(a.procs)


if __name__ == '__main__':
    main()
