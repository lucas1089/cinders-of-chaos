#!/usr/bin/env python3
"""Audit the teleports, holes and stairs at monster areas (server/README.md "Hunt warnings (O323)").

usage: python3 -I server/tools/audit_hunt_transitions.py DATA_DIR [--map FILE] [--md FILE] [--lua FILE] [--csv FILE]
                                                         [--hunts FILE] [--quiet]

Owner, 2026-10-29: "some low-level hunts have a hole or a portal inside them that takes the player to a place with much
stronger monsters and high density". DATA_DIR is a server data folder with world/<map>.otbm and -spawn.xml, items/
items.otb and items.xml and monster/ (the base copy or an installed server). Not in CI (it needs the map, about a
minute; tools/audit_hunt_transitions_test.py runs the same maths on a synthetic map).
What it does
  transitions  every teleport item with a destination (tools/map/otbm.py), and every floor change the way
               check_dead_holes.py reads them (floor change item, ladder, rope spot, sewer grate): the landing is what the
               engine does (holes and stairs down: z + 1; stairs, ramps, ladders up: z - 1 and a step)
  source       a transition is "in or at the edge" of a monster area when a spawn is within ATTACH tiles on its floor. The
               source band is the known monsters of the same floor within LOCAL_PASSES of the entry (at least MIN_LOCAL):
               lo, hi, median level (hall_order.band), average experience per kill, density = monsters per 100 walkable
               tiles within DENSITY_R. When the entry lies within NAME_R tiles of the destination of a hall hunt
               (tools/hall_hunts.csv) that hunt names the area and its hall level is the source level
  destination  the same numbers round the landing; fewer than MIN_LOCAL known monsters: nothing to fear (a town, a temple,
               a quiet room)
  verdict      THRESHOLDS: `danger` when the destination's level is 2 x the source's or more (and 25 more), or, from 1.5 x
               (and 15 more), its experience per kill is over 3 x or its density over 3 x; `extreme` when the level is
               3 x or more (and 40 more); a source level under 8 counts as 8; else `ok`. No entry is blocked: the warning only tells the player
Writes (all deterministic, no dates)
  --md   docs/HUNT_TRANSITIONS.md   the table: source area, position, kind, destination, destination band, monsters, density,
                                    verdict (danger and extreme in full, `ok` ones in full while they are few, else counted)
  --lua  server/data/scripts/chaos/hunt_warnings_config.lua   the `places` of the dangerous ones between its markers
                                    (hunt_warnings.lua reads them); the numbers and texts of that file stay
  --csv  FILE                       every transition found, one row each (for review)
Exit 0 on success, 1 on a refusal. Python 3 and numpy (tools/map/otbm.py, itemdb.py).
"""
import csv, os, re, sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
ROOT = os.path.dirname(SERVER)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'map'))

import check_dead_holes as CD  # noqa: E402
import hall_order as HO  # noqa: E402

HUNTS_CSV = os.path.join(HERE, 'hall_hunts.csv')
DOC = os.path.join(ROOT, 'docs', 'HUNT_TRANSITIONS.md')
CONFIG = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'hunt_warnings_config.lua')

ATTACH = 6              # tiles from a spawn of the hunt: "in or at the edge"
DENSITY_R = 12          # radius of the density box
NAME_R = 60             # a landing is "in" the hall hunt whose destination is within this
GROUP_R = 12            # landings this close on a floor are one destination (one warning message per character)
LOCAL_PASSES = ((25, (0,)),)   # a destination or a source: the monsters of the same floor within 25 tiles
MIN_LOCAL = 4
ALL_ROWS_MAX = 400      # `ok` rows are listed in full up to this many, else counted by kind
THRESHOLDS = dict(level=2.0, level_min_step=25, exp=3.0, density=3.0, soft_level=1.5, soft_min_step=15, extreme=3.0,
                  extreme_min_step=40, source_floor=8)
TELEPORT_GROUP = 7
VERDICTS = ('ok', 'danger', 'extreme')


class AuditError(Exception):
    pass


# ------------------------------------------------------------------------------------------------ inputs
def read_hunts(path=HUNTS_CSV):
    """the hall hunts that have a destination: [dict(id, name, level, lo, hi, dest)] (hunting scale)"""
    rows = HO.hunting_rows(HO.read_csv(path))
    return [dict(id=r['id'], name=r['name'], level=r['level'], lo=r['lo'], hi=r['hi'],
                 dest=(r['dest_x'], r['dest_y'], r['dest_z']))
            for r in rows if r.get('kind') == 'hunt' and r.get('dest_x') is not None]


