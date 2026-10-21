#!/usr/bin/env python3
"""Where the Haunted Harvest's mechanics and set pieces stand: data/scripts/chaos/harvest_places.lua.

usage: python3 -I server/tools/gen_harvest_places.py [--check]

The two event plans (server/tools/areaplan/events/haunted_harvest.json and harvest_catacombs.json) are compiled here
exactly as install_content_areas.py compiles them (area_plan_compile.compile_plan: same seed, same tiles), and the
places are chosen on the compiled tiles, so harvest_event.lua can put the kit's items there at startup
(server/README.md "Haunted Harvest"):
  mechanics  pumpkin patches (pumpkin_fields, west_furrows), graves (graveyard; four in the King's Crypt for the boss's
             ritual phase), the crypt seal (2x2, in the ruined chapel), upright coffins (coffin_gallery), candy
             cauldrons (hamlet), the cursed bell (gibbet_hill), the ritual circle (3x3, centred on the planned
             teleport of the ritual chamber, which the event removes) and their landings;
  set pieces the corn maze (corn walls on a 3-tile grid in corn_maze: a perfect maze, opened again wherever it cut a
             tile off), the ruined chapel's crypt stone walls, the graveyard's iron fence, three clapboard huts and a
             barn in the hamlet, haystacks, carts, scarecrows, giant pumpkins, trees, gibbets, jack-o'-lanterns, crypts,
             altars and candles. Ids are the kit's server ids (data/items/pack33_kit.csv).
Rules: only on walkable tiles (the planner's flat decoration may lie under a piece), never on a spawn point, the NPC,
the arrival, a portal or a teleport landing (and one tile around them); a blocking piece never on the shortest walk
from the arrival to a zone, spawn, portal or teleport (but the corn maze's walls: they make walks of their own) and only
where its walkable neighbours stay joined; a mechanic counts as blocking (its grown or closed state blocks).
Afterwards every tile the arrival reached before is still reached with every blocking piece and mechanic in place
(the script stops otherwise).
The plans are compiled as with ChaosHarvestArt.PAIR33 on (the kit's decoration overlay merged), whatever the switch
says now: the places are used only then. The output depends on the plans, the kit and the overlay: after changing
one, run this again (CI runs --check). Python 3, standard library; luajit or lua5.3 for the area generator.
"""
import json, os, random, sys
from collections import deque

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import area_plan_compile as PC  # noqa: E402
import install_pack33_items as KIT  # noqa: E402

EVENTS = os.path.join(HERE, 'areaplan', 'events')
SURFACE, CRYPT = 'haunted_harvest', 'harvest_catacombs'
OUT = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'harvest_places.lua')
D8 = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]
D4 = [(0, -1), (1, 0), (0, 1), (-1, 0)]


class PlaceError(Exception):
    pass


def kit_ids():
    return {r['key']: r['server_id'] for r in KIT.load_rows()}


def switch_on_decor():
    """compile as with ChaosHarvestArt.PAIR33 on: the places are used only then, and the kit's decoration overlay
    (areaplan/decor_pack33_kit.json) is merged only then, so the places must match that compile whatever the switch
    says now"""
    import area_plan_decor as D
    if not getattr(D, '_harvest_forced', False):
        D.harvest_on = lambda path=None: True
        D._kits = None
        D._harvest_forced = True


def compile_event(pid):
    switch_on_decor()
    plan = json.load(open(os.path.join(EVENTS, pid + '.json'), encoding='utf-8'))
    r = PC.compile_plan(plan)
    errs = PC.qa_errors(r)
    if errs:
        raise PlaceError('%s: the compiled plan has QA errors: %s' % (pid, errs[0]))
    return plan, r


