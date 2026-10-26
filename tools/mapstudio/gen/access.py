"""Walkability over all floors of a generated area, and the repair that keeps every ramp usable.

A tile is walkable when its stack starts with a walkable ground and holds no blocking item (item flags:
cliff pieces, fill, water, rails and big plants block; rims, borders and ramps do not). Ramps link floors:
a ramp with floorchange d at (x, y, z) leads to (x + dx, y + dy, z - 1); the way down is taken as the same
link (the reference map's invisible down marker <id> is not placed yet). Movement is 8-directional, as in the client.
"""
from __future__ import annotations

import heapq
from collections import deque

from common import kind_of

DIRS = {"n": (0, -1), "e": (1, 0), "s": (0, 1), "w": (-1, 0)}
STEPS = [(i, j) for i in (-1, 0, 1) for j in (-1, 0, 1) if i or j]


def blocks(items, i):
    o = items.get(int(i))
    return bool(o) and "not_walkable" in o["flags"]


def walkable(items, stack):
    if not stack:
        return False
    g = items.get(int(stack[0]))
    if not g or kind_of(g["flags"]) != "ground" or "not_walkable" in g["flags"]:
        return False
    return not any(blocks(items, i) for i in stack[1:])


def ramp_links(floors, ramp_dirs):
    """{(z, x, y) of a ramp: (z - 1, x', y') it leads onto}."""
    out = {}
    for z, layer in floors.items():
        for (x, y), stack in layer.items():
            for i in stack:
                d = ramp_dirs.get(int(i))
                if d:
                    dx, dy = DIRS[d]
                    out[(z, x, y)] = (z - 1, x + dx, y + dy)
    return out


def reach(floors, items, ramp_dirs, start):
    """All (z, x, y) a player can walk to from start."""
    links = ramp_links(floors, ramp_dirs)
    back = {v: k for k, v in links.items()}
    seen, queue = {start}, deque([start])
    while queue:
        z, x, y = queue.popleft()
        nexts = [(z, x + i, y + j) for i, j in STEPS]
        nexts += [t for t in (links.get((z, x, y)), back.get((z, x, y))) if t]
        for n in nexts:
            if n not in seen and walkable(items, floors.get(n[0], {}).get((n[1], n[2]))):
                seen.add(n)
                queue.append(n)
    return seen


def main_start(floors, items, floor=7):
    """A tile of the largest walkable region on the floor."""
    layer = floors.get(floor, {})
    best, seen = None, set()
    for pos in layer:
        if pos in seen or not walkable(items, layer[pos]):
            continue
        part = reach({floor: layer}, items, {}, (floor, *pos))
        seen |= {(x, y) for _, x, y in part}
        if not best or len(part) > len(best[1]):
            best = (pos, part)
    return (floor, *best[0]) if best else None


def repair(floors, items, ramp_dirs, plants, start):
    """Keeps every ramp reachable from start: where plants cut a ramp end off, clears the plants on the
    cheapest way to it (a plant-blocked tile costs 8 steps). plants: item ids that may be removed.
    Returns (plants removed, ramps still cut off)."""
    links = ramp_links(floors, ramp_dirs)
    back = {v: k for k, v in links.items()}

    def state(n):
        stack = floors.get(n[0], {}).get((n[1], n[2]))
        if walkable(items, stack):
            return 1
        if stack and walkable(items, [i for i in stack if int(i) not in plants]):
            return 8
        return None

    best, prev = {start: 0}, {}
    queue = [(0, start)]
    while queue:
        d, cur = heapq.heappop(queue)
        if d > best[cur]:
            continue
        z, x, y = cur
        nexts = [(z, x + i, y + j) for i, j in STEPS]
        nexts += [t for t in (links.get(cur), back.get(cur)) if t]
        for n in nexts:
            c = state(n)
            if c is not None and d + c < best.get(n, 1e18):
                best[n], prev[n] = d + c, cur
                heapq.heappush(queue, (d + c, n))
    removed, cut = 0, []

    def clear_way(end):
        nonlocal removed
        n = end
        while n != start:
            if state(n) == 8:
                layer = floors[n[0]]
                before = len(layer[(n[1], n[2])])
                layer[(n[1], n[2])] = [i for i in layer[(n[1], n[2])] if int(i) not in plants]
                removed += before - len(layer[(n[1], n[2])])
            n = prev[n]

    for ramp, top in links.items():
        for end in (ramp, top):
            if end not in best:
                cut.append(end)
            else:
                clear_way(end)
    # open areas that only plants wall off: one way in per pocket of 4+ walkable tiles (single tiles shut in
    # by a grove are left, as on the reference map)
    got = reach(floors, items, ramp_dirs, start)
    shut = {n for n in best if n not in got and state(n) == 1}
    seen = set()
    for n in sorted(shut, key=lambda t: best[t]):
        if n in seen:
            continue
        pocket, queue = [n], deque([n])
        seen.add(n)
        while queue:
            z, x, y = queue.popleft()
            for i, j in STEPS:
                nb = (z, x + i, y + j)
                if nb in shut and nb not in seen:
                    seen.add(nb)
                    pocket.append(nb)
                    queue.append(nb)
        if len(pocket) >= 4:
            clear_way(min(pocket, key=lambda t: best[t]))
    return removed, sorted(set(cut))


