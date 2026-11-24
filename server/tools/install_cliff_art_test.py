#!/usr/bin/env python3
"""python3 -I server/tools/install_cliff_art_test.py : install_cliff_art.py on the committed table and on synthetic server files (42 rows:
ids, kind, names, flags; the nodes added and verified, idempotent; the items.xml block added once, kept, rewritten on a change, refused
when an id is taken outside it; the client pair guard end to end, PAIR_CLIFF = 83, not on windows-assets yet; the install_all wiring).
No base server needed (O746)."""
import os, struct, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_cliff_art as T  # noqa: E402
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
check(len(rows) == 42 and [r['client_id'] for r in rows] == list(range(44564, 44606)), 'table: client ids 44564..44605 in order')
check([r['server_id'] for r in rows] == list(range(48564, 48606)), 'table: server ids 48564..48605 in order')
check(C.PAIR_CLIFF == 83 and C.PAIR_MISSILE_U16 == 83 and C.PAIR_ASSETS >= C.PAIR_CLIFF,
      'the guard needs pair 83 (with the wide missiles), on windows-assets since 2026-11-24')
check(all(r['kind'] == 'border' and r['otb_flags_manifest'] == T.ONTOP and r['top_order'] == 1 for r in rows), 'border pieces: ONTOP, top order 1')
check(not any(r['otb_flags'] & (1 | 32 | 64 | 128) for r in rows), 'not solid, pickupable, moveable or stackable')
check(all(r['name'].startswith('cliff ') for r in rows) and len({r['name'] for r in rows}) == 42, 'names start with "cliff ", none twice')
check(sum(1 for r in rows if r['ex']['palette'] == 'stone') == 21 and sum(1 for r in rows if r['ex']['piece'].startswith('lip_')) == 24,
      'two palettes of 21: 9 face pieces and 12 lip pieces each')

# items.otb
base = otb([item_node(2671, 3582)])
new, c = patch_otb(base, rows)
check(c['new'] == 42 and c['updated'] == 0, 'otb: 42 nodes added')
check(verify_otb(new, rows) >= 42, 'otb: every node verified')
again, c2 = patch_otb(new, rows)
check(again == new and c2['new'] == 0 and c2['updated'] == 0, 'otb: a second run changes nothing')
try:
    patch_otb(otb([item_node(48570, 9999, 0, 2)]), rows)
    check(False, 'otb: a server id of another item stops the script')
except (SystemExit, AssertionError):
    pass

# items.xml
xml = '<?xml version="1.0"?>\n<items>\n\t<item id="2671" name="a ham" />\n</items>\n'
x1, note = T.patch_xml(xml, rows)
check('added' in note and x1.count(' name="cliff ') == 42 and 'name="cliff stone south face a"' in x1, 'xml: block added with 42 items')
x2, note2 = T.patch_xml(x1, rows)
check(x2 == x1 and 'up to date' in note2, 'xml: a second run keeps the block')
renamed = [dict(r, name='cliff renamed') if r['key'] == 'earth_lip_n' else r for r in rows]
x3, note3 = T.patch_xml(x1, renamed)
check('rewritten' in note3 and x3.count('cliff renamed') == 1 and x3.count(T.XML_BEGIN) == 1, 'xml: block rewritten')
try:
    T.patch_xml(xml.replace('</items>', '\t<item id="48600" name="taken" />\n</items>'), rows)
    check(False, 'xml: a taken id stops the script')
except SystemExit:
    pass


def server(config):
    d = tempfile.mkdtemp(prefix='cliffsrv_')
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
    p = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'install_cliff_art.py'), os.path.join(d, 'data')] + list(extra),
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
    return p.returncode, p.stdout


for cfg, label in ((None, 'no config.lua'), ('x = 1\n', 'no key'), ('chaosClientPair = 74\n', 'pair 74'), ('chaosClientPair = 82\n', 'pair 82 (the newest built)')):
    d = server(cfg)
    before = snap(d)
    rc, out = run(d)
    check(rc == 0 and out.startswith('WARNING: cliffart skipped') and 'client pair 83' in out and snap(d) == before,
          'guard, %s: skipped with a message, nothing written (%s)' % (label, out.strip()[:100]))
d = server('chaosClientPair = 83\n')
rc, out = run(d, '--dry-run')
check(rc == 0 and 'dry run' in out and 'installing' in out and 'items.otb.bak' not in os.listdir(os.path.join(d, 'data', 'items')),
      'pair 83, dry run: reads and reports, writes nothing')
rc, out = run(d)
after = snap(d)
kids, _ = scan(after[os.path.join(d, 'data', 'items', 'items.otb')])
ids = {k[2]: k[3] for k in kids}
check(rc == 0 and all(ids.get(r['server_id']) == r['client_id'] for r in rows) and 2400 in ids,
      'pair 83: 42 nodes with their client ids, the stock node kept (%s)' % out.strip()[-80:])
check(os.path.exists(os.path.join(d, 'data', 'items', 'items.otb.bak')), 'items.otb.bak kept')
xmlb = after[os.path.join(d, 'data', 'items', 'items.xml')]
check(b'id="48605"' in xmlb and b'cliff earth lip bend south-west' in xmlb, 'pair 83: items.xml written')
rc, out = run(d)
check(rc == 0 and snap(d) == after, 'pair 83: a second run changes nothing')
open(os.path.join(d, 'config.lua'), 'w').write('chaosClientPair = 99\n')
rc, out = run(d)
check(rc == 0 and snap(d) == after, 'a higher pair installs the same')
d = server('chaosClientPair = 83\n')
open(os.path.join(d, 'data', 'items', 'items.otb'), 'wb').write(otb([item_node(48570, 9999, 0, 2)]))
before = snap(d)
rc, out = run(d)
check(rc != 0 and snap(d) == before, 'a server id that belongs to another item stops the install, nothing written')

# the wiring
check('cliffart' in A.STEPS and A.STEPS.index('cliffart') == A.STEPS.index('decorflames') + 1, 'install_all: the step runs right after decorflames')
check('cliffart' in A.__doc__ and 'install_cliff_art.py' in A.__doc__, 'install_all: the docstring lists the step')
check(hasattr(A, 'step_cliffart'), 'install_all: the step function')

print('install_cliff_art_test:', 'OK' if not failed else '%d failure(s)' % failed)
sys.exit(1 if failed else 0)
