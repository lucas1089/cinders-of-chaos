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


def expected_stack(n, e, s, w, ends=False):
    """The pieces a wall tile needs, bottom to top, from which of its 4 neighbours are wall tiles (round 9: chosen by the wall
    skeleton, each case looked at in a render; the old rule put a thin post wherever a wall turned, which left a notch of
    dark ground at T joints, elbows and run ends). Classes: H, V, C (corner), P (post, a lone tile only), EH, EV.
      straight: H (east-west), V (north-south)      turns: east+south P (round 10, was C), west+south H, east+north V, west+north C
      T: west+east+south H, west+east+north V under H, north+south+east V, north+south+west H under V
      cross: V under H            ends: west end of a run EH, north end EV, east end H, south end V (no end pieces: H / V)
    """
    cnt = (n, e, s, w)
    if all(cnt):
        return ["V", "H"]
    if sum(cnt) == 3:
        if not n:
            return ["H"]
        if not s:
            return ["V", "H"]
        return ["V"] if e else ["H", "V"]
    if sum(cnt) == 2:
        if e and w:
            return ["H"]
        if n and s:
            return ["V"]
        if e and s:
            return ["P"]      # round 10: the corner piece's cap hangs one tile over its west neighbour (floor or cover): a stub
        if w and n:
            return ["C"]
        return ["H"] if (w and s) else ["V"]
    if e:
        return ["EH" if ends else "H"]
    if w:
        return ["H"]
    if s:
        return ["EV" if ends else "V"]
    if n:
        return ["V"]
    return ["P"]


def expected_class(n, e, s, w, ends=False):
    """The main piece of expected_stack (its top piece)."""
    return expected_stack(n, e, s, w, ends)[-1]


def wall_tiles(floor, size):
    """The tiles that need a wall piece beside the floor mask `floor` (set of (x, y)): non-floor tiles that touch the
    floor on 4 sides, plus the diagonal tile that closes a convex corner (both its 4-neighbours toward the floor
    are wall tiles), plus (round 9) every one-tile strip of solid between two wall tiles (two parallel walls with one tile
    between them would show a black strip). Returns a set."""
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
    need = w4 | diag
    strips = set()
    for x in range(size):
        for y in range(size):
            t = (x, y)
            if t in need or t in floor:
                continue
            if ((x, y - 1) in need and (x, y + 1) in need) or ((x - 1, y) in need and (x + 1, y) in need):
                strips.add(t)
    return need | strips


def arms(wall, t):
    """(n, e, s, w): which neighbours of wall tile t are arms of the wall skeleton. A neighbour that lies in a run PARALLEL to
    t (t and the neighbour both have wall on both sides along the other axis: two walls side by side, a thick wall) is
    not an arm."""
    x, y = t
    n, e, s, w = ((x, y - 1) in wall, (x + 1, y) in wall, (x, y + 1) in wall, (x - 1, y) in wall)
    row = lambda q: (q[0] - 1, q[1]) in wall and (q[0] + 1, q[1]) in wall
    col = lambda q: (q[0], q[1] - 1) in wall and (q[0], q[1] + 1) in wall
    if e and w:        # t is in a horizontal run: a north or south neighbour in a horizontal run is a parallel wall
        n = n and not row((x, y - 1))
        s = s and not row((x, y + 1))
    if n and s:        # t is in a vertical run
        e = e and not col((x + 1, y))
        w = w and not col((x - 1, y))
    return n, e, s, w


def classify(wall, ends=False):
    """{tile: [classes bottom to top]} for a set of wall tiles."""
    return {t: expected_stack(*arms(wall, t), ends) for t in wall}


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
        spec = spec_of(kit)
        self.wall_ids = set(classes_of(spec)) if spec else set()
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
        """A walkable ground (blocking decor on it does not matter; a tile with a wall piece is a wall, not floor)."""
        st = self.stack(x, y)
        if not st or int(st[0]) in self.no_walk or int(st[0]) in self.black_ids:
            return False
        if self.wall_ids and any(int(i) in self.wall_ids for i in st[1:]):
            return False
        return self.ground_floor(x, y)

    def ground_floor(self, x, y):
        """The tile's ground alone is walkable ground (a wall piece on it is ignored)."""
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
            ok = t in need and [cls[i] for i in hit] == want[t]
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


GAP_REACH = 40  # px: solid ground with wall sprite pixels on both opposite sides within this reach is a gap
GAP_MIN = 6     # px: smallest gap blob that counts