class Area:
    """the compiled tiles of one plan and what may go where"""

    def __init__(self, r, rng):
        self.r, self.rng = r, rng
        self.walk = set(r['walk'])
        self.tiles = r['tiles']
        self.arrival = tuple(r['arrival'])
        self.zrect = r['zrect']
        self.blocked = set()      # tiles a placed blocking piece (or a mechanic) takes
        self.used = set()         # tiles anything of ours takes
        self.out = []             # (category, entry)
        guard = {self.arrival}
        ex = r['exit'] or {}
        if ex.get('at'):
            guard.add(tuple(ex['at']))
        for s in r['spawns']:
            guard.add((s['x'], s['y'], s['z']))
        for n in r['npcs']:
            guard.add((n['x'], n['y'], n['z']))
        if r['boss']:
            b = r['boss']
            guard.add((b['x'], b['y'], b['z']))
        for t in r['teleports']:
            guard.add(tuple(t['at']))
            guard.add(tuple(t['to']))
        self.points = set(guard)
        self.guard = set()
        for (x, y, z) in guard:
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    self.guard.add((x + dx, y + dy, z))
        self.lanes = self._lanes()
        self.reach0 = self.reach(set())

    def free(self, t):
        """walkable (the planner's flat decoration may lie on it), not guarded, not ours yet"""
        return t in self.walk and t in self.tiles and t not in self.guard and t not in self.used

    def bfs(self, blocked, start=None):
        start = start or self.arrival
        seen = {start: None}
        q = deque([start])
        while q:
            c = q.popleft()
            for dx, dy in D8:
                n = (c[0] + dx, c[1] + dy, c[2])
                if n in self.walk and n not in blocked and n not in seen:
                    seen[n] = c
                    q.append(n)
        return seen

    def reach(self, blocked):
        return set(self.bfs(blocked))

    def _lanes(self):
        par = self.bfs(set())
        targets = set(self.points)
        for zid, (x1, y1, x2, y2, z) in self.zrect.items():
            cx, cy = (x1 + x2) // 2, (y1 + y2) // 2
            best = min((t for t in self.walk if t[2] == z and x1 <= t[0] <= x2 and y1 <= t[1] <= y2),
                       key=lambda t: (abs(t[0] - cx) + abs(t[1] - cy), t), default=None)
            if best:
                targets.add(best)
        lanes = set()
        for t in targets:
            while t is not None and t in par:
                lanes.add(t)
                t = par[t]
        return lanes

    def simple(self, t):
        """blocking t keeps its walkable neighbours joined (around the ring of 8)"""
        ring = [(t[0] + dx, t[1] + dy, t[2]) for dx, dy in ((-1, -1), (0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0))]
        open_ = [n in self.walk and n not in self.blocked for n in ring]
        if not any(open_):
            return False
        runs = sum(1 for i in range(8) if open_[i] and not open_[i - 1])
        return runs <= 1 or all(open_)

    def can_block(self, t):
        return self.free(t) and t not in self.lanes and self.simple(t)

    def zone_tiles(self, zid, inset=0):
        x1, y1, x2, y2, z = self.zrect[zid]
        return sorted(t for t in self.walk if t[2] == z and x1 + inset <= t[0] <= x2 - inset and
                      y1 + inset <= t[1] <= y2 - inset)

    def put(self, cat, entry, tiles, block):
        for t in tiles:
            self.used.add(t)
        if block:
            self.blocked.add(tiles[0])
        self.out.append((cat, entry))

    def footprint_ok(self, t, w, h, block):
        """a w x h piece anchored on t (bottom-right): t free (and blockable), the tiles it draws over walkable and
        free of our pieces"""
        if not (self.can_block(t) if block else self.free(t)):
            return False
        for dx in range(w):
            for dy in range(h):
                q = (t[0] - dx, t[1] - dy, t[2])
                if q == t:
                    continue
                if q not in self.walk or q in self.used or q in self.points:
                    return False
        return True

    def scatter(self, cat, zid, n, ids, w=1, h=1, block=True, spacing=2, inset=1, near_wall=False, extra=None):
        cands = self.zone_tiles(zid, inset)
        self.rng.shuffle(cands)
        placed = []
        for t in cands:
            if len(placed) >= n:
                break
            if any(max(abs(t[0] - p[0]), abs(t[1] - p[1])) < spacing for p in placed):
                continue
            if near_wall and all((t[0] + dx, t[1] + dy, t[2]) in self.walk for dx, dy in D4):
                continue
            if not self.footprint_ok(t, w, h, block):
                continue
            iid = ids[len(placed) % len(ids)] if isinstance(ids, list) else ids
            entry = dict(id=iid, x=t[0], y=t[1], z=t[2])
            if extra:
                entry.update(extra(len(placed)))
            fp = [(t[0] - dx, t[1] - dy, t[2]) for dy in range(h) for dx in range(w)]
            self.put(cat, entry, fp, block)
            placed.append(t)
        return placed

    def outline(self, cat, zid, inset, piece, skip=0.0, gap_lanes=True):
        """walls along the zone rect shrunk by `inset`; piece(kind) -> id with kind h, v or post"""
        x1, y1, x2, y2, z = self.zrect[zid]
        x1, y1, x2, y2 = x1 + inset, y1 + inset, x2 - inset, y2 - inset
        ring = []
        for x in range(x1, x2 + 1):
            ring += [(x, y1, z), (x, y2, z)]
        for y in range(y1 + 1, y2):
            ring += [(x1, y, z), (x2, y, z)]
        n = 0
        for t in sorted(set(ring)):
            if self.rng.random() < skip:
                continue
            if not self.can_block(t) or (gap_lanes and t in self.lanes):
                continue
            corner = t[0] in (x1, x2) and t[1] in (y1, y2)
            kind = 'post' if corner else ('h' if t[1] in (y1, y2) else 'v')
            self.put(cat, dict(id=piece(kind), x=t[0], y=t[1], z=t[2]), [t], True)
            n += 1
        return n

    def joined(self):
        after = self.reach(self.blocked)
        return all(t in after or t in self.blocked for t in self.reach0)

    def undo(self, mark):
        """take back every piece placed after out[mark]"""
        for cat, e in self.out[mark:]:
            t = (e['x'], e['y'], e['z'])
            self.blocked.discard(t)
            self.used.discard(t)
        del self.out[mark:]

    def check(self, what):
        after = self.reach(self.blocked)
        lost = [t for t in self.reach0 if t not in after and t not in self.blocked]
        if lost:
            raise PlaceError('%s: %d tile(s) cut off from the arrival, e.g. %s' % (what, len(lost), lost[0]))


