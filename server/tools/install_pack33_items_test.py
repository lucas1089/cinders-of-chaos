#!/usr/bin/env python3
"""python3 -I server/tools/install_pack33_items_test.py : the harvest kit of pair 33 on the server side
(install_pack33_items.py) and the Haunted Harvest's own items and NPC (install_harvest_event.py), on a synthetic
items.otb / items.xml and npc folder: the manifest follows the things file (ids, kinds, the review, the decay chains,
names) and is up to date, like the generated Lua table; the nodes are added, verified and left alone on a second run;
a taken id is refused; the items.xml blocks carry the decay; the event items copy their stock nodes; the NPC files
are copied once. No base server and no pair needed."""
import os, shutil, struct, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_pack33_items as T  # noqa: E402
import install_harvest_event as H  # noqa: E402
from install_pack_items import patch_otb, verify_otb  # noqa: E402
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


# ---------------------------------------------------------------- the manifest and the Lua table
rows = T.manifest_rows()
check(len(rows) == 515, 'the kit: 514 items and the corpse (%d)' % len(rows))
check(T.manifest_text(rows) == open(T.MANIFEST, encoding='utf-8').read(), 'pack33_kit.csv is up to date (--manifest)')
loaded = T.load_rows()
check(T.lua_text(loaded) == open(T.LUA_OUT, encoding='utf-8').read(), 'chaos_pack33_kit.lua is up to date (--lua)')
by = {r['key']: r for r in loaded}
check(by['tilled_soil_1']['server_id'] == 41093 and by['corpse_hollow_king']['server_id'] == 41607, 'ids 41093..41607')
check(all(r['server_id'] == r['client_id'] + 3000 for r in loaded), 'server id = client id + 3000')
check(by['tilled_soil_1']['otb_group'] == 1 and by['tilled_soil_1']['speed'] == 100, 'a ground: the ground group, speed 100')
check(by['corn_wall_h']['otb_flags'] & T.SOLID, 'a corn wall blocks')
check(not by['corn_wall_gap_h']['otb_flags'] & T.SOLID, 'a gap in the corn does not')
for k in T.REVIEW:
    check(by[k]['kind'] == 'stump' and by[k]['otb_flags'] & T.SOLID and by[k]['ex'].get('review'),
          'review: %s blocks and remembers the draft' % k)
check(by['jack_lantern_grin']['light_level'] == 3 and by['jack_lantern_grin']['light_color'] == 206, 'a lantern has light')
check(by['jack_lantern_grin']['otb_flags'] & T.ANIM, 'an animated piece')
check(by['spider_web_corner_h']['otb_flags'] & T.HANG, 'a wall hanging is hangable')
check(by['corpse_hollow_king']['otb_group'] == 2, 'the corpse is a container')
for k, (to, sec) in T.DECAY.items():
    check(by[k]['ex'].get('decay') == '%s:%d' % (to, sec), 'decay %s -> %s' % (k, to))
check(by['pumpkin_stage_5_ripe']['name'] == 'ripe pumpkin' and by['seal_sealed']['name'] == 'crypt seal', 'names')
check(by['crypt_brick_h']['name'] == 'crypt brick wall' and by['iron_cemetery_h']['name'] == 'iron cemetery fence',
      'wall and fence names')
check(all(not any(ch.isdigit() for ch in r['name']) or r['kind'] == 'corpse' for r in loaded), 'no variant numbers in names')

# ---------------------------------------------------------------- items.otb / items.xml
stock = [item_node(100, 100, group=1), item_node(6569, 6569, flags=32 | 64 | 128), item_node(2092, 2092, flags=32 | 64),
         item_node(2047, 2047, flags=32 | 64), item_node(9737, 9737, flags=32 | 64)]
raw = otb(stock)
new, c = patch_otb(raw, loaded)
check(c['new'] == 515 and c['updated'] == 0, 'every kit node added')
check(verify_otb(new, loaded) == 520, 'verified')
again, c2 = patch_otb(new, loaded)
check(again == new and c2['new'] == 0 and c2['updated'] == 0, 'a second run changes nothing')
clash = otb(stock + [item_node(41093, 999, flags=1)])
try:
    patch_otb(clash, loaded)
    check(False, 'a taken server id is refused')
except SystemExit:
    pass
xml = '<?xml version="1.0"?>\n<items>\n\t<item id="100" name="grass" />\n</items>\n'
x1, note = T.patch_xml(xml, loaded)
check('added' in note and x1.count('<item id="4') == 515, 'items.xml block added')
check('<item id="41528" article="a" name="ripe pumpkin" />' in x1, 'a ripe pumpkin waits (no decay)')
check('<item id="41524" article="a" name="pumpkin mound">\n\t\t<attribute key="decayTo" value="41525" />' in x1,
      'a mound grows into a sprout')
check('<attribute key="decayTo" value="41534" />\n\t\t<attribute key="duration" value="1" />' in x1, 'the seal breaks open')
check('<attribute key="corpseType" value="blood" />' in x1, 'the corpse')
x2, note2 = T.patch_xml(x1, loaded)
check(x2 == x1 and 'up to date' in note2, 'items.xml: a second run changes nothing')
try:
    T.patch_xml(xml.replace('</items>', '\t<item id="41100" name="x" />\n</items>'), loaded)
    check(False, 'an id with an entry outside the block is refused')
except SystemExit:
    pass

# ---------------------------------------------------------------- the event's items and NPC
items = H.read_items()
check([r['id'] for r in items] == [41620, 41621, 41622, 41623], 'the four event items')
hn, notes, wanted = H.patch_otb(raw, items)
check(H.verify_otb(hn, wanted) == 9, 'event nodes added and verified')
kids = {k[2]: k for k in scan(hn)[0]}
check(kids[41620][3] == 6569 and kids[41620][5] & 128, 'the candy is a stackable copy of the stock candy')
check(kids[41621][3] == 2092 and not kids[41621][5] & 128, 'the key copies the bone key')
hn2, _n, _w = H.patch_otb(hn, items)
check(hn2 == hn, 'event nodes: a second run changes nothing')
hx, hnote = H.patch_xml(xml, items)
check('name="hollow candy" plural="hollow candies"' in hx and 'added' in hnote, 'the event block in items.xml')
check(H.patch_xml(hx, items)[0] == hx, 'and kept on a second run')
td = tempfile.mkdtemp(prefix='harvest_install_test_')
try:
    os.makedirs(os.path.join(td, 'npc', 'scripts'))
    n1 = H.install_gamble.copy_npc(td, H.NPC, False)
    check(os.path.isfile(os.path.join(td, 'npc', 'Widow Hessa.xml')) and
          os.path.isfile(os.path.join(td, 'npc', 'scripts', 'widow_hessa.lua')), 'the NPC files copied')
    n2 = H.install_gamble.copy_npc(td, H.NPC, False)
    check(all('up to date' in n for n in n2) and len(n1) == 2, 'and left alone the second time')
finally:
    shutil.rmtree(td, ignore_errors=True)

print('install_pack33_items_test: %s' % ('ok' if not failed else '%d failure(s)' % failed))
sys.exit(1 if failed else 0)
