#!/usr/bin/env python3
"""python3 -I server/tools/install_assets_decor_test.py : install_assets_decor.py on a synthetic items.otb / items.xml
(the shipped manifest: 9 rows, ids, kinds; the nodes added and verified, idempotent; the items.xml block added once,
kept, rewritten on a change, refused when an id is taken outside it; the generated Lua up to date; the switch on).
No base server needed."""
import os, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_assets_decor as T  # noqa: E402
from install_pack_items import patch_otb, verify_otb  # noqa: E402
from install_gems import escape, attr, START, END, A_SERVERID, A_CLIENTID  # noqa: E402

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


rows = T.rows_of(T.DEFAULT_MANIFEST)
check(len(rows) == 9, 'manifest: nine catacomb items')
check([r['server_id'] for r in rows] == list(range(36986, 36995)), 'manifest: server ids 36986..36994 in order')
check(all(r['kind'] == ('stump' if r['ex']['block'] == '1' else 'decor') for r in rows),
      'blocking ones are stumps, the rest decor')
portal = [r for r in rows if r['key'] == 'crypt_portal']
check(len(portal) == 1 and portal[0]['size'] == '3x3' and portal[0]['light_level'] == 3, 'portal: 3x3 with a light')
check(all(r['otb_flags'] & 32 == 0 for r in rows), 'no item is pickupable')
check(T.pair27_on(), 'switch ChaosAssetsArt.PAIR27 is on (pair 27 is live)')
import tempfile  # noqa: E402
with tempfile.TemporaryDirectory() as td:
    off = os.path.join(td, 'chaos_assets_art.lua')
    open(off, 'w').write(open(T.SWITCH).read().replace('M.PAIR27 = true', 'M.PAIR27 = false'))
    check(not T.pair27_on(off) and not T.pair27_on(os.path.join(td, 'missing.lua')), 'switch read as off when false or missing')

base = otb([item_node(2671, 3582)])
new, c = patch_otb(base, rows)
check(c['new'] == 9 and c['updated'] == 0, 'otb: 9 nodes added')
check(verify_otb(new, rows) >= 9, 'otb: every node verified')
again, c2 = patch_otb(new, rows)
check(again == new and c2['new'] == 0 and c2['updated'] == 0, 'otb: a second run changes nothing')

xml = '<?xml version="1.0"?>\n<items>\n\t<item id="2671" name="a ham" />\n</items>\n'
x1, note = T.patch_xml(xml, rows)
check('added' in note and x1.count('<item id="369') == 9, 'xml: block added with 9 items')
x2, note2 = T.patch_xml(x1, rows)
check(x2 == x1 and 'up to date' in note2, 'xml: a second run keeps the block')
renamed = [dict(r, name='renamed hatch') if r['key'] == 'crypt_seal' else r for r in rows]
x3, note3 = T.patch_xml(x1, renamed)
check('rewritten' in note3 and x3.count('renamed hatch') == 1 and x3.count(T.XML_BEGIN) == 1, 'xml: block rewritten')
try:
    T.patch_xml(xml.replace('</items>', '\t<item id="36990" name="taken" />\n</items>'), rows)
    check(False, 'xml: a taken id stops the script')
except SystemExit:
    pass
check(open(T.LUA_OUT).read() == T.lua_text(rows), 'chaos_assets_decor.lua is up to date (install_assets_decor.py --lua)')

print('install_assets_decor_test:', 'OK' if not failed else '%d failure(s)' % failed)
sys.exit(1 if failed else 0)
