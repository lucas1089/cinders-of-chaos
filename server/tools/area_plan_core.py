#!/usr/bin/env python3
"""The area planner's pure parts (server/tools/area_planner.py; docs/MAP_GUIDE.md "Area planner").

A plan (JSON, schema areaplan/schema.json) says what an area is: biome, zones, paths, connections, spawns, boss, NPCs,
chests, entry and exit. It never names an item id. This module
  * reads our catalogues: biomes and materials (tools/areaplan_build.lua catalogue), monsters with their hunting level
    (data/scripts/chaos/bounty_pool.lua, data/monster/monsters/chaos), NPC names (data/npc), the level tiers
    (bounty_config.lua bands);
  * checks a plan against the schema and the game rules (validate), with messages an AI can act on;
  * places the zones and routes the paths (layout), deterministic from the plan's seed;
  * runs the reachability maths on the plan graph (plan_reach) and on tiles (tile_reach).
Compiling, QA and rendering are in area_plan_compile.py. Python 3 standard library only.
"""
import difflib, json, math, os, random, re, subprocess, zlib
from collections import deque

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
ROOT = os.path.dirname(SERVER)
PLANDIR = os.path.join(HERE, 'areaplan')
SCHEMA_PATH = os.path.join(PLANDIR, 'schema.json')
SCHEMA_ID = 'chaos-area-plan/1'

SIZES = {'small': (7, 7), 'medium': (11, 9), 'large': (15, 12), 'huge': (20, 16)}
ARENA = {'small': 9, 'medium': 13, 'large': 17, 'huge': 21}
COMPASS = {'north': (0.5, 0.2), 'south': (0.5, 0.8), 'east': (0.8, 0.5), 'west': (0.2, 0.5), 'center': (0.5, 0.5),
           'northwest': (0.2, 0.2), 'northeast': (0.8, 0.2), 'southwest': (0.2, 0.8), 'southeast': (0.8, 0.8)}
GAP = 3                      # tiles of rock or wall between two zones
MARGIN_LO, MARGIN_HI = 4, 3  # first and last usable local cell (1-based): the rock rim needs the rest
MAX_ZONES_PER_FLOOR = 24
DEFAULT_ORIGIN = (14800, 14800)
SCREEN = (15, 11)            # the tiles a 10.98 client shows
D8 = ((0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1))


# ================================================================================================= catalogues
_cache = {}


def lua_bin():
    return os.environ.get('LUAJIT', 'luajit')


def catalogue(pair24=None, dark=False):
    """biomes, light and decoration levels, the link and chest items (from our Lua tables)"""
    if pair24 is None:
        pair24 = pair24_switch()
    key = ('cat', pair24, dark)
    if key not in _cache:
        args = [lua_bin(), 'tools/areaplan_build.lua', 'catalogue'] + (['pair24'] if pair24 else []) + (['dark'] if dark else [])
        out = subprocess.run(args, cwd=SERVER, check=True, capture_output=True, text=True).stdout
        _cache[key] = json.loads(out)
    return _cache[key]


def pair24_switch():
    """ChaosThemeArt.PAIR24 in data/lib/chaos_theme_art.lua (the pair 24 grounds are used only while it is on)"""
    path = os.path.join(SERVER, 'data', 'lib', 'chaos_theme_art.lua')
    try:
        return re.search(r'^M\.PAIR24\s*=\s*true\b', open(path, encoding='utf-8').read(), re.M) is not None
    except OSError:
        return False


def monsters():
    """{lower name: {name, level, boss}} from the bounty pool (hunting level of every monster that spawns) and our own
    monster files (level-scaled ones: the middle of <level min max>)"""
    if 'mon' in _cache:
        return _cache['mon']
    out = {}
    text = open(os.path.join(SERVER, 'data', 'scripts', 'chaos', 'bounty_pool.lua'), encoding='utf-8').read()
    cut = text.find('bosses = {')
    rx = re.compile(r'\{name = "([^"]+)", level = (\d+)')
    for m in rx.finditer(text):
        out[m.group(1).lower()] = dict(name=m.group(1), level=int(m.group(2)), boss=m.start() > cut >= 0)
    base = os.path.join(SERVER, 'data', 'monster', 'monsters', 'chaos')
    for dirpath, _dirs, files in os.walk(base):
        for f in sorted(files):
            if not f.endswith('.xml'):
                continue
            s = open(os.path.join(dirpath, f), encoding='utf-8', errors='replace').read(4000)
            m = re.search(r'<monster\s+name="([^"]+)"', s)
            if not m or m.group(1).lower() in out:
                continue
            lv = re.search(r'<level\s+min="(\d+)"\s+max="(\d+)"', s)
            out[m.group(1).lower()] = dict(name=m.group(1), level=(int(lv.group(1)) + int(lv.group(2))) // 2 if lv else None,
                                           boss='boss' in os.path.basename(dirpath).lower())
    _cache['mon'] = out
    return out


