#!/usr/bin/env python3
"""Give the base map's towns the Cinders of Chaos names (server/README.md "Town names").

usage: python3 -I patch_base_towns.py DATA_DIR [--map PATH] [--names CSV] [--dry-run] [--no-backup]
       python3 -I patch_base_towns.py --list PATH.otbm

The new names come from server/tools/base_towns.csv (columns id,name; --names for another file), matched by town id. The old names are never
written anywhere by this tool or by the repository: only the ids and the new names are in the CSV.

The map is DATA_DIR/world/<mapName>.otbm (mapName from the config.lua next to DATA_DIR), or the only .otbm in
DATA_DIR/world, or --map PATH. In the OTBM file the towns are one node (type 12) under the map data node, with one child
node (type 13) per town: u32 id, u16 length, the name, u16 x, u16 y, u8 z of the temple (bytes 0xFD, 0xFE, 0xFF escaped
with 0xFD). Names are length-prefixed, so the towns node is rebuilt with the new names and spliced in place; every byte
before and after it stays the same. Ids, temple positions and the order of the towns are kept, and so are the house
and spawn files, which refer to towns by id only.

Safety: exactly one towns node must be found, every town node must parse to the end of its payload, and the written
bytes are parsed again before the file is replaced (written to a temporary file next to the map, then renamed). The
first time the map changes, <map>.otbm.bak keeps the original (unless --no-backup). A town on the map that has no
row in the CSV keeps its name and is listed; a CSV id that is not on the map is listed too.

Idempotent: a second run reports "nothing to change" and does not touch the file. --dry-run reads only.
"""
import csv
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CSV_PATH = os.path.join(HERE, 'base_towns.csv')

ESC, START, END = 0xFD, 0xFE, 0xFF
T_TOWNS, T_TOWN = 12, 13


class MapError(Exception):
    pass


# ------------------------------------------------------------------------------------------------ bytes
def escape(data):
    out = bytearray()
    for b in data:
        if b in (ESC, START, END):
            out.append(ESC)
        out.append(b)
    return bytes(out)


def _unescaped(data, i):
    """True when data[i] is a real marker: preceded by an even run of escape bytes"""
    j = i
    while j > 0 and data[j - 1] == ESC:
        j -= 1
    return (i - j) % 2 == 0


def _payload(data, i):
    """the unescaped payload from i up to the next real marker -> (bytes, index of that marker)"""
    out = bytearray()
    n = len(data)
    while i < n:
        b = data[i]
        if b == ESC:
            if i + 1 >= n:
                raise MapError('escape byte at the end of the file')
            out.append(data[i + 1])
            i += 2
        elif b in (START, END):
            return bytes(out), i
        else:
            out.append(b)
            i += 1
    raise MapError('node not closed before the end of the file')


def find_towns(data):
    """(start, end) of the towns node: start at its 0xFE, end just after its closing 0xFF"""
    found = [m.start() for m in re.finditer(b'\xfe\x0c', data) if _unescaped(data, m.start())]
    if len(found) != 1:
        raise MapError('%d towns nodes found (want exactly one)' % len(found))
    start = found[0]
    towns, end = parse_towns_node(data, start)
    return start, end, towns


def parse_towns_node(data, start):
    """-> ([(id, name bytes, x, y, z, extra bytes)], end) for the node starting at `start` (its 0xFE)"""
    if data[start] != START or data[start + 1] != T_TOWNS:
        raise MapError('no towns node at %d' % start)
    head, i = _payload(data, start + 2)
    if head:
        raise MapError('towns node has %d bytes of its own' % len(head))
    towns = []
    while True:
        if data[i] == END:
            return towns, i + 1
        if data[i] != START or i + 1 >= len(data) or data[i + 1] != T_TOWN:
            raise MapError('unexpected node in the towns node at %d' % i)
        body, i = _payload(data, i + 2)
        if data[i] != END:
            raise MapError('a town node has child nodes (at %d)' % i)
        i += 1
        if len(body) < 6:
            raise MapError('town node too short')
        tid, ln = struct.unpack_from('<IH', body, 0)
        if 6 + ln + 5 > len(body):
            raise MapError('town %d: name and temple do not fit the node' % tid)
        name = body[6:6 + ln]
        x, y, z = struct.unpack_from('<HHB', body, 6 + ln)
        towns.append((tid, name, x, y, z, body[6 + ln + 5:]))


def walk_nodes(data):
    """[(type, depth)] of every node of an OTBM file, checking that the tree closes exactly at the end (a plain loop:
    for tests and small maps)"""
    if len(data) < 6 or data[4] != START:
        raise MapError('no root node')
    out, depth, i, n = [], 0, 4, len(data)
    while i < n:
        b = data[i]
        if b == ESC:
            i += 2
            continue
        if b == START:
            depth += 1
            out.append((data[i + 1], depth))
            i += 2
            continue
        if b == END:
            depth -= 1
            if depth < 0:
                raise MapError('node closed twice at %d' % i)
            if depth == 0 and i != n - 1:
                raise MapError('bytes after the root node')
        i += 1
    if depth != 0:
        raise MapError('%d node(s) not closed' % depth)
    return out


def build_towns_node(towns):
    out = bytearray([START, T_TOWNS])
    for tid, name, x, y, z, extra in towns:
        body = struct.pack('<IH', tid, len(name)) + name + struct.pack('<HHB', x, y, z) + extra
        out += bytes([START, T_TOWN]) + escape(body) + bytes([END])
    out.append(END)
    return bytes(out)