def maze(a, zid, K, rng):
    """corn walls on a 3-tile grid over the zone: a perfect maze (randomised depth-first), then opened wherever a tile
    was cut off; returns the number of wall pieces"""
    x1, y1, x2, y2, z = a.zrect[zid]
    cw, ch = (x2 - x1) // 3, (y2 - y1) // 3
    if cw < 2 or ch < 2:
        return 0
    open_walls = set()
    seen = {(0, 0)}
    stack = [(0, 0)]
    while stack:
        c = stack[-1]
        nb = [(c[0] + dx, c[1] + dy) for dx, dy in D4 if 0 <= c[0] + dx < cw and 0 <= c[1] + dy < ch and
              (c[0] + dx, c[1] + dy) not in seen]
        if not nb:
            stack.pop()
            continue
        n = nb[rng.randrange(len(nb))]
        open_walls.add(frozenset((c, n)))
        seen.add(n)
        stack.append(n)
    walls = set()
    for i in range(cw + 1):
        for j in range(ch + 1):
            px, py = x1 + 3 * i, y1 + 3 * j
            walls.add((px, py, z))  # the posts
            if i < cw:  # the horizontal wall between cell (i, j - 1) and (i, j)
                inner = 0 < j < ch
                if not inner or frozenset(((i, j - 1), (i, j))) not in open_walls:
                    walls.update({(px + 1, py, z), (px + 2, py, z)})
            if j < ch:
                inner = 0 < i < cw
                if not inner or frozenset(((i - 1, j), (i, j))) not in open_walls:
                    walls.update({(px, py + 1, z), (px, py + 2, z)})
    walls = {t for t in walls if a.free(t)}
    # open again: wherever the walls cut a tile off from the arrival, drop the wall nearest to the reached part
    while True:
        blocked = a.blocked | walls
        after = a.reach(blocked)
        lost = [t for t in a.reach0 if t not in after and t not in blocked]
        if not lost:
            break
        cand = sorted((w for w in walls if any((w[0] + dx, w[1] + dy, w[2]) in after for dx, dy in D8) and
                       any((w[0] + dx, w[1] + dy, w[2]) in set(lost) for dx, dy in D8)), key=lambda w: (w[1], w[0]))
        if not cand:
            cand = sorted(walls, key=lambda w: min(abs(w[0] - l[0]) + abs(w[1] - l[1]) for l in lost[:50]))
        walls.discard(cand[0])
    n = 0
    for t in sorted(walls, key=lambda t: (t[1], t[0])):
        h = any((t[0] + d, t[1], t[2]) in walls for d in (-1, 1))
        v = any((t[0], t[1] + d, t[2]) in walls for d in (-1, 1))
        key = 'corn_wall_post' if (h and v) or not (h or v) else ('corn_wall_h' if h else 'corn_wall_v')
        a.put('maze', dict(id=K[key], x=t[0], y=t[1], z=t[2]), [t], True)
        n += 1
    return n