def npcs():
    if 'npc' in _cache:
        return _cache['npc']
    out = {}
    d = os.path.join(SERVER, 'data', 'npc')
    for f in sorted(os.listdir(d)):
        p = os.path.join(d, f)
        if f.endswith('.xml'):
            m = re.search(r'<npc\s+name="([^"]+)"', open(p, encoding='utf-8', errors='replace').read(2000))
            if m:
                out[m.group(1).lower()] = m.group(1)
        elif f == 'base_npc_names.csv':
            for line in open(p, encoding='utf-8').read().splitlines()[1:]:
                parts = line.split(',')
                if len(parts) > 1 and parts[1]:
                    out.setdefault(parts[1].lower(), parts[1])
    _cache['npc'] = out
    return out


def tiers():
    """the level tiers: the bounty board's bands, [(min, max, pick_lo, pick_hi)]"""
    if 'tiers' in _cache:
        return _cache['tiers']
    text = open(os.path.join(SERVER, 'data', 'scripts', 'chaos', 'bounty_config.lua'), encoding='utf-8').read()
    out = [tuple(map(int, m)) for m in re.findall(r'min = (\d+), max = (\d+), pick = \{(\d+), (\d+)\}', text)]
    _cache['tiers'] = out
    return out


def tier_window(lo, hi):
    """(touched tiers, pick_lo, pick_hi) of a level band. The last tier has no top (800+), but the bounty board's pick
    window ends at 1500; a band above it may also take monsters up to its own top + 100 (the 1300-2000 set)"""
    t = [b for b in tiers() if b[0] <= hi and b[1] >= lo]
    if not t:
        return [], None, None
    phi = max(b[3] for b in t)
    if any(b[1] >= 99999 for b in t):
        phi = max(phi, hi + 100)
    return t, min(b[2] for b in t), phi


CHEST_ACTION_BLOCK = (47960, 47999)    # one action id per planned area with chests (server/README.md "Area planner")
CHEST_STORAGE_BLOCK = (7101200, 7101299)  # one player storage per quest chest (server/README.md "Storage keys")


def chest_action(plan):
    """the action id of the area's quest chests: the plan's chest_action, else one from the block by the area id"""
    if plan.get('chest_action'):
        return plan['chest_action']
    lo, hi = CHEST_ACTION_BLOCK
    return lo + zlib.crc32(plan['id'].encode()) % (hi - lo + 1)


def chest_storage(quest):
    lo, hi = CHEST_STORAGE_BLOCK
    return lo + zlib.crc32(quest.encode()) % (hi - lo + 1)


def reward_items():
    """{lower name: (id, name)} of the items a chest may give, from our item tables: renamed base items
    (data/items/base_item_names.csv), our uniques (chaos_items.xml), the crafting orbs (chaos_orbs_config.lua) and the
    pack products and food (art_items.csv)"""
    if 'rewards' in _cache:
        return _cache['rewards']
    out = {}
    d = os.path.join(SERVER, 'data')

    def add(i, name):
        if name and name.lower() not in out:
            out[name.lower()] = (int(i), name)
    for line in open(os.path.join(d, 'items', 'base_item_names.csv'), encoding='utf-8').read().splitlines()[1:]:
        p = line.split(',')
        if len(p) >= 3 and p[0].isdigit():
            add(p[0], p[2])
    for m in re.finditer(r'<item id="(\d+)"[^>]*name="([^"]+)"', open(os.path.join(d, 'items', 'chaos_items.xml'),
                                                                      encoding='utf-8').read()):
        add(m.group(1), m.group(2))
    for m in re.finditer(r'\{id = (\d+),[^\n]*?name = "([^"]+)"', open(os.path.join(d, 'lib', 'chaos_orbs_config.lua'),
                                                                     encoding='utf-8').read()):
        add(m.group(1), m.group(2))
    import csv
    with open(os.path.join(d, 'items', 'art_items.csv'), encoding='utf-8') as f:
        for r in csv.DictReader(f):
            if r.get('kind') in ('product', 'food'):
                add(r['server_id'], r['name'])
    _cache['rewards'] = out
    return out


def resolve_reward(reward):
    """a chest's reward with item ids: {gold, experience, message, items: [(id, count, name)]}"""
    if not reward:
        return None
    items = []
    for it in reward.get('items', []):
        i, name = reward_items()[it['name'].lower()]
        items.append((i, it.get('count', 1), name))
    return dict(gold=reward.get('gold', 0), experience=reward.get('experience', 0), message=reward.get('message', ''),
                items=items)


# ================================================================================================= schema
def load_schema():
    if 'schema' not in _cache:
        _cache['schema'] = json.load(open(SCHEMA_PATH, encoding='utf-8'))
    return _cache['schema']


def _type_ok(v, t):
    return {'object': isinstance(v, dict), 'array': isinstance(v, list), 'string': isinstance(v, str),
            'integer': isinstance(v, int) and not isinstance(v, bool), 'boolean': isinstance(v, bool),
            'number': isinstance(v, (int, float)) and not isinstance(v, bool)}.get(t, True)


