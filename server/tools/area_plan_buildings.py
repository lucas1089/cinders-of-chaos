#!/usr/bin/env python3
"""Parametric buildings of the area planner (O515): temple, depot, shop and house, with the door on a chosen side.

A plan lists `buildings` (areaplan/schema.json): a kind, a zone, a position or "auto inside the zone", a door side
(n, e, s, w or "route": the side that faces the nearest route), an optional size and an optional NPC. The prefab of the
kind (areaplan/prefabs/<kind>.json) names width and height ranges, a wall family, a floor family, a roof, features
(altar, pillar_pair, bench_row, counter, shelf_row) and decor slots. It never names an item id: families resolve through
  * areagen_config.lua and tools/areaplan_build.lua `materials`: wall brushes, ground families, the door pair;
  * areaplan/decor_kits.json: kit groups (altar, pillar, brazier, torch, banner, ...);
  * areaplan/building_families.json: a few stock ids (counter, bench, shelf, locker, table, chair).

Frame of a prefab ("canonical", the door in the south wall): `width` runs across the door wall, `height` from the north
(back) wall to the door wall; dx counts interior columns from the west, dy interior rows from the north; a negative
number counts from the far end, "c" is the door column. layout() turns the whole building with the door side: a door
on the east wall swaps width and height on the map.

Pure parts (layout, family resolution, site search, QA of the stamped tiles) are tested without the generator in
area_plan_buildings_test.py; area_plan_compile.py calls place_all() after the generator ran and qa_all() on the final
tiles. Python 3 standard library only.
"""
import json, math, os, random

import area_plan_core as C
import map_tile_rules as MR

PREFAB_DIR = os.path.join(C.PLANDIR, 'prefabs')
FAMILIES_PATH = os.path.join(C.PLANDIR, 'building_families.json')
KINDS = ('temple', 'depot', 'shop', 'house')
SIDES = {'n': (0, -1), 'e': (1, 0), 's': (0, 1), 'w': (-1, 0)}
DIR_OF = {v: k for k, v in SIDES.items()}
FEATURES = ('altar', 'pillar_pair', 'bench_row', 'counter', 'shelf_row')
ROLES = ('floor', 'hang')
HANG_WALLS = ('back', 'front', 'left', 'right')
GAP = 2                     # free tiles kept between two buildings
SIZE_LIMITS = (5, 21)
_cache = {}


class BuildingError(Exception):
    pass


# ================================================================================================= tables
def prefab(kind):
    if kind not in _cache:
        with open(os.path.join(PREFAB_DIR, kind + '.json'), encoding='utf-8') as f:
            _cache[kind] = json.load(f)
    return _cache[kind]


def families():
    if 'fam' not in _cache:
        with open(FAMILIES_PATH, encoding='utf-8') as f:
            _cache['fam'] = json.load(f)['families']
    return _cache['fam']


def prefab_problems(pf, mats=None, fams=None, kit_groups=None):
    """[message] for a prefab: keys, ranges, feature and slot fields, families (and the material names when given)"""
    out = []
    fams = fams if fams is not None else families()
    kind = pf.get('kind')
    for k in ('kind', 'width', 'height', 'door_side', 'door_width', 'wall', 'floor', 'roof', 'pz'):
        if k not in pf:
            out.append('%s: missing "%s"' % (kind, k))
    for k in ('width', 'height'):
        r = pf.get(k)
        if not (isinstance(r, list) and len(r) == 2 and all(isinstance(v, int) for v in r) and SIZE_LIMITS[0] <= r[0] <= r[1] <= SIZE_LIMITS[1]):
            out.append('%s: %s must be [lo, hi] inside %d-%d' % (kind, k, SIZE_LIMITS[0], SIZE_LIMITS[1]))
    if pf.get('door_side') not in ('route', 'n', 'e', 's', 'w'):
        out.append('%s: door_side %r' % (kind, pf.get('door_side')))
    if pf.get('door_width') not in (1, 2):
        out.append('%s: door_width must be 1 or 2' % kind)

    def coordinate_ok(v):
        return v == 'c' or (isinstance(v, int) and not isinstance(v, bool))
    for k in ('features', 'slots'):
        for i, e in enumerate(pf.get(k, [])):
            p = '%s.%s[%d]' % (kind, k, i)
            if e.get('family') not in fams:
                out.append('%s: no family %r in building_families.json' % (p, e.get('family')))
            else:
                f = fams[e['family']]
                for g in (f.get('group'), f.get('group_h'), f.get('group_v')):
                    if g and kit_groups is not None and g not in kit_groups:
                        out.append('%s: family %s names the kit group %s, which the decoration kits lack' % (p, e['family'], g))
                if k == 'slots' and bool(f.get('hang')) != (e.get('role') == 'hang'):
                    out.append('%s: family %s and role %s do not go together' % (p, e['family'], e.get('role')))
            if k == 'features':
                if e.get('type') not in FEATURES:
                    out.append('%s: unknown feature type %r' % (p, e.get('type')))
                if not coordinate_ok(e.get('dy')):
                    out.append('%s: dy must be an integer or "c"' % p)
                if e.get('type') in ('altar', 'pillar_pair') and not coordinate_ok(e.get('dx')):
                    out.append('%s: dx must be an integer or "c"' % p)
            else:
                if e.get('role') not in ROLES:
                    out.append('%s: role %r' % (p, e.get('role')))
                if e.get('role') == 'hang' and e.get('wall') not in HANG_WALLS:
                    out.append('%s: a hang slot needs wall back, front, left or right' % p)
                for a in ('dx', 'dy'):
                    if not coordinate_ok(e.get(a)):
                        out.append('%s: %s must be an integer or "c"' % (p, a))
    if mats is not None:
        if pf.get('wall') not in mats['walls']:
            out.append('%s: no wall family %r' % (kind, pf.get('wall')))
        if pf.get('floor') not in mats['families']:
            out.append('%s: no floor family %r' % (kind, pf.get('floor')))
    npc = pf.get('npc')
    if npc and not all(a in npc for a in ('dx', 'dy', 'role')):
        out.append('%s: npc needs dx, dy and role' % kind)
    return out


