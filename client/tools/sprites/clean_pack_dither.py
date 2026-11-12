#!/usr/bin/env python3
"""Take the ordered-dither mesh out of the pack effects, in place (pair 66, ROADMAP O523).

python3 -I clean_pack_dither.py build       DAT SPR --out-dir OUT [--dry-run] [--stats-out stats.csv]
python3 -I clean_pack_dither.py stats       DAT SPR [--out stats.csv]
python3 -I clean_pack_dither.py check-clean DAT SPR

Why. The pack effect imports (gen_pack27_fx.py, gen_pack36_fx.py, ...) cut the soft glow of a 64 px (or 32 px) pack frame to a
0 / 255 alpha with a 4x4 Bayer threshold (`clean_alpha`). A glow of alpha 0.5 becomes every second pixel, a halo becomes a checker
mesh around the art (client/MANIFEST.md "Pair 66": E12 and E44 at pair 64). The import rule is a hard cut now (`CUT`,
gen_pack27_fx.py), but the strips are cut from the purchased packs, which are not in git and not in every checkout, so the effects
already in the pair are cleaned by this tool, from the pair only: no art is read from outside, nothing is drawn, no pixel is invented,
colours never change, pixels only go.

The rule, per frame canvas of an effect or missile (all layers and patterns; tile (0, 0) at the bottom right, like every canvas
of this repo), on the alpha > 0 mask:
  checker  a pixel with no 4-neighbour and at least 2 diagonal neighbours (a Bayer cell at alpha 0.3 to 0.5 keeps a checker);
  lattice  a pixel with nothing in its 3x3 box and at least 2 of the 8 pixels at distance 2 (every other pixel and row, the
           cell at alpha 0.06 to 0.25 keeps 2 to 4 pixels two apart).
Those pixels become (0, 0, 0, 0). Solid art, outlines, one pixel wide lines, and single sparks (no second dot two pixels away)
stay. A cell that was dithered above alpha 0.5 is mostly connected and stays as it is (it reads as solid art with a few holes).
An effect is cleaned only when it holds at least MIN_REMOVED such pixels over all its frames, so a few lattice coincidences in
hand drawn art change nothing. A sprite is rewritten only when every thing that uses it is a cleaned effect or missile, every use
gives the same tile and no other sprite id shares its record; an effect with a sprite that fails this is left whole (listed).
The dat is copied byte for byte (no id, no flag, no frame group changes). The spr keeps its count and its ids; a changed record is
rewritten where it is, a tile that is empty afterwards loses its record, the offset table is recomputed. Deterministic.
Limits: the dots of a faint fringe (one pixel per 4x4 cell) stay as single dots; the end frames of a looping set (`dissolve` in
gen_pack27_fx.py: a deliberate Bayer fade of opaque art) lose their mesh too, so they fade faster.
The loot beams (effects 4090-4101, O522, pair 65) are never touched (`SKIP`): full size art with soft alpha.
check-clean: no effect or missile of the pair has MIN_REMOVED or more such pixels left.
"""
import argparse
import csv
import os
import struct
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
import clean_wing_shadows as cws  # noqa: E402
import import_art_things as iat  # noqa: E402
from datspr import Dat, Spr, sprite_index  # noqa: E402

MIN_REMOVED = 12        # an effect with fewer mesh pixels over all its frames is left as it is
MIN_SOLID = 40          # and one that would keep fewer pixels with a 4-neighbour (no solid art: a dithered smoke) too
CHECKER_DIAG = 3        # diagonal neighbours of a checker pixel, of its colour
CHECKER_AXIS = 2        # and pixels two away along an axis, of its colour (the checker's own lattice; two lines crossing have none)
LATTICE_NEAR = 5        # of the 8 pixels two away (axis and diagonal) of a lattice pixel, of its colour
KINDS = ('effect', 'missile')
SKIP = {('e', i) for i in range(4090, 4102)}   # (t.cat of datspr: 'e' effect, 'm' missile, id)   # the loot beams (O522, pair 65): full size art with soft alpha, never touched here


# ------------------------------------------------------------------------------------------------ the rule
def shift(a, dy, dx):
    """a moved by (dy, dx), zeros come in"""
    h, w = a.shape
    o = np.zeros_like(a)
    o[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)] = a[max(-dy, 0):h + min(-dy, 0), max(-dx, 0):w + min(-dx, 0)]
    return o


DIAG = ((1, 1), (1, -1), (-1, 1), (-1, -1))
AXIS2 = ((2, 0), (-2, 0), (0, 2), (0, -2))
DIAG2 = ((2, 2), (2, -2), (-2, 2), (-2, -2))
COLOUR_TOL = 150        # sum of the channel differences under which two pixels count as one glow (a halo is 2 or 3 palette steps)
RIM_STEPS = 2           # pixels at the edge of the mesh that go too: this many steps out from its core


