#!/usr/bin/env python3
"""Dressing of a compiled area (area_plan_compile.py; docs/MAP_GUIDE.md "Area planner", Decoration).

The area generator lays grounds, borders, walls and a light scatter. This pass adds the biome's decoration kit
(areaplan/decor_kits.json: stock 10.98 items measured on the pair, grouped by look and role) with placement rules
instead of a uniform scatter:
  * halls and boss rooms of a dungeon: pillars in mirrored rows, braziers beside the throne, statues in the corners;
  * wall decoration hung on the north and west walls of dungeon rooms (torches, candles, tapestries, banners), the
    light pieces as often as the plan's light asks;
  * light props against the walls (braziers, lava holes, glowing mushrooms, crystals);
  * corner pieces, wall-hugging props, clusters of 2-5 small items around an anchor piece, edging along paths;
  * floor detail on a gradient: dense along the walls, sparse in the middle so fights stay readable.
  * nothing else next to a quest chest (`clear_around`, run last): the reward chest is one tile, front facing, and stands
    alone; every decoration item, hung wall piece and loose scatter on the eight tiles around it is taken off again.
Rules: never on a protected tile (spawn, teleport, its landing, link, chest, NPC, boss, arrival), nothing blocking on a
route the area needs (the shortest walks from the arrival to every zone, spawn and special tile) or inside a planned
path, a blocking piece only where its walkable neighbours stay joined, one decoration item per tile. The QA of the
compiler checks afterwards that no walkable tile was cut off. `decoration` scales every rate, `light` the lights.
"""
import json, os, re

import area_plan_core as C

KITS_PATH = os.path.join(C.PLANDIR, 'decor_kits.json')
# the owner's decoration of client pair 26 (desert plants, the waypoint seal): merged only while the server switch
# ChaosOwnerArt.PAIR26 is on (server/data/lib/chaos_owner_art.lua; a client on an older pair has no such items)
OWNER_PATH = os.path.join(C.PLANDIR, 'decor_owner_art.json')
OWNER_SWITCH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'data', 'lib',
                            'chaos_owner_art.lua')
# the catacomb kit of the client pair 27 trial (sarcophagi, crypt hatches, the portal ring): merged after the owner's
# overlay only while ChaosAssetsArt.PAIR27 is on (server/data/lib/chaos_assets_art.lua; off while pair 27 is a trial)
ASSETS_PATH = os.path.join(C.PLANDIR, 'decor_assets_art.json')
ASSETS_SWITCH = os.path.join(os.path.dirname(OWNER_SWITCH), 'chaos_assets_art.lua')
# the harvest kit of client pair 33 (corn, pumpkins, tombstones, urns, coffins, ...; kits for the biomes harvest and
# harvest_crypt): merged last, only while ChaosHarvestArt.PAIR33 is on (server/data/lib/chaos_harvest_art.lua)
HARVEST_PATH = os.path.join(C.PLANDIR, 'decor_pack33_kit.json')
HARVEST_SWITCH = os.path.join(os.path.dirname(OWNER_SWITCH), 'chaos_harvest_art.lua')
DECOR = {'sparse': 0.55, 'normal': 1.0, 'dense': 1.5}
LIGHT = {'dark': 0.5, 'dim': 0.75, 'normal': 1.0, 'bright': 1.5}
# rates at "normal" (per candidate tile unless noted)
RATE = dict(floor_wall=0.14, floor_near=0.08, floor_mid=0.03, wall_side=0.07, corner=0.55, clusters_per100=1.9,
            path_edge=0.16, wall_spacing=4, light_floor_per100=1.1, light_small=0.012, hall_min=(11, 9))
_kits = None


def owner_on(path=OWNER_SWITCH):
    if not os.path.isfile(path):
        return False
    return re.search(r'^M\.PAIR26\s*=\s*true\b', open(path, encoding='utf-8').read(), re.M) is not None


