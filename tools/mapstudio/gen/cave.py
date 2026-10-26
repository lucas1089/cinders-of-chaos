"""Cave mode (kit key "cave"): solid rock with a carved floor, chambers joined by tunnels. Used by gen/generate.py in
place of layout() (the same dict comes back: the rock is the kit's "water" role, the carved floor is the land).

Shape (docs/kits/cave.md): chambers placed by Poisson-disc spacing, joined by a minimum spanning tree plus 10-15%
extra edges (loops); each edge is a winding course drawn with a round brush of width 2/3/4/5 (shares from the kit),
a new width on every run of 8-20 tiles; dead-end spurs; pillars inside chambers. A target share of the area inside
the margin should be walkable (15-25%): chambers, then spurs, are added or dropped until it is met. Then the outline
is cleaned and roughened (staircase walls), and every walkable tile is joined to the biggest walkable part (small
parts are filled, big ones get a tunnel). Stairs: alcoves cut into a wall, each seats a ramp up to the floor above.

Wall styles (kit cave.styles): "on_floor" = the wall piece lies on the floor tile at the edge and blocks it, so a
tunnel is carved 2 wider than its walkable width; "on_rock" = the wall piece lies on the rock tile beside the floor,
the floor stays free to its edge.
"""
from __future__ import annotations

import heapq
import math
import random
from collections import deque

from lib import clean, roughen, touches
from shapes import blend, distance

MARGIN = 5  # solid tiles kept all round the area
STEPS8 = [(i, j) for i in (-1, 0, 1) for j in (-1, 0, 1) if i or j]
DIRS = {"n": (0, -1), "e": (1, 0), "s": (0, 1), "w": (-1, 0)}

# per-shape defaults; every number can be overridden by the kit (cave.chambers, tunnel_width, loops, ...)
MODES = {
    "mix": {"per_1000": 0.9, "radius": [3, 6], "spacing": 14, "loops": [0.10, 0.15], "spurs_per_1000": 3.0,
            "pillars_per_chamber": 2, "tunnel_width": {"2": 0.2, "3": 0.6, "4": 0.1, "5": 0.1}},
    # tunnels only: small junction nodes (a node is a short wide spot), more spurs, no pillars
    "tunnels": {"per_1000": 1.6, "radius": [2, 3], "spacing": 10, "loops": [0.10, 0.15], "spurs_per_1000": 5.0,
                "pillars_per_chamber": 0, "tunnel_width": {"2": 0.2, "3": 0.6, "4": 0.1, "5": 0.1}},
    # chambers only: big halls touching or joined by short wide bands, many pillars, no spurs
    "chambers": {"per_1000": 1.4, "radius": [4, 8], "spacing": 12, "loops": [0.15, 0.25], "spurs_per_1000": 0.0,
                 "pillars_per_chamber": 3, "tunnel_width": {"4": 0.3, "5": 0.4, "6": 0.3}},
}


def brush(w):
    """Offsets of a round brush w tiles across (even widths are centred between tiles: 2 = a 2x2 block)."""
    if w % 2:
        r = (w - 1) // 2
        return [(i, j) for j in range(-r, r + 1) for i in range(-r, r + 1) if i * i + j * j <= r * r + 0.25]
    h = w // 2
    lim = h * h - 0.5
    return [(i, j) for j in range(-h + 1, h + 1) for i in range(-h + 1, h + 1)
            if (i - 0.5) ** 2 + (j - 0.5) ** 2 <= lim]


def settings(cfg):
    """The kit's cave block over the defaults of its shape."""
    shape = cfg.get("shape", "mix")
    s = {**MODES[shape], "shape": shape, "floor_share": [0.15, 0.25]}
    for k, v in cfg.get("chambers", {}).items():
        s[k] = v
    for k in ("tunnel_width", "loops", "spurs_per_1000", "floor_share", "pillars_per_chamber"):
        if k in cfg:
            s[k] = cfg[k]
    if not isinstance(s["loops"], (list, tuple)):
        s["loops"] = [s["loops"], s["loops"]]
    return s


def walk_mask(floor, style):
    """Tiles a player can stand on: the floor, minus (on_floor) the edge tiles that carry a wall piece."""
    size = len(floor)
    if style == "on_rock":
        return [row[:] for row in floor]
    return [[floor[y][x] and not any(not floor[y + j][x + i] if 0 <= x + i < size and 0 <= y + j < size else True
                                     for i, j in STEPS8) for x in range(size)] for y in range(size)]


