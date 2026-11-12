"""Unit test of audit_map_tiles.py and map_tile_rules.py on a synthetic map (run: python3 -I server/tools/audit_map_tiles_test.py)."""
import contextlib
import io
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
ROOT = os.path.dirname(SERVER)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'map'))
import audit_map_synth as S  # noqa: E402
import audit_map_tiles as A  # noqa: E402
import map_tile_rules as R  # noqa: E402

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


# ---- the rules shared with the planner's QA
check(R.no_ground_below(None, [5]) and R.no_ground_below(0, [5]), 'items with an empty ground slot have no ground')
check(not R.no_ground_below(None, []) and not R.no_ground_below(351, [5]), 'an empty tile and a tile with a ground are fine')
check(R.no_ground_below(5, [], lambda i: i == 351), 'a non-ground in the ground slot is no ground')
check(R.blocking_on_special([300, 201], {300}, lambda i: i == 201) == [(300, 201)], 'a blocker on a door tile')
check(R.blocking_on_special([400], {400}, lambda i: False, walkable=False) == [(400, None)], 'a teleport tile nobody can stand on')
check(R.blocking_on_special([300, 5], {300}, lambda i: i == 300) == [], 'the door itself is no blocker')
check(R.blocking_on_special([5, 6], {300}, lambda i: True) == [], 'no special item: nothing to say')

# ---- the ports of the Lua rules: all 256 border patterns and all 16 wall patterns
LUA = None
for cand in ('luajit', 'lua5.3', 'lua'):
    if shutil.which(cand):
        LUA = cand
        break
if LUA:
    script = '''
dofile("data/scripts/chaos/areagen_core.lua")
local A = ChaosAreaGenCore
for m = 0, 255 do
  local function b(k) return (math.floor(m / 2 ^ k) % 2) == 1 end
  local t = A.borderPieces(b(0), b(1), b(2), b(3), b(4), b(5), b(6), b(7))
  print("B", m, table.concat(t, ","))
end
for m = 0, 15 do
  local function b(k) return (math.floor(m / 2 ^ k) % 2) == 1 end
  print("W", m, A.wallPiece(b(0), b(1), b(2), b(3)))
end
'''
    res = subprocess.run([LUA, '-e', script], cwd=SERVER, capture_output=True, text=True)
    check(res.returncode == 0, 'the Lua reference runs: ' + res.stderr[-200:])
    bad = 0
    n = 0
    for line in res.stdout.splitlines():
        p = line.split('\t')
        if p[0] == 'B':
            m = int(p[1])
            bits = [bool((m >> k) & 1) for k in range(8)]
            got = ','.join(R.border_pieces(*bits))
            n += 1
            if got != (p[2] if len(p) > 2 else ''):
                bad += 1
        elif p[0] == 'W':
            m = int(p[1])
            n += 1
            if R.wall_piece(*[bool((m >> k) & 1) for k in range(4)]) != p[2]:
                bad += 1
    check(n == 272 and bad == 0, 'border_pieces and wall_piece equal the Lua originals: %d of %d differ' % (bad, n))

# ---- our tables
tables = A.load_tables()
check(len(tables['borders']) == 132 and len(tables['walls']) == 10, 'tables: %d border ids, %d wall ids' % (len(tables['borders']), len(tables['walls'])))
check(tables['borders'][5632] == [('dirt_wall', 'n', {'earth'})], 'dirt wall n belongs to earth over the cave: %r' % tables['borders'][5632])
check(tables['borders'][4476][0][1] == 'dnw' and tables['walls'][3363] == ('ruin', 'pole'), 'gravel dnw, ruin pole')
check(30490 in tables['grounds']['darkmoss'] and 30529 in tables['borders'], 'dark tile names resolve to their ids')
lt = A._Lua('return {a = 1, b = {1, 2, {x = "s\\"q"}}, ["k"] = -2.5, c = true, -- note\n d = {}}')
lt.take('return')
v = lt.value()
check(v == {'a': 1, 'b': [1, 2, {'x': 's"q'}], 'k': -2.5, 'c': True, 'd': {}} or v == {'a': 1, 'b': [1, 2, {'x': 's"q'}], 'k': -2.5, 'c': True, 'd': []},
      'the Lua table reader: %r' % (v,))

