#!/usr/bin/env python3
"""Audit the level band of every base hunt teleport's destination (server/README.md "Hunt bands (O333)").

usage: python3 -I server/tools/audit_hunt_bands.py DATA_DIR [--map FILE] [--hunts FILE] [--md FILE] [--csv FILE]
                                                   [--gates FILE] [--suggest [--apply]] [--quiet]

Tester report, 2026-10-29: "some hunt teleports send you to the wrong place". The sign said level 25 (Demon Skeleton),
the arrival held two Demon Skeletons and random monsters of level 15-20. In the same zone a stock portal led among
monsters of level 300 and 1000. DATA_DIR is a server data folder with world/<map>.otbm and -spawn.xml, items/items.otb and
items.xml and monster/ (the base copy or an installed server). Not in CI (it needs the map, about one minute;
tools/audit_hunt_bands_test.py runs the same maths on a synthetic map).
For every hunt of tools/hall_hunts.csv (kind `hunt`, base hunts with a destination on the map; the planned hunts are
generated areas and are built to their band)
  area      the known monsters the player can walk to from the arrival (flood fill) within AREA_R tiles on the arrival
            floor; with fewer than MIN_COUNT the nearest group wider (PASSES: 40 tiles, then the floors below, then 70, the
            way the hall's bands were derived). Count, share inside the band (lo and hi of the CSV, BAND_SLACK round them),
            share far outside it (FAR_FACTOR x), median level, how many are the hunt's own monsters (the `monsters`,
            `display` and `name` of the CSV) and how many stand within NEAR_R tiles of the arrival
  flags     defects: empty (no known monster), few (under MIN_COUNT), spread (under MIN_IN_SHARE inside the band), far
            (FAR_SHARE or more far outside it), named (under MIN_NAMED of the hunt's own monsters while under
            NAMED_OK_SHARE are in the band), mixed (the band is wider than MIXED x: the sign says 15-60 for a place where
            neither fits). Info only: thin (the arrival is at a cave mouth, not in the monsters)
  portals   every stock portal reachable on foot from the arrival (flood fill up to REACH_R tiles, REACH_MAX tiles):
            teleports with a destination on the map and floor changes (tools/audit_hunt_transitions.py reads them the same
            way). The far side is the known monsters within AREA_R tiles of the landing (at least audit_hunt_transitions.MIN_LOCAL). `gate`
            when the far side's median is over PORTAL_UP x the band's top and PORTAL_STEP more; `low` when under half the
            band's bottom (harmless, listed). A portal back into the hall is skipped.
  suggest   (--suggest) for a hunt with flags: the best arrival tiles of the map for its band (a spawn of the hunt's own
            monsters, AREA_R tiles round it hold SUGGEST_MIN or more monsters, SUGGEST_IN_SHARE of them in the band, none far
            outside, a walkable arrival with a region of REGION_MIN tiles, no spawn within 3 tiles, no protection zone or
            house, no gate portal in reach, not within 40 tiles of another hunt's arrival)
Writes (deterministic, no dates)
  --md      docs/HUNT_BANDS.md      the table of every hunt, the portals to gate and the better arrivals
  --csv     FILE                    one row per hunt (for review)
  --gates   tools/hunt_gates.csv    the portals to gate, one row each (patch_hunt_gates.py takes them off the map). Only the
                                    portals in reach of the CSV's hunts as they are now, so run --apply first, then this
  --apply   (with --suggest) tools/hall_hunts.csv: each flagged hunt moves to its best suggested arrival (dest, level,
                                    lo, hi; the note says where it came from) and the `returns` lines for
                                    hunt_teleports_config.lua are printed (the way back beside the new arrival)
Exit 0 on success, 1 on a refusal. Python 3 and numpy (tools/map/otbm.py, itemdb.py).
"""
import csv, os, sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
ROOT = os.path.dirname(SERVER)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'map'))

import audit_hunt_transitions as AT  # noqa: E402
import audit_waystone_maps as WM  # noqa: E402
import hall_order as HO  # noqa: E402

DOC = os.path.join(ROOT, 'docs', 'HUNT_BANDS.md')
GATES = os.path.join(HERE, 'hunt_gates.csv')