def components(mask):
    """8-connected parts of a mask, biggest first, as sets."""
    size = len(mask)
    seen, out = set(), []
    for y in range(size):
        for x in range(size):
            if not mask[y][x] or (x, y) in seen:
                continue
            part, queue = {(x, y)}, deque([(x, y)])
            seen.add((x, y))
            while queue:
                cx, cy = queue.popleft()
                for i, j in STEPS8:
                    nx, ny = cx + i, cy + j
                    if 0 <= nx < size and 0 <= ny < size and mask[ny][nx] and (nx, ny) not in seen:
                        seen.add((nx, ny))
                        part.add((nx, ny))
                        queue.append((nx, ny))
            out.append(part)
    return sorted(out, key=len, reverse=True)


class Carver:
    """One cave being drawn: the floor mask and what was drawn (nodes, courses) for later steps and the summary."""

    def __init__(self, size, rng, cfg, style, road_path, smooth_course):
        self.size, self.rng, self.s, self.style = size, rng, cfg, style
        self.road_path, self.smooth_course = road_path, smooth_course
        self.extra = 2 if style == "on_floor" else 0  # carved width = walkable width + the wall ring
        self.lo, self.hi = MARGIN, size - 1 - MARGIN
        self.floor = [[False] * size for _ in range(size)]
        self.nodes, self.chambers, self.courses, self.spurs = [], [], [], []
        self.width_tiles = {}  # walkable width -> course tiles drawn with it
        self.bend = blend(size, rng, [(6, 0.5), (3, 0.5)])

    # ------------------------------------------------------------------ drawing
    def stamp(self, x, y, offs):
        for i, j in offs:
            nx, ny = x + i, y + j
            if self.lo <= nx <= self.hi and self.lo <= ny <= self.hi:
                self.floor[ny][nx] = True

    def chamber(self, cx, cy, radius):
        """A noisy ellipse: three harmonics on the radius."""
        rng = self.rng
        ax, ay = radius * rng.uniform(0.9, 1.25), radius * rng.uniform(0.9, 1.25)
        ph = [rng.uniform(0, 6.283) for _ in range(3)]
        am = [rng.uniform(0.05, 0.14) for _ in range(3)]
        reach = int(max(ax, ay) * 1.4) + 1
        tiles = []
        for y in range(cy - reach, cy + reach + 1):
            for x in range(cx - reach, cx + reach + 1):
                dx, dy = (x - cx) / ax, (y - cy) / ay
                th = math.atan2(dy, dx)
                lim = 1 + sum(am[k] * math.sin((k + 2) * th + ph[k]) for k in range(3))
                if math.hypot(dx, dy) <= lim and self.lo <= x <= self.hi and self.lo <= y <= self.hi:
                    self.floor[y][x] = True
                    tiles.append((x, y))
        return tiles

    def place_nodes(self, n):
        """Poisson-disc dart throwing: n centres at least `spacing` apart (the spacing shrinks if the area is full)."""
        rng, s = self.rng, self.s
        spacing, out, tries = s["spacing"], [], 0
        while len(out) < n and spacing >= 6:
            r = rng.randint(*s["radius"]) + (1 if self.extra else 0)
            lo, hi = self.lo + r + 1, self.hi - r - 1
            if hi <= lo:
                break
            x, y = rng.randint(lo, hi), rng.randint(lo, hi)
            tries += 1
            if all(math.hypot(x - ox, y - oy) >= spacing for ox, oy, _ in out):
                out.append((x, y, r))
            if tries % 300 == 299:
                spacing -= 1
        return out

    def spanning(self, nodes):
        """Prim's tree over the node centres plus a few extra short edges (loops). Returns the edge list."""
        rng = self.rng
        n = len(nodes)
        d = lambda a, b: math.hypot(nodes[a][0] - nodes[b][0], nodes[a][1] - nodes[b][1])
        inside, edges = {0}, []
        while len(inside) < n:
            a, b = min(((a, b) for a in inside for b in range(n) if b not in inside), key=lambda e: d(*e))
            edges.append((a, b))
            inside.add(b)
        lo, hi = self.s["loops"]
        extra = int(round(len(edges) * rng.uniform(lo, hi)))
        if extra == 0 and len(edges) >= 4 and hi > 0 and rng.random() < 0.5:
            extra = 1
        have = {frozenset(e) for e in edges}
        spare = sorted((frozenset((a, b)) for a in range(n) for b in range(a + 1, n)
                        if frozenset((a, b)) not in have), key=lambda e: d(*sorted(e)))
        near = spare[:max(1, 3 * n)]
        rng.shuffle(near)
        edges += [tuple(sorted(e)) for e in near[:extra]]
        return edges, extra

    def widths_for(self, length):
        """A walkable width for each run of 8-20 tiles along a course of `length` tiles."""
        table = self.s["tunnel_width"]
        keys = list(table)
        out, k = [], 0
        while k < length:
            run = self.rng.randint(8, 20)
            w = int(self.rng.choices(keys, [table[x] for x in keys])[0])
            out += [w] * min(run, length - k)
            k += run
        return out

    def tunnel(self, a, b):
        size = self.size
        bend = self.bend
        lo, hi = self.lo, self.hi
        cost = lambda x, y: 1 + 14 * bend[y][x] ** 2 if lo <= x <= hi and lo <= y <= hi else None
        path = self.road_path(size, a, b, cost)
        if not path:
            return []
        course = self.smooth_course(path)
        for (x, y), w in zip(course, self.widths_for(len(course))):
            self.stamp(x, y, brush(w + self.extra))
            self.width_tiles[w] = self.width_tiles.get(w, 0) + 1
        self.courses.append(course)
        return course

    def spur(self):
        """A dead-end branch 4-12 tiles long, leaving a course sideways, kept clear of the rest of the floor."""
        rng, floor, size = self.rng, self.floor, self.size
        if not self.courses:
            return False
        for _ in range(30):
            course = rng.choice(self.courses)
            if len(course) < 6:
                continue
            k = rng.randint(2, len(course) - 3)
            (x0, y0), (x1, y1) = course[k - 2], course[k + 2]
            along = math.atan2(y1 - y0, x1 - x0)
            heading = along + rng.choice((-1, 1)) * rng.uniform(1.1, 2.0)
            w = rng.choice((2, 2, 3)) + self.extra
            length = rng.randint(4, 12)
            offs = brush(w)
            x, y = float(course[k][0]), float(course[k][1])
            mine, drawn = set(), []
            ok, tail = True, 0
            for step in range(length + 4):
                x += math.cos(heading) * 1.0
                y += math.sin(heading) * 1.0
                if rng.random() < 0.3:
                    heading += rng.uniform(-0.7, 0.7)
                tx, ty = round(x), round(y)
                tiles = [(tx + i, ty + j) for i, j in offs]
                if any(not (self.lo <= a <= self.hi and self.lo <= b <= self.hi) for a, b in tiles):
                    ok = step >= 4
                    break
                if step >= 3 and any(floor[b + j][a + i] for a, b in tiles for i in range(-2, 3) for j in range(-2, 3)
                                     if 0 <= a + i < size and 0 <= b + j < size and (a + i, b + j) not in mine):
                    ok = step >= 5
                    break
                mine |= set(tiles)
                drawn.append((tx, ty, tiles))
                if step >= length:
                    break
            if ok and len(drawn) >= 4:
                for _, _, tiles in drawn:
                    for a, b in tiles:
                        floor[b][a] = True
                self.spurs.append(len(drawn))
                return True
        return False

    def pillars(self, chambers):
        """Rock islands of 2-8 tiles inside chambers, each with 2 tiles of floor all round."""
        rng, floor, size = self.rng, self.floor, self.size
        made = 0
        for cx, cy, r in chambers:
            if r < 4:
                continue
            for _ in range(rng.randint(0, self.s["pillars_per_chamber"])):
                for _ in range(12):
                    qx = cx + rng.randint(-r + 3, r - 3)
                    qy = cy + rng.randint(-r + 3, r - 3)
                    blob = [(qx, qy)]
                    for _ in range(rng.randint(2, 8) - 1):
                        opts = [(a + i, b + j) for a, b in blob for i, j in ((1, 0), (-1, 0), (0, 1), (0, -1))
                                if (a + i, b + j) not in blob]
                        blob.append(rng.choice(opts))
                    ring = {(a + i, b + j) for a, b in blob for i in range(-2, 3) for j in range(-2, 3)}
                    if all(0 <= a < size and 0 <= b < size and (floor[b][a] or (a, b) in blob) for a, b in ring):
                        for a, b in blob:
                            floor[b][a] = False
                        made += 1
                        break
        return made

    # ------------------------------------------------------------------ measures
    def share(self):
        inner = (self.hi - self.lo + 1) ** 2
        return sum(map(sum, walk_mask(self.floor, self.style))) / inner


