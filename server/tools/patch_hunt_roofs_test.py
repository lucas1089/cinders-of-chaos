#!/usr/bin/env python3
"""python3 -I server/tools/patch_hunt_roofs_test.py : patch_hunt_roofs.py on a synthetic map.

A small roof on floor 6 (edges NW N NE W E SW S SE, red tile fill with wooden frames, stone ledges, an inner corner,
an edge on a wall tile) and one on floor 5 (oriel windows) become the new rusty tin pieces: each new piece one tile down and
right of the old one, the fill ground stays, frames, ledges, windows and old edges go, a ring tile left empty goes, a tile
the roof needs that the map has not is added. A roof outside the box, one on another floor and a tile with a container (the
piece is not put there, listed) are left alone. A dry run writes nothing, --out leaves the map alone, the real run writes the
.bak and the tile count is old + added - removed, a second run changes nothing, a map without the roof items is refused.
The ids and the box of the real tool are checked for overlaps. No base server needed (numpy for otbm.py)."""
import os, shutil, struct, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'map'))
import patch_hunt_roofs as T  # noqa: E402
import install_content_areas as IC  # noqa: E402
import otbm  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


FILL, FLOOR, WALL, BAG = 9535, 405, 5266, 1987
FRAME, LEDGE_H, LEDGE_V, WINDOW, INNER = 9093, 9100, 9101, 9102, 9548
NW, N, NE, SW, S, SE, W, E = 9537, 9538, 9539, 9540, 9541, 9542, 9543, 9544
BOX = dict(x=(10, 30), y=(10, 30), z=(5, 6))


def t(ground, *items, flags=0):
    return dict(flags=flags, ground=ground, items=[i if isinstance(i, tuple) else (i, {}) for i in items])


def otbm_file(tiles):
    esc = IC._esc
    root = b'\xFE' + esc(bytes([0]) + struct.pack('<IHHII', 2, 65000, 65000, 3, 57))
    md = b'\xFE' + esc(bytes([2]))
    towns = b'\xFE' + esc(bytes([12])) + b'\xFF'
    return b'\x00\x00\x00\x00' + root + md + IC.tile_nodes(tiles) + towns + b'\xFF\xFF'


def base_tiles():
    tiles = {}
    z = 6
    #   x 10..13, y 10..12: the roof
    tiles[(10, 10, z)] = t(None, NW)
    tiles[(11, 10, z)] = t(None, N)
    tiles[(12, 10, z)] = t(None, N)
    tiles[(13, 10, z)] = t(None, NE)
    tiles[(10, 11, z)] = t(None, W)
    tiles[(11, 11, z)] = t(FILL, FRAME)
    tiles[(12, 11, z)] = t(FILL, FRAME, LEDGE_V)
    tiles[(13, 11, z)] = t(None, E, LEDGE_H)
    tiles[(10, 12, z)] = t(None, SW)
    tiles[(11, 12, z)] = t(None, S)
    tiles[(12, 12, z)] = t(None, INNER)
    tiles[(13, 12, z)] = t(None, SE)
    # a wall tile with an edge on it, and its neighbour with ground (the piece of (10,11) lands on (11,12) above)
    tiles[(15, 15, z)] = t(FLOOR, WALL, NW)
    tiles[(16, 16, z)] = t(FLOOR)
    # floor 5: a roof of fill with windows; the tile (21,21) holds a container: no piece there
    tiles[(20, 20, 5)] = t(None, NW)
    tiles[(21, 21, 5)] = t(FILL, WINDOW, (BAG, {'kids': [2148]}))
    # outside the box and on another floor: untouched
    tiles[(100, 100, 6)] = t(None, NW)
    tiles[(101, 101, 6)] = t(FILL, FRAME)
    tiles[(20, 20, 7)] = t(FILL, FRAME)
    # tiles the roof does not touch
    tiles[(25, 25, 6)] = t(FLOOR)
    return tiles


def stacks(mp):
    m = otbm.load_otbm(mp)
    return {(int(m.tiles['x'][i]), int(m.tiles['y'][i]), int(m.tiles['z'][i])): [int(a) for a in m.stack(i)]
            for i in range(len(m.tiles['x']))}


def setup(root):
    data = os.path.join(root, 'data')
    os.makedirs(os.path.join(data, 'world'))
    mp = os.path.join(data, 'world', 'w.otbm')
    open(mp, 'wb').write(otbm_file(base_tiles()))
    return data, mp


