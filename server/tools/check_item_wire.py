#!/usr/bin/env python3
"""Check that the server and the client agree on how many bytes every item takes in a game packet.

usage: python3 -I server/tools/check_item_wire.py ITEMS_OTB TIBIA_DAT [--examples N]

The server writes an item as client id, mark, then a count byte when its items.otb node is stackable (else a fluid
byte for a splash or fluid container), then a phase byte when the node has FLAG_ANIMATION
(protocolgame.cpp / networkmessage.cpp addItem). Our client (10.98, GameThingMarks, GameItemAnimationPhase) reads a
count byte when the dat thing is stackable or a quiver (market category 25 or the client's quiver ids), else a fluid
byte for fluid / splash, then a phase byte when the thing has more than one phase (protocolgameparse.cpp getItem).
When the two differ for one item, every packet holding it (a container, a tile, an inventory slot) is cut short or
runs over for the client: "ProtocolGame parse message exception ... InputMessage eof reached" (2026-10-16: the gems'
own animated looks 33905.. on nodes without FLAG_ANIMATION, seen opening a Loot Bag that held gems; fixed in
install_gems.py). Run it on the installed server's items.otb and the client pair after any install or import.
Exit 1 when a node disagrees. Pure Python; the dat is read with client/tools/sprites/check_pair.py (the client's rules).
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', '..', 'client', 'tools', 'sprites'))

FLAG_STACKABLE = 1 << 7
FLAG_ANIMATION = 1 << 24
GROUP_SPLASH, GROUP_FLUID = 11, 12
QUIVER_CATEGORY = 25   # the client's ItemQuiversMarketCategory
QUIVER_IDS = {35524, 35562, 35848, 35849, 36666, 39150, 39160, 45644}   # the client's hard-coded quiver ids


def server_bytes(group, flags):
    """(count or fluid byte, phase byte) the server sends after the mark"""
    sub = 1 if (flags & FLAG_STACKABLE or group in (GROUP_SPLASH, GROUP_FLUID)) else 0
    return sub, 1 if flags & FLAG_ANIMATION else 0


def client_bytes(cid, stackable, fluid, splash, market_category, phases):
    """(count or fluid byte, phase byte) the client reads after the mark"""
    quiver = cid in QUIVER_IDS or market_category == QUIVER_CATEGORY
    sub = 1 if (stackable or quiver or fluid or splash) else 0
    return sub, 1 if phases > 1 else 0


def compare(nodes, things):
    """nodes: [(server id, client id, group, flags)]; things: {client id: (stackable, fluid, splash, market category,
    phases)}. Returns [(server id, client id, what)] for every node whose bytes differ or whose look is missing."""
    bad = []
    for sid, cid, group, flags in nodes:
        if not sid or not cid:
            continue
        t = things.get(cid)
        if t is None:
            bad.append((sid, cid, 'no client thing'))
            continue
        s = server_bytes(group, flags)
        c = client_bytes(cid, *t)
        if s != c:
            parts = []
            if s[0] != c[0]:
                parts.append('count/fluid byte: server %d, client %d' % (s[0], c[0]))
            if s[1] != c[1]:
                parts.append('phase byte: server %d, client %d (FLAG_ANIMATION %s, %d phases)'
                             % (s[1], c[1], 'set' if s[1] else 'missing', t[4]))
            bad.append((sid, cid, '; '.join(parts)))
    return bad


def load(otb_path, dat_path):
    from install_gems import scan
    from check_pair import parse_dat
    kids, _ = scan(open(otb_path, 'rb').read())
    nodes = [(k[2], k[3], k[4], k[5]) for k in kids]
    _sig, _counts, things, _end = parse_dat(open(dat_path, 'rb').read())
    out = {}
    for t in things['item']:
        market = t.flag('market')
        phases = t.groups[0].phases if t.groups else 1
        out[t.id] = (t.flag('stackable') is not None, t.flag('fluid') is not None, t.flag('splash') is not None,
                     market[0] if market else None, phases)
    return nodes, out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('otb')
    ap.add_argument('dat')
    ap.add_argument('--examples', type=int, default=40)
    a = ap.parse_args(argv)
    nodes, things = load(a.otb, a.dat)
    bad = compare(nodes, things)
    for sid, cid, what in bad[:a.examples]:
        print('server %d / client %d: %s' % (sid, cid, what))
    if len(bad) > a.examples:
        print('... %d more' % (len(bad) - a.examples))
    print('check_item_wire: %d item nodes, %d disagree' % (len(nodes), len(bad)))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
