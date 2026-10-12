#!/usr/bin/env python3
"""Tests of gen_field_timers.py on a small items.xml and items.otb built here (no installed server needed).
usage: python3 -I client/tools/gen_field_timers_test.py"""
import os, struct, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_field_timers as G

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


def esc(b):
    """escape the node markers inside a payload (0xfd before 0xfd, 0xfe, 0xff)"""
    out = bytearray()
    for x in b:
        if x in (0xfd, 0xfe, 0xff):
            out.append(0xfd)
        out.append(x)
    return bytes(out)


def otb(pairs):
    """an items.otb with one item node per (server id, client id)"""
    data = bytearray(b'\x00\x00\x00\x00')  # file identifier
    root = struct.pack('<I', 0) + bytes([0x01]) + struct.pack('<H', 4) + struct.pack('<I', 3)  # flags, version attr
    data += b'\xfe\x00' + esc(root)
    for sid, cid in pairs:
        pl = struct.pack('<I', 0) + bytes([0x10]) + struct.pack('<H', 2) + struct.pack('<H', sid) \
            + bytes([0x11]) + struct.pack('<H', 2) + struct.pack('<H', cid)
        data += b'\xfe\x01' + esc(pl) + b'\xff'
    data += b'\xff'
    return bytes(data)


XML = b'''<?xml version="1.0" encoding="iso-8859-1"?>
<items>
  <item id="100" name="fire"><attribute key="type" value="magicfield"/><attribute key="decayTo" value="101"/><attribute key="duration" value="120"/></item>
  <item id="101" name="fire"><attribute key="type" value="magicfield"/><attribute key="decayTo" value="0"/><attribute key="duration" value="60"/></item>
  <item id="102" name="magic wall"><attribute key="type" value="magicfield"/><attribute key="decayTo" value="0"/><attribute key="duration" value="20"/></item>
  <item id="103" name="magic wall"><attribute key="type" value="magicfield"/></item>
  <item id="104" name="searing fire"><attribute key="type" value="magicfield"/><attribute key="decayTo" value="105"/><attribute key="duration" value="10"/></item>
  <item id="105" name="ashes"><attribute key="decayTo" value="104"/><attribute key="duration" value="5"/></item>
  <item id="106" name="corpse"><attribute key="decayTo" value="0"/><attribute key="duration" value="60"/></item>
  <item fromid="107" toid="108" name="wild growth"><attribute key="type" value="magicfield"/><attribute key="decayTo" value="0"/><attribute key="duration" value="45"/></item>
  <item id="109" name="odd wall"><attribute key="type" value="magicfield"/><attribute key="decayTo" value="0"/><attribute key="duration" value="30"/></item>
  <item id="110" name="smoke"><attribute key="type" value="magicfield"/><attribute key="decayTo" value="111"/><attribute key="duration" value="8"/></item>
  <item id="111" name="soot" />
  <item id="112" name="lost"><attribute key="type" value="magicfield"/><attribute key="decayTo" value="0"/><attribute key="duration" value="9"/></item>
  <item id="113" name="it's"><attribute key="type" value="MagicField"/><attribute key="decayto" value="0"/><attribute key="duration" value="7"/></item>
</items>
'''
PAIRS = [(100, 2000), (101, 2001), (102, 2002), (103, 2002), (104, 2004), (105, 2005), (106, 2006), (107, 2007),
         (108, 2008), (109, 2002), (110, 2010), (111, 2011), (113, 2013)]  # 112 has no client id; 109 clashes with 102

items = G.read_items(XML)
check(items[100]['decayTo'] == 101 and items[100]['duration'] == 120, 'items.xml attributes')
check(items[108]['name'] == 'wild growth', 'fromid / toid range')
check(G.chain_seconds(items, 100) == 180, 'a chain adds up')
check(G.chain_seconds(items, 101) == 60, 'the last stage alone')
check(G.chain_seconds(items, 104) is None, 'a cycle never goes away')
check(G.chain_seconds(items, 103) is None, 'no decay')
check(G.chain_seconds(items, 110) == 8, 'turns into a lasting item: the timer ends with the change')

cids = G.otb_client_ids(otb(PAIRS))
check(cids.get(100) == 2000 and cids.get(113) == 2013, 'items.otb client ids')
check(112 not in cids, 'no client id')
# a payload byte that needs escaping (0xfe in a client id) survives
check(G.otb_client_ids(otb([(300, 0x01fe)]))[300] == 0x01fe, 'escaped bytes')

table, notes = G.build(items, cids)
check(table.get(2000) == (180000, 'fire'), 'fire: 3 minutes in all')
check(table.get(2001) == (60000, 'fire'), 'its last stage')
check(2002 not in table, 'magic wall left out: 102 and 109 share a client id with different times')
check(any('client id 2002' in n for n in notes), 'the clash is reported')
check(2004 not in table and 2005 not in table, 'the cycle is left out')
check(2006 not in table, 'not a magic field (a corpse)')
check(table.get(2007) == (45000, 'wild growth') and table.get(2008) == (45000, 'wild growth'), 'range items')
check(table.get(2010) == (8000, 'smoke'), 'smoke until it turns into soot')
check(any('server id 112' in n for n in notes), 'a missing client id is reported')
check(table.get(2013) == (7000, "it's"), 'case of type and decayTo ignored')

# without the clash the shared id of a timed wall and a lasting one (a wall placed on the map) is kept
table2, _ = G.build(items, G.otb_client_ids(otb([(102, 2002), (103, 2002)])))
check(table2.get(2002) == (20000, 'magic wall'), 'a lasting item sharing the id is ignored')

text = G.render(table)
check(text.startswith('-- GENERATED by client/tools/gen_field_timers.py'), 'header')
check("  [2000] = { t = 180000, n = 'fire' }," in text, 'a row')
check("n = 'it\\'s'" in text, 'quotes escaped')
check(text.rstrip().endswith('}'), 'closed')

# the command line on a temporary server folder: write, then --check
with tempfile.TemporaryDirectory() as d:
    os.makedirs(os.path.join(d, 'srv', 'data', 'items'))
    open(os.path.join(d, 'srv', 'data', 'items', 'items.xml'), 'wb').write(XML)
    open(os.path.join(d, 'srv', 'data', 'items', 'items.otb'), 'wb').write(otb(PAIRS))
    out = os.path.join(d, 'fielddata.lua')
    tool = os.path.join(HERE, 'gen_field_timers.py')
    r = subprocess.run([sys.executable, '-I', tool, os.path.join(d, 'srv'), '--out', out], capture_output=True, text=True)
    check(r.returncode == 0 and os.path.exists(out), 'writes the file: ' + r.stdout + r.stderr)
    r = subprocess.run([sys.executable, '-I', tool, os.path.join(d, 'srv'), '--out', out, '--check'],
                       capture_output=True, text=True)
    check(r.returncode == 0, '--check: up to date')
    open(out, 'a').write('-- edited\n')
    r = subprocess.run([sys.executable, '-I', tool, os.path.join(d, 'srv'), '--out', out, '--check'],
                       capture_output=True, text=True)
    check(r.returncode == 1, '--check: an edited file is reported')

# the committed table parses as the module expects: client id -> {t, n}
committed = open(G.DEFAULT_OUT, encoding='utf-8').read()
check(committed.startswith('-- GENERATED by client/tools/gen_field_timers.py'), 'committed file is generated')
check('TileOverlayFields = {' in committed, 'committed table name')

print('gen_field_timers_test:', 'OK' if not fails else '%d failed' % fails)
sys.exit(1 if fails else 0)
