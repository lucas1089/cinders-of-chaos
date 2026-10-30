#!/usr/bin/env python3
"""Spawn fills of the waystone maps, trim of the lobes of maps 9 and 12, Gloom Pillars thinned: writes tools/spawn_expand.json
(for patch_base_spawns.py) and tools/waystone_trim.json (for patch_waystone_trim.py). server/README.md "Spawn fills of the
waystone maps and the late game areas (O337)".

usage: python3 -I gen_spawn_expand.py DATA_DIR [--out PATH] [--trim PATH] [--check] [--quiet]

DATA_DIR is the data folder of an INSTALLED server (install_all.py, then this tool: the audit's view of the map, tools/audit_hunts.py).
The spawn file it reads is the one the `spawns` step wrote: blocks marked chaosadd="X..." (its own) are ignored and the entries its
`remove` list took out count as present, so a second run on the same data gives the same two files byte for byte (--check compares
instead of writing, exit 1 when they differ). The trim is read back through the map: a map that already has the blocking items is
measured with them off (tools/waystone_trim.json is applied again, not stacked).
What it does (limits of tools/audit_hunts.py, a little inside them):
  trim     waystone maps 9 and 12 above TRIM_SWEEP seconds of full sweep (the limit is 300): dead-end lobes behind a neck of at most
           NECK tiles, with no boss lever or entrance in them and at most MAX_LOBE_SPAWNS monsters, largest first, until the sweep is
           under TRIM_SWEEP; all or nothing (a map whose dead ends are too small to bring it under the limit is left whole: map 12, an
           open forest and desert whose lobes sit behind necks of 40 to 90 tiles, would need 300 tiles of fence for 4,700 tiles). The
           neck tiles get a solid decoration of the neighbourhood (waystone_trim.json); the monsters in the lobes are listed in `remove`
  fill     waystone maps 3, 5, 9, 11 and 12 under FILL_TO (3.15) monsters per 100 walkable tiles (sparse is under 3.0: the rift layout
           limit of 34 tiles per monster is 2.94): spawn blocks of three on the tiles farthest from every monster, at least SPACING
           sqm apart and from the next block, each copying the nearest monster of the tier (its monster and final spawntime)
  thin     Gloom Pillars (10 per 100, limit 6): entries taken out, those whose ground other monsters cover first, until it holds THIN_TO
           per 100; never a row of late_game_spawns.csv
Python 3 and numpy (the audit's readers)."""
import json
import math
import os
import sys
from collections import defaultdict, deque

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
ROOT = os.path.dirname(SERVER)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'map'))

import audit_hunts as A  # noqa: E402
import audit_waystone_maps as WM  # noqa: E402
import patch_base_spawns as pbs  # noqa: E402

