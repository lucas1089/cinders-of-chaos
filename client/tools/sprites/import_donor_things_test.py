#!/usr/bin/env python3
"""Tests of import_donor_things.py that need no donor: the wide-header reader (v1098w, dats of more than 65535 items:
14 byte header with a u32 last item id), the standard header, flag conversion by name and the manifest key prefix.

python3 -I client/tools/sprites/import_donor_things_test.py      (numpy: python3-numpy)
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import import_donor_things as m  # noqa: E402

FAILS = []


def expect(cond, what):
    if not cond:
        FAILS.append(what)
        print('FAIL', what)


def group(w=1, h=1, phases=1, sprites=None):
    n = w * h * phases
    return {'gtype': 0, 'w': w, 'h': h, 'exact': 32, 'layers': 1, 'px': 1, 'py': 1, 'pz': 1, 'phases': phases,
            'anim': ((0, 0, 0), (500,) * (2 * phases)) if phases > 1 else None,
            'sprites': sprites or tuple(range(1, n + 1))}


NB = m.NEW_BYTE
ITEMS = [
    ([(NB['bottom'], b''), (NB['notmoveable'], b''), (NB['notwalkable'], b'')], group(2, 2)),
    ([(NB['light'], struct.pack('<HH', 3, 206)), (NB['notmoveable'], b'')], group(1, 1, 3)),
    ([(NB['minimap'], struct.pack('<H', 99))], group(1, 2)),
]


def build(n_blank, wide):
    """a dat of 100+n_blank+3 - 1 items: blank items, then the three of ITEMS; no outfits, effects, missiles"""
    last = 99 + n_blank + len(ITEMS)
    body = m.BLANK_ITEM * n_blank + b''.join(m.entry_bytes('item', fl, [g]) for fl, g in ITEMS)
    if wide:
        head = struct.pack('<IIHHH', 0x4a10, last, 0, 0, 0)
    else:
        head = struct.pack('<IHHHH', 0x4a10, last, 0, 0, 0)
    return head + body


def test_wide_header():
    data = build(0, True)
    t = m.parse_dat(data, m.OUR_KINDS, None, (True, True, True), wide=True)
    expect(len(t['item']) == 3 and t['item'][0].id == 100 and t['item'][2].id == 102, 'wide: three items from id 100')
    expect(t['item'][0].groups[0]['w'] == 2 and t['item'][1].groups[0]['phases'] == 3, 'wide: sizes and phases read')
    expect(not t['outfit'] and not t['effect'] and not t['missile'], 'wide: no outfits, effects, missiles')
    # more than 65535 items: the u32 count carries it, the same dat in the standard header would be misread
    big = build(65600, True)
    tb = m.parse_dat(big, m.OUR_KINDS, None, (True, True, True), wide=True)
    expect(len(tb['item']) == 65603 and tb['item'][-1].id == 65702, 'wide: 65603 items (last id 65702) parsed to EOF')
    try:
        m.parse_dat(big, m.OUR_KINDS, None, (True, True, True), wide=False)
        expect(False, 'standard header on a wide dat must not parse')
    except (m.ParseError, struct.error, IndexError):
        pass


def test_standard_header():
    data = build(0, False)
    t = m.parse_dat(data, m.OUR_KINDS)
    expect(len(t['item']) == 3, 'standard header still parses')
    g = m.parse_generic(build(0, True), 'v1098w', {})
    expect(g[1] == (True, True, True) and len(g[0]['item']) == 3, 'parse_generic v1098w: layout and items')
    g2 = m.parse_generic(build(0, False), 'v1098', {})
    expect(len(g2[0]['item']) == 3, 'parse_generic v1098 unchanged')


def test_flags_and_key():
    t = m.parse_dat(build(0, True), m.OUR_KINDS, None, (True, True, True), wide=True)['item']
    flags, stripped = m.convert_flags(t[0], 'v1098w')
    expect(not stripped and [b for b, _ in flags] == sorted([NB['bottom'], NB['notmoveable'], NB['notwalkable']]),
           'v1098w flags pass by name')
    row = m.otb_row(38759, 3000, 'ice prop 1', t[0], flags, 'decor48', 'ice')
    expect(row['key'] == 'decor48_ice_38759' and row['server_id'] == 41759 and row['client_id'] == 38759, 'key prefix + purpose')
    expect(row['size'] == '2x2' and row['top_order'] == 2 and row['otb_flags'] & m.OTB_SOLID, 'otb row: size, bottom, solid')
    row2 = m.otb_row(38760, 3000, 'x', t[1], m.convert_flags(t[1], 'v1098w')[0], 'decor48', 'lava')
    expect(row2['light_level'] == 3 and row2['light_color'] == 206 and row2['phases'] == 3 and row2['otb_flags'] & m.OTB_ANIM,
           'otb row: light and animation')
    row3 = m.otb_row(28000, 12000, 'claw 1', t[2], [], 'donor_b', '')
    expect(row3['key'] == 'donor_b_28000', 'default key unchanged')


test_wide_header()
test_standard_header()
test_flags_and_key()
if FAILS:
    print(len(FAILS), 'FAILED')
    sys.exit(1)
print('import_donor_things_test: ok')
