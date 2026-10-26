#!/usr/bin/env python3
"""python3 -I server/tools/install_reward_chest_test.py: install_reward_chest.py on a synthetic items.otb / items.xml with
the stock node (server 21584, client 19250, container group): the look copies its group, flags and attributes with
server id 32310 and client id 38657, agrees with the client things file (art_import/reward_chest.csv) and the configs
(rift_config.lua / descent_config.lua: the new id and the fallback 21584), is verified and left alone on a second run;
a taken id is refused; the items.xml block is added once and takes the stock entry's attributes. No base server needed."""
import csv, os, re, shutil, struct, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_reward_chest as C  # noqa: E402
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


CHAOS = os.path.join(os.path.dirname(HERE), 'data', 'scripts', 'chaos')
sid, cid = C.LOOK
# the configs and the client things file agree with the installer
rift = open(os.path.join(CHAOS, 'rift_config.lua'), encoding='utf-8').read()
check(re.search(r'chest\s*=\s*\{\s*itemId\s*=\s*%d\b' % sid, rift) is not None, 'rift_config.lua chest.itemId is the new id')
check(re.search(r'chest\s*=\s*\{[^}]*fallbackId\s*=\s*%d\b' % C.STOCK_SID, rift) is not None, 'rift_config.lua fallbackId is the stock chest')
descent = open(os.path.join(CHAOS, 'descent_config.lua'), encoding='utf-8').read()
check(re.search(r'chest\s*=\s*%d\b' % sid, descent) is not None, 'descent_config.lua objects.chest is the new id')
check(re.search(r'chestFallback\s*=\s*%d\b' % C.STOCK_SID, descent) is not None, 'descent_config.lua chestFallback is the stock chest')
things = os.path.join(os.path.dirname(os.path.dirname(HERE)), 'client', 'tools', 'sprites', 'art_import', 'reward_chest.csv')
rows = list(csv.DictReader(open(things, newline='')))
check([int(r['server_id']) for r in rows] == [sid], 'client things file: server id')
check(rows[0]['flags'] == 'copy:19250', 'client things file copies the stock client id 19250')
check(C.RANGE[0] <= sid <= C.RANGE[1] and cid == 38657, 'id inside the reserved block, client id of pair 45')

d = tempfile.mkdtemp()
try:
    os.makedirs(os.path.join(d, 'items'))
    stock = item_node(21584, 19250, flags=9, group=2, extra=((0x2A, b'\x03\x00\x1d\x00'),))
    base = [stock, item_node(2160, 3031)]
    open(os.path.join(d, 'items', 'items.otb'), 'wb').write(otb(base))
    xml0 = ('<items>\n\t<item id="2160" name="crystal coin" />\n\t<item id="21584" article="a" name="reward chest">\n'
            '\t\t<attribute key="description" value="Rewards &amp; more." />\n\t\t<attribute key="containersize" value="24" />\n'
            '\t\t<attribute key="pickupable" value="0" />\n\t</item>\n</items>\n')
    open(os.path.join(d, 'items', 'items.xml'), 'w').write(xml0)
    check(C.main([d, '--dry-run']) == 0, 'dry run')
    check(open(os.path.join(d, 'items', 'items.otb'), 'rb').read() == otb(base), 'dry run writes nothing')
    check(C.main([d]) == 0, 'install')
    data = open(os.path.join(d, 'items', 'items.otb'), 'rb').read()
    kids, _ = scan(data)
    by = {k[2]: k for k in kids}
    check(len(kids) == 3, 'one node added (%d)' % len(kids))
    k = by[sid]
    check(k[3] == cid and k[4] == 2 and k[5] == 9, 'node %d: client %d, container group, flags of the stock chest' % (sid, cid))
    check(dict(k[6])[0x2A] == b'\x03\x00\x1d\x00', 'the node keeps the stock attributes')
    check(by[21584][3] == 19250, 'the stock chest is untouched')
    check(os.path.exists(os.path.join(d, 'items', 'items.otb.bak')), 'backup')
    xml = open(os.path.join(d, 'items', 'items.xml')).read()
    check(xml.count(C.XML_BEGIN) == 1 and '<item id="32310" article="a" name="reward chest">' in xml, 'items.xml block')
    block = xml[xml.index(C.XML_BEGIN):]
    check('value="24"' in block and 'Rewards &amp; more.' in block and 'key="pickupable" value="0"' in block,
          "the stock entry's attributes are used")
    check(C.main([d]) == 0, 'second run')
    check(open(os.path.join(d, 'items', 'items.otb'), 'rb').read() == data, 'second run: items.otb unchanged')
    check(open(os.path.join(d, 'items', 'items.xml')).read() == xml, 'second run: items.xml unchanged')
    # a changed node is replaced
    kids, _ = scan(data)
    open(os.path.join(d, 'items', 'items.otb'), 'wb').write(otb(base + [item_node(sid, cid, flags=1, group=2)]))
    check(C.main([d]) == 0, 'a stale node is rewritten')
    k = {x[2]: x for x in scan(open(os.path.join(d, 'items', 'items.otb'), 'rb').read())[0]}[sid]
    check(k[5] == 9, 'stale node: flags of the stock chest again')
    # a taken id
    open(os.path.join(d, 'items', 'items.otb'), 'wb').write(otb(base + [item_node(sid, 5000)]))
    try:
        C.main([d])
        check(False, 'a taken id is refused')
    except SystemExit as e:
        check(str(sid) in str(e), 'a taken id is refused: %s' % e)
    # an items.xml entry outside the block
    open(os.path.join(d, 'items', 'items.otb'), 'wb').write(otb(base))
    open(os.path.join(d, 'items', 'items.xml'), 'w').write(xml0.replace('</items>', '\t<item id="32310" name="x" />\n</items>'))
    try:
        C.main([d])
        check(False, 'an items.xml clash is refused')
    except SystemExit as e:
        check('32310' in str(e), 'an items.xml clash is refused')
    # no stock node
    open(os.path.join(d, 'items', 'items.otb'), 'wb').write(otb([item_node(2160, 3031)]))
    try:
        C.main([d])
        check(False, 'a missing stock node is refused')
    except SystemExit as e:
        check('21584' in str(e), 'a missing stock node is refused')
finally:
    shutil.rmtree(d)

print('install_reward_chest_test: %s' % ('OK' if not failed else 'FAILED %d' % failed))
sys.exit(1 if failed else 0)
