#!/usr/bin/env python3
"""Area planner: semantic area plans -> tiles with our area generator -> QA -> previews (docs/MAP_GUIDE.md "Area planner").

A plan (JSON, schema server/tools/areaplan/schema.json, examples in server/tools/areaplan/examples/) names a biome,
zones, paths, connections, spawns, a boss, NPCs, chests, entry, exit, protection zones, decoration and light. It never
holds an item id: every id comes from our own tables (areagen_config.lua and the other catalogues read by
tools/areaplan_build.lua).

    python3 -I server/tools/area_planner.py validate PLAN.json [--json]
    python3 -I server/tools/area_planner.py compile PLAN.json OUT_DIR [--pair24 on|off] [--dark]
    python3 -I server/tools/area_planner.py render PLAN.json OUT_DIR ITEMS.otb ITEMS.xml Tibia.dat Tibia.spr [--scale 0.5]
    python3 -I server/tools/area_planner.py stats PLAN.json [--json]
    python3 -I server/tools/area_planner.py approve PLAN.json [--note TEXT]         (adds it to the knowledge base)
    python3 -I server/tools/area_planner.py suggest BIOME LEVEL_LO LEVEL_HI [--json]
    python3 -I server/tools/area_planner.py similar PLAN.json [-n 5]
    python3 -I server/tools/area_planner.py catalogue [--monsters] [--npcs] [--json]
    python3 -I server/tools/area_planner.py plan --from-prompt "TEXT" [--out PLAN.json] [--level LO HI]
    python3 -I server/tools/area_planner.py place OUT/<id>.otbm WORLD.otbm COPY.otbm --at X Y Z [--spawn WORLD-spawn.xml COPY-spawn.xml]
    python3 -I server/tools/area_planner.py install OUT SERVER_DIR [--dry-run]
    python3 -I server/tools/area_planner.py check-kits ITEMS.otb ITEMS.xml Tibia.dat

validate  the schema and the game rules (reachability, monsters and level tiers, PZ, boss room, links, sizes); exit 1
          on an error. Each line: LEVEL path: message. Fix: hint.
compile   OUT_DIR/<id>.otbm (OTBM 2, items 3.57, for the map editor), <id>-frame.otbm (the view frame: bare rock on every
          spot within 9 x 7 of a walkable tile that has no tile), <id>-spawn.xml (monsters, boss, NPCs) and <id>.json
          (zones, chests with their quest keys, portals, links, stats, QA); exit 1 on a QA error.
render    compile, then OUT_DIR/<id>_z<z>.png per floor (the area with its view frame) with the client sprites and <id>_map.png (minimap colours and
          marks). Review only: the pair stays out of git and the pictures are not published.
stats     walkable tiles, monsters, density per 100 tiles and per screen, steps from the entry to the boss and zones.
suggest   numbers from the approved plans of a biome near a level band, and our monsters and bosses of that band.
similar   the approved plans closest to a plan.
          --no-dress leaves out the decoration pass (to compare before and after).
place     paste a compiled area into a COPY of the world map (never the world file) at X Y Z: refused when a tile lands
          on a world tile; with --spawn also a copy of the world spawn file with the area's spawns; the chest script's
          ORIGIN follows the area.
install   copy OUT/data/... (the quest chest script, new NPCs) into a server's data folder; idempotent, refuses a
          clash of action id, storage or file.
check-kits every id of the decoration kits, stair brush and roof against items.otb, items.xml and the pair (known,
          has a sprite, blocks or not as the kit says, gives light, floor change); exit 1 on a problem.
plan      ask an LLM for a plan (only with an endpoint set in the environment; see area_plan_ai.py), with up to 3 fix
          rounds on the validator's errors. Without one it says how to set one up and exits.
The knowledge base: $AREAPLAN_KB or ~/.local/share/cinders-of-chaos/area_planner/kb.sqlite3 (outside git).
Needs LuaJIT (LUAJIT=... to point elsewhere); render also numpy and Pillow.
"""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import area_plan_core as C


