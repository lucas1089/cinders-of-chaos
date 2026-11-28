#!/usr/bin/env python3
"""python3 -I server/tools/install_idle_loops_test.py : install_idle_loops.py (step `idleloops`, O787) on a synthetic
items.otb: below the pair 92 gate the listed nodes keep no FLAG_ANIMATION, from it they get it, only a node whose server
AND client id are the row's, idempotent, lowering the record takes it back; the shipped data/items/item_wire_idle.csv
names the client ids of the 24 recipes of client/tools/sprites/gen_idle_loops.py. No base server and no pair needed."""
import csv
import io
import json
import os
import shutil
import struct
import sys
import tempfile
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import client_pair  # noqa: E402
import install_idle_loops as I  # noqa: E402
from install_dark_tiles import scan  # noqa: E402
from install_gems import escape, attr, START, END, A_SERVERID, A_CLIENTID  # noqa: E402
from item_wire_table import FLAG_ANIMATION as A  # noqa: E402

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


def flags_of(path):
    kids, _ = scan(open(path, 'rb').read())
    return {k[2]: k[5] for k in kids}


def run(data, *extra):
    out = io.StringIO()
    with redirect_stdout(out):
        rc = I.main([data] + list(extra))
    return rc, out.getvalue()


d = tempfile.mkdtemp(prefix='idle_loops_test_')
try:
    data = os.path.join(d, 'data')
    os.makedirs(os.path.join(data, 'items'))
    otb_path = os.path.join(data, 'items', 'items.otb')
    open(otb_path, 'wb').write(otb([item_node(2047, 2917, 0x60), item_node(2048, 2918, 0x60),
                                    item_node(43120, 39120, 0x2005), item_node(9999, 7777, 0x10)]))
    table = os.path.join(d, 'idle.csv')
    open(table, 'w').write('server,client,animation,group\n2047,2917,1,\n43120,39120,1,\n9999,1234,1,\n55555,555,1,\n')
    cfg = os.path.join(d, 'config.lua')

    open(cfg, 'w').write('chaosClientPair = %d\n' % (client_pair.PAIR_IDLE_LOOPS - 1))
    before = open(otb_path, 'rb').read()
    rc, out = run(data, '--table', table)
    check(rc == 0 and 'WARNING' in out, 'below the gate: a warning, exit 0: %s' % out)
    check(open(otb_path, 'rb').read() == before, 'below the gate: the still nodes stay as they were')

    open(cfg, 'w').write('chaosClientPair = %d\n' % client_pair.PAIR_IDLE_LOOPS)
    rc, out = run(data, '--table', table, '--dry-run')
    check(rc == 0 and open(otb_path, 'rb').read() == before, 'dry run writes nothing')
    rc, out = run(data, '--table', table)
    f = flags_of(otb_path)
    check(rc == 0 and f[2047] == 0x60 | A and f[43120] == 0x2005 | A, 'at the gate: FLAG_ANIMATION on the listed nodes: %s' % out)
    check(f[2048] == 0x60 and f[9999] == 0x10, 'a node not listed, or listed with another client id, is left alone')
    check('2 nodes' in out and 'not present' in out, 'the report counts the nodes and the absent server id: %s' % out)
    check(os.path.exists(otb_path + '.bak') and open(otb_path + '.bak', 'rb').read() == before, 'items.otb.bak keeps the original')
    once = open(otb_path, 'rb').read()
    run(data, '--table', table)
    check(open(otb_path, 'rb').read() == once, 'a second run changes nothing')

    open(cfg, 'w').write('chaosClientPair = %d\n' % (client_pair.PAIR_IDLE_LOOPS - 2))
    run(data, '--table', table)
    check(open(otb_path, 'rb').read() == before, 'lowering the record takes the flags back: the bytes of before')
    os.remove(cfg)
    rc, out = run(data, '--table', table)
    check(rc == 0 and 'missing' in out and open(otb_path, 'rb').read() == before, 'no record: the still form')
finally:
    shutil.rmtree(d, ignore_errors=True)

# the shipped table: one row per node, animation 1, the client ids of the 24 recipes, none in item_wire.csv
rows = list(csv.DictReader(open(I.TABLE, newline='')))
sids = [int(r['server']) for r in rows]
check(len(sids) == len(set(sids)), 'item_wire_idle.csv: no server id twice')
check(all(r['animation'] == '1' and r['group'] == '' for r in rows), 'item_wire_idle.csv: animation 1, no group')
recipes = os.path.join(HERE, '..', '..', 'client', 'tools', 'sprites', 'art_import', 'idle_loops')
cids = {json.load(open(os.path.join(recipes, f)))['client_id'] for f in os.listdir(recipes) if f.endswith('.json')}
check({int(r['client']) for r in rows} == cids and len(cids) == 24, 'item_wire_idle.csv names the client ids of the 24 recipes')
main = {int(r['server']) for r in csv.DictReader(open(os.path.join(os.path.dirname(I.TABLE), 'item_wire.csv'), newline=''))}
check(not (main & set(sids)), 'no idle loop node is in item_wire.csv too')
check(client_pair.PAIR_IDLE_LOOPS == 92, 'the gate is pair 92')

print('install_idle_loops_test: %s' % ('OK' if not failed else '%d FAILED' % failed))
sys.exit(1 if failed else 0)
