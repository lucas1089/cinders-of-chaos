#!/usr/bin/env python3
"""Look audit of a compiled area plan: what the owner sees in the room, which the tile lint (audit_map_tiles.py) cannot
(server/README.md "Hollow Crypt look (O574)").

usage: python3 -I server/tools/audit_plan_look.py [PLAN.json ...] [--check]

Owner 2026-11-14 (Hollow Crypt, pt-BR "muitas coisas quebradas e chao errado"): the lint found nothing, yet in game a
room showed a lone stone block with a wooden plank on top in the middle, light grey rooms among dark ones, a diagonal
wooden piece cut off by a wall. The codes (one line each: CODE plan x,y,z: what):
  ROOM_FLOOR_MIX    the floor of one room (a zone that is not the boss room) holds the grounds of more than one family
  PLAN_FLOOR_SPLIT  the rooms of the plan (not the boss room) are not all of one ground family (two kinds of floor
                    among the rooms of one hunt)
  LONE_PROP         a blocking decoration piece stands free in a room (no wall on the 8 tiles round it) with no other
                    decoration within 2 tiles: a block alone in the middle of the floor
  WOOD_PROP         a stock sarcophagus or wooden coffin (wooden lid on a stone slab: ids WOOD_PROP_IDS) in a plan of
                    LOOK_PLANS
  HANGING_CUT       a hung tapestry or banner (2 tiles wide) whose neighbour along the wall is not a wall of the same
                    run: the piece is drawn over the floor or the corner and looks cut off
LOOK_PLANS are the plans held to all five codes (--check exits 1 for a finding in them); the other plans are only
reported, because their decoration was placed before the rules and re-placing it needs a restored map. Read only.
"""
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import area_plan_decor as D  # noqa: E402
import audit_map_tiles as A  # noqa: E402

PLANS = os.path.join(HERE, 'areaplan', 'plans')
LOOK_PLANS = ('hollow_crypt',)
WOOD_PROP_IDS = frozenset([7361, 7362, 1742, 1743, 1744])
WALL_IDS = frozenset(range(3361, 3366))        # the `ruin` brush of areagen_config.lua `walls`
LONE_RADIUS = 2
CODES = ('ROOM_FLOOR_MIX', 'PLAN_FLOOR_SPLIT', 'LONE_PROP', 'WOOD_PROP', 'HANGING_CUT')


def _walls_of(tables):
    ids = set(WALL_IDS)
    ids.update(tables['walls'])
    return ids


def look_findings(plan, res, tables=None, groups=None, wall_ids=None):
    """-> list of (code, x, y, z, text) for a compiled plan (res of area_plan_compile.compile_plan)"""
    tables = tables or A.load_tables()
    groups = groups or D.kits()['groups']
    wall_ids = wall_ids or _walls_of(tables)
    tiles = res['tiles']
    out = []
    fam_of = {}
    for fam, ids in tables['grounds'].items():
        for i in ids:
            fam_of.setdefault(i, fam)
    roles = {z['id']: z.get('role') for z in plan['zones']}
    room_fam = {}
    for zid, (x1, y1, x2, y2, zz) in sorted(res['zrect'].items()):
        if roles.get(zid) == 'boss':
            continue
        fams = {}
        for y in range(y1, y2 + 1):
            for x in range(x1, x2 + 1):
                t = tiles.get((x, y, zz))
                if t and t['ground']:
                    fams.setdefault(fam_of.get(t['ground'], 'id%d' % t['ground']), (x, y, zz))
        room_fam[zid] = set(fams)
        # a cave or a marsh mixes grounds in a room on purpose (patches, pools): only the held plans are looked at
        if len(fams) > 1 and plan['id'] in LOOK_PLANS:
            x, y, z = sorted(fams.values())[0]
            out.append(('ROOM_FLOOR_MIX', x, y, z, '%s: %s' % (zid, ', '.join(sorted(fams)))))
    if plan['id'] in LOOK_PLANS:
        kinds = {}
        for zid, f in room_fam.items():
            kinds.setdefault(tuple(sorted(f)), []).append(zid)
        if len(kinds) > 1:
            x1, y1, _x2, _y2, zz = res['zrect'][sorted(room_fam)[0]]
            out.append(('PLAN_FLOOR_SPLIT', x1, y1, zz, '; '.join('%s: %s' % ('+'.join(k), ','.join(sorted(v)))
                                                               for k, v in sorted(kinds.items()))))

    def is_wall(k):
        t = tiles.get(k)
        return bool(t) and any(i in wall_ids for i, _a in t['items'])

    # lit pieces (braziers, pillars with a flame) are placed alone on purpose and are not looked at
    block_ids = {i for g in groups.values() if g['block'] and not g.get('light') for i in g['ids']}
    hang = {}
    for gname, g in groups.items():
        if gname.startswith(('tapestry_', 'banner_')):
            for i in g['ids']:
                hang[i] = gname[-1]
    for (x, y, z), t in sorted(tiles.items()):
        ids = [i for i, _a in t['items']]
        for i in ids:
            if i in WOOD_PROP_IDS and plan['id'] in LOOK_PLANS:
                out.append(('WOOD_PROP', x, y, z, 'id %d' % i))
            if i in hang:
                h = hang[i] == 'h'
                a = (x - 1, y, z) if h else (x, y - 1, z)
                b = (x + 1, y, z) if h else (x, y + 1, z)
                if not (is_wall((x, y, z)) and is_wall(a) and is_wall(b)):
                    out.append(('HANGING_CUT', x, y, z, 'id %d' % i))
            if i in block_ids and i not in wall_ids:
                near = [(x + dx, y + dy, z) for dx in range(-LONE_RADIUS, LONE_RADIUS + 1)
                        for dy in range(-LONE_RADIUS, LONE_RADIUS + 1) if dx or dy]
                if any(is_wall(n) for n in near if max(abs(n[0] - x), abs(n[1] - y)) <= 1):
                    continue
                other = any(n in tiles and any(j not in wall_ids for j, _a in tiles[n]['items']) for n in near)
                if not other:
                    out.append(('LONE_PROP', x, y, z, 'id %d' % i))
    return out


def audit_plan(path):
    import area_import
    import area_plan_compile as PC
    plan = json.load(open(path, encoding='utf-8'))
    if area_import.is_import(plan):
        return None
    res = PC.compile_plan(plan)
    return plan['id'], look_findings(plan, res)


def main(argv):
    check = '--check' in argv
    files = [a for a in argv if not a.startswith('-')] or sorted(glob.glob(os.path.join(PLANS, '*.json')))
    bad = 0
    for f in files:
        got = audit_plan(f)
        if got is None:
            continue
        pid, found = got
        by = {}
        for c, x, y, z, text in found:
            by.setdefault(c, []).append((x, y, z, text))
        if by:
            print('%-26s %s' % (pid, ', '.join('%s %d' % (c, len(v)) for c, v in sorted(by.items()))))
            if pid in LOOK_PLANS:
                bad += len(found)
                for c, v in sorted(by.items()):
                    for x, y, z, text in v[:5]:
                        print('   %s %d,%d,%d %s' % (c, x, y, z, text))
    print('look audit: %s' % ('%d findings in the held plans' % bad if bad else 'the held plans are clean'))
    return 1 if check and bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
