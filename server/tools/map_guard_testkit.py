"""Builders for the tests of the map writers (O512): a synthetic OTBM file from {pos: [item nodes]}, with towns and
waypoints, escaped bytes handled like the real format; and a fault that makes a writer touch one far tile. Not a tool."""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)


def esc(b):
    out = bytearray()
    for c in b:
        if c in (0xFD, 0xFE, 0xFF):
            out.append(0xFD)
        out.append(c)
    return bytes(out)


def node(payload, kids=b''):
    return b'\xFE' + esc(payload) + kids + b'\xFF'


def item(iid, attrs=b'', kids=b''):
    return node(bytes([6]) + struct.pack('<H', iid) + attrs, kids)


def tile_node(pos, items=(), flags=None, house=None):
    p = bytes([14 if house else 5, pos[0] & 0xFF, pos[1] & 0xFF])
    if house:
        p += struct.pack('<I', house)
    if flags:
        p += bytes([3]) + struct.pack('<I', flags)
    return node(p, b''.join(items))


def text_attr(at, s):
    return bytes([at]) + struct.pack('<H', len(s)) + s


def build(tiles, towns=((1, b'Cinderhold'),), waypoints=()):
    """tiles: {(x, y, z): [item nodes]} or a ready tile node (bytes); towns: [(id, name)]; one area per 256 x 256 square"""
    areas = {}
    for pos, v in tiles.items():
        areas.setdefault((pos[0] & 0xFF00, pos[1] & 0xFF00, pos[2]), []).append(pos)
    body = b''
    for (ax, ay, az), poss in sorted(areas.items()):
        inner = b''
        for pos in sorted(poss, key=lambda p: (p[1], p[0])):
            v = tiles[pos]
            inner += v if isinstance(v, bytes) else tile_node(pos, v)
        body += node(bytes([4]) + struct.pack('<HHB', ax, ay, az), inner)
    tn = b''.join(node(bytes([13]) + struct.pack('<IH', i, len(n)) + n + struct.pack('<HHB', 100, 100, 7)) for i, n in towns)
    body += node(bytes([12]), tn)
    if waypoints:
        body += node(bytes([15]), b''.join(node(bytes([16]) + bytes([len(n)]) + n + struct.pack('<HHB', 1, 2, 3)) for n in waypoints))
    root = node(bytes([0]) + struct.pack('<IHHII', 2, 65000, 65000, 3, 57), node(bytes([2]) + text_attr(1, b'test map'), body))
    return b'\x00\x00\x00\x00' + root


def world(n=40):
    t = {}
    for i in range(n):
        t[(1000 + i, 1000 + (i % 5), 7)] = [item(100 + i), item(2000 + i, bytes([4]) + struct.pack('<H', 47000 + i))]
    t[(1005, 1000, 6)] = [item(300, text_attr(6, b'a sign'))]
    return t


def inject_far_cut(module, path):
    """make module.tile_ranges (install_content_areas) cut one more tile than asked: a writer that also removes a far
    tile (the last one of the file the writer did not ask for). Returns (state, undo): state['far'] is that tile once
    the writer has run; undo() puts the real function back."""
    import map_write_guard as G
    orig = module.tile_ranges
    last = [G.pos_of(k) for k in sorted(G.scan(path).keys.tolist(), reverse=True)[:200]]
    state = {}

    def faulty(data, positions, houses=None, missing=None):
        out = orig(data, positions, houses=houses, missing=missing)
        asked = set(positions)
        state['far'] = far = next(p for p in last if p not in asked)
        out.update(orig(data, [far], houses=houses))
        return out
    module.tile_ranges = faulty

    def undo():
        module.tile_ranges = orig
    return state, undo


def corrupt_far_item(data, skip=()):
    """the map bytes with the id of the last item node whose tile is not in `skip` changed by one bit: (bytes, tile)"""
    import gen_poi as GP
    i = len(data)
    while True:
        i = data.rfind(b'\xFE\x06', 0, i)
        if i < 0:
            raise ValueError('no item node to corrupt outside the skipped tiles')
        lo = data[i + 2]
        if not GP.real(data, i) or lo >= 0xFC or lo ^ 1 >= 0xFC:
            continue
        p = GP.tile_position(data, i)
        if p in skip:
            continue
        return data[:i + 2] + bytes([lo ^ 1]) + data[i + 3:], p


def inject_far_item(module, name, skip=()):
    """for the writers that patch map bytes in memory: module.<name> (the function that builds the new bytes) also
    changes one item id on a far tile. Returns (state, undo): state['far'] is that tile once the writer has run."""
    orig = getattr(module, name)
    state = {}

    def faulty(*a, **k):
        out = orig(*a, **k)
        new, state['far'] = corrupt_far_item(out, skip)
        return new
    setattr(module, name, faulty)
    return state, lambda: setattr(module, name, orig)


def fault_check(check, IC, make_map, run, root, what):
    """O512: the guard of a writer. A fresh synthetic map (make_map(path)), then run(data_dir, map_path) while
    IC.tile_ranges also cuts a far tile: the writer must raise IC.InstallError naming that tile, leave the map as it
    was and leave the .tmp for inspection."""
    data = os.path.join(root, 'fault_' + what.replace(' ', '_'))
    os.makedirs(os.path.join(data, 'world'))
    mp = os.path.join(data, 'world', 'w.otbm')
    make_map(mp)
    before = open(mp, 'rb').read()
    state, undo = inject_far_cut(IC, mp)
    try:
        run(data, mp)
        check(False, '%s: a writer that also cuts a far tile is refused' % what)
    except IC.InstallError as e:
        check('far' in state and '%d,%d,%d: tile removed outside' % state['far'] in str(e),
              '%s: the far tile is named: %s' % (what, str(e)[:200]))
    finally:
        undo()
    check(open(mp, 'rb').read() == before, '%s: the map is as it was' % what)
    check(os.path.exists(mp + '.tmp'), '%s: the .tmp stays for inspection' % what)
