#!/usr/bin/env python3
"""python3 -I server/tools/install_decor_flames_test.py : install_decor_flames.py on the shipped manifest and on synthetic server files
(4 rows: ids, kinds, names, flags, lights; the nodes added and verified, idempotent; the items.xml block added once, kept, rewritten on
a change, refused when an id is taken outside it; the client pair guard end to end, PAIR_DECOR = 74, which windows-assets carries since
2026-11-18 (O647); the install_all wiring). No base server needed."""
import os, struct, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_decor_flames as T  # noqa: E402
import install_all as A  # noqa: E402
import client_pair as C  # noqa: E402
from install_pack_items import patch_otb, verify_otb  # noqa: E402
from install_gems import scan, escape, attr, START, END, A_SERVERID, A_CLIENTID  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def item_node(sid, cid, flags=0, group=0):
    body = struct.pack('<I', flags) + attr(A_SERVERID, struct.pack('<H', sid)) + attr(A_CLIENTID, struct.pack('<H', cid))
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def otb(nodes):
    root = bytes([START, 0]) + escape(struct.pack('<I', 0))
    return b'\x00\x00\x00\x00' + root + b''.join(nodes) + bytes([END])


rows = T.rows_of()
check([r['key'] for r in rows] == ['brazier', 'campfire', 'candle', 'spirit'], 'manifest: brazier, campfire, candle, spirit')
check([r['client_id'] for r in rows] == [44560, 44561, 44562, 44563], 'manifest: client ids 44560..44563 in order')
check([r['server_id'] for r in rows] == [48560, 48561, 48562, 48563], 'manifest: server ids 48560..48563 in order')
check(C.PAIR_DECOR == 74 and C.PAIR_ASSETS >= C.PAIR_DECOR, 'the guard needs pair 74, which windows-assets carries (O647)')
check([r['kind'] for r in rows] == ['stump', 'decor', 'decor', 'decor'], 'kinds: a solid brazier, walkable the rest')
check(rows[0]['otb_flags'] & 1 and not any(r['otb_flags'] & 1 for r in rows[1:]), 'the brazier is solid, the others are not')
check(all(r['otb_flags'] & T.ANIM and not r['otb_flags'] & (32 | 64 | 128) for r in rows), 'animated, not pickupable, moveable or stackable')
check([(r['light_level'], r['light_color']) for r in rows] == [(7, 206), (7, 206), (3, 206), (5, 101)],
      'lights: warm for the fires, a cold one for the spirit flame')
check(all(r['name'].startswith('flame ') for r in rows), 'names start with "flame "')
check(44544 not in [r['client_id'] for r in rows], 'the torch 44544 is not a row (it is animated in place)')

# items.otb
base = otb([item_node(2671, 3582)])
new, c = patch_otb(base, rows)
check(c['new'] == 4 and c['updated'] == 0, 'otb: 4 nodes added')
check(verify_otb(new, rows) >= 4, 'otb: every node verified')
again, c2 = patch_otb(new, rows)
check(again == new and c2['new'] == 0 and c2['updated'] == 0, 'otb: a second run changes nothing')
try:
    patch_otb(otb([item_node(48560, 9999, 0, 2)]), rows)
    check(False, 'otb: a server id of another item stops the script')
except (SystemExit, AssertionError):
    pass

# items.xml
xml = '<?xml version="1.0"?>\n<items>\n\t<item id="2671" name="a ham" />\n</items>\n'
x1, note = T.patch_xml(xml, rows)
check('added' in note and x1.count('<item id="4856') == 4 and 'name="flame brazier"' in x1, 'xml: block added with 4 items')
x2, note2 = T.patch_xml(x1, rows)
check(x2 == x1 and 'up to date' in note2, 'xml: a second run keeps the block')
renamed = [dict(r, name='flame renamed') if r['key'] == 'candle' else r for r in rows]
x3, note3 = T.patch_xml(x1, renamed)
check('rewritten' in note3 and x3.count('flame renamed') == 1 and x3.count(T.XML_BEGIN) == 1, 'xml: block rewritten')
try:
    T.patch_xml(xml.replace('</items>', '\t<item id="48562" name="taken" />\n</items>'), rows)
    check(False, 'xml: a taken id stops the script')
