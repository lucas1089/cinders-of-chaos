#!/usr/bin/env python3
"""Write the points of interest of the map markers (server/README.md "Map markers": poi.lua, client game_mapmarkers).

usage: python3 -I gen_poi.py SERVER_DIR [--map PATH] [--out PATH] [--check] [--quiet]

SERVER_DIR is an installed server folder (config.lua and data/; run after the towns, npcnames and worldtexts steps, as
install_all.py's step "poi" does). The result is SERVER_DIR/data/chaos_poi.lua (or --out): a Lua table
    return {version = "<sha1 of the marks>", marks = {{k = kind, x, y, z, n = name, r = 0 | 1}, ...}}
r = 0: always on the map; r = 1: discovered (shown once the character came near it, poi.lua). --check compares with the
file there and exits 1 when it differs (nothing written). --map reads that map instead of SERVER_DIR's (install_all.py
--dry-run: its copy has no map).

What is read, and the kinds written:
  temple   the towns node of the map (the temple of every town). The name is the town's name from tools/base_towns.csv
           (by town id), else the name in the map once the towns step renamed it; a town without a known new name is
           "Temple" alone.
  depot    the depot lockers of the map (items.xml type "depot"): lockers within DEPOT_JOIN tiles on one floor are one
           depot, kept when it has DEPOT_MIN lockers at least, named after the nearest town.
  craft    the base crafting tables (action ids 38820-38826 on the map), tables within 20 tiles as one "Crafting hall"
           (three or more) or one table named after its kind.
  shop / travel / bank / bless   the NPCs of the map's spawn file whose script or file offers that service (a travel
           module, deposit and withdraw, the blessings, a shop); r = 0 within TOWN_RADIUS of a temple, else r = 1.
  hunt     hunting areas: the bounty pool's monsters (data/scripts/chaos/bounty_pool.lua: name and hunting level) at the
           busiest spots of the bestiary spawn data (bestiary_spawns.lua), spots of one floor within HUNT_JOIN tiles
           merged, the level band from the middle 70 % of the spawn entries, the two most common monsters as the name;
           areas with fewer than HUNT_MIN entries are left out. r = 1.
           The band is printed as the HUNTING level: the pool level times pace_config.lua baseLevelMult (owner 2026-10-27;
           lo = max(1, lo10 * mult), hi = hi10 * mult). baseLevelMult is 1 since 2026-10-28 (O285): the pool level.
  boss     the island, raid and lair bosses of bossspawns_config.lua (their places). r = 1.
The Chaos NPCs, the portals next to the temples and the dungeons are added by poi.lua at runtime (they are placed when
the server starts).

Names: never an old-world name. Every name is checked against the rename lists (data/npc/base_npc_names.csv,
data/npc/base_world_names.csv, data/monster/base_monster_names.csv, by the sha256 of each phrase); a mark whose name
still holds an old name is left out and counted ("unrenamed").
Deterministic: the same inputs give the same bytes. Needs only the standard library.
"""
import csv
import hashlib
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
sys.path.insert(0, HERE)  # python -I leaves the script's folder off sys.path

import patch_base_towns as towns_lib  # noqa: E402
from base_rename_lib import phrases, digest  # noqa: E402

ESC, START, END = 0xFD, 0xFE, 0xFF
T_AREA, T_TILE, T_HOUSETILE, T_ITEM = 4, 5, 14, 6
A_ACTION = 4
FIXED = {4: 2, 5: 2, 8: 5, 10: 2, 12: 1, 14: 1, 15: 1, 16: 4, 17: 1, 18: 4, 20: 4, 21: 4, 22: 2, 23: 4}
STRINGS = {1, 6, 7, 19, 30, 31, 32}

CRAFT_AIDS = {38820: 'Herbalist table', 38821: 'Woodcutting table', 38822: 'Mining table', 38823: 'Crafting table',
              38824: 'Jewelsmith table', 38825: 'Armorsmith table', 38826: 'Weaponsmith table'}
TOWN_RADIUS = 80      # a service NPC this close to a temple is always shown
DEPOT_JOIN = 30       # lockers of one floor this close are one depot
DEPOT_MIN = 4         # a depot has this many lockers at least (fewer: a quest or house prop)
CRAFT_JOIN = 20
HUNT_JOIN = 40
HUNT_MIN = 12         # spawn entries of a hunting area at least
HUNT_MAX = 300        # at most this many hunting areas (the biggest)
NAME_TOWN_RADIUS = 200
KIND_ORDER = ['temple', 'depot', 'craft', 'bank', 'bless', 'travel', 'shop', 'boss', 'hunt']
SERVICE_LABEL = {'travel': 'travel', 'bank': 'bank', 'bless': 'blessings', 'shop': 'shop'}
BOSS_LABEL = {'island': 'island boss', 'raid': 'raid boss', 'lair': 'boss lair'}


