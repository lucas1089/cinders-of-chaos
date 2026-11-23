"""Plateaus and cliffs over several floors with ramps (O744, server/README.md "Plateaus and cliffs (O744)").

Plan field `plateaus` (off by default, so a held plan keeps its bytes):

    "plateaus": {"count": 3, "size": [12, 18], "height": [1, 2], "ramps": [1, 2], "zones": ["ridge", "crags"]}

A plateau is a raised walkable region one floor up (z - 1) over a zone of floor 1, and for height 2 a second, smaller
tier on top of it (z - 2). Pieces, all from our tables (no new id):
  * the cliff: the biome's rock family (the view frame family, `mountain` 919 in the open biomes, `earth` in a cave)
    whose border set runs over any lower ground (`gravel` 4468-4479 for the mountain, `dirt_wall` for the earth). Our
    art has no cliff or ledge piece of its own (art_items.csv holds none), so the cliff is the generator's own mountain
    edge: the plateau's footprint is mountain ground on the floor below (the cliff face, not walkable) and the gravel
    pieces lie on the tiles round it (the cliff foot, blocking as the generator's rock edges are).
  * the top: the footprint again one floor up with the ground that lay under it; its outer ring is mountain again (the
    lip, closed except at the ramps) and the gravel pieces on the tiles inside the lip; the rest is walkable.
  * the ramps: our stair brush (O740, the rule of a plan's `stairs` connection): the stone stairs 3687 on the floor
    below lead up to the tile north of the stairs ground 411 above; stepping on 411 goes down south of the stone
    stairs. The brush runs north-south only, so a ramp is cut into a south facing edge: a notch three tiles wide in the
    cliff and in the lip, the stairs in its middle, the tile south of it and the tile north of the stairs ground clear.

Pure Python on the compiled tiles; area_plan_compile.py calls place_all after the buildings and before the teleports,
spawns and decoration, then qa on the final tiles.
"""
import random

import map_tile_rules as MR

D8 = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1))
CLEAR = 2           # tiles between a plateau (with its cliff foot) and a route, a building, a crossing or another plateau
WATER_CLEAR = 3     # tiles between a plateau's cliff foot and any water
ARRIVAL_CLEAR = 4   # Chebyshev tiles from the arrival
LEDGE = 4           # height 2: the upper tier lies LEDGE + 1 tiles inside the lower footprint
MIN_TOP = 12        # walkable tiles a tier needs on top
SHAPES = 4          # shapes tried per size
MIN_TWO = 17        # tiles a side of the lower footprint of a plateau of height 2 (validator and placing)
SPACING = 6         # columns between two ramps of one tier


class PlateauError(Exception):
    pass


def spec(plan):
    """the plan's `plateaus` with its defaults, or None when there are none"""
    p = plan.get('plateaus')
    if not p or not p.get('count'):
        return None
    rng_of = lambda v, d: (v, v) if isinstance(v, int) else tuple(v or d)
    return dict(count=p['count'], size=tuple(p.get('size', (12, 16))), height=rng_of(p.get('height'), (1, 1)),
                ramps=rng_of(p.get('ramps'), (1, 2)), zones=list(p.get('zones', ())))


