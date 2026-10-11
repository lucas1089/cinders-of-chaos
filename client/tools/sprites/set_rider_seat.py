#!/usr/bin/env python3
"""Give mounts with a negative displacement a rider seat (dat Bones attribute) in COPIES of our 10.98 pair.

python3 -I set_rider_seat.py --ours-dat Tibia.dat --ours-spr Tibia.spr --spec monster_looks/rider_seats.csv \
        --out-dir OUT [--expect-dat-md5 MD5]

Donor B mounts (the Bone Steed 1561, the faction mounts 2132-2135) are centred on their tile with negative
displacements. The client draws such a mount by its own displacement and the rider at its usual place, so the rider
sat about half a tile up-left of the saddle. Client base patch 0034 moves the rider by the mount's Bones attribute
(10.98 dat byte 39: four x, y pairs of signed 16-bit pixels, in the file order north, south, east, west) when the mount
has a negative displacement and the rider has no Bones. A client without 0034 ignores it (stock Bones needs both).

The spec CSV has one row per mount: look, north, east, south, west (each "x y", pixels the rider moves; + is right /
down), note. Only outfits with a negative displacement are accepted. The attribute is inserted just before the
entry's 0xFF; an entry that has it already gets its 16 bytes replaced (re-running on an output changes nothing).
Outputs in --out-dir: Tibia.dat, Tibia.spr (a byte copy). Inputs are never modified. Deterministic.
Verification (always run): the output re-parses with the same counts; every entry not in the spec is byte-identical;
each spec entry is its old bytes plus (or with) only the Bones attribute, which decodes to the spec; the spr is
byte-identical (md5).
"""
import sys, os, csv, struct, argparse, hashlib, shutil
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from datspr import Dat

BONES = 39                      # file byte of ThingAttrBones (38) in 10.10+ dats
DIRS_FILE = ('north', 'south', 'east', 'west')   # order the client reads them


def md5(path):
    h = hashlib.md5()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def signed(v):
    return v - 65536 if v >= 32768 else v


def read_spec(path):
    spec = {}
    with open(path, newline='', encoding='utf-8') as f:
        for row in csv.DictReader(f):
            look = int(row['look'])
            if look in spec:
                sys.exit(f'{path}: look {look} twice')
            seat = {}
            for d in ('north', 'east', 'south', 'west'):
                x, y = (int(v) for v in row[d].split())
                if not (-128 <= x <= 128 and -128 <= y <= 128):
                    sys.exit(f'{path}: look {look} {d} seat {x} {y} out of range')
                seat[d] = (x, y)
            spec[look] = seat
    if not spec:
        sys.exit(f'{path}: no rows')
    return spec


def bones_bytes(seat):
    return bytes([BONES]) + b''.join(struct.pack('<hh', *seat[d]) for d in DIRS_FILE)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--ours-dat', required=True); ap.add_argument('--ours-spr', required=True)
    ap.add_argument('--spec', required=True)
    ap.add_argument('--out-dir', required=True)
    ap.add_argument('--expect-dat-md5', default=None, help='fail unless the input dat has this md5')
    a = ap.parse_args()

    if a.expect_dat_md5 and md5(a.ours_dat) != a.expect_dat_md5:
        sys.exit(f'{a.ours_dat}: md5 is not {a.expect_dat_md5}')
    spec = read_spec(a.spec)
    dat = Dat(a.ours_dat)
    if dat.variant[0] != 'new':
        sys.exit('not a 10.10+ dat (flag table "new")')
    d = dat.data
    edits = []   # (start, end, new bytes) in file order
    for look in sorted(spec):
        t = dat.outfit(look)
        if t is None:
            sys.exit(f'outfit {look} is not in the pair')
        disp = t.flags.get('displacement')
        if not disp or not (signed(disp[0]) < 0 or signed(disp[1]) < 0):
            sys.exit(f'outfit {look} has no negative displacement: patch 0034 would not use a seat')
        blob = bones_bytes(spec[look])
        old = [(s, e) for s, e in t.extras if d[s] == BONES]
        if old:
            s, e = old[0]
            edits.append((s, e, blob))
        else:
            edits.append((t.attr_end, t.attr_end, blob))
    out = bytearray()
    pos = 0
    for s, e, blob in sorted(edits):
        out += d[pos:s] + blob
        pos = e
    out += d[pos:]

    os.makedirs(a.out_dir, exist_ok=True)
    od, osp = os.path.join(a.out_dir, 'Tibia.dat'), os.path.join(a.out_dir, 'Tibia.spr')
    with open(od, 'wb') as f:
        f.write(out)
    if os.path.abspath(a.ours_spr) != os.path.abspath(osp):
        shutil.copyfile(a.ours_spr, osp)

    # verification
    new = Dat(od)
    if new.counts != dat.counts or new.variant != dat.variant:
        sys.exit('verify: counts or variant changed')
    nd = new.data
    targets = {('o', look) for look in spec}
    checked = 0
    for ca, cb in zip((dat.items, dat.outfits, dat.effects, dat.missiles),
                      (new.items, new.outfits, new.effects, new.missiles)):
        for ta, tb in zip(ca, cb):
            ra, rb = d[ta.raw[0]:ta.raw[1]], nd[tb.raw[0]:tb.raw[1]]
            if (ta.cat, ta.id) in targets:
                seat = spec[ta.id]
                bb = [x for x in tb.extras if nd[x[0]] == BONES]
                if len(bb) != 1:
                    sys.exit(f'verify: outfit {ta.id} has {len(bb)} Bones attributes')
                s, e = bb[0][0] - tb.raw[0], bb[0][1] - tb.raw[0]
                if rb[s:e] != bones_bytes(seat):
                    sys.exit(f'verify: outfit {ta.id} Bones bytes differ from the spec')
                rest = rb[:s] + rb[e:]
                old = [x for x in ta.extras if d[x[0]] == BONES]
                ref = ra if not old else ra[:old[0][0] - ta.raw[0]] + ra[old[0][1] - ta.raw[0]:]
                if rest != ref:
                    sys.exit(f'verify: outfit {ta.id} changed beyond the Bones attribute')
                if tb.sprites != ta.sprites or tb.flags.get('displacement') != ta.flags.get('displacement'):
                    sys.exit(f'verify: outfit {ta.id} sprites or displacement changed')
            elif ra != rb:
                sys.exit(f'verify: {ta.cat}{ta.id} is not byte-identical')
            checked += 1
    if md5(osp) != md5(a.ours_spr):
        sys.exit('verify: spr differs')
    print(f'{len(spec)} mounts seated, {checked - len(spec)} other entries byte-identical, spr byte-identical')
    for look in sorted(spec):
        print(f'  {look}: ' + ', '.join(f'{k} {v[0]:+d} {v[1]:+d}' for k, v in spec[look].items()))
    print(f'dat {md5(od)}  spr {md5(osp)}')


if __name__ == '__main__':
    main()
