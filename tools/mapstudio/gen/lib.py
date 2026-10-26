"""Shared generation steps: noise, mask cleanup, 12-piece edges, trees and decor."""
from __future__ import annotations

N4 = {"n": (0, -1), "e": (1, 0), "s": (0, 1), "w": (-1, 0)}
DIAG = {"nw": (-1, -1), "ne": (1, -1), "sw": (-1, 1), "se": (1, 1)}


def noise(size, cell, rng):
    """Smooth value noise in [0, 1]: random lattice every `cell` tiles, bilinear with smoothstep."""
    n = size // cell + 2
    lat = [[rng.random() for _ in range(n)] for _ in range(n)]
    out = [[0.0] * size for _ in range(size)]
    for y in range(size):
        for x in range(size):
            gx, gy = x / cell, y / cell
            ix, iy = int(gx), int(gy)
            fx, fy = gx - ix, gy - iy
            fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
            a = lat[iy][ix] + (lat[iy][ix + 1] - lat[iy][ix]) * fx
            b = lat[iy + 1][ix] + (lat[iy + 1][ix + 1] - lat[iy + 1][ix]) * fx
            out[y][x] = a + (b - a) * fy
    return out


def weighted(rng, table):
    ids = list(table)
    return int(rng.choices(ids, [table[i] for i in ids])[0])


def footprint(obj):
    g = obj["groups"][0]
    return g["width"], g["height"]


def pinched(at, x, y):
    """True when the pieces a 12-piece set would draw on outside tile (x, y) face opposite ways: region on two
    opposite sides, or on a side and the far diagonal (N and SE), or on two diagonals with nothing between
    (NE and SW, NE and NW). Such a tile is a strip too thin for the set; on the reference map shores and mountain cliffs
    it never happens (tools/odd_borders.py)."""
    n, e, s, w = at(x, y - 1), at(x + 1, y), at(x, y + 1), at(x - 1, y)
    # edge and inner pieces face their sides; an outer piece faces both letters of its diagonal
    fn, fe, fs, fw = n, e, s, w
    if not n and not w and at(x - 1, y - 1):
        fn = fw = True
    if not n and not e and at(x + 1, y - 1):
        fn = fe = True
    if not s and not w and at(x - 1, y + 1):
        fs = fw = True
    if not s and not e and at(x + 1, y + 1):
        fs = fe = True
    return (fn and fs) or (fe and fw)


def clean(mask, outside=False):
    """Makes a region drawable with a 12-piece set, in place: a tile outside the region whose pieces would face
    opposite ways (pinched: region on opposite sides, or a side and the far diagonal, or two diagonals with a
    gap between) joins it; a region tile with no region on its 4 sides leaves it. `outside` is what lies
    beyond the area's edge."""
    size = len(mask)

    def at(x, y):
        return mask[y][x] if 0 <= x < size and 0 <= y < size else outside

    # only tiles on or beside the outline can change; later sweeps visit just the neighbours of what changed
    todo = {(x, y) for y in range(size) for x in range(size)
            if any(at(x + i, y + j) != mask[y][x] for i in (-1, 0, 1) for j in (-1, 0, 1))}
    budget = 4 * size * size  # a settled shape needs far fewer changes; past this something oscillates
    while todo:
        nxt = set()
        budget -= len(todo)
        if budget < 0:
            raise RuntimeError("clean() did not settle")
        for x, y in sorted(todo, key=lambda t: (t[1], t[0])):
            if mask[y][x]:
                if at(x, y - 1) or at(x + 1, y) or at(x, y + 1) or at(x - 1, y):
                    continue
                mask[y][x] = False
                changed = [(x, y)]
            elif pinched(at, x, y):
                mask[y][x] = True
                changed = [(x, y)]
                if not (at(x, y - 1) or at(x + 1, y) or at(x, y + 1) or at(x - 1, y)):
                    # pinched by diagonals only: joined alone it would be isolated, removed and pinched again
                    # forever; join the side tile toward each diagonal region tile too, so it connects
                    for dx, dy in DIAG.values():
                        cx = x + dx
                        if at(x + dx, y + dy) and 0 <= cx < size:
                            mask[y][cx] = True
                            changed.append((cx, y))
            else:
                continue
            for cx, cy in changed:
                nxt |= {(cx + i, cy + j) for i in (-1, 0, 1) for j in (-1, 0, 1)
                        if 0 <= cx + i < size and 0 <= cy + j < size}
        todo = nxt


