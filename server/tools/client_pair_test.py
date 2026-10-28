#!/usr/bin/env python3
"""python3 -I server/tools/client_pair_test.py : the client pair guard (client_pair.py) and the steps it holds back
(install_pickups.py needs pair 55, install_fist_weapons.py pair 56 for its repoint and new4 rows, install_weapons800.py
pair 56): the key read / written in config.lua, set refusing a lower value, a missing or low record skipping with a
message and writing nothing, a high enough record installing, a second run changing nothing. No base server needed."""
import os, struct, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import client_pair as C  # noqa: E402
import install_fist_weapons as F  # noqa: E402
from install_gems import escape, attr, START, END, A_SERVERID, A_CLIENTID, FLAG_PICKUPABLE, FLAG_MOVEABLE  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


# ---- parse / patch
check(C.parse('') is None and C.parse('a = 1\n') is None, 'no key: None')
check(C.parse('chaosClientPair = 54\n') == 54, 'key read')
check(C.parse('x = 1\n  chaosClientPair=56 -- shipped\n') == 56, 'key read with a comment and no spaces')
check(C.parse('chaosClientPair = "abc"\n') is None, 'not a number: None')
t, old = C.patch('a = 1\n', 55)
check(old is None and t.startswith('a = 1\nchaosClientPair = 55 --') and t.endswith('\n') and C.parse(t) == 55, 'missing key appended')
t2, old2 = C.patch(t, 56)
check(old2 == '55' and C.parse(t2) == 56 and t2.count('chaosClientPair') == 1 and 'Cinders of Chaos' in t2, 'key replaced, comment kept')
check(C.patch(t2, 56)[0] == t2, 'same value: no change')
check(C.patch('a = 1', 3)[0].startswith('a = 1\nchaosClientPair = 3'), 'text without a final newline')


def server(config):
    d = tempfile.mkdtemp(prefix='pairguard_')
    if config is not None:
        open(os.path.join(d, 'config.lua'), 'w').write(config)
    os.makedirs(os.path.join(d, 'data', 'items'))
    os.makedirs(os.path.join(d, 'data', 'movements'))
    return d


