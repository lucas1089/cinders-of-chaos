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
KINDS = ('temple', 'depot', 'shop', 'house')      # the walled kinds
OPEN_KINDS = ('camp',)                            # O740: an open kind, no walls, no door, no roof
ALL_KINDS = KINDS + OPEN_KINDS
MAX_UP = 2                                        # O740: floors above a building (z - 1, z - 2)
SIDES = {'n': (0, -1), 'e': (1, 0), 's': (0, 1), 'w': (-1, 0)}
DIR_OF = {v: k for k, v in SIDES.items()}
FEATURES = ('altar', 'pillar_pair', 'bench_row', 'counter', 'shelf_row')
ROLES = ('floor', 'hang')
HANG_WALLS = ('back', 'front', 'left', 'right')
GAP = 2                     # free tiles kept between two buildings
OPEN_SHARE = 0.75           # O740: the walkable share of an open kind's patch (the rest keeps its trees and stones)
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
    is_open = bool(pf.get('open'))
    need = ('kind', 'width', 'height', 'pz') if is_open else \
        ('kind', 'width', 'height', 'door_side', 'door_width', 'wall', 'floor', 'roof', 'pz')
    for k in need:
        if k not in pf:
            out.append('%s: missing "%s"' % (kind, k))
    if is_open:
        for k in ('wall', 'door_side', 'door_width', 'features', 'npc', 'upper'):
            if pf.get(k):
                out.append('%s: an open kind has no "%s"' % (kind, k))
        if pf.get('roof'):
            out.append('%s: an open kind has no roof' % kind)
    for k in ('width', 'height'):
        r = pf.get(k)
        if not (isinstance(r, list) and len(r) == 2 and all(isinstance(v, int) for v in r) and SIZE_LIMITS[0] <= r[0] <= r[1] <= SIZE_LIMITS[1]):
            out.append('%s: %s must be [lo, hi] inside %d-%d' % (kind, k, SIZE_LIMITS[0], SIZE_LIMITS[1]))
    if not is_open and pf.get('door_side') not in ('route', 'n', 'e', 's', 'w'):
        out.append('%s: door_side %r' % (kind, pf.get('door_side')))
    if not is_open and pf.get('door_width') not in (1, 2):
        out.append('%s: door_width must be 1 or 2' % kind)
    for name in (pf.get('upper') or {}).get('pieces', []):
        if name not in fams:
            out.append('%s.upper: no family %r in building_families.json' % (kind, name))
        elif fams[name].get('hang'):
            out.append('%s.upper: %s is a hung piece; upper floors take floor pieces' % (kind, name))

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
    if mats is not None and not is_open:
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


def open_layout(pf, w, h, extra_slots=()):
    """an open kind (O740: camp): a w x h patch with no wall, no door and no roof, its pieces on floor slots (dx, dy
    over the whole patch, "c" the middle). It does not turn: the same patch for every side. Pure; the shape of layout()"""
    if w < 3 or h < 3:
        raise BuildingError('a %d x %d patch is too small' % (w, h))
    out = dict(W=w, H=h, iw=w, ih=h, side='s', dw=0, c0=(w - 1) // 2, door=[], outside=[], inside=[], walls={},
               floor={(x, y) for x in range(w) for y in range(h)}, items=[], reach=[], npc=None, conflicts=[], dropped=[],
               open=True)
    claimed = {}
    for i, s in enumerate(list(pf.get('slots', [])) + list(extra_slots)):
        if w < s.get('min_iw', 0) or h < s.get('min_ih', 0):
            continue
        what = 'slot %d' % i
        if s.get('role') != 'floor':
            out['dropped'].append('%s: an open kind has no wall to hang a piece on' % what)
            continue
        t = (coord(s['dx'], w, what + ' dx'), coord(s['dy'], h, what + ' dy'))
        if t in claimed:
            out['conflicts'].append('%s at %s overlaps %s' % (what, t, claimed[t]))
            continue
        claimed[t] = what
        out['items'].append(dict(tile=t, family=s['family'], role='floor', kind='slot', what=what,
                                 facing=s.get('facing', 's'), axis=None, wall_dir=None))
    return out


