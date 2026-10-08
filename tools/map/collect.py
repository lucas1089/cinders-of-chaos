"""Collect survey JSON files into one ranked summary (stats.json + stats.csv).

    python3 -I collect.py OUT_DIR survey1.json [survey2.json ...] [--alias alias.json]

Quality score (0-100) per map, from the natural area types (forest, grassland, dirt, desert, ice, swamp,
lava, cave) weighted by their open tiles:
  35 x border_or_wall coverage of ground transitions (water edges left out)
  20 x detail: nature deco per open tile, full marks inside 0.12-0.80, linear below, falling above 0.80
  15 x variation: 1 - share of 16x16 blocks whose main ground family uses one id for >= 95 % of tiles
  15 x not barren: 1 - min(1, 4 x share of open tiles in blocks that are single-id AND under 0.05 deco
       per tile (needs the survey's _blocks.npz next to the .json))
  15 x no spam: 1 - min(1, 50 x share of tiles with 3+ deco items)
minus 10 when more than 1 % of item uses have ids missing from items.otb.
Maps with fewer than 20 000 open tiles in natural areas are scored but flagged 'small'.
"""
import sys, os, json, csv

NAT = ('forest', 'grassland', 'dirt', 'desert', 'ice', 'swamp', 'lava', 'cave')
TYPES = ('town', 'building', 'dungeon', 'cave', 'forest', 'grassland', 'dirt', 'desert', 'ice', 'swamp', 'lava', 'water', 'exotic')
KEYS = ('share_of_open', 'deco_per_tile', 'nature_per_tile', 'furniture_per_tile', 'lights_per_100', 'empty_share',
        'heavy_share', 'border_coverage', 'border_or_wall', 'ground_variants_median', 'flat_block_share',
        'transitions_per_100', 'water_edge_coverage', 'deco_block_p25', 'deco_block_p75', 'distinct_deco_ids', 'distinct_border_ids')


def wavg(rows, k):
    num = den = 0.0
    for v in rows:
        x = v.get(k)
        if x is None:
            continue
        num += x * v['open_tiles']; den += v['open_tiles']
    return num / den if den else None


def barren_share(path):
    import numpy as np
    if not os.path.exists(path):
        return None
    z = np.load(path)
    B = z['blocks']
    if B.ndim != 2 or not len(B):
        return 0.0
    T = list(z['types']); c = {k: i for i, k in enumerate(z['cols'])}
    b = B[np.isin(B[:, c['type']], [T.index(t) for t in NAT])]
    o = b[:, c['open']]
    bar = (b[:, c['topshare']] >= 0.95) & (b[:, c['deco']] / np.maximum(o, 1) < 0.05)
    return float((o * bar).sum() / max(o.sum(), 1))


def score(d, barren=None):
    rows = [v for t, v in d.get('areas', {}).items() if t in NAT and v.get('open_tiles', 0) > 0]
    if not rows:
        return None, {}
    cov = wavg(rows, 'border_or_wall') or 0.0
    nat = wavg(rows, 'nature_per_tile') or 0.0
    flat = wavg(rows, 'flat_block_share') or 0.0
    heavy = wavg(rows, 'heavy_share') or 0.0
    if nat < 0.12:
        det = nat / 0.12
    elif nat <= 0.80:
        det = 1.0
    else:
        det = max(0.0, 1.0 - (nat - 0.80) / 0.8)
    bar = barren or 0.0
    s = 35 * cov + 20 * det + 15 * (1 - flat) + 15 * (1 - min(1.0, 4 * bar)) + 15 * (1 - min(1.0, 50 * heavy))
    ov = d.get('overall', {})
    unk = ov.get('unknown_item_uses', 0) / max(ov.get('items', 1), 1)
    if unk > 0.01:
        s -= 10
    parts = dict(natural_open=sum(v['open_tiles'] for v in rows), border_or_wall=round(cov, 3), nature_per_tile=round(nat, 3),
                 flat_block_share=round(flat, 3), barren_share=round(bar, 3), heavy_share=round(heavy, 4), unknown_share=round(unk, 4))
    return round(s, 1), parts


def main():
    a = sys.argv[1:]
    alias = {}
    if '--alias' in a:
        i = a.index('--alias'); alias = json.load(open(a[i + 1])); del a[i:i + 2]
    out, files = a[0], a[1:]
    maps = []
    for f in files:
        d = json.load(open(f))
        lab = alias.get(d.get('label', ''), d.get('label', os.path.basename(f)))
        s, parts = score(d, barren_share(f[:-5] + '_blocks.npz'))
        if s is None:
            continue
        ov = d['overall']
        rec = dict(map=lab, score=s, small=parts['natural_open'] < 20000, full=ov['open_tiles'] >= 100000, **parts,
                   tiles=ov['tiles'], open_tiles=ov['open_tiles'], floors_used=ov['floors_used'],
                   items_per_tile=ov['items_per_tile'], items_version=ov['items_version'], towns=ov['towns'],
                   bounds=ov['bounds_p1_p99'], house_tiles=ov['house_tiles'],
                   overall_detail={k: d['overall_detail'].get(k) for k in KEYS if k in d['overall_detail']},
                   areas={t: {k: v.get(k) for k in KEYS + ('open_tiles', 'blocks')} for t, v in d['areas'].items()},
                   hunting=d.get('hunting'), houses=d.get('houses'),
                   towns_detail=[{k: v for k, v in t.items() if k not in ('temple', 'footprint')} for t in d.get('towns', [])],
                   floorchanges=d.get('floorchanges'))
        maps.append(rec)
    maps.sort(key=lambda r: (-r['score'], r['map']))
    for i, r in enumerate(maps):
        r['rank'] = i + 1
    os.makedirs(out, exist_ok=True)
    json.dump(dict(note='Map study summary; see docs/MAP_GUIDE.md. Scores: tools/map/collect.py.', maps=maps),
              open(os.path.join(out, 'stats.json'), 'w'), separators=(',', ':'))
    with open(os.path.join(out, 'stats.csv'), 'w', newline='') as fh:
        w = csv.writer(fh)
        w.writerow(['rank', 'map', 'score', 'small', 'area_type'] + list(KEYS) + ['open_tiles'])
        for r in maps:
            for t in TYPES:
                v = r['areas'].get(t)
                if v:
                    w.writerow([r['rank'], r['map'], r['score'], r['small'], t] + [v.get(k) for k in KEYS] + [v.get('open_tiles')])
    for r in maps:
        print(f"{r['rank']:3d} {r['score']:5.1f} {'S' if r['small'] else ' '} {r['map']:28s} cov {r['border_or_wall']:.2f} nat {r['nature_per_tile']:.2f} flat {r['flat_block_share']:.2f} barren {r['barren_share']:.3f} heavy {r['heavy_share']:.4f} open {r['open_tiles']}")


if __name__ == '__main__':
    main()
