"""Floating islands (kit key `islands`, round 8): separate landmasses over void, joined only by straight bridges.

The layout dict that comes back has the shape of layout() (the void is the "water" mask, the islands are the land) plus
`bridge_tiles` (the tiles of the bridge strips, land that the generator lays in the kit's bridge ground) and `islands`.

kit islands: {"per_1000": islands per 1000 inner tiles, "radius": [lo, hi] tiles, "gap": void tiles kept between two
 islands, "margin": land stays this far from the area edge (room for the cover rings), "width": {"2": share, "3": share}
 of a bridge strip, "max_len": longest bridge, "loops": [lo, hi] extra bridges beyond the spanning tree, "lake_min":
 an enclosed void pocket smaller than this is filled (no single-tile holes), "bridge_key": ground role of the strips}

Rules the layout keeps (and `stats` reports): every island is joined by at least one bridge and the bridges are the only
way between islands; islands keep `gap` void tiles apart (a bridge is the only land that crosses a gap); a bridge is a
straight strip 2-3 tiles wide, never closer than 2 tiles to a third island; the void has no pocket under `lake_min`
tiles and no 1-tile inlet (lib.clean).
"""
from __future__ import annotations

import math

import lib
from shapes import distance

N4 = ((0, -1), (1, 0), (0, 1), (-1, 0))


def ellipse(cx, cy, rx, ry, field, k, size):
    out = set()
    for y in range(max(0, int(cy - ry * 1.6)), min(size, int(cy + ry * 1.6) + 1)):
        for x in range(max(0, int(cx - rx * 1.6)), min(size, int(cx + rx * 1.6) + 1)):
            d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
            if d < 1 + (field[y][x] - 0.5) * k:
                out.add((x, y))
    return out


def tidy(land, size):
    """No 1-wide spurs and no 1-wide inlets on an island outline; the largest 4-connected piece stays."""
    for _ in range(4):
        changed = False
        for t in sorted(land):
            if sum((t[0] + i, t[1] + j) in land for i, j in N4) < 2:
                land.discard(t)
                changed = True
        cand = {(x + i, y + j) for x, y in land for i, j in N4} - land
        for t in sorted(cand):
            if 0 <= t[0] < size and 0 <= t[1] < size and sum((t[0] + i, t[1] + j) in land for i, j in N4) >= 3:
                land.add(t)
                changed = True
        if not changed:
            break
    seen, best = set(), set()
    for t in sorted(land):
        if t in seen:
            continue
        comp, stack = set(), [t]
        while stack:
            a = stack.pop()
            if a in comp or a not in land:
                continue
            comp.add(a)
            stack += [(a[0] + i, a[1] + j) for i, j in N4]
        seen |= comp
        if len(comp) > len(best):
            best = comp
    return best


def grow(land, n):
    out = set(land)
    for _ in range(n):
        out |= {(x + i, y + j) for x, y in out for i in (-1, 0, 1) for j in (-1, 0, 1)}
    return out


def lines_of(tiles, transpose):
    out = {}
    for x, y in tiles:
        a, b = (y, x) if transpose else (x, y)
        out.setdefault(a, []).append(b)
    return out


def strip(a_tiles, b_tiles, near_other, land, width, max_len, rng, transpose, size):
    """Best straight strip from island A (on the low side) to island B along one axis: {line: (from, to)} of void tiles."""
    ra, rb = lines_of(a_tiles, transpose), lines_of(b_tiles, transpose)
    ok = {}
    for line in ra:
        if line not in rb:
            continue
        ar, bl = max(ra[line]), min(rb[line])
        if bl - ar - 1 < 1 or bl - ar - 1 > max_len:
            continue
        span = range(ar + 1, bl)
        if all(((v, line) if transpose else (line, v)) not in land and ((v, line) if transpose else (line, v)) not in near_other
               for v in span):
            ok[line] = (ar + 1, bl - 1)
    best = []
    for l0 in sorted(ok):
        if all(l0 + k in ok for k in range(width)):
            length = max(ok[l0 + k][1] - ok[l0 + k][0] + 1 for k in range(width))
            best.append((length + rng.random(), {l0 + k: ok[l0 + k] for k in range(width)}))
    if not best:
        return None
    best.sort(key=lambda t: t[0])
    lines = best[0][1]
    return {((v, line) if transpose else (line, v)) for line, (lo, hi) in lines.items() for v in range(lo, hi + 1)}


def pockets(land, size, least):
    """Fills enclosed void pockets under `least` tiles (4-connected void that never reaches the area edge)."""
    seen = set()
    filled = 0
    for y in range(size):
        for x in range(size):
            t = (x, y)
            if t in land or t in seen:
                continue
            comp, stack, edge = set(), [t], False
            while stack:
                a = stack.pop()
                if a in comp:
                    continue
                if not (0 <= a[0] < size and 0 <= a[1] < size):
                    edge = True
                    continue
                if a in land:
                    continue
                comp.add(a)
                stack += [(a[0] + i, a[1] + j) for i, j in N4]
            seen |= comp
            if not edge and len(comp) < least:
                land |= comp
                filled += len(comp)
    return filled


