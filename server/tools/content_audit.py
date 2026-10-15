#!/usr/bin/env python3
"""Hunting content per level band, from the spawn file that is really loaded (docs/CONTENT.md).

usage: python3 -I content_audit.py DATA_DIR [--spawn PATH] [--map PATH] [--json OUT] [--top N]

DATA_DIR is an installed server's data folder (at least the install steps files, monsternames, lategame, monsters and
spawns, so the spawn file carries our monster names and the late game entries). The monster levels come from our
bounty pool (data/scripts/chaos/bounty_pool.lua, the same estimate the bounty board and the area planner use); a
monster missing there gets gen_bounty_pool.py's estimate from DATA_DIR's monster files.

A hunt is a group of spawn entries on one floor where each entry is at most LINK tiles (12) from another one, with at
least MIN_ENTRIES (10) hostile monsters that give experience. Its level is the median level of its entries, weighted by
the entry count. A hunt serves a band when at least SHARE (20 %) of its entries, and at least MIN_ENTRIES, are monsters
of that band, so a mixed hunt (the late game rows of tools/late_game_spawns.csv replace a share of an older hunt) counts
for each band it really serves. Capacity is how many parties hunt it at once without sharing a screen: one party per
PARTY_ENTRIES (30) entries of the band, at least 1. The generated areas (areagen_config.lua) and the planned areas
(server/tools/areaplan/plans/) are added from their own data, marked as such.

The output is a table per band (hunts, spawn entries, parties at once, the biggest hunts with their nearest town) and,
with --json, every hunt. Read only: it writes nothing but --json.
"""
import json, os, re, statistics, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.normpath(os.path.join(HERE, '..'))
sys.path.insert(0, HERE)

LINK = 12
MIN_ENTRIES = 10
PARTY_ENTRIES = 30
SHARE = 0.2
BANDS = [(1, 19), (20, 49), (50, 99), (100, 199), (200, 299), (300, 499), (500, 699), (700, 999), (1000, 99999)]


def band_label(b):
    return '%d+' % b[0] if b[1] > 9999 else '%d-%d' % (b[0], b[1] + 1)


def band_of(level):
    for b in BANDS:
        if b[0] <= level <= b[1]:
            return b
    return BANDS[0]


def pool_levels():
    text = open(os.path.join(SERVER, 'data', 'scripts', 'chaos', 'bounty_pool.lua'), encoding='utf-8').read()
    cut = text.find('bosses = {')
    out = {}
    for m in re.finditer(r'\{name = "([^"]+)", level = (\d+), exp = (\d+)', text):
        out[m.group(1).lower()] = (int(m.group(2)), int(m.group(3)), m.start() > cut >= 0)
    return out


def data_levels(data_dir):
    import gen_bounty_pool as G
    out = {}
    for key, m in G.load_monsters(data_dir).items():
        ok = m['attackable'] and m['hostile'] and m['exp'] > 0
        out[key] = (G.estimate_level(m), m['exp'] if ok else 0, m['boss'])
    return out


def parse_spawns(text):
    """[(name, x, y, z)]"""
    out = []
    for blk in re.finditer(r'<spawn\s([^>]*)>(.*?)</spawn>', text, re.S):
        head = blk.group(1)
        g = lambda k: int(re.search(r'\b%s="(-?\d+)"' % k, head).group(1))
        cx, cy, cz = g('centerx'), g('centery'), g('centerz')
        for m in re.finditer(r'<monster\s([^>]*?)/?>', blk.group(2)):
            t = m.group(1)
            n = re.search(r'\bname="([^"]+)"', t)
            if not n:
                continue
            v = lambda k: int((re.search(r'\b%s="(-?\d+)"' % k, t) or [0, 0])[1])
            z = re.search(r'\bz="(-?\d+)"', t)
            out.append((n.group(1), cx + v('x'), cy + v('y'), int(z.group(1)) if z else cz))
    return out