# ------------------------------------------------------------------------------------------------ rename
def read_names(path=CSV_PATH):
    names = {}
    with open(path, encoding='utf-8', newline='') as f:
        for row in csv.DictReader(f):
            tid, name = row.get('id', '').strip(), row.get('name', '').strip()
            if not tid or tid.startswith('#'):
                continue
            if not tid.isdigit() or not name:
                raise SystemExit('%s: bad row %r' % (path, row))
            if int(tid) in names:
                raise SystemExit('%s: town id %s twice' % (path, tid))
            if '"' in name or len(name.encode('latin-1')) > 0xFFFF:
                raise SystemExit('%s: bad name for town %s' % (path, tid))
            names[int(tid)] = name
    lowered = [n.lower() for n in names.values()]
    if len(set(lowered)) != len(lowered):
        raise SystemExit('%s: two towns with the same name' % path)
    return names


def rename(data, names):
    """-> (new data or None when nothing changes, [notes])"""
    start, end, towns = find_towns(data)
    notes, new_towns, changed = [], [], 0
    on_map = set()
    for tid, name, x, y, z, extra in towns:
        on_map.add(tid)
        want = names.get(tid)
        if want is None:
            notes.append('town %d (temple %d,%d,%d): no row in base_towns.csv, name kept' % (tid, x, y, z))
            new_towns.append((tid, name, x, y, z, extra))
            continue
        b = want.encode('latin-1')
        if b != name:
            changed += 1
            notes.append('town %d: renamed to "%s"' % (tid, want))
        new_towns.append((tid, b, x, y, z, extra))
    for tid in sorted(set(names) - on_map):
        notes.append('base_towns.csv: town %d is not on the map' % tid)
    if not changed:
        notes.append('towns: %d on the map, nothing to change' % len(towns))
        return None, notes
    node = build_towns_node(new_towns)
    out = data[:start] + node + data[end:]
    # parse the result again: same towns (ids, temples) with the new names, and the bytes around unchanged
    s2, e2, back = find_towns(out)
    mo, md = memoryview(out), memoryview(data)
    if s2 != start or mo[e2:] != md[end:] or mo[:start] != md[:start]:
        raise MapError('the rebuilt towns node does not sit where the old one was')
    if [(t[0], t[2], t[3], t[4], t[5]) for t in back] != [(t[0], t[2], t[3], t[4], t[5]) for t in towns]:
        raise MapError('the rebuilt towns node lost ids or temples')
    if [t[1] for t in back] != [t[1] for t in new_towns]:
        raise MapError('the rebuilt towns node has other names')
    notes.append('towns: %d renamed of %d (verified)' % (changed, len(towns)))
    return out, notes


# ------------------------------------------------------------------------------------------------ files
def map_path(data_dir):
    world = os.path.join(data_dir, 'world')
    cfg = os.path.join(os.path.dirname(os.path.abspath(data_dir)), 'config.lua')
    if os.path.isfile(cfg):
        m = re.search(r'^\s*mapName\s*=\s*"([^"]+)"', open(cfg, encoding='utf-8', errors='replace').read(), re.M)
        if m:
            p = os.path.join(world, m.group(1) + '.otbm')
            if os.path.isfile(p):
                return p
    maps = sorted(n for n in os.listdir(world) if n.endswith('.otbm')) if os.path.isdir(world) else []
    return os.path.join(world, maps[0]) if len(maps) == 1 else None


def list_towns(path):
    data = open(path, 'rb').read()
    _s, _e, towns = find_towns(data)
    for tid, name, x, y, z, _extra in towns:
        print('%d\t%s\t%d,%d,%d' % (tid, name.decode('latin-1'), x, y, z))
    return 0


def main(argv):
    dry = '--dry-run' in argv
    backup = '--no-backup' not in argv
    args, path, listing, names = [], None, False, CSV_PATH
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == '--map' and i + 1 < len(argv):
            path = argv[i + 1]
            i += 1
        elif a == '--names' and i + 1 < len(argv):
            names = argv[i + 1]
            i += 1
        elif a == '--list':
            listing = True
        elif not a.startswith('--'):
            args.append(a)
        i += 1
    if listing:
        if len(args) != 1:
            print(__doc__)
            return 2
        return list_towns(args[0])
    if len(args) != 1:
        print(__doc__)
        return 2
    if path is None:
        path = map_path(args[0])
    if not path or not os.path.isfile(path):
        print('no map found (DATA_DIR/world/<mapName>.otbm); pass --map PATH')
        return 1
    data = open(path, 'rb').read()
    if data[:2] == b'\x1f\x8b':
        print('%s is compressed; unpack it first' % path)
        return 1
    try:
        out, notes = rename(data, read_names(names))
    except MapError as e:
        print('%s: %s; nothing written' % (path, e))
        return 1
    for n in notes:
        print(n)
    if out is None:
        return 0
    if dry:
        print('dry run: %s would change' % os.path.basename(path))
        return 0
    if backup and not os.path.exists(path + '.bak'):
        with open(path + '.bak', 'wb') as f:
            f.write(data)
    tmp = path + '.tmp'
    with open(tmp, 'wb') as f:
        f.write(out)
    os.replace(tmp, path)
    print('%s written (%d bytes, was %d)' % (os.path.basename(path), len(out), len(data)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