def build_floor(size, rng, cfg, style, road_path, smooth_course):
    """Carves the floor mask. Returns (floor, info)."""
    s = settings(cfg)
    base = rng.getrandbits(32)
    inner = (size - 2 * MARGIN) ** 2
    lo_share, hi_share = s["floor_share"]
    n = max(2, int(round(s["per_1000"] * inner / 1000)))
    best = None
    tried = set()
    for attempt in range(14):
        tried.add(n)
        cv = Carver(size, random.Random(f"{base}-{n}"), s, style, road_path, smooth_course)
        nodes = cv.place_nodes(n)
        if len(nodes) < 2:
            n = max(2, n - 1)
            continue
        centres = [(x, y) for x, y, _ in nodes]
        edges, loops = cv.spanning(nodes)
        for x, y, r in nodes:
            cv.chamber(x, y, r)
        for a, b in edges:
            cv.tunnel(centres[a], centres[b])
        cv.pillars(nodes)
        want = int(round(s["spurs_per_1000"] * sum(map(sum, cv.floor)) / 1000))
        for _ in range(want):
            cv.spur()
        share = cv.share()
        if s["spurs_per_1000"] > 0:  # still short: more spurs before more chambers (up to 3x the usual)
            extra = 0
            while share < lo_share and extra < max(6, 3 * want):
                extra += 1
                if not cv.spur():
                    break
                share = cv.share()
        info = {"nodes": len(nodes), "loops": loops, "spurs": len(cv.spurs), "attempts": attempt + 1,
                "share": round(share, 3), "width_tiles": dict(sorted(cv.width_tiles.items())),
                "centres": [(x, y, r) for x, y, r in nodes], "edges": len(edges)}
        score = 0 if lo_share <= share <= hi_share else min(abs(share - lo_share), abs(share - hi_share))
        if best is None or score < best[0]:
            best = (score, cv.floor, info)
        if score == 0:
            break
        n2 = n + 1 if share < lo_share else n - 1
        if n2 < 2 or n2 in tried:
            break
        n = n2
    return best[1], best[2]


