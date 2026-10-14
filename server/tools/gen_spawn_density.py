#!/usr/bin/env python3
"""Fill every thin base-map hunt to the target density: writes tools/spawn_density.json for patch_base_spawns.py.

usage: python3 -I gen_spawn_density.py DATA_DIR ITEMS_OTB [--map PATH.otbm|.npz] [--out PATH] [--target D] [--min D]
                                       [--cap F] [--max-add N] [--block N] [--spacing N] [--stats PATH] [--check]

DATA_DIR is a scratch install of the base server (install_all.py steps files, lib, monsternames, lategame, monsters,
spawns; docs/CONTENT.md). Needs numpy and the map reader of tools/map/ (otbm.py, itemdb.py); ITEMS_OTB defaults to
DATA_DIR/items/items.otb. The spawn file is read as the spawns step wrote it, without the fill this tool made before
(spawns marked chaosadd="F..." are ignored), so a second run on the same data gives the same JSON byte for byte.
--check compares instead of writing (exit status 1 when the JSON differs). --stats PATH writes every hunt (also those
not filled) with its numbers, for the README tables.

Hunts are grouped as tools/content_audit.py does (entries of monsters that give experience, on one floor, at most 12
tiles apart, at least 10 of them). For each hunt (server/README.md "Spawn density and respawn", Fill):
  region    walkable tiles within 6 sqm of one of its entries and connected to one, without protection zone, house,
            floor change, teleport or door tiles, and without the town tiles: 8 sqm around a house tile, 5 sqm around
            a protection zone tile
  skipped   a closed pocket (the walkable set around the hunt ends under 400 tiles and has no floor change or
            teleport: quest rooms reached by a lever or a scripted teleport), a region under 60 tiles, no monster
            that can be copied
  density   the hunt's entries per 100 region tiles. Under `min` (4.3) it is raised to `target` (4.5), at most
            `cap` x its entries more (2.5) and `max-add` (600) monsters. Hunts under hunting level 30 (the audit's
            level 15) keep the earlier fill: under 3.25 raised to 3.4, x2.0, +400, one-monster spawns (`low`)
  a spawn   a block of up to `block` (3) monsters: its centre on a free walkable tile of the region (no NPC within
            3 sqm, no floor change next to it), at least `spacing` (5) sqm from every other entry and block (down to
            3 when the region is full): the tile farthest from all of them, ties by x then y; the other monsters on
            the nearest free candidate tiles within 2 sqm. It copies the nearest ordinary entry of the hunt (no boss, a
            monster with 10+ entries on the map, spawntime up to 300 s, not one that tools/patch_base_spawns.py moved
            or added), and so its spawntime
"""
import collections, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import content_audit as audit  # noqa: E402
import gen_bounty_pool as pool  # noqa: E402
import patch_base_spawns as pbs  # noqa: E402

DEFAULT_OUT = os.path.join(HERE, 'spawn_density.json')
REACH = 6          # region: tiles within this many sqm of an entry
SPACING = 3        # a new spawn is at least this far from any entry (Chebyshev)
HOUSE_MARGIN = 8   # town tiles: this close to a house tile
PZ_MARGIN = 5      # ... or to a protection zone tile
NPC_MARGIN = 3
POCKET = 400       # a closed set under this many walkable tiles with no exit is a quest pocket
MIN_REGION = 60
MAX_SPAWNTIME = 300
MIN_COPIES = 10
BLOCK_RADIUS = 2   # a spawn block of the pack fill: its monsters within this many sqm of its centre

WALK, CAND, EXIT, PZ, HOUSE = 1, 2, 4, 8, 16


