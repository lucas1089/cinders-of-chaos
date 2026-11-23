#!/usr/bin/env python3
"""Tests of brush_from_sample.py (O741): python3 -I server/tools/brush_from_sample_test.py

Synthetic OTBM samples (map_guard_testkit.build): a new ground painted on a stock ground in a plus, a 1-wide corridor,
a U and a single tile, its pieces laid by our rule (the editor's on the patterns where the two differ). Covers: the
12 pieces found, the brush JSON in the gen_editor_brushes.py format, the art_items.csv rows, gaps (a rectangle has no
inner corner), conflicts (a wrong piece, two pieces of one item, a split vote, a stray piece), a piece seen only
beside another, --json, --write and its refusal, and the Python rule against ChaosAreaGenCore.borderPieces on all
256 patterns in luajit and lua5.3 and against the editor's rule of gen_editor_brushes_test.py."""
import csv
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import brush_from_sample as B  # noqa: E402
import gen_editor_brushes as G  # noqa: E402
import gen_editor_brushes_test as GT  # noqa: E402
from map_guard_testkit import build, item  # noqa: E402

STOCK, NEW, DECOR = 100, 39900, 2000   # NEW and its pieces: ids no art_items.csv row has
PIECE_ID = {p: NEW + 1 + i for i, p in enumerate(B.ROW_ORDER)}   # our piece name -> id
SLOT_ID = {s: PIECE_ID[G.PIECE_OF[s]] for s in B.PIECES}        # editor piece name -> id
X0, Y0, W, H, Z = 1000, 1000, 48, 30, 7


def plus(cx, cy):
    out = set()
    for dx in range(-4, 5):
        for dy in range(-1, 2):
            out.add((cx + dx, cy + dy))
            out.add((cx + dy, cy + dx))
    return out


def shapes(full=True):
    if not full:
        return {(x, y) for x in range(1005, 1012) for y in range(1005, 1011)}
    s = plus(1008, 1010)
    s |= {(x, 1004) for x in range(1018, 1030)}                 # 1-wide corridor
    s |= {(1034, 1010), (1034, 1011), (1035, 1011), (1036, 1011), (1036, 1010)}   # a U around (1035, 1010)
    s |= {(1040, 1022)}                                          # single tile
    return s


def paint(over, edit=None, decor=()):
    """{pos: [item nodes]}: NEW on `over`, STOCK elsewhere with the pieces its pattern needs; edit(pos, ids) -> ids"""
    tiles = {}
    for x in range(X0, X0 + W):
        for y in range(Y0, Y0 + H):
            if (x, y) in over:
                tiles[(x, y, Z)] = [item(NEW)]
                continue
            v = {d: (x + dx, y + dy) in over for d, (dx, dy) in B_DIRS.items()}
            ours, ed = B.rules(v)
            pick = ours if ours == ed or (x + y) % 2 else ed
            ids = [SLOT_ID[p] for p in sorted(pick)]
            if (x, y) in decor:
                ids.append(DECOR)
            if edit:
                ids = edit((x, y), ids)
            tiles[(x, y, Z)] = [item(STOCK)] + [item(i) for i in ids]
    return tiles


B_DIRS = {'n': (0, -1), 'e': (1, 0), 's': (0, 1), 'w': (-1, 0), 'nw': (-1, -1), 'ne': (1, -1), 'sw': (-1, 1),
          'se': (1, 1)}


