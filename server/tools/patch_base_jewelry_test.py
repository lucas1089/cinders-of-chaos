#!/usr/bin/env python3
"""Tests of patch_base_jewelry.py on a small synthetic items.xml and movements.xml (no base server needed).

usage: python3 -I server/tools/patch_base_jewelry_test.py
"""
import io
import os
import shutil
import sys
import tempfile

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import patch_base_jewelry as P  # noqa: E402
import struct  # noqa: E402
from install_gems import scan, escape, attr, START, END, A_SERVERID, A_CLIENTID  # noqa: E402

ITEMS = '''<?xml version="1.0" encoding="UTF-8"?>
<items>
	<item id="2165" article="a" name="stealth ring">
		<attribute key="weight" value="90" />
		<attribute key="slotType" value="ring" />
		<attribute key="transformEquipTo" value="2202" />
		<attribute key="stopduration" value="1" />
		<attribute key="showduration" value="1" />
	</item>
	<item id="2202" article="a" name="stealth ring (invisibility)">
		<attribute key="weight" value="90" />
		<attribute key="slotType" value="ring" />
		<attribute key="decayTo" value="0" />
		<attribute key="transformDeEquipTo" value="2165" />
		<attribute key="duration" value="600" />
		<attribute key="invisible" value="1" />
		<attribute key="showduration" value="1" />
	</item>
	<item id="2197" article="a" name="stone skin amulet">
		<attribute key="weight" value="700" />
		<attribute key="slotType" value="necklace" />
		<attribute key="charges" value="5" />
		<attribute key="showcharges" value="1" />
		<attribute key="absorbPercentPhysical" value="80" />
	</item>
	<item id="2198" article="an" name="elven amulet">
		<attribute key="weight" value="270" />
		<attribute key="slotType" value="necklace" />
		<attribute key="charges" value="50" />
		<attribute key="showcharges" value="1" />
		<attribute key="absorbPercentPhysical" value="5" />
		<attribute key="showattributes" value="1" />
	</item>
	<item id="2207" article="a" name="sword ring">
		<attribute key="weight" value="90" />
		<attribute key="slotType" value="ring" />
		<attribute key="transformEquipTo" value="2210" />
		<attribute key="stopduration" value="1" />
		<attribute key="showduration" value="1" />
	</item>
	<item id="2210" article="a" name="sword ring (sword fighting +4)">
		<attribute key="weight" value="90" />
		<attribute key="slotType" value="ring" />
		<attribute key="decayTo" value="0" />
		<attribute key="transformDeEquipTo" value="2207" />
		<attribute key="skillSword" value="4" />
		<attribute key="duration" value="1800" />
		<attribute key="showduration" value="1" />
	</item>
	<item id="6300" article="a" name="death ring">
		<attribute key="weight" value="80" />
		<attribute key="slotType" value="ring" />
		<attribute key="transformEquipTo" value="6301" />
		<attribute key="stopduration" value="1" />
		<attribute key="showduration" value="1" />
		<attribute key="absorbPercentDeath" value="4" />
	</item>
	<item id="6301" article="a" name="death ring">
		<attribute key="weight" value="80" />
		<attribute key="slotType" value="ring" />
		<attribute key="decayTo" value="0" />
		<attribute key="transformDeEquipTo" value="6300" />
		<attribute key="duration" value="480" />
		<attribute key="armor" value="1" />
		<attribute key="absorbPercentDeath" value="5" />
		<attribute key="showduration" value="1" />
	</item>
	<item id="10309" article="a" name="claw">
		<attribute key="slotType" value="ring" />
		<attribute key="transformDeEquipTo" value="10310" />
	</item>
	<item id="10310" article="a" name="claw">
		<attribute key="slotType" value="ring" />
		<attribute key="transformEquipTo" value="10309" />
	</item>
	<item id="2400" article="a" name="sword">
		<attribute key="weight" value="3000" />
		<attribute key="charges" value="10" />
	</item>
</items>
'''

