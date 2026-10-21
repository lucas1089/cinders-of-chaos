#!/usr/bin/env python3
"""python3 -I server/tools/gen_harvest_places_test.py : the Haunted Harvest's two areas and their places
(server/tools/areaplan/events/, gen_harvest_places.py, server/README.md "Haunted Harvest").
- both plans compile with no QA error; their origins keep 10+ tiles from every other plan and generated area of the
  14336-15359 block, whatever the floor;
- data/scripts/chaos/harvest_places.lua is what gen_harvest_places.py builds now (CI: --check);
- the places: mechanics and set pieces on walkable tiles of their area, never on a spawn point, the NPC, the arrival
  or a portal; with every blocking piece and mechanic in place every tile the arrival reached is reached; the seal's
  4 and the circle's 9 tiles walkable; the circle sits on the ritual chamber's planned teleport and leads to its
  landing in the King's Crypt;
- the decoration overlay (areaplan/decor_pack33_kit.json): every id a kit id, blocking as the kit says, never a timed
  mechanic state; install_content_areas.py takes the events folder only while the switch is on.
Needs luajit or lua5.3 (the area generator)."""
import glob, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_harvest_places as G  # noqa: E402
import install_content_areas as ICA  # noqa: E402
import install_pack33_items as KIT  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


# ---------------------------------------------------------------- where the areas lie
mine = {}
for pid in (G.SURFACE, G.CRYPT):
    p = json.load(open(os.path.join(G.EVENTS, pid + '.json'), encoding='utf-8'))
    o = p['origin']
    mine[pid] = (o['x'], o['y'], o['x'] + p['size'][0] - 1, o['y'] + p['size'][1] - 1)
    check(14336 <= o['x'] <= 15359 and 14336 <= o['y'] <= 15359, '%s: origin inside the block' % pid)
others = []
for path in glob.glob(os.path.join(HERE, 'areaplan', '*', '*.json')):
    if os.path.dirname(path) == G.EVENTS:
        continue
    p = json.load(open(path, encoding='utf-8'))
    o = p.get('origin')
    if o and 'examples' not in path:
        others.append((p['id'], o['x'], o['y'], o['x'] + p['size'][0] - 1, o['y'] + p['size'][1] - 1))
src = open(os.path.join(G.SERVER, 'data', 'scripts', 'chaos', 'areagen_config.lua'), encoding='utf-8').read()
for m in re.finditer(r'origin = \{x = (\d+), y = (\d+), z = \d+\}, size = \{(\d+), (\d+)\}', src):
    x, y, w, h = (int(v) for v in m.groups())
    others.append(('areagen %d,%d' % (x, y), x, y, x + w - 1, y + h - 1))
check(len(others) > 20, 'the other areas are read (%d)' % len(others))
boxes = list(mine.items())
for i, (pid, (x0, y0, x1, y1)) in enumerate(boxes):
    for oid, a0, b0, a1, b1 in others + [(q, *r) for q, r in boxes[i + 1:]]:
        gap = max(a0 - x1, x0 - a1, b0 - y1, y0 - b1)
        check(gap >= 10, '%s keeps 10 tiles from %s (%d)' % (pid, oid, gap))

# ---------------------------------------------------------------- the places
text, info, sa, ca = G.build()
check(text == open(G.OUT, encoding='utf-8').read(), 'harvest_places.lua is up to date (run gen_harvest_places.py)')
for a, name in ((sa, 'surface'), (ca, 'catacombs')):
    check(not G.PC.qa_errors(a.r), '%s: no QA error' % name)
    for cat, e in a.out:
        t = (e['x'], e['y'], e['z'])
        check(t in a.walk, '%s %s at %s on walkable floor' % (name, cat, t))
        check(t not in a.points, '%s %s at %s not on a spawn, NPC, arrival or portal' % (name, cat, t))
    after = a.reach(a.blocked)
    lost = [t for t in a.reach0 if t not in after and t not in a.blocked]
    check(not lost, '%s: nothing cut off from the arrival (%d)' % (name, len(lost)))
    maze = {(e['x'], e['y'], e['z']) for cat, e in a.out if cat == 'maze'}
    check(not ((a.blocked - maze) & a.lanes), '%s: no blocking piece but the maze on a walk to a zone, spawn or portal' % name)
seal = [e for c, e in sa.out if c == 'seal'][0]
for dx in (0, 1):
    for dy in (0, 1):
        check((seal['x'] - dx, seal['y'] - dy, seal['z']) in sa.walk, 'the seal stands on walkable floor')
x1, y1, x2, y2, _z = sa.zrect['ruined_chapel']
check(x1 <= seal['x'] <= x2 and y1 <= seal['y'] <= y2, 'the seal is in the ruined chapel')
c = info['circle']
check(c['teleport'] == tuple(t['at'] for t in ca.r['teleports'] if t['to'] == list(c['landing']) or tuple(t['to']) == c['landing'])[0],
      'the circle sits on the planned teleport to the King\'s Crypt')
kx1, ky1, kx2, ky2, _kz = ca.zrect['kings_crypt']
check(kx1 <= c['landing'][0] <= kx2 and ky1 <= c['landing'][1] <= ky2, 'its portal leads into the King\'s Crypt')
check(info['huts'] >= 2 and info['maze'] >= 60 and info['graves'] >= 8, 'huts, the corn maze and graves (%s)' % info)

# ---------------------------------------------------------------- the decoration overlay
rows = {r['server_id']: r for r in KIT.load_rows()}
over = json.load(open(os.path.join(HERE, 'areaplan', 'decor_pack33_kit.json'), encoding='utf-8'))
timed = {rows[i]['server_id'] for i in rows if rows[i]['ex'].get('decay')}
for name, g in over['groups'].items():
    for i in g['ids']:
        check(i in rows, '%s: %d is a kit id' % (name, i))
        if i in rows:
            check(bool(rows[i]['otb_flags'] & KIT.SOLID) == g['block'], '%s: blocking as the kit says' % name)
            check(i not in timed and not rows[i]['ex'].get('mechanic', '').startswith(('pumpkin', 'grave', 'crypt_seal')),
                  '%s: no mechanic state as decoration' % name)
for kit_name, spec in over['kits'].items():
    for cat, kit_rows in spec['add'].items():
        for g, w in kit_rows:
            check(g in over['groups'] or g in json.load(open(os.path.join(HERE, 'areaplan', 'decor_kits.json')))['groups'],
                  '%s.%s: group %s exists' % (kit_name, cat, g))
check(over['biome_kit'] == {'harvest': 'haunted_harvest', 'harvest_crypt': 'harvest_crypt'}, 'the two biomes')

# ---------------------------------------------------------------- the switch decides the install
check(ICA.harvest_on() is True, 'the switch is on (pair 33 on windows-assets since 2026-10-21)')
check(ICA.EVENTS_DIR in ICA.FIXED_DIRS, 'install_content_areas.py places the event areas while it is on')
check(os.path.isfile(os.path.join(G.SERVER, 'data', 'lib', 'chaos_harvest_art.lua')), 'the switch file')

print('gen_harvest_places_test: %s' % ('ok' if not failed else '%d failure(s)' % failed))
sys.exit(1 if failed else 0)
