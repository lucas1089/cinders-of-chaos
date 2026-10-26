"""Kit-driven hunting island generator: coast, lakes, rivers, stacked mountain levels with ramps, passes and
crossings, layered ground borders, roads and patches, and clumped vegetation, all checked for reachability.

python -B run.py gen/generate.py --kit <name> [--name island-v10] [--size 96] [--seed 1] [knobs, see --help]
The kit (kit/<name>.json) gives the items and learned numbers: first learned from the reference map's jungle
(base ground with sand roads joining the ramps and the shore, worn patches inside the sand, rock soil and
gravel aprons at cliff feet), then its lava caves (a volcanic island in a lava sea crossed by crust fords).
Plants grow by family at the reference rates, denser near edges (tools/edge_density.py). Writes
areas/<name>/area.txt (with the knobs and run stats in its header) and render.png, and prints a summary.
"""
from __future__ import annotations

import argparse
import heapq
import json
import random
import subprocess
import sys
from collections import Counter, deque

import access
from common import ROOT, kit_name, load_items, load_kit, save_area, water_ids
from shapes import blend, distance, largest, parts, place_ramps, region
from lib import (break_runs, clean, edge_pieces, open_shape, pinched, place_clumped, place_flora, rank_field,
                 roughen, route_corridors, touches, weighted)

Z = 7
ORIGIN = 1000


TERRACE = {1: 2, 2: 2}  # level index -> tiles it stays inside the level below (tools/relief_study.py)


def terrace_step(k):
    """How far level index k (1 = level 2) stays inside the one below. The reference map's terraces are narrow at every
    height (level 3 edges: 33% one tile, 31% two tiles from the drop); a 2-tile step plus stacked faces
    (mountain_levels) gives the 1-tile look."""
    return TERRACE.get(k, 2)