def main():
    # the real tool's tables
    check(not (set(T.EDGES) & set(T.GONE)) and not (set(T.INNER) & set(T.GONE)), 'old id groups do not overlap')
    check(not (T.NEW & T.OLD), 'new ids are not old ids')
    check(sorted(T.PIECE) == ['e', 'n', 'ne', 'nw', 's', 'se', 'sw', 'w'] and set(T.EDGES.values()) == set(T.PIECE),
          'every edge side has a piece')
    check(all(41477 <= i <= 41487 for i in T.NEW), 'the pieces are the rusty tin set of the kit (41477-41487)')
    root = tempfile.mkdtemp(prefix='hunt_roofs_test_')
    try:
        data, mp = setup(root)
        before = open(mp, 'rb').read()
        s0 = stacks(mp)
        log = []
        T.run(data, dry=True, map_path=mp, known=T.NEW, box=BOX, log=log.append)
        check(open(mp, 'rb').read() == before and not os.path.exists(mp + '.bak'), 'dry run writes nothing')
        out = os.path.join(root, 'out.otbm')
        T.run(data, map_path=mp, out=out, known=T.NEW, box=BOX, log=log.append)
        check(open(mp, 'rb').read() == before and os.path.exists(out), '--out leaves the map alone')
        try:
            T.run(data, map_path=mp, known=set(), box=BOX, log=log.append)
            check(False, 'a map server without the roof items is refused')
        except T.RoofError as e:
            check('pack33items' in str(e), 'the refusal names the step: %s' % e)
        check(open(mp, 'rb').read() == before, 'the refusal writes nothing')
        log = []
        done = T.run(data, map_path=mp, known=T.NEW, box=BOX, log=log.append)
        s = stacks(mp)
        check(os.path.exists(mp + '.bak') and open(mp + '.bak', 'rb').read() == before, '.bak written first')
        check(len(s) == len(s0) + done['added'] - done['deleted'], 'tile count: %d' % len(s))
        z = 6
        # the pieces, one tile down and right of the old ones
        check(s[(11, 11, z)] == [FILL, T.PIECE['nw']], 'NW piece on (11,11): %s' % s[(11, 11, z)])
        check(s[(12, 11, z)] == [FILL, T.PIECE['n']], 'N piece on (12,11): %s' % s[(12, 11, z)])
        check((13, 11, z) in s and s[(13, 11, z)] == [T.PIECE['n']], 'N piece on (13,11) (its old edge went): %s' % s.get((13, 11, z)))
        check(s[(14, 11, z)] == [T.PIECE['ne']], 'NE piece on the added tile (14,11): %s' % s.get((14, 11, z)))
        check(s[(11, 12, z)] == [T.PIECE['w']], 'W piece on (11,12): %s' % s.get((11, 12, z)))
        check(len(s[(12, 12, z)]) == 1 and s[(12, 12, z)][0] in T.INTERIOR, 'interior piece on (12,12): %s' % s[(12, 12, z)])
        check(len(s[(13, 12, z)]) == 1 and s[(13, 12, z)][0] in T.INTERIOR, 'interior piece on (13,12) from the fill: %s' % s[(13, 12, z)])
        check(s[(14, 12, z)] == [T.PIECE['e']], 'E piece on the added tile (14,12): %s' % s.get((14, 12, z)))
        check(s[(11, 13, z)] == [T.PIECE['sw']] and s[(12, 13, z)] == [T.PIECE['s']]
              and len(s[(13, 13, z)]) == 1 and s[(13, 13, z)][0] in T.INTERIOR
              and s[(14, 13, z)] == [T.PIECE['se']], 'bottom row: SW S (inner corner = interior) SE: %s' % [s.get((x, 13, z)) for x in range(11, 15)])
        check((10, 10, z) not in s and (11, 10, z) not in s and (13, 10, z) not in s and (10, 12, z) not in s,
              'ring tiles left empty are removed')
        left = [p for p, st in s.items() if any(i in T.OLD for i in st)
                and BOX['x'][0] <= p[0] <= BOX['x'][1] and BOX['y'][0] <= p[1] <= BOX['y'][1] and p[2] in (5, 6)]
        check(left == [(21, 21, 5)], 'no old piece is left in the box but on the container tile: %s' % left)
        # wall tile with an edge on it
        check(s[(15, 15, z)] == [FLOOR, WALL] and s[(16, 16, z)] == [FLOOR, T.PIECE['nw']],
              'wall kept, edge moved: %s %s' % (s[(15, 15, z)], s[(16, 16, z)]))
        # floor 5: the container tile is left alone (no piece, its window stays), the edge piece's tile is gone
        check(s[(21, 21, 5)] == [FILL, WINDOW, BAG], 'the container tile is left alone whole: %s' % s[(21, 21, 5)])
        check(any('left alone' in l for l in log), 'the container tile is listed: %s' % log)
        check((20, 20, 5) not in s and (22, 22, 5) in s and len(s[(22, 22, 5)]) == 1 and s[(22, 22, 5)][0] in T.INTERIOR,
              'floor 5 fill piece on the added tile (22,22): %s' % s.get((22, 22, 5)))
        # untouched
        check(s[(100, 100, 6)] == [NW] and s[(101, 101, 6)] == [FILL, FRAME], 'a roof outside the box is untouched')
        check(s[(20, 20, 7)] == [FILL, FRAME] and s[(25, 25, 6)] == [FLOOR], 'another floor and plain tiles are untouched')
        after = open(mp, 'rb').read()
        log = []
        again = T.run(data, map_path=mp, known=T.NEW, box=BOX, log=log.append)
        check(open(mp, 'rb').read() == after and again['changed'] == again['added'] == again['deleted'] == 0,
              'a second run changes nothing: %s %s' % (again, log))
        check(any('nothing to do' in l for l in log), 'the second run says so')
        # interior variants are by position: the same position gives the same piece
        check(T.piece_for('c', (5, 6, 6)) == T.piece_for('c', (5, 6, 6)) and T.piece_for('n', (1, 1, 6)) == T.PIECE['n'],
              'pieces are deterministic')
    finally:
        shutil.rmtree(root, ignore_errors=True)
    print('patch_hunt_roofs_test: %s' % ('FAILED %d' % failed if failed else 'ok'))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