class PoiError(Exception):
    pass


# ------------------------------------------------------------------------------------------------ map bytes
def real(data, i):
    """data[i] is a real marker (not escaped)"""
    j = i
    while j > 0 and data[j - 1] == ESC:
        j -= 1
    return (i - j) % 2 == 0


def esc(b):
    out = bytearray()
    for c in b:
        if c in (ESC, START, END):
            out.append(ESC)
        out.append(c)
    return bytes(out)


def payload(data, i):
    """unescaped bytes from i to the next real marker"""
    out = bytearray()
    n = len(data)
    while i < n:
        c = data[i]
        if c == ESC:
            out.append(data[i + 1])
            i += 2
        elif c in (START, END):
            break
        else:
            out.append(c)
            i += 1
    return bytes(out)


def last_real(data, needle, before):
    """index of the last real occurrence of needle (starting with 0xFE) before `before`, or -1"""
    i = data.rfind(needle, 0, before)
    while i >= 0 and not real(data, i):
        i = data.rfind(needle, 0, i)
    return i


def last_node_start(data, before):
    i = data.rfind(b'\xfe', 0, before)
    while i >= 0 and not real(data, i):
        i = data.rfind(b'\xfe', 0, i)
    return i


def tile_position(data, item_at):
    """absolute (x, y, z) of the tile holding the node at item_at"""
    t = max(last_real(data, bytes([START, T_TILE]), item_at), last_real(data, bytes([START, T_HOUSETILE]), item_at))
    a = last_real(data, bytes([START, T_AREA]), t if t >= 0 else item_at)
    if t < 0 or a < 0:
        raise PoiError('item at %d is not on a tile' % item_at)
    ap, tp = payload(data, a + 2), payload(data, t + 2)
    if len(ap) < 5 or len(tp) < 2:
        raise PoiError('short tile or area node near %d' % item_at)
    bx, by, bz = struct.unpack_from('<HHB', ap, 0)
    return bx + tp[0], by + tp[1], bz


def parse_item(p):
    """unescaped item payload -> (id, {attr: value bytes}) or None"""
    if len(p) < 2:
        return None
    attrs, q = {}, 2
    while q < len(p):
        a = p[q]
        q += 1
        if a in FIXED:
            n = FIXED[a]
            if q + n > len(p):
                return None
            attrs[a] = p[q:q + n]
            q += n
        elif a in STRINGS:
            if q + 2 > len(p):
                return None
            ln = struct.unpack_from('<H', p, q)[0]
            attrs[a] = p[q + 2:q + 2 + ln]
            q += 2 + ln
        else:
            return None
    return struct.unpack_from('<H', p, 0)[0], attrs


def find_items(data, ids):
    """[(id, (x, y, z))] of every item node with one of these ids"""
    out = []
    for iid in sorted(ids):
        needle = bytes([START, T_ITEM]) + esc(struct.pack('<H', iid))
        i = data.find(needle)
        while i >= 0:
            if real(data, i):
                out.append((iid, tile_position(data, i)))
            i = data.find(needle, i + 1)
    return out


def find_action_items(data, aids):
    """[(action id, (x, y, z))] of every item node carrying one of these action ids"""
    out = []
    for aid in sorted(aids):
        needle = bytes([A_ACTION]) + esc(struct.pack('<H', aid))
        i = data.find(needle)
        while i >= 0:
            s = last_node_start(data, i)
            if s >= 0 and data[s + 1] == T_ITEM:
                parsed = parse_item(payload(data, s + 2))
                if parsed and struct.unpack('<H', parsed[1].get(A_ACTION, b'\0\0'))[0] == aid:
                    pos = tile_position(data, s)
                    if (aid, pos) not in out:
                        out.append((aid, pos))
            i = data.find(needle, i + 1)
    return out


# ------------------------------------------------------------------------------------------------ data files
def read_text(path):
    with open(path, encoding='utf-8', errors='replace') as f:
        return f.read()


