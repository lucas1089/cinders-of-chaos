"""Region shapes shared by the generators: noise blends, distance fields, connected parts, and ramp spots.
"""
from __future__ import annotations

from collections import deque

from lib import N4, clean, noise, touches


def blend(size, rng, parts):
    """Sum of noise layers, parts = [(cell, weight), ...]."""
    layers = [(noise(size, cell, rng), w) for cell, w in parts]
    return [[sum(n[y][x] * w for n, w in layers) for x in range(size)] for y in range(size)]


def distance(size, sources):
    """4-neighbour steps from the nearest True tile of `sources`."""
    dist = [[None] * size for _ in range(size)]
    queue = deque()
    for y in range(size):
        for x in range(size):
            if sources[y][x]:
                dist[y][x] = 0
                queue.append((x, y))
    while queue:
        x, y = queue.popleft()
        for dx, dy in N4.values():
            nx, ny = x + dx, y + dy
            if 0 <= nx < size and 0 <= ny < size and dist[ny][nx] is None:
                dist[ny][nx] = dist[y][x] + 1
                queue.append((nx, ny))
    big = size * 2
    return [[big if d is None else d for d in row] for row in dist]


def parts(size, mask):
    """The 4-connected regions of `mask`, as sets of (x, y)."""
    seen, out = set(), []
    for y in range(size):
        for x in range(size):
            if mask[y][x] and (x, y) not in seen:
                part, queue = set(), deque([(x, y)])
                seen.add((x, y))
                while queue:
                    cx, cy = queue.popleft()
                    part.add((cx, cy))
                    for dx, dy in N4.values():
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < size and 0 <= ny < size and mask[ny][nx] and (nx, ny) not in seen:
                            seen.add((nx, ny))
                            queue.append((nx, ny))
                out.append(part)
    return out


def largest(size, mask):
    """Only the largest 4-connected region of `mask`."""
    best = max(parts(size, mask), key=len, default=set())
    return [[(x, y) in best for x in range(size)] for y in range(size)]


def region(size, field, threshold, allowed):
    """Tiles where field > threshold and allowed(x, y), cleaned for a 12-piece set, then cut back to allowed
    tiles again (cleaning can grow a region) until stable."""
    mask = [[field[y][x] > threshold and allowed(x, y) for x in range(size)] for y in range(size)]
    for _ in range(4):
        clean(mask)
        # the top's rim needs the same of the region's own shape: no 1-wide necks
        inverse = [[not v for v in row] for row in mask]
        clean(inverse, outside=True)
        mask = [[not v for v in row] for row in inverse]
        cut = False
        for y in range(size):
            for x in range(size):
                if mask[y][x] and not allowed(x, y):
                    mask[y][x] = False
                    cut = True
        if not cut:
            break
    # small pits enclosed by the region read as holes: fill them
    for part in parts(size, [[not v for v in row] for row in mask]):
        if len(part) < 40 and not any(x in (0, size - 1) or y in (0, size - 1) for x, y in part):
            for x, y in part:
                mask[y][x] = True
    return mask


def place_ramps(size, hill, free, rng, landing=None, source=None, want=None, taken=(), why=None):
    """{(x, y): (direction, part)} for ramps up the hills, as the reference map places earth ramps (tools/ramp_check.py):
    the ramp on a tile right outside the hill, named for the side the hill is on, its lower half on the next
    tile away. Only on straight stretches of edge (the hill along the ramp's two neighbours too), with the ramp
    tile where free(x, y). A ramp must be usable: the lower half and the approach tile beyond it satisfy
    source (default free) and never touch the hill (a cliff piece there would block them); when given,
    landing(x, y) must hold on the hill tile the ramp leads onto and on the next tile inward, so the player
    arrives on open ground, not against a cliff. One ramp per hill, two when the hill has 60+ tiles; `want`
    sets the count for every hill instead. Ramps stay 8+ tiles from each other and from `taken` ramp tiles."""
    source = source or free
    out = {}
    for part in parts(size, hill):
        spots = []
        for x, y in part:
            for d, (dx, dy) in N4.items():
                rx, ry = x - dx, y - dy           # ramp tile: hill lies on side d of it
                lx, ly = rx - dx, ry - dy         # lower half: one further away
                ax, ay = lx - dx, ly - dy         # approach: where the player stands before climbing
                along = [(rx + dy, ry + dx), (rx - dy, ry - dx)]
                inward = (x + dx, y + dy)
                if not all(0 <= cx < size and 0 <= cy < size
                           for cx, cy in [(rx, ry), (lx, ly), (ax, ay), inward, *along]):
                    continue
                reason = ("in target" if hill[ry][rx] else "ramp tile not free" if not free(rx, ry)
                          else "below not reachable" if not (source(lx, ly) and source(ax, ay))
                          else "below touches target" if touches(hill, lx, ly) or touches(hill, ax, ay)
                          else "landing not clear" if landing and not (landing(x, y) and landing(*inward))
                          else "edge not straight" if not all(hill[cy + dy][cx + dx] and not hill[cy][cx]
                                                             for cx, cy in along)
                          else None)
                if why is not None:
                    why[reason or "ok"] += 1
                if reason:
                    continue
                spots.append((d, (rx, ry), (lx, ly)))
        rng.shuffle(spots)
        count = want if want is not None else 2 if len(part) >= 60 else 1
        for d, ramp, low in spots:
            if count == 0:
                break
            if any(abs(ramp[0] - ox) + abs(ramp[1] - oy) < 8 for ox, oy in [*out, *taken]):
                continue
            out[ramp] = (d, 0)
            out[low] = (d, 1)
            count -= 1
    return out