MOVES = '''<?xml version="1.0" encoding="UTF-8"?>
<movements>
	<movevent event="Equip" itemid="2165" slot="ring" function="onEquipItem" />
	<movevent event="Equip" itemid="2202" slot="ring" function="onEquipItem" />
	<movevent event="DeEquip" itemid="2202" slot="ring" function="onDeEquipItem" />
	<movevent event="Equip" itemid="2207" slot="ring" function="onEquipItem" />
	<movevent event="Equip" itemid="2210" slot="ring" function="onEquipItem" />
	<movevent event="DeEquip" itemid="2210" slot="ring" function="onDeEquipItem" />
	<movevent event="Equip" itemid="6300" slot="ring" level="20" function="onEquipItem">
		<vocation name="Mystic" />
	</movevent>
	<movevent event="DeEquip" fromid="6300" toid="6301" slot="ring" function="onDeEquipItem" />
	<movevent event="Equip" itemid="2198" slot="necklace" function="onEquipItem" />
	<movevent event="DeEquip" itemid="2198" slot="necklace" function="onDeEquipItem" />
</movements>
'''

fails = 0


def ok(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + what)


def block(text, iid):
    start = text.index('<item id="%d"' % iid)
    return text[start:text.index('</item>', start)]


tmp = tempfile.mkdtemp()
try:
    os.makedirs(os.path.join(tmp, 'items'))
    os.makedirs(os.path.join(tmp, 'movements'))
    ipath = os.path.join(tmp, 'items', 'items.xml')
    mpath = os.path.join(tmp, 'movements', 'movements.xml')
    open(ipath, 'w', encoding='latin-1', newline='').write(ITEMS)
    open(mpath, 'w', encoding='latin-1', newline='').write(MOVES)
    quiet = lambda *a: None  # noqa: E731

    # the consumables come from chaos_jewelry.lua
    skip = P.consumables()
    ok(2165 in skip and 2202 in skip and 2197 in skip and 2164 in skip, 'consumables read from chaos_jewelry.lua')
    ok(2207 not in skip and 2198 not in skip, 'skill rings and the elven amulet are gear')

    ok(P.run(tmp, check=True, out=quiet) == 1, '--check: work to do')
    ok(open(ipath, encoding='latin-1').read() == ITEMS, '--check writes nothing')
    ok(P.run(tmp, dry=True, out=quiet) == 0 and open(ipath, encoding='latin-1').read() == ITEMS, 'dry run writes nothing')
    ok(P.run(tmp, out=quiet) == 0, 'run')
    text = open(ipath, encoding='latin-1').read()
    moves = open(mpath, encoding='latin-1').read()

    # 1. the unworn sword ring carries the worn stats, no transformation
    b = block(text, 2207)
    ok('skillSword" value="4"' in b, 'sword ring: the worn skill on the unworn id')
    ok('transformEquipTo' not in b and 'stopduration' not in b and 'showduration' not in b, 'sword ring: no transform')
    ok('showattributes" value="1"' in b, 'sword ring: shows its attributes')
    # the worn values win over the unworn ones; stats only the worn id has are added
    b = block(text, 6300)
    ok('absorbPercentDeath" value="5"' in b and 'absorbPercentDeath" value="4"' not in b, 'death ring: worn value wins')
    ok('armor" value="1"' in b, 'death ring: armour added')
    ok(b.count('absorbPercentDeath') == 1, 'death ring: one death absorb line')
    # 2. a worn id keeps working: no duration, still turns back
    b = block(text, 2210)
    ok('duration' not in b and 'decayTo' not in b, 'worn sword ring: no duration')
    ok('transformDeEquipTo" value="2207"' in b and 'skillSword' in b, 'worn sword ring: still turns back, keeps stats')
    # 3. charges go
    b = block(text, 2198)
    ok('charges' not in b and 'absorbPercentPhysical" value="5"' in b, 'elven amulet: no charges, keeps its absorb')
    # consumables and other items unchanged
    for iid in (2165, 2202, 2197):
        ok(block(text, iid) == block(ITEMS, iid), 'consumable %d unchanged' % iid)
    ok(block(text, 2400) == block(ITEMS, 2400), 'a weapon with charges is no jewelry: unchanged')
    ok(block(text, 10310) == block(ITEMS, 10310), 'a worn id without stats is not merged')

    # movements: a DeEquip entry for the merged sword ring, right after its Equip line; none twice
    ok('<movevent event="DeEquip" itemid="2207" slot="ring" function="onDeEquipItem" />' in moves, 'sword ring DeEquip')
    ok(moves.index('itemid="2207" slot="ring" function="onEquipItem"') < moves.index('DeEquip" itemid="2207"')
       < moves.index('Equip" itemid="2210"'), 'DeEquip next to the Equip entry')
    ok(moves.count('itemid="6300"') == 1, 'death ring: a DeEquip range covers it, nothing added')
    ok(moves.count('DeEquip" itemid="2198"') == 1, 'elven amulet: its DeEquip entry kept, not doubled')
    ok('itemid="2165"' in moves and moves.count('DeEquip" itemid="2165"') == 0, 'consumable: no entry added')
    ok('itemid="10310"' not in moves and 'itemid="10309"' not in moves, 'a ring pair without stats: no entry added')

    # idempotent
    ok(P.run(tmp, check=True, out=quiet) == 0, '--check after the run: nothing to do')
    ok(P.run(tmp, out=quiet) == 0, 'second run')
    ok(open(ipath, encoding='latin-1').read() == text, 'second run: items.xml unchanged')
    ok(open(mpath, encoding='latin-1').read() == moves, 'second run: movements.xml unchanged')

    # an unworn id with no movement entry at all gets both
    open(mpath, 'w', encoding='latin-1', newline='').write('<movements>\n</movements>\n')
    open(ipath, 'w', encoding='latin-1', newline='').write(ITEMS)
    P.run(tmp, out=quiet)
    moves = open(mpath, encoding='latin-1').read()
    ok('Equip" itemid="2207" slot="ring" function="onEquipItem"' in moves and 'DeEquip" itemid="2207"' in moves,
       'both entries added when the base had none')
    ok(moves.rstrip().endswith('</movements>'), 'entries inside <movements>')