AREA_R = 20             # tiles round the arrival (and round a landing) whose monsters count
NEAR_R = 12             # the arrival's own surroundings: known monsters walked to within this many tiles
MIXED = 3.0             # a band wider than 3 x (hi over lo): `mixed`
MIN_NEAR = 5            # fewer: `thin` (the arrival is at the edge of the area or in front of it)
MIN_COUNT = 8           # fewer known monsters in AREA_R: `few`
BAND_SLACK = 0.2        # a monster is inside the band between lo x (1 - slack) and hi x (1 + slack)
MIN_IN_SHARE = 0.6
FAR_FACTOR = 2.0        # far outside: over 2 x the band's top (and FAR_STEP more) or under half its bottom
FAR_STEP = 25
FAR_SHARE = 0.25
MIN_NAMED = 4
NAMED_OK_SHARE = 0.9    # `named` is a defect only while under this share of the monsters is inside the band (a camp of
                        # level-scaled kin of the sign's monster is fine)
REACH_R = 45            # the flood fill stays within this many tiles of the arrival
REACH_MAX = 12000
PORTAL_UP = 1.5         # a gate: the far side's median over 1.5 x the band's top
PORTAL_STEP = 30        # and over its top by this much
SUGGEST_MIN = 12
SUGGEST_IN_SHARE = 0.8
REGION_MIN = 500
APART = 40              # a suggested arrival keeps this far from every other hunt's arrival
HALL_MARGIN = 40
TF_PZ = 1
FLAGS = ('empty', 'few', 'spread', 'far', 'named', 'mixed')


class BandError(Exception):
    pass


# ------------------------------------------------------------------------------------------------ the area
def inside(level, lo, hi, slack=BAND_SLACK):
    return lo * (1 - slack) <= level <= hi * (1 + slack)


def far_outside(level, lo, hi):
    return (level > FAR_FACTOR * hi and level - hi >= FAR_STEP) or (level < lo / FAR_FACTOR and lo - level >= FAR_STEP)


def area_stats(spawns, pos, lo, hi, own=(), r=AREA_R, tiles=None, floors=(0,)):
    """dict(total, count, in_share, far_share, median, named, top, floors) of the known monsters within r tiles of `pos` on
    the floors pos z + `floors`. tiles: the set of tiles walked from pos (reach); a monster counts when its spawn tile
    is in it or beside it (a creature that cannot walk to the arrival is not part of the hunt)"""
    np = spawns.np
    x, y, z = pos
    m = (np.abs(spawns.x - x) <= r) & (np.abs(spawns.y - y) <= r) & np.isin(spawns.z - z, floors)
    allidx = np.flatnonzero(m)
    if tiles is not None:
        allidx = np.array([i for i in allidx if beside(tiles, int(spawns.x[i]), int(spawns.y[i]), int(spawns.z[i]))], np.int64)
    idx = allidx[spawns.level[allidx] > 0] if len(allidx) else allidx
    out = dict(total=len(allidx), count=len(idx), in_share=0.0, far_share=0.0, median=0, named=0, top=[], idx=idx)
    if not len(idx):
        return out
    lv = spawns.level[idx]
    out['in_share'] = sum(1 for v in lv if inside(int(v), lo, hi)) / float(len(idx))
    out['far_share'] = sum(1 for v in lv if far_outside(int(v), lo, hi)) / float(len(idx))
    out['median'] = int(np.median(lv))
    mine = {n.lower() for n in own if n}
    out['named'] = sum(1 for i in idx if spawns.names[int(spawns.n[i])].lower() in mine)
    c = Counter(spawns.names[int(spawns.n[i])] for i in idx)
    out['top'] = [n for n, _c in sorted(c.items(), key=lambda kv: (-kv[1], kv[0]))[:4]]
    return out


def beside(tiles, x, y, z):
    return any((x + dx, y + dy, z) in tiles for dy in (-1, 0, 1) for dx in (-1, 0, 1))


DOWN = (0, 1, 2, 3)
# the monsters a hunter meets, nearest group first: (name, radius, floors, walked from the arrival)
PASSES = (('here', AREA_R, (0,), True), ('wide', 40, (0,), False), ('below', 40, DOWN, False), ('deep', 70, DOWN, False))