def cluster(points):
    """points [(x, y, z)] -> list of index lists (single linkage within LINK tiles, same floor)"""
    parent = list(range(len(points)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    grid = {}
    for i, (x, y, z) in enumerate(points):
        grid.setdefault((x // LINK, y // LINK, z), []).append(i)
    for (gx, gy, z), idx in grid.items():
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                other = grid.get((gx + dx, gy + dy, z))
                if not other:
                    continue
                for i in idx:
                    xi, yi, _ = points[i]
                    for j in other:
                        if j > i and max(abs(points[j][0] - xi), abs(points[j][1] - yi)) <= LINK:
                            a, b = find(i), find(j)
                            if a != b:
                                parent[a] = b
    groups = {}
    for i in range(len(points)):
        groups.setdefault(find(i), []).append(i)
    return list(groups.values())


def weighted_median(values):
    return int(statistics.median_low(values)) if values else 0


def towns_of(map_path):
    if not map_path or not os.path.exists(map_path):
        return []
    sys.path.insert(0, os.path.join(SERVER, '..', 'tools', 'map'))
    import otbm
    names = {}
    csv_path = os.path.join(HERE, 'base_towns.csv')
    for line in open(csv_path, encoding='utf-8').read().splitlines()[1:]:
        p = line.split(',')
        if len(p) > 1:
            names[int(p[0])] = p[1]
    m = otbm.load_otbm(map_path)
    return [(names.get(tid, 'town %d' % tid), pos) for tid, _n, pos in m.towns if tid in names]


def nearest_town(towns, x, y):
    if not towns:
        return ''
    return min(towns, key=lambda t: (t[1][0] - x) ** 2 + (t[1][1] - y) ** 2)[0]


def lua_areas():
    """generated areas of areagen_config.lua: [(name, lo, hi, kind)]"""
    text = open(os.path.join(SERVER, 'data', 'scripts', 'chaos', 'areagen_config.lua'), encoding='utf-8').read()
    out = []
    for m in re.finditer(r'id = "(\w+)", name = "([^"]+)", kind = "(\w+)".*?level = \{(\d+), (\d+)\}', text, re.S):
        out.append(dict(name=m.group(2), level=[int(m.group(4)), int(m.group(5))], kind='generated ' + m.group(3)))
    return out


def planned_areas():
    out = []
    d = os.path.join(HERE, 'areaplan', 'plans')
    if os.path.isdir(d):
        for f in sorted(os.listdir(d)):
            if f.endswith('.json'):
                p = json.load(open(os.path.join(d, f), encoding='utf-8'))
                out.append(dict(name=p['name'], level=p['level'], kind='planned ' + p['biome'],
                                entries=sum(s.get('count', 1) for s in p.get('spawns', []))))
    return out


def audit(data_dir, spawn_path=None, map_path=None):
    if not spawn_path:
        cfg = os.path.join(data_dir, '..', 'config.lua')
        mn = re.search(r'^\s*mapName\s*=\s*"([^"]+)"', open(cfg, encoding='utf-8', errors='replace').read(), re.M)
        spawn_path = os.path.join(data_dir, 'world', mn.group(1) + '-spawn.xml')
        map_path = map_path or os.path.join(data_dir, 'world', mn.group(1) + '.otbm')
    levels = data_levels(data_dir)
    levels.update(pool_levels())
    entries = []
    for name, x, y, z in parse_spawns(open(spawn_path, encoding='utf-8', errors='replace').read()):
        lv = levels.get(name.lower())
        if lv and lv[1] > 0 and not lv[2]:
            entries.append((name, x, y, z, lv[0]))
    groups = cluster([(e[1], e[2], e[3]) for e in entries])
    towns = towns_of(map_path)
    hunts = []
    for g in groups:
        if len(g) < MIN_ENTRIES:
            continue
        rows = [entries[i] for i in g]
        lv = weighted_median(sorted(r[4] for r in rows))
        count = {}
        for r in rows:
            count[r[0]] = count.get(r[0], 0) + 1
        xs, ys = [r[1] for r in rows], [r[2] for r in rows]
        cx, cy = sum(xs) // len(xs), sum(ys) // len(ys)
        per = {}
        for r in rows:
            k = band_label(band_of(r[4]))
            per[k] = per.get(k, 0) + 1
        hunts.append(dict(level=lv, entries=len(rows), band_entries=per, parties=max(1, len(rows) // PARTY_ENTRIES), x=cx, y=cy,
                          z=rows[0][3], town=nearest_town(towns, cx, cy), kind='world',
                          monsters=[n for n, _c in sorted(count.items(), key=lambda kv: (-kv[1], kv[0]))[:3]]))
    for a in lua_areas() + planned_areas():
        lv = (a['level'][0] + a['level'][1]) // 2
        hunts.append(dict(level=lv, entries=a.get('entries', 0), parties=1, band_entries={band_label(band_of(lv)): 1},
                          kind=a['kind'], name=a['name'], monsters=[]))
    return hunts


def summary(hunts, top=3):
    rows = []
    for b in BANDS:
        k = band_label(b)
        hs = [h for h in hunts if h['band_entries'].get(k, 0) >= (1 if h['kind'] != 'world' else
                                                                 max(MIN_ENTRIES, SHARE * h['entries']))]
        world = [h for h in hs if h['kind'] == 'world']
        world.sort(key=lambda h: -h['band_entries'][k])
        rows.append(dict(band=k, hunts=len(world), entries=sum(h['band_entries'][k] for h in world),
                         parties=sum(max(1, h['band_entries'][k] // PARTY_ENTRIES) for h in world),
                         extra=[h['name'] + ' (' + h['kind'] + ')' for h in hs if h['kind'] != 'world'],
                         top=['%s near %s (z %d, %d entries)' % (' / '.join(h['monsters']), h['town'] or '?', h['z'],
                                                               h['band_entries'][k]) for h in world[:top]]))
    return rows


def main(argv):
    args = list(argv)

    def opt(name):
        if name in args:
            k = args.index(name)
            v = args[k + 1]
            del args[k:k + 2]
            return v
        return None
    spawn, mp, js, top = opt('--spawn'), opt('--map'), opt('--json'), int(opt('--top') or 3)
    if len(args) != 1:
        print(__doc__)
        return 2
    hunts = audit(args[0], spawn, mp)
    rows = summary(hunts, top)
    print('| band | hunts | spawn entries of the band | parties at once | other areas |')
    print('|---|---|---|---|---|')
    for r in rows:
        print('| %s | %d | %d | %d | %s |' % (r['band'], r['hunts'], r['entries'], r['parties'], ', '.join(r['extra']) or '-'))
    for r in rows:
        print('\n%s: %s' % (r['band'], '; '.join(r['top']) or 'none'))
    if js:
        with open(js, 'w', encoding='utf-8') as f:
            json.dump(dict(bands=rows, hunts=hunts), f, indent=1, sort_keys=True)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
