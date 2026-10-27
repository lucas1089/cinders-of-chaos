"""Wall and void check (round 8). Counts what the owner sees as broken in room and cave kits:

  void_touch    tiles with no ground, or with a black ground (mean luma under 12), that touch (8 neighbours) a walkable
                tile or a wall tile. A black tile beside the floor or beside a wall is the bug.
  wall_wrong    wall pieces that are not the piece their neighbours ask for (4-piece wall sets: horizontal, vertical,
                corner, pole; see expected_class), wall pieces standing where no floor asks for a wall, and (kits whose
                wall is a 12-piece cliff set on the floor edge) cliff pieces that differ from what the rock around asks.
  wall_missing  tiles beside the floor (4 neighbours, plus the diagonal tile that closes a convex corner) that carry no
                wall piece.

Used by gen/generate.py (header stat `wall_check`, kits with the key `wall_check`) and by tools/wall_check.py, which
reads any area.txt. The rule of the 4-piece sets, as the reference rooms lay them (checked on test rooms of the kit
sets): a wall tile joins its 4 neighbours that are wall tiles; both ways through (east and west, or north and south) is
a run piece (horizontal / vertical); a corner that goes east and south is the corner piece; every other corner, a T that
does not go east and south, an end of a run (beside a doorway) and a lone tile is the pole piece.
"""
from __future__ import annotations

STEPS8 = [(i, j) for i in (-1, 0, 1) for j in (-1, 0, 1) if i or j]
N4 = ((0, -1), (1, 0), (0, 1), (-1, 0))
BLACK_LUMA = 12.0


def spec_of(kit):
    """The 4-piece wall spec of a kit: its `walls` key, else read off the 12-piece `wall` set the older kits carry
    (edge_n = horizontal, edge_e = vertical, inner_nw = pole, outer_se = corner). None when the kit has neither."""
    w = kit.get("walls")
    if w:
        return w
    old = kit.get("wall")
    if old and "edge_n" in old:
        return {"h": [old["edge_n"]], "v": [old["edge_e"]], "pole": old["inner_nw"], "corner": old["outer_se"]}
    return None


def classes_of(spec):
    """{piece id: 'H' | 'V' | 'C' | 'P' | 'EH' | 'EV'} for a wall spec (variants count as their class). EH and EV are the
    end pieces of a run (a kit without `end_h` / `end_v` uses its pole there)."""
    out = {}
    for key, cls in (("h", "H"), ("v", "V")):
        v = spec.get(key, [])
        for i in (v if isinstance(v, list) else [v]):
            out[int(i)] = cls
        for i in (spec.get("variants", {}).get(key, {})):
            out[int(i)] = cls
    out[int(spec["corner"])] = "C"
    out[int(spec["pole"])] = "P"
    for i in spec.get("extra_poles", []):
        out[int(i)] = "P"
    if spec.get("end_h"):
        out[int(spec["end_h"])] = "EH"
    if spec.get("end_v"):
        out[int(spec["end_v"])] = "EV"
    return out


def expected_class(n, e, s, w, ends=False):
    """The piece a wall tile needs from which of its 4 neighbours are wall tiles. A run piece joins both ways; an end of
    a run (beside a doorway) takes the end piece on its west or north end (the sprite's cap is on that side) and the
    pole on its east or south end; a corner that goes east and south is the corner piece; the rest are poles."""
    horiz, vert = e or w, n or s
    if horiz and vert:
        return "C" if (e and s) else "P"
    if horiz:
        return "H" if (e and w) else ("EH" if ends else "P") if e else "P"
    if vert:
        return "V" if (n and s) else ("EV" if ends else "P") if s else "P"
    return "P"


def wall_tiles(floor, size):
    """The tiles that need a wall piece beside the floor mask `floor` (set of (x, y)): non-floor tiles that touch the
    floor on 4 sides, plus the diagonal tile that closes a convex corner (both its 4-neighbours toward the floor
    are wall tiles). Returns a set."""
    w4 = set()
    for x, y in floor:
        for i, j in N4:
            t = (x + i, y + j)
            if t not in floor and 0 <= t[0] < size and 0 <= t[1] < size:
                w4.add(t)
    diag = set()
    for x, y in floor:
        for i, j in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
            t = (x + i, y + j)
            if t in floor or t in w4 or not (0 <= t[0] < size and 0 <= t[1] < size):
                continue
            if (x + i, y) in w4 and (x, y + j) in w4:
                diag.add(t)
    return w4 | diag


def classify(wall, ends=False):
    """{tile: class} for a set of wall tiles."""
    return {(x, y): expected_class((x, y - 1) in wall, (x + 1, y) in wall, (x, y + 1) in wall, (x - 1, y) in wall, ends)
            for x, y in wall}


def luma_of(items, cache, item_id):
    """(mean luma, opaque share) of an item's first sprite."""
    import numpy as np
    from common import item_image
    obj = items.get(int(item_id))
    if not obj:
        return 255.0, 0.0
    a = np.asarray(item_image(obj, cache, 0, 0).convert("RGBA")).astype(float)
    m = a[..., 3] > 0
    if not m.any():
        return 255.0, 0.0
    l = 0.3 * a[..., 0] + 0.59 * a[..., 1] + 0.11 * a[..., 2]
    return float(l[m].mean()), float(m.mean())


