#!/usr/bin/env python3
"""python3 -I server/tools/install_cursed_chest_test.py: install_cursed_chest.py on a synthetic items.otb / items.xml with
the stock chest node (server 12664, client 4073, container group): the three looks copy its group, flags and attributes
with server ids 32281-32283 and client ids 38642-38644, agree with cursedchest_config.lua (ids) and the client things
files (art_import/cursed_chest.csv, cursed_chest_k3.csv), are verified and left alone on a second run; the first look is a
still since pair 53 (no animation flag) and a node an earlier run wrote with the flag is rewritten without it; a taken id
is refused; the items.xml block is added once and takes the stock entry's container size. No base server needed."""
import csv, os, re, shutil, struct, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_cursed_chest as C  # noqa: E402
from install_gems import escape, attr, scan, START, END, A_SERVERID, A_CLIENTID  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def item_node(sid, cid, flags=0, group=0, extra=()):
    body = struct.pack('<I', flags) + attr(A_SERVERID, struct.pack('<H', sid)) + attr(A_CLIENTID, struct.pack('<H', cid))
    for k, v in extra:
        body += attr(k, v)
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def otb(nodes):
    root = bytes([START, 0]) + escape(struct.pack('<I', 0))
    return b'\x00\x00\x00\x00' + root + b''.join(nodes) + bytes([END])


# the config and the client things file agree with the installer
cfg = open(os.path.join(os.path.dirname(HERE), 'data', 'scripts', 'chaos', 'cursedchest_config.lua'), encoding='utf-8').read()
m = re.search(r'\bitemIds\s*=\s*\{([^}]*)\}', cfg)
m2 = re.search(r'legacyItemIds\s*=\s*\{([^}]*)\}', cfg)
check(m is not None and m2 is not None and [int(x) for x in re.findall(r'\d+', m.group(1) + ',' + m2.group(1))]
      == [s for s, _c, _a in C.LOOKS], 'cursedchest_config.lua itemIds (the look) and legacyItemIds (the older looks) are the installer server ids')
check([int(x) for x in re.findall(r'\d+', m.group(1))] == [32281], 'cursedchest_config.lua: one look, the one-tile one (32281)')
check(re.search(r'itemId\s*=\s*%d\b' % C.STOCK_SID, cfg) is not None, 'the fallback itemId is the stock chest')
things = os.path.join(os.path.dirname(os.path.dirname(HERE)), 'client', 'tools', 'sprites', 'art_import', 'cursed_chest.csv')
rows = list(csv.DictReader(open(things, newline='')))
check([int(r['server_id']) for r in rows] == [s for s, _c, _a in C.LOOKS], 'client things file: server ids')
k3 = list(csv.DictReader(open(os.path.join(os.path.dirname(things), 'cursed_chest_k3.csv'), newline='')))
check(len(k3) == 1 and (k3[0]['w'], k3[0]['h'], k3[0]['phases'], k3[0]['mode'], int(k3[0]['server_id'])) == ('1', '1', '1', 'redraw', 32281)
      and k3[0]['extra'] == 'item=38642', 'client things file of the one-tile look: 1 x 1, one phase, redraws 38642 / server 32281')
check([a for _s, _c, a in C.LOOKS] == [False, False, True], 'the first look (one tile, pair 53) and B are stills, C is animated')
check(all(C.RANGE[0] <= s <= C.RANGE[1] for s, _c, _a in C.LOOKS), 'ids inside the reserved block')

d = tempfile.mkdtemp()
try:
    os.makedirs(os.path.join(d, 'items'))
    stock = item_node(12664, 4073, flags=9, group=2, extra=((0x2A, b'\x03\x00\x1d\x00'),))
    base = [stock, item_node(2160, 3031)]
    open(os.path.join(d, 'items', 'items.otb'), 'wb').write(otb(base))
    xml0 = ('<items>\n\t<item id="2160" name="crystal coin" />\n\t<item fromid="12664" toid="12665" article="a" '
            'name="treasure chest">\n\t\t<attribute key="containerSize" value="24" />\n\t</item>\n</items>\n')
    open(os.path.join(d, 'items', 'items.xml'), 'w').write(xml0)
    check(C.main([d, '--dry-run']) == 0, 'dry run')
    check(open(os.path.join(d, 'items', 'items.otb'), 'rb').read() == otb(base), 'dry run writes nothing')
    check(C.main([d]) == 0, 'install')
    data = open(os.path.join(d, 'items', 'items.otb'), 'rb').read()
    kids, _ = scan(data)
    by = {k[2]: k for k in kids}
    check(len(kids) == 5, 'three nodes added (%d)' % len(kids))
    for sid, cid, anim in C.LOOKS:
        k = by[sid]
        check(k[3] == cid and k[4] == 2 and k[5] == (9 | (1 << 24 if anim else 0)),
              'node %d: client %d, container group, flags of the stock chest (+ animation: %s)' % (sid, cid, anim))
        check(dict(k[6])[0x2A] == b'\x03\x00\x1d\x00', 'node %d keeps the stock attributes' % sid)
    check(by[12664][3] == 4073, 'the stock chest is untouched')
    check(os.path.exists(os.path.join(d, 'items', 'items.otb.bak')), 'backup')
    xml = open(os.path.join(d, 'items', 'items.xml')).read()
    check(xml.count(C.XML_BEGIN) == 1 and '<item id="32283" article="a" name="cursed chest">' in xml, 'items.xml block')
    check(xml.count('value="24"') == 4, 'the stock entry container size (24) is used')
    check(C.main([d]) == 0, 'second run')
    check(open(os.path.join(d, 'items', 'items.otb'), 'rb').read() == data, 'second run: items.otb unchanged')
    check(open(os.path.join(d, 'items', 'items.xml')).read() == xml, 'second run: items.xml unchanged')
    # a server that ran the install of pair 43 has the first look with FLAG_ANIMATION: the next run drops it
    old = otb(base + [item_node(32281, 38642, flags=9 | (1 << 24), group=2, extra=((0x2A, b'\x03\x00\x1d\x00'),))])
    open(os.path.join(d, 'items', 'items.otb'), 'wb').write(old)
    check(C.main([d]) == 0, 'migration run')
    kids2, _ = scan(open(os.path.join(d, 'items', 'items.otb'), 'rb').read())
    by2 = {k[2]: k for k in kids2}
    check(by2[32281][5] == 9 and by2[32283][5] == 9 | (1 << 24), 'the first look lost the animation flag, the third keeps it')
    check([k[2] for k in kids2].count(32281) == 1, 'the first look was rewritten in place, not added twice')
    migrated = open(os.path.join(d, 'items', 'items.otb'), 'rb').read()
    check(C.main([d]) == 0 and open(os.path.join(d, 'items', 'items.otb'), 'rb').read() == migrated, 'idempotent after the migration')
    # a taken id
    open(os.path.join(d, 'items', 'items.otb'), 'wb').write(otb(base + [item_node(32282, 5000)]))
    try:
        C.main([d])
        check(False, 'a taken id is refused')
    except SystemExit as e:
        check('32282' in str(e), 'a taken id is refused: %s' % e)
    # no stock node
    open(os.path.join(d, 'items', 'items.otb'), 'wb').write(otb([item_node(2160, 3031)]))
    try:
        C.main([d])
        check(False, 'a missing stock node is refused')
    except SystemExit as e:
        check('12664' in str(e), 'a missing stock node is refused')
finally:
    shutil.rmtree(d)

print('install_cursed_chest_test: %s' % ('OK' if not failed else 'FAILED %d' % failed))
sys.exit(1 if failed else 0)
