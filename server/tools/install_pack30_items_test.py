#!/usr/bin/env python3
"""python3 -I server/tools/install_pack30_items_test.py : install_pack30_items.py on synthetic manifests and a synthetic
items.otb / items.xml (blank padding skipped, ids and kinds checked, nodes added and verified, idempotent, taken ids
refused, items.xml block added / kept / rewritten, the generated Lua and Hideout lists; the shipped generated files up to
date). No base server and no real manifest needed."""
import os, struct, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_pack30_items as T  # noqa: E402
from install_pack_items import patch_otb, verify_otb  # noqa: E402
from install_gems import escape, attr, START, END, A_SERVERID, A_CLIENTID  # noqa: E402

failed = 0
HEAD = 'client_id,server_id,key,kind,mode,name,size,otb_group,otb_flags,top_order,speed,light_level,light_color,extra\n'


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def raises(fn, what):
    try:
        fn()
    except (SystemExit, AssertionError):
        return
    check(False, what)


def item_node(sid, cid, flags=0, group=0):
    body = struct.pack('<I', flags) + attr(A_SERVERID, struct.pack('<H', sid)) + attr(A_CLIENTID, struct.pack('<H', cid))
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def otb(nodes):
    root = bytes([START, 0]) + escape(struct.pack('<I', 0))
    return b'\x00\x00\x00\x00' + root + b''.join(nodes) + bytes([END])


def row(cid, key, kind, name, size, grp, flags, extra='', speed=0, mode='new'):
    return '%d,%d,%s,%s,%s,%s,%s,%d,%d,0,%d,0,0,"%s"\n' % (cid, cid + 3000, key, kind, mode, name, size, grp, flags, speed, extra)


def write(d, name, rows):
    open(os.path.join(d, name), 'w').write(HEAD + ''.join(rows))