def make_layout(pf, w, h, side, extra_slots=()):
    """layout() for a walled kind, open_layout() for an open one"""
    return open_layout(pf, w, h, extra_slots) if pf.get('open') else layout(pf, w, h, side, extra_slots)


def family_blocks(name, fams, kit):
    """does a family's piece block the tile (a hung piece never does)"""
    spec = fams[name]
    if spec.get('hang'):
        return False
    if 'group' in spec:
        return bool(kit['groups'][spec['group']]['block'])
    return bool(spec.get('block'))


def _all_reached(free, start):
    """every tile of `free` joined to start (8 neighbours)"""
    if start not in free:
        return False
    seen, stack = {start}, [start]
    while stack:
        t = stack.pop()
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                n = (t[0] + dx, t[1] + dy)
                if n in free and n not in seen:
                    seen.add(n)
                    stack.append(n)
    return seen == free


def plan_levels(lay, n_up, cellar, blocks, upper_pieces=()):
    """the floors above a walled building and the way down to its cellar (O740), in the layout's relative tiles. Pure.
    The stairs are our stair brush: the stone stairs on the floor below lead up to the tile one step their way
    (C.STAIR_HEADINGS: north, or west since O745) of the stairs ground on the floor above; stepping on the stairs
    ground goes down to the tile one step the other way of the stone stairs (the rule of the plan's `stairs`
    connections). A heading is tried only when the north stairs fit nowhere (C.STAIR_ORDER). The cellar is reached by
    the large hole (down onto the ladder) and the ladder (up to the tile south of the hole). A stair or hole tile
    changes the floor, so it counts as no way through: every free interior tile of every floor stays joined to the way
    in without it. blocks(family) -> the piece blocks.
    -> dict(levels=[{k, stairs, heading, down, start, items}], hole, hole_up, dropped); raises BuildingError when no
    place fits"""
    interior = set(lay['floor'])
    claimed0 = {it['tile'] for it in lay['items'] if it['role'] == 'floor'}
    blocked0 = {it['tile'] for it in lay['items'] if it['role'] == 'floor' and blocks(it['family'])}
    keep0 = set(lay['reach']) | set(lay['inside']) | ({lay['npc']} if lay['npc'] else set())
    start0 = lay['inside'][0]
    s0 = lay['inside'][0]

    def step(h):
        return C.STAIR_HEADINGS[h][1]

    def landing(t, h):
        return (t[0] - step(h)[0], t[1] - step(h)[1])

    def order(start):
        return sorted(interior, key=lambda t: (-(abs(t[0] - start[0]) + abs(t[1] - start[1])), t[1], t[0]))

    def stairs_all(level_claimed, level_blocked, level_keep, barriers, start):
        for h in C.STAIR_ORDER:
            fx, fy = step(h)
            for t in order(start):
                land, arr = (t[0] - fx, t[1] - fy), (t[0] + fx, t[1] + fy)
                if t in level_claimed or t in level_keep or t in barriers or t == start:
                    continue
                if land not in interior or land in level_claimed or land in barriers or arr not in interior:
                    continue
                if _all_reached(interior - level_blocked - barriers - {t}, start):
                    yield t, h

    def stairs_on(*a):
        return next(stairs_all(*a), (None, None))

    def hole_for(st, sh):
        """(hole, up) on the ground floor beside the stairs `st` of heading `sh` (or None), or None"""
        bars = {st} if st else set()
        land = landing(st, sh) if st else None
        for t in order(s0):
            up = (t[0], t[1] + 1)
            if t in claimed0 or t in keep0 or t in bars or t == start0 or up not in interior or up in claimed0 or up in bars:
                continue
            if st and (up == land or t == land):
                continue
            if _all_reached(interior - blocked0 - bars - {t}, start0):
                return t, up
        return None
    levels = [dict(k=0, stairs=None, heading=None, down=None, start=start0, items=[])]
    dropped = []
    hole = hole_up = None
    if n_up:
        found = None
        for t, h in stairs_all(claimed0, blocked0, keep0, set(), start0):  # the first stairs tile that leaves room for the hole
            if not cellar:
                found = (t, h, None)
                break
            hz = hole_for(t, h)
            if hz:
                found = (t, h, hz)
                break
        if found is None:
            raise BuildingError('no tile inside takes the stairs up (a free tile with a free one on each side of it '
                                'along the stairs)' + (' beside the hole to the cellar' if cellar else ''))
        levels[0]['stairs'], levels[0]['heading'] = found[0], found[1]
        if found[2]:
            hole, hole_up = found[2]
    elif cellar:
        hz = hole_for(None, None)
        if hz is None:
            raise BuildingError('no tile inside takes the hole to the cellar (a free tile with a free one south of it)')
        hole, hole_up = hz
    for k in range(1, n_up + 1):
        down, dh = levels[k - 1]['stairs'], levels[k - 1]['heading']
        start = (down[0] + step(dh)[0], down[1] + step(dh)[1])
        lv = dict(k=k, stairs=None, heading=None, down=down, start=start, items=[])
        bars = {down}
        if k < n_up:
            t, h = stairs_on(set(), set(), {start}, bars, start)
            if t is None:
                raise BuildingError('no tile of floor %d takes the stairs up' % k)
            lv['stairs'], lv['heading'] = t, h
            bars.add(t)
        busy = bars | {start} | ({landing(lv['stairs'], lv['heading'])} if lv['stairs'] else set())
        xs, ys = [t[0] for t in interior], [t[1] for t in interior]
        corners = [(min(xs), min(ys)), (max(xs), min(ys)), (max(xs), max(ys)), (min(xs), max(ys))]
        blk = set()
        for name in upper_pieces:
            put = None
            for c in corners:
                if c in busy or c not in interior:
                    continue
                if blocks(name) and not _all_reached(interior - bars - blk - {c}, start):
                    continue
                put = c
                break
            if put is None:
                dropped.append('floor %d: no free corner for %s' % (k, name))
                continue
            busy.add(put)
            if blocks(name):
                blk.add(put)
            lv['items'].append(dict(tile=put, family=name, facing='s' if put[1] == min(ys) else 'n'))
        levels.append(lv)
    return dict(levels=levels, hole=hole, hole_up=hole_up, dropped=dropped)