def _near(mask, reach, axis):
    """For every pixel: is a True pixel within `reach` px on BOTH sides along `axis`?"""
    import numpy as np
    m = mask if axis == 1 else mask.T
    h, w = m.shape
    idx = np.arange(w)[None, :]
    last = np.maximum.accumulate(np.where(m, idx, -10 ** 6), axis=1)
    nxt = np.minimum.accumulate(np.where(m, idx, 10 ** 6)[:, ::-1], axis=1)[:, ::-1]
    ok = ((idx - last) <= reach) & ((nxt - idx) <= reach) & (last >= 0) & (nxt < 10 ** 6)
    return ok if axis == 1 else ok.T


def gap_mask(layer, size, origin, items, kit, no_walk=()):
    """(gap pixel mask, wall sprite mask, pad px) of the `gaps` check (round 9, `wall_gaps`: black points in walls). The wall pieces
    are drawn alone (at the client's offsets) to get the opaque sprite pixels W. A pixel is a gap pixel when it lies on a tile
    that is not floor (solid ground, cover or void: it shows dark), no wall sprite pixel covers it, and wall sprite pixels
    lie on both of its sides within GAP_REACH px along its row or along its column (a hole inside a corner or a T, a strip
    between two walls, ground showing through the sheared end of a sprite). Both masks share one frame (the area plus `pad` px)."""
    import numpy as np
    from common import TILE, displacement, item_image
    pr = Probe(layer, size, origin, items, kit, no_walk)
    spec = spec_of(kit)
    ids = set(classes_of(spec)) if spec else {int(i) for i in (kit.get("cliff_wall") or {}).values()}
    pad = 2 * TILE
    W = np.zeros((size * TILE + 2 * pad, size * TILE + 2 * pad), bool)
    if ids:  # an open fence (sprites under 25% opaque) hides no ground: nothing can show through it, no gap check
        runs = [np.asarray(item_image(items[i], pr.cache, origin, origin))[..., 3] > 0 for i, c in classes_of(spec).items() if c in ("H", "V")] if spec else []
        if runs and sum(float(r.mean()) for r in runs) / len(runs) < 0.25:
            return np.zeros_like(W), W, pad
    ramp_ids = {int(i) for key in ("mountain_ramp", "hill_ramp") for v in kit.get(key, {}).values() for i in v}
    floor = np.zeros((size, size), bool)
    for y in range(size):
        for x in range(size):
            st = pr.stack(x, y)
            if not st:
                continue
            floor[y, x] = pr.ground_floor(x, y) or any(int(i) in ramp_ids for i in st)  # a stair ramp is walkable too
            for i in st[1:]:
                if int(i) in ids:
                    obj = items[int(i)]
                    img = np.asarray(item_image(obj, pr.cache, origin + x, origin + y))[..., 3] > 0
                    dx, dy = displacement(obj)
                    px = pad + x * TILE + TILE - img.shape[1] - dx
                    py = pad + y * TILE + TILE - img.shape[0] - dy
                    W[py:py + img.shape[0], px:px + img.shape[1]] |= img
    free = ~np.kron(floor, np.ones((TILE, TILE), bool))
    free = np.pad(free, pad, constant_values=True) & ~W
    box = np.zeros_like(W)
    box[pad:pad + size * TILE, pad:pad + size * TILE] = True
    gap = free & box & (_near(W, GAP_REACH, 1) & _near(W, GAP_REACH, 0)) if ids else np.zeros_like(W)
    return gap, W, pad


