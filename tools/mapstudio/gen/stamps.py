"""Structure stamps (kit key `stamps`, round 8): small prefabs laid from tile patterns the kit defines (a barn, a scarecrow
field, rows of fenced graves, the outline of a big top).

kit stamps: [{"name": .., "pattern": ["row", ...], "legend": {char: cell}, "count": [lo, hi], "in": [room themes],
 "margin": tiles kept free round the stamp, "mirror": true}]
A pattern row is one string per tile row; a space is not part of the stamp, and every other character is a tile the stamp
needs free and open. A legend cell is
  {"wall": "<kit stamp_walls key>"}                  a wall tile; the piece follows its neighbours of the same wall
                                                       (horizontal, vertical, corner, pole, end) like gen/walls.py
  {"wall": .., "piece": id}                          a fixed piece that counts as wall for its neighbours (a door, a window)
  {"ground": [ids], "items": [ids], "chance": p}     ground under the tile, and one item on it (chance p, default 1)
  {}                                                 plain ground (the stamp's footprint stays clear)
kit stamp_walls: {"<name>": {"h": [id], "v": [id], "corner": id, "pole": id, "end_h": id, "end_v": id}} (the shape of kit walls).
Items stand on their anchor tile (a bigger sprite hangs up and left), as everywhere in the generator.
Where: `in` lists room theme names (dungeon kits); without it the stamp goes on open land (`sites` the caller passes).
Existing decor inside the footprint is cleared (ground and border pieces stay). The ids come back for the access repair.
"""
from __future__ import annotations

import wallcheck


def wall_piece(spec, cls):
    return {"H": int(spec["h"][0]), "V": int(spec["v"][0]), "C": int(spec["corner"]), "P": int(spec["pole"]),
            "EH": int(spec.get("end_h", spec["pole"])), "EV": int(spec.get("end_v", spec["pole"]))}[cls]


def cells_of(spec, mirror):
    rows = [r[::-1] for r in spec["pattern"]] if mirror else list(spec["pattern"])
    w = max(len(r) for r in rows)
    rows = [r.ljust(w) for r in rows]
    return {(x, y): c for y, r in enumerate(rows) for x, c in enumerate(r) if c != " "}, w, len(rows)


def lay(layer, size, origin, kit, rng, sites, keep_ids=frozenset()):
    """sites: list of (label, free tiles set). Returns (set of tiles used, set of item ids placed, count placed)."""
    used, ids, placed = set(), set(), 0
    for spec in kit.get("stamps") or []:
        margin = spec.get("margin", 1)
        pools = [free for label, free in sites if not spec.get("in") or label in spec["in"]]
        for _ in range(rng.randint(*spec.get("count", [1, 1]))):
            cells, w, h = cells_of(spec, bool(spec.get("mirror") and rng.random() < 0.5))
            need = {(x + i, y + j) for x, y in cells for i in range(-margin, margin + 1) for j in range(-margin, margin + 1)}
            cand = sorted({(fx - ox, fy - oy) for free in pools for fx, fy in free for ox, oy in [(0, 0)]
                           if all((fx + dx, fy + dy) in free and (fx + dx, fy + dy) not in used for dx, dy in need)})
            if not cand:
                break
            ox, oy = rng.choice(cand)
            tiles = {(ox + x, oy + y): c for (x, y), c in cells.items()}
            if any(t in used for t in tiles):
                continue
            walls = {}
            for t, c in tiles.items():
                cell = spec["legend"].get(c, {})
                if cell.get("wall"):
                    walls.setdefault(cell["wall"], set()).add(t)
            for t, c in sorted(tiles.items(), key=lambda a: (a[0][1], a[0][0])):
                cell = spec["legend"].get(c, {})
                st = layer.get((origin + t[0], origin + t[1]))
                if st is None:
                    continue
                st[1:] = [i for i in st[1:] if int(i) in keep_ids]
                if cell.get("ground"):
                    st[0] = int(rng.choice(cell["ground"]))
                if cell.get("wall"):
                    group = walls[cell["wall"]]
                    wspec = kit["stamp_walls"][cell["wall"]]
                    if cell.get("piece"):
                        pid = int(cell["piece"])
                    else:
                        cls = wallcheck.expected_class((t[0], t[1] - 1) in group, (t[0] + 1, t[1]) in group,
                                                       (t[0], t[1] + 1) in group, (t[0] - 1, t[1]) in group,
                                                       bool(wspec.get("end_h") and wspec.get("end_v")))
                        pid = wall_piece(wspec, cls)
                    st.append(pid)
                    ids.add(pid)
                elif cell.get("items") and rng.random() < cell.get("chance", 1.0):
                    pid = int(rng.choice(cell["items"]))
                    st.append(pid)
                    ids.add(pid)
            used |= set(tiles) | {(x + i, y + j) for x, y in tiles for i in (-1, 0, 1) for j in (-1, 0, 1)}
            placed += 1
    return used, ids, placed