def same_colour(img, a, dy, dx):
    """bool: the pixel (dy, dx) away is kept and has the colour of this one (sum of |dr| |dg| |db| <= COLOUR_TOL)"""
    s = np.zeros_like(img)
    h, w = a.shape
    s[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)] = img[max(-dy, 0):h + min(-dy, 0), max(-dx, 0):w + min(-dx, 0)]
    d = np.abs(img[..., :3].astype(np.int16) - s[..., :3].astype(np.int16)).sum(axis=2)
    return shift(a, dy, dx).astype(bool) & (d <= COLOUR_TOL)


def mesh_mask(img):
    """RGBA canvas -> bool mask of the mesh pixels: the interior of a checker or lattice of one colour, and its rim.
    (An alpha plane alone is accepted too: then every colour counts as the same.)"""
    img = np.asarray(img)
    if img.ndim == 2:
        img = np.stack([np.zeros_like(img)] * 3 + [img], axis=2)
    a = (img[..., 3] > 0).astype(np.int16)
    k4 = shift(a, 1, 0) + shift(a, -1, 0) + shift(a, 0, 1) + shift(a, 0, -1)
    d4 = sum(shift(a, dy, dx) for dy, dx in DIAG)
    on = (a == 1) & (k4 == 0)
    md4 = sum(same_colour(img, a, dy, dx).astype(np.int16) for dy, dx in DIAG)
    mx2 = sum(same_colour(img, a, dy, dx).astype(np.int16) for dy, dx in AXIS2)
    md2 = sum(same_colour(img, a, dy, dx).astype(np.int16) for dy, dx in DIAG2)
    # checker interior: at least 3 of the 4 diagonal neighbours and 2 of the 4 pixels two away along an axis are kept and of the
    # glow's colour (a 1 px diagonal line has 2 diagonals, in a line; two lines crossing have 4 and no axis one; a line of another
    # colour inside a halo has 2 of the halo's colour)
    core = on & (md4 >= CHECKER_DIAG) & (mx2 >= CHECKER_AXIS)
    # lattice interior (every other pixel of every other row, alone or with a diagonal neighbour): at least 5 of the 8 pixels two away
    # of the same colour (a diagonal line has 2, two crossing 4)
    core |= on & (mx2 + md2 >= LATTICE_NEAR)
    for _ in range(RIM_STEPS):
        near = np.zeros(a.shape, bool)
        for dy, dx in DIAG:
            near |= same_colour(img, a, dy, dx) & shift(core.astype(np.int16), dy, dx).astype(bool)
        core = core | (on & near & (d4 >= 1))
    return core


def clean_canvas(img):
    """RGBA canvas -> (cleaned canvas, mask of the pixels that went)"""
    m = mesh_mask(img)
    out = img.copy()
    out[m] = 0
    return out, m


# ------------------------------------------------------------------------------------------------ frames of a thing
def canvases(t, spr):
    """[(key, RGBA canvas, [(sid, tile slice) ...])] for every (x, y, z, layer, phase) of the thing"""
    w, h = t.w, t.h
    out = []
    for ph in range(t.phases):
        for z in range(t.pz):
            for y in range(t.py):
                for x in range(t.px):
                    for ly in range(t.layers):
                        img = np.zeros((h * 32, w * 32, 4), np.uint8)
                        tiles = []
                        for hh in range(h):
                            for ww in range(w):
                                sid = int(t.sprites[sprite_index(t, x, y, z, ly, ph, ww, hh)])
                                sl = (slice((h - 1 - hh) * 32, (h - hh) * 32), slice((w - 1 - ww) * 32, (w - ww) * 32))
                                if sid:
                                    a = spr.sprite(sid)
                                    if a is not None:
                                        img[sl] = a
                                tiles.append((sid, sl))
                        out.append(((ph, z, y, x, ly), img, tiles))
    return out


def things(dat):
    for cat, lst in (('effect', dat.effects), ('missile', dat.missiles)):
        for t in lst:
            yield cat, t


def solid_after(cv, masks):
    """pixels with a 4-neighbour that stay, over all frames"""
    n = 0
    for (_k, img, _tl), m in zip(cv, masks):
        a = ((img[..., 3] > 0) & ~m).astype(np.int16)
        k4 = shift(a, 1, 0) + shift(a, -1, 0) + shift(a, 0, 1) + shift(a, 0, -1)
        n += int(((a == 1) & (k4 >= 1)).sum())
    return n


