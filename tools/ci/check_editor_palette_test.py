#!/usr/bin/env python3
"""Tests of check_editor_palette.py on synthetic tables: python3 -I tools/ci/check_editor_palette_test.py"""
import json
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import check_editor_palette as c  # noqa: E402

PIECES = c.PIECES


def table():
    rows = ['client_id,server_id,key,kind,mode,name,size,otb_group,otb_flags,top_order,speed,light_level,light_color,extra',
            '1,100,ground_moss,ground,new,moss,1x1,1,0,0,150,0,0,']
    for n, p in enumerate(PIECES):
        rows.append('%d,%d,border_moss_%s,border,new,moss %s,1x1,0,8192,1,0,0,0,piece=%s' % (2 + n, 101 + n, p, p, p))
    rows.append('20,200,water_deep,water,new,deep,1x1,1,0,0,0,0,0,')
    return '\n'.join(rows) + '\n'


def good():
    order = ('n', 'e', 's', 'w', 'nw', 'ne', 'sw', 'se', 'in_nw', 'in_ne', 'in_se', 'in_sw')
    ids = {p: 101 + PIECES.index(p) for p in PIECES}
    brushes = {'borders': {'cinders_moss': [0] + [ids[p] for p in order]},
               'grounds': {'cinders moss': {'items': [[100, 100]], 'lookid': 100, 'zorder': 3600,
                                            'borders': [{'align': 'outer', 'border': 'cinders_moss', 'to': '*'}]}}}
    tilesets = {'terrain': {'Cinders': [100, 200]}, 'raw': {'Cinders border pieces': sorted(ids.values())}}
    return brushes, tilesets


class T(unittest.TestCase):
    def run_check(self, brushes, tilesets, csv_text=None):
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, 'a.csv'), 'w', encoding='utf-8') as f:
                f.write(csv_text or table())
            with open(os.path.join(d, 'cinders_brushes.json'), 'w') as f:
                json.dump(brushes, f)
            with open(os.path.join(d, 'cinders_tilesets.json'), 'w') as f:
                json.dump(tilesets, f)
            return c.check(d, os.path.join(d, 'a.csv'))

    def test_good(self):
        self.assertEqual(self.run_check(*good()), [])

    def test_dead_border_id(self):
        b, t = good()
        b['borders']['cinders_moss'][3] = 9999
        self.assertTrue(any('9999' in p and 'not in art_items' in p for p in self.run_check(b, t)))

    def test_wrong_kind_in_slot(self):
        b, t = good()
        b['borders']['cinders_moss'][1] = 200
        self.assertTrue(any('not a border piece' in p for p in self.run_check(b, t)))

    def test_missing_piece(self):
        b, t = good()
        b['borders']['cinders_moss'][5] = b['borders']['cinders_moss'][6]
        self.assertTrue(any('lacks the pieces' in p for p in self.run_check(b, t)))

    def test_ground_without_brush(self):
        b, t = good()
        b['grounds'] = {}
        self.assertTrue(any('has no ground brush' in p for p in self.run_check(b, t)))

    def test_dead_palette_id_and_unlisted_item(self):
        b, t = good()
        t['terrain']['Cinders'] = [100, 4242]
        out = self.run_check(b, t)
        self.assertTrue(any('4242' in p for p in out))
        self.assertTrue(any('water_deep' in p and 'no palette' in p for p in out))

    def test_undefined_border_set(self):
        b, t = good()
        b['grounds']['cinders moss']['borders'][0]['border'] = 'nope'
        self.assertTrue(any('not defined' in p for p in self.run_check(b, t)))

    def test_committed_files(self):
        self.assertEqual(c.check(), [])


if __name__ == '__main__':
    unittest.main()
