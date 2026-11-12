"""Unit test of audit_houses.py on a synthetic map and houses.xml (run: python3 -I server/tools/audit_houses_test.py).
Eight houses: one clean, and one for each of the seven codes with exactly that one fault."""
import contextlib
import csv
import io
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'map'))
import audit_houses as H  # noqa: E402
import audit_map_synth as S  # noqa: E402

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


ITEMS = {351: dict(name='cave floor', group=1), 500: dict(name='tin roof', group=1),
         300: dict(name='wooden door', group=13, flags=1), 201: dict(name='statue', flags=1)}
tmp = tempfile.mkdtemp(prefix='audit_houses_')
S.write_items(tmp, ITEMS)

HOUSE_CODES = {1: None, 2: 'MULTI_FLOOR', 3: 'NO_DOOR', 4: 'DOOR_UNREACHABLE', 5: 'ENTRY_BLOCKED', 6: 'HOUSE_FLAGS', 7: 'SIZE',
               8: 'ROOF_SHARE'}
tiles, rows = {}, []


def region(h):
    return 100 + 20 * h, 100


for h in HOUSE_CODES:
    ox, oy = region(h)
    side = 2 if h == 7 else 4                    # house 7 is a closet of 4 tiles
    for dx in range(side + 2):
        for dy in range(side + 2):
            tiles[(ox + dx, oy + dy, 7)] = dict(items=[351])             # the street round the house
    for dx in range(1, side + 1):
        for dy in range(1, side + 1):
            x, y = ox + dx, oy + dy
            flags = 1 if h != 6 or (dx, dy) != (1, 1) else 0             # protection zone, but one tile of house 6
            tiles[(x, y, 7)] = dict(items=[351], house=h, flags=flags if h == 6 else 0)
            roofed = not (h == 8 and dy > 1)                              # house 8: only a quarter has a roof
            if roofed:
                tiles[(x, y, 6)] = dict(items=[500])
    door = (ox + 1, oy + 1, 7) if h == 7 else (ox + 2, oy + 1, 7)
    if h != 3:
        tiles[door] = dict(items=[351, 300], house=h, flags=tiles[door]['flags'])
    if h == 4:
        tiles[(door[0], door[1] - 1, 7)] = dict(items=[351, 201])        # the street tile in front of the door is blocked
    entry = (door[0], door[1] - 1, 7) if h not in (4, 5) else ((ox + 4, oy, 7) if h == 4 else (9999, 9999, 7))
    rows.append(dict(id=h, name='House %d' % h, entry=entry))
# house 2: an upper floor, roofed
ox, oy = region(2)
tiles[(ox + 1, oy + 1, 6)] = dict(items=[351], house=2)
tiles[(ox + 1, oy + 1, 5)] = dict(items=[500])
MAP, XML = os.path.join(tmp, 'm.otbm'), os.path.join(tmp, 'items.xml')
OTB = os.path.join(tmp, 'items.otb')
HOUSES = os.path.join(tmp, 'm-house.xml')
S.write_map(MAP, tiles, 'm-house.xml')
S.write_houses(HOUSES, rows)

EMPTY = os.path.join(tmp, 'known_empty.csv')
open(EMPTY, 'w').write('house,code,reason\n')


def run(*args):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        rc = H.main(list(args))
    return rc, out.getvalue()


houses = H.read_houses(HOUSES)
check(len(houses) == 8 and houses[2] == dict(name='House 2', entry=(142, 100, 7), size=0), 'houses.xml is read: %r' % houses.get(2))
import audit_map_tiles as A  # noqa: E402
world = A.load_world(MAP, OTB, XML, log=lambda *_: None, tables=dict(borders={}, grounds={}, walls={}))
found, meta = H.audit(world[0], houses)
for h, code in HOUSE_CODES.items():
    got = sorted(c for c, _d in found.get(h, []))
    check(got == ([code] if code else []), 'house %d: %s, found %s' % (h, code or 'clean', got))
check(meta[7][0] == 4 and meta[1][0] == 16 and meta[2][0] == 17, 'tile counts: %r' % {k: meta[k][0] for k in (1, 2, 7)})
f2, _m = H.audit(world[0], houses, max_floors=2)
check(not f2[2], '--max-floors 2 lets the two-floor house pass')