finally:
    shutil.rmtree(tmp)


# ------------------------------------------------------------------ items.otb: the own looks of pair 35
def item_node(sid, cid, flags=0x60, group=0):
    body = struct.pack('<I', flags) + attr(A_SERVERID, struct.pack('<H', sid)) + attr(A_CLIENTID, struct.pack('<H', cid))
    body += attr(0x2A, b'\x01\x02')  # another attribute, kept as it is
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def otb(nodes):
    return b'\x00\x00\x00\x00' + bytes([START, 0]) + escape(struct.pack('<I', 0)) + b''.join(nodes) + bytes([END])


ROWS = P.bases()
ok(len(ROWS) == 29 and ROWS[0] == (2168, 38612, 3052) and ROWS[-1] == (27215, 38640, 24559),
   'bases read from chaos_jewelry.lua (server id, look, stock)')
ok([r[1] for r in ROWS] == list(range(38612, 38641)), 'looks 38612..38640 in order')
ANIM = P.FLAG_ANIMATION


def base_nodes(skip=(), cid_of=None):
    out = []
    for sid, look, stock in ROWS:
        if sid in skip:
            continue
        cid = (cid_of or {}).get(sid, stock)
        out.append(item_node(sid, cid, 0x60 | (ANIM if sid == 7889 else 0)))
    # other nodes: a sword with an escaped client id (0x0BFD) and a group-2 container
    out.append(item_node(2400, 0x0BFD, 0x60))
    out.append(item_node(1987, 2853, 0x24, group=2))
    return out


