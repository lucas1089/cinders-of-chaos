#!/usr/bin/env python3
"""Tests of gen_pack37_looks.py on synthetic .obd files (no owner art): the reader for versions 200 and 300, the
refusals, the sheet layout the importer reads, and the fry box mark paint-over.

    python3 -I client/tools/sprites/gen_pack37_looks_test.py
"""
import lzma, os, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import gen_pack37_looks as G
from import_art_things import OutfitLayout, outfit_frames, _atlas, ATLAS_DIR

FAILS = []


def expect(cond, what):
    if not cond:
        FAILS.append(what)
        print('FAIL', what)


def argb(colour):
    r, g, b, a = colour
    return bytes((a, r, g, b)) * 1024


def obd(version, groups, flags=b'\x19' + struct.pack('<hh', 8, 8)):
    """groups: [(type, w, h, layers, py, pz, frames)]; sprite k of a group is filled with colour (k % 250 + 1, ...)"""
    body = b''
    if version == 300:
        body += bytes([len(groups)])
    for (gt, w, h, L, py, pz, fr) in groups:
        if version == 300:
            body += bytes([gt])
        body += bytes([w, h]) + (bytes([w * 32]) if (w > 1 or h > 1) else b'') + bytes([L, 4, py, pz, fr])
        if fr > 1:
            body += bytes([0]) + struct.pack('<ib', 0, 0) + struct.pack('<II', 100, 100) * fr
        for k in range(w * h * L * 4 * py * pz * fr):
            px = argb((k % 250 + 1, 7, 9, 255))
            body += struct.pack('<I', k + 1) + (b'' if version == 200 else struct.pack('<I', 4096)) + px
    head = struct.pack('<HHB', version, 1098, 2)
    tex = len(head) + 4 + len(flags) + 1
    raw = head + struct.pack('<I', tex) + flags + b'\xff' + body
    return lzma.compress(raw, format=lzma.FORMAT_ALONE)


def test_reader():
    o = G.read_obd(obd(300, [(0, 2, 2, 2, 3, 2, 4), (1, 2, 2, 2, 3, 2, 2)]))
    expect(o['version'] == 300 and o['flags'][0x19] == (8, 8), 'v300: version and displacement')
    g0, g1 = o['groups']
    expect((g0['w'], g0['h'], g0['layers'], g0['py'], g0['pz'], g0['frames']) == (2, 2, 2, 3, 2, 4), 'v300: group 0 shape')
    expect(g1['type'] == 1 and g1['frames'] == 2 and g1['durs'] == [(100, 100)] * 2, 'v300: group 1 type and durations')
    expect(len(g0['tiles']) == 2 * 2 * 2 * 4 * 3 * 2 * 4, 'v300: every sprite read')
    expect(tuple(g0['tiles'][5][0, 0]) == (6, 7, 9, 255), 'ARGB becomes RGBA')
    o2 = G.read_obd(obd(200, [(0, 1, 1, 1, 1, 1, 3)]))
    expect(o2['version'] == 200 and len(o2['groups']) == 1 and o2['groups'][0]['frames'] == 3, 'v200: one group, frames')
    bad = [obd(300, [(0, 1, 1, 1, 1, 1, 1)])[:-3],                        # truncated stream
           lzma.compress(struct.pack('<HHB', 300, 1098, 1) + b'\0' * 8, format=lzma.FORMAT_ALONE),   # an item
           lzma.compress(struct.pack('<HHBI', 300, 1098, 2, 9) + b'\xff' + b'\x01\x00\x01\x01' + b'\x05\x04\x01\x01\x01'
                         + b'\0' * 8, format=lzma.FORMAT_ALONE)]          # five layers
    for i, data in enumerate(bad):
        try:
            G.read_obd(data)
            expect(False, 'bad file %d refused' % i)
        except (G.ObdError, lzma.LZMAError, struct.error):
            pass


def test_sheet_matches_importer(tmp):
    o = G.read_obd(obd(300, [(0, 2, 2, 2, 3, 2, 4), (1, 2, 2, 2, 3, 2, 2)]))
    sheet, f = G.sheet_of(o, 'synthetic')
    from PIL import Image
    os.makedirs(os.path.join(tmp, 'p'), exist_ok=True)
    Image.fromarray(sheet).save(os.path.join(tmp, 'p', 'synthetic.png'))
    row = {'key': 'synthetic', 'atlas': 'p/synthetic', 'x': 0, 'y': 0, 'w': f['w'], 'h': f['h'], 'patterns': '4',
           'phases': f['phases'], 'flags': f['flags'], 'ex': dict(p.split('=', 1) for p in f['extra'].split('|'))}
    ATLAS_DIR[0] = tmp
    _atlas.clear()
    lay = OutfitLayout(row)
    expect(lay.phases == (4, 2) and lay.py == 3 and lay.pz == 2 and lay.layers == 2, 'importer reads the layout')
    frames = outfit_frames(row, lay)
    g = o['groups'][1]
    want = G.cell(g, 1, 1, 2, 3, 1)
    expect(np.array_equal(frames[(1, 1, 3, 1, 2, 1)], want), 'importer cell = group 1, frame 1, west, layer 1, addon 2, mounted')
    expect(f['flags'] == 'displacement:8:8', 'displacement from the file')
    expect(sheet.shape == (6 * 64, 2 * 3 * 2 * 4 * 64, 4), 'sheet: one row per frame, one column per slot')


