#!/usr/bin/env python3
"""python3 -I server/tools/install_supports_test.py: install_supports.py on a synthetic items.otb with the ten stock rune
stones (server 24685.., client 22029..): the 100 rune nodes copy their stone's group, flags (stackable, use-with) and
attributes with their own server id (32101..32200) and own client id (38658..38757, pair 46), agree with the client things
file (art_import/support_runes.csv), are verified and left alone on a second run; a taken client id is refused; a node still
on the stock look is turned to the own look; without clientFirstId every node keeps (or goes back to) the stock stone's client
id. No base server needed."""
import csv, os, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_supports as C  # noqa: E402
from install_gems import escape, attr, scan, START, END, A_SERVERID, A_CLIENTID, FLAG_USEABLE, FLAG_STACKABLE  # noqa: E402

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


cfg = C.read_config()
rows = C.runes(cfg)
check(len(rows) == 100 and cfg['clientFirstId'] == 38658, 'a hundred runes, clientFirstId 38658')
check([r[0] for r in rows] == list(range(32101, 32201)) and [r[5] for r in rows] == list(range(38658, 38758)),
      'server ids 32101-32200 and client ids 38658-38757')

# the client things file agrees: same server id, same client id order
things = os.path.join(os.path.dirname(os.path.dirname(HERE)), 'client', 'tools', 'sprites', 'art_import', 'support_runes.csv')
trows = list(csv.DictReader(open(things, newline='')))
check([int(r['server_id']) for r in trows] == [r[0] for r in rows], 'client things file: server ids in the same order')
check([r['name'] for r in trows] == [r[2] for r in rows], 'client things file: the item names')
for r, t in zip(rows, trows):
    stock_client = r[1] - 2656
    check(t['flags'] == 'copy:%d' % stock_client, '%s copies the stock client id %d' % (t['name'], stock_client))

STOCK = [(s, s - 2656) for s in cfg['sprites']]


def base_nodes():
    return [item_node(sid, cid, flags=FLAG_STACKABLE | FLAG_USEABLE | 0x20, group=2, extra=((0x2A, b'\x03\x00\x1d\x00'),))
            for sid, cid in STOCK] + [item_node(2160, 3031)]


def run(data, rs):
    new, notes, wanted = C.patch_otb(data, rs)
    n = C.verify_otb(new, rs, wanted)
    return new, notes, n


data = otb(base_nodes())
new, notes, n = run(data, rows)
kids, _ = scan(new)
by = {k[2]: k for k in kids}
check(n == len(base_nodes()) + 100, 'verified: every old node and the hundred runes')
check(all(by[r[0]][3] == r[5] for r in rows), 'every rune has its own client id')
check(all(by[r[0]][5] & FLAG_STACKABLE and by[r[0]][5] & FLAG_USEABLE for r in rows), 'stackable and use-with kept')
check(all(by[r[0]][4] == 2 for r in rows), 'group of the stock stone kept')
other = lambda k: [(a, v) for a, v in k[6] if a not in (A_SERVERID, A_CLIENTID)]
check(all(other(by[r[0]]) == other(by[r[1]]) for r in rows), 'every other attribute of the stock stone is there')
check(sorted(k[2] for k in kids if k[2] in set(r[0] for r in rows)) == [r[0] for r in rows], 'a hundred rune nodes appended')
new2, notes2, _ = run(new, rows)
check(new2 == new and any('present' in x for x in notes2), 'a second run changes nothing')

# a client id of another item is refused
clash = otb(base_nodes() + [item_node(5555, 38700)])
try:
    run(clash, rows)
    check(False, 'a taken client id is refused')
except SystemExit as e:
    check('38700' in str(e) and '5555' in str(e), 'the refusal names the client id and its owner')

# a node of the rune range that belongs to another client id is refused
odd = otb(base_nodes() + [item_node(32101, 777)])
try:
    run(odd, rows)
    check(False, 'a rune node on a foreign client id is refused')
except SystemExit as e:
    check('32101' in str(e), 'the refusal names the server id')

# nodes still on the stock look (installed before pair 46) are turned to the own look
stock_rows = [r[:5] + (None,) for r in rows]
old, _n, _c = run(data, stock_rows)
check(all(scan(old)[0][i][3] in dict(STOCK).values() for i in range(len(STOCK) + 1, len(STOCK) + 1 + 100)), 'fallback keeps stock client ids')
turned, notes3, _ = run(old, rows)
check(all({k[2]: k for k in scan(turned)[0]}[r[0]][3] == r[5] for r in rows), 'the stock look is turned to the own look')
check(turned == new, 'the result is the fresh install')
# and back (clientFirstId unset)
back, _n2, _c2 = run(turned, stock_rows)
check(back == old, 'without clientFirstId the nodes go back to the stock stone')

# the items.xml block does not depend on the look
x1 = C.xml_block(rows)
x2 = C.xml_block(stock_rows)
check(x1 == x2 and x1.count('<item id=') == 100, 'items.xml block: 100 runes, the same for both looks')

print('install_supports_test: %s' % ('OK' if not failed else 'FAILED %d' % failed))
sys.exit(1 if failed else 0)