def schema_errors(v, s, path='plan'):
    """the subset of JSON Schema our schema uses: type, const, enum, required, properties, additionalProperties,
    items, minItems, maxItems, minimum, maximum, minLength, maxLength, pattern, oneOf"""
    out = []
    if 'oneOf' in s:
        if not any(not schema_errors(v, alt, path) for alt in s['oneOf']):
            out.append((path, 'must be one of: ' + ' or '.join(
                ('one of ' + ', '.join(map(str, a['enum']))) if 'enum' in a else ('a list of %d %ss' % (a.get('minItems', 0), a['items']['type'])) if a.get('type') == 'array' else a.get('type', '?')
                for a in s['oneOf'])))
        return out
    if 'const' in s and v != s['const']:
        return [(path, 'must be %s' % json.dumps(s['const']))]
    if 'enum' in s and v not in s['enum']:
        return [(path, '%s is not allowed; use one of %s' % (json.dumps(v), ', '.join(map(str, s['enum']))))]
    if 'type' in s and not _type_ok(v, s['type']):
        return [(path, 'must be a%s %s' % ('n' if s['type'][0] in 'aeiou' else '', s['type']))]
    if isinstance(v, dict):
        for k in s.get('required', []):
            if k not in v:
                out.append((path, 'missing "%s"' % k))
        props = s.get('properties', {})
        for k, x in v.items():
            if k in props:
                out += schema_errors(x, props[k], '%s.%s' % (path, k))
            elif s.get('additionalProperties') is False:
                out.append((path, 'unknown key "%s" (allowed: %s)' % (k, ', '.join(props))))
    if isinstance(v, list):
        if 'minItems' in s and len(v) < s['minItems']:
            out.append((path, 'needs at least %d item(s)' % s['minItems']))
        if 'maxItems' in s and len(v) > s['maxItems']:
            out.append((path, 'holds at most %d item(s)' % s['maxItems']))
        if 'items' in s:
            for i, x in enumerate(v):
                out += schema_errors(x, s['items'], '%s[%d]' % (path, i))
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        if 'minimum' in s and v < s['minimum']:
            out.append((path, '%s is below the minimum %s' % (v, s['minimum'])))
        if 'maximum' in s and v > s['maximum']:
            out.append((path, '%s is above the maximum %s' % (v, s['maximum'])))
    if isinstance(v, str):
        if 'minLength' in s and len(v) < s['minLength']:
            out.append((path, 'is shorter than %d characters' % s['minLength']))
        if 'maxLength' in s and len(v) > s['maxLength']:
            out.append((path, 'is longer than %d characters' % s['maxLength']))
        if 'pattern' in s and not re.match(s['pattern'], v):
            out.append((path, '"%s" does not match %s' % (v, s['pattern'])))
    return out


# ================================================================================================= issues
class Issue:
    def __init__(self, level, path, msg, hint=None):
        self.level, self.path, self.msg, self.hint = level, path, msg, hint

    def __str__(self):
        return '%s %s: %s%s' % (self.level, self.path, self.msg, (' Fix: ' + self.hint) if self.hint else '')

    def as_dict(self):
        return dict(level=self.level, path=self.path, message=self.msg, hint=self.hint)


def errors(issues):
    return [i for i in issues if i.level == 'ERROR']


# ================================================================================================= plan helpers
def plan_seed(plan):
    return plan.get('seed') or (zlib.crc32(plan.get('id', 'area').encode()) % 2000000000 + 1)


def biome_of(plan, cat):
    return cat['biomes'].get(plan.get('biome'))


def zone_shape(z, biome):
    if z.get('shape'):
        return z['shape']
    return 'room' if biome and biome['kind'] == 'dungeon' else 'cave'


def zone_dims(z, biome):
    s = z.get('size', 'medium')
    if isinstance(s, list):
        return s[0], s[1]
    if zone_shape(z, biome) == 'arena':
        return ARENA[s], ARENA[s]
    return SIZES[s]


def default_style(biome):
    return 'corridor' if biome and biome['kind'] == 'dungeon' else 'tunnel'


def plan_edges(plan):
    """directed zone edges: (from, to, kind, index)"""
    out = []
    for i, p in enumerate(plan.get('paths', [])):
        out.append((p['from'], p['to'], 'path', i))
        out.append((p['to'], p['from'], 'path', i))
    zf = {z['id']: z['floor'] for z in plan.get('zones', [])}
    for i, c in enumerate(plan.get('connections', [])):
        t, a, b = c['type'], c['from'], c['to']
        if t == 'teleport':
            out.append((a, b, t, i))
            if c.get('two_way', True):
                out.append((b, a, t, i))
        elif t == 'hole':
            out.append((a, b, t, i))
        else:
            out.append((a, b, t, i))
            out.append((b, a, t, i))
    return out


def plan_reach(plan):
    """zones reached from the entry over the plan graph (paths both ways, stairs and ladders both ways, holes down,
    teleports one or both ways): {zone: hops}"""
    start = plan.get('entry', {}).get('zone')
    adj = {}
    for a, b, _k, _i in plan_edges(plan):
        adj.setdefault(a, []).append(b)
    dist = {start: 0}
    q = deque([start])
    while q:
        a = q.popleft()
        for b in adj.get(a, []):
            if b not in dist:
                dist[b] = dist[a] + 1
                q.append(b)
    return dist


def boss_entrances(plan, zone):
    """the ways into a zone: paths, stairs, ladders and holes into it, teleports that land in it"""
    n = []
    for a, b, k, i in plan_edges(plan):
        if b == zone and a != zone:
            n.append((k, i, a))
    seen, out = set(), []
    for k, i, a in n:
        if (k, i) not in seen:
            seen.add((k, i))
            out.append((k, i, a))
    return out