rc, text = run('--map', MAP, '--items', OTB, '--xml', XML, '--houses', HOUSES, '--known', EMPTY)
check(rc == 0 and '8 houses, 7 findings, 7 not in the known list' in text, 'the report: ' + text[:400])
check('NO_DOOR house=3 "House 3" tiles=16 first=' in text and 'ENTRY_BLOCKED house=5 "House 5"' in text, 'lines name house id and name')
check('SIZE house=7 "House 7" tiles=4 first=' in text and '4 tiles (band 13-180)' in text, 'the size line')
check('ROOF_SHARE house=8' in text and '25% of 16 tiles have a roof' in text, 'the roof line: ' + text)
check('HOUSE_FLAGS house=6' in text and 'protection zone on 15 of 16 tiles' in text, 'the flags line')
check('entry 9999,9999,7 is not a tile' in text, 'the entry line')
rc, text = run('--map', MAP, '--items', OTB, '--xml', XML, '--houses', HOUSES, '--known', EMPTY, '--summary')
check('fix' not in text and 'house=' not in text and 'SIZE' in text, '--summary prints counts only')
rc, _t = run('--map', MAP, '--items', OTB, '--xml', XML, '--houses', HOUSES, '--known', EMPTY, '--check', '--quiet')
check(rc == 1, '--check fails on findings that are not known')
csvp = os.path.join(tmp, 'o.csv')
run('--map', MAP, '--items', OTB, '--xml', XML, '--houses', HOUSES, '--known', EMPTY, '--csv', csvp, '--quiet')
crow = list(csv.reader(open(csvp)))
check(crow[0][:3] == ['house', 'code', 'name'] and len(crow) == 8, '--csv: a header and a row per finding: %d' % len(crow))
known = os.path.join(tmp, 'known.csv')
with open(known, 'w') as fh:
    fh.write('# known\nhouse,code,reason\n')
    for r in crow[1:]:
        fh.write('%s,%s,synthetic\n' % (r[0], r[1]))
rc, text = run('--map', MAP, '--items', OTB, '--xml', XML, '--houses', HOUSES, '--known', known, '--check')
check(rc == 0 and '8 houses, 7 findings, 0 not in the known list' in text, '--check passes when every finding is listed: ' + text[-120:])
with open(known, 'a') as fh:
    fh.write('99,SIZE,gone\n')
rc, text = run('--map', MAP, '--items', OTB, '--xml', XML, '--houses', HOUSES, '--known', known, '--check')
check(rc == 0 and 'known entry no longer found: house 99 SIZE' in text, 'a stale entry is printed and does not fail')
text_known = open(known).read().replace('3,NO_DOOR,synthetic\n', '')
open(known, 'w').write(text_known)
rc, text = run('--map', MAP, '--items', OTB, '--xml', XML, '--houses', HOUSES, '--known', known, '--check')
check(rc == 1 and 'NEW findings: 1' in text, '--check fails on the one that is not listed')
rc, text = run('--map', MAP, '--items', OTB, '--xml', XML, '--houses', HOUSES, '--known', EMPTY, '--max-floors', '2', '--summary')
check(('%-17s %5d' % ('MULTI_FLOOR', 0)) in text and ' 6 findings' in text, '--max-floors 2 on the command line: ' + text[:200])

# refusals
rc, text = run('--map', MAP, '--items', OTB, '--houses', os.path.join(tmp, 'nope.xml'))
check(rc == 1 and 'no house file' in text, 'a missing house file is refused')
rc, text = run('--map', os.path.join(tmp, 'nope.otbm'), '--items', OTB, '--houses', HOUSES)
check(rc == 1 and 'refused' in text, 'a missing map is refused')
rc, text = run('--max-floors', 'x', '--map', MAP)
check(rc == 1, 'a bad number is refused')

# SERVER_DIR: the house file next to the map by config.lua mapName
srv = os.path.join(tmp, 'srv')
os.makedirs(os.path.join(srv, 'data', 'world'))
os.makedirs(os.path.join(srv, 'data', 'items'))
shutil.copy(MAP, os.path.join(srv, 'data', 'world', 'cm.otbm'))
shutil.copy(HOUSES, os.path.join(srv, 'data', 'world', 'cm-house.xml'))
shutil.copy(OTB, os.path.join(srv, 'data', 'items', 'items.otb'))
shutil.copy(XML, os.path.join(srv, 'data', 'items', 'items.xml'))
open(os.path.join(srv, 'config.lua'), 'w').write('mapName = "cm"\n')
before = open(os.path.join(srv, 'data', 'world', 'cm.otbm'), 'rb').read() + open(os.path.join(srv, 'data', 'world', 'cm-house.xml'), 'rb').read()
rc, text = run(srv, '--known', EMPTY, '--summary')
check(rc == 0 and '8 houses, 7 findings' in text, 'SERVER_DIR finds the map and the house file: ' + text[-120:])
after = open(os.path.join(srv, 'data', 'world', 'cm.otbm'), 'rb').read() + open(os.path.join(srv, 'data', 'world', 'cm-house.xml'), 'rb').read()
check(before == after, 'nothing is written')
rc, text = run(srv, '--summary')
check(rc == 0 and open(H.KNOWN).read().count('\n') <= 3, 'the shipped known list starts empty')

shutil.rmtree(tmp)
print('audit_houses_test: %s' % ('ok' if not fails else '%d FAILED' % fails))
sys.exit(1 if fails else 0)
