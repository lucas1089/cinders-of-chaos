"""Room themes (round 8, kit key `themes` with `cave.rooms`): the floor and decor of every room of a dungeon layout.

Each room (gen/rooms.py) has a `theme`; corridors use the theme `corridor`. A theme:

  "floor":   {"role": "base" | "sand" | "grey_sand" | "rock_soil", "accent": {"role": .., "share": 0.15, "size": [2, 3]}}
             the ground of the whole room (the kit's role spec) with accent blobs of a second role
  "along":   [{"ids": [..], "sides": ["n", "s", "e", "w"], "step": tiles between starts, "chance": 0..1, "gap": [lo, hi]}]
             items stood against the walls of those sides; the item's footprint sits inside the room, next to the wall
  "rows":    [{"ids": [..], "every": rows between, "axis": "x" | "y", "margin": m, "gap_chance": 0.12, "gap": [1, 2]}]
             free-standing rows (stacks of bookcases, rows of tables) with an aisle between each pair
  "grid":    [{"ids": [..], "step": [sx, sy], "margin": m, "chance": c}]  items on a lattice
  "center":  [{"ids": [..], "count": [lo, hi], "spread": tiles}]  items near the middle of the room
  "scatter": {"<id>": rate per free tile}
  "props":   [{"ids": [..], "count": [lo, hi]}]  items on random free tiles

Items keep out of the 2 tiles inside every doorway, and never overlap (a multi-tile item stands on its bottom-right tile
and covers its width x height up-left, as everywhere in the generator). The decor ids come back to the caller so the
access repair may clear any item that closes a path.
"""
from __future__ import annotations

from lib import footprint

SIDES = {"n": (0, -1), "e": (1, 0), "s": (0, 1), "w": (-1, 0)}


def pick(rng, g):
    return g["lead"] if rng.random() < 0.6 or not g.get("members") else rng.choice(g["members"])


def interior(r):
    return {(x, y) for y in range(r[1], r[3] + 1) for x in range(r[0], r[2] + 1)}


def door_zones(r, floor):
    """Interior tiles within 2 of a doorway: floor tiles of the ring just outside the rectangle."""
    x0, y0, x1, y1 = r
    ring = [(x, y0 - 1) for x in range(x0, x1 + 1)] + [(x, y1 + 1) for x in range(x0, x1 + 1)] + \
           [(x0 - 1, y) for y in range(y0, y1 + 1)] + [(x1 + 1, y) for y in range(y0, y1 + 1)]
    zone = set()
    for t in ring:
        if t in floor:
            for i in range(-2, 3):
                for j in range(-2, 3):
                    q = (t[0] + i, t[1] + j)
                    if x0 <= q[0] <= x1 and y0 <= q[1] <= y1:
                        zone.add(q)
    return zone


def footprint_tiles(item, x, y, items):
    w, h = footprint(items[item])
    return [(x - dx, y - dy) for dx in range(w) for dy in range(h)]


class Dresser:
    def __init__(self, layer, kit, items, rng, origin, floor):
        self.layer, self.kit, self.items, self.rng, self.o, self.floor = layer, kit, items, rng, origin, floor
        self.taken = set()
        self.used = set()

    def put(self, item, x, y, free, single=False):
        """Places `item` with its anchor on (x, y) when every footprint tile is in `free` and not taken. `single`: the item
        occupies its anchor tile only (a bookcase or bed whose 64x64 sprite overhangs its tile)."""
        tiles = [(x, y)] if single else footprint_tiles(item, x, y, self.items)
        if not all(t in free and t not in self.taken for t in tiles):
            return False
        self.taken |= set(tiles)
        self.layer[(self.o + x, self.o + y)].append(item)
        self.used.add(item)
        return True


def place_along(d, r, free, spec):
    x0, y0, x1, y1 = r
    rng = d.rng
    for side in spec.get("sides", ["n", "s"]):
        pos = (x0 if side in "ns" else y0) + spec.get("inset", 0)
        end = (x1 if side in "ns" else y1) - spec.get("inset", 0)
        while pos <= end:
            item = int(rng.choice(spec["ids"]))
            w, h = (1, 1) if spec.get("single") else footprint(d.items[item])
            span = w if side in "ns" else h
            if side == "n":
                ax, ay = pos + w - 1, y0 + h - 1
            elif side == "s":
                ax, ay = pos + w - 1, y1
            elif side == "w":
                ax, ay = x0 + w - 1, pos + h - 1
            else:
                ax, ay = x1, pos + h - 1
            if rng.random() < spec.get("chance", 1.0) and d.put(item, ax, ay, free, spec.get("single")):
                pos += span + rng.randint(*spec.get("gap", [0, 0]))
            else:
                pos += 1


