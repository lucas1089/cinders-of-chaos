"""Liquid pools (kit key `pools`, round 8): blob-shaped patches of a liquid ground on open land, each with its own border.

kit pools: [{"ground": [ids of the liquid ground], "border": "<kit 12-piece set laid on the land around the pool>",
 "share": share of the allowed land, "scale": blob radius in tiles (3 small, 6 big), "min": smallest blob,
 "decor": {id: rate} (items on the pool's land rim, e.g. bones)}]
The liquid grounds are not walkable (the caller adds them to access.NO_WALK). A pool keeps 2 tiles from anything the
caller does not allow (shore, cliffs, ramps, walls) so its border pieces have room. Pools come out as rounded blobs (lib.clean).
"""
from __future__ import annotations

from shapes import blend, parts
import lib
from lib import edge_pieces


def lay(layer, size, origin, kit, rng, allowed, pick):
    """Returns (set of pool tiles, set of liquid ground ids)."""
    specs = kit.get("pools") or []
    taken, ids = set(), set()
    for spec in specs:
        scale = spec.get("scale", 4)  # blob radius in tiles (half the blob's width)
        field = blend(size, rng, [(max(2, scale // 2), 0.7), (2, 0.3)])

        def inner(x, y):
            return all(0 <= x + i < size and 0 <= y + j < size and allowed(x + i, y + j) and (x + i, y + j) not in taken
                       for i in (-1, 0, 1) for j in (-1, 0, 1))
        tiles = [(x, y) for y in range(size) for x in range(size) if inner(x, y)]
        if not tiles:
            continue
        want = max(1, round(spec.get("share", 0.03) * len(tiles) / (3.14 * scale * scale * 0.8)))
        mask = [[False] * size for _ in range(size)]
        centres = []
        for _ in range(want * 12):
            if len(centres) >= want:
                break
            cx, cy = rng.choice(tiles)
            if any(abs(cx - ax) + abs(cy - ay) < scale * 2.6 for ax, ay in centres):
                continue
            rx, ry = scale * rng.uniform(0.8, 1.3), scale * rng.uniform(0.8, 1.3)
            blob = [(x, y) for y in range(max(0, int(cy - ry * 1.4)), min(size, int(cy + ry * 1.4) + 1))
                    for x in range(max(0, int(cx - rx * 1.4)), min(size, int(cx + rx * 1.4) + 1))
                    if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 < 1 + (field[y][x] - 0.5) * 0.9 and inner(x, y)]
            if len(blob) < spec.get("min", 6):
                continue
            centres.append((cx, cy))
            for x, y in blob:
                mask[y][x] = True
        for part in parts(size, mask):
            if len(part) < spec.get("min", 6):
                for x, y in part:
                    mask[y][x] = False
        lib.clean(mask)
        pool = {(x, y) for y in range(size) for x in range(size) if mask[y][x]}
        if any(not allowed(x, y) for x, y in pool):  # a cleaned-in tile outside the allowed land: drop that tile's blob part
            bad = {t for t in pool if not allowed(*t)}
            for part in parts(size, mask):
                if set(part) & bad:
                    for x, y in part:
                        mask[y][x] = False
            pool = {(x, y) for y in range(size) for x in range(size) if mask[y][x]}
        border = kit.get(spec.get("border")) if spec.get("border") else None
        for x, y in sorted(pool):
            layer[(origin + x, origin + y)] = [int(rng.choice(spec["ground"]))]
        rim = {(x + i, y + j) for x, y in pool for i, j in ((0, 1), (1, 0), (0, -1), (-1, 0), (1, 1), (-1, 1), (1, -1), (-1, -1))} - pool
        for x, y in sorted(rim):
            st = layer.get((origin + x, origin + y))
            if st is None:
                continue
            if border:
                for k, piece in enumerate(edge_pieces(mask, x, y, border)):
                    st.insert(1 + k, int(piece))
            for key, rate in spec.get("decor", {}).items():
                if rng.random() < rate:
                    st.append(int(key))
                    break
        taken |= pool | rim
        ids |= {int(i) for i in spec["ground"]}
    return taken, ids
