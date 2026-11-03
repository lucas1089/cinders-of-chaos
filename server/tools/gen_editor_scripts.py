#!/usr/bin/env python3
"""The map editor's script pack: our area generator and every compiled area plan, for the editor's Lua 5.1 scripts
(docs/MAP_GUIDE.md "Generator in the map editor", O381). The Windows package ships it as mapeditor\\cinders\\
(.github/workflows/windows-package.yml); nothing of it is committed (the plans are rebuilt from their JSON).

    python3 -I server/tools/gen_editor_scripts.py OUT_DIR [--only ID,...] [--no-plans]

OUT_DIR gets (the paths mirror server/, so the scripts work from there in tests/editor_scripts_test.lua):
  generate_area.lua, paint_plan.lua    the entry scripts (tools/editor_scripts/), parameters at the top
  README.txt                           how to run them in the editor
  tools/editor_scripts/cinders_editor.lua, tools/areaplan_build.lua, data/...   the generator and its tables
  monsters.lua                         {name, level, boss} of our monsters (area_plan_core.monsters): the level band
  plans/<id>.lua                       one compiled plan: rows "x y z ground item ..." of its tiles and view frame
  plans/<id>-notes.txt                 what the editor cannot write: spawns, NPCs, boss, action ids, teleport targets,
                                       protection zones
  plans/index.lua, plans/index.txt     the plans with their size, floors and tile counts
The plans: every JSON of server/tools/areaplan/plans, annexes, chronicle, rooms and events, compiled like the install
(area_plan_compile.py at its own origin; an imported hunt by area_import.py). A plan that does not compile stops the
run (exit 1). Needs LuaJIT ($LUAJIT) like area_planner.py.
"""
import json, os, shutil, sys, tempfile
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
sys.path.insert(0, HERE)

# server/ path -> pack path
COPY = [
    ('tools/editor_scripts/generate_area.lua', 'generate_area.lua'),
    ('tools/editor_scripts/paint_plan.lua', 'paint_plan.lua'),
    ('tools/editor_scripts/cinders_editor.lua', 'tools/editor_scripts/cinders_editor.lua'),
    ('tools/areaplan_build.lua', 'tools/areaplan_build.lua'),
    ('data/scripts/chaos/areagen_core.lua', None),
    ('data/scripts/chaos/areagen_config.lua', None),
    ('data/scripts/chaos/rift_config.lua', None),
    ('data/lib/chaos_dark_tiles.lua', None),
    ('data/lib/chaos_theme_items.lua', None),
    ('data/lib/chaos_theme_art.lua', None),
    ('data/lib/chaos_pack33_kit.lua', None),
    ('data/items/art_items.csv', None),
]
PLAN_DIRS = ('plans', 'annexes', 'chronicle', 'rooms', 'events')


class GenError(Exception):
    pass


def crlf(text):
    return text.replace('\r\n', '\n').replace('\n', '\r\n')


def copy_files(out):
    for src, dst in COPY:
        s = os.path.join(SERVER, src)
        d = os.path.join(out, dst or src)
        os.makedirs(os.path.dirname(d), exist_ok=True)
        shutil.copyfile(s, d)
    with open(os.path.join(HERE, 'editor_scripts', 'README.txt'), encoding='utf-8') as f:
        text = f.read()
    with open(os.path.join(out, 'README.txt'), 'w', encoding='utf-8', newline='') as f:
        f.write(crlf(text))


def lua_str(s):
    return '"' + str(s).replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'


def long_str(text):
    eq = '='
    while (']' + eq + ']') in text:
        eq += '='
    return '[' + eq + '[\n' + text + ']' + eq + ']'