def ramp_windows(size, mask, rng, spacing=8, room=None):
    """Tiles to keep out of roughening so ramps can still be placed: on straight stretches of each patch's
    edge (the tile outside and its two neighbours along the edge all face the patch), a 3-wide window from 3
    tiles outside (approach, lower half, ramp) to 2 tiles inside (landing and the tile after it), where
    room(x, y) holds on the 3 outside tiles (e.g. they lie on the level below). About one window per 50
    tiles of patch, at least 2, spaced apart."""
    out = set()
    for part in parts(size, mask):
        spots = []
        for x, y in part:
            for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0)):
                rx, ry = x - dx, y - dy
                along = [(rx + dy, ry + dx), (rx - dy, ry - dx)]
                if not all(0 <= cx < size and 0 <= cy < size and 0 <= cx + dx < size and 0 <= cy + dy < size
                           for cx, cy in [(rx, ry), *along]):
                    continue
                outside = [(x - t * dx, y - t * dy) for t in (1, 2, 3)]
                if room and not all(0 <= ox < size and 0 <= oy < size and room(ox, oy) for ox, oy in outside):
                    continue
                if not mask[ry][rx] and all(mask[cy + dy][cx + dx] and not mask[cy][cx] for cx, cy in along):
                    spots.append((x, y, dx, dy))
        rng.shuffle(spots)
        chosen = []
        for x, y, dx, dy in spots:
            if len(chosen) >= max(2, len(part) // 50):
                break
            if all(abs(x - cx) + abs(y - cy) >= spacing for cx, cy, _, _ in chosen):
                chosen.append((x, y, dx, dy))
        for x, y, dx, dy in chosen:
            for a in (-1, 0, 1):
                for t in range(-3, 3):
                    out.add((x + a * dy + t * dx, y + a * dx + t * dy))
    return out


def quantile_region(size, field, share, allowed):
    """region() over the tiles where allowed(), cut so about `share` of them are inside."""
    values = sorted(field[y][x] for y in range(size) for x in range(size) if allowed(x, y))
    if share <= 0 or not values:
        return [[False] * size for _ in range(size)]
    return region(size, field, values[int(len(values) * (1 - min(share, 0.99)))], allowed)


def layout(size, rng, p):
    """Masks: water (sea, lakes, rivers), mountain levels, hill. Grounds come later (grounds())."""
    c = (size - 1) / 2
    r = p.rough / 100  # rough edges: share of fine noise in the coastline
    shape = blend(size, rng, [(24, 1 - 0.5 * r), (8, 0.45 * r), (3, 0.15 * r)])
    # a full island: open sea 5+ tiles wide along every edge of the area
    margin = lambda x, y: min(x, y, size - 1 - x, size - 1 - y) >= 5
    land = [[margin(x, y) and shape[y][x] - ((((x - c) ** 2 + (y - c) ** 2) ** 0.5) / c) ** 3 * 0.8 > 0.05
             for x in range(size)] for y in range(size)]
    land = largest(size, land)
    sea = largest(size, [[not v for v in row] for row in land])
    for part in parts(size, [[not land[y][x] and not sea[y][x] for x in range(size)] for y in range(size)]):
        if len(part) < 40:
            for x, y in part:
                land[y][x] = True
    shore = distance(size, [[not v for v in row] for row in land])
    # lakes: inland blobs, about lakes% of the inland tiles
    lakes = quantile_region(size, blend(size, rng, [(12, 0.6), (5, 0.4)]), p.lakes / 100,
                            lambda x, y: shore[y][x] >= 5)
    for part in parts(size, lakes):
        if len(part) < 20:  # ponds read as holes
            for x, y in part:
                lakes[y][x] = False
    water = [[not land[y][x] or lakes[y][x] for x in range(size)] for y in range(size)]
    clean(water, outside=True)
    roughen(water, rng, outside=True, allowed=lambda x, y: margin(x, y) or water[y][x])
    shore = distance(size, water)

    # mountains: one elevation field cut into up to `levels` levels (tools/relief_study.py): level 1 about
    # mountains% of the inland tiles, each next level about half (then less) of the one below
    rock = blend(size, rng, [(16, 0.55), (6, 0.3), (3, 0.15)])
    on_land = sorted(rock[y][x] for y in range(size) for x in range(size) if shore[y][x] >= 5)
    # most mountains keep off the shore, but where a coarse noise field is high they run down into the water
    # (reference map: ~13% of water edges are mountain cliffs, the cliff pieces drawn on the water tiles)
    sea_cliff = blend(size, rng, [(14, 0.7), (6, 0.3)])
    levels, below = [], lambda x, y: shore[y][x] >= 5 or (shore[y][x] >= 1 and sea_cliff[y][x] > 1 - p.sea_cliffs / 100)
    level_field = rock
    for keep in (p.mountains / 100, 0.5, 0.35, 0.3, 0.3)[:p.levels]:
        if keep <= 0:
            break
        cut = on_land[int(len(on_land) * (1 - keep))]
        mask = region(size, level_field, cut, below)
        if not levels:  # sea cliffs: where the sea-cliff field is high, mountains near the water grow out to it
            # and coastal headlands 3-6 tiles deep rise from the shore
            reach = distance(size, mask)
            depth = blend(size, rng, [(6, 1.0)])
            cut_sea = 1 - p.sea_cliffs / 100
            for y in range(size):
                for x in range(size):
                    if mask[y][x] or shore[y][x] < 1 or sea_cliff[y][x] <= cut_sea:
                        continue
                    if (shore[y][x] <= 6 and reach[y][x] <= 6) or shore[y][x] <= 3 + 3 * depth[y][x]:
                        mask[y][x] = True
            clean(mask)
            for y in range(size):
                for x in range(size):
                    mask[y][x] = mask[y][x] and shore[y][x] >= 1
        # a ramp needs a straight 3-tile cliff to sit in; keep a few such windows per patch out of roughening
        if levels:  # the 3 tiles below the ramp lie on the level below, the ramp tile off its rim
            prev_in = distance(size, [[not v for v in row] for row in levels[-1]])
            room = lambda x, y, prev_in=prev_in: prev_in[y][x] >= 1
        else:
            room = lambda x, y: shore[y][x] >= 2
        open_shape(mask)  # no necks or spurs: tops stay walkable, shapes stay solid
        seats = ramp_windows(size, mask, rng, room=room)
        roughen(mask, rng, allowed=lambda x, y, below=below: below(x, y) and (x, y) not in seats)
        for part in parts(size, mask):  # lone pillars of a few tiles read as stray blocks
            if len(part) < 8:
                for x, y in part:
                    mask[y][x] = False
        if sum(map(sum, mask)) < 12:
            break
        levels.append(mask)
        inside = distance(size, [[not v for v in row] for row in mask])
        # the next level follows its own noise, only partly the rock field: it rises as an off-centre chunk
        # with a broad plateau beside it, as on the reference map (tools/path_study.py: 79% of the reference map's level-1 top tiles
        # away from cliffs lie in open space 9+ wide), not as a concentric ring leaving a thin ledge all round
        fresh = blend(size, rng, [(10, 0.6), (4, 0.4)])
        level_field = [[0.35 * level_field[y][x] + 0.65 * fresh[y][x] for x in range(size)] for y in range(size)]
        on_land = sorted(level_field[y][x] for y in range(size) for x in range(size) if mask[y][x])
        # reference map: many 1-2 tile terraces; above level 2 that piles cliffs into a dark mass, so 3+
        step = terrace_step(len(levels))
        below = lambda x, y, inside=inside, step=step: inside[y][x] >= step
    mountain = levels[0] if levels else [[False] * size for _ in range(size)]
    near_mountain = distance(size, mountain)

    # rivers: from inland springs beside a mountain down to the sea along the cheapest path through low rock
    # and a strong noise field (meanders), kept 4+ tiles off other water so rivers do not merge into bays;
    # the course is smoothed and drawn with a round brush exactly `river_width` across
    river = set()
    for _ in range(p.rivers):
        near_water = distance(size, water)
        springs = [(x, y) for y in range(size) for x in range(size)
                   if shore[y][x] >= 8 and near_mountain[y][x] in (2, 3)]
        mouths = [(x, y) for y in range(size) for x in range(size) if shore[y][x] == 1]
        if not springs or not mouths:
            break
        # a long river: the spring among the most inland quarter of candidates, the mouth a quarter of the map
        # or more away (a spring near the coast gave rivers of a few tiles)
        springs.sort(key=lambda t: -shore[t[1]][t[0]])
        start = rng.choice(springs[:max(1, len(springs) // 4)])
        far = [t for t in mouths if abs(t[0] - start[0]) + abs(t[1] - start[1]) >= size // 4]
        goal = rng.choice(far or mouths)
        bend = blend(size, rng, [(6, 0.5), (3, 0.5)])
        path = road_path(size, start, goal, lambda x, y: None if near_mountain[y][x] < 2
                         else 1 + 4 * rock[y][x] + 16 * bend[y][x] ** 2 + (20 if 1 < near_water[y][x] < 4 else 0))
        r = (p.river_width - 1) / 2
        for x, y in smooth_course(path):
            for j in range(-int(r) - 1, int(r) + 2):
                for i in range(-int(r) - 1, int(r) + 2):
                    if (i * i + j * j <= r * r + 0.25 and 0 <= x + i < size and 0 <= y + j < size
                            and near_mountain[y + j][x + i] >= 2):
                        water[y + j][x + i] = True
                        river.add((x + i, y + j))
        clean(water, outside=True)
        for part in parts(size, [[not v for v in row] for row in water]):  # scraps cut off at river mouths
            if len(part) < 30:
                for x, y in part:
                    water[y][x] = True
        for y in range(size):  # cleaning must not push water under a mountain
            for x in range(size):
                if mountain[y][x]:
                    water[y][x] = False
        shore = distance(size, water)
    if river:  # river banks get the same staircase outline as the coast, never under a mountain, and never
        # across a few straight stretches kept as bridge windows (a bridge needs the same water run on every line)
        river = {(x, y) for x, y in river if water[y][x]}
        flat = [[False] * size for _ in range(size)]
        # at most 2 windows per river: unused windows keep straight banks (user review, seed 102 short river)
        windows = spaced(bridge_sites(size, {"water": water, "river": river, "mountain": mountain, "hill": flat}, rng),
                         2 * p.rivers, gap=10)
        protected = {t for b in windows for t in b.guard()}
        near_river = {(x + i, y + j) for x, y in river for i in range(-2, 3) for j in range(-2, 3)}
        roughen(water, rng, allowed=lambda x, y: (x, y) in near_river and near_mountain[y][x] >= 2
                and (x, y) not in protected, outside=True)
        shore = distance(size, water)

    # no land spit too thin for the shore set (user review, seeds 102 and 108): clean's pinch rule turns every
    # such land tile into water. (An opening of the land did this too, but shaved the coast's staircase bumps
    # off again: shore runs 0.02 -> 0.10.)
    clean(water, outside=True)
    for y in range(size):
        for x in range(size):
            water[y][x] = water[y][x] and not mountain[y][x]
    shore = distance(size, water)

    lift = blend(size, rng, [(10, 0.7), (4, 0.3)])
    hill_ok = lambda x, y: shore[y][x] >= 4 and near_mountain[y][x] >= 5
    hill = quantile_region(size, lift, p.hills / 100, hill_ok)
    open_shape(hill)
    roughen(hill, rng, allowed=hill_ok)
    for part in parts(size, hill):  # 2x2 tops read as stray blocks
        if len(part) < 12:
            for x, y in part:
                hill[y][x] = False
    passes = carve_passes(size, water, levels, hill, rng, shore_blocks=not getattr(p, "water_low", False))
    sealed = seal_pockets(size, water, levels, hill, rng, river)
    # a last staircase pass on every level: passes, sealing and terrace clamps reshape the levels after their
    # first roughening and leave straight cliffs (cliff edge pieces 0.42, runs of 4+ 0.13; the reference map 0.35 and 0.00)
    for k, lv in enumerate(levels):
        if k == 0:
            ok = lambda x, y: not water[y][x]
        else:
            inside = distance(size, [[not v for v in row] for row in levels[k - 1]])
            ok = lambda x, y, inside=inside, step=terrace_step(k): inside[y][x] >= step
        break_runs(lv, rng, allowed=ok, mode="shrink" if k else "both")
        if k == 0:  # a water tile the mountain now pinches (a 1-wide inlet) becomes rock: the cliff runs on
            clean(lv)
            for y in range(size):
                for x in range(size):
                    if lv[y][x]:
                        water[y][x] = False
        for j in range(k + 1, len(levels)):  # keep every higher level its terrace step inside the one below
            inside_j = distance(size, [[not v for v in row] for row in levels[j - 1]])
            step_j = terrace_step(j)
            for y in range(size):
                for x in range(size):
                    levels[j][y][x] = levels[j][y][x] and inside_j[y][x] >= step_j
            clean(levels[j])
            for y in range(size):
                for x in range(size):
                    levels[j][y][x] = levels[j][y][x] and inside_j[y][x] >= step_j
    if getattr(p, "water_low", False):
        # the kit's liquid is its lowest layer (fire): the land draws its border onto the liquid's tiles, so a
        # liquid tile pinched by land (a 1-wide inlet or notch) would carry pieces facing both ways. Clean the land
        # shape instead of the water shape: such tiles become land.
        land = [[not v for v in row] for row in water]
        clean(land)
        for y in range(size):
            for x in range(size):
                water[y][x] = not land[y][x]
        shore = distance(size, water)
    # the staircase grows level 1 too, and the land clean above fills lava notches: a way that was water at the
    # first carving can now be shut by cliffs (fire seed 108: a 220-tile shelf behind new cliff bumps). Carve again;
    # carve_passes only shrinks the relief
    passes += carve_passes(size, water, levels, hill, rng, shore_blocks=not getattr(p, "water_low", False))
    mountain = levels[0] if levels else mountain
    # earth hills and grey mountains never meet: their cliffs would overlap (user review, seed 105). Sea cliffs,
    # passes and sealing move the mountain after the hills were laid, so check again at the end.
    # square distance 4: the hill's cliff ring, one free tile, the mountain's cliff ring (a step count let
    # diagonal neighbours through and the two cliffs shared tiles)
    for y in range(size):
        for x in range(size):
            if hill[y][x] and any(0 <= x + i < size and 0 <= y + j < size and mountain[y + j][x + i]
                                  for i in range(-4, 5) for j in range(-4, 5)):
                hill[y][x] = False
    clean(hill)
    for part in parts(size, hill):
        if len(part) < 12:
            for x, y in part:
                hill[y][x] = False
    river ={(x, y) for x, y in river if water[y][x]}
    return {"water": water, "mountain": mountain, "levels": levels, "hill": hill, "shore": shore, "river": river,
            "passes": passes, "sealed": sealed}


def seal_pockets(size, water, levels, hill, rng, river=(), least=20):
    """Small ground pockets that relief and water shut off from the main ground (a headland closing a bay,
    a cliff meeting a lake) join the mountain: the pocket and the blocked shore and cliff-foot tiles around
    it become level 1, so the rock runs down into the water there, as on the reference map, instead of leaving a walkable
    patch nobody can reach. Pockets of `least`+ tiles, and pockets on a river (bridges reach those), are left.
    The sealed rock is roughened like every other outline. Edits levels[0] in place; returns how many tiles
    were sealed."""
    if not levels:
        return 0
    lv = levels[0]
    relief = lambda x, y: lv[y][x] or hill[y][x]
    walk = lambda x, y: (not water[y][x] and not relief(x, y) and not touches(water, x, y)
                         and not touches(lv, x, y) and not touches(hill, x, y))
    regions = sorted(parts8(size, walk), key=len, reverse=True)
    near_river = {(x + i, y + j) for x, y in river for i in range(-3, 4) for j in range(-3, 4)}
    grown = set()
    for part in regions[1:]:
        if len(part) >= least or part & near_river:
            continue
        grow = {(x + i, y + j) for x, y in part for i in (-1, 0, 1) for j in (-1, 0, 1)}
        for x, y in grow:
            if 0 <= x < size and 0 <= y < size and not water[y][x] and not hill[y][x] and not lv[y][x]:
                lv[y][x] = True
                grown.add((x, y))
    if grown:
        clean(lv)
        area = {(x + i, y + j) for x, y in grown for i in (-2, -1, 0, 1, 2) for j in (-2, -1, 0, 1, 2)}
        roughen(lv, rng, allowed=lambda x, y: (x, y) in area and not water[y][x] and not hill[y][x])
        for y in range(size):  # never into the water
            for x in range(size):
                lv[y][x] = lv[y][x] and not water[y][x]
    return len(grown)


def join_landmass(size, m, big, stray, rng, gap, keep=()):
    """A land neck from the joined ground to a landmass that nothing else reaches (no bridge site fits): the
    cheapest way over water (a water tile costs 3, a land tile 1, relief and `keep` tiles are never crossed) from
    `big` to the nearest region of `stray`; the water on it, brushed 5 wide so a 3-wide walkable lane stays
    between the shore pieces, becomes land, and the new shores get the staircase outline. Needs a way over at
    most `gap` water tiles, else nothing is cut. Edits m (water, river, shore) in place; returns the water
    tiles turned to land (0 = no neck)."""
    water, river = m["water"], m["river"]
    relief = lambda x, y: m["mountain"][y][x] or m["hill"][y][x]
    other = {t for part in stray for t in part}
    best, prev = {t: 0 for t in big}, {}
    queue = [(0, t) for t in big]
    heapq.heapify(queue)
    goal = None
    while queue:
        d, (x, y) = heapq.heappop(queue)
        if (x, y) in other:
            goal = (x, y)
            break
        if d > best[(x, y)]:
            continue
        for i, j in ((0, 1), (1, 0), (0, -1), (-1, 0)):
            nx, ny = x + i, y + j
            if not (2 <= nx < size - 2 and 2 <= ny < size - 2) or relief(nx, ny) or (nx, ny) in keep:
                continue
            step = 3 if water[ny][nx] else 1
            if d + step < best.get((nx, ny), 1e18):
                best[(nx, ny)], prev[(nx, ny)] = d + step, (x, y)
                heapq.heappush(queue, (d + step, (nx, ny)))
    if not goal:
        return 0
    path, t = [], goal
    while t in prev:
        path.append(t)
        t = prev[t]
    wet = sum(1 for x, y in path if water[y][x])
    if not wet or wet > gap:  # no water on the way: relief or shore pieces shut it, not water
        return 0
    turned, area = 0, set()
    for x, y in path:
        if not water[y][x]:
            continue
        for i in range(-2, 3):
            for j in range(-2, 3):
                nx, ny = x + i, y + j
                if i * i + j * j <= 6 and 0 <= nx < size and 0 <= ny < size and water[ny][nx] \
                        and not relief(nx, ny) and (nx, ny) not in keep:
                    water[ny][nx] = False
                    river.discard((nx, ny))
                    turned += 1
                    area |= {(nx + a, ny + b) for a in range(-3, 4) for b in range(-3, 4)}
    clean(water, outside=True)
    roughen(water, rng, allowed=lambda x, y: (x, y) in area and not relief(x, y) and (x, y) not in keep,
            outside=True, mode="shrink")
    m["shore"] = distance(size, water)
    return turned


def ground_regions(size, water, levels, hill, least=60, shore_blocks=True):
    """Big regions of ground that will be walkable (shore and cliff pieces block their tiles), largest first.
    shore_blocks=False when the land's border onto the water is walkable (lava: water is the lowest layer)."""
    mountain = levels[0] if levels else [[False] * size for _ in range(size)]
    walk = [[not water[y][x] and not mountain[y][x] and not hill[y][x]
             and not (shore_blocks and touches(water, x, y))
             and not touches(mountain, x, y) and not touches(hill, x, y) for x in range(size)] for y in range(size)]
    return sorted((part for part in parts(size, walk) if len(part) >= least), key=len, reverse=True)


def carve_passes(size, water, levels, hill, rng, tries=40, shore_blocks=True):
    """Mountain passes, so ranges never cut the ground in two: while the walkable ground falls into several
    regions that relief (not water: rivers get bridges) separates, a 5-wide valley is cut along the cheapest
    path through the relief from the largest region to the nearest other one. Higher levels are cut back to
    stay 2+ tiles inside the level below; scraps under 8 tiles are dropped. Edits the masks in place and
    returns how many passes were cut. shore_blocks as in ground_regions (lava shores are walkable)."""
    cut, carved = 0, set()
    for _ in range(tries):
        regions = ground_regions(size, water, levels, hill, 20, shore_blocks)
        if len(regions) < 2:
            break
        home, other = regions[0], {t for part in regions[1:] for t in part}
        relief = lambda x, y: (levels and levels[0][y][x]) or hill[y][x]
        best, prev = {t: 0 for t in home}, {}
        queue = [(0, t) for t in home]
        heapq.heapify(queue)
        goal = None
        while queue:
            d, (x, y) = heapq.heappop(queue)
            if (x, y) in other:
                goal = (x, y)
                break
            if d > best[(x, y)]:
                continue
            for i, j in ((0, 1), (1, 0), (0, -1), (-1, 0)):
                nx, ny = x + i, y + j
                # never along tiles touching water: they hold shore pieces, which block, whether cut or not
                if not (0 <= nx < size and 0 <= ny < size) or water[ny][nx] or (shore_blocks
                                                                                and touches(water, nx, ny)):
                    continue
                step = 1 + (4 + sum(lv[ny][nx] for lv in levels) if relief(nx, ny) else 0)
                if d + step < best.get((nx, ny), 1e18):
                    best[(nx, ny)], prev[(nx, ny)] = d + step, (x, y)
                    heapq.heappush(queue, (d + step, (nx, ny)))
        if not goal:
            break  # only water separates them: bridges' job
        path, t = [], goal
        while t in prev:
            path.append(t)
            t = prev[t]
        for x, y in path:
            if not relief(x, y) and not any(relief(x + i, y + j) for i in (-1, 0, 1) for j in (-1, 0, 1)
                                            if 0 <= x + i < size and 0 <= y + j < size):
                continue
            for i in range(-2, 3):
                for j in range(-2, 3):
                    # a round brush: a square one left straight canyon walls (user review, seed 105)
                    if i * i + j * j <= 6 and 0 <= x + i < size and 0 <= y + j < size:
                        for lv in levels:
                            lv[y + j][x + i] = False
                        hill[y + j][x + i] = False
                        carved.add((x + i, y + j))
        for k, lv in enumerate(levels):
            if k:
                inside = distance(size, [[not v for v in row] for row in levels[k - 1]])
                step = terrace_step(k)
                for y in range(size):
                    for x in range(size):
                        lv[y][x] = lv[y][x] and inside[y][x] >= step
            clean(lv)
            if k:
                for y in range(size):
                    for x in range(size):
                        lv[y][x] = lv[y][x] and levels[k - 1][y][x]
            for part in parts(size, lv):
                if len(part) < 8:
                    for x, y in part:
                        lv[y][x] = False
        cut += 1
    if carved:  # pass walls get the same staircase outline as every other cliff; only shrinking, so passes
        # never close again
        around = {(x + i, y + j) for x, y in carved for i in range(-3, 4) for j in range(-3, 4)}
        for k, lv in enumerate(levels):
            roughen(lv, rng, allowed=lambda x, y: (x, y) in around, mode="shrink")
            if k:
                for y in range(size):
                    for x in range(size):
                        lv[y][x] = lv[y][x] and levels[k - 1][y][x]
        roughen(hill, rng, allowed=lambda x, y: (x, y) in around, mode="shrink")
    while levels and not any(map(any, levels[-1])):
        levels.pop()
    return cut


class Bridge:
    """A wooden bridge as the reference map builds them (refs/bridge-ew11, refs/bridge-ns, tools/bridge_scan.py).
    Along the crossing: the lip on the inland tile before the near bank (laid over its own ground and borders),
    deck over the near bank and the water, the end piece on the far bank tile. Beside the deck on both sides: a rail row of end, first, repeated
    middle, last, end pieces on top of the existing stacks. East-west bridges have two deck rows (5 reference-map
    bridges, 5-11 long); north-south ones one deck column (one reference-map bridge, 4 long; the middle rail pieces
    <id>/<id> are the unused 2x2 ids between the observed ones)."""

    def __init__(self, ns, start, end, at):
        self.ns, self.start, self.end, self.at = ns, start, end, at  # ns: along y; at: deck x (ns) or row (ew)

    def tile(self, along, across):
        return (across, along) if self.ns else (along, across)

    def deck(self):
        rows = (self.at,) if self.ns else (self.at, self.at + 1)
        return [self.tile(a, c) for c in rows for a in range(self.start, self.end + 1)]

    def rails(self):
        sides = (self.at - 1, self.at + 1) if self.ns else (self.at - 1, self.at + 2)
        return [[self.tile(a, c) for a in range(self.start, self.end + 1)] for c in sides]

    def corridor(self):
        rows = (self.at,) if self.ns else (self.at, self.at + 1)
        return [self.tile(a, c) for c in rows for a in range(self.start - 1, self.end + 2)]

    def area(self):
        lo, hi = (self.at - 1, self.at + 1) if self.ns else (self.at - 1, self.at + 2)
        return [self.tile(a, c) for c in range(lo, hi + 1) for a in range(self.start - 2, self.end + 3)]

    def guard(self):
        """The bridge with its straight bank lines and both landing zones: kept out of roughening and free of
        plants."""
        lo, hi = (self.at - 2, self.at + 2) if self.ns else (self.at - 2, self.at + 3)
        return [self.tile(a, c) for c in range(lo, hi + 1) for a in range(self.start - 4, self.end + 5)]

    def key(self):
        return (self.ns, self.start, self.end, self.at)


def ford_sites(size, m, rng):
    """Crossing sites for fords (a strip of walkable cooled crust across lava): a run of 2-9 liquid tiles along
    the crossing's centre line, with walkable land (no relief) at both ends and one more land tile beyond. No
    straight-bank or landing-zone rule: unlike a wooden bridge, crust is an irregular natural strip."""
    water = m["water"]
    land = lambda x, y: 0 <= x < size and 0 <= y < size and not water[y][x] \
        and not m["mountain"][y][x] and not m["hill"][y][x]
    sites = []
    for ns in (False, True):
        for at in range(2, size - 3):
            a = 1
            while a < size - 2:
                b = Bridge(ns, a - 1, a - 1, at)
                tx, ty = b.tile(a, at)
                if not water[ty][tx] or not land(*b.tile(a - 1, at)):
                    a += 1
                    continue
                a2 = a
                while a2 + 1 < size and water[b.tile(a2 + 1, at)[1]][b.tile(a2 + 1, at)[0]]:
                    a2 += 1
                # only the centre line must be a clean crossing: the crust fills whatever lava lies under the
                # other deck and rail lines, so a slanting channel can be forded too
                ok = 2 <= a2 - a + 1 <= 9
                ok = ok and land(*b.tile(a - 1, at)) and land(*b.tile(a2 + 1, at))
                ok = ok and land(*b.tile(a - 2, at)) and land(*b.tile(a2 + 2, at))
                if ok:
                    sites.append(Bridge(ns, a - 1, a2 + 1, at))
                a = a2 + 1
    rng.shuffle(sites)
    return sites


def bridge_sites(size, m, rng, most=3):
    """Bridge sites across straight river stretches: a water run of 2-9 river tiles along the crossing that is
    the same on every deck and rail line and on one more line beyond each rail, so both banks run straight
    past the bridge and its ends rest on flat ground, not on a bend (user review, seed 102). Both ends open
    onto a landing zone 3 tiles deep and a tile wider than the deck on each side, all walkable ground with no
    relief or water within reach, so the path off the bridge is wide (user review, seeds 103 and 106).
    North-south bridges need 2+ water tiles, east-west ones 3+ (the reference map's shortest: 4 and 5 long)."""
    water, river = m["water"], m["river"]
    relief = lambda x, y: m["mountain"][y][x] or m["hill"][y][x]
    land = lambda x, y: 0 <= x < size and 0 <= y < size and not water[y][x] and not relief(x, y)
    open_ground = lambda x, y: land(x, y) and not touches(water, x, y) and not touches(m["mountain"], x, y) \
        and not touches(m["hill"], x, y)
    sites = []
    for ns in (False, True):
        for at in range(2, size - 3):
            a = 1
            while a < size - 2:
                b = Bridge(ns, a - 1, a - 1, at)
                if b.tile(a, at) not in river or not land(*b.tile(a - 1, at)):
                    a += 1
                    continue
                a2 = a
                while a2 + 1 < size and water[b.tile(a2 + 1, at)[1]][b.tile(a2 + 1, at)[0]]:
                    a2 += 1
                # as on the reference map (refs/bridge-ew11, refs/bridge-ns): the lip on the inland tile before the near bank,
                # the deck over the near bank and the water, the end piece on the far bank; both bank tiles are
                # under planks, so the shore border reads as running on under the bridge (user review, batch-03)
                b = Bridge(ns, a - 2, a2 + 1, at)
                lo, hi = (at - 2, at + 2) if ns else (at - 2, at + 3)  # rails plus one line beyond each
                ok = (2 if ns else 3) <= a2 - a + 1 <= 9
                for c in range(lo, hi + 1):
                    ok = ok and all(b.tile(k, c) in river for k in range(a, a2 + 1))
                    ok = ok and land(*b.tile(a - 1, c)) and land(*b.tile(a2 + 1, c))
                    if not ok:
                        break
                deck_lo, deck_hi = (at, at) if ns else (at, at + 1)
                for c in range(deck_lo - 1, deck_hi + 2):  # landing zones
                    for k in (2, 3, 4):  # near side: the lip tile and two beyond; far side: three beyond the end
                        ok = ok and open_ground(*b.tile(a - k, c)) and open_ground(*b.tile(a2 + k, c))
                    ok = ok and open_ground(*b.tile(a - 5, c))
                if ok:
                    sites.append(b)
                a = a2 + 1
    rng.shuffle(sites)
    return sites


def spaced(sites, most, taken=(), gap=20):
    """Up to `most` sites from the list, 20+ tiles from each other and from the taken ones (10 gave twin bridges\n    over one river, user review batch-04)."""
    chosen = list(taken)
    mid = lambda b: b.tile((b.start + b.end) // 2, b.at)
    for b in sites:
        if len(chosen) - len(taken) >= most:
            break
        if all(abs(mid(b)[0] - mid(c)[0]) + abs(mid(b)[1] - mid(c)[1]) >= gap for c in chosen):
            chosen.append(b)
    return chosen[len(taken):]


def connecting(sites, comp_at):
    """Bridges that join the big walkable ground regions into one, starting from the largest (region 0):
    each picked site has one end in a joined region and the other in a new one. comp_at(x, y) -> region or
    None; a site's ends are looked up on the approach tiles beyond its lip and its end piece.
    Returns (bridges, joined region numbers)."""
    def side(b, a, step):
        for k in range(3):
            c = comp_at(*b.tile(a + step * k, b.at))
            if c is not None:
                return c
        return None

    joined, out = {0}, []
    grew = True
    while grew:
        grew = False
        for b in sites:
            if b in out:
                continue
            ends = {side(b, b.start - 1, -1), side(b, b.end + 1, 1)}
            if None in ends or len(ends) < 2:
                continue
            if len(ends & joined) == 1:
                joined |= ends
                out.append(b)
                grew = True
    return out, joined


def smooth_course(path, window=5):
    """Grid path -> smoothed tile course: a moving average over `window` points, then every tile on the
    straight segments between them (so the river neither zigzags nor leaves gaps)."""
    if len(path) < 3:
        return path
    pts = []
    for k in range(len(path)):
        span = path[max(0, k - window // 2):k + window // 2 + 1]
        pts.append((sum(x for x, _ in span) / len(span), sum(y for _, y in span) / len(span)))
    out = []
    for (x1, y1), (x2, y2) in zip(pts, pts[1:]):
        steps = max(1, int(max(abs(x2 - x1), abs(y2 - y1)) * 2))
        for s in range(steps + 1):
            t = s / steps
            tile = (round(x1 + (x2 - x1) * t), round(y1 + (y2 - y1) * t))
            if not out or out[-1] != tile:
                out.append(tile)
    return out


def road_path(size, start, goal, cost):
    """Cheapest 8-neighbour path from start to goal (diagonal steps keep roads from running in right angles);
    cost(x, y) is None where a road may not go."""
    best, prev = {start: 0.0}, {}
    queue = [(0.0, start)]
    while queue:
        d, cur = heapq.heappop(queue)
        if cur == goal:
            break
        if d > best.get(cur, 1e18):
            continue
        for dx, dy in [(i, j) for i in (-1, 0, 1) for j in (-1, 0, 1) if i or j]:
            n = (cur[0] + dx, cur[1] + dy)
            if not (0 <= n[0] < size and 0 <= n[1] < size):
                continue
            step = cost(*n)
            if step is None:
                continue
            nd = d + step * (1.41 if dx and dy else 1.0)
            if nd < best.get(n, 1e18):
                best[n], prev[n] = nd, cur
                heapq.heappush(queue, (nd, n))
    if goal not in prev and goal != start:
        return []
    path, cur = [goal], goal
    while cur != start:
        cur = prev[cur]
        path.append(cur)
    return path


def grounds(size, rng, m, stops, p, bridges=(), needed=(), worn_share=0.12, broad_at=0.62, brush=None, rough_passes=None, limit=None):
    """Sand (brown jungle sand) and grey-brown sand masks. On the reference map most brown sand is winding
    roads 2-3 tiles wide: here roads join the ramp feet (stops) and `roads` shore points along the cheapest path
    through a noise field (so they wind), plus sand patches over about sand% of open ground. Grey-brown sand
    sits inside the sand. roads = -1 turns roads off."""
    water, hill, levels = m["water"], m["hill"], m["levels"]
    # the reference map has no water border onto jungle sand (no <id>/<id>), so sand never touches water
    blocked = [[water[y][x] or touches(water, x, y) or (levels and levels[0][y][x]) or hill[y][x]
                for x in range(size)] for y in range(size)]
    near_block = distance(size, blocked)
    wiggle = blend(size, rng, [(6, 0.6), (3, 0.4)])
    broad = blend(size, rng, [(10, 0.7), (4, 0.3)])
    # bridge corridors: both deck rows from one tile before the lip to one tile past the end; roads may pass
    # there (never painted as sand: those tiles stay blocked for painting)
    corridor = {t: b for b in bridges for t in b.corridor()}

    def cost(x, y):
        if (x, y) in corridor:
            return 1
        if blocked[y][x]:
            return None
        return 1 + 12 * wiggle[y][x] ** 2 + (8 if near_block[y][x] < 3 else 0)  # keep off cliff feet and shores

    coast = [(x, y) for y in range(size) for x in range(size) if m["shore"][y][x] == 3]
    rng.shuffle(coast)
    points = list(stops) + coast[:p.roads] if p.roads >= 0 else []
    # a needed bridge gets a road across it: its two approach points in a row, so the second one joins the
    # first through the corridor
    bridge_points = set()
    for b in needed:
        points += [b.tile(b.start - 2, b.at), b.tile(b.end + 2, b.at)]
        bridge_points |= set(points[-2:])
    limit = limit or {}  # kit road_limit: {"share": road mask cap as share of non-water tiles, "bridge": longest bridge approach road}
    patches = quantile_region(size, blend(size, rng, [(9, 0.5), (4, 0.3), (2, 0.2)]), p.sand / 100,
                              lambda x, y: near_block[y][x] >= 2 and m["shore"][y][x] >= 3)  # no rng use between here and the old place: same maps
    cap = max(1, int(limit["share"] * sum(1 for row in water for v in row if not v)) - sum(map(sum, patches))) \
        if limit.get("share") else 0  # the budget in road tiles; sand patches count against it
    roads, used = set(), set(needed)
    joined = [points[0]] if points else []
    for point in points[1:]:  # join each point to the nearest already-joined one: a tree of roads
        if cap and len(roads) >= cap and point not in bridge_points:
            continue  # road budget spent: this ramp foot or shore point gets no road
        q = min(joined, key=lambda j: abs(j[0] - point[0]) + abs(j[1] - point[1]))
        path = road_path(size, point, q, cost)
        used |= {corridor[t] for t in path if t in corridor}
        if limit.get("bridge") and point in bridge_points:
            path = path[-limit["bridge"]:]  # a short approach road, not a long tree branch from the bridge
        for x, y in (path[::-1] if cap else path):  # with a budget: from the point, so the road stops short of the joined network
            if cap and len(roads) >= cap and point not in bridge_points:
                break
            # 3 wide, 5 where a noise field is high: The reference map's roads are 3-7 wide (tools/ground_context.py)
            r = 2 if broad[y][x] > broad_at else 1  # kit road_broad: noise level above which a road is 5 wide (grass: 2 = never)
            for i, j in ((i, j) for i in range(-r, r + 1) for j in range(-r, r + 1) if i * i + j * j <= (brush if brush is not None and r == 1 else r * r + 1)):  # kit road_brush: 1 = a plus-shaped 3-wide brush, narrower on diagonals than the 3x3 block
                if 0 <= x + i < size and 0 <= y + j < size and not blocked[y + j][x + i]:
                    roads.add((x + i, y + j))
        joined.append(point)
    sand = [[(x, y) in roads or patches[y][x] for x in range(size)] for y in range(size)]
    clean(sand)
    for y in range(size):  # cleaning must not push sand into water, mountains or hills
        for x in range(size):
            if blocked[y][x]:
                sand[y][x] = False
    # staircase outlines; roads only grow, so roughening never narrows or cuts them
    if rough_passes is None:
        roughen(sand, rng, allowed=lambda x, y: not blocked[y][x], mode="grow", p=0.4)
    else:  # kit road_rough: fewer bump passes; 4 of them thickened a 3-wide road to 7-9 tiles on diagonals
        break_runs(sand, rng, lambda x, y: not blocked[y][x], passes=rough_passes, mode="grow")
    for y in range(size):  # never on water-touching, relief or hill tiles: the reference map has no water border onto sand
        for x in range(size):
            sand[y][x] = sand[y][x] and not blocked[y][x]
    inside_sand = distance(size, [[not v for v in row] for row in sand])
    grey = worn_rims(size, rng, sand, inside_sand, worn_share)
    return sand, grey, sorted(used, key=Bridge.key)


def worn_rims(size, rng, sand, inside_sand, share=0.12):
    """Grey-brown sand as the reference map lays it on its roads (tools/ground_context.py on refs/<window>: 12% of the
    brown sand area; 91% of grey tiles on their own patch's edge, so the patches are 1-2 tiles thin): small
    thin blobs of 3-7 tiles grown along the road's edge against the grass, now and then one tile deeper, never a
    block in the middle of the road (user review: rectangles on roads)."""
    grey = [[False] * size for _ in range(size)]
    edge = [(x, y) for y in range(size) for x in range(size) if sand[y][x] and inside_sand[y][x] == 1]
    rng.shuffle(edge)
    target = int(share * sum(map(sum, sand)))
    placed = 0
    for sx, sy in edge:
        if placed >= target:
            break
        if grey[sy][sx] or any(0 <= sx + i < size and 0 <= sy + j < size and grey[sy + j][sx + i]
                               for i in range(-2, 3) for j in range(-2, 3)):
            continue  # patches stay apart
        blob, want = [(sx, sy)], rng.randint(3, 7)
        grey[sy][sx] = True
        while len(blob) < want:
            options = [(x + i, y + j) for x, y in blob for i, j in ((0, 1), (1, 0), (0, -1), (-1, 0))
                       if 0 <= x + i < size and 0 <= y + j < size and sand[y + j][x + i] and not grey[y + j][x + i]
                       and (inside_sand[y + j][x + i] == 1 or (inside_sand[y + j][x + i] == 2 and rng.random() < 0.25))]
            if not options:
                break
            nx, ny = rng.choice(options)
            grey[ny][nx] = True
            blob.append((nx, ny))
        placed += len(blob)
    return grey


DIRS = {"n": (0, -1), "e": (1, 0), "s": (0, 1), "w": (-1, 0)}


def layered_borders(kit, keys, x, y):
    """The border pieces on one tile from the ranked ground layers (kit layers, learned with
    tools/seam_audit.py --pair): every layer ranked above this tile's ground draws its own border set toward
    its tiles, lowest layer first, the way the reference map stacks them. keys: grid of kit ground keys (None for tiles
    that are no ground of the table, e.g. relief). A layer with `onto` draws only onto those grounds; a layer
    whose border is a dict draws a different set per lower ground ({lower key: set}, as the fire slab does onto
    lava and onto mauve cobble), and nothing onto grounds the dict leaves out."""
    size = len(keys)
    order = [lay["kit"] for lay in kit["layers"]]
    here = keys[y][x]
    if here not in order:
        return []
    out = []
    for lay in kit["layers"][order.index(here) + 1:]:
        border = border_of(lay, here)
        if not border:
            continue
        mask = [[keys[j][i] == lay["kit"] for i in range(max(0, x - 1), min(size, x + 2))]
                for j in range(max(0, y - 1), min(size, y + 2))]
        if not any(map(any, mask)):
            continue
        full = _Window(keys, lay["kit"])
        out += edge_pieces(full, x, y, kit[border], outside=lay.get("outside", False))
    return out


def border_of(lay, lower):
    """The set a layer draws onto a lower ground: its "border" (a set name, or a dict per lower ground), or None
    when it draws nothing there."""
    border = lay.get("border")
    if isinstance(border, dict):
        return border.get(lower)
    if not border or ("onto" in lay and lower not in lay["onto"]):
        return None
    return border


def tidy_grounds(kit, keys, rng, water=None):
    """dissolve_islands once, then settle_layers, then jag_edges and settle again. Not alternated with
    dissolve: settle can leave a one-tile island where it fills a pinch, and dissolving that island recreates
    the pinch (seed 108). settle_layers alone only raises layers and always settles. Returns tiles changed."""
    changed = dissolve_islands(kit, keys) + settle_layers(kit, keys)
    changed += jag_edges(kit, keys, rng, water) + settle_layers(kit, keys)
    return changed


UNBORDERED_AT_WATER = ("sand", "grey_sand", "gravel")  # the reference map has no water border onto these


def jag_edges(kit, keys, rng, water=None, longest=2):
    """The reference map's ground outlines are staircases: about a third each edge, inner and outer pieces, almost no run of
    3+ equal edge pieces (tools/outline_study.py; user review: "brushes too straight"). On the finished key grid,
    where nothing later straightens it again: for every straight stretch where a lower ground meets a higher
    one along one side, longer than `longest` tiles, every 2-3 tiles one tile flips: a lower tile becomes the
    higher ground (a bump) or the higher tile beside it becomes the lower ground (a notch). A notch never puts
    an unbordered ground (sand, gravel) against water. Water and bridge tiles never change. Returns flips."""
    size = len(keys)
    order = [lay["kit"] for lay in kit["layers"]]
    rank = {k: r for r, k in enumerate(order)}
    layer_of = {lay["kit"]: lay for lay in kit["layers"]}
    unbordered = kit.get("no_water_border", UNBORDERED_AT_WATER)
    fixed = {"water", "bridge", None}
    wet = lambda x, y: water is not None and any(
        0 <= x + i < size and 0 <= y + j < size and water[y + j][x + i] for i in (-1, 0, 1) for j in (-1, 0, 1))
    flips = 0
    for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0)):
        ax, ay = (1, 0) if dy else (0, 1)

        def straight(x, y):
            """Lower tile (x, y) whose higher neighbour lies at (dx, dy), with the same key on that side of
            its two neighbours along the edge: the higher ground's key, or None."""
            if not (0 <= x < size and 0 <= y < size) or keys[y][x] in fixed:
                return None
            hx, hy = x + dx, y + dy
            if not (0 <= hx < size and 0 <= hy < size):
                return None
            high = keys[hy][hx]
            if high in fixed or high not in rank or rank[high] <= rank.get(keys[y][x], 99):
                return None
            if not border_of(layer_of[high], keys[y][x]):  # only seams the kit draws a border for
                return None
            return high

        seen = set()
        for y in range(size):
            for x in range(size):
                high = straight(x, y)
                if high is None or (x, y) in seen or straight(x - ax, y - ay) == high:
                    continue
                # a run spans every lower ground: the higher ground draws the same pieces on all of them
                run, tx, ty = [], x, y
                while straight(tx, ty) == high:
                    run.append((tx, ty))
                    seen.add((tx, ty))
                    tx, ty = tx + ax, ty + ay
                if len(run) <= longest:
                    continue
                k = rng.randint(1, 2)
                while k < len(run) - 1:
                    bx, by = run[k]
                    low = keys[by][bx]
                    hx, hy = bx + dx, by + dy
                    if rng.random() < 0.5:
                        keys[by][bx] = high  # bump: the higher ground reaches one tile into the lower
                    elif not (low in unbordered and wet(hx, hy)):
                        keys[hy][hx] = low  # notch: the lower ground reaches one tile into the higher
                    else:
                        keys[by][bx] = high
                    flips += 1
                    k += rng.randint(2, 3)
    return flips


def dissolve_islands(kit, keys, limit=12):
    """Small islands of one ground (under `limit` tiles, 4-connected) whose every side neighbour is one other
    ground of the layer table join that ground, in place: they come out as little squares and rectangles
    (user review, seed 107: a 3x3 grass square inside a road junction). Returns how many tiles changed."""
    size = len(keys)
    layers = {lay["kit"] for lay in kit["layers"]} - {"water"}
    seen, changed = set(), 0
    for y in range(size):
        for x in range(size):
            key = keys[y][x]
            if (x, y) in seen or key not in layers:
                continue
            part, queue, around = [(x, y)], deque([(x, y)]), set()
            seen.add((x, y))
            while queue:
                cx, cy = queue.popleft()
                for i, j in ((0, 1), (1, 0), (0, -1), (-1, 0)):
                    nx, ny = cx + i, cy + j
                    if not (0 <= nx < size and 0 <= ny < size):
                        around.add(None)
                    elif keys[ny][nx] == key:
                        if (nx, ny) not in seen:
                            seen.add((nx, ny))
                            part.append((nx, ny))
                            queue.append((nx, ny))
                    else:
                        around.add(keys[ny][nx])
            if len(part) < limit and len(around) == 1 and next(iter(around)) in layers:
                other = next(iter(around))
                for px, py in part:
                    keys[py][px] = other
                changed += len(part)
    return changed


def settle_layers(kit, keys, fixed=("water",)):
    """Makes a ground-key grid drawable by its layered borders, in place. For every layer from the top down, a
    tile of a lower layer that would carry that layer's pieces facing opposite ways (lib.pinched: a strip of
    lower ground too thin for the set) becomes the higher layer; repeated until stable. Layers in `fixed`
    (water) never spread. Returns how many tiles changed."""
    size = len(keys)
    order = [lay["kit"] for lay in kit["layers"]]
    rank = {k: r for r, k in enumerate(order)}
    changed_total, changed = 0, True
    while changed:
        changed = False
        for lay in reversed(kit["layers"]):
            key = lay["kit"]
            if key in fixed or not lay.get("border"):
                continue
            for y in range(size):
                for x in range(size):
                    here = keys[y][x]
                    if here not in rank or here in fixed or rank[here] >= rank[key] or not border_of(lay, here):
                        continue
                    # layers that draw this same set onto this ground count as one mask: a strip pinched between two of
                    # them would carry the set's pieces facing opposite ways (kit: gravel, stone floor and planks draw one set)
                    same = {other["kit"] for other in kit["layers"] if border_of(other, here) == border_of(lay, here)}
                    at = lambda x2, y2, same=same: 0 <= x2 < size and 0 <= y2 < size and keys[y2][x2] in same
                    if pinched(at, x, y):
                        keys[y][x] = key
                        changed = True
                        changed_total += 1
    return changed_total


class _Window:
    """A read-only mask view (mask[y][x] is keys[y][x] == key) without building the whole grid per tile."""

    def __init__(self, keys, key):
        self.keys, self.key = keys, key

    def __len__(self):
        return len(self.keys)

    def __getitem__(self, y):
        row = self.keys[y]
        return _Row(row, self.key)


class _Row:
    def __init__(self, row, key):
        self.row, self.key = row, key

    def __getitem__(self, x):
        return self.row[x] == self.key


def clear_top(levels, k, x, y):
    """A walkable top tile of level k+1 (index k): on the level, not under the next one and not beside it
    (those tiles carry the next level's cliff pieces, which block)."""
    if not levels[k][y][x]:
        return False
    if k + 1 < len(levels):
        nxt = levels[k + 1]
        return not touches(nxt, x, y) and not nxt[y][x]
    return True


def notch_seat(size, levels, k, part, reached_below, used, rng, ground=None):
    """A ramp onto level k (index, 1+) seated in a notch: an edge tile E of the level, facing a reachable
    tile O of the level below in direction d, loses E and E+d (3 wide along the edge), so the ramp stands on
    E+d, its lower half on E and the approach on O; the landing E+2d and the tile after it stay on the level
    (higher levels pulled back to keep them clear). Only notches whose landing is near `part`. Returns the
    ramp dict ({} when no seat fits). Level 0 (k = 0, kit key notch_level0) is seated the same way into the
    mountain's foot: `ground` (the open ground mask: not water, not touching it) stands for the level below."""
    lv = levels[k]
    below = levels[k - 1] if k else ground
    near = {(x + i, y + j) for x, y in part for i in range(-3, 4) for j in range(-3, 4)}
    name = {v: n for n, v in DIRS.items()}
    inb = lambda x, y: 0 <= x < size and 0 <= y < size
    seats = []
    for y in range(size):
        for x in range(size):
            if not lv[y][x]:
                continue
            for (dx, dy), d in name.items():
                ax, ay = dy, dx  # along the edge
                ox, oy = x - dx, y - dy  # the approach: a cliff-foot tile now, free once the notch is cut
                if not inb(ox - dx, oy - dy) or lv[oy][ox] or not below[oy][ox] or (ox, oy) in used:
                    continue
                if not reached_below(ox - dx, oy - dy):  # the player comes from the tile beyond it
                    continue
                notch = [(x + s * dx + a * ax, y + s * dy + a * ay) for s in (0, 1) for a in (-1, 0, 1)]
                keep = [(x + 2 * dx + a * ax, y + 2 * dy + a * ay) for a in (-1, 0, 1)] + [(x + 3 * dx, y + 3 * dy)]
                if not all(inb(*t) and below[t[1]][t[0]] and (t not in used) for t in notch):
                    continue
                if not all(inb(*t) and lv[t[1]][t[0]] for t in keep) or (x + 2 * dx, y + 2 * dy) not in near:
                    continue
                seats.append((x, y, dx, dy, d, notch))
    if not seats:
        return {}
    x, y, dx, dy, d, notch = rng.choice(seats)
    for j in range(k, len(levels)):
        for tx, ty in notch:
            levels[j][ty][tx] = False
    if k + 1 < len(levels):
        pull_back(size, levels, k + 1, [(x + t * dx, y + t * dy) for t in (2, 3, 4)])
    return {(x + dx, y + dy): (d, 0), (x, y): (d, 1)}


def pull_back(size, levels, first, tiles):
    """Clears room for a ramp landing: levels `first` and up lose every tile within one step of the given
    tiles, then stay clean, nested (level 2 two tiles inside level 1, higher ones three) and free of scraps."""
    gone = {(x + i, y + j) for x, y in tiles for i in (-1, 0, 1) for j in (-1, 0, 1)}
    for j in range(first, len(levels)):
        lv = levels[j]
        for x, y in gone:
            if 0 <= x < size and 0 <= y < size:
                lv[y][x] = False
        clean(lv)
        inside = distance(size, [[not v for v in row] for row in levels[j - 1]])
        step = terrace_step(j)
        for y in range(size):
            for x in range(size):
                lv[y][x] = lv[y][x] and inside[y][x] >= step
        for part in parts(size, lv):
            if len(part) < 8:
                for x, y in part:
                    lv[y][x] = False


def parts8(size, ok):
    """The 8-connected regions of the tiles where ok(), as sets (players move diagonally too)."""
    seen, out = set(), []
    for y in range(size):
        for x in range(size):
            if (x, y) in seen or not ok(x, y):
                continue
            part, queue = {(x, y)}, deque([(x, y)])
            seen.add((x, y))
            while queue:
                cx, cy = queue.popleft()
                for i in (-1, 0, 1):
                    for j in (-1, 0, 1):
                        n = (cx + i, cy + j)
                        if 0 <= n[0] < size and 0 <= n[1] < size and n not in seen and ok(*n):
                            seen.add(n)
                            part.add(n)
                            queue.append(n)
            out.append(part)
    return out


def component_of(size, ok, seeds):
    """Mask of the tiles where ok() that are 8-connected to any seed."""
    out = [[False] * size for _ in range(size)]
    queue = deque((x, y) for x, y in seeds if 0 <= x < size and 0 <= y < size and ok(x, y))
    for x, y in queue:
        out[y][x] = True
    while queue:
        x, y = queue.popleft()
        for i in (-1, 0, 1):
            for j in (-1, 0, 1):
                nx, ny = x + i, y + j
                if 0 <= nx < size and 0 <= ny < size and not out[ny][nx] and ok(nx, ny):
                    out[ny][nx] = True
                    queue.append((nx, ny))
    return out


def aprons(size, rng, m, sand, ramps, span, with_gravel=True, off_sand=False, patches=0):
    """Rock soil and gravel at mountain feet on the ground floor, as on the reference map (tools/ground_context.py): thin
    bands (81% edge tiles), 38% of rock soil on the cliff tiles themselves, 30% one tile out, 18% two out;
    gravel a little further (mostly 1-3 out) and bordered by the rock soil. Noise breaks the bands up.
    Never on water-touching, sand, ramp or bridge tiles; off_sand: never beside sand either (no border between
    them in the kit). Returns (rock, gravel) masks; gravel is empty when with_gravel is off."""
    water, mountain = m["water"], m["mountain"]
    out = distance(size, mountain)
    field = blend(size, rng, [(5, 0.6), (2, 0.4)])
    keep = {1: 0.25, 2: 0.45, 3: 0.62}  # cut per distance: denser at the foot

    def allowed(x, y):
        return (not water[y][x] and not mountain[y][x] and not touches(water, x, y) and not sand[y][x]
                and not (off_sand and touches(sand, x, y))
                and not m["hill"][y][x] and (x, y) not in ramps and (x, y) not in span)

    rock = [[allowed(x, y) and out[y][x] in keep and field[y][x] > keep[out[y][x]] for x in range(size)]
            for y in range(size)]
    clean(rock)
    rock = [[rock[y][x] and allowed(x, y) for x in range(size)] for y in range(size)]
    roughen(rock, rng, allowed=lambda x, y: allowed(x, y) and out[y][x] <= 4)
    if patches:  # kit rock_patches: rock soil patches out on open ground too (the reference: 6.8% of floor 7 against 3.6% at cliff feet only)
        extra = quantile_region(size, blend(size, rng, [(6, 0.6), (3, 0.4)]), patches,
                                lambda x, y: allowed(x, y) and out[y][x] >= 3)
        roughen(extra, rng, allowed=lambda x, y: allowed(x, y) and out[y][x] >= 3)
        clean(extra)
        rock = [[rock[y][x] or (extra[y][x] and allowed(x, y)) for x in range(size)] for y in range(size)]
    if not with_gravel:
        return rock, [[False] * size for _ in range(size)]
    gfield = blend(size, rng, [(4, 0.6), (2, 0.4)])
    gravel = [[allowed(x, y) and not rock[y][x] and 2 <= out[y][x] <= 4 and gfield[y][x] > 0.6
               and touches(rock, x, y) for x in range(size)] for y in range(size)]
    clean(gravel)
    gravel = [[gravel[y][x] and allowed(x, y) and not rock[y][x] for x in range(size)] for y in range(size)]
    roughen(gravel, rng, allowed=lambda x, y: allowed(x, y) and not rock[y][x])
    return rock, gravel


def top_patches(size, rng, top, inside, near_higher, k, with_gravel=True, shares=None, mix=None):
    """Ground patchwork on the top of mountain level k, as on the reference map (tools/top_ground_study.py):
    rock soil and gravel gather on rim tiles and at the foot of the next cliff (z6: a third of those tiles,
    5% of inner ones; z5: about 45% and 10%; z4: most of the top); brown sand patches sit inner (z5 inner
    33%); the rest is jungle grass. Gravel sits inside the rock bands. Returns a grid of kit keys
    (base, sand, rock_soil, gravel; None off the top)."""
    edge = [[min(inside[y][x], near_higher[y][x]) for x in range(size)] for y in range(size)]
    # shares asked of the noise cut; cleaning narrow terraces loses about a third, so they sit above the targets
    band_share, inner_share = {1: (0.55, 0.06), 2: (0.6, 0.12)}.get(k, (0.85, 0.45))
    band_share, inner_share = (shares or {}).get(str(k), (band_share, inner_share))  # kit top_rock: {level: [band, inner]}
    sand_share = {1: 0.10, 2: 0.33}.get(k, 0.0)
    rocky = blend(size, rng, [(4, 0.6), (2, 0.4)])
    band = quantile_region(size, rocky, band_share, lambda x, y: top[y][x] and edge[y][x] <= 2)
    inner = quantile_region(size, blend(size, rng, [(6, 0.6), (3, 0.4)]), inner_share,
                            lambda x, y: top[y][x] and edge[y][x] >= 3)
    rock = [[band[y][x] or inner[y][x] for x in range(size)] for y in range(size)]
    on_top = lambda x, y: top[y][x]
    roughen(rock, rng, allowed=on_top)
    n_top = sum(map(sum, top))
    g_share = 0.35  # kit top_mix: gravel as a share of the top tiles (not of the rock soil region)
    if mix and mix.get("gravel"):
        g_share, with_gravel = min(0.9, mix["gravel"] * n_top / max(1, sum(map(sum, rock)))), True
    gravel = quantile_region(size, blend(size, rng, [(3, 0.6), (2, 0.4)]), g_share if with_gravel else 0,
                             lambda x, y: rock[y][x] and touches(rock, x, y))
    roughen(gravel, rng, allowed=lambda x, y: rock[y][x])
    near_rock = distance(size, rock)
    sand = quantile_region(size, blend(size, rng, [(7, 0.6), (3, 0.4)]), sand_share,
                           lambda x, y: top[y][x] and edge[y][x] >= 2 and near_rock[y][x] >= 2)
    roughen(sand, rng, allowed=lambda x, y: top[y][x] and near_rock[y][x] >= 2)
    keys = [[None] * size for _ in range(size)]
    for y in range(size):
        for x in range(size):
            if top[y][x]:
                keys[y][x] = (("top_gravel" if mix else "gravel") if gravel[y][x] else "rock_soil" if rock[y][x]
                              else "sand" if sand[y][x] else "base")
    if mix:  # kit top_mix: patches of the reference's other top grounds (stone floor, planks) inside the grass; they may
        # touch rock soil and gravel (the kit draws gravel_on_rock there) but stay 2+ tiles from each other
        grass_at = lambda x, y: keys[y][x] == "base"
        for name, role in (("stone", "top_stone"), ("plank", "top_plank")):
            if not mix.get(name):
                continue
            apart = distance(size, [[keys[y][x] in ("top_stone", "top_plank") for x in range(size)] for y in range(size)])
            allowed = lambda x, y, apart=apart: grass_at(x, y) and apart[y][x] >= 3
            n_allowed = sum(1 for y in range(size) for x in range(size) if allowed(x, y))
            patch = quantile_region(size, blend(size, rng, [(8, 0.6), (4, 0.4)]),
                                    min(0.9, mix[name] * n_top / max(1, n_allowed)), allowed)
            roughen(patch, rng, allowed=lambda x, y, apart=apart: grass_at(x, y) and apart[y][x] >= 2)
            for y in range(size):
                for x in range(size):
                    if patch[y][x] and grass_at(x, y):
                        keys[y][x] = role
    return keys


def liquid(size, rng, kit, items, water, mountain, fords, span):
    """Ground and decor for the water tiles when the kit layers its liquid in bands (fire: tools/bands.py on
    the reference map's lava caves). Each tile's band is its distance to land; within a band a smooth ranked noise picks the
    variant in the kit's order (cooled crust, crust chunks, molten, obsidian), so variants come in patches with
    the band's shares. Ford tiles get the crossing ground. Decor (kit water_flora): flow pieces on molten lava 2+
    tiles out, vents on crust. Returns (ground_at(x, y) or None, {(x, y): decor id})."""
    spec = kit["water"]
    if "bands" not in spec:
        return None, {}
    land = [[not v for v in row] for row in water]
    out = distance(size, land)
    u = rank_field(size, blend(size, rng, [(4, 0.6), (2, 0.4)]), lambda x, y: water[y][x])
    variant = {}
    for y in range(size):
        for x in range(size):
            if not water[y][x]:
                continue
            weights = next(w for limit, w in spec["bands"] if out[y][x] <= limit)
            acc, pick_ = 0.0, spec["order"][-1]
            for name in spec["order"]:
                acc += weights.get(name, 0)
                if u[y][x] < acc:
                    pick_ = name
                    break
            variant[(x, y)] = pick_
    crossing = kit.get("crossing", {}).get("ground")

    def ground_at(x, y):
        if (x, y) in fords and crossing:
            return crossing
        return pick(rng, spec["variants"][variant[(x, y)]])

    flora_spec = kit.get("water_flora", {})
    deep_max = spec.get("deep_flora_max", 99)  # flows near the rock, not across an open sea
    kind = lambda x, y: ("deep" if variant.get((x, y)) == "molten" and 2 <= out[y][x] <= deep_max
                         else "crust" if variant.get((x, y)) in ("crust", "crust2") else None)
    ok = lambda x, y: (water[y][x] and (x, y) not in fords and (x, y) not in span and not touches(mountain, x, y))
    plants = place_flora(size, kind, flora_spec, items, rng, ok) if flora_spec else {}
    return ground_at, plants


def pick(rng, g):
    return g["lead"] if rng.random() < 0.6 or not g["members"] else rng.choice(g["members"])


def build(p):
    size = p.size
    rng = random.Random(p.seed)
    kit = load_kit(getattr(p, "kit", None))
    items = load_items()
    p.water_low = kit["layers"][0]["kit"] == "water"
    m = layout(size, rng, p)
    water, mountain, hill = m["water"], m["mountain"], m["hill"]

    def open_ground(x, y):
        return not water[y][x] and not mountain[y][x] and not hill[y][x]

    levels = m["levels"]
    # walkable ground as it will be: shore and cliff pieces block their tiles, so a ramp must start in a big
    # open region, never in a pocket between cliffs and water
    regions = ground_regions(size, water, levels, hill, 20, not p.water_low)  # river-side strips count: bridges join them
    region_of = {t: k for k, part in enumerate(regions) for t in part}
    # bridges: first those that join the ground regions into one (so no side of a river is cut off), then a few
    # more that roads may use. Ramps only start from regions joined to the main ground.
    if kit.get("crossing", {}).get("type") == "ford":  # fords may cross any lava that splits the ground
        candidates = ford_sites(size, m, rng)
    else:
        # a kit without bridge pieces gets no bridges (water then only splits ground that passes can't join)
        candidates = bridge_sites(size, m, rng) if m["river"] and "bridge_ns" in kit and "bridge_ew" in kit else []
    needed, joined = connecting(candidates, lambda x, y: region_of.get((x, y)))
    join = kit.get("join_land")  # kit key: {"least": walkable tiles, "gap": most water tiles a neck crosses}
    necks = 0
    for _ in range(8 if join else 0):  # landmasses no bridge joins get a land neck, nearest first
        big = {t for k in joined for t in regions[k]}
        stray = [part for part in ground_regions(size, water, levels, hill, join["least"], not p.water_low)
                 if not part & big]
        keep = {t for b in needed for t in b.guard()}
        for part in stray:
            if join_landmass(size, m, big, [part], rng, join["gap"], keep):
                necks += 1
                break
        else:
            break
        regions = ground_regions(size, water, levels, hill, 20, not p.water_low)
        region_of = {t: k for k, part in enumerate(regions) for t in part}
        needed, joined = connecting(candidates, lambda x, y: region_of.get((x, y)))
    # plus one crossing per river: a road is always led over it, so every river gets a bridge when a site fits
    sites = needed + spaced(candidates, p.rivers, needed)
    big = {t for t, k in region_of.items() if k in joined}
    on_big = lambda x, y: (x, y) in big
    ramps = place_ramps(size, hill, lambda x, y: open_ground(x, y) and not touches(water, x, y)
                        and not touches(mountain, x, y), rng, landing=lambda x, y: hill[y][x], source=on_big)
    # rock ramps up the mountains, level by level (same geometry as the earth ramps, tools/ramp_check.py): every
    # walkable part of a level's top (8-connected clear tiles, 30+) gets its own ramp from something already
    # reachable below, when a usable spot exists; parts landed on carry on to the next level (gen/access.py)
    per_level, reached_below = [], on_big
    road_least = kit.get("road_least", 0)  # kit key: ramps onto top parts smaller than this get no road to their foot
    quiet = set()
    ramp_least = kit.get("ramp_least", 30)  # kit key: smallest top part (8-connected clear tiles) that gets a ramp
    per_level, reached_below = [], on_big
    for k in range(len(levels)):
        if k == 0:
            free = lambda x, y: (open_ground(x, y) and not touches(water, x, y) and not touches(hill, x, y)
                                 and (x, y) not in ramps)
        else:
            inside = distance(size, [[not v for v in row] for row in levels[k - 1]])
            free = lambda x, y, k=k, inside=inside: (levels[k - 1][y][x] and not levels[k][y][x]
                                                     and inside[y][x] >= 1)
        placed = {}
        tops = parts8(size, lambda x, y, k=k: clear_top(levels, k, x, y))
        for part in sorted(tops, key=len, reverse=True):
            if len(part) < ramp_least:
                break
            used = set(placed) | set(ramps) | {t for lv in per_level for t in lv}
            args = dict(source=lambda x, y, rb=reached_below: rb(x, y) and (x, y) not in used,
                        want=2 if len(part) >= 120 else 1, taken=[t for t, (d, h) in placed.items() if h == 0])
            spot_free = lambda x, y, free=free: free(x, y) and (x, y) not in used
            step = place_ramps(size, levels[k], spot_free, rng, landing=lambda x, y, part=part: (x, y) in part,
                               **args)
            if not step and k + 1 < len(levels):
                # no clear landing: land next to the part where the next level stands too close, then pull
                # that level back around the landing (gen/generate.py pull_back)
                near = {(x + i, y + j) for x, y in part for i in (-2, -1, 0, 1, 2) for j in (-2, -1, 0, 1, 2)}
                step = place_ramps(size, levels[k], spot_free, rng,
                                   landing=lambda x, y, k=k, near=near: (x, y) in near and levels[k][y][x]
                                   and not levels[k + 1][y][x], **{**args, "want": 1})
                for (x, y), (d, half) in step.items():
                    if half == 0:
                        dx, dy = DIRS[d]
                        pull_back(size, levels, k + 1, [(x + t * dx, y + t * dy) for t in (1, 2, 3)])
            if not step and (k >= 1 or kit.get("notch_level0")):
                # the terrace below is too narrow for approach, lower half and ramp: cut a notch into this
                # level's edge and seat the ramp in it, as the reference map sets stairs into its cliffs
                step = notch_seat(size, levels, k, part, reached_below, used, rng,
                                  [[not water[y][x] and not touches(water, x, y) for x in range(size)]
                                   for y in range(size)])
                if k == 0:  # a seat cut into the mountain's foot: no road is led to it (kit road_least)
                    quiet |= set(step) if road_least else set()
            if len(part) < road_least:
                quiet |= set(step)
            placed.update(step)
        landed = [(x + DIRS[d][0], y + DIRS[d][1]) for (x, y), (d, half) in placed.items() if half == 0]
        reached = component_of(size, lambda x, y, k=k: clear_top(levels, k, x, y), landed)
        per_level.append(placed)
        reached_below = lambda x, y, reached=reached: reached[y][x]
    mramps = per_level[0] if per_level else {}
    terrace = per_level[1:]
    top_parts = []  # per level: (top parts of 30+ tiles with a ramp landing, all of them)
    for k, placed in enumerate(per_level):
        landed = {(x + DIRS[d][0], y + DIRS[d][1]) for (x, y), (d, half) in placed.items() if half == 0}
        big_tops = [part for part in parts8(size, lambda x, y, k=k: clear_top(levels, k, x, y)) if len(part) >= ramp_least]
        top_parts.append((sum(1 for part in big_tops if part & landed), len(big_tops)))
    feet = [pos for pos, (d, half) in {**ramps, **mramps}.items() if half == 1 and pos not in quiet]
    # tiles that stay free of plants so every ramp keeps room: ramp, lower half, the approach before it, the
    # landing and the tile after it
    keep = set()
    for k, rs in enumerate([mramps, ramps, *terrace]):
        for (x, y), (d, half) in rs.items():
            dx, dy = DIRS[d]
            keep |= {(x - dx, y - dy), (x, y)} if half == 1 else {(x, y), (x + dx, y + dy), (x + 2 * dx, y + 2 * dy)}
            # and a clear 3x3 where the player stands before climbing and where they arrive (user review: palms
            # crowding a ramp, seed 107)
            centre = (x - dx, y - dy) if half == 1 else (x + dx, y + dy)
            keep |= {(centre[0] + i, centre[1] + j) for i in (-1, 0, 1) for j in (-1, 0, 1)}
    sand, grey, bridges = grounds(size, rng, m, feet, p, sites, sites, kit.get("worn_share", 0.12),
                                 kit.get("road_broad", 0.62), kit.get("road_brush"), kit.get("road_rough"), kit.get("road_limit"))
    span = {t for b in bridges for t in b.guard()}  # rails, deck, banks and landings: kept clear of plants
    rock_layer = next((lay for lay in kit["layers"] if lay["kit"] == "rock_soil"), {})
    rock, gravel = aprons(size, rng, m, sand, {**ramps, **mramps}, span, "gravel" in kit,
                          off_sand=not border_of(rock_layer, "sand"), patches=kit.get("rock_patches", 0))
    ford = kit.get("crossing", {}).get("type") == "ford"

    def first_key(x, y):
        if water[y][x]:
            return "water"
        if mountain[y][x] or hill[y][x]:
            return None
        return ("grey_sand" if grey[y][x] else "sand" if sand[y][x] else "gravel" if gravel[y][x]
                else "rock_soil" if rock[y][x] else "base")

    # the ground grid, settled so no strip of a lower ground is too thin for the layer borders around it
    keys = [[first_key(x, y) for x in range(size)] for y in range(size)]
    fords = set()
    for b in bridges:
        if ford:  # a ford: the lava under the deck and both rail lines becomes cooled crust (walkable on the reference map);
            # it stays lava for borders, so the slab draws its lava border onto it as the reference map does onto crust
            for x, y in b.deck() + [t for line in b.rails() for t in line]:
                if water[y][x]:
                    fords.add((x, y))
            continue
        for x, y in b.deck():  # deck and end tiles: no ground draws its border toward a bridge (user review)
            if (y if b.ns else x) != b.start:
                keys[y][x] = "bridge"
    settled = tidy_grounds(kit, keys, rng, water)
    # a ground with no border onto the water (fire: grey rock, mauve cobble) that still touches it becomes the
    # base ground, which has one; then settle once more
    off_water = kit.get("no_water_border", UNBORDERED_AT_WATER)
    base_at = lambda x, y: 0 <= x < size and 0 <= y < size and keys[y][x] == "base"
    # likewise a higher ground with no border onto a lower one it touches (fire: grey rock beside mauve cobble)
    layer_of = {lay["kit"]: lay for lay in kit["layers"]}
    rank = {k: r for r, k in enumerate(layer_of)}
    unbordered = lambda hi, lo: (hi != "base" and lo in rank and rank[lo] < rank[hi] and lo != "water"
                                 and not border_of(layer_of[hi], lo) and border_of(layer_of["base"], lo))
    for _ in range(6):
        changed = 0
        for y in range(size):
            for x in range(size):
                near = [keys[y + j][x + i] for i, j in ((0, 1), (1, 0), (0, -1), (-1, 0))
                        if 0 <= x + i < size and 0 <= y + j < size]
                if keys[y][x] in off_water and "water" in near or (keys[y][x] in rank
                                                                   and any(unbordered(keys[y][x], k) for k in near)):
                    keys[y][x] = "base"
                    changed += 1
                elif p.water_low and keys[y][x] == "water" and (x, y) not in fords and pinched(base_at, x, y):
                    # a liquid tile the base ground pinches (a mountain bump beside it leaves base on two sides):
                    # the base's border on it would face both ways, so it becomes base
                    keys[y][x] = "base"
                    water[y][x] = False
                    changed += 1
        changed += settle_layers(kit, keys)
        settled += changed
        if not changed:
            break

    def family(x, y):
        k = keys[y][x]
        return k if k in ("water", "bridge") else "relief" if k is None else kit[k]["family"]

    def growable(x, y):
        # no plants on water, shore, cliff or ramp tiles
        return (open_ground(x, y) and not touches(water, x, y) and not touches(mountain, x, y)
                and not touches(hill, x, y) and (x, y) not in ramps and (x, y) not in mramps
                and (x, y) not in span and (x, y) not in keep)

    # sand and grey sand: per-tile rates; jungle grass: clumped to the reference map's measured local densities
    base = kit["base"]["family"]
    lower = {k: v for k, v in kit["flora"].items() if k != base}
    # kit key apron_flora: {"G<family>": {id: rate}} replaces the top table on floor 7 (rock soil on the reference map's
    # floor 7 carries more plants and stones than the same soil on tops, tools/edge_density.py)
    lower.update({kit[k]["family"]: kit.get("apron_flora", {}).get(kit[k]["family"]) or kit["top_flora"][kit[k]["family"]]
                  for k in ("rock_soil", "gravel") if k in kit and kit[k]["family"] in kit["top_flora"]})
    # roads stay open: blocking plants on sand only on its outer edge where the sand is 3+ wide
    blocking = lambda i: "not_walkable" in items[int(i)]["flags"]
    soft = {f: {i: r for i, r in t.items() if not blocking(i)} for f, t in lower.items()}
    hard = {f: {i: r for i, r in t.items() if blocking(i)} for f, t in lower.items()}
    deep = distance(size, [[not sand[y][x] for x in range(size)] for y in range(size)])
    roadside = lambda x, y: not sand[y][x] or (deep[y][x] == 1 and any(
        0 <= x + i < size and 0 <= y + j < size and deep[y + j][x + i] >= 2 for i in (-1, 0, 1) for j in (-1, 0, 1)))
    flora = place_flora(size, family, hard, items, rng, lambda x, y: growable(x, y) and roadside(x, y))
    flora.update(place_flora(size, family, soft, items, rng, lambda x, y: growable(x, y) and (x, y) not in flora))
    clumps = kit["clumps"]
    learned = json.loads((ROOT / clumps["quantiles"]).read_text(encoding="utf-8"))
    on_grass = lambda x, y: family(x, y) == base
    u = rank_field(size, blend(size, rng, [(7, 0.6), (3, 0.4)]), on_grass)
    edge_base = distance(size, [[not on_grass(x, y) for x in range(size)] for y in range(size)])
    buckets = learned["buckets"]

    def bucket_at(x, y):
        d = edge_base[y][x]
        return next((k for k, (lo, hi) in enumerate(buckets) if lo <= d <= hi), None)

    def canopy(x, y):  # canopies may hang over roads, sand and water, never over raised ground or bridges
        return not mountain[y][x] and not hill[y][x] and (x, y) not in span

    blocking_bases = {t for t, i in flora.items() if "not_walkable" in items[int(i)]["flags"]}
    grass_plants = place_clumped(size, u, learned["quantiles"], bucket_at,
                                 {"big": clumps["big"], "small": clumps["small"]}, items, rng,
                                 lambda x, y: on_grass(x, y) and growable(x, y) and (x, y) not in flora,
                                 canopy, {c: v * p.vegetation / 100 for c, v in clumps["boost"].items()},
                                 blocking=blocking_bases, edge_boost=clumps.get("edge_boost"))
    flora.update(grass_plants)

    # glades: small dense groves scattered through big open meadows (user review: large meadows read empty).
    # Deep grass (6+ tiles from any other ground) under the top 10% of a fine noise gets plants at the density
    # the reference map has right beside edges (clump bucket 2-3), so each glade is a tight cluster with open grass around
    deep = lambda x, y: edge_base[y][x] >= 6 and on_grass(x, y) and growable(x, y) and (x, y) not in flora
    glade = quantile_region(size, blend(size, rng, [(4, 0.7), (2, 0.3)]), 0.10, deep)
    u2 = rank_field(size, blend(size, rng, [(3, 1.0)]), lambda x, y: glade[y][x])
    flora.update(place_clumped(size, u2, learned["quantiles"], lambda x, y: 1,
                               {"big": clumps["big"], "small": clumps["small"]}, items, rng,
                               lambda x, y: glade[y][x] and (x, y) not in flora, canopy,
                               {c: v * p.vegetation / 100 for c, v in clumps["boost"].items()}))

    if clumps.get("cliff_small"):  # kit clumps.cliff_small: grass at a cliff foot (touching the mountain, not water) takes the
        # walkable small plants too, at this share of the clump density (the reference: 19% of such tiles, ours had none)
        walk_small = {i: w for i, w in clumps["small"].items() if not blocking(i)}
        flora.update(place_clumped(size, u, learned["quantiles"], bucket_at, {"small": walk_small}, items, rng,
                                   lambda x, y: on_grass(x, y) and open_ground(x, y) and touches(mountain, x, y)
                                   and not touches(water, x, y) and not touches(hill, x, y) and (x, y) not in ramps
                                   and (x, y) not in mramps and (x, y) not in span and (x, y) not in keep
                                   and (x, y) not in flora, canopy,
                                   {"small": clumps["cliff_small"] * p.vegetation / 100}))

    def bank(x, y):
        # jungle grass touching water (not cliff or ramp tiles): The reference map's banks carry water-edge plants
        return (family(x, y) == kit["base"]["family"] and touches(water, x, y) and not touches(mountain, x, y)
                and not touches(hill, x, y) and (x, y) not in ramps and (x, y) not in mramps
                and (x, y) not in span)

    # bases on bank tiles; footprints may reach over the water, as the reference map's agaves and sludge ferns do
    banks = place_flora(size, lambda x, y: kit["base"]["family"], kit["bank_flora"], items, rng,
                        lambda x, y: (water[y][x] or bank(x, y) or growable(x, y)) and (x, y) not in flora)
    banks = {pos: i for pos, i in banks.items() if bank(*pos)}
    flora.update(banks)

    # meadow cover: grass where nothing grew within 2 tiles gets the reference map's deep-meadow scatter (tools/meadow_items.py:
    # tufts, mushrooms, a few wig bushes, all walkable), a little denser than the reference map (user review: open
    # meadows read empty)
    bases = set(flora)
    bare = lambda x, y: (on_grass(x, y) and growable(x, y) and (x, y) not in bases
                         and not any((x + i, y + j) in bases for i in range(-2, 3) for j in range(-2, 3)))
    flora.update(place_flora(size, lambda x, y: "meadow", {"meadow": kit["meadow"]}, items, rng, bare))

    water_ground, water_plants = liquid(size, rng, kit, items, water, mountain, fords, span)
    layer = {}
    for y in range(size):
        for x in range(size):
            f = family(x, y)
            if f == "water":  # where a mountain meets the water, the reference map draws its cliff on the water tiles; in a
                # kit where land ranks above water (fire), the land's border is drawn on the water tiles too
                ground = water_ground(x, y) if water_ground else pick(rng, kit["water"])
                stack = [ground] + layered_borders(kit, keys, x, y) + edge_pieces(mountain, x, y, kit["mountain_cliff"])
                if (x, y) in water_plants:
                    stack.append(water_plants[(x, y)])
            elif f == "relief":
                stack = [kit["mountain" if mountain[y][x] else "hill"]["lead"]]
            elif f == "bridge":
                stack = []  # laid by the bridge pass below
            else:
                stack = [pick(rng, kit[keys[y][x]])] + layered_borders(kit, keys, x, y)
                if ramps.get((x, y), (None, 1))[1] != 0:  # a ramp replaces the cliff on its tile
                    stack += edge_pieces(hill, x, y, kit["hill_cliff"])
                if mramps.get((x, y), (None, 1))[1] != 0:
                    stack += edge_pieces(mountain, x, y, kit["mountain_cliff"])
                if (x, y) in ramps:
                    d, half = ramps[(x, y)]
                    stack.append(kit["hill_ramp"][d][half])
                if (x, y) in mramps:
                    d, half = mramps[(x, y)]
                    stack.append(kit["mountain_ramp"][d][half])
                if (x, y) in flora:
                    stack.append(flora[(x, y)])
            layer[(ORIGIN + x, ORIGIN + y)] = stack

    # bridges (class Bridge): lip on the first bank tile, deck over the water, end piece on the far bank tile;
    # rail pieces (end, first, repeated middle, last, end) on top of the stacks beside the deck
    families = kit.get("bridge_families")  # kit key: [{"name": .., "ew": {..}, "ns": {..}}, ..]; one per crossing, seeded by crossing
    kinds = []
    for b in ([] if ford else bridges):
        kb = kit["bridge_ns" if b.ns else "bridge_ew"]
        if families:
            fam = random.Random(f"bridge-{p.seed}-{b.key()}").choice(families)
            kb = fam["ns" if b.ns else "ew"]
            kinds.append(fam.get("name", "?"))
        for x, y in b.deck():
            along = y if b.ns else x
            if along == b.start:  # the lip lies on the inland tile's own ground and borders (a family without a lip leaves the tile as it is)
                if kb.get("lip"):
                    layer[(ORIGIN + x, ORIGIN + y)].append(kb["lip"])
            else:
                layer[(ORIGIN + x, ORIGIN + y)] = [kb.get("end", kb["deck"]) if along == b.end else kb["deck"]]
        for line, rail in zip(b.rails(), (kb["west"], kb["east"]) if b.ns else (kb["north"], kb["south"])):
            for k, (x, y) in enumerate(line):
                last = len(line) - 1
                piece = rail[0] if len(rail) == 1 or k == 0 else rail[1] if k == 1 else rail[4] if k == last \
                    else rail[3] if k == last - 1 else rail[2]  # a one-piece rail repeats along the whole side
                layer[(ORIGIN + x, ORIGIN + y)].append(piece)

    floors = {Z: layer}
    top_flora, terrace_ramps, routes = mountain_levels(size, m["levels"], kit, items, rng, floors, terrace, keep,
                                                       [mramps, *terrace], p.vegetation)

    # earth hills: one level (see gen/island.py)
    floor = floors.setdefault(Z - 1, {})
    drop = [[not v for v in row] for row in hill]
    for y in range(size):
        for x in range(size):
            if not hill[y][x]:
                continue
            pos = (ORIGIN + x, ORIGIN + y)
            stack = [pick(rng, kit["base"])]
            rim = edge_pieces(drop, x, y, kit["hill_rim"], outside=True)
            stack += rim
            if not rim and rng.random() < 0.18:
                around = {int(i) for j in (-1, 0, 1) for i_ in (-1, 0, 1)
                          for i in floor.get((pos[0] + i_, pos[1] + j), [])[1:]}
                options = {k: v for k, v in kit["hill_top"].items() if int(k) not in around
                           and items[int(k)]["groups"][0]["width"] == 1}
                if options:
                    stack.append(weighted(rng, options))
            floor[pos] = stack
    # access: every ramp reachable from the main ground; plants that cut a ramp off are cleared
    ramp_dirs = {ids[0]: d for key in ("mountain_ramp", "hill_ramp") for d, ids in kit.get(key, {}).items()}
    plant_ids = {int(i) for t in (kit["flora"], kit["top_flora"], kit["bank_flora"]) for f in t.values() for i in f}
    plant_ids |= {int(i) for c in ("big", "small") for i in kit["clumps"][c]} | {int(i) for i in kit.get("hill_top", {})}
    # odd borders (tools/odd_borders.py): tiles where one set's pieces face opposite ways; every 12-piece set
    sets = [s for s, v in kit.items() if isinstance(v, dict) and "edge_n" in v and "inner_se" in v]
    piece_of = {int(i): (s, n.partition("_")[2]) for s in sets for n, i in kit[s].items()}
    odd = Counter()
    for fl in floors.values():
        for stack in fl.values():
            faces = {}
            for i in stack:
                if int(i) in piece_of:
                    s, d = piece_of[int(i)]
                    faces.setdefault(s, set()).update(d)
            for s, f in faces.items():
                if ("n" in f and "s" in f) or ("e" in f and "w" in f):
                    odd[s] += 1
    # grounds with no water border (sand, grey sand, gravel) must never touch water: the seam would be bare
    unbordered = sum(1 for y in range(size) for x in range(size)
                     if keys[y][x] in kit.get("no_water_border", UNBORDERED_AT_WATER)
                     and any(0 <= x + i < size and 0 <= y + j < size and keys[y + j][x + i] == "water"
                             for i, j in ((0, 1), (1, 0), (0, -1), (-1, 0))))
    # bare seams: two different grounds of the layer table side by side where the higher draws no border
    layer_of = {lay["kit"]: lay for lay in kit["layers"]}
    rank = {lay["kit"]: r for r, lay in enumerate(kit["layers"])}
    bare = Counter()
    for y in range(size):
        for x in range(size):
            for i, j in ((1, 0), (0, 1)):
                if x + i < size and y + j < size:
                    a, b = keys[y][x], keys[y + j][x + i]
                    if a != b and a in rank and b in rank:
                        hi_, lo_ = (a, b) if rank[a] > rank[b] else (b, a)
                        if not border_of(layer_of[hi_], lo_):
                            bare[f"{hi_}|{lo_}"] += 1
    grey_cliff, brown_cliff = set(kit["mountain_cliff"].values()), set(kit.get("hill_cliff", {}).values())
    clashes = sum(1 for s in floors[Z].values() if {int(i) for i in s} & grey_cliff and {int(i) for i in s} & brown_cliff)
    access.NO_WALK = water_ids(kit)  # liquid never counts as walkable ground (see gen/access.py NO_WALK)
    start = access.main_start(floors, items)
    cleared, cut = access.repair(floors, items, ramp_dirs, plant_ids, start, kit.get("repair_pocket", 4)) if start else (0, [])
    dropped = access.drop_cut_off_tops(floors, items, ramp_dirs, start, Z) if start and kit.get("drop_cut_off_tops") else {}
    closed = access.close_pockets(floors, items, ramp_dirs, start, kit["pocket_fill"], rng) \
        if start and kit.get("pocket_fill") else 0  # kit pocket_fill: ids of 1x1 blocking plants that close unreached nooks
    check = access.report(floors, items, ramp_dirs, start) if start else {}
    stats = {"access": {**check, "plants_cleared": cleared, "cut_off": cut, "passes": m["passes"],
                        "pockets_sealed": m["sealed"], "land_necks": necks, "tops_dropped": dropped, "pockets_closed": closed, "route_tiles": routes, "cliff_clashes": clashes,
                        "odd_borders": dict(odd), "ground_settled": settled, "bare_water_seams": unbordered,
                        "bare_seams": dict(bare), "fords": len(fords),
                        "narrow_share": access.widths(floors, items),
                        "top_parts_with_ramp": top_parts},
             "flora": len(flora), "top_flora": top_flora, "ramps": len(ramps) // 2,
             "bridges": [("ns" if b.ns else "ew", *[ORIGIN + v for v in b.tile(b.start, b.at)], b.end - b.start + 1)
                         for b in bridges], "bridge_sites": len(sites), "bridge_kinds": kinds,
             "mountain_ramps": [len(mramps) // 2, *terrace_ramps],
             "levels": [sum(map(sum, v)) for v in m["levels"]],
             "sand": sum(map(sum, sand)), "grey": sum(map(sum, grey)), "river": len(m["river"]),
             **{k: sum(map(sum, m[k])) for k in ("water", "hill")}}
    return floors, stats


def mountain_levels(size, levels, kit, items, rng, floors, terrace, keep, arrivals, vegetation=100):
    """Stacked mountain levels, as the reference map builds them: a level-k tile carries the fill on every floor below its
    top, and its walkable top is a ground on Z - k. A top's edge tiles get the rim toward the drop; top tiles
    beside the next level get the mountain cliff. Tops get ground patchwork (top_patches) and plants at the
    main map's top rates. Each patch of the next level gets a rock ramp up from this level's top: the ramp on
    the top tile beside it, the lower half one tile further out, both off the rim.
    arrivals[k - 1]: the ramps that lead onto level k. Returns (plants on tops, ramps per terrace level, route
    corridor tiles per level)."""
    total, ramp_counts, routes = 0, [], []
    for k, mask in enumerate(levels, 1):
        floor = floors.setdefault(Z - k, {})
        higher = levels[k] if k < len(levels) else None
        drop = [[not v for v in row] for row in mask]
        inside = distance(size, drop)
        near_higher = distance(size, higher) if higher else [[size] * size for _ in range(size)]
        top = [[mask[y][x] and not (higher and higher[y][x]) for x in range(size)] for y in range(size)]
        free = [[inside[y][x] >= 2 and near_higher[y][x] >= 1 for x in range(size)] for y in range(size)]
        ramps = terrace[k - 1] if higher else {}
        ramp_counts += [len(ramps) // 2] if higher else []
        # stacked cliffs (tools/double_cliff.py): where the next level stands one tile in from this level's edge,
        # the reference map often leaves the ring tile without ground or rim, holding only the higher level's cliff pieces,
        # so the two cliffs read as one tall rock face (35% of level-2 edges; 22% keep a 1-tile ledge)
        stacked = [[False] * size for _ in range(size)]
        if higher:
            runs = blend(size, rng, [(4, 0.6), (2, 0.4)])
            near_ramp = {(x + i, y + j) for x, y in ramps for i in (-1, 0, 1) for j in (-1, 0, 1)}
            for y in range(size):
                for x in range(size):
                    if (top[y][x] and inside[y][x] == 1 and touches(higher, x, y) and runs[y][x] > 0.4
                            and (x, y) not in near_ramp):
                        stacked[y][x] = True
                        top[y][x] = False
        keys = top_patches(size, rng, top, inside, near_higher, k, "gravel" in kit, kit.get("top_rock"), kit.get("top_mix"))
        tidy_grounds(kit, keys, rng)
        family = {}
        for y in range(size):
            for x in range(size):
                if not mask[y][x]:
                    continue
                pos = (ORIGIN + x, ORIGIN + y)
                if stacked[y][x]:
                    floor[pos] = edge_pieces(higher, x, y, kit["mountain_cliff"])
                    continue
                if not top[y][x]:
                    floor[pos] = [kit["mountain"]["lead"]]
                    continue
                key = keys[y][x]
                family[(x, y)] = kit[key]["family"]
                stack = [pick(rng, kit[key])] + layered_borders(kit, keys, x, y)
                stack += edge_pieces(drop, x, y, kit["top_rim"], outside=True)
                if higher and ramps.get((x, y), (None, 1))[1] != 0:  # the ramp replaces the cliff on its tile
                    stack += edge_pieces(higher, x, y, kit["mountain_cliff"])
                if (x, y) in ramps:
                    d, half = ramps[(x, y)]
                    stack.append(kit["mountain_ramp"][d][half])
                floor[pos] = stack
        base = kit["base"]["family"]
        # routes on this top (user review: paths among mountains must make sense): every ramp arriving here is
        # joined to every ramp leaving it and to the middle of each top part it lands on, along paths that keep
        # off the edges; a 3-wide corridor around them takes only walkable plants, groves grow elsewhere
        onto = arrivals[k - 1]
        arrive = [(x + DIRS[d][0], y + DIRS[d][1]) for (x, y), (d, half) in onto.items() if half == 0]
        leave = [(x - 2 * DIRS[d][0], y - 2 * DIRS[d][1]) for (x, y), (d, half) in ramps.items() if half == 0]
        walk_top = lambda x, y: top[y][x]
        middles = []
        for part in parts8(size, walk_top):
            if len(part) >= 30 and any(t in part for t in arrive):
                cx = sum(x for x, _ in part) / len(part)
                cy = sum(y for _, y in part) / len(part)
                middles.append(min(part, key=lambda t: (t[0] - cx) ** 2 + (t[1] - cy) ** 2))
        corridor = route_corridors(size, walk_top, arrive + leave, middles)
        routes.append(len(corridor))
        clear = lambda x, y: top[y][x] and near_higher[y][x] >= 2 and (x, y) not in ramps and (x, y) not in keep
        # rock soil, gravel and sand on tops: per-tile rates, never on the corridor
        plants = place_flora(size, lambda x, y: family.get((x, y)),
                             {f: t for f, t in kit["top_flora"].items() if f != base}, items, rng,
                             lambda x, y: clear(x, y) and (x, y) not in corridor)
        # jungle grass on tops: clumped like the main map's tops on this floor (tools/clump_study.py --floor);
        # rim tiles included: on the reference map they carry more plants than inner top tiles (tools/rim_plants.py)
        clumps = kit["clumps"]
        learned = json.loads((ROOT / clumps["tops"][str(min(k, len(clumps["tops"])))]).read_text(encoding="utf-8"))
        grass = lambda x, y: family.get((x, y)) == base
        u = rank_field(size, blend(size, rng, [(7, 0.6), (3, 0.4)]), grass)
        edge = distance(size, [[mask[y][x] and not grass(x, y) for x in range(size)] for y in range(size)])
        buckets = learned["buckets"]

        def bucket_at(x, y):
            return next((b for b, (lo, hi) in enumerate(buckets) if lo <= edge[y][x] <= hi), None)

        def canopy(x, y):  # never under the next level or over a ramp; may hang over this level's drop
            return not (higher and higher[y][x]) and (x, y) not in ramps

        plants.update(place_clumped(size, u, learned["quantiles"], bucket_at,
                                    {"big": clumps["big"], "small": clumps["small"]}, items, rng,
                                    lambda x, y: grass(x, y) and clear(x, y) and (x, y) not in plants, canopy,
                                    {c: v * vegetation / 100 for c, v in clumps["boost"].items()},
                                    walk_only=corridor))
        for (x, y), i in plants.items():
            floor[(ORIGIN + x, ORIGIN + y)].append(i)
        total += len(plants)
    return total, ramp_counts, routes


def main():
    p = argparse.ArgumentParser(description="Knobs follow a map editor's 'Generate Area' dialog; 100 = as on the reference map.")
    p.add_argument("--name", default="island-v10")
    p.add_argument("--kit", help="kit/<name>.json (default: $MAPSTUDIO_KIT, else the studio default)")
    p.add_argument("--size", type=int, default=96, help="area width and height in tiles")
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--rough", type=int, default=70, help="coastline roughness 0-100")
    p.add_argument("--mountains", type=float, default=36, help="level 1 as %% of inland tiles (0 = none)")
    p.add_argument("--levels", type=int, default=4, help="most mountain levels (1-5)")
    p.add_argument("--hills", type=float, default=4, help="earth hills as %% of inland tiles")
    p.add_argument("--lakes", type=float, default=0, help="inland lakes as %% of inland tiles")
    p.add_argument("--sea-cliffs", type=float, default=15,
                   help="share of the land (by a coarse noise field) where mountains may run into the water")
    p.add_argument("--rivers", type=int, default=0, help="rivers from inland springs to the sea")
    p.add_argument("--river-width", type=int, default=3)
    p.add_argument("--roads", type=int, default=3, help="shore points joined by roads (-1 = no roads)")
    p.add_argument("--sand", type=float, default=4, help="sand patches as %% of open ground")
    p.add_argument("--vegetation", type=float, default=100, help="plant density, 100 = reference map")
    a = p.parse_args()
    # the kit's own defaults (fire: no earth hills, wider lava rivers) for every knob left at its default
    a.kit = kit_name(a.kit)
    kit_defaults = load_kit(a.kit).get("defaults", {})
    for k, v in kit_defaults.items():
        if getattr(a, k) == p.get_default(k):
            setattr(a, k, v)
    area, stats = build(a)
    out = ROOT / "areas" / a.name
    knobs = {k: v for k, v in vars(a).items() if k != "name"}
    save_area(out / "area.txt", area, {"gen": "generate", **knobs, **stats})
    land = a.size * a.size - stats["water"]
    print(a.name, f"land {land} tiles: mountains {stats['levels'][0] / land:.0%} "
          f"(levels {stats['levels']}), hills {stats['hill'] / land:.0%}, sand {stats['sand'] / land:.0%}, "
          f"plants {stats['flora'] + stats['top_flora']}, ramps {stats['ramps']} + {stats['mountain_ramps']}, "
          f"bridges {stats['bridges']} of {stats['bridge_sites']} sites, kinds {stats.get('bridge_kinds', [])}")
    acc = stats["access"]
    print(f"  paths: route corridor tiles per level {acc['route_tiles']}, share of walkable tiles in 1-2 wide "
          f"space per floor {acc['narrow_share']}, grey/brown cliff clashes {acc['cliff_clashes']}")
    print(f"  borders: odd tiles per set {acc['odd_borders']}, ground tiles settled {acc['ground_settled']}, "
          f"unbordered ground touching water {acc['bare_water_seams']}, bare seams {acc['bare_seams']}, "
          f"ford tiles {acc['fords']}")
    print(f"  access: passes {acc['passes']}, pocket tiles sealed {acc['pockets_sealed']}, land necks {acc.get('land_necks', 0)}, pocket tiles closed {acc.get('pockets_closed', 0)}, cut-off top tiles dropped {acc.get('tops_dropped', {})}, top parts 30+ with a ramp per level {acc['top_parts_with_ramp']}, "
          f"ramps usable {acc.get('ramps_usable')}, plants cleared {acc['plants_cleared']}, "
          f"cut off {acc['cut_off']}, reached/walkable per floor {acc.get('reached/walkable')}")
    subprocess.run([sys.executable, "-B", str(ROOT / "run.py"), "tools/render.py", str(out / "area.txt"),
                    "--floor", str(Z), "--upper", "--out", str(out / "render.png")], check=True)


if __name__ == "__main__":
    main()
