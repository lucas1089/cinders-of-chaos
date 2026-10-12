"""Score a rectangle of a map against docs/MAP_GUIDE.md.

    python3 -I tools/map/score_area.py MAP.otbm ITEMS.otb ITEMS.xml X0 Y0 X1 Y1 Z [Z2 ...]
            [--dat Tibia.dat] [--type cave] [--spawn F-spawn.xml] [--json OUT.json] [--png OUT.png --spr Tibia.spr]

Loads only the map (a cached .npz from otbm.save_cache() works too), cuts the rectangle on each floor given,
and reports per floor and per area type:
  border coverage   share of natural ground transitions with a border item (or a wall) on either tile
  deco per tile     decoration items per open tile, and the spread over 16x16 blocks
  empty share       open tiles with nothing on them but ground and borders
  heavy share       open tiles with 3 or more deco items (spam)
  ground variants   distinct ground ids inside the main ground family per 16x16 block; flat-block share
  lights            light sources per 100 open tiles (caves, dungeons)
  hunting layout    with --spawn: corridor width, dead ends, loops, room share around the spawns
Each value is compared with the band of the guide for the detected (or --type) area type and printed as
OK / LOW / HIGH. Exit code 0 when nothing is out of band, 1 otherwise. Deterministic.
The bands come from the best-ranked maps of the study (docs/map_guide/stats.json); edit BANDS to retune.
"""
import sys, os, json, argparse, collections
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import otbm
from itemdb import ItemDB
import analyze as an

# (low, high) per metric and area type; None = no limit on that side. Taken from the 10th-90th percentile of
# the best-ranked full-size maps of the study (score >= 88, docs/map_guide/stats.json), widened a little because
# a reviewed rectangle is much smaller than a whole map. See docs/MAP_GUIDE.md section "Numbers per area type".
GENERIC = {
    'border_or_wall': (0.97, None),     # ground transitions with a border or wall item on either tile
    'heavy_share': (None, 0.01),        # tiles with 3+ deco items (spam)
}
BANDS = {
    'town':      dict(deco_per_tile=(0.12, 0.40), empty_share=(None, 0.88), lights_per_100=(1.0, None), heavy_share=(None, 0.012)),
    'building':  dict(deco_per_tile=(0.10, 0.40), empty_share=(None, 0.90), lights_per_100=(1.5, None), heavy_share=(None, 0.012)),
    'dungeon':   dict(deco_per_tile=(0.10, 0.35), empty_share=(None, 0.90), lights_per_100=(2.0, None)),
    'cave':      dict(deco_per_tile=(0.10, 0.35), empty_share=(None, 0.90), ground_variants_median=(3, None),
                      flat_block_share=(None, 0.25)),
    'forest':    dict(deco_per_tile=(0.30, 0.60), empty_share=(None, 0.70), ground_variants_median=(6, None),
                      flat_block_share=(None, 0.30)),
    'grassland': dict(deco_per_tile=(0.10, 0.30), empty_share=(None, 0.90), flat_block_share=(None, 0.50)),
    'dirt':      dict(deco_per_tile=(0.15, 0.35), empty_share=(None, 0.85), flat_block_share=(None, 0.35)),
    'desert':    dict(deco_per_tile=(0.04, 0.25)),
    'ice':       dict(deco_per_tile=(0.02, 0.20), ground_variants_median=(10, None), flat_block_share=(None, 0.10)),
    'swamp':     dict(deco_per_tile=(0.08, 0.30)),
    'lava':      dict(deco_per_tile=(0.03, 0.15), lights_per_100=(5.0, None)),
    'water':     dict(),
    'exotic':    dict(deco_per_tile=(0.07, 0.30), lights_per_100=(2.0, None)),
    'hunting':   dict(corridor_width_median=(3, 12), dead_end_per_1000=(None, 30), loops_per_1000=(5, None),
                      monsters_per_100_hunt_tiles=(1.5, 5.0)),
}


MIN_BLOCKS = 3   # an area type needs at least this many 16x16 blocks in the rectangle to be judged


def band(t, k):
    return BANDS.get(t, {}).get(k, GENERIC.get(k))


def score_rect(m, db, x0, y0, x1, y1, zs, force_type=None, spawns=None):
    it = an.ItemTables(db)
    out = dict(rect=[x0, y0, x1, y1], floors={})
    for z in zs:
        idx = m.rect(x0, y0, x1, y1, z)
        if len(idx) == 0:
            out['floors'][z] = dict(tiles=0); continue
        sub = otbm.Map({k: v[idx] for k, v in m.tiles.items()}, m.items, [], m.header)
        f = an.tile_features(_slice_items(m, idx, sub), it)
        w, h = x1 - x0 + 1, y1 - y0 + 1
        D = an.to_dense(f, np.arange(len(idx)), x0, y0, w, h)
        rows = collections.defaultdict(list)
        for by in range(0, h, 16):
            for bx in range(0, w, 16):
                sl = (slice(by, min(by + 16, h)), slice(bx, min(bx + 16, w)))
                t = force_type or an.block_type(D, z, sl)
                if t is None:
                    continue
                rows[t].append(an.block_metrics(D, sl))
        res = {t: an.summarize(r) for t, r in rows.items()}
        allr = [r for rr in rows.values() for r in rr]
        fl = dict(tiles=int(len(idx)), open=int(D['open'].sum()), types=res, total=an.summarize(allr) if allr else {})
        if spawns:
            fl['hunting'] = hunting(D, spawns, x0, y0, z)
        out['floors'][z] = fl
    return out


