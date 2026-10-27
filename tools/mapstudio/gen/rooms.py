"""Dungeon mode (kit key `cave.rooms`, round 8): rectangular rooms and cell blocks joined by straight corridors, in place of
the organic chambers of gen/cave.py. Used by gen/generate.py when the kit's cave block has `rooms`; the layout dict that
comes back has the same shape as cave_layout() (the solid rock is the kit's "water" role, the floor is the land) plus
`rooms` (what each rectangle is) so `dress` can give every room its floor and decor.

Layout: nodes (a room, or a cell block = a hall with small cells on one or both long sides, a 1-tile doorway each) are
placed by dart throwing with `gap` free tiles between them, joined by a minimum spanning tree plus a few extra edges.
Every edge is a straight corridor (an L or a Z, 2-3 tiles wide, `corridor` shares) between two rooms; it leaves a room
through a doorway the corridor itself cuts into the wall: the corridor's band sits flush with the room's side or 2+ tiles
in, never 1 tile in, so no wall stub of one tile is left beside a doorway. Walls are laid afterwards from the floor mask
(gen/walls.py), so every outline is made of straight runs with real corners.

cave.rooms: {"per_1000": nodes per 1000 inner tiles, "gap": free tiles between nodes, "corridor": {"2": share, "3": share},
 "loops": [lo, hi], "floor_share": [lo, hi], "kinds": [{"name", "theme", "w": [lo, hi], "h": [lo, hi], "weight"}, or
 {"name": "cellblock", "structure": "cells", "cells": [lo, hi], "cell": [w, h], "hall": 3, "theme": "cell",
  "hall_theme": "hall", "both": 0.7, "weight"}]}
"""
from __future__ import annotations

import math
from collections import deque

from shapes import distance

MARGIN = 7  # solid tiles kept all round the area (wall ring and cover rings stay inside the area)


def rect_tiles(x0, y0, x1, y1):
    return {(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)}


def inflate(r, n):
    return r[0] - n, r[1] - n, r[2] + n, r[3] + n


def overlap(a, b):
    return not (a[2] < b[0] or b[2] < a[0] or a[3] < b[1] or b[3] < a[1])


def pick_weighted(rng, items, key="weight"):
    return rng.choices(items, [it.get(key, 1) for it in items])[0]


class Node:
    """One place on the map: a room (one rectangle) or a cell block (a hall and its cells). `rect` is the bounding
    rectangle of the floor, `main` the rectangle corridors start from, `rooms` every room inside it."""

    def __init__(self, kind, rect, main, rooms, floor, axis=None):
        self.kind, self.rect, self.main, self.rooms, self.floor, self.axis = kind, rect, main, rooms, floor, axis

    @property
    def centre(self):
        r = self.main
        return (r[0] + r[2]) / 2, (r[1] + r[3]) / 2


def make_room(rng, kind, lo, hi, gap, taken):
    """A room of one kind at a random place that keeps `gap` tiles from the nodes in `taken` (rects). Returns a Node or None."""
    w, h = rng.randint(*kind["w"]), rng.randint(*kind["h"])
    for _ in range(40):
        x0, y0 = rng.randint(lo, hi - w + 1), rng.randint(lo, hi - h + 1)
        r = (x0, y0, x0 + w - 1, y0 + h - 1)
        if hi - w + 1 < lo or hi - h + 1 < lo:
            return None
        if any(overlap(inflate(r, gap), t) for t in taken):
            continue
        room = {"rect": r, "kind": kind["name"], "theme": kind["theme"], "main": True}
        return Node(kind["name"], r, r, [room], rect_tiles(*r))
    return None