def thing_masks(t, spr):
    """-> (canvases, masks, removed, flagged): flagged when the thing is cleaned"""
    cv = canvases(t, spr)
    masks = [mesh_mask(img) for _k, img, _tl in cv]
    removed = sum(int(m.sum()) for m in masks)
    flagged = removed >= MIN_REMOVED and solid_after(cv, masks) >= MIN_SOLID and (t.cat, t.id) not in SKIP
    return cv, masks, removed, flagged


def count_mesh(t, spr):
    cv, masks, removed, flagged = thing_masks(t, spr)
    return removed if flagged else 0


# ------------------------------------------------------------------------------------------------ plan
def plan(dat, spr):
    """-> (changed {sid: tile}, stats {(cat, id): (removed, frames, opaque)}, left {(cat, id): why})

    A sprite used in several places (a tile that repeats in a frame group, a tile shared by two effects) is cut where EVERY use
    sees mesh: the pixels that all uses agree on. So a tile never loses a pixel that one of its uses keeps."""
    users = defaultdict(set)
    for cat, lst in (('item', dat.items), ('outfit', dat.outfits), ('effect', dat.effects), ('missile', dat.missiles)):
        for t in lst:
            for s in set(int(x) for x in t.sprites):
                if s:
                    users[s].add((cat, t.id))
    offs = np.asarray(spr.offs)
    by_off = defaultdict(list)
    for sid in np.nonzero(offs)[0]:
        by_off[int(offs[sid])].append(int(sid) + 1)

    stats, mine = {}, {}
    agree = {}                                    # sid -> mask of the pixels every use removes
    target = {}
    for cat, t in things(dat):
        if not t.sprites or not any(int(s) for s in t.sprites):
            continue
        cv, masks, removed, flagged = thing_masks(t, spr)
        key = (cat, t.id)
        if flagged:
            stats[key] = (removed, len(cv), sum(int((img[..., 3] > 0).sum()) for _k, img, _tl in cv))
            mine[key] = {int(s) for s in t.sprites if s}
        for (_k, _img, tiles), m in zip(cv, masks):
            for sid, sl in tiles:
                if not sid:
                    continue
                use = np.ascontiguousarray(m[sl]) if flagged else np.zeros((32, 32), bool)
                agree[sid] = use if sid not in agree else (agree[sid] & use)
                target.setdefault(sid, set()).add(key)
    why, changed = {}, {}
    for sid, m in agree.items():
        if not m.any():
            continue
        old = spr.sprite(sid)
        if old is None:
            continue
        old = iat.decoded(old)
        new = old.copy()
        new[m] = 0
        if np.array_equal(new, old):
            continue
        bad = users[sid] - target[sid]
        if bad:
            why[sid] = 'shared with ' + ', '.join('%s %d' % u for u in sorted(bad))
        elif len(by_off.get(int(offs[sid - 1]), [])) > 1:
            why[sid] = 'its record is shared by sprite ids %s' % by_off[int(offs[sid - 1])]
        else:
            changed[sid] = new
    left = {}
    blocked = set(why)
    while True:
        moved = False
        for k, sids in mine.items():
            if k in left:
                continue
            hit = sids & blocked
            if hit:
                sid = min(hit)
                left[k] = 'sprite %d: %s' % (sid, why[sid])
                for s in sids & set(changed):
                    changed.pop(s)
                    why.setdefault(s, '%s %d is left whole' % k)
                    blocked.add(s)
                moved = True
        if not moved:
            break
    for k in left:
        stats.pop(k, None)
    return changed, stats, left


# ------------------------------------------------------------------------------------------------ build
def build(a, log=print):
    dat, spr = Dat(a.dat), Spr(a.spr)
    if not (spr.u32count and spr.alpha):
        raise SystemExit('not an alpha u32 spr')
    changed, stats, left = plan(dat, spr)
    removed = sum(v[0] for v in stats.values())
    empty = sum(1 for t in changed.values() if not (t[..., 3] > 0).any())
    log('effects and missiles cleaned: %d (%d effects, %d missiles), left whole: %d' % (
        len(stats), sum(1 for k in stats if k[0] == 'effect'), sum(1 for k in stats if k[0] == 'missile'), len(left)))
    for k, w in sorted(left.items()):
        log('  left whole: %s %d: %s' % (k[0], k[1], w))
    log('sprites to rewrite: %d (%d empty afterwards), mesh pixels removed over all frames: %d' % (len(changed), empty, removed))
    if getattr(a, 'stats_out', None):
        with open(a.stats_out, 'w', newline='') as fh:
            w = csv.writer(fh, lineterminator='\n')
            w.writerow(['kind', 'id', 'removed', 'frames', 'opaque'])
            for (cat, i), (r, n, o) in sorted(stats.items()):
                w.writerow([cat, i, r, n, o])
    if a.dry_run:
        log('dry run: nothing written')
        return changed, stats, left
    if os.path.abspath(os.path.dirname(a.dat)) == os.path.abspath(a.out_dir):
        raise SystemExit('out-dir must differ from the input dir')
    st = os.statvfs(os.path.dirname(os.path.abspath(a.out_dir)) or '.')
    if st.f_bavail * st.f_frsize < len(spr.m) + (64 << 20):
        raise SystemExit('not enough disk space for the output spr (%s bytes)' % f'{len(spr.m):,}')
    os.makedirs(a.out_dir, exist_ok=True)
    dat_path, spr_path = os.path.join(a.out_dir, 'Tibia.dat'), os.path.join(a.out_dir, 'Tibia.spr')
    with open(a.dat, 'rb') as s, open(dat_path, 'wb') as d:
        d.write(s.read())
    size, dropped = cws.write_spr_in_place(spr_path, spr, changed)
    log('wrote %s, %s (%s bytes, %d records dropped)' % (dat_path, spr_path, f'{size:,}', dropped))
    verify(dat, spr, changed, stats, spr_path, log)
    return changed, stats, left