def depot_ids(items_xml):
    ids = set()
    for m in re.finditer(r'<item\b([^>]*?)(/?)>(.*?)(?=<item\b|</items>)', read_text(items_xml), re.S):
        attrs, body = m.group(1), m.group(3)
        if not re.search(r'<attribute\s+key="type"\s+value="depot"', body, re.I):
            continue
        one = re.search(r'\bid="(\d+)"', attrs)
        lo, hi = re.search(r'\bfromid="(\d+)"', attrs), re.search(r'\btoid="(\d+)"', attrs)
        if one:
            ids.add(int(one.group(1)))
        elif lo and hi:
            ids.update(range(int(lo.group(1)), int(hi.group(1)) + 1))
    return ids


def spawn_npcs(spawn_xml):
    """[(name, x, y, z)] of the NPC entries of a spawn file"""
    out = []
    text = read_text(spawn_xml)
    for sm in re.finditer(r'<spawn\b([^>]*)>(.*?)</spawn>', text, re.S):
        head = sm.group(1)
        cx, cy, cz = (re.search(r'\bcenter%s="(-?\d+)"' % k, head) for k in 'xyz')
        if not (cx and cy and cz):
            continue
        for nm in re.finditer(r'<npc\b([^>]*)/?>', sm.group(2)):
            a = nm.group(1)
            name, x, y = (re.search(r'\b%s="([^"]*)"' % k, a) for k in ('name', 'x', 'y'))
            if name and x and y:
                out.append((name.group(1), int(cx.group(1)) + int(x.group(1)), int(cy.group(1)) + int(y.group(1)),
                            int(cz.group(1))))
    return out


def npc_services(npc_dir):
    """npc name (lower case) -> service kind of the NPC files (travel, bank, bless, shop)"""
    out = {}
    if not os.path.isdir(npc_dir):
        return out
    for fname in sorted(os.listdir(npc_dir)):
        if not fname.endswith('.xml'):
            continue
        xml = read_text(os.path.join(npc_dir, fname))
        nm = re.search(r'<npc\b[^>]*\bname="([^"]+)"', xml)
        if not nm:
            continue
        sc = re.search(r'<npc\b[^>]*\bscript="([^"]+)"', xml)
        script = ''
        if sc:
            for cand in (os.path.join(npc_dir, 'scripts', sc.group(1)), os.path.join(npc_dir, sc.group(1))):
                if os.path.isfile(cand):
                    script = read_text(cand)
                    break
        kind = None
        if 'StdModule.travel' in script:
            kind = 'travel'
        elif re.search(r"['\"]deposit['\"]", script) and re.search(r"['\"]withdraw['\"]", script):
            kind = 'bank'
        elif 'StdModule.bless' in script:
            kind = 'bless'
        elif re.search(r'key="module_shop"\s+value="1"|key="shop_buyable"|key="shop_sellable"', xml) or \
                re.search(r'ShopModule|addBuyableItem|addSellableItem', script):
            kind = 'shop'
        if kind:
            out[nm.group(1).strip().lower()] = kind
    return out


def lua_list(text, pattern):
    return [m.groups() for m in re.finditer(pattern, text)]


def hunting_data(chaos_dir):
    """(name -> level, name -> [(x, y, z, entries)]) from the bounty pool and the bestiary spawn data"""
    pool = read_text(os.path.join(chaos_dir, 'bounty_pool.lua'))
    hunt = pool.split('bosses =')[0]
    levels = {}
    for name, lv in lua_list(hunt, r'\{name = "([^"]+)", level = (\d+)'):
        levels[name] = int(lv)
    spawns = {}
    text = read_text(os.path.join(chaos_dir, 'bestiary_spawns.lua'))
    for name, areas in lua_list(text, r'\["([^"]+)"\] = \{spawns = \d+, areas = \{(.*?)\}\}'):
        spawns[name] = [tuple(int(v) for v in a) for a in re.findall(r'\{(\d+), (\d+), (\d+), (\d+)(?=\}|$)', areas)]
    return levels, spawns


def base_level_mult(chaos_dir):
    """pace_config.lua baseLevelMult: the hunting level of a monster is the bounty pool level times it (the marks print
    the hunting level, owner 2026-10-27); the installed copy first, else the repo's"""
    for d in (chaos_dir, os.path.join(SERVER, 'data', 'scripts', 'chaos')):
        f = os.path.join(d, 'pace_config.lua')
        if os.path.isfile(f):
            m = re.search(r'\bbaseLevelMult\s*=\s*(\d+(?:\.\d+)?)', read_text(f))
            if m:
                v = float(m.group(1))
                return int(v) if v == int(v) else v
    raise PoiError('pace_config.lua baseLevelMult not found')