OUT = os.path.join(HERE, 'spawn_expand.json')
TRIM_OUT = os.path.join(HERE, 'waystone_trim.json')
LATE_CSV = os.path.join(HERE, 'late_game_spawns.csv')
PREFIX = 'X'              # chaosadd marker of these blocks (spawn_density.json's are F...)
FILL_MAPS = (3, 5, 9, 11, 12)
TRIM_MAPS = (9, 12)
FILL_TO = 3.15            # waystone maps: monsters per 100 walkable tiles after the fill
TRIM_SWEEP = 296.0        # seconds: trim until the full sweep is under this (the audit's limit is 300)
NECK = 10                 # a lobe is behind at most this many tiles of its front
MAX_LOBE_SPAWNS = 40
SPACING = 4               # a new block is at least this far (Chebyshev) from every monster and every other new block
BLOCK = 3
BLOCK_R = 2
MAX_SPAWNTIME = 300
THIN_TO = 5.4             # Gloom Pillars: monsters per 100 tiles after the thinning
# solid decoration a neck may get: the bushes and plants of the jungle set, palms, stone walls (the map's own pieces)
BLOCKERS = tuple(range(4010, 4025)) + (2725, 3454, 3463)
FALLBACK_BLOCKER = 3454
STEPS8 = [(dx, dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy]


# ------------------------------------------------------------------------------------------------ the spawn file
def read_entries(spawn_text, taken_out=()):
    """[dict(x, y, z, name, st, late, added)] of the monsters of the spawn file without the blocks of this tool (chaosadd="X...");
    added: the block was added by another step (spawn_density.json's fill, the H4 / H5 adds), so patch_base_spawns.py can neither
    copy nor take out its entries by position. Entries of `taken_out` ([x, y, z] rows of the earlier spawn_expand.json) that the
    file shows as removed count as present"""
    out = []
    taken = {tuple(p) for p in taken_out}
    for blk in pbs.SPAWN_RE.finditer(spawn_text):
        head = blk.group(1)
        mark = pbs.attr(head, 'chaosadd') or ''
        if mark.startswith(PREFIX):
            continue
        c = (pbs.num(pbs.attr(head, 'centerx')), pbs.num(pbs.attr(head, 'centery')), pbs.num(pbs.attr(head, 'centerz')))
        body = blk.group(2)
        for tag in pbs.MON_RE.findall(pbs.COMMENT_RE.sub('', body)):
            x, y, z = pbs.entry_pos(c, tag)
            out.append(dict(x=x, y=y, z=z, name=pbs.attr(tag, 'name') or '', st=pbs.num(pbs.attr(tag, 'spawntime')),
                            late=pbs.attr(tag, 'lategame') is not None, added=bool(mark)))
        for m in pbs.REMOVED_RE.finditer(body):
            tag = m.group(1)
            x, y, z = pbs.entry_pos(c, tag)
            if (x, y, z) in taken:
                out.append(dict(x=x, y=y, z=z, name=pbs.attr(tag, 'name') or '', st=pbs.num(pbs.attr(tag, 'spawntime')),
                                late=pbs.attr(tag, 'lategame') is not None, added=False))
    return out


# ------------------------------------------------------------------------------------------------ fills (pure)
def far_blocks(cand, taken, n_blocks, spacing=SPACING):
    """up to n_blocks block centres among cand [(x, y)]: farthest-point choice, the tile with the largest Chebyshev distance to
    the nearest entry of `taken` or earlier block (at least `spacing`), ties by x then y. numpy"""
    import numpy as np
    if not cand or n_blocks <= 0:
        return []
    cx = np.array([c[0] for c in cand], np.int64)
    cy = np.array([c[1] for c in cand], np.int64)
    d = np.full(len(cand), 10 ** 6, np.int64)
    for (x, y) in taken:
        np.minimum(d, np.maximum(np.abs(cx - x), np.abs(cy - y)), out=d)
    order = np.lexsort((cy, cx))
    out = []
    for _ in range(n_blocks):
        k = int(np.argmax(d[order]))
        if d[order][k] < spacing:
            break
        i = int(order[k])
        out.append((int(cx[i]), int(cy[i])))
        np.minimum(d, np.maximum(np.abs(cx - cx[i]), np.abs(cy - cy[i])), out=d)
    return out


def extras(center, cand_set, used, k, radius=BLOCK_R):
    """up to k more tiles for a block at center: candidates within radius (Chebyshev) not used, nearest first, ties by x then y"""
    cx, cy = center
    near = []
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            p = (cx + dx, cy + dy)
            if (dx or dy) and p in cand_set and p not in used:
                near.append((max(abs(dx), abs(dy)), p[0], p[1]))
    near.sort()
    return [(x, y) for _d, x, y in near[:k]]


def fill_area(ident, z, box, region, entries, likes_src, n_new):
    """one fill area (the format of spawn_density.json): n_new monsters in blocks of three on the region tiles [(x, y)] farthest
    from every entry [(x, y)]; each block copies the nearest of likes_src [(x, y)]. Returns (area dict, monsters placed)"""
    centers = far_blocks(sorted(region), set(entries), int(math.ceil(n_new / float(BLOCK))))
    cand = set(region)
    used = set(entries) | set(centers)
    likes, like_idx, add, left = [], {}, [], n_new
    for c in centers:
        if left <= 0:
            break
        ex = extras(c, cand, used, min(BLOCK, left) - 1)
        used |= set(ex)
        src = min(likes_src, key=lambda q: (max(abs(q[0] - c[0]), abs(q[1] - c[1])), q[0], q[1]))
        if src not in like_idx:
            like_idx[src] = len(likes)
            likes.append([src[0], src[1]])
        row = [c[0], c[1], like_idx[src]]
        for (x, y) in ex:
            row += [x - c[0], y - c[1]]
        add.append(row)
        left -= 1 + len(ex)
    return dict(id=ident, z=z, box=list(box), likes=likes, add=add), n_new - max(0, left)


# ------------------------------------------------------------------------------------------------ trim (pure)
def bfs(graph, start):
    dist = {start: 0}
    dq = deque([start])
    while dq:
        p = dq.popleft()
        for dx, dy in STEPS8:
            q = (p[0] + dx, p[1] + dy, p[2])
            if q in graph and q not in dist:
                dist[q] = dist[p] + 1
                dq.append(q)
    return dist


def lobes(graph, start, protected, spawn_at, neck=NECK, max_spawns=MAX_LOBE_SPAWNS):
    """[dict(size, neck, tiles, spawns)] of the dead-end lobes of the walkable set `graph` (tiles (x, y, z), 8-neighbour moves) seen from
    `start`: the tiles farther than layer d that hang on a front of at most `neck` tiles of layer d, without a tile of `protected`
    (or next to one) and with at most max_spawns monsters (spawn_at {(x, y): n}). Nested lobes are all listed, largest first"""
    dist = bfs(graph, start)
    layers = defaultdict(list)
    for t, d in dist.items():
        layers[d].append(t)
    parent, size = {}, {}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    cands = []
    for d in range(max(layers), 0, -1):
        touch = defaultdict(set)
        for t in layers[d]:
            for dx, dy in STEPS8:
                q = (t[0] + dx, t[1] + dy, t[2])
                if q in parent:
                    touch[find(q)].add(t)
        for root, front in touch.items():
            if len(front) <= neck:
                cands.append((d, sorted(front), root))
        for t in layers[d]:
            parent[t] = t
            size[t] = 1
        for t in layers[d]:
            for dx, dy in STEPS8:
                q = (t[0] + dx, t[1] + dy, t[2])
                if q in parent and dist[q] >= d:
                    ra, rb = find(t), find(q)
                    if ra != rb:
                        parent[rb] = ra
    out = []
    near_prot = set()
    for p in protected:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                near_prot.add((p[0] + dx, p[1] + dy, p[2]))
    for d, front, rep in cands:
        stack = [rep]           # a tile of the lobe: the flood over the tiles farther than d gives exactly this lobe
        comp = {rep}
        while stack:
            p = stack.pop()
            for dx, dy in STEPS8:
                q = (p[0] + dx, p[1] + dy, p[2])
                if dist.get(q, -1) > d and q not in comp:
                    comp.add(q)
                    stack.append(q)
        if not comp or comp & near_prot:
            continue
        sp = sum(spawn_at.get((t[0], t[1]), 0) for t in comp)
        if sp > max_spawns:
            continue
        out.append(dict(size=len(comp), neck=front, tiles=comp, spawns=sp, layer=d))
    out.sort(key=lambda o: (-o['size'], o['layer'], o['neck'][0]))
    return out


def choose_lobes(found, need_tiles):
    """largest lobes first, none inside (or around) one already taken, until they hold need_tiles tiles; fewer when there are no
    more. Returns the lobes taken"""
    taken, covered, got = [], set(), 0
    for o in found:
        if got >= need_tiles:
            break
        if covered & o['tiles'] or covered & set(o['neck']):
            continue
        taken.append(o)
        covered |= o['tiles'] | set(o['neck'])
        got += o['size'] + len(o['neck'])
    return taken


# ------------------------------------------------------------------------------------------------ thinning (pure)
def thin(entries, tiles_of, level_cap, keep):
    """entries [(x, y, z)] of an area, tiles_of(entry) the region tiles the entry covers, keep the entries that may not go. Takes
    entries out, each time the one that uncovers the fewest tiles (ties: the most covered neighbourhood, then x, y, z), until
    monsters per 100 tiles of the rest is at most level_cap. Returns the entries taken out"""
    cover = defaultdict(int)
    for e in entries:
        for t in tiles_of(e):
            cover[t] += 1
    live = list(entries)
    out = []
    removable = [e for e in live if e not in keep]
    while removable and len(live) * 100.0 / max(1, len(cover)) > level_cap:
        best, key = None, None
        for e in removable:
            ts = tiles_of(e)
            k = (sum(1 for t in ts if cover[t] == 1), -sum(cover[t] for t in ts), e)
            if key is None or k < key:
                best, key = e, k
        for t in tiles_of(best):
            cover[t] -= 1
            if not cover[t]:
                del cover[t]
        live.remove(best)
        removable.remove(best)
        out.append(best)
    return out


# ------------------------------------------------------------------------------------------------ the installed map
def late_rows():
    import csv
    return {(int(r['centerx']) + int(r['x']), int(r['centery']) + int(r['y']), int(r['z']))
            for r in csv.DictReader(open(LATE_CSV, encoding='utf-8'))}


def blocker_near(m, kinds, front):
    """the solid decoration of the BLOCKERS the neighbourhood of a neck has most often (ties: lower id), else a stone wall"""
    from collections import Counter
    c = Counter()
    xs = sum(t[0] for t in front) // len(front)
    ys = sum(t[1] for t in front) // len(front)
    z = front[0][2]
    for y in range(ys - 8, ys + 9):
        for x in range(xs - 8, xs + 9):
            i = m.find(x, y, z)
            if i >= 0:
                for s in m.stack(i)[1:]:
                    if int(s) in BLOCKERS and int(s) in kinds.block:
                        c[int(s)] += 1
    return sorted(c.items(), key=lambda kv: (-kv[1], kv[0]))[0][0] if c else FALLBACK_BLOCKER


def waystone(data_dir, w, entries, trim_off, log):
    """(areas, remove, trim rows) for the waystone maps; trim_off: the tiles of the trim file already on the map (measured as open)"""
    import audit_hunt_transitions as AT  # noqa: F401
    ws = os.path.join(data_dir, 'scripts', 'customs', 'waystone_system')
    cfg_text = open(os.path.join(SERVER, 'data', 'scripts', 'chaos', 'waystone_tiers_config.lua'), encoding='utf-8').read()
    maps = WM.parse_tier_maps(open(os.path.join(ws, 'tier_maps.lua'), encoding='utf-8', errors='replace').read())
    names = WM.parse_config_monsters(cfg_text)
    clear = {(x, y, z) for x, y, z, _i in WM.parse_clear_path(cfg_text)}
    walk, spot, m, kinds = w['walk'], w['spot'], w['m'], w['kinds']
    open_walk = lambda p: (walk(p) or p in clear or p in trim_off)
    bdir = os.path.join(ws, 'waystone_bosses')
    bosses = []
    for f in sorted(os.listdir(bdir)):
        if f.startswith('boss_'):
            bosses.append(WM.parse_boss(open(os.path.join(bdir, f), encoding='utf-8', errors='replace').read()))
    areas, remove, trim_rows = [], [], []
    tuning = json.load(open(os.path.join(HERE, 'spawn_tuning.json'), encoding='utf-8'))
    # the entries that spawn_tuning.json's `add` rows copy (`like`) and its `move` rows move stay where they are
    needed = {tuple(ad['like']) for ad in tuning.get('add') or []} | {tuple(mv['at']) for mv in tuning.get('move') or []}
    for i, (tier, name, a, b, dest) in enumerate(maps):
        n = i + 1
        if n not in FILL_MAPS:
            continue
        z = a[2]
        box = (a[0], a[1], b[0], b[1], z, z)
        declared = {s.lower() for s in names[tier - 1]}
        inside = [e for e in entries if A.in_box((e['x'], e['y'], e['z']), box)]
        mine = [e for e in inside if e['name'].lower() in declared]
        graph = A.reach_all(open_walk, {}, dest, box)
        region = {t for t in graph if spot(t)}
        level = (A.WAYSTONE_BAND[0] + A.WAYSTONE_BAND[1]) // 2
        sweep = A.sweep_seconds(len(region), level)
        row = None
        out_mon = []
        if n in TRIM_MAPS and sweep > TRIM_SWEEP:
            prot = {tuple(p) for bs in bosses if a[0] <= bs['from'][0] <= b[0] and a[1] <= bs['from'][1] <= b[1] and bs['from'][2] == z
                    for p in bs['levers'] + [bs['entrance']]}
            spawn_at = defaultdict(int)
            for e in inside:
                spawn_at[(e['x'], e['y'])] += 1
            found = lobes(graph, tuple(dest), prot, spawn_at)
            need = len(region) - int(TRIM_SWEEP * A.SWEEP_WIDTH * A.tiles_per_second(level))
            took = choose_lobes(found, need)
            if sum(o['size'] for o in took) < need:
                log('waystone map %d: no trim, the dead ends behind necks of %d tiles or less hold %d of the %d tiles that would have to go'
                    % (n, NECK, sum(o['size'] for o in took), need))
                took = []
            blocked = set()
            items = []
            for o in took:
                item = blocker_near(m, kinds, o['neck'])
                for t in o['neck']:
                    items.append([t[0], t[1], t[2], item])
                blocked |= set(o['neck'])
                out_mon += [e for e in inside if (e['x'], e['y'], z) in o['tiles']]
            graph = A.reach_all(lambda p: open_walk(p) and p not in blocked, {}, dest, box)
            region = {t for t in graph if spot(t)}
            row = dict(map=n, items=sorted(items))
            if took:
                log('waystone map %d: trim %d lobe(s), %d neck tiles, %d monsters in them: %d -> %d tiles, sweep %.0f -> %.0f s' % (
                    n, len(took), len(items), len(out_mon), len(graph) + sum(o['size'] for o in took), len(graph), sweep, A.sweep_seconds(len(region), level)))
        cut = [e for e in mine if not any((e['x'] + dx, e['y'] + dy, z) in graph for dx in (-1, 0, 1) for dy in (-1, 0, 1))]
        for e in cut:
            if e not in out_mon:
                out_mon.append(e)
        for e in out_mon:
            if not e['added'] and (e['x'], e['y'], e['z']) not in needed:
                remove.append([e['x'], e['y'], e['z']])
        live = [e for e in mine if e not in out_mon]
        if row and row['items']:
            trim_rows.append(row)
        want = int(math.ceil(FILL_TO * len(region) / 100.0)) - len(live)
        log('waystone map %d (tier %d): %d monsters on %d tiles (%.2f per 100), %d to add' % (
            n, tier, len(live), len(region), 100.0 * len(live) / max(1, len(region)), max(0, want)))
        if want <= 0:
            continue
        cand = {(t[0], t[1]) for t in region if walk(t) and sum(1 for dx, dy in STEPS8 if (t[0] + dx, t[1] + dy, z) in region) >= 5}
        area, got = fill_area('XW%02d' % n, z, box, cand, [(e['x'], e['y']) for e in inside if e not in out_mon],
                              [(e['x'], e['y']) for e in live if 0 < e['st'] <= MAX_SPAWNTIME and not e['added']], want)
        log('  %d new monsters in %d blocks' % (got, len(area['add'])))
        areas.append(area)
    return areas, remove, trim_rows


def gloom(w, entries, level_of, log):
    """the entries of Gloom Pillars to take out"""
    walk, spot = w['walk'], w['spot']
    name, box = [x for x in A.LATE_AREAS if x[0] == 'Gloom Pillars'][0]
    inside = [e for e in entries if A.in_box((e['x'], e['y'], e['z']), box) and level_of(e['name']) > 0]
    ents = [(e['x'], e['y'], e['z']) for e in inside]
    tiles = A.region_tiles(ents, walk, spot)
    m = A.metrics(ents, tiles, 700)
    log('%s: %d monsters on %d tiles, %.1f per 100' % (name, m['monsters'], m['walkable'], m['per100']))
    if m['per100'] <= THIN_TO:
        return []
    r = A.REGION_R
    cache = {}

    def tiles_of(e):
        if e not in cache:
            cache[e] = [(e[0] + dx, e[1] + dy, e[2]) for dy in range(-r, r + 1) for dx in range(-r, r + 1)
                        if (e[0] + dx, e[1] + dy, e[2]) in tiles]
        return cache[e]
    keep = {(x, y, z) for (x, y, z) in late_rows()} | {(e['x'], e['y'], e['z']) for e in inside if e['late'] or e['added']}
    gone = thin(ents, tiles_of, THIN_TO, keep)
    left = [e for e in ents if e not in gone]
    t2 = A.region_tiles(left, walk, spot)
    log('  thinned: %d entries out, %d monsters on %d tiles (%.1f per 100)' % (len(gone), len(left), len(t2), 100.0 * len(left) / max(1, len(t2))))
    return [list(e) for e in gone]


# ------------------------------------------------------------------------------------------------ files
def render(doc):
    lines = ['{', ' "_doc": %s,' % json.dumps(doc['_doc']), ' "areas": [']
    lines.append(',\n'.join('  ' + json.dumps(a, separators=(',', ':')) for a in doc['areas']))
    lines += [' ],', ' "remove": [']
    lines.append(',\n'.join('  ' + json.dumps(r, separators=(',', ':')) for r in doc['remove']))
    lines += [' ]', '}']
    return '\n'.join(lines) + '\n'


def render_trim(doc):
    lines = ['{', ' "_doc": %s,' % json.dumps(doc['_doc']), ' "maps": [']
    maps = []
    for mp in doc['maps']:
        maps.append('  {"map": %d, "items": [\n%s\n  ]}' % (mp['map'], ',\n'.join('   ' + json.dumps(r, separators=(',', ':')) for r in mp['items'])))
    lines.append(',\n'.join(maps))
    lines += [' ]', '}']
    return '\n'.join(lines) + '\n'


def run(data_dir, out_path=OUT, trim_path=TRIM_OUT, check=False, log=print):
    import audit_hunt_transitions as AT
    w = A.build_world(data_dir, log=lambda *_: None)
    levels, _exps = AT.monster_tables(data_dir)
    level_of = lambda n: levels.get(n.lower(), 0)
    text = open(w['map_path'][:-5] + '-spawn.xml', encoding='latin-1').read()
    prev = json.load(open(out_path, encoding='utf-8')) if os.path.isfile(out_path) else {}
    trim_off = set()
    if os.path.isfile(trim_path):
        for mp in json.load(open(trim_path, encoding='utf-8'))['maps']:
            for x, y, z, _i in mp['items']:
                trim_off.add((x, y, z))
    entries = read_entries(text, prev.get('remove') or [])
    log('%d monster entries' % len(entries))
    # the trim file's items are on the map when this runs on an installed server: measure the map with them off
    base_walk = w['walk']
    w = dict(w, walk=lambda p: base_walk(p) or p in trim_off)
    areas, remove, trim_rows = waystone(data_dir, w, entries, trim_off, log)
    remove += gloom(w, entries, level_of, log)
    doc = dict(_doc=("Written by tools/gen_spawn_expand.py from the installed map, read by tools/patch_base_spawns.py (install step spawns) as a "
                     "second fill file: `areas` are the fill format of spawn_density.json (XW.. = a waystone map), `remove` the entries taken "
                     "out (the lobes of waystone maps 9 and 12 that waystone_trim.json closes, Gloom Pillars thinned). server/README.md "
                     "'Spawn fills of the waystone maps and the late game areas (O337)'."),
               areas=areas, remove=sorted(remove))
    tdoc = dict(_doc=("Written by tools/gen_spawn_expand.py, read by tools/patch_waystone_trim.py (install step waystonetrim): per waystone map the "
                      "tiles [x, y, z, item] that get a solid decoration, the necks in front of the dead-end lobes that make the map too big "
                      "to sweep in 300 s. server/README.md 'Spawn fills of the waystone maps and the late game areas (O337)'."),
                maps=sorted(trim_rows, key=lambda r: r['map']))
    body, tbody = render(doc), render_trim(tdoc)
    if check:
        bad = 0
        for path, new in ((out_path, body), (trim_path, tbody)):
            cur = open(path, encoding='utf-8').read() if os.path.isfile(path) else ''
            if cur != new:
                log('%s differs from what the map gives' % path)
                bad = 1
        return bad
    for path, new in ((out_path, body), (trim_path, tbody)):
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(new)
    log('wrote %s (%d areas, %d blocks, %d entries out) and %s (%d tiles)' % (
        out_path, len(areas), sum(len(a['add']) for a in areas), len(remove), trim_path, sum(len(r['items']) for r in trim_rows)))
    return 0


def main(argv):
    opts, pos, i = {}, [], 0
    while i < len(argv):
        a = argv[i]
        if a in ('--out', '--trim'):
            if i + 1 >= len(argv):
                print('%s needs a value' % a)
                return 1
            opts[a] = argv[i + 1]
            i += 1
        elif a in ('--check', '--quiet'):
            opts[a] = True
        elif a in ('-h', '--help'):
            print(__doc__)
            return 0
        elif a.startswith('-'):
            print('unknown option %s' % a)
            return 1
        else:
            pos.append(a)
        i += 1
    if len(pos) != 1:
        print(__doc__)
        return 1
    try:
        return run(pos[0], opts.get('--out', OUT), opts.get('--trim', TRIM_OUT), bool(opts.get('--check')),
                   (lambda *_: None) if opts.get('--quiet') else print)
    except (A.HuntAuditError, OSError) as e:
        print('refused: %s' % e)
        return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