def wall_piece(K, prefix, broken_rng=None):
    def piece(kind):
        if kind == 'post':
            return K[prefix + '_post']
        if broken_rng and broken_rng.random() < 0.25:
            return K['%s_broken_%s' % (prefix, kind)]
        return K['%s_%s' % (prefix, kind)]
    return piece


def surface(a, K, rng):
    S = K['pumpkin_stage_1_mound']
    stages = [K['pumpkin_stage_%d_%s' % (n, s)] for n, s in ((1, 'mound'), (2, 'sprout'), (3, 'vine'), (4, 'green'), (5, 'ripe'))]
    del S
    # the ruined chapel, the graveyard's fence and the hamlet first (outlines need the open ground)
    a.outline('chapel', 'ruined_chapel', 2, wall_piece(K, 'crypt_stone', rng), skip=0.3)
    seal = a.scatter('seal', 'ruined_chapel', 1, K['seal_sealed'], w=2, h=2, block=True, inset=5, spacing=1)
    if not seal:
        raise PlaceError('no tile for the crypt seal in the ruined chapel')
    a.scatter('chapel', 'ruined_chapel', 1, K['altar_bare'], w=2, h=1, inset=3)
    a.scatter('chapel', 'ruined_chapel', 1, K['spellbook_lectern'], inset=3)
    a.scatter('chapel', 'ruined_chapel', 4, K['black_candles'], inset=3)
    a.scatter('chapel', 'ruined_chapel', 3, K['candles_cluster'], block=False, inset=3)
    a.scatter('chapel', 'ruined_chapel', 2, K['skull_pile'], inset=3)
    a.outline('fence', 'graveyard', 1, lambda k: K['iron_cemetery_post'] if k == 'post' else K['iron_cemetery_' + k],
              skip=0.15)
    graves = a.scatter('grave', 'graveyard', 12, K['grave_mound'], w=1, h=2, inset=3, spacing=3)
    a.scatter('graveyard', 'graveyard', 14, [K['tombstone_round'], K['tombstone_cross'], K['tombstone_cracked'],
                                            K['tombstone_angel']], inset=2, spacing=2)
    a.scatter('graveyard', 'graveyard', 2, K['crypt_small'], w=2, h=2, inset=3, spacing=4)
    a.scatter('graveyard', 'graveyard', 2, K['open_grave'], w=1, h=2, block=False, inset=3)
    a.scatter('graveyard', 'graveyard', 3, K['lantern_post'], inset=2, spacing=6)
    # the hamlet: a barn and three huts (outlines of 6 x 5 and 5 x 4, a door gap in the south wall), cauldrons, the witches' things
    huts = 0
    for (w, h, prefix) in ((6, 5, 'barn_planks'), (5, 4, 'clapboard'), (5, 4, 'clapboard'), (5, 4, 'clapboard')):
        x1, y1, x2, y2, z = a.zrect['hamlet']
        spots = [(x, y) for x in range(x1, x2 - w + 2) for y in range(y1, y2 - h + 2)]
        rng.shuffle(spots)
        for (x, y) in spots:
            box = [(xx, yy, z) for xx in range(x, x + w) for yy in range(y, y + h)]
            if not all(t not in a.used and t not in a.points and (t in a.walk or not (t[0] in (x, x + w - 1) or t[1] in (y, y + h - 1))) for t in box):
                continue
            ring = [t for t in box if t[0] in (x, x + w - 1) or t[1] in (y, y + h - 1)]
            door = (x + w // 2, y + h - 1, z)
            pieces = [t for t in ring if t != door]
            if not all(a.free(t) and t not in a.lanes for t in pieces) or not a.free(door):
                continue
            mark = len(a.out)
            for t in pieces:
                corner = t[0] in (x, x + w - 1) and t[1] in (y, y + h - 1)
                kind = 'post' if corner else ('h' if t[1] in (y, y + h - 1) else 'v')
                iid = K['%s_post' % prefix] if kind == 'post' else K['%s_%s' % (prefix, kind)]
                if kind == 'h' and rng.random() < 0.2:
                    iid = K['%s_window_h' % prefix]
                a.put('hamlet', dict(id=iid, x=t[0], y=t[1], z=t[2]), [t], True)
            a.put('hamlet', dict(id=K['%s_door_open_h' % prefix], x=door[0], y=door[1], z=door[2]), [door], False)
            if not a.joined():
                a.undo(mark)
                continue
            huts += 1
            break
    a.scatter('cauldron', 'hamlet', 4, K['candy_cauldron_full'], inset=2, spacing=4)
    a.scatter('hamlet', 'hamlet', 2, K['brew_table'], w=2, h=1, inset=2, spacing=4)
    a.scatter('hamlet', 'hamlet', 2, K['cauldron'], inset=2, spacing=4)
    a.scatter('hamlet', 'hamlet', 3, [K['broom_leaning'], K['candy_pile'], K['well_old']], inset=2, spacing=4)
    a.scatter('hamlet', 'hamlet', 2, K['witch_hat'], block=False, inset=2)
    a.scatter('hamlet', 'hamlet', 4, K['jack_lantern_grin'], inset=1, spacing=5)
    # the fields: pumpkin patches (mechanics, any stage), the harvest set pieces
    for zid, n in (('pumpkin_fields', 22), ('west_furrows', 14)):
        a.scatter('pumpkin', zid, n, stages, inset=1, spacing=2,
                  extra=lambda i: dict(stage=1 + (i * 7) % 5))
        a.scatter('fields', zid, 2, K['haystack'], w=2, h=2, inset=2, spacing=5)
        a.scatter('fields', zid, 1, K['pumpkin_giant'], w=2, h=2, inset=2, spacing=5)
        a.scatter('fields', zid, 1, K['pumpkin_cart'], w=2, h=1, inset=2, spacing=5)
        a.scatter('fields', zid, 3, [K['scarecrow_pumpkin'], K['scarecrow']], inset=2, spacing=5)
        a.scatter('fields', zid, 4, [K['jack_lantern_scary'], K['jack_lantern_cute']], inset=1, spacing=5)
        a.scatter('fields', zid, 3, [K['hay_bale_stack'], K['wheelbarrow'], K['apple_barrel']], inset=2, spacing=4)
    # the corn maze
    nmaze = maze(a, 'corn_maze', K, rng)
    a.scatter('maze', 'corn_maze', 3, K['jack_lantern_grin'], inset=2, spacing=6)
    # the dead orchard and the gibbet hill
    a.scatter('orchard', 'dead_orchard', 10, [K['autumn_oak'], K['dead_tree_gnarled']], w=2, h=2, inset=2, spacing=4)
    a.scatter('orchard', 'dead_orchard', 3, K['apple_barrel'], inset=2, spacing=4)
    a.scatter('orchard', 'dead_orchard', 3, K['crows_ground'], w=2, h=1, block=False, inset=2, spacing=5)
    a.scatter('orchard', 'dead_orchard', 3, K['lantern_post'], inset=1, spacing=6)
    bell = a.scatter('bell', 'gibbet_hill', 1, K['cursed_bell_still'], inset=4, spacing=1)
    a.scatter('gibbets', 'gibbet_hill', 5, [K['gibbet_swing'], K['gibbet_bones'], K['gibbet_empty']], inset=2, spacing=3)
    a.scatter('gibbets', 'gibbet_hill', 2, K['bats_flock'], w=2, h=2, block=False, inset=2, spacing=5)
    a.scatter('gibbets', 'gibbet_hill', 2, K['crows_ground'], w=2, h=1, block=False, inset=2, spacing=5)
    a.scatter('gibbets', 'gibbet_hill', 2, K['signpost_crooked'], inset=2, spacing=5)
    # the crossroads (camp): lights only
    a.scatter('crossroads', 'crossroads', 4, K['lantern_post'], inset=1, spacing=4)
    a.check('surface')
    return dict(graves=len(graves), maze=nmaze, huts=huts, bell=len(bell))


def catacombs(a, K, rng):
    coffins = a.scatter('coffin', 'coffin_gallery', 8, K['coffin_up_closed'], inset=0, spacing=3, near_wall=True)
    a.scatter('crypt', 'coffin_gallery', 2, K['sarcophagus_closed'], w=1, h=2, inset=2, spacing=4)
    a.scatter('crypt', 'candle_vault', 6, K['black_candles'], inset=1, spacing=3)
    a.scatter('crypt', 'candle_vault', 1, K['necromancer_altar'], w=2, h=1, inset=3, spacing=3)
    a.scatter('crypt', 'ossuary_hall', 3, K['bone_pile_large'], w=2, h=2, inset=3, spacing=5)
    a.scatter('crypt', 'bone_pits', 3, K['bone_pile_large'], w=2, h=2, inset=3, spacing=5)
    a.scatter('crypt', 'bone_pits', 4, K['skull_pile'], inset=2, spacing=4)
    king = a.scatter('kinggrave', 'kings_crypt', 4, K['grave_mound'], w=1, h=2, inset=3, spacing=5)
    a.scatter('crypt', 'kings_crypt', 4, K['black_candles'], inset=2, spacing=4)
    # the ritual circle: 3 x 3, centred on the planned teleport of the ritual chamber (its anchor is the south-east tile)
    rz = a.zrect['ritual_chamber']
    tele = [t for t in a.r['teleports'] if rz[0] <= t['at'][0] <= rz[2] and rz[1] <= t['at'][1] <= rz[3]]
    if len(tele) != 1:
        raise PlaceError('the ritual chamber has %d planned teleports, 1 expected' % len(tele))
    tx, ty, tz = tele[0]['at']
    circle = [(tx + dx, ty + dy, tz) for dy in (-1, 0, 1) for dx in (-1, 0, 1)]
    if not all(t in a.walk for t in circle):
        raise PlaceError('the ritual circle around %s is not all walkable floor' % (tele[0]['at'],))
    a.check('catacombs')
    return dict(coffins=len(coffins), kingGraves=len(king), circle=dict(anchor=(tx + 1, ty + 1, tz), tiles=circle,
                                                                          teleport=(tx, ty, tz), landing=tuple(tele[0]['to'])))


def lua_pos(t):
    return '{x = %d, y = %d, z = %d}' % tuple(t)


def lua_text(sa, ca, info, K):
    L = ['-- Where the Haunted Harvest\'s mechanics and set pieces stand (server/tools/gen_harvest_places.py, from the two',
         '-- compiled plans of server/tools/areaplan/events/). Generated; do not edit by hand. harvest_event.lua puts the',
         '-- items on these tiles at startup (only while ChaosHarvestArt.PAIR33 is on and the areas are on the map).',
         '-- Ids are server ids of the pair 33 kit (data/lib/chaos_pack33_kit.lua).', '', 'return {']
    for name, a in (('surface', sa), ('catacombs', ca)):
        r = a.r
        L.append('\t%s = {plan = "%s", origin = %s, arrival = %s, exit = %s},' % (
            name, r['manifest']['id'], lua_pos(r['origin']), lua_pos(r['arrival']), lua_pos(r['exit']['at'])))
    seal = [e for c, e in sa.out if c == 'seal'][0]
    st = (seal['x'], seal['y'], seal['z'])
    L.append('\t-- the crypt seal (2 x 2, anchor = its south-east tile): the step on any of its tiles while it is open')
    L.append('\tseal = {anchor = %s, tiles = {%s}},' % (lua_pos(st), ', '.join(
        lua_pos((st[0] - dx, st[1] - dy, st[2])) for dy in (1, 0) for dx in (1, 0))))
    c = info['circle']
    L.append('\t-- the ritual circle (3 x 3) over the planned teleport of the ritual chamber, and where its portal leads')
    L.append('\tcircle = {anchor = %s, teleport = %s, landing = %s, tiles = {%s}},' % (
        lua_pos(c['anchor']), lua_pos(c['teleport']), lua_pos(c['landing']), ', '.join(lua_pos(t) for t in c['tiles'])))
    for key, cat, a in (('pumpkins', 'pumpkin', sa), ('graves', 'grave', sa), ('cauldrons', 'cauldron', sa),
                        ('bells', 'bell', sa), ('coffins', 'coffin', ca), ('kingGraves', 'kinggrave', ca)):
        rows = [e for cc, e in a.out if cc == cat]
        L.append('\t%s = {' % key)
        for e in rows:
            L.append('\t\t{x = %d, y = %d, z = %d%s},' % (e['x'], e['y'], e['z'], ', stage = %d' % e['stage'] if 'stage' in e else ''))
        L.append('\t},')
    L.append('\t-- set pieces: {id, x, y, z}')
    L.append('\tdecor = {')
    for a in (sa, ca):
        for cc, e in a.out:
            if cc in ('seal', 'pumpkin', 'grave', 'cauldron', 'bell', 'coffin', 'kinggrave'):
                continue
            L.append('\t\t{%d, %d, %d, %d}, -- %s' % (e['id'], e['x'], e['y'], e['z'], cc))
    L += ['\t}', '}', '']
    return '\n'.join(L)


def build():
    K = kit_ids()
    _p1, r1 = compile_event(SURFACE)
    _p2, r2 = compile_event(CRYPT)
    sa = Area(r1, random.Random(33201))
    ca = Area(r2, random.Random(33202))
    info = surface(sa, K, sa.rng)
    info.update(catacombs(ca, K, ca.rng))
    return lua_text(sa, ca, info, K), info, sa, ca


def main():
    check = '--check' in sys.argv[1:]
    try:
        text, info, sa, ca = build()
    except (PlaceError, PC.CompileError) as e:
        print('refused: %s' % e)
        return 1
    if check:
        if not os.path.isfile(OUT) or open(OUT, encoding='utf-8').read() != text:
            print('%s is stale: run server/tools/gen_harvest_places.py' % OUT)
            return 1
        print('harvest_places.lua up to date')
        return 0
    open(OUT, 'w', encoding='utf-8', newline='').write(text)
    print('wrote %s (%d surface and %d catacomb pieces; %s)' % (OUT, len(sa.out), len(ca.out), json.dumps(
        {k: v for k, v in info.items() if k != 'circle'})))
    return 0


if __name__ == '__main__':
    sys.exit(main())
