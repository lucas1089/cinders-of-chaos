#!/usr/bin/env python3
"""Bounty board monster pool (data/scripts/chaos/bounty_pool.lua) from the map that is really loaded.

usage: python3 -I gen_bounty_pool.py DATA_DIR [OUT_FILE] [--spawn PATH] [--config PATH] [--csv PATH]

Reads
  - the spawn file of the loaded map: DATA_DIR/world/<mapName>-spawn.xml, mapName from config.lua
    (default DATA_DIR/../config.lua), or --spawn PATH
  - the monster definitions: DATA_DIR/monster/monsters.xml (name -> XML file) and every Lua monster under
    DATA_DIR/monster/ (Game.createMonsterType("Name"))
and writes OUT_FILE (default: data/scripts/chaos/bounty_pool.lua next to this tools folder, i.e. the repo copy) as a
plain Lua table: every monster that spawns on the map with its spawn count, experience, health, outfit and an
estimated hunting level (see estimate_level). bounty.lua picks the daily contracts from it per level band.

Rerun it after any change to the spawn file (for example after tools/late_game.py) or to monster experience/health.
The output is sorted and carries no date, so a rerun without changes gives the same file. --csv writes every
spawned monster (also the rejected ones, with the reason) for review.
"""
import glob, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.join(HERE, '..', 'data', 'scripts', 'chaos', 'bounty_pool.lua')

MIN_SPAWNS = 6           # hunt/elite targets need at least this many spawn entries on the map
MIN_EXP = 1              # experience 0 = scenery / training monsters
BOSS_MAX_SPAWNTIME = 4 * 3600  # bosses that respawn slower than this are not doable in a day
# names that the project's CI name check (tools/ci/check_names.py) would reject are never written to the pool; the
# pattern is read from that file so it is not repeated here
def _deny_pattern():
    path = os.path.join(HERE, '..', '..', 'tools', 'ci', 'check_names.py')
    try:
        text = open(path, encoding='utf-8').read()
    except OSError:
        return None
    m = re.search(r"DENY = re\.compile\((r'.*?'\s*(?:r'.*?')?)\s*,\s*re\.I\)", text, re.S)
    if not m:
        return None
    pattern = ''.join(re.findall(r"r'(.*?)'", m.group(1), re.S))
    return re.compile(pattern, re.I)


DENY = _deny_pattern()


def read(path):
    with open(path, encoding='utf-8', errors='replace') as f:
        return f.read()


def attr(tag, name):
    m = re.search(r'\b%s\s*=\s*"([^"]*)"' % name, tag)
    return m.group(1) if m else None


def num(v, default=0):
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return default


def map_name(config_text):
    m = re.search(r'^\s*mapName\s*=\s*"([^"]+)"', config_text, re.M)
    return m.group(1) if m else None


def parse_spawns(text):
    """{lower name: {'name', 'count', 'spawntime' (min seen)}}"""
    out = {}
    for m in re.finditer(r'<monster\s[^>]*?/?>', text):
        tag = m.group(0)
        name = attr(tag, 'name')
        if not name:
            continue
        e = out.setdefault(name.lower(), {'name': name, 'count': 0, 'spawntime': None})
        e['count'] += 1
        st = num(attr(tag, 'spawntime'), 60)
        e['spawntime'] = st if e['spawntime'] is None else min(e['spawntime'], st)
    return out


def parse_xml_monster(path):
    t = read(path)
    head = re.search(r'<monster\s[^>]*>', t)
    if not head:
        return None
    h = head.group(0)
    m = {'name': attr(h, 'name') or '', 'exp': num(attr(h, 'experience')), 'health': 0, 'look': 0, 'lookTypeEx': 0,
         'boss': False, 'hostile': True, 'attackable': True, 'minLevel': 0, 'maxLevel': 0, 'src': 'xml'}
    hp = re.search(r'<health\s[^>]*>', t)
    if hp:
        m['health'] = num(attr(hp.group(0), 'max'))
    look = re.search(r'<look\s[^>]*>', t)
    if look:
        m['look'] = num(attr(look.group(0), 'type'))
        m['lookTypeEx'] = num(attr(look.group(0), 'typeex'))
        for k in ('head', 'body', 'legs', 'feet', 'addons'):
            m['look_' + k] = num(attr(look.group(0), k))
    lv = re.search(r'<level\s[^>]*>', t)
    if lv:
        m['minLevel'], m['maxLevel'] = num(attr(lv.group(0), 'min')), num(attr(lv.group(0), 'max'))
    for f in re.finditer(r'<flag\s+(\w+)\s*=\s*"([^"]*)"', t):
        k, v = f.group(1).lower(), f.group(2)
        if k in ('isboss', 'rewardboss') and v not in ('0', 'false'):
            m['boss'] = True
        elif k == 'hostile':
            m['hostile'] = v not in ('0', 'false')
        elif k == 'attackable':
            m['attackable'] = v not in ('0', 'false')
    return m