def assets_on(path=ASSETS_SWITCH):
    if not os.path.isfile(path):
        return False
    return re.search(r'^M\.PAIR27\s*=\s*true\b', open(path, encoding='utf-8').read(), re.M) is not None


def harvest_on(path=HARVEST_SWITCH):
    if not os.path.isfile(path):
        return False
    return re.search(r'^M\.PAIR33\s*=\s*true\b', open(path, encoding='utf-8').read(), re.M) is not None


def merge_owner(k, extra):
    """decor_kits.json plus the owner's overlay: its groups, its kits (a `base` kit's rows plus `add` rows per
    category; with `replace`, the `add` rows replace the base kit's rows of those categories) and its biome mapping;
    the input is not changed"""
    out = json.loads(json.dumps(k))
    for name, g in extra['groups'].items():
        assert name not in out['groups'], 'group %s twice' % name
        out['groups'][name] = g
    for name, spec in extra['kits'].items():
        kit = json.loads(json.dumps(out['kits'][spec['base']]))
        for cat, rows in spec['add'].items():
            kit[cat] = list(rows) if spec.get('replace') else kit.get(cat, []) + rows
        out['kits'][name] = kit
    out['biome_kit'].update(extra['biome_kit'])
    return out


def kits():
    global _kits
    if _kits is None:
        _kits = json.load(open(KITS_PATH, encoding='utf-8'))
        if owner_on():
            _kits = merge_owner(_kits, json.load(open(OWNER_PATH, encoding='utf-8')))
        if assets_on():
            _kits = merge_owner(_kits, json.load(open(ASSETS_PATH, encoding='utf-8')))
        if harvest_on():
            _kits = merge_owner(_kits, json.load(open(HARVEST_PATH, encoding='utf-8')))
    return _kits


def kit_for(biome):
    k = kits()
    name = k['biome_kit'].get(biome)
    return (name, k['kits'][name]) if name else (None, None)


def all_ids():
    """every id of the kits (for the id check of the QA)"""
    k = kits()
    out = set()
    for g in k['groups'].values():
        out.update(g['ids'])
    out.update(k['brushes'].values())
    out.update(k['roof']['ground'])
    return out


