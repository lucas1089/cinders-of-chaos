"""Unit test of fix_houses.py on a synthetic map and houses.xml (run: python3 -I server/tools/fix_houses_test.py).
Six houses: clean; protection zone on 15 of 16 tiles; a PvP flag on two tiles (one with an inline ground and a byte
that needs escaping in its position); both faults; no door (for a human); a flag fault on the known list (left)."""
import contextlib
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
import audit_map_tiles as A  # noqa: E402
import fix_houses as F  # noqa: E402
import map_guard_testkit as K  # noqa: E402
import map_write_guard as MG  # noqa: E402

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


ITEMS = {351: dict(name='cave floor', group=1), 500: dict(name='tin roof', group=1),
         300: dict(name='wooden door', group=13, flags=1)}
tmp = tempfile.mkdtemp(prefix='fix_houses_')
S.write_items(tmp, ITEMS)
OTB, XML = os.path.join(tmp, 'items.otb'), os.path.join(tmp, 'items.xml')

# house id -> (origin x, the tile flags of the 4 x 4 house by (dx, dy), a door)
PZ, PVP = H.TF_PZ, H.TF_PVP
SPEC = {
    1: (100, {}, True),
    2: (120, {(1, 1): 0}, True),                              # PZ_ADD on one tile
    3: (250, {(3, 3): PZ | PVP, (4, 3): PZ | PVP | 4}, True),  # PVP_CLEAR; x 254 is 0xFE (escaped), no-logout bit kept
    4: (140, {(1, 1): 0, (4, 4): PZ | PVP}, True),            # both
    5: (160, {}, False),                                      # NO_DOOR: a human
    6: (180, {(1, 1): 0}, True),                              # HOUSE_FLAGS on the known list: left
}
tiles, rows = {}, []
for h, (ox, special, has_door) in SPEC.items():
    oy = 100
    for dx in range(6):
        for dy in range(6):
            tiles[(ox + dx, oy + dy, 7)] = dict(items=[351])
    for dx in range(1, 5):
        for dy in range(1, 5):
            x, y = ox + dx, oy + dy
            tiles[(x, y, 7)] = dict(items=[351], house=h, flags=special.get((dx, dy), PZ), inline=(h == 3 and dy == 3))
            tiles[(x, y, 6)] = dict(items=[500])
    if has_door:
        d = (ox + 2, oy + 1, 7)
        tiles[d] = dict(items=[351, 300], house=h, flags=tiles[d]['flags'])
    rows.append(dict(id=h, name='House %d' % h, entry=(ox + 2, oy, 7)))
MAP = os.path.join(tmp, 'm.otbm')
HOUSES = os.path.join(tmp, 'm-house.xml')
S.write_map(MAP, tiles, 'm-house.xml')
S.write_houses(HOUSES, rows)
KNOWN = os.path.join(tmp, 'known.csv')
open(KNOWN, 'w').write('house,code,reason\n6,HOUSE_FLAGS,synthetic: left on purpose\n')
ORIG = open(MAP, 'rb').read()


def run(*args):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        rc = F.main(list(args))
    return rc, out.getvalue()


def audit_codes(path):
    w, _f = A.load_world(path, OTB, XML, log=lambda *_: None, tables=dict(borders={}, grounds={}, walls={}))
    found, _m = H.audit(w, H.read_houses(HOUSES))
    return {h: sorted(c for c, _d in r) for h, r in found.items() if r}, w


BASE = ('--map', MAP, '--items', OTB, '--xml', XML, '--houses', HOUSES, '--known', KNOWN)
codes, _w = audit_codes(MAP)
check(codes == {2: ['HOUSE_FLAGS'], 3: ['HOUSE_FLAGS'], 4: ['HOUSE_FLAGS', 'HOUSE_FLAGS'], 5: ['NO_DOOR'], 6: ['HOUSE_FLAGS']},
      'the synthetic map has the planned findings: %r' % codes)

# dry run (the default): the plan, the counts, nothing written
rc, text = run(*BASE)
check(rc == 0 and 'PZ_ADD               2 tile(s) in 2 house(s)' in text, 'PZ_ADD count: ' + text[:400])
check('PVP_CLEAR            3 tile(s) in 2 house(s)' in text, 'PVP_CLEAR count: ' + text[:400])
check('5 tile(s) to rewrite; 1 finding(s) for a human; 1 known and left' in text, 'the totals: ' + text[:500])
check('PZ_ADD house=2 tile=121,101,7: flags 0 -> 1' in text, 'a PZ_ADD line')
check('PVP_CLEAR house=3 tile=254,103,7: flags 21 -> 5' in text, 'a PVP_CLEAR line keeps the other bits')
check('HUMAN NO_DOOR house=5' in text and 'house=6' not in text, 'the human list; the known house is not planned')
check('dry run, nothing written' in text and open(MAP, 'rb').read() == ORIG, 'the dry run writes nothing')
rc, _t = run(*(BASE + ('--dry-run', '--write')))
check(rc == 1, '--dry-run with --write is refused')

