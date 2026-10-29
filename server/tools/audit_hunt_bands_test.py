"""Unit test of audit_hunt_bands.py on synthetic data (run: python3 -I server/tools/audit_hunt_bands_test.py)."""
import os
import re
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import audit_hunt_bands as B
import audit_hunt_transitions as AT
import hall_order as HO

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


# ---- band maths
check(B.inside(20, 20, 40) and B.inside(16, 20, 40) and B.inside(48, 20, 40), 'slack: 0.8 x lo to 1.2 x hi is inside')
check(not B.inside(15, 20, 40) and not B.inside(49, 20, 40), 'outside the slack')
check(B.far_outside(300, 20, 40) and not B.far_outside(70, 20, 40), 'far: over 2 x the top')
check(B.far_outside(5, 40, 60) and not B.far_outside(25, 40, 60), 'far: under half the bottom')
check(not B.far_outside(10, 12, 15), 'a small step is never far (25 more)')
check(B.portal_verdict(15, 60, dict(level=300)) == 'gate', 'a portal to level 300 from a 15-60 hunt is a gate')
check(B.portal_verdict(15, 60, dict(level=80)) == 'ok', 'a portal to level 80 is not (under 1.5 x the top)')
check(B.portal_verdict(15, 60, dict(level=100)) == 'gate', 'level 100 is over 1.5 x the top and 30 more')
check(B.portal_verdict(15, 60, None) == 'ok', 'a quiet far side is ok')
check(B.portal_verdict(200, 300, dict(level=20)) == 'low', 'a portal to a far lower area is listed as low')
check(B.tight_band(dict(level=25, lo=15, hi=60)) == (16, 38), 'tight band: level / 1.5 .. level x 1.5: %r' % (B.tight_band(dict(level=25, lo=15, hi=60)),))

# ---- spawns: a hunt arrival at (100, 100, 7): rats and wolves round it, a demon cave on the floor below and far away
try:
    import numpy as np
except ImportError:
    print('numpy missing: the spawn tests are skipped')
    sys.exit(1 if fails else 0)
