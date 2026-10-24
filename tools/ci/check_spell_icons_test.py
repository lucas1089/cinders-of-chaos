#!/usr/bin/env python3
"""Tests of check_spell_icons.py: the real data passes, and each kind of missing icon is caught (O157).
usage: python3 -I tools/ci/check_spell_icons_test.py"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import check_spell_icons as C  # noqa: E402


def sheets():
    return {s: (C.read_png(os.path.join(C.SHEETS_DIR, 'spell-icons-%s.png' % s)), cw, ch) for s, cw, ch in C.SHEETS}


def main():
    sh = sheets()
    spells, server = C.load_spelldata(), C.load_server()
    assert len(spells) >= 148 and len(server) == len(spells), (len(spells), len(server))
    assert C.problems(spells, server, sh) == [], C.problems(spells, server, sh)

    def one(**kw):
        s = [dict(x) for x in spells]
        s[-1].update(kw)
        return C.problems(s, server, sh)

    # a cell past the end of the sheet (the 16-row sheet of before O133 had 320 cells)
    assert any('outside the sheet' in b for b in one(clientId=999)), 'outside'
    # a cell nobody drew: the filler plate (the last cell of the sheet)
    last = (sh['32x32'][0][1] // 32) * C.COLS
    assert any('filler' in b for b in one(clientId=last - 1)), 'filler'
    # an empty cell (Thief-line cells were once transparent): a transparent RGBA cell and a flat RGB cell
    w, h, bpp, rows = sh['32x32'][0]
    blank_sheet = (w, h, bpp, [bytes(len(r)) for r in rows])
    s2 = dict(sh)
    s2['32x32'] = (blank_sheet, 32, 32)
    assert any('is empty' in b for b in C.problems(spells, server, s2)), 'empty'
    # two spells on one cell, no icon key, a server spell missing from the spell data
    assert any('share the icon cell' in b for b in one(clientId=spells[0]['clientId'])), 'shared cell'
    assert any('no iconKey' in b for b in one(iconKey=None)), 'no key'
    assert any('not in spelldata' in b for b in C.problems(spells[:-1], server, sh)), 'missing spell'
    # the five Thief spells of the owner report resolve to drawn cells
    names = {s['name']: s for s in spells}
    for n in ('Gutting Slash', 'Razor Rain', 'Venom Spiral', 'Crescent Cut', 'Last Breath'):
        assert n in names and names[n]['clientId'], n
    print('check_spell_icons_test: OK')


if __name__ == '__main__':
    main()
