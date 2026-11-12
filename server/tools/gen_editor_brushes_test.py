#!/usr/bin/env python3
"""Tests of gen_editor_brushes.py (O514): python3 -I server/tools/gen_editor_brushes_test.py

 - the committed files are what the generator writes, the JSON has the schema the editor reads
 - every id is a pack item of the right kind (server/data/items/art_items.csv), every ground has its 12 pieces,
   every palette id appears once, every ground family has a brush
 - the mapping of our 12 pieces to the editor's 12 slots:
     * the table the area planner uses (areaplan_build.lua) is the one the generator writes
     * the editor's selection rule (editor_pieces below: the rule of the upstream editor's 256-entry neighbour table,
       checked against that table when this test was written: 0 of 256 patterns differ) against our own
       ChaosAreaGenCore.borderPieces on all 256 patterns of the 8 neighbours, in LuaJIT and Lua 5.3
     * the shape of the art: with Pillow and numpy, the opaque part of each piece of the committed art sheet shows
       where the higher ground lies
"""
import itertools
import json
import os
import shutil
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_editor_brushes as g  # noqa: E402

ROOT = g.ROOT
SERVER = os.path.join(ROOT, 'server')

# neighbour order of the editor's mask: bit 0..7 = nw, n, ne, w, e, sw, s, se
BITS = ('nw', 'n', 'ne', 'w', 'e', 'sw', 's', 'se')
SIDES_OF = {'n': {'n'}, 'e': {'e'}, 's': {'s'}, 'w': {'w'},
            'dnw': {'n', 'w'}, 'dne': {'n', 'e'}, 'dse': {'s', 'e'}, 'dsw': {'s', 'w'}}


def editor_pieces(mask):
    """The pieces the upstream editor puts on a tile whose neighbours in `mask` are the higher ground.

    Read from its BrushStore::computeBorderItems with the table TerrainBorderAlignment::kBorderTypes (one entry of up
    to four slots per mask) and written as a rule, which reproduces all 256 entries:
      - exactly two sides that meet (n+w, n+e, s+e, s+w): the inner corner d.. of that pair, nothing else of the sides
      - any other sides: one edge n / e / s / w per side
      - a diagonal neighbour whose two sides are both not the higher ground: the outer corner c.. of it
    """
    v = {name: bool(mask >> i & 1) for i, name in enumerate(BITS)}
    n, e, s, w = v['n'], v['e'], v['s'], v['w']
    pairs = (('dnw', n, w), ('dne', n, e), ('dse', s, e), ('dsw', s, w))
    out = []
    if n + e + s + w == 2 and any(a and b for _, a, b in pairs):
        out += [name for name, a, b in pairs if a and b]
    else:
        out += [name for name, on in (('n', n), ('e', e), ('s', s), ('w', w)) if on]
    for name, diag, a, b in (('cnw', v['nw'], n, w), ('cne', v['ne'], n, e), ('csw', v['sw'], s, w),
                             ('cse', v['se'], s, e)):
        if diag and not a and not b:
            out.append(name)
    return out


def lua_pieces(lua):
    """ChaosAreaGenCore.borderPieces for all 256 masks, run by the interpreter `lua`"""
    code = ('dofile("data/scripts/chaos/areagen_core.lua")\n'
            'for m = 0, 255 do\n'
            ' local function b(i) return math.floor(m / 2 ^ i) % 2 == 1 end\n'
            ' local r = ChaosAreaGenCore.borderPieces(b(1), b(4), b(6), b(3), b(2), b(0), b(7), b(5))\n'
            ' print(m .. " " .. table.concat(r, " "))\n'
            'end\n')
    p = subprocess.run([lua, '-e', code], cwd=SERVER, capture_output=True, text=True, timeout=60)
    if p.returncode != 0:
        raise AssertionError('%s failed: %s' % (lua, p.stderr[:400]))
    out = {}
    for line in p.stdout.splitlines():
        parts = line.split()
        out[int(parts[0])] = parts[1:]
    assert len(out) == 256
    return out


def coverage(pieces):
    """(sides covered, outer corners) of a piece set"""
    sides, corners = set(), set()
    for p in pieces:
        if p in SIDES_OF:
            sides |= SIDES_OF[p]
        else:
            corners.add(p)
    return sides, corners