def monsters_lua(out):
    import area_plan_core as C
    rows = sorted(C.monsters().values(), key=lambda m: (m['name'].lower(), m['name']))
    lines = ['-- our monsters with their hunting level (server/tools/area_plan_core.py monsters); made by',
             '-- tools/gen_editor_scripts.py for generate_area.lua (the level band of the spawn list)', 'return {']
    for m in rows:
        if m['level'] is None:
            continue
        lines.append('\t{%s, %d, %s},' % (lua_str(m['name']), m['level'], 'true' if m['boss'] else 'false'))
    lines.append('}')
    with open(os.path.join(out, 'monsters.lua'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')
    return len(lines) - 4


def plan_paths(only=None):
    out = []
    for d in PLAN_DIRS:
        base = os.path.join(HERE, 'areaplan', d)
        if not os.path.isdir(base):
            continue
        for name in sorted(os.listdir(base)):
            if name.endswith('.json') and (not only or name[:-5] in only):
                out.append(os.path.join(base, name))
    return out


def compile_into(path, tmp):
    """compile one plan into tmp like the install does; (plan, otbm tiles, frame tiles, spawn xml text, manifest)"""
    import area_import
    import area_plan_compile as P
    with open(path, encoding='utf-8') as f:
        plan = json.load(f)
    pid = plan['id']
    if area_import.is_import(plan):
        try:
            area_import.compile_plan(path, tmp)
        except area_import.ImportError_ as e:
            raise GenError('%s: %s' % (os.path.basename(path), e))
    else:
        try:
            res = P.compile_plan(plan)
        except P.CompileError as e:
            raise GenError('%s: %s' % (os.path.basename(path), e))
        errs = P.qa_errors(res)
        if errs:
            raise GenError('%s: %s' % (os.path.basename(path), '; '.join(errs[:5])))
        P.write_outputs(res, tmp)

    def read(name):
        p = os.path.join(tmp, name)
        if not os.path.exists(p):
            return {}
        with open(p, 'rb') as f:
            _h, tiles, problems = P.read_otbm_full(f.read())
        if problems:
            raise GenError('%s: %s: %s' % (pid, name, '; '.join(problems[:3])))
        return tiles

    tiles = read(pid + '.otbm')
    frame = read(pid + '-frame.otbm')
    spawn = ''
    sp = os.path.join(tmp, pid + '-spawn.xml')
    if os.path.exists(sp):
        with open(sp, encoding='utf-8') as f:
            spawn = f.read()
    man = {}
    mp = os.path.join(tmp, pid + '.json')
    if os.path.exists(mp):
        with open(mp, encoding='utf-8') as f:
            man = json.load(f)
    return plan, tiles, frame, spawn, man


def rows_text(tiles, skip=()):
    lines = []
    for k in sorted(tiles, key=lambda p: (p[2], p[1], p[0])):
        if k in skip:
            continue
        t = tiles[k]
        vals = [k[0], k[1], k[2], t['ground'] or 0] + [i for i, _a in t['items']]
        lines.append(' '.join(str(v) for v in vals))
    return '\n'.join(lines) + ('\n' if lines else '')


def notes_text(plan, tiles, spawn, man):
    """what the editor cannot write, with absolute positions (exact when the plan is painted at its own place)"""
    out = ['%s (%s), biome %s, level %s' % (plan.get('name', plan['id']), plan['id'], plan.get('biome', '?'),
                                            '-'.join(str(v) for v in plan.get('level', [])) or '?'),
           'Positions are the server map\'s: exact when the plan is painted at its own place (the Destination the log',
           'names). Painted elsewhere, add Destination minus that corner.', '']
    mons, npcs = [], []
    if spawn.strip():
        root = ET.fromstring(spawn)
        for s in root.iter('spawn'):
            cx, cy = int(s.get('centerx')), int(s.get('centery'))
            for c in s:
                x, y, z = cx + int(c.get('x', 0)), cy + int(c.get('y', 0)), int(c.get('z', s.get('centerz')))
                row = '%-28s %d %d %d' % (c.get('name'), x, y, z)
                if c.tag == 'npc':
                    npcs.append(row)
                else:
                    mons.append('%s  respawn %s s, radius %s' % (row, c.get('spawntime', '?'), s.get('radius', '?')))
    out.append('Monsters (%d; place them with the creature palette, or keep the server\'s spawn file):' % len(mons))
    out += ['  ' + r for r in mons] or ['  none']
    boss = man.get('boss')
    if boss:
        out.append('Boss: %s at %d %d %d' % (boss.get('monster'), boss['x'], boss['y'], boss['z']))
    out.append('NPCs (%d):' % len(npcs))
    out += ['  ' + r for r in npcs] or ['  none']
    attrs = []
    for k in sorted(tiles, key=lambda p: (p[2], p[1], p[0])):
        for iid, a in tiles[k]['items']:
            if a:
                parts = []
                if 'aid' in a:
                    parts.append('action id %d' % a['aid'])
                if 'uid' in a:
                    parts.append('unique id %d' % a['uid'])
                if 'tele' in a:
                    parts.append('teleport to %d %d %d' % tuple(a['tele']))
                attrs.append('  item %d at %d %d %d: %s' % (iid, k[0], k[1], k[2], ', '.join(parts)))
    out.append('Item attributes to set by hand (%d):' % len(attrs))
    out += attrs or ['  none']
    pz = sorted(k for k, t in tiles.items() if t['flags'] & 1)
    out.append('Protection zone tiles: %d (mark them with the zone tool)' % len(pz))
    for zid, z in sorted((man.get('zones') or {}).items()):
        if z.get('pz'):
            r = z['rect']
            out.append('  zone %s: x %d-%d, y %d-%d, z %d' % (zid, r[0], r[2], r[1], r[3], z['z']))
    return '\n'.join(out) + '\n'


def write_plan(out, path, tmp):
    plan, tiles, frame, spawn, man = compile_into(path, tmp)
    pid = plan['id']
    if not tiles:
        raise GenError('%s: the compile wrote no tiles' % pid)
    origin = man.get('origin')
    if not origin and plan.get('origin'):
        origin = [plan['origin']['x'], plan['origin']['y'], plan['origin']['z']]
    floors = sorted({k[2] for k in tiles})
    per_floor = {z: sum(1 for k in tiles if k[2] == z) + sum(1 for k in frame if k[2] == z and k not in tiles) for z in floors}
    notes = notes_text(plan, tiles, spawn, man)
    text = ['-- %s: made by tools/gen_editor_scripts.py from %s (do not edit); painted by paint_plan.lua' %
            (pid, os.path.relpath(path, SERVER)), 'return {',
            '\tid = %s,' % lua_str(pid), '\tname = %s,' % lua_str(plan.get('name', pid)),
            '\tbiome = %s,' % lua_str(plan.get('biome', '')),
            '\tlevel = {%s},' % ', '.join(str(int(v)) for v in plan.get('level', [])),
            '\torigin = %s,' % ('{x = %d, y = %d, z = %d}' % tuple(origin) if origin else 'nil'),
            '\tfloors = {%s},' % ', '.join(str(z) for z in floors),
            '\ttiles = %s,' % long_str(rows_text(tiles)),
            '\tframe = %s,' % long_str(rows_text(frame, skip=tiles)),
            '\tnotes = %s,' % long_str(notes), '}']
    d = os.path.join(out, 'plans')
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, pid + '.lua'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(text) + '\n')
    with open(os.path.join(d, pid + '-notes.txt'), 'w', encoding='utf-8', newline='') as f:
        f.write(crlf(notes))
    nframe = sum(1 for k in frame if k not in tiles)
    return dict(id=pid, name=plan.get('name', pid), level=plan.get('level', []), floors=floors, tiles=len(tiles),
                frame=nframe, per_floor=per_floor, folder=os.path.basename(os.path.dirname(path)))


def write_index(out, entries):
    d = os.path.join(out, 'plans')
    os.makedirs(d, exist_ok=True)
    lua = ['-- the compiled plans (tools/gen_editor_scripts.py)', 'return {']
    txt = ['The area plans of this package (paint_plan.lua: plan = "<id>"). A plan over 100,000 tiles is painted',
           'one floor per run (floor = <z>). Tiles = area + view frame.', '',
           '%-28s %-10s %-11s %-12s %s' % ('id', 'levels', 'floors (z)', 'tiles', 'name')]
    for e in entries:
        lua.append('\t{id = %s, name = %s, tiles = %d, frame = %d, floors = {%s}},' % (
            lua_str(e['id']), lua_str(e['name']), e['tiles'], e['frame'], ', '.join(str(z) for z in e['floors'])))
        big = max(e['per_floor'].values()) > 100000 or e['tiles'] + e['frame'] > 100000
        txt.append('%-28s %-10s %-11s %-12s %s%s' % (
            e['id'], '-'.join(str(v) for v in e['level']) or '-', ','.join(str(z) for z in e['floors']),
            '%d' % (e['tiles'] + e['frame']), e['name'], '  (one floor per run)' if big else ''))
    lua.append('}')
    with open(os.path.join(d, 'index.lua'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lua) + '\n')
    with open(os.path.join(d, 'index.txt'), 'w', encoding='utf-8', newline='') as f:
        f.write(crlf('\n'.join(txt) + '\n'))


def build(out, only=None, plans=True, log=print):
    os.makedirs(out, exist_ok=True)
    copy_files(out)
    n = monsters_lua(out)
    log('%s: scripts, generator tables, %d monsters' % (out, n))
    entries = []
    if plans:
        paths = plan_paths(only)
        if only and len(paths) != len(only):
            found = {os.path.basename(p)[:-5] for p in paths}
            raise GenError('no plan named ' + ', '.join(sorted(set(only) - found)))
        for path in paths:
            tmp = tempfile.mkdtemp(prefix='editor_plan_')
            try:
                e = write_plan(out, path, tmp)
            finally:
                shutil.rmtree(tmp, ignore_errors=True)
            entries.append(e)
            log('  %-28s %6d tiles + %6d frame, floors %s' % (e['id'], e['tiles'], e['frame'], e['floors']))
        write_index(out, entries)
    return entries


def main(argv):
    args = list(argv)
    only = None
    plans = True
    if '--no-plans' in args:
        args.remove('--no-plans')
        plans = False
    if '--only' in args:
        k = args.index('--only')
        only = [s for s in args[k + 1].split(',') if s]
        del args[k:k + 2]
    if len(args) != 1:
        print(__doc__)
        return 2
    try:
        build(args[0], only, plans)
    except GenError as e:
        print('ERROR: %s' % e, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