def verify(dat, spr, changed, stats, spr_path, log):
    ns = Spr(spr_path)
    nd = Dat(os.path.join(os.path.dirname(spr_path), 'Tibia.dat'))
    assert ns.count == spr.count and ns.signature == spr.signature
    assert nd.data == dat.data, 'dat differs'
    for sid in range(1, spr.count + 1):
        if sid in changed:
            continue
        x, y = int(spr.offs[sid - 1]), int(ns.offs[sid - 1])
        assert (x == 0) == (y == 0), ('slot emptiness changed', sid)
        if x:
            n = 5 + struct.unpack_from('<H', spr.m, x + 3)[0]
            assert spr.m[x:x + n] == ns.m[y:y + n], ('record bytes changed', sid)
    for sid, tile in changed.items():
        got = ns.sprite(sid)
        got = np.zeros((32, 32, 4), np.uint8) if got is None else iat.decoded(got)
        assert np.array_equal(got, tile), ('rewritten sprite differs', sid)
    # every changed pixel of every cleaned thing is a mesh pixel of the rule, colours never change
    bad = 0
    for (cat, i) in stats:
        t = (nd.effects if cat == 'effect' else nd.missiles)[i - 1]
        for (_k, old, _tl), (_k2, new, _tl2) in zip(canvases(t, spr), canvases(t, ns)):
            diff = np.any(old != new, axis=2)
            if diff.any():
                m = mesh_mask(old)
                if not (diff <= m).all() or (new[diff] != 0).any():
                    bad += 1
    assert not bad, '%d frames changed outside the rule' % bad
    log('verified: dat identical, %d unchanged records identical, %d rewritten sprites decode to the cleaned tiles, every '
        'changed pixel is a mesh pixel' % (spr.count - len(changed), len(changed)))


def stats_rows(dat, spr):
    rows = []
    for cat, t in things(dat):
        if not t.sprites or not any(int(s) for s in t.sprites):
            continue
        n = count_mesh(t, spr)
        if n:
            rows.append({'kind': cat, 'id': t.id, 'mesh_pixels': n, 'cleaned': int(n > 0)})
    return rows


def check_clean(dat, spr):
    return ['%s %d: %d mesh pixels left' % (r['kind'], r['id'], r['mesh_pixels']) for r in stats_rows(dat, spr) if r['cleaned']]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    for name in ('build', 'stats', 'check-clean'):
        p = sub.add_parser(name)
        p.add_argument('dat')
        p.add_argument('spr')
        if name == 'build':
            p.add_argument('--out-dir', required=True)
            p.add_argument('--dry-run', action='store_true')
            p.add_argument('--stats-out', help='CSV of every cleaned thing: kind, id, mesh pixels removed, frames, opaque pixels')
        if name == 'stats':
            p.add_argument('--out')
    a = ap.parse_args(argv)
    if a.cmd == 'build':
        build(a)
        return 0
    dat, spr = Dat(a.dat), Spr(a.spr)
    if a.cmd == 'stats':
        rows = stats_rows(dat, spr)
        if a.out:
            with open(a.out, 'w', newline='') as fh:
                w = csv.DictWriter(fh, ['kind', 'id', 'mesh_pixels', 'cleaned'], lineterminator='\n')
                w.writeheader()
                w.writerows(rows)
        print('%d things with mesh pixels, %d at or over %d' % (len(rows), sum(r['cleaned'] for r in rows), MIN_REMOVED))
        return 0
    bad = check_clean(dat, spr)
    for b in bad:
        print(b)
    if bad:
        return 1
    print('no effect or missile has %d or more mesh pixels' % MIN_REMOVED)
    return 0


if __name__ == '__main__':
    sys.exit(main())