class Spawns:
    """the spawn file as arrays: x, y, z, level (0 unknown), experience, a name index"""

    def __init__(self, points, levels, exps):
        import numpy as np
        self.np = np
        self.names = sorted({p[3] for p in points})
        idx = {n: i for i, n in enumerate(self.names)}
        self.x = np.array([p[0] for p in points], np.int32)
        self.y = np.array([p[1] for p in points], np.int32)
        self.z = np.array([p[2] for p in points], np.int32)
        self.n = np.array([idx[p[3]] for p in points], np.int32)
        self.level = np.array([levels.get(p[3].lower(), 0) for p in points], np.int32)
        self.exp = np.array([exps.get(p[3].lower(), 0) for p in points], np.float64)

    def near(self, dest, passes=HO.PASSES, min_count=8):
        """indices of the known monsters round dest (hall_order.hunt_band's passes); empty when none"""
        np = self.np
        dx, dy, dz = dest
        got = np.zeros(0, np.int64)
        for r, dzs in passes:
            m = (np.abs(self.x - dx) <= r) & (np.abs(self.y - dy) <= r) & np.isin(self.z - dz, dzs) & (self.level > 0)
            got = np.flatnonzero(m)
            if len(got) >= min_count:
                break
        return got

    def band(self, idx):
        """(lo, hi, level, top names, average experience) of the monsters at idx, None when there are none"""
        if not len(idx):
            return None
        np = self.np
        names, counts = np.unique(self.n[idx], return_counts=True)
        levels = {int(n): int(self.level[idx][self.n[idx] == n][0]) for n in names}
        lo, hi, med = HO.band([(levels[int(n)], int(c)) for n, c in zip(names, counts)])
        top = sorted(zip(counts.tolist(), [self.names[int(n)] for n in names]), key=lambda t: (-t[0], t[1]))[:3]
        return lo, hi, med, [n for _c, n in top], float(self.exp[idx].mean())

    def density(self, pos, walkable):
        """monsters per 100 walkable tiles within DENSITY_R of pos on its floor (0 without walkable tiles)"""
        np = self.np
        x, y, z = pos
        m = (np.abs(self.x - x) <= DENSITY_R) & (np.abs(self.y - y) <= DENSITY_R) & (self.z == z)
        tiles = walkable(x - DENSITY_R, y - DENSITY_R, x + DENSITY_R, y + DENSITY_R, z)
        return 100.0 * int(m.sum()) / tiles if tiles else 0.0


def monster_tables(data_dir):
    """({name: level}, {name: experience}) of the monster definitions (gen_bounty_pool.py's level estimate)"""
    import gen_bounty_pool as B
    mons = B.load_monsters(data_dir)
    return {k: B.estimate_level(m) for k, m in mons.items()}, {k: m['exp'] for k, m in mons.items()}


def spawn_points(map_path):
    stem = map_path[:-5] if map_path.endswith('.otbm') else map_path
    path = stem + '-spawn.xml'
    if not os.path.isfile(path):
        raise AuditError('no spawn file %s' % path)
    return HO.spawn_points(open(path, encoding='latin-1').read())


# ------------------------------------------------------------------------------------------------ the map
class Ground:
    """counting walkable tiles on the map: ground ids and blocking ids (items.otb), tile stacks from otbm.py"""

    def __init__(self, m, kinds):
        self.m, self.k = m, kinds

    def count(self, x0, y0, x1, y1, z):
        n = 0
        for i in self.m.rect(x0, y0, x1, y1, z):
            st = [int(s) for s in self.m.stack(int(i))]
            if st and st[0] in self.k.ground and not any(s in self.k.block for s in st):
                n += 1
        return n


# ------------------------------------------------------------------------------------------------ verdict
def verdict(src, dst, th=THRESHOLDS):
    """'ok' / 'danger' / 'extreme' for a transition: src and dst are dict(level, exp, density); dst None: no monsters"""
    if not dst or not dst.get('level'):
        return 'ok'
    s, d = max(src['level'], th['source_floor']), dst['level']
    if d >= th['extreme'] * s and d - s >= th['extreme_min_step']:
        return 'extreme'
    if d >= th['level'] * s and d - s >= th['level_min_step']:
        return 'danger'
    if d > th['soft_level'] * s and d - s >= th['soft_min_step']:
        if dst['exp'] > th['exp'] * max(src['exp'], 1.0):
            return 'danger'
        if dst['density'] > th['density'] * max(src['density'], 1.0):
            return 'danger'
    return 'ok'