def area_view(spawns, pos, lo, hi, own, tiles, min_count=MIN_COUNT, passes=PASSES):
    """area_stats of the first pass of PASSES with at least min_count known monsters (the last one when none), plus
    `pass` (its name) and `near` (known monsters walked to within NEAR_R tiles on the arrival floor)"""
    got = None
    for name, r, floors, walked in passes:
        got = area_stats(spawns, pos, lo, hi, own, r=r, tiles=tiles if walked else None, floors=floors)
        got['pass'] = name
        if got['count'] >= min_count:
            break
    near = area_stats(spawns, pos, lo, hi, own, r=NEAR_R, tiles=tiles)
    got['near'] = near['count']
    return got


def area_flags(st, own_count=MIN_NAMED, lo=0, hi=0):
    """(defects, info) of an area view. Defects: `empty` / `few` known monsters, `spread` (under MIN_IN_SHARE inside the
    band), `far` (FAR_SHARE or more far outside it), `named` (under MIN_NAMED of the hunt's own monsters while under NAMED_OK_SHARE
    of the monsters are inside the band), `mixed` (a band wider than MIXED x: the sign says 15-60 for a place where neither fits).
    Info: `thin` (the arrival is not in the monsters: the nearest group is more than AREA_R tiles off or under MIN_NEAR
    are within NEAR_R; stock caves are entered at their mouth, so it is a note, not a defect). Monsters on the floors
    below are a cave under stairs (owner, 2026-10-16) and are judged by band only"""
    if st['count'] == 0:
        return ['empty'], []
    f = []
    if st['count'] < MIN_COUNT:
        f.append('few')
    if st['in_share'] < MIN_IN_SHARE:
        f.append('spread')
    if st['far_share'] >= FAR_SHARE:
        f.append('far')
    if own_count and st['named'] < min(MIN_NAMED, own_count) and st['in_share'] < NAMED_OK_SHARE:
        f.append('named')
    if lo and hi > MIXED * lo:
        f.append('mixed')
    info = ['thin'] if st['pass'] in ('here', 'wide') and st['near'] < MIN_NEAR else []
    return f, info


# ------------------------------------------------------------------------------------------------ portals in reach
def reach(walk, start, r=REACH_R, cap=REACH_MAX):
    """tiles reachable on foot from start within r tiles (Chebyshev), at most cap of them"""
    x, y, z = start
    got = WM.flood(walk, start, (x - r, y - r, x + r, y + r, z))
    return set(sorted(got)[:cap]) if len(got) > cap else got


def portals_in_reach(tiles, trans_at):
    """[transition dicts] standing on, or beside, a reached tile (a floor change or teleport tile is not walkable for the flood)"""
    seen, out = set(), []
    for (x, y, z) in tiles:
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                p = (x + dx, y + dy, z)
                if p in seen:
                    continue
                seen.add(p)
                for t in trans_at.get(p, ()):
                    out.append(t)
    return sorted(out, key=lambda t: (t['pos'], t['item']))


def portal_verdict(lo, hi, far):
    """'gate' / 'low' / 'ok' for a portal whose far side is `far` (dict(level, ...) or None: quiet)"""
    if not far or not far.get('level'):
        return 'ok'
    d = far['level']
    if d > PORTAL_UP * hi and d - hi >= PORTAL_STEP:
        return 'gate'
    if d < lo / FAR_FACTOR and lo - d >= FAR_STEP:
        return 'low'
    return 'ok'


def in_box(p, box):
    return box[0] <= p[0] <= box[1] and box[4] <= p[1] <= box[5] and box[2] <= p[2] <= box[3]


def hall_box(rows, margin=HALL_MARGIN):
    """(x0, x1, z0, z1, y0, y1): the hall's floors and span from the CSV's own teleport places, plus a margin"""
    pl = [(r['x'], r['y'], r['z']) for r in rows if r.get('x') is not None]
    if not pl:
        return None
    return (min(p[0] for p in pl) - margin, max(p[0] for p in pl) + margin, min(p[2] for p in pl), max(p[2] for p in pl),
            min(p[1] for p in pl) - margin, max(p[1] for p in pl) + margin)


