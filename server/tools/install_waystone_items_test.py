#!/usr/bin/env python3
"""python3 -I server/tools/install_waystone_items_test.py: install_waystone_items.py on a synthetic items.otb / items.xml
with the six base Waystone Tier nodes: the nine new tiers copy their base look with their own server ids, agree with
waystone_tiers_config.lua (ids, levels), are verified and left alone on a second run; a taken id is refused; the
items.xml block is added once. No base server needed."""
import os, re, shutil, struct, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_waystone_items as W  # noqa: E402
from install_gems import escape, attr, scan, START, END, A_SERVERID, A_CLIENTID  # noqa: E402

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


# the config agrees: ids and levels of every tier
cfg = open(os.path.join(os.path.dirname(HERE), 'data', 'scripts', 'chaos', 'waystone_tiers_config.lua'), encoding='utf-8').read()
tiers = [(int(lv), int(it)) for lv, it in re.findall(r'\{level = (\d+), item = (\d+)', cfg)]
check(len(tiers) == 15, 'fifteen tiers in the config (%d)' % len(tiers))
for t, (lv, it) in enumerate(tiers, 1):
    check(lv == W.level(t), 'tier %d level %d' % (t, lv))
    if t <= 6:
        check(it == W.BASE_IDS[t - 1], 'tier %d is the base item' % t)
    else:
        check(it == W.NEW[t][0], 'tier %d item %d' % (t, it))
rows = W.rows()
check([r['name'] for r in rows][0] == 'Waystone Tier VII' and rows[-1]['name'] == 'Waystone Tier XV', 'names VII..XV')
check('monster level 2500' in rows[-1]['description'], 'the level in the description')

d = tempfile.mkdtemp()
try:
    os.makedirs(os.path.join(d, 'items'))
    base = [item_node(29845 + i, 27189 + i, flags=96) for i in range(6)] + [item_node(2160, 3031)]
    open(os.path.join(d, 'items', 'items.otb'), 'wb').write(otb(base))
    open(os.path.join(d, 'items', 'items.xml'), 'w').write('<items>\n\t<item id="2160" name="crystal coin" />\n</items>\n')
    check(W.main([d]) == 0, 'install')
    data = open(os.path.join(d, 'items', 'items.otb'), 'rb').read()
    kids, _ = scan(data)
    by = {k[2]: k for k in kids}
    check(len(kids) == 16, 'nine nodes added (%d)' % len(kids))
    check(by[41951][3] == 27191, 'VII looks like III')
    check(by[41959][3] == 27194 and by[41959][5] == 96, 'XV looks like VI, same flags')
    check(os.path.exists(os.path.join(d, 'items', 'items.otb.bak')), 'backup')
    xml = open(os.path.join(d, 'items', 'items.xml')).read()
    check(xml.count(W.XML_BEGIN) == 1 and '<item id="41959" name="Waystone Tier XV">' in xml, 'items.xml block')
    check(W.main([d]) == 0, 'second run')
    check(open(os.path.join(d, 'items', 'items.otb'), 'rb').read() == data, 'second run: items.otb unchanged')
    check(open(os.path.join(d, 'items', 'items.xml')).read() == xml, 'second run: items.xml unchanged')
    # a taken id
    open(os.path.join(d, 'items', 'items.otb'), 'wb').write(otb(base + [item_node(41955, 5000)]))
    try:
        W.main([d])
        check(False, 'a taken id is refused')
    except SystemExit as e:
        check('41955' in str(e), 'a taken id is refused: %s' % e)
finally:
    shutil.rmtree(d)

print('install_waystone_items_test: %s' % ('OK' if not failed else 'FAILED %d' % failed))
sys.exit(1 if failed else 0)