def place_rows(d, r, free, spec):
    x0, y0, x1, y1 = r
    rng = d.rng
    m = spec.get("margin", 1)
    every = spec.get("every", 3)
    axis = spec.get("axis", "x")
    lines = range((y0 if axis == "x" else x0) + m, (y1 if axis == "x" else x1) - m + 1, every)
    for ln in lines:
        pos, stop = (x0 if axis == "x" else y0) + m, (x1 if axis == "x" else y1) - m
        while pos <= stop:
            item = int(rng.choice(spec["ids"]))
            w, h = (1, 1) if spec.get("single") else footprint(d.items[item])
            ax, ay = (pos + w - 1, ln + h - 1) if axis == "x" else (ln + w - 1, pos + h - 1)
            if rng.random() < spec.get("gap_chance", 0.1):
                pos += rng.randint(*spec.get("gap", [1, 2]))
                continue
            pos += (w if axis == "x" else h) if d.put(item, ax, ay, free, spec.get("single")) else 1


def place_grid(d, r, free, spec):
    x0, y0, x1, y1 = r
    sx, sy = spec.get("step", [3, 3])
    m = spec.get("margin", 1)
    for y in range(y0 + m, y1 - m + 1, sy):
        for x in range(x0 + m, x1 - m + 1, sx):
            if d.rng.random() < spec.get("chance", 1.0):
                d.put(int(d.rng.choice(spec["ids"])), x, y, free, spec.get("single"))


def place_center(d, r, free, spec):
    x0, y0, x1, y1 = r
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    sp = spec.get("spread", 2)
    for _ in range(d.rng.randint(*spec.get("count", [1, 1]))):
        for _ in range(12):
            if d.put(int(d.rng.choice(spec["ids"])), cx + d.rng.randint(-sp, sp), cy + d.rng.randint(-sp, sp), free):
                break


def place_props(d, r, free, spec):
    for _ in range(d.rng.randint(*spec.get("count", [1, 1]))):
        tiles = sorted(t for t in free if t not in d.taken)
        for _ in range(20):
            if not tiles:
                return
            x, y = d.rng.choice(tiles)
            if d.put(int(d.rng.choice(spec["ids"])), x, y, free):
                break


def apply_theme(d, r, free, theme):
    for spec in theme.get("along", []):
        place_along(d, r, free, spec)
    for spec in theme.get("rows", []):
        place_rows(d, r, free, spec)
    for spec in theme.get("grid", []):
        place_grid(d, r, free, spec)
    for spec in theme.get("center", []):
        place_center(d, r, free, spec)
    for spec in theme.get("props", []):
        place_props(d, r, free, spec)
    for key, rate in theme.get("scatter", {}).items():
        item = int(key)
        for t in sorted(free):
            if d.rng.random() < rate:
                d.put(item, t[0], t[1], free)


def floor_of(d, kit, spec, tiles):
    """Sets the ground of `tiles` from the theme's floor spec."""
    rng = d.rng
    role = spec.get("role", "base")
    accent = spec.get("accent")
    blobs = set()
    if accent:
        want = int(len(tiles) * accent.get("share", 0.12))
        lo, hi = accent.get("size", [2, 3])
        ts = sorted(tiles)
        for _ in range(60):
            if len(blobs) >= want or not ts:
                break
            x, y = rng.choice(ts)
            w, h = rng.randint(lo, hi), rng.randint(lo, hi)
            blobs |= {(x + i, y + j) for i in range(w) for j in range(h) if (x + i, y + j) in tiles}
    for t in tiles:
        g = kit[accent["role"]] if accent and t in blobs else kit[role]
        st = d.layer.get((d.o + t[0], d.o + t[1]))
        if st:
            st[0] = pick(rng, g)
            del st[1:]  # old borders and clumps go; the theme lays its own decor


def dress(layer, m, kit, items, rng, origin, size, wall_pieces):
    """Floor and decor of every room and corridor. Returns the set of decor ids placed."""
    themes = kit.get("themes", {})
    floor = m["floor_set"]
    d = Dresser(layer, kit, items, rng, origin, floor)
    in_room = set()
    # stairs ramp tiles and their approach stay as they are
    keep = set()
    for st in m.get("stairs", []):
        keep |= {st["ramp"], st["low"], st["approach"], *st["landing"]}
        dx = {"n": (0, -1), "s": (0, 1), "e": (1, 0), "w": (-1, 0)}[st["d"]]
        keep |= {(st["approach"][0] - dx[0] + i, st["approach"][1] - dx[1] + j) for i in (-1, 0, 1) for j in (-1, 0, 1)}
    for room in m["rooms"]:
        theme = themes.get(room["theme"])
        if not theme:
            continue
        r = room["rect"]
        tiles = interior(r)
        in_room |= tiles
        tiles -= keep
        floor_of(d, kit, theme.get("floor", {"role": "base"}), tiles)
        free = tiles - door_zones(r, floor)
        # no decor on door tiles of cells
        if room.get("door"):
            free.discard(room["door"])
        apply_theme(d, r, free, theme)
    corridor = themes.get("corridor")
    if corridor:
        free = {t for t in floor if t not in in_room and t not in keep}
        apply_theme(d, (0, 0, size - 1, size - 1), free, {k: v for k, v in corridor.items() if k == "scatter"})
    return d.used