# ------------------------------------------------------------------------------------------------ suggestions
def arrival_tile(walk, spot, spawns, centre, region_min=REGION_MIN, search=8):
    """the walkable tile nearest `centre` with `spot(tile)` true, no spawn within 3 tiles and a region of region_min tiles
    (flood fill within 40 tiles); None when there is none within `search` tiles"""
    np = spawns.np
    cx, cy, z = centre
    best = None
    cand = sorted(((abs(x - cx) + abs(y - cy), x, y) for x in range(cx - search, cx + search + 1)
                   for y in range(cy - search, cy + search + 1)))
    near = (spawns.z == z) & (np.abs(spawns.x - cx) <= search + 4) & (np.abs(spawns.y - cy) <= search + 4)
    sx, sy = spawns.x[near], spawns.y[near]
    for _d, x, y in cand:
        p = (x, y, z)
        if not walk(p) or not spot(p):
            continue
        if len(sx) and (np.maximum(np.abs(sx - x), np.abs(sy - y)) <= 3).any():
            continue
        if len(WM.flood(walk, p, (x - 40, y - 40, x + 40, y + 40, z))) < region_min:
            continue
        best = p
        break
    return best


def tight_band(hunt):
    """the band a suggested arrival is judged by: the hunt's own band cut to its level / 1.5 .. level x 1.5"""
    lv = hunt['level']
    return max(hunt['lo'], int(lv / 1.5)), min(hunt['hi'], int(lv * 1.5 + 0.999))


def suggest(spawns, hunt, walk, spot, trans_at, others, gate_free=True, limit=3, ctx=None):
    """[dict(arrival, stats)] up to `limit` better arrival tiles for a hunt, best first (see the module doc)"""
    np = spawns.np
    lo, hi = tight_band(hunt)
    own = {n.lower() for n in hunt.get('monsters', ()) if n} | ({hunt['name'].lower()} if hunt.get('name') else set())
    inband = np.array([inside(int(v), lo, hi) for v in spawns.level], bool) & (spawns.level > 0)
    namedm = np.array([spawns.names[int(i)].lower() in own for i in spawns.n], bool) & inband
    centres = np.flatnonzero(namedm)
    scored = []
    for i in centres:
        x, y, z = int(spawns.x[i]), int(spawns.y[i]), int(spawns.z[i])
        st = area_stats(spawns, (x, y, z), lo, hi, sorted(own))
        if st['count'] < SUGGEST_MIN or st['in_share'] < SUGGEST_IN_SHARE or st['far_share'] > 0 or st['named'] < MIN_NAMED:
            continue
        if any(o[2] == z and max(abs(o[0] - x), abs(o[1] - y)) < APART for o in others):
            continue
        close = round(abs(st['median'] - hunt['level']) / float(max(hunt['level'], 1)), 1)
        scored.append((close, -min(st['named'], 30), -st['count'], x, y, z, st))
    scored.sort(key=lambda t: t[:6])
    out, used = [], []
    for _d, _n, _c, x, y, z, st in scored:
        if any(u[2] == z and max(abs(u[0] - x), abs(u[1] - y)) < APART for u in used):
            continue
        a = arrival_tile(walk, spot, spawns, (x, y, z))
        if a is None:
            continue
        tiles = reach(walk, a)
        view = area_view(spawns, a, lo, hi, sorted(own), tiles)
        if area_flags(view, len(own), lo, hi)[0] or view['pass'] != 'here':
            continue
        if gate_free and ctx is not None:
            if any(ctx(t, a, lo, hi) == 'gate' for t in portals_in_reach(tiles, trans_at)):
                continue
        bd = spawns.band(view['idx'])
        out.append(dict(arrival=a, stats=view, band=(bd[0], bd[1], bd[2]), top=bd[3], at=return_tile(walk, spot, tiles, a)))
        used.append((x, y, z))
        if len(out) >= limit * 3:
            break
    out.sort(key=lambda c: (round(abs(c['band'][2] - hunt['level']) / float(max(hunt['level'], 1)), 1),
                            -min(c['stats']['named'], 12), -c['stats']['count'], c['arrival']))
    return out[:limit]