# ================================================================================================= layout
def frame(side):
    """(d, r): where the canonical south (the door) and east (the right hand) point on the map for a door side"""
    d = SIDES[side]
    return d, (d[1], -d[0])


def coord(v, n, what='coordinate'):
    """an interior coordinate: 'c' = the door column, an integer from the west / north, a negative one from the far end"""
    if v == 'c':
        return (n - 1) // 2
    if isinstance(v, bool) or not isinstance(v, int):
        raise BuildingError('%s %r is not an integer or "c"' % (what, v))
    k = v if v >= 0 else n + v
    if not 0 <= k < n:
        raise BuildingError('%s %d is outside the interior (%d wide)' % (what, v, n))
    return k


def size_range(pf):
    return tuple(pf['width']), tuple(pf['height'])


def layout(pf, w, h, side, extra_slots=(), door_width=None):
    """the building as relative tiles (top-left of its footprint on the map is (0, 0)) for a canonical footprint w x h
    (width across the door wall, height from the back wall to the door wall) with the door on `side`. Pure.
    -> dict(W, H, iw, ih, side, door, outside, inside, walls {tile: piece type}, floor {tile}, items [dict], reach,
    npc, conflicts, dropped); items: tile, family, role, facing, axis, wall_dir, kind ('feature' or 'slot'), what"""
    iw, ih = w - 2, h - 2
    dw = door_width or pf.get('door_width', 1)
    if iw < dw + 2 or ih < 2:
        raise BuildingError('a %d x %d footprint is too small for a door of %d' % (w, h, dw))
    d, r = frame(side)

    def tr(fx, fy):
        return fx * r[0] + fy * d[0], fx * r[1] + fy * d[1]
    corners = [tr(0, 0), tr(w - 1, 0), tr(0, h - 1), tr(w - 1, h - 1)]
    mx, my = min(c[0] for c in corners), min(c[1] for c in corners)
    W, H = max(c[0] for c in corners) - mx + 1, max(c[1] for c in corners) - my + 1

    def rel(fx, fy):
        x, y = tr(fx, fy)
        return x - mx, y - my

    def fp(cx, cy):          # interior (canonical) -> footprint (canonical)
        return cx + 1, cy + 1
    c0 = (iw - 1) // 2
    door_cols = list(range(c0 + 1, c0 + 1 + dw))
    wallset, doors = set(), []
    for fx in range(w):
        for fy in range(h):
            if fx in (0, w - 1) or fy in (0, h - 1):
                if fy == h - 1 and fx in door_cols:
                    doors.append(rel(fx, fy))
                wallset.add(rel(fx, fy))
    walls = {}
    for t in wallset:
        n_, e_, s_, w_ = ((t[0] + dx, t[1] + dy) in wallset for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0)))
        walls[t] = MR.wall_piece(n_, e_, s_, w_)
    floor = {rel(*fp(cx, cy)) for cx in range(iw) for cy in range(ih)}
    outside = [(t[0] + d[0], t[1] + d[1]) for t in doors]
    inside = [(t[0] - d[0], t[1] - d[1]) for t in doors]
    out = dict(W=W, H=H, iw=iw, ih=ih, side=side, dw=dw, c0=c0, door=doors, outside=outside, inside=inside, walls=walls,
               floor=floor, items=[], reach=[], npc=None, conflicts=[], dropped=[])
    claimed = {}

    def facing_of(vec):
        return DIR_OF[vec]

    def add(tile, fam, role, kind, what, facing=None, axis=None, wall_dir=None, block=None):
        if role == 'floor':
            if tile in claimed:
                out['conflicts'].append('%s at %s overlaps %s' % (what, tile, claimed[tile]))
                return False
            claimed[tile] = what
        out['items'].append(dict(tile=tile, family=fam, role=role, kind=kind, what=what, facing=facing, axis=axis,
                                 wall_dir=wall_dir))
        return True

    def real_facing(canon):
        """a canonical facing (n e s w, door side = s) on the map"""
        cv = {'s': (0, 1), 'n': (0, -1), 'e': (1, 0), 'w': (-1, 0)}[canon]
        # canonical down (0, 1) -> d, canonical right (1, 0) -> r
        v = (cv[0] * r[0] + cv[1] * d[0], cv[0] * r[1] + cv[1] * d[1])
        return facing_of(v)
    axis_x = 'h' if r[0] != 0 else 'v'          # a canonical row (along x) runs along x on the map when r is horizontal
    for i, f in enumerate(pf.get('features', [])):
        if iw < f.get('min_iw', 0) or ih < f.get('min_ih', 0):
            continue
        t = f['type']
        what = '%s %d' % (t, i)
        if t in ('altar', 'pillar_pair'):
            cx, cy = coord(f['dx'], iw, what + ' dx'), coord(f['dy'], ih, what + ' dy')
            cells = [(cx, cy)] + ([(iw - 1 - cx, cy)] if t == 'pillar_pair' and iw - 1 - cx != cx else [])
            for cx_, cy_ in cells:
                if add(rel(*fp(cx_, cy_)), f['family'], 'floor', 'feature', what, facing=real_facing('s')) and f.get('reach'):
                    if cy_ + 1 < ih:
                        out['reach'].append(rel(*fp(cx_, cy_ + 1)))
        elif t == 'bench_row':
            cy = coord(f['dy'], ih, what + ' dy')
            cols = list(range(1, c0)) + list(range(c0 + dw, iw - 1))
            for cx in cols:
                add(rel(*fp(cx, cy)), f['family'], 'floor', 'feature', what, facing=real_facing('n'))
        elif t in ('counter', 'shelf_row'):
            cx0, cy = coord(f.get('dx', 0), iw, what + ' dx'), coord(f['dy'], ih, what + ' dy')
            n = f.get('length', 'full')
            n = iw - cx0 if n == 'full' else int(n)
            cols = list(range(cx0, min(iw, cx0 + n)))
            if t == 'counter':
                if f.get('gap') == 'start' and cols:
                    cols = cols[1:]
                elif f.get('gap') == 'end' and cols:
                    cols = cols[:-1]
            for cx in cols:
                if add(rel(*fp(cx, cy)), f['family'], 'floor', 'feature', what, facing=real_facing('s'), axis=axis_x) \
                        and f.get('reach') and cy + 1 < ih:
                    out['reach'].append(rel(*fp(cx, cy + 1)))
    for i, s in enumerate(list(pf.get('slots', [])) + list(extra_slots)):
        if iw < s.get('min_iw', 0) or ih < s.get('min_ih', 0):
            continue
        what = 'slot %d' % i
        cx, cy = coord(s['dx'], iw, what + ' dx'), coord(s['dy'], ih, what + ' dy')
        if s['role'] == 'floor':
            canon = s.get('facing', 's')
            add(rel(*fp(cx, cy)), s['family'], 'floor', 'slot', what, facing=real_facing(canon))
        else:
            wall = s['wall']
            fx, fy = fp(cx, cy)
            tfx, tfy = {'back': (fx, 0), 'front': (fx, h - 1), 'left': (0, fy), 'right': (w - 1, fy)}[wall]
            cvec = {'back': (0, -1), 'front': (0, 1), 'left': (-1, 0), 'right': (1, 0)}[wall]
            mv = (cvec[0] * r[0] + cvec[1] * d[0], cvec[0] * r[1] + cvec[1] * d[1])      # the wall's side on the map
            if mv in ((0, -1), (-1, 0)):
                out['items'].append(dict(tile=rel(tfx, tfy), family=s['family'], role='hang', kind='slot', what=what,
                                         facing=None, axis=None, wall_dir=facing_of(mv)))
            else:
                out['dropped'].append('%s: hung pieces only draw on north and west walls' % what)
    npc = pf.get('npc')
    if npc:
        cx, cy = coord(npc['dx'], iw, 'npc dx'), coord(npc['dy'], ih, 'npc dy')
        t = rel(*fp(cx, cy))
        if t in claimed:
            out['conflicts'].append('the npc at %s overlaps %s' % (t, claimed[t]))
        out['npc'] = t
        out['npc_role'] = npc.get('role')
    return out


