#!/usr/bin/env python3
"""python3 -I server/tools/install_temple_art_test.py : install_temple_art.py on the shipped manifest and on synthetic server files
(39 rows: ids, kinds, names, flags; the nodes added and verified, idempotent; the items.xml block added once, kept, rewritten on a
change, refused when an id is taken outside it; the client pair guard end to end; the manifest against the one the art generator
writes). No base server needed."""
import os, struct, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', '..', 'client', 'tools', 'sprites'))
import install_temple_art as T  # noqa: E402
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
kinds = {}
for r in rows:
    kinds[r['kind']] = kinds.get(r['kind'], 0) + 1
check(len(rows) == 39 and kinds == {'ground': 11, 'decor': 6, 'stump': 22}, 'manifest: 39 rows, 11 ground, 6 decor, 22 stump (%s)' % kinds)
check([r['client_id'] for r in rows] == list(range(44511, 44550)), 'manifest: client ids 44511..44549 in order')
check([r['server_id'] for r in rows] == list(range(48511, 48550)), 'manifest: server ids 48511..48549 in order')
check(C.PAIR_TEMPLE == 60 and C.PAIR_TEMPLE > C.PAIR_RELIC, 'the guard needs pair 60, after the relic sets (58)')
check(all(r['otb_group'] == 1 and r['speed'] == 100 for r in rows if r['kind'] == 'ground'), 'ground: otb group 1, speed 100')
check(all(r['otb_flags'] & 1 for r in rows if r['kind'] == 'stump') and not any(r['otb_flags'] & 1 for r in rows if r['kind'] != 'stump'),
      'stump items are solid, the rest walkable')
check(all(not r['otb_flags'] & (32 | 64 | 128) for r in rows), 'no item is pickupable, moveable or stackable')
torch = [r for r in rows if r['key'] == 'torch'][0]
check((torch['light_level'], torch['light_color']) == (6, 206), 'the torch carries light 6, colour 206')
names = {r['name'] for r in rows}
check({'temple marble floor', 'temple pillar', 'temple torch', 'temple red carpet'} <= names and all(n.startswith('temple ') for n in names),
      'names start with "temple " (marble floor, pillar, torch, carpet present)')

# that the manifest is what the generator writes for art_import/temple.csv is checked by gen_temple_art_test.py (it
# needs Pillow and numpy, which run in the fx venv job, not in this one)

# items.otb
base = otb([item_node(2671, 3582)])
new, c = patch_otb(base, rows)
check(c['new'] == 39 and c['updated'] == 0, 'otb: 39 nodes added')
check(verify_otb(new, rows) >= 39, 'otb: every node verified')
again, c2 = patch_otb(new, rows)
check(again == new and c2['new'] == 0 and c2['updated'] == 0, 'otb: a second run changes nothing')
try:
    patch_otb(otb([item_node(48511, 9999, 0, 2)]), rows)
    check(False, 'otb: a server id of another item stops the script')
except (SystemExit, AssertionError):
    pass

# items.xml
xml = '<?xml version="1.0"?>\n<items>\n\t<item id="2671" name="a ham" />\n</items>\n'
x1, note = T.patch_xml(xml, rows)
check('added' in note and x1.count('<item id="485') == 39 and 'name="temple pillar"' in x1, 'xml: block added with 39 items')
x2, note2 = T.patch_xml(x1, rows)
check(x2 == x1 and 'up to date' in note2, 'xml: a second run keeps the block')
renamed = [dict(r, name='temple renamed') if r['key'] == 'torch' else r for r in rows]
x3, note3 = T.patch_xml(x1, renamed)
check('rewritten' in note3 and x3.count('temple renamed') == 1 and x3.count(T.XML_BEGIN) == 1, 'xml: block rewritten')
try:
    T.patch_xml(xml.replace('</items>', '\t<item id="48520" name="taken" />\n</items>'), rows)
    check(False, 'xml: a taken id stops the script')
except SystemExit:
    pass


# the whole tool on a synthetic server, with the client pair guard
def server(config):
    d = tempfile.mkdtemp(prefix='templesrv_')
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
    p = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'install_temple_art.py'), os.path.join(d, 'data')] + list(extra),
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
    return p.returncode, p.stdout


for cfg, label in ((None, 'no config.lua'), ('x = 1\n', 'no key'), ('chaosClientPair = 58\n', 'pair 58'), ('chaosClientPair = 59\n', 'pair 59')):
    d = server(cfg)
    before = snap(d)
    rc, out = run(d)
    check(rc == 0 and out.startswith('WARNING: templeart skipped') and 'client pair 60' in out and snap(d) == before,
          'guard, %s: skipped with a message, nothing written (%s)' % (label, out.strip()[:100]))
d = server('chaosClientPair = 60\n')
rc, out = run(d, '--dry-run')
check(rc == 0 and 'dry run' in out and 'installing' in out and 'items.otb.bak' not in os.listdir(os.path.join(d, 'data', 'items')),
      'pair 60, dry run: reads and reports, writes nothing')
rc, out = run(d)
after = snap(d)
kids, _ = scan(after[os.path.join(d, 'data', 'items', 'items.otb')])
ids = {k[2]: k[3] for k in kids}
check(rc == 0 and all(ids.get(r['server_id']) == r['client_id'] for r in rows) and 2400 in ids,
      'pair 60: 39 nodes with their client ids, the stock node kept (%s)' % out.strip()[-80:])
check(os.path.exists(os.path.join(d, 'data', 'items', 'items.otb.bak')), 'items.otb.bak kept')
check(b'id="48549"' in after[os.path.join(d, 'data', 'items', 'items.xml')] and b'temple torch' in after[os.path.join(d, 'data', 'items', 'items.xml')],
      'pair 60: items.xml written')
rc, out = run(d)
check(rc == 0 and snap(d) == after, 'pair 60: a second run changes nothing')
open(os.path.join(d, 'config.lua'), 'w').write('chaosClientPair = 99\n')
rc, out = run(d)
check(rc == 0 and snap(d) == after, 'a higher pair installs the same')
d = server('chaosClientPair = 60\n')
open(os.path.join(d, 'data', 'items', 'items.otb'), 'wb').write(otb([item_node(48511, 9999, 0, 2)]))
before = snap(d)
rc, out = run(d)
check(rc != 0 and snap(d) == before, 'a server id that belongs to another item stops the install, nothing written')

print('install_temple_art_test:', 'OK' if not failed else '%d failure(s)' % failed)
sys.exit(1 if failed else 0)
