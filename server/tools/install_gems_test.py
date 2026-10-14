#!/usr/bin/env python3
"""python3 -I server/tools/install_gems_test.py : install_gems.py on a synthetic items.otb (the config read from
chaos_gems_config.lua; 35 gem nodes copied from the stock gem sprites while ownLook is false; with ownLook = true the
same nodes get our own looks 33905.. (client/tools/sprites/art_import/gems.csv) and keep the rest of the stock node;
flipping back restores them; idempotent; a look id another item uses stops it). No base server needed."""
import os, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_gems as T  # noqa: E402
from install_gems import scan, escape, attr, START, END, A_SERVERID, A_CLIENTID, FLAG_STACKABLE, FLAG_USEABLE  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def item_node(sid, cid, flags=FLAG_STACKABLE, group=0, extra=b''):
    body = struct.pack('<I', flags) + attr(A_SERVERID, struct.pack('<H', sid)) + attr(A_CLIENTID, struct.pack('<H', cid)) + extra
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def otb(nodes):
    root = bytes([START, 0]) + escape(struct.pack('<I', 0))
    return b'\x00\x00\x00\x00' + root + b''.join(nodes) + bytes([END])


cfg = T.read_config()
check(cfg['ownLook'] is False, 'config: stock sprites until a pair with our gem looks is published')
check(cfg['lookFirst'] == 33905, 'config: our looks after the Everfull Ration (33904)')
n = len(cfg['tiers']) * len(cfg['types'])
check(n == 35, 'seven gems in five tiers')

# stock nodes for every stock gem sprite of the config (server ids 2000.., an extra attribute kept)
stock_cids = sorted({c for t in cfg['types'] for c in (t['clientId'], t['clientIdHigh']) if c})
extra = attr(0x14, struct.pack('<H', 7))   # any further attribute of the stock node (copied as it is)
base = otb([item_node(2000 + i, c, FLAG_STACKABLE, 0, extra) for i, c in enumerate(stock_cids)])

rows = T.gems(cfg)
new, notes, wanted = T.patch_otb(base, rows, cfg)
check(T.verify_otb(new, rows, wanted) == len(stock_cids) + n, 'stock looks: verified')
by = {k[2]: k for k in scan(new)[0]}
check(by[32001][3] == 3030 and by[32004][3] == 676, 'ruby: small ruby up to Polished, enchanted from Flawless')
check(by[32001][5] & FLAG_USEABLE and by[32001][5] & FLAG_STACKABLE, 'useable and stackable')
again, notes2, _ = T.patch_otb(new, rows, cfg)
check(again == new and 'present' in notes2[0], 'idempotent')

own = dict(cfg, ownLook=True)
rows_own = T.gems(own)
check([r[1] for r in rows_own] == list(range(33905, 33905 + n)), 'ownLook: client ids 33905..33939 in config order')
check([r[0] for r in rows_own] == [r[0] for r in rows], 'ownLook: same server ids')
mine, notes3, wanted3 = T.patch_otb(new, rows_own, own)
check(any('updated' in x for x in notes3), 'ownLook: the nodes are rewritten')
check(T.verify_otb(mine, rows_own, wanted3) == len(stock_cids) + n, 'ownLook: verified')
by3 = {k[2]: k for k in scan(mine)[0]}
check(by3[32001][3] == 33905 and by3[32035][3] == 33939, 'ownLook: our looks')
check([a for a in by3[32004][6] if a[0] == 0x14] == [(0x14, struct.pack('<H', 7))], 'ownLook: stock attributes kept')
check(by3[32004][5] == by[32004][5], 'ownLook: same flags as the stock copy')
check(T.patch_otb(mine, rows_own, own)[0] == mine, 'ownLook: idempotent')
back, _, _ = T.patch_otb(mine, rows, cfg)
check(back == new, 'ownLook off again: the stock looks come back byte for byte')
# a look id another item uses stops it
clash = otb([item_node(2000 + i, c) for i, c in enumerate(stock_cids)] + [item_node(5000, 33910)])
try:
    T.patch_otb(clash, rows_own, own)
    check(False, 'a taken look id stops the script')
except SystemExit as e:
    check('already used' in str(e), 'a taken look id stops the script')

print('install_gems_test: %s' % ('OK' if not failed else '%d FAILED' % failed))
sys.exit(1 if failed else 0)