def _slice_items(m, idx, sub):
    cnt = m.tiles['cnt'][idx].astype(np.int64); off = m.tiles['off'][idx].astype(np.int64)
    take = np.concatenate([np.arange(o, o + c) for o, c in zip(off, cnt)]) if len(idx) else np.zeros(0, np.int64)
    t = dict(sub.tiles); t['cnt'] = cnt.astype(np.uint16)
    t['off'] = (np.cumsum(cnt) - cnt).astype(np.uint32)
    return otbm.Map(t, m.items[take], [], m.header)


def hunting(D, spawns, x0, y0, z):
    from scipy import ndimage
    h, w = D['walk'].shape
    mm = np.zeros((h, w), bool)
    n = 0
    for s in spawns:
        for (x, y, zz, _) in s['mons']:
            if zz == z and 0 <= x - x0 < w and 0 <= y - y0 < h:
                mm[y - y0, x - x0] = True; n += 1
    if not n:
        return None
    wk = D['walk']
    area = ndimage.maximum_filter(mm, size=13) & wk
    wmin = np.minimum(an.run_lengths(wk, 0), an.run_lengths(wk, 1))
    nbh = np.zeros((h, w), np.int32)
    nbh[:, 1:] += wk[:, :-1]; nbh[:, :-1] += wk[:, 1:]; nbh[1:, :] += wk[:-1, :]; nbh[:-1, :] += wk[1:, :]
    V = int(area.sum())
    E = int((area[:, 1:] & area[:, :-1]).sum() + (area[1:, :] & area[:-1, :]).sum())
    Q = int((area[1:, 1:] & area[:-1, 1:] & area[1:, :-1] & area[:-1, :-1]).sum())
    _, C = ndimage.label(area)
    W = wmin[area]
    return dict(monsters=n, hunt_tiles=V, monsters_per_100_hunt_tiles=round(100 * n / max(V, 1), 2),
                corridor_width_median=float(np.median(W)) if V else None,
                dead_end_per_1000=round(1000 * int((area & (nbh == 1)).sum()) / max(V, 1), 2),
                loops_per_1000=round(1000 * max(E - V + C - Q, 0) / max(V, 1), 2),
                room_share=round(float((W >= 5).mean()) if V else 0, 3))


def verdicts(res):
    lines, bad = [], 0
    for z, fl in res['floors'].items():
        for t, s in fl.get('types', {}).items():
            if s.get('blocks', 0) < MIN_BLOCKS:
                lines.append(f'z{z} {t:9s} only {s.get("blocks", 0)} block(s) of 16x16, not judged')
                continue
            for k in ('border_or_wall', 'deco_per_tile', 'empty_share', 'heavy_share', 'ground_variants_median',
                      'flat_block_share', 'lights_per_100'):
                b = band(t, k); v = s.get(k)
                if b is None or v is None:
                    continue
                lo, hi = b
                st = 'LOW' if lo is not None and v < lo else 'HIGH' if hi is not None and v > hi else 'OK'
                bad += st != 'OK'
                lines.append(f'z{z} {t:9s} {k:24s} {v:>7} band {lo}..{hi} {st}')
        hu = fl.get('hunting')
        if hu:
            for k in ('corridor_width_median', 'dead_end_per_1000', 'loops_per_1000', 'monsters_per_100_hunt_tiles'):
                b = band('hunting', k); v = hu.get(k)
                if b is None or v is None:
                    continue
                lo, hi = b
                st = 'LOW' if lo is not None and v < lo else 'HIGH' if hi is not None and v > hi else 'OK'
                bad += st != 'OK'
                lines.append(f'z{z} hunting   {k:24s} {v:>7} band {lo}..{hi} {st}')
    return lines, bad


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('map'); ap.add_argument('otb'); ap.add_argument('xml')
    ap.add_argument('x0', type=int); ap.add_argument('y0', type=int); ap.add_argument('x1', type=int); ap.add_argument('y1', type=int)
    ap.add_argument('z', type=int, nargs='+')
    ap.add_argument('--dat'); ap.add_argument('--type', choices=an.AREA_TYPES); ap.add_argument('--spawn')
    ap.add_argument('--json'); ap.add_argument('--png'); ap.add_argument('--spr')
    a = ap.parse_args()
    m = otbm.load_map(a.map)
    db = ItemDB(a.otb, a.xml, a.dat)
    sp = None
    if a.spawn:
        from survey import parse_spawns
        sp = parse_spawns(a.spawn)
    res = score_rect(m, db, a.x0, a.y0, a.x1, a.y1, a.z, a.type, sp)
    for z, fl in res['floors'].items():
        print(f"floor {z}: {fl.get('tiles', 0)} tiles, {fl.get('open', 0)} open; area types: "
              + ', '.join(f"{t} {s['blocks']} blocks" for t, s in fl.get('types', {}).items()))
    lines, bad = verdicts(res)
    print('\n'.join(lines))
    print(f'{bad} value(s) out of band' if bad else 'all values inside the guide bands')
    if a.json:
        json.dump(res, open(a.json, 'w'), indent=1)
    if a.png:
        from datspr import Spr
        import render
        img, _ = render.render(m, db, Spr(a.spr), a.x0, a.y0, a.x1, a.y1, a.z[0])
        img.save(a.png)
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
