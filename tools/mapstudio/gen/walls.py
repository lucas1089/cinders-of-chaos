"""Straight walls from a floor mask (round 8, kit key `walls`).

For a set of floor tiles, every tile beside the floor (4 neighbours, plus the tile closing a convex corner) gets one
wall piece of the kit's set, chosen from its neighbours' wall tiles (gen/wallcheck.py expected_class): horizontal and
vertical runs, the corner piece where a wall turns east and south, poles at the other corners and junctions, end pieces
where a run stops at a doorway. Windows and broken pieces (`variants`) replace single run pieces now and then. The tiles
behind the walls get solid ground for `cover` more rings, so no void touches a wall or the floor.

Kit key `walls`: {"h": [id], "v": [id], "corner": id, "pole": id, "end_h": id, "end_v": id,
                  "variants": {"h": {id: share}, "v": {id: share}}, "cover": 2, "solid": ground spec (default: the kit's liquid)}
The 16-piece wall sets of pack 30 are laid out base+0 post, +1 horizontal, +2 vertical, +3 corner, +4 end (horizontal),
+5 end (vertical), +6 / +7 door, +8 / +9 open door, +10 / +11 window, +12 / +13 broken (see wall_spec()).
"""
from __future__ import annotations

import wallcheck


def wall_spec(base, windows=0.0, broken=0.0, cover=2, solid=None):
    """The `walls` key for a pack 30 wall set whose post sits at id `base`."""
    spec = {"h": [base + 1], "v": [base + 2], "corner": base + 3, "pole": base, "end_h": base + 4, "end_v": base + 5,
            "cover": cover}
    var = {"h": {}, "v": {}}
    if windows:
        var["h"][str(base + 10)] = windows
        var["v"][str(base + 11)] = windows
    if broken:
        var["h"][str(base + 12)] = broken
        var["v"][str(base + 13)] = broken
    if windows or broken:
        spec["variants"] = var
    if solid:
        spec["solid"] = solid
    return spec


def build(floor, size, spec, rng, keep_clear=()):
    """Returns ({tile: wall piece id}, {tiles that take solid ground: walls plus the cover rings}).
    `keep_clear` tiles never get a variant piece."""
    need = wallcheck.wall_tiles(floor, size)
    ends = bool(spec.get("end_h") and spec.get("end_v"))
    cls = wallcheck.classify(need, ends)
    pole, corner = int(spec["pole"]), int(spec["corner"])
    runs = {"H": [int(i) for i in spec["h"]], "V": [int(i) for i in spec["v"]]}
    single = {"C": corner, "P": pole, "EH": int(spec.get("end_h", pole)), "EV": int(spec.get("end_v", pole))}
    var = spec.get("variants", {})
    pieces, picked = {}, set()
    for t in sorted(cls, key=lambda t: (t[1], t[0])):
        c = cls[t]
        if c in single:
            pieces[t] = single[c]
            continue
        ids = runs[c]
        pid = ids[0] if len(ids) == 1 else rng.choice(ids)
        table = var.get("h" if c == "H" else "v", {})
        if table and t not in keep_clear and not any((t[0] + i, t[1] + j) in picked for i in (-1, 0, 1) for j in (-1, 0, 1)):
            for key, share in table.items():
                if rng.random() < share:
                    pid = int(key)
                    picked.add(t)
                    break
        pieces[t] = pid
    ground = set(pieces)
    ring = set(pieces)
    for _ in range(spec.get("cover", 2)):
        ring |= {(x + i, y + j) for x, y in ring | floor for i in (-1, 0, 1) for j in (-1, 0, 1)
                 if 0 <= x + i < size and 0 <= y + j < size and (x + i, y + j) not in floor}
    solid = (ring - floor) | ground
    # void pockets the cover rings leave between two buildings (no way out to the area's edge) are filled: they would show
    # as black holes inside the dark ground
    seen = set()
    queue = [(x, y) for y in range(size) for x in range(size) if (x in (0, size - 1) or y in (0, size - 1))
             and (x, y) not in solid and (x, y) not in floor]
    seen.update(queue)
    while queue:
        x, y = queue.pop()
        for i in (-1, 0, 1):
            for j in (-1, 0, 1):
                t = (x + i, y + j)
                if 0 <= t[0] < size and 0 <= t[1] < size and t not in seen and t not in solid and t not in floor:
                    seen.add(t)
                    queue.append(t)
    solid |= {(x, y) for y in range(size) for x in range(size) if (x, y) not in solid and (x, y) not in floor
              and (x, y) not in seen}
    return pieces, solid
