#!/usr/bin/env python3
"""python3 -I server/tools/install_pouches_test.py: install_pouches.py on a synthetic items.otb / items.xml (four pouches
read from pouches_config.lua, container nodes copied from their stock bags, the Gem Pouch keeps its stock bag's look,
idempotent, an install of the older capacities is rewritten in place, an id taken by another item stops it). No base
server needed."""
import os, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_pouches as T  # noqa: E402
from install_gems import scan, escape, attr, START, END, A_SERVERID, A_CLIENTID, FLAG_PICKUPABLE, FLAG_MOVEABLE  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def item_node(sid, cid, flags=FLAG_PICKUPABLE | FLAG_MOVEABLE, group=2):
    body = struct.pack('<I', flags) + attr(A_SERVERID, struct.pack('<H', sid)) + attr(A_CLIENTID, struct.pack('<H', cid))
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def otb(nodes):
    root = bytes([START, 0]) + escape(struct.pack('<I', 0))
    return b'\x00\x00\x00\x00' + root + b''.join(nodes) + bytes([END])


cfg = T.read_config()
check(list(T.NAMES) == ['loot', 'orbs', 'keys', 'gems'], 'four pouches')
check(cfg['orbs']['capacity'] == 100 and cfg['keys']['capacity'] == 100 and cfg['gems']['capacity'] == 100
      and cfg['loot']['capacity'] == 255, 'capacities: orbs, keys, gems 100, loot 255')
check(cfg['gems']['id'] == 32095 and cfg['gems']['sourceId'] == 5801 and cfg['gems']['clientId'] == 0, 'the Gem Pouch: id 32095, stock look')
check(len({c['id'] for c in cfg.values()}) == 4, 'four distinct server ids')

stock = [item_node(cfg[n]['sourceId'], 20000 + i) for i, n in enumerate(T.NAMES)]
base = otb(stock)
new, notes, wanted = T.patch_otb(base, cfg)
check(len(notes) == 4 and all('added' in n for n in notes), 'four nodes added')
kids, _ = scan(new)
by = {k[2]: k for k in kids}
check(by[32095][3] == by[5801][3], 'the Gem Pouch shows its stock bag look (no new sprite)')
check(by[32082][3] == cfg['orbs']['clientId'], 'the Orbs Pouch shows its own look')
check(T.verify_otb(new, cfg, wanted) == 8, 'verified, eight nodes')
again, notes2, _ = T.patch_otb(new, cfg)
check(again == new and all('present' in n for n in notes2), 'the nodes are idempotent')

xml = '<?xml version="1.0"?>\n<items>\n</items>\n'
x1, _ = T.patch_xml(xml, cfg)
check(x1.count('containerSize') == 4 and 'id="32095"' in x1, 'items.xml: four entries')
x2, note = T.patch_xml(x1, cfg)
check(x2 == x1 and 'up to date' in note, 'items.xml: idempotent')
# an install from before the change (orbs 40, keys 30, no Gem Pouch) is brought up to date
old_cfg = {k: dict(v) for k, v in cfg.items()}
old_cfg['orbs']['capacity'], old_cfg['keys']['capacity'] = 40, 30
old_names = T.NAMES
T.NAMES = ('loot', 'orbs', 'keys')
old_xml, _ = T.patch_xml(xml, old_cfg)
T.NAMES = old_names
check('containerSize" value="40"' in old_xml and 'containerSize" value="30"' in old_xml, 'old install: capacities 40 and 30')
x3, note = T.patch_xml(old_xml, cfg)
check('rewritten' in note and 'containerSize" value="40"' not in x3 and 'containerSize" value="30"' not in x3 and x3.count('containerSize" value="100"') == 3 and 'id="32095"' in x3,
      'items.xml: an old block is rewritten with 100 slots and the Gem Pouch')
check(T.patch_xml(x3, cfg)[0] == x3, 'items.xml: second run changes nothing')
# a foreign item on the Gem Pouch id stops the install
try:
    T.patch_otb(otb(stock + [item_node(32095, 9999)]), cfg)
    check(False, 'a foreign item on 32095 must stop the install')
except SystemExit as e:
    check('already belongs' in str(e), 'a foreign item on 32095 stops the install')
try:
    T.patch_xml(xml.replace('</items>', '\t<item id="32095" name="x" />\n</items>'), cfg)
    check(False, 'an items.xml entry on 32095 must stop the install')
except SystemExit as e:
    check('already has an entry' in str(e), 'an items.xml entry on 32095 stops the install')

if failed:
    sys.exit(1)
print('install_pouches_test: ok')
