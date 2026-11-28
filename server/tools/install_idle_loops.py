#!/usr/bin/env python3
"""The items.otb nodes of the 24 idle loops write the phase byte once the client has pair 92 (O787; install_all step
`idleloops`; server/README.md "Idle loops (pair 92)").

usage: python3 -I install_idle_loops.py DATA_DIR [--dry-run] [--table CSV]

Pair 92 animates 24 stock and orb items in place (client/tools/sprites/gen_idle_loops.py): the same client ids, more
than one phase. The client reads a phase byte after such an item, so its server nodes need FLAG_ANIMATION, and a client
on an older pair reads none, so they must not have it before: data/items/item_wire_idle.csv lists the nodes (server id,
client id, animation 1) and this step follows the recorded client pair (config.lua chaosClientPair, client_pair.py):
  pair PAIR_IDLE_LOOPS or newer   every listed node gets FLAG_ANIMATION (the table as written);
  older or missing                every listed node loses it again (the still look of pair 91 and before), with a warning.
Either way only a node whose server id AND client id are the row's is touched (patch_item_wire.py does the bytes), so a
second run changes nothing and lowering the record undoes the step. Runs after `itemwire` and after every item step that
writes these nodes (orbs). items.otb.bak keeps the original the first time.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import client_pair  # noqa: E402
from item_wire_table import read_table  # noqa: E402
from patch_item_wire import patch_otb, verify  # noqa: E402

TABLE = os.path.join(os.path.dirname(HERE), 'data', 'items', 'item_wire_idle.csv')


def wanted(table, on):
    """the table with every row's animation set by the gate"""
    return {sid: (cid, 1 if on else 0, grp) for sid, (cid, _a, grp) in table.items()}


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    dry = '--dry-run' in args
    path = TABLE
    if '--table' in args:
        i = args.index('--table')
        path = args[i + 1]
        del args[i:i + 2]
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data = args[0]
    table = dict(read_table(path))
    if not table:
        print('no idle loop table (%s): nothing to do' % path)
        return 0
    on, msg = client_pair.allows(data, client_pair.PAIR_IDLE_LOOPS, 'idle loops (FLAG_ANIMATION on %d nodes)' % len(table))
    print(msg if on else msg + ' The listed nodes keep or get back no FLAG_ANIMATION (the still look).')
    otb = os.path.join(data, 'items', 'items.otb')
    if not os.path.exists(otb):
        print('items.otb not found in', os.path.join(data, 'items'))
        return 1
    raw = open(otb, 'rb').read()
    tab = wanted(table, on)
    new, notes, changes = patch_otb(raw, tab)
    n = verify(new, tab)
    for line in notes:
        print(line.replace('follow the client pair', 'follow the idle loop gate'))
    for sid, what in changes[:30]:
        print('  server %d: %s' % (sid, what))
    print('items.otb: verified (%d item nodes)' % n)
    if dry:
        print('dry run: nothing written')
        return 0
    if new != raw:
        if not os.path.exists(otb + '.bak'):
            open(otb + '.bak', 'wb').write(raw)
        open(otb, 'wb').write(new)
    return 0


if __name__ == '__main__':
    sys.exit(main())