def boss_spots(chaos_dir):
    text = read_text(os.path.join(chaos_dir, 'bossspawns_config.lua'))
    out = []
    pat = (r'\{key = "([^"]+)", category = "(island|raid|lair)", name = "([^"]+)"(?:(?!\{key =).)*?'
           r'pos = \{x = (\d+), y = (\d+), z = (\d+)\}')
    for key, cat, name, x, y, z in re.findall(pat, text, re.S):
        out.append((cat, name, int(x), int(y), int(z)))
    return out


def read_hashes(paths):
    out = set()
    for p in paths:
        if os.path.isfile(p):
            with open(p, encoding='utf-8', newline='') as f:
                for row in csv.DictReader(f):
                    key = (row.get('sha256') or '').strip().lower()
                    if re.match(r'^[0-9a-f]{64}$', key):
                        out.add(key)
    return out


def read_town_names(path):
    out = {}
    if os.path.isfile(path):
        with open(path, encoding='utf-8', newline='') as f:
            for row in csv.DictReader(f):
                if (row.get('id') or '').strip().isdigit() and (row.get('name') or '').strip():
                    out[int(row['id'])] = row['name'].strip()
    return out


# ------------------------------------------------------------------------------------------------ pure parts
def cheb(a, b):
    return max(abs(a[0] - b[0]), abs(a[1] - b[1]))


def cluster(points, join):
    """greedy clusters of (x, y, z, weight, payload) on one floor within `join` tiles of a cluster's centre, heaviest
    first. -> [{x, y, z, w, items}] with the weighted centre (rounded)"""
    groups = []
    for p in sorted(points, key=lambda q: (-q[3], q[2], q[0], q[1])):
        x, y, z, w = p[0], p[1], p[2], max(p[3], 1)
        for g in groups:
            if g['z'] == z and cheb((g['sx'] / g['w'], g['sy'] / g['w']), (x, y)) <= join:
                g['sx'] += x * w
                g['sy'] += y * w
                g['w'] += w
                g['items'].append(p)
                break
        else:
            groups.append({'z': z, 'sx': x * w, 'sy': y * w, 'w': w, 'items': [p]})
    out = []
    for g in groups:
        out.append({'x': int(round(g['sx'] / g['w'])), 'y': int(round(g['sy'] / g['w'])), 'z': g['z'], 'w': g['w'],
                    'items': g['items']})
    return out