def ruin_plan(lay, share, rng, hung=()):
    """which wall tiles break and which floor tiles lose their floor in a ruin of `share` percent (O740). Pure.
    The door, the two wall tiles on each side of it (a wall piece beside the door keeps a wall neighbour, so the map
    tile audit, which does not count a door as wall, gives it the same piece) and a wall that carries a hung piece, with
    its neighbours, stay. The gaps only open the walls, so no way gets longer and the door path stays as it was.
    -> (gaps, patches): sets of relative tiles"""
    if share <= 0:
        return set(), set()
    door = set(lay['door'])
    near = {(t[0] + dx, t[1] + dy) for t in door for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (2, 0), (-2, 0), (0, 2), (0, -2))}
    keep = {(t[0] + dx, t[1] + dy) for t in hung for dx in (-1, 0, 1) for dy in (-1, 0, 1)}    # a hung piece and its run
    eligible = sorted(t for t in lay['walls'] if t not in door and t not in near and t not in keep)
    n = int(round(len(eligible) * share / 100.0))
    gaps = set(rng.sample(eligible, min(n, len(eligible))))
    taken = {it['tile'] for it in lay['items'] if it['role'] == 'floor'} | set(lay['reach']) | set(lay['inside'])
    if lay['npc']:
        taken.add(lay['npc'])
    free = sorted(t for t in lay['floor'] if t not in taken)
    m = int(round(len(free) * share / 200.0))
    patches = set(rng.sample(free, min(m, len(free))))
    return gaps, patches


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
    if lay.get('open'):
        # O740: an open kind takes the walkable tiles of its patch and leaves a tree or a stone as it stands (cutting
        # them would square off the edge of the floor, the outline rule of "Asymmetric areas"): every piece on a
        # walkable tile the entry reaches, OPEN_SHARE of the patch walkable, no ring, no door
        n_walk = 0
        for t in _rect_tiles(bx, by, lay['W'], lay['H']):
            a = (t[0], t[1], z)
            if not (x1 <= t[0] <= x2 and y1 <= t[1] <= y2):
                return 'leaves its zone'
            if a in blocked:
                return 'overlaps %s' % blocked[a]
            n_walk += a in walk
        for it in lay['items']:
            a = (bx + it['tile'][0], by + it['tile'][1], z)
            if a not in walk or (reach0 is not None and a not in reach0):
                return 'puts %s on %s, which is not a walkable tile the entry reaches' % (it['family'], a)
        if n_walk < OPEN_SHARE * lay['W'] * lay['H']:
            return 'stands on too little open ground (%d of %d tiles walkable)' % (n_walk, lay['W'] * lay['H'])
        return None
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
    inner = {(bx + t[0], by + t[1], z) for t in lay['floor'] if t not in lay.get('block', ())} | \
        {(bx + t[0], by + t[1], z) for t in lay['door']}
    if lay.get('open'):         # O740: an open kind keeps what was not walkable as it was
        inner = {a for a in inner if a in walk}
    after = reach_fn((walk - foot) | inner)
    return sum(1 for t in reach0 if t not in foot and t not in after)