def open_shape(mask, allowed=None, block=3):
    """Morphological opening, in place: a tile stays only if it lies in some full block x block square of the
    region. block 3: necks and spurs 1-2 tiles wide go (user review: a hill shaped like a "3", two blobs on a
    one-tile neck), every part 3+ thick keeps its outline. block 2: only 1-wide spits go, so 2-wide outline
    bumps survive. allowed(x, y): tiles that may change. Then cleaned."""
    size = len(mask)
    inside = lambda x, y: 0 <= x < size and 0 <= y < size and mask[y][x]
    offs = range(-1, 2) if block == 3 else range(0, 2)
    core = {(x, y) for y in range(size) for x in range(size)
            if all(inside(x + i, y + j) for i in offs for j in offs)}
    near = range(-1, 2) if block == 3 else range(-1, 1)
    for y in range(size):
        for x in range(size):
            if mask[y][x] and (not allowed or allowed(x, y)) and \
                    not any((x + i, y + j) in core for i in near for j in near):
                mask[y][x] = False
    clean(mask)


def break_runs(mask, rng, allowed=None, outside=False, longest=3, passes=4, mode="both"):
    """No straight outline longer than `longest` tiles (the reference map has almost none of 4+): every longer run of
    outside tiles facing the region on the same side gets, every few tiles, a 1-tile bump of the region
    (grow) or a 2-tile notch into it (shrink); both survive clean(). Edits mask in place."""
    size = len(mask)

    def at(x, y):
        return mask[y][x] if 0 <= x < size and 0 <= y < size else outside

    def ok(x, y):
        return 0 <= x < size and 0 <= y < size and (not allowed or allowed(x, y))

    for _ in range(passes):
        flips = set()
        for d, (dx, dy) in N4.items():
            ax, ay = (1, 0) if dy else (0, 1)  # along the outline
            seen = set()
            for y in range(size):
                for x in range(size):
                    if (x, y) in seen:
                        continue
                    straight = lambda tx, ty: (not at(tx, ty) and at(tx + dx, ty + dy)
                                               and not at(tx - dx, ty - dy))
                    if not straight(x, y) or straight(x - ax, y - ay):
                        continue
                    run = []
                    tx, ty = x, y
                    while straight(tx, ty):
                        run.append((tx, ty))
                        seen.add((tx, ty))
                        tx, ty = tx + ax, ty + ay
                    if len(run) <= longest:
                        continue
                    k = rng.randint(1, longest - 1)
                    while k < len(run) - 1:
                        bx, by = run[k]
                        grow = mode == "grow" or (mode == "both" and rng.random() < 0.5)
                        bump = [(bx, by), (bx + ax, by + ay)]  # 2 wide: a 1-wide bump is too thin for a rim
                        if grow and all(ok(*t) and not at(*t) for t in bump):
                            flips |= set(bump)
                        elif not grow:
                            notch = [(bx + dx, by + dy), (bx + dx + ax, by + dy + ay)]
                            # only where the shape is 4+ thick, so 3+ stay behind the notch: never a neck
                            behind = [(bx + t * dx + a * ax, by + t * dy + a * ay) for t in (2, 3, 4) for a in (0, 1)]
                            if all(ok(*t) for t in notch) and all(at(*t) for t in behind):
                                flips |= set(notch)
                        k += rng.randint(2, longest)
        if not flips:
            break
        before = [row[:] for row in mask]
        for x, y in flips:
            mask[y][x] = not mask[y][x]
        clean(mask, outside)
        if allowed:  # cleaning may reach past the allowed tiles (user review: sand pushed into the sea)
            for y in range(size):
                for x in range(size):
                    if mask[y][x] != before[y][x] and not allowed(x, y):
                        mask[y][x] = before[y][x]