class Dresser:
    def __init__(self, tiles, walk, zones, kind, biome, protected, keep_clear, corridor, plain_ids, wall_kind, rng,
                 decoration='normal', light='normal', boss=None):
        self.tiles, self.walk, self.zones, self.kind = tiles, walk, zones, kind
        self.protected, self.keep_clear, self.corridor = protected, keep_clear, corridor
        self.plain_ids, self.wall_kind, self.rng, self.boss = plain_ids, wall_kind, rng, boss
        self.dm = DECOR.get(decoration, 1.0)
        self.lm = LIGHT.get(light, 1.0)
        self.kit_name, self.kit = kit_for(biome)
        self.groups = kits()['groups']
        self.placed = []          # (tile, id, group, category)
        self.blocked = set()      # tiles a blocking piece took
        self.counts = {}
        self.fixed = {}
        self.fixed_groups = {g for cat in ('wall_h', 'wall_v', 'light_wall_h', 'light_wall_v')
                             for g, _w in (self.kit or {}).get(cat, [])}
        for gs in ((self.kit or {}).get('hall') or {}).values():
            self.fixed_groups.update(gs)
        self.zone_of = {}
        for z in zones:
            x1, y1, x2, y2, zz = z['rect']
            for y in range(y1, y2 + 1):
                for x in range(x1, x2 + 1):
                    self.zone_of.setdefault((x, y, zz), z)
        self.dist = self._wall_distance()

    # ------------------------------------------------------------------------------------------------ helpers
    def _wall_distance(self, cap=6):
        """steps (8 neighbours) from each walkable tile to the nearest tile that is not walkable"""
        dist = {}
        frontier = []
        for t in self.walk:
            if any((t[0] + dx, t[1] + dy, t[2]) not in self.walk for dx, dy in C.D8):
                dist[t] = 1
                frontier.append(t)
        d = 1
        while frontier and d < cap:
            d += 1
            nxt = []
            for t in frontier:
                for dx, dy in C.D8:
                    n = (t[0] + dx, t[1] + dy, t[2])
                    if n in self.walk and n not in dist:
                        dist[n] = d
                        nxt.append(n)
            frontier = nxt
        for t in self.walk:
            dist.setdefault(t, cap)
        return dist

    def occupied(self, t):
        return any(i not in self.plain_ids for i, _a in self.tiles[t]['items'])

    def pick_group(self, rows):
        rows = [r for r in rows if r[0] in self.groups]
        if not rows:
            return None
        total = sum(w for _g, w in rows)
        v = self.rng.random() * total
        for g, w in rows:
            v -= w
            if v < 0:
                return g
        return rows[-1][0]

    def clear(self, t):
        """take the generator's loose decoration off a tile, for a set piece (throne, braziers, pillars)"""
        if t in self.walk and t not in self.protected and t in self.tiles:
            self.tiles[t]['items'] = [it for it in self.tiles[t]['items'] if it[0] in self.plain_ids]

    def free(self, t):
        return t in self.walk and t not in self.protected and t in self.tiles and not self.occupied(t)

    def clear_around(self, centers, keep_ids):
        """take everything but the ids in keep_ids (grounds' borders, wall pieces, the chest) and items with attributes
        (portals, teleports, anything an action id marks) off the eight tiles around each centre; a blocking piece that
        goes makes its tile walkable again. -> number of items taken off. The decoration lists and counters follow."""
        ring = {(c[0] + dx, c[1] + dy, c[2]) for c in centers for dx, dy in C.D8} - set(centers)
        gone = 0
        for t in sorted(ring):
            if t not in self.tiles:
                continue
            items = self.tiles[t]['items']
            kept = [it for it in items if it[0] in keep_ids or it[1]]
            if len(kept) == len(items):
                continue
            gone += len(items) - len(kept)
            self.tiles[t]['items'] = kept
        if not gone:
            return 0
        placed, dropped = [], []
        for p in self.placed:
            t, iid, _g, _c = p
            (dropped if t in ring and t in self.tiles and all(i != iid for i, _a in self.tiles[t]['items']) else placed).append(p)
        self.placed = placed
        for t, _iid, g, cat in dropped:
            self.counts[cat] = self.counts.get(cat, 1) - 1
            if not self.counts[cat]:
                del self.counts[cat]
            if self.groups[g]['block'] and t in self.blocked:
                self.blocked.discard(t)
                self.walk.add(t)
        return gone

    def can_block(self, t, spacing=1, lanes=True):
        # set pieces of a hall may stand on a route: a blocking piece is only placed where its neighbours stay
        # joined, so the route bends round it
        if not self.free(t) or (lanes and t in self.keep_clear) or t in self.corridor:
            return False
        if spacing and any((t[0] + dx, t[1] + dy, t[2]) in self.blocked for dx in range(-spacing, spacing + 1)
                           for dy in range(-spacing, spacing + 1) if dx or dy):
            return False
        # a 2x2 sprite draws over its north-west neighbours: keep it off the tiles in front of protected ones
        if any((t[0] + dx, t[1] + dy, t[2]) in self.protected for dx, dy in ((0, 0), (-1, 0), (0, -1), (-1, -1),
                                                                             (1, 0), (0, 1), (1, 1))):
            return False
        return _simple(self.walk, t)

    def put(self, t, group, cat):
        g = self.groups[group]
        if group in self.fixed_groups:
            # one look per area for hung cloth, banners and hall pieces (one tapestry colour, one pillar); the
            # _h and _v groups of one kind list their colours in the same order and share the pick
            stem = group[:-2] if group[-2:] in ('_h', '_v') else group
            k = self.fixed.setdefault('idx:' + stem, self.rng.randrange(len(g['ids'])))
            iid = g['ids'][k % len(g['ids'])]
        else:
            iid = g['ids'][self.rng.randrange(len(g['ids']))]
        self.tiles[t]['items'].append((iid, {}))
        if g['block']:
            self.walk.discard(t)
            self.blocked.add(t)
        self.placed.append((t, iid, group, cat))
        self.counts[cat] = self.counts.get(cat, 0) + 1
        return True

    def try_block(self, t, rows, cat, spacing=1):
        if not self.can_block(t, spacing):
            return False
        g = self.pick_group(rows)
        if not g:
            return False
        if not self.groups[g]['block']:
            return self.free(t) and self.put(t, g, cat)
        return self.put(t, g, cat)

    def covers_protected(self, t, group):
        """a sprite wider or taller than a tile draws over its west and north neighbours"""
        if self.groups[group]['size'] < 2:
            return False
        return any((t[0] + dx, t[1] + dy, t[2]) in self.protected for dx, dy in ((-1, 0), (0, -1), (-1, -1)))

    def try_flat(self, t, rows, cat):
        g = self.pick_group([r for r in rows if r[0] in self.groups and not self.groups[r[0]]['block']])
        if g and self.free(t) and not self.covers_protected(t, g):
            return self.put(t, g, cat)
        return False

    def chance(self, p):
        return self.rng.random() < p

    def rate(self, key):
        """RATE[key] times the kit's own factor for it (kit "rates")"""
        return RATE[key] * (self.kit.get('rates') or {}).get(key, 1.0)

    # ------------------------------------------------------------------------------------------------ passes
    def halls(self):
        hall = self.kit.get('hall')
        if not hall or self.kind != 'dungeon':
            return
        mw, mh = RATE['hall_min']
        for z in self.zones:
            if z['shape'] != 'room':
                continue
            x1, y1, x2, y2, zz = z['rect']
            w, h = x2 - x1 + 1, y2 - y1 + 1
            is_boss = z['role'] == 'boss'
            if not is_boss and (max(w, h) < mw or min(w, h) < mh) and self.dm < 1.4:
                continue
            if 'hall_pillar' not in self.fixed:
                self.fixed['hall_pillar'] = self.pick_group([[g, 1] for g in hall['pillar']])
            pillar = self.fixed['hall_pillar']
            # mirrored rows along the long side, two tiles in from the walls, every 4 tiles
            pairs = []
            if w >= h:
                xs = list(range(x1 + 2, x2 - 1, 4))
                off = (x2 - 2 - xs[-1]) // 2 if xs else 0
                pairs = [((x + off, y1 + 2, zz), (x + off, y2 - 2, zz)) for x in xs]
            else:
                ys = list(range(y1 + 2, y2 - 1, 4))
                off = (y2 - 2 - ys[-1]) // 2 if ys else 0
                pairs = [((x1 + 2, y + off, zz), (x2 - 2, y + off, zz)) for y in ys]
            for a, b in pairs:
                self.clear(a)
                self.clear(b)
                if self.can_block(a, 1, False) and self.can_block(b, 1, False):
                    self.put(a, pillar, 'hall pillars')
                    self.put(b, pillar, 'hall pillars')
            # statues in the four inner corners, mirrored
            if 'hall_statue' not in self.fixed:
                self.fixed['hall_statue'] = self.pick_group([[g, 1] for g in hall.get('statue', [])])
            statue = self.fixed['hall_statue']
            if statue:
                cs = [(x1 + 1, y1 + 1, zz), (x2 - 1, y1 + 1, zz), (x1 + 1, y2 - 1, zz), (x2 - 1, y2 - 1, zz)]
                for a, b in ((cs[0], cs[1]), (cs[2], cs[3])):
                    if self.can_block(a, 1, False) and self.can_block(b, 1, False):
                        self.put(a, statue, 'hall statues')
                        self.put(b, statue, 'hall statues')
            if is_boss and self.boss:
                bx, by, bz = self.boss
                throne = self.pick_group([[g, 1] for g in hall.get('throne', [])])
                for dy in (-2, -1):
                    t = (bx, by + dy, bz)
                    self.clear(t)
                    if throne and self.free(t):
                        self.put(t, throne, 'throne')
                        break
                brazier = self.pick_group([[g, 1] for g in hall.get('brazier', [])])
                for dx, dy in ((2, -2), (3, -1), (2, -1), (3, -2), (2, 0)):
                    a, b = (bx - dx, by + dy, bz), (bx + dx, by + dy, bz)
                    self.clear(a)
                    self.clear(b)
                    if brazier and self.can_block(a, 0, False) and self.can_block(b, 0, False):
                        self.put(a, brazier, 'braziers')
                        self.put(b, brazier, 'braziers')
                        break

    def wall_decor(self):
        if self.kind != 'dungeon' or not self.kit.get('wall_h'):
            return
        spacing = max(2, int(round(RATE['wall_spacing'] / max(0.5, self.dm))))
        runs = {'h': [], 'v': []}
        for t, kind in self.wall_kind.items():
            if t not in self.tiles or self.occupied_wall(t):
                continue
            if kind == 'horizontal':
                room = (t[0], t[1] + 1, t[2])
                if room in self.walk and room in self.zone_of and room not in self.corridor:
                    runs['h'].append(t)
            elif kind == 'vertical':
                room = (t[0] + 1, t[1], t[2])
                if room in self.walk and room in self.zone_of and room not in self.corridor:
                    runs['v'].append(t)
        for d in ('h', 'v'):
            last = {}
            n = 0
            key = (lambda t: (t[2], t[1], t[0])) if d == 'h' else (lambda t: (t[2], t[0], t[1]))
            for t in sorted(runs[d], key=key):
                line = (t[2], t[1]) if d == 'h' else (t[2], t[0])
                pos = t[0] if d == 'h' else t[1]
                if line in last and pos - last[line] < spacing:
                    continue
                last[line] = pos
                n += 1
                lights = self.kit.get('light_wall_' + d) or []
                if lights and self.chance(min(0.9, 0.5 * self.lm)):
                    g = self.pick_group(lights)
                    cat = 'wall lights'
                else:
                    g = self.pick_group(self.kit['wall_' + d])
                    cat = 'wall decor'
                if g:
                    self.put(t, g, cat)

    def occupied_wall(self, t):
        # a wall tile carries its wall piece and borders; anything else (a hung item already) counts
        return any(i not in self.plain_ids and i not in self.wall_ids for i, _a in self.tiles[t]['items'])

    def light_props(self):
        rows = self.kit.get('light_floor') or []
        if not rows:
            return
        for z in self.zones:
            cells = [t for t in self.zone_cells(z) if self.dist[t] in (1, 2)]
            want = int(round(len(list(self.zone_cells(z))) / 100.0 * self.rate('light_floor_per100') * self.lm))
            self.rng.shuffle(cells)
            made = 0
            for t in cells:
                if made >= want:
                    break
                if any(max(abs(t[0] - p[0]), abs(t[1] - p[1])) < 5 and p[2] == t[2]
                       for p, _i, _g, c in self.placed if c in ('light props', 'braziers')):
                    continue
                if self.try_block(t, rows, 'light props', 1):
                    made += 1

    def zone_cells(self, z):
        x1, y1, x2, y2, zz = z['rect']
        return [(x, y, zz) for y in range(y1, y2 + 1) for x in range(x1, x2 + 1) if (x, y, zz) in self.walk]

    def corners(self):
        rows = self.kit.get('corner') or []
        if not rows:
            return
        for t in sorted(self.walk):
            if t not in self.zone_of or t in self.corridor:
                continue
            n = (t[0], t[1] - 1, t[2]) not in self.walk
            s = (t[0], t[1] + 1, t[2]) not in self.walk
            w = (t[0] - 1, t[1], t[2]) not in self.walk
            e = (t[0] + 1, t[1], t[2]) not in self.walk
            corner = 'nw' if n and w else 'ne' if n and e else 'sw' if s and w else 'se' if s and e else None
            if not corner or not self.chance(self.rate('corner') * self.dm):
                continue
            use = [r for r in rows if r[0] != 'cobweb_corner' or corner == 'nw']
            g = self.pick_group(use)
            if not g:
                continue
            if self.groups[g]['block']:
                if self.can_block(t, 1):
                    self.put(t, g, 'corners')
            elif self.free(t) and not self.covers_protected(t, g):
                self.put(t, g, 'corners')

    def wall_side(self):
        rows = self.kit.get('wall_side') or []
        for t in sorted(self.walk):
            if self.dist.get(t) != 1 or t not in self.zone_of or t in self.corridor:
                continue
            if self.chance(self.rate('wall_side') * self.dm):
                self.try_block(t, rows, 'wall props', 1)

    def clusters(self):
        anchors = self.kit.get('centre') or []
        around = self.kit.get('around') or []
        for z in self.zones:
            cells = self.zone_cells(z)
            if z['role'] in ('boss',) and self.kind == 'dungeon':
                continue
            want = int(round(len(cells) / 100.0 * self.rate('clusters_per100') * self.dm))
            cand = [t for t in cells if self.dist.get(t) in (2, 3)]
            self.rng.shuffle(cand)
            made = 0
            for t in cand:
                if made >= want:
                    break
                if any(max(abs(t[0] - p[0]), abs(t[1] - p[1])) < 5 and p[2] == t[2] for p, _i, _g, c in self.placed
                       if c == 'clusters'):
                    continue
                if not self.try_block(t, anchors, 'clusters', 1):
                    continue
                made += 1
                k = self.rng.randint(2, 5)
                ring = [(t[0] + dx, t[1] + dy, t[2]) for dx in range(-2, 3) for dy in range(-2, 3) if dx or dy]
                self.rng.shuffle(ring)
                for n in ring:
                    if k <= 0:
                        break
                    if self.try_flat(n, around, 'cluster detail'):
                        k -= 1

    def path_edges(self):
        rows = self.kit.get('path_edge') or []
        for t in sorted(self.corridor):
            if t in self.walk and self.dist.get(t) == 1 and self.chance(self.rate('path_edge') * self.dm):
                self.try_flat(t, rows, 'path edging')

    def floor_detail(self):
        rows = self.kit.get('floor') or []
        small = self.kit.get('light_small') or []
        for t in sorted(self.walk):
            d = self.dist.get(t, 6)
            p = self.rate('floor_wall') if d == 1 else self.rate('floor_near') if d == 2 else self.rate('floor_mid')
            if small and d <= 2 and self.chance(RATE['light_small'] * self.lm):
                self.try_flat(t, small, 'small lights')
            elif self.chance(p * self.dm):
                self.try_flat(t, rows, 'floor detail')

    def run(self, wall_ids):
        self.wall_ids = wall_ids
        if not self.kit:
            return self
        self.halls()
        self.wall_decor()
        self.light_props()
        self.corners()
        self.wall_side()
        self.clusters()
        self.path_edges()
        self.floor_detail()
        return self