def route_cost(lay, bx, by, route_pts):
    """squared distance of the tile outside the door to the nearest route point"""
    if not lay['outside']:
        return 0
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


def place_all(plan, zrect, walk, tiles, special, corridor, arrival, origin, mats, kit, fams, seed, E, Wn, reach_fn,
              cellar_fn=None, border_ids=frozenset()):
    """place and stamp every building of the plan on the generated tiles (before the teleports, chests, NPCs and
    decoration). Changes tiles and walk. zrect: {zone: (x1, y1, x2, y2, z)} absolute; special: tiles to keep clear (the
    arrival, the holes and ladders); corridor: the tiles of the plan's paths; reach_fn(walk) -> the tiles reached from the
    entry. O740: cellar_fn(building, spec, ladder tile) runs the generator for a cellar (area_plan_compile.py); border_ids:
    the border pieces an open kind keeps on its tiles.
    -> dict(records, prot, special, pz, wall_ids, floor_ids, door_ids, block_ids, item_ids, roof_ids, foot, edges (the floor
    changes of stairs and cellars, (from, to)), extra (the tiles of the floors above and the cellars), cellars, skip_border,
    extra_allowed, extra_ground, extra_block)"""
    ox, oy, _oz = origin
    res = dict(records=[], prot=set(), special=set(), pz=set(), wall_ids=set(), floor_ids=set(), door_ids=set(),
               block_ids=set(), item_ids=set(), roof_ids=set(), foot=set(), edges=[], extra=set(), cellars=[],
               skip_border=set(), extra_allowed=set(), extra_ground=set(), extra_block=set())
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
            if pf.get('open'):
                lays = {'s': open_layout(pf, w, h, b.get('slots', ()))}
                lays['s']['block'] = {it['tile'] for it in lays['s']['items'] if family_blocks(it['family'], fams, kit)}
            else:
                lays = {s: layout(pf, w, h, s, b.get('slots', ())) for s in 'nesw'}
        except BuildingError as e:
            E('building %s: %s' % (bid, e))
            continue
        if lays['s']['conflicts']:
            E('building %s: %s' % (bid, '; '.join(lays['s']['conflicts'])))
            continue
        side_req = 's' if pf.get('open') else (b.get('door') or pf['door_side'])
        sides = tuple('nesw') if side_req == 'route' else (side_req,)
        n_up, cellar = int(b.get('floors_above', 0)), b.get('cellar')
        levels = {}
        if n_up or cellar:        # O740: the stairs and the cellar hole must fit on the side
            why_lv = None
            for s_ in sides:
                try:
                    levels[s_] = plan_levels(lays[s_], n_up, cellar, lambda f_: family_blocks(f_, fams, kit),
                                             (pf.get('upper') or {}).get('pieces', ()))
                except BuildingError as e:
                    why_lv = str(e)
            sides = tuple(s_ for s_ in sides if s_ in levels)
            if not sides:
                E('building %s: %s' % (bid, why_lv))
                continue
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
        rec = stamp(b, pf, lay, bx, by, zz, tiles, walk, mats, kit, fams, rng, b.get('wall') or pf.get('wall'),
                    b.get('floor') or pf.get('floor'), res, E, levels=levels.get(side),
                    ruin=b.get('ruin', plan.get('ruin', 0)), cellar_fn=cellar_fn, border_ids=border_ids)
        for t in _rect_tiles(bx - GAP, by - GAP, lay['W'] + 2 * GAP, lay['H'] + 2 * GAP):
            blocked[(t[0], t[1], zz)] = 'building %s' % bid
        res['records'].append(rec)
    return res