# ================================================================================================= materials
def resolve_item(f, fam, kit, rng, look, facing=None, axis=None, wall_dir=None):
    """(item id, blocks) of one placement of a family (a kit group, `dirs`, `h`/`v` or `ids`)"""
    spec = fam[f]
    if spec.get('hang'):
        g = kit['groups'][spec['group_h'] if wall_dir == 'n' else spec['group_v']]
        k = look.setdefault(f, rng.randrange(len(g['ids'])))
        return g['ids'][k % len(g['ids'])], False
    if 'group' in spec:
        g = kit['groups'][spec['group']]
        k = look.setdefault(f, rng.randrange(len(g['ids'])))
        return g['ids'][k % len(g['ids'])], bool(g['block'])
    if 'dirs' in spec:
        return spec['dirs'][facing or 's'], bool(spec.get('block'))
    if 'h' in spec:
        return spec[axis][0], bool(spec.get('block'))
    return spec['ids'][0], bool(spec.get('block'))


def wall_ids_of(brush):
    return {i for ids in brush.values() for i in ids}


# ================================================================================================= placing
def _rect_tiles(bx, by, W, H):
    return [(bx + x, by + y) for x in range(W) for y in range(H)]


def ring_target(rect, k, n):
    """the k-th of n points on an ellipse inside a zone rectangle (x1, y1, x2, y2), clockwise from the north: the
    centres the `auto` buildings of one zone aim at, so they stand round the zone's middle"""
    x1, y1, x2, y2 = rect
    cx, cy = (x1 + x2) / 2.0, (y1 + y2) / 2.0
    ax, ay = (x2 - x1 + 1) * 0.32, (y2 - y1 + 1) * 0.32
    a = -math.pi / 2 + 2 * math.pi * k / max(1, n)
    return cx + ax * math.cos(a), cy + ay * math.sin(a)