# ---- the synthetic items
ITEMS = {
    351: dict(name='cave floor', group=1), 101: dict(name='earth', group=1), 500: dict(name='tin roof', group=1),
    920: dict(name='gloom', group=1),
    5632: dict(name='dirt wall n', order=1),
    3361: dict(name='stone wall v', flags=1, order=2), 3362: dict(name='stone wall h', flags=1, order=2),
    3363: dict(name='stone wall pole', flags=1, order=2), 3365: dict(name='stone wall corner', flags=1, order=2),
    200: dict(name='table'), 201: dict(name='statue', flags=1), 210: dict(name='pebble'),
    300: dict(name='wooden door', group=13, flags=1), 400: dict(name='magic forcefield', group=7),
    700: dict(name='gold coin', flags=1 << 7),
}
tmp = tempfile.mkdtemp(prefix='audit_map_tiles_')
S.write_items(tmp, ITEMS)


def patch(ox, oy, z=7, w=5, h=5):
    return {(ox + dx, oy + dy, z): dict(items=[351]) for dx in range(w) for dy in range(h)}


tiles = {}
# one region per fault, 20 tiles apart; the centre of a region is (ox + 2, oy + 2)
REG = {}
for k, code in enumerate(A.CODES):
    REG[code] = (100 + 20 * k, 100)
    tiles.update(patch(*REG[code]))


def at(code, dx=2, dy=2):
    return (REG[code][0] + dx, REG[code][1] + dy, 7)


tiles[at('NO_GROUND')] = dict(items=[200])
tiles[at('GROUND_NOT_FIRST')] = dict(items=[200, 351])
tiles[at('DUP_ITEM')] = dict(items=[351, 5632, 5632])
tiles[at('DUP_ITEM', 2, 1)] = dict(items=[101])          # the earth north of it: the pieces are not orphans
tiles[at('UNKNOWN_ID')] = dict(items=[351, 9999])
tiles[at('ORPHAN_BORDER')] = dict(items=[351, 5632])
tiles[at('WALL_MISMATCH')] = dict(items=[351, 3362])      # a lone wall tile is a pole
tiles[at('BLOCKED_DOOR')] = dict(items=[351, 300])
for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0)):
    tiles[at('BLOCKED_DOOR', 2 + dx, 2 + dy)] = dict(items=[351, 201])
tiles[at('BLOCKED_ON_SPECIAL')] = dict(items=[351, 201, (400, {'tele': at('BLOCKED_ON_SPECIAL', 0, 0)})])
tiles[at('BLOCKED_TELEPORT')] = dict(items=[351, (400, {'tele': (3000, 3000, 7)})])
del tiles[at('ROOF_NO_SUPPORT')]                           # nothing under the roof
tiles[(REG['ROOF_NO_SUPPORT'][0] + 2, REG['ROOF_NO_SUPPORT'][1] + 2, 6)] = dict(items=[500])
tiles[at('TOO_MANY_ITEMS')] = dict(items=[351] + [210] * 12)
# the clean area: a wall row, a bordered edge, a door with open sides, a teleport with a walkable landing, a roof over
# walkable ground, a tile with exactly MAX_ITEMS items, a stack of coins, an inline ground
cx, cy = 100, 300
tiles.update(patch(cx, cy, 7, 12, 8))
for dx in range(3):
    tiles[(cx + dx, cy, 7)] = dict(items=[351, 3362])
tiles[(cx + 5, cy + 2, 7)] = dict(items=[101])
tiles[(cx + 5, cy + 3, 7)] = dict(items=[351, 5632])      # earth to its north: the piece n has its higher ground
tiles[(cx + 7, cy + 2, 7)] = dict(items=[351, 300])       # a door with open sides (the tiles around are floor)
tiles[(cx + 9, cy + 2, 7)] = dict(items=[351, (400, {'tele': (cx + 10, cy + 2, 7)})])
tiles[(cx + 1, cy + 5, 6)] = dict(items=[500])            # a roof with walkable ground under it
tiles[(cx + 3, cy + 5, 7)] = dict(items=[351] + [210] * 11)
tiles[(cx + 4, cy + 5, 7)] = dict(items=[351, 700, 700])  # stackables twice: normal
tiles[(cx + 6, cy + 5, 7)] = dict(items=[351, 200], inline=True)
tiles[(cx + 8, cy + 5, 7)] = dict(items=[351, 3363])     # a lone wall piece is a pole
S.write_map(os.path.join(tmp, 'm.otbm'), tiles)
CLEAN_BOX = (cx, cy, cx + 11, cy + 7)

OTB, XML, MAP = (os.path.join(tmp, n) for n in ('items.otb', 'items.xml', 'm.otbm'))
KNOWN_EMPTY = os.path.join(tmp, 'known_empty.csv')
open(KNOWN_EMPTY, 'w').write('code,x,y,z,reason\n')