def return_tile(walk, spot, tiles, a):
    """the tile beside the arrival for the way back (hunt_teleports_config.lua returns `at`): nearest reached spot tile that is not it"""
    best = None
    for (x, y, z) in tiles:
        if (x, y, z) == a or not spot((x, y, z)) or not walk((x, y, z)):
            continue
        d = (max(abs(x - a[0]), abs(y - a[1])), abs(x - a[0]) + abs(y - a[1]), x, y)
        if best is None or d < best[0]:
            best = (d, (x, y, z))
    return best[1] if best else None
    return out


# ------------------------------------------------------------------------------------------------ the audit
def audit(hunts, spawns, walk, spot, trans, hall, log=print, want_suggest=False):
    """one row per hunt: dict(hunt, stats, flags, portals [dict(t, far, verdict)], reach, suggest)"""
    trans_at = {}
    for t in trans:
        trans_at.setdefault(t['pos'], []).append(t)
    cache = {}

    def far_side(land):
        if land not in cache:
            cache[land] = AT.describe(spawns, lambda *a: 0, land)   # None: fewer than AT.MIN_LOCAL known monsters
        return cache[land]

    def verdict_of(t, _a, lo, hi):
        if hall and in_box(t['land'], hall):
            return 'ok'
        return portal_verdict(lo, hi, far_side(t['land']))
    rows = []
    for h in hunts:
        arrival = h['dest']
        own = sorted({n for n in h.get('monsters', ()) if n})
        tiles = reach(walk, arrival)
        st = area_view(spawns, arrival, h['lo'], h['hi'], own, tiles)
        flags, info = area_flags(st, len(own), h['lo'], h['hi'])
        ports = []
        for t in portals_in_reach(tiles, trans_at):
            if t['land'] == arrival:
                continue
            v = verdict_of(t, arrival, h['lo'], h['hi'])
            ports.append(dict(t=t, far=far_side(t['land']), verdict=v))
        rows.append(dict(hunt=h, stats=st, flags=flags, info=info, portals=ports, reach=len(tiles), suggest=[]))
    if want_suggest:
        arrivals = [r['hunt']['dest'] for r in rows]
        for r in rows:
            if not r['flags'] and not any(p['verdict'] == 'gate' for p in r['portals']):
                continue
            others = [a for a in arrivals if a != r['hunt']['dest']]
            r['suggest'] = suggest(spawns, r['hunt'], walk, spot, trans_at, others, ctx=verdict_of)
            log('%s: %d suggestion(s)' % (r['hunt']['name'], len(r['suggest'])))
    return rows


# ------------------------------------------------------------------------------------------------ output
def pos_text(p):
    return '%d,%d,%d' % tuple(p)


def clean(s):
    return str(s).replace('|', '/')


def gates_of(rows):
    """[(pos, land, level lo of the far side, hunt name)] of the portals to gate: the far side's lowest level label, once
    per portal (a portal in reach of two hunts is gated at the lower hunt's band)"""
    best = {}
    for r in rows:
        for p in r['portals']:
            if p['verdict'] != 'gate':
                continue
            t = p['t']
            key = (t['pos'], t['item'])
            need = AT.level_label(p['far']['lo'] if p['far']['lo'] else p['far']['level'])
            cur = best.get(key)
            if cur is None or r['hunt']['hi'] < cur[4]:
                best[key] = (t['pos'], t['land'], need, r['hunt']['name'], r['hunt']['hi'], t['kind'], t['item'])
    return sorted(best.values(), key=lambda g: (g[0], g[6]))


