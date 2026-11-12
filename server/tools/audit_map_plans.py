#!/usr/bin/env python3
"""Run the map tile audit over the compiled area plans (server/README.md "Map tile audit (O511)", "Run over the planned areas").

usage: python3 -I server/tools/audit_map_plans.py [PLAN.json ...] [--dir DIR] [--csv OUT] [--check] [--limit N] [--quiet]

Each plan (default: every file of tools/areaplan/plans) is compiled in memory the way `area_planner.py compile` does, the
area and its view frame are written as one OTBM into a temporary folder, and tools/audit_map_tiles.py runs over it. The
base server's items.otb is not in git, so the item database is built from what the generator itself knows (the ground
slot is a ground, the pieces of areagen_config.lua `pieces` are borders, `walls` are blocking walls, the decoration kits'
blocking groups and the themes' obstacles, lights and props block, the portal is a teleport, the hole, the ladder and the
stairs change the floor, the kit roof ground is a roof). So UNKNOWN_ID cannot fire here and every blocking flag is the
generator's own belief, not the live items.otb's; the structure rules (ground first, borders, walls, doors, teleports,
roofs, item counts) are what this run tests. Needs luajit (the generator) and numpy. --check exits 1 when any plan has
a finding. Read only: nothing but the temporary folder is written.
"""
import glob
import json
import os
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
ROOT = os.path.dirname(SERVER)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'map'))

import audit_map_tiles as A  # noqa: E402

PLANS = os.path.join(HERE, 'areaplan', 'plans')


class TableDB:
    """the item database of the generator's own tables, in the shape audit_map_tiles.World reads"""

    def __init__(self, tiles, cfg, kits, portal_id):
        from itemdb import C
        N = 65536
        self.known = np.zeros(N, bool)
        self.group = np.zeros(N, np.uint8)
        self.flags = np.zeros(N, np.uint32)
        self.order = np.zeros(N, np.uint8)
        self.cls = np.full(N, C['other'], np.uint8)
        self.name = [''] * N
        ids = set()
        grounds = set()
        for t in tiles.values():
            if t['ground']:
                grounds.add(t['ground'])
            ids.update(i for i, _a in t['items'])
        for i in grounds | ids:
            self.known[i] = True
        for g in grounds:
            self.group[g] = 1
            self.cls[g] = C['ground']
        dark = A.dark_ids()

        def ident(v):
            return v if isinstance(v, int) else dark.get(v)
        for pieces in cfg['pieces'].values():
            for v in pieces.values():
                i = ident(v)
                if i is not None and i not in grounds:
                    self.order[i], self.cls[i] = 1, C['border']
        solid = set()
        for kinds in cfg['walls'].values():
            for rows in kinds.values():
                for row in rows:
                    i = ident(row[0])
                    if i is not None:
                        self.order[i], self.cls[i] = 2, C['wall']
                        solid.add(i)
        for theme in cfg['themes'].values():
            for part in [theme] + ([theme['dark']] if isinstance(theme.get('dark'), dict) else []):
                for key in ('obstacles', 'lights', 'props'):
                    for row in (part.get(key) or {}).get('items', []):
                        i = ident(row[0])
                        if i is not None:
                            solid.add(i)
        for g in kits['groups'].values():
            if g.get('block'):
                solid.update(g['ids'])
        for i in solid:
            if i not in grounds:
                self.flags[i] |= 1
        self.group[portal_id] = 7
        for i in (cfg['items']['hole'], cfg['items']['ladder'], kits['brushes']['stairs_up']):
            self.cls[i] = C['floorchg']
        for i in kits['roof']['ground']:
            self.name[i] = 'flat roof'
        # a ground family per generator family (the border rule reads it)
        self.fam = np.zeros(N, np.int32)
        for n, (_fam, d) in enumerate(sorted(cfg['families'].items()), 1):
            for g in d['grounds']:
                i = ident(g[0] if isinstance(g, list) else g)
                if i is not None:
                    self.fam[i] = n

    def ground_family(self):
        return self.fam


def audit_plan(plan_file, log=print):
    """-> (plan id, Findings, tiles) for one compiled plan; None for a plan that does not compile"""
    import area_import
    import area_plan_compile as PC
    import area_plan_decor as D
    import otbm
    plan = json.load(open(plan_file, encoding='utf-8'))
    if area_import.is_import(plan):
        return None
    try:
        res = PC.compile_plan(plan)
    except PC.CompileError as e:
        log('%s: does not compile: %s' % (plan['id'], str(e).splitlines()[0]))
        return None
    tiles = dict(res['frame'])
    tiles.update(res['tiles'])
    data = PC.otbm_bytes(plan['name'], plan['id'], 'audit', tiles, 'x-spawn.xml', 'x-house.xml')
    cfg = A.read_lua_return_table(A.AREAGEN_CONFIG)
    portal = cfg['items']['portal']
    db = TableDB(tiles, cfg, D.kits(), portal)
    with tempfile.TemporaryDirectory(prefix='audit_map_plans_') as tmp:
        path = os.path.join(tmp, plan['id'] + '.otbm')
        with open(path, 'wb') as f:
            f.write(data)
        m = otbm.load_otbm(path)
    found = otbm.teleports(m, {portal})
    m._raw = None
    w = A.World(m, db, doors=(), teles={portal}, roofs=(), tables=A.load_tables())
    return plan['id'], A.audit(w, teles_found=found), tiles


def main(argv):
    opts, pos, i = {}, [], 0
    while i < len(argv):
        a = argv[i]
        if a in ('--dir', '--csv', '--limit'):
            if i + 1 >= len(argv):
                print('%s needs a value' % a)
                return 1
            opts[a] = argv[i + 1]
            i += 1
        elif a in ('--check', '--quiet'):
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
    log = (lambda *_: None) if opts.get('--quiet') else print
    files = pos or sorted(glob.glob(os.path.join(opts.get('--dir', PLANS), '*.json')))
    limit = int(opts.get('--limit', 5))
    totals = {c: 0 for c in A.CODES}
    plans_with = 0
    rows = []
    n = 0
    for fpath in files:
        got = audit_plan(fpath, log)
        if got is None:
            continue
        n += 1
        pid, f, _tiles = got
        counts = {c: f.count(c) for c in A.CODES if f.count(c)}
        for c, v in counts.items():
            totals[c] += v
        if counts:
            plans_with += 1
            log('%-28s %s' % (pid, ', '.join('%s %d' % kv for kv in counts.items())))
            for c in counts:
                for k, (x, y, z, t) in enumerate(f.rows(c)):
                    if k >= limit:
                        break
                    log('    %s %d,%d,%d ids=%s fix=%s' % (c, x, y, z, t, A.FIX[c]))
                    rows.append((pid, c, x, y, z, t))
        else:
            rows.append((pid, '', 0, 0, 0, ''))
    log('%d plans audited, %d with findings; totals: %s' % (
        n, plans_with, ', '.join('%s %d' % (c, v) for c, v in totals.items() if v) or 'none'))
    if '--csv' in opts:
        import csv
        with open(opts['--csv'], 'w', encoding='utf-8', newline='') as fh:
            wr = csv.writer(fh, lineterminator='\n')
            wr.writerow(['plan', 'code', 'x', 'y', 'z', 'ids'])
            wr.writerows(r for r in rows if r[1])
    return 1 if opts.get('--check') and plans_with else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
