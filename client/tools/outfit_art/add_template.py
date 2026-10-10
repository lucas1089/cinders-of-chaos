#!/usr/bin/env python3
"""Copy one-layer outfits of a pair as NEW look types with a colour template layer, so players can colour them.

python3 -I client/tools/outfit_art/add_template.py --ours-dat PAIR/Tibia.dat --ours-spr PAIR/Tibia.spr \
        --looks 1505,1506,1508,1510 --expect-first 2069 --out-dir NEWPAIR [--preview DIR]

The source outfits stay as they are (old entries byte-identical); each copy keeps the source's frame groups, sizes,
patterns, phases, animator and flags, and gets layer 1 = the template the client multiplies by the player's colours
(yellow head, red body, green legs, blue feet).

Which pixels become colourable: the outfit's accent colour (the most common hue among its saturated, not dark
pixels, within 18 degrees). Those pixels are turned into grey (their brightness, stretched so the brightest reaches
about 235) in the art layer, and marked in the template by where they sit along the figure: the client draws a
standing figure along the up-left diagonal, so the first 30% from its top-left is the head, then body to 62%, legs to
86%, feet after. Everything else (the dark cloth, skin, steel, the weapon) keeps its own colours.

Verified on every run: the output re-parses; every slot of every copy decodes pixel-identical to the frames built
here; every old item, outfit, effect and missile entry is byte-identical; 3000 sampled old sprites are unchanged.
Deterministic.
"""
import argparse
import colorsys
import os
import random
import struct
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "sprites"))
from datspr import Dat, Spr, TABLE_NEW, _DATA, sprite_index  # noqa: E402
from import_outfits import parse_body  # noqa: E402
from import_art_things import encode_sprite, decoded  # noqa: E402

NEW_BYTE = {name: b for b, name in TABLE_NEW.items()}
REG = [(0.30, (255, 255, 0)), (0.62, (255, 0, 0)), (0.86, (0, 255, 0)), (9.0, (0, 0, 255))]


class G:
    pass


def frame_of(g, spr, d, a, z, layer, ph):
    W, H = g.w * 32, g.h * 32
    c = np.zeros((H, W, 4), np.uint8)
    for hh in range(g.h):
        for ww in range(g.w):
            sp = spr.sprite(g.sprites[sprite_index(g, d, a, z, layer, ph, ww, hh)])
            if sp is not None:
                m = sp[..., 3] > 0
                c[(g.h - 1 - hh) * 32:(g.h - hh) * 32, (g.w - 1 - ww) * 32:(g.w - ww) * 32][m] = sp[m]
    return c


def tiles(img, w, h):
    return {(ww, hh): np.ascontiguousarray(img[(h - 1 - hh) * 32:(h - hh) * 32, (w - 1 - ww) * 32:(w - ww) * 32])
            for hh in range(h) for ww in range(w)}


def hsv(rgb):
    a = rgb.astype(np.float64) / 255.0
    mx, mn = a.max(-1), a.min(-1)
    v = mx
    s = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-9), 0)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    d = np.maximum(mx - mn, 1e-9)
    h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
    return h, s, v