def level_band(pairs, mult=1):
    """(level, weight) pairs -> (lo, hi): the middle 70 % of the weight, lo rounded down and hi up to tens, then times mult"""
    pairs = sorted(pairs)
    total = sum(w for _, w in pairs)
    if total <= 0:
        return None
    acc, lo, hi = 0, None, None
    for lv, w in pairs:
        acc += w
        if lo is None and acc >= total * 0.15:
            lo = lv
        if hi is None and acc >= total * 0.85:
            hi = lv
    lo10 = (lo // 10) * 10
    return max(1, int(lo10 * mult)), int(max(lo10 + 10, -(-hi // 10) * 10) * mult)


def title(name):
    return ' '.join(w[:1].upper() + w[1:] for w in name.split(' '))


def hunting_areas(levels, spawns, mult=1):
    points = []
    for name, lv in levels.items():
        for x, y, z, e in spawns.get(name.lower(), []):
            points.append((x, y, z, e, (name, lv)))
    out = []
    for g in cluster(points, HUNT_JOIN):
        if g['w'] < HUNT_MIN:
            continue
        # the mark prints the hunting level (pool level x baseLevelMult)
        band = level_band([(it[4][1], it[3]) for it in g['items']], mult)
        names = {}
        for it in g['items']:
            names[it[4][0]] = names.get(it[4][0], 0) + it[3]
        top = sorted(names.items(), key=lambda kv: (-kv[1], kv[0]))[:2]
        label = 'Hunting: %s (level %d-%d)' % (', '.join(title(n) for n, _ in top), band[0], band[1])
        out.append((g['w'], {'k': 'hunt', 'x': g['x'], 'y': g['y'], 'z': g['z'], 'n': label, 'r': 1}))
    out.sort(key=lambda t: (-t[0], t[1]['z'], t[1]['x'], t[1]['y']))
    return [m for _, m in out[:HUNT_MAX]]


def nearest_town(pos, temples):
    best, bd = None, None
    for t in temples:
        if t['z'] != pos[2] and abs(t['z'] - pos[2]) > 2:
            continue
        d = cheb((t['x'], t['y']), pos)
        if d <= NAME_TOWN_RADIUS and (bd is None or d < bd):
            best, bd = t, d
    return best, bd


def build_marks(towns, depots, crafts, npcs, services, levels, spawns, bosses, town_names, mult=1):
    """the marks from parsed inputs (pure; tested by gen_poi_test.py)
    towns [(id, name, x, y, z)], depots [(x, y, z)], crafts [(aid, (x, y, z))], npcs [(name, x, y, z)],
    services {lower name: kind}, levels / spawns (hunting_data), bosses [(cat, name, x, y, z)], town_names {id: name}"""
    marks, temples = [], []
    for tid, name, x, y, z in towns:
        town = town_names.get(tid) or name
        temples.append({'x': x, 'y': y, 'z': z, 'town': town})
        marks.append({'k': 'temple', 'x': x, 'y': y, 'z': z, 'n': ('Temple of ' + town) if town else 'Temple', 'r': 0})
    for g in cluster([(x, y, z, 1, None) for x, y, z in depots], DEPOT_JOIN):
        if len(g['items']) < DEPOT_MIN:
            continue
        t, _ = nearest_town((g['x'], g['y'], g['z']), temples)
        marks.append({'k': 'depot', 'x': g['x'], 'y': g['y'], 'z': g['z'],
                      'n': ('Depot, ' + t['town']) if t and t['town'] else 'Depot', 'r': 0})
    for g in cluster([(p[0], p[1], p[2], 1, aid) for aid, p in crafts], CRAFT_JOIN):
        kinds = sorted(set(it[4] for it in g['items']))
        name = 'Crafting hall' if len(g['items']) >= 3 else CRAFT_AIDS.get(kinds[0], 'Crafting table')
        marks.append({'k': 'craft', 'x': g['x'], 'y': g['y'], 'z': g['z'], 'n': name, 'r': 0})
    for name, x, y, z in npcs:
        kind = services.get(name.strip().lower())
        if not kind:
            continue
        t, d = nearest_town((x, y, z), temples)
        near = t is not None and d <= TOWN_RADIUS
        marks.append({'k': kind, 'x': x, 'y': y, 'z': z, 'n': '%s (%s)' % (name.strip(), SERVICE_LABEL[kind]),
                      'r': 0 if near else 1})
    for cat, name, x, y, z in bosses:
        marks.append({'k': 'boss', 'x': x, 'y': y, 'z': z, 'n': '%s (%s)' % (name, BOSS_LABEL[cat]), 'r': 1})
    marks += hunting_areas(levels, spawns, mult)
    # one mark of a kind per tile
    seen, out = set(), []
    for m in marks:
        key = (m['k'], m['x'], m['y'], m['z'])
        if key not in seen and 0 < m['x'] < 65535 and 0 < m['y'] < 65535 and 0 <= m['z'] <= 15:
            seen.add(key)
            out.append(m)
    out.sort(key=lambda m: (KIND_ORDER.index(m['k']), m['z'], m['x'], m['y'], m['n']))
    return out


def drop_old_names(marks, hashes):
    """-> (kept marks, number left out): a mark whose name holds an old name of the rename lists"""
    kept, dropped = [], 0
    for m in marks:
        if any(digest(p) in hashes for p in phrases(m['n'], 4)):
            dropped += 1
        else:
            kept.append(m)
    return kept, dropped


def lua_string(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', ' ') + '"'


def render(marks):
    body = []
    for m in marks:
        body.append('\t\t{k = %s, x = %d, y = %d, z = %d, n = %s, r = %d},' % (
            lua_string(m['k']), m['x'], m['y'], m['z'], lua_string(m['n']), m['r']))
    rows = '\n'.join(body)
    version = hashlib.sha1(rows.encode('utf-8')).hexdigest()[:12]
    counts = {}
    for m in marks:
        counts[m['k']] = counts.get(m['k'], 0) + 1
    summary = ', '.join('%s %d' % (k, counts[k]) for k in KIND_ORDER if k in counts)
    return ('-- Points of interest of the map markers (poi.lua, client game_mapmarkers). GENERATED by server/tools/gen_poi.py\n'
            '-- from the installed map, items, NPCs and spawn data: do not edit by hand, rerun the tool (install step "poi").\n'
            '-- k kind, x y z, n name, r 0 always shown / 1 discovered near it. %d marks: %s.\n'
            'return {\n\tversion = "%s",\n\tmarks = {\n%s\n\t}\n}\n') % (len(marks), summary or 'none', version, rows)


# ------------------------------------------------------------------------------------------------ main
def generate(server_dir, map_file=None):
    data_dir = os.path.join(server_dir, 'data')
    map_file = map_file or towns_lib.map_path(data_dir)
    if not map_file or not os.path.isfile(map_file):
        raise PoiError('no map in %s/world' % data_dir)
    with open(map_file, 'rb') as f:
        data = f.read()
    _s, _e, raw_towns = towns_lib.find_towns(data)
    towns = [(tid, name.decode('utf-8', 'replace'), x, y, z) for tid, name, x, y, z, _extra in raw_towns]
    depots = [pos for _iid, pos in find_items(data, depot_ids(os.path.join(data_dir, 'items', 'items.xml')))]
    crafts = find_action_items(data, CRAFT_AIDS.keys())
    del data
    stem = os.path.splitext(os.path.basename(map_file))[0]
    spawn_file = os.path.join(data_dir, 'world', stem + '-spawn.xml')
    if not os.path.isfile(spawn_file):
        spawn_file = os.path.splitext(map_file)[0] + '-spawn.xml'
    npcs = spawn_npcs(spawn_file) if os.path.isfile(spawn_file) else []
    services = npc_services(os.path.join(data_dir, 'npc'))
    chaos_dir = os.path.join(data_dir, 'scripts', 'chaos')
    if not os.path.isfile(os.path.join(chaos_dir, 'bounty_pool.lua')):
        chaos_dir = os.path.join(SERVER, 'data', 'scripts', 'chaos')
    levels, spawns = hunting_data(chaos_dir)
    bosses = boss_spots(chaos_dir)
    town_names = read_town_names(os.path.join(HERE, 'base_towns.csv'))
    hashes = read_hashes([os.path.join(SERVER, 'data', 'npc', 'base_npc_names.csv'),
                          os.path.join(SERVER, 'data', 'npc', 'base_world_names.csv'),
                          os.path.join(SERVER, 'data', 'monster', 'base_monster_names.csv')])
    # a town name the map still has from the old world is not written: the temple is then just "Temple"
    towns = [(tid, name if not any(digest(p) in hashes for p in phrases(name, 4)) else '', x, y, z)
             for tid, name, x, y, z in towns]
    marks = build_marks(towns, depots, crafts, npcs, services, levels, spawns, bosses, town_names,
                        base_level_mult(chaos_dir))
    marks, dropped = drop_old_names(marks, hashes)
    stats = {'towns': len(towns), 'lockers': len(depots), 'tables': len(crafts), 'npcs': len(npcs), 'unrenamed': dropped}
    return marks, stats


def main(argv):
    values, args, opts = {}, [], set()
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ('--out', '--map'):
            if i + 1 >= len(argv):
                print(__doc__)
                return 2
            values[a] = argv[i + 1]
            i += 2
            continue
        if a.startswith('--'):
            opts.add(a)
        else:
            args.append(a)
        i += 1
    out = values.get('--out')
    if len(args) != 1:
        print(__doc__)
        return 2
    server_dir = args[0]
    out = out or os.path.join(server_dir, 'data', 'chaos_poi.lua')
    try:
        marks, stats = generate(server_dir, values.get('--map'))
    except (PoiError, towns_lib.MapError, OSError) as e:
        print('gen_poi: %s' % e)
        return 1
    text = render(marks)
    old = read_text(out) if os.path.isfile(out) else None
    if '--quiet' not in opts:
        print('gen_poi: %d marks (%s towns, %s lockers, %s crafting tables, %s NPC entries read; %s unrenamed names left '
              'out)' % (len(marks), stats['towns'], stats['lockers'], stats['tables'], stats['npcs'], stats['unrenamed']))
    if '--check' in opts:
        if old != text:
            print('gen_poi: %s is not up to date' % out)
            return 1
        return 0
    if old == text:
        print('gen_poi: %s unchanged' % out)
        return 0
    tmp = out + '.tmp'
    with open(tmp, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    os.replace(tmp, out)
    print('gen_poi: wrote %s' % out)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