def stamp(b, pf, lay, bx, by, z, tiles, walk, mats, kit, fams, rng, wall_name, floor_name, res, E, levels=None, ruin=0,
          cellar_fn=None, border_ids=frozenset()):
    """write one building's tiles; -> its record. O740: `levels` (plan_levels) adds the floors above and the cellar
    hole, `ruin` (percent) breaks walls and floors of a building without floors above, an open kind keeps its ground"""
    is_open = bool(lay.get('open'))
    brush = mats['walls'][wall_name] if not is_open else {}
    floors = mats['families'][floor_name]['grounds'] if floor_name else []
    door_pair = mats['doors'][pf.get('door_family', 'wood')]
    orient = 'h' if lay['side'] in ('n', 's') else 'v'
    door_closed = door_pair[orient]['closed']
    A = lambda t: (bx + t[0], by + t[1], z)
    look = {}
    rec = dict(id=b['id'], kind=b['kind'], zone=b['zone'], side=lay['side'], rect=(bx, by, bx + lay['W'] - 1, by + lay['H'] - 1, z),
               size=[lay['W'], lay['H']], wall=wall_name, floor=floor_name, door=[A(t) for t in lay['door']],
               outside=[A(t) for t in lay['outside']], inside=[A(t) for t in lay['inside']], reach=[A(t) for t in lay['reach']],
               interior=sorted(A(t) for t in lay['floor']), walls={}, features=[], hang=[], blocked=[], roof=[], npc=None,
               ids=set(), pz=bool(b.get('pz', pf.get('pz'))), dropped=list(lay['dropped']), prefab_roof=bool(b.get('roof', pf.get('roof'))),
               floor_ids=set(floors), wall_ids=wall_ids_of(brush), door_ids={door_closed} if not is_open else set(),
               block_ids=set())
    foot = [A(t) for t in list(lay['walls']) + list(lay['floor'])]
    if is_open:     # O740: the walkable tiles of the patch; a tree or a stone in it stays
        foot = [a for a in foot if a in walk]
        rec['open'] = True
        rec['interior'] = sorted(foot)
        rec['patch'] = lay['W'] * lay['H']
    rec['foot'] = foot
    under = {t: tiles[t]['ground'] for t in foot if t in tiles}       # the ground before the stamp (a ruin's patches)
    for t in foot:
        if is_open:     # O740: the camp keeps its ground and its border pieces; the tile's decoration goes
            tiles[t]['items'] = [it for it in tiles[t]['items'] if it[0] in border_ids]
        else:
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
        if not is_open:
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
    n_up = len(levels['levels']) - 1 if levels else 0
    if ruin and not is_open and not n_up:
        _ruin(rec, lay, A, tiles, walk, under, floors, brush, kit, fams, ruin, (bx, by, z))
        rec['prefab_roof'] = False      # a ruin is open to the sky
    if n_up:
        _levels(rec, lay, levels, A, z, tiles, walk, floors, brush, kit, fams, rng, look, res, E)
    if levels and levels['hole'] is not None:
        _cellar(rec, b, levels, A, tiles, walk, cellar_fn, res, E)
    if rec['prefab_roof']:
        roof = kit['roof']['ground'][0]
        rz = z - 1 - n_up
        for t in foot:
            above = (t[0], t[1], rz)
            if rz < 0:
                E('building %s: no floor above z %d for its roof' % (b['id'], rz + 1))
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
    res['skip_border'].update(foot)
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


