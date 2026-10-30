#!/usr/bin/env python3
"""The items.otb nodes whose wire bytes must follow the client pair, and what they must be (server/README.md "Item wire
bytes"). Library for install_dark_tiles / install_pack_items (manifest rows), patch_item_wire.py (every other node) and
check_item_wire.py (--write-table, --table).

The server writes an item as client id, mark, a count byte when the node is stackable (a fluid byte when its group is
splash or fluid), then a phase byte when the node has FLAG_ANIMATION. The client reads the count byte when the dat thing is
stackable or a quiver (fluid byte for fluid / splash) and the phase byte when the thing has more than one phase. Where the
two differ one item cuts a whole tile / map / container packet short. The dat is what the player's client draws, so the node
follows the dat:

- animation 0: the dat thing has one phase (art pruned, never drawn animated, or a stock look the pair holds still): the
  node loses FLAG_ANIMATION. animation 1: more than one phase and the node lacks the flag: it gets it.
- group 11 / 12: the dat thing is a splash / fluid (a flag the importer copied from the source art, a blood splatter, a
  barrel): the node takes that group, so the server writes the fluid byte (0, empty) the client reads. Empty = group kept.

data/items/item_wire.csv: server, client, animation, group (not server_id: other tools read every CSV there for that
column). A row applies only to the node with that server id AND that client id (any other node is left alone). Written by `check_item_wire.py --write-table` from an installed items.otb
and the pair; after a pair change, a prune / restore or a new item block run it again and commit.
"""
import csv
import os

HERE = os.path.dirname(os.path.abspath(__file__))
TABLE = os.path.join(os.path.dirname(HERE), 'data', 'items', 'item_wire.csv')
FLAG_ANIMATION = 1 << 24
GROUP_SPLASH, GROUP_FLUID = 11, 12
FIELDS = ('server', 'client', 'animation', 'group')

_cache = {}


def read_table(path=None):
    """{server id: (client id, animation 0/1, group or None)}; a missing file is an empty table"""
    path = path or TABLE
    if path in _cache:
        return _cache[path]
    out = {}
    if os.path.exists(path):
        with open(path, newline='') as fh:
            for r in csv.DictReader(fh):
                sid = int(r['server'])
                assert sid not in out, 'item_wire.csv: server id %d twice' % sid
                grp = int(r['group']) if r['group'] != '' else None
                assert grp in (None, GROUP_SPLASH, GROUP_FLUID), 'item_wire.csv: server id %d: group %r' % (sid, r['group'])
                assert r['animation'] in ('0', '1'), 'item_wire.csv: server id %d: animation %r' % (sid, r['animation'])
                out[sid] = (int(r['client']), int(r['animation']), grp)
    _cache[path] = out
    return out


def adjust(sid, cid, group, flags, table=None):
    """(group, flags) of a node the way the table wants it; unchanged for a node it does not list or whose client id differs.
    flags / group None (a node taking only a new look) stay None."""
    row = (table if table is not None else read_table()).get(sid)
    if row is None or row[0] != cid or flags is None:
        return group, flags
    _cid, anim, grp = row
    flags = (flags | FLAG_ANIMATION) if anim else (flags & ~FLAG_ANIMATION)
    if grp is not None:
        group = grp
    return group, flags


def adjust_rows(rows, table=None):
    """the manifest rows (dicts with server_id, client_id, otb_group, otb_flags) with the table applied, in place; the
    flags the manifest says stay in otb_flags_manifest (what the art was made as, for generated tables that list it)"""
    for r in rows:
        r['otb_flags_manifest'] = r['otb_flags']
        r['otb_group'], r['otb_flags'] = adjust(r['server_id'], r['client_id'], r['otb_group'], r['otb_flags'], table)
    return rows


def table_text(rows):
    """rows: [(server id, client id, animation, group or None)]"""
    lines = [','.join(FIELDS)]
    for sid, cid, anim, grp in sorted(rows):
        lines.append('%d,%d,%d,%s' % (sid, cid, anim, '' if grp is None else grp))
    return '\n'.join(lines) + '\n'