def site_ok(bx, by, lay, z, buildable, walk, zone_rect, blocked, reach0):
    """can the footprint go at (bx, by) (its top-left tile)? -> None, or the reason it cannot. buildable(tile): a built
    tile with ground that may carry a floor (walkable, or blocked only by a tree or a stone, which the stamp removes)"""
    x1, y1, x2, y2 = zone_rect
    for t in _rect_tiles(bx, by, lay['W'], lay['H']):
        if not (x1 <= t[0] <= x2 and y1 <= t[1] <= y2):
            return 'leaves its zone'
        if (t[0], t[1], z) in blocked:
            return 'overlaps %s' % blocked[(t[0], t[1], z)]
        if not buildable((t[0], t[1], z)):
            return 'stands on %s, which is no ground a floor can lie on (rock, water or the rim)' % ((t[0], t[1], z),)
    for t in _rect_tiles(bx - 1, by - 1, lay['W'] + 2, lay['H'] + 2):      # the ring round it: no wall against the rim
        if not (bx <= t[0] < bx + lay['W'] and by <= t[1] < by + lay['H']) and not buildable((t[0], t[1], z)):
            return 'stands against rock, water or the rim at %s' % ((t[0], t[1], z),)
    for o in lay['outside']:
        a = (bx + o[0], by + o[1], z)
        if a not in walk:
            return 'the tile outside the door %s is not walkable' % (a,)
        if reach0 is not None and a not in reach0:
            return 'the tile outside the door %s is cut off from the entry' % (a,)
    return None


def cut_off(bx, by, lay, z, walk, reach0, reach_fn):
    """the number of tiles that the footprint would cut off from the entry (the tiles reached now that stay out of reach
    once its walls and the tiles under it are gone; the interior counts as reached through the door)"""
    foot = {(t[0], t[1], z) for t in _rect_tiles(bx, by, lay['W'], lay['H'])}
    inner = {(bx + t[0], by + t[1], z) for t in lay['floor']} | {(bx + t[0], by + t[1], z) for t in lay['door']}
    after = reach_fn((walk - foot) | inner)
    return sum(1 for t in reach0 if t not in foot and t not in after)


