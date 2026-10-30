"""Asymmetric area rule (docs/MAP_GUIDE.md "Asymmetric areas"): scores of the walkable mask of one floor.

A new area is never round, square or rectangular. Four numbers, limits in areaplan/shape_rules.json:
  symmetry lr / tb   overlap (intersection over union) of the mask with its mirror image in the bounding box
  bbox fill          walkable tiles / bounding box tiles (a rectangle is 1.0)
  hull fill          walkable tiles / convex hull area (a disc or a box is about 1.0, a lobed outline is lower)
  straight run       the longest straight run of edge tiles on one side (a built wall, not a grown one)
Pure functions on a set of (x, y) cells, so the tests feed synthetic masks.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
RULES = os.path.join(HERE, 'areaplan', 'shape_rules.json')


def rules():
    with open(RULES, encoding='utf-8') as f:
        return json.load(f)


def is_legacy(plan_id, cfg=None):
    return plan_id in (cfg or rules())['legacy_plans']


def _hull_area(cells):
    pts = set()
    for x, y in cells:
        pts.update(((x, y), (x + 1, y), (x, y + 1), (x + 1, y + 1)))
    pts = sorted(pts)
    if len(pts) < 3:
        return float(len(cells))

    def half(seq):
        out = []
        for p in seq:
            while len(out) >= 2 and (out[-1][0] - out[-2][0]) * (p[1] - out[-2][1]) - (out[-1][1] - out[-2][1]) * (p[0] - out[-2][0]) <= 0:
                out.pop()
            out.append(p)
        return out
    h = half(pts)[:-1] + half(reversed(pts))[:-1]
    a = 0
    for i in range(len(h)):
        x1, y1 = h[i]
        x2, y2 = h[(i + 1) % len(h)]
        a += x1 * y2 - x2 * y1
    return abs(a) / 2.0


def longest_straight_run(cells):
    """longest run of walkable tiles in a line whose same side (north, south, west or east) is not walkable"""
    cells = set(cells)
    best = 0
    for dx, dy in ((0, -1), (0, 1), (-1, 0), (1, 0)):
        edge = {(x, y) for x, y in cells if (x + dx, y + dy) not in cells}
        for x, y in edge:
            px, py = (1, 0) if dy else (0, 1)       # along the edge
            if (x - px, y - py) in edge:
                continue                              # not the start of a run
            n = 0
            while (x + n * px, y + n * py) in edge:
                n += 1
            best = max(best, n)
    return best


def scores(cells):
    cells = set(cells)
    if not cells:
        return dict(tiles=0, sym_lr=0.0, sym_tb=0.0, bbox_fill=0.0, hull_fill=0.0, straight=0, bbox=(0, 0))
    x0, x1 = min(c[0] for c in cells), max(c[0] for c in cells)
    y0, y1 = min(c[1] for c in cells), max(c[1] for c in cells)
    w, h = x1 - x0 + 1, y1 - y0 + 1
    lr = {(x0 + x1 - x, y) for x, y in cells}
    tb = {(x, y0 + y1 - y) for x, y in cells}
    return dict(tiles=len(cells), bbox=(w, h),
                sym_lr=round(len(cells & lr) / len(cells | lr), 3),
                sym_tb=round(len(cells & tb) / len(cells | tb), 3),
                bbox_fill=round(len(cells) / float(w * h), 3),
                hull_fill=round(len(cells) / _hull_area(cells), 3),
                straight=longest_straight_run(cells))


def breaches(sc, cfg=None):
    """list of text lines, one per limit the scores break; empty when the outline is asymmetric enough"""
    cfg = cfg or rules()
    out = []
    if sc['sym_lr'] > cfg['max_symmetry_lr']:
        out.append('left-right mirror overlap %.2f (limit %.2f): too symmetric' % (sc['sym_lr'], cfg['max_symmetry_lr']))
    if sc['sym_tb'] > cfg['max_symmetry_tb']:
        out.append('top-bottom mirror overlap %.2f (limit %.2f): too symmetric' % (sc['sym_tb'], cfg['max_symmetry_tb']))
    if sc['bbox_fill'] > cfg['max_bbox_fill']:
        out.append('fills %.2f of its bounding box (limit %.2f): too boxy' % (sc['bbox_fill'], cfg['max_bbox_fill']))
    if sc['hull_fill'] > cfg['max_hull_fill']:
        out.append('fills %.2f of its convex hull (limit %.2f): too round or convex' % (sc['hull_fill'], cfg['max_hull_fill']))
    if sc['straight'] > cfg['max_straight_run']:
        out.append('a straight edge run of %d tiles (limit %d): looks built, not grown' % (sc['straight'], cfg['max_straight_run']))
    return out


def check_floors(walk, plan_id, floors_z, cfg=None):
    """QA lines [(level, text)] for the walkable (x, y, z) tiles of every floor with enough tiles.
    ERROR for a new plan, WARN for a plan of the legacy list"""
    cfg = cfg or rules()
    level = 'WARN' if is_legacy(plan_id, cfg) else 'ERROR'
    out = []
    for n, z in enumerate(floors_z, 1):
        cells = {(x, y) for x, y, zz in walk if zz == z}
        if len(cells) < cfg['min_floor_tiles']:
            continue
        for b in breaches(scores(cells), cfg):
            out.append((level, 'outline of floor %d: %s (docs/MAP_GUIDE.md "Asymmetric areas")' % (n, b)))
    return out