def open_lanes(floors, items, plants, swap, rng, strict_tops=True):
    """Keeps paths through vegetation open, the way the reference map's blocking plants sit (tools/path_study.py: on
    the reference map 85% of open ground lies in walkable space 9+ wide, 1-2 wide gaps are rare): blocking plants either
    touch another blocker or leave 3+ walkable tiles. A blocking plant (id in `plants`) that leaves a 1- or
    2-tile gap to another blocking plant, in any of the 8 directions, is swapped for a walkable plant of the
    same size (swap: {(w, h): id}), so the look keeps its density. On tops (floors above 7, when strict_tops)
    the gap counts against any blocker, cliffs and the drop included: tops are where tight ledges trap
    paths. Returns how many plants were swapped."""
    swapped = 0
    dirs = [(i, j) for i in (-1, 0, 1) for j in (-1, 0, 1) if i or j]
    for z, layer in floors.items():
        def blocked(t):
            s = layer.get(t)
            return not s or not walkable(items, s)

        def plant_at(t):
            s = layer.get(t)
            return bool(s) and any(int(i) in plants and blocks(items, i) for i in s)

        bases = [t for t in layer if plant_at(t)]
        rng.shuffle(bases)
        for x, y in bases:
            if not plant_at((x, y)):
                continue
            tight = False
            for dx, dy in dirs:
                if blocked((x + dx, y + dy)):
                    continue
                for m in (1, 2):
                    t = (x + (m + 1) * dx, y + (m + 1) * dy)
                    if not blocked((x + m * dx, y + m * dy)):
                        if blocked(t) and (plant_at(t) or (strict_tops and z < 7)):
                            tight = True
                        if blocked(t):
                            break
                    else:
                        break
                if tight:
                    break
            if not tight:
                continue
            stack = layer[(x, y)]
            around = {int(i) for i_ in (-1, 0, 1) for j in (-1, 0, 1) for i in layer.get((x + i_, y + j), [])}
            for k, i in enumerate(stack):
                if int(i) in plants and blocks(items, i):
                    g = items[int(i)]["groups"][0]
                    options = swap.get((g["width"], g["height"])) or swap[(2, 2)]
                    fresh = [o for o in options if o not in around] or options
                    stack[k] = rng.choice(fresh)
                    swapped += 1
                    break
    return swapped


def widths(floors, items):
    """Share of walkable tiles in 1-2 wide space (min of horizontal and vertical walkable run), per floor."""
    out = {}
    for z, layer in floors.items():
        walk = {t for t, s in layer.items() if walkable(items, s)}

        def run(x, y, dx, dy):
            n = 1
            for sgn in (1, -1):
                k = 1
                while (x + sgn * k * dx, y + sgn * k * dy) in walk and n < 3:
                    n, k = n + 1, k + 1
            return n

        narrow = sum(1 for x, y in walk if min(run(x, y, 1, 0), run(x, y, 0, 1)) <= 2)
        out[z] = round(narrow / max(1, len(walk)), 3)
    return out


def report(floors, items, ramp_dirs, start):
    """Counts for the run summary: walkable tiles per floor, reached tiles per floor, ramps usable."""
    got = reach(floors, items, ramp_dirs, start)
    links = ramp_links(floors, ramp_dirs)
    usable = sum(1 for r, t in links.items() if r in got and t in got)
    per = {}
    for z, layer in floors.items():
        w = sum(1 for s in layer.values() if walkable(items, s))
        per[z] = (sum(1 for t in got if t[0] == z), w)
    return {"ramps_usable": f"{usable}/{len(links)}", "reached/walkable": per}