class Sample(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix='o741_')

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def write(self, tiles, name='s.otbm'):
        path = os.path.join(self.tmp, name)
        with open(path, 'wb') as f:
            f.write(build(tiles))
        return path

    def run_tool(self, *args):
        buf = io.StringIO()
        rc = B.main(list(args), out=buf)
        return rc, buf.getvalue()

    def test_full_sample(self):
        path = self.write(paint(shapes(), decor={(1003, 1010), (1020, 1003), (1001, 1001)}))
        rc, text = self.run_tool(path, '--ground', str(NEW), '--key', 'ash_moss', '--z', '3420')
        self.assertEqual(rc, 0, text)
        self.assertNotIn('conflict', text)
        self.assertNotIn('gaps', text)
        for s in B.PIECES:
            self.assertRegex(text, r'\n  %-4s %-6s item %6d ' % (s, G.PIECE_OF[s], SLOT_ID[s]))
        j = json.loads(text.split('brush JSON:\n', 1)[1].split('art_items.csv rows:', 1)[0])
        self.assertEqual(j['borders'], {'cinders_ash_moss': [0] + [SLOT_ID[s] for s in G.SLOTS]})
        gr = j['grounds']['cinders ash moss']
        self.assertEqual((gr['lookid'], gr['zorder'], gr['items']), (NEW, 3420, [[NEW, 100]]))
        self.assertEqual(gr['borders'], [{'align': 'outer', 'border': 'cinders_ash_moss', 'to': '*'}])
        rows = list(csv.DictReader(io.StringIO(text.split('art_items.csv rows:\n', 1)[1]), fieldnames=B.COLUMNS))
        self.assertEqual(len(rows), 13)
        self.assertEqual((rows[0]['key'], rows[0]['client_id'], rows[0]['server_id'], rows[0]['kind']),
                         ('ground_ash_moss', str(NEW - 3000), str(NEW), 'ground'))
        for r in rows[1:]:
            p = r['extra'][len('piece='):]
            self.assertEqual(r['key'], 'border_ash_moss_' + p)
            self.assertEqual(int(r['server_id']), PIECE_ID[p])
            self.assertEqual(r['otb_flags'], '8192')

    def test_patterns_counted(self):
        path = self.write(paint(shapes()))
        rc, text = self.run_tool(path, '--ground', str(NEW), '--key', 'ash_moss')
        self.assertEqual(rc, 0, text)
        self.assertRegex(text, r'\d+ patterns of 256 seen \(\d+ where both rules agree\)')

    def test_rectangle_has_gaps(self):
        path = self.write(paint(shapes(full=False)))
        rc, text = self.run_tool(path, '--ground', str(NEW), '--key', 'ash_moss')
        self.assertEqual(rc, 1)
        self.assertIn('gaps: dnw dne dse dsw', text)
        self.assertIn('no brush: 4 gaps, 0 conflicts', text)
        self.assertNotIn('brush JSON', text)

    def test_wrong_piece_on_one_tile(self):
        bad = (1006, 1007)   # west of the north arm: its piece is e

        def edit(pos, ids):
            return [SLOT_ID['w']] if pos == bad else ids
        self.assertEqual(paint(shapes())[(bad[0], bad[1], Z)], [item(STOCK), item(SLOT_ID['e'])])
        rc, text = self.run_tool(self.write(paint(shapes(), edit)), '--ground', str(NEW), '--key', 'k')
        self.assertEqual(rc, 1)
        self.assertRegex(text, r'conflict: pattern \d+: missing e, extra w on 1 tile: 1006,1007,7')

    def test_one_item_for_two_pieces(self):
        def edit(pos, ids):
            return [SLOT_ID['n'] if i == SLOT_ID['e'] else i for i in ids]
        rc, text = self.run_tool(self.write(paint(shapes(), edit)), '--ground', str(NEW), '--key', 'k')
        self.assertEqual(rc, 1)
        self.assertIn('conflict: item %d wins 2 pieces: e n' % SLOT_ID['n'], text)

    def test_split_vote(self):
        alt = 3999

        def edit(pos, ids):
            return [alt if i == SLOT_ID['s'] and pos[0] % 2 else i for i in ids]
        rc, text = self.run_tool(self.write(paint(shapes(), edit)), '--ground', str(NEW), '--key', 'k')
        self.assertEqual(rc, 1)
        self.assertRegex(text, r'conflict: s: item \d+ on \d+ of \d+ tiles \(under 75%\)')

    def test_stray_piece(self):
        def edit(pos, ids):
            return ids + [SLOT_ID['n']] if pos == (1045, 1028) else ids
        rc, text = self.run_tool(self.write(paint(shapes(), edit)), '--ground', str(NEW), '--key', 'k')
        self.assertEqual(rc, 1)
        self.assertIn('conflict: piece on a tile with no new-ground neighbour on 1 tile: 1045,1028,7', text)

    def test_under_filter(self):
        path = self.write(paint(shapes()))
        rc, text = self.run_tool(path, '--ground', str(NEW), '--key', 'k', '--under', '777')
        self.assertEqual(rc, 1)
        self.assertIn('0 lower tiles', text)

    def test_json_and_write(self):
        path = self.write(paint(shapes()))
        art = os.path.join(self.tmp, 'art_items.csv')
        shutil.copy(G.ART_ITEMS, art)
        before = open(art, encoding='utf-8').read()
        out = os.path.join(self.tmp, 'b.json')
        rc, text = self.run_tool(path, '--ground', str(NEW), '--key', 'ash_moss', '--json', out, '--art', art)
        self.assertEqual(rc, 0, text)
        self.assertEqual(open(art, encoding='utf-8').read(), before, 'nothing written without --write')
        self.assertIn('cinders_ash_moss', json.load(open(out)).get('borders'))
        rc, text = self.run_tool(path, '--ground', str(NEW), '--key', 'ash_moss', '--art', art, '--write')
        self.assertEqual(rc, 0, text)
        rows = G.read_items(art)
        fam = {short: pieces for short, _, pieces in G.families(rows)}
        self.assertEqual(fam['ash_moss'], PIECE_ID)
        # the generator takes the new rows once the ground has a z order
        b = G.build_brushes(rows, dict(G.planner_z(), ash_moss=3420))
        self.assertEqual(b['borders']['cinders_ash_moss'][1:], [SLOT_ID[s] for s in G.SLOTS])
        with self.assertRaises(SystemExit) as cm:
            self.run_tool(path, '--ground', str(NEW), '--key', 'ash_moss', '--art', art, '--write')
        self.assertIn('already has', str(cm.exception))

    def test_bad_arguments(self):
        self.assertEqual(self.run_tool('nope.otbm', '--ground', '1', '--key', 'k')[0], 2)
        self.assertEqual(self.run_tool(self.write(paint(set())), '--ground', '1', '--key', 'Bad-Key')[0], 2)