def test_delogo():
    red, yellow, black = (226, 39, 41, 255), (226, 202, 39, 255), (0, 0, 0, 255)
    a = np.zeros((20, 20, 4), np.uint8)
    a[2:18, 2:18] = red
    a[2, 2:18] = black
    a[6:9, 6:10] = yellow          # a mark inside the red face
    a[0:2, 0:6] = yellow           # fries at the edge: not enclosed
    b, n = G.delogo(a)
    expect(n == 12 and tuple(b[7, 7]) == red, 'the enclosed mark is painted box red')
    expect(tuple(b[0, 0]) == yellow, 'yellow at the edge stays')
    big = np.zeros((40, 40, 4), np.uint8)
    big[:] = red
    big[5:30, 5:30] = yellow
    expect(G.delogo(big)[1] == 0, 'a large yellow area stays (fries, not a mark)')


def test_stand_shift():
    g = {'w': 2, 'h': 2, 'layers': 1, 'px': 4, 'py': 2, 'pz': 2, 'frames': 1}
    g['tiles'] = [np.zeros((32, 32, 4), np.uint8) for _ in range(2 * 2 * 4 * 2 * 2)]

    def put(z, d, row, y=0):   # one opaque pixel in the right column of the cell, at canvas row `row` (32..63)
        g['tiles'][G.tile_index(g, 0, z, y, d, 0, 0, 0)][row - 32, 5] = (1, 2, 3, 255)
    put(0, 0, 53)                       # feet at 53: displacement 0 needs 2 rows down
    put(0, 1, 53); put(0, 1, 62, 1)     # the same, but the addon reaches row 62: only 1 row of room
    put(0, 2, 56); put(0, 2, 40)        # feet at 56: 1 row up
    put(0, 3, 55)                       # already on the ground
    put(1, 2, 60)                       # mounted: not counted, not moved
    expect(G.stand_shifts([g], 0) == [2, 1, -1, 0], 'stand shifts: %r' % G.stand_shifts([g], 0))
    expect(G.stand_shifts([g], 8) == [10, 1, 7, 8], 'with displacement 8 more is needed, clamped by the room')
    c = G.cell(g, 0, 0, 0, 0, 0)
    expect(G._rows(G.shift_rows(c, 2)).tolist() == [55], 'shift_rows moves the art down')
    expect(G._rows(G.shift_rows(c, -3)).tolist() == [50], 'and up')
    try:
        G.shift_rows(c, 11)
        expect(False, 'shift_rows refuses to cut the art')
    except G.ObdError:
        pass
    o = {'flags': {0x19: (8, 8)}, 'groups': [g]}
    G.STAND_SHIFT.add('synthetic_moon'); G.DISPLACEMENT['synthetic_moon'] = (0, 0)
    try:
        sheet, f = G.sheet_of(o, 'synthetic_moon')
    finally:
        G.STAND_SHIFT.discard('synthetic_moon'); del G.DISPLACEMENT['synthetic_moon']
    expect(f['shifts'] == [2, 1, -1, 0] and f['flags'] == 'displacement:0:0', 'sheet_of applies the shifts')
    col = lambda z, y, d: sheet[:, ((z * 2 + y) * 4 + d) * 64:((z * 2 + y) * 4 + d + 1) * 64]
    expect(G._rows(col(0, 0, 0)).tolist() == [55], 'standing north cell moved down 2')
    expect(G._rows(col(0, 1, 1)).tolist() == [63], 'the addon moves with the body (east, 1 row)')
    expect(G._rows(col(0, 0, 2)).tolist() == [39, 55], 'standing south cell moved up 1')
    expect(G._rows(col(1, 0, 2)).tolist() == [60], 'mounted cell untouched')
    row = ['k', 'outfit', 'look', 'K', 'a/k', 0, 0, 2, 2, 4, '1', 'displacement:0:0', 'new', '', 'id=2668|sex=male']
    expect(G.fix_row(row)[12:] == ['replace', '', 'id=2668|sex=male|look=2668'] and row[12] == 'new', 'fix_row')


def test_tables():
    expect(G.check_tables() == [], 'committed tables agree: %r' % G.check_tables())
    expect(len({k for k, *_ in G.LOOKS}) == len(G.LOOKS), 'unique keys')
    expect(set(G.DISPLACEMENT) <= {k for k, *_ in G.LOOKS}, 'displacement overrides name looks')
    expect(G.STAND_SHIFT <= set(G.DISPLACEMENT) and min(min(v) for v in G.DISPLACEMENT.values()) >= 0,
           'the moon set is shifted and keeps a displacement of 0 or more (no negative-offset drawing)')


def main():
    import tempfile, shutil
    tmp = tempfile.mkdtemp()
    try:
        test_reader()
        test_sheet_matches_importer(tmp)
        test_delogo()
        test_stand_shift()
        test_tables()
    finally:
        shutil.rmtree(tmp)
    if FAILS:
        print('%d failures' % len(FAILS))
        sys.exit(1)
    print('gen_pack37_looks_test: OK')


if __name__ == '__main__':
    main()
