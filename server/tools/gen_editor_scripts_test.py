#!/usr/bin/env python3
"""Tests for gen_editor_scripts.py (the map editor's script pack, O381): a pack with three real plans (a planned hunt,
an imported hunt, a two-floor room) and the generator tables; every Lua file of it parses; paint_plan.lua run in the
pack against the stand-in of the editor's runner (editor_scripts/dme_mock.lua, LuaJIT and Lua 5.1 when installed)
writes exactly the compiled tiles and frame, the same rows as the compiled .otbm; generate_area.lua takes its monsters
from the pack's monsters.lua; the notes name the spawns.

    python3 -I server/tools/gen_editor_scripts_test.py
"""
import os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_editor_scripts as G

PLANS = ['thistlewood_hollow', 'brickhold_depths', 'idle_hall']
MOCK = os.path.join(HERE, 'editor_scripts', 'dme_mock.lua')
RUN = r'''
local mock = dofile(arg[1])
local params = {}
for k = 4, #arg, 2 do params[arg[k]] = tonumber(arg[k + 1]) or arg[k + 1] end
local r = mock.run(arg[3], {root = arg[2], seed = 11, params = params})
local zs = {}
for _, t in pairs(r.tiles) do zs[t.z] = true end
local n = 0
for _ in pairs(zs) do n = n + 1 end
io.write(tostring(r.ok), " ", r.count, " ", r.items, " ", n, "\n", tostring(r.error), "\n", table.concat(r.log, "\n"), "\n")
'''

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


def lua_bins():
    out = []
    for b in ('luajit', 'lua5.1'):
        if shutil.which(b):
            out.append(b)
    return out


def run_lua(binary, runner, root, script, **params):
    args = [binary, runner, MOCK, root + '/', script]
    for k, v in params.items():
        args += [k, str(v)]
    res = subprocess.run(args, capture_output=True, text=True)
    lines = res.stdout.split('\n')
    head = lines[0].split() if lines and lines[0] else ['false', '0', '0', '0']
    return dict(ok=head[0] == 'true', count=int(head[1]), items=int(head[2]), floors=int(head[3]),
                error=lines[1] if len(lines) > 1 else res.stderr, log='\n'.join(lines[2:]), stderr=res.stderr)


def main():
    tmp = tempfile.mkdtemp(prefix='editor_pack_test_')
    try:
        out = os.path.join(tmp, 'cinders')
        entries = G.build(out, only=PLANS, log=lambda *_a: None)
        check(sorted(e['id'] for e in entries) == sorted(PLANS), 'the three plans: %s' % [e['id'] for e in entries])
        for rel in ('generate_area.lua', 'paint_plan.lua', 'README.txt', 'monsters.lua', 'plans/index.lua', 'plans/index.txt',
                    'tools/editor_scripts/cinders_editor.lua', 'tools/areaplan_build.lua',
                    'data/scripts/chaos/areagen_core.lua', 'data/items/art_items.csv'):
            check(os.path.isfile(os.path.join(out, rel)), 'the pack has ' + rel)
        check(not os.path.exists(os.path.join(out, 'dme_mock.lua')) and
              not os.path.exists(os.path.join(out, 'tools', 'editor_scripts', 'dme_mock.lua')), 'the test stand-in is not shipped')
        with open(os.path.join(out, 'README.txt'), 'rb') as f:
            check(b'\r\n' in f.read(), 'README.txt has Windows line ends')
        # every Lua file parses in the editor's Lua (luac5.1 when installed)
        if shutil.which('luac5.1'):
            for dirpath, _d, files in os.walk(out):
                for f in files:
                    if f.endswith('.lua'):
                        p = os.path.join(dirpath, f)
                        r = subprocess.run(['luac5.1', '-p', p], capture_output=True, text=True)
                        check(r.returncode == 0, 'Lua 5.1 parses %s: %s' % (os.path.relpath(p, out), r.stderr.strip()))
        by_id = {e['id']: e for e in entries}
        check(by_id['idle_hall']['floors'] == [6, 7], 'idle_hall has two floors: %s' % by_id['idle_hall']['floors'])
        notes = open(os.path.join(out, 'plans', 'thistlewood_hollow-notes.txt'), encoding='utf-8').read()
        check('Monsters (' in notes and 'respawn' in notes, 'the notes list the monsters')
        runner = os.path.join(tmp, 'run.lua')
        with open(runner, 'w') as f:
            f.write(RUN)
        bins = lua_bins()
        check(bins, 'luajit or lua5.1 installed')
        for b in bins:
            for pid in PLANS:
                e = by_id[pid]
                r = run_lua(b, runner, out, 'paint_plan.lua', plan=pid)
                check(r['ok'], '%s %s: paints (%s %s)' % (b, pid, r['error'], r['stderr'][-300:]))
                check(r['count'] == e['tiles'] + e['frame'], '%s %s: %d tiles written, %d compiled + %d frame' % (
                    b, pid, r['count'], e['tiles'], e['frame']))
                check(r['floors'] == len(e['floors']), '%s %s: every floor' % (b, pid))
                r3 = run_lua(b, runner, out, 'paint_plan.lua', plan=pid, floor=e['floors'][-1])
                check(r3['ok'] and r3['floors'] == 1 and r3['count'] == e['per_floor'][e['floors'][-1]],
                      '%s %s: one floor (%d, expected %d)' % (b, pid, r3['count'], e['per_floor'][e['floors'][-1]]))
            r = run_lua(b, runner, out, 'generate_area.lua', biome='crypt', width=60, height=50, spawnFile='spawns_test.txt')
            check(r['ok'] and r['count'] > 500, '%s generate_area with the pack monsters: %s' % (b, r['error']))
            check('spawn points' in r['log'], '%s: the log lists the spawns' % b)
            check(os.path.isfile(os.path.join(out, 'spawns_test.txt')), '%s: the spawn list next to the script' % b)
        # the rows are the compiled map's tiles
        tmpc = os.path.join(tmp, 'c')
        os.makedirs(tmpc)
        _plan, tiles, _frame, _sp, _man = G.compile_into(os.path.join(HERE, 'areaplan', 'plans', 'thistlewood_hollow.json'), tmpc)
        text = open(os.path.join(out, 'plans', 'thistlewood_hollow.lua'), encoding='utf-8').read()
        body = text.split('tiles = [=[\n', 1)[1].split(']=]', 1)[0] if 'tiles = [=[' in text else \
            text.split('tiles = [[\n', 1)[1].split(']]', 1)[0]
        rows = {}
        for line in body.strip().split('\n'):
            v = [int(x) for x in line.split()]
            rows[(v[0], v[1], v[2])] = (v[3], v[4:])
        check(len(rows) == len(tiles), 'one row per compiled tile')
        same = all(rows.get(k) == (t['ground'] or 0, [i for i, _a in t['items']]) for k, t in tiles.items())
        check(same, 'every row is the compiled tile (ground and items in order)')
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print('gen_editor_scripts: %s' % ('ok' if not fails else '%d failed' % fails))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