class Solve(unittest.TestCase):
    def test_piece_seen_only_beside_another(self):
        v1 = dict.fromkeys(B.BITS, False)
        v1['n'] = True
        v2 = dict(v1, se=True)
        tiles = []
        for i, v in enumerate((v1, v1, v2)):
            ours, ed = B.rules(v)
            items = [11] if v is v1 else [11, 22]
            tiles.append(((i, 0, 7), B.mask_of(v), ours, ed, 1, items))
        self.assertEqual(B.rules(v2)[0], frozenset({'n', 'cse'}))
        win, stats, gaps, conflicts = B.solve(tiles, {2}, {1, 2})
        self.assertEqual((win, conflicts), ({'n': 11, 'cse': 22}, []))
        self.assertEqual(len(gaps), 10)


class Rule(unittest.TestCase):
    def py(self):
        out = {}
        for m in range(256):
            v = {d: bool(m >> i & 1) for i, d in enumerate(B.BITS)}
            out[m] = B.border_pieces(v['n'], v['e'], v['s'], v['w'], v['ne'], v['nw'], v['se'], v['sw'])
        return out

    def test_against_lua(self):
        py = self.py()
        ran = 0
        for lua in ('luajit', 'lua5.3'):
            if not shutil.which(lua):
                continue
            ran += 1
            self.assertEqual(GT.lua_pieces(lua), py, lua)
        if not ran:
            self.skipTest('no luajit or lua5.3')

    def test_editor_rule_and_agreement(self):
        same = 0
        for m in range(256):
            v = {d: bool(m >> i & 1) for i, d in enumerate(B.BITS)}
            self.assertEqual(B.editor_pieces(v), GT.editor_pieces(m))
            self.assertEqual(B.mask_of(v), m)
            ours, ed = B.rules(v)
            same += ours == ed
        self.assertEqual(same, 176)


if __name__ == '__main__':
    unittest.main(verbosity=1)