def _simple(walk, t):
    """removing tile t keeps its walkable neighbours joined (one group around it)"""
    ring = [(t[0] + dx, t[1] + dy, t[2]) in walk for dx, dy in C.D8]
    groups, seen = 0, set()
    for k in range(8):
        if ring[k] and k not in seen:
            groups += 1
            stack = [k]
            seen.add(k)
            while stack:
                a = stack.pop()
                for b in range(8):
                    if ring[b] and b not in seen and abs(C.D8[a][0] - C.D8[b][0]) <= 1 and abs(C.D8[a][1] - C.D8[b][1]) <= 1:
                        seen.add(b)
                        stack.append(b)
    return groups <= 1


def lanes(walk, start, targets, links=(), teleports=()):
    """the tiles of one shortest walk from start to each target (over links and teleports): kept free of blocking
    decoration so every place the area needs stays reachable on the same route"""
    dist = C.tile_reach(walk, start, links, teleports)
    back = {}
    for hole, landing, up in links:
        back.setdefault(landing, []).append(hole)
        if up:
            back.setdefault(up, []).append(landing)
    for a, b in teleports:
        back.setdefault(b, []).append(a)
    out = set()
    for t in targets:
        if t not in dist:
            continue
        cur = t
        while cur != start and cur not in out:
            out.add(cur)
            d = dist[cur]
            prev = None
            for dx, dy in C.D8:
                n = (cur[0] + dx, cur[1] + dy, cur[2])
                if dist.get(n) == d - 1:
                    prev = n
                    break
            if prev is None:
                for n in back.get(cur, []):
                    if dist.get(n) == d - 1:
                        prev = n
                        break
            if prev is None:
                break
            cur = prev
        out.add(start)
    return out