def render_md(rows, mark=''):
    n = Counter()
    for r in rows:
        n['hunts'] += 1
        n['flagged'] += 1 if r['flags'] else 0
        n['gates'] += sum(1 for p in r['portals'] if p['verdict'] == 'gate')
    out = ['# Hunt bands (O333)', '',
           'Tester, 2026-10-29: some hunt teleports send the player to the wrong place. The sign said level 25 and the arrival',
           'held two of the named monster and random monsters of other levels. A stock portal in the same zone led among',
           'monsters of level 300 and 1000. This table is the audit. It is made by `server/tools/audit_hunt_bands.py` from the',
           'base map and spawn file%s and is not run in CI.' % mark, '',
           '## How to read it', '',
           '- **Band**: the sign\'s level range of the hunt (`tools/hall_hunts.csv`). A monster is inside it between lo x %.1f and hi x %.1f.'
           % (1 - BAND_SLACK, 1 + BAND_SLACK),
           '- **Monsters**: known monsters on the arrival floor within %d tiles of the arrival.' % AREA_R,
           '- **In band / far**: share of them inside the band, and far outside it (over %.0f x the top, or under half the bottom).'
           % FAR_FACTOR,
           '- **Own**: how many are the hunt\'s own monsters (the ones its sign and display name).',
           '- **Flags**: `empty` no known monster, `few` under %d, `spread` under %d%% inside the band, `far` %d%% or more far'
           ' outside, `named` under %d of its own monsters.' % (MIN_COUNT, MIN_IN_SHARE * 100, FAR_SHARE * 100, MIN_NAMED),
           '- **Gate**: a stock portal reachable on foot from the arrival whose far side has a median level over %.1f x the'
           ' band\'s top and %d more.' % (PORTAL_UP, PORTAL_STEP),
           '', '## Totals', '',
           '%d hunts, %d flagged, %d gate portals in reach.' % (n['hunts'], n['flagged'], n['gates']), '',
           '## Hunts', '',
           '| Hunt (level) | Band | Arrival | Monsters | In band | Far | Median | Own | Flags | Gates |',
           '|---|---|---|---|---|---|---|---|---|---|']
    for r in sorted(rows, key=lambda r: (r['hunt']['level'], r['hunt']['name'], r['hunt']['id'])):
        h, s = r['hunt'], r['stats']
        out.append('| %s (%d) | %d-%d | %s | %d | %.0f%% | %.0f%% | %d | %d | %s | %d |' % (
            clean(h['name']), h['level'], h['lo'], h['hi'], pos_text(h['dest']), s['count'], 100 * s['in_share'],
            100 * s['far_share'], s['median'], s['named'], ', '.join(r['flags']) or 'ok',
            sum(1 for p in r['portals'] if p['verdict'] == 'gate')))
    out += ['', '## Stock portals in reach of a hunt arrival', '']
    pl = [(r, p) for r in rows for p in r['portals'] if p['verdict'] in ('gate', 'low')]
    if pl:
        out += ['| Hunt | Portal | Kind | Lands | Far side band (median) | Monsters | Verdict |', '|---|---|---|---|---|---|---|']
        for r, p in sorted(pl, key=lambda rp: (rp[0]['hunt']['level'], rp[0]['hunt']['name'], rp[1]['t']['pos'])):
            f, t = p['far'], p['t']
            out.append('| %s | %s | %s | %s | %d-%d (%d) | %s | %s |' % (
                clean(r['hunt']['name']), pos_text(t['pos']), t['kind'], pos_text(t['land']), f['lo'], f['hi'], f['level'],
                ', '.join(clean(x) for x in f['top']), p['verdict']))
    else:
        out += ['None.']
    sug = [r for r in rows if r['suggest']]
    if sug:
        out += ['', '## Better arrivals (--suggest)', '',
                '| Hunt | Now | Suggested | Monsters | In band | Median | Own |', '|---|---|---|---|---|---|---|']
        for r in sug:
            for s in r['suggest']:
                st = s['stats']
                out.append('| %s | %s | %s | %d | %.0f%% | %d | %d |' % (
                    clean(r['hunt']['name']), pos_text(r['hunt']['dest']), pos_text(s['arrival']), st['count'],
                    100 * st['in_share'], st['median'], st['named']))
    out += ['', '## Limits', '',
            '- Only the base hunts of the CSV. The planned hunts are generated at their own origins and built to their band.',
            '- Portals with a destination on the map and floor changes. A teleport whose target a movement script sets (an',
            '  action or unique id) has no destination on the map and is not found.',
            '- Levels are the hall\'s scale (`gen_bounty_pool.py` estimate). Run the audit on the installed server\'s data',
            '  folder too: the first run is on the base copy.', '']
    return '\n'.join(out)