def _opt(args, name, default=None, n=1):
    if name in args:
        k = args.index(name)
        v = args[k + 1:k + 1 + n]
        del args[k:k + 1 + n]
        return v[0] if n == 1 else v
    return default


def _flag(args, name):
    if name in args:
        args.remove(name)
        return True
    return False


def load_plan(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def main(argv):
    args = list(argv)
    as_json = _flag(args, '--json')
    dark = _flag(args, '--dark')
    dress = not _flag(args, '--no-dress')
    p24 = _opt(args, '--pair24')
    pair24 = None if p24 is None else p24 == 'on'
    if not args:
        print(__doc__)
        return 2
    cmd = args.pop(0)
    if cmd in ('validate', 'compile') and args:
        import area_import  # an imported hunt (docs/MAP_GUIDE.md "Imported hunts") is checked and compiled by its own tool
        if area_import.is_import(load_plan(args[0])):
            return area_import.main([cmd] + args)
    if cmd == 'validate':
        plan = load_plan(args[0])
        issues = C.validate(plan, pair24=pair24)
        if as_json:
            print(json.dumps([i.as_dict() for i in issues], indent=1))
        else:
            for i in issues:
                print(i)
            print('%d error(s), %d warning(s)' % (len(C.errors(issues)), len(issues) - len(C.errors(issues))))
        return 1 if C.errors(issues) else 0
    if cmd in ('compile', 'stats', 'render', 'approve'):
        import area_plan_compile as PC
        note = _opt(args, '--note', '')
        scale = float(_opt(args, '--scale', '0.5'))
        plan = load_plan(args[0])
        try:
            res = PC.compile_plan(plan, pair24=pair24, dark=dark, dress=dress)
        except PC.CompileError as e:
            print(e)
            return 1
        for lvl, m in res['qa']:
            print('%s %s' % (lvl, m))
        errs = PC.qa_errors(res)
        if cmd == 'compile':
            for p in PC.write_outputs(res, args[1]):
                print(p)
        elif cmd == 'render':
            PC.write_outputs(res, args[1])
            for p, miss in PC.render_floors(res, args[1], args[2], args[3], args[4], args[5], scale):
                print(p, ('(%d items without a sprite in this pair)' % miss) if miss else '')
        elif cmd == 'stats':
            s = res['stats']
            if as_json:
                print(json.dumps(s, indent=1, sort_keys=True))
            else:
                print('%s: %d tiles, %d walkable, %d monsters on %d points, %.2f per 100 walkable'
                      % (plan['id'], s['tiles'], s['walkable'], s['monsters'], s['spawn_points'], s['per100']))
                for f in s['floors']:
                    print('  floor %d (z %d): walkable %d, monsters %d, %.2f per 100, %.2f per screen (max %d, %d screens)'
                          % (f['floor'], f['z'], f['walkable'], f['monsters'], f['per100'], f['per_screen'],
                             f['per_screen_max'], f['screens']))
                print('  steps from the entry: boss %s, farthest zone %s' % (s['entry_to_boss'], s['farthest_zone']))
                print('  zones: ' + ', '.join('%s %d' % kv for kv in sorted(s['zone_steps'].items(), key=lambda kv: kv[1])))
                print('  borders: %d transitions, %d open; unknown ids %d' % (s['transitions'], s['unbordered'], s['unknown_ids']))
        elif cmd == 'approve':
            if errs:
                print('not approved: the compile has QA errors')
                return 1
            import area_plan_kb as KB
            db = KB.connect()
            h = KB.approve(db, plan, res['stats'], note)
            print('approved %s (%s) into %s' % (plan['id'], h, KB.kb_path()))
        return 1 if errs else 0
    if cmd == 'suggest':
        import area_plan_kb as KB
        biome, lo, hi = args[0], int(args[1]), int(args[2])
        out = KB.suggest(KB.connect(), biome, lo, hi)
        if as_json:
            print(json.dumps(out, indent=1, sort_keys=True))
        else:
            for k in sorted(out):
                print('%s: %s' % (k, out[k]))
        return 0
    if cmd == 'similar':
        import area_plan_kb as KB
        n = int(_opt(args, '-n', '5'))
        plan = load_plan(args[0])
        found = KB.similar(KB.connect(), plan, None, n)
        if not found:
            print('no approved plan yet (%s)' % KB.kb_path())
        for d, r in found:
            print('%.3f  %-24s %-8s %d-%d  %dx%d  floors %d  zones %d  %.2f per 100' % (
                d, r['id'], r['biome'], r['level_lo'], r['level_hi'], r['width'], r['height'], r['floors'], r['zones'], r['per100']))
        return 0
    if cmd == 'catalogue':
        cat = C.catalogue(pair24, dark)
        if _flag(args, '--monsters'):
            ms = sorted(C.monsters().values(), key=lambda m: (m['level'] or 0, m['name']))
            out = [dict(name=m['name'], level=m['level'], boss=m['boss']) for m in ms]
        elif _flag(args, '--npcs'):
            out = sorted(C.npcs().values())
        else:
            out = dict(biomes=cat['biomes'], decoration=cat['decoration'], light=cat['light'], pair24=cat['pair24'],
                       tiers=[dict(min=t[0], max=t[1], pick=[t[2], t[3]]) for t in C.tiers()])
        if as_json or not isinstance(out, dict):
            print(json.dumps(out, indent=1, sort_keys=True))
        else:
            for k, b in sorted(out['biomes'].items()):
                print('%-9s %-8s %-12s z%-2d %s%s' % (k, b['kind'], b['theme'], b['z'], b['desc'],
                                                    (' [needs %s]' % b['needs']) if b.get('needs') else ''))
            print('decoration %s, light %s, pair 24 %s' % (', '.join(sorted(out['decoration'])), ', '.join(sorted(out['light'])),
                                                          'on' if out['pair24'] else 'off'))
        return 0
    if cmd == 'place':
        import area_plan_place as PL
        at = _opt(args, '--at', None, 3)
        sp = _opt(args, '--spawn', None, 2)
        if not at or len(args) < 3:
            print(__doc__)
            return 2
        try:
            out = PL.place(args[0], args[1], args[2], tuple(map(int, at)), sp[0] if sp else None, sp[1] if sp else None)
        except PL.PlaceError as e:
            print('not placed: %s' % e)
            return 1
        print('placed %d tiles, shift %s, into %s (the world map itself is untouched)' % (out['tiles'], out['shift'], out['out']))
        if out['touching']:
            print('WARN %d world tiles touch the area; check the seam in the map editor' % out['touching'])
        if out.get('roof'):
            print('WARN ' + out['roof'])
        for k in ('spawn_blocks', 'chest_script'):
            if k in out:
                print('%s: %s' % (k, out[k]))
        return 0
    if cmd == 'install':
        import area_plan_place as PL
        dry = _flag(args, '--dry-run')
        try:
            PL.install(args[0], args[1], dry)
        except PL.PlaceError as e:
            print('not installed: %s' % e)
            return 1
        return 0
    if cmd == 'check-kits':
        import area_plan_decor as D
        return 0 if D.check_kits(args[0], args[1], args[2]) else 1
    if cmd == 'plan':
        import area_plan_ai as AI
        prompt = _opt(args, '--from-prompt')
        out = _opt(args, '--out')
        band = _opt(args, '--level', None, 2)
        if not prompt:
            print('plan needs --from-prompt "TEXT"')
            return 2
        try:
            transport = AI.make_transport()
        except AI.NotConfigured as e:
            print('%s.\n\n%s' % (e, AI.HOWTO))
            return 2
        cat = C.catalogue(pair24, dark)
        try:
            plan, issues, rounds = AI.plan_from_prompt(prompt, transport, cat, tuple(map(int, band)) if band else None)
        except RuntimeError as e:
            print(e)
            return 1
        ok = plan is not None and not C.errors(issues)
        text = json.dumps(plan, indent=2) + '\n' if plan is not None else ''
        if out and plan is not None:
            path = out if ok else out + '.invalid'
            with open(path, 'w', encoding='utf-8') as f:
                f.write(text)
            print('wrote %s' % path)
        elif plan is not None:
            print(text)
        for i in issues:
            print(i)
        return 0 if ok else 1
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
