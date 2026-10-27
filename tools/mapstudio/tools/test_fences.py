"""Fence check (round 10): fence and wall lines have no gaps, their corners are wall pieces, their doors can be walked.

python -B run.py tools/test_fences.py                  # kit stamps (static) + every areas/*/seed-*/area.txt of kits with wall sets
python -B run.py tools/test_fences.py areas/carnival-review-05      # a batch (or one seed folder) only
Exit code 1 when any check fails. Three parts:

1. Stamp patterns (every kit's `stamps`, no game data needed). A stamp that has wall cells must be a closed outline:
   - every non-wall cell on the outline (the pattern's edge ring) is part of a doorway: a run of ring cells with a wall cell at both
     ends, no corner cell inside it (a corner left out, or a lantern standing on it, leaves the two runs that meet there apart);
   - no wall cell is a loose end: a cell with one wall neighbour must be followed on its line by a floor cell without items (a
     doorway) or by the edge of the pattern; no lone wall cell;
   - an outline with an interior can be entered: a doorway in the ring or a fixed piece (`piece`) that can be walked (a closed door or
     gate seals the interior, and the access repair used to cut a hole into the fence to reach it).
   The walkable test of fixed pieces needs the item data (config.json); without it the piece test is skipped and said so.
2. Unit tests of the pattern rules on made-up patterns (an open corner, a lantern corner, a sealed box, a good box).
3. Areas (header-less, read from area.txt): wallcheck.fence_gaps per area must be 0 (a fence run ending against a blocking item,
   rock or void, a lone fence tile). Needs the item data; skipped without it.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "gen"))

from common import ROOT, load_area, load_items, load_kit, water_ids  # noqa: E402
import wallcheck  # noqa: E402

N4 = ((0, -1), (1, 0), (0, 1), (-1, 0))


def pattern_problems(spec, walkable=None):
    """Problems of one stamp spec as strings. `walkable(piece id)` says whether a fixed piece can be walked (None: not tested)."""
    rows = list(spec["pattern"])
    w = max(len(r) for r in rows)
    rows = [r.ljust(w) for r in rows]
    h = len(rows)
    legend = spec["legend"]
    cell = lambda x, y: legend.get(rows[y][x], {}) if 0 <= x < w and 0 <= y < h and rows[y][x] != " " else None
    is_wall = lambda x, y: bool((cell(x, y) or {}).get("wall"))
    walls = {(x, y) for y in range(h) for x in range(w) if is_wall(x, y)}
    if not walls:
        return []
    out = []
    # 1. the outline: non-wall cells of the edge ring form doorways bounded by walls
    ring = [(x, y) for y in range(h) for x in range(w) if x in (0, w - 1) or y in (0, h - 1)]
    corners = {(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)}
    for c in sorted(corners):
        if c not in walls:
            out.append(f"corner cell {c} of the outline is not a wall cell (the two runs that meet there stay apart)")
    doorways = 0
    for t in ring:
        if t in walls or t in corners:
            continue
        # a ring cell without wall: it must sit in a run that is bounded by wall cells along the ring on both sides
        # (walk along the ring both ways; both ends must be wall cells)
        x, y = t
        along = ((1, 0), (-1, 0)) if y in (0, h - 1) else ((0, 1), (0, -1))
        ends = []
        for dx, dy in along:
            u = t
            while 0 <= u[0] + dx < w and 0 <= u[1] + dy < h and (u[0] + dx, u[1] + dy) not in walls:
                u = (u[0] + dx, u[1] + dy)
            ends.append((u[0] + dx, u[1] + dy) in walls)
        if not all(ends):
            out.append(f"ring cell {t} has no wall at the end of its run (the outline is open there)")
    # a doorway is a run; count runs once by their first cell
    for t in ring:
        if t in walls or t in corners:
            continue
        along = (-1, 0) if t[1] in (0, h - 1) else (0, -1)
        if (t[0] + along[0], t[1] + along[1]) in walls:
            doorways += 1
    # 2. loose ends
    for t in sorted(walls):
        nb = [d for d in N4 if (t[0] + d[0], t[1] + d[1]) in walls]
        if not nb:
            out.append(f"lone wall cell {t}")
        elif len(nb) == 1:
            u = (t[0] - nb[0][0], t[1] - nb[0][1])
            c = cell(*u)
            if c is not None and (c.get("items") or c.get("wall")) and u not in walls:
                out.append(f"wall cell {t} ends against an item cell {u} (a lantern or prop where the outline turns)")
    # 3. the interior can be entered
    interior = [(x, y) for y in range(1, h - 1) for x in range(1, w - 1) if (x, y) not in walls]
    if interior and not doorways:
        pieces = {int(c["piece"]) for c in (legend.get(ch, {}) for ch in set("".join(rows))) if c.get("wall") and c.get("piece")}
        if walkable is None:
            pass
        elif not any(walkable(p) for p in pieces):
            out.append("the interior is sealed: no doorway and no walkable door or gate piece "
                       f"(fixed pieces {sorted(pieces)}; a blocking door shuts the outline, the repair pass then cut a hole into it)")
    return out


def try_items():
    try:
        return load_items()
    except Exception as e:  # no data files in this checkout
        print(f"SKIP item data not available ({type(e).__name__}): walkable piece test and area scan")
        return None


def unit_tests():
    bad = 0

    def expect(name, spec, want, walkable=None):
        nonlocal bad
        got = pattern_problems(spec, walkable)
        if bool(got) != want:
            bad += 1
            print(f"FAIL unit {name}: {'no problem found' if want else 'unexpected ' + str(got)}")

    leg = {"#": {"wall": "w"}, "L": {"items": [1]}, ".": {}, "D": {"wall": "w", "piece": 7}}
    good = ["#######", "#.....#", "#.....#", "##...##"]
    expect("closed box with a doorway", {"pattern": good, "legend": leg}, False)
    expect("lantern on the corner", {"pattern": ["L#####L", "#.....#", "#.....#", "##...##"], "legend": leg}, True)
    expect("empty corner", {"pattern": [".#####.", "#.....#", "#.....#", "##...##"], "legend": leg}, True)
    expect("lantern in a doorway of the outline", {"pattern": ["###L###", "#.....#", "#.....#", "#######"], "legend": leg}, True)
    expect("sealed box, blocking door", {"pattern": ["#######", "#.....#", "###D###"], "legend": leg}, True, lambda p: False)
    expect("box, walkable door", {"pattern": ["#######", "#.....#", "###D###"], "legend": leg}, False, lambda p: True)
    expect("lone wall cell", {"pattern": ["#######", "#.....#", "#..#..#", "#.....#", "##...##"], "legend": leg}, True)
    print(f"unit tests: {7 - bad}/7 ok")
    return bad


def stamp_tests(items):
    walkable = (lambda p: p in items and "not_walkable" not in items[p]["flags"]) if items else None
    bad = n = 0
    for f in sorted((ROOT / "kit").glob("*.json")):
        kit = load_kit(f.stem)
        for spec in kit.get("stamps") or []:
            n += 1
            for msg in pattern_problems(spec, walkable):
                bad += 1
                print(f"FAIL stamp {f.stem}/{spec['name']}: {msg}")
    print(f"stamp patterns: {n} checked, {bad} problems")
    return bad


def area_tests(items, args):
    if items is None:
        return 0
    paths = []
    for a in args or ["areas"]:
        p = (ROOT / a) if not Path(a).is_absolute() else Path(a)
        paths += sorted(p.glob("seed-*/area.txt")) + sorted(p.glob("*/seed-*/area.txt")) if not (p / "area.txt").exists() else [p / "area.txt"]
    bad = n = 0
    for path in paths:
        meta, area = load_area(path)
        kit = load_kit(meta["kit"])
        if not wallcheck.fence_ids(kit):
            continue
        n += 1
        pools = {int(i) for i in (meta.get("pools") or {}).get("ids", [])}
        no_walk = water_ids(kit) | pools | {int(i) for i in (kit.get("void_cover") or {}).get("ground", [])}
        r = wallcheck.fence_gaps(area.get(meta.get("floor", kit.get("floor", 7)), {}), meta["size"], 1000, items, kit, no_walk)
        if r["fence_gaps"]:
            bad += 1
            print(f"FAIL {path.parent.parent.name}/{path.parent.name}: fence_gaps {r['fence_gaps']} {r['samples']}")
    print(f"areas: {n} with wall sets checked, {bad} with fence gaps")
    return bad


def main():
    items = try_items()
    bad = unit_tests() + stamp_tests(items) + area_tests(items, [a for a in sys.argv[1:] if not a.startswith("-")])
    print("OK" if not bad else f"{bad} failing")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