def gate_rows(gates, kinds, world):
    """[(x, y, z, item, action, ground, kind, land, level, hunt)] for patch_hunt_gates.py: `remove` takes the item off its tile,
    `ground` swaps a tile whose ground IS the floor change (stairs, a ramp) for the plain ground round it; `none` when
    no plain ground is near"""
    import check_dead_holes as CD
    out = []
    for pos, land, need, name, _hi, kind, item in gates:
        ids = world.tile(*pos) or []
        if ids and ids[0] == item:
            g = CD.plain_ground(kinds, world, pos)
            action, ground = ('ground', g) if g else ('none', '')
        else:
            action, ground = 'remove', ''
        out.append((pos[0], pos[1], pos[2], item, action, ground, kind, pos_text(land), need, clean(name)))
    return out


GATE_HEAD = ('# Stock portals in reach of a base hunt arrival whose far side is far above the hunt\'s band (server/tools/audit_hunt_bands.py\n'
             '# --gates, server/README.md "Hunt bands (O333)"), the patch list of patch_hunt_gates.py (install step `huntgates`):\n'
             '# remove = the item goes off the tile; ground = the tile\'s ground IS the floor change, it becomes `ground`;\n'
             '# none = no plain ground near, left alone. Positions and item ids only, no map data.\n')


def write_gates(path, rows):
    """tools/hunt_gates.csv; True when the file changed"""
    import io
    buf = io.StringIO()
    buf.write(GATE_HEAD)
    w = csv.writer(buf, lineterminator='\n')
    w.writerow(['x', 'y', 'z', 'item', 'action', 'ground', 'kind', 'lands', 'far_level', 'hunt'])
    for r in sorted(rows):
        w.writerow(r)
    text = buf.getvalue()
    old = open(path, encoding='utf-8').read() if os.path.isfile(path) else None
    if old != text:
        open(path, 'w', encoding='utf-8', newline='\n').write(text)
    return old != text


def write_csv(path, rows):
    with open(path, 'w', encoding='utf-8', newline='') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(['id', 'name', 'level', 'lo', 'hi', 'x', 'y', 'z', 'monsters', 'in_share', 'far_share', 'median', 'own', 'pass', 'near', 'flags',
                    'gates', 'suggested'])
        for r in rows:
            h, s = r['hunt'], r['stats']
            w.writerow([h['id'], h['name'], h['level'], h['lo'], h['hi']] + list(h['dest']) + [
                s['count'], '%.2f' % s['in_share'], '%.2f' % s['far_share'], s['median'], s['named'], s['pass'], s['near'], ' '.join(r['flags']),
                sum(1 for p in r['portals'] if p['verdict'] == 'gate'),
                ' '.join(pos_text(x['arrival']) for x in r['suggest'])])


# ------------------------------------------------------------------------------------------------ run
def read_hunts(path=AT.HUNTS_CSV):
    """the CSV's hunts: dict(id, name, level, lo, hi, dest, monsters) on the hunting scale"""
    rows = HO.hunting_rows(HO.read_csv(path))
    return [dict(id=r['id'], name=r['name'], level=r['level'], lo=r['lo'], hi=r['hi'],
                 dest=(r['dest_x'], r['dest_y'], r['dest_z']), monsters=[x for x in ((r.get('monsters') or '').split('|') + [r.get('display') or '', r['name']]) if x],
                 x=r.get('x'), y=r.get('y'), z=r.get('z'))
            for r in rows if r.get('kind') == 'hunt']


def apply_retargets(rows, hunts_csv, log=print):
    """move every flagged hunt that has a suggestion to its best one in hall_hunts.csv; returns [(id, name, old, new, band, at)]"""
    mult = HO.base_level_mult()
    if mult != 1:
        raise BandError('baseLevelMult is %d: the CSV is on the pool scale, --apply handles only 1' % mult)
    raw = HO.read_csv(hunts_csv)
    by = {r['id']: r for r in raw}
    done = []
    for r in rows:
        if not r['flags'] or not r['suggest']:
            continue
        row, sg = by[r['hunt']['id']], r['suggest'][0]
        old = (row['dest_x'], row['dest_y'], row['dest_z'])
        row['dest_x'], row['dest_y'], row['dest_z'] = sg['arrival']
        row['lo'], row['hi'], row['level'] = sg['band']
        row['note'] = ('retargeted O333 from %s (%s); ' % (pos_text(old), ' '.join(r['flags'])) + row['note']).strip('; ')
        done.append((row['id'], row['name'], old, sg['arrival'], sg['band'], sg['at']))
    if done:
        HO.write_csv(raw, hunts_csv)
    for hid, name, _old, new, _band, at in done:
        log('returns: {id = "%s", at = {x = %d, y = %d, z = %d}}, -- %s' % ((hid,) + tuple(at or new) + (name,)))
    return done