except SystemExit:
    pass


def server(config):
    d = tempfile.mkdtemp(prefix='flamesrv_')
    if config is not None:
        open(os.path.join(d, 'config.lua'), 'w').write(config)
    os.makedirs(os.path.join(d, 'data', 'items'))
    open(os.path.join(d, 'data', 'items', 'items.otb'), 'wb').write(otb([item_node(2400, 2400)]))
    open(os.path.join(d, 'data', 'items', 'items.xml'), 'w').write('<?xml version="1.0"?>\n<items>\n</items>\n')
    return d


def snap(d):
    out = {}
    for root, _, files in os.walk(os.path.join(d, 'data')):
        for n in files:
            out[os.path.join(root, n)] = open(os.path.join(root, n), 'rb').read()
    return out


def run(d, *extra):
    p = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'install_decor_flames.py'), os.path.join(d, 'data')] + list(extra),
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
    return p.returncode, p.stdout


for cfg, label in ((None, 'no config.lua'), ('x = 1\n', 'no key'), ('chaosClientPair = 60\n', 'pair 60'), ('chaosClientPair = 73\n', 'pair 73 (the newest built)')):
    d = server(cfg)
    before = snap(d)
    rc, out = run(d)
    check(rc == 0 and out.startswith('WARNING: decorflames skipped') and 'client pair 74' in out and snap(d) == before,
          'guard, %s: skipped with a message, nothing written (%s)' % (label, out.strip()[:100]))
d = server('chaosClientPair = 74\n')
rc, out = run(d, '--dry-run')
check(rc == 0 and 'dry run' in out and 'installing' in out and 'items.otb.bak' not in os.listdir(os.path.join(d, 'data', 'items')),
      'pair 74, dry run: reads and reports, writes nothing')
rc, out = run(d)
after = snap(d)
kids, _ = scan(after[os.path.join(d, 'data', 'items', 'items.otb')])
ids = {k[2]: k[3] for k in kids}
check(rc == 0 and all(ids.get(r['server_id']) == r['client_id'] for r in rows) and 2400 in ids,
      'pair 74: 4 nodes with their client ids, the stock node kept (%s)' % out.strip()[-80:])
check(os.path.exists(os.path.join(d, 'data', 'items', 'items.otb.bak')), 'items.otb.bak kept')
xmlb = after[os.path.join(d, 'data', 'items', 'items.xml')]
check(b'id="48563"' in xmlb and b'flame cold spirit' in xmlb, 'pair 74: items.xml written')
rc, out = run(d)
check(rc == 0 and snap(d) == after, 'pair 74: a second run changes nothing')
open(os.path.join(d, 'config.lua'), 'w').write('chaosClientPair = 99\n')
rc, out = run(d)
check(rc == 0 and snap(d) == after, 'a higher pair installs the same')
d = server('chaosClientPair = 74\n')
open(os.path.join(d, 'data', 'items', 'items.otb'), 'wb').write(otb([item_node(48560, 9999, 0, 2)]))
before = snap(d)
rc, out = run(d)
check(rc != 0 and snap(d) == before, 'a server id that belongs to another item stops the install, nothing written')

# the wiring
check('decorflames' in A.STEPS and A.STEPS.index('decorflames') == A.STEPS.index('templeart') + 1, 'install_all: the step runs right after templeart')
check('decorflames' in A.__doc__ and 'install_decor_flames.py' in A.__doc__, 'install_all: the docstring lists the step')

print('install_decor_flames_test:', 'OK' if not failed else '%d failure(s)' % failed)
sys.exit(1 if failed else 0)