def accent_of(frames):
    px = np.concatenate([f[f[..., 3] > 0][:, :3] for f in frames])
    h, s, v = hsv(px)
    sel = (s > 0.45) & (v > 0.25)
    hist = np.bincount((h[sel] // 6).astype(int) % 60, minlength=60)
    k = int(np.argmax(hist))
    return k * 6 + 3, px[sel]


def hue_near(h, h0, tol=18):
    return np.abs((h - h0 + 180) % 360 - 180) <= tol


def masked(frame, h0, scale):
    """(art with the accent in grey, template)."""
    on = frame[..., 3] > 0
    art = frame.copy()
    tmpl = np.zeros_like(frame)
    if not on.any():
        return art, tmpl
    h, s, v = hsv(frame[..., :3])
    acc = on & (s > 0.35) & (v > 0.18) & hue_near(h, h0)
    ys, xs = np.nonzero(on)
    t0, t1 = (xs + ys).min(), (xs + ys).max()
    yy, xx = np.mgrid[0:frame.shape[0], 0:frame.shape[1]]
    t = ((xx + yy) - t0) / max(t1 - t0, 1)
    lum = 0.299 * frame[..., 0] + 0.587 * frame[..., 1] + 0.114 * frame[..., 2]
    g = np.clip(lum * scale, 0, 255).astype(np.uint8)
    art[acc, 0] = g[acc]
    art[acc, 1] = g[acc]
    art[acc, 2] = g[acc]
    lo = -1.0
    for hi, col in REG:
        m = acc & (t > lo) & (t <= hi)
        tmpl[m, :3] = col
        tmpl[m, 3] = 255
        lo = hi
    return art, tmpl


def flags_bytes(t):
    out = bytearray()
    for name, val in sorted(t.flags.items(), key=lambda kv: NEW_BYTE[kv[0]]):
        kind = _DATA.get(name)
        out.append(NEW_BYTE[name])
        if kind == "u16":
            out += struct.pack("<H", val)
        elif kind == "u16x2":
            out += struct.pack("<HH", *val)
        else:
            assert kind is None and val is True, (name, val)
    return bytes(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--ours-dat", required=True)
    ap.add_argument("--ours-spr", required=True)
    ap.add_argument("--looks", required=True)
    ap.add_argument("--expect-first", type=int, default=None)
    ap.add_argument("--out-dir", required=True)
    a = ap.parse_args()
    os.makedirs(a.out_dir, exist_ok=True)
    od, ospr = Dat(a.ours_dat), Spr(a.ours_spr)
    no = od.counts[1]
    first = no + 1
    if a.expect_first is not None and first != a.expect_first:
        sys.exit("the first new id would be %d, not %d (wrong pair)" % (first, a.expect_first))
    looks = [int(x) for x in a.looks.split(",")]
    recs, plans = {}, []
    for look in looks:
        t = od.outfit(look)
        gs = parse_body(od, t)
        assert all(g.layers == 1 for g in gs), "%d already has a template layer" % look
        base = [frame_of(g, ospr, d, ad, z, 0, ph) for g in gs for ph in range(g.phases) for d in range(g.px)
                for ad in range(g.py) for z in range(g.pz)]
        h0, accpx = accent_of(base)
        lum = 0.299 * accpx[:, 0] + 0.587 * accpx[:, 1] + 0.114 * accpx[:, 2]
        scale = 235.0 / max(np.percentile(lum, 95), 1.0)
        groups = []
        for g in gs:
            n = G()
            n.gtype, n.w, n.h, n.exact, n.layers, n.px, n.py, n.pz, n.phases, n.anim = \
                g.gtype, g.w, g.h, g.exact, 2, g.px, g.py, g.pz, g.phases, g.anim
            ids, frames = [None] * (g.w * g.h * 2 * g.px * g.py * g.pz * g.phases), {}
            for ph in range(g.phases):
                for d in range(g.px):
                    for ad in range(g.py):
                        for z in range(g.pz):
                            art, tm = masked(frame_of(g, ospr, d, ad, z, 0, ph), h0, scale)
                            for layer, img in ((0, art), (1, tm)):
                                frames[(ph, d, ad, z, layer)] = img
                                for (ww, hh), tile in tiles(img, g.w, g.h).items():
                                    rec = encode_sprite(tile)
                                    ids[sprite_index(n, d, ad, z, layer, ph, ww, hh)] = rec
                                    if rec is not None:
                                        recs.setdefault(rec, None)
            groups.append((n, ids, frames))
        plans.append((look, t, h0, groups))
        print("look %d: accent hue %d, grey scale %.2f" % (look, h0, scale))
    cnt = ospr.count
    newrecs = list(recs)
    rec_id = {None: 0}
    for i, rec in enumerate(newrecs):
        rec_id[rec] = cnt + 1 + i
    d = od.data
    end = od.outfits[-1].raw[1]
    blob = bytearray()
    for look, t, h0, groups in plans:
        e = bytearray(flags_bytes(t)) + b"\xff" + bytes([len(groups)])
        for n, ids, frames in groups:
            e += bytes([n.gtype, n.w, n.h])
            if n.w > 1 or n.h > 1:
                e += bytes([n.exact])
            e += bytes([n.layers, n.px, n.py, n.pz, n.phases])
            if n.phases > 1:
                asyn, loop, start, durs = n.anim
                e += struct.pack("<Bib", asyn, loop, start) + struct.pack("<" + "II" * n.phases, *durs)
            e += struct.pack("<%dI" % len(ids), *[rec_id[x] for x in ids])
        blob += e
    out = bytearray(d[:end]) + blob + d[end:]
    struct.pack_into("<H", out, 6, no + len(plans))
    open(os.path.join(a.out_dir, "Tibia.dat"), "wb").write(out)
    m = ospr.m
    nn = len(newrecs)
    toffs = ospr.offs.astype("<u8").copy()
    toffs[toffs > 0] += 4 * nn
    cur = len(m) + 4 * nn
    new_offs = []
    for rec in newrecs:
        new_offs.append(cur)
        cur += len(rec)
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
    print("outfits %d -> %d (new %d..%d); spr %d -> %d" % (no, no + len(plans), first, no + len(plans), cnt, cnt + nn))
    # verification
    md, ms = Dat(os.path.join(a.out_dir, "Tibia.dat")), Spr(os.path.join(a.out_dir, "Tibia.spr"))
    assert md.variant == od.variant and md.counts[0] == od.counts[0] and md.counts[2:] == od.counts[2:]
    for t in od.items:
        mt = md.items[t.id - 100]
        assert md.data[mt.raw[0]:mt.raw[1]] == d[t.raw[0]:t.raw[1]]
    for t in od.outfits + od.effects + od.missiles:
        mt = {"o": md.outfits, "e": md.effects, "m": md.missiles}[t.cat][t.id - 1]
        assert md.data[mt.raw[0]:mt.raw[1]] == d[t.raw[0]:t.raw[1]]
    nslot = 0
    for k, (look, t, h0, groups) in enumerate(plans):
        mt = md.outfit(first + k)
        assert mt.flags == t.flags
        mg = parse_body(md, mt)
        for g2, (n, ids, frames) in zip(mg, groups):
            assert (g2.gtype, g2.layers, g2.px, g2.py, g2.pz, g2.phases) == (n.gtype, 2, n.px, n.py, n.pz, n.phases)
            for (ph, dd, ad, z, layer), img in frames.items():
                for (ww, hh), tile in tiles(img, n.w, n.h).items():
                    got = ms.sprite(g2.sprites[sprite_index(g2, dd, ad, z, layer, ph, ww, hh)])
                    if got is None:
                        assert not tile[..., 3].any()
                    else:
                        assert np.array_equal(got, decoded(tile))
                    nslot += 1
    random.seed(1)
    for sid in random.sample(range(1, cnt + 1), min(3000, cnt)) + [1, cnt]:
        x, y = ospr.sprite(sid), ms.sprite(sid)
        assert (x is None) == (y is None) and (x is None or (x == y).all()), sid
    print("verified: %d copies with a template, %d sprite slots pixel-identical; every old entry byte-identical; "
          "3000 sampled old sprites unchanged" % (len(plans), nslot))


if __name__ == "__main__":
    main()