def run(data_dir, map_path=None, md=None, gates=None, csv_path=None, hunts_csv=AT.HUNTS_CSV, want_suggest=False,
        apply=False, log=print):
    import otbm
    from itemdb import ItemDB
    import check_dead_holes as CD
    if apply and not want_suggest:
        raise BandError('--apply needs --suggest')
    if map_path is None:
        import patch_base_towns
        map_path = patch_base_towns.map_path(data_dir)
    if not map_path or not os.path.isfile(map_path):
        raise BandError('no world map in %s/world' % data_dir)
    otb = os.path.join(data_dir, 'items', 'items.otb')
    xml = os.path.join(data_dir, 'items', 'items.xml')
    if not os.path.isfile(otb):
        raise BandError('no %s' % otb)
    xml = xml if os.path.isfile(xml) else None
    kinds = CD.Kinds.from_files(otb, xml)
    db = ItemDB(otb, xml)
    log('reading %s ...' % map_path)
    m = otbm.load_otbm(map_path)
    levels, exps = AT.monster_tables(data_dir)
    spawns = AT.Spawns(AT.spawn_points(map_path), levels, exps)
    all_rows = HO.read_csv(hunts_csv)
    hunts = read_hunts(hunts_csv)
    hall = hall_box(all_rows)
    trans = AT.find_transitions(m, kinds, db, xml)
    log('%d hunts, %d spawned monsters, %d transitions' % (len(hunts), len(spawns.x), len(trans)))
    stacks = {}
    teles = AT.teleport_ids(db, xml)

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
        return bool(s) and not (s[0] & TF_PZ) and not s[1]
    rows = audit(hunts, spawns, walk, spot, trans, hall, log, want_suggest)
    n = Counter('flagged' if r['flags'] else 'ok' for r in rows)
    g = gates_of(rows)
    log('%d hunts: %d ok, %d flagged; %d portals to gate' % (len(rows), n['ok'], n['flagged'], len(g)))
    for r in rows:
        if r['flags'] or any(p['verdict'] == 'gate' for p in r['portals']):
            log('  %-28s %s%s' % (r['hunt']['name'], ','.join(r['flags']) or '-',
                                   '  gates %d' % sum(1 for p in r['portals'] if p['verdict'] == 'gate')
                                   if any(p['verdict'] == 'gate' for p in r['portals']) else ''))
    if apply:
        done = apply_retargets(rows, hunts_csv, log)
        log('%d hunt(s) moved in %s' % (len(done), hunts_csv))
    if md:
        open(md, 'w', encoding='utf-8', newline='\n').write(render_md(rows, ''))
        log('wrote %s' % md)
    if gates:
        log('%s %s' % (gates, 'updated' if write_gates(gates, gate_rows(g, kinds, CD.MapWorld(m))) else 'unchanged'))
    if csv_path:
        write_csv(csv_path, rows)
    return rows


def main(argv):
    opts, pos, i = {}, [], 0
    while i < len(argv):
        a = argv[i]
        if a in ('--map', '--md', '--gates', '--csv', '--hunts'):
            if i + 1 >= len(argv):
                print('%s needs a value' % a)
                return 1
            opts[a] = argv[i + 1]
            i += 1
        elif a in ('--quiet', '--suggest', '--apply'):
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
        run(pos[0], map_path=opts.get('--map'), md=opts.get('--md'), gates=opts.get('--gates'), csv_path=opts.get('--csv'),
            hunts_csv=opts.get('--hunts', AT.HUNTS_CSV), want_suggest=bool(opts.get('--suggest')), apply=bool(opts.get('--apply')),
            log=(lambda *_: None) if opts.get('--quiet') else print)
    except (BandError, AT.AuditError, HO.HallError, OSError) as e:
        print('refused: %s' % e)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