def gaps(layer, size, origin, items, kit, no_walk=(), samples=6):
    """Counts the blobs of `gap_mask` (see there); returns {"wall_gaps": n, "samples": [(tile x, tile y, px)]}."""
    import numpy as np
    from scipy import ndimage
    from common import TILE
    gap, W, pad = gap_mask(layer, size, origin, items, kit, no_walk)
    lab, n = ndimage.label(gap)
    out, cnt = [], 0
    for k in range(1, n + 1):
        ys, xs = np.nonzero(lab == k)
        if len(ys) >= GAP_MIN:
            cnt += 1
            if len(out) < samples:
                out.append((origin + int((xs.mean() - pad) // TILE), origin + int((ys.mean() - pad) // TILE), int(len(ys))))
    return {"wall_gaps": cnt, "samples": out}


def bands(layer, size, origin, items, kit, no_walk=()):
    """Round 9 `wall_bands`: solid bands 2-4 tiles thick with floor on both sides (two stacked walls, or two walls with a 1-2 tile
    dark strip between them), counted as 4-connected blobs of band tiles. 1 thick is one shared wall, 5+ plain rock."""
    pr = Probe(layer, size, origin, items, kit, no_walk)
    ramp_ids = {int(i) for key in ("mountain_ramp", "hill_ramp") for v in kit.get(key, {}).values() for i in v}
    floor = {(x, y) for y in range(size) for x in range(size)
             if pr.floor(x, y) or any(int(i) in ramp_ids for i in (pr.stack(x, y) or ()))}
    bad = set()
    for (x, y) in floor:
        for dx, dy in ((1, 0), (0, 1)):
            for t in (2, 3, 4):
                run = [(x + k * dx, y + k * dy) for k in range(1, t + 1)]
                if all(r not in floor for r in run) and (x + (t + 1) * dx, y + (t + 1) * dy) in floor \
                        and all((r[0] + dy, r[1] + dx) not in floor and (r[0] - dy, r[1] - dx) not in floor for r in run):
                    bad.update(run)
    need = {(x + i, y + j) for x, y in floor for i in (-1, 0, 1) for j in (-1, 0, 1)} - floor
    cand = {(x + i, y + j) for x, y in need for i in (-1, 0, 1) for j in (-1, 0, 1)} - need - floor
    bad |= {t for t in cand if sum((t[0] + a, t[1] + b) in need for a, b in ((1, 0), (-1, 0), (0, 1), (0, -1))) >= 3}  # 1-tile rock notch
    seen, blobs = set(), []
    for t in sorted(bad):
        if t in seen:
            continue
        comp, todo = [], [t]
        seen.add(t)
        while todo:
            c = todo.pop()
            comp.append(c)
            for n in ((c[0] + 1, c[1]), (c[0] - 1, c[1]), (c[0], c[1] + 1), (c[0], c[1] - 1)):
                if n in bad and n not in seen:
                    seen.add(n)
                    todo.append(n)
        blobs.append(comp[0])
    return {"wall_bands": len(blobs), "samples": [(origin + x, origin + y) for x, y in blobs[:6]]}


def spurs(layer, size, origin, items, kit, no_walk=(), samples=6):
    """Round 10 `wall_spurs`: wall pieces that stick out of the wall line (the owner's "paredes pra fora"). Kits with a 4-piece wall
    set only (others return 0). Counted per wall tile:
      cap       a corner piece (class C, whose sprite cap hangs one tile over its WEST neighbour) with no wall tile to its west: the
                cap pokes into the floor or the dark cover as a stub (the elbow of every room corner showed it)
      lone      a wall tile with no wall tile on any of its 4 sides, unless it is a door jamb (floor on both sides along a line)
      dead_end  a run end (exactly 1 wall neighbour) whose continuation is not floor: a wall that stops in solid ground (an end
                beside a doorway has floor there and is fine)
      diagonal  a wall tile that touches floor only diagonally and has at most one wall neighbour (a single tile hanging off a corner)
    Returns {"wall_spurs": n, "kinds": {...}, "samples": [(tile x, tile y, kind)]}."""
    out = {"wall_spurs": 0, "kinds": {"cap": 0, "lone": 0, "dead_end": 0, "diagonal": 0}, "samples": []}
    spec = spec_of(kit)
    if not kit.get("walls") or not spec:
        return out
    pr = Probe(layer, size, origin, items, kit, no_walk)
    cls = classes_of(spec)
    wall, kinds = set(), {}
    for y in range(size):
        for x in range(size):
            st = pr.stack(x, y)
            if st:
                hit = [cls[int(i)] for i in st[1:] if int(i) in cls]
                if hit:
                    wall.add((x, y))
                    kinds[(x, y)] = hit
    floor = {(x, y) for y in range(size) for x in range(size) if pr.floor(x, y)}
    walk = lambda t: t in floor or (pr.stack(*t) is not None and 0 <= t[0] < size and 0 <= t[1] < size and pr.ground_floor(*t))
    for t in sorted(wall, key=lambda t: (t[1], t[0])):
        x, y = t
        nb = [(i, j) for i, j in N4 if (x + i, y + j) in wall]
        kind = None
        if "C" in kinds[t] and (x - 1, y) not in wall:
            kind = "cap"
        elif not nb:
            jamb = ((x - 1, y) in floor and (x + 1, y) in floor) or ((x, y - 1) in floor and (x, y + 1) in floor)
            kind = None if jamb else "lone"
        elif len(nb) == 1:
            i, j = nb[0]
            if not walk((x - i, y - j)):
                kind = "dead_end"
        if kind is None and len(nb) <= 1 and not any((x + i, y + j) in floor for i, j in N4) \
                and any((x + i, y + j) in floor for i, j in ((-1, -1), (1, -1), (-1, 1), (1, 1))):
            kind = "diagonal"
        if kind:
            out["wall_spurs"] += 1
            out["kinds"][kind] += 1
            if len(out["samples"]) < samples:
                out["samples"].append((origin + x, origin + y, kind))
    return out


def summary(res):
    return {k: res[k] for k in ("void_touch", "wall_wrong", "wall_missing") + (("wall_gaps",) if "wall_gaps" in res else ())}