# ------------------------------------------------------------------------------------------------ pure planning
def dilate(mask, r):
    """Chebyshev dilation of a 2D numpy bool array by r"""
    import numpy as np
    h, w = mask.shape
    p = np.zeros((h + 2 * r, w + 2 * r), bool)
    p[r:r + h, r:r + w] = mask
    rows = np.zeros((h + 2 * r, w), bool)
    for d in range(2 * r + 1):
        rows |= p[:, d:d + w]
    out = np.zeros((h, w), bool)
    for d in range(2 * r + 1):
        out |= rows[d:d + h, :]
    return out


def pocket(grid, starts, limit=POCKET):
    """True when the walkable set reached from starts (through doors too) is closed: under limit tiles and no exit
    tile. grid[y][x] carries the WALK / EXIT bits; leaving the grid counts as open"""
    h, w = len(grid), len(grid[0])
    seen = set()
    todo = collections.deque()
    for s in starts:
        if s not in seen:
            seen.add(s)
            todo.append(s)
    while todo:
        x, y = todo.popleft()
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                nx, ny = x + dx, y + dy
                if (nx, ny) in seen:
                    continue
                if not (0 <= nx < w and 0 <= ny < h):
                    return False
                c = grid[ny][nx]
                if c & EXIT:
                    return False
                if c & WALK:
                    seen.add((nx, ny))
                    if len(seen) >= limit:
                        return False
                    todo.append((nx, ny))
    return True


def region_of(grid, entries, town):
    """walkable tiles (no exit tile) within REACH of an entry and connected to one; town[y][x] marks town tiles"""
    h, w = len(grid), len(grid[0])
    near = [[False] * w for _ in range(h)]
    for x, y in entries:
        for yy in range(max(0, y - REACH), min(h, y + REACH + 1)):
            row = near[yy]
            for xx in range(max(0, x - REACH), min(w, x + REACH + 1)):
                row[xx] = True

    def ok(x, y):
        c = grid[y][x]
        return near[y][x] and c & WALK and not c & (EXIT | PZ | HOUSE) and not town[y][x]
    seen = set()
    todo = collections.deque()
    for x, y in entries:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                p = (x + dx, y + dy)
                if 0 <= p[0] < w and 0 <= p[1] < h and p not in seen and ok(*p):
                    seen.add(p)
                    todo.append(p)
    while todo:
        x, y = todo.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            p = (x + dx, y + dy)
            if 0 <= p[0] < w and 0 <= p[1] < h and p not in seen and ok(*p):
                seen.add(p)
                todo.append(p)
    return seen


def place(region, cand, entries, n, spacing=SPACING):
    """up to n new points of region that are candidates: each the candidate farthest (Chebyshev) from every entry and
    point placed so far, at least `spacing` away; ties by x, then y. Deterministic."""
    pts = sorted(p for p in region if p in cand)
    if not pts or n <= 0:
        return []
    big = 1 << 30
    dist = {}
    for p in pts:
        dist[p] = min((max(abs(p[0] - e[0]), abs(p[1] - e[1])) for e in entries), default=big)
    out = []
    while len(out) < n:
        best, bd = None, -1
        for p in pts:
            d = dist[p]
            if d > bd:
                best, bd = p, d
        if best is None or bd < spacing:
            break
        out.append(best)
        for p in pts:
            d = max(abs(p[0] - best[0]), abs(p[1] - best[1]))
            if d < dist[p]:
                dist[p] = d
    return out


def nearest(p, sources):
    """the source (x, y) nearest to p: Chebyshev, then squared distance, then y, then x"""
    return min(sources, key=lambda s: (max(abs(s[0] - p[0]), abs(s[1] - p[1])),
                                       (s[0] - p[0]) ** 2 + (s[1] - p[1]) ** 2, s[1], s[0]))


