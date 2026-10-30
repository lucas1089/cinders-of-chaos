#!/usr/bin/env python3
"""Audit every hunt of the installed map: right monsters, density and size (server/README.md "Hunt audit (O337)").

usage: python3 -I server/tools/audit_hunts.py DATA_DIR [--kind base,planned,waystone,late,refs,data] [--md FILE] [--csv FILE]
                                              [--known FILE] [--suggest [--apply]] [--check] [--quiet]

Owner, 2026-10-30: "check again whether every hunt points to the right monsters, the monster density of those hunts and
their size". DATA_DIR is the data folder of an INSTALLED server (python3 -I tools/install_all.py SERVER_DIR first: the
planned hunts, the hall and the late game spawns are part of the map only after the install) with world/<map>.otbm and
-spawn.xml, items/items.otb + items.xml, monster/ and lib/chaos_hunt_places.lua. Not in CI (it needs the map, about
three minutes and 4 GB; tools/audit_hunts_test.py runs the same maths on synthetic data).
The hunts (one row each)
  base      the base server's hunts of tools/hall_hunts.csv (kind `hunt`) at the destination of their teleport. Right
            monsters: tools/audit_hunt_bands.py's view (known monsters walked to from the arrival, share inside the band,
            far outside it, the hunt's own monsters). Region: the walked tiles within REGION_R of those monsters
  planned   the generated hunts (tools/areaplan/plans/<id>.json placed at its origin, listed in data/lib/chaos_hunt_places.lua).
            Region: every walkable tile of the plan's box that is not a protection zone. Monsters: the spawn entries of the
            box
  waystone  the 12 waystone maps (data/scripts/customs/waystone_system/tier_maps.lua, the base copy of the install): the
            tier's five monsters against what spawns in the rectangle, hunting levels 468-612 (waystone_tiers_config.lua)
  late      the four late game areas (late_game_spawns.csv): every row of the CSV is on the map, the Chaos monsters against the
            area's other monsters, density and size of the ground round them
  refs      the places that name a hunt and its level: goals_config.lua `hunts` and the leveling guide against the plans
  data      the generated spawn tables the bestiary and the bounty board read (bestiary_spawns.lua, bounty_pool.lua) against the
            ones the installed map gives: a monster a hunt spawns must have its place in the bestiary and its contract
Per hunt
  right     `empty` / `few` / `spread` / `far` / `named` / `mixed` for a base hunt (audit_hunt_bands.py), `gate` (a stock portal in reach leads into far stronger monsters); for a planned
            one `missing` (a monster of the plan has no spawn in its box), `foreign` (a spawn in the box that is not the
            plan's: another hunt's monster or the base map's), `display` (the monster the sign shows does not spawn in
            the area), `arrival` (the arrival tile does not walk or is outside the box), `cut` (spawns or ground that no
            walk from the arrival reaches: dead pockets), `band` (the spawned monsters are not inside the plan's level
            band: under IN_SHARE inside it, or FAR_SHARE far outside)
  density   monsters per 100 walkable tiles, monsters per screen (15 x 11), tiles per monster. `sparse` under SPARSE,
            `packed` over PACKED per 100 or MAX_MEAN_SCREEN on average, `stacked` (STACK_MAX + 1 or more entries on one tile),
            `dead` (DEAD_SHARE of the ground has no monster on the screen of a player standing on it; the hunts whose whole ground is the region)
  size      walkable tiles of the region and the full sweep (tiles / SWEEP_WIDTH / the walking speed at the hunt's level,
            tools/rift_layout_model.lua's model). `small` under MIN_SWEEP seconds or MIN_REGION tiles or MIN_MONSTERS
            monsters, `big` over MAX_SWEEP seconds
--known FILE (default tools/hunt_audit_known.csv): defects the owner accepted or that need map editing (id, flag, reason).
--check exits 1 when a defect is not in it, and when a known one is gone (so the list shrinks).
Writes (deterministic, no dates): --md the table (docs/HUNT_AUDIT.md), --csv one row per hunt.
Exit 0 on success, 1 on a refusal or a failed --check. Python 3 and numpy (tools/map/otbm.py, itemdb.py).
"""
import csv
import math
import os
import re
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
ROOT = os.path.dirname(SERVER)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'map'))

import audit_hunt_bands as B  # noqa: E402
import audit_hunt_transitions as AT  # noqa: E402
import audit_waystone_maps as WM  # noqa: E402
import hall_order as HO  # noqa: E402

PLANS = os.path.join(HERE, 'areaplan', 'plans')
KNOWN = os.path.join(HERE, 'hunt_audit_known.csv')
DOC = os.path.join(ROOT, 'docs', 'HUNT_AUDIT.md')

# ---- limits. Each one is a number the repo already sets, named where it comes from
SCREEN = (15, 11)       # the client's view (area_plan_core.SCREEN)
SPARSE = 3.0            # monsters per 100 walkable tiles: gen_spawn_density.py's "hunts still under 3.0"
PACKED = 6.0            # area_plan_compile.py warns above 6 per 100 (the guide asks 1.5-5; base hunts run 4.0-5.0)
MAX_MEAN_SCREEN = 10.0  # PACKED x 165 tiles of a screen
STACK_MAX = 3           # a pack is up to 3 monsters; more on one tile are stacked
DEAD_SHARE = 0.35       # share of the ground that has no monster on the screen of a player standing on it
DEAD_MIN_WALK = 30      # a screen counts when it holds this many walkable tiles (area_plan_core.screen_density)
REGION_R = 6            # base hunt region: tiles within this of a monster (gen_spawn_density.REACH)
LINK_R = 12             # monsters this close on a floor are one hunt (content_audit.py, gen_spawn_density.py)
CLUSTER_CAP = 3000      # a hunt of the open land is cut here
SWEEP_WIDTH = 8         # tiles of width cleared per step of the full sweep (rift_layout_balance_config.lua)
MIN_SWEEP = 45          # seconds: a hunt swept faster is a closet
MAX_SWEEP = 300         # seconds: rift_layout_balance_config.lua sweepSecondsMax
MIN_REGION = 400        # walkable tiles: gen_spawn_density.POCKET
MIN_MONSTERS = 12       # monsters: audit_hunt_bands.SUGGEST_MIN
IN_SHARE = 0.6          # audit_hunt_bands.MIN_IN_SHARE
FAR_SHARE = 0.25        # audit_hunt_bands.FAR_SHARE
LATE_FIT = 2.0          # the Chaos monsters of a late game area within 2 x of the level of the area's other monsters
FOREIGN_SHARE = 0.05    # share of the box's monsters that may belong to no plan before `foreign`
WAYSTONE_BAND = (468, 612)   # waystone_tiers_config.lua: "hunting level 468-612" in every tier
KINDS = ('base', 'planned', 'waystone', 'late', 'refs', 'data')
FLAGS = ('empty', 'few', 'spread', 'far', 'named', 'mixed', 'missing', 'foreign', 'display', 'arrival', 'cut', 'band',
         'sparse', 'packed', 'stacked', 'dead', 'small', 'big', 'teleport', 'gate', 'ref', 'stale')