levels = {'rat': 5, 'wolf': 10, 'demon': 120, 'hydra': 140, 'troll': 12, 'ghost': 0}
exps = {k: 1.0 for k in levels}
pts = [(95 + i, 100, 7, 'rat' if i % 2 else 'wolf') for i in range(10)]           # 10 monsters in the field
pts += [(100 + i, 108, 7, 'troll') for i in range(4)]                               # 4 trolls
pts += [(98 + i % 4, 98 + i // 4, 8, 'demon' if i % 3 else 'hydra') for i in range(12)]   # a cave below
pts += [(100, 101, 7, 'ghost'), (500, 500, 7, 'rat')]
sp = AT.Spawns(pts, levels, exps)
everywhere = set((x, y, 7) for x in range(80, 130) for y in range(80, 130))
st = B.area_stats(sp, (100, 100, 7), 5, 15, ['rat', 'wolf'], tiles=everywhere)
check(st['count'] == 14 and st['named'] == 10, 'stats: 14 known monsters, 10 of them the hunt\'s own: %r' % ({k: v for k, v in st.items() if k != 'idx'},))
check(abs(st['in_share'] - 1.0) < 1e-9 and st['far_share'] == 0.0, 'all inside the band 5-15')
walled = set((x, y, 7) for x in range(80, 100) for y in range(80, 130))                      # walked region cuts the field in two
st2 = B.area_stats(sp, (90, 100, 7), 5, 15, ['rat'], tiles=walled)
check(st2['count'] < 14, 'a monster that cannot be walked to is not counted: %d' % st2['count'])
cave = B.area_stats(sp, (100, 100, 7), 5, 15, [], floors=(1,))
check(cave['count'] == 12 and cave['far_share'] == 1.0 and cave['in_share'] == 0.0, 'the cave below is all far: %r' % cave['far_share'])
view = B.area_view(sp, (100, 100, 7), 5, 15, ['rat'], everywhere)
check(view['pass'] == 'here' and view['near'] >= B.MIN_NEAR, 'view: the field is the first pass, near counted: %r %r' % (view['pass'], view['near']))
lone = B.area_view(sp, (300, 300, 7), 5, 15, [], set())
check(lone['count'] == 0 and lone['pass'] == 'deep', 'nothing anywhere: empty on the last pass')
flags, info = B.area_flags(view, 1, 5, 15)
check(flags == [] and info == [], 'a good area has no flags: %r %r' % (flags, info))
check(B.area_flags(lone, 1, 5, 15)[0] == ['empty'], 'empty')
bad = dict(view, count=3, in_share=0.4, far_share=0.5, named=0, near=0)
check(B.area_flags(bad, 2, 5, 15)[0] == ['few', 'spread', 'far', 'named'], 'few, spread, far and named: %r' % (B.area_flags(bad, 2, 5, 15)[0],))
check('mixed' in B.area_flags(view, 1, 15, 60)[0], 'a band wider than 3 x is mixed')
check('named' not in B.area_flags(dict(view, named=0), 3, 5, 15)[0], 'no own monster is fine while the monsters are in the band (a camp of kin)')
check('thin' in B.area_flags(dict(view, near=1), 1, 5, 15)[1], 'thin is info, not a defect')

# ---- reach and portals on a small grid: a room x 100..110, y 100..110 on floor 7, a wall column at x 111
def walk(p):
    x, y, z = p
    return z == 7 and 100 <= x <= 110 and 100 <= y <= 110


tiles = B.reach(walk, (105, 105, 7))
check(len(tiles) == 121, 'flood fill: the room has 121 tiles: %d' % len(tiles))
check(B.reach(lambda p: False, (1, 1, 7)) == set(), 'a blocked start reaches nothing')
trans = [dict(pos=(111, 105, 7), kind='teleport', item=1387, land=(300, 300, 7)),    # beside the room: in reach
         dict(pos=(105, 99, 7), kind='hole/down', item=480, land=(400, 400, 7)),    # beside the room on the other side, lands in a quiet place
         dict(pos=(120, 105, 7), kind='teleport', item=1387, land=(300, 300, 7)),   # 9 tiles off: not in reach
         dict(pos=(105, 105, 8), kind='hole/down', item=480, land=(105, 105, 9))]   # another floor: not
by = {}
for t in trans:
    by.setdefault(t['pos'], []).append(t)
got = B.portals_in_reach(tiles, by)
check([t['pos'] for t in got] == [(105, 99, 7), (111, 105, 7)], 'portals beside the reached tiles: %r' % [t['pos'] for t in got])

# ---- the audit on the fake map
hunts = [dict(id='h1', name='Rat', level=8, lo=5, hi=15, dest=(100, 100, 7), monsters=['rat', 'wolf'], x=1, y=1, z=1)]
far_pts = pts + [(300 + i, 300, 7, 'demon') for i in range(6)]            # the teleport leads among level 120
sp2 = AT.Spawns(far_pts, levels, exps)
rows = B.audit(hunts, sp2, walk, lambda p: True, trans, None, log=lambda *_: None)
r = rows[0]
check(r['flags'] == [] and r['stats']['count'] >= 8, 'the field hunt is fine: %r' % r['flags'])
verd = {p['t']['pos']: p['verdict'] for p in r['portals']}
check(verd == {(105, 99, 7): 'ok', (111, 105, 7): 'gate'}, 'only the portal among level 120 is a gate: %r' % verd)
hall = (290, 310, 7, 7, 290, 310)
rows_h = B.audit(hunts, sp2, walk, lambda p: True, trans, hall, log=lambda *_: None)
check(all(p['verdict'] == 'ok' for p in rows_h[0]['portals']), 'a portal back into the hall is skipped')
g = B.gates_of(rows)
check(len(g) == 1 and g[0][0] == (111, 105, 7) and g[0][2] == 120, 'gates_of: one portal, the far side\'s lowest level 120: %r' % (g,))

# ---- suggestions: a better area for a hunt that stands among the wrong monsters
many = [(200 + i % 6, 200 + i // 6, 7, 'wolf') for i in range(20)] + [(205, 205, 7, 'rat')] * 0
sp3 = AT.Spawns(pts + many, levels, exps)
open_world = lambda p: p[2] == 7 and 190 <= p[0] <= 240 and 190 <= p[1] <= 240 or walk(p)
hunt = dict(id='h2', name='Wolf', level=10, lo=5, hi=15, dest=(500, 500, 7), monsters=['wolf'])
sg = B.suggest(sp3, hunt, open_world, lambda p: True, {}, [(100, 100, 7)], limit=2)
check(len(sg) >= 1, 'a suggestion for the wolf hunt')
if sg:
    a = sg[0]['arrival']
    check(195 <= a[0] <= 210 and 195 <= a[1] <= 210 and a[2] == 7, 'it stands in the wolf pack: %r' % (a,))
    check(sg[0]['band'][2] == 10 and sg[0]['at'] and sg[0]['at'] != a, 'the band is the pack\'s, a way back tile beside the arrival: %r' % ((sg[0]['band'], sg[0]['at']),))
check(B.suggest(sp3, hunt, open_world, lambda p: True, {}, [(202, 202, 7)], limit=2) == [], 'not within 40 tiles of another hunt\'s arrival')

# ---- outputs
d = tempfile.mkdtemp()
try:
    rows[0]['suggest'] = sg
    md = B.render_md(rows)
    check('# Hunt bands (O333)' in md and '| Rat (8) |' in md and 'gate' in md, 'markdown table')
    check('—' not in md and '–' not in md, 'no dashes in the prose')
    gp = os.path.join(d, 'gates.csv')
    rowsg = [(111, 105, 7, 1387, 'remove', '', 'teleport', '300,300,7', 120, 'Rat')]
    check(B.write_gates(gp, rowsg) is True and B.write_gates(gp, rowsg) is False, 'gates csv: written, a second write changes nothing')
    import patch_hunt_gates as G
    check(G.read_rows(gp)[0]['pos'] == (111, 105, 7), 'patch_hunt_gates reads what the audit writes')
    cp = os.path.join(d, 'a.csv')
    B.write_csv(cp, rows)
    check(len(open(cp).read().splitlines()) == 2, 'csv: header and a row')
    # apply: a copy of the real CSV; the first hunt moves, the note says where from, a second run has nothing to move
    hp = os.path.join(d, 'h.csv')
    shutil.copy(AT.HUNTS_CSV, hp)
    raw = HO.read_csv(hp)
    first = [r for r in raw if r['kind'] == 'hunt'][0]
    rr = dict(hunt=dict(id=first['id']), flags=['mixed'], suggest=[dict(arrival=(1, 2, 3), band=(7, 14, 10), at=(1, 3, 3))])
    done = B.apply_retargets([rr], hp, log=lambda *_: None)
    new = {r['id']: r for r in HO.read_csv(hp)}[first['id']]
    check(done and (new['dest_x'], new['dest_y'], new['dest_z']) == (1, 2, 3) and (new['lo'], new['hi'], new['level']) == (7, 14, 10),
          'apply: dest and band moved')
    check(new['note'].startswith('retargeted O333 from %d,%d,%d' % (first['dest_x'], first['dest_y'], first['dest_z'])), 'apply: the note says where from')
    check(B.apply_retargets([dict(rr, flags=[])], hp, log=lambda *_: None) == [], 'apply: an unflagged hunt does not move')
finally:
    shutil.rmtree(d, ignore_errors=True)

# ---- the real CSV and config: every retargeted hunt has its way back listed, the gate list is well formed
rows_csv = HO.read_csv(AT.HUNTS_CSV)
cfg = open(os.path.join(os.path.dirname(HERE), 'data', 'scripts', 'chaos', 'hunt_teleports_config.lua'), encoding='utf-8').read()
listed = set(re.findall(r'\{id = "([^"]+)", at =', cfg))
for r in rows_csv:
    if r['kind'] == 'hunt' and 'retargeted' in r['note']:
        check(r['id'] in listed, '%s was retargeted: hunt_teleports_config.lua returns must list its way back' % r['id'])
        check(r['hi'] <= r['lo'] * B.MIXED, '%s: a retargeted hunt has a band narrower than %.0f x' % (r['id'], B.MIXED))
gates = os.path.join(HERE, 'hunt_gates.csv')
if os.path.isfile(gates):
    import patch_hunt_gates as G
    gr = G.read_rows(gates)
    check(len({(g['pos'], g['item']) for g in gr}) == len(gr), 'hunt_gates.csv: no duplicate row')

if fails:
    print('%d failed' % fails)
    sys.exit(1)
print('audit_hunt_bands_test: ok')
