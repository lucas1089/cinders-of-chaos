#!/usr/bin/env python3
"""The area planner's knowledge base: approved plans and their stats in a small SQLite file outside git
(docs/MAP_GUIDE.md "Area planner"). Path: $AREAPLAN_KB, else $XDG_DATA_HOME/cinders-of-chaos/area_planner/kb.sqlite3
(~/.local/share/... ; %LOCALAPPDATA% on Windows). `approve` adds a plan, `suggest` and `similar` read it.
"""
import hashlib, json, math, os, sqlite3, statistics, time

import area_plan_core as C


def kb_path(env=None):
    env = os.environ if env is None else env
    if env.get('AREAPLAN_KB'):
        return env['AREAPLAN_KB']
    base = env.get('XDG_DATA_HOME') or env.get('LOCALAPPDATA') or os.path.join(os.path.expanduser('~'), '.local', 'share')
    return os.path.join(base, 'cinders-of-chaos', 'area_planner', 'kb.sqlite3')


def connect(path=None):
    path = path or kb_path()
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    db = sqlite3.connect(path)
    db.execute('''CREATE TABLE IF NOT EXISTS plans (
        hash TEXT PRIMARY KEY, id TEXT, name TEXT, biome TEXT, level_lo INTEGER, level_hi INTEGER,
        width INTEGER, height INTEGER, floors INTEGER, zones INTEGER, monsters INTEGER, walkable INTEGER,
        per100 REAL, per_screen REAL, entry_to_boss INTEGER, farthest INTEGER, approved_at INTEGER, note TEXT,
        plan_json TEXT, stats_json TEXT)''')
    return db


def plan_hash(plan):
    return hashlib.sha256(json.dumps(plan, sort_keys=True).encode()).hexdigest()[:16]


def approve(db, plan, stats, note='', now=None):
    """store an approved plan and its compiled stats (the same plan again replaces its row)"""
    h = plan_hash(plan)
    per_screen = statistics.mean(f['per_screen'] for f in stats['floors']) if stats['floors'] else 0
    db.execute('INSERT OR REPLACE INTO plans VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
               (h, plan['id'], plan['name'], plan['biome'], plan['level'][0], plan['level'][1], plan['size'][0],
                plan['size'][1], plan['floors'], len(plan['zones']), stats['monsters'], stats['walkable'], stats['per100'],
                round(per_screen, 2), stats.get('entry_to_boss'), stats.get('farthest_zone'),
                int(now if now is not None else time.time()), note, json.dumps(plan, sort_keys=True),
                json.dumps(stats, sort_keys=True)))
    db.commit()
    return h


def rows(db, where='', args=()):
    cur = db.execute('SELECT hash, id, name, biome, level_lo, level_hi, width, height, floors, zones, monsters, walkable, '
                     'per100, per_screen, entry_to_boss, farthest, plan_json FROM plans ' + where + ' ORDER BY approved_at, hash', args)
    keys = [d[0] for d in cur.description]
    return [dict(zip(keys, r)) for r in cur.fetchall()]


def suggest(db, biome, lo, hi):
    """typical numbers of the approved plans of a biome near a level band, the monsters they used, and the catalogue's
    monsters of the band. Returns a dict (works on an empty base too)."""
    _t, plo, phi = C.tier_window(lo, hi)
    same = [r for r in rows(db, 'WHERE biome = ?', (biome,))]
    near = [r for r in same if r['level_hi'] >= lo - 100 and r['level_lo'] <= hi + 100] or same
    out = dict(biome=biome, level=[lo, hi], pick=[plo, phi], approved=len(near))
    if near:
        med = lambda k: statistics.median(r[k] for r in near if r[k] is not None) if any(r[k] is not None for r in near) else None
        out['typical'] = dict(width=med('width'), height=med('height'), floors=med('floors'), zones=med('zones'),
                              monsters=med('monsters'), per100=med('per100'), per_screen=med('per_screen'),
                              entry_to_boss=med('entry_to_boss'))
        used = {}
        for r in near:
            for s in json.loads(r['plan_json']).get('spawns', []):
                used[s['monster']] = used.get(s['monster'], 0) + s['count']
        out['monsters_used'] = sorted(used, key=lambda m: (-used[m], m))[:10]
        out['examples'] = [r['id'] for r in near[-5:]]
    else:
        # nothing approved yet: the guide's numbers (docs/MAP_GUIDE.md "Hunting areas")
        out['typical'] = dict(width=72, height=60, floors=1, zones=5, per100=3.0, note='no approved plan of this biome yet: '
                              'the map guide\'s bands (1.5-5 monsters per 100 tiles, rooms 25-70 tiles, a loop)')
    if plo is not None:
        pool = [m for m in C.monsters().values() if m['level'] and plo <= m['level'] <= phi and not m['boss']]
        pool.sort(key=lambda m: (abs(m['level'] - (lo + hi) // 2), m['name']))
        out['monsters_in_band'] = ['%s (%d)' % (m['name'], m['level']) for m in pool[:15]]
        bosses = [m for m in C.monsters().values() if m['boss'] and m['level'] and plo <= m['level'] <= phi * 1.5]
        bosses.sort(key=lambda m: (abs(m['level'] - hi), m['name']))
        out['bosses_in_band'] = ['%s (%d)' % (m['name'], m['level']) for m in bosses[:8]]
    return out


def features(biome, lo, hi, w, h, floors, zones, per100):
    return (biome, math.log(max(1, lo)), math.log(max(1, hi)), w / 40.0, h / 40.0, floors, zones / 4.0, per100)


def distance(a, b):
    d = 0.0 if a[0] == b[0] else 2.0
    return d + math.sqrt(sum((x - y) ** 2 for x, y in zip(a[1:], b[1:])))


def similar(db, plan, stats=None, n=5):
    """the n approved plans closest to this one (biome, level band, size, floors, zones, density)"""
    per100 = stats['per100'] if stats else 3.0
    me = features(plan['biome'], plan['level'][0], plan['level'][1], plan['size'][0], plan['size'][1], plan['floors'],
                  len(plan['zones']), per100)
    mine = plan_hash(plan)
    out = []
    for r in rows(db):
        if r['hash'] == mine:
            continue
        f = features(r['biome'], r['level_lo'], r['level_hi'], r['width'], r['height'], r['floors'], r['zones'], r['per100'])
        out.append((round(distance(me, f), 3), r))
    out.sort(key=lambda x: (x[0], x[1]['hash']))
    return out[:n]
