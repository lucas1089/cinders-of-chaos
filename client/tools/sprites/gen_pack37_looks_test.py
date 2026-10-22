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


def test_tables():
    expect(G.check_tables() == [], 'committed tables agree: %r' % G.check_tables())
    expect(len({k for k, *_ in G.LOOKS}) == len(G.LOOKS), 'unique keys')
    expect(set(G.DISPLACEMENT) <= {k for k, *_ in G.LOOKS}, 'displacement overrides name looks')


def main():
    import tempfile, shutil
    tmp = tempfile.mkdtemp()
    try:
        test_reader()
        test_sheet_matches_importer(tmp)
        test_delogo()
        test_tables()
    finally:
        shutil.rmtree(tmp)
    if FAILS:
        print('%d failures' % len(FAILS))
        sys.exit(1)
    print('gen_pack37_looks_test: OK')


if __name__ == '__main__':
    main()