def make_cells(rng, kind, lo, hi, gap, taken):
    """A cell block: a hall (kind `hall` tiles wide, along x or y) with cells on one or both long sides; each cell shares
    its wall with the hall and with its neighbours and has a 1-tile doorway into the hall."""
    k = rng.randint(*kind["cells"])
    cw, ch = kind["cell"]
    hall = kind.get("hall", 3)
    both = rng.random() < kind.get("both", 0.7)
    horizontal = rng.random() < 0.5
    length = k * (cw + 1) - 1  # along the hall; cell columns are cw wide with a wall tile between
    if horizontal:
        total_w, total_h = length, hall + (ch + 1) * (2 if both else 1)
    else:
        total_w, total_h = hall + (ch + 1) * (2 if both else 1), length
    if hi - total_w + 1 < lo or hi - total_h + 1 < lo:
        return None
    for _ in range(40):
        x0, y0 = rng.randint(lo, hi - total_w + 1), rng.randint(lo, hi - total_h + 1)
        r = (x0, y0, x0 + total_w - 1, y0 + total_h - 1)
        if any(overlap(inflate(r, gap), t) for t in taken):
            continue
        break
    else:
        return None
    # hall position inside the block: cells above (or left) first, then the hall, then cells below (or right)
    side = rng.choice((-1, 1)) if not both else 0  # one-sided block: the cells are on this side
    off = (ch + 1) if (both or side < 0) else 0
    if horizontal:
        hall_rect = (x0, y0 + off, x0 + length - 1, y0 + off + hall - 1)
    else:
        hall_rect = (x0 + off, y0, x0 + off + hall - 1, y0 + length - 1)
    rooms = [{"rect": hall_rect, "kind": "hall", "theme": kind.get("hall_theme", "hall"), "main": True}]
    floor = rect_tiles(*hall_rect)
    sides = ([-1, 1] if both else [side])
    for sd in sides:
        for c in range(k):
            a = c * (cw + 1)
            if horizontal:
                cx0 = x0 + a
                cy0 = hall_rect[1] - 1 - ch if sd < 0 else hall_rect[3] + 2
                cell = (cx0, cy0, cx0 + cw - 1, cy0 + ch - 1)
                door = (cx0 + (cw - 1) // 2, hall_rect[1] - 1 if sd < 0 else hall_rect[3] + 1)
            else:
                cy0 = y0 + a
                cx0 = hall_rect[0] - 1 - ch if sd < 0 else hall_rect[2] + 2
                cell = (cx0, cy0, cx0 + ch - 1, cy0 + cw - 1)
                door = (hall_rect[0] - 1 if sd < 0 else hall_rect[2] + 1, cy0 + (cw - 1) // 2)
            rooms.append({"rect": cell, "kind": "cell", "theme": kind["theme"], "main": False, "door": door})
            floor |= rect_tiles(*cell)
            floor.add(door)
    fx = [t[0] for t in floor]
    fy = [t[1] for t in floor]
    bound = (min(fx), min(fy), max(fx), max(fy))
    return Node("cellblock", bound, hall_rect, rooms, floor, "h" if horizontal else "v")


def bands(r, axis, w, rng):
    """Allowed start coordinates of a corridor band of width w along `axis` ('y': rows, a horizontal corridor; 'x': columns)
    of room rect r: flush with a side or 2+ tiles in from it. Returns a shuffled list."""
    lo, hi = (r[1], r[3]) if axis == "y" else (r[0], r[2])
    out = []
    for s in range(lo, hi - w + 2):
        near, far = s - lo, hi - (s + w - 1)
        if (near == 0 or near >= 2) and (far == 0 or far >= 2):
            out.append(s)
    if not out:
        out = [lo + max(0, (hi - lo + 1 - w) // 2)]
    rng.shuffle(out)
    return out


def edge_width(rng, corridor, a, b):
    """A hall's corridors are as wide as the hall (flush, no jog); other corridors draw from the kit's shares."""
    for nd in (a, b):
        if nd.axis:
            r = nd.main
            return (r[3] - r[1] + 1) if nd.axis == "h" else (r[2] - r[0] + 1)
    return int(rng.choices(list(corridor), [corridor[k] for k in corridor])[0])


def seg_rect(p, q, w):
    return (min(p[0], q[0]), min(p[1], q[1]), max(p[0], q[0]) + w - 1, max(p[1], q[1]) + w - 1)


def routes(rng, a, b, w, lo, hi):
    """Candidate polylines (lists of band-start points) from node a to node b: L and Z shapes."""
    ra, rb = a.main, b.main
    # a hall's corridor runs along its axis at its own width, flush
    ay = bands(ra, "y", w, rng) if a.axis != "h" else [ra[1]]
    ax = bands(ra, "x", w, rng) if a.axis != "v" else [ra[0]]
    by = bands(rb, "y", w, rng) if b.axis != "h" else [rb[1]]
    bx = bands(rb, "x", w, rng) if b.axis != "v" else [rb[0]]
    ca = (int(a.centre[0]) - w // 2, int(a.centre[1]) - w // 2)
    cb = (int(b.centre[0]) - w // 2, int(b.centre[1]) - w // 2)
    out = []
    for i in range(3):
        y1, y2, x1, x2 = ay[i % len(ay)], by[i % len(by)], ax[i % len(ax)], bx[i % len(bx)]
        if a.axis != "v" and b.axis != "h":  # H first: along a row of a, then a column of b
            out.append([(ca[0], y1), (x2, y1), (x2, cb[1])])
        if a.axis != "h" and b.axis != "v":  # V first
            out.append([(x1, ca[1]), (x1, y2), (cb[0], y2)])
        if a.axis != "v" and b.axis != "v":  # H V H
            mx = int((ca[0] + cb[0]) / 2 + rng.randint(-3, 3))
            out.append([(ca[0], y1), (mx, y1), (mx, y2), (cb[0], y2)])
        if a.axis != "h" and b.axis != "h":  # V H V
            my = int((ca[1] + cb[1]) / 2 + rng.randint(-3, 3))
            out.append([(x1, ca[1]), (x1, my), (x2, my), (x2, cb[1])])
    rng.shuffle(out)
    return out


def route_ok(path, w, own, nodes, lo, hi, placed=()):
    rects = [seg_rect(p, q, w) for p, q in zip(path, path[1:])]
    for r in rects:
        if r[0] < lo or r[1] < lo or r[2] > hi or r[3] > hi:
            return None
        for q in placed:  # round 9: corridors of other edges: join them or keep 1 or 5+ tiles away
            if overlap(r, inflate(q, 5)) and not overlap(r, inflate(q, 2)):
                return None
        for n in nodes:
            if n in own:
                if overlap(r, inflate(n.rect, 5)) and not overlap(r, inflate(n.rect, 2)):
                    return None
                continue
            if overlap(r, inflate(n.rect, 1)):
                return None
            if overlap(r, inflate(n.rect, 5)) and not overlap(r, inflate(n.rect, 2)):
                return None  # round 9: 2-4 solid tiles between a corridor and a room show two walls and a dark strip
    return rects


def double_walls(floor, thick=(2, 3, 4)):
    """Round 9: solid bands 2-4 tiles thick with floor on both sides: two walls stacked or with a 1-2 tile dark strip between
    them (a band 1 thick is one shared wall, 5 or more shows plain rock). Returns the tiles of such bands."""
    bad = set()
    for (x, y) in floor:
        for dx, dy in ((1, 0), (0, 1)):
            for t in thick:
                run = [(x + k * dx, y + k * dy) for k in range(1, t + 1)]
                if all(r not in floor for r in run) and (x + (t + 1) * dx, y + (t + 1) * dy) in floor \
                        and all((r[0] + dy, r[1] + dx) not in floor and (r[0] - dy, r[1] - dx) not in floor for r in run):
                    bad.update(run)  # (a wall column between two doorways has floor beside it: not a band)
    return bad


def rock_pockets(floor):
    """Round 9: rock tiles that touch no floor but have wall tiles on 3 of their 4 sides (a 1-tile dark notch between walls)."""
    need = {(x + i, y + j) for x, y in floor for i in (-1, 0, 1) for j in (-1, 0, 1)} - floor
    cand = {(x + i, y + j) for x, y in need for i in (-1, 0, 1) for j in (-1, 0, 1)} - need - floor
    return {t for t in cand if sum((t[0] + a, t[1] + b) in need for a, b in ((1, 0), (-1, 0), (0, 1), (0, -1))) >= 3}


def layout_floor(size, rng, cfg):
    """Draws the floor: returns (floor set, nodes, edges, info)."""
    lo, hi = MARGIN, size - 1 - MARGIN
    gap = cfg.get("gap", 3)
    kinds = cfg["kinds"]
    inner = (hi - lo + 1) ** 2
    n = max(3, int(round(cfg.get("per_1000", 0.9) * inner / 1000)))
    lo_share, hi_share = cfg.get("floor_share", [0.2, 0.3])
    corridor = cfg.get("corridor", {"2": 0.5, "3": 0.5})
    best = None
    tried = set()
    for attempt in range(25):
        tried.add(n)
        taken, nodes = [], []
        for _ in range(n * 6):
            if len(nodes) >= n:
                break
            kind = pick_weighted(rng, kinds)
            node = (make_cells if kind.get("structure") == "cells" else make_room)(rng, kind, lo, hi, gap, taken)
            if node:
                nodes.append(node)
                taken.append(node.rect)
        if len(nodes) < 2:
            n = max(3, n - 1)
            continue
        # tree plus loops
        dist = lambda a, b: math.hypot(a.centre[0] - b.centre[0], a.centre[1] - b.centre[1])
        inside, edges = {0}, []
        while len(inside) < len(nodes):
            a, b = min(((a, b) for a in inside for b in range(len(nodes)) if b not in inside),
                       key=lambda e: dist(nodes[e[0]], nodes[e[1]]))
            edges.append((a, b))
            inside.add(b)
        extra = int(round(len(edges) * rng.uniform(*cfg.get("loops", [0.1, 0.25]))))
        have = {frozenset(e) for e in edges}
        spare = sorted((frozenset((a, b)) for a in range(len(nodes)) for b in range(a + 1, len(nodes))
                        if frozenset((a, b)) not in have), key=lambda e: dist(*[nodes[i] for i in sorted(e)]))
        near = spare[:max(1, 2 * len(nodes))]
        rng.shuffle(near)
        edges += [tuple(sorted(e)) for e in near[:extra]]
        # route every edge; edges that find no way are dropped (the tree edges decide who stays)
        floor_rects, joined, linked = [], 0, {0}
        widths = {}
        done = []
        for ei, (a, b) in enumerate(edges):
            na, nb = nodes[a], nodes[b]
            w = edge_width(rng, corridor, na, nb)
            ok = None
            for _ in range(3):  # a few widths when the first finds no way
                for path in routes(rng, na, nb, w, lo, hi):
                    rects = route_ok(path, w, (na, nb), nodes, lo, hi, [q for d in done for q in d[2][1]])
                    if rects:
                        ok = (w, rects)
                        break
                if ok or na.axis or nb.axis:
                    break
                w = edge_width(rng, corridor, na, nb)
            if ok:
                done.append((a, b, ok))
                widths[ok[0]] = widths.get(ok[0], 0) + sum((r[2] - r[0] + 1) * (r[3] - r[1] + 1) for r in ok[1])
        # keep the biggest group of nodes the routes join
        parent = list(range(len(nodes)))

        def find(i):
            while parent[i] != i:
                parent[i] = parent[parent[i]]
                i = parent[i]
            return i
        for a, b, _ in done:
            parent[find(a)] = find(b)
        groups = {}
        for i in range(len(nodes)):
            groups.setdefault(find(i), []).append(i)
        keep = set(max(groups.values(), key=len))
        floor = set()
        for i in keep:
            floor |= nodes[i].floor
        for a, b, (w, rects) in done:
            if a in keep and b in keep:
                for r in rects:
                    floor |= rect_tiles(*r)
        share = len(floor) / inner
        info = {"nodes": len(keep), "loops": extra, "attempts": attempt + 1, "share": round(share, 3),
                "width_tiles": dict(sorted(widths.items())), "edges": len(done)}
        score = 0 if lo_share <= share <= hi_share else min(abs(share - lo_share), abs(share - hi_share))
        pockets = len(double_walls(floor)) + len(rock_pockets(floor))  # round 9: two walls with 0-1 tile between them are not wanted
        info["double_walls"] = pockets
        score = (1 if pockets else 0, pockets, score)
        if best is None or score < best[0]:
            best = (score, floor, [nodes[i] for i in sorted(keep)], info)
        if score[:2] == (0, 0) and score[2] == 0:
            break
        if attempt >= 24:
            break
        n2 = n if lo_share <= share <= hi_share else (n + 1 if share < lo_share else n - 1)
        if n2 < 3:
            n2 = n
        n = n2

    return best[1], best[2], best[3]


def rooms_layout(size, rng, cave_cfg, style, stairs_fn):
    """The layout() dict for a dungeon: the floor from layout_floor, rock everywhere else, ramp alcoves cut by stairs_fn."""
    cfg = cave_cfg["rooms"]
    floor_set, nodes, info = layout_floor(size, rng, cfg)
    floor = [[(x, y) in floor_set for x in range(size)] for y in range(size)]
    count = cave_cfg.get("stairs", {}).get("count", [0, 0]) if cave_cfg.get("stairs") else [0, 0]
    want = rng.randint(*count)
    base_bad = len(double_walls(floor_set)) + len(rock_pockets(floor_set))
    for _ in range(12):  # round 9: an alcove that leaves a thin band against a room is cut again elsewhere
        trial = [row[:] for row in floor]
        found = stairs_fn(trial, rng, style, want, clear=5) if count[1] else []
        tf = {(x, y) for y in range(size) for x in range(size) if trial[y][x]}
        if len(double_walls(tf)) + len(rock_pockets(tf)) <= base_bad:
            break
    floor = trial if count[1] else floor
    water = [[not v for v in row] for row in floor]
    rooms = [dict(r) for n in nodes for r in n.rooms]
    floor_set = {(x, y) for y in range(size) for x in range(size) if floor[y][x]}
    info.update({"style": style, "stairs": len(found), "tiles_removed": 0, "tunnels_joined": 0, "spurs": 0,
                 "rooms": len(rooms), "kinds": sorted({r["kind"] for r in rooms})})
    off = [[False] * size for _ in range(size)]
    return {"water": water, "mountain": off, "levels": [], "hill": [row[:] for row in off],
            "shore": distance(size, water), "river": set(), "passes": 0, "sealed": 0,
            "cave": info, "stairs": found, "rooms": rooms, "floor_set": floor_set}