class Generated(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rows = g.read_items()
        cls.planner = g.planner_z()
        cls.out = g.outputs(cls.rows, cls.planner)
        cls.brushes = json.loads(cls.out['cinders_brushes.json'])
        cls.tilesets = json.loads(cls.out['cinders_tilesets.json'])
        cls.by_id = {r['id']: r for r in cls.rows}

    def test_committed_files_are_current(self):
        for name, text in self.out.items():
            with open(os.path.join(g.OUT_DIR, name), encoding='utf-8', newline='') as f:
                self.assertEqual(f.read(), text, name + ' is out of date: run gen_editor_brushes.py')

    def test_schema(self):
        b = self.brushes
        self.assertEqual(sorted(b), ['borders', 'grounds'])
        for key, arr in b['borders'].items():
            self.assertTrue(key.startswith('cinders_'))
            self.assertEqual(len(arr), 13)
            self.assertEqual(arr[0], 0)
            self.assertTrue(all(isinstance(i, int) and i > 0 for i in arr[1:]))
            self.assertEqual(len(set(arr[1:])), 12, key)
        for name, gr in b['grounds'].items():
            self.assertTrue(name.startswith('cinders '))
            self.assertEqual(sorted(gr), ['borders', 'friends', 'hate_friends', 'items', 'lookid', 'optional',
                                          'solo_optional', 'zorder'])
            self.assertEqual(gr['items'], [[gr['lookid'], 100]])
            self.assertEqual(len(gr['borders']), 1)
            blk = gr['borders'][0]
            self.assertEqual((blk['align'], blk['to']), ('outer', '*'))
            self.assertIn(blk['border'], b['borders'])
        # a tie is settled by the editor's name order (one ground owns the border, the other gets none): the planner
        # has one, dense grass and fresh snow, which never touch
        by_z = {}
        for name, gr in b['grounds'].items():
            by_z.setdefault(gr['zorder'], []).append(name)
        ties = sorted(sorted(v) for v in by_z.values() if len(v) > 1)
        self.assertEqual(ties, [['cinders dense grass', 'cinders fresh snow']])

    def test_every_ground_family_has_a_brush(self):
        grounds = [r for r in self.rows if r['kind'] == 'ground']
        self.assertEqual(len(grounds), 12)
        self.assertEqual(len(self.brushes['grounds']), len(grounds))
        have = {gr['lookid'] for gr in self.brushes['grounds'].values()}
        self.assertEqual(have, {r['id'] for r in grounds})
        self.assertEqual(len(self.brushes['borders']), len(grounds))

    def test_ids_are_pack_items_of_the_right_kind(self):
        for key, arr in self.brushes['borders'].items():
            short = key[len('cinders_'):]
            for slot, i in zip(g.SLOTS, arr[1:]):
                r = self.by_id.get(i)
                self.assertIsNotNone(r, '%s slot %s: id %d is not in art_items.csv' % (key, slot, i))
                self.assertEqual(r['kind'], 'border')
                self.assertEqual(r['key'], 'border_%s_%s' % (short, g.PIECE_OF[slot]))
        for gr in self.brushes['grounds'].values():
            self.assertEqual(self.by_id[gr['lookid']]['kind'], 'ground')
        for cat, palettes in self.tilesets.items():
            for name, ids in palettes.items():
                self.assertEqual(len(ids), len(set(ids)), name + ' lists an id twice')
                for i in ids:
                    self.assertIn(i, self.by_id, '%s: id %d' % (name, i))

    def test_palettes(self):
        t = self.tilesets
        kinds = lambda ids: {self.by_id[i]['kind'] for i in ids}  # noqa: E731
        self.assertEqual(kinds(t['terrain']['Cinders']), {'ground', 'water', 'shore'})
        self.assertEqual(kinds(t['raw']['Cinders objects']), {'lake', 'dock', 'tree', 'stump'})
        self.assertEqual(kinds(t['raw']['Cinders border pieces']), {'border'})
        want = {k: sum(1 for r in self.rows if r['kind'] == k) for k in
                ('ground', 'water', 'shore', 'lake', 'dock', 'tree', 'stump', 'border')}
        self.assertEqual(len(t['terrain']['Cinders']), want['ground'] + want['water'] + want['shore'])
        self.assertEqual(len(t['raw']['Cinders objects']), want['lake'] + want['dock'] + want['tree'] + want['stump'])
        self.assertEqual(len(t['raw']['Cinders border pieces']), want['border'])

    def test_z_order_over_stock_grounds(self):
        # the stock grounds of the editor at the pin: dirt 1000, sand 3000, grass 3500: ours draw over dirt and sand
        z = {name: gr['zorder'] for name, gr in self.brushes['grounds'].items()}
        for name, v in z.items():
            self.assertGreater(v, 3000, name)
        self.assertGreaterEqual(min(z.values()), 3050)
        for short, v in self.planner.items():
            ours = z['cinders ' + next(r['name'] for r in self.rows if r['key'] == 'ground_' + short)]
            self.assertEqual(ours, v, 'the planner and the editor disagree on ' + short)


class Mapping(unittest.TestCase):
    def test_table_is_the_planners(self):
        with open(g.PLANNER, encoding='utf-8') as f:
            text = f.read()
        for slot, piece in (('cnw', 'outer_nw'), ('cne', 'outer_ne'), ('csw', 'outer_sw'), ('cse', 'outer_se'),
                            ('dnw', 'inner_nw'), ('dne', 'inner_ne'), ('dsw', 'inner_sw'), ('dse', 'inner_se')):
            self.assertIn('%s = get("%s")' % (slot, piece), text)
        pack_piece = {'outer_nw': 'nw', 'outer_ne': 'ne', 'outer_sw': 'sw', 'outer_se': 'se', 'inner_nw': 'in_nw',
                      'inner_ne': 'in_ne', 'inner_sw': 'in_sw', 'inner_se': 'in_se'}
        for k, v in pack_piece.items():
            self.assertIn('%s = "%s"' % (k, v), text)
        want = {'n': 'n', 'e': 'e', 's': 's', 'w': 'w', 'cnw': 'nw', 'cne': 'ne', 'csw': 'sw', 'cse': 'se',
                'dnw': 'in_nw', 'dne': 'in_ne', 'dse': 'in_se', 'dsw': 'in_sw'}
        self.assertEqual(g.PIECE_OF, want)
        self.assertEqual(g.SLOTS, ('n', 'e', 's', 'w', 'cnw', 'cne', 'csw', 'cse', 'dnw', 'dne', 'dse', 'dsw'))

    def test_editor_rule_agrees_with_borderpieces(self):
        interpreters = [i for i in ('luajit', 'lua5.3') if shutil.which(i)]
        self.assertTrue(interpreters, 'no luajit or lua5.3')
        for lua in interpreters:
            ours = lua_pieces(lua)
            same = differ = 0
            for mask in range(256):
                ed, ar = editor_pieces(mask), ours[mask]
                if sorted(ed) == sorted(ar):
                    same += 1
                    continue
                differ += 1
                sides = sum(1 for k in ('n', 'e', 's', 'w') if mask >> BITS.index(k) & 1)
                # by design, on three or four sides only: the editor puts an edge per side, the generator the inner
                # corner of a pair of sides and an edge for the rest. Same sides and same corners covered.
                self.assertGreaterEqual(sides, 3, 'mask %s: %s vs %s' % (format(mask, '08b'), ed, ar))
                self.assertEqual(coverage(ed), coverage(ar), 'mask %s' % format(mask, '08b'))
            self.assertEqual(same + differ, 256)
            self.assertEqual(differ, 80, lua)

    def test_every_mask_one_to_four_pieces_and_only_ours(self):
        for mask in range(256):
            ed = editor_pieces(mask)
            self.assertLessEqual(len(ed), 4)
            self.assertEqual(len(ed) == 0, mask == 0)
            self.assertTrue(set(ed) <= set(g.SLOTS))
        # every piece of every mask lands on an id of the ground's own set
        brushes = g.build_brushes(g.read_items(), g.planner_z())
        for arr in brushes['borders'].values():
            for mask in range(256):
                for p in editor_pieces(mask):
                    self.assertGreater(arr[1 + g.SLOTS.index(p)], 0)


STRAY = 6  # pixels of a 256 pixel band: the art has a stray transparent pixel here and there


class ArtShape(unittest.TestCase):
    """The opaque part of a piece is the higher ground: the piece named n has the higher ground to the north, so its
    transparent part (the lower ground showing) is at the south. Read from the committed art sheet."""

    @classmethod
    def setUpClass(cls):
        try:
            import numpy  # noqa: F401
            from PIL import Image  # noqa: F401
        except ImportError:
            raise unittest.SkipTest('Pillow and numpy are needed for the art shape check')
        art = os.path.join(ROOT, 'client', 'tools', 'sprites', 'art_import')
        import csv
        from PIL import Image
        import numpy as np
        cls.np = np
        cls.cells = {}
        sheets = {}
        with open(os.path.join(art, 'things.csv'), encoding='utf-8', newline='') as f:
            for r in csv.DictReader(f):
                if r['key'].startswith('border_') and r['atlas'] == 'grounds':
                    if 'grounds' not in sheets:
                        sheets['grounds'] = np.array(Image.open(os.path.join(art, 'grounds.png')).convert('RGBA'))
                    x, y = int(r['x']), int(r['y'])
                    cls.cells[r['key']] = sheets['grounds'][y:y + 32, x:x + 32, 3] < 128

    def bands(self, key):
        t = self.cells[key]
        # the middle of each side (the corners belong to two sides)
        return {'n': int(t[:8, 8:24].sum()), 's': int(t[24:, 8:24].sum()), 'w': int(t[8:24, :8].sum()),
                'e': int(t[8:24, 24:].sum())}

    def test_pieces(self):
        shorts = [s for s, _, _ in g.families(g.read_items())]
        self.assertEqual(len(shorts), 12)
        # Only the families whose rim is cut out of the tile (transparent pixels along it) can be read from the alpha
        # channel; the others paint the rim into an opaque tile and are checked by eye (server/README.md "Editor
        # brushes (O514)").
        cut = [s for s in shorts
               if all(self.cells['border_%s_%s' % (s, p)].sum() >= 20 for p in ('n', 's', 'e', 'w'))]
        self.assertGreaterEqual(len(cut), 2, cut)
        for short in cut:
            def b(piece):
                return self.bands('border_%s_%s' % (short, piece))
            # edges: lower ground shows on the far side only
            for piece, far, others in (('n', 's', 'nwe'), ('s', 'n', 'swe'), ('e', 'w', 'nse'), ('w', 'e', 'nsw')):
                v = b(piece)
                self.assertGreater(v[far], 0, '%s %s' % (short, piece))
                for o in others:
                    if o != piece:
                        self.assertLessEqual(v[o], STRAY, '%s %s: transparent on the side of the higher ground'
                                             % (short, piece))
            # outer corners: the higher ground on two sides, the lower one shows on the two others
            for piece, high, low in (('nw', 'nw', 'se'), ('ne', 'ne', 'sw'), ('sw', 'sw', 'ne'), ('se', 'se', 'nw')):
                v = b(piece)
                for k in high:
                    self.assertLessEqual(v[k], STRAY, '%s %s' % (short, piece))
                for k in low:
                    self.assertGreater(v[k], 0, '%s %s' % (short, piece))
            # inner corners: nearly the whole tile is the higher ground; a bite, when there is one, is at the corner
            # away from the named one
            for piece in ('in_nw', 'in_ne', 'in_sw', 'in_se'):
                t = self.cells['border_%s_%s' % (short, piece)]
                self.assertLess(t.sum(), 0.04 * t.size, '%s %s' % (short, piece))
                if t.sum():
                    ys, xs = self.np.nonzero(t)
                    far_y = 'n' if piece[3] == 's' else 's'
                    far_x = 'w' if piece[4] == 'e' else 'e'
                    cy = ys.mean() < 16
                    cx = xs.mean() < 16
                    self.assertEqual(('n' if cy else 's', 'w' if cx else 'e'), (far_y, far_x),
                                     '%s %s: the bite is not at the far corner' % (short, piece))


if __name__ == '__main__':
    unittest.main(verbosity=1)