def cluster(landings, radius=GROUP_R):
    """{landing: group number from 1}: landings on a floor within `radius` tiles (a chain) are one destination"""
    keys = sorted(set(landings), key=lambda p: (p[2], p[0], p[1]))
    parent = {k: k for k in keys}

    def find(k):
        while parent[k] != k:
            parent[k] = parent[parent[k]]
            k = parent[k]
        return k
    for i, a in enumerate(keys):
        for b in keys[i + 1:]:
            if b[2] != a[2]:
                break
            if b[0] - a[0] > radius:
                continue
            if abs(b[1] - a[1]) <= radius:
                parent[find(b)] = find(a)
    roots = sorted({find(k) for k in keys}, key=lambda p: (p[2], p[0], p[1]))
    num = {r: i + 1 for i, r in enumerate(roots)}
    return {k: num[find(k)] for k in keys}


def level_label(n):
    """the level shown in a warning: down to a multiple of 5"""
    return max(5, int(n) // 5 * 5)


# ------------------------------------------------------------------------------------------------ the scan
def teleport_ids(db, items_xml=None):
    """item ids of teleports: otb group 7 and the items.xml entries of type teleport (check_hunt_returns.py does the same)"""
    import numpy as np
    ids = {int(i) for i in np.flatnonzero(db.group == TELEPORT_GROUP)}
    if items_xml and os.path.isfile(items_xml):
        text = open(items_xml, encoding='latin-1').read()
        for mm in re.finditer(r'<item\b([^>]*?)>(.*?)</item>', text, re.S):
            if re.search(r'key="type"\s+value="teleport"', mm.group(2)):
                a = dict(re.findall(r'(\w+)="([^"]*)"', mm.group(1)))
                if 'id' in a:
                    ids.add(int(a['id']))
    return ids


def find_transitions(m, kinds, db, items_xml=None):
    """[dict(pos, kind, item, land)]: teleports with a destination, floor changes and use floor changes"""
    import otbm
    out = []
    for ti, iid, dest in otbm.teleports(m, teleport_ids(db, items_xml)):
        if tuple(dest) == (0, 0, 0):
            continue
        p = (int(m.tiles['x'][ti]), int(m.tiles['y'][ti]), int(m.tiles['z'][ti]))
        out.append(dict(pos=p, kind='teleport', item=iid, land=tuple(int(v) for v in dest)))
    world = CD.MapWorld(m)
    for p, ids, r in CD.changes(kinds, world, CD.positions_with_changes(m, kinds)):
        if r['dead']:
            continue
        out.append(dict(pos=p, kind='%s/%s' % (kinds.label(ids[0]), r['dir']), item=ids[0], land=r['land']))
    return sorted(out, key=lambda t: (t['pos'], t['item']))


def edge_distance(spawns, trans):
    """[distance in tiles from each transition to the nearest spawn on its floor; large when none]"""
    np = spawns.np
    out = []
    for t in trans:
        x, y, z = t['pos']
        m = (spawns.z == z) & (np.abs(spawns.x - x) <= ATTACH) & (np.abs(spawns.y - y) <= ATTACH)
        if m.any():
            out.append(int(np.maximum(np.abs(spawns.x[m] - x), np.abs(spawns.y[m] - y)).min()))
        else:
            out.append(10 ** 6)
    return out


def describe(spawns, walkable, pos, passes=LOCAL_PASSES):
    """dict(lo, hi, level, top, exp, density) round pos; None where fewer than MIN_LOCAL known monsters spawn"""
    idx = spawns.near(pos, passes=passes, min_count=MIN_LOCAL)
    if len(idx) < MIN_LOCAL:
        return None
    got = spawns.band(idx)
    lo, hi, level, top, exp = got
    return dict(lo=lo, hi=hi, level=level, top=top, exp=exp, density=spawns.density(pos, walkable))


def named_place(hunts, pos):
    """the hall hunt whose destination is nearest to pos (same floor, within NAME_R), else None"""
    best = None
    for h in hunts:
        d = h['dest']
        if d[2] != pos[2]:
            continue
        dist = max(abs(d[0] - pos[0]), abs(d[1] - pos[1]))
        if dist <= NAME_R and (best is None or dist < best[0]):
            best = (dist, h)
    return best[1] if best else None


def audit(m, kinds, db, hunts, spawns, log=print, items_xml=None):
    """the rows of every transition in or at the edge of a monster area: dict(hunt, pos, kind, item, land, src, dst, place,
    verdict, dist). `hunt` is the hall hunt the entry belongs to (dict(name, level, ...)); an entry that is in no
    hall hunt gets an area of its own, named by its position, with the level of the monsters round the entry."""
    ground = Ground(m, kinds)
    trans = find_transitions(m, kinds, db, items_xml)
    log('%d transition(s) on the map' % len(trans))
    dist = edge_distance(spawns, trans)
    cand = [(t, d) for t, d in zip(trans, dist) if d <= ATTACH]
    log('%d at a monster area' % len(cand))
    cache, rows = {}, []
    for t, d in cand:
        src = describe(spawns, ground.count, t['pos'])
        if src is None:
            continue
        hall = named_place(hunts, t['pos'])
        if hall is not None and hall['dest'][2] == t['pos'][2] and \
                max(abs(hall['dest'][0] - t['pos'][0]), abs(hall['dest'][1] - t['pos'][1])) <= NAME_R:
            h = hall
            src['level'] = h['level']      # the hall's level (the CSV) is the hunt's level
        else:
            h = dict(id='', name='area %s' % pos_text(t['pos']), level=src['level'], lo=src['lo'], hi=src['hi'])
        if t['land'] not in cache:
            cache[t['land']] = describe(spawns, ground.count, t['land'])
        dst = cache[t['land']]
        v = verdict(src, dst)
        rows.append(dict(hunt=h, pos=t['pos'], kind=t['kind'], item=t['item'], land=t['land'], src=src, dst=dst,
                         place=named_place(hunts, t['land']), verdict=v, dist=d))
    return rows


# ------------------------------------------------------------------------------------------------ output
def pos_text(p):
    return '%d,%d,%d' % tuple(p)


def clean(name):
    return name.replace('|', '/')


def render_md(rows, hunts, th=THRESHOLDS):
    """docs/HUNT_TRANSITIONS.md (English, short sentences; the table in full for danger and extreme)"""
    n = Counter(r['verdict'] for r in rows)
    out = ['# Hunt transitions (O323)', '',
           'Owner, 2026-10-29: some low-level hunts have a hole or a portal inside them that takes the player to a place',
           'with much stronger monsters and high density. This table is the audit. It is made by',
           '`server/tools/audit_hunt_transitions.py` from the base map and spawn file, and is not run in CI.', '',
           '## How to read it', '',
           '- **Source area**: the hunt of `tools/hall_hunts.csv` the entry belongs to (within %d tiles of its destination, its hall level),' % NAME_R,
           '  else `area x,y,z` with the level of the monsters round the entry. The entry has a spawn within %d tiles.' % ATTACH,
           '- **Kind**: `teleport`, or a floor change (`hole/down`, `stairs/up`, `ladder/up`, `grate/down`).',
           '- **Destination band**: level range (low to high, the 20th to 80th percentile of the monsters round the landing)',
           '  and the median level. Same maths as the hall order.',
           '- **Density**: monsters per 100 walkable tiles within %d tiles. The source density is in brackets.' % DENSITY_R,
           '- **Verdict**: `danger` when the destination level is %.0f x the source level or more (and %d more), or, from %.1f x'
           % (th['level'], th['level_min_step'], th['soft_level']),
           '  (and %d more), when the experience per kill is over %.0f x or the density is over %.0f x.'
           % (th['soft_min_step'], th['exp'], th['density']),
           '  `extreme` is a destination %.0f x the source level or more (and %d more): a candidate for a level gate (none is added).'
           % (th['extreme'], th['extreme_min_step']),
           '  A source level under %d counts as %d (the level estimate of rats and fish is noise).' % (th['source_floor'], th['source_floor']),
           '', '## Totals', '',
           '%d transitions at a monster area: %d ok, %d danger, %d extreme.' % (len(rows), n['ok'], n['danger'], n['extreme']), '']
    by = Counter()
    for r in rows:
        if r['verdict'] != 'ok' and not r['hunt']['name'].startswith('area '):
            by[r['hunt']['name']] += 1
    if by:
        out += ['Hall hunts with a dangerous entry: ' + ', '.join('%s (%d)' % (k, v) for k, v in sorted(by.items())) + '.', '']
    areas = len({r['hunt']['name'] for r in rows if r['verdict'] != 'ok' and r['hunt']['name'].startswith('area ')})
    out += ['Dangerous entries outside every hall hunt: %d, in %d areas of their own.' % (
        sum(1 for r in rows if r['verdict'] != 'ok' and r['hunt']['name'].startswith('area ')), areas), '']
    out += ['## What was done', '',
            '- Near each `danger` and `extreme` entry the game flashes a skull-like effect every few seconds for players in view',
            '  and shows a red warning once per player and area (`hunt_warnings.lua`, `hunt_warnings_config.lua`): "Perigo:',
            '  monstros muito mais fortes adiante (nível N+)" or "Danger: much stronger monsters ahead (level N+)".',
            '- After arriving by a floor change or teleport a second red message says the player is in a level N+ area.',
            '- The entries stay. No level gate was added and no one is blocked.', '']

    def table(sel):
        lines = ['| Source area (level) | Position | Kind | Destination | Destination band (median) | Monsters | Density (source) | Verdict |',
                 '|---|---|---|---|---|---|---|---|']
        for r in sel:
            d = r['dst']
            if d:
                band = '%d-%d (%d)' % (d['lo'], d['hi'], d['level'])
                mons = ', '.join(clean(x) for x in d['top'])
                dens = '%.1f (%.1f)' % (d['density'], r['src']['density'])
            else:
                band, mons, dens = 'no monsters', '', '0 (%.1f)' % r['src']['density']
            where = pos_text(r['land']) + (' (%s)' % clean(r['place']['name']) if r['place'] else '')
            lines.append('| %s (%d) | %s | %s | %s | %s | %s | %s | %s |' % (
                clean(r['hunt']['name']), r['hunt']['level'], pos_text(r['pos']), r['kind'], where, band, mons, dens,
                r['verdict']))
        return lines
    key = lambda r: (r['hunt']['level'], r['hunt']['name'], r['pos'], r['item'])
    bad = sorted((r for r in rows if r['verdict'] != 'ok'), key=key)
    ok = sorted((r for r in rows if r['verdict'] == 'ok'), key=key)
    out += ['## Dangerous entries (%d)' % len(bad), '']
    out += table(bad) if bad else ['None.']
    out += ['']
    if len(ok) <= ALL_ROWS_MAX:
        out += ['## Entries that are ok (%d)' % len(ok), ''] + (table(ok) if ok else ['None.']) + ['']
    else:
        c = Counter(r['kind'] for r in ok)
        out += ['## Entries that are ok (%d)' % len(ok), '',
                'Too many to list (mostly the stairs of a cave to its own next floor). By kind: ' +
                ', '.join('%s %d' % kv for kv in sorted(c.items())) + '.', '']
    out += ['## Limits', '',
            '- Only the base map and its spawn file. The planned content hunts are placed at their own origins and lead only to',
            '  their exit portal. Run the audit on the installed server\'s data folder too.',
            '- Levels are the hall\'s scale (`gen_bounty_pool.py` estimate, `baseLevelMult` applied). A level-scaled monster',
            '  uses the middle of its range.',
            '- Teleports whose target a movement script sets (an action or unique id in movements.xml) have no destination on the',
            '  map and are not in the table. Most teleport items of the base map are of that kind. Holes a player digs are not either.',
            '- Walking off a cliff edge onto a lower floor (a tile with no ground) is not a transition item and is not in the table.',
            '']
    return '\n'.join(out)


def lua_pos(p):
    return '{x = %d, y = %d, z = %d}' % tuple(p)


def render_places(rows):
    """(places Lua text, the group levels): one line per dangerous entry"""
    bad = sorted((r for r in rows if r['verdict'] != 'ok'), key=lambda r: (r['pos'], r['item']))
    groups = cluster([r['land'] for r in bad])
    lv = {}
    for r in bad:
        g = groups[r['land']]
        lv[g] = min(lv.get(g, 10 ** 9), r['dst']['lo'] if r['dst'] and r['dst']['lo'] else r['dst']['level'])
    lines = []
    for i, r in enumerate(bad, 1):
        g = groups[r['land']]
        lines.append('\t{id = %d, kind = "%s", pos = %s, to = %s, group = %d, level = %d, from = "%s", verdict = "%s"},' % (
            i, 'teleport' if r['kind'] == 'teleport' else 'floor', lua_pos(r['pos']), lua_pos(r['land']),
            g, level_label(lv[g]), clean(r['hunt']['name']).replace('"', ''), r['verdict']))
    return '\n'.join(lines), {g: level_label(v) for g, v in lv.items()}


def write_config(path, rows):
    """hunt_warnings_config.lua: the file's own numbers and texts stay, the `places` between the markers are replaced"""
    text = open(path, encoding='utf-8').read()
    a, b = text.find('-- BEGIN places'), text.find('-- END places')
    if a < 0 or b < 0 or b < a:
        raise AuditError('%s: no `-- BEGIN places` / `-- END places` markers' % path)
    body, _lv = render_places(rows)
    head = '-- BEGIN places (written by server/tools/audit_hunt_transitions.py; %d)\n' % len(
        [r for r in rows if r['verdict'] != 'ok'])
    new = text[:a] + head + 'C.places = {\n' + (body + '\n' if body else '') + '}\n' + text[b:]
    if new != text:
        open(path, 'w', encoding='utf-8', newline='\n').write(new)
    return new != text


def write_csv(path, rows):
    with open(path, 'w', encoding='utf-8', newline='') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(['hunt', 'level', 'x', 'y', 'z', 'kind', 'item', 'land_x', 'land_y', 'land_z', 'dst_lo', 'dst_hi', 'dst_level',
                    'dst_exp', 'dst_density', 'src_density', 'verdict'])
        for r in rows:
            d = r['dst'] or {}
            w.writerow([r['hunt']['name'], r['hunt']['level']] + list(r['pos']) + [r['kind'], r['item']] + list(r['land']) +
                       [d.get('lo', ''), d.get('hi', ''), d.get('level', ''), '%.0f' % d['exp'] if d else '',
                        '%.1f' % d['density'] if d else '', '%.1f' % r['src']['density'], r['verdict']])


# ------------------------------------------------------------------------------------------------ run
def run(data_dir, map_path=None, md=None, lua=None, csv_path=None, hunts_csv=HUNTS_CSV, log=print):
    import otbm
    from itemdb import ItemDB
    if map_path is None:
        import patch_base_towns
        map_path = patch_base_towns.map_path(data_dir)
    if not map_path or not os.path.isfile(map_path):
        raise AuditError('no world map in %s/world' % data_dir)
    otb = os.path.join(data_dir, 'items', 'items.otb')
    xml = os.path.join(data_dir, 'items', 'items.xml')
    if not os.path.isfile(otb):
        raise AuditError('no %s' % otb)
    xml = xml if os.path.isfile(xml) else None
    kinds = CD.Kinds.from_files(otb, xml)
    db = ItemDB(otb, xml)
    log('reading %s ...' % map_path)
    m = otbm.load_otbm(map_path)
    levels, exps = monster_tables(data_dir)
    spawns = Spawns(spawn_points(map_path), levels, exps)
    hunts = read_hunts(hunts_csv)
    log('%d hunts, %d spawned monsters' % (len(hunts), len(spawns.x)))
    rows = audit(m, kinds, db, hunts, spawns, log, xml)
    n = Counter(r['verdict'] for r in rows)
    log('%d transition(s) at a hunt: %d ok, %d danger, %d extreme' % (len(rows), n['ok'], n['danger'], n['extreme']))
    if md:
        open(md, 'w', encoding='utf-8', newline='\n').write(render_md(rows, hunts))
        log('wrote %s' % md)
    if lua:
        log('%s %s' % (lua, 'updated' if write_config(lua, rows) else 'unchanged'))
    if csv_path:
        write_csv(csv_path, rows)
    return rows


def main(argv):
    opts, pos, i = {}, [], 0
    while i < len(argv):
        a = argv[i]
        if a in ('--map', '--md', '--lua', '--csv', '--hunts'):
            if i + 1 >= len(argv):
                print('%s needs a value' % a)
                return 1
            opts[a] = argv[i + 1]
            i += 1
        elif a == '--quiet':
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
        run(pos[0], map_path=opts.get('--map'), md=opts.get('--md'), lua=opts.get('--lua'), csv_path=opts.get('--csv'),
            hunts_csv=opts.get('--hunts', HUNTS_CSV), log=(lambda *_: None) if opts.get('--quiet') else print)
    except (AuditError, HO.HallError, OSError) as e:
        print('refused: %s' % e)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