def route_cost(lay, bx, by, route_pts):
    """squared distance of the tile outside the door to the nearest route point"""
    o = lay['outside'][0]
    ox_, oy_ = bx + o[0], by + o[1]
    return min((ox_ - p[0]) ** 2 + (oy_ - p[1]) ** 2 for p in route_pts)


def find_site(lays, sides, z, buildable, walk, zone_rect, blocked, reach0, target, route_pts, reach_fn):
    """(side, bx, by) of the best valid site, or None. For every side the footprint whose centre is nearest `target`
    (ties: top row, west column) that fits and cuts nothing off; of those the side whose door faces the nearest route
    point (ties: n, e, s, w). Deterministic."""
    x1, y1, x2, y2 = zone_rect
    found = []
    for side in sides:
        lay = lays[side]
        cands = []
        for by in range(y1, y2 - lay['H'] + 2):
            for bx in range(x1, x2 - lay['W'] + 2):
                cx, cy = bx + (lay['W'] - 1) / 2.0, by + (lay['H'] - 1) / 2.0
                cands.append((round((cx - target[0]) ** 2 + (cy - target[1]) ** 2, 6), by, bx))
        cands.sort()
        for _d, by, bx in cands:
            if site_ok(bx, by, lay, z, buildable, walk, zone_rect, blocked, reach0) is None \
                    and cut_off(bx, by, lay, z, walk, reach0, reach_fn) == 0:
                found.append((round(route_cost(lay, bx, by, route_pts), 3) if len(sides) > 1 else 0,
                              'nesw'.index(side), side, bx, by))
                break
    if not found:
        return None
    found.sort()
    return found[0][2:]


def place_all(plan, zrect, walk, tiles, special, corridor, arrival, origin, mats, kit, fams, seed, E, Wn, reach_fn):
    """place and stamp every building of the plan on the generated tiles (before the teleports, chests, NPCs and
    decoration). Changes tiles and walk. zrect: {zone: (x1, y1, x2, y2, z)} absolute; special: tiles to keep clear (the
    arrival, the holes and ladders); corridor: the tiles of the plan's paths; reach_fn(walk) -> the tiles reached from the
    entry. -> dict(records, prot, special, pz, wall_ids, floor_ids, door_ids, block_ids, item_ids, roof_ids, foot)"""
    ox, oy, _oz = origin
    res = dict(records=[], prot=set(), special=set(), pz=set(), wall_ids=set(), floor_ids=set(), door_ids=set(),
               block_ids=set(), item_ids=set(), roof_ids=set(), foot=set())
    walkable_grounds = {g for d in mats['families'].values() if d['walk'] for g in d['grounds']}
    buildable = lambda t: t in walk or (t in tiles and tiles[t]['ground'] in walkable_grounds)
    blocked = {t: 'a route' for t in corridor}
    for s in special:
        for dx in range(-1, 2):
            for dy in range(-1, 2):
                blocked[(s[0] + dx, s[1] + dy, s[2])] = 'a special tile (the arrival, a hole or a ladder)'
    autos = {}
    for i, b in enumerate(plan['buildings']):
        if 'at' not in b:
            autos.setdefault(b['zone'], []).append(i)
    ring = {i: (k, len(idx)) for idx in autos.values() for k, i in enumerate(idx)}
    for i, b in enumerate(plan['buildings']):
        bid = b['id']
        pf = prefab(b['kind'])
        zx1, zy1, zx2, zy2, zz = zrect[b['zone']]
        zone_rect = (zx1, zy1, zx2, zy2)
        rng = random.Random(seed * 211 + i * 17 + 3)
        (wlo, whi), (hlo, hhi) = size_range(pf)
        w, h = b['size'] if 'size' in b else (rng.randint(wlo, whi), rng.randint(hlo, hhi))
        try:
            lays = {s: layout(pf, w, h, s, b.get('slots', ())) for s in 'nesw'}
        except BuildingError as e:
            E('building %s: %s' % (bid, e))
            continue
        if lays['s']['conflicts']:
            E('building %s: %s' % (bid, '; '.join(lays['s']['conflicts'])))
            continue
        side_req = b.get('door') or pf['door_side']
        sides = tuple('nesw') if side_req == 'route' else (side_req,)
        reach0 = set(reach_fn(walk))
        route_pts = [(arrival[0], arrival[1]), ((zx1 + zx2) / 2.0, (zy1 + zy2) / 2.0)]
        route_pts += [(t[0], t[1]) for k, t in enumerate(sorted(corridor)) if t[2] == zz and k % 3 == 0][:300]
        if 'at' in b:
            bx, by = ox + b['at'][0], oy + b['at'][1]
            why = {s: site_ok(bx, by, lays[s], zz, buildable, walk, zone_rect, blocked, reach0) for s in sides}
            good = [s for s in sides if why[s] is None]
            if not good:
                E('building %s (%s) at %d,%d: it %s' % (bid, b['kind'], b['at'][0], b['at'][1], why[sides[0]]))
                continue
            good.sort(key=lambda s: (route_cost(lays[s], bx, by, route_pts) if len(good) > 1 else 0, 'nesw'.index(s)))
            site = (good[0], bx, by)
            n_cut = cut_off(bx, by, lays[site[0]], zz, walk, reach0, reach_fn)
            if n_cut:
                Wn('building %s cuts %d walkable tile(s) off the entry' % (bid, n_cut))
        else:
            k, n = ring[i]
            site = find_site(lays, sides, zz, buildable, walk, zone_rect, blocked, reach0, ring_target(zone_rect, k, n),
                             route_pts, reach_fn)
            if not site:
                E('building %s (%s, %d x %d): no place for it in zone %s; make the zone bigger or the building smaller'
                  % (bid, b['kind'], w, h, b['zone']))
                continue
        side, bx, by = site
        lay = lays[side]
        rec = stamp(b, pf, lay, bx, by, zz, tiles, walk, mats, kit, fams, rng, b.get('wall') or pf['wall'],
                    b.get('floor') or pf['floor'], res, E)
        for t in _rect_tiles(bx - GAP, by - GAP, lay['W'] + 2 * GAP, lay['H'] + 2 * GAP):
            blocked[(t[0], t[1], zz)] = 'building %s' % bid
        res['records'].append(rec)
    return res