# ------------------------------------------------------------------------------------------------ shapes
def shape(rng, w, h, wander=None):
    """a footprint of w x h tiles: rows whose west and east edges wander by a tile, the corners cut, never round or
    square; the last rows only narrow downwards and the first ones only widen (no one tile spike) -> {(dx, dy)}"""
    if w < 5 or h < 5:
        raise PlateauError('a plateau is at least 5 x 5 tiles')
    lim = wander or max(1, w // 6)
    left, right = [], []
    lo, hi = rng.randint(0, 1), w - 1 - rng.randint(0, 1)
    for _y in range(h):
        lo = min(lim, max(0, lo + rng.choice((-1, 0, 0, 1))))
        hi = max(w - 1 - lim, min(w - 1, hi + rng.choice((-1, 0, 0, 1))))
        left.append(lo)
        right.append(hi)
    med = lambda v: [sorted(v[max(0, y - 1):y + 2])[len(v[max(0, y - 1):y + 2]) // 2] for y in range(len(v))]
    left, right = med(left), med(right)         # no edge that steps out for one row only
    cut = [rng.randint(1, 2) for _k in range(4)]     # nw, ne, sw, se corner cuts
    for k in range(2):
        left[k] += max(0, cut[0] - k)
        right[k] -= max(0, cut[1] - k)
        left[h - 1 - k] += max(0, cut[2] - k)
        right[h - 1 - k] -= max(0, cut[3] - k)
    tail = max(3, h // 3)
    for y in range(h - tail, h):            # narrowing towards the south edge (the ramps' side)
        left[y] = max(left[y], left[y - 1])
        right[y] = min(right[y], right[y - 1])
    for y in range(min(3, h) - 2, -1, -1):  # widening from the north edge
        left[y] = max(left[y], left[y + 1])
        right[y] = min(right[y], right[y + 1])
    moved = True
    while moved:            # a row that steps out past both its neighbours steps back
        moved = False
        for y in range(1, h - 1):
            if left[y] < min(left[y - 1], left[y + 1]):
                left[y], moved = min(left[y - 1], left[y + 1]), True
            if right[y] > max(right[y - 1], right[y + 1]):
                right[y], moved = max(right[y - 1], right[y + 1]), True
    return {(x, y) for y in range(h) for x in range(left[y], right[y] + 1)}


def ring(cells, d=1):
    """the cells within Chebyshev d of `cells` and not in it"""
    out = set()
    for x, y in cells:
        for dx in range(-d, d + 1):
            for dy in range(-d, d + 1):
                out.add((x + dx, y + dy))
    return out - set(cells)


def rim(cells):
    """the cells of `cells` with a neighbour outside it"""
    cells = set(cells)
    return {(x, y) for x, y in cells if any((x + dx, y + dy) not in cells for dx, dy in D8)}


def erode(cells, k):
    """the cells whose square of radius k lies inside `cells`"""
    cells = set(cells)
    return {(x, y) for x, y in cells
            if all((x + dx, y + dy) in cells for dx in range(-k, k + 1) for dy in range(-k, k + 1))}


def ramp_spots(cells):
    """(x, y) of the cells where a ramp fits: a south facing edge flat over five columns, two rows deep over the
    three middle ones and the lip behind it whole"""
    cells = set(cells)
    out = []
    for x, y in sorted(cells, key=lambda t: (t[1], t[0])):
        if all((c, y) in cells and (c, y + 1) not in cells and (c, y - 1) in cells for c in range(x - 2, x + 3)) \
                and all((c, y - 2) in cells for c in range(x - 2, x + 3)) \
                and all((c, y - 3) in cells for c in range(x - 1, x + 2)):
            out.append((x, y))
    return out


def notch(r):
    return {(r[0] - 1, r[1]), r, (r[0] + 1, r[1])}


def levels_of(G, ramps1, G2=None, ramps2=()):
    """the solid (cliff ground) and built cells of each level, relative: level 0 = the base floor, 1 = z - 1, 2 = z - 2.
    -> {level: dict(solid, built, stairs_low, stairs_top)}; built None on level 0 (the base floor's own tiles)"""
    N1 = set().union(*[notch(r) for r in ramps1]) if ramps1 else set()
    N2 = set().union(*[notch(r) for r in ramps2]) if ramps2 else set()
    lv = {0: dict(solid=set(G) - N1, built=None, stairs_low=set(ramps1), stairs_top=set()),
          1: dict(solid=(rim(G) - N1) | ((set(G2) - N2) if G2 else set()), built=set(G),
                  stairs_low=set(ramps2), stairs_top=set(ramps1))}
    if G2:
        lv[2] = dict(solid=rim(G2) - N2, built=set(G2), stairs_low=set(), stairs_top=set(ramps2))
    return lv


def pieces_for(cell, fam_at, bd):
    """the border piece ids a cell wants from every higher family round it (map_tile_rules.border_pieces, our
    generator's rule; a family over this one or over any), lower families first -> (ids, cliff piece ids); None when
    a set the cell needs is not whole in our tables"""
    x, y = cell
    f = fam_at(cell)
    near = {}
    for dx, dy in D8:
        g = fam_at((x + dx, y + dy))
        if g and g != f and bd['fz'].get(g, 0) > bd['fz'].get(f, 0):
            near.setdefault(g, set()).add((dx, dy))
    ids, cliff = [], []
    for g in sorted(near, key=lambda g: (bd['fz'][g], g)):
        setname = bd['rules'].get((g, f)) or bd['rules'].get((g, '*'))
        if not setname:
            continue
        names = bd['pieces'].get(setname)
        if names is None:
            return None
        m = near[g]
        got = [names[n] for n in MR.border_pieces((0, -1) in m, (1, 0) in m, (0, 1) in m, (-1, 0) in m, (1, -1) in m,
                                                  (-1, -1) in m, (1, 1) in m, (-1, 1) in m)]
        ids += got
        if g == bd['cfam']:
            cliff += got
    return ids, cliff


# ------------------------------------------------------------------------------------------------ placing
def cliff_of(meta, mats):
    """(family, ground id, {piece name: id}) of the cliff: the view frame family when its border set runs over any
    lower ground and is whole in our tables, else the mountain"""
    fr = (meta.get('frame') or {}).get('family')
    for fam in (fr, 'mountain'):
        if not fam:
            continue
        setname = mats.get('over_any', {}).get(fam)
        d = mats['families'].get(fam)
        if setname and d and not d['walk'] and setname in mats.get('pieces', {}):
            return fam, d['grounds'][0], mats['pieces'][setname]
    raise PlateauError('the biome has no cliff family (a blocking rock whose border set runs over any ground)')


def place_all(plan, zrect, walk, tiles, special, avoid, arrival, meta, mats, kit, seed, E, Wn, reach_fn, link_edges):
    """place and stamp every plateau. Changes tiles and walk. avoid: tiles a plateau and its cliff foot keep CLEAR from
    (routes, buildings, crossings); reach_fn(walk, edges) -> {tile: steps}.
    -> dict(records, edges, extra (tiles above the plan's floors), foot (the base footprints and cliff feet, for the
    outline), special, prot, skip_border (the stairs on the floor below), open_ok (the stairs grounds above, open to
    the south), top (zone -> walkable tiles on top), ids (pieces and grounds laid))"""
    sp = spec(plan)
    res = dict(records=[], edges=[], extra=set(), foot=set(), special=set(), prot=set(), skip_border=set(), open_ok=set(),
               top={}, ids=set(), grounds=set(), cliff=dict(family=None, ground=None))
    if not sp:
        return res
    stairs_up = kit['brushes']['stairs_up']
    stairs_ground = kit['brushes']['stairs_down_ground']
    try:
        cfam, cground, names = cliff_of(meta, mats)
    except PlateauError as e:
        E('plateaus: %s' % e)
        return res
    border_ids = {i for s_ in (meta['sets'].values() if isinstance(meta['sets'], dict) else []) for i in s_}
    fam_of = {}
    for f, d in meta['families'].items():
        for g in d['grounds']:
            if g is not None:
                fam_of.setdefault(g, f)
    fz = {f: d['z'] for f, d in meta['families'].items()}
    fz.setdefault(cfam, mats['families'][cfam]['z'])
    rules = {(r_['over'], r_['under']): r_['set'] for r_ in meta['borders']}
    rules.setdefault((cfam, '*'), mats['over_any'][cfam])
    bd = dict(cfam=cfam, cground=cground, fam_of=fam_of, fz=fz, rules=rules, pieces=mats.get('pieces', {}),
              fwalk={f: d.get('walk', True) for f, d in meta['families'].items()}, border_ids=border_ids, used=set())
    water = {k for k, t in tiles.items() if (fam_of.get(t['ground']) or '').startswith('water')}
    pick = sp['zones'] or [z['id'] for z in sorted(plan['zones'], key=lambda z: z['id'])
                           if z['floor'] == 1 and z.get('role', 'hunt') not in ('boss', 'camp') and not z.get('pz')]
    pick = sorted(pick, key=lambda zid: (-(zrect[zid][2] - zrect[zid][0] + 1) * (zrect[zid][3] - zrect[zid][1] + 1), zid)) \
        if not sp['zones'] else pick
    if not pick:
        E('plateaus: no zone to put them in (floor 1, not the boss room, the camp or a protection zone)')
        return res
    bad = {}            # tile -> why a plateau keeps off it

    def keep_off(cells, why, d):
        for t in cells:
            for dx in range(-d, d + 1):
                for dy in range(-d, d + 1):
                    bad.setdefault((t[0] + dx, t[1] + dy, t[2]), why)
    keep_off(avoid, 'a route, a building or a crossing', CLEAR)
    keep_off(special, 'a special tile', 2)
    keep_off(water, 'water', WATER_CLEAR)
    for k in range(sp['count']):
        zid = pick[k % len(pick)]
        rng = random.Random(seed * 389 + k * 7919 + 11)
        height = rng.randint(*sp['height'])
        lo, hi = sp['size']
        w = rng.randint(lo, hi)
        h = rng.randint(max(lo, w - 3), min(hi, w + 3))
        floor_ = max(lo - 2, 5 if height == 1 else MIN_TWO)
        rec = None
        tries, why = [], {}
        while rec is None and min(w, h) >= floor_:
            for _shape_try in range(SHAPES):
                G = shape(random.Random(rng.random()), w, h, 1 if height == 2 else None)
                G2 = None
                if height == 2:
                    G2 = erode(G, LEDGE)
                    G2 = max(_groups(G2), key=len) if G2 else set()
                    if len(erode(G2, 2)) < MIN_TOP:     # the upper tier: its lip, its cliff foot and room on top
                        why['no room for the upper tier'] = why.get('no room for the upper tier', 0) + 1
                        continue
                rec = _site(k, zid, height, G, G2, zrect[zid], walk, tiles, bad, arrival, bd, sp, rng,
                            res, reach_fn, link_edges, stairs_up, stairs_ground, why)
                if rec is not None:
                    break
            tries.append('%dx%d' % (w, h))
            if w >= h and w - 2 >= floor_:      # the longer side first, then both
                w -= 2
            elif h - 2 >= floor_:
                h -= 2
            else:
                w, h = w - 2, h - 2
        if rec is None:
            E('plateau %d (height %d) in zone %s: no room for it (tried %s); make the zone bigger, the plateau smaller or '
              'keep the routes and buildings off its middle; places refused: %s' % (k + 1, height, zid, ', '.join(tries),
                                                                  ', '.join('%s %d' % kv for kv in sorted(why.items(), key=lambda kv: -kv[1]))))
            continue
        res['records'].append(rec)
        for c in rec['clear']:
            bad.setdefault(c, 'plateau %s' % rec['id'])
    res['ids'] |= {cground, stairs_up, stairs_ground} | set(names.values()) | bd['used']
    res['grounds'] |= {cground, stairs_ground}
    res['cliff'] = dict(family=cfam, ground=cground)
    return res


def _groups(cells):
    cells, out = set(cells), []
    while cells:
        s = cells.pop()
        g, st = {s}, [s]
        while st:
            x, y = st.pop()
            for dx, dy in D8:
                n = (x + dx, y + dy)
                if n in cells:
                    cells.discard(n)
                    g.add(n)
                    st.append(n)
        out.append(g)
    return out


def _choose_ramps(spots, want, landing_ok, arrival):
    """greedy: the spots nearest the arrival first, SPACING columns apart"""
    spots = [s for s in spots if landing_ok(s)]
    spots.sort(key=lambda s: ((s[0] - arrival[0]) ** 2 + (s[1] - arrival[1]) ** 2, s[1], s[0]))
    out = []
    for s in spots:
        if all(abs(s[0] - o[0]) >= SPACING or abs(s[1] - o[1]) >= 3 for o in out):
            out.append(s)
        if len(out) >= want:
            break
    return out


def _site(k, zid, height, Gl, G2l, zr, walk, tiles, bad, arrival, bd, sp, rng, res, reach_fn, link_edges,
          stairs_up, stairs_ground, why):
    x1, y1, x2, y2, z = zr
    gw = max(x for x, _y in Gl) + 1
    gh = max(y for _x, y in Gl) + 1
    cx, cy = (x1 + x2) / 2.0, (y1 + y2) / 2.0
    pos = [(bx, by) for by in range(y1 - 2, y2 + 3 - gh + 1) for bx in range(x1 - 2, x2 + 3 - gw + 1)]
    jit = {p: rng.random() for p in pos}
    pos.sort(key=lambda p: ((p[0] + gw / 2.0 - cx) ** 2 + (p[1] + gh / 2.0 - cy) ** 2 + jit[p], p[1], p[0]))
    want = rng.randint(*sp['ramps'])
    ring1l, ring2l = ring(Gl, 1), ring(Gl, 2)
    reach0 = None
    for bx, by in pos:
        A = lambda c, zz=z: (bx + c[0], by + c[1], zz)
        G = {(bx + x, by + y) for x, y in Gl}
        cells = [A(c) for c in Gl] + [A(c) for c in ring1l]
        if any(c not in tiles for c in cells):
            why['off the built tiles'] = why.get('off the built tiles', 0) + 1
            continue
        fams = {bd['fam_of'].get(tiles[c]['ground']) for c in cells}
        if None in fams or any(not bd['fwalk'].get(f, True) or f.startswith('water') for f in fams):
            why['rock, water or a ground of no family'] = why.get('rock, water or a ground of no family', 0) + 1
            continue
        if any(A(c) in bad for c in ring2l) or any(A(c) in bad for c in Gl):
            why['near a route, building, water or plateau'] = why.get('near a route, building, water or plateau', 0) + 1
            continue
        if any(max(abs(c[0] - arrival[0]), abs(c[1] - arrival[1])) < ARRIVAL_CLEAR and c[2] == arrival[2] for c in cells):
            why['near the arrival'] = why.get('near the arrival', 0) + 1
            continue
        if any((bx + x, by + y, z - 1) in tiles for x, y in Gl):
            why['floor above taken'] = why.get('floor above taken', 0) + 1
            continue
        G2 = {(bx + x, by + y) for x, y in G2l} if G2l else None
        if G2 is not None and any((x, y, z - 2) in tiles for x, y in G2):
            why['no room for the upper tier'] = why.get('no room for the upper tier', 0) + 1
            continue
        # ramps of the lower tier: their landing (two tiles south) walkable on the base floor and off the bad tiles
        ok1 = lambda s: all((s[0], s[1] + d, z) in walk and (s[0], s[1] + d, z) not in bad for d in (1, 2, 3))
        r1 = _choose_ramps(ramp_spots(G), want, ok1, arrival)
        if len(r1) < sp['ramps'][0]:
            why['no clear south edge for a ramp'] = why.get('no clear south edge for a ramp', 0) + 1
            continue
        r2 = ()
        if G2 is not None:
            band = (G - rim(G)) - set(G2)
            ok2 = lambda s: all((s[0], s[1] + d) in band for d in (1, 2))
            r2 = _choose_ramps(ramp_spots(G2), want, ok2, arrival)
            if len(r2) < sp['ramps'][0]:
                why['no ramp to the upper tier'] = why.get('no ramp to the upper tier', 0) + 1
                continue
        lv = levels_of(G, r1, G2, r2)
        st = _stamp_sets(lv, G, z, walk, tiles, bd)
        if st is None:
            why['a ramp tile not walkable'] = why.get('a ramp tile not walkable', 0) + 1
            continue
        new_walk, edges, check, _plan = st
        if any(sum(1 for t in check if t[2] == z - L) < MIN_TOP for L in lv if L):
            why['too little room on top'] = why.get('too little room on top', 0) + 1
            continue
        if reach0 is None:
            reach0 = set(reach_fn(walk, link_edges + res['edges']))
        dist = reach_fn(new_walk, link_edges + res['edges'] + edges)
        foot0 = {A(c) for c in Gl} | {A(c) for c in ring1l}
        lost = [t for t in reach0 if t in new_walk and t not in dist]
        if lost or any(t not in dist for t in check):
            why['cuts the way'] = why.get('cuts the way', 0) + 1
            continue
        return _commit(k, zid, height, lv, G, G2, r1, r2, z, st, walk, tiles, bd, stairs_up, stairs_ground, res,
                       foot0, {A(c) for c in ring2l} | foot0)
    return None


def _stamp_sets(lv, G, z, walk, tiles, bd):
    """the tiles of the plateau, the walkable tiles after it and the tiles that must be reached; None when a ramp's
    tiles do not come out walkable or a border set is missing"""
    new_walk = set(walk)
    plan = {}       # (x, y, z) -> dict(ground, items, walk[, stairs])
    edges, check = [], []
    fam_of, cfam, cground = bd['fam_of'], bd['cfam'], bd['cground']
    for L, d in sorted(lv.items()):
        zz = z - L
        solid = d['solid']
        area = (set(G) | ring(G, 1)) if L == 0 else d['built']
        stairs = d['stairs_top'] | d['stairs_low']

        def fam_at(c, L=L, zz=zz, solid=solid, area=area, stairs=stairs):
            if c in solid:
                return cfam
            if L == 0:
                t = tiles.get((c[0], c[1], zz))
                return fam_of.get(t['ground']) if t else None
            if c not in area or c in d['stairs_top']:
                return None
            return fam_of.get(tiles[(c[0], c[1], z)]['ground'])
        for c in sorted(area):
            t = (c[0], c[1], zz)
            ground = tiles[(c[0], c[1], z)]['ground']
            if c in solid:
                plan[t] = dict(ground=cground, items=[], walk=False)
                continue
            if c in d['stairs_top']:
                plan[t] = dict(ground=None, items=[], walk=True, stairs='top')
                continue
            if c in d['stairs_low']:
                plan[t] = dict(ground=ground, items=[], walk=True, stairs='low')
                continue
            got = pieces_for(c, fam_at, bd)
            if got is None:
                return None
            pcs, cliff = got
            base_walk = (t in walk) if L == 0 else True
            plan[t] = dict(ground=ground, items=pcs, walk=base_walk and not cliff)
    for t, p in plan.items():
        if p['walk']:
            new_walk.add(t)
        else:
            new_walk.discard(t)
    for L, d in lv.items():
        zz = z - L
        for x, y in d['stairs_top']:
            low, top = (x, y, zz + 1), (x, y, zz)
            up, down = (x, y - 1, zz), (x, y + 1, zz + 1)
            for need in (low, top, up, down, (x, y + 2, zz + 1)):
                if need not in new_walk:
                    return None
            edges += [(low, up), (top, down)]
    for t, p in plan.items():
        if t[2] < z and p['walk']:
            check.append(t)
    return new_walk, edges, check, plan


def _commit(k, zid, height, lv, G, G2, r1, r2, z, st, walk, tiles, bd, stairs_up, stairs_ground, res, foot0,
            clear):
    new_walk, edges, check, plan = st
    pid = 'p%d' % (k + 1)
    for t, p in sorted(plan.items()):
        if p.get('stairs') == 'top':
            tiles[t] = dict(ground=stairs_ground, items=[], flags=0)
        elif p.get('stairs') == 'low':
            tiles[t] = dict(ground=p['ground'], items=[(stairs_up, {})], flags=0)
        elif t[2] == z:     # the border pieces again; a tile that stays walkable keeps its own decoration
            keep = [it for it in tiles[t]['items'] if it[0] not in bd['border_ids']] if p['walk'] else []
            tiles[t] = dict(ground=p['ground'], items=[(i, {}) for i in p['items']] + keep, flags=tiles[t]['flags'])
        else:
            tiles[t] = dict(ground=p['ground'], items=[(i, {}) for i in p['items']], flags=0)
    for p in plan.values():
        bd['used'].update(p['items'])
    res['foot'] |= foot0 & walk     # the outline keeps the tiles that were walkable before the cliff took them
    walk.clear()
    walk.update(new_walk)
    res['edges'] += edges
    ramps = []
    for L, d in sorted(lv.items()):
        zz = z - L
        for x, y in sorted(d['stairs_top']):
            r = dict(level=L, low=(x, y, zz + 1), top=(x, y, zz), up=(x, y - 1, zz), down=(x, y + 1, zz + 1),
                     landing=(x, y + 2, zz + 1))
            ramps.append(r)
            res['special'].update((r['low'], r['top'], r['up'], r['down'], r['landing']))
            res['skip_border'].add(r['low'])
            res['open_ok'].add(r['top'])
    above = {t for t in plan if t[2] < z}
    res['extra'] |= above
    res['prot'] |= set(plan) - set(check)
    top_walk = sorted(t for t in check)
    res['top'].setdefault(zid, []).extend(top_walk)
    levels = []
    for L, d in sorted(lv.items()):
        if L == 0:
            continue
        zz = z - L
        levels.append(dict(level=L, z=zz, built=sorted((x, y, zz) for x, y in d['built']),
                           solid=sorted((x, y, zz) for x, y in d['solid']),
                           walk=sorted(t for t in top_walk if t[2] == zz)))
    xs = [x for x, _y in G]
    ys = [y for _x, y in G]
    rec = dict(id=pid, zone=zid, height=height, z=z, rect=(min(xs), min(ys), max(xs), max(ys)), foot=sorted(G),
               upper=sorted(G2) if G2 else None, levels=levels, ramps=ramps, clear=clear,
               base=dict(solid=sorted((x, y, z) for x, y in lv[0]['solid']),
                         feet=sorted(t for t in plan if t[2] == z and plan[t]['items'])))
    return rec


# ------------------------------------------------------------------------------------------------ QA
def qa(records, tiles, walk, dist, avoid_sets, E, Wn, info, stairs_up, stairs_ground, cliff_ground):
    """QA of the plateaus on the final tiles. avoid_sets: {what: tiles} a plateau and its cliff foot keep off (water,
    crossings, buildings). info(text) adds an INFO line"""
    owner = {}
    for rec in records:
        label = 'plateau %s (zone %s, height %d)' % (rec['id'], rec['zone'], rec['height'])
        foot = set((x, y, rec['z']) for x, y in rec['foot'])
        for what, cells in avoid_sets.items():
            hit = sorted(t for t in rec['clear'] if t in cells)
            if hit:
                E('%s: its cliff lies on or next to %s at %s' % (label, what, hit[0]))
        for t in rec['clear']:
            if t in owner and owner[t] != rec['id'] and t in foot:
                E('%s overlaps plateau %s at %s' % (label, owner[t], t))
                break
        for t in rec['clear']:
            owner.setdefault(t, rec['id'])
        for t in rec['base']['solid']:
            if tiles.get(t, {}).get('ground') != cliff_ground or t in walk:
                E('%s: the cliff face at %s is not the cliff ground' % (label, t))
                break
        for lv in rec['levels']:
            built = set(lv['built'])
            z = lv['z']
            for t in sorted(built):
                if t not in tiles:
                    E('%s: floor z %d misses its tile %s' % (label, z, t))
                    break
                edge = any((t[0] + dx, t[1] + dy, z) not in tiles for dx, dy in D8)
                if edge and t in walk and tiles[t]['ground'] != stairs_ground:
                    E('%s: the cliff ring of z %d is open at %s' % (label, z, t))
            out = [t for t in lv['walk'] if t in walk and t not in dist]
            if out:
                E('%s: %d tile(s) on top (z %d) cannot be reached (first %s)' % (label, len(out), z, out[0]))
            if len([t for t in lv['walk'] if t in walk]) < MIN_TOP:
                E('%s: only %d walkable tile(s) on top at z %d' % (label, len(lv['walk']), z))
        for r in rec['ramps']:
            low, top = tiles.get(r['low']), tiles.get(r['top'])
            if not low or [i for i, _a in low['items']] != [stairs_up]:
                E('%s: the ramp at %s holds %s, not the stone stairs alone' % (label, r['low'], low and [i for i, _a in low['items']]))
            if not top or top['ground'] != stairs_ground or top['items']:
                E('%s: the ramp top at %s is not the bare stairs ground' % (label, r['top']))
            for what, t in (('the tile north of the ramp top', r['up']), ('the tile south of the ramp', r['down']),
                            ('the ramp\'s landing', r['landing'])):
                if t not in walk:
                    E('%s: the ramp at %s runs into a wall: %s %s is not walkable' % (label, r['low'], what, t))
                elif t not in dist:
                    E('%s: %s %s cannot be reached' % (label, what, t))
            if r['low'] not in dist:
                E('%s: the ramp at %s cannot be reached' % (label, r['low']))
            info('ramp: plateau %s at %d,%d,%d up to z %d' % (rec['id'], r['low'][0], r['low'][1], r['low'][2], r['top'][2]))


def manifest_of(rec, dist):
    steps = [dist[t] for lv in rec['levels'] for t in lv['walk'] if t in dist]
    return dict(id=rec['id'], zone=rec['zone'], height=rec['height'], z=rec['z'], rect=list(rec['rect']),
                footprint=len(rec['foot']), top=[dict(z=lv['z'], tiles=len(lv['built']), walkable=len(lv['walk']))
                                                 for lv in rec['levels']],
                ramps=[dict(low=list(r['low']), top=list(r['top'])) for r in rec['ramps']],
                entry_to_top=min(steps) if steps else None)