def _ruin(rec, lay, A, tiles, walk, under, floors, brush, kit, fams, share, where):
    """break the walls and floors of a stamped building (O740, `ruin` percent). A gap takes the ground that lay there
    before, the walls left get the piece their new neighbours want; a patch of the floor takes the old ground; loose
    debris (no blocking piece) on half of the gaps and the patches. Nothing blocks, so no way gets longer."""
    rr = random.Random(where[0] * 7919 + where[1] * 104729 + where[2] * 31 + int(share))
    hung = [h for h, _i in rec['hang']]
    gaps, patches = ruin_plan(lay, share, rr, [(h[0] - where[0], h[1] - where[1]) for h in hung])
    wall_ids = rec['wall_ids']
    for t in sorted(gaps):
        a = A(t)
        tiles[a]['items'] = [it for it in tiles[a]['items'] if it[0] not in wall_ids]
        tiles[a]['ground'] = under.get(a, floors[0])
        walk.add(a)
        rec['walls'].pop(a, None)
    door_set = set(rec['door'])
    wall_set = set(rec['walls']) | door_set
    for a in sorted(rec['walls']):
        n_, e_, s_, w_ = ((a[0] + dx, a[1] + dy, a[2]) in wall_set for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0)))
        want = MR.wall_piece(n_, e_, s_, w_)
        if want != rec['walls'][a]:
            wid = rr.choice(brush[want])
            tiles[a]['items'] = [it if it[0] not in wall_ids else (wid, {}) for it in tiles[a]['items']]
            rec['walls'][a] = want
            rec['block_ids'].add(wid)
    for t in sorted(patches):
        a = A(t)
        tiles[a]['ground'] = under.get(a, tiles[a]['ground'])
    debris = kit['groups'][fams['debris']['group']]['ids']
    loose = sorted(gaps | patches)
    rr.shuffle(loose)
    for t in loose[:len(loose) // 2]:
        iid = rr.choice(debris)
        tiles[A(t)]['items'].append((iid, {}))
        rec['ids'].add(iid)
    rec['ruin'] = dict(share=share, gaps=sorted(A(t) for t in gaps), patches=len(patches), debris=len(loose) // 2)
    rec['floor_ids'] |= {tiles[A(t)]['ground'] for t in gaps | patches}


def _levels(rec, lay, levels, A, z, tiles, walk, floors, brush, kit, fams, rng, look, res, E):
    """the floors above (O740): the same footprint at z - k with the full wall ring (the door becomes wall), the floor
    family, the stairs (stone stairs below, the stairs ground above; their heading from plan_levels, O745) and the
    pieces of the prefab's `upper`"""
    stairs_ground = kit['brushes']['stairs_down_ground']
    rec['levels'] = []
    for lv in levels['levels'][1:]:
        heading = levels['levels'][lv['k'] - 1]['heading']
        key, (fx, fy) = C.STAIR_HEADINGS[heading]
        stairs_up = kit['brushes'][key]
        zk = z - lv['k']
        Ak = lambda t, zk=zk: (A(t)[0], A(t)[1], zk)
        if zk < 0:
            E('building %s: no floor %d above z %d' % (rec['id'], lv['k'], z))
            break
        taken = [Ak(t) for t in list(lay['walls']) + list(lay['floor']) if Ak(t) in tiles]
        if taken:
            E('building %s: floor %d at %s is taken by another floor of the area' % (rec['id'], lv['k'], taken[0]))
            break
        info = dict(k=lv['k'], z=zk, walls={}, interior=sorted(Ak(t) for t in lay['floor']), items=[],
                    start=Ak(lv['start']), down=Ak(lv['down']), stairs=Ak(lv['stairs']) if lv['stairs'] else None,
                    heading=heading, stairs_id=stairs_up)
        for t in list(lay['walls']) + list(lay['floor']):
            tiles[Ak(t)] = dict(ground=rng.choice(floors), items=[], flags=0)
        for t, kind in sorted(lay['walls'].items()):
            wid = rng.choice(brush[kind])
            tiles[Ak(t)]['items'].append((wid, {}))
            info['walls'][Ak(t)] = kind
            rec['block_ids'].add(wid)
        for t in lay['floor']:
            walk.add(Ak(t))
            res['extra'].add(Ak(t))
        for it in lv['items']:
            a = Ak(it['tile'])
            iid, blk = resolve_item(it['family'], fams, kit, rng, look, it['facing'])
            tiles[a]['items'].append((iid, {}))
            rec['ids'].add(iid)
            if blk:
                walk.discard(a)
                rec['block_ids'].add(iid)
            info['items'].append(dict(family=it['family'], at=a, id=iid, block=blk))
        # the stairs from the floor below: stone stairs there lead up one step their way of the stairs ground here
        below = (info['down'][0], info['down'][1], zk + 1)
        tiles[below]['items'].append((stairs_up, {}))
        tiles[info['down']]['ground'] = stairs_ground
        arrive, land = (info['down'][0] + fx, info['down'][1] + fy, zk), (below[0] - fx, below[1] - fy, zk + 1)
        res['edges'] += [(below, arrive), (info['down'], land)]
        res['special'].update((below, info['down'], land, arrive))
        res['extra_ground'].add(stairs_ground)
        res['foot'].update(Ak(t) for t in list(lay['walls']) + list(lay['floor']))
        res['prot'].update(Ak(t) for t in list(lay['walls']) + list(lay['floor']))
        rec['floor_ids'] |= set(floors)
        rec['levels'].append(info)
    rec['dropped'] += levels['dropped']


def _cellar(rec, b, levels, A, tiles, walk, cellar_fn, res, E):
    """the cellar one floor down (O740): the generator builds a small dungeon whose arrival lies under the large hole;
    the ladder there climbs to the tile south of the hole"""
    hole, up = A(levels['hole']), A(levels['hole_up'])
    ladder_at = (hole[0], hole[1], hole[2] + 1)
    if cellar_fn is None:
        E('building %s: a cellar needs the area generator' % rec['id'])
        return
    c = cellar_fn(b, b['cellar'], ladder_at)
    for p in c['problems']:
        E('building %s cellar: %s' % (rec['id'], p))
    clash = sorted(k for k in c['tiles'] if k in tiles)
    if clash:
        E('building %s: its cellar overlaps another floor of the area at %s' % (rec['id'], clash[0]))
        return
    if ladder_at not in c['walk']:
        E('building %s: the cellar has no walkable tile under the hole %s' % (rec['id'], hole))
        return
    for k, t in c['tiles'].items():
        tiles[k] = t
    walk.update(c['walk'])
    tiles[ladder_at]['items'].append((c['ladder'], {}))
    tiles[hole]['items'].append((c['hole'], {}))
    res['edges'] += [(hole, ladder_at), (ladder_at, up)]
    res['special'].update((hole, up, ladder_at))
    res['extra'] |= set(c['walk'])
    res['skip_border'] |= set(c['tiles'])
    res['prot'] |= set(c['tiles'])
    res['extra_allowed'] |= c['allowed'] | {c['hole'], c['ladder']}
    res['extra_ground'] |= c['grounds']
    res['extra_block'] |= c['block']
    res['cellars'].append(dict(building=rec['id'], walk=set(c['walk']), frame=c['frame'], z=ladder_at[2]))
    rec['cellar'] = dict(hole=hole, up=up, ladder=ladder_at, biome=c['biome'], walk=sorted(c['walk']),
                         tiles=len(c['tiles']))


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
        brush = mats['walls'][rec['wall']] if not rec.get('open') else {}
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
            (E if rec.get('open') else Wn)('%s: %d interior tile(s) cannot be reached (first %s)' % (label, len(pockets), pockets[0]))
        n_up = len(rec.get('levels', ()))
        for lv in rec.get('levels', ()):       # O740: the floors above
            lw = set(lv['walls'])
            for a, kind in sorted(lv['walls'].items()):
                n_, e_, s_, w_ = ((a[0] + dx, a[1] + dy, a[2]) in lw for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0)))
                want = MR.wall_piece(n_, e_, s_, w_)
                have = [i for i, _x in tiles[a]['items'] if i in ids_of]
                if not have or want not in ids_of[have[0]]:
                    E('%s: floor %d: the wall piece at %s is not the %s piece it needs' % (label, lv['k'], a, want))
            if lv['start'] not in dist:
                E('%s: floor %d cannot be reached by its stairs (%s)' % (label, lv['k'], lv['start']))
            out = [a for a in lv['interior'] if a in walk and a not in dist]
            if out:
                E('%s: floor %d: %d tile(s) out of reach (first %s)' % (label, lv['k'], len(out), out[0]))
        cel = rec.get('cellar')
        if cel:                                 # O740: the cellar
            for what, a in (('the hole', cel['hole']), ('the tile south of the hole', cel['up']), ('the ladder', cel['ladder'])):
                if a not in dist:
                    E('%s: %s at %s cannot be reached' % (label, what, a))
            out = [a for a in cel['walk'] if a in walk and a not in dist]
            if out:
                E('%s: the cellar has %d tile(s) out of reach (first %s)' % (label, len(out), out[0]))
        for a in (rec.get('ruin') or {}).get('gaps', ()):
            if a not in walk:
                E('%s: the ruin gap at %s is not walkable' % (label, a))
        if rec['prefab_roof']:
            miss = [t for t in rec['foot'] if tiles.get((t[0], t[1], t[2] - 1 - n_up), {}).get('ground') not in roof_ground]
            if miss:
                E('%s: the roof misses %d footprint tile(s) (first %s)' % (label, len(miss), miss[0]))
        elif rec['roof']:
            E('%s: a roof was laid but the prefab has none' % label)