def stamp(b, pf, lay, bx, by, z, tiles, walk, mats, kit, fams, rng, wall_name, floor_name, res, E):
    """write one building's tiles; -> its record"""
    brush = mats['walls'][wall_name]
    floors = mats['families'][floor_name]['grounds']
    door_pair = mats['doors'][pf.get('door_family', 'wood')]
    orient = 'h' if lay['side'] in ('n', 's') else 'v'
    door_closed = door_pair[orient]['closed']
    A = lambda t: (bx + t[0], by + t[1], z)
    look = {}
    rec = dict(id=b['id'], kind=b['kind'], zone=b['zone'], side=lay['side'], rect=(bx, by, bx + lay['W'] - 1, by + lay['H'] - 1, z),
               size=[lay['W'], lay['H']], wall=wall_name, floor=floor_name, door=[A(t) for t in lay['door']],
               outside=[A(t) for t in lay['outside']], inside=[A(t) for t in lay['inside']], reach=[A(t) for t in lay['reach']],
               interior=sorted(A(t) for t in lay['floor']), walls={}, features=[], hang=[], blocked=[], roof=[], npc=None,
               ids=set(), pz=bool(b.get('pz', pf.get('pz'))), dropped=list(lay['dropped']), prefab_roof=bool(b.get('roof', pf['roof'])),
               floor_ids=set(floors), wall_ids=wall_ids_of(brush), door_ids={door_closed}, block_ids=set())
    foot = [A(t) for t in list(lay['walls']) + list(lay['floor'])]
    rec['foot'] = foot
    for t in foot:
        tiles[t] = dict(ground=rng.choice(floors), items=[], flags=0)
    for t, kind in sorted(lay['walls'].items()):
        a = A(t)
        if t in lay['door']:
            tiles[a]['items'].append((door_closed, {}))
            walk.add(a)
            continue
        wid = rng.choice(brush[kind])
        tiles[a]['items'].append((wid, {}))
        walk.discard(a)
        rec['walls'][a] = kind
        rec['block_ids'].add(wid)
    for t in lay['floor']:
        walk.add(A(t))
    for it in lay['items']:
        a = A(it['tile'])
        iid, blk = resolve_item(it['family'], fams, kit, rng, look, it['facing'], it['axis'], it['wall_dir'])
        tiles[a]['items'].append((iid, {}))
        rec['ids'].add(iid)
        if it['role'] == 'hang':
            rec['hang'].append((a, iid))
            continue
        if blk:
            walk.discard(a)
            rec['blocked'].append(a)
            rec['block_ids'].add(iid)
        rec['features'].append(dict(what=it['what'], family=it['family'], at=a, id=iid, block=blk))
    if lay['npc']:
        rec['npc'] = A(lay['npc'])
    if rec['prefab_roof']:
        roof = kit['roof']['ground'][0]
        for t in foot:
            above = (t[0], t[1], t[2] - 1)
            if t[2] - 1 < 0:
                E('building %s: no floor above z %d for its roof' % (b['id'], t[2]))
                break
            if above in tiles:
                E('building %s: the roof tile %s is taken by another floor of the area' % (b['id'], above))
                break
            tiles[above] = dict(ground=roof, items=[], flags=0)
            rec['roof'].append(above)
        res['roof_ids'].add(roof)
    res['wall_ids'] |= rec['wall_ids']
    res['floor_ids'] |= rec['floor_ids']
    res['door_ids'] |= rec['door_ids']
    res['block_ids'] |= rec['block_ids']
    res['item_ids'] |= rec['ids']
    res['foot'].update(foot)
    res['prot'].update(foot)
    res['prot'].update(rec['outside'])
    res['special'].update(rec['outside'] + rec['reach'])
    if rec['npc']:
        res['special'].add(rec['npc'])
    if rec['pz']:
        for t in lay['floor']:
            res['pz'].add(A(t))
        for t in lay['door']:
            res['pz'].add(A(t))
    return rec