def islands_layout(size, rng, cfg):
    margin = cfg.get("margin", 6)
    gap = cfg.get("gap", 4)
    lo_r, hi_r = cfg.get("radius", [6, 13])
    sizes = cfg.get("sizes")  # round 9: [[weight, lo, hi], ...] radius classes (small, middle, ...); `big` [lo, hi]: one large island
    big = cfg.get("big")
    square = bool(cfg.get("perpendicular"))
    inner = (size - 2 * margin) ** 2
    want = max(3, round(cfg.get("per_1000", 0.9) * inner / 1000))
    field = lib.noise(size, 6, rng)
    land, isl, blocked = set(), [], set()
    for _ in range(600):
        if len(isl) >= want:
            break
        if big and not isl:  # the large island is placed first, while there is room
            rx, ry = rng.uniform(*big), rng.uniform(*big)
        elif sizes:
            _, cl, ch = rng.choices(sizes, [c[0] for c in sizes])[0]
            rx, ry = rng.uniform(cl, ch), rng.uniform(cl, ch)
        else:
            rx, ry = rng.uniform(lo_r, hi_r), rng.uniform(lo_r, hi_r)
        cx = rng.uniform(margin + rx * 0.9, size - 1 - margin - rx * 0.9)
        cy = rng.uniform(margin + ry * 0.9, size - 1 - margin - ry * 0.9)
        t = ellipse(cx, cy, rx, ry, field, 0.9, size)
        if rng.random() < 0.55:  # a second lobe: a bay and a point on the outline
            a = rng.uniform(0, 2 * math.pi)
            t |= ellipse(cx + math.cos(a) * rx * 0.7, cy + math.sin(a) * ry * 0.7, rx * 0.6, ry * 0.6, field, 0.9, size)
        t = tidy(t, size)
        if len(t) < 40 or any(not (margin <= x < size - margin and margin <= y < size - margin) for x, y in t):
            continue
        if t & blocked:
            continue
        isl.append(t)
        blocked |= grow(t, gap)
        land |= t
    # bridges: spanning tree by centre distance, then loops
    centre = [(sum(x for x, _ in t) / len(t), sum(y for _, y in t) / len(t)) for t in isl]
    order = sorted(((math.dist(centre[i], centre[j]), i, j) for i in range(len(isl)) for j in range(i + 1, len(isl))))
    parent = list(range(len(isl)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    widths = cfg.get("width", {"2": 0.6, "3": 0.4})
    max_len = cfg.get("max_len", 18)
    bridges, tiles = [], set()
    loops_left = rng.randint(*cfg.get("loops", [1, 2]))

    def carve(st, i, j):
        """Round 9 (kit islands.perpendicular): island land beside the strip (not at its two ends) is cut away, so the bridge leaves
        and enters straight, never along an island edge. Returns the cut tiles, or None when more than 6 per side would go."""
        xs, ys = {x for x, _ in st}, {y for _, y in st}
        vertical = len(ys) >= len(xs)  # the strip runs along y
        cut = set()
        for x, y in st:
            for d in (-1, 1):
                n = (x + d, y) if vertical else (x, y + d)
                if n not in st and (n in isl[i] or n in isl[j]):
                    cut.add(n)
        return cut if len(cut) <= 12 else None

    def finish(st, i, j):
        if not square:
            return st
        cut = carve(st, i, j)
        if cut is None:
            return None
        isl[i] -= cut
        isl[j] -= cut
        land.difference_update(cut)
        return st

    def try_edge(i, j):
        w = int(rng.choices(list(widths), [widths[k] for k in widths])[0])
        others = set().union(*[t for k, t in enumerate(isl) if k not in (i, j)]) if len(isl) > 2 else set()
        near_other = grow(others, 1) if others else set()
        for first, second in ((i, j), (j, i)):
            for transpose in (False, True):
                s = strip(isl[first], isl[second], near_other, land | tiles, w, max_len, rng, transpose, size)
                if s:
                    s = finish(s, i, j)
                    if s:
                        return s
        if w > 2:
            return try_edge_w(i, j, 2, near_other)
        return None

    def try_edge_w(i, j, w, near_other):
        for first, second in ((i, j), (j, i)):
            for transpose in (False, True):
                s = strip(isl[first], isl[second], near_other, land | tiles, w, max_len, rng, transpose, size)
                if s:
                    s = finish(s, i, j)
                    if s:
                        return s
        return None

    for _, i, j in order:
        joined = find(i) == find(j)
        if joined and (loops_left <= 0 or math.dist(centre[i], centre[j]) > (max(hi_r, big[1] if big else 0) * 3.2)):
            continue
        s = try_edge(i, j)
        if not s:
            continue
        tiles |= s
        bridges.append((i, j, len(s)))
        if joined:
            loops_left -= 1
        else:
            parent[find(i)] = find(j)
    groups = {}
    for i in range(len(isl)):
        groups.setdefault(find(i), []).append(i)
    keep = set(max(groups.values(), key=len))
    land = set()
    for k in keep:
        land |= isl[k]
    kept_bridges = [b for b in bridges if b[0] in keep and b[1] in keep]
    # strip tiles stay when they join a kept island: flood from the kept islands over the strips
    reach, stack = set(), [t for t in tiles if any((t[0] + i, t[1] + j) in land for i, j in N4)]
    while stack:
        a = stack.pop()
        if a in reach or a not in tiles:
            continue
        reach.add(a)
        stack += [(a[0] + i, a[1] + j) for i, j in N4]
    tiles = reach
    land |= tiles
    filled = pockets(land, size, cfg.get("lake_min", 24))
    mask = [[(x, y) not in land for x in range(size)] for y in range(size)]
    lib.clean(mask, outside=True)
    land = {(x, y) for y in range(size) for x in range(size) if not mask[y][x]}
    tiles &= land
    water = mask
    off = [[False] * size for _ in range(size)]
    info = {"islands": len(keep), "dropped": len(isl) - len(keep), "bridges": len(kept_bridges), "bridge_tiles": len(tiles),
            "pockets_filled": filled, "land_share": round(len(land) / (size * size), 3)}
    return {"water": water, "mountain": off, "levels": [], "hill": [row[:] for row in off],
            "shore": distance(size, water), "river": set(), "passes": 0, "sealed": 0,
            "islands": info, "bridge_tiles": tiles, "floor_set": land}