def wanted(entries, tiles, lo, target, cap, max_add):
    """how many spawns a hunt of `entries` on `tiles` region tiles gets"""
    if tiles <= 0 or entries * 100.0 / tiles >= lo:
        return 0
    need = int(-(-target * tiles // 100)) - entries
    return max(0, min(need, int(cap * entries), max_add))


# ------------------------------------------------------------------------------------------------ map
def tile_codes(m, db):
    """uint8 code per map tile: WALK, CAND, EXIT, PZ, HOUSE"""
    import numpy as np
    from itemdb import C
    t = m.tiles
    n = len(t['x'])
    cnt = t['cnt'].astype(np.int64)
    owner = np.repeat(np.arange(n), cnt)
    ids = m.items.astype(np.int64)
    fl = db.flags
    door = db.cls == C['door']
    fc = (db.cls == C['floorchg']) | (db.group == 7)
    solid = ((fl & 1) > 0) & ~door & ~fc
    pathblk = ((fl & 4) > 0) & ~door & ~fc
    ground = db.group == 1

    def any_of(mask):
        return np.bincount(owner, weights=mask[ids], minlength=n) > 0
    has_ground, nsolid, npath = any_of(ground), any_of(solid), any_of(pathblk)
    nfc, ndoor = any_of(fc), any_of(door)
    pz = (t['flags'] & 1) > 0
    house = t['house'] > 0
    walk = has_ground & ~nsolid
    code = np.zeros(n, np.uint8)
    code[walk] |= WALK
    code[walk & ~npath & ~nfc & ~ndoor & ~pz & ~house] |= CAND
    code[nfc] |= EXIT
    code[pz] |= PZ
    code[house] |= HOUSE
    return code


def grid_of(m, code, x0, y0, x1, y1, z):
    import numpy as np
    w, h = x1 - x0 + 1, y1 - y0 + 1
    g = np.zeros((h, w), np.uint8)
    idx = m.rect(x0, y0, x1, y1, z)
    if len(idx):
        xs = m.tiles['x'][idx].astype(np.int64) - x0
        ys = m.tiles['y'][idx].astype(np.int64) - y0
        g[ys, xs] = code[idx]
    return g


# ------------------------------------------------------------------------------------------------ plan
def hunts_of(data_dir, spawn_text):
    """[(level, [(name, x, y, z, level, spawntime, copyable)])] and the NPC positions"""
    levels = audit.data_levels(data_dir)
    levels.update(audit.pool_levels())
    monsters = pool.load_monsters(data_dir)
    total = collections.Counter()
    rows, npcs = [], []
    for blk in pbs.SPAWN_RE.finditer(spawn_text):
        head = blk.group(1)
        if (pbs.attr(head, 'chaosadd') or '').startswith('F'):
            continue
        if pbs.attr(head, 'chaoscontent') is not None or pbs.attr(head, 'chaoshunt') is not None:
            continue  # a planned area (install step contentareas, after spawns): sized by its own plan
        added = pbs.attr(head, 'chaosadd') is not None
        c = (pbs.num(pbs.attr(head, 'centerx')), pbs.num(pbs.attr(head, 'centery')), pbs.num(pbs.attr(head, 'centerz')))
        for tag in pbs.MON_RE.findall(pbs.COMMENT_RE.sub('', blk.group(2))):  # not the entries the spawns step took out
            name = pbs.attr(tag, 'name') or ''
            x, y, z = pbs.entry_pos(c, tag)
            total[name.lower()] += 1
            rows.append((name, x, y, z, pbs.num(pbs.attr(tag, 'spawntime')),
                         not added and pbs.attr(tag, 'chaosxy') is None))
        for tag in re.findall(r'<npc\s[^>]*?/>', blk.group(2)):
            npcs.append((c[0] + pbs.num(pbs.attr(tag, 'x')), c[1] + pbs.num(pbs.attr(tag, 'y')), c[2]))
    entries = []
    for name, x, y, z, st, plain in rows:
        lv = levels.get(name.lower())
        if lv and lv[1] > 0 and not lv[2]:
            m = monsters.get(name.lower())
            copy = plain and pbs.huntable(m) and total[name.lower()] >= MIN_COPIES and 0 < st <= MAX_SPAWNTIME
            entries.append((name, x, y, z, lv[0], st, copy))
    out = []
    for g in audit.cluster([(e[1], e[2], e[3]) for e in entries]):
        if len(g) < audit.MIN_ENTRIES:
            continue
        hs = sorted(entries[i] for i in g)
        out.append((audit.weighted_median(sorted(r[4] for r in hs)), hs))
    out.sort(key=lambda h: (h[1][0][3], min(r[2] for r in h[1]), min(r[1] for r in h[1])))
    return out, npcs, [(r[1], r[2], r[3]) for r in rows]


def blocks_of(n, block):
    """sizes of the spawn blocks for n new monsters in blocks of up to `block` (the last one smaller)"""
    if n <= 0:
        return []
    block = max(1, block)
    full, rest = divmod(n, block)
    return [block] * full + ([rest] if rest else [])


def extras(center, cand, taken, k, radius=BLOCK_RADIUS):
    """up to k more tiles for a spawn block at center: candidates within `radius` (Chebyshev), not taken, nearest
    first, ties by x then y. Deterministic."""
    if k <= 0:
        return []
    cx, cy = center
    near = []
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            p = (cx + dx, cy + dy)
            if (dx or dy) and p in cand and p not in taken:
                near.append((max(abs(dx), abs(dy)), p[0], p[1]))
    near.sort()
    return [(x, y) for _d, x, y in near[:k]]


def plan(m, code, hunts, npcs, others, lo, target, cap, max_add, log=None, block=1, spacing=SPACING, low=None):
    """others: every monster entry of the file [(x, y, z)] (spacing counts all of them and the spawns placed here).
    block > 1: the new monsters come in spawn blocks of up to `block` (radius BLOCK_RADIUS) whose centres are at least
    `spacing` apart (falling back one sqm at a time down to SPACING when the region is full). low = (level, lo, target,
    cap, max_add): hunts under that level use those numbers with one-monster spawns (new players)."""
    npc_at = collections.defaultdict(list)
    for x, y, z in npcs:
        npc_at[z].append((x, y))
    B = 64
    bucket = collections.defaultdict(list)
    for x, y, z in others:
        bucket[(x // B, y // B, z)].append((x, y))
    areas, skipped = [], collections.Counter()
    pad = REACH + HOUSE_MARGIN + 2
    big = 32
    for k, (level, rows) in enumerate(hunts):
        if log and k % 100 == 0:
            log('%d / %d hunts' % (k, len(hunts)))
        z = rows[0][3]
        xs, ys = [r[1] for r in rows], [r[2] for r in rows]
        x0, y0, x1, y1 = min(xs) - pad - big, min(ys) - pad - big, max(xs) + pad + big, max(ys) + pad + big
        g = grid_of(m, code, x0, y0, x1, y1, z)
        ent = sorted(set((r[1] - x0, r[2] - y0) for r in rows))
        grid = g.tolist()
        starts = [(x + dx, y + dy) for x, y in ent for dx in (-1, 0, 1) for dy in (-1, 0, 1)
                  if grid[y + dy][x + dx] & WALK and not grid[y + dy][x + dx] & EXIT]
        if not starts or pocket(grid, starts):
            skipped['closed pocket'] += 1
            continue
        town = (dilate((g & HOUSE) > 0, HOUSE_MARGIN) | dilate((g & PZ) > 0, PZ_MARGIN)).tolist()
        region = region_of(grid, ent, town)
        if len(region) < MIN_REGION:
            skipped['region under %d tiles' % MIN_REGION] += 1
            continue
        h_lo, h_target, h_cap, h_max, h_block, h_spacing = lo, target, cap, max_add, block, spacing
        if low and level < low[0]:
            h_lo, h_target, h_cap, h_max = low[1:5]
            h_block, h_spacing = 1, SPACING
        n = wanted(len(rows), len(region), h_lo, h_target, h_cap, h_max)
        sources = [(r[1] - x0, r[2] - y0) for r in rows if r[6]]
        if n and not sources:
            skipped['no monster to copy'] += 1
            continue
        pts = []
        if n:
            exitd = dilate((g & EXIT) > 0, 1).tolist()
            npcd = set()
            for nx, ny in npc_at[z]:
                if x0 <= nx <= x1 and y0 <= ny <= y1:
                    for dy in range(-NPC_MARGIN, NPC_MARGIN + 1):
                        for dx in range(-NPC_MARGIN, NPC_MARGIN + 1):
                            npcd.add((nx - x0 + dx, ny - y0 + dy))
            cand = set(p for p in region if grid[p[1]][p[0]] & CAND and not exitd[p[1]][p[0]] and p not in npcd)
            near = set(ent)
            for bx in range(x0 // B, x1 // B + 1):
                for by in range(y0 // B, y1 // B + 1):
                    for ox, oy in bucket.get((bx, by, z), ()):
                        if x0 <= ox <= x1 and y0 <= oy <= y1:
                            near.add((ox - x0, oy - y0))
            if h_block <= 1:
                pts = [(p, []) for p in place(region, cand, sorted(near), n)]
            else:
                sizes = blocks_of(n, h_block)
                taken = set(near)
                centres = []
                sp = h_spacing
                while len(centres) < len(sizes) and sp >= SPACING:
                    got = place(region, cand, sorted(taken), len(sizes) - len(centres), sp)
                    for c in got:
                        taken.add(c)
                    centres += got
                    sp -= 1
                pts = []
                for c, size in zip(centres, sizes):
                    more = extras(c, cand, taken, size - 1)
                    for e in more:
                        taken.add(e)
                    pts.append((c, more))
        likes, adds = [], []
        monsters = 0
        for p, more in pts:
            s = nearest(p, sources)
            like = [s[0] + x0, s[1] + y0]
            if like not in likes:
                likes.append(like)
            row = [p[0] + x0, p[1] + y0, likes.index(like)]
            for e in more:
                row += [e[0] - p[0], e[1] - p[1]]
            adds.append(row)
            monsters += 1 + len(more)
            bucket[((p[0] + x0) // B, (p[1] + y0) // B, z)].append((p[0] + x0, p[1] + y0))
            for e in more:
                bucket[((e[0] + x0) // B, (e[1] + y0) // B, z)].append((e[0] + x0, e[1] + y0))
        ax, ay = xs + [a[0] for a in adds], ys + [a[1] for a in adds]
        areas.append(dict(level=level, z=z, box=[min(ax), min(ay), max(ax), max(ay)], entries=len(rows),
                          tiles=len(region), before=round(len(rows) * 100.0 / len(region), 2),
                          after=round((len(rows) + monsters) * 100.0 / len(region), 2), likes=likes, add=adds,
                          monsters=monsters))
    return areas, skipped


def render(areas, skipped, args):
    out = ['{',
           '  "_doc": "Written by tools/gen_spawn_density.py, read by tools/patch_base_spawns.py (install step spawns). '
           'One row per base-map hunt: id, floor, box [x0, y0, x1, y1], hunt level, entries, region tiles, density per '
           '100 tiles before / after, likes (the entries copied, [x, y] on the floor) and add ([x, y, index in likes, '
           'then dx, dy of each further monster of the spawn block]). server/README.md Spawn density and respawn, Fill '
           'and Pack combat (pace).",',
           '  "min": %s, "target": %s, "cap": %s, "maxAdd": %d, "block": %d, "spacing": %d,' % (
               args['min'], args['target'], args['cap'], args['max_add'], args.get('block', 1),
               args.get('spacing', SPACING)),
           '  "low": %s,' % json.dumps(args.get('low')),
           '  "skipped": %s,' % json.dumps(dict(sorted(skipped.items())), sort_keys=True),
           '  "areas": [']
    rows = []
    for i, a in enumerate(areas):
        rows.append('    {"id": "F%04d", "z": %d, "box": %s, "level": %d, "entries": %d, "tiles": %d, "before": %s, '
                    '"after": %s, "likes": %s, "add": %s}' % (
                        i + 1, a['z'], json.dumps(a['box']), a['level'], a['entries'], a['tiles'], a['before'],
                        a['after'], json.dumps(a['likes'], separators=(',', ':')),
                        json.dumps(a['add'], separators=(',', ':'))))
    out.append(',\n'.join(rows))
    out += ['  ]', '}', '']
    return '\n'.join(out)


# Pack combat (pace, 2026-10-14): from hunting level 30 (the audit's fair-hunt level 15, x2) every hunt under 4.3 per
# 100 region tiles is raised to 4.5, at most x2.5 its entries and +600 monsters, in spawn blocks of 3 whose centres are
# 5+ sqm apart. Hunts under it keep the earlier fill (3.25 -> 3.4, one-monster spawns): new players.
DEFAULTS = dict(min=4.3, target=4.5, cap=2.5, max_add=600, block=3, spacing=5, low=[15, 3.25, 3.4, 2.0, 400])


def main(argv):
    opts = dict(DEFAULTS)
    args, i, check, paths = [], 0, False, {}
    while i < len(argv):
        a = argv[i]
        if a in ('--map', '--out', '--stats', '--target', '--min', '--cap', '--max-add', '--block', '--spacing'):
            v = argv[i + 1]
            i += 1
            if a in ('--map', '--out', '--stats'):
                paths[a] = v
            elif a == '--max-add':
                opts['max_add'] = int(v)
            elif a in ('--block', '--spacing'):
                opts[a[2:]] = int(v)
            else:
                opts[a[2:]] = float(v)
        elif a == '--check':
            check = True
        else:
            args.append(a)
        i += 1
    if not 1 <= len(args) <= 2:
        print(__doc__)
        return 2
    data = args[0]
    otb = args[1] if len(args) > 1 else os.path.join(data, 'items', 'items.otb')
    sys.path.insert(0, os.path.join(HERE, '..', '..', 'tools', 'map'))
    import otbm
    from itemdb import ItemDB
    cfg = pbs.read(os.path.join(data, '..', 'config.lua'))
    name = pool.map_name(cfg)
    spawn_text = pbs.read(os.path.join(data, 'world', name + '-spawn.xml'))
    hunts, npcs, others = hunts_of(data, spawn_text)
    print('%d hunts' % len(hunts))
    db = ItemDB(otb, os.path.join(data, 'items', 'items.xml'))
    m = otbm.load_map(paths.get('--map') or os.path.join(data, 'world', name + '.otbm'))
    code = tile_codes(m, db)
    areas, skipped = plan(m, code, hunts, npcs, others, opts['min'], opts['target'], opts['cap'], opts['max_add'], log=print,
                          block=opts['block'], spacing=opts['spacing'], low=opts['low'])
    if paths.get('--stats'):
        with open(paths['--stats'], 'w', encoding='utf-8') as f:
            json.dump([dict([(k, v) for k, v in a.items() if k not in ('likes', 'add')], adds=a['monsters'])
                       for a in areas], f)
    areas = [a for a in areas if a['add']]
    text = render(areas, skipped, opts)
    out = paths.get('--out', DEFAULT_OUT)
    print('%d hunts filled, %d spawn blocks, %d monsters; skipped %s' % (
        len(areas), sum(len(a['add']) for a in areas), sum(a['monsters'] for a in areas), dict(skipped)))
    if check:
        same = os.path.isfile(out) and pbs.read(out) == text
        print('%s: %s' % (out, 'up to date' if same else 'differs'))
        return 0 if same else 1
    pbs.write(out, text)
    print('wrote', out)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