# the late game areas (server/README.md "Late game"): name, box (x1, y1, x2, y2, z1, z2)
LATE_AREAS = (
    ('Nightglass Core', (34185, 30999, 34306, 31111, 11, 14)),
    ('Jaded Roots', (34274, 31198, 34393, 31321, 9, 12)),
    ('Gloom Pillars', (34445, 31191, 34546, 31303, 9, 11)),
    ('Putrefactory', (33981, 31144, 34065, 31224, 11, 12)),
)


class HuntAuditError(Exception):
    pass


# ------------------------------------------------------------------------------------------------ pure maths
def tiles_per_second(level):
    """walking speed of a player of `level` in tiles a second (rift_core.lua R.tilesPerSecond: engine step formula)"""
    level = max(1, level or 1)
    speed = 270 + 2.5 * (min(level, 300) - 1) + max(0, level - 300)
    calc = max(1, math.floor(857.36 * math.log(speed / 2 + 261.29) - 4795.01 + 0.5))
    ms = math.ceil(1000 * 150 / calc / 10) * 10
    return 1000.0 / ms


def sweep_seconds(walkable, level):
    return walkable / float(SWEEP_WIDTH) / tiles_per_second(level)


def metrics(entries, tiles, level):
    """density and size of a region: entries [(x, y, z)] (one per monster), tiles the set of walkable (x, y, z).
    dict(monsters, walkable, per100, tpm, screen_mean, screen_max, screens, dead_share, stacked, stack_max, sweep)"""
    n, w = len(entries), len(tiles)
    out = dict(monsters=n, walkable=w, per100=(100.0 * n / w) if w else 0.0, tpm=(w / float(n)) if n else 0.0,
               screen_mean=0.0, screen_max=0, screens=0, dead_share=0.0, stacked=0, stack_max=0,
               sweep=sweep_seconds(w, level))
    if not w:
        return out
    stack = Counter(entries)
    out['stacked'] = sum(1 for c in stack.values() if c > STACK_MAX)
    out['stack_max'] = max(stack.values()) if stack else 0
    sw, sh = SCREEN
    x0, y0 = min(t[0] for t in tiles), min(t[1] for t in tiles)
    walk_in, mon_in = Counter(), Counter()
    for x, y, z in tiles:
        walk_in[(z, (x - x0) // sw, (y - y0) // sh)] += 1
    for x, y, z in entries:
        mon_in[(z, (x - x0) // sw, (y - y0) // sh)] += 1
    vals = [mon_in.get(k, 0) for k, c in walk_in.items() if c >= DEAD_MIN_WALK]
    if vals:
        out['screens'] = len(vals)
        out['screen_mean'] = sum(vals) / float(len(vals))
        out['screen_max'] = max(vals)
    # dead ground: a tile with no monster on the screen of a player standing on it (7 tiles each side, 5 up and down)
    vx, vy = sw // 2, sh // 2
    seen = set()
    for x, y, z in set(entries):
        for dy in range(-vy, vy + 1):
            for dx in range(-vx, vx + 1):
                seen.add((x + dx, y + dy, z))
    out['dead_share'] = sum(1 for t in tiles if t not in seen) / float(w)
    return out


def density_flags(m, dead=False):
    f = []
    if m['monsters'] and m['per100'] < SPARSE:
        f.append('sparse')
    if m['per100'] > PACKED or m['screen_mean'] > MAX_MEAN_SCREEN:
        f.append('packed')
    if m['stacked']:
        f.append('stacked')
    if dead and m['dead_share'] >= DEAD_SHARE:
        f.append('dead')
    return f


def size_flags(m, big=True):
    """`small` / `big`; big=False for the base hunts, whose region is a cluster of neighbouring caves (a big one is no defect)"""
    f = []
    if m['walkable'] < MIN_REGION or m['sweep'] < MIN_SWEEP or m['monsters'] < MIN_MONSTERS:
        f.append('small')
    if big and m['sweep'] > MAX_SWEEP:
        f.append('big')
    return f


def band_fit(levels, lo, hi):
    """(in_share, far_share, median) of the monster levels against a band"""
    lv = [v for v in levels if v > 0]
    if not lv:
        return 0.0, 0.0, 0
    s = sorted(lv)
    return (sum(1 for v in lv if B.inside(v, lo, hi)) / float(len(lv)),
            sum(1 for v in lv if B.far_outside(v, lo, hi)) / float(len(lv)), s[len(s) // 2])


def region_tiles(entries, walk, spot, allowed=None, r=REGION_R):
    """walkable tiles (spot true: no protection zone or house) within r of an entry, inside `allowed` when given"""
    out, seen = set(), set()
    for (x, y, z) in set(entries):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                p = (x + dx, y + dy, z)
                if p in seen:
                    continue
                seen.add(p)
                if (allowed is None or p in allowed) and walk(p) and spot(p):
                    out.add(p)
    return out


def reach_all(walk, trans_at, start, box):
    """tiles reachable on foot from start inside box = (x1, y1, x2, y2, z1, z2), taking the floor changes and teleports
    of trans_at ({pos: [dict(land)]}) the way a player does"""
    x1, y1, x2, y2, z1, z2 = box
    if not walk(start):
        return set()
    seen = {start}
    stack = [start]
    steps = [(dx, dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy]
    while stack:
        x, y, z = stack.pop()
        for dx, dy in steps:
            n = (x + dx, y + dy, z)
            if n in seen or not (x1 <= n[0] <= x2 and y1 <= n[1] <= y2):
                continue
            if walk(n):
                seen.add(n)
                stack.append(n)
            for t in trans_at.get(n, ()):
                land = t['land']
                if land not in seen and z1 <= land[2] <= z2 and x1 <= land[0] <= x2 and y1 <= land[1] <= y2:
                    seen.add(land)
                    stack.append(land)
    return seen


# ------------------------------------------------------------------------------------------------ readers
def parse_spawn_entries(text):
    """[dict(x, y, z, name, content, hunt)] of every monster of a spawn file; content / hunt: the block's chaoscontent /
    chaoshunt mark ('' without)"""
    out = []
    for m in HO.SPAWN_RE.finditer(text):
        head, body = m.group(1), m.group(2)
        try:
            cx, cy, cz = (int(re.search(r'\b%s="(-?\d+)"' % k, head).group(1)) for k in ('centerx', 'centery', 'centerz'))
        except AttributeError:
            continue
        content = re.search(r'chaoscontent="([^"]*)"', head)
        hunt = re.search(r'chaoshunt="([^"]*)"', head)
        for t in re.finditer(r'<monster\b[^>]*>', body):
            tag = t.group(0)
            nm = re.search(r'\bname="([^"]+)"', tag)
            if not nm:
                continue
            g = lambda k: re.search(r'\b%s="(-?\d+)"' % k, tag)
            out.append(dict(x=cx + (int(g('x').group(1)) if g('x') else 0), y=cy + (int(g('y').group(1)) if g('y') else 0),
                            z=int(g('z').group(1)) if g('z') else cz, name=nm.group(1),
                            content=content.group(1) if content else '', hunt=hunt.group(1) if hunt else ''))
    return out


def _pos(text):
    m = re.search(r'x = (\d+), y = (\d+), z = (\d+)', text or '')
    return tuple(int(v) for v in m.groups()) if m else None


def _name(row):
    m = re.search(r'name = "((?:[^"\\]|\\.)*)"', row)
    return m.group(1) if m else ''


def parse_places(text):
    """data/lib/chaos_hunt_places.lua -> dict(places=[dict(id, name, level, teleport, arrival, exit, monster)],
    base=[dict(id, name, level, teleport, dest)])"""
    out = dict(places=[], base=[])
    sec = re.search(r'places = \{(.*?)\n\t\},', text, re.S)
    for row in re.findall(r'^\t\t\{(.*)\},$', sec.group(1) if sec else '', re.M):
        g = lambda k: re.search(r'\b%s = (\{[^}]*\}|"(?:[^"\\]|\\.)*"|nil)' % k, row)
        lv = re.search(r'level = \{(\d+), (\d+)\}', row)
        mon = g('monster')
        out['places'].append(dict(
            id=re.search(r'id = "([^"]+)"', row).group(1), name=_name(row),
            level=(int(lv.group(1)), int(lv.group(2))) if lv else None,
            teleport=_pos(g('teleport').group(1)) if g('teleport') else None,
            arrival=_pos(g('arrival').group(1)) if g('arrival') else None,
            exit=_pos(g('exit').group(1)) if g('exit') else None,
            monster=mon.group(1).strip('"') if mon and mon.group(1) != 'nil' else ''))
    sec = re.search(r'base = \{(.*?)\n\t\},', text, re.S)
    for row in re.findall(r'^\t\t\{(.*)\},$', sec.group(1) if sec else '', re.M):
        g = lambda k: re.search(r'\b%s = (\{[^}]*\})' % k, row)
        lv = re.search(r'level = \{(\d+), (\d+)\}', row)
        out['base'].append(dict(id=re.search(r'id = "([^"]+)"', row).group(1),
                                name=_name(row),
                                level=(int(lv.group(1)), int(lv.group(2))) if lv else None,
                                teleport=_pos(g('teleport').group(1)) if g('teleport') else None,
                                dest=_pos(g('dest').group(1)) if g('dest') else None))
    return out


def read_plans(plans_dir=PLANS):
    """{id: plan dict} of the planned hunts' JSON files"""
    import json
    out = {}
    if os.path.isdir(plans_dir):
        for fn in sorted(os.listdir(plans_dir)):
            if fn.endswith('.json'):
                p = json.load(open(os.path.join(plans_dir, fn), encoding='utf-8'))
                out[p['id']] = p
    return out


def plan_box(plan):
    """(x1, y1, x2, y2, z1, z2) of a plan placed at its origin"""
    o, (w, h) = plan['origin'], plan['size']
    return (o['x'], o['y'], o['x'] + w - 1, o['y'] + h - 1, o['z'], o['z'] + plan.get('floors', 1) - 1)


def in_box(p, box):
    return box[0] <= p[0] <= box[2] and box[1] <= p[1] <= box[3] and box[4] <= p[2] <= box[5]


# ------------------------------------------------------------------------------------------------ the audits
def audit_planned(plan, place, entries, level_of, walk, spot, trans_at, stand_in=False):
    """one planned hunt. entries: spawn entry dicts inside its box (spawn_entries_in); level_of(name) -> hunting level (0
    unknown). Returns the row dict(kind, id, name, band, flags, ...)"""
    box = plan_box(plan)
    lo, hi = plan['level']
    mine = [e for e in entries if e['content'] == plan['id']]
    declared = {s['monster'] for s in plan.get('spawns', ())}
    if plan.get('boss'):
        b = plan['boss']
        declared.add(b['monster'] if isinstance(b, dict) else b)
    present = {e['name'] for e in entries if e['hunt'] != plan['id']}      # display monsters are not part of the hunt
    show = [e for e in entries if e['hunt'] != plan['id']]
    own = [e for e in show if e['content'] == plan['id'] or e['name'] in declared]
    flags = []
    detail = []
    # the tiles of the hunt: walkable, no protection zone
    xs = range(box[0], box[2] + 1)
    ys = range(box[1], box[3] + 1)
    tiles = {(x, y, z) for z in range(box[4], box[5] + 1) for y in ys for x in xs if walk((x, y, z)) and spot((x, y, z))}
    got = {e['name'] for e in own}
    gone = sorted(declared - got)
    if gone:
        flags.append('missing')
        detail.append('no spawn of ' + ', '.join(gone))
    foreign = [e for e in show if e['content'] != plan['id'] and e['name'] not in declared]
    if foreign and len(foreign) > FOREIGN_SHARE * max(1, len(show)):
        flags.append('foreign')
        c = Counter(e['name'] for e in foreign)
        detail.append('%d foreign: ' % len(foreign) + ', '.join('%s x%d' % kv for kv in c.most_common(4)))
    if place and place.get('monster') and not stand_in and place['monster'] not in {e['name'] for e in show}:
        flags.append('display')
        detail.append('sign shows %s' % place['monster'])
    arrival = place.get('arrival') if place else None
    reach = set()
    if not place or not arrival or not in_box(arrival, box) or not walk(arrival):
        flags.append('arrival')
        detail.append('arrival %s' % (arrival,))
    else:
        reach = reach_all(walk, trans_at, arrival, box)
        cut_mon = [e for e in show if not any((e['x'] + dx, e['y'] + dy, e['z']) in reach for dx in (-1, 0, 1) for dy in (-1, 0, 1))]
        cut_ground = len(tiles - reach)
        if len(cut_mon) > 0.05 * max(1, len(show)) or cut_ground > 0.1 * max(1, len(tiles)):
            flags.append('cut')
            detail.append('%d monster(s) and %d ground tiles not reached from the arrival' % (len(cut_mon), cut_ground))
    levels = [level_of(e['name']) for e in own]
    in_share, far_share, med = band_fit(levels, lo, hi)
    if levels and (in_share < IN_SHARE or far_share >= FAR_SHARE):
        flags.append('band')
        detail.append('%.0f%% inside %d-%d, %.0f%% far, median %d' % (100 * in_share, lo, hi, 100 * far_share, med))
    if place and place.get('level') and tuple(place['level']) != (lo, hi):
        flags.append('band')
        detail.append('places file says %s' % (place['level'],))
    m = metrics([(e['x'], e['y'], e['z']) for e in show], tiles, (lo + hi) // 2)
    flags += density_flags(m, dead=True) + size_flags(m)
    return dict(kind='planned', id=plan['id'], name=plan['name'], lo=lo, hi=hi, level=(lo + hi) // 2, flags=flags,
                detail='; '.join(detail), in_share=in_share, far_share=far_share, median=med, m=m,
                own=len(own), floors=plan.get('floors', 1))


def hunt_cluster(spawns, seeds, link=LINK_R, cap=CLUSTER_CAP):
    """[index] of the known monsters of the hunt the monsters `seeds` (indices) belong to: the spawns on one floor at
    most `link` tiles apart (tools/content_audit.py and gen_spawn_density.py group hunts the same way), at most `cap`"""
    np = spawns.np
    known = np.flatnonzero(spawns.level > 0)
    grid = defaultdict(list)
    for i in known:
        grid[(int(spawns.x[i]) // link, int(spawns.y[i]) // link, int(spawns.z[i]))].append(int(i))
    seen = {int(i) for i in seeds}
    todo = list(seen)
    while todo and len(seen) < cap:
        i = todo.pop()
        x, y, z = int(spawns.x[i]), int(spawns.y[i]), int(spawns.z[i])
        for gx in (x // link - 1, x // link, x // link + 1):
            for gy in (y // link - 1, y // link, y // link + 1):
                for j in grid.get((gx, gy, z), ()):
                    if j not in seen and abs(int(spawns.x[j]) - x) <= link and abs(int(spawns.y[j]) - y) <= link:
                        seen.add(j)
                        todo.append(j)
    return sorted(seen)


def coords(spawns, idx):
    return [(int(spawns.x[i]), int(spawns.y[i]), int(spawns.z[i])) for i in idx]


def audit_base(rows_b, spawns, walk, spot, places_base, trans_at, display_of=None, level_of=None):
    """base hunts: rows_b are audit_hunt_bands.audit rows. The right-monster flags are the band audit's (the monsters
    walked to within 20 tiles of the arrival); density and size are those of the whole hunt (hunt_cluster) on the
    ground within REGION_R of its monsters. The teleport check compares the map's teleport (trans_at) with the places
    file's destination"""
    out = []
    np = spawns.np
    byid = {p['id']: p for p in places_base}
    for r in rows_b:
        h, st = r['hunt'], r['stats']
        arrival = h['dest']
        flags = list(r['flags'])
        detail = []
        members = hunt_cluster(spawns, st['idx'])
        ents = coords(spawns, members)
        tiles = region_tiles(ents, walk, spot)
        m = metrics(ents, tiles, h['level'])
        flags += density_flags(m) + size_flags(m, big=False)
        if r['info']:
            detail.append('thin: arrival at a cave mouth')
        shown = {spawns.names[int(spawns.n[i])].lower() for i in members}
        sign = [x for x in ((display_of or {}).get(h['id']), h['name']) if x]
        if sign and not any(x.lower() in shown for x in sign):
            flags.append('display')
            detail.append('the sign shows %s, which does not spawn in the hunt' % sign[0])
        elif sign and level_of and level_of(sign[0]) and not B.inside(level_of(sign[0]), h['lo'], h['hi']):
            flags.append('band')
            detail.append('%s is a level %d monster, the sign says %d-%d' % (sign[0], level_of(sign[0]), h['lo'], h['hi']))
        pl = byid.get(h['id'])
        if pl and pl.get('teleport') and pl.get('dest'):
            ts = trans_at.get(pl['teleport'], [])
            if ts and ts[0]['land'] != pl['dest']:
                flags.append('teleport')
                detail.append('the map teleport leads to %s, the hunt is at %s' % (ts[0]['land'], pl['dest']))
        if not walk(arrival):
            flags.append('arrival')
            detail.append('arrival does not walk')
        gates = sum(1 for p in r['portals'] if p['verdict'] == 'gate')
        if gates:
            flags.append('gate')
            detail.append('%d stock portal(s) in reach lead into far stronger monsters (tools/hunt_gates.csv)' % gates)
        out.append(dict(kind='base', id=h['id'], name=h['name'], lo=h['lo'], hi=h['hi'], level=h['level'], flags=flags,
                        detail='; '.join(detail), in_share=st['in_share'], far_share=st['far_share'], median=st['median'],
                        m=m, own=st['named'], pass_=st['pass'], arrival=arrival,
                        gates=gates))
    return out


SUGGEST_FLAGS = ('display', 'sparse', 'small', 'packed', 'empty', 'few', 'spread', 'far', 'named')


def suggest_base(spawns, hunt, sign, walk, spot, trans_at, others, ctx=None, limit=3):
    """[dict(arrival, stats, band, at, cluster)] up to `limit` arrivals for a base hunt whose sign names `sign` (the names
    of the sign's monster, the CSV's name and display): the hunt of that monster whose band fits the monster's own level and
    that is not sparse, small or packed (density_flags, size_flags), with at least MIN_NAMED of the sign's monsters in view
    of the arrival and a view audit_hunt_bands.py finds clean (no stock portal into far stronger monsters when ctx is
    given), not within APART tiles of another hunt's arrival. Best first: median level nearest the level of the sign's monster, then
    the sign's monsters in view, then the size"""
    np = spawns.np
    names = {n.lower() for n in sign if n}
    # the band is the level of the sign's own monster (an arrival moved for its band, O333, left Behemoth (level 80) at 20-30)
    own_levels = [int(spawns.level[i]) for i in np.flatnonzero(spawns.level > 0) if spawns.names[int(spawns.n[i])].lower() in names]
    centre = sorted(own_levels)[len(own_levels) // 2] if own_levels else hunt['level']
    hunt = dict(hunt, level=centre, lo=0, hi=10 ** 6)
    lo, hi = B.tight_band(hunt)
    cand = [int(i) for i in np.flatnonzero(spawns.level > 0)
            if spawns.names[int(spawns.n[i])].lower() in names and B.inside(int(spawns.level[i]), lo, hi)]
    candset = set(cand)
    done, scored = set(), []
    for i in cand:
        if i in done:
            continue
        members = hunt_cluster(spawns, [i])
        done.update(members)
        if len(members) < MIN_MONSTERS:
            continue
        ents = coords(spawns, members)
        m = metrics(ents, region_tiles(ents, walk, spot), hunt['level'])
        if density_flags(m) or size_flags(m, big=False):
            continue
        mine = [j for j in members if j in candset]
        scored.append((members, mine, m))
    own = sorted(names)
    out, used = [], []
    for members, mine, m in scored:
        best = None
        for j in mine[:60]:
            x, y, z = int(spawns.x[j]), int(spawns.y[j]), int(spawns.z[j])
            if any(o[2] == z and max(abs(o[0] - x), abs(o[1] - y)) < B.APART for o in others):
                continue
            if any(u[2] == z and max(abs(u[0] - x), abs(u[1] - y)) < B.APART for u in used):
                continue
            a = B.arrival_tile(walk, spot, spawns, (x, y, z))
            if a is None:
                continue
            tiles = B.reach(walk, a)
            view = B.area_view(spawns, a, lo, hi, own, tiles)
            if B.area_flags(view, len(own), lo, hi)[0] or view['pass'] != 'here' or view['named'] < B.MIN_NAMED:
                continue
            loc = coords(spawns, view['idx'])
            if density_flags(metrics(loc, region_tiles(loc, walk, spot), centre)):
                continue       # the hunt as a whole is fine but the part round the arrival is sparse or packed
            if ctx is not None and any(ctx(t, a, lo, hi) == 'gate' for t in B.portals_in_reach(tiles, trans_at)):
                continue
            key = (round(abs(view['median'] - hunt['level']) / float(max(hunt['level'], 1)), 1), -min(view['named'], 12), -view['count'])
            if best is None or key < best[0]:
                best = (key, a, view, tiles)
        if best is None:
            continue
        _k, a, view, tiles = best
        bd = spawns.band(view['idx'])
        # the sign's band stays within level / 1.5 .. level x 1.5 of the monster in view (the hall's rule: under 3 x wide)
        band = (max(bd[0], lo), min(bd[1], hi), max(lo, min(hi, bd[2])))
        out.append(dict(key=best[0] + (m['monsters'],), arrival=a, stats=view, band=band, top=bd[3],
                        at=B.return_tile(walk, spot, tiles, a), cluster=m))
        used.append(a)
    out.sort(key=lambda c: (c['key'], c['arrival']))
    return out[:limit]


def audit_box_area(name, kind, box, band, declared, entries, level_of, walk, spot, ident=None, start=None, dead=True):
    """a waystone map or a late game area: the spawn entries of a rectangle (z1..z2) and its ground. The ground is every
    walkable non-protection tile of the rectangle, or with `start` (the arrival) the tiles walked to from it (the part a
    group can use; a pocket nobody reaches is not size). declared: the monsters that belong there (a spawn of any other is
    foreign); band (lo, hi) of their hunting level"""
    x1, y1, x2, y2, z1, z2 = box
    if start is not None:
        tiles = {t for t in reach_all(walk, {}, start, box) if spot(t)}
    else:
        tiles = {(x, y, z) for z in range(z1, z2 + 1) for y in range(y1, y2 + 1) for x in range(x1, x2 + 1)
                 if walk((x, y, z)) and spot((x, y, z))}
    show = [e for e in entries if in_box((e['x'], e['y'], e['z']), box)]
    flags, detail = [], []
    names = Counter(e['name'] for e in show)
    if declared:
        gone = sorted(n for n in declared if not names.get(n))
        if len(gone) > 1:
            flags.append('missing')
            detail.append('no spawn of ' + ', '.join(gone))
        foreign = [e for e in show if e['name'] not in declared]
        if foreign and len(foreign) > FOREIGN_SHARE * max(1, len(show)):
            flags.append('foreign')
            detail.append('%d foreign: ' % len(foreign) + ', '.join('%s x%d' % kv for kv in Counter(e['name'] for e in foreign).most_common(4)))
    lo, hi = band
    own = [e for e in show if not declared or e['name'] in declared]
    levels = [level_of(e['name']) for e in own]
    in_share, far_share, med = band_fit(levels, lo, hi)
    if levels and (in_share < IN_SHARE or far_share >= FAR_SHARE):
        flags.append('band')
        detail.append('%.0f%% inside %d-%d, %.0f%% far, median %d' % (100 * in_share, lo, hi, 100 * far_share, med))
    if start is not None:
        cut = [e for e in show if not any((e['x'] + dx, e['y'] + dy, e['z']) in tiles for dx in (-1, 0, 1) for dy in (-1, 0, 1))]
        if len(cut) > 0.05 * max(1, len(show)):
            flags.append('cut')
            detail.append('%d of %d spawns not reached from the arrival' % (len(cut), len(show)))
    m = metrics([(e['x'], e['y'], e['z']) for e in show], tiles, (lo + hi) // 2)
    flags += density_flags(m, dead=dead) + size_flags(m)
    return dict(kind=kind, id=ident or name, name=name, lo=lo, hi=hi, level=(lo + hi) // 2, flags=flags,
                detail='; '.join(detail), in_share=in_share, far_share=far_share, median=med, m=m, own=len(own), floors=z2 - z1 + 1)


def audit_late(name, box, rows, entries, level_of, walk, spot, ident=None):
    """a late game area: rows are the late_game_spawns.csv rows of the area (dict(x, y, z, monster) absolute). `missing`: a
    row whose monster is not at its place in the spawn file; `band`: the Chaos monsters' median level is out of
    LATE_FIT x the median of the area's other monsters; density and size over the ground within REGION_R of its monsters"""
    show = [e for e in entries if in_box((e['x'], e['y'], e['z']), box)]
    at = {(e['x'], e['y'], e['z'], e['name'].lower()) for e in show}
    flags, detail = [], []
    gone = [r for r in rows if (r['x'], r['y'], r['z'], r['monster'].lower()) not in at]
    if gone:
        flags.append('missing')
        detail.append('%d of %d late game spawns are not on the map (first %s at %s)' % (
            len(gone), len(rows), gone[0]['monster'], (gone[0]['x'], gone[0]['y'], gone[0]['z'])))
    new = {r['monster'].lower() for r in rows}
    lv_new = sorted(v for v in (level_of(e['name']) for e in show if e['name'].lower() in new) if v > 0)
    lv_old = sorted(v for v in (level_of(e['name']) for e in show if e['name'].lower() not in new) if v > 0)
    med_new = lv_new[len(lv_new) // 2] if lv_new else 0
    med_old = lv_old[len(lv_old) // 2] if lv_old else 0
    lo, hi = (int(med_old / LATE_FIT), int(med_old * LATE_FIT)) if med_old else (0, 0)
    if med_new and med_old and not lo <= med_new <= hi:
        flags.append('band')
        detail.append('late game monsters median %d, the rest of the area %d' % (med_new, med_old))
    ents = [(e['x'], e['y'], e['z']) for e in show if level_of(e['name']) > 0]
    tiles = region_tiles(ents, walk, spot)
    m = metrics(ents, tiles, max(med_new, med_old, 1))
    flags += density_flags(m) + size_flags(m, big=False)
    in_share, far_share, med = band_fit([level_of(e['name']) for e in show], lo, hi) if hi else (0.0, 0.0, 0)
    return dict(kind='late', id=ident or name, name=name, lo=lo, hi=hi, level=max(med_new, med_old), flags=flags,
                detail='; '.join(detail), in_share=in_share, far_share=far_share, median=med_new, m=m, own=len(rows),
                floors=box[5] - box[4] + 1)


def pool_entries(text):
    """{lower name: spawns} of a generated spawn table: bounty_pool.lua rows `{name = "X", ... spawns = N` or
    bestiary_spawns.lua rows `["x"] = {spawns = N`"""
    out = {}
    for n, c in re.findall(r'\{name = "((?:[^"\\]|\\.)*)",[^}]*?spawns = (\d+)', text):
        out[n.lower()] = int(c)
    for n, c in re.findall(r'^\t\["((?:[^"\\]|\\.)*)"\] = \{spawns = (\d+)', text, re.M):
        out[n] = int(c)
    return out


def audit_generated(ident, committed, fresh):
    """the committed generated spawn table (bestiary_spawns.lua, bounty_pool.lua) against the one the installed map gives.
    A row for the table when they differ: monsters the map spawns that the table does not know (no place in the bestiary,
    no contract), monsters it lists that no longer spawn, and counts that differ"""
    if committed == fresh:
        return None
    old, new = pool_entries(committed), pool_entries(fresh)
    missing = sorted(set(new) - set(old))
    gone = sorted(set(old) - set(new))
    moved = sorted(k for k in set(old) & set(new) if old[k] != new[k])
    detail = '%d monsters of the map are not in the file%s; %d listed ones do not spawn; %d counts differ' % (
        len(missing), (' (' + ', '.join(missing[:4]) + (', ...' if len(missing) > 4 else '') + ')') if missing else '', len(gone), len(moved))
    return dict(kind='data', id=ident, name=ident, flags=['stale'], detail=detail, level=0, lo=0, hi=0, in_share=0.0, far_share=0.0,
                median=0, m=None, own=0, floors=0)


def audit_refs(plans, goals, guide_text, places):
    """the places that name a plan's level band: goals_config.lua hunts {id: (lo, hi)} and the leveling guide's 'Name (lo-hi)'
    list; both must say what the plan says. Returns rows for the mismatches only"""
    rows = []
    for pid, (lo, hi) in sorted(goals.items()):
        p = plans.get(pid)
        if not p:
            rows.append(dict(kind='refs', id=pid, flags=['ref'], detail='goals_config.lua names a hunt with no plan'))
        elif tuple(p['level']) != (lo, hi):
            rows.append(dict(kind='refs', id=pid, flags=['ref'], detail='goals_config.lua says %d-%d, the plan %d-%d' % (lo, hi, p['level'][0], p['level'][1])))
    names = {p['name']: p for p in plans.values()}
    for name, lo, hi in re.findall(r'([A-Z][A-Za-z\' ]+?) \((\d+)-(\d+)\)', guide_text or ''):
        p = names.get(name.strip())
        if p and tuple(p['level']) != (int(lo), int(hi)):
            rows.append(dict(kind='refs', id=p['id'], flags=['ref'], detail='the leveling guide says %s (%s-%s), the plan %d-%d' % (name, lo, hi, p['level'][0], p['level'][1])))
    return rows


# ------------------------------------------------------------------------------------------------ known list, output
def read_known(path=KNOWN):
    """{(id, flag): reason} of the accepted defects file"""
    out = {}
    if os.path.isfile(path):
        for row in csv.DictReader(l for l in open(path, encoding='utf-8') if not l.startswith('#')):
            out[(row['id'], row['flag'])] = row['reason']
    return out


def check_rows(rows, known):
    """(new defects [(id, flag)], stale known entries [(id, flag)])"""
    seen = {(r['id'], f) for r in rows for f in r['flags']}
    return sorted(seen - set(known)), sorted(set(known) - seen)


def fmt_m(m):
    return '%d | %d | %.1f | %.1f | %.1f | %d | %.0f%% | %d' % (m['monsters'], m['walkable'], m['per100'], m['screen_mean'],
                                                                 m['tpm'], m['screen_max'], 100 * m['dead_share'], m['sweep'])


def clean(s):
    return str(s).replace('|', '/')


def render_md(rows, known):
    n = Counter()
    for r in rows:
        n[r['kind']] += 1
    flagged = [r for r in rows if r['flags']]
    out = ['# Hunt audit (O337)', '',
           'Owner, 2026-10-30: check again whether every hunt points to the right monsters, the monster density of the hunts',
           'and their size. Made by `server/tools/audit_hunts.py` on an installed server (not run in CI, it needs the map).',
           'Limits and the rules are in the tool\'s header and in `server/README.md` "Hunt audit (O337)".', '',
           '## Totals', '',
           '%s. %d hunts with a defect (%d of them accepted in `tools/hunt_audit_known.csv`).' % (
               ', '.join('%d %s' % (v, k) for k, v in sorted(n.items())), len(flagged),
               sum(1 for r in flagged if all((r['id'], f) in known for f in r['flags']))), '',
           'Columns: Mon = monsters (spawn entries), Walk = walkable tiles of the region, /100 = monsters per 100 walkable tiles,',
           '/screen = mean monsters per 15 x 11 screen, T/mon = walkable tiles per monster, Peak = most monsters on one screen,',
           'Dead = ground with no monster on the screen of a player standing there, Sweep = full sweep seconds at the hunt\'s level.', '']
    for kind, title in (('base', 'Base hunts'), ('planned', 'Planned hunts'), ('waystone', 'Waystone maps'), ('late', 'Late game areas')):
        sub = [r for r in rows if r['kind'] == kind]
        if not sub:
            continue
        out += ['## ' + title, '', '| Hunt (level) | Band | In band | Far | Median | Mon | Walk | /100 | /screen | T/mon | Peak | Dead | Sweep | Flags |',
                '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|']
        for r in sorted(sub, key=lambda r: (r['level'], r['id'])):
            fl = ', '.join(('%s*' % f if (r['id'], f) in known else f) for f in r['flags']) or 'ok'
            out.append('| %s (%d) | %d-%d | %.0f%% | %.0f%% | %d | %s | %s |' % (
                clean(r['name']), r['level'], r['lo'], r['hi'], 100 * r['in_share'], 100 * r['far_share'], r['median'],
                fmt_m(r['m']).replace(' | ', ' | '), fl))
        out.append('')
    refs = [r for r in rows if r['kind'] in ('refs', 'data')]
    if refs:
        out += ['## References and generated tables', '', '| Place | Problem |', '|---|---|'] + ['| %s | %s |' % (r['id'], clean(r['detail'])) for r in refs] + ['']
    if flagged:
        out += ['## Defects', '', '| Hunt | Flags | Detail |', '|---|---|---|']
        for r in sorted(flagged, key=lambda r: (r['kind'], r.get('level', 0), r['id'])):
            out.append('| %s | %s | %s |' % (clean(r.get('name', r['id'])), ', '.join(r['flags']), clean(r.get('detail', ''))))
        out.append('')
    out += ['A star marks a defect listed in `tools/hunt_audit_known.csv` (accepted or waiting for a map edit).', '']
    return '\n'.join(out)


def write_csv(path, rows):
    with open(path, 'w', encoding='utf-8', newline='') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(['kind', 'id', 'name', 'level', 'lo', 'hi', 'monsters', 'walkable', 'per100', 'screen_mean', 'tpm', 'screen_peak',
                    'dead_share', 'sweep', 'in_share', 'far_share', 'median', 'flags', 'detail'])
        for r in rows:
            m = r.get('m') or {}
            w.writerow([r['kind'], r['id'], r.get('name', ''), r.get('level', ''), r.get('lo', ''), r.get('hi', ''), m.get('monsters', ''),
                        m.get('walkable', ''), '%.2f' % m['per100'] if m else '', '%.2f' % m['screen_mean'] if m else '',
                        '%.1f' % m['tpm'] if m else '', m.get('screen_max', ''), '%.2f' % m['dead_share'] if m else '',
                        '%.0f' % m['sweep'] if m else '', '%.2f' % r.get('in_share', 0), '%.2f' % r.get('far_share', 0),
                        r.get('median', ''), ' '.join(r['flags']), r.get('detail', '')])


# ------------------------------------------------------------------------------------------------ run
def read_goals(path):
    text = open(path, encoding='utf-8').read() if os.path.isfile(path) else ''
    blk = re.search(r'C\.hunts = \{(.*?)\n\}', text, re.S)
    return {m[0]: (int(m[1]), int(m[2])) for m in re.findall(r'id = "([^"]+)"[^}]*?level = \{(\d+), (\d+)\}', blk.group(1) if blk else '')}


def build_world(data_dir, map_path=None, log=print):
    """(map, walk, spot, trans, spawns text path, levels, exps, kinds, db)"""
    import otbm
    from itemdb import ItemDB
    import check_dead_holes as CD
    if map_path is None:
        import patch_base_towns
        map_path = patch_base_towns.map_path(data_dir)
    if not map_path or not os.path.isfile(map_path):
        raise HuntAuditError('no world map in %s/world' % data_dir)
    otb = os.path.join(data_dir, 'items', 'items.otb')
    xml = os.path.join(data_dir, 'items', 'items.xml')
    if not os.path.isfile(otb):
        raise HuntAuditError('no %s' % otb)
    xml = xml if os.path.isfile(xml) else None
    kinds = CD.Kinds.from_files(otb, xml)
    db = ItemDB(otb, xml)
    log('reading %s ...' % map_path)
    m = otbm.load_otbm(map_path)
    teles = AT.teleport_ids(db, xml)
    stacks = {}

    def stack(p):
        if p not in stacks:
            i = m.find(*p)
            stacks[p] = None if i < 0 else (int(m.tiles['flags'][i]), int(m.tiles['house'][i]), [int(s) for s in m.stack(i)])
        return stacks[p]

    def walk(p):
        s = stack(p)
        if not s or not s[2] or s[2][0] not in kinds.ground:
            return False
        return not any(i in kinds.block or i in kinds.fc or i in teles for i in s[2])

    def spot(p):
        s = stack(p)
        return bool(s) and not (s[0] & B.TF_PZ) and not s[1]
    trans = AT.find_transitions(m, kinds, db, xml)
    return dict(m=m, map_path=map_path, walk=walk, spot=spot, trans=trans, kinds=kinds, db=db)


def apply_renames(renames, hunts_csv, log=print):
    """[(hunt dict, new name)]: the CSV row's name, display and first `monsters` entry become the monster that stands at the
    arrival (the sign says what is there), the note records it. Returns how many rows changed"""
    raw = HO.read_csv(hunts_csv)
    by = {r['id']: r for r in raw}
    n = 0
    for h, new in renames:
        row = by[h['id']]
        old = row['name']
        if old == new:
            continue
        mons = [m for m in (row.get('monsters') or '').split('|') if m and m.lower() not in (old.lower(), new.lower())]
        row['monsters'] = '|'.join([new] + mons)
        row['name'], row['display'] = new, new
        row['note'] = ('renamed O337 from %s (the sign monster does not spawn at the arrival); ' % old + row['note']).strip('; ')
        n += 1
        log('renamed: %s -> %s (%s)' % (old, new, h['id']))
    if n:
        HO.write_csv(raw, hunts_csv)
    return n


def make_ctx(spawns, hall):
    """ctx(t, arrival, lo, hi) -> 'gate' / 'low' / 'ok' for a stock portal in reach (audit_hunt_bands.audit's verdict_of)"""
    cache = {}

    def far_side(land):
        if land not in cache:
            cache[land] = AT.describe(spawns, lambda *a: 0, land)
        return cache[land]

    def ctx(t, _a, lo, hi):
        if hall and B.in_box(t['land'], hall):
            return 'ok'
        return B.portal_verdict(lo, hi, far_side(t['land']))
    return ctx


def run(data_dir, kinds=KINDS, md=None, csv_path=None, known_path=KNOWN, check=False, hunts_csv=AT.HUNTS_CSV,
        plans_dir=PLANS, log=print, suggest=False, apply=False):
    w = build_world(data_dir, log=log)
    walk, spot = w['walk'], w['spot']
    trans_at = defaultdict(list)
    for t in w['trans']:
        trans_at[t['pos']].append(t)
    levels, exps = AT.monster_tables(data_dir)
    level_of = lambda n: levels.get(n.lower(), 0)
    spawn_path = w['map_path'][:-5] + '-spawn.xml'
    entries = parse_spawn_entries(open(spawn_path, encoding='latin-1').read())
    log('%d spawn entries' % len(entries))
    rows = []
    places_file = os.path.join(data_dir, 'lib', 'chaos_hunt_places.lua')
    places = parse_places(open(places_file, encoding='utf-8').read()) if os.path.isfile(places_file) else dict(places=[], base=[])
    if 'base' in kinds:
        spawns = AT.Spawns(AT.spawn_points(w['map_path']), levels, exps)
        hunts = B.read_hunts(hunts_csv)
        hall = B.hall_box(HO.read_csv(hunts_csv))
        rb = B.audit(hunts, spawns, walk, spot, w['trans'], hall, lambda *_: None, False)
        disp = {r['id']: r.get('display') or '' for r in HO.read_csv(hunts_csv)}
        base_rows = audit_base(rb, spawns, walk, spot, places['base'], trans_at, disp, level_of)
        rows += base_rows
        log('%d base hunts' % len(rb))
        if suggest:
            ctx = make_ctx(spawns, hall)
            arrivals = [r['hunt']['dest'] for r in rb]
            moves, renames = [], []
            for br, r in zip(base_rows, rb):
                if not [f for f in br['flags'] if f in SUGGEST_FLAGS]:
                    continue
                h = r['hunt']
                sign = [h['name'], disp.get(h['id'], '')]
                sg = suggest_base(spawns, h, sign, walk, spot, trans_at, [a for a in arrivals if a != h['dest']], ctx)
                log('%s (%s): %d suggestion(s)%s' % (h['name'], ','.join(br['flags']), len(sg), ''.join(
                    '\n    %s median %d, %d monsters in view, hunt of %d monsters' % (B.pos_text(c['arrival']), c['band'][2], c['stats']['named'],
                                                                                    c['cluster']['monsters']) for c in sg)))
                if sg:
                    moves.append(dict(hunt=h, flags=br['flags'], suggest=sg))
                elif 'display' in br['flags'] and r['stats']['top']:
                    renames.append((h, r['stats']['top'][0]))
                    log('    no better area: the sign could name %s, the monster most in view' % r['stats']['top'][0])
            if apply and (moves or renames):
                done = B.apply_retargets(moves, hunts_csv, log, tag='O337') if moves else []
                log('%d hunt(s) moved in %s' % (len(done), hunts_csv))
                log('%d sign(s) renamed in %s' % (apply_renames(renames, hunts_csv, log), hunts_csv))
    plans = read_plans(plans_dir)
    if 'planned' in kinds:
        by = {p['id']: p for p in places['places']}
        cfg_text = open(os.path.join(SERVER, 'data', 'scripts', 'chaos', 'hunt_teleports_config.lua'), encoding='utf-8').read()
        stand_in = set(re.findall(r'id = "([^"]+)", monster = "[^"]+", standIn = true', cfg_text))
        for pid, plan in sorted(plans.items()):
            if pid not in by:
                continue
            box = plan_box(plan)
            ents = [e for e in entries if in_box((e['x'], e['y'], e['z']), box)]
            rows.append(audit_planned(plan, by[pid], ents, level_of, walk, spot, trans_at, pid in stand_in))
        log('%d planned hunts' % len([r for r in rows if r['kind'] == 'planned']))
    if 'waystone' in kinds:
        ws = os.path.join(data_dir, 'scripts', 'customs', 'waystone_system', 'tier_maps.lua')
        cfg = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'waystone_tiers_config.lua')
        if os.path.isfile(ws) and os.path.isfile(cfg):
            cfg_text = open(cfg, encoding='utf-8').read()
            maps = WM.parse_tier_maps(open(ws, encoding='utf-8', errors='replace').read())
            names = WM.parse_config_monsters(cfg_text)
            clear = {(x, y, z) for x, y, z, _i in WM.parse_clear_path(cfg_text)}     # taken off the map at startup
            wwalk = lambda p: walk(p) or p in clear
            for i, (tier, name, a, b, dest) in enumerate(maps):
                label = 'Waystone map %d (tier %d, %s)' % (i + 1, tier, name.split(':')[0].strip())
                rows.append(audit_box_area(label, 'waystone', (a[0], a[1], b[0], b[1], a[2], a[2]), WAYSTONE_BAND, set(names[tier - 1]),
                                           entries, level_of, wwalk, spot, ident='waystone_%d' % (i + 1), start=dest))
    if 'late' in kinds:
        csv_path_late = os.path.join(HERE, 'late_game_spawns.csv')
        late_rows = defaultdict(list)
        for r in csv.DictReader(open(csv_path_late, encoding='utf-8')):
            late_rows[r['area']].append(dict(x=int(r['centerx']) + int(r['x']), y=int(r['centery']) + int(r['y']), z=int(r['z']), monster=r['monster']))
        for name, box in LATE_AREAS:
            rows.append(audit_late(name, box, late_rows.get(name, []), entries, level_of, walk, spot, ident=name.lower().replace(' ', '_')))
    if 'refs' in kinds:
        goals = read_goals(os.path.join(SERVER, 'data', 'scripts', 'chaos', 'goals_config.lua'))
        guide = ''
        for lang in ('en', 'pt-BR'):
            p = os.path.join(ROOT, 'website', 'overlay', 'plugins', 'chaos', 'wiki', 'guides', 'leveling.%s.md' % lang)
            if os.path.isfile(p):
                guide += open(p, encoding='utf-8').read() + '\n'
        rows += audit_refs(plans, goals, guide, places)
    if 'data' in kinds:
        import gen_bestiary_spawns as GBS
        import gen_bounty_pool as GBP
        spawn_text = open(spawn_path, encoding='latin-1').read()
        chaos = os.path.join(SERVER, 'data', 'scripts', 'chaos')
        fresh_b = GBS.render(GBS.parse(spawn_text))
        hunt, bosses, _r = GBP.build(data_dir, spawn_path)
        fresh_p = GBP.render(hunt, bosses, 'world/<mapName>-spawn.xml')
        for ident, fn, fresh in (('bestiary_spawns', 'bestiary_spawns.lua', fresh_b), ('bounty_pool', 'bounty_pool.lua', fresh_p)):
            row = audit_generated(ident, open(os.path.join(chaos, fn), encoding='utf-8').read(), fresh)
            if row:
                rows.append(row)
    known = read_known(known_path)
    new, stale = check_rows(rows, known)
    n = Counter(r['kind'] for r in rows)
    log('%s; %d hunts with a defect; %d new, %d stale in the known list' % (
        ', '.join('%d %s' % (v, k) for k, v in sorted(n.items())), sum(1 for r in rows if r['flags']), len(new), len(stale)))
    for r in rows:
        if r['flags']:
            log('  %-9s %-34s %s  %s' % (r['kind'], str(r.get('name', r['id']))[:34], ','.join(r['flags']), r.get('detail', '')[:110]))
    if md:
        open(md, 'w', encoding='utf-8', newline='\n').write(render_md(rows, known))
        log('wrote %s' % md)
    if csv_path:
        write_csv(csv_path, rows)
    if check and (new or stale):
        for i, f in new:
            log('NEW defect: %s %s' % (i, f))
        for i, f in stale:
            log('STALE known entry (fixed or gone): %s %s' % (i, f))
        return rows, 1
    return rows, 0


def main(argv):
    opts, pos, i = {}, [], 0
    while i < len(argv):
        a = argv[i]
        if a in ('--kind', '--md', '--csv', '--known', '--hunts', '--plans'):
            if i + 1 >= len(argv):
                print('%s needs a value' % a)
                return 1
            opts[a] = argv[i + 1]
            i += 1
        elif a in ('--check', '--quiet', '--suggest', '--apply'):
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
    kinds = tuple(opts['--kind'].split(',')) if '--kind' in opts else KINDS
    bad = [k for k in kinds if k not in KINDS]
    if bad:
        print('unknown kind %s (one of %s)' % (','.join(bad), ','.join(KINDS)))
        return 1
    try:
        _rows, rc = run(pos[0], kinds, md=opts.get('--md'), csv_path=opts.get('--csv'), known_path=opts.get('--known', KNOWN),
                        check=bool(opts.get('--check')), suggest=bool(opts.get('--suggest')), apply=bool(opts.get('--apply')), hunts_csv=opts.get('--hunts', AT.HUNTS_CSV), plans_dir=opts.get('--plans', PLANS),
                        log=(lambda *_: None) if opts.get('--quiet') else print)
    except (HuntAuditError, B.BandError, AT.AuditError, HO.HallError, OSError) as e:
        print('refused: %s' % e)
        return 1
    return rc


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
