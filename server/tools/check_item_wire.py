#!/usr/bin/env python3
"""Check that the server and the client agree on how many bytes every item takes in a game packet.

usage: python3 -I server/tools/check_item_wire.py ITEMS_OTB TIBIA_DAT [--examples N] [--write-table [CSV]]
       python3 -I server/tools/check_item_wire.py --table-check TIBIA_DAT [CSV]

The server writes an item as client id, mark, then a count byte when its items.otb node is stackable (else a fluid
byte for a splash or fluid container), then a phase byte when the node has FLAG_ANIMATION
(protocolgame.cpp / networkmessage.cpp addItem). Our client (10.98, GameThingMarks, GameItemAnimationPhase) reads a
count byte when the dat thing is stackable or a quiver (market category 25; since base patch 0173 no hard-coded quiver
ids), else a fluid byte for fluid / splash, then a phase byte when the thing has more than one phase
(protocolgameparse.cpp getItem).
When the two differ for one item, every packet holding it (a container, a tile, an inventory slot) is cut short or
runs over for the client: "ProtocolGame parse message exception ... InputMessage eof reached" (2026-10-16: the gems'
own animated looks 33905.. on nodes without FLAG_ANIMATION, seen opening a Loot Bag that held gems; fixed in
install_gems.py). Run it on the installed server's items.otb and the client pair after any install or import.
Exit 1 when a node disagrees. Pure Python; the dat is read with client/tools/sprites/check_pair.py (the client's rules).

The fix lives in data/items/item_wire.csv (item_wire_table.py; install_all step itemwire, patch_item_wire.py; the item
installers apply it to their manifest rows): per node FLAG_ANIMATION on / off by the dat's phases, group splash / fluid by
the dat's flag. `--write-table` writes it from an installed items.otb and the pair (rows already in the table stay, with
their values worked out again; a node it cannot fix with the table, a stackable or quiver mismatch, is listed and exit 1).
Run it after a new pair, a prune / restore or a new item block, then commit the file. `--table-check` needs only the dat
(CI, live-pair job): every row is a pure function of the dat thing, so a stale row is found without a server.
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', '..', 'client', 'tools', 'sprites'))

from item_wire_table import FLAG_ANIMATION, GROUP_SPLASH, GROUP_FLUID, TABLE, read_table, table_text  # noqa: E402

FLAG_STACKABLE = 1 << 7
QUIVER_CATEGORY = 25   # the client's ItemQuiversMarketCategory


def server_bytes(group, flags):
    """(count or fluid byte, phase byte) the server sends after the mark"""
    sub = 1 if (flags & FLAG_STACKABLE or group in (GROUP_SPLASH, GROUP_FLUID)) else 0
    return sub, 1 if flags & FLAG_ANIMATION else 0


def client_bytes(cid, stackable, fluid, splash, market_category, phases):
    """(count or fluid byte, phase byte) the client reads after the mark"""
    quiver = market_category == QUIVER_CATEGORY
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


def wanted(things_row):
    """(animation 0/1, group or None) the table wants for a dat thing (stackable, fluid, splash, market category, phases)"""
    _stack, fluid, splash, _market, phases = things_row
    return (1 if phases > 1 else 0), (GROUP_SPLASH if splash else GROUP_FLUID if fluid else None)


def make_table(nodes, things, old):
    """([(server id, client id, animation, group)], [unfixable (server id, client id, what)]): a row for every node that
    disagrees and for every node already in the table (old: item_wire_table.read_table)"""
    rows, stuck = [], []
    for sid, cid, group, flags in nodes:
        if not sid or not cid or cid not in things:
            continue
        anim, grp = wanted(things[cid])
        have_anim = 1 if flags & FLAG_ANIMATION else 0
        listed = sid in old and old[sid][0] == cid
        fixed = (anim, grp if grp is not None else group)
        s = server_bytes(fixed[1], flags & ~FLAG_ANIMATION | (FLAG_ANIMATION if anim else 0))
        c = client_bytes(cid, *things[cid])
        if s != c:
            stuck.append((sid, cid, 'count/fluid byte: server %d, client %d (stackable, quiver or a group the table cannot set)'
                          % (s[0], c[0])))
            continue
        if listed or have_anim != anim or fixed[1] != group:
            rows.append((sid, cid, anim, grp))
    return rows, stuck


def table_check(rows, things):
    """problems of table rows (server id, client id, animation, group) against the dat things"""
    bad = []
    for sid, cid, anim, grp in rows:
        t = things.get(cid)
        if t is None:
            bad.append('server %d / client %d: no client thing' % (sid, cid))
        elif wanted(t) != (anim, grp):
            bad.append('server %d / client %d: table says animation %s group %s, the dat wants %s' % ((sid, cid, anim, grp) + (wanted(t),)))
    return bad


def load_dat(dat_path):
    from check_pair import parse_dat
    _sig, _counts, things, _end = parse_dat(open(dat_path, 'rb').read())
    out = {}
    for t in things['item']:
        market = t.flag('market')
        phases = t.groups[0].phases if t.groups else 1
        out[t.id] = (t.flag('stackable') is not None, t.flag('fluid') is not None, t.flag('splash') is not None,
                     market[0] if market else None, phases)
    return out


def load(otb_path, dat_path):
    from install_gems import scan
    kids, _ = scan(open(otb_path, 'rb').read())
    nodes = [(k[2], k[3], k[4], k[5]) for k in kids]
    return nodes, load_dat(dat_path)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('files', nargs='*', help='ITEMS_OTB TIBIA_DAT (with --table-check: TIBIA_DAT [CSV])')
    ap.add_argument('--examples', type=int, default=40)
    ap.add_argument('--write-table', nargs='?', const=TABLE, metavar='CSV')
    ap.add_argument('--table-check', action='store_true')
    a = ap.parse_args(argv)
    if a.table_check:
        if not 1 <= len(a.files) <= 2:
            ap.error('--table-check needs TIBIA_DAT [CSV]')
        path = a.files[1] if len(a.files) == 2 else TABLE
        table = read_table(path)
        bad = table_check([(s, c, an, g) for s, (c, an, g) in sorted(table.items())], load_dat(a.files[0]))
        for line in bad[:a.examples]:
            print(line)
        print('check_item_wire --table-check: %d rows, %d stale' % (len(table), len(bad)))
        return 1 if bad else 0
    if len(a.files) != 2:
        ap.error('needs ITEMS_OTB TIBIA_DAT')
    nodes, things = load(*a.files)
    if a.write_table:
        old = read_table(a.write_table)
        rows, stuck = make_table(nodes, things, old)
        for sid, cid, what in stuck[:a.examples]:
            print('server %d / client %d: %s' % (sid, cid, what))
        with open(a.write_table, 'w', newline='') as fh:
            fh.write(table_text(rows))
        print('check_item_wire: wrote %d rows to %s, %d nodes the table cannot fix' % (len(rows), a.write_table, len(stuck)))
        return 1 if stuck else 0
    bad = compare(nodes, things)
    for sid, cid, what in bad[:a.examples]:
        print('server %d / client %d: %s' % (sid, cid, what))
    if len(bad) > a.examples:
        print('... %d more' % (len(bad) - a.examples))
    print('check_item_wire: %d item nodes, %d disagree' % (len(nodes), len(bad)))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