# ================================================================================================= validation
def validate(plan, cat=None, pair24=None):
    """[Issue]: schema, references, sizes, reachability, monsters and tiers, PZ, boss room, links"""
    issues = []
    E = lambda p, m, h=None: issues.append(Issue('ERROR', p, m, h))
    W = lambda p, m, h=None: issues.append(Issue('WARN', p, m, h))
    if not isinstance(plan, dict):
        E('plan', 'must be a JSON object')
        return issues
    for p, m in schema_errors(plan, load_schema()):
        E(p, m)
    if errors(issues):
        return issues          # the rules below need a well-formed plan
    cat = cat or catalogue(pair24)
    biome = biome_of(plan, cat)
    if not biome:
        E('plan.biome', 'unknown biome "%s"' % plan['biome'], 'use one of ' + ', '.join(sorted(cat['biomes'])))
        return issues
    if biome.get('needs'):
        W('plan.biome', 'biome %s uses %s; without them the area shows blank tiles' % (plan['biome'], biome['needs']))
    if biome.get('pair24') and not cat.get('pair24'):
        W('plan.biome', 'the pair 24 switch is off: %s uses its stock fallback grounds (no pair 24 swamp, acid, lava '
          'or water)' % plan['biome'])
    W_, H_ = plan['size']
    floors = plan['floors']
    zones = plan['zones']
    zid = {}
    for i, z in enumerate(zones):
        p = 'plan.zones[%d]' % i
        if z['id'] in zid:
            E(p + '.id', 'zone id "%s" is used twice' % z['id'], 'give every zone its own id')
        zid[z['id']] = z
        if z['floor'] > floors:
            E(p + '.floor', 'floor %d but the area has %d floor(s)' % (z['floor'], floors),
              'raise "floors" or move the zone to floor 1-%d' % floors)
        w, h = zone_dims(z, biome)
        if w > W_ - MARGIN_LO - MARGIN_HI or h > H_ - MARGIN_LO - MARGIN_HI:
            E(p + '.size', 'zone %s is %dx%d, too big for a %dx%d area (%d tiles of rim on each side)'
              % (z['id'], w, h, W_, H_, MARGIN_LO), 'make the zone smaller or the area bigger')
        if 'at' in z:
            x, y = z['at']
            if x < MARGIN_LO - 1 or y < MARGIN_LO - 1 or x + w > W_ - MARGIN_HI or y + h > H_ - MARGIN_HI:
                E(p + '.at', 'zone %s at %d,%d (%dx%d) leaves the usable area %d..%d x %d..%d'
                  % (z['id'], x, y, w, h, MARGIN_LO - 1, W_ - MARGIN_HI - 1, MARGIN_LO - 1, H_ - MARGIN_HI - 1),
                  'move it inside or leave "at" out so the planner places it')
        if z.get('pz') and z.get('role') == 'boss':
            E(p + '.pz', 'the boss room cannot be a protection zone')
    for f in range(1, floors + 1):
        n = sum(1 for z in zones if z['floor'] == f)
        if n == 0:
            E('plan.zones', 'floor %d has no zone' % f, 'add a zone on floor %d or lower "floors"' % f)
        if n > MAX_ZONES_PER_FLOOR:
            E('plan.zones', 'floor %d has %d zones, at most %d' % (f, n, MAX_ZONES_PER_FLOOR))
    # fixed zones must not overlap
    fixed = [(z, zone_rect_fixed(z, biome)) for z in zones if 'at' in z]
    for a in range(len(fixed)):
        for b in range(a + 1, len(fixed)):
            za, ra = fixed[a]
            zb, rb = fixed[b]
            if za['floor'] == zb['floor'] and rect_overlap(ra, rb, GAP - 1):
                E('plan.zones', 'zones %s and %s overlap or are closer than %d tiles' % (za['id'], zb['id'], GAP),
                  'move one of them or leave "at" out')

    def ref(path, name, what='zone'):
        if name not in zid:
            close = difflib.get_close_matches(name, list(zid), 1)
            E(path, 'no %s "%s"' % (what, name), ('did you mean "%s"?' % close[0]) if close else 'add the zone first')
            return None
        return zid[name]
    for i, p in enumerate(plan.get('paths', [])):
        a, b = ref('plan.paths[%d].from' % i, p['from']), ref('plan.paths[%d].to' % i, p['to'])
        if a and b:
            if a is b:
                E('plan.paths[%d]' % i, 'a path from %s to itself' % a['id'])
            elif a['floor'] != b['floor']:
                E('plan.paths[%d]' % i, 'path %s-%s joins floor %d and floor %d' % (a['id'], b['id'], a['floor'], b['floor']),
                  'join floors with a connection of type stairs, ladder or hole')
    for i, c in enumerate(plan.get('connections', [])):
        p = 'plan.connections[%d]' % i
        a, b = ref(p + '.from', c['from']), ref(p + '.to', c['to'])
        if 'two_way' in c and c['type'] != 'teleport':
            W(p + '.two_way', 'only a teleport has two_way; ignored')
        if not (a and b):
            continue
        if a is b:
            E(p, 'a connection from %s to itself' % a['id'])
        elif c['type'] in ('stairs', 'ladder', 'hole'):
            if abs(a['floor'] - b['floor']) != 1:
                E(p, '%s joins floor %d and floor %d; a %s joins two floors next to each other'
                  % (c['type'], a['floor'], b['floor'], c['type']), 'use a teleport or add a floor in between')
            elif c['type'] == 'hole' and a['floor'] > b['floor']:
                E(p, 'a hole leads down: "from" (%s, floor %d) must be above "to" (%s, floor %d)'
                  % (a['id'], a['floor'], b['id'], b['floor']), 'swap from and to, or use a ladder')
    entry = plan['entry']['zone']
    ez = ref('plan.entry.zone', entry)
    if ez and ez['floor'] != 1:
        E('plan.entry.zone', 'the entry %s is on floor %d; players arrive on floor 1' % (entry, ez['floor']),
          'pick a floor 1 zone as the entry')
    if ez and ez.get('role') == 'boss':
        E('plan.entry.zone', 'the entry cannot be the boss room')
    if 'exit' in plan:
        ref('plan.exit.zone', plan['exit']['zone'])
    else:
        W('plan.exit', 'no exit: players leave by walking back to the entry', 'add "exit": {"zone": "%s"}' % entry)
    # reachability over the plan graph
    if not errors(issues):
        reach = plan_reach(plan)
        for i, z in enumerate(zones):
            if z['id'] not in reach:
                near = [o['id'] for o in zones if o['id'] in reach and o['floor'] == z['floor']]
                hint = ('add {"from": "%s", "to": "%s"} to "paths"' % (near[0], z['id'])) if near else \
                    'add a stairs connection from a reached zone on the floor above, or a teleport'
                E('plan.zones[%d]' % i, 'zone %s cannot be reached from the entry %s' % (z['id'], entry), hint)
    # monsters, tiers
    mons = monsters()
    lo, hi = plan['level']
    if lo > hi:
        E('plan.level', 'the band %d-%d is upside down' % (lo, hi), 'write [lowest, highest]')
    touched, plo, phi = tier_window(lo, hi)
    if len(touched) > 2:
        E('plan.level', 'the band %d-%d spans %d level tiers (%s)' % (lo, hi, len(touched),
          ', '.join('%d-%s' % (t[0], t[1] if t[1] < 99999 else '+') for t in touched)),
          'keep the band inside one tier or two neighbouring tiers')
    elif not touched:
        E('plan.level', 'the band %d-%d is under the lowest tier (%d+)' % (lo, hi, tiers()[0][0]))

    def suggest(level, n=5):
        pool = [m for m in mons.values() if m['level'] and plo is not None and plo <= m['level'] <= phi and not m['boss']]
        pool.sort(key=lambda m: (abs(m['level'] - level), m['name']))
        return ', '.join('%s (%d)' % (m['name'], m['level']) for m in pool[:n])

    def monster(path, name, boss=False):
        m = mons.get(name.lower())
        if not m:
            close = difflib.get_close_matches(name.lower(), list(mons), 3)
            E(path, 'no monster "%s" in our monster list' % name,
              ('did you mean %s?' % ', '.join('"%s"' % mons[c]['name'] for c in close)) if close else
              ('monsters of this band: ' + suggest((lo + hi) // 2)) if plo else None)
            return None
        if m['name'] != name:
            W(path, 'write "%s" as "%s"' % (name, m['name']))
        if plo is None or m['level'] is None:
            return m
        if boss:
            if m['level'] < plo or m['level'] > phi * 1.5:
                E(path, 'boss %s is level %d, outside %d-%d for the band %d-%d' % (m['name'], m['level'], plo, int(phi * 1.5), lo, hi),
                  'pick a boss of level %d-%d' % (plo, int(phi * 1.5)))
            elif not m['boss']:
                W(path, '%s is not a boss monster; it spawns with normal health' % m['name'])
        elif not plo <= m['level'] <= phi:
            E(path, '%s is level %d; the band %d-%d takes monsters of level %d-%d' % (m['name'], m['level'], lo, hi, plo, phi),
              'pick from: ' + suggest(m['level']))
        return m
    zone_monsters = {}
    for i, s in enumerate(plan.get('spawns', [])):
        p = 'plan.spawns[%d]' % i
        z = ref(p + '.zone', s['zone'])
        monster(p + '.monster', s['monster'])
        if z:
            if z.get('pz'):
                E(p + '.zone', 'spawn in %s, a protection zone' % z['id'], 'move the spawn or drop "pz"')
            if z.get('role') == 'boss':
                W(p + '.zone', '%s is the boss room; extra spawns there make the boss fight crowded' % z['id'])
            if z['id'] == entry:
                W(p + '.zone', 'spawns in the entry zone stand at least 4 tiles from the arrival')
            zone_monsters[z['id']] = zone_monsters.get(z['id'], 0) + s['count']
    for zname, n in zone_monsters.items():
        w, h = zone_dims(zid[zname], biome)
        dens = 100.0 * n / max(1, w * h * 0.7)
        if dens > 8:
            W('plan.zones', 'zone %s holds %d monsters on about %d tiles (%.1f per 100; the guide asks 1.5-5)'
              % (zname, n, int(w * h * 0.7), dens), 'lower the counts or make the zone bigger')
    bossz = [z for z in zones if z.get('role') == 'boss']
    if 'boss' in plan:
        b = plan['boss']
        z = ref('plan.boss.zone', b['zone'])
        monster('plan.boss.monster', b['monster'], boss=True)
        if z and z.get('role') != 'boss':
            E('plan.boss.zone', 'the boss stands in %s, which is not the boss room' % z['id'],
              'set "role": "boss" on %s' % z['id'])
        if z and z.get('pz'):
            E('plan.boss.zone', 'the boss room %s is a protection zone' % z['id'])
    elif bossz:
        W('plan.zones', 'zone %s has role boss but the plan has no "boss"' % bossz[0]['id'])
    if len(bossz) > 1:
        E('plan.zones', '%d zones have role boss: %s' % (len(bossz), ', '.join(z['id'] for z in bossz)),
          'one boss room per area')
    for z in bossz:
        ways = boss_entrances(plan, z['id'])
        if len(ways) != 1:
            E('plan.zones', 'the boss room %s has %d entrances (%s); it needs exactly one'
              % (z['id'], len(ways), ', '.join('%s from %s' % (k, a) for k, _i, a in ways) or 'none'),
              'keep one path, stairs or teleport into it; a way out can be a one-way teleport ("two_way": false)')
    nlist = npcs()
    for i, n in enumerate(plan.get('npcs', [])):
        p = 'plan.npcs[%d]' % i
        z = ref(p + '.zone', n['zone'])
        if n.get('new'):
            if n['name'].lower() in nlist:
                E(p + '.name', 'NPC %s exists already; "new" is for an NPC the compile writes a stub for' % n['name'],
                  'drop "new" to place the existing NPC')
            elif not re.match(r"^[A-Z][A-Za-z' -]{2,30}$", n['name']):
                E(p + '.name', 'a new NPC name needs a capital letter first and 3-31 letters, spaces or apostrophes')
        elif n['name'].lower() not in nlist:
            close = difflib.get_close_matches(n['name'].lower(), list(nlist), 3)
            E(p + '.name', 'no NPC "%s" in our NPC list' % n['name'],
              ('did you mean %s?' % ', '.join('"%s"' % nlist[c] for c in close)) if close else 'see `area_planner.py catalogue --npcs`')
        if z and not z.get('pz'):
            W(p + '.zone', 'NPC %s stands outside a protection zone' % n['name'], 'set "pz": true on %s' % z['id'])
    rewards = reward_items()
    slots = {}
    for i, c in enumerate(plan.get('chests', [])):
        ref('plan.chests[%d].zone' % i, c['zone'])
        st = chest_storage(c['quest'])
        if st in slots and slots[st] != c['quest']:
            E('plan.chests[%d].quest' % i, 'quest keys %s and %s share storage %d' % (slots[st], c['quest'], st),
              'rename one of the quest keys')
        slots[st] = c['quest']
        rw = c.get('reward')
        if not rw:
            W('plan.chests[%d]' % i, 'chest %s has no reward; its script gives nothing' % c['quest'],
              'add "reward": {"gold": ..., "items": [{"name": ..., "count": ...}]}')
            continue
        for j, it in enumerate(rw.get('items', [])):
            if it['name'].lower() not in rewards:
                close = difflib.get_close_matches(it['name'].lower(), list(rewards), 3)
                E('plan.chests[%d].reward.items[%d].name' % (i, j), 'no item "%s" in our item tables' % it['name'],
                  ('did you mean %s?' % ', '.join('"%s"' % rewards[x][1] for x in close)) if close else
                  'use a name from data/items/base_item_names.csv, chaos_items.xml or the orbs')
    keys = [c['quest'] for c in plan.get('chests', [])]
    for k in set(keys):
        if keys.count(k) > 1:
            W('plan.chests', 'quest key %s is used by %d chests' % (k, keys.count(k)))
    return issues


# ================================================================================================= layout
def rect_overlap(a, b, gap=0):
    return a[0] - gap <= b[2] and a[2] + gap >= b[0] and a[1] - gap <= b[3] and a[3] + gap >= b[1]


def zone_rect_fixed(z, biome):
    w, h = zone_dims(z, biome)
    x, y = z['at']
    return (x + 1, y + 1, x + w, y + h)       # local 1-based, inclusive


def center(r):
    return ((r[0] + r[2]) // 2, (r[1] + r[3]) // 2)


def core_radius(r):
    return max(1, (min(r[2] - r[0], r[3] - r[1]) // 2) - 1)


class LayoutError(Exception):
    pass


def layout(plan, cat):
    """zone rectangles, link points, landing spots and path routes (local 1-based cells). Deterministic."""
    biome = biome_of(plan, cat)
    W_, H_ = plan['size']
    seed = plan_seed(plan)
    rng = random.Random(seed * 31 + 7)
    zones = plan['zones']
    byid = {z['id']: z for z in zones}
    rects = {}
    links = []        # {conn, floor (upper), x, y, upper, lower, type}
    floor_paths = {f: [] for f in range(1, plan['floors'] + 1)}
    spots = {f: [] for f in range(1, plan['floors'] + 1)}
    entry = plan['entry']['zone']
    adj = {}
    for p in plan.get('paths', []):
        adj.setdefault(p['from'], []).append(p['to'])
        adj.setdefault(p['to'], []).append(p['from'])
    lo_x, lo_y, hi_x, hi_y = MARGIN_LO, MARGIN_LO, W_ - MARGIN_HI, H_ - MARGIN_HI

    def fits(r, f):
        if r[0] < lo_x or r[1] < lo_y or r[2] > hi_x or r[3] > hi_y:
            return False
        return not any(rect_overlap(r, q, GAP) for zid, q in rects.items() if byid[zid]['floor'] == f)

    def place(z, target, must=None):
        w, h = zone_dims(z, biome)
        best = None
        for y1 in range(lo_y, hi_y - h + 2):
            for x1 in range(lo_x, hi_x - w + 2):
                r = (x1, y1, x1 + w - 1, y1 + h - 1)
                c = center(r)
                d = (c[0] - target[0]) ** 2 + (c[1] - target[1]) ** 2
                if must and not (r[0] + 1 <= must[0] <= r[2] - 1 and r[1] + 1 <= must[1] <= r[3] - 2):
                    d += 10 ** 6
                key = (d, y1, x1)
                if (best is None or key < best[0]) and fits(r, z['floor']):
                    best = (key, r)
        if not best:
            raise LayoutError('zone %s (%dx%d) does not fit on floor %d of the %dx%d area next to the other zones'
                              % (z['id'], w, h, z['floor'], W_, H_))
        rects[z['id']] = best[1]

    for f in range(1, plan['floors'] + 1):
        fz = [z for z in zones if z['floor'] == f]
        for z in fz:
            if 'at' in z:
                rects[z['id']] = zone_rect_fixed(z, biome)
        # zones reached from the floor above get the hole's point as their target
        incoming = {}
        for l in links:
            if l['floor'] == f - 1:
                incoming.setdefault(l['lower'], (l['x'], l['y']))
        order = [z for z in fz if 'at' not in z and z['id'] in incoming]
        order += [z for z in fz if 'at' not in z and z.get('place') and z not in order]
        # the rest: breadth-first from the placed ones (entry first)
        roots = [z['id'] for z in fz if z['id'] == entry] + [z['id'] for z in fz if z['id'] in incoming or 'at' in z or z.get('place')]
        seen, bfs = set(), []
        q = deque(r for r in roots)
        while q:
            a = q.popleft()
            if a in seen:
                continue
            seen.add(a)
            bfs.append(a)
            for b in adj.get(a, []):
                if byid[b]['floor'] == f and b not in seen:
                    q.append(b)
        for z in fz:
            if z['id'] not in seen:
                bfs.append(z['id'])
        for zid in bfs:
            z = byid[zid]
            if z not in order and 'at' not in z:
                order.append(z)
        for z in order:
            if z['id'] in incoming:
                place(z, incoming[z['id']], must=incoming[z['id']])
            elif z.get('place'):
                fx, fy = COMPASS[z['place']]
                place(z, (int(W_ * fx), int(H_ * fy)))
            else:
                nb = [rects[b] for b in adj.get(z['id'], []) if b in rects and byid[b]['floor'] == f]
                if nb:
                    c = center(nb[0])
                    dx, dy = D8[rng.randrange(8)]
                    w, h = zone_dims(z, biome)
                    dist_x = (nb[0][2] - nb[0][0]) // 2 + w // 2 + GAP + 4
                    dist_y = (nb[0][3] - nb[0][1]) // 2 + h // 2 + GAP + 4
                    place(z, (c[0] + dx * dist_x, c[1] + dy * dist_y))
                else:
                    place(z, (W_ // 2, H_ // 2))
        # link points of the connections from this floor down
        arrival = center(rects[entry]) if byid[entry]['floor'] == f else None
        for i, c in enumerate(plan.get('connections', [])):
            if c['type'] == 'teleport':
                continue
            a, b = byid[c['from']], byid[c['to']]
            up, low = (a, b) if a['floor'] < b['floor'] else (b, a)
            if up['floor'] != f:
                continue
            r = rects[up['id']]
            cx, cy = center(r)
            rad = core_radius(r)
            target = center(rects[low['id']]) if low['id'] in rects else (cx + 2, cy + 1)
            taken = [(l['x'], l['y']) for l in links if l['floor'] == f] + ([arrival] if arrival else [])
            cand = []
            for y in range(r[1] + 1, r[3] - 1):
                for x in range(r[0] + 1, r[2]):
                    if max(abs(x - cx), abs(y - cy)) > rad:
                        continue
                    if any(max(abs(x - t[0]), abs(y - t[1])) < 3 for t in taken):
                        continue
                    d_c = max(abs(x - cx), abs(y - cy))
                    cand.append(((0 if d_c >= 2 else 1), (x - target[0]) ** 2 + (y - target[1]) ** 2, y, x))
            if not cand:
                raise LayoutError('zone %s is too small for the %s of connection %d (make it at least medium)'
                                  % (up['id'], c['type'], i))
            cand.sort()
            _k, _d, y, x = cand[0]
            links.append(dict(conn=i, floor=f, x=x, y=y, upper=up['id'], lower=low['id'], type=c['type']))
        # landings: a hole's point outside the core of its lower zone gets a spot and a path to it
        for l in links:
            if l['floor'] == f - 1:
                r = rects[l['lower']]
                cx, cy = center(r)
                if max(abs(l['x'] - cx), abs(l['y'] - cy)) > core_radius(r) - 1 or zone_shape(byid[l['lower']], biome) != 'room':
                    spots[f].append((l['x'], l['y'], 1))
                    floor_paths[f].append(dict(points=[(l['x'], l['y']), (cx, cy)], width=3, style=default_style(biome),
                                               kind='landing', zones=(None, l['lower'])))
    # path routes
    for i, p in enumerate(plan.get('paths', [])):
        a, b = byid[p['from']], byid[p['to']]
        ra, rb = rects[a['id']], rects[b['id']]
        ca, cb = center(ra), center(rb)
        wd = p.get('width', 3)
        others = [(zid, q) for zid, q in rects.items() if byid[zid]['floor'] == a['floor'] and zid not in (a['id'], b['id'])]

        def cost(pts):
            cells = route_cells(pts, wd)
            c = 0
            for zid, q in others:
                hit = any(q[0] - 1 <= x <= q[2] + 1 and q[1] - 1 <= y <= q[3] + 1 for x, y in cells)
                if hit:
                    c += 1000 if byid[zid].get('role') == 'boss' else 1
            return c
        opts = [[ca, (cb[0], ca[1]), cb], [ca, (ca[0], cb[1]), cb]]
        costs = [cost(o) for o in opts]
        k = 0 if costs[0] < costs[1] else 1 if costs[1] < costs[0] else rng.randrange(2)
        floor_paths[a['floor']].append(dict(points=opts[k], width=wd, style=p.get('style') or default_style(biome),
                                            kind='path', index=i, zones=(a['id'], b['id']), crosses_boss=costs[k] >= 1000))
    anchors = {}
    for f in range(1, plan['floors'] + 1):
        fz = [z for z in zones if z['floor'] == f]
        anchors[f] = center(rects[fz[0]['id']]) if fz else (W_ // 2, H_ // 2)
    return dict(rects=rects, links=links, paths=floor_paths, spots=spots, anchors=anchors, seed=seed,
                arrival=center(rects[entry]))


def route_cells(pts, width):
    """the cells of an axis-aligned route (horizontal, then vertical between points), as the corridor carver opens"""
    half = (width - 1) // 2
    out = set()
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        for x in range(min(ax, bx), max(ax, bx) + 1):
            for d in range(-half, width - half):
                out.add((x, ay + d))
        for y in range(min(ay, by), max(ay, by) + 1):
            for d in range(-half, width - half):
                out.add((bx + d, y))
    return out


# ================================================================================================= tiles
def tile_reach(walk, start, links=(), teleports=()):
    """breadth-first steps over walkable tiles (8 neighbours) from start; links = [(hole, ladder, up)] (stepping on a
    hole drops to the ladder tile, using the ladder climbs to `up`; ladder None = a hole only), teleports = [(from, to)].
    walk is a set of (x, y, z). Returns {tile: steps}."""
    drop, climb, tele = {}, {}, {}
    for hole, ladder, up in links:
        drop[hole] = ladder
        if ladder:
            climb[ladder] = up
    for a, b in teleports:
        tele[a] = b
    dist = {start: 0} if start in walk else {}
    q = deque(dist)
    while q:
        t = q.popleft()
        d = dist[t] + 1
        nxt = [(t[0] + dx, t[1] + dy, t[2]) for dx, dy in D8]
        for special in (drop, climb, tele):
            if t in special and special[t]:
                nxt.append(special[t])
        for n in nxt:
            if n in walk and n not in dist:
                dist[n] = d
                q.append(n)
    return dist


def openings(walk, rect, z):
    """the ways into a rectangle on floor z: groups (8 neighbours) of walkable tiles just outside it that touch a
    walkable tile inside it"""
    x1, y1, x2, y2 = rect
    inside = lambda x, y: x1 <= x <= x2 and y1 <= y <= y2
    door = set()
    for x in range(x1 - 1, x2 + 2):
        for y in range(y1 - 1, y2 + 2):
            if inside(x, y) or (x, y, z) not in walk:
                continue
            if any(inside(x + dx, y + dy) and (x + dx, y + dy, z) in walk for dx, dy in D8):
                door.add((x, y))
    groups = 0
    seen = set()
    for c in sorted(door):
        if c in seen:
            continue
        groups += 1
        stack = [c]
        seen.add(c)
        while stack:
            a = stack.pop()
            for dx, dy in D8:
                n = (a[0] + dx, a[1] + dy)
                if n in door and n not in seen:
                    seen.add(n)
                    stack.append(n)
    return groups


def screen_density(walk_xy, monsters_xy, x0, y0, w, h, min_walk=30):
    """monsters per screen (15 x 11 tiles) over the screens of one floor with min_walk walkable tiles: (mean, max, n)"""
    sw, sh = SCREEN
    vals = []
    for sy in range(y0, y0 + h, sh):
        for sx in range(x0, x0 + w, sw):
            nw = sum(1 for x in range(sx, sx + sw) for y in range(sy, sy + sh) if (x, y) in walk_xy)
            if nw >= min_walk:
                vals.append(sum(c for (x, y), c in monsters_xy.items() if sx <= x < sx + sw and sy <= y < sy + sh))
    if not vals:
        return 0.0, 0, 0
    return sum(vals) / len(vals), max(vals), len(vals)