def manifest_of(rec, dist=None):
    return dict(id=rec['id'], kind=rec['kind'], zone=rec['zone'], door_side=rec['side'], rect=list(rec['rect'][:4]), z=rec['rect'][4],
                size=rec['size'], wall=rec['wall'], floor=rec['floor'], door=[list(t) for t in rec['door']],
                outside=[list(t) for t in rec['outside']], route_steps=(dist.get(rec['outside'][0]) if dist and rec['outside'] else None),
                roof_tiles=len(rec['roof']), features=[dict(f, at=list(f['at'])) for f in rec['features']],
                hung=len(rec['hang']), dropped=rec['dropped'], pz=rec['pz'],
                npc=list(rec['npc']) if rec['npc'] else None, **_manifest_o740(rec, dist))


def _manifest_o740(rec, dist):
    """the O740 parts of a building's manifest entry, only the ones it uses (an O515 building keeps its entry)"""
    out = {}
    if rec.get('open'):
        out['open'] = True
    if rec.get('levels'):
        out['floors_above'] = [dict(z=lv['z'], stairs_from=list(lv['down']), climb=C.CLIMB[lv['heading']],
                                    walkable=len(lv['interior']),
                                    pieces=[i['family'] for i in lv['items']]) for lv in rec['levels']]
    if rec.get('cellar'):
        c = rec['cellar']
        out['cellar'] = dict(biome=c['biome'], hole=list(c['hole']), ladder=list(c['ladder']), walkable=len(c['walk']),
                             tiles=c['tiles'], steps=dist.get(c['ladder']) if dist else None)
    if rec.get('ruin'):
        r = rec['ruin']
        out['ruin'] = dict(share=r['share'], gaps=len(r['gaps']), patches=r['patches'], debris=r['debris'])
    return out


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