ORIG = otb(base_nodes())
tmp = tempfile.mkdtemp()
try:
    os.makedirs(os.path.join(tmp, 'items'))
    ipath = os.path.join(tmp, 'items', 'items.xml')
    opath = os.path.join(tmp, 'items', 'items.otb')
    open(ipath, 'w', encoding='latin-1', newline='').write(ITEMS)
    open(opath, 'wb').write(ORIG)
    log = []
    quiet = lambda *a: log.append(' '.join(str(x) for x in a))  # noqa: E731

    ok(P.run(tmp, check=True, out=quiet) == 1, 'otb --check: work to do')
    ok(open(opath, 'rb').read() == ORIG and not os.path.exists(opath + '.bak'), 'otb --check writes nothing')
    ok(P.run(tmp, dry=True, out=quiet) == 0 and open(opath, 'rb').read() == ORIG, 'otb dry run writes nothing')
    ok(P.run(tmp, out=quiet) == 0, 'otb run')
    new = open(opath, 'rb').read()
    ok(open(opath + '.bak', 'rb').read() == ORIG, 'items.otb.bak keeps the original')
    kids = {k[2]: k for k in scan(new)[0]}
    old = {k[2]: k for k in scan(ORIG)[0]}
    ok(all(kids[s][3] == look for s, look, _st in ROWS), 'every base on its own look')
    ok(not (kids[7889][5] & ANIM) and old[7889][5] & ANIM, 'lightning pendant: the animation flag goes')
    ok(all(kids[s][5] == 0x60 for s, _l, _st in ROWS if s != 7889), 'other flags as they were')
    ok(all(kids[s][6][2] == (0x2A, b'\x01\x02') and kids[s][4] == 0 for s, _l, _st in ROWS), 'group, other attributes kept')
    ok(kids[2400][3] == 0x0BFD and kids[1987][3] == 2853 and kids[1987][4] == 2, 'other nodes unchanged')
    ok(item_node(2400, 0x0BFD, 0x60) in new, 'the escaped node byte for byte')
    ok(item_node(1987, 2853, 0x24, group=2) in new, 'the container node byte for byte')

    # idempotent
    ok(P.run(tmp, check=True, out=quiet) == 0, 'otb --check after the run: nothing to do')
    ok(P.run(tmp, out=quiet) == 0 and open(opath, 'rb').read() == new, 'otb second run: unchanged')

    # --stock-looks: back to the stock bytes (animation flag again), .bak not overwritten
    ok(P.run(tmp, check=True, stock_looks=True, out=quiet) == 1, '--stock-looks --check: work to do')
    ok(P.run(tmp, stock_looks=True, out=quiet) == 0 and open(opath, 'rb').read() == ORIG, '--stock-looks: the stock bytes')
    ok(P.run(tmp, check=True, stock_looks=True, out=quiet) == 0, '--stock-looks twice: nothing to do')
    ok(P.run(tmp, out=quiet) == 0 and open(opath, 'rb').read() == new, 'own looks again')
    ok(open(opath + '.bak', 'rb').read() == ORIG, '.bak written once')

    # refusals: nothing written, items.xml included
    def refused(data, what):
        open(ipath, 'w', encoding='latin-1', newline='').write(ITEMS)
        open(opath, 'wb').write(data)
        log[:] = []
        ok(P.run(tmp, out=quiet) == 1, what + ': refused')
        ok(open(opath, 'rb').read() == data, what + ': items.otb unchanged')
        ok(open(ipath, encoding='latin-1').read() == ITEMS, what + ': items.xml unchanged')
        return ' '.join(log)

    msg = refused(otb(base_nodes(cid_of={2207: 4000})), 'a base with another client id')
    ok('node 2207 has client id 4000' in msg, 'the refusal names the node')
    msg = refused(otb(base_nodes(skip=(26808,))), 'a base missing')
    ok('no node 26808' in msg, 'the refusal names the missing base')
    msg = refused(otb(base_nodes() + [item_node(30000, 38620, 0x60)]), 'a look already in use')
    ok('client id 38620' in msg, 'the refusal names the client id')
    ok(P.run(tmp, stock_looks=True, out=quiet) == 0, '--stock-looks needs no free look')
finally:
    shutil.rmtree(tmp)

if fails:
    print('patch_base_jewelry_test: %d failure(s)' % fails)
    sys.exit(1)
print('patch_base_jewelry_test: ok')