class Probe:
    """Reads a floor layer {(x, y): [ids]} of an area (ORIGIN-based coordinates, `size` tiles square)."""

    def __init__(self, layer, size, origin, items, kit, no_walk=()):
        from common import SpriteCache
        from common import kind_of
        self.layer, self.size, self.origin, self.items = layer, size, origin, items
        self.cache = SpriteCache()
        self.no_walk = set(no_walk)
        self._luma = {}
        self.kind_of_ground = lambda flags: kind_of(flags) == "ground"
        self.black_ids = set()
        for stack in layer.values():
            if stack and int(stack[0]) not in self._luma:
                l, cover = luma_of(items, self.cache, stack[0])
                self._luma[int(stack[0])] = (l, cover)
                if l < BLACK_LUMA and cover > 0.5:
                    self.black_ids.add(int(stack[0]))

    def stack(self, x, y):
        return self.layer.get((self.origin + x, self.origin + y))

    def is_ground(self, i):
        o = self.items.get(int(i))
        return bool(o) and self.kind_of_ground(o["flags"])

    def void(self, x, y):
        st = self.stack(x, y)
        return not st or not self.is_ground(st[0]) or int(st[0]) in self.black_ids

    def floor(self, x, y):
        """A walkable ground (blocking decor on it does not matter)."""
        st = self.stack(x, y)
        if not st or int(st[0]) in self.no_walk or int(st[0]) in self.black_ids:
            return False
        o = self.items.get(int(st[0]))
        return bool(o) and self.kind_of_ground(o["flags"]) and "not_walkable" not in o["flags"]


def check(layer, size, origin, items, kit, no_walk=(), edge_pieces=None, samples=6, pool_ids=()):
    """The counts of the module docstring for one floor layer. Returns a dict (counts and a few sample tiles)."""
    pr = Probe(layer, size, origin, items, kit, no_walk)
    inside = lambda x, y: 0 <= x < size and 0 <= y < size
    floor = {(x, y) for y in range(size) for x in range(size) if pr.floor(x, y)}
    spec = spec_of(kit)
    cls = classes_of(spec) if spec else {}
    cliff = kit.get("cliff_wall") if not spec else None
    cliff_ids = {int(i) for i in cliff.values()} if cliff else set()
    wall = set()
    piece = {}
    for y in range(size):
        for x in range(size):
            st = pr.stack(x, y)
            if not st:
                continue
            hit = [int(i) for i in st[1:] if int(i) in cls]
            if hit:
                wall.add((x, y))
                piece[(x, y)] = hit
    out = {"void_touch": 0, "void_touch_floor": 0, "void_touch_wall": 0, "wall_wrong": 0, "wall_missing": 0,
           "wall_tiles": len(wall), "black_ids": sorted(pr.black_ids), "samples": {"void": [], "wrong": [], "missing": []}}
    # --- void beside floor or wall
    for y in range(size):
        for x in range(size):
            if not pr.void(x, y):
                continue
            near_floor = any(inside(x + i, y + j) and (x + i, y + j) in floor for i, j in STEPS8)
            near_wall = any(inside(x + i, y + j) and (x + i, y + j) in wall for i, j in STEPS8)
            if near_floor or near_wall:
                out["void_touch"] += 1
                out["void_touch_floor"] += near_floor
                out["void_touch_wall"] += near_wall
                if len(out["samples"]["void"]) < samples:
                    out["samples"]["void"].append((origin + x, origin + y))
    # --- 4-piece walls
    if spec:
        need = wall_tiles(floor, size)
        want = classify(wall, bool(spec.get("end_h") and spec.get("end_v")))
        for t, hit in piece.items():
            ok = t in need and len(hit) == 1 and cls[hit[0]] == want[t]
            if not ok:
                out["wall_wrong"] += 1
                if len(out["samples"]["wrong"]) < samples:
                    out["samples"]["wrong"].append((origin + t[0], origin + t[1], want[t], [cls[i] for i in hit]))
        for t in need - wall:
            out["wall_missing"] += 1
            if len(out["samples"]["missing"]) < samples:
                out["samples"]["missing"].append((origin + t[0], origin + t[1]))
    # --- 12-piece cliff set on the floor edge (kits with wall style on_floor): the rock around asks for the pieces
    elif cliff and edge_pieces:
        pools = {(x, y) for y in range(size) for x in range(size)
                 if layer.get((origin + x, origin + y)) and int(layer[(origin + x, origin + y)][0]) in {int(i) for i in pool_ids}}
        rock = [[not ((x, y) in floor or (x, y) in pools) for x in range(size)] for y in range(size)]  # a liquid pool on the floor is no rock
        ramps = {int(i) for key in ("mountain_ramp", "hill_ramp") for v in kit.get(key, {}).values() for i in v}
        for (x, y) in floor:
            if ramps & {int(i) for i in layer[(origin + x, origin + y)]}:
                continue  # a ramp seat carries no wall piece
            want = sorted(int(i) for i in edge_pieces(rock, x, y, cliff, outside=True))
            have = sorted(int(i) for i in layer[(origin + x, origin + y)][1:] if int(i) in cliff_ids)
            if want != have:
                if have:
                    out["wall_wrong"] += 1
                else:
                    out["wall_missing"] += 1
                key = "wrong" if have else "missing"
                if len(out["samples"][key]) < samples:
                    out["samples"][key].append((origin + x, origin + y))
    return out


def summary(res):
    return {k: res[k] for k in ("void_touch", "wall_wrong", "wall_missing")}