def lua_field(t, key):
    m = re.search(r'^\s*monster\.%s\s*=\s*([^\n]+)' % key, t, re.M)
    return m.group(1).strip().rstrip(',') if m else None


def parse_lua_monsters(path):
    t = read(path)
    names = re.findall(r'Game\.createMonsterType\(\s*"([^"]+)"\s*\)', t)
    if len(names) != 1:
        return []  # files that define several types or none are skipped (rare; review with --csv)
    m = {'name': names[0], 'exp': num(lua_field(t, 'experience')), 'health': num(lua_field(t, 'maxHealth')),
         'look': 0, 'lookTypeEx': 0, 'boss': False, 'hostile': True, 'attackable': True, 'minLevel': 0, 'maxLevel': 0,
         'src': 'lua'}
    lt = re.search(r'monster\.outfit\s*=\s*\{([^}]*)\}', t, re.S)
    if lt:
        o = lt.group(1)
        g = lambda k: num((re.search(r'\b%s\s*=\s*(\d+)' % k, o) or [None, 0])[1])
        m['look'], m['lookTypeEx'] = g('lookType'), g('lookTypeEx')
        m['look_head'], m['look_body'], m['look_legs'], m['look_feet'], m['look_addons'] = (
            g('lookHead'), g('lookBody'), g('lookLegs'), g('lookFeet'), g('lookAddons'))
    fl = re.search(r'monster\.flags\s*=\s*\{(.*?)\n\}', t, re.S)
    if fl:
        f = fl.group(1)
        if re.search(r'\b(rewardBoss|isBoss)\s*=\s*true', f):
            m['boss'] = True
        if re.search(r'\bhostile\s*=\s*false', f):
            m['hostile'] = False
        if re.search(r'\battackable\s*=\s*false', f):
            m['attackable'] = False
    if re.search(r'monster\.bosstiary\s*=', t):
        m['boss'] = True
    return [m]


def load_monsters(data_dir):
    mons = {}
    reg = os.path.join(data_dir, 'monster', 'monsters.xml')
    if os.path.exists(reg):
        for tag in re.findall(r'<monster\s[^>]*?/?>', read(reg)):
            name, f = attr(tag, 'name'), attr(tag, 'file')
            path = os.path.join(data_dir, 'monster', f or '')
            if not name or not f or not os.path.exists(path):
                continue
            m = parse_xml_monster(path)
            if m:
                m['name'] = m['name'] or name
                mons[name.lower()] = m
    for path in sorted(glob.glob(os.path.join(data_dir, 'monster', '**', '*.lua'), recursive=True)):
        for m in parse_lua_monsters(path):
            mons.setdefault(m['name'].lower(), m)  # monsters.xml wins, as in the engine (loaded first)
    return mons


def estimate_level(m):
    """The character level this monster is a fair hunt for.
    Level-scaled monsters (<level min max>) use the middle of their range. Others: 1.6 x sqrt(experience), which puts
    a Dragon (700) at 42, a Hydra (2100) at 73, a Demon (6000) at 124 and a 20000 exp monster at 226, raised by
    health when a monster is much tougher than its experience says (health / 60 ~ the level at which it dies quickly)."""
    if m['minLevel'] > 0 and m['maxLevel'] >= m['minLevel']:
        return (m['minLevel'] + m['maxLevel']) // 2
    by_exp = 1.6 * (max(m['exp'], 1) ** 0.5)
    by_hp = m['health'] / 60.0
    lvl = max(by_exp, min(by_hp, by_exp * 1.5))
    return max(1, int(round(lvl)))