# ================================================================================================= QA
def qa_all(records, tiles, walk, dist, mats, E, Wn, roof_ground):
    """QA of the stamped buildings on the final tiles. dist: steps from the entry (area_plan_core.tile_reach)."""
    owner = {}
    for rec in records:
        bid = rec['id']
        label = 'building %s (%s)' % (bid, rec['kind'])
        for t in rec['foot']:
            if t in owner and owner[t] != bid:
                E('%s overlaps building %s at %s' % (label, owner[t], t))
                break
            owner[t] = bid
        brush = mats['walls'][rec['wall']]
        door_set = set(rec['door'])
        wall_set = set(rec['walls']) | door_set
        ids_of = {}
        for kind, ids in brush.items():
            for i in ids:
                ids_of.setdefault(i, set()).add(kind)
        for a, kind in sorted(rec['walls'].items()):
            n_, e_, s_, w_ = ((a[0] + dx, a[1] + dy, a[2]) in wall_set for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0)))
            want = MR.wall_piece(n_, e_, s_, w_)
            have = [i for i, _x in tiles[a]['items'] if i in ids_of]
            if not have:
                E('%s: the wall tile %s carries no wall piece' % (label, a))
            elif want not in ids_of[have[0]]:
                E('%s: the wall piece at %s is a %s piece where a %s piece belongs' % (label, a, '/'.join(sorted(ids_of[have[0]])), want))
        for a in rec['door']:
            ids = [i for i, _x in tiles[a]['items']]
            if a not in walk:
                E('%s: the door tile %s is not walkable' % (label, a))
            if any(i not in rec['door_ids'] for i in ids):
                E('%s: the door tile %s holds %s besides the door' % (label, a, [i for i in ids if i not in rec['door_ids']]))
            for _sid, blocker in MR.blocking_on_special(ids, rec['door_ids'], rec['block_ids'].__contains__, a in walk):
                E('%s: the door at %s %s' % (label, a, ('has the blocking item %d on its tile' % blocker) if blocker else 'is on a tile nobody can walk on'))
            if a not in dist:
                E('%s: the door at %s cannot be reached from the entry' % (label, a))
        for a in rec['outside']:
            if a not in walk:
                E('%s: the tile outside the door %s is not walkable' % (label, a))
            elif a not in dist:
                E('%s: the tile outside the door %s is cut off from the entry' % (label, a))
        for a in rec['inside']:
            if a not in dist:
                E('%s: the way in from the door is blocked at %s' % (label, a))
        for a in rec['reach']:
            if a not in dist:
                E('%s: the tile %s in front of a counter or an altar cannot be reached from the door' % (label, a))
        if rec['npc'] and rec['npc'] not in walk:
            E('%s: the npc stands on a tile that is blocked' % label)
        pockets = [a for a in rec['interior'] if a in walk and a not in dist]
        if pockets:
            Wn('%s: %d interior tile(s) cannot be reached (first %s)' % (label, len(pockets), pockets[0]))
        if rec['prefab_roof']:
            miss = [t for t in rec['foot'] if tiles.get((t[0], t[1], t[2] - 1), {}).get('ground') not in roof_ground]
            if miss:
                E('%s: the roof misses %d footprint tile(s) (first %s)' % (label, len(miss), miss[0]))
        elif rec['roof']:
            E('%s: a roof was laid but the prefab has none' % label)


