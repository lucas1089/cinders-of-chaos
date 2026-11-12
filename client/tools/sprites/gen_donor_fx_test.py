#!/usr/bin/env python3
"""Tests of gen_donor_fx.py and the per phase durations of import_fx_art.py (O525), no donor files needed.

    python3 -I client/tools/sprites/gen_donor_fx_test.py
"""
import csv
import io
import os
import struct
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_donor_fx as G  # noqa: E402
import import_fx_art as I  # noqa: E402
import import_vfx as V  # noqa: E402


def eq(a, b, msg):
    assert a == b, '%s: got %r, want %r' % (msg, a, b)


def main():
    # send offset: the whole tiles that put the art centre nearest the target tile's middle
    eq(G.fit_axis(144, 9), 4, 'centred 9 tiles')            # the middle tile of 9 is tile 4: sent 4 tiles past the target
    eq(G.fit_axis(16, 1), 0, 'one tile')
    eq(G.fit_axis(48, 4), 2, 'art in the second tile of 4 (px 48 = middle of tile 1: 4 - 1 - d = 1)')
    eq(G.fit_axis(80, 5), 2, 'centre of 5 tiles')
    eq(G.axis_error(48, 3, 1), 0, 'error 0 when the centre is on the tile middle')
    eq(G.fit_axis(73, 5), 2, 'a little off the middle tile')
    # durations text
    eq(G.durs_text(None, 4), '100', 'no animator')
    eq(G.durs_text((0, 0, 0, (80, 80, 100, 120)), 2), '80;100:120', 'min and max kept when they differ')
    eq(G.total_ms('40;100:120;100'), 40 + 110 + 100, 'total ms is the mean of each pair')
    eq(G.name_of(489, 'ice', 'hit'), 'donor_ice_hit_489', 'name')

    # the importer: durs column -> per phase pairs; the dat entry carries them
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, 's.csv')
        with open(p, 'w', newline='') as fh:
            w = csv.writer(fh, lineterminator='\n')
            w.writerow(['replace', 'kind', 'name', 'file', 'w', 'h', 'phases', 'ms', 'dx', 'dy', 'note', 'alpha', 'durs'])
            w.writerow(['', 'effect', 'a', 'a.png', 1, 1, 3, 90, 0, 0, 'n', 'soft', '80;100:120;60'])
            w.writerow(['', 'effect', 'b', 'b.png', 1, 1, 2, 70, 0, 0, 'n', '', ''])
        rows = I.read_spec(p)
    eq(rows[0]['durs'], [(80, 80), (100, 120), (60, 60)], 'durs parsed')
    eq(rows[1]['durs'], None, 'no durs column value')
    g = dict(kind='effect', w=1, h=1, layers=1, px=1, py=1, phases=3, ms=90, frames={}, dx=0, dy=0, disp=None,
             durs=[(80, 80), (100, 120), (60, 60)])
    b = V.entry_bytes(g, [1, 2, 3])
    want = struct.pack('<' + 'II' * 3, 80, 80, 100, 120, 60, 60)
    assert want in b, 'entry_bytes writes each phase its own min and max'
    g2 = dict(g, durs=None)
    assert struct.pack('<' + 'II' * 3, 90, 90, 90, 90, 90, 90) in V.entry_bytes(g2, [1, 2, 3]), 'one ms for all phases as before'

    # the committed files agree (no art needed)
    eq(G.check_without_art(), 0, 'donor_fx.csv, donor_fx.sums, the catalog')
    eq(G.ids(True), 0, 'the id table, the element tags and the allow rows are up to date')
    rows = G.read_spec()
    eq(len(rows), 40, '40 effects')
    eq(len({r['donor'] for r in rows}), 40, 'each donor effect once')
    cat = G.catalog_rows()
    first = int(cat[0]['id'])
    eq([int(c['id']) for c in cat], list(range(first, first + 40)), 'consecutive ids')
    lua = open(G.LUA, encoding='utf-8').read()
    for r, c in zip(rows, cat):
        assert 'ChaosVfx.%s = {id = %s, dx = %s, dy = %s, ms = %d}' % (r['name'], c['id'], r['dx'], r['dy'], G.total_ms(r['durs'])) in lua, r['name']
    tags = {r['name']: r['element'] for r in csv.DictReader(open(G.TAGS, newline='', encoding='utf-8'))}
    for r in rows:
        eq(tags.get(r['name']), r['element'], 'tag of ' + r['name'])
    print('gen_donor_fx_test: ok')
    return 0


if __name__ == '__main__':
    sys.exit(main())