def roughen(mask, rng, p=0.45, allowed=None, outside=False, passes=0, mode="both"):
    """The reference map's staircase outlines (tools/outline_study.py: about a third each edge, inner and outer corner
    pieces, almost never 4+ equal edge pieces in a row). break_runs alone matches that best
    (tools/shape_lab.py: 0.32 / 0.33 / 0.36, no long runs); `passes` random flip passes (p per outline tile)
    can come first for extra wobble. Shapes are cleaned so they stay drawable with a 12-piece set. mode: both,
    grow (only add tiles) or shrink (only remove). allowed(x, y): where the mask may change; elsewhere the
    original value is kept. Edits mask in place."""
    size = len(mask)
    original = [row[:] for row in mask]

    def at(x, y):
        return mask[y][x] if 0 <= x < size and 0 <= y < size else outside

    for _ in range(passes):
        flips = []
        for y in range(size):
            for x in range(size):
                v = mask[y][x]
                if (mode == "grow" and v) or (mode == "shrink" and not v):
                    continue
                if allowed and not allowed(x, y):
                    continue
                if any(at(x + dx, y + dy) != v for dx, dy in N4.values()) and rng.random() < p:
                    flips.append((x, y))
        for x, y in flips:
            mask[y][x] = not mask[y][x]
        clean(mask, outside)
        if allowed:
            for y in range(size):
                for x in range(size):
                    if not allowed(x, y):
                        mask[y][x] = original[y][x]
    break_runs(mask, rng, allowed, outside, mode=mode)


def edge_pieces(mask, x, y, pieces, outside=False):
    """Pieces of a 12-piece set on tile (x, y), which lies outside the region `mask` (naming checked on the reference map
    refs with tools/piece_check.py, same for borders, shores and cliffs): edge_<d> for a region side,
    inner_<dd> where two adjacent sides are region, outer_<dd> where only that diagonal is."""
    size = len(mask)

    def at(dx, dy):
        nx, ny = x + dx, y + dy
        return mask[ny][nx] if 0 <= nx < size and 0 <= ny < size else outside

    side = {k: at(*d) for k, d in N4.items()}
    out = []
    for a, c in (("n", "w"), ("n", "e"), ("s", "w"), ("s", "e")):
        if side[a] and side[c]:
            out.append(pieces["inner_" + a + c])
            side[a + c] = True
    for k in "nesw":
        covered = any(side.get(k + c) or side.get(c + k) for c in "nesw")
        if side[k] and not covered:
            out.append(pieces["edge_" + k])
    for k, d in DIAG.items():
        if at(*d) and not side[k[0]] and not side[k[1]]:
            out.append(pieces["outer_" + k])
    return out


def touches(mask, x, y, reach=1):
    size = len(mask)
    return any(mask[y + j][x + i] for j in range(-reach, reach + 1) for i in range(-reach, reach + 1)
               if 0 <= x + i < size and 0 <= y + j < size)


def place_trees(size, ok, table, items, rng, field):
    """Dense clumps where `field` is high (bases 2 tiles apart, canopies overlapping), lone trees with a 1-tile
    gap elsewhere. Every footprint tile must pass ok(x, y); footprints never overlap; a tree never takes the
    species of a tree within 4 tiles if another species fits. Returns ({(x, y): id}, taken tiles)."""
    taken = set()
    trees = {}
    cells = [(x, y) for y in range(size) for x in range(size)]
    rng.shuffle(cells)
    for x, y in cells:
        f = field[y][x]
        dense = f > 0.56
        if rng.random() > (0.9 if dense else 0.45 if f > 0.48 else 0.025):
            continue
        near = {t for (tx, ty), t in trees.items() if abs(tx - x) <= 4 and abs(ty - y) <= 4}
        choices = {k: v for k, v in table.items() if int(k) not in near} or table
        tree = weighted(rng, choices)
        w, h = footprint(items[tree])
        # the item stands on its bottom-right tile and covers w x h up-left
        area = {(x - dx, y - dy) for dx in range(w) for dy in range(h)}
        if not all(0 <= ax < size and 0 <= ay < size and ok(ax, ay) for ax, ay in area):
            continue
        if dense:
            # inside a clump canopies overlap: only the tree's own tile and its 4 neighbours stay free
            if any((x + i, y + j) in trees or (x + i, y + j) in taken
                   for i, j in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1))):
                continue
        else:
            halo = {(ax + i, ay + j) for ax, ay in area for i in (-1, 0, 1) for j in (-1, 0, 1)}
            if halo & taken:
                continue
        taken |= {(x, y)} if dense else area
        trees[(x, y)] = tree
    return trees, taken