with tempfile.TemporaryDirectory() as td:
    check(T.manifest_files(td) == [], 'no manifest: empty list')
    check(T.load_rows([]) == [] and 'return {' in T.lua_text([]) and T.hideout_text([]).endswith('return {\n}\n'),
          'no manifest: empty generated files')
    write(td, 'pack30_items.csv', [
        row(34443, 'blade_a', 'sword', 'iron blade', '2x2', 0, 32 | 64, 'blank=0'),
        row(34444, 'pad_1', 'weapon', 'pad', '1x1', 0, 0, 'blank=1'),
        row(34719, 'flask_lava_small', 'flask', 'lava flask (small)', '1x1', 0, 32 | 128 | (1 << 24)),
    ])
    write(td, 'pack30_looks.csv', [row(34759, 'wolf_corpse', 'corpse', 'dead sootfang wolf', '2x2', 2, 1 << 26, 'race=blood')])
    write(td, 'pack30_grounds.csv', [row(34859, 'frozen_floor', 'ground', 'frozen floor', '1x1', 1, 0, '', speed=150)])
    write(td, 'pack30_decor1.csv', [
        row(35159, 'oak_table', 'stump', 'oak table', '1x1', 0, 8193),
        row(35160, 'red_rug', 'decor', 'red rug', '1x2', 0, 0),
        row(35161, 'big_statue', 'stump', 'big statue', '3x3', 0, 8193),
        row(35162, 'wall_lamp_a', 'wall', 'wall lamp', '1x1', 0, 1 << 16, 'hideout=1|ms=100'),
        row(35163, 'hidden_chest', 'stump', 'chest', '1x1', 0, 8193, 'hideout=0'),
        row(35164, 'tower_r0c0', 'stump', 'tower', '2x2', 0, 8193, 'group=tower|gw=4|gh=2|piece=0,0'),
        row(35165, 'tower_r1c0', 'stump', 'tower', '2x2', 0, 8193, 'group=tower|gw=4|gh=2|piece=1,0'),
    ])
    write(td, 'pack30_bldg2.csv', [row(37113, 'keep', 'stump', 'keep', '4x4', 0, 8193)])
    open(os.path.join(td, 'pack30_outfits.csv'), 'w').write('outfit_id,key\n2237,a\n')
    files = T.manifest_files(td)
    check([os.path.basename(f) for f in files] == ['pack30_bldg2.csv', 'pack30_decor1.csv', 'pack30_grounds.csv',
                                                    'pack30_items.csv', 'pack30_looks.csv'], 'manifests found, outfit table skipped')
    rows = T.load_rows(files)
    check(len(rows) == 12 and all(r['key'] != 'pad_1' for r in rows), 'blank padding row skipped')
    check([r['server_id'] for r in rows] == sorted(r['server_id'] for r in rows), 'rows sorted by server id')

    # otb
    base = otb([item_node(2671, 3582)])
    new, c = patch_otb(base, rows)
    check(c['new'] == 12 and verify_otb(new, rows) >= 12, 'otb: nodes added and verified')
    again, c2 = patch_otb(new, rows)
    check(again == new and c2['new'] == 0 and c2['updated'] == 0, 'otb: a second run changes nothing')
    raises(lambda: patch_otb(otb([item_node(rows[0]['server_id'], 5, 999, 3)]), rows), 'otb: an id of another item stops')
    # item_wire.csv took FLAG_ANIMATION off a node an earlier install wrote with it: the old node is still ours
    import item_wire_table as W
    flask = [dict(r) for r in rows if r['key'] == 'flask_lava_small']
    W.adjust_rows(flask, {flask[0]['server_id']: (flask[0]['client_id'], 0, None)})
    old_node = item_node(flask[0]['server_id'], flask[0]['client_id'], flask[0]['otb_flags_manifest'], flask[0]['otb_group'])
    wired, c3 = patch_otb(otb([old_node]), flask)
    check(c3['updated'] == 1 and verify_otb(wired, flask) == 1, 'otb: a node with the flags before item_wire.csv is replaced')

    # xml
    xml = '<?xml version="1.0"?>\n<items>\n\t<item id="2671" name="a ham" />\n</items>\n'
    x1, note = T.patch_xml(xml, rows)
    check('added' in note and x1.count('<item id="') == 13, 'xml: block added with 12 items')
    check('A sword from the pack art (pair 30).' in x1 and 'article="an" name="iron blade"' in x1, 'xml: description and article')
    check('corpseType' in x1 and 'containerSize' in x1, 'xml: corpse attributes')
    x2, note2 = T.patch_xml(x1, rows)
    check(x2 == x1 and 'up to date' in note2, 'xml: a second run keeps the block')
    ren = [dict(r, name='renamed table') if r['key'] == 'oak_table' else r for r in rows]
    x3, note3 = T.patch_xml(x1, ren)
    check('rewritten' in note3 and x3.count('renamed table') == 1 and x3.count(T.XML_BEGIN) == 1, 'xml: block rewritten')
    raises(lambda: T.patch_xml(xml.replace('</items>', '\t<item id="38159" name="taken" />\n</items>'), rows),
           'xml: a taken id stops')
    raises(lambda: T.patch_xml(xml.replace('</items>', '\t<item fromid="38000" toid="38300" name="x" />\n</items>'), rows),
           'xml: a taken id range stops')

    # lua and hideout
    lua = T.lua_text(rows)
    check('["blade_a"] = {id = 37443, w = 2, h = 2, kind = "sword"' in lua, 'lua: item line')
    check('["tower"] = {gw = 4, gh = 2, pieces = {{0, 0, 38164}, {1, 0, 38165}}}' in lua, 'lua: group with ordered pieces')
    hl = T.hideout_text(rows)
    check('p30_oak_table' in hl and 'block = true' in hl and 'price = 80' in hl, 'hideout: 1x1 table, blocking, 80')
    check('p30_red_rug' in hl and 'layer = "floor"' in hl and 'price = 120' in hl, 'hideout: rug on the floor, 120')
    check('p30_wall_lamp_a' in hl and 'wall = {n = 38162, w = 38162}' in hl, 'hideout: wall item')
    check('big_statue' not in hl and 'hidden_chest' not in hl and 'tower' not in hl and 'blade_a' not in hl and 'keep' not in hl,
          'hideout: 3x3, hideout=0, pieces, other blocks stay out')

    # row rules
    def bad(r, what):
        write(td, 'pack30_bad.csv', [r])
        raises(lambda: T.load_rows(T.manifest_files(td)), what)
        os.remove(os.path.join(td, 'pack30_bad.csv'))
    bad(row(34443, 'x', 'sword', 'x', '2x2', 0, 0), 'a sword must be pickupable')
    bad(row(34460, 'x', 'flask', 'x', '1x1', 0, 32), 'a flask must be stackable')
    bad(row(36000, 'x', 'wall', 'x', '1x1', 0, 0), 'a wall item must be hangable')
    bad(row(36001, 'x', 'stump', 'x', '1x1', 0, 0), 'a stump must block')
    bad(row(36002, 'x', 'decor', 'x', '1x1', 0, 1), 'decor must not block')
    bad(row(36003, 'x', 'ground', 'x', '1x1', 0, 0), 'a ground must be in the ground group')
    bad(row(34443, 'blade_a', 'decor', 'dup', '1x1', 0, 0), 'a key or id twice stops')
    bad(row(37000, 'x', 'decor', 'x', '1x1', 0, 0), 'client 37000 (donor hole) is refused')
    bad(row(34000, 'x', 'decor', 'x', '1x1', 0, 0), 'client id below the block is refused')
    write(td, 'pack30_bad.csv', ['34443,99999,x,decor,new,x,1x1,0,0,0,0,0,0,\n'])
    raises(lambda: T.load_rows(T.manifest_files(td)), 'server id must be client id + 3000')

check(T.hideout_cat('tomb_candle') == 'light' and T.hideout_cat('gothic_banner') == 'banner'
      and T.hideout_cat('pine_tree') == 'nature' and T.hideout_cat('plain') == 'furniture', 'hideout categories')
check(not T.pair30_on() and T.pair30_on.__defaults__[0] == T.SWITCH, 'switch ChaosPack30Art.PAIR30 is off')
with tempfile.TemporaryDirectory() as td:
    on = os.path.join(td, 'a.lua')
    open(on, 'w').write(open(T.SWITCH).read().replace('M.PAIR30 = false', 'M.PAIR30 = true'))
    check(T.pair30_on(on) and not T.pair30_on(os.path.join(td, 'missing.lua')), 'switch read as on / missing as off')

real = T.load_rows(T.manifest_files())
check(open(T.LUA_OUT).read() == T.lua_text(real), 'chaos_pack30_items.lua is up to date (install_pack30_items.py --lua)')
check(open(T.HIDEOUT_OUT).read() == T.hideout_text(real),
      'hideout_pack30_config.lua is up to date (install_pack30_items.py --hideout-lua)')

print('install_pack30_items_test:', 'OK' if not failed else '%d failure(s)' % failed)
sys.exit(1 if failed else 0)