def run(*args):
    p = subprocess.run([sys.executable, '-I'] + list(args), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
    return p.returncode, p.stdout


# ---- allows / recorded
check(C.recorded(os.path.join(server(None), 'data')) is None, 'no config.lua: None')
d = server('serverName = "x"\n')
check(C.recorded(os.path.join(d, 'data')) is None, 'config without the key: None')
ok, msg = C.allows(os.path.join(d, 'data'), 55, 'pickups')
check(not ok and 'skipped' in msg and 'missing' in msg and 'client-pair set 55' in msg and msg.startswith('WARNING: '), 'missing record skips and says how to set it')
d = server('chaosClientPair = 54\n')
ok, msg = C.allows(os.path.join(d, 'data'), 55, 'pickups')
check(not ok and 'recorded pair is 54' in msg, 'lower record skips')
for n in (55, 56, 60):
    d = server('chaosClientPair = %d\n' % n)
    check(C.allows(os.path.join(d, 'data'), 55, 'pickups')[0], 'record %d allows pair 55' % n)
d = server('chaosClientPair = 55\n')
check(not C.allows(os.path.join(d, 'data'), 56, 'fist')[0], 'record 55 does not allow pair 56')

# ---- the command line
d = server('a = 1\n')
rc, out = run(os.path.join(HERE, 'client_pair.py'), 'show', d)
check(rc == 0 and out.strip() == 'chaosClientPair=missing', 'show: missing')
rc, out = run(os.path.join(HERE, 'client_pair.py'), 'set', d, '55')
check(rc == 0 and C.recorded(os.path.join(d, 'data')) == 55 and '(missing) -> 55' in out, 'set: appended')
rc, out = run(os.path.join(HERE, 'client_pair.py'), 'set', d, '55')
check(rc == 0 and 'already' in out, 'set: idempotent')
rc, out = run(os.path.join(HERE, 'client_pair.py'), 'set', d, '54')
check(rc == 1 and 'refused' in out and C.recorded(os.path.join(d, 'data')) == 55, 'set: lowering refused')
rc, out = run(os.path.join(HERE, 'client_pair.py'), 'set', d, '54', '--force')
check(rc == 0 and C.recorded(os.path.join(d, 'data')) == 54, 'set --force lowers')
rc, out = run(os.path.join(HERE, 'client_pair.py'), 'set', d, '56', '--dry-run')
check(rc == 0 and C.recorded(os.path.join(d, 'data')) == 54 and 'dry run' in out, 'set --dry-run writes nothing')
for bad in (['set', d, 'x'], ['set', d, '0'], ['set', d], ['show'], ['bogus', d]):
    check(run(os.path.join(HERE, 'client_pair.py'), *bad)[0] == 1, 'bad arguments refused: ' + ' '.join(bad[:1] + bad[2:]))

# ---- fist weapons: apply_pair_guard on the shipped manifest
rows = F.rows_of(F.DEFAULT_MANIFESTS)
for pair in (None, 54, 55):
    g, notes = F.apply_pair_guard(rows, pair)
    check(len(g) == 19 and len(notes) == 1, 'pair %s: 19 rows (the 3 new4 rows held back)' % pair)
    check(all(r['mode'] != 'new4' for r in g), 'pair %s: no new4 row' % pair)
    for r in g:
        if r['mode'] == 'repoint':
            check(r['client_id'] == r['server_id'] - 12000 and 28003 <= r['client_id'] <= 28012, 'pair %s: %s on its donor look' % (pair, r['key']))
    check([r['server_id'] for r in g] == [r['server_id'] for r in rows if r['mode'] != 'new4'], 'pair %s: order and ids kept' % pair)
g, notes = F.apply_pair_guard(rows, 56)
check(g is rows and notes == [], 'pair 56: every row as the manifest says')
check(F.apply_pair_guard(rows, 99)[0] is rows, 'pair 99: the same')
check(all(r['client_id'] >= 44399 for r in rows if r['mode'] in ('repoint', 'new4')), 'the manifest itself is not changed by the guard')


# ---- the tools end to end on a synthetic server
def item_node(sid, cid, flags=FLAG_PICKUPABLE | FLAG_MOVEABLE, group=0):
    body = struct.pack('<I', flags) + attr(A_SERVERID, struct.pack('<H', sid)) + attr(A_CLIENTID, struct.pack('<H', cid))
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def otb(nodes):
    root = bytes([START, 0]) + escape(struct.pack('<I', 0))
    return b'\x00\x00\x00\x00' + root + b''.join(nodes) + bytes([END])


def fill(d):
    stock = [item_node(7618, 7618), item_node(7620, 7620), item_node(30000, 25045)]
    open(os.path.join(d, 'data', 'items', 'items.otb'), 'wb').write(otb(stock))
    open(os.path.join(d, 'data', 'items', 'items.xml'), 'w').write('<?xml version="1.0"?>\n<items>\n</items>\n')
    open(os.path.join(d, 'data', 'movements', 'movements.xml'), 'w').write('<movements>\n</movements>\n')


def snap(d):
    out = {}
    for root, _, files in os.walk(os.path.join(d, 'data')):
        for n in files:
            out[os.path.join(root, n)] = open(os.path.join(root, n), 'rb').read()
    return out


for cfg, label in ((None, 'no config'), ('x = 1\n', 'no key'), ('chaosClientPair = 54\n', 'pair 54')):
    d = server(cfg)
    fill(d)
    before = snap(d)
    rc, out = run(os.path.join(HERE, 'install_pickups.py'), os.path.join(d, 'data'))
    check(rc == 0 and 'WARNING' in out and 'skipped' in out and snap(d) == before, 'pickups, %s: skipped, nothing written (%s)' % (label, out.strip()[:80]))
d = server('chaosClientPair = 55\n')
fill(d)
rc, out = run(os.path.join(HERE, 'install_pickups.py'), os.path.join(d, 'data'))
after = snap(d)
check(rc == 0 and 'installing' in out and b'32088' in after[os.path.join(d, 'data', 'items', 'items.xml')], 'pickups, pair 55: installed (%s)' % out.strip()[:120])
rc, out = run(os.path.join(HERE, 'install_pickups.py'), os.path.join(d, 'data'))
check(rc == 0 and snap(d) == after, 'pickups: a second run changes nothing')

# fist weapons: 54 -> donor looks and no new4; then 56 -> the new looks; then idempotent
d = server('chaosClientPair = 54\n')
fill(d)
rc, out = run(os.path.join(HERE, 'install_fist_weapons.py'), os.path.join(d, 'data'))
xml = open(os.path.join(d, 'data', 'items', 'items.xml')).read()
check(rc == 0 and 'donor looks' in out and out.startswith('WARNING: fistweapons'), 'fist, pair 54: message (%s)' % out.strip()[:200])
check('id="40003"' in xml and 'id="48409"' not in xml and 'id="48411"' not in xml, 'fist, pair 54: repoint items in, new4 items out')
from install_gems import scan  # noqa: E402
kids, _ = scan(open(os.path.join(d, 'data', 'items', 'items.otb'), 'rb').read())
by = {k[2]: k[3] for k in kids}
check(by.get(40003) == 28003 and by.get(40012) == 28012 and 48409 not in by, 'fist, pair 54: nodes on the donor client ids, no new node')
mid = snap(d)
rc, out = run(os.path.join(HERE, 'install_fist_weapons.py'), os.path.join(d, 'data'))
check(rc == 0 and snap(d) == mid, 'fist, pair 54: a second run changes nothing')
C_path = os.path.join(d, 'config.lua')
open(C_path, 'w').write('chaosClientPair = 56\n')
rc, out = run(os.path.join(HERE, 'install_fist_weapons.py'), os.path.join(d, 'data'))
xml = open(os.path.join(d, 'data', 'items', 'items.xml')).read()
kids, _ = scan(open(os.path.join(d, 'data', 'items', 'items.otb'), 'rb').read())
by = {k[2]: k[3] for k in kids}
check(rc == 0 and by.get(40003) == 44399 and by.get(48409) == 44409 and by.get(48411) == 44411 and 'id="48410"' in xml,
      'fist, pair 56: the nodes move to the pair 56 looks and the new weapons come in (%s)' % out.strip()[:120])
done = snap(d)
rc, out = run(os.path.join(HERE, 'install_fist_weapons.py'), os.path.join(d, 'data'))
check(rc == 0 and snap(d) == done, 'fist, pair 56: a second run changes nothing')
# a server that has the old bare donor entries of the repointed claws takes them over (no "entry outside the block" stop)
d = server('chaosClientPair = 56\n')
fill(d)
x = os.path.join(d, 'data', 'items', 'items.xml')
open(x, 'w').write('<items>\n\t<item id="40003" name="claw 4" />\n</items>\n')
rc, out = run(os.path.join(HERE, 'install_fist_weapons.py'), os.path.join(d, 'data'))
check(rc == 0 and open(x).read().count('id="40003"') == 1, 'a bare donor entry of a repointed claw is taken over (%s)' % out.strip()[-120:])

print('client_pair_test: %s' % ('ok' if not failed else '%d failed' % failed))
sys.exit(1 if failed else 0)