def place_flora(size, family_at, tables, items, rng, ok, scale=None):
    """Plants and trees by the ground family under them, at learned per-tile rates: tables = {family: {id: rate}}.
    Each tile rolls its family's items in order and takes the first hit that fits. A multi-tile item stands on its
    bottom-right tile and needs ok() on every footprint tile; bases may sit side by side and canopies overlap,
    as on the reference map (lush jungle grass has palm bases on 18% of its tiles). No item has an equal id on its 8
    neighbours. scale(x, y), when given, multiplies the tile's rates (edge density). Returns {(x, y): id}."""
    flora = {}
    cells = [(x, y) for y in range(size) for x in range(size)]
    rng.shuffle(cells)
    for x, y in cells:
        if not ok(x, y) or (x, y) in flora:
            continue
        table = tables.get(family_at(x, y))
        if not table:
            continue
        mult = scale(x, y) if scale else 1.0
        for key, rate in table.items():
            if rng.random() >= rate * mult:
                continue
            item = int(key)
            if any(flora.get((x + i, y + j)) == item for i in (-1, 0, 1) for j in (-1, 0, 1)):
                continue
            w, h = footprint(items[item])
            area = [(x - dx, y - dy) for dx in range(w) for dy in range(h)]
            if not all(0 <= ax < size and 0 <= ay < size and ok(ax, ay) for ax, ay in area):
                continue
            flora[(x, y)] = item
            break
    return flora


def rank_field(size, field, ok):
    """field values over the tiles where ok(), replaced by their rank in [0, 1) (a uniform field)."""
    cells = sorted(((field[y][x], x, y) for y in range(size) for x in range(size) if ok(x, y)))
    out = [[0.0] * size for _ in range(size)]
    for k, (_, x, y) in enumerate(cells):
        out[y][x] = k / max(1, len(cells))
    return out


LANE_DIRS = [(i, j) for i in (-1, 0, 1) for j in (-1, 0, 1) if i or j]


def leaves_gap(x, y, blocked):
    """True when a blocker at (x, y) would leave a 1- or 2-tile walkable gap to another blocker in one of the 8
    directions (blocked(x, y) says what blocks). The reference map's blocking plants touch or stand 3+ apart
    (tools/path_study.py), so lanes between them stay walkable."""
    for dx, dy in LANE_DIRS:
        if blocked(x + dx, y + dy):
            continue
        for m in (1, 2):
            if blocked(x + m * dx, y + m * dy):
                break
            if blocked(x + (m + 1) * dx, y + (m + 1) * dy):
                return True
    return False


def place_clumped(size, u, quantiles, bucket_at, tables, items, rng, ok_base, ok_canopy, boost=1.0,
                  static_block=None, blocking=(), lanes=False, walk_only=()):
    """Plants placed so their local density follows a measured distribution (tools/clump_study.py).
    u: uniform field (rank_field of smooth noise), so neighbouring tiles get similar targets and plants clump.
    quantiles[cls][bucket]: 21 density quantiles; a tile's target density = that quantile function at u, and
    its chance to hold a base = target * boost. tables[cls]: {id: weight}. Big plants go first; a base needs
    ok_base, its footprint tiles (up-left of the base) ok_canopy, so canopies may overhang roads, shores and
    cliff feet as on the reference map. No item has an equal id on its 8 neighbours. walk_only: tiles (route corridors)
    that take only walkable items. With lanes, a blocking plant may not leave a 1-2 tile gap (leaves_gap) to
    another blocking base (this call's, or `blocking`) or to a tile where static_block(x, y); a walkable item
    is tried instead (off by default: it thinned groves too much; route corridors keep paths open).
    Returns {(x, y): id}."""
    walk_only = set(walk_only)
    placed = {}
    blocks = lambda i: "not_walkable" in items[int(i)]["flags"]
    hard = set(blocking)
    is_blocked = lambda bx, by: (bx, by) in hard or (static_block is not None and static_block(bx, by))
    cells = [(x, y) for y in range(size) for x in range(size)]
    for cls in ("big", "small"):
        table = tables.get(cls)
        if not table:
            continue
        rng.shuffle(cells)
        for x, y in cells:
            if (x, y) in placed or not ok_base(x, y):
                continue
            b = bucket_at(x, y)
            if b is None:
                continue
            have = quantiles[cls]
            # a study window may lack a distance band (no ground that far from an edge): use the nearest one
            qs = have.get(str(b)) or have[min(have, key=lambda k: abs(int(k) - b))]
            pos = u[y][x] * 20
            k = min(int(pos), 19)
            target = qs[k] + (qs[k + 1] - qs[k]) * (pos - k)
            if rng.random() >= target * (boost[cls] if isinstance(boost, dict) else boost):
                continue
            options = dict(table)
            gap = None
            for _ in range(4):
                if not options:
                    break
                item = weighted(rng, options)
                options.pop(str(item), None)
                if any(placed.get((x + i, y + j)) == item for i in (-1, 0, 1) for j in (-1, 0, 1)):
                    continue
                if blocks(item):
                    if gap is None:
                        gap = (x, y) in walk_only or (lanes and leaves_gap(x, y, is_blocked))
                    if gap:  # keep the lane: only walkable items here
                        options = {k: v for k, v in options.items() if not blocks(k)}
                        continue
                w, h = footprint(items[item])
                if not all(0 <= x - dx < size and 0 <= y - dy < size and ok_canopy(x - dx, y - dy)
                           for dx in range(w) for dy in range(h)):
                    continue
                placed[(x, y)] = item
                if blocks(item):
                    hard.add((x, y))
                break
    return placed


