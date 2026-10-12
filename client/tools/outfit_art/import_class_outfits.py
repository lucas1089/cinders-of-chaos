#!/usr/bin/env python3
"""Append the class outfits rendered by build.py to COPIES of our 10.98 Tibia.dat / Tibia.spr.

python3 -I client/tools/outfit_art/import_class_outfits.py --ours-dat PAIR/Tibia.dat --ours-spr PAIR/Tibia.spr \
        --out-dir NEWPAIR --line warrior [--first-outfit 2100] [--manifest-out FILE.csv]

Each outfit gets the stock player layout (read off look 131 of the input and checked): displacement 8,8; two frame
groups, idle (1 phase) and walking (8 phases, 300 ms); 2x2 tiles; 2 layers (art + colour template); 4 directions;
3 addon patterns (base, addon 1, addon 2: the addons are empty for now); 2 mount patterns (on foot, riding).
Look types: --first-outfit, +1, ... in the order class (base, ascension 1, ascension 2) x sex (male, female);
--first-outfit pads with blank outfits so the ids stay fixed, and the run stops if the input already has that many.

Inputs are never modified. Deterministic. Verified on every run: the output re-parses with the same variant; every
sprite slot of the new outfits decodes pixel-identical to the frames (empty addon slots are sprite 0); padding is
blank; every old item, outfit, effect and missile entry is byte-identical; 3000 sampled old sprites are unchanged.
"""
import argparse
import csv
import os
import random
import struct
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SPRITES = os.path.join(os.path.dirname(HERE), "sprites")
sys.path.insert(0, HERE)
sys.path.insert(0, SPRITES)
from datspr import Dat, Spr, TABLE_NEW, sprite_index  # noqa: E402
from import_art_things import encode_sprite, tiles_of, decoded, BLANK_OUTFIT  # noqa: E402
from import_outfits import parse_body  # noqa: E402

import build  # noqa: E402

NEW_BYTE = {name: b for b, name in TABLE_NEW.items()}
W, H, LAYERS, PX, PY, PZ = 2, 2, 2, 4, 3, 2
GROUPS = ((0, 1), (1, build.WALK))          # (group type, phases)
WALK_MS = 300


class Shape:
    def __init__(self, phases):
        self.w, self.h, self.layers, self.px, self.py, self.pz, self.phases = W, H, LAYERS, PX, PY, PZ, phases


def check_stock_layout(od):
    g = parse_body(od, od.outfit(131))
    got = [(x.gtype, x.w, x.h, x.layers, x.px, x.py, x.pz, x.phases) for x in g]
    want = [(gt, W, H, LAYERS, PX, PY, PZ, n) for gt, n in GROUPS]
    assert got == want, ("the stock player layout changed", got, want)
    assert od.outfit(131).flags.get("displacement") == (8, 8)


def frame_of(idle, walk, gi, ph, d, a, z, layer):
    """64x64 RGBA of a slot, or None for the empty addon patterns."""
    if a != 0:
        return None
    src = idle if gi == 0 else walk
    return src[ph, z, d, layer]