def build(data_dir, spawn_path):
    spawns = parse_spawns(read(spawn_path))
    mons = load_monsters(data_dir)
    hunt, bosses, rows = [], [], []
    for key, s in sorted(spawns.items()):
        m = mons.get(key)
        reason = ''
        if not m:
            reason = 'no definition'
        elif DENY and DENY.search(m['name']):
            reason = 'name rejected by the name check'
        elif not m['attackable'] or not m['hostile']:
            reason = 'not hostile/attackable'
        elif m['exp'] < MIN_EXP:
            reason = 'no experience'
        if m:
            lvl = estimate_level(m)
            entry = {'name': m['name'], 'level': lvl, 'exp': m['exp'], 'health': m['health'], 'spawns': s['count'],
                     'look': m['look'], 'outfit': [m.get('look_' + k, 0) for k in ('head', 'body', 'legs', 'feet', 'addons')],
                     'spawntime': s['spawntime']}
            if not reason and m['boss']:
                if s['spawntime'] <= BOSS_MAX_SPAWNTIME:
                    bosses.append(entry)
                    reason = 'boss'
                else:
                    reason = 'boss with respawn %ds (above %d)' % (s['spawntime'], BOSS_MAX_SPAWNTIME)
            elif not reason and s['count'] < MIN_SPAWNS:
                reason = 'only %d spawn(s)' % s['count']
            elif not reason:
                hunt.append(entry)
                reason = 'hunt'
            rows.append((m['name'], lvl, m['exp'], m['health'], s['count'], s['spawntime'], m['minLevel'], m['maxLevel'], reason))
        else:
            rows.append((s['name'], 0, 0, 0, s['count'], s['spawntime'], 0, 0, reason))
    key = lambda e: (e['level'], e['name'].lower())
    return sorted(hunt, key=key), sorted(bosses, key=key), rows


def lua_string(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def render(hunt, bosses, spawn_name):
    def line(e):
        outfit = e['outfit']
        extra = ''
        if any(outfit):
            extra = ', head = %d, body = %d, legs = %d, feet = %d, addons = %d' % tuple(outfit)
        return '\t\t{name = %s, level = %d, exp = %d, health = %d, spawns = %d, look = %d%s},' % (
            lua_string(e['name']), e['level'], e['exp'], e['health'], e['spawns'], e['look'], extra)

    out = [
        '-- Bounty board monster pool (bounty.lua). GENERATED by server/tools/gen_bounty_pool.py: do not edit by hand,',
        '-- rerun the tool after changing spawns (e.g. tools/late_game.py) or monster experience/health.',
        '-- Source: %s and the monster definitions of the same data folder.' % spawn_name,
        '-- level = estimated hunting level (middle of <level min max> for level-scaled monsters, else from experience',
        '-- and health); spawns = spawn entries on the map; look = outfit look type (window preview).',
        '-- hunt: %d monsters with at least %d spawns. bosses: %d (boss flag, respawn up to %d s).' % (
            len(hunt), MIN_SPAWNS, len(bosses), BOSS_MAX_SPAWNTIME),
        '',
        'return {',
        '\thunt = {',
    ]
    out += [line(e) for e in hunt]
    out += ['\t},', '\tbosses = {']
    out += [line(e) for e in bosses]
    out += ['\t}', '}', '']
    return '\n'.join(out)


def main():
    argv = sys.argv[1:]
    opts = {}
    for k in ('--spawn', '--config', '--csv'):
        if k in argv:
            i = argv.index(k)
            opts[k] = argv[i + 1]
            del argv[i:i + 2]
    if not argv or len(argv) > 2:
        print(__doc__)
        return 1
    data_dir = argv[0]
    out_path = argv[1] if len(argv) == 2 else DEFAULT_OUT
    spawn_path = opts.get('--spawn')
    if not spawn_path:
        cfg_path = opts.get('--config', os.path.join(data_dir, '..', 'config.lua'))
        name = map_name(read(cfg_path))
        if not name:
            print(f'{cfg_path}: mapName not found, pass --spawn')
            return 1
        spawn_path = os.path.join(data_dir, 'world', name + '-spawn.xml')
    hunt, bosses, rows = build(data_dir, spawn_path)
    text = render(hunt, bosses, 'world/<mapName>-spawn.xml')
    with open(out_path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    if '--csv' in opts:
        import csv
        with open(opts['--csv'], 'w', newline='', encoding='utf-8') as f:
            w = csv.writer(f)
            w.writerow(['name', 'level', 'exp', 'health', 'spawns', 'spawntime', 'minlevel', 'maxlevel', 'result'])
            w.writerows(sorted(rows, key=lambda r: (r[1], r[0])))
    print(f'{out_path}: {len(hunt)} hunt monsters, {len(bosses)} bosses ({len(rows)} spawned names)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