def run(*args, **kw):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        rc = A.main(list(args))
    return rc, out.getvalue()


world = A.load_world(MAP, OTB, XML, log=lambda *_: None)
f = A.audit(world[0], teles_found=world[1])
for code in A.CODES:
    rows = list(f.rows(code))
    want = at(code) if code != 'ROOF_NO_SUPPORT' else (REG[code][0] + 2, REG[code][1] + 2, 6)
    check(len(rows) == 1 and rows[0][:3] == want, '%s: found once at %s: %r' % (code, want, rows))
check(sum(f.count(c) for c in A.CODES) == len(A.CODES), 'nothing else is found: %s' % {c: f.count(c) for c in A.CODES if f.count(c)})
fc = A.audit(world[0], box=CLEAN_BOX, teles_found=world[1])
check(sum(fc.count(c) for c in A.CODES) == 0, 'the clean area is silent: %s' % {c: list(fc.rows(c)) for c in A.CODES if fc.count(c)})
check(f.by['TOO_MANY_ITEMS'][1][0] == 13, 'the count is reported')
check(A.Findings.ids_text('BLOCKED_TELEPORT', 400, (7 << 32) | (3000 << 16) | 3000) == '400>3000,3000,7', 'teleport ids text')

# ---- ids and fix hints in the lines
rc, text = run('--map', MAP, '--items', OTB, '--xml', XML, '--known', KNOWN_EMPTY)
check(rc == 0, 'a run without --check exits 0')
check('NO_GROUND %d,%d,%d ids=200 fix=add-ground' % at('NO_GROUND') in text, 'a NO_GROUND line: ' + text[:300])
check('GROUND_NOT_FIRST %d,%d,%d ids=200,351 fix=reorder' % at('GROUND_NOT_FIRST') in text, 'a GROUND_NOT_FIRST line')
check('DUP_ITEM %d,%d,%d ids=5632 fix=remove-dup' % at('DUP_ITEM') in text, 'a DUP_ITEM line')
check('UNKNOWN_ID %d,%d,%d ids=9999 fix=replace-id' % at('UNKNOWN_ID') in text, 'an UNKNOWN_ID line')
check('ORPHAN_BORDER %d,%d,%d ids=5632 fix=fix-border' % at('ORPHAN_BORDER') in text, 'an ORPHAN_BORDER line')
check('WALL_MISMATCH %d,%d,%d ids=3362,pole fix=fix-wall' % at('WALL_MISMATCH') in text, 'a WALL_MISMATCH line')
check('BLOCKED_DOOR %d,%d,%d ids=300 fix=open-door' % at('BLOCKED_DOOR') in text, 'a BLOCKED_DOOR line')
check('BLOCKED_ON_SPECIAL %d,%d,%d ids=400,201 fix=clear-tile' % at('BLOCKED_ON_SPECIAL') in text, 'a BLOCKED_ON_SPECIAL line')
check('BLOCKED_TELEPORT %d,%d,%d ids=400>3000,3000,7 fix=retarget' % at('BLOCKED_TELEPORT') in text, 'a BLOCKED_TELEPORT line')
check('ROOF_NO_SUPPORT %d,%d,6 ids=500 fix=support-or-remove-roof' % at('ROOF_NO_SUPPORT')[:2] in text, 'a ROOF_NO_SUPPORT line')
check('TOO_MANY_ITEMS %d,%d,%d ids=count=13 fix=thin' % at('TOO_MANY_ITEMS') in text, 'a TOO_MANY_ITEMS line')

# ---- --box, --floor, --summary, --csv, --known, --check
rc, text = run('--map', MAP, '--items', OTB, '--xml', XML, '--known', KNOWN_EMPTY, '--box',
               ','.join(str(v) for v in (REG['DUP_ITEM'][0], 100, REG['DUP_ITEM'][0] + 4, 104)), '--summary')