def tidy(floor, rng, style):
    """Staircase walls, a drawable outline, one walkable part. Edits the floor mask in place; returns tiles removed
    from unjoined parts and the number of tunnels cut to join parts."""
    size = len(floor)
    lo, hi = MARGIN, size - 1 - MARGIN
    inside = lambda x, y: lo <= x <= hi and lo <= y <= hi

    def outline():
        # on_floor: the wall piece lies on floor tiles (water = rock is the region, as for a sea shore);
        # on_rock: it lies on rock tiles, so the floor is the region
        if style == "on_floor":
            water = [[not v for v in row] for row in floor]
            clean(water, outside=True)
            for y in range(size):
                for x in range(size):
                    floor[y][x] = not water[y][x] and inside(x, y)
        else:
            clean(floor)
            for y in range(size):
                for x in range(size):
                    floor[y][x] = floor[y][x] and inside(x, y)

    water = [[not v for v in row] for row in floor]
    roughen(water, rng, outside=True, allowed=lambda x, y: inside(x, y))
    for y in range(size):
        for x in range(size):
            floor[y][x] = not water[y][x] and inside(x, y)
    outline()
    removed = joined = 0
    for _ in range(8):
        walk = walk_mask(floor, style)
        comps = components(walk)
        if not comps:
            break
        main = comps[0]
        if len(comps) == 1:
            # floor tiles that carry a wall but touch no walkable tile of the main part are leftovers
            keep = {(x + i, y + j) for x, y in main for i in (-1, 0, 1) for j in (-1, 0, 1)}
            stray = [(x, y) for y in range(size) for x in range(size) if floor[y][x] and (x, y) not in keep]
            if not stray:
                break
            for x, y in stray:
                floor[y][x] = False
            removed += len(stray)
            outline()
            continue
        for part in comps[1:]:
            if len(part) >= 14:
                joined += join(floor, part, main, style, inside)
            else:
                grow = {(x + i, y + j) for x, y in part for i in (-1, 0, 1) for j in (-1, 0, 1)}
                near_main = {(x + i, y + j) for x, y in main for i in (-1, 0, 1) for j in (-1, 0, 1)}
                for x, y in grow - near_main:
                    if floor[y][x]:
                        floor[y][x] = False
                        removed += 1
        outline()
    return removed, joined