def route_corridors(size, walk, points, extra=(), width=1):
    """Walking routes on one floor and the corridor around them: every point is joined to the nearest point
    already joined (a tree, like the roads), along the cheapest 8-neighbour path over walk(x, y) tiles that
    keeps off the edges (a tile beside a non-walk tile costs 4 more). `extra` points join the tree too.
    Returns the corridor: route tiles and those within `width` of them (Chebyshev) that are walk tiles."""
    import heapq
    pts = [p for p in [*points, *extra] if 0 <= p[0] < size and 0 <= p[1] < size and walk(*p)]
    if len(pts) < 2:
        return set()
    near_edge = lambda x, y: any(not (0 <= x + i < size and 0 <= y + j < size and walk(x + i, y + j))
                                 for i in (-1, 0, 1) for j in (-1, 0, 1))
    joined, route = {pts[0]}, {pts[0]}
    for goal in pts[1:]:
        if goal in route:
            continue
        best, prev, queue, end = {goal: 0.0}, {}, [(0.0, goal)], None
        while queue:
            d, cur = heapq.heappop(queue)
            if cur in route:
                end = cur
                break
            if d > best.get(cur, 1e18):
                continue
            for i, j in LANE_DIRS:
                n = (cur[0] + i, cur[1] + j)
                if not (0 <= n[0] < size and 0 <= n[1] < size) or not walk(*n):
                    continue
                nd = d + (1.41 if i and j else 1.0) + (4 if near_edge(*n) else 0)
                if nd < best.get(n, 1e18):
                    best[n], prev[n] = nd, cur
                    heapq.heappush(queue, (nd, n))
        if end is None:  # not on the same walkable part: it starts a route of its own
            route.add(goal)
            continue
        t = end
        while t != goal:
            route.add(t)
            t = prev[t]
        route.add(goal)
    return {(x + i, y + j) for x, y in route for i in range(-width, width + 1) for j in range(-width, width + 1)
            if 0 <= x + i < size and 0 <= y + j < size and walk(x + i, y + j)}


def place_decor(size, ok, kit, items, trees, taken, rng):
    """Tufts across open ground; bushes, ferns and plants mostly near trees; no two equal decor ids touching."""
    decor = {}
    for y in range(size):
        for x in range(size):
            if not ok(x, y) or (x, y) in taken:
                continue
            near_tree = any(abs(tx - x) <= 3 and abs(ty - y) <= 3 for tx, ty in trees)
            r = rng.random()
            if r < (0.08 if near_tree else 0.025):
                table = kit["decor"]
            elif r < 0.22:
                table = kit["tufts"]
            else:
                continue
            around = {decor.get((x + i, y + j)) for i in (-1, 0, 1) for j in (-1, 0, 1)}
            options = {k: v for k, v in table.items() if int(k) not in around}
            if not options:
                continue
            item = weighted(rng, options)
            w, h = footprint(items[item])
            area = {(x - dx, y - dy) for dx in range(w) for dy in range(h)}
            if not all(0 <= ax < size and 0 <= ay < size and ok(ax, ay) and (ax, ay) not in taken for ax, ay in area):
                continue
            if w * h > 1:
                taken |= area
            decor[(x, y)] = item
    return decor