# a guard refusal (O512): the writer also changes an item id on a far tile
orig_rewrite = F.rewrite
state = {}


def faulty(data, plan_tiles):
    new, expect = orig_rewrite(data, plan_tiles)
    new, state['far'] = K.corrupt_far_item(new, skip=set(plan_tiles))
    return new, expect


F.rewrite = faulty
try:
    rc, text = run(*(BASE + ('--write',)))
finally:
    F.rewrite = orig_rewrite
check(rc == 1 and 'map write guard refused' in text and ('%d,%d,%d: tile changed outside' % state['far']) in text,
      'the guard names the far tile: ' + text[-400:])
check(open(MAP, 'rb').read() == ORIG and os.path.isfile(MAP + '.tmp') and not os.path.exists(MAP + '.bak'),
      'after a refusal the map is as it was, the .tmp stays, no backup')
os.remove(MAP + '.tmp')

# a writer that means other bytes than it writes: expect catches it
orig_new_payload = F._new_payload
F._new_payload = lambda pl, kind, flags, pos: orig_new_payload(pl, kind, flags | (2 if pos == (121, 101, 7) else 0), pos)
real_rewrite = F.rewrite


def lying(data, plan_tiles):
    new, expect = real_rewrite(data, plan_tiles)
    F._new_payload = orig_new_payload
    _n2, expect = real_rewrite(data, plan_tiles)
    return new, expect


F.rewrite = lying
try:
    rc, text = run(*(BASE + ('--write',)))
finally:
    F.rewrite, F._new_payload = real_rewrite, orig_new_payload
check(rc == 1 and '121,101,7: the tile is not what the writer meant' in text, 'expect refuses a tile with other bytes: ' + text[-300:])
check(open(MAP, 'rb').read() == ORIG, 'and the map is as it was')
os.remove(MAP + '.tmp')

# --out: the fixed map goes to another file
OUT = os.path.join(tmp, 'fixed.otbm')
rc, text = run(*(BASE + ('--out', OUT)))
check(rc == 0 and 'map write guard: ' in text and '5 rewritten' in text and open(MAP, 'rb').read() == ORIG,
      '--out writes elsewhere through the guard: ' + text[-300:])
codes, w = audit_codes(OUT)
check(codes == {5: ['NO_DOOR'], 6: ['HOUSE_FLAGS']}, 'after the fix only the human and known findings stay: %r' % codes)
t = w.m.tiles
fl = {(int(x), int(y), int(z)): (int(f), int(hh)) for x, y, z, f, hh in zip(t['x'], t['y'], t['z'], t['flags'], t['house'])}
check(fl[(254, 103, 7)] == (5, 3) and fl[(253, 103, 7)] == (1, 3) and fl[(141, 101, 7)] == (1, 4) and fl[(144, 104, 7)] == (1, 4),
      'flags and house ids after the fix: %r' % [fl[p] for p in ((254, 103, 7), (253, 103, 7), (141, 101, 7), (144, 104, 7))])
check(fl[(181, 101, 7)] == (0, 6), 'the known house is untouched')
check(MG.check(MAP, OUT, change={(121, 101, 7), (253, 103, 7), (254, 103, 7), (141, 101, 7), (144, 104, 7)}) is not None,
      'the guard proves only the five tiles differ')

# --write in place: backup, then a second run plans nothing (idempotent) and writes nothing
rc, text = run(*(BASE + ('--write',)))
check(rc == 0 and os.path.isfile(MAP + '.bak') and open(MAP + '.bak', 'rb').read() == ORIG, '--write keeps a backup')
check(open(MAP, 'rb').read() == open(OUT, 'rb').read(), '--write and --out give the same bytes')
after = open(MAP, 'rb').read()
rc, text = run(*(BASE + ('--write',)))
check(rc == 0 and '0 tile(s) to rewrite' in text and 'nothing to fix' in text and open(MAP, 'rb').read() == after,
      'a second run plans nothing: ' + text[:300])

# refusals
rc, text = run('--map', MAP, '--items', OTB, '--houses', os.path.join(tmp, 'nope.xml'))
check(rc == 1 and 'no house file' in text, 'a missing house file is refused')
rc, text = run('--map', os.path.join(tmp, 'nope.otbm'), '--items', OTB, '--houses', HOUSES)
check(rc == 1 and 'no map' in text, 'a missing map is refused')
try:
    F._new_payload(bytes([1, 2, 7, 0]), 5, 1, (1, 2, 7))
    check(False, 'an unknown tile attribute is refused')
except F.FixError as e:
    check('attribute 7' in str(e), 'the unknown attribute is named')

shutil.rmtree(tmp)
print('fix_houses_test: %s' % ('ok' if not fails else '%d FAILED' % fails))
sys.exit(1 if fails else 0)