def join(floor, part, main, style, inside):
    """A tunnel from an unjoined walkable part to the main one: the cheapest way (a floor tile costs 1, rock 3),
    drawn 3 walkable wide. Returns 1."""
    size = len(floor)
    best = {t: 0 for t in part}
    prev, queue, goal = {}, [(0, t) for t in part], None
    heapq.heapify(queue)
    while queue:
        d, (x, y) = heapq.heappop(queue)
        if (x, y) in main:
            goal = (x, y)
            break
        if d > best[(x, y)]:
            continue
        for i, j in STEPS8:
            nx, ny = x + i, y + j
            if not inside(nx, ny):
                continue
            nd = d + (1 if floor[ny][nx] else 3) * (1.41 if i and j else 1)
            if nd < best.get((nx, ny), 1e18):
                best[(nx, ny)], prev[(nx, ny)] = nd, (x, y)
                heapq.heappush(queue, (nd, (nx, ny)))
    if not goal:
        return 0
    offs = brush(3 + (2 if style == "on_floor" else 0))
    t = goal
    while t in prev:
        for i, j in offs:
            if inside(t[0] + i, t[1] + j):
                floor[t[1] + j][t[0] + i] = True
        t = prev[t]
    return 1


def stairs(floor, rng, style, count):
    """Alcoves for ramps up to the floor above. For a walkable tile I with a wall tile at I+d and rock from I+2d on: an
    alcove 3 wide and 2 deep is cut into the rock at I+2d, I+3d; the ramp stands on I+3d (touching the rock), the
    lower half on I+2d, the approach is I+d, the landing is the tile past the ramp on the floor above. Edits the
    floor in place. Returns [{"ramp": (x, y), "low": (x, y), "d": name, "landing": [tiles on the floor above]}]."""
    size = len(floor)
    walk = walk_mask(floor, style)
    rock = lambda x, y: 0 <= x < size and 0 <= y < size and not floor[y][x]
    spots = []
    for y in range(MARGIN + 2, size - MARGIN - 2):
        for x in range(MARGIN + 2, size - MARGIN - 2):
            if not walk[y][x]:
                continue
            for name, (dx, dy) in DIRS.items():
                ax, ay = dy, dx
                if not floor[y + dy][x + dx]:
                    continue
                cells = [(x + t * dx + a * ax, y + t * dy + a * ay) for t in (2, 3) for a in (-1, 0, 1)]
                behind = [(x + t * dx + a * ax, y + t * dy + a * ay) for t in (2, 3, 4, 5) for a in (-3, -2, 2, 3)]
                behind += [(x + 4 * dx + a * ax, y + 4 * dy + a * ay) for a in (-1, 0, 1)]
                behind += [(x + 5 * dx + a * ax, y + 5 * dy + a * ay) for a in (-1, 0, 1)]
                if not all(rock(*t) for t in cells + behind):
                    continue
                if not all(0 <= t[0] < size and 0 <= t[1] < size for t in cells + behind):
                    continue
                spots.append((x, y, name))
    rng.shuffle(spots)
    chosen = []
    for x, y, name in spots:
        if len(chosen) >= count:
            break
        if all(abs(x - cx) + abs(y - cy) >= 30 for cx, cy, _ in chosen):
            chosen.append((x, y, name))
    out = []
    for x, y, name in chosen:
        dx, dy = DIRS[name]
        ax, ay = dy, dx
        for t in (2, 3):
            for a in (-1, 0, 1):
                floor[y + t * dy + a * ay][x + t * dx + a * ax] = True
        landing = [(x + t * dx + a * ax, y + t * dy + a * ay) for t in (4, 5, 6) for a in (-1, 0, 1)]
        out.append({"ramp": (x + 3 * dx, y + 3 * dy), "low": (x + 2 * dx, y + 2 * dy), "d": name,
                    "approach": (x + dx, y + dy), "landing": landing})
    return out


def cave_layout(size, rng, cfg, style, road_path, smooth_course):
    """The layout() dict for a cave: water = the solid rock (the kit's liquid role), no relief."""
    floor, info = build_floor(size, rng, cfg, style, road_path, smooth_course)
    removed, joined = tidy(floor, rng, style)
    found = stairs(floor, rng, style, rng.randint(*cfg.get("stairs", {}).get("count", [0, 0]))
                   if cfg.get("stairs") else 0)
    water = [[not v for v in row] for row in floor]
    info.update({"style": style, "stairs": len(found), "tiles_removed": removed, "tunnels_joined": joined})
    off = [[False] * size for _ in range(size)]
    return {"water": water, "mountain": off, "levels": [], "hill": [row[:] for row in off],
            "shore": distance(size, water), "river": set(), "passes": 0, "sealed": 0,
            "cave": info, "stairs": found}
