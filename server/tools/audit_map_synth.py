"""Synthetic OTBM maps, items.otb and items.xml for the tests of the map audits (audit_map_tiles_test.py,
audit_houses_test.py). Test support only: nothing here reads or writes a real map.

    items = {100: dict(name='grass', group=1), 1000: dict(name='wall', flags=1, order=2), ...}
    write_items(dir, items)                      -> dir/items.otb, dir/items.xml
    tiles = {(x, y, z): dict(items=[100, 200], flags=0, house=0), ...}
    write_map(path, tiles, houses_file='x-house.xml')

An entry of a tile's `items` is an id or (id, {'tele': (x, y, z)}). The first id is written as a child item node like the
others (the map editor does the same), or as the inline ground attribute when the tile sets inline=True.
"""
import os
import struct


def _esc(b):
    return b.replace(b'\xfd', b'\xfd\xfd').replace(b'\xfe', b'\xfd\xfe').replace(b'\xff', b'\xfd\xff')


def _node(kind, payload=b'', kids=()):
    return b'\xfe' + bytes([kind]) + _esc(payload) + b''.join(kids) + b'\xff'


def write_items(folder, items):
    """items: {server id: dict(group=0, flags=0, order=0, name='', type='', cid=server id)}"""
    os.makedirs(folder, exist_ok=True)
    kids = []
    for sid in sorted(items):
        d = items[sid]
        pl = struct.pack('<I', d.get('flags', 0))
        pl += b'\x10' + struct.pack('<HH', 2, sid)
        pl += b'\x11' + struct.pack('<HH', 2, d.get('cid', sid))
        if d.get('order'):
            pl += b'\x2b' + struct.pack('<HB', 1, d['order'])
        kids.append(_node(d.get('group', 0), pl))
    root = _node(0, struct.pack('<I', 0) + b'\x01' + struct.pack('<H', 140) + bytes(140), kids)
    with open(os.path.join(folder, 'items.otb'), 'wb') as f:
        f.write(b'\x00\x00\x00\x00' + root)
    rows = []
    for sid in sorted(items):
        d = items[sid]
        attrs = 'id="%d" name="%s"' % (sid, d.get('name', ''))
        if d.get('type'):
            rows.append('<item %s><attribute key="type" value="%s" /></item>' % (attrs, d['type']))
        else:
            rows.append('<item %s />' % attrs)
    with open(os.path.join(folder, 'items.xml'), 'w', encoding='latin1') as f:
        f.write('<?xml version="1.0"?>\n<items>\n' + '\n'.join(rows) + '\n</items>\n')


def map_bytes(tiles, houses_file='synth-house.xml', spawn_file='synth-spawn.xml'):
    root_pl = struct.pack('<IHHII', 2, 34800, 34200, 3, 57)
    md_pl = b''
    for at, s in ((1, 'synthetic map'), (11, spawn_file), (13, houses_file)):
        md_pl += bytes([at]) + struct.pack('<H', len(s)) + s.encode('latin1')
    areas = {}
    for (x, y, z), t in tiles.items():
        areas.setdefault((x & 0xFF00, y & 0xFF00, z), []).append((x, y, z, t))
    area_nodes = []
    for (ax, ay, az) in sorted(areas, key=lambda k: (k[2], k[1], k[0])):
        tile_nodes = []
        for x, y, z, t in sorted(areas[(ax, ay, az)], key=lambda r: (r[1], r[0])):
            stack = list(t.get('items', []))
            house = t.get('house', 0)
            pl = bytes([x & 0xFF, y & 0xFF]) + (struct.pack('<I', house) if house else b'')
            if t.get('flags'):
                pl += b'\x03' + struct.pack('<I', t['flags'])
            if t.get('inline') and stack:
                first = stack.pop(0)
                pl += b'\x09' + struct.pack('<H', first if isinstance(first, int) else first[0])
            kids = []
            for it in stack:
                iid, attrs = (it, {}) if isinstance(it, int) else it
                ipl = struct.pack('<H', iid)
                if attrs.get('tele'):
                    ipl += b'\x08' + struct.pack('<HHB', *attrs['tele'])
                kids.append(_node(6, ipl))
            tile_nodes.append(_node(14 if house else 5, pl, kids))
        area_nodes.append(_node(4, struct.pack('<HHB', ax, ay, az), tile_nodes))
    md = _node(2, md_pl, area_nodes + [_node(12), _node(15)])
    return b'\x00\x00\x00\x00' + _node(0, root_pl, [md])


def write_map(path, tiles, houses_file='synth-house.xml'):
    with open(path, 'wb') as f:
        f.write(map_bytes(tiles, houses_file))


def write_houses(path, rows):
    """rows: [dict(id, name, entry=(x, y, z), size=0)] -> a houses.xml of the base server's layout"""
    lines = ['<?xml version="1.0"?>', '<houses>']
    for r in rows:
        ex, ey, ez = r['entry']
        lines.append('\t<house name="%s" houseid="%d" entryx="%d" entryy="%d" entryz="%d" rent="1000" townid="1" size="%d" />'
                     % (r['name'], r['id'], ex, ey, ez, r.get('size', 0)))
    lines.append('</houses>')
    with open(path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')