check('DUP_ITEM' in text and 'total 1 findings, 1 not in the known list' in text, '--box keeps one finding: ' + text[-200:])
rc, text = run('--map', MAP, '--items', OTB, '--xml', XML, '--known', KNOWN_EMPTY, '--floor', '6', '--summary')
check('total 1 findings' in text and 'ROOF_NO_SUPPORT' in text, '--floor 6 keeps the roof only')
rc, text = run('--map', MAP, '--items', OTB, '--xml', XML, '--known', KNOWN_EMPTY, '--summary')
check(all(('%-18s %7d' % (c, 1)) in text for c in A.CODES) and text.count('fix=') == 0, '--summary: one count per code, no lines')
csvp = os.path.join(tmp, 'out.csv')
rc, _t = run('--map', MAP, '--items', OTB, '--xml', XML, '--known', KNOWN_EMPTY, '--csv', csvp, '--quiet')
import csv  # noqa: E402
rows = list(csv.reader(open(csvp)))
check(rows[0] == ['code', 'x', 'y', 'z', 'ids', 'fix'] and len(rows) == 1 + len(A.CODES), '--csv: a header and a row per finding: %d' % len(rows))
rc, _t = run('--map', MAP, '--items', OTB, '--xml', XML, '--known', KNOWN_EMPTY, '--check', '--quiet')
check(rc == 1, '--check fails on findings that are not known')
known_all = os.path.join(tmp, 'known_all.csv')
with open(known_all, 'w') as fh:
    fh.write('# findings of the synthetic map\ncode,x,y,z,reason\n')
    for p in rows[1:]:
        fh.write('%s,%s,%s,%s,synthetic\n' % tuple(p[:4]))
rc, text = run('--map', MAP, '--items', OTB, '--xml', XML, '--known', known_all, '--check')
check(rc == 0 and 'not in the known list' in text and ', 0 new)' in text, '--check passes when every finding is listed: ' + text[-200:])
known_nine = os.path.join(tmp, 'known_nine.csv')
open(known_nine, 'w').write(open(known_all).read().replace('DUP_ITEM,%d,%d,%d,synthetic\n' % at('DUP_ITEM'), ''))
rc, text = run('--map', MAP, '--items', OTB, '--xml', XML, '--known', known_nine, '--check')
check(rc == 1 and 'NEW findings: 1' in text, '--check fails on the one finding that is not listed')
rc, text = run('--map', MAP, '--items', OTB, '--xml', XML, '--known', known_all, '--check', '--box', '0,0,50,50')
check(rc == 0 and 'no longer found' not in text, 'a known entry outside --box is not called stale')
rc, text = run('--map', MAP, '--items', OTB, '--xml', XML, '--known', known_all, '--check', '--limit', '1')
check(rc == 0, 'a known list with every finding passes --check with --limit')
# a known entry that is gone is printed, and does not fail
with open(known_all, 'a') as fh:
    fh.write('NO_GROUND,5,5,7,gone\n')
rc, text = run('--map', MAP, '--items', OTB, '--xml', XML, '--known', known_all, '--check')
check(rc == 0 and 'known entry no longer found: NO_GROUND 5,5,7' in text, 'a stale known entry is reported only')

# ---- refusals
rc, text = run('--map', os.path.join(tmp, 'nope.otbm'), '--items', OTB)
check(rc == 1 and 'refused' in text, 'a missing map is refused')
rc, text = run('--map', MAP, '--items', os.path.join(tmp, 'nope.otb'))
check(rc == 1 and 'refused' in text, 'a missing items.otb is refused')
rc, text = run('--map', MAP, '--items', OTB, '--box', '5,5,1,1')
check(rc == 1 and 'bad --box' in text, 'a bad box is refused')
rc, text = run('--bogus')
check(rc == 1, 'an unknown option is refused')

# ---- SERVER_DIR: data/world/<mapName>.otbm and data/items
srv = os.path.join(tmp, 'srv')
os.makedirs(os.path.join(srv, 'data', 'world'))
os.makedirs(os.path.join(srv, 'data', 'items'))
shutil.copy(MAP, os.path.join(srv, 'data', 'world', 'chaosmap.otbm'))
shutil.copy(OTB, os.path.join(srv, 'data', 'items', 'items.otb'))
shutil.copy(XML, os.path.join(srv, 'data', 'items', 'items.xml'))
open(os.path.join(srv, 'config.lua'), 'w').write('mapName = "chaosmap"\n')
rc, text = run(srv, '--known', KNOWN_EMPTY, '--summary')
check(rc == 0 and 'total 11 findings' in text, 'SERVER_DIR finds the map by config.lua: ' + text[-160:])
before = open(MAP, 'rb').read()
run(srv, '--known', KNOWN_EMPTY, '--quiet')
check(open(MAP, 'rb').read() == before and open(os.path.join(srv, 'data', 'world', 'chaosmap.otbm'), 'rb').read() == before,
      'the map is never written')
rc, text = run(srv, '--summary')       # the real known list is empty (a header only)
check(rc == 0 and open(A.KNOWN).read().count('\n') <= 3, 'the shipped known list starts empty')

shutil.rmtree(tmp)
print('audit_map_tiles_test: %s' % ('ok' if not fails else '%d FAILED' % fails))
sys.exit(1 if fails else 0)