def check_kits(items_otb, items_xml, dat, log=print):
    """every kit id against the live items and the pair: known, a sprite, blocking as the kit says, light where the
    group says, not pickupable; the stair brush floor changes, the roof is a ground"""
    import re, sys
    sys.path.insert(0, os.path.join(C.ROOT, 'tools', 'map'))
    from itemdb import ItemDB
    db = ItemDB(items_otb, items_xml, dat)
    xml = open(items_xml, encoding='latin-1').read()

    def floorchange(i):
        m = re.search(r'<item id="%d"[^>]*>(.*?)</item>' % i, xml, re.S)
        if m:
            return re.search(r'key="floorchange" value="(\w+)"', m.group(1))
        for m in re.finditer(r'<item fromid="(\d+)" toid="(\d+)"[^>]*>(.*?)</item>', xml, re.S):
            if int(m.group(1)) <= i <= int(m.group(2)):
                return re.search(r'key="floorchange" value="(\w+)"', m.group(3))
        return None
    bad = 0
    things = db.dat.items
    k = kits()
    for name, g in sorted(k['groups'].items()):
        for i in g['ids']:
            why = []
            c = int(db.cid[i]) if db.known[i] else 0
            if not c or c - 100 >= len(things):
                why.append('no client sprite')
            else:
                f = things[c - 100].flags
                block = bool(int(db.flags[i]) & 1 or 'notwalkable' in f)
                if block != g['block']:
                    why.append('blocks' if block else 'does not block')
                if g['light'] and not f.get('light', (0, 0))[0] and not any(
                        things[int(db.cid[j]) - 100].flags.get('light', (0, 0))[0] for j in g['ids'] if j != i):
                    why.append('gives no light')
                if 'pickupable' in f:
                    why.append('pickupable')
            if why:
                bad += 1
                log('%6d %-22s BAD: %s' % (i, name, '; '.join(why)))
    b = k['brushes']
    fc = floorchange(b['stairs_down_ground'])
    if not fc or fc.group(1) != 'down':
        bad += 1
        log('%6d stairs ground BAD: no floorchange down' % b['stairs_down_ground'])
    fc = floorchange(b['stairs_up'])
    if not fc or fc.group(1) != 'north':
        bad += 1
        log('%6d stone stairs BAD: no floorchange north' % b['stairs_up'])
    for i in k['roof']['ground']:
        if not (db.group[i] == 1 or 'ground' in things[int(db.cid[i]) - 100].flags):
            bad += 1
            log('%6d roof BAD: not a ground' % i)
    n = sum(len(g['ids']) for g in k['groups'].values())
    log('%d kit ids in %d groups, %d problem(s)' % (n, len(k['groups']), bad))
    return bad == 0