def exact_size(idle, walk):
    m = 32
    for arr in (idle, walk):
        on = arr[..., 3].reshape(-1, 64, 64) > 0
        on = on.any(0)
        ys, xs = np.nonzero(on)
        if len(xs):
            m = max(m, 64 - xs.min(), 64 - ys.min())
    return min(m, 64)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--ours-dat", required=True)
    ap.add_argument("--ours-spr", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--line", action="append", default=None)
    ap.add_argument("--first-outfit", type=int, default=2100)
    ap.add_argument("--manifest-out", default=None)
    ap.add_argument("--variant", default="", help="frames_<variant>.npz (e.g. a repaint) instead of frames.npz")
    a = ap.parse_args()
    build.VARIANT = a.variant
    lines = a.line or ["warrior"]
    os.makedirs(a.out_dir, exist_ok=True)
    for p in (a.ours_dat, a.ours_spr):
        assert os.path.abspath(os.path.dirname(p)) != os.path.abspath(a.out_dir), "out-dir must differ from the input dir"
    od, ospr = Dat(a.ours_dat), Spr(a.ours_spr)
    assert od.variant[0] == "new" and all(od.variant[1:]), od.variant
    assert ospr.u32count and ospr.alpha
    check_stock_layout(od)
    no = od.counts[1]
    if a.first_outfit <= no:
        sys.exit("--first-outfit %d is not above the last outfit %d (wrong pair, or already imported)" % (a.first_outfit, no))
    pad = a.first_outfit - no - 1

    outfits = []
    for line in lines:
        for c in build.LINES[line]:
            for sx in build.SEXES:
                idle, walk = build.load_frames(c, sx)
                assert idle.shape == (1, PZ, PX, LAYERS, 64, 64, 4) and walk.shape == (build.WALK, PZ, PX, LAYERS, 64, 64, 4)
                outfits.append((line, c, sx, idle, walk))

    recs, per = {}, []
    for line, c, sx, idle, walk in outfits:
        groups = []
        for gi, (gt, nph) in enumerate(GROUPS):
            shp = Shape(nph)
            ids = [None] * (W * H * LAYERS * PX * PY * PZ * nph)
            for ph in range(nph):
                for d in range(PX):
                    for ad in range(PY):
                        for z in range(PZ):
                            for layer in range(LAYERS):
                                f = frame_of(idle, walk, gi, ph, d, ad, z, layer)
                                if f is None:
                                    continue
                                for (ww, hh), tile in tiles_of(f, W, H).items():
                                    rec = encode_sprite(tile)
                                    ids[sprite_index(shp, d, ad, z, layer, ph, ww, hh)] = rec
                                    if rec is not None:
                                        recs.setdefault(rec, None)
            groups.append((shp, ids))
        per.append((line, c, sx, idle, walk, groups))

    # every record is appended, none is shared with the input: the art stays apart from the stock sprites even
    # where a tiny tile happens to match one byte for byte
    existing = {}
    cnt = ospr.count
    newrecs, rec_id = [], {None: 0}
    for rec in recs:
        if rec in existing:
            rec_id[rec] = existing[rec]
        else:
            newrecs.append(rec)
            rec_id[rec] = cnt + len(newrecs)

    # dat
    d = od.data
    outfits_end = od.outfits[-1].raw[1]
    blob = bytearray(BLANK_OUTFIT * pad)
    for line, c, sx, idle, walk, groups in per:
        e = bytearray([NEW_BYTE["displacement"]]) + struct.pack("<HH", 8, 8) + b"\xff" + bytes([len(GROUPS)])
        ex = exact_size(idle, walk)
        for (gt, nph), (shp, ids) in zip(GROUPS, groups):
            e += bytes([gt, W, H, ex, LAYERS, PX, PY, PZ, nph])
            if nph > 1:
                e += struct.pack("<Bib", 0, 0, 0) + struct.pack("<" + "II" * nph, *([WALK_MS] * (2 * nph)))
            e += struct.pack("<%dI" % len(ids), *[rec_id[x] for x in ids])
        blob += e
    out = bytearray(d[:outfits_end]) + blob + d[outfits_end:]
    last = a.first_outfit + len(per) - 1
    struct.pack_into("<H", out, 6, last)
    open(os.path.join(a.out_dir, "Tibia.dat"), "wb").write(out)

    # spr: bigger table, old records shifted, new ones appended
    m = ospr.m
    nn = len(newrecs)
    toffs = ospr.offs.astype("<u8").copy()
    toffs[toffs > 0] += 4 * nn
    cur = len(m) + 4 * nn
    new_offs = []
    for rec in newrecs:
        new_offs.append(cur)
        cur += len(rec)
    assert cur < 1 << 32
    table = np.concatenate([toffs, np.array(new_offs, dtype="<u8")]).astype("<u4")
    with open(os.path.join(a.out_dir, "Tibia.spr"), "wb") as f:
        f.write(struct.pack("<II", ospr.signature, cnt + nn))
        f.write(table.tobytes())
        pos = 8 + 4 * cnt
        while pos < len(m):
            f.write(m[pos:pos + (1 << 24)])
            pos += 1 << 24
        for rec in newrecs:
            f.write(rec)
    print("outfits %d -> %d (%d blank, new %d..%d); spr: %d distinct sprites appended (%d -> %d)"
          % (no, last, pad, a.first_outfit, last, nn, cnt, cnt + nn))

    # verification
    md, ms = Dat(os.path.join(a.out_dir, "Tibia.dat")), Spr(os.path.join(a.out_dir, "Tibia.spr"))
    assert md.variant == od.variant and md.counts[0] == od.counts[0] and md.counts[2:] == od.counts[2:]
    assert ms.count == cnt + nn and ms.alpha and ms.signature == ospr.signature
    for t in od.items:
        mt = md.items[t.id - 100]
        assert md.data[mt.raw[0]:mt.raw[1]] == d[t.raw[0]:t.raw[1]], ("item changed", t.id)
    for t in od.outfits + od.effects + od.missiles:
        lst = {"o": md.outfits, "e": md.effects, "m": md.missiles}[t.cat]
        mt = lst[t.id - 1]
        assert md.data[mt.raw[0]:mt.raw[1]] == d[t.raw[0]:t.raw[1]], ("thing changed", t.cat, t.id)
    for i in range(pad):
        mt = md.outfits[no + i]
        assert md.data[mt.raw[0]:mt.raw[1]] == BLANK_OUTFIT
    nslot = 0
    for k, (line, c, sx, idle, walk, groups) in enumerate(per):
        mt = md.outfit(a.first_outfit + k)
        assert mt.flags.get("displacement") == (8, 8)
        mg = parse_body(md, mt)
        for gi, (gt, nph) in enumerate(GROUPS):
            g = mg[gi]
            assert (g.gtype, g.w, g.h, g.layers, g.px, g.py, g.pz, g.phases) == (gt, W, H, LAYERS, PX, PY, PZ, nph)
            for ph in range(nph):
                for dd in range(PX):
                    for ad in range(PY):
                        for z in range(PZ):
                            for layer in range(LAYERS):
                                f = frame_of(idle, walk, gi, ph, dd, ad, z, layer)
                                for hh in range(H):
                                    for ww in range(W):
                                        sid = g.sprites[sprite_index(g, dd, ad, z, layer, ph, ww, hh)]
                                        got = ms.sprite(sid)
                                        if f is None:
                                            assert sid == 0
                                            continue
                                        tile = tiles_of(f, W, H)[(ww, hh)]
                                        if got is None:
                                            assert not tile[:, :, 3].any(), (c, sx)
                                        else:
                                            assert np.array_equal(got, decoded(tile)), (c, sx, gi, ph, dd, z, layer)
                                        nslot += 1
    random.seed(1)
    for sid in random.sample(range(1, cnt + 1), min(3000, cnt)) + [1, cnt]:
        x, y = ospr.sprite(sid), ms.sprite(sid)
        assert (x is None) == (y is None) and (x is None or (x == y).all()), sid
    print("verified: %d outfits, %d sprite slots pixel-identical to the frames; %d blank padding; every old entry "
          "byte-identical; 3000 sampled old sprites unchanged" % (len(per), nslot, pad))
    if a.manifest_out:
        with open(a.manifest_out, "w", newline="") as fh:
            w = csv.writer(fh, lineterminator="\n")
            w.writerow(["look_type", "line", "class", "sex"])
            for k, (line, c, sx, *_r) in enumerate(per):
                w.writerow([a.first_outfit + k, line, c, sx])
        print("manifest", a.manifest_out)


if __name__ == "__main__":
    main()
