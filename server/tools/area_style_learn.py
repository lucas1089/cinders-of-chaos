#!/usr/bin/env python3
"""Learn an area planner style profile from a painted area (O743; server/README.md "Style profile (O743)").

    python3 -I tools/area_style_learn.py REF.otbm --box X1,Y1,X2,Y2,Z [--name KEY] [--json OUT] [--write]

Reads the box of the map (tools/map/otbm.py; only read, never written) and counts, per tile class, the item shares:
  grounds     the walkable tiles' ground families and ids, and the families of the tiles nobody walks on
  walls       wall pieces by brush and kind
  decoration  every other legal item: by decoration kit group and id, with the blocking, light, vegetation and
              debris subsets
and the statistics: decoration items per 100 walkable tiles (and of each subset), how decoration groups (sizes of
the 8-neighbour groups of decorated tiles, groups of 3+ per 100 walkable tiles), wall run lengths, the open share
(walkable tiles whose eight neighbours are all walkable) and the corridor width (per walkable tile the shorter of
its east-west and north-south walkable runs).

Only ids the planner knows are kept (area_plan_style.catalogue: our grounds and walls, the decoration kits, the
generator's own ids and data/items/art_items.csv); any other id is reported and dropped. The profile holds shares and
statistics, never a position or a tile layout (the copy guard of area_style_learn_test.py checks a compile against its
reference). A box with fewer than MIN_WALKABLE walkable tiles is refused: too few to be statistics.

--write writes tools/areaplan/styles/<KEY>.json (KEY defaults to the file name); --json OUT writes elsewhere; without
either the summary is printed only. Learn only from our own maps (a compiled plan, our world map), never from an
imported or third-party map.
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'map'))

import area_plan_style as ST   # noqa: E402

MIN_WALKABLE = 200
D8 = ((-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1))


def shares(counts, digits=4):
    total = float(sum(counts.values()))
    if not total:
        return {}
    return {str(k): round(v / total, digits) for k, v in sorted(counts.items(), key=lambda kv: str(kv[0]))}


def hist(values, cap):
    out = {}
    for v in values:
        k = str(v) if v < cap else '%d+' % cap
        out[k] = out.get(k, 0) + 1
    return shares(out)


def read_box(path, box):
    """{(x, y, z): (ground or None, [item ids])} of the tiles in the box"""
    import otbm
    m = otbm.load_map(path)
    x1, y1, x2, y2, z = box
    out = {}
    for i in m.rect(x1, y1, x2, y2, z):
        t = m.tiles
        st = [int(v) for v in m.stack(int(i))]
        out[(int(t['x'][i]), int(t['y'][i]), int(t['z'][i]))] = st
    return out


def learn(stacks, cat, name, source=None):
    """(profile, report): stacks {(x, y, z): [ids, ground first]} -> the profile dict; report: walkable, dropped ids"""
    walk, wallt, deco_t = set(), set(), {}
    g_walk, g_ids, g_other = {}, {}, {}
    brushes, wkinds = {}, {}
    groups, dids = {}, {}
    sub = {'block': {}, 'light': {}, 'vegetation': {}, 'debris': {}}
    dropped = {}
    for pos in sorted(stacks):
        st = stacks[pos]
        ground = st[0] if st and st[0] in cat['ground'] else None
        items = st[1:] if ground is not None else st
        fam = cat['ground'].get(ground)
        blocked = fam is None or not cat['fam_walk'].get(fam, False)
        n_deco = 0
        for iid in items:
            role, fl = ST.item_class(cat, iid)
            if role is None:
                dropped[iid] = dropped.get(iid, 0) + 1
            elif role == 'border':
                blocked = blocked or fl['block']
            elif role == 'wall':
                blocked = True
                wallt.add(pos)
                b = cat['wall'][iid]
                brushes[b] = brushes.get(b, 0) + 1
                k = cat['wall_kind'][iid]
                wkinds[k] = wkinds.get(k, 0) + 1
            elif role == 'decor':
                n_deco += 1
                dids[iid] = dids.get(iid, 0) + 1
                if fl['group']:
                    groups[fl['group']] = groups.get(fl['group'], 0) + 1
                for k in sub:
                    if fl[k]:
                        sub[k][iid] = sub[k].get(iid, 0) + 1
                if fl['block']:
                    blocked = True
        if n_deco:
            deco_t[pos] = n_deco
        if fam and pos not in wallt:
            if cat['fam_walk'].get(fam, False):
                g_ids[ground] = g_ids.get(ground, 0) + 1
                g_walk[fam] = g_walk.get(fam, 0) + 1
            else:
                g_other[fam] = g_other.get(fam, 0) + 1
        if not blocked:
            walk.add(pos)
    nw = len(walk)
    per = lambda n: round(100.0 * n / max(1, nw), 3)     # noqa: E731
    # decoration groups: 8-neighbour groups of decorated tiles
    seen, sizes = set(), []
    for p in sorted(deco_t):
        if p in seen:
            continue
        seen.add(p)
        todo, n = [p], 0
        while todo:
            q = todo.pop()
            n += 1
            for dx, dy in D8:
                r = (q[0] + dx, q[1] + dy, q[2])
                if r in deco_t and r not in seen:
                    seen.add(r)
                    todo.append(r)
        sizes.append(n)
    # wall runs, east-west and north-south
    runs = []
    for p in wallt:
        for dx, dy in ((1, 0), (0, 1)):
            if (p[0] - dx, p[1] - dy, p[2]) in wallt:
                continue
            n, q = 0, p
            while q in wallt:
                n += 1
                q = (q[0] + dx, q[1] + dy, q[2])
            if n >= 2:
                runs.append(n)
    # corridor width and open share
    widths, open_n = [], 0
    for p in walk:
        if all((p[0] + dx, p[1] + dy, p[2]) in walk for dx, dy in D8):
            open_n += 1
        w = []
        for dx, dy in ((1, 0), (0, 1)):
            n = 1
            for sgn in (1, -1):
                q = (p[0] + sgn * dx, p[1] + sgn * dy, p[2])
                while q in walk:
                    n += 1
                    q = (q[0] + sgn * dx, q[1] + sgn * dy, q[2])
            w.append(n)
        widths.append(min(w))
    n_deco = sum(dids.values())
    prof = dict(
        schema=ST.SCHEMA, key=name,
        source=dict(name=(source or {}).get('name', name), box=(source or {}).get('box'), walkable=nw,
                    area=len(stacks)),
        grounds=dict(families=shares(g_walk), ids=shares(g_ids), unwalked=shares(g_other)),
        walls=dict(brushes=shares(brushes), kinds=shares(wkinds), pieces=sum(brushes.values())),
        decor=dict(groups=shares(groups), ids=shares(dids), items=n_deco,
                   block=shares(sub['block']), light=shares(sub['light']), vegetation=shares(sub['vegetation']),
                   debris=shares(sub['debris'])),
        density=dict(decor_per100=per(n_deco), block_per100=per(sum(sub['block'].values())),
                     light_per100=per(sum(sub['light'].values())), vegetation_per100=per(sum(sub['vegetation'].values())),
                     debris_per100=per(sum(sub['debris'].values())), decorated_share=round(len(deco_t) / max(1, nw), 4)),
        clusters=dict(sizes=hist(sizes, 9), per100=per(len(sizes)), per100_3plus=per(sum(1 for s in sizes if s >= 3)),
                      mean=round(sum(sizes) / max(1, len(sizes)), 3)),
        wall_runs=dict(lengths=hist(runs, 13), mean=round(sum(runs) / max(1, len(runs)), 3)),
        open_share=round(open_n / max(1, nw), 4),
        corridor_width=hist(widths, 7),
        dropped_items=sum(dropped.values()))
    return prof, dict(walkable=nw, dropped=dropped)


def parse_box(s):
    v = [int(x) for x in s.split(',')]
    if len(v) != 5 or v[0] > v[2] or v[1] > v[3]:
        raise argparse.ArgumentTypeError('--box X1,Y1,X2,Y2,Z with X1 <= X2 and Y1 <= Y2')
    return v


def main(argv=None, out=sys.stdout):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('ref', help='the painted area (OTBM)')
    ap.add_argument('--box', type=parse_box, required=True, help='X1,Y1,X2,Y2,Z')
    ap.add_argument('--name', help='profile key (default: the file name)')
    ap.add_argument('--json', help='write the profile to this file')
    ap.add_argument('--write', action='store_true', help='write tools/areaplan/styles/<KEY>.json')
    ap.add_argument('--style-dir', help=argparse.SUPPRESS)
    a = ap.parse_args(argv)
    key = a.name or os.path.splitext(os.path.basename(a.ref))[0].lower().replace('-', '_')
    if not ST.KEY_RE.match(key):
        print('refused: the key "%s" is not lower-case letters, digits and _' % key, file=out)
        return 2
    stacks = read_box(a.ref, a.box)
    prof, rep = learn(stacks, ST.catalogue(), key, dict(name=os.path.basename(a.ref), box=','.join(str(v) for v in a.box)))
    if rep['walkable'] < MIN_WALKABLE:
        print('refused: %d walkable tiles in the box, at least %d are needed to be statistics' % (rep['walkable'], MIN_WALKABLE),
              file=out)
        return 2
    p = lambda s='': print(s, file=out)  # noqa: E731
    p('style %s: %d tiles, %d walkable, open share %.2f' % (key, len(stacks), rep['walkable'], prof['open_share']))
    top = lambda d, n=6: ', '.join('%s %.2f' % kv for kv in sorted(d.items(), key=lambda kv: (-kv[1], kv[0]))[:n]) or '-'  # noqa: E731
    p('  ground families: ' + top(prof['grounds']['families']))
    p('  wall brushes:    ' + top(prof['walls']['brushes']))
    p('  decor groups:    ' + top(prof['decor']['groups']))
    d = prof['density']
    p('  per 100 walkable: decor %.2f, blocking %.2f, light %.2f, vegetation %.2f, debris %.2f'
      % (d['decor_per100'], d['block_per100'], d['light_per100'], d['vegetation_per100'], d['debris_per100']))
    p('  clusters: %.2f per 100 (%.2f of 3+), mean size %.2f; wall run mean %.2f'
      % (prof['clusters']['per100'], prof['clusters']['per100_3plus'], prof['clusters']['mean'], prof['wall_runs']['mean']))
    p('  corridor width: ' + ', '.join('%s %.2f' % kv for kv in sorted(prof['corridor_width'].items())))
    if rep['dropped']:
        p('  dropped %d item(s) of %d unknown id(s): %s' % (sum(rep['dropped'].values()), len(rep['dropped']),
                                                          ', '.join('%d x%d' % kv for kv in sorted(rep['dropped'].items())[:20])))
    text = json.dumps(prof, indent=1, sort_keys=True) + '\n'
    assert not ST.problems(prof), ST.problems(prof)
    if a.json:
        with open(a.json, 'w', encoding='utf-8') as f:
            f.write(text)
        p('wrote ' + a.json)
    if a.write:
        d_ = a.style_dir or ST.STYLE_DIR
        os.makedirs(d_, exist_ok=True)
        path = os.path.join(d_, key + '.json')
        with open(path, 'w', encoding='utf-8') as f:
            f.write(text)
        p('wrote ' + path)
    return 0


if __name__ == '__main__':
    sys.exit(main())