def manifest_of(rec, dist=None):
    return dict(id=rec['id'], kind=rec['kind'], zone=rec['zone'], door_side=rec['side'], rect=list(rec['rect'][:4]), z=rec['rect'][4],
                size=rec['size'], wall=rec['wall'], floor=rec['floor'], door=[list(t) for t in rec['door']],
                outside=[list(t) for t in rec['outside']], route_steps=(dist.get(rec['outside'][0]) if dist else None),
                roof_tiles=len(rec['roof']), features=[dict(f, at=list(f['at'])) for f in rec['features']],
                hung=len(rec['hang']), dropped=rec['dropped'], pz=rec['pz'],
                npc=list(rec['npc']) if rec['npc'] else None)


# ================================================================================================= check on the live data
def stock_ids(mats, fams=None):
    """[(id, what, kind, blocks)] of every item id the buildings can write that is not a decor kit group: the stock ids of
    building_families.json, the wall brushes, the floor grounds and the doors (kind: item, wall, ground, door)"""
    fams = fams if fams is not None else families()
    out = []
    for name, f in sorted(fams.items()):
        ids = list(f.get('ids', [])) + list(f.get('dirs', {}).values()) + list(f.get('h', [])) + list(f.get('v', []))
        out += [(i, 'family %s' % name, 'item', bool(f.get('block'))) for i in ids]
    for kind in KINDS:
        pf = prefab(kind)
        for i in sorted(wall_ids_of(mats['walls'][pf['wall']])):
            out.append((i, 'wall %s (%s)' % (pf['wall'], kind), 'wall', True))
        for i in mats['families'][pf['floor']]['grounds']:
            out.append((i, 'floor %s (%s)' % (pf['floor'], kind), 'ground', False))
    for name, pair in sorted(mats['doors'].items()):
        for orient, ids in sorted(pair.items()):
            for state, i in sorted(ids.items()):
                out.append((i, 'door %s %s %s' % (name, orient, state), 'door', False))
    seen, uniq = set(), []
    for row in out:
        if (row[0], row[1]) not in seen:
            seen.add((row[0], row[1]))
            uniq.append(row)
    return uniq


def check_buildings(items_otb, items_xml, dat, log=print):
    """the stock ids of the buildings against the live items and the pair (area_planner.py check-kits): known, a sprite,
    blocking as listed, doors of the door group, walls and grounds of their kind, nothing pickupable. Prints the size of
    each door sprite and the pieces of each oriented family, for a look: the order of the four directions is not
    verified in git. -> True when nothing is wrong"""
    import re, sys
    sys.path.insert(0, os.path.join(C.ROOT, 'tools', 'map'))
    from itemdb import ItemDB
    db = ItemDB(items_otb, items_xml, dat)
    xml = open(items_xml, encoding='latin-1').read()
    things = db.dat.items
    mats = C.materials()
    bad = 0

    def is_door(i):
        if db.known[i] and int(db.group[i]) == 13:
            return True
        m = re.search(r'<item id="%d"[^>]*>(.*?)</item>' % i, xml, re.S)
        if m and 'value="door"' in m.group(1):
            return True
        return any(int(a) <= i <= int(b) and 'value="door"' in body
                   for a, b, body in re.findall(r'<item fromid="(\d+)" toid="(\d+)"[^>]*>(.*?)</item>', xml, re.S))
    rows = stock_ids(mats)
    for i, what, kind, block in rows:
        why = []
        c = int(db.cid[i]) if db.known[i] else 0
        if not c or c - 100 >= len(things):
            why.append('no client sprite')
        else:
            f = things[c - 100].flags
            blk = bool(int(db.flags[i]) & 1 or 'notwalkable' in f)
            if kind in ('item', 'wall') and blk != block:
                why.append('blocks' if blk else 'does not block')
            if kind == 'ground' and not (int(db.group[i]) == 1 or 'ground' in f):
                why.append('not a ground')
            if kind == 'door' and not is_door(i):
                why.append('not a door (items.otb group 13, items.xml type door)')
            if 'pickupable' in f:
                why.append('pickupable')
            if kind == 'door':
                log('%6d %-30s sprite %dx%d, look at it: v = a wall that runs north-south, h = east-west' % (i, what, things[c - 100].w, things[c - 100].h))
        if why:
            bad += 1
            log('%6d %-30s BAD: %s' % (i, what, '; '.join(why)))
    log('%d building ids, %d problem(s)' % (len(rows), bad))
    return bad == 0
